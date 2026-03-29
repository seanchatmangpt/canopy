defmodule CanopyWeb.ProcessMiningControllerTest do
  @moduledoc """
  Chicago TDD tests for the ProcessMiningController degraded paths.

  These tests verify that when BusinessOS is unavailable, the controller:
    - GET  /api/v1/process-mining/kpis    → 200 + businessos_available: false
    - GET  /api/v1/process-mining/status  → 200 + businessos_available: false
    - POST /api/v1/process-mining/discover → 503 + businessos_available: false

  BOS is intentionally pointed at a dead port (19999) to exercise the error
  branches without needing a live BusinessOS instance.

  Routes live under the :authenticated pipeline, so a Guardian JWT is required.
  Pattern mirrors board_intelligence_controller_test.exs.
  """
  use CanopyWeb.ConnCase, async: false

  alias Canopy.Repo
  alias Canopy.Schemas.User

  # Point BOS at a port that is guaranteed unreachable so Req.post/get errors.
  @dead_bos_url "http://127.0.0.1:19999"
  @real_bos_url "http://127.0.0.1:8001"

  setup do
    Application.put_env(:canopy, :bos_url, @dead_bos_url)

    on_exit(fn ->
      Application.put_env(:canopy, :bos_url, @real_bos_url)
    end)

    user = insert_user()
    conn = build_authenticated_conn(user)
    {:ok, conn: conn}
  end

  # ── GET /api/v1/process-mining/kpis ─────────────────────────────────────────

  describe "GET /api/v1/process-mining/kpis — BOS down (degraded path)" do
    test "returns 200 when BusinessOS is unreachable", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/kpis")
      assert conn.status == 200
    end

    test "body has businessos_available: false when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/kpis")
      body = json_response(conn, 200)
      assert body["businessos_available"] == false
    end

    test "body includes nil KPI fields instead of crashing", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/kpis")
      body = json_response(conn, 200)
      # All KPI fields present but nil — frontend degrades gracefully
      assert Map.has_key?(body, "avg_cycle_time_hours")
      assert Map.has_key?(body, "conformance_score")
      assert Map.has_key?(body, "active_cases")
      assert Map.has_key?(body, "bottleneck_activity")
      assert body["avg_cycle_time_hours"] == nil
      assert body["conformance_score"] == nil
    end

    test "body includes error message when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/kpis")
      body = json_response(conn, 200)
      assert Map.has_key?(body, "error")
      assert body["error"] == "BusinessOS unavailable"
    end

    test "never returns 500 when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/kpis")
      refute conn.status == 500
    end
  end

  # ── GET /api/v1/process-mining/status ───────────────────────────────────────

  describe "GET /api/v1/process-mining/status — BOS down (degraded path)" do
    test "returns 200 when BusinessOS is unreachable", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/status")
      assert conn.status == 200
    end

    test "body has businessos_available: false when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/status")
      body = json_response(conn, 200)
      assert body["businessos_available"] == false
    end

    test "body has status: unavailable when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/status")
      body = json_response(conn, 200)
      assert body["status"] == "unavailable"
    end

    test "body includes error field when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/status")
      body = json_response(conn, 200)
      assert Map.has_key?(body, "error")
      assert body["error"] == "BusinessOS unavailable"
    end

    test "never returns 500 when BOS is down", %{conn: conn} do
      conn = get(conn, "/api/v1/process-mining/status")
      refute conn.status == 500
    end
  end

  # ── POST /api/v1/process-mining/discover ────────────────────────────────────

  describe "POST /api/v1/process-mining/discover — BOS down (degraded path)" do
    test "returns 503 when BusinessOS is unreachable", %{conn: conn} do
      conn = post(conn, "/api/v1/process-mining/discover", %{"log_path" => "/tmp/test.csv"})
      assert conn.status == 503
    end

    test "body has businessos_available: false when BOS is down", %{conn: conn} do
      conn = post(conn, "/api/v1/process-mining/discover", %{"log_path" => "/tmp/test.csv"})
      body = json_response(conn, 503)
      assert body["businessos_available"] == false
    end

    test "body includes error field on 503", %{conn: conn} do
      conn = post(conn, "/api/v1/process-mining/discover", %{"log_path" => "/tmp/test.csv"})
      body = json_response(conn, 503)
      assert Map.has_key?(body, "error")
      assert body["error"] == "BusinessOS unavailable"
    end

    test "returns 503 even without request body", %{conn: conn} do
      conn = post(conn, "/api/v1/process-mining/discover", %{})
      assert conn.status == 503
    end

    test "never returns 500 when BOS is down", %{conn: conn} do
      conn =
        post(conn, "/api/v1/process-mining/discover", %{
          "log_path" => "/tmp/test.csv",
          "algorithm" => "alpha"
        })

      refute conn.status == 500
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "PM Test User #{System.unique_integer([:positive])}",
          email: "pm_test#{System.unique_integer([:positive])}@chatmangpt.com",
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

  defp build_authenticated_conn(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:assigns, %{current_user: user})
  end
end
