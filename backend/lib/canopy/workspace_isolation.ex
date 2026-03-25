defmodule Canopy.WorkspaceIsolation do
  @moduledoc "Multi-workspace isolation and RBAC context."

  alias Canopy.Repo
  alias Canopy.Schemas.{Workspace, WorkspaceUser}
  import Ecto.Query

  # Query helpers for workspace-scoped data access

  def get_user_workspaces(user_id) do
    Repo.all(
      from w in Workspace,
        left_join: wu in WorkspaceUser, on: wu.workspace_id == w.id and wu.user_id == ^user_id,
        where: (w.owner_id == ^user_id or wu.user_id == ^user_id) and w.is_active == true,
        distinct: true,
        order_by: [desc: w.inserted_at]
    )
  end

  def get_user_workspace(user_id, workspace_id) do
    Repo.one(
      from w in Workspace,
        left_join: wu in WorkspaceUser, on: wu.workspace_id == w.id and wu.user_id == ^user_id,
        where: (w.owner_id == ^user_id or wu.user_id == ^user_id) and w.id == ^workspace_id,
        select: w
    )
  end

  def user_workspace_role(user_id, workspace_id) do
    case Repo.one(
      from wu in WorkspaceUser,
        join: w in Workspace, on: w.id == wu.workspace_id,
        where: wu.user_id == ^user_id and wu.workspace_id == ^workspace_id and w.is_active == true,
        select: wu.role
    ) do
      nil ->
        # Check if user owns the workspace
        case Repo.one(from w in Workspace, where: w.id == ^workspace_id and w.owner_id == ^user_id and w.is_active == true, select: true) do
          true -> "owner"
          nil -> nil
        end

      role ->
        role
    end
  end

  def can_access_workspace?(user_id, workspace_id) do
    user_workspace_role(user_id, workspace_id) != nil
  end

  def can_manage_workspace?(user_id, workspace_id) do
    case user_workspace_role(user_id, workspace_id) do
      "owner" -> true
      "admin" -> true
      _ -> false
    end
  end

  def add_workspace_user(workspace_id, user_id, role \\ "user") do
    %WorkspaceUser{}
    |> WorkspaceUser.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  def update_workspace_user_role(workspace_id, user_id, role) do
    try do
      case Repo.one(
        from wu in WorkspaceUser,
          where: wu.workspace_id == ^workspace_id and wu.user_id == ^user_id
      ) do
        nil ->
          {:error, :not_found}

        workspace_user ->
          workspace_user
          |> WorkspaceUser.changeset(%{role: role})
          |> Repo.update()
      end
    rescue
      _e in Ecto.Query.CastError ->
        {:error, :not_found}
    end
  end

  def remove_workspace_user(workspace_id, user_id) do
    Repo.delete_all(
      from wu in WorkspaceUser,
        where: wu.workspace_id == ^workspace_id and wu.user_id == ^user_id
    )

    :ok
  end

  def list_workspace_users(workspace_id) do
    Repo.all(
      from wu in WorkspaceUser,
        where: wu.workspace_id == ^workspace_id,
        preload: :user,
        order_by: [asc: wu.inserted_at]
    )
  end

  def deactivate_workspace(workspace_id) do
    Repo.update_all(
      from(w in Workspace, where: w.id == ^workspace_id),
      set: [is_active: false]
    )

    :ok
  end

  def activate_workspace(workspace_id) do
    Repo.update_all(
      from(w in Workspace, where: w.id == ^workspace_id),
      set: [is_active: true]
    )

    :ok
  end
end
