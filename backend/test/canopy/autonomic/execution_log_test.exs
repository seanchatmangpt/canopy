defmodule Canopy.Autonomic.ExecutionLogTest do
  use ExUnit.Case, async: false

  alias Canopy.Autonomic.ExecutionLog

  setup do
    ExecutionLog.init()
    agent_id = "test-agent-#{System.unique_integer([:positive])}"
    on_exit(fn -> ExecutionLog.clear(agent_id) end)
    {:ok, agent_id: agent_id}
  end

  describe "consecutive_failures/1" do
    test "consecutive_failures_counts_correctly", %{agent_id: agent_id} do
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 10})
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 11})
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 12})

      assert ExecutionLog.consecutive_failures(agent_id) == 3
    end

    test "consecutive_failures_resets_at_success", %{agent_id: agent_id} do
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 10})
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 11})
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :success, latency_ms: 5})

      assert ExecutionLog.consecutive_failures(agent_id) == 0
    end
  end

  describe "last_outcome/1" do
    test "last_outcome/1 returns most recent entry", %{agent_id: agent_id} do
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 20})
      # Small sleep to ensure monotonic timestamps differ
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :success, latency_ms: 5})

      result = ExecutionLog.last_outcome(agent_id)

      assert result != nil
      assert result.outcome == :success
    end
  end

  describe "recent_results/2" do
    test "recent_results/2 returns newest first", %{agent_id: agent_id} do
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 30})
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :success, latency_ms: 10})
      Process.sleep(2)
      ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 50})

      results = ExecutionLog.recent_results(agent_id, 3)

      assert length(results) == 3
      # Newest entry is a failure with latency 50
      [first | _] = results
      assert first.outcome == :failure
      assert first.latency_ms == 50
    end

    test "ring buffer evicts oldest beyond max_depth", %{agent_id: agent_id} do
      # Record 11 entries — one more than the @max_depth of 10
      for i <- 1..11 do
        Process.sleep(2)
        ExecutionLog.record(agent_id, %{outcome: :success, latency_ms: i})
      end

      results = ExecutionLog.recent_results(agent_id)

      assert length(results) <= 10
    end
  end
end
