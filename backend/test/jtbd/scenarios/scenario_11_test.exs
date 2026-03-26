defmodule Canopy.JTBD.Scenarios.Scenario11Test do
  @moduledoc """
  Chicago TDD RED tests for JTBD Scenario 11: Process Intelligence Query

  Claim: Canopy queries pm4py-rust for natural language insights about process models.
  Example: "What is the bottleneck?" → Returns insights with latency < 10s.

  RED Phase: Write failing test assertions before implementation.
  - Test name describes claim
  - Assertions capture exact behavior (not proxy checks)
  - Test FAILS because implementation doesn't exist yet
  - Test will require OTEL span proof + schema conformance

  Scenario steps:
    1. Agent sends natural language query about process model
    2. Scenario calls pm4py-rust API (POST /api/query)
    3. pm4py-rust analyzes model and returns insight
    4. Scenario returns insight with latency_ms
    5. OTEL span emitted with outcome=success

  Soundness: 10s timeout, no deadlock, bounded concurrency (max 20 queries)
  """

  use ExUnit.Case, async: false

  setup do
    # Reset the concurrency counter table before each test
    Canopy.JTBD.Scenarios.Scenario11.init_concurrency_table()
    :ok
  end

  describe "scenario_11: process_intelligence_query — RED phase" do
    test "process_intelligence_query executes with required parameters" do
      # Arrange: Build query per JTBD spec
      query_params = %{
        "query" => "What is the bottleneck?",
        "model_type" => "petri_net",
        "model_data" => %{"places" => [], "transitions" => []}
      }

      # Act: Call scenario implementation (doesn't exist yet — RED)
      {:ok, result} = Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 10_000)

      # Assert: Query executed and returned insight
      assert is_binary(result.query)
      assert result.query == "What is the bottleneck?"
      assert is_binary(result.insight)
      assert String.length(result.insight) > 0
      assert is_integer(result.latency_ms)
      assert result.latency_ms >= 0
    end

    test "process_intelligence_query emits OTEL span with outcome=success" do
      # Arrange: Query params
      query_params = %{
        "query" => "What is the bottleneck?",
        "model_type" => "petri_net",
        "model_data" => %{"places" => [], "transitions" => []}
      }

      # Act: Execute scenario
      {:ok, result} = Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 10_000)

      # Assert: Span emitted with correct attributes
      assert result.span_emitted == true
      assert result.outcome == "success"
      assert result.system == "canopy"
      assert result.latency_ms > 0
    end

    test "process_intelligence_query validates query is non-empty" do
      query_params = %{
        # Invalid: empty
        "query" => "",
        "model_type" => "petri_net"
      }

      assert {:error, :invalid_query} =
               Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 10_000)
    end

    test "process_intelligence_query accepts optional model_type" do
      # Arrange: Query without model_type
      query_params = %{
        "query" => "What is the bottleneck?"
        # model_type is optional
      }

      # Act: Should still work with default model_type
      {:ok, result} = Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 10_000)

      # Assert: Returns insight
      assert result.outcome == "success"
      assert is_binary(result.insight)
    end

    test "process_intelligence_query returns error on timeout" do
      query_params = %{
        "query" => "What is the bottleneck?",
        "model_type" => "petri_net"
      }

      {:error, reason} = Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 1)
      assert reason == :timeout
    end

    test "process_intelligence_query bounded concurrency max 20 queries" do
      query_template = %{
        "query" => "What is the bottleneck?",
        "model_type" => "petri_net"
      }

      # Queue 21 queries (exceeds max 20)
      tasks =
        Enum.map(1..21, fn i ->
          Task.async(fn ->
            Canopy.JTBD.Scenarios.Scenario11.execute(
              Map.put(query_template, "query_id", "query-#{i}"),
              timeout_ms: 10_000
            )
          end)
        end)

      results = Task.await_many(tasks, 15_000)

      successful = Enum.filter(results, fn r -> match?({:ok, _}, r) end)
      backpressure = Enum.filter(results, fn r -> match?({:error, :concurrency_limit}, r) end)

      assert length(successful) <= 20
      assert length(backpressure) >= 1
    end

    test "process_intelligence_query latency less than 10s for happy path" do
      query_params = %{
        "query" => "What is the bottleneck?",
        "model_type" => "petri_net"
      }

      start_ms = System.monotonic_time(:millisecond)
      {:ok, result} = Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 10_000)
      end_ms = System.monotonic_time(:millisecond)

      actual_latency = end_ms - start_ms

      assert actual_latency >= 0
      assert actual_latency < 10_000
      assert result.latency_ms > 0
    end

    test "process_intelligence_query captures query and model_type in result" do
      query_params = %{
        "query" => "What are the inefficient steps?",
        "model_type" => "dfg"
      }

      {:ok, result} = Canopy.JTBD.Scenarios.Scenario11.execute(query_params, timeout_ms: 10_000)

      assert result.query == "What are the inefficient steps?"
      assert result.model_type == "dfg"
    end
  end
end
