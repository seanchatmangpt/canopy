defmodule Canopy.Autonomic.ExecutionLog do
  @moduledoc """
  ETS ring-buffer recording agent execution outcomes.

  No supervised process — all state in ETS `:canopy_execution_log` (ordered_set).
  Tracks up to @max_depth outcomes per agent_id; oldest are evicted automatically.

  ## WvdA Boundedness

  Bounded by `@max_depth 10` per agent_id (no unbounded growth).

  ## Key Schema

      {agent_id, monotonic_ms} → %{outcome: :success | :failure, latency_ms: integer, recorded_at: DateTime}
  """

  require Logger

  @table :canopy_execution_log
  @max_depth 10

  @doc "Initialize ETS table. Call from Application.start/2 before supervision tree."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :ordered_set, :public, {:write_concurrency, true}])
    end

    :ok
  end

  @doc """
  Record an execution outcome for `agent_id`.

  `result` map should include `:outcome` (`:success` | `:failure`) and optionally
  `:latency_ms`.

  Evicts oldest entry when depth exceeds @max_depth (ring buffer behaviour).
  """
  @spec record(term(), map()) :: :ok
  def record(agent_id, result) when is_map(result) do
    key = {agent_id, System.monotonic_time(:millisecond)}

    entry = %{
      outcome: result[:outcome] || result["outcome"] || :unknown,
      latency_ms: result[:latency_ms] || result["latency_ms"] || 0,
      recorded_at: DateTime.utc_now()
    }

    :ets.insert(@table, {key, entry})

    # Evict oldest entries beyond @max_depth
    evict_oldest(agent_id)
    :ok
  end

  @doc "Return the N most recent outcomes for `agent_id` (newest-first)."
  @spec recent_results(term(), pos_integer()) :: [map()]
  def recent_results(agent_id, n \\ @max_depth) do
    # ordered_set with {agent_id, monotonic_ms} keys — select by agent_id prefix
    ms_range = :ets.select(@table, [
      {{{agent_id, :_}, :_}, [], [:"$_"]}
    ])

    ms_range
    |> Enum.sort_by(fn {{_id, ts}, _v} -> ts end, :desc)
    |> Enum.take(n)
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  @doc "Count consecutive failures at the tail of the log for `agent_id`."
  @spec consecutive_failures(term()) :: non_neg_integer()
  def consecutive_failures(agent_id) do
    recent_results(agent_id, @max_depth)
    |> Enum.take_while(&(&1.outcome == :failure))
    |> length()
  end

  @doc "Return the most recent outcome entry for `agent_id`, or nil."
  @spec last_outcome(term()) :: map() | nil
  def last_outcome(agent_id) do
    case recent_results(agent_id, 1) do
      [entry] -> entry
      [] -> nil
    end
  end

  @doc "Remove all execution log entries for `agent_id`."
  @spec clear(term()) :: :ok
  def clear(agent_id) do
    entries = :ets.select(@table, [{{{agent_id, :_}, :_}, [], [:"$_"]}])

    Enum.each(entries, fn {key, _} ->
      :ets.delete(@table, key)
    end)

    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp evict_oldest(agent_id) do
    entries = :ets.select(@table, [{{{agent_id, :_}, :_}, [], [:"$_"]}])

    if length(entries) > @max_depth do
      # ordered_set is sorted by key; oldest = smallest monotonic_ms
      sorted = Enum.sort_by(entries, fn {{_id, ts}, _v} -> ts end)
      to_delete = Enum.take(sorted, length(entries) - @max_depth)

      Enum.each(to_delete, fn {key, _} ->
        :ets.delete(@table, key)
      end)
    end
  end
end
