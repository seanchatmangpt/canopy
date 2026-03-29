defmodule Canopy.Workspaces do
  @moduledoc """
  Context module for workspace operations.

  Implements real Ecto queries for workspace management:
  - list_workspaces/1: List all workspaces owned by a user
  - get_workspace!/1: Get a workspace by ID (raises on missing)
  - create_workspace/1: Create a new workspace
  - list_workspace_users/1: List all users in a workspace
  - add_workspace_member/2: Add a member to a workspace
  - remove_member/2: Remove a user from a workspace
  - user_has_access?/2: Check membership
  """

  import Ecto.Query

  alias Canopy.Repo
  alias Canopy.Schemas.{Workspace, WorkspaceUser, User}

  @doc """
  List all workspaces owned by `user_id`.
  """
  def list_workspaces(user_id) do
    Repo.all(from(w in Workspace, where: w.owner_id == ^user_id))
  end

  @doc """
  Get a workspace by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_workspace!(id) do
    Repo.get!(Workspace, id)
  end

  @doc """
  Create a new workspace.

  Returns `{:ok, workspace}` on success or `{:error, changeset}` on failure.
  """
  def create_workspace(attrs) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List all users who are members of `workspace_id`.

  Returns a list of `%User{}` structs.
  """
  def list_workspace_users(workspace_id) do
    Repo.all(
      from(u in User,
        join: wu in WorkspaceUser,
        on: wu.user_id == u.id,
        where: wu.workspace_id == ^workspace_id,
        select: u
      )
    )
  end

  @doc """
  Add a user as a member of a workspace (default role: "member").

  Returns `{:ok, workspace_user}` or `{:error, changeset}`.
  """
  def add_workspace_member(workspace_id, user_id, role \\ "member") do
    %WorkspaceUser{}
    |> WorkspaceUser.changeset(%{workspace_id: workspace_id, user_id: user_id, role: role})
    |> Repo.insert()
  end

  @doc """
  Remove a user from a workspace.

  Returns the number of deleted rows.
  """
  def remove_member(workspace_id, user_id) do
    {count, _} =
      Repo.delete_all(
        from(wu in WorkspaceUser,
          where: wu.workspace_id == ^workspace_id and wu.user_id == ^user_id
        )
      )

    count
  end

  @doc """
  Check whether `user_id` is a member of `workspace_id`.

  Returns `true` or `false`.
  """
  def user_has_access?(workspace_id, user_id) do
    Repo.exists?(
      from(wu in WorkspaceUser,
        where: wu.workspace_id == ^workspace_id and wu.user_id == ^user_id
      )
    )
  end
end
