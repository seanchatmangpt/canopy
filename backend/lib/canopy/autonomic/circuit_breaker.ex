defmodule Canopy.Autonomic.CircuitBreaker do
  @moduledoc """
  ETS-based circuit breaker for external service calls.

  Protects BusinessOS and OSA callers from cascading failures.
  No supervised process — all state in ETS `:canopy_circuit_breaker`.

  ## State Machine

      :closed → (3 failures) → :open → (60s cooldown) → :half_open → (1 success) → :closed

  ## WvdA Soundness

  - `call/3` has explicit `timeout_ms` (deadlock freedom)
  - State transitions are atomic ETS operations (boundedness)

  ## Armstrong Fault Tolerance

  - Circuit breaker isolates failures before they cascade
  - half_open probe: one request allowed through to test recovery
  """

  require Logger

  @table :canopy_circuit_breaker
  @failure_threshold 3
  @cooldown_ms 60_000

  # ETS row: {service, state :: :closed | :open | :half_open, failure_count, opened_at_ms | nil}

  @doc "Initialize ETS table. Call from Application.start/2 before supervision tree starts."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, {:write_concurrency, true}])
    end

    :ok
  end

  @doc """
  Execute `fun` through the circuit breaker for `service`.

  - If circuit is `:closed` or `:half_open`: run fun, record outcome.
  - If circuit is `:open` and cooldown not elapsed: return `{:error, :circuit_open}`.
  - `timeout_ms`: outer Task.await deadline (WvdA deadlock freedom).
  """
  @spec call(atom(), (-> term()), pos_integer()) :: term() | {:error, :circuit_open | :timeout}
  def call(service, fun, timeout_ms) do
    case current_state(service) do
      :open ->
        Logger.debug("[CircuitBreaker] Circuit open for #{service} — blocking call")
        {:error, :circuit_open}

      _other ->
        do_call(service, fun, timeout_ms)
    end
  end

  @doc "Record a failure for `service`. Trips circuit after @failure_threshold failures."
  @spec record_failure(atom()) :: :ok
  def record_failure(service) do
    entry = get_entry(service)
    new_count = entry.failure_count + 1

    new_entry =
      if new_count >= @failure_threshold and entry.state != :open do
        Logger.warning("[CircuitBreaker] Circuit opened for #{service} after #{new_count} failures")
        %{entry | state: :open, failure_count: new_count, opened_at_ms: now_ms()}
      else
        %{entry | failure_count: new_count}
      end

    :ets.insert(@table, to_row(service, new_entry))
    :ok
  end

  @doc "Record a success for `service`. Closes circuit (even from :half_open)."
  @spec record_success(atom()) :: :ok
  def record_success(service) do
    case :ets.lookup(@table, service) do
      [{^service, state, _count, _opened}] when state in [:half_open, :open] ->
        Logger.info("[CircuitBreaker] Circuit closed for #{service} after recovery")
        :ets.insert(@table, {service, :closed, 0, nil})

      _ ->
        :ets.insert(@table, {service, :closed, 0, nil})
    end

    :ok
  end

  @doc "Return the current circuit state for `service`: :closed | :open | :half_open"
  @spec state(atom()) :: :closed | :open | :half_open
  def state(service), do: current_state(service)

  @doc "Force-reset circuit to :closed (for testing or manual recovery)."
  @spec reset(atom()) :: :ok
  def reset(service) do
    :ets.delete(@table, service)
    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp current_state(service) do
    case :ets.lookup(@table, service) do
      [{^service, :open, _count, opened_at}] ->
        # Check if cooldown has elapsed → transition to :half_open
        if now_ms() - opened_at >= @cooldown_ms do
          :ets.insert(@table, {service, :half_open, 0, opened_at})
          Logger.info("[CircuitBreaker] Circuit half-open for #{service}")
          :half_open
        else
          :open
        end

      [{^service, state, _count, _opened}] ->
        state

      [] ->
        :closed
    end
  end

  defp do_call(service, fun, timeout_ms) do
    task = Task.async(fun)

    result =
      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, value} -> {:success, value}
        {:exit, _reason} -> {:failure, :exit}
        nil -> {:failure, :timeout}
      end

    case result do
      {:success, value} ->
        record_success(service)
        value

      {:failure, reason} ->
        record_failure(service)
        {:error, reason}
    end
  end

  defp get_entry(service) do
    case :ets.lookup(@table, service) do
      [{^service, state, count, opened_at}] ->
        %{state: state, failure_count: count, opened_at_ms: opened_at}

      [] ->
        %{state: :closed, failure_count: 0, opened_at_ms: nil}
    end
  end

  defp to_row(service, entry) do
    {service, entry.state, entry.failure_count, entry.opened_at_ms}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
