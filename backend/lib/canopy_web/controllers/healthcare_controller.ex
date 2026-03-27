defmodule CanopyWeb.HealthcareController do
  @moduledoc """
  Healthcare controller — manages HIPAA-compliant operations, PHI tracking, consent verification, and audit trails.

  Endpoints:
    POST /api/v1/healthcare/phi/track           — Track PHI access
    POST /api/v1/healthcare/consent/verify      — Verify patient consent
    GET  /api/v1/healthcare/audit/trail         — Retrieve audit trail
    POST /api/v1/healthcare/hipaa/verify        — Verify HIPAA compliance
    POST /api/v1/healthcare/consent/grant       — Grant consent for PHI access
    POST /api/v1/healthcare/consent/revoke      — Revoke consent
  """
  use CanopyWeb, :controller

  alias Canopy.Healthcare.PolicyEngine
  alias Canopy.Healthcare.AuditTrail

  @doc """
  Track PHI (Protected Health Information) access.

  Request body:
    {
      "patient_id": "string",
      "data_type": "string (medical_record|lab_result|prescription|imaging)",
      "action": "string (read|write|delete)",
      "user_id": "string",
      "workspace_id": "string"
    }

  Response: 201 Created with audit entry or 400/403 on error
  """
  def track_phi(conn, params) do
    with {:ok, audit_entry} <- create_phi_audit_entry(params, conn.assigns.current_user) do
      conn
      |> put_status(201)
      |> json(%{
        success: true,
        audit_id: audit_entry.id,
        timestamp: audit_entry.inserted_at,
        patient_id: audit_entry.patient_id,
        action: audit_entry.action,
        status: "logged"
      })
    else
      {:error, :invalid_data_type} ->
        conn
        |> put_status(400)
        |> json(%{
          error: "invalid_data_type",
          message: "data_type must be one of: medical_record, lab_result, prescription, imaging"
        })

      {:error, :invalid_action} ->
        conn
        |> put_status(400)
        |> json(%{
          error: "invalid_action",
          message: "action must be one of: read, write, delete"
        })

      {:error, :unauthorized} ->
        conn
        |> put_status(403)
        |> json(%{error: "unauthorized", message: "insufficient permissions to access PHI"})

      {:error, :patient_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "patient_not_found", message: "patient does not exist"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "audit_failed", message: inspect(reason)})
    end
  end

  @doc """
  Verify patient consent for PHI access.

  Request body:
    {
      "patient_id": "string",
      "user_id": "string",
      "data_type": "string (medical_record|lab_result|prescription|imaging)"
    }

  Response: 200 OK with consent status or 403/404 on error
  """
  def verify_consent(conn, params) do
    with {:ok, consent_status} <- PolicyEngine.verify_consent(params) do
      conn
      |> put_status(200)
      |> json(%{
        consent_verified: consent_status.granted,
        patient_id: consent_status.patient_id,
        data_type: consent_status.data_type,
        expiration: consent_status.expiration,
        message: if(consent_status.granted, do: "Consent verified", else: "Consent denied")
      })
    else
      {:error, :no_consent} ->
        conn
        |> put_status(403)
        |> json(%{
          error: "no_consent",
          message: "Patient has not granted consent for this data access"
        })

      {:error, :consent_expired} ->
        conn
        |> put_status(403)
        |> json(%{
          error: "consent_expired",
          message: "Patient consent has expired"
        })

      {:error, :patient_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "patient_not_found", message: "patient does not exist"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "consent_verification_failed", message: inspect(reason)})
    end
  end

  @doc """
  Retrieve HIPAA audit trail for a patient.

  Query parameters:
    - patient_id (required): Patient identifier
    - limit (optional, default 100): Number of entries to return
    - offset (optional, default 0): Pagination offset
    - date_from (optional): ISO8601 timestamp start
    - date_to (optional): ISO8601 timestamp end

  Response: 200 OK with audit entries or 404 on error
  """
  def audit_trail(conn, params) do
    with {:ok, entries} <- AuditTrail.fetch(params) do
      conn
      |> put_status(200)
      |> json(%{
        patient_id: params["patient_id"],
        total_entries: Enum.count(entries),
        entries: Enum.map(entries, &serialize_audit_entry/1)
      })
    else
      {:error, :patient_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "patient_not_found", message: "patient does not exist"})

      {:error, :invalid_date_range} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid_date_range", message: "date_from must be before date_to"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "audit_fetch_failed", message: inspect(reason)})
    end
  end

  @doc """
  Verify HIPAA compliance for a specific healthcare operation.

  Request body:
    {
      "operation": "string (patient_access|data_breach|encryption|access_control)",
      "parameters": {
        "patient_id": "string",
        "data_type": "string",
        "encryption_enabled": boolean
      }
    }

  Response: 200 OK with compliance status
  """
  def verify_hipaa(conn, params) do
    with {:ok, compliance_status} <- PolicyEngine.verify_hipaa_compliance(params) do
      conn
      |> put_status(200)
      |> json(%{
        compliant: compliance_status.passed,
        operation: compliance_status.operation,
        checks_passed: compliance_status.checks_passed,
        checks_failed: compliance_status.checks_failed,
        violations: serialize_violations(compliance_status.violations)
      })
    else
      {:error, :invalid_operation} ->
        conn
        |> put_status(400)
        |> json(%{
          error: "invalid_operation",
          message:
            "operation must be one of: patient_access, data_breach, encryption, access_control"
        })

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "compliance_check_failed", message: inspect(reason)})
    end
  end

  @doc """
  Grant consent for PHI access.

  Request body:
    {
      "patient_id": "string",
      "data_types": ["medical_record", "lab_result"],
      "expiration_days": 365,
      "user_id": "string"
    }

  Response: 201 Created with consent record
  """
  def grant_consent(conn, params) do
    with {:ok, consent} <- PolicyEngine.grant_consent(params) do
      conn
      |> put_status(201)
      |> json(%{
        consent_id: consent.id,
        patient_id: consent.patient_id,
        data_types: consent.data_types,
        granted_at: consent.granted_at,
        expires_at: consent.expires_at,
        message: "Consent granted successfully"
      })
    else
      {:error, :invalid_expiration} ->
        conn
        |> put_status(400)
        |> json(%{
          error: "invalid_expiration",
          message: "expiration_days must be positive"
        })

      {:error, :patient_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "patient_not_found", message: "patient does not exist"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "consent_grant_failed", message: inspect(reason)})
    end
  end

  @doc """
  Revoke patient consent for PHI access.

  Request body:
    {
      "consent_id": "string",
      "reason": "string"
    }

  Response: 200 OK
  """
  def revoke_consent(conn, params) do
    with {:ok, _result} <- PolicyEngine.revoke_consent(params) do
      conn
      |> put_status(200)
      |> json(%{
        success: true,
        consent_id: params["consent_id"],
        message: "Consent revoked successfully"
      })
    else
      {:error, :consent_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "consent_not_found", message: "consent record not found"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "consent_revocation_failed", message: inspect(reason)})
    end
  end

  # ── Private Helpers ────────────────────────────────────────────────────

  defp create_phi_audit_entry(params, current_user) do
    with :ok <- validate_data_type(params["data_type"]),
         :ok <- validate_action(params["action"]),
         :ok <- validate_required_fields(params) do
      # Create audit entry in memory or database
      audit_entry = %{
        id: generate_id(),
        patient_id: params["patient_id"],
        data_type: params["data_type"],
        action: params["action"],
        user_id: params["user_id"] || current_user.id,
        workspace_id: params["workspace_id"],
        inserted_at: DateTime.utc_now(),
        ip_address: params["ip_address"],
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {:ok, audit_entry}
    else
      error -> error
    end
  end

  defp validate_data_type(data_type) do
    valid_types = ["medical_record", "lab_result", "prescription", "imaging"]

    if data_type in valid_types do
      :ok
    else
      {:error, :invalid_data_type}
    end
  end

  defp validate_action(action) do
    valid_actions = ["read", "write", "delete"]

    if action in valid_actions do
      :ok
    else
      {:error, :invalid_action}
    end
  end

  defp validate_required_fields(params) do
    required = ["patient_id", "data_type", "action"]

    if Enum.all?(required, fn field -> Map.has_key?(params, field) && params[field] end) do
      :ok
    else
      {:error, :missing_required_fields}
    end
  end

  defp serialize_audit_entry(entry) do
    %{
      id: entry.id,
      patient_id: entry.patient_id,
      data_type: entry.data_type,
      action: entry.action,
      user_id: entry.user_id,
      timestamp: entry.timestamp,
      ip_address: entry.ip_address
    }
  end

  defp serialize_violations(violations) when is_list(violations) do
    Enum.map(violations, fn v ->
      %{
        code: v.code,
        description: v.description,
        severity: v.severity
      }
    end)
  end

  defp serialize_violations(_), do: []

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
