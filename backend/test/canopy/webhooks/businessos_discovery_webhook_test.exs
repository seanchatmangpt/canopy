defmodule Canopy.Webhooks.BusinessosDiscoveryWebhookTest do
  use Canopy.DataCase
  import Ecto.Query

  alias Canopy.Webhooks.BusinessosDiscoveryWebhook
  alias Canopy.Schemas.{Workspace, Agent, Issue}
  alias Canopy.Repo

  setup do
    # Create test workspace
    workspace =
      Repo.insert!(%Workspace{
        name: "Test Workspace",
        path: "/tmp/test-ws"
      })

    # Create process-mining-monitor agent
    agent =
      Repo.insert!(%Agent{
        workspace_id: workspace.id,
        slug: "process-mining-monitor",
        name: "Process Mining Monitor",
        role: "process_miner",
        adapter: "osa",
        model: "gpt-4",
        status: "idle"
      })

    {:ok, workspace: workspace, agent: agent}
  end

  describe "handle_discovery_complete/2" do
    test "creates issue when discovery completes", %{workspace: workspace, agent: _agent} do
      payload = %{
        "model_id" => "model-abc-123",
        "algorithm" => "heuristics",
        "activities_count" => 42,
        "fitness_score" => 0.95
      }

      assert {:ok, result} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(workspace.id, payload)

      assert is_binary(result.issue_id)
      assert is_binary(result.agent_id)

      # Verify issue was created with correct data
      issue = Repo.get!(Issue, result.issue_id)
      assert issue.title == "Process Model: heuristics"
      assert issue.description == "model-abc-123"
      assert issue.status == "backlog"
      assert issue.priority == "high"
      assert issue.workspace_id == workspace.id
    end

    test "assigns issue to agent on successful creation", %{workspace: workspace, agent: agent} do
      payload = %{
        "model_id" => "model-def-456",
        "algorithm" => "inductive",
        "activities_count" => 25,
        "fitness_score" => 0.88
      }

      {:ok, result} = BusinessosDiscoveryWebhook.handle_discovery_complete(workspace.id, payload)

      # Verify issue is assigned to agent
      issue = Repo.get!(Issue, result.issue_id)
      assert issue.assignee_id == agent.id
      assert result.agent_id == agent.id
    end

    test "is idempotent: duplicate POSTs create only 1 issue", %{
      workspace: workspace,
      agent: _agent
    } do
      payload = %{
        "model_id" => "model-xyz-789",
        "algorithm" => "alphabetic",
        "activities_count" => 15,
        "fitness_score" => 0.92
      }

      # First call
      {:ok, result1} = BusinessosDiscoveryWebhook.handle_discovery_complete(workspace.id, payload)
      issue_id_1 = result1.issue_id

      # Duplicate call with same model_id
      {:ok, result2} = BusinessosDiscoveryWebhook.handle_discovery_complete(workspace.id, payload)
      issue_id_2 = result2.issue_id

      # Should return same issue
      assert issue_id_1 == issue_id_2

      # Verify only 1 issue exists in DB
      issue_count =
        Repo.aggregate(from(i in Issue, where: i.workspace_id == ^workspace.id), :count)

      assert issue_count == 1
    end

    test "returns error when workspace not found" do
      payload = %{
        "model_id" => "model-xxx",
        "algorithm" => "heuristics",
        "activities_count" => 10,
        "fitness_score" => 0.85
      }

      # Use a valid UUID that doesn't exist
      nonexistent_id = "00000000-0000-0000-0000-000000000000"

      assert {:error, :workspace_not_found} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(nonexistent_id, payload)
    end

    test "returns error when process-mining-monitor agent not found" do
      # Create a workspace without the process-mining-monitor agent
      other_ws = Repo.insert!(%Workspace{name: "Other WS", path: "/tmp/other"})

      payload = %{
        "model_id" => "model-qqq",
        "algorithm" => "heuristics",
        "activities_count" => 5,
        "fitness_score" => 0.75
      }

      assert {:error, :agent_not_found} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(other_ws.id, payload)
    end

    test "returns error with invalid payload (missing fields)" do
      workspace = Repo.insert!(%Workspace{name: "WS", path: "/tmp/ws"})

      # Missing algorithm
      payload_missing_algorithm = %{
        "model_id" => "model-aaa",
        "activities_count" => 10,
        "fitness_score" => 0.85
      }

      assert {:error, :invalid_payload} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(
                 workspace.id,
                 payload_missing_algorithm
               )

      # Missing model_id
      payload_missing_model = %{
        "algorithm" => "heuristics",
        "activities_count" => 10,
        "fitness_score" => 0.85
      }

      assert {:error, :invalid_payload} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(
                 workspace.id,
                 payload_missing_model
               )

      # Missing activities_count
      payload_missing_count = %{
        "model_id" => "model-bbb",
        "algorithm" => "heuristics",
        "fitness_score" => 0.85
      }

      assert {:error, :invalid_payload} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(
                 workspace.id,
                 payload_missing_count
               )

      # Missing fitness_score
      payload_missing_score = %{
        "model_id" => "model-ccc",
        "algorithm" => "heuristics",
        "activities_count" => 10
      }

      assert {:error, :invalid_payload} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(
                 workspace.id,
                 payload_missing_score
               )
    end

    test "returns error with invalid payload types" do
      workspace = Repo.insert!(%Workspace{name: "WS2", path: "/tmp/ws2"})

      Repo.insert!(%Agent{
        workspace_id: workspace.id,
        slug: "process-mining-monitor",
        name: "Agent",
        role: "miner",
        adapter: "osa",
        model: "gpt-4",
        status: "idle"
      })

      # activities_count is not an integer
      payload_bad_count = %{
        "model_id" => "model-ddd",
        "algorithm" => "heuristics",
        "activities_count" => "not-an-int",
        "fitness_score" => 0.85
      }

      assert {:error, :invalid_payload} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(
                 workspace.id,
                 payload_bad_count
               )

      # fitness_score is not a number
      payload_bad_score = %{
        "model_id" => "model-eee",
        "algorithm" => "heuristics",
        "activities_count" => 10,
        "fitness_score" => "not-a-number"
      }

      assert {:error, :invalid_payload} =
               BusinessosDiscoveryWebhook.handle_discovery_complete(
                 workspace.id,
                 payload_bad_score
               )
    end

    test "populates agent_id in response", %{workspace: workspace, agent: agent} do
      payload = %{
        "model_id" => "model-zzz",
        "algorithm" => "heuristics",
        "activities_count" => 30,
        "fitness_score" => 0.90
      }

      {:ok, result} = BusinessosDiscoveryWebhook.handle_discovery_complete(workspace.id, payload)

      assert result.agent_id == agent.id
    end
  end
end
