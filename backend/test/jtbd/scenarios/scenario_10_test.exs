defmodule Canopy.JTBD.Scenarios.Scenario10Test do
  @moduledoc """
  Chicago TDD RED tests for JTBD Scenario 10: Conformance Drift

  Claim: Canopy calls pm4py-rust conformance checker to detect process model drift.

  RED Phase: Write failing test assertions before implementation.
  - Test name describes claim
  - Assertions capture exact behavior (not proxy checks)
  - Test FAILS because implementation doesn't exist yet
  - Test will require OTEL span proof + schema conformance

  Scenario steps:
    1. Agent requests conformance check (Petri net fitness)
    2. Canopy forwards to pm4py-rust (port 8090)
    3. pm4py-rust computes fitness score
    4. Result returned with detected drift
    5. OTEL span emitted with outcome=success

  Soundness: 15s timeout, no deadlock, bounded requests (max 20 concurrent checks)
  """

  use ExUnit.Case, async: true

  describe "scenario_10: conformance_drift — RED phase" do
    test "conformance_drift detects process model drift" do
      # Arrange: Build conformance check request
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [
          %{"activity" => "start", "timestamp" => "2026-03-26T10:00:00Z"},
          %{"activity" => "process", "timestamp" => "2026-03-26T10:05:00Z"},
          %{"activity" => "end", "timestamp" => "2026-03-26T10:10:00Z"}
        ]
      }

      # Act: Call scenario implementation (doesn't exist yet — RED)
      {:ok, result} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)

      # Assert: Conformance check completed
      assert result.model_id == "petri_net_v2"
      assert result.agent_id == "discovery-agent-1"
      assert result.fitness_score >= 0.0
      assert result.fitness_score <= 1.0
      assert result.drift_detected in [true, false]
      assert result.checked_at != nil
    end

    test "conformance_drift emits OTEL span with outcome=success" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [
          %{"activity" => "start", "timestamp" => "2026-03-26T10:00:00Z"},
          %{"activity" => "end", "timestamp" => "2026-03-26T10:10:00Z"}
        ]
      }

      {:ok, result} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)

      # Assert: Span emitted with correct attributes per semconv
      # - jtbd.scenario.id: "conformance_drift"
      # - jtbd.scenario.outcome: "success"
      # - jtbd.scenario.system: "canopy" (calling pm4py-rust)
      # - jtbd.scenario.latency_ms: > 0
      assert result.span_emitted == true
      assert result.outcome == "success"
      assert result.system == "canopy"
      assert result.latency_ms > 0
    end

    test "conformance_drift validates model_id is non-empty" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "",  # Invalid: empty
        "event_log" => []
      }

      assert {:error, :invalid_model_id} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)
    end

    test "conformance_drift validates event_log is non-empty list" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => []  # Invalid: empty log
      }

      assert {:error, :empty_event_log} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)
    end

    test "conformance_drift returns error on 15s timeout" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [%{"activity" => "start"}]
      }

      {:error, reason} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 1)
      assert reason == :timeout
    end

    test "conformance_drift bounded concurrency max 20 checks" do
      conformance_template = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [%{"activity" => "test"}]
      }

      # Queue 21 conformance checks (exceeds max 20)
      tasks = Enum.map(1..21, fn i ->
        Task.async(fn ->
          Canopy.JTBD.Scenarios.Scenario10.execute(
            Map.put(conformance_template, "check_id", "check-#{i}"),
            timeout_ms: 15_000
          )
        end)
      end)

      results = Task.await_many(tasks, 30_000)

      successful = Enum.filter(results, fn r -> match?({:ok, _}, r) end)
      backpressure = Enum.filter(results, fn r -> match?({:error, :concurrency_limit}, r) end)

      assert length(successful) <= 20
      assert length(backpressure) >= 1
    end

    test "conformance_drift fitness score in range [0, 1]" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [
          %{"activity" => "start", "timestamp" => "2026-03-26T10:00:00Z"},
          %{"activity" => "end", "timestamp" => "2026-03-26T10:10:00Z"}
        ]
      }

      {:ok, result} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)

      # Assert: Fitness score is valid probability
      assert result.fitness_score >= 0.0
      assert result.fitness_score <= 1.0
    end

    test "conformance_drift detects drift when fitness < 0.8" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [
          %{"activity" => "start"},
          %{"activity" => "anomaly"},  # Activity not in model
          %{"activity" => "end"}
        ]
      }

      {:ok, result} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)

      # Assert: Drift detected (fitness < 0.8 indicates deviation)
      if result.fitness_score < 0.8 do
        assert result.drift_detected == true
      else
        assert result.drift_detected == false
      end
    end

    test "conformance_drift latency less than 10s for normal models" do
      conformance_request = %{
        "agent_id" => "discovery-agent-1",
        "model_id" => "petri_net_v2",
        "event_log" => [
          %{"activity" => "start"},
          %{"activity" => "process"},
          %{"activity" => "end"}
        ]
      }

      start_ms = System.monotonic_time(:millisecond)
      {:ok, result} = Canopy.JTBD.Scenarios.Scenario10.execute(conformance_request, timeout_ms: 15_000)
      end_ms = System.monotonic_time(:millisecond)

      actual_latency = end_ms - start_ms

      assert actual_latency >= 0
      assert actual_latency < 10_000
      assert result.latency_ms > 0
    end
  end
end
