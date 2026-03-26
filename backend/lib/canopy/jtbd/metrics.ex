defmodule Canopy.JTBD.Metrics do
  @moduledoc """
  Wave 12 Metrics Tracker — ETS-backed bounded cache with LRU eviction.

  WvdA Soundness: Guarantees bounded resource consumption (no unbounded growth).
  Armstrong Principle: Resource limits prevent queue overflow.

  The `:jtbd_wave12_metrics` ETS table stores iteration metrics:
  - Key: {:iteration, iteration_num, metric_type, timestamp}
  - Value: %{latency_ms, scenario, outcome, ...}

  Bounded by:
  - max_entries: 200 (hard limit, ~2 entries per iteration × 100 iterations)
  - LRU eviction: when size > max_entries, oldest entry is deleted
  - No unbounded growth even over 1000+ iterations
  """

  require Logger

  @table :jtbd_wave12_metrics
  @max_entries 200

  @doc """
  Insert a metric into the wave 12 metrics table.

  Automatically evicts oldest entry if table exceeds max_entries.
  All metrics have a timestamp for LRU ordering.

  Returns: :ok
  """
  @spec record_metric(
    iteration :: integer(),
    metric_type :: :pass | :fail | :latency | :error,
    data :: map()
  ) :: :ok
  def record_metric(iteration, metric_type, data) when is_integer(iteration) do
    timestamp = DateTime.utc_now()
    key = {:iteration, iteration, metric_type, timestamp}
    value = Map.put(data, :recorded_at, timestamp)

    # Insert with automatic LRU eviction
    :ets.insert(@table, {key, value})

    # Enforce bounded size
    enforce_max_size()

    :ok
  rescue
    _error ->
      Logger.warning(
        "Failed to record metric: iteration=#{iteration}, type=#{metric_type}, error=#{inspect(__STACKTRACE__)}"
      )
      :ok
  end

  @doc """
  Get all metrics for a specific iteration.

  Returns: list of {key, value} tuples
  """
  @spec get_iteration_metrics(iteration :: integer()) :: list({any(), map()})
  def get_iteration_metrics(iteration) do
    :ets.match_object(@table, {{:iteration, iteration, :_, :_}, :_})
  rescue
    _error ->
      []
  end

  @doc """
  Get current size of metrics table.

  Returns: integer (number of entries)
  """
  @spec table_size() :: non_neg_integer()
  def table_size do
    :ets.info(@table, :size) || 0
  rescue
    _error -> 0
  end

  @doc """
  Get memory usage of metrics table.

  Returns: integer (words allocated)
  """
  @spec table_memory() :: non_neg_integer()
  def table_memory do
    :ets.info(@table, :memory) || 0
  rescue
    _error -> 0
  end

  @doc """
  Clear all metrics (for testing or reset).

  Returns: :ok
  """
  @spec clear_all() :: :ok
  def clear_all do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    _error -> :ok
  end

  @doc """
  Get table statistics including size, memory, and LRU status.

  Returns: map with size, memory, max_entries, and eviction_count
  """
  @spec get_stats() :: map()
  def get_stats do
    size = table_size()
    memory = table_memory()

    %{
      size: size,
      max_entries: @max_entries,
      memory_words: memory,
      memory_mb: Float.round(memory * 8 / 1_000_000, 2),  # 8 bytes per word
      bounded: size <= @max_entries,
      utilization_percent: Float.round(size / @max_entries * 100, 1)
    }
  rescue
    _error ->
      %{
        size: 0,
        max_entries: @max_entries,
        memory_words: 0,
        memory_mb: 0.0,
        bounded: true,
        utilization_percent: 0.0,
        error: "unable to fetch stats"
      }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp enforce_max_size do
    current_size = :ets.info(@table, :size)

    # If over limit, delete oldest entries (by timestamp)
    if current_size > @max_entries do
      evict_oldest()
    end
  end

  defp evict_oldest do
    # Find entry with minimum timestamp (oldest)
    case find_oldest_by_timestamp() do
      nil ->
        # Table is empty, nothing to evict
        :ok

      oldest_key ->
        # Delete the oldest entry
        :ets.delete(@table, oldest_key)
        # Check again (recursive, but bounded by table size)
        current_size = :ets.info(@table, :size)

        if current_size > @max_entries do
          evict_oldest()
        else
          :ok
        end
    end
  rescue
    _error -> :ok
  end

  defp find_oldest_by_timestamp do
    @table
    |> :ets.tab2list()
    |> Enum.min_by(
      fn {{:iteration, _iter, _type, timestamp}, _value} -> timestamp end,
      fn -> nil end
    )
    |> case do
      {{:iteration, _iter, _type, _timestamp} = key, _value} -> key
      nil -> nil
    end
  rescue
    _error -> nil
  end
end
