defmodule Canopy.WorkspaceIsolationTest do
  use Canopy.DataCase

  alias Canopy.Repo
  alias Canopy.WorkspaceIsolation
  alias Canopy.Schemas.{User, Workspace, WorkspaceUser}

  describe "get_user_workspaces/1" do
    test "returns only workspaces owned by user" do
      user1 = insert_user()
      user2 = insert_user()

      ws1 = insert_workspace(%{owner_id: user1.id})
      ws2 = insert_workspace(%{owner_id: user1.id})
      ws3 = insert_workspace(%{owner_id: user2.id})

      workspaces = WorkspaceIsolation.get_user_workspaces(user1.id)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert ws1.id in workspace_ids
      assert ws2.id in workspace_ids
      refute ws3.id in workspace_ids
    end

    test "includes workspaces where user is a member" do
      user1 = insert_user()
      user2 = insert_user()

      ws1 = insert_workspace(%{owner_id: user2.id})
      WorkspaceIsolation.add_workspace_user(ws1.id, user1.id, "user")

      workspaces = WorkspaceIsolation.get_user_workspaces(user1.id)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert ws1.id in workspace_ids
    end

    test "excludes inactive workspaces" do
      user = insert_user()
      ws_active = insert_workspace(%{owner_id: user.id, is_active: true})
      ws_inactive = insert_workspace(%{owner_id: user.id, is_active: false})

      workspaces = WorkspaceIsolation.get_user_workspaces(user.id)
      workspace_ids = Enum.map(workspaces, & &1.id)

      assert ws_active.id in workspace_ids
      refute ws_inactive.id in workspace_ids
    end
  end

  describe "get_user_workspace/2" do
    test "returns workspace if user owns it" do
      user = insert_user()
      ws = insert_workspace(%{owner_id: user.id})

      result = WorkspaceIsolation.get_user_workspace(user.id, ws.id)

      assert result != nil
      assert result.id == ws.id
    end

    test "returns workspace if user is a member" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user1.id, "user")

      result = WorkspaceIsolation.get_user_workspace(user1.id, ws.id)

      assert result != nil
      assert result.id == ws.id
    end

    test "returns nil if user has no access" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      result = WorkspaceIsolation.get_user_workspace(user1.id, ws.id)

      assert result == nil
    end
  end

  describe "user_workspace_role/2" do
    test "returns 'owner' if user owns workspace" do
      user = insert_user()
      ws = insert_workspace(%{owner_id: user.id})

      role = WorkspaceIsolation.user_workspace_role(user.id, ws.id)

      assert role == "owner"
    end

    test "returns role if user is a member" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user1.id, "admin")

      role = WorkspaceIsolation.user_workspace_role(user1.id, ws.id)

      assert role == "admin"
    end

    test "returns nil if user has no access" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      role = WorkspaceIsolation.user_workspace_role(user1.id, ws.id)

      assert role == nil
    end
  end

  describe "can_access_workspace?/2" do
    test "returns true if user has access" do
      user = insert_user()
      ws = insert_workspace(%{owner_id: user.id})

      assert WorkspaceIsolation.can_access_workspace?(user.id, ws.id)
    end

    test "returns false if user has no access" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      refute WorkspaceIsolation.can_access_workspace?(user1.id, ws.id)
    end
  end

  describe "can_manage_workspace?/2" do
    test "returns true if user owns workspace" do
      user = insert_user()
      ws = insert_workspace(%{owner_id: user.id})

      assert WorkspaceIsolation.can_manage_workspace?(user.id, ws.id)
    end

    test "returns true if user is admin" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user1.id, "admin")

      assert WorkspaceIsolation.can_manage_workspace?(user1.id, ws.id)
    end

    test "returns false if user is viewer" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user2.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user1.id, "viewer")

      refute WorkspaceIsolation.can_manage_workspace?(user1.id, ws.id)
    end
  end

  describe "add_workspace_user/3" do
    test "adds user to workspace with specified role" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user1.id})

      {:ok, _} = WorkspaceIsolation.add_workspace_user(ws.id, user2.id, "admin")

      role = WorkspaceIsolation.user_workspace_role(user2.id, ws.id)
      assert role == "admin"
    end

    test "defaults to 'user' role when not specified" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user1.id})

      {:ok, _} = WorkspaceIsolation.add_workspace_user(ws.id, user2.id)

      role = WorkspaceIsolation.user_workspace_role(user2.id, ws.id)
      assert role == "user"
    end
  end

  describe "update_workspace_user_role/3" do
    test "updates user role in workspace" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user1.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user2.id, "user")
      {:ok, _} = WorkspaceIsolation.update_workspace_user_role(ws.id, user2.id, "admin")

      role = WorkspaceIsolation.user_workspace_role(user2.id, ws.id)
      assert role == "admin"
    end

    test "returns error if workspace_user not found" do
      user = insert_user()

      result = WorkspaceIsolation.update_workspace_user_role("fake-id", user.id, "admin")

      assert {:error, :not_found} = result
    end
  end

  describe "remove_workspace_user/2" do
    test "removes user from workspace" do
      user1 = insert_user()
      user2 = insert_user()
      ws = insert_workspace(%{owner_id: user1.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user2.id, "user")
      assert WorkspaceIsolation.can_access_workspace?(user2.id, ws.id)

      WorkspaceIsolation.remove_workspace_user(ws.id, user2.id)

      refute WorkspaceIsolation.can_access_workspace?(user2.id, ws.id)
    end
  end

  describe "list_workspace_users/1" do
    test "returns all users in workspace with preloaded user data" do
      user1 = insert_user()
      user2 = insert_user()
      user3 = insert_user()
      ws = insert_workspace(%{owner_id: user1.id})

      WorkspaceIsolation.add_workspace_user(ws.id, user2.id, "admin")
      WorkspaceIsolation.add_workspace_user(ws.id, user3.id, "viewer")

      members = WorkspaceIsolation.list_workspace_users(ws.id)

      assert length(members) == 2
      assert Enum.any?(members, fn m -> m.user_id == user2.id and m.role == "admin" end)
      assert Enum.any?(members, fn m -> m.user_id == user3.id and m.role == "viewer" end)
    end
  end

  describe "deactivate_workspace/1 and activate_workspace/1" do
    test "deactivates and reactivates workspace" do
      user = insert_user()
      ws = insert_workspace(%{owner_id: user.id, is_active: true})

      WorkspaceIsolation.deactivate_workspace(ws.id)

      reloaded = Repo.get(Workspace, ws.id)
      refute reloaded.is_active

      WorkspaceIsolation.activate_workspace(ws.id)

      reloaded = Repo.get(Workspace, ws.id)
      assert reloaded.is_active
    end
  end

  # Helpers

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "Test User #{System.unique_integer([:positive])}",
          email: "user#{System.unique_integer([:positive])}@example.com",
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
end
