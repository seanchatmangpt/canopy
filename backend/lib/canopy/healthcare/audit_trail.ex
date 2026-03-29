defmodule Canopy.Healthcare.AuditTrail do
  @moduledoc """
  Healthcare Audit Trail — logs and retrieves all PHI access and healthcare operations for compliance.

  HIPAA Audit Trail Requirements:
    - Log all PHI access (read, write, delete)
    - Include user, timestamp, data type, action, IP address
    - Retention: 6+ years per HIPAA standards
    - Tamper-proof (append-only log)
    - Query audit logs within 24 hours
  """

  require Logger

  @doc """
  Fetch audit trail entries for a patient.

  Parameters:
    - patient_id (required)
    - limit (optional, default 100)
    - offset (optional, default 0)
    - date_from (optional): ISO8601 timestamp
    - date_to (optional): ISO8601 timestamp
    - action (optional): Filter by action (read, write, delete)

  Returns:
    {:ok, list_of_entries}
    {:error, reason}
  """
  def fetch(params) do
    patient_id = params["patient_id"]
    limit = String.to_integer(params["limit"] || "100")
    offset = String.to_integer(params["offset"] || "0")
    date_from = params["date_from"]
    date_to = params["date_to"]
    action_filter = params["action"]

    with :ok <- validate_patient_id(patient_id),
         :ok <- validate_date_range(date_from, date_to),
         entries <- query_audit_entries(patient_id, date_from, date_to, action_filter),
         filtered <- Enum.drop(entries, offset),
         limited <- Enum.take(filtered, limit) do
      {:ok, limited}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Log a PHI access event to the audit trail.

  Parameters:
    - patient_id: Patient identifier
    - action: read|write|delete
    - data_type: medical_record|lab_result|prescription|imaging
    - user_id: User performing action
    - user_role: Role of user (admin, healthcare_provider, staff, etc.)
    - ip_address: IP address of requester
    - timestamp: When access occurred
    - changes (optional): For write operations, what was changed

  Returns:
    {:ok, audit_entry}
    {:error, reason}
  """
  def log_access(params) do
    audit_entry = %{
      id: generate_id(),
      patient_id: params["patient_id"],
      action: params["action"],
      data_type: params["data_type"],
      user_id: params["user_id"],
      user_role: params["user_role"],
      ip_address: params["ip_address"],
      timestamp: params["timestamp"] || DateTime.utc_now(),
      changes: params["changes"],
      status: "logged"
    }

    # Append to append-only log (cannot be modified after creation)
    persist_audit_entry(audit_entry)

    Logger.info(
      "[Healthcare Audit] PHI access: patient=#{audit_entry.patient_id}, " <>
        "action=#{audit_entry.action}, user=#{audit_entry.user_id}, " <>
        "data_type=#{audit_entry.data_type}"
    )

    {:ok, audit_entry}
  end

  @doc """
  Generate audit trail report for compliance review.

  Parameters:
    - patient_id (optional): Filter to single patient
    - date_from (required): Report start date
    - date_to (required): Report end date

  Returns:
    {:ok, %{
      total_entries: integer,
      report_period: {date_from, date_to},
      access_by_user: map,
      access_by_action: map,
      access_by_data_type: map,
      suspicious_activity: list
    }}
  """
  def generate_report(params) do
    date_from = params["date_from"]
    date_to = params["date_to"]
    patient_id = params["patient_id"]

    with :ok <- validate_date_range(date_from, date_to),
         entries <- query_audit_entries(patient_id, date_from, date_to, nil) do
      {:ok,
       %{
         total_entries: Enum.count(entries),
         report_period: {date_from, date_to},
         access_by_user: summarize_by_user(entries),
         access_by_action: summarize_by_action(entries),
         access_by_data_type: summarize_by_data_type(entries),
         suspicious_activity: detect_suspicious_activity(entries)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a specific PHI access is in the audit trail.

  Parameters:
    - patient_id
    - user_id
    - action
    - timestamp_within_seconds (optional, default 60)

  Returns:
    {:ok, true | false}
  """
  def has_access_record?(params) do
    patient_id = params["patient_id"]
    user_id = params["user_id"]
    action = params["action"]
    tolerance_seconds = params["tolerance_seconds"] || 60

    now = DateTime.utc_now()
    timestamp_from = DateTime.add(now, -tolerance_seconds)

    entries = query_audit_entries(patient_id, timestamp_from, now, action)

    has_matching_user = Enum.any?(entries, fn e -> e.user_id == user_id end)

    {:ok, has_matching_user}
  end

  # ── Private Helpers ────────────────────────────────────────────────────

  defp validate_patient_id(patient_id) do
    if patient_id && String.length(patient_id) > 0,
      do: :ok,
      else: {:error, :patient_not_found}
  end

  defp validate_date_range(date_from, date_to) do
    cond do
      !date_from and !date_to -> :ok
      !date_from or !date_to -> {:error, :invalid_date_range}
      parse_datetime(date_from) && parse_datetime(date_to) -> :ok
      true -> {:error, :invalid_date_range}
    end
  end

  defp parse_datetime(datetime_str) do
    DateTime.from_iso8601(datetime_str)
    |> case do
      {:ok, _dt, _offset} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp query_audit_entries(patient_id, date_from, date_to, action_filter) do
    # In production: query from database or append-only log store
    # For now: return mock entries

    {:ok, dt_from, _} =
      if date_from, do: DateTime.from_iso8601(date_from), else: {:ok, DateTime.utc_now(), 0}

    {:ok, dt_to, _} =
      if date_to, do: DateTime.from_iso8601(date_to), else: {:ok, DateTime.utc_now(), 0}

    # Generate mock audit entries
    [
      %{
        id: "audit_001",
        patient_id: patient_id,
        action: "read",
        data_type: "medical_record",
        user_id: "provider_123",
        user_role: "healthcare_provider",
        ip_address: "192.168.1.100",
        timestamp: DateTime.add(dt_from, 3600),
        status: "logged"
      },
      %{
        id: "audit_002",
        patient_id: patient_id,
        action: "read",
        data_type: "lab_result",
        user_id: "lab_staff_456",
        user_role: "staff",
        ip_address: "192.168.1.101",
        timestamp: DateTime.add(dt_from, 7200),
        status: "logged"
      },
      %{
        id: "audit_003",
        patient_id: patient_id,
        action: "write",
        data_type: "medical_record",
        user_id: "provider_123",
        user_role: "healthcare_provider",
        ip_address: "192.168.1.100",
        timestamp: DateTime.add(dt_from, 10800),
        status: "logged"
      }
    ]
    |> filter_by_date(dt_from, dt_to)
    |> filter_by_action(action_filter)
  end

  defp filter_by_date(entries, date_from, date_to) do
    Enum.filter(entries, fn e ->
      DateTime.compare(e.timestamp, date_from) in [:gt, :eq] &&
        DateTime.compare(e.timestamp, date_to) in [:lt, :eq]
    end)
  end

  defp filter_by_action(entries, nil), do: entries

  defp filter_by_action(entries, action) do
    Enum.filter(entries, fn e -> e.action == action end)
  end

  defp summarize_by_user(entries) do
    entries
    |> Enum.group_by(fn e -> e.user_id end)
    |> Enum.map(fn {user_id, user_entries} ->
      {user_id,
       %{
         access_count: Enum.count(user_entries),
         last_access: Enum.max_by(user_entries, fn e -> e.timestamp end).timestamp,
         actions: Enum.map(user_entries, fn e -> e.action end) |> Enum.uniq()
       }}
    end)
    |> Enum.into(%{})
  end

  defp summarize_by_action(entries) do
    entries
    |> Enum.group_by(fn e -> e.action end)
    |> Enum.map(fn {action, action_entries} ->
      {action, Enum.count(action_entries)}
    end)
    |> Enum.into(%{})
  end

  defp summarize_by_data_type(entries) do
    entries
    |> Enum.group_by(fn e -> e.data_type end)
    |> Enum.map(fn {data_type, type_entries} ->
      {data_type, Enum.count(type_entries)}
    end)
    |> Enum.into(%{})
  end

  defp detect_suspicious_activity(_entries) do
    # Detect patterns:
    # 1. Multiple failed access attempts
    # 2. Access by unusual users
    # 3. Bulk data reads
    # 4. Late-night access
    # 5. Access from unusual IP addresses

    # For now, return empty list (in production: implement sophisticated detection)
    []
  end

  defp persist_audit_entry(audit_entry) do
    # In production: write to append-only log (cannot be modified)
    # Options:
    #   1. Database table with unique IDs, no UPDATE allowed
    #   2. Event store (append-only log)
    #   3. Distributed ledger
    Logger.debug("[Healthcare Audit] Entry persisted: #{audit_entry.id}")
    :ok
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
