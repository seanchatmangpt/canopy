defmodule Canopy.Board.ConwayMonitor do
  @moduledoc """
  Conway's Law + board escalation monitor for Canopy agent routing.

  Subscribes to heartbeat routing events via Phoenix.PubSub, computes Conway
  scores per-routing-event, emits `board.conway_check` OTEL spans, and
  broadcasts `:board_escalation` events when violations are detected.

  ## Routing Logic

  **Conway violation** (score > 0.4 = boundary >40% of cycle time):
    - Structural org problem — cannot be auto-healed
    - Broadcasts `board:escalations` topic on EventBus
    - NOT passed to any auto-healing path

  ## WvdA Soundness

  - Bounded check rate: max 1_000 checks/minute via rate limiter ETS counter
    (drops excess with Logger.warning — no crash)
  - Liveness: GenServer handles events one at a time; no busy loop
  - Timeouts: GenServer.call timeouts guarded; no unbounded wait
  - ETS table: bounded by escalation cooldown dedup (one key per process_id)

  ## Armstrong Fault Tolerance

  - Registered as `:permanent` child — supervisor restarts on crash
  - No silent rescue: crashes propagate to supervisor
  - No shared mutable state: all events via PubSub message passing
  - ETS only for bounded rate-limit counter and cooldown dedup
  """

  use GenServer
  require Logger
  require OpenTelemetry.Tracer

  alias Canopy.Board.ConwayChecker
  alias OpenTelemetry.SemConv.Incubating.BoardSpanNames
  alias OpenTelemetry.SemConv.Incubating.BoardAttributes

  @board_routing_topic "canopy:board:routing"
  @board_escalations_topic "canopy:board:escalations"
  @ets_table :canopy_conway_monitor
  @escalation_cooldown_ms 30 * 60 * 1_000
  # WvdA: bounded check rate — max 1_000 per minute, resets each minute
  @max_checks_per_minute 1_000
  @rate_window_ms 60_000
  @query_timeout_ms 5_000

  # ── Public API ────────────────────────────────────────────────────────────────

  @doc "Start the ConwayMonitor GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Synchronously run a Conway check for the given boundary/cycle times.

  This is the primary interface used by heartbeat/dispatcher integration.
  Returns the ConwayChecker result map.
  """
  @spec check_routing(String.t(), non_neg_integer(), non_neg_integer()) :: map()
  def check_routing(process_id, boundary_time_ms, cycle_time_ms) do
    GenServer.call(
      __MODULE__,
      {:check_routing, process_id, boundary_time_ms, cycle_time_ms},
      @query_timeout_ms
    )
  catch
    :exit, {:timeout, _} ->
      Logger.error("[ConwayMonitor] check_routing timeout for #{process_id}")
      %{is_violation: false, conway_score: 0.0, boundary_time_ms: 0, cycle_time_ms: 0}
  end

  @doc "Publish a routing event for Conway analysis (async broadcast)."
  @spec publish_routing_event(map()) :: :ok
  def publish_routing_event(event) do
    Canopy.EventBus.broadcast(@board_routing_topic, {:routing_event, event})
  end

  @doc "Return current monitor status."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status, @query_timeout_ms)
  catch
    :exit, {:timeout, _} ->
      Logger.error("[ConwayMonitor] status query timeout")
      %{error: :timeout}
  end

  # ── GenServer Callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])
    end

    # Subscribe to routing events via EventBus (Phoenix.PubSub)
    Canopy.EventBus.subscribe(@board_routing_topic)

    Logger.info("[ConwayMonitor] Started — subscribed to #{@board_routing_topic}")

    state = %{
      checks_total: 0,
      violations_total: 0,
      escalations_sent: 0,
      last_check_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:check_routing, process_id, boundary_time_ms, cycle_time_ms}, _from, state) do
    result = do_conway_check(process_id, boundary_time_ms, cycle_time_ms)

    new_state = %{
      state
      | checks_total: state.checks_total + 1,
        violations_total: state.violations_total + if(result.is_violation, do: 1, else: 0),
        last_check_at: DateTime.utc_now()
    }

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:routing_event, event}, state) do
    process_id = Map.get(event, :process_id, "unknown")
    boundary_time_ms = Map.get(event, :boundary_time_ms, 0)
    cycle_time_ms = Map.get(event, :cycle_time_ms, 0)

    # WvdA: rate limit — drop excess checks without crash
    if within_rate_limit?() do
      _result = do_conway_check(process_id, boundary_time_ms, cycle_time_ms)
    else
      Logger.warning(
        "[ConwayMonitor] Rate limit reached (#{@max_checks_per_minute}/min), dropping check for #{process_id}"
      )
    end

    new_state = %{
      state
      | checks_total: state.checks_total + 1,
        last_check_at: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  # Run the Conway check inside an OTEL span, emit escalation if violation.
  defp do_conway_check(process_id, boundary_time_ms, cycle_time_ms) do
    span_name = BoardSpanNames.board_conway_check()

    OpenTelemetry.Tracer.with_span span_name, %{
      BoardAttributes.board_process_id() => process_id
    } do
      result = ConwayChecker.check(boundary_time_ms, cycle_time_ms)

      # Set span attributes using typed semconv constants
      OpenTelemetry.Tracer.set_attributes([
        {BoardAttributes.board_is_violation(), result.is_violation},
        {BoardAttributes.board_conway_score(), result.conway_score},
        {BoardAttributes.board_process_id(), process_id}
      ])

      if result.is_violation do
        maybe_emit_escalation(process_id, result)
      end

      result
    end
  end

  # Emit board_escalation via EventBus, deduped by cooldown window.
  defp maybe_emit_escalation(process_id, result) do
    cooldown_key = {:escalation_cooldown, process_id}
    now_ms = System.monotonic_time(:millisecond)

    should_emit =
      case :ets.lookup(@ets_table, cooldown_key) do
        [{_, last_ms}] when now_ms - last_ms < @escalation_cooldown_ms -> false
        _ -> true
      end

    if should_emit do
      :ets.insert(@ets_table, {cooldown_key, now_ms})
      pct = round(result.conway_score * 100)

      Logger.info(
        "[ConwayMonitor] Conway violation for #{process_id} " <>
          "(score=#{result.conway_score}), escalating to board"
      )

      Canopy.EventBus.broadcast(@board_escalations_topic, %{
        event: :board_escalation,
        process_id: process_id,
        escalation_type: :conway_violation,
        conway_score: result.conway_score,
        message:
          "Org boundary consuming #{pct}% of cycle time in #{process_id}. " <>
            "Requires org restructuring decision.",
        timestamp: DateTime.utc_now()
      })
    else
      Logger.debug(
        "[ConwayMonitor] Skipping duplicate escalation for #{process_id} (within cooldown)"
      )
    end
  end

  # WvdA: bounded rate — increment ETS counter, reset each minute window.
  defp within_rate_limit? do
    now_ms = System.monotonic_time(:millisecond)
    window_key = :rate_window

    case :ets.lookup(@ets_table, window_key) do
      [{_, window_start_ms, count}] when now_ms - window_start_ms < @rate_window_ms ->
        if count < @max_checks_per_minute do
          :ets.insert(@ets_table, {window_key, window_start_ms, count + 1})
          true
        else
          false
        end

      _ ->
        # New window
        :ets.insert(@ets_table, {window_key, now_ms, 1})
        true
    end
  end
end
