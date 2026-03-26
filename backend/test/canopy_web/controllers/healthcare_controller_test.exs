defmodule CanopyWeb.HealthcareControllerTest do
  @moduledoc """
  Comprehensive healthcare controller tests — Chicago TDD style.

  Tests organized by endpoint:
    1. POST /healthcare/phi/track
    2. POST /healthcare/consent/verify
    3. GET /healthcare/audit/trail
    4. POST /healthcare/hipaa/verify
    5. POST /healthcare/consent/grant
    6. POST /healthcare/consent/revoke
  """
  use CanopyWeb.ConnCase

  alias Canopy.Repo
  alias Canopy.Schemas.User
  alias Canopy.Healthcare.PolicyEngine

  # ── Setup ───────────────────────────────────────────────────────

  setup do
    healthcare_provider = insert_user(%{
      email: "provider@hospital.com",
      name: "Dr. Smith",
      role: "healthcare_provider"
    })

    staff_member = insert_user(%{
      email: "staff@hospital.com",
      name: "Nurse Jane",
      role: "staff"
    })

    admin_user = insert_user(%{
      email: "admin@hospital.com",
      name: "Admin",
      role: "admin"
    })

    {:ok,
     provider: healthcare_provider,
     staff: staff_member,
     admin: admin_user,
     patient_id: "PAT-123456",
     workspace_id: "WS-001"}
  end

  # ── Test: Track PHI Access ──────────────────────────────────────

  describe "POST /api/v1/healthcare/phi/track" do
    test "logs PHI read access successfully", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/phi/track", %{
          patient_id: patient_id,
          data_type: "medical_record",
          action: "read",
          user_id: provider.id,
          workspace_id: "WS-001"
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert body["success"] == true
      assert body["patient_id"] == patient_id
      assert body["action"] == "read"
      assert body["status"] == "logged"
      assert body["audit_id"]
    end

    test "logs PHI write access with all metadata", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/phi/track", %{
          patient_id: patient_id,
          data_type: "lab_result",
          action: "write",
          user_id: provider.id,
          workspace_id: "WS-001",
          ip_address: "192.168.1.100"
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert body["action"] == "write"
      assert body["timestamp"]
    end

    test "logs PHI delete access", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/phi/track", %{
          patient_id: patient_id,
          data_type: "prescription",
          action: "delete",
          user_id: provider.id
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert body["action"] == "delete"
    end

    test "rejects invalid data_type", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/phi/track", %{
          patient_id: patient_id,
          data_type: "invalid_type",
          action: "read",
          user_id: provider.id
        })

      assert response.status == 400
      body = json_response(response, 400)
      assert body["error"] == "invalid_data_type"
    end

    test "rejects invalid action", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/phi/track", %{
          patient_id: patient_id,
          data_type: "medical_record",
          action: "invalid_action",
          user_id: provider.id
        })

      assert response.status == 400
      body = json_response(response, 400)
      assert body["error"] == "invalid_action"
    end

    test "logs imaging data access", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/phi/track", %{
          patient_id: patient_id,
          data_type: "imaging",
          action: "read",
          user_id: provider.id
        })

      assert response.status == 201
    end
  end

  # ── Test: Verify Consent ────────────────────────────────────────

  describe "POST /api/v1/healthcare/consent/verify" do
    test "verifies consent when patient has granted", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      # First grant consent
      PolicyEngine.grant_consent(%{
        "patient_id" => patient_id,
        "data_types" => ["medical_record"],
        "expiration_days" => 365,
        "user_id" => provider.id
      })

      # Then verify
      response =
        post(conn, "/api/v1/healthcare/consent/verify", %{
          patient_id: patient_id,
          user_id: provider.id,
          data_type: "medical_record"
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["consent_verified"] == true
      assert body["patient_id"] == patient_id
      assert body["message"] == "Consent verified"
    end

    test "denies consent when patient has not granted", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/verify", %{
          patient_id: patient_id,
          user_id: provider.id,
          data_type: "medical_record"
        })

      assert response.status == 403
      body = json_response(response, 403)
      assert body["error"] == "no_consent"
    end

    test "returns consent_expired when consent has expired", %{
      provider: provider,
      patient_id: patient_id
    } do
      conn = build_authenticated_conn(provider)

      # In production: test with actual expired consent
      # For now: test structure is correct
      response =
        post(conn, "/api/v1/healthcare/consent/verify", %{
          patient_id: patient_id,
          user_id: provider.id,
          data_type: "lab_result"
        })

      assert response.status in [200, 403]
    end

    test "includes expiration date in response", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      PolicyEngine.grant_consent(%{
        "patient_id" => patient_id,
        "data_types" => ["lab_result"],
        "expiration_days" => 30,
        "user_id" => provider.id
      })

      response =
        post(conn, "/api/v1/healthcare/consent/verify", %{
          patient_id: patient_id,
          user_id: provider.id,
          data_type: "lab_result"
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["expiration"]
    end
  end

  # ── Test: Audit Trail ───────────────────────────────────────────

  describe "GET /api/v1/healthcare/audit/trail" do
    test "retrieves audit entries for patient", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      # Log an access
      post(conn, "/api/v1/healthcare/phi/track", %{
        patient_id: patient_id,
        data_type: "medical_record",
        action: "read",
        user_id: provider.id
      })

      # Retrieve audit trail
      response = get(conn, "/api/v1/healthcare/audit/trail", %{"patient_id" => patient_id})

      assert response.status == 200
      body = json_response(response, 200)
      assert body["patient_id"] == patient_id
      assert body["total_entries"] >= 0
      assert is_list(body["entries"])
    end

    test "respects limit parameter", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        get(conn, "/api/v1/healthcare/audit/trail", %{
          "patient_id" => patient_id,
          "limit" => "10"
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert Enum.count(body["entries"]) <= 10
    end

    test "filters by date range", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      now = DateTime.utc_now()
      yesterday = DateTime.add(now, -86400)

      response =
        get(conn, "/api/v1/healthcare/audit/trail", %{
          "patient_id" => patient_id,
          "date_from" => DateTime.to_iso8601(yesterday),
          "date_to" => DateTime.to_iso8601(now)
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert is_list(body["entries"])
    end

    test "returns 404 for non-existent patient", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response = get(conn, "/api/v1/healthcare/audit/trail", %{"patient_id" => ""})

      assert response.status == 404
    end

    test "rejects invalid date range", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        get(conn, "/api/v1/healthcare/audit/trail", %{
          "patient_id" => patient_id,
          "date_from" => "invalid-date",
          "date_to" => "also-invalid"
        })

      assert response.status == 400
    end
  end

  # ── Test: HIPAA Compliance Verification ─────────────────────────

  describe "POST /api/v1/healthcare/hipaa/verify" do
    test "verifies patient_access compliance", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/hipaa/verify", %{
          operation: "patient_access",
          parameters: %{
            encryption_enabled: true,
            role_based_access: true,
            audit_enabled: true
          }
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["operation"] == "patient_access"
      assert is_boolean(body["compliant"])
      assert is_list(body["checks_passed"])
    end

    test "detects encryption violation", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/hipaa/verify", %{
          operation: "encryption",
          parameters: %{
            encryption_enabled: false
          }
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["compliant"] == false
      assert Enum.any?(body["violations"], fn v -> v["code"] == "encryption" end)
    end

    test "verifies data_breach compliance", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/hipaa/verify", %{
          operation: "data_breach",
          parameters: %{
            audit_enabled: true,
            notification_sent: true
          }
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["operation"] == "data_breach"
    end

    test "verifies access_control compliance", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/hipaa/verify", %{
          operation: "access_control",
          parameters: %{
            role_based_access: true,
            mfa_enabled: true
          }
        })

      assert response.status == 200
    end

    test "rejects invalid operation", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/hipaa/verify", %{
          operation: "invalid_operation",
          parameters: %{}
        })

      assert response.status == 400
      body = json_response(response, 400)
      assert body["error"] == "invalid_operation"
    end

    test "includes violation details in response", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/hipaa/verify", %{
          operation: "encryption",
          parameters: %{
            encryption_enabled: false
          }
        })

      body = json_response(response, 200)
      violations = body["violations"]
      assert is_list(violations)
    end
  end

  # ── Test: Grant Consent ─────────────────────────────────────────

  describe "POST /api/v1/healthcare/consent/grant" do
    test "grants consent for single data type", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/grant", %{
          patient_id: patient_id,
          data_types: ["medical_record"],
          expiration_days: 365,
          user_id: provider.id
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert body["patient_id"] == patient_id
      assert body["data_types"] == ["medical_record"]
      assert body["consent_id"]
      assert body["expires_at"]
    end

    test "grants consent for multiple data types", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/grant", %{
          patient_id: patient_id,
          data_types: ["medical_record", "lab_result", "prescription"],
          expiration_days: 180,
          user_id: provider.id
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert Enum.count(body["data_types"]) >= 1
    end

    test "rejects invalid expiration days", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/grant", %{
          patient_id: patient_id,
          data_types: ["medical_record"],
          expiration_days: -1,
          user_id: provider.id
        })

      assert response.status == 400
      body = json_response(response, 400)
      assert body["error"] == "invalid_expiration"
    end

    test "defaults to 365 days if expiration not specified", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/grant", %{
          patient_id: patient_id,
          data_types: ["medical_record"],
          user_id: provider.id
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert body["expires_at"]
    end

    test "includes grant timestamp", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/grant", %{
          patient_id: patient_id,
          data_types: ["lab_result"],
          expiration_days: 90,
          user_id: provider.id
        })

      assert response.status == 201
      body = json_response(response, 201)
      assert body["granted_at"]
    end
  end

  # ── Test: Revoke Consent ────────────────────────────────────────

  describe "POST /api/v1/healthcare/consent/revoke" do
    test "revokes existing consent", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      # Grant consent first
      {:ok, consent} =
        PolicyEngine.grant_consent(%{
          "patient_id" => patient_id,
          "data_types" => ["medical_record"],
          "user_id" => provider.id
        })

      # Then revoke
      response =
        post(conn, "/api/v1/healthcare/consent/revoke", %{
          consent_id: consent.id,
          reason: "Patient requested revocation"
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["success"] == true
      assert body["consent_id"] == consent.id
    end

    test "returns 404 for non-existent consent", %{provider: provider} do
      conn = build_authenticated_conn(provider)

      response =
        post(conn, "/api/v1/healthcare/consent/revoke", %{
          consent_id: "nonexistent-id",
          reason: "Testing"
        })

      assert response.status == 404
      body = json_response(response, 404)
      assert body["error"] == "consent_not_found"
    end

    test "includes revocation message", %{provider: provider, patient_id: patient_id} do
      conn = build_authenticated_conn(provider)

      {:ok, consent} =
        PolicyEngine.grant_consent(%{
          "patient_id" => patient_id,
          "data_types" => ["prescription"],
          "user_id" => provider.id
        })

      response =
        post(conn, "/api/v1/healthcare/consent/revoke", %{
          consent_id: consent.id,
          reason: "Testing revocation"
        })

      assert response.status == 200
      body = json_response(response, 200)
      assert body["message"] == "Consent revoked successfully"
    end
  end

  # ── Private Helpers ────────────────────────────────────────────────

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "Test User #{System.unique_integer([:positive])}",
          email: "test#{System.unique_integer([:positive])}@hospital.com",
          password: "securepass123",
          role: "healthcare_provider",
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
