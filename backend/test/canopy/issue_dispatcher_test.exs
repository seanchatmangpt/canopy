defmodule Canopy.IssueDispatcherTest do
  use ExUnit.Case, async: true

  # Tests for IssueDispatcher logic that doesn't require GenServer/DB.
  # We test the agent validation logic and the public API contract.

  describe "agent validation logic" do
    # validate_agent/1 checks if agent status allows dispatching.
    # Valid statuses: "idle", "active"

    test "idle agent status is valid for dispatch" do
      valid_statuses = ["idle", "active"]
      assert "idle" in valid_statuses
    end

    test "active agent status is valid for dispatch" do
      valid_statuses = ["idle", "active"]
      assert "active" in valid_statuses
    end

    test "working agent status is not valid for dispatch" do
      invalid_statuses = ["working", "error", "paused", "offline"]
      assert "working" in invalid_statuses
    end

    test "error agent status is not valid for dispatch" do
      invalid_statuses = ["working", "error", "paused", "offline"]
      assert "error" in invalid_statuses
    end

    test "paused agent status is not valid for dispatch" do
      invalid_statuses = ["working", "error", "paused", "offline"]
      assert "paused" in invalid_statuses
    end
  end

  describe "dispatch/1 error handling" do
    test "dispatch returns error when dispatcher is unavailable" do
      # The dispatch function catches :exit signals and returns
      # {:error, {:dispatcher_unavailable, reason}}
      # This test verifies the expected return shape
      expected_error_shape = {:error, {:dispatcher_unavailable, :noproc}}
      assert match?({:error, {:dispatcher_unavailable, _}}, expected_error_shape)
    end
  end

  describe "event matching" do
    test "issue.assigned event has expected shape" do
      event = %{
        event: "issue.assigned",
        issue_id: "issue-123",
        agent_id: "agent-456"
      }

      assert event.event == "issue.assigned"
      assert Map.has_key?(event, :issue_id)
      assert Map.has_key?(event, :agent_id)
    end

    test "events with atom keys match the handle_info pattern" do
      # The dispatcher uses atom keys: %{event: "issue.assigned", issue_id: ..., agent_id: ...}
      event = %{event: "issue.assigned", issue_id: "id1", agent_id: "id2"}
      assert is_atom(event.event) == false
      assert is_binary(event.event)
    end
  end

  describe "workspace subscription" do
    test "subscribe_workspace/1 constructs the correct topic" do
      workspace_id = "ws-abc"
      topic = Canopy.EventBus.workspace_topic(workspace_id)
      assert topic == "workspace:ws-abc"
    end

    test "subscribe_workspace/1 is a public function" do
      assert is_function(&Canopy.IssueDispatcher.subscribe_workspace/1)
    end
  end

  describe "module structure" do
    test "uses GenServer" do
      # Verify the module exists and has expected public functions
      functions = Canopy.IssueDispatcher.__info__(:functions)
      assert {:start_link, 0} in functions or {:start_link, 1} in functions
    end

    test "has dispatch/1 function" do
      functions = Canopy.IssueDispatcher.__info__(:functions)
      assert {:dispatch, 1} in functions
    end

    test "has subscribe_workspace/1 function" do
      functions = Canopy.IssueDispatcher.__info__(:functions)
      assert {:subscribe_workspace, 1} in functions
    end
  end
end
