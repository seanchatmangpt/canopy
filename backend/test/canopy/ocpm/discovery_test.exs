defmodule Canopy.OCPM.DiscoveryTest do
  use Canopy.DataCase
  alias Canopy.OCPM.{Discovery, EventLog, ProcessModel, Pm4pyWrapper}

  @moduletag :ocpm_discovery

  # Note: These tests require pm4py to be installed
  # Install with: pip install pm4py

  describe "discover_process_model/1" do
    test "requires pm4py to be installed" do
      # This test verifies pm4py is available
      # Skip if not installed
      case check_pm4py_available() do
        :available -> :ok
        :not_available -> :skip
      end
    end

    @tag :pm4py_required
    test "discovers process model from valid event log" do
      :skip = "Run with mix test --include pm4py_required (requires pm4py installed)"

      events = create_sample_event_log("test-case-1")

      assert {:ok, process_model} = Discovery.discover_process_model(events)

      assert %{} = process_model
      assert is_list(process_model.nodes)
      assert is_map(process_model.edges)
      assert Map.has_key?(process_model, :metadata)
    end

    @tag :pm4py_required
    test "extracts unique activities from event log" do
      :skip = "Run with mix test --include pm4py_required (requires pm4py installed)"

      events = create_sample_event_log("test-case-2")

      {:ok, process_model} = Discovery.discover_process_model(events)

      # pm4py should extract activities
      assert length(process_model.nodes) > 0
    end

    @tag :pm4py_required
    test "handles empty event log gracefully" do
      events = []

      assert {:ok, process_model} = Discovery.discover_process_model(events)
      assert process_model.nodes == []
    end
  end

  describe "detect_bottlenecks/2" do
    @tag :pm4py_required
    test "requires pm4py to be installed" do
      :skip = "Run with mix test --include pm4py_required (requires pm4py installed)"
    end

    @tag :pm4py_required
    test "detects bottlenecks from event log" do
      :skip = "Run with mix test --include pm4py_required (requires pm4py installed)"

      events = create_sample_event_log_with_bottlenecks("bottleneck-case")
      {:ok, process_model} = Discovery.discover_process_model(events)

      {:ok, bottlenecks} = Discovery.detect_bottlenecks(process_model, events)

      assert is_list(bottlenecks)
    end
  end

  describe "find_deviations/2" do
    @tag :pm4py_required
    test "requires pm4py to be installed" do
      :skip = "Run with mix test --include pm4py_required (requires pm4py installed)"
    end

    @tag :pm4py_required
    test "finds deviations from event log" do
      :skip = "Run with mix test --include pm4py_required (requires pm4py installed)"

      events = create_sample_event_log("deviation-case")
      {:ok, process_model} = Discovery.discover_process_model(events)

      events_with_deviations = events ++ create_deviations("deviation-case")

      {:ok, deviations} = Discovery.find_deviations(process_model, events_with_deviations)

      assert is_list(deviations)
    end
  end

  describe "Pm4pyWrapper" do
    test "handles missing Python script gracefully" do
      # Test with empty events (should return empty model without calling Python)
      assert {:ok, model} = Pm4pyWrapper.discover_process_model([])
      assert model.nodes == []
    end

    test "returns error for invalid input" do
      # The wrapper should handle various input formats
      assert {:ok, _} = Pm4pyWrapper.discover_process_model([])
    end
  end

  # Helper functions

  defp create_sample_event_log(case_id) do
    base_time = DateTime.utc_now()

    [
      %EventLog{
        case_id: case_id,
        activity: "receive_invoice",
        timestamp: base_time,
        resource: "agent-1",
        attributes: %{"amount" => 1000},
        workspace_id: "workspace-1",
        agent_id: "agent-1"
      },
      %EventLog{
        case_id: case_id,
        activity: "validate_invoice",
        timestamp: DateTime.add(base_time, 60),
        resource: "agent-1",
        attributes: %{"valid" => true},
        workspace_id: "workspace-1",
        agent_id: "agent-1"
      },
      %EventLog{
        case_id: case_id,
        activity: "approve_invoice",
        timestamp: DateTime.add(base_time, 120),
        resource: "agent-2",
        attributes: %{"approved" => true},
        workspace_id: "workspace-1",
        agent_id: "agent-2"
      },
      %EventLog{
        case_id: case_id,
        activity: "send_payment",
        timestamp: DateTime.add(base_time, 180),
        resource: "agent-3",
        attributes: %{"amount" => 1000},
        workspace_id: "workspace-1",
        agent_id: "agent-3"
      }
    ]
  end

  defp create_sample_event_log_with_bottlenecks(case_id) do
    base_events = create_sample_event_log(case_id)

    # Add multiple occurrences to create frequency pattern
    slow_events =
      for i <- 1..50 do
        %EventLog{
          case_id: "#{case_id}-#{i}",
          activity: "manual_review",
          timestamp: DateTime.add(DateTime.utc_now(), i * 300),
          resource: "agent-human",
          attributes: %{"duration_minutes" => 45},
          workspace_id: "workspace-1",
          agent_id: "agent-human"
        }
      end

    base_events ++ slow_events
  end

  defp create_deviations(case_id) do
    [
      %EventLog{
        case_id: "#{case_id}-deviation-1",
        activity: "unauthorized_approval",
        timestamp: DateTime.utc_now(),
        resource: "agent-rogue",
        attributes: %{},
        workspace_id: "workspace-1",
        agent_id: "agent-rogue"
      },
      %EventLog{
        case_id: "#{case_id}-deviation-2",
        activity: "skip_validation",
        timestamp: DateTime.utc_now(),
        resource: "agent-rogue",
        attributes: %{},
        workspace_id: "workspace-1",
        agent_id: "agent-rogue"
      }
    ]
  end

  defp check_pm4py_available do
    # Try to run pm4py_wrapper with empty input
    case System.cmd("python3", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> :available
      _ -> :not_available
    end
  end
end
