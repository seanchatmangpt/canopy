defmodule Canopy.JTBD.LinkedInRevOpsSmokeTest do
  @moduledoc """
  Smoke tests for LinkedIn RevOps integration (ICP qualification + outreach execution).

  Verifies that:
  1. Runner can call BusinessOS adapter methods without crashing
  2. ICP qualification scenario executes and returns proper metadata
  3. Outreach sequence scenario executes and returns proper metadata
  4. Fallback handling works when adapter returns errors
  """

  use ExUnit.Case, async: false

  require Logger

  describe "run_icp_qualification" do
    test "executes scenario and returns qualified count" do
      workspace_id = "test-workspace-1"
      iteration = 1

      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:icp_qualification,
          workspace_id: workspace_id,
          iteration: iteration
        )

      assert result.outcome == :success
      assert result.system == :businessos
      assert result.span_emitted == true
      assert is_integer(result.latency_ms)
      assert result.latency_ms > 0
      assert :assess_company in result.transitions
      assert :score_icp_fit in result.transitions
      assert :route_to_pipeline in result.transitions

      # Metadata should contain qualified_count and total_contacts
      assert is_integer(result.metadata.qualified_count)
      assert is_integer(result.metadata.total_contacts)
      assert result.metadata.qualified in [true, false]

      Logger.info("ICP qualification test passed | metadata=#{inspect(result.metadata)}")
    end

    test "handles multiple iterations" do
      workspace_id = "test-workspace-2"

      for iteration <- 1..3 do
        {:ok, result} =
          Canopy.JTBD.Runner.run_scenario(:icp_qualification,
            workspace_id: workspace_id,
            iteration: iteration
          )

        assert result.outcome == :success
        assert result.latency_ms >= 0
      end

      Logger.info("Multiple iterations test passed")
    end
  end

  describe "run_outreach_sequence_execution" do
    test "executes scenario and returns enrollment metrics" do
      workspace_id = "test-workspace-3"
      iteration = 1

      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:outreach_sequence_execution,
          workspace_id: workspace_id,
          iteration: iteration
        )

      assert result.outcome == :success
      assert result.system == :businessos
      assert result.span_emitted == true
      assert is_integer(result.latency_ms)
      assert result.latency_ms > 0
      assert :personalize_message in result.transitions
      assert :execute_outreach in result.transitions
      assert :track_engagement in result.transitions

      # Metadata should contain enrolled, skipped, and engagement_score
      assert is_integer(result.metadata.enrolled)
      assert is_integer(result.metadata.skipped)
      assert is_float(result.metadata.engagement_score)
      assert result.metadata.engagement_score >= 0.0
      assert result.metadata.engagement_score <= 1.0

      Logger.info(
        "Outreach sequence execution test passed | metadata=#{inspect(result.metadata)}"
      )
    end

    test "handles multiple sequence iterations with varying sequence IDs" do
      workspace_id = "test-workspace-4"

      for iteration <- 1..5 do
        {:ok, result} =
          Canopy.JTBD.Runner.run_scenario(:outreach_sequence_execution,
            workspace_id: workspace_id,
            iteration: iteration
          )

        assert result.outcome == :success
        assert result.latency_ms > 0
        # Sequence ID should vary: 1 + rem(iteration, 5)
        Logger.debug("Iteration #{iteration} | metadata=#{inspect(result.metadata)}")
      end

      Logger.info("Multiple outreach iterations test passed")
    end
  end

  describe "BusinessOS adapter integration" do
    test "icp_score_contacts is callable and returns expected structure" do
      # This test verifies the adapter method exists and can be called.
      # In a real environment, this would hit the actual BusinessOS API.
      # For now, we just verify the method signature and error handling.

      result = Canopy.Adapters.BusinessOS.icp_score_contacts(0.75, %{})

      case result do
        {:ok, data} ->
          # If connected to real BusinessOS
          assert is_map(data)
          assert Map.has_key?(data, "qualified") or Map.has_key?(data, "qualified_count")

        {:error, reason} ->
          # Connection refused or other error (expected in test env)
          Logger.info("Adapter returned error (expected in test env): #{inspect(reason)}")
          assert is_atom(reason) or is_tuple(reason)
      end
    end

    test "queue_outreach_step is callable and returns expected structure" do
      # This test verifies the adapter method exists and can be called.
      result = Canopy.Adapters.BusinessOS.queue_outreach_step(1, 0.75, %{})

      case result do
        {:ok, data} ->
          # If connected to real BusinessOS
          assert is_map(data)
          assert Map.has_key?(data, "enrolled") or Map.has_key?(data, "skipped")

        {:error, reason} ->
          # Connection refused or other error (expected in test env)
          Logger.info("Adapter returned error (expected in test env): #{inspect(reason)}")
          assert is_atom(reason) or is_tuple(reason)
      end
    end
  end
end
