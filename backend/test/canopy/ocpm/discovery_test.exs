defmodule Canopy.OCPM.DiscoveryTest do
  use Canopy.DataCase
  alias Canopy.OCPM.{Discovery, EventLog, ProcessModel}

  @moduletag :ocpm_discovery

  describe "discover_process_model/1" do
    test "discovers process model from valid event log" do
      # Create sample event log
      events = create_sample_event_log("test-case-1")

      # Run discovery
      {:ok, process_model} = Discovery.discover_process_model(events)

      # Verify process model structure
      assert %ProcessModel{} = process_model
      assert is_list(process_model.nodes)
      assert is_map(process_model.edges)
      assert process_model.version == "1.0.0"
      assert process_model.discovered_at != nil
    end

    test "extracts unique activities from event log" do
      events = create_sample_event_log("test-case-2")

      {:ok, process_model} = Discovery.discover_process_model(events)

      # Should extract 5 unique activities
      assert length(process_model.nodes) == 5
      assert "receive_invoice" in process_model.nodes
      assert "validate_invoice" in process_model.nodes
      assert "approve_invoice" in process_model.nodes
      assert "send_payment" in process_model.nodes
    end

    test "builds correct succession relations" do
      events = create_sample_event_log("test-case-3")

      {:ok, process_model} = Discovery.discover_process_model(events)

      # Should have edges representing succession
      assert map_size(process_model.edges) > 0

      # Verify specific edge exists
      assert Map.has_key?(process_model.edges, "receive_invoice -> validate_invoice")
    end

    test "handles empty event log gracefully" do
      events = []

      assert {:ok, process_model} = Discovery.discover_process_model(events)
      assert process_model.nodes == []
      assert process_model.edges == %{}
    end

    test "handles single activity event log" do
      events = [
        %EventLog{
          case_id: "single-case",
          activity: "only_activity",
          timestamp: DateTime.utc_now(),
          resource: "agent-1",
          attributes: %{},
          workspace_id: "workspace-1",
          agent_id: "agent-1"
        }
      ]

      {:ok, process_model} = Discovery.discover_process_model(events)

      assert length(process_model.nodes) == 1
      assert "only_activity" in process_model.nodes
      assert map_size(process_model.edges) == 0
    end
  end

  describe "detect_bottlenecks/2" do
    setup do
      events = create_sample_event_log_with_bottlenecks("bottleneck-case")
      {:ok, process_model} = Discovery.discover_process_model(events)

      %{events: events, process_model: process_model}
    end

    test "detects frequency bottlenecks", %{events: events, process_model: process_model} do
      bottlenecks = Discovery.detect_bottlenecks(process_model, events)

      # Should find frequency bottlenecks
      frequency_bottlenecks = Enum.filter(bottlenecks, fn b -> b.type == :frequency end)
      assert length(frequency_bottlenecks) > 0
    end

    test "detects duration bottlenecks", %{events: events, process_model: process_model} do
      bottlenecks = Discovery.detect_bottlenecks(process_model, events)

      # Should find duration bottlenecks
      duration_bottlenecks = Enum.filter(bottlenecks, fn b -> b.type == :duration end)
      assert length(duration_bottlenecks) > 0
    end

    test "calculates bottleneck severity correctly" do
      events = create_sample_event_log_with_bottlenecks("severity-case")
      {:ok, process_model} = Discovery.discover_process_model(events)

      bottlenecks = Discovery.detect_bottlenecks(process_model, events)

      # At least one critical bottleneck should exist
      critical_bottlenecks = Enum.filter(bottlenecks, fn b -> b.severity == :critical end)
      assert length(critical_bottlenecks) > 0
    end

    test "returns bottleneck list with required fields", %{events: events, process_model: process_model} do
      bottlenecks = Discovery.detect_bottlenecks(process_model, events)

      Enum.each(bottlenecks, fn bottleneck ->
        assert Map.has_key?(bottleneck, :activity)
        assert Map.has_key?(bottleneck, :type)
        assert Map.has_key?(bottleneck, :severity)
        assert Map.has_key?(bottleneck, :impact)
      end)
    end
  end

  describe "find_deviations/2" do
    setup do
      # Create a baseline process model
      events = create_sample_event_log("deviation-case")
      {:ok, process_model} = Discovery.discover_process_model(events)

      # Create events with deviations
      events_with_deviations = events ++ create_deviations("deviation-case")

      %{process_model: process_model, events: events_with_deviations}
    end

    test "detects missing activities", %{process_model: process_model, events: events} do
      deviations = Discovery.find_deviations(process_model, events)

      missing_deviations = Enum.filter(deviations, fn d -> d.deviation_type == :missing end)
      assert length(missing_deviations) > 0
    end

    test "detects extra activities", %{process_model: process_model, events: events} do
      deviations = Discovery.find_deviations(process_model, events)

      extra_deviations = Enum.filter(deviations, fn d -> d.deviation_type == :extra end)
      assert length(extra_deviations) > 0
    end

    test "detects order violations", %{process_model: process_model, events: events} do
      deviations = Discovery.find_deviations(process_model, events)

      order_deviations = Enum.filter(deviations, fn d -> d.deviation_type == :order_violation end)
      assert length(order_deviations) > 0
    end

    test "categorizes deviations by severity", %{process_model: process_model, events: events} do
      deviations = Discovery.find_deviations(process_model, events)

      # Should have different severity levels
      severities = Enum.map(deviations, fn d -> d.severity end) |> Enum.uniq()
      assert :critical in severities or :warning in severities or :info in severities
    end

    test "returns deviations with case context", %{process_model: process_model, events: events} do
      deviations = Discovery.find_deviations(process_model, events)

      Enum.each(deviations, fn deviation ->
        assert Map.has_key?(deviation, :case_id)
        assert Map.has_key?(deviation, :deviation_type)
        assert Map.has_key?(deviation, :severity)
        assert Map.has_key?(deviation, :description)
      end)
    end
  end

  describe "confidence calculation" do
    test "calculates confidence intervals for succession relations" do
      events = create_sample_event_log("confidence-case")

      {:ok, process_model} = Discovery.discover_process_model(events)

      # Each edge should have frequency and confidence
      Enum.each(process_model.edges, fn {_key, edge_data} ->
        assert Map.has_key?(edge_data, :frequency)
        assert Map.has_key?(edge_data, :confidence)
        assert edge_data.confidence >= 0.0
        assert edge_data.confidence <= 1.0
      end)
    end

    test "filters relations below confidence threshold" do
      events = create_sample_event_log("threshold-case")

      {:ok, process_model} = Discovery.discover_process_model(events, confidence_threshold: 0.95)

      # All edges should meet confidence threshold
      Enum.each(process_model.edges, fn {_key, edge_data} ->
        assert edge_data.confidence >= 0.95
      end)
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

    # Add multiple occurrences of slow activity to create bottleneck
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
end
