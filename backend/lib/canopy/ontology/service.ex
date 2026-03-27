defmodule Canopy.Ontology.Service do
  @moduledoc """
  Business logic layer for ontology management in Canopy.

  Provides caching and coordination between the HTTP client (Canopy.Ontology.Client)
  and Phoenix controllers. Acts as a GenServer to manage ontology cache state.

  Cache Strategy:
    - ontologies: Full list cached for 5 minutes
    - classes: Individual class details cached for 10 minutes
    - search: Search results cached for 2 minutes
    - statistics: Global statistics cached for 1 minute

  Uses ETS for mutable state (cache_hits, cache_misses counters).
  """
  use GenServer

  require Logger

  alias Canopy.Ontology.Client

  @call_timeout 5_000

  # Public API

  @doc """
  Start the service GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  List available ontologies with caching.

  Options:
    - limit: Max results (default 50)
    - offset: Pagination offset (default 0)
    - cache: Use cache if available (default true)

  Returns:
    {:ok, ontologies, total, metadata}
    {:error, reason}

  Metadata includes:
    - cache_hit: boolean (whether result came from cache)
    - retrieved_at: DateTime when data was fetched
  """
  def list_ontologies(opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    cache_key = {:ontologies, {limit, offset}}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, ontologies, total, metadata} = get_cached(cache_key)
      {:ok, ontologies, total, Map.put(metadata, :cache_hit, true)}
    else
      case Client.list_ontologies(limit: limit, offset: offset) do
        {:ok, ontologies, total} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            count: length(ontologies),
            total: total
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, ontologies, total, metadata}, ttl_seconds: 300)
          {:ok, ontologies, total, metadata}

        {:error, reason} ->
          Logger.error("Failed to list ontologies: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Get detailed information about a specific ontology.

  Options:
    - cache: Use cache if available (default true)

  Returns:
    {:ok, ontology_map, metadata}
    {:error, reason}
  """
  def get_ontology(ontology_id, opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    cache_key = {:ontology, ontology_id}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, ontology, metadata} = get_cached(cache_key)
      {:ok, ontology, Map.put(metadata, :cache_hit, true)}
    else
      case Client.get_ontology(ontology_id) do
        {:ok, ontology} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            ontology_id: ontology_id
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, ontology, metadata}, ttl_seconds: 600)
          {:ok, ontology, metadata}

        {:error, reason} ->
          Logger.error("Failed to get ontology #{ontology_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Search for classes and properties in an ontology.

  Options:
    - type: "class", "property", or "both" (default: "both")
    - limit: Max results (default: 20)
    - offset: Pagination offset (default: 0)
    - cache: Use cache if available (default true)

  Returns:
    {:ok, [results], metadata}
    {:error, reason}
  """
  def search(ontology_id, query, opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    search_type = Keyword.get(opts, :type, "both")
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    cache_key = {:search, {ontology_id, query, search_type, limit, offset}}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, results, metadata} = get_cached(cache_key)
      {:ok, results, Map.put(metadata, :cache_hit, true)}
    else
      case Client.search(ontology_id, query,
             type: search_type,
             limit: limit,
             offset: offset
           ) do
        {:ok, results} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            query: query,
            ontology_id: ontology_id,
            count: length(results)
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, results, metadata}, ttl_seconds: 120)
          {:ok, results, metadata}

        {:error, reason} ->
          Logger.error("Search failed in #{ontology_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Get detailed information about a specific class in an ontology.

  Options:
    - cache: Use cache if available (default true)

  Returns:
    {:ok, class_info_map, metadata}
    {:error, reason}
  """
  def get_class(ontology_id, class_id, opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    cache_key = {:class, {ontology_id, class_id}}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, class_info, metadata} = get_cached(cache_key)
      {:ok, class_info, Map.put(metadata, :cache_hit, true)}
    else
      case Client.get_class(ontology_id, class_id) do
        {:ok, class_info} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            ontology_id: ontology_id,
            class_id: class_id
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, class_info, metadata}, ttl_seconds: 600)
          {:ok, class_info, metadata}

        {:error, reason} ->
          Logger.error("Failed to get class #{class_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Get statistics across all ontologies with caching.

  Options:
    - cache: Use cache if available (default true)

  Returns:
    {:ok, stats_map, metadata}
    {:error, reason}
  """
  def get_statistics(opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    cache_key = {:statistics, :global}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, stats, metadata} = get_cached(cache_key)
      {:ok, stats, Map.put(metadata, :cache_hit, true)}
    else
      case Client.get_statistics() do
        {:ok, stats} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, stats, metadata}, ttl_seconds: 60)
          {:ok, stats, metadata}

        {:error, reason} ->
          Logger.error("Failed to get statistics: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Reload ontologies from OSA and clear cache.

  Returns:
    :ok
    {:error, reason}
  """
  def reload_ontologies do
    case Client.reload_ontologies() do
      :ok ->
        clear_all_cache()
        Logger.info("Ontologies reloaded and cache cleared")
        :ok

      {:error, reason} ->
        Logger.error("Failed to reload ontologies: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get cache statistics (hits, misses, hit rate).

  Returns:
    %{hits: integer, misses: integer, hit_rate: float}
  """
  def cache_stats do
    GenServer.call(__MODULE__, :cache_stats, @call_timeout)
  end

  @doc """
  Clear all cached data.
  """
  def clear_all_cache do
    GenServer.call(__MODULE__, :clear_cache, @call_timeout)
  end

  @doc """
  Clear cache for a specific ontology.
  """
  def clear_ontology_cache(ontology_id) do
    GenServer.call(__MODULE__, {:clear_ontology, ontology_id}, @call_timeout)
  end

  # GenServer Callbacks

  @impl GenServer
  def init(_opts) do
    # Ensure ETS tables exist (create only if they don't exist)
    ensure_cache_table()
    ensure_stats_table()

    {:ok, %{}}
  end

  defp ensure_cache_table do
    case :ets.whereis(:ontology_cache) do
      :undefined ->
        :ets.new(:ontology_cache, [:set, :public, :named_table])

      _ ->
        :ok
    end
  end

  defp ensure_stats_table do
    case :ets.whereis(:ontology_cache_stats) do
      :undefined ->
        :ets.new(:ontology_cache_stats, [:set, :public, :named_table])
        :ets.insert(:ontology_cache_stats, cache_hits: 0, cache_misses: 0)

      _ ->
        # Reset counters
        :ets.delete_all_objects(:ontology_cache_stats)
        :ets.insert(:ontology_cache_stats, cache_hits: 0, cache_misses: 0)
    end
  end

  @impl GenServer
  def handle_call(:cache_stats, _from, state) do
    hits = get_ets_counter(:cache_hits)
    misses = get_ets_counter(:cache_misses)
    total = hits + misses
    hit_rate = if total > 0, do: hits / total, else: 0.0

    stats = %{
      hits: hits,
      misses: misses,
      total: total,
      hit_rate: Float.round(hit_rate, 3)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:clear_cache, _from, state) do
    :ets.delete_all_objects(:ontology_cache)
    :ets.delete_all_objects(:ontology_cache_stats)
    :ets.insert(:ontology_cache_stats, cache_hits: 0, cache_misses: 0)

    Logger.info("Ontology cache cleared")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:clear_ontology, ontology_id}, _from, state) do
    # Delete all cache entries related to this ontology
    :ets.delete_all_objects(:ontology_cache)

    Logger.info("Cache cleared for ontology #{ontology_id}")
    {:reply, :ok, state}
  end

  # Private Helpers

  defp cached?(key) do
    case :ets.lookup(:ontology_cache, key) do
      [{^key, _value, expires_at}] ->
        DateTime.utc_now() |> DateTime.before?(expires_at)

      [] ->
        false
    end
  end

  defp get_cached(key) do
    case :ets.lookup(:ontology_cache, key) do
      [{^key, value, _expires_at}] ->
        value

      [] ->
        nil
    end
  end

  defp cache_result(key, value, ttl_seconds: ttl) do
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)
    :ets.insert(:ontology_cache, {key, value, expires_at})
  end

  defp record_cache_hit do
    :ets.update_counter(:ontology_cache_stats, :cache_hits, {2, 1})
  end

  defp record_cache_miss do
    :ets.update_counter(:ontology_cache_stats, :cache_misses, {2, 1})
  end

  defp get_ets_counter(key) do
    case :ets.lookup(:ontology_cache_stats, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end
end
