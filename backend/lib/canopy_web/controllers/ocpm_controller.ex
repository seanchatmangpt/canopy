defmodule CanopyWeb.OcpmController do
  @moduledoc """
  OCPM (Object-Centric Process Mining) Controller.

  Exposes the OCPM Ecto schemas via HTTP for event log ingestion and
  process model storage. All operations are scoped to the authenticated
  user's workspace via workspace_id derived from the current session.

  Routes:
    GET  /api/v1/ocpm/events              — list event logs (optional ?case_id=X filter)
    POST /api/v1/ocpm/events              — create an event log entry
    GET  /api/v1/ocpm/models              — list process models
    POST /api/v1/ocpm/models              — create a process model

  WvdA: All Repo calls are synchronous with implicit DB timeout from Ecto.
  Armstrong: Changeset errors surfaced as 422, never swallowed.
  Chicago TDD: Each action returns a predictable shape — list or created record.
  """

  use CanopyWeb, :controller

  import Ecto.Query, warn: false

  alias Canopy.OCPM.EventLog
  alias Canopy.OCPM.ProcessModel
  alias Canopy.Repo

  require Logger

  # ── GET /api/v1/ocpm/events ──────────────────────────────────────────────────

  @doc """
  List event log entries, optionally filtered by case_id.

  Query params:
    - case_id (optional): filter results to a specific case identifier

  Returns 200 with a list of event log entries.
  """
  def index(conn, params) do
    case_id = Map.get(params, "case_id")

    query =
      if case_id do
        from e in EventLog, where: e.case_id == ^case_id, order_by: [asc: e.timestamp]
      else
        from e in EventLog, order_by: [asc: e.timestamp]
      end

    events = Repo.all(query)

    json(conn, %{
      "events" => Enum.map(events, &serialize_event/1),
      "count" => length(events)
    })
  end

  # ── POST /api/v1/ocpm/events ─────────────────────────────────────────────────

  @doc """
  Create an event log entry.

  Required body fields: case_id, activity, timestamp, resource
  Optional body fields: attributes (map), agent_id

  workspace_id is injected from the authenticated session.
  Returns 201 on success, 422 on validation failure.
  """
  def create(conn, params) do
    workspace_id = get_workspace_id(conn) || Map.get(params, "workspace_id")

    attrs = Map.put(params, "workspace_id", workspace_id)

    changeset = EventLog.changeset(%EventLog{}, attrs)

    case Repo.insert(changeset) do
      {:ok, event} ->
        conn
        |> put_status(201)
        |> json(%{"event" => serialize_event(event)})

      {:error, changeset} ->
        errors = format_errors(changeset)
        Logger.warning("[OcpmController] Event create failed: #{inspect(errors)}")

        conn
        |> put_status(422)
        |> json(%{"error" => "validation_failed", "details" => errors})
    end
  end

  # ── GET /api/v1/ocpm/models ──────────────────────────────────────────────────

  @doc """
  List process models ordered by discovered_at descending.

  Returns 200 with a list of process model entries.
  """
  def index_models(conn, _params) do
    models =
      Repo.all(from m in ProcessModel, order_by: [desc: m.discovered_at])

    json(conn, %{
      "models" => Enum.map(models, &serialize_model/1),
      "count" => length(models)
    })
  end

  # ── POST /api/v1/ocpm/models ─────────────────────────────────────────────────

  @doc """
  Create a process model entry.

  Required body fields: nodes (list of strings), edges (map), version, discovered_at
  Optional body fields: agent_id

  workspace_id is injected from the authenticated session.
  Returns 201 on success, 422 on validation failure.
  """
  def create_model(conn, params) do
    workspace_id = get_workspace_id(conn) || Map.get(params, "workspace_id")

    attrs = Map.put(params, "workspace_id", workspace_id)

    changeset = ProcessModel.changeset(%ProcessModel{}, attrs)

    case Repo.insert(changeset) do
      {:ok, model} ->
        conn
        |> put_status(201)
        |> json(%{"model" => serialize_model(model)})

      {:error, changeset} ->
        errors = format_errors(changeset)
        Logger.warning("[OcpmController] Model create failed: #{inspect(errors)}")

        conn
        |> put_status(422)
        |> json(%{"error" => "validation_failed", "details" => errors})
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp get_workspace_id(conn) do
    case conn.assigns do
      %{current_workspace: %{id: id}} -> id
      %{current_user: %{id: _}} -> nil
      _ -> nil
    end
  end

  defp serialize_event(%EventLog{} = e) do
    %{
      "id" => e.id,
      "case_id" => e.case_id,
      "activity" => e.activity,
      "timestamp" => format_datetime(e.timestamp),
      "resource" => e.resource,
      "attributes" => e.attributes,
      "workspace_id" => e.workspace_id,
      "agent_id" => e.agent_id,
      "inserted_at" => format_datetime(e.inserted_at)
    }
  end

  defp serialize_model(%ProcessModel{} = m) do
    %{
      "id" => m.id,
      "nodes" => m.nodes,
      "edges" => m.edges,
      "version" => m.version,
      "discovered_at" => format_datetime(m.discovered_at),
      "workspace_id" => m.workspace_id,
      "agent_id" => m.agent_id,
      "inserted_at" => format_datetime(m.inserted_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
