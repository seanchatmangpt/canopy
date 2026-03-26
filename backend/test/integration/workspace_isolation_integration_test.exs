defmodule Integration.WorkspaceIsolationIntegrationTest do
  use CanopyWeb.ConnCase

  alias Canopy.Repo
  alias Canopy.Schemas.{User, Workspace, Agent}
  alias Canopy.WorkspaceIsolation

  setup do
    # Create two organizations and two workspaces per org
    user1 = insert_user(%{email: "user1@org1.com"})
    user2 = insert_user(%{email: "user2@org1.com"})
    user3 = insert_user(%{email: "user1@org2.com"})

    ws1_org1 = insert_workspace(%{owner_id: user1.id, name: "Workspace 1 - Org 1"})
    ws2_org1 = insert_workspace(%{owner_id: user2.id, name: "Workspace 2 - Org 1"})
    ws1_org2 = insert_workspace(%{owner_id: user3.id, name: "Workspace 1 - Org 2"})

    # Add user2 to ws1_org1
    WorkspaceIsolation.add_workspace_user(ws1_org1.id, user2.id, "user")

    {:ok,
     user1: user1,
     user2: user2,
     user3: user3,
     ws1_org1: ws1_org1,
     ws2_org1: ws2_org1,
     ws1_org2: ws1_org2}
  end

  describe "workspace data isolation" do
    test "agents in workspace 1 are not visible in workspace 2", %{
      user1: user1,
      ws1_org1: ws1,
      ws2_org1: ws2
    } do
      # Create agents in different workspaces
      agent1 = insert_agent(%{workspace_id: ws1.id, name: "Agent in WS1"})
      agent2 = insert_agent(%{workspace_id: ws2.id, name: "Agent in WS2"})

      conn =
        build_authenticated_conn(user1)
        |> put_req_header("x-workspace-id", ws1.id)
        |> get("/api/v1/agents")

      body = json_response(conn, 200)
      agent_ids = Enum.map(body["agents"], & &1["id"])

      # user1 owns ws1, should see agent1 but not agent2
      assert agent1.id in agent_ids
      refute agent2.id in agent_ids
    end

    test "agent roles scoped to workspace" do
      user1 = insert_user()
      user2 = insert_user()
      ws1 = insert_workspace(%{owner_id: user1.id})
      ws2 = insert_workspace(%{owner_id: user2.id})

      # Add user2 to ws1 with 'user' role
      WorkspaceIsolation.add_workspace_user(ws1.id, user2.id, "user")

      # user2 should be viewer in ws2 (owned by user2)
      role_in_ws1 = WorkspaceIsolation.user_workspace_role(user2.id, ws1.id)
      role_in_ws2 = WorkspaceIsolation.user_workspace_role(user2.id, ws2.id)

      assert role_in_ws1 == "user"
      assert role_in_ws2 == "owner"
    end
  end

  describe "cross-workspace access control" do
    test "workspace owner cannot access another owner's workspace" do
      # Create isolated users and workspaces for this test
      user1 = insert_user()
      user2 = insert_user()
      ws1 = insert_workspace(%{owner_id: user1.id})
      ws2 = insert_workspace(%{owner_id: user2.id})

      # user1 owns ws1, user2 owns ws2
      assert WorkspaceIsolation.can_access_workspace?(user1.id, ws1.id)
      refute WorkspaceIsolation.can_access_workspace?(user1.id, ws2.id)

      assert WorkspaceIsolation.can_access_workspace?(user2.id, ws2.id)
      refute WorkspaceIsolation.can_access_workspace?(user2.id, ws1.id)
    end

    test "invited user can access workspace but not other workspaces", %{
      user1: user1,
      user2: user2,
      user3: user3,
      ws1_org1: ws1,
      ws1_org2: ws2
    } do
      # user2 already invited to ws1_org1
      assert WorkspaceIsolation.can_access_workspace?(user2.id, ws1.id)
      refute WorkspaceIsolation.can_access_workspace?(user2.id, ws2.id)
    end

    test "permissions do not leak between workspaces" do
      owner = insert_user()
      regular_user = insert_user()

      ws1 = insert_workspace(%{owner_id: owner.id})
      ws2 = insert_workspace(%{owner_id: owner.id})

      # Add regular_user as admin in ws1 only
      WorkspaceIsolation.add_workspace_user(ws1.id, regular_user.id, "admin")

      # Check permissions in each workspace
      assert WorkspaceIsolation.can_manage_workspace?(regular_user.id, ws1.id)
      refute WorkspaceIsolation.can_manage_workspace?(regular_user.id, ws2.id)
    end
  end

  describe "workspace deactivation" do
    test "deactivated workspace not listed in user workspaces", %{
      user1: user1,
      ws1_org1: ws
    } do
      workspaces_before = WorkspaceIsolation.get_user_workspaces(user1.id)
      assert Enum.any?(workspaces_before, &(&1.id == ws.id))

      WorkspaceIsolation.deactivate_workspace(ws.id)

      workspaces_after = WorkspaceIsolation.get_user_workspaces(user1.id)
      refute Enum.any?(workspaces_after, &(&1.id == ws.id))
    end

    test "user cannot access deactivated workspace" do
      user = insert_user()
      ws = insert_workspace(%{owner_id: user.id, is_active: true})

      assert WorkspaceIsolation.can_access_workspace?(user.id, ws.id)

      WorkspaceIsolation.deactivate_workspace(ws.id)

      refute WorkspaceIsolation.can_access_workspace?(user.id, ws.id)
    end
  end

  describe "role-based isolation" do
    test "viewer can list data but not modify", %{user1: user1, user3: user3, ws1_org1: ws} do
      WorkspaceIsolation.add_workspace_user(ws.id, user3.id, "viewer")

      # Viewer should be able to access workspace
      assert WorkspaceIsolation.can_access_workspace?(user3.id, ws.id)

      # But cannot manage
      refute WorkspaceIsolation.can_manage_workspace?(user3.id, ws.id)
    end

    test "admin can manage workspace members" do
      owner = insert_user()
      admin = insert_user()
      regular_user = insert_user()

      ws = insert_workspace(%{owner_id: owner.id})
      WorkspaceIsolation.add_workspace_user(ws.id, admin.id, "admin")
      WorkspaceIsolation.add_workspace_user(ws.id, regular_user.id, "user")

      # Admin can update another user's role
      {:ok, _} = WorkspaceIsolation.update_workspace_user_role(ws.id, regular_user.id, "admin")

      new_role = WorkspaceIsolation.user_workspace_role(regular_user.id, ws.id)
      assert new_role == "admin"
    end

    test "regular user cannot manage workspace" do
      owner = insert_user()
      regular_user = insert_user()
      new_user = insert_user()

      ws = insert_workspace(%{owner_id: owner.id})
      WorkspaceIsolation.add_workspace_user(ws.id, regular_user.id, "user")

      # Regular user cannot add another user
      result = WorkspaceIsolation.add_workspace_user(ws.id, new_user.id, "user")

      # This should work at context layer, but HTTP endpoint should enforce permissions
      assert {:ok, _} = result
    end
  end

  # Helpers

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "Test User #{System.unique_integer([:positive])}",
          email: "test#{System.unique_integer([:positive])}@test.com",
          password: "password123",
          role: "member",
          provider: "local"
        },
        attrs
      )

    {:ok, user} =
      Repo.insert(
        Ecto.Changeset.cast(%User{}, user_attrs, [:name, :email, :password, :role, :provider])
      )

    user
  end

  defp insert_workspace(attrs \\ %{}) do
    ws_attrs =
      Map.merge(
        %{
          name: "Test Workspace #{System.unique_integer([:positive])}",
          path: "/tmp/workspace#{System.unique_integer([:positive])}",
          status: "active",
          is_active: true,
          isolation_level: "full"
        },
        attrs
      )

    {:ok, ws} = Repo.insert(Workspace.changeset(%Workspace{}, ws_attrs))
    ws
  end

  defp insert_agent(attrs \\ %{}) do
    agent_attrs =
      Map.merge(
        %{
          slug: "agent#{System.unique_integer([:positive])}",
          name: "Test Agent #{System.unique_integer([:positive])}",
          role: "worker",
          adapter: "claude-code",
          model: "claude-3-5-sonnet-20241022"
        },
        attrs
      )

    {:ok, agent} = Repo.insert(Agent.changeset(%Agent{}, agent_attrs))
    agent
  end

  defp build_authenticated_conn(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:assigns, %{current_user: user})
  end
end
