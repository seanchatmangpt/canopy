defmodule CanopyWeb.WorkspaceMemberControllerTest do
  use CanopyWeb.ConnCase

  alias Canopy.Repo
  alias Canopy.Schemas.{User, Workspace}
  alias Canopy.WorkspaceIsolation

  setup do
    user1 = insert_user(%{email: "owner@test.com"})
    user2 = insert_user(%{email: "admin@test.com"})
    user3 = insert_user(%{email: "member@test.com"})
    user4 = insert_user(%{email: "newuser@test.com"})

    ws = insert_workspace(%{owner_id: user1.id, name: "Test Workspace"})

    WorkspaceIsolation.add_workspace_user(ws.id, user2.id, "admin")
    WorkspaceIsolation.add_workspace_user(ws.id, user3.id, "user")

    {:ok, user1: user1, user2: user2, user3: user3, user4: user4, workspace: ws}
  end

  describe "GET /api/v1/workspaces/:id/members" do
    test "returns list of workspace members for authorized admin", %{user1: user1, workspace: ws} do
      conn = build_authenticated_conn(user1)
      |> get("/api/v1/workspaces/#{ws.id}/members")

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["members"]
      assert length(body["members"]) == 2
      assert Enum.any?(body["members"], fn m -> m["email"] == "admin@test.com" end)
      assert Enum.any?(body["members"], fn m -> m["email"] == "member@test.com" end)
    end

    test "rejects access for non-admin user", %{user3: user3, workspace: ws} do
      conn = build_authenticated_conn(user3)
      |> get("/api/v1/workspaces/#{ws.id}/members")

      assert conn.status == 403
      body = json_response(conn, 403)
      assert body["error"] == "forbidden"
    end

    test "rejects access for unauthorized user", %{user4: user4, workspace: ws} do
      conn = build_authenticated_conn(user4)
      |> get("/api/v1/workspaces/#{ws.id}/members")

      assert conn.status == 403
    end
  end

  describe "POST /api/v1/workspaces/:id/members" do
    test "adds new user to workspace as specified role", %{user1: user1, user4: user4, workspace: ws} do
      conn = build_authenticated_conn(user1)
      |> post("/api/v1/workspaces/#{ws.id}/members", %{
        email: user4.email,
        role: "admin"
      })

      assert conn.status == 201
      body = json_response(conn, 201)

      assert body["user"]["email"] == user4.email
      assert body["user"]["role"] == "admin"

      # Verify user can now access workspace
      assert WorkspaceIsolation.can_access_workspace?(user4.id, ws.id)
    end

    test "defaults to 'user' role when not specified", %{user1: user1, user4: user4, workspace: ws} do
      conn = build_authenticated_conn(user1)
      |> post("/api/v1/workspaces/#{ws.id}/members", %{email: user4.email})

      assert conn.status == 201
      body = json_response(conn, 201)
      assert body["user"]["role"] == "user"
    end

    test "rejects adding member if user not admin", %{user3: user3, user4: user4, workspace: ws} do
      conn = build_authenticated_conn(user3)
      |> post("/api/v1/workspaces/#{ws.id}/members", %{
        email: user4.email,
        role: "user"
      })

      assert conn.status == 403
    end

    test "returns 404 if email not found", %{user1: user1, workspace: ws} do
      conn = build_authenticated_conn(user1)
      |> post("/api/v1/workspaces/#{ws.id}/members", %{
        email: "nonexistent@test.com",
        role: "user"
      })

      assert conn.status == 404
      body = json_response(conn, 404)
      assert body["error"] == "not_found"
    end
  end

  describe "DELETE /api/v1/workspaces/:id/members/:user_id" do
    test "removes user from workspace when authorized", %{user1: user1, user3: user3, workspace: ws} do
      assert WorkspaceIsolation.can_access_workspace?(user3.id, ws.id)

      conn = build_authenticated_conn(user1)
      |> delete("/api/v1/workspaces/#{ws.id}/members/#{user3.id}")

      assert conn.status == 200

      refute WorkspaceIsolation.can_access_workspace?(user3.id, ws.id)
    end

    test "rejects removal when user not admin", %{user2: user2, user3: user3, workspace: ws} do
      conn = build_authenticated_conn(user2)
      |> delete("/api/v1/workspaces/#{ws.id}/members/#{user3.id}")

      # user2 is admin, should be allowed
      assert conn.status == 200
    end

    test "rejects removal when user is member only", %{user3: user3, user2: user2, workspace: ws} do
      conn = build_authenticated_conn(user3)
      |> delete("/api/v1/workspaces/#{ws.id}/members/#{user2.id}")

      assert conn.status == 403
    end
  end

  # Helpers

  defp insert_user(attrs \\ %{}) do
    user_attrs = Map.merge(%{
      name: "Test User #{System.unique_integer([:positive])}",
      email: "test#{System.unique_integer([:positive])}@test.com",
      password: "password123",
      role: "member",
      provider: "local"
    }, attrs)

    {:ok, user} = Repo.insert(Ecto.Changeset.cast(%User{}, user_attrs, [:name, :email, :password, :role, :provider]))
    user
  end

  defp insert_workspace(attrs \\ %{}) do
    ws_attrs = Map.merge(%{
      name: "Test Workspace #{System.unique_integer([:positive])}",
      path: "/tmp/workspace#{System.unique_integer([:positive])}",
      status: "active",
      is_active: true,
      isolation_level: "full"
    }, attrs)

    {:ok, ws} = Repo.insert(Workspace.changeset(%Workspace{}, ws_attrs))
    ws
  end

  defp build_authenticated_conn(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:assigns, %{current_user: user})
  end
end
