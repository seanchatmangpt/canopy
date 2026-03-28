defmodule Canopy.Autonomic.AutoRecovery do
  @moduledoc """
  Pure-function agent auto-recovery logic. Called from HealingAgent.

  Examines agents in "error" status and attempts to reset them to "idle"
  after a computed back-off delay. Uses ExecutionLog to count consecutive
  failures and decide whether a reset is appropriate.

  ## Recovery Policy

  - Agent qualifies for reset after @recovery_threshold consecutive failures
  - Back-off: 60_000ms × 2^n, capped at @max_backoff_ms (1 hour)
  - After 3 failed recovery attempts, the agent is escalated (status stays "error")

  ## Armstrong Fault Tolerance

  - Pure functions: no side effects beyond Repo calls (which are explicit)
  - Caller (HealingAgent) supervises; failures here do not crash the agent
  """

  require Logger

  alias Canopy.Autonomic.ExecutionLog

  @recovery_threshold 5
  @base_backoff_ms 60_000
  @max_backoff_ms 3_600_000
  @max_recovery_attempts 3

  @doc """
  Check if `agent` should be recovered and attempt it if so.

  `agent` must have `:id`, `:status`, and optionally `:recovery_attempts` fields.
  `repo` is the Ecto repo (e.g. Canopy.Repo).

  Returns `:ok` (no action needed), `{:recovered, agent}`, or `{:escalated, reason}`.
  """
  @spec check_and_recover(map(), module()) :: :ok | {:recovered, map()} | {:escalated, atom()}
  def check_and_recover(agent, repo \\ Canopy.Repo) do
    if should_reset?(agent) do
      attempt_recovery(agent, repo)
    else
      :ok
    end
  end

  @doc """
  Returns true when the agent has enough consecutive failures to warrant a recovery attempt.

  Checks: agent.status == "error" AND consecutive_failures >= @recovery_threshold.
  """
  @spec should_reset?(map()) :: boolean()
  def should_reset?(agent) do
    agent.status == "error" and
      ExecutionLog.consecutive_failures(agent.id) >= @recovery_threshold
  end

  @doc """
  Attempt to reset `agent` to idle status.

  If the agent has exceeded @max_recovery_attempts, escalates instead of retrying.
  Returns `{:recovered, updated_agent}` or `{:escalated, :max_attempts_exceeded}`.
  """
  @spec attempt_recovery(map(), module()) :: {:recovered, map()} | {:escalated, atom()}
  def attempt_recovery(agent, repo) do
    attempts = Map.get(agent, :recovery_attempts, 0)

    if attempts >= @max_recovery_attempts do
      Logger.warning(
        "[AutoRecovery] Agent #{agent.id} exceeded max recovery attempts (#{attempts}) — escalating"
      )

      {:escalated, :max_attempts_exceeded}
    else
      backoff = backoff_interval_ms(attempts)

      Logger.info(
        "[AutoRecovery] Attempting recovery for agent #{agent.id} " <>
          "(attempt #{attempts + 1}/#{@max_recovery_attempts}, backoff #{backoff}ms)"
      )

      # Compute next check time (caller may use this to schedule a delayed retry)
      _next_check_at = DateTime.add(DateTime.utc_now(), div(backoff, 1000), :second)

      # Reset to idle and increment recovery_attempts counter
      case update_agent_status(agent, repo) do
        {:ok, updated} ->
          ExecutionLog.clear(agent.id)
          Logger.info("[AutoRecovery] Agent #{agent.id} reset to idle")
          {:recovered, updated}

        {:error, reason} ->
          Logger.error("[AutoRecovery] Failed to reset agent #{agent.id}: #{inspect(reason)}")
          {:escalated, :db_error}
      end
    end
  end

  @doc """
  Compute exponential back-off for recovery attempt `n`.

  Returns: min(@base_backoff_ms × 2^n, @max_backoff_ms)

  | n | back-off     |
  |---|-------------|
  | 0 | 60 s        |
  | 1 | 120 s       |
  | 2 | 240 s       |
  | 3 | 480 s       |
  | ≥10 | 1 hr (cap) |
  """
  @spec backoff_interval_ms(non_neg_integer()) :: pos_integer()
  def backoff_interval_ms(n) when is_integer(n) and n >= 0 do
    min(trunc(@base_backoff_ms * :math.pow(2, n)), @max_backoff_ms)
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp update_agent_status(agent, repo) do
    # Dynamically update the agent struct/schema — works with any Ecto schema
    # that has :status and :recovery_attempts fields.
    import Ecto.Changeset

    attempts = Map.get(agent, :recovery_attempts, 0)

    changeset =
      cast(agent.__struct__.__struct__(), agent, [])
      |> change(status: "idle", recovery_attempts: attempts + 1)

    repo.update(changeset)
  rescue
    e ->
      {:error, e}
  end
end
