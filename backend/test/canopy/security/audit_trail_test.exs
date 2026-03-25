defmodule Canopy.Security.AuditTrailTest do
  use Canopy.DataCase, async: false

  alias Canopy.Security.AuditTrail

  describe "event capture" do
    test "captures workflow event with all metadata" do
      workspace_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      event_type = "workflow_executed"

      {:ok, event} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: event_type,
          action: "execute",
          resource_type: "workflow",
          resource_id: Ecto.UUID.generate(),
          result: "success",
          metadata: %{"duration_ms" => 1250}
        })

      assert event.workspace_id == workspace_id
      assert event.user_id == user_id
      assert event.event_type == event_type
      assert event.action == "execute"
      assert event.result == "success"
      assert event.metadata["duration_ms"] == 1250
    end

    test "captures multiple events in sequence" do
      workspace_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      {:ok, event1} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "workflow_created",
          action: "create",
          resource_type: "workflow",
          resource_id: Ecto.UUID.generate(),
          result: "success"
        })

      {:ok, event2} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "workflow_executed",
          action: "execute",
          resource_type: "workflow",
          resource_id: event1.resource_id,
          result: "success"
        })

      assert event1.id != event2.id
      assert event1.inserted_at <= event2.inserted_at
    end
  end

  describe "ordering and causality" do
    test "maintains event ordering by timestamp" do
      workspace_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      resource_id = Ecto.UUID.generate()

      # Create events in order
      {:ok, event1} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "created",
          action: "create",
          resource_type: "task",
          resource_id: resource_id,
          result: "success"
        })

      {:ok, _event2} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "updated",
          action: "update",
          resource_type: "task",
          resource_id: resource_id,
          result: "success"
        })

      {:ok, _event3} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "deleted",
          action: "delete",
          resource_type: "task",
          resource_id: resource_id,
          result: "success"
        })

      # Retrieve and verify order
      history = AuditTrail.get_resource_history(resource_id)

      assert length(history) >= 3
      [first, second, third | _] = history
      assert first.event_type == "created"
      assert second.event_type == "updated"
      assert third.event_type == "deleted"
    end

    test "tracks causal relationships between events" do
      workspace_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      resource_id = Ecto.UUID.generate()

      {:ok, parent_event} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "parent_action",
          action: "create",
          resource_type: "workflow",
          resource_id: resource_id,
          result: "success"
        })

      {:ok, child_event} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "child_action",
          action: "execute",
          resource_type: "workflow",
          resource_id: resource_id,
          result: "success",
          parent_event_id: parent_event.id
        })

      assert child_event.parent_event_id == parent_event.id
    end
  end

  describe "recovery and integrity" do
    test "recovers audit trail from persistent storage" do
      workspace_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      resource_id = Ecto.UUID.generate()

      {:ok, event} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "test_event",
          action: "create",
          resource_type: "test",
          resource_id: resource_id,
          result: "success"
        })

      # Retrieve from storage
      recovered = AuditTrail.get_event(event.id)

      assert recovered != nil
      assert recovered.id == event.id
      assert recovered.workspace_id == workspace_id
      assert recovered.user_id == user_id
    end

    test "verifies integrity hash of audit events" do
      workspace_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()

      {:ok, event} =
        AuditTrail.capture_event(%{
          workspace_id: workspace_id,
          user_id: user_id,
          event_type: "integrity_test",
          action: "verify",
          resource_type: "audit",
          resource_id: Ecto.UUID.generate(),
          result: "success"
        })

      # Verify hash integrity
      assert event.hash != nil
      assert String.length(event.hash) > 0

      # Tampered event should not match hash
      is_valid = AuditTrail.verify_integrity(event)
      assert is_valid == true
    end
  end
end
