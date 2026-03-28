defmodule Canopy.Autonomic.ScheduleGovernor do
  @moduledoc """
  ETS-based schedule governor that can skip or back-off agent executions.

  No supervised process — state in ETS `:canopy_schedule_governor`.

  ## Skip Conditions

  An agent execution is skipped when:
  1. `businessos_down?/0` is true AND the agent's adapter is `"businessos"`
  2. The CircuitBreaker for `:businessos` is `:open`

  ## Adaptive Back-off

  `next_interval_ms/2` returns an increased interval when an agent has
  consecutive failures, bounded by @min_interval_ms and @max_interval_ms.

  ## WvdA Boundedness

  @min_interval_ms and @max_interval_ms cap interval growth.
  """

  require Logger

  alias Canopy.Autonomic.CircuitBreaker
  alias Canopy.Autonomic.ExecutionLog

  @table :canopy_schedule_governor
  @min_interval_ms 30_000
  @max_interval_ms 3_600_000

  @doc "Initialize ETS table. Call from Application.start/2 before supervision tree."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, {:write_concurrency, true}])
    end

    :ok
  end

  @doc """
  Returns true if the scheduled execution should be skipped.

  Skip conditions:
  1. BusinessOS is down AND adapter is "businessos"
  2. CircuitBreaker for :businessos is :open

  `adapter` is a string matching the agent's adapter field.
  """
  @spec should_skip?(term(), term(), String.t() | nil) :: boolean()
  def should_skip?(agent_id, _schedule_id, adapter) do
    bos_dependent = adapter == "businessos"

    skip =
      (bos_dependent and businessos_down?()) or
        (bos_dependent and CircuitBreaker.state(:businessos) == :open)

    if skip do
      Logger.debug(
        "[ScheduleGovernor] Skipping agent #{agent_id} (bos_down=#{businessos_down?()}, " <>
          "circuit=#{CircuitBreaker.state(:businessos)})"
      )
    end

    skip
  end

  @doc """
  Calculate the next interval for an agent, applying adaptive back-off.

  Returns `base_ms` doubled per consecutive failure, bounded by
  @min_interval_ms and @max_interval_ms.
  """
  @spec next_interval_ms(term(), pos_integer()) :: pos_integer()
  def next_interval_ms(agent_id, base_ms) do
    failures = ExecutionLog.consecutive_failures(agent_id)

    scaled = trunc(base_ms * :math.pow(2, min(failures, 10)))

    max(@min_interval_ms, min(scaled, @max_interval_ms))
  end

  @doc """
  Update skip flags based on HealthAgent results.

  `health_results` is the map returned by `HealthAgent.run/0`:
  `%{status: ..., alerts: [...]}`.

  Sets the `businessos_down` flag when BusinessOS is unreachable or degraded.
  """
  @spec update_flags(map()) :: :ok
  def update_flags(health_results) when is_map(health_results) do
    alerts = health_results[:alerts] || []

    bos_down =
      Enum.any?(alerts, fn
        {:businessos, %{healthy: false}} -> true
        {:businessos, %{status: "unreachable"}} -> true
        _ -> false
      end)

    :ets.insert(@table, {:businessos_down, bos_down})

    if bos_down do
      Logger.warning("[ScheduleGovernor] BusinessOS flagged as down — BOS-dependent agents skipped")
    end

    :ok
  end

  def update_flags(_other), do: :ok

  @doc "Returns true when the HealthAgent has flagged BusinessOS as down."
  @spec businessos_down?() :: boolean()
  def businessos_down? do
    case :ets.lookup(@table, :businessos_down) do
      [{:businessos_down, value}] -> value
      [] -> false
    end
  end
end
