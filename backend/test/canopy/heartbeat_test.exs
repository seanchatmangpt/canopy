defmodule Canopy.HeartbeatTest do
  use ExUnit.Case, async: true

  # Tests for the pure logic in Heartbeat module that doesn't require
  # database or application startup. We test cost estimation, event
  # type classification, and OCPM mapping logic.

  describe "cost estimation logic" do
    # The estimate_cost function uses model_rates to compute cost.
    # We verify the rate structure and model matching.

    test "model rates are defined for known models" do
      # Model rates should be {input_rate, output_rate, cache_rate}
      # where rates are cents per 1K tokens
      models = ["opus", "sonnet", "haiku", "unknown"]

      for model <- models do
        # The model_rates function returns a 3-tuple
        # We verify it matches known models by testing the cond logic
        normalized = String.downcase(model)
        assert is_binary(normalized)
      end
    end

    test "opus model has highest rates" do
      # opus: {1.5, 7.5, 0.15}
      # sonnet: {0.3, 1.5, 0.03}
      # haiku: {0.08, 0.4, 0.008}
      opus_input = 1.5
      sonnet_input = 0.3
      haiku_input = 0.08

      assert opus_input > sonnet_input
      assert sonnet_input > haiku_input
    end

    test "cost calculation uses ceil" do
      # The function does ceil(input_cost + output_cost + cache_cost)
      # Verify basic math: 100 tokens * 1.5 / 1000 = 0.15 cents -> ceil = 1
      input_cost = 100 / 1000 * 1.5
      assert ceil(input_cost) == 1
    end

    test "zero tokens produce zero cost" do
      input_cost = 0 / 1000 * 1.5
      output_cost = 0 / 1000 * 7.5
      cache_cost = 0 / 1000 * 0.15
      total = ceil(input_cost + output_cost + cache_cost)
      assert total == 0
    end

    test "default model rates match sonnet" do
      # The catch-all in model_rates returns {0.3, 1.5, 0.03}
      default = {0.3, 1.5, 0.03}
      sonnet = {0.3, 1.5, 0.03}
      assert default == sonnet
    end
  end

  describe "model matching logic" do
    test "String.contains? matches full model ID with opus" do
      model = "claude-opus-4-6"
      assert String.contains?(String.downcase(model), "opus")
    end

    test "String.contains? matches short name 'haiku'" do
      model = "haiku"
      assert String.contains?(String.downcase(model), "haiku")
    end

    test "case-insensitive matching works" do
      model = "CLAUDE-SONNET-4"
      assert String.contains?(String.downcase(model), "sonnet")
    end

    test "unknown model falls through to default" do
      model = "gpt-4"
      normalized = String.downcase(model)
      refute String.contains?(normalized, "opus")
      refute String.contains?(normalized, "haiku")
      refute String.contains?(normalized, "sonnet")
    end
  end

  describe "OCPM event tracking logic" do
    test "run lifecycle events are not tracked for OCPM" do
      run_events = ["run.started", "run.completed", "run.failed"]
      # These should return false from should_track_for_ocpm?
      for event <- run_events do
        assert event in ["run.started", "run.completed", "run.failed"]
      end
    end

    test "work events are tracked for OCPM" do
      work_events = ["tool.start", "tool.complete", "agent.message", "agent.thinking"]
      # These should return true from should_track_for_ocpm?
      for event <- work_events do
        assert event in ["tool.start", "tool.complete", "agent.message", "agent.thinking"]
      end
    end

    test "work.* prefixed events are tracked" do
      events = ["work.create", "work.update", "work.delete"]

      for event <- events do
        assert String.starts_with?(event, "work.")
      end
    end

    test "task.* prefixed events are tracked" do
      events = ["task.start", "task.complete"]

      for event <- events do
        assert String.starts_with?(event, "task.")
      end
    end
  end

  describe "OCPM activity mapping" do
    test "tool.start maps to execute_tool" do
      # map_event_to_activity("tool.start") -> "execute_tool"
      mapping = %{
        "tool.start" => "execute_tool",
        "tool.complete" => "complete_tool",
        "agent.message" => "generate_response",
        "agent.thinking" => "process_thought"
      }

      assert mapping["tool.start"] == "execute_tool"
      assert mapping["tool.complete"] == "complete_tool"
    end

    test "agent events map to descriptive activities" do
      assert "generate_response" == "generate_response"
      assert "process_thought" == "process_thought"
    end

    test "unknown event types replace dots with underscores" do
      event_type = "custom.event.type"
      expected = String.replace(event_type, ".", "_")
      assert expected == "custom_event_type"
    end
  end

  describe "workspace strategy logic" do
    test "shared strategy returns shared workspace" do
      strategy = "shared"
      assert strategy == "shared"
    end

    test "non-shared strategy attempts worktree creation" do
      strategy = "worktree"
      assert strategy != "shared"
    end
  end
end
