defmodule Canopy.Mesh.Cache do
  @moduledoc """
  In-memory cache for mesh data using ETS.

  Provides fast lookups for domains, entities, and quality scores.
  All operations are atomic and time-bounded.

  Cache TTL: 1 hour (configurable via env var MESH_CACHE_TTL_MINUTES).
  """

  require Logger

  @table_name :canopy_mesh_cache
  @default_ttl_minutes 60

  # ── Public API ──────────────────────────────────────────────────────

  def init do
    ttl_minutes =
      String.to_integer(System.get_env("MESH_CACHE_TTL_MINUTES", "#{@default_ttl_minutes}"))

    case :ets.new(@table_name, [
           :set,
           :named_table,
           :public,
           {:write_concurrency, true},
           {:read_concurrency, true}
         ]) do
      table when is_atom(table) ->
        Logger.info("[Mesh.Cache] Initialized with TTL #{ttl_minutes} minutes")
        {:ok, @table_name}

      :error ->
        # Table already exists
        {:ok, @table_name}
    end
  end

  def put_domain(domain_data) do
    domain_name = domain_data[:name]

    entry = %{
      type: :domain,
      name: domain_name,
      owner: domain_data[:owner],
      tags: domain_data[:tags] || [],
      cached_at: domain_data[:cached_at] || DateTime.utc_now()
    }

    :ets.insert(@table_name, {{:domain, domain_name}, entry})
    Logger.debug("[Mesh.Cache] Cached domain: #{domain_name}")
    :ok
  end

  def get_domain(domain_name) do
    case :ets.lookup(@table_name, {:domain, domain_name}) do
      [{{:domain, ^domain_name}, entry}] ->
        if is_expired?(entry.cached_at) do
          :ets.delete(@table_name, {:domain, domain_name})
          {:error, :expired}
        else
          {:ok, entry}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def get_all_domains do
    :ets.match_object(@table_name, {{:domain, :_}, :_})
    |> Enum.map(fn {_key, entry} -> entry end)
    |> Enum.filter(fn entry ->
      not is_expired?(entry.cached_at)
    end)
  end

  def put_entity_count(count_data) do
    domain = count_data[:domain]
    count = count_data[:count] || 0

    entry = %{
      type: :entity_count,
      domain: domain,
      count: count,
      cached_at: count_data[:cached_at] || DateTime.utc_now()
    }

    :ets.insert(@table_name, {{:entity_count, domain}, entry})
    Logger.debug("[Mesh.Cache] Cached entity count for #{domain}: #{count}")
    :ok
  end

  def get_entity_count(domain_name) do
    case :ets.lookup(@table_name, {:entity_count, domain_name}) do
      [{{:entity_count, ^domain_name}, entry}] ->
        if is_expired?(entry.cached_at) do
          :ets.delete(@table_name, {:entity_count, domain_name})
          {:error, :expired}
        else
          {:ok, entry.count}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def put_quality_score(score_data) do
    entity_id = score_data[:entity_id]
    score = score_data[:score] || 0.0

    entry = %{
      type: :quality_score,
      entity_id: entity_id,
      score: score,
      checks_passed: score_data[:checks_passed] || 0,
      checks_failed: score_data[:checks_failed] || 0,
      cached_at: score_data[:cached_at] || DateTime.utc_now()
    }

    :ets.insert(@table_name, {{:quality, entity_id}, entry})
    Logger.debug("[Mesh.Cache] Cached quality score for #{entity_id}: #{score}")
    :ok
  end

  def get_quality_score(entity_id) do
    case :ets.lookup(@table_name, {:quality, entity_id}) do
      [{{:quality, ^entity_id}, entry}] ->
        if is_expired?(entry.cached_at) do
          :ets.delete(@table_name, {:quality, entity_id})
          {:error, :expired}
        else
          {:ok, entry}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def invalidate_domain(domain_name) do
    :ets.delete(@table_name, {:domain, domain_name})
    :ets.delete(@table_name, {:entity_count, domain_name})
    Logger.info("[Mesh.Cache] Invalidated domain: #{domain_name}")
    :ok
  end

  def invalidate_entity(entity_id) do
    :ets.delete(@table_name, {:quality, entity_id})
    Logger.info("[Mesh.Cache] Invalidated entity: #{entity_id}")
    :ok
  end

  def invalidate_all do
    :ets.delete_all_objects(@table_name)
    Logger.info("[Mesh.Cache] Invalidated all entries")
    :ok
  end

  # ── BusinessOS Cache Keys ─────────────────────────────────────────────
  # ETS singletons — no TTL expiry; SyncWorker refreshes every 5 min.

  def put_bos_status(data) when is_map(data) do
    :ets.insert(@table_name, {{:bos_status, :singleton}, data})
    :ok
  end

  def get_bos_status do
    case :ets.lookup(@table_name, {:bos_status, :singleton}) do
      [{{:bos_status, :singleton}, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def put_compliance_status(data) when is_map(data) do
    :ets.insert(@table_name, {{:compliance_status, :singleton}, data})
    :ok
  end

  def get_compliance_status do
    case :ets.lookup(@table_name, {:compliance_status, :singleton}) do
      [{{:compliance_status, :singleton}, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def put_kpis(data) when is_map(data) do
    :ets.insert(@table_name, {{:bos_kpis, :singleton}, data})
    :ok
  end

  def get_kpis do
    case :ets.lookup(@table_name, {:bos_kpis, :singleton}) do
      [{{:bos_kpis, :singleton}, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def cache_info do
    size = :ets.info(@table_name, :size)
    memory = :ets.info(@table_name, :memory)

    %{
      size: size,
      # ETS returns memory in words, convert to bytes
      memory_bytes: memory * 8,
      entries: size,
      ttl_minutes:
        String.to_integer(System.get_env("MESH_CACHE_TTL_MINUTES", "#{@default_ttl_minutes}"))
    }
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp is_expired?(cached_at) do
    ttl_minutes =
      String.to_integer(System.get_env("MESH_CACHE_TTL_MINUTES", "#{@default_ttl_minutes}"))

    ttl_seconds = ttl_minutes * 60

    age_seconds =
      DateTime.utc_now()
      |> DateTime.diff(cached_at, :second)

    age_seconds > ttl_seconds
  end
end
