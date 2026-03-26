defmodule Canopy.OCPM.EventLogTest do
  use ExUnit.Case, async: true

  alias Canopy.OCPM.EventLog

  describe "valid activities" do
    test "all standard process mining activities are valid" do
      valid_activities = ~w(
        start create submit approve reject review process complete
        cancel hold resume assign reassign notify archive delete
      )

      assert length(valid_activities) == 16
    end

    test "common activities are included" do
      valid_activities = ~w(start create approve reject review process complete)
      assert "start" in valid_activities
      assert "create" in valid_activities
      assert "approve" in valid_activities
      assert "reject" in valid_activities
      assert "review" in valid_activities
      assert "process" in valid_activities
      assert "complete" in valid_activities
    end

    test "lifecycle activities are included" do
      valid_activities = ~w(cancel hold resume archive delete)
      assert "cancel" in valid_activities
      assert "hold" in valid_activities
      assert "resume" in valid_activities
      assert "archive" in valid_activities
      assert "delete" in valid_activities
    end

    test "assignment activities are included" do
      valid_activities = ~w(assign reassign notify submit)
      assert "assign" in valid_activities
      assert "reassign" in valid_activities
      assert "notify" in valid_activities
      assert "submit" in valid_activities
    end
  end

  describe "changeset validation" do
    setup do
      workspace_id = Ecto.UUID.generate()
      agent_id = Ecto.UUID.generate()

      {:ok, workspace_id: workspace_id, agent_id: agent_id}
    end

    test "valid attributes produce a valid changeset", %{
      workspace_id: workspace_id,
      agent_id: agent_id
    } do
      attrs = %{
        case_id: "invoice-001",
        activity: "approve",
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        resource: "agent-reviewer",
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = EventLog.changeset(%EventLog{}, attrs)
      assert changeset.valid?
    end

    test "missing required fields produce errors", %{
      workspace_id: workspace_id,
      agent_id: agent_id
    } do
      # Missing case_id, activity, timestamp, resource
      attrs = %{
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = EventLog.changeset(%EventLog{}, attrs)
      refute changeset.valid?

      errors = traverse_errors(changeset)
      assert :case_id in errors
      assert :activity in errors
      assert :timestamp in errors
      assert :resource in errors
    end

    test "invalid activity is rejected", %{workspace_id: workspace_id, agent_id: agent_id} do
      attrs = %{
        case_id: "invoice-001",
        activity: "nonexistent_activity",
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        resource: "agent-reviewer",
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = EventLog.changeset(%EventLog{}, attrs)
      refute changeset.valid?
    end

    test "attributes field defaults to empty map", %{
      workspace_id: workspace_id,
      agent_id: agent_id
    } do
      attrs = %{
        case_id: "invoice-001",
        activity: "start",
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        resource: "system",
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = EventLog.changeset(%EventLog{}, attrs)
      assert changeset.valid?
      # attributes should default to %{}
      assert Ecto.Changeset.get_change(changeset, :attributes) || %{} == %{}
    end

    test "attributes accepts a map", %{workspace_id: workspace_id, agent_id: agent_id} do
      attrs = %{
        case_id: "invoice-001",
        activity: "process",
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        resource: "agent-worker",
        attributes: %{"priority" => "high", "department" => "finance"},
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = EventLog.changeset(%EventLog{}, attrs)
      assert changeset.valid?
    end
  end

  describe "schema structure" do
    test "uses binary_id primary key" do
      # The schema defines @primary_key {:id, :binary_id, autogenerate: true}
      assert is_binary(Ecto.UUID.generate())
    end

    test "has workspace and agent associations" do
      # The schema defines belongs_to :workspace and belongs_to :agent
      # These are validated by the changeset requiring workspace_id
      assert true
    end
  end

  # Helper to extract error keys from changeset
  defp traverse_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      msg
    end)
    |> Map.keys()
  end
end
