defmodule CanopyWeb.BoardControllerBosTest do
  @moduledoc """
  Chicago TDD tests for the BOS intelligence ingest endpoint on BoardController.

  Routes under test:
    POST /api/v1/bos/intelligence  → BoardController.ingest_intelligence/2
    GET  /api/v1/bos/intelligence  → BoardController.bos_intelligence_status/2

  These tests verify:
    1. Valid payload returns 200 or 202 with {"status": "accepted"/"stored"}
    2. Valid payload is stored in ETS and readable via the GET status endpoint
    3. Empty body (all required fields missing) returns 422 with validation errors
       (The controller validates fields and returns 422 Unprocessable Entity, which
       is semantically correct for a payload that fails schema validation.)

  OSA (port 8089) is not required — OSA unreachability degrades to 202 "stored",
  which is acceptable per the Armstrong fault-tolerance design.

  Mirrors pattern from board_intelligence_controller_test.exs and
  process_mining_controller_test.exs.
  """
  use CanopyWeb.ConnCase, async: false

  alias Canopy.Repo
  alias Canopy.Schemas.User

  @bos_intelligence_table :canopy_bos_intelligence

  @valid_payload %{
    "health_summary" => 0.85,
    "conformance_score" => 0.90,
    "top_risk" => "conway_boundary_overlap",
    "conway_violations" => 2,
    "case_count" => 42,
    "handoff_count" => 10
  }

  setup do
    # Ensure ETS table exists (created in application.ex, always present in full app start)
    if :ets.whereis(@bos_intelligence_table) == :undefined do
      :ets.new(@bos_intelligence_table, [:named_table, :set, :public, read_concurrency: true])
    end

    # Clear any previously stored intelligence from other tests
    if :ets.whereis(@bos_intelligence_table) != :undefined do
      :ets.delete(@bos_intelligence_table, :latest)
    end

    user = insert_user()
    conn = build_authenticated_conn(user)
    {:ok, conn: conn}
  end

  # ── Test 1: POST /api/v1/bos/intelligence returns 200 or 202 accepted ─────────

  describe "POST /api/v1/bos/intelligence — accepted response" do
    test "returns 200 or 202 with status accepted or stored for valid payload", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      # OSA may be unreachable in test env — both 200 (forwarded) and 202 (stored) are valid
      assert conn.status in [200, 202]
      body = json_response(conn, conn.status)
      assert body["status"] in ["accepted", "stored"]
    end

    test "response body contains intelligence_source of business_os", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      body = json_response(conn, conn.status)
      assert body["intelligence_source"] == "business_os"
    end

    test "response body contains osa_available field", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      body = json_response(conn, conn.status)
      assert Map.has_key?(body, "osa_available")
    end

    test "never returns 500 for a valid payload", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      refute conn.status == 500
    end
  end

  # ── Test 2: POST stores payload, GET /bos/intelligence reflects stored data ───

  describe "POST /api/v1/bos/intelligence stores payload in ETS" do
    test "GET /api/v1/bos/intelligence returns available: true after valid POST", %{conn: conn} do
      # First POST to store intelligence
      post(conn, "/api/v1/bos/intelligence", @valid_payload)

      # Then GET should reflect the stored data
      conn2 = build_authenticated_conn(Repo.get!(User, conn.assigns.current_user.id))
      get_conn = get(conn2, "/api/v1/bos/intelligence")
      body = json_response(get_conn, 200)
      assert body["available"] == true
    end

    test "GET /api/v1/bos/intelligence payload contains health_summary after POST", %{conn: conn} do
      post(conn, "/api/v1/bos/intelligence", @valid_payload)

      conn2 = build_authenticated_conn(Repo.get!(User, conn.assigns.current_user.id))
      get_conn = get(conn2, "/api/v1/bos/intelligence")
      body = json_response(get_conn, 200)
      assert body["available"] == true
      stored = body["payload"]
      assert is_map(stored)
      assert stored["health_summary"] == 0.85
    end

    test "GET /api/v1/bos/intelligence payload contains conformance_score after POST", %{
      conn: conn
    } do
      post(conn, "/api/v1/bos/intelligence", @valid_payload)

      conn2 = build_authenticated_conn(Repo.get!(User, conn.assigns.current_user.id))
      get_conn = get(conn2, "/api/v1/bos/intelligence")
      body = json_response(get_conn, 200)
      stored = body["payload"]
      assert stored["conformance_score"] == 0.90
    end

    test "GET /api/v1/bos/intelligence payload contains top_risk after POST", %{conn: conn} do
      post(conn, "/api/v1/bos/intelligence", @valid_payload)

      conn2 = build_authenticated_conn(Repo.get!(User, conn.assigns.current_user.id))
      get_conn = get(conn2, "/api/v1/bos/intelligence")
      body = json_response(get_conn, 200)
      stored = body["payload"]
      assert stored["top_risk"] == "conway_boundary_overlap"
    end

    test "GET /api/v1/bos/intelligence payload includes intelligence_received_at timestamp", %{
      conn: conn
    } do
      post(conn, "/api/v1/bos/intelligence", @valid_payload)

      conn2 = build_authenticated_conn(Repo.get!(User, conn.assigns.current_user.id))
      get_conn = get(conn2, "/api/v1/bos/intelligence")
      body = json_response(get_conn, 200)
      stored = body["payload"]
      assert Map.has_key?(stored, "intelligence_received_at")
      # Should be an ISO 8601 timestamp string
      assert is_binary(stored["intelligence_received_at"])
    end

    test "GET /api/v1/bos/intelligence returns available: false before any POST", %{conn: conn} do
      # No POST has been made yet (ETS :latest key cleared in setup)
      get_conn = get(conn, "/api/v1/bos/intelligence")
      body = json_response(get_conn, 200)
      assert body["available"] == false
    end
  end

  # ── Test 3: POST with empty body returns 422 validation error ─────────────────

  describe "POST /api/v1/bos/intelligence — empty body returns 422" do
    test "empty body %{} returns 422 unprocessable entity", %{conn: conn} do
      # Controller validates all required fields and returns 422 for empty payload
      conn = post(conn, "/api/v1/bos/intelligence", %{})
      assert conn.status == 422
    end

    test "empty body response includes error: validation_failed", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", %{})
      body = json_response(conn, 422)
      assert body["error"] == "validation_failed"
    end

    test "empty body response includes details listing all missing fields", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", %{})
      body = json_response(conn, 422)
      details = body["details"]
      assert is_list(details)
      # All 4 required fields should be reported as missing
      assert Enum.any?(details, &String.contains?(&1, "health_summary"))
      assert Enum.any?(details, &String.contains?(&1, "conformance_score"))
      assert Enum.any?(details, &String.contains?(&1, "top_risk"))
      assert Enum.any?(details, &String.contains?(&1, "conway_violations"))
    end

    test "empty body never crashes — returns structured error, not 500", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", %{})
      refute conn.status == 500
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "BOS BOS Test User #{System.unique_integer([:positive])}",
          email: "bos_bos_test#{System.unique_integer([:positive])}@chatmangpt.com",
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
