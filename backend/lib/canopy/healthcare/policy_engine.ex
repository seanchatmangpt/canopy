defmodule Canopy.Healthcare.PolicyEngine do
  @moduledoc """
  Healthcare Policy Engine — manages consent workflows, HIPAA compliance checks, and healthcare data policies.

  Key responsibilities:
    1. Load and evaluate consent policies
    2. Grant/revoke patient consent
    3. Verify HIPAA compliance
    4. Manage healthcare data access rules
    5. Track policy changes in audit trail

  Standards: HIPAA, HITECH Act, State privacy laws
  """

  require Logger

  @default_consent_days 365
  @supported_operations ["patient_access", "data_breach", "encryption", "access_control"]
  @supported_data_types [
    "medical_record",
    "lab_result",
    "prescription",
    "imaging",
    "dental",
    "mental_health"
  ]

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Load a consent policy from storage or configuration.

  Returns:
    {:ok, policy} — Policy loaded successfully
    {:error, :not_found} — Policy not found
  """
  def load_policy(policy_id) do
    case fetch_policy(policy_id) do
      nil -> {:error, :not_found}
      policy -> {:ok, policy}
    end
  end

  @doc """
  Evaluate whether a patient's consent grants access to requested data.

  Parameters:
    - patient_id: Patient identifier
    - user_id: Healthcare provider or staff member
    - data_type: Type of data being accessed (medical_record, lab_result, etc.)

  Returns:
    {:ok, %{granted: boolean, expiration: datetime, reason: string}}
    {:error, reason}
  """
  def verify_consent(params) do
    patient_id = params["patient_id"]
    user_id = params["user_id"]
    data_type = params["data_type"]

    with :ok <- validate_consent_params(patient_id, data_type),
         {:ok, consent} <- fetch_consent(patient_id, data_type) do
      {:ok,
       %{
         patient_id: patient_id,
         user_id: user_id,
         data_type: data_type,
         granted: consent.status == "active" && !consent_expired?(consent),
         expiration: consent.expires_at,
         reason: if(consent_expired?(consent), do: "expired", else: "valid")
       }}
    else
      {:error, :no_consent} ->
        {:error, :no_consent}

      {:error, :consent_expired} ->
        {:error, :consent_expired}

      error ->
        error
    end
  end

  @doc """
  Grant patient consent for PHI access.

  Parameters:
    - patient_id: Patient identifier
    - data_types: List of data types allowed (medical_record, lab_result, etc.)
    - expiration_days: Days until consent expires (default: 365)
    - user_id: Healthcare provider granting consent

  Returns:
    {:ok, consent_record}
    {:error, reason}
  """
  def grant_consent(params) do
    patient_id = params["patient_id"]
    data_types = params["data_types"] || [@supported_data_types]
    expiration_days = params["expiration_days"] || @default_consent_days
    user_id = params["user_id"]

    with :ok <- validate_patient_id(patient_id),
         :ok <- validate_data_types(data_types),
         :ok <- validate_expiration_days(expiration_days) do
      consent = %{
        id: generate_id(),
        patient_id: patient_id,
        data_types: List.flatten([data_types]),
        granted_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), expiration_days * 86400),
        granted_by: user_id,
        status: "active"
      }

      # Persist to cache (in production, use database)
      store_consent(consent)

      Logger.info(
        "[Healthcare] Consent granted for patient #{patient_id}, types: #{inspect(data_types)}"
      )

      {:ok, consent}
    else
      {:error, :invalid_expiration} -> {:error, :invalid_expiration}
      {:error, :invalid_data_types} -> {:error, :invalid_data_types}
      {:error, :patient_not_found} -> {:error, :patient_not_found}
      error -> error
    end
  end

  @doc """
  Revoke patient consent for PHI access.

  Parameters:
    - consent_id: Consent record identifier
    - reason: Reason for revocation

  Returns:
    {:ok, result}
    {:error, reason}
  """
  def revoke_consent(params) do
    consent_id = params["consent_id"]
    reason = params["reason"] || "no reason provided"

    case fetch_consent_by_id(consent_id) do
      nil ->
        {:error, :consent_not_found}

      consent ->
        revoked_consent = consent |> Map.put(:status, "revoked") |> Map.put(:revoked_at, DateTime.utc_now())
        store_consent(revoked_consent)

        Logger.info("[Healthcare] Consent revoked: #{consent_id}, reason: #{reason}")

        {:ok, %{consent_id: consent_id, revoked_at: DateTime.utc_now(), reason: reason}}
    end
  end

  @doc """
  Verify HIPAA compliance for a specific healthcare operation.

  Parameters:
    - operation: Operation type (patient_access, data_breach, encryption, access_control)
    - parameters: Operation-specific parameters

  Returns:
    {:ok, %{compliant: boolean, checks_passed: list, checks_failed: list, violations: list}}
    {:error, reason}
  """
  def verify_hipaa_compliance(params) do
    operation = params["operation"]
    operation_params = params["parameters"] || %{}

    with :ok <- validate_operation(operation) do
      checks = run_compliance_checks(operation, operation_params)

      checks_passed = Enum.filter(checks, fn c -> c.passed end)
      checks_failed = Enum.filter(checks, fn c -> !c.passed end)
      violations = Enum.filter(checks_failed, fn c -> c.severity == "critical" end)

      {:ok,
       %{
         operation: operation,
         passed: Enum.empty?(violations),
         checks_passed: Enum.map(checks_passed, & &1.name),
         checks_failed: Enum.map(checks_failed, & &1.name),
         violations: Enum.map(violations, &serialize_violation/1)
       }}
    else
      {:error, :invalid_operation} -> {:error, :invalid_operation}
      error -> error
    end
  end

  @doc """
  Evaluate a policy against specific healthcare conditions.

  Parameters:
    - policy: Policy record or policy_id
    - context: Evaluation context (patient_id, user_role, data_type, etc.)

  Returns:
    {:ok, %{allowed: boolean, reason: string}}
    {:error, reason}
  """
  def evaluate_policy(policy, context) do
    with {:ok, policy} <- ensure_policy(policy) do
      allow? = check_policy_rules(policy, context)

      {:ok, %{allowed: allow?, policy_id: policy.id, context: context}}
    else
      error -> error
    end
  end

  # ── Private Helpers ────────────────────────────────────────────────────

  defp validate_consent_params(patient_id, data_type) do
    cond do
      !patient_id -> {:error, :missing_patient_id}
      !data_type -> {:error, :missing_data_type}
      data_type not in @supported_data_types -> {:error, :invalid_data_type}
      true -> :ok
    end
  end

  defp validate_patient_id(patient_id) do
    if patient_id && String.length(patient_id) > 0, do: :ok, else: {:error, :patient_not_found}
  end

  defp validate_data_types(data_types) do
    if is_list(data_types) && Enum.all?(data_types, fn t -> t in @supported_data_types end) do
      :ok
    else
      {:error, :invalid_data_types}
    end
  end

  defp validate_expiration_days(days) do
    if is_number(days) && days > 0, do: :ok, else: {:error, :invalid_expiration}
  end

  defp validate_operation(operation) do
    if operation in @supported_operations, do: :ok, else: {:error, :invalid_operation}
  end

  defp consent_expired?(consent) do
    DateTime.compare(DateTime.utc_now(), consent.expires_at) == :gt
  end

  defp run_compliance_checks(_operation, params) do
    [
      check_encryption(params),
      check_access_control(params),
      check_audit_logging(params),
      check_data_minimization(params),
      check_retention_policy(params)
    ]
  end

  defp check_encryption(params) do
    %{
      name: "encryption",
      passed: params["encryption_enabled"] == true,
      severity: "critical",
      message: "Data must be encrypted at rest and in transit"
    }
  end

  defp check_access_control(params) do
    %{
      name: "access_control",
      passed: params["role_based_access"] == true,
      severity: "critical",
      message: "Role-based access control must be enforced"
    }
  end

  defp check_audit_logging(params) do
    %{
      name: "audit_logging",
      passed: params["audit_enabled"] == true,
      severity: "critical",
      message: "All PHI access must be logged and auditable"
    }
  end

  defp check_data_minimization(params) do
    %{
      name: "data_minimization",
      passed: params["data_minimization"] == true,
      severity: "high",
      message: "Only necessary PHI should be accessed"
    }
  end

  defp check_retention_policy(params) do
    %{
      name: "retention_policy",
      passed: params["retention_configured"] == true,
      severity: "high",
      message: "Data retention policy must be defined"
    }
  end

  defp serialize_violation(violation) do
    %{
      code: violation.name,
      description: violation.message,
      severity: violation.severity
    }
  end

  defp check_policy_rules(_policy, context) do
    user_role = context["user_role"] || "user"
    data_type = context["data_type"]

    # Simplified rule evaluation
    # In production: load rules from database and evaluate systematically
    user_role in ["admin", "healthcare_provider"] && data_type in @supported_data_types
  end

  defp ensure_policy(policy) when is_map(policy), do: {:ok, policy}
  defp ensure_policy(policy_id), do: load_policy(policy_id)

  # ── Storage Layer (In-Memory Cache) ────────────────────────────────

  defp fetch_consent(patient_id, data_type) do
    try do
      case Agent.get(Application.get_env(:canopy, :consent_agent, nil), fn state ->
             Map.get(state, {patient_id, data_type})
           end) do
        nil ->
          {:error, :no_consent}

        consent ->
          if consent_expired?(consent) do
            {:error, :consent_expired}
          else
            {:ok, consent}
          end
      end
    rescue
      _ -> {:error, :no_consent}
    end
  end

  defp fetch_consent_by_id(consent_id) do
    Agent.get(Application.get_env(:canopy, :consent_agent, nil), fn state ->
      Enum.find(Map.values(state), fn c -> c.id == consent_id end)
    end)
  rescue
    _ -> nil
  end

  defp store_consent(consent) do
    Agent.update(Application.get_env(:canopy, :consent_agent, nil), fn state ->
      Map.put(state, {consent.patient_id, List.first(consent.data_types)}, consent)
    end)
  rescue
    _ -> :ok
  end

  defp fetch_policy(policy_id) do
    # In production: fetch from database or distributed cache
    default_policies = %{
      "hipaa_standard" => %{
        id: "hipaa_standard",
        name: "HIPAA Standard",
        rules: [
          %{rule: "encryption_required", severity: "critical"},
          %{rule: "audit_logging_required", severity: "critical"},
          %{rule: "access_control_required", severity: "critical"}
        ]
      }
    }

    Map.get(default_policies, policy_id)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
