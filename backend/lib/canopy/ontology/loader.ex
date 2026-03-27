defmodule Canopy.Ontology.Loader do
  @moduledoc """
  Manages ontology loading and caching on Canopy startup.

  Loads available ontologies from OSA registry on application startup
  and maintains a local cache for fast lookups. Provides cache management
  functions for refresh, eviction, and statistics.
  """
  use GenServer

  require Logger

  alias Canopy.Ontology.Client

  @cache_table :ontology_cache
  @stats_table :ontology_stats
  # 1 hour
  @default_ttl_seconds 3600
  # 30 minutes
  @refresh_interval_seconds 1800

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Start the ontology loader GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Load all ontologies from OSA into local cache.

  Called on application startup. Fetches ontology list from OSA
  and stores in ETS for fast access.

  Returns:
    {:ok, ontology_count}
    {:error, reason}
  """
  def load_all do
    GenServer.call(__MODULE__, :load_all, 30000)
  end

  @doc """
  Get a cached ontology by ID.

  Returns:
    {:ok, ontology_map} if found and not expired
    {:error, :not_found} if not in cache
    {:error, :expired} if TTL exceeded
  """
  def get_ontology(ontology_id) do
    case :ets.lookup(@cache_table, ontology_id) do
      [{^ontology_id, ontology, timestamp}] ->
        ttl = System.get_env("ONTOLOGY_CACHE_TTL_SEC") || @default_ttl_seconds
        ttl_ms = String.to_integer(ttl) * 1000

        if System.monotonic_time(:millisecond) - timestamp < ttl_ms do
          {:ok, ontology}
        else
          :ets.delete(@cache_table, ontology_id)
          {:error, :expired}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Search cached ontologies by name/description.

  Returns:
    [ontologies_matching_query]
  """
  def search_cached(query_term) when is_binary(query_term) do
    query_lower = String.downcase(query_term)

    :ets.tab2list(@cache_table)
    |> Enum.filter(fn {_id, ontology, _ts} ->
      name = Map.get(ontology, "name", "") |> String.downcase()
      desc = Map.get(ontology, "description", "") |> String.downcase()
      String.contains?(name, query_lower) or String.contains?(desc, query_lower)
    end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  List all cached ontologies.

  Returns:
    [ontology_maps]
  """
  def list_cached do
    :ets.tab2list(@cache_table)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Get cache statistics.

  Returns:
    %{
      "cached_ontologies" => count,
      "cache_size_bytes" => approx_size,
      "oldest_entry_age_seconds" => age,
      "ttl_seconds" => ttl
    }
  """
  def cache_stats do
    cache_info = :ets.info(@cache_table)
    # Words to bytes
    size = Keyword.get(cache_info, :memory, 0) * 8

    oldest_timestamp =
      :ets.tab2list(@cache_table)
      |> Enum.map(&elem(&1, 2))
      |> Enum.min(fn -> System.monotonic_time(:millisecond) end)

    age_ms = System.monotonic_time(:millisecond) - oldest_timestamp
    age_seconds = div(age_ms, 1000)

    ttl =
      System.get_env("ONTOLOGY_CACHE_TTL_SEC")
      |> case do
        nil -> @default_ttl_seconds
        val -> String.to_integer(val)
      end

    %{
      "cached_ontologies" => Keyword.get(cache_info, :size, 0),
      "cache_size_bytes" => size,
      "oldest_entry_age_seconds" => max(0, age_seconds),
      "ttl_seconds" => ttl
    }
  end

  @doc """
  Clear all cached ontologies.

  Returns:
    :ok
  """
  def clear_cache do
    :ets.delete_all_objects(@cache_table)
    Logger.info("Ontology cache cleared")
    :ok
  end

  @doc """
  Refresh cache from OSA.

  Reloads ontology list and updates cache with fresh data.

  Returns:
    {:ok, new_count}
    {:error, reason}
  """
  def refresh_cache do
    GenServer.call(__MODULE__, :load_all, 30000)
  end

  # ── GenServer Callbacks ──────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@cache_table, [:named_table, :set, :protected])
    :ets.new(@stats_table, [:named_table, :set, :protected])

    # Start periodic refresh
    schedule_refresh()

    # Load ontologies on startup
    case load_ontologies_from_osa() do
      {:ok, count} ->
        Logger.info("Loaded #{count} ontologies on startup")
        {:ok, %{loaded_count: count, last_refresh: System.monotonic_time(:second)}}

      {:error, reason} ->
        Logger.warning("Failed to load ontologies on startup: #{inspect(reason)}")
        {:ok, %{loaded_count: 0, last_refresh: System.monotonic_time(:second)}}
    end
  end

  @impl true
  def handle_call(:load_all, _from, state) do
    case load_ontologies_from_osa() do
      {:ok, count} ->
        new_state = Map.put(state, :last_refresh, System.monotonic_time(:second))
        {:reply, {:ok, count}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:refresh_cache, state) do
    case load_ontologies_from_osa() do
      {:ok, count} ->
        Logger.debug("Refreshed ontology cache: #{count} ontologies")
        schedule_refresh()
        {:noreply, Map.put(state, :last_refresh, System.monotonic_time(:second))}

      {:error, reason} ->
        Logger.warning("Ontology cache refresh failed: #{inspect(reason)}")
        schedule_refresh()
        {:noreply, state}
    end
  end

  # ── Private Helpers ──────────────────────────────────────────────────────

  defp load_ontologies_from_osa do
    case Client.list_ontologies(limit: 1000, offset: 0) do
      {:ok, ontologies, _total} ->
        timestamp = System.monotonic_time(:millisecond)

        Enum.each(ontologies, fn ontology ->
          ontology_id = Map.get(ontology, "id") || Map.get(ontology, :id)

          if ontology_id do
            :ets.insert(@cache_table, {ontology_id, ontology, timestamp})
          end
        end)

        {:ok, length(ontologies)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_refresh do
    interval_ms = @refresh_interval_seconds * 1000
    Process.send_after(self(), :refresh_cache, interval_ms)
  end
end
