defmodule CanopyWeb.Plugs.WorkspaceContextTest do
  use CanopyWeb.ConnCase

  alias Canopy.Repo
  alias Canopy.Schemas.{User, Workspace}
  alias Canopy.WorkspaceIsolation
  alias CanopyWeb.Plugs.WorkspaceContext

  setup do
    # Create test users
    user1 = insert_user(%{email: "user1@test.com"})
    user2 = insert_user(%{email: "user2@test.com"})

    # Create test workspaces
    ws1 = insert_workspace(%{owner_id: user1.id, name: "Workspace 1"})
    ws2 = insert_workspace(%{owner_id: user1.id, name: "Workspace 2"})
    ws3 = insert_workspace(%{owner_id: user2.id, name: "Workspace 3"})

    # Add user2 to ws1 as member
    WorkspaceIsolation.add_workspace_user(ws1.id, user2.id, "user")

    {:ok, user1: user1, user2: user2, ws1: ws1, ws2: ws2, ws3: ws3}
  end

  describe "WorkspaceContext plug" do
    test "extracts workspace_id from params and validates access", %{user1: user1, ws1: ws1} do
      conn =
        build_authenticated_conn(user1)
        |> put_req_header("content-type", "application/json")
        |> Map.put(:params, %{"workspace_id" => ws1.id})

      conn = WorkspaceContext.call(conn, [])

      assert conn.assigns[:current_workspace_id] == ws1.id
      assert conn.assigns[:current_workspace].id == ws1.id
      assert conn.assigns[:current_workspace_role] == "owner"
    end

    test "extracts workspace_id from X-Workspace-ID header", %{user1: user1, ws1: ws1} do
      conn =
        build_authenticated_conn(user1)
        |> put_req_header("x-workspace-id", ws1.id)

      conn = WorkspaceContext.call(conn, [])

      assert conn.assigns[:current_workspace_id] == ws1.id
    end

    test "rejects request if user lacks access to workspace", %{user1: user1, ws3: ws3} do
      conn =
        build_authenticated_conn(user1)
        |> put_req_header("content-type", "application/json")
        |> Map.put(:params, %{"workspace_id" => ws3.id})

      conn = WorkspaceContext.call(conn, [])

      assert conn.status == 403
      assert conn.halted
    end

    test "allows member access to workspace", %{user2: user2, ws1: ws1} do
      conn =
        build_authenticated_conn(user2)
        |> put_req_header("content-type", "application/json")
        |> Map.put(:params, %{"workspace_id" => ws1.id})

      conn = WorkspaceContext.call(conn, [])

      assert conn.assigns[:current_workspace_id] == ws1.id
      assert conn.assigns[:current_workspace_role] == "user"
    end

    test "sets default workspace when none specified", %{user1: user1} do
      conn = build_authenticated_conn(user1)

      conn = WorkspaceContext.call(conn, [])

      assert conn.assigns[:current_workspace] != nil
      assert conn.assigns[:current_workspace_id] != nil
    end

    test "passes through when no user authenticated" do
      conn = build_conn()

      conn = WorkspaceContext.call(conn, [])

      assert conn.assigns[:current_workspace] == nil
      assert conn.assigns[:current_workspace_id] == nil
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

  defp build_authenticated_conn(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:assigns, %{current_user: user})
  end
end
