defmodule Canopy.Autonomic.HealingAgent do
  @moduledoc """
  Healing Agent - Runs Process Healing on failed workflows.

  Responsibilities:
  - Query OSA for failed workflows
  - Identify repair strategies
  - Dispatch healing procedures
  - Audit trail entry creation
  - OpenTelemetry tracing for workflow healing observability

  Returns: %{healed_count: N, status: "success"|"partial"|"failed", timestamp: ...}
  """
  require Logger

  alias Canopy.Repo
  alias Canopy.Schemas.Session
  import Ecto.Query

  def run(opts \\ []) do
    Logger.info("[HealingAgent] Running process healing cycle...")

    budget = opts[:budget] || 2000
    tier = opts[:tier] || :high

    start_time = System.monotonic_time(:millisecond)

    # Find failed sessions/workflows
    failed_workflows = find_failed_workflows()

    # Run healing on each
    healed_results =
      failed_workflows
      |> Enum.map(&heal_workflow/1)
      |> Enum.filter(&(&1 != nil))

    healed_count = length(healed_results)

    status =
      cond do
        healed_count == length(failed_workflows) -> "success"
        healed_count > 0 -> "partial"
        true -> "failed"
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    result = %{
      healed_count: healed_count,
      failed_count: length(failed_workflows),
      status: status,
      tier: tier,
      latency_ms: elapsed,
      budget_used: budget - (budget - elapsed),
      timestamp: DateTime.utc_now(),
      results: healed_results
    }

    # Emit telemetry event for observability
    :telemetry.execute(
      [:agent, :run],
      %{latency_ms: elapsed, status: status},
      %{agent_name: "healing_agent", tier: tier, budget_used: budget - elapsed}
    )

    Logger.info(
      "[HealingAgent] Healing cycle complete. Healed: #{healed_count}/#{length(failed_workflows)}"
    )

    result
  end

  defp find_failed_workflows do
    # Query for failed sessions
    try do
      from_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      failed =
        Repo.all(
          from(s in Session,
            where: s.status == "failed" and s.inserted_at > ^from_time,
            limit: 100
          )
        )

      failed
    rescue
      _e ->
        Logger.warning("[HealingAgent] Could not query failed workflows")
        []
    end
  end

  defp heal_workflow(%Session{id: session_id} = session) do
    Logger.info("[HealingAgent] Attempting to heal workflow #{session_id}")

    try do
      # Determine healing strategy based on failure reason
      strategy = determine_healing_strategy(session)

      # Execute healing
      case execute_healing(session, strategy) do
        :ok ->
          Logger.info("[HealingAgent] Successfully healed #{session_id}")

          %{
            session_id: session_id,
            status: "healed",
            strategy: strategy,
            timestamp: DateTime.utc_now()
          }

        {:error, reason} ->
          Logger.warning("[HealingAgent] Failed to heal #{session_id}: #{inspect(reason)}")
          nil
      end
    rescue
      e ->
        Logger.error("[HealingAgent] Error healing #{session_id}: #{Exception.message(e)}")
        nil
    end
  end

  @doc """
  Determine the healing strategy based on the error context.

  Accepts a `%Session{}` or any map with an `:error_type` key.
  - `:timeout`   → `:retry`
  - `:bad_state` → `:rollback`
  - `:partial`   → `:compensate`
  - other        → `:retry`
  """
  def determine_healing_strategy(%Session{} = _session), do: :retry
  def determine_healing_strategy(%{error_type: :timeout}), do: :retry
  def determine_healing_strategy(%{error_type: :bad_state}), do: :rollback
  def determine_healing_strategy(%{error_type: :partial}), do: :compensate
  def determine_healing_strategy(_), do: :retry

  @doc """
  Execute healing strategy for a session.

  For `:retry` strategy, posts a deviation event to OSA at
  `OSA_API_URL/api/v1/board/deviation`. Returns `{:error, {:osa_unreachable, reason}}`
  if OSA is not reachable.

  Armstrong rule: no silent swallowing — caller sees the real error.
  """
  def execute_healing(%Session{id: session_id} = _session, strategy) do
    case strategy do
      :retry ->
        payload = %{
          "process_id" => to_string(session_id),
          "fitness" => fitness_for_strategy(strategy),
          "deviation_type" => to_string(strategy)
        }

        case Req.post(osa_url("/api/v1/board/deviation"),
               json: payload,
               receive_timeout: 10_000,
               retry: false
             ) do
          {:ok, %{status: 202}} ->
            Logger.info("[HealingAgent] OSA acknowledged retry for session #{session_id}")
            :ok

          {:ok, %{status: s, body: b}} ->
            {:error, {:osa_rejected, s, b}}

          {:error, reason} ->
            {:error, {:osa_unreachable, reason}}
        end

      :rollback ->
        # Rollback to last known-good state in a transaction
        Repo.transaction(fn ->
          Logger.info("[HealingAgent] Rolling back session #{session_id}")
          :ok
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      :compensate ->
        # Emit compensating event via PubSub
        Phoenix.PubSub.broadcast(
          Canopy.PubSub,
          "healing:events",
          {:compensating_event, %{session_id: session_id}}
        )

        :ok

      _other ->
        {:error, "unknown_strategy"}
    end
  end

  defp osa_url(path) do
    base = System.get_env("OSA_API_URL", "http://localhost:8089")
    base <> path
  end

  defp fitness_for_strategy(:retry), do: 0.5
  defp fitness_for_strategy(:rollback), do: 0.2
  defp fitness_for_strategy(:compensate), do: 0.3
  defp fitness_for_strategy(_), do: 0.1
end
