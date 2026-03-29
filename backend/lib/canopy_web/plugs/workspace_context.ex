defmodule CanopyWeb.Plugs.WorkspaceContext do
  @moduledoc """
  Workspace context middleware that extracts workspace_id from:
    1. URL path parameter `:workspace_id`
    2. Query parameter `?workspace_id=...`
    3. Request header `X-Workspace-ID`
    4. Session storage (for SPA clients)

  Validates that the current user has access to the requested workspace
  and stores the workspace ID in conn.assigns for use in handlers and data queries.

  Must run AFTER `CanopyWeb.Plugs.Auth` so that conn.assigns.current_user is available.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Canopy.WorkspaceIsolation
  alias Canopy.Repo
  alias Canopy.Schemas.Workspace

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    user = conn.assigns[:current_user]

    # Extract workspace_id from multiple sources (in priority order)
    workspace_id =
      conn.params["workspace_id"] ||
        get_req_header(conn, "x-workspace-id") |> List.first() ||
        conn.private[:workspace_id]

    case {user, workspace_id} do
      {nil, _} ->
        # No user, no workspace context
        conn

      {_user, nil} ->
        # User authenticated but no workspace specified
        # Try to use default workspace from user preferences or first workspace
        case get_user_default_workspace(user.id) do
          nil ->
            # No default workspace, let handler decide
            conn
            |> assign(:current_workspace, nil)
            |> assign(:current_workspace_id, nil)

          workspace ->
            conn
            |> assign(:current_workspace, workspace)
            |> assign(:current_workspace_id, workspace.id)
        end

      {_user, workspace_id} ->
        # Validate workspace access
        case WorkspaceIsolation.get_user_workspace(user.id, workspace_id) do
          nil ->
            conn
            |> put_status(403)
            |> json(%{
              error: "forbidden",
              message: "You do not have access to this workspace"
            })
            |> halt()

          workspace ->
            role = WorkspaceIsolation.user_workspace_role(user.id, workspace_id)

            conn
            |> assign(:current_workspace, workspace)
            |> assign(:current_workspace_id, workspace.id)
            |> assign(:current_workspace_role, role)
        end
    end
  end

  defp get_user_default_workspace(user_id) do
    import Ecto.Query

    case Repo.one(
           from w in Workspace,
             where:
               w.owner_id == ^user_id or (w.is_active == true and w.isolation_level == "public"),
             order_by: [desc: w.inserted_at],
             limit: 1
         ) do
      nil -> nil
      workspace -> workspace
    end
  end
end
