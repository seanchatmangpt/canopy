defmodule CanopyWeb.BoardIntelligenceControllerTest do
  @moduledoc """
  Chicago TDD tests for POST /api/v1/bos/intelligence (BoardController.ingest_intelligence/2).

  Tests validate:
  - 422 on missing required fields
  - 422 on out-of-range values
  - 200/202 on valid payload (OSA may be unreachable in test env — degraded is ok)
  """
  use CanopyWeb.ConnCase, async: false

  alias Canopy.Repo
  alias Canopy.Schemas.User

  @valid_payload %{
    "health_summary" => 0.85,
    "conformance_score" => 0.90,
    "top_risk" => "conway_boundary_overlap",
    "conway_violations" => 2,
    "case_count" => 42,
    "handoff_count" => 10
  }

  setup do
    user = insert_user()
    conn = build_authenticated_conn(user)
    {:ok, conn: conn}
  end

  describe "POST /api/v1/bos/intelligence — validation (422)" do
    test "missing health_summary returns 422", %{conn: conn} do
      payload = Map.delete(@valid_payload, "health_summary")
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      body = json_response(conn, 422)
      assert body["error"] == "validation_failed"
      assert Enum.any?(body["details"], &String.contains?(&1, "health_summary"))
    end

    test "health_summary greater than 1 returns 422", %{conn: conn} do
      payload = Map.put(@valid_payload, "health_summary", 1.5)
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert conn.status == 422
    end

    test "health_summary less than 0 returns 422", %{conn: conn} do
      payload = Map.put(@valid_payload, "health_summary", -0.5)
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert conn.status == 422
    end

    test "missing conformance_score returns 422", %{conn: conn} do
      payload = Map.delete(@valid_payload, "conformance_score")
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert json_response(conn, 422)["error"] == "validation_failed"
    end

    test "conformance_score out of [0,1] returns 422", %{conn: conn} do
      payload = Map.put(@valid_payload, "conformance_score", 2.0)
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert conn.status == 422
    end

    test "missing top_risk returns 422", %{conn: conn} do
      payload = Map.delete(@valid_payload, "top_risk")
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert json_response(conn, 422)["error"] == "validation_failed"
    end

    test "empty top_risk returns 422", %{conn: conn} do
      payload = Map.put(@valid_payload, "top_risk", "")
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert conn.status == 422
    end

    test "negative conway_violations returns 422", %{conn: conn} do
      payload = Map.put(@valid_payload, "conway_violations", -1)
      conn = post(conn, "/api/v1/bos/intelligence", payload)
      assert conn.status == 422
    end
  end

  describe "POST /api/v1/bos/intelligence — success paths (OSA unavailable in test)" do
    test "valid payload returns 200 or 202", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      assert conn.status in [200, 202]
    end

    test "response body has status field", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      body = json_response(conn, conn.status)
      assert Map.has_key?(body, "status")
      assert body["status"] in ["accepted", "stored"]
    end

    test "response body has intelligence_source set to business_os", %{conn: conn} do
      conn = post(conn, "/api/v1/bos/intelligence", @valid_payload)
      body = json_response(conn, conn.status)
      assert Map.get(body, "intelligence_source") == "business_os"
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "BOS Test User #{System.unique_integer([:positive])}",
          email: "bos_test#{System.unique_integer([:positive])}@chatmangpt.com",
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
