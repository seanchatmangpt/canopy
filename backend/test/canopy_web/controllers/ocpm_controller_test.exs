defmodule CanopyWeb.OcpmControllerTest do
  @moduledoc """
  Chicago TDD tests for the OcpmController.

  Verifies the three core behaviors:
    1. POST /api/v1/ocpm/events  — creates an event log entry (201)
    2. GET  /api/v1/ocpm/events  — returns list of events (200 with array body)
    3. GET  /api/v1/ocpm/events?case_id=X — filters results by case_id

  Tests use real Repo inserts (Chicago School: no mocking of the DB layer).
  Authentication pattern mirrors process_mining_controller_test.exs.
  """
  use CanopyWeb.ConnCase, async: false

  alias Canopy.Repo
  alias Canopy.Schemas.User
  alias Canopy.Schemas.Workspace
  alias Canopy.OCPM.EventLog

  @valid_event_params %{
    "case_id" => "CASE-001",
    "activity" => "approve",
    "timestamp" => "2026-03-24T10:00:00Z",
    "resource" => "agent-42"
  }

  setup do
    user = insert_user()
    workspace = insert_workspace(user)
    conn = build_authenticated_conn(user)
    {:ok, conn: conn, user: user, workspace: workspace}
  end

  # ── POST /api/v1/ocpm/events ─────────────────────────────────────────────────

  describe "POST /api/v1/ocpm/events creates an event log entry" do
    test "returns 201 on valid params", %{conn: conn, workspace: workspace} do
      params = Map.put(@valid_event_params, "workspace_id", workspace.id)
      conn = post(conn, "/api/v1/ocpm/events", params)
      assert conn.status == 201
    end

    test "response body contains the created event", %{conn: conn, workspace: workspace} do
      params = Map.put(@valid_event_params, "workspace_id", workspace.id)
      conn = post(conn, "/api/v1/ocpm/events", params)
      body = json_response(conn, 201)
      assert is_map(body["event"])
      assert body["event"]["case_id"] == "CASE-001"
      assert body["event"]["activity"] == "approve"
      assert body["event"]["resource"] == "agent-42"
    end

    test "response body event has an id", %{conn: conn, workspace: workspace} do
      params = Map.put(@valid_event_params, "workspace_id", workspace.id)
      conn = post(conn, "/api/v1/ocpm/events", params)
      body = json_response(conn, 201)
      assert is_binary(body["event"]["id"])
      assert byte_size(body["event"]["id"]) > 0
    end

    test "returns 422 when required field activity is missing", %{conn: conn, workspace: workspace} do
      params =
        @valid_event_params
        |> Map.delete("activity")
        |> Map.put("workspace_id", workspace.id)

      conn = post(conn, "/api/v1/ocpm/events", params)
      body = json_response(conn, 422)
      assert body["error"] == "validation_failed"
    end

    test "returns 422 when activity is not in the valid list", %{conn: conn, workspace: workspace} do
      params =
        @valid_event_params
        |> Map.put("activity", "unknown_action")
        |> Map.put("workspace_id", workspace.id)

      conn = post(conn, "/api/v1/ocpm/events", params)
      assert conn.status == 422
    end

    test "returns 422 when required field case_id is missing", %{conn: conn, workspace: workspace} do
      params =
        @valid_event_params
        |> Map.delete("case_id")
        |> Map.put("workspace_id", workspace.id)

      conn = post(conn, "/api/v1/ocpm/events", params)
      assert conn.status == 422
    end
  end

  # ── GET /api/v1/ocpm/events returns list ────────────────────────────────────

  describe "GET /api/v1/ocpm/events returns list" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, "/api/v1/ocpm/events")
      assert conn.status == 200
    end

    test "body has events array", %{conn: conn} do
      conn = get(conn, "/api/v1/ocpm/events")
      body = json_response(conn, 200)
      assert is_list(body["events"])
    end

    test "body has count field", %{conn: conn} do
      conn = get(conn, "/api/v1/ocpm/events")
      body = json_response(conn, 200)
      assert is_integer(body["count"])
    end

    test "count matches number of events in list", %{conn: conn, workspace: workspace} do
      insert_event_log(%{workspace_id: workspace.id, case_id: "LIST-001"})
      insert_event_log(%{workspace_id: workspace.id, case_id: "LIST-002"})

      conn = get(conn, "/api/v1/ocpm/events")
      body = json_response(conn, 200)
      assert body["count"] == length(body["events"])
    end
  end

  # ── GET /api/v1/ocpm/events?case_id=X filters results ───────────────────────

  describe "GET /api/v1/ocpm/events?case_id=X filters results" do
    test "returns only events matching the case_id", %{conn: conn, workspace: workspace} do
      insert_event_log(%{workspace_id: workspace.id, case_id: "FILTER-TARGET"})
      insert_event_log(%{workspace_id: workspace.id, case_id: "FILTER-OTHER"})

      conn = get(conn, "/api/v1/ocpm/events", %{"case_id" => "FILTER-TARGET"})
      body = json_response(conn, 200)

      assert body["count"] >= 1
      assert Enum.all?(body["events"], fn e -> e["case_id"] == "FILTER-TARGET" end)
    end

    test "returns empty list when case_id has no matching events", %{conn: conn} do
      conn = get(conn, "/api/v1/ocpm/events", %{"case_id" => "NO-SUCH-CASE"})
      body = json_response(conn, 200)
      assert body["events"] == []
      assert body["count"] == 0
    end

    test "does not include events from other case_ids in filtered result",
         %{conn: conn, workspace: workspace} do
      insert_event_log(%{workspace_id: workspace.id, case_id: "WANTED"})
      insert_event_log(%{workspace_id: workspace.id, case_id: "NOT-WANTED"})

      conn = get(conn, "/api/v1/ocpm/events", %{"case_id" => "WANTED"})
      body = json_response(conn, 200)

      refute Enum.any?(body["events"], fn e -> e["case_id"] == "NOT-WANTED" end)
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "OCPM Test User #{System.unique_integer([:positive])}",
          email: "ocpm_test#{System.unique_integer([:positive])}@chatmangpt.com",
          password: "securepass123",
          role: "admin",
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

  defp insert_workspace(user, attrs \\ %{}) do
    workspace_attrs =
      Map.merge(
        %{
          name: "OCPM Workspace #{System.unique_integer([:positive])}",
          path: "/ocpm/test/#{System.unique_integer([:positive])}",
          owner_id: user.id
        },
        attrs
      )

    {:ok, workspace} =
      Repo.insert(Workspace.changeset(%Workspace{}, workspace_attrs))

    workspace
  end

  defp insert_event_log(attrs) do
    base = %{
      case_id: "TEST-CASE-#{System.unique_integer([:positive])}",
      activity: "approve",
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      resource: "test-resource"
    }

    merged = Map.merge(base, attrs)

    {:ok, event} = Repo.insert(EventLog.changeset(%EventLog{}, stringify_keys(merged)))
    event
  end

  defp build_authenticated_conn(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:assigns, %{current_user: user})
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
