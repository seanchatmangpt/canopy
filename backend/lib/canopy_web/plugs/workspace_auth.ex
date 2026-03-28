defmodule CanopyWeb.Plugs.WorkspaceAuth do
  @moduledoc """
  Validates that the current user owns (or has access to) the workspace
  referenced in the request params.

  Extracts `workspace_id` from:
    1. `params["workspace_id"]` (query string or body)
    2. Resource's `workspace_id` for show/update/delete on nested resources

  If no `workspace_id` is present in the request, the plug passes through
  (the endpoint may not be workspace-scoped). When a `workspace_id` IS
  present, the plug verifies the authenticated user owns that workspace.

  Must be placed AFTER `CanopyWeb.Plugs.Auth` in the pipeline so that
  `conn.assigns.current_user` is available.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  import Ecto.Query

  alias Canopy.Repo
  alias Canopy.Schemas.Workspace
  alias Canopy.WorkspaceIsolation

  def init(opts), do: opts

  def call(conn, _opts) do
    workspace_id = conn.path_params["workspace_id"]
    user = conn.assigns[:current_user]

    cond do
      # No workspace_id in params — scope to all workspaces owned by the current user
      is_nil(workspace_id) or workspace_id == "" ->
        user_workspace_ids =
          Repo.all(from w in Workspace, where: w.owner_id == ^user.id, select: w.id)

        assign(conn, :user_workspace_ids, user_workspace_ids)

      # Validate membership (owner or workspace_users entry) when workspace_id is present
      true ->
        case WorkspaceIsolation.get_user_workspace(user.id, workspace_id) do
          nil ->
            conn
            |> put_status(403)
            |> json(%{error: "forbidden", message: "You do not have access to this workspace"})
            |> halt()

          workspace ->
            conn
            |> assign(:workspace, workspace)
            |> assign(:user_workspace_ids, [workspace_id])
        end
    end
  end
end
