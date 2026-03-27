defmodule CanopyWeb.WorkspaceMemberController do
  use CanopyWeb, :controller

  alias Canopy.Repo
  alias Canopy.Schemas.User
  alias Canopy.WorkspaceIsolation
  import Ecto.Query

  def index(conn, %{"workspace_id" => workspace_id}) do
    current_user = conn.assigns[:current_user]
    _workspace = conn.assigns[:current_workspace]

    # Check permission: only workspace admins can list members
    case WorkspaceIsolation.user_workspace_role(current_user.id, workspace_id) do
      role when role in ["owner", "admin"] ->
        members = WorkspaceIsolation.list_workspace_users(workspace_id)

        serialized =
          Enum.map(members, fn wu ->
            %{
              id: wu.user.id,
              email: wu.user.email,
              name: wu.user.name,
              role: wu.role,
              joined_at: wu.inserted_at
            }
          end)

        json(conn, %{members: serialized})

      _ ->
        conn
        |> put_status(403)
        |> json(%{error: "forbidden", message: "You do not have permission to view members"})
    end
  end

  def add_member(conn, %{"workspace_id" => workspace_id} = params) do
    current_user = conn.assigns[:current_user]
    user_email = params["email"]
    role = params["role"] || "user"

    with {:ok, _} <- check_workspace_admin(current_user.id, workspace_id),
         {:ok, user} <- find_user_by_email(user_email),
         {:ok, _} <- WorkspaceIsolation.add_workspace_user(workspace_id, user.id, role) do
      conn
      |> put_status(201)
      |> json(%{
        message: "User added to workspace",
        user: %{id: user.id, email: user.email, name: user.name, role: role}
      })
    else
      {:error, :forbidden} ->
        conn
        |> put_status(403)
        |> json(%{error: "forbidden", message: "You are not authorized to add members"})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "not_found", message: "User not found"})

      {:error, _} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", message: "Failed to add member to workspace"})
    end
  end

  def remove_member(conn, %{"workspace_id" => workspace_id, "user_id" => user_id}) do
    current_user = conn.assigns[:current_user]

    with {:ok, _} <- check_workspace_admin(current_user.id, workspace_id) do
      WorkspaceIsolation.remove_workspace_user(workspace_id, user_id)

      json(conn, %{message: "User removed from workspace"})
    else
      {:error, :forbidden} ->
        conn
        |> put_status(403)
        |> json(%{error: "forbidden", message: "You are not authorized to remove members"})
    end
  end

  def update_member_role(conn, %{"workspace_id" => workspace_id, "user_id" => user_id} = params) do
    current_user = conn.assigns[:current_user]
    new_role = params["role"]

    with {:ok, _} <- check_workspace_admin(current_user.id, workspace_id),
         {:ok, _workspace_user} <-
           WorkspaceIsolation.update_workspace_user_role(workspace_id, user_id, new_role) do
      json(conn, %{
        message: "Member role updated",
        user: %{id: user_id, role: new_role}
      })
    else
      {:error, :forbidden} ->
        conn
        |> put_status(403)
        |> json(%{error: "forbidden", message: "You are not authorized to update members"})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "not_found", message: "Member not found"})

      {:error, _} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", message: "Failed to update member role"})
    end
  end

  # Private helpers

  defp check_workspace_admin(user_id, workspace_id) do
    case WorkspaceIsolation.user_workspace_role(user_id, workspace_id) do
      role when role in ["owner", "admin"] -> {:ok, role}
      _ -> {:error, :forbidden}
    end
  end

  defp find_user_by_email(email) do
    case Repo.one(from u in User, where: u.email == ^email) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
