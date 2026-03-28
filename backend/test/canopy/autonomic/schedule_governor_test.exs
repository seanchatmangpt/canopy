defmodule Canopy.Autonomic.ScheduleGovernorTest do
  use ExUnit.Case, async: false

  alias Canopy.Autonomic.CircuitBreaker
  alias Canopy.Autonomic.ExecutionLog
  alias Canopy.Autonomic.ScheduleGovernor

  setup do
    CircuitBreaker.init()
    ExecutionLog.init()
    ScheduleGovernor.init()

    agent_id = "gov-test-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      :ets.delete_all_objects(:canopy_schedule_governor)
      :ets.delete_all_objects(:canopy_circuit_breaker)
      ExecutionLog.clear(agent_id)
    end)

    {:ok, agent_id: agent_id}
  end

  describe "should_skip?/3 — businessos dependency" do
    test "skip_when_bos_down_and_agent_depends_on_bos", %{agent_id: agent_id} do
      ScheduleGovernor.update_flags(%{
        alerts: [{:businessos, %{healthy: false}}]
      })

      assert ScheduleGovernor.should_skip?(agent_id, "sched-1", "businessos") == true
    end

    test "no_skip_for_non_bos_agent", %{agent_id: agent_id} do
      # Flag BusinessOS as down
      ScheduleGovernor.update_flags(%{
        alerts: [{:businessos, %{healthy: false}}]
      })

      # An OSA-backed agent must not be skipped
      assert ScheduleGovernor.should_skip?(agent_id, "sched-1", "osa") == false

      # An agent with no adapter (nil) must not be skipped either
      assert ScheduleGovernor.should_skip?(agent_id, "sched-1", nil) == false
    end

    test "no_skip_when_bos_up", %{agent_id: agent_id} do
      # Provide health results with no BusinessOS alerts
      ScheduleGovernor.update_flags(%{alerts: []})

      assert ScheduleGovernor.businessos_down?() == false
      assert ScheduleGovernor.should_skip?(agent_id, "sched-1", "businessos") == false
    end
  end

  describe "next_interval_ms/2 — adaptive back-off" do
    test "next_interval_ms/2 returns base when no failures", %{agent_id: agent_id} do
      # No log entries → zero consecutive failures → returns base_ms (≥ @min_interval_ms)
      base_ms = 60_000
      result = ScheduleGovernor.next_interval_ms(agent_id, base_ms)

      # Must honour min-interval (30_000) and return exactly base_ms when no failures
      assert result == base_ms
    end

    test "next_interval_ms/2 doubles per consecutive failure", %{agent_id: agent_id} do
      base_ms = 60_000

      # Record 1 consecutive failure for this agent.
      # No need to sleep — a single record is always a distinct key.
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 100})

      result = ScheduleGovernor.next_interval_ms(agent_id, base_ms)

      # 1 failure → base_ms × 2^1 = 120_000
      assert result == base_ms * 2
    end
  end
end
