defmodule CanopyWeb.SpawnController do
  use CanopyWeb, :controller

  alias Canopy.Repo
  alias Canopy.Schemas.{Agent, Session}
  import Ecto.Query

  def create(conn, params) do
    agent_id = params["agent_id"]
    # Fix 4: accept both "context" and "prompt" as the initial context
    context = params["context"] || params["prompt"] || ""

    # Fix 5: look up the agent to propagate workspace_id onto the session
    agent = Repo.get!(Agent, agent_id)

    session_params = %{
      "agent_id" => agent_id,
      "workspace_id" => agent.workspace_id,
      "model" => params["model"] || agent.model,
      "started_at" => DateTime.utc_now() |> DateTime.truncate(:second),
      "context" => context,
      "status" => "active"
    }

    changeset = Session.changeset(%Session{}, session_params)

    case Repo.insert(changeset) do
      {:ok, session} ->
        # Pass the pre-created session_id so Heartbeat.run/2 reuses this row
        # instead of inserting a second one.
        Task.Supervisor.start_child(Canopy.HeartbeatRunner, fn ->
          Canopy.Heartbeat.run(agent_id, context: context, session_id: session.id)
        end)

        conn
        |> put_status(201)
        |> json(%{session: %{id: session.id, status: session.status}})

      {:error, cs} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(cs)})
    end
  end

  def active(conn, _params) do
    sessions =
      Repo.all(
        from s in Session,
          where: s.status == "active",
          order_by: [desc: s.started_at]
      )

    json(conn, %{
      instances:
        Enum.map(sessions, fn s ->
          %{
            id: s.id,
            agent_id: s.agent_id,
            model: s.model,
            status: s.status,
            started_at: s.started_at
          }
        end)
    })
  end

  def kill(conn, %{"id" => id}) do
    case Repo.get(Session, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      session ->
        case session
             |> Ecto.Changeset.change(
               status: "cancelled",
               completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
             )
             |> Repo.update() do
          {:ok, _} ->
            json(conn, %{ok: true})

          {:error, _changeset} ->
            conn |> put_status(500) |> json(%{error: "update_failed"})
        end
    end
  end

  def history(conn, params) do
    limit = min(String.to_integer(params["limit"] || "50"), 100)

    sessions =
      Repo.all(
        from s in Session,
          where: s.status in ["completed", "failed", "cancelled"],
          order_by: [desc: s.completed_at],
          limit: ^limit
      )

    json(conn, %{
      history:
        Enum.map(sessions, fn s ->
          %{
            id: s.id,
            agent_id: s.agent_id,
            model: s.model,
            status: s.status,
            started_at: s.started_at,
            completed_at: s.completed_at,
            cost_cents: s.cost_cents
          }
        end)
    })
  end

  # --- Private helpers ---

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
