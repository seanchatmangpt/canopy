defmodule Canopy.Autonomic.AutoRecoveryTest do
  use ExUnit.Case, async: false

  alias Canopy.Autonomic.AutoRecovery
  alias Canopy.Autonomic.CircuitBreaker
  alias Canopy.Autonomic.ExecutionLog

  # ---------------------------------------------------------------------------
  # Pure-function tests — backoff_interval_ms/1
  # No ETS, no Ecto required.
  # ---------------------------------------------------------------------------
  describe "backoff_interval_ms/1 — pure exponential back-off" do
    test "backoff_doubles_per_threshold" do
      assert AutoRecovery.backoff_interval_ms(0) == 60_000
      assert AutoRecovery.backoff_interval_ms(1) == 120_000
      assert AutoRecovery.backoff_interval_ms(2) == 240_000
    end

    test "backoff_caps_at_max" do
      assert AutoRecovery.backoff_interval_ms(100) == 3_600_000
    end
  end

  # ---------------------------------------------------------------------------
  # should_reset?/1 tests — require ETS (ExecutionLog)
  # ---------------------------------------------------------------------------
  describe "should_reset?/1 — consecutive failure threshold" do
    setup do
      CircuitBreaker.init()
      ExecutionLog.init()

      agent_id = "recovery-test-#{System.unique_integer([:positive])}"

      on_exit(fn ->
        :ets.delete_all_objects(:canopy_circuit_breaker)
        ExecutionLog.clear(agent_id)
      end)

      {:ok, agent_id: agent_id}
    end

    test "should_reset?/1 false when status is not error", %{agent_id: agent_id} do
      agent = %{id: agent_id, status: "idle", recovery_attempts: 0}

      refute AutoRecovery.should_reset?(agent)
    end

    test "should_reset?/1 false when failures below threshold", %{agent_id: agent_id} do
      # Record only 2 consecutive failures (threshold is 5).
      # Sleep 2ms between records so each gets a distinct monotonic_ms key.
      for _ <- 1..2 do
        ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 50})
        Process.sleep(2)
      end

      agent = %{id: agent_id, status: "error", recovery_attempts: 0}

      refute AutoRecovery.should_reset?(agent)
    end

    test "should_reset?/1 true when error status and 5+ consecutive failures",
         %{agent_id: agent_id} do
      # Record 5 consecutive failures to meet the recovery threshold.
      # ExecutionLog keys are {agent_id, monotonic_ms}; sleep 2ms between
      # records ensures distinct timestamps in the ordered_set.
      for _ <- 1..5 do
        ExecutionLog.record(agent_id, %{outcome: :failure, latency_ms: 50})
        Process.sleep(2)
      end

      agent = %{id: agent_id, status: "error", recovery_attempts: 0}

      assert AutoRecovery.should_reset?(agent)
    end
  end
end
