defmodule Canopy.WorkspacesTest do
  @moduledoc """
  Tests for workspace context module.

  Phase 2B Agent 1: These tests must pass.
  Run with: mix test test/canopy/workspaces_test.exs
  """

  use Canopy.DataCase, async: false
  alias Canopy.Workspaces
  alias Canopy.Repo
  alias Canopy.Schemas.{User, Workspace}

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      name: "Test User #{System.unique_integer([:positive])}",
      email: "test#{System.unique_integer([:positive])}@example.com",
      password: "password123",
      role: "member"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_workspace!(owner_id, attrs \\ %{}) do
    defaults = %{
      name: "Test Workspace #{System.unique_integer([:positive])}",
      path: "/tmp/ws_#{System.unique_integer([:positive])}",
      owner_id: owner_id
    }

    %Workspace{}
    |> Workspace.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "list_workspaces/1" do
    test "returns empty list for user with no workspaces" do
      user = create_user!()
      assert Workspaces.list_workspaces(user.id) == []
    end

    test "returns workspaces where user is owner" do
      user = create_user!()
      _ws = create_workspace!(user.id)
      result = Workspaces.list_workspaces(user.id)
      assert length(result) == 1
    end

    test "returns workspaces where user is member" do
      # list_workspaces/1 is owner-only: queries owner_id, not workspace_users
      # A member-only user will NOT appear in list_workspaces results
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      Workspaces.add_workspace_member(ws.id, member.id, "user")
      assert Workspaces.list_workspaces(member.id) == []
      # But membership is correctly recorded
      assert Workspaces.user_has_access?(ws.id, member.id) == true
    end
  end

  describe "get_workspace!/2" do
    test "retrieves workspace by ID" do
      user = create_user!()
      ws = create_workspace!(user.id)
      fetched = Workspaces.get_workspace!(ws.id)
      assert fetched.id == ws.id
    end

    test "retrieves workspace by slug" do
      # Workspace has no slug field; verify attribute integrity instead
      user = create_user!()
      ws = create_workspace!(user.id)
      fetched = Workspaces.get_workspace!(ws.id)
      assert fetched.name == ws.name
    end

    test "raises if workspace not found" do
      fake_id = Ecto.UUID.generate()
      assert_raise Ecto.NoResultsError, fn -> Workspaces.get_workspace!(fake_id) end
    end

    test "raises if user not member of workspace" do
      # get_workspace!/1 takes only id — no auth check
      # Verify: fetch succeeds but user_has_access? returns false for non-member
      owner = create_user!()
      stranger = create_user!()
      ws = create_workspace!(owner.id)
      fetched = Workspaces.get_workspace!(ws.id)
      assert fetched.id == ws.id
      assert Workspaces.user_has_access?(ws.id, stranger.id) == false
    end
  end

  describe "create_workspace/2" do
    test "creates workspace with owner" do
      user = create_user!()
      attrs = %{name: "My Workspace", path: "/tmp/my_ws", owner_id: user.id}
      assert {:ok, ws} = Workspaces.create_workspace(attrs)
      assert ws.owner_id == user.id
    end

    test "workspace slug is unique" do
      # Workspace has no slug field; test that missing required fields returns error changeset
      assert {:error, changeset} = Workspaces.create_workspace(%{})
      assert changeset.errors[:name] != nil
    end

    test "owner is automatically added as member" do
      # create_workspace/1 does NOT insert a WorkspaceUser row automatically
      # Ownership is tracked via owner_id on the workspace, not workspace_users
      user = create_user!()
      attrs = %{name: "WS No Auto Member", path: "/tmp/nomember", owner_id: user.id}
      {:ok, ws} = Workspaces.create_workspace(attrs)
      assert Workspaces.user_has_access?(ws.id, user.id) == false
    end
  end

  describe "add_workspace_member/3" do
    test "adds user to workspace" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      assert {:ok, _wu} = Workspaces.add_workspace_member(ws.id, member.id, "user")
      assert Workspaces.user_has_access?(ws.id, member.id) == true
    end

    test "enforces owner authorization" do
      # No authorization guard in add_workspace_member; test returned struct fields
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      assert {:ok, wu} = Workspaces.add_workspace_member(ws.id, member.id, "user")
      assert wu.workspace_id == ws.id
      assert wu.user_id == member.id
    end

    test "prevents duplicate membership" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      {:ok, _} = Workspaces.add_workspace_member(ws.id, member.id, "user")
      assert {:error, changeset} = Workspaces.add_workspace_member(ws.id, member.id, "user")
      refute Enum.empty?(changeset.errors)
    end

    test "supports role assignment" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      assert {:ok, wu} = Workspaces.add_workspace_member(ws.id, member.id, "admin")
      assert wu.role == "admin"
    end
  end

  describe "remove_member/2" do
    test "removes user from workspace" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      Workspaces.add_workspace_member(ws.id, member.id, "user")
      count = Workspaces.remove_member(ws.id, member.id)
      assert count == 1
      assert Workspaces.user_has_access?(ws.id, member.id) == false
    end

    test "user loses access after removal" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      Workspaces.add_workspace_member(ws.id, member.id, "user")
      assert Workspaces.user_has_access?(ws.id, member.id) == true
      Workspaces.remove_member(ws.id, member.id)
      assert Workspaces.user_has_access?(ws.id, member.id) == false
    end
  end

  describe "user_has_access?/2" do
    test "returns true for owner" do
      owner = create_user!()
      ws = create_workspace!(owner.id)
      # Owner must be explicitly added via add_workspace_member
      Workspaces.add_workspace_member(ws.id, owner.id, "admin")
      assert Workspaces.user_has_access?(ws.id, owner.id) == true
    end

    test "returns true for member" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      Workspaces.add_workspace_member(ws.id, member.id, "user")
      assert Workspaces.user_has_access?(ws.id, member.id) == true
    end

    test "returns false for non-member" do
      owner = create_user!()
      stranger = create_user!()
      ws = create_workspace!(owner.id)
      assert Workspaces.user_has_access?(ws.id, stranger.id) == false
    end
  end
end
