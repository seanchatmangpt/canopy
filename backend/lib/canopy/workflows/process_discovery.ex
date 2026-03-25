defmodule Canopy.Workflows.ProcessDiscovery do
  @moduledoc """
  Process discovery workflow for Canopy.

  Orchestrates the discovery of process models from event logs using pm4py-rust.

  State machine:
    pending → discovering → discovered/failed
    failed → retrying → discovered/failed (with exponential backoff)

  Integrates with:
    - Canopy.Adapters.PM4pyRust (discovery engine)
    - Canopy.Repo (persistence)
    - Canopy.EventBus (event broadcasting)
  """

  use GenServer

  require Logger

  # ── Types ───────────────────────────────────────────────────────────

  @type state ::
          :pending
          | :discovering
          | :discovered
          | :failed
          | :retrying

  @type discovery_config :: %{
    event_log: map(),
    algorithm: String.t(),
    max_retries: non_neg_integer(),
    url: String.t(),
    timeout: non_neg_integer()
  }

  @type workflow_state :: %{
    workflow_id: String.t(),
    state: state(),
    config: discovery_config(),
    result: map() | nil,
    error: String.t() | nil,
    retry_count: non_neg_integer(),
    started_at: DateTime.t(),
    completed_at: DateTime.t() | nil
  }

  # ── Client API ──────────────────────────────────────────────────────

  @doc """
  Start a new process discovery workflow.

  Returns {:ok, workflow_id} or {:error, reason}
  """
  def start_discovery(event_log, algorithm \\ "alpha", config \\ %{}) do
    workflow_id = Ecto.UUID.generate()

    config = Map.merge(
      %{
        "event_log" => event_log,
        "algorithm" => algorithm,
        "max_retries" => 3,
        "url" => System.get_env("PM4PY_RUST_URL", "http://127.0.0.1:8000"),
        "timeout" => 30_000
      },
      config
    )

    case start_link({workflow_id, config}) do
      {:ok, _pid} ->
        Logger.info("[ProcessDiscovery] Started workflow #{workflow_id}")
        {:ok, workflow_id}

      {:error, reason} ->
        Logger.error("[ProcessDiscovery] Failed to start workflow: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get current state of a discovery workflow.
  """
  def get_state(workflow_id) do
    try do
      state = GenServer.call(workflow_registry_lookup(workflow_id), :get_state, 5_000)
      {:ok, state}
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  @doc """
  Wait for workflow to complete with optional timeout.
  """
  def wait_for_completion(workflow_id, timeout \\ 120_000) do
    start_time = System.monotonic_time(:millisecond)

    Enum.reduce_while(Stream.interval(500), nil, fn _,  _ ->
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed > timeout do
        {:halt, {:error, :timeout}}
      else
        case get_state(workflow_id) do
          {:ok, %{state: :discovered, result: result}} ->
            {:halt, {:ok, result}}

          {:ok, %{state: :failed, error: error}} ->
            {:halt, {:error, {:discovery_failed, error}}}

          _ ->
            {:cont, nil}
        end
      end
    end)
  end

  @doc """
  Cancel a running discovery workflow.
  """
  def cancel(workflow_id) do
    case GenServer.call(workflow_registry_lookup(workflow_id), :cancel, 5_000) do
      :ok -> {:ok, workflow_id}
      error -> {:error, error}
    end
  end

  # ── GenServer ───────────────────────────────────────────────────────

  def start_link({workflow_id, config}) do
    GenServer.start_link(__MODULE__, {workflow_id, config}, name: workflow_name(workflow_id))
  end

  @impl true
  def init({workflow_id, config}) do
    Process.send_after(self(), :start_discovery, 100)

    state = %{
      workflow_id: workflow_id,
      state: :pending,
      config: config,
      result: nil,
      error: nil,
      retry_count: 0,
      started_at: DateTime.utc_now(),
      completed_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:start_discovery, state) do
    Logger.debug("[ProcessDiscovery] Starting discovery for #{state.workflow_id}")

    new_state = %{state | state: :discovering}
    broadcast_state_change(new_state)

    Process.send_after(self(), :perform_discovery, 100)

    {:noreply, new_state}
  end

  def handle_info(:perform_discovery, state) do
    case perform_discovery(state.config) do
      {:ok, model} ->
        Logger.info("[ProcessDiscovery] Discovery succeeded for #{state.workflow_id}")

        completed_state = %{
          state
          | state: :discovered,
            result: model,
            completed_at: DateTime.utc_now()
        }

        broadcast_state_change(completed_state)
        broadcast_completion_event(completed_state)

        {:noreply, completed_state}

      {:error, reason} ->
        handle_discovery_error(state, reason)
    end
  end

  def handle_info(:retry_discovery, state) do
    case perform_discovery(state.config) do
      {:ok, model} ->
        Logger.info("[ProcessDiscovery] Retry succeeded for #{state.workflow_id}")

        completed_state = %{
          state
          | state: :discovered,
            result: model,
            completed_at: DateTime.utc_now()
        }

        broadcast_state_change(completed_state)
        broadcast_completion_event(completed_state)

        {:noreply, completed_state}

      {:error, reason} ->
        handle_discovery_error(state, reason)
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:cancel, _from, state) do
    Logger.info("[ProcessDiscovery] Cancelling workflow #{state.workflow_id}")

    cancelled_state = %{
      state
      | state: :failed,
        error: "Cancelled by user",
        completed_at: DateTime.utc_now()
    }

    broadcast_state_change(cancelled_state)

    {:reply, :ok, cancelled_state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp perform_discovery(config) do
    Logger.debug("[ProcessDiscovery] Calling pm4py-rust discovery...")

    Canopy.Adapters.PM4pyRust.discover(
      config["event_log"],
      config["algorithm"],
      %{
        "url" => config["url"],
        "timeout" => config["timeout"]
      }
    )
  end

  defp handle_discovery_error(state, reason) do
    max_retries = state.config["max_retries"] || 3
    retry_count = state.retry_count + 1

    if retry_count < max_retries do
      # Schedule retry with exponential backoff
      backoff_ms = min(1000 * Integer.pow(2, retry_count - 1), 30_000)

      Logger.warning(
        "[ProcessDiscovery] Discovery failed for #{state.workflow_id}, " <>
        "retrying in #{backoff_ms}ms (attempt #{retry_count}/#{max_retries}): #{inspect(reason)}"
      )

      new_state = %{state | state: :retrying, retry_count: retry_count}
      broadcast_state_change(new_state)

      Process.send_after(self(), :retry_discovery, backoff_ms)

      {:noreply, new_state}
    else
      # Max retries exceeded
      Logger.error(
        "[ProcessDiscovery] Discovery failed for #{state.workflow_id} after #{max_retries} attempts: " <>
        inspect(reason)
      )

      error_msg = format_error(reason)

      failed_state = %{
        state
        | state: :failed,
          error: error_msg,
          retry_count: retry_count,
          completed_at: DateTime.utc_now()
      }

      broadcast_state_change(failed_state)
      broadcast_failure_event(failed_state)

      {:noreply, failed_state}
    end
  end

  defp format_error({:connection_failed, reason}) do
    "Connection failed: #{inspect(reason)}"
  end

  defp format_error({:invalid_log, msg}) do
    "Invalid event log: #{msg}"
  end

  defp format_error({:discovery_failed, msg}) do
    "Discovery failed: #{msg}"
  end

  defp format_error(reason) do
    inspect(reason)
  end

  defp broadcast_state_change(state) do
    Phoenix.PubSub.broadcast(
      Canopy.PubSub,
      "process_discovery:#{state.workflow_id}",
      {:discovery_state_changed, state}
    )
  end

  defp broadcast_completion_event(state) do
    event = %{
      "workflow_id" => state.workflow_id,
      "event_type" => "discovery_complete",
      "timestamp" => DateTime.utc_now(),
      "model" => state.result,
      "duration_ms" => DateTime.diff(state.completed_at, state.started_at, :millisecond)
    }

    Phoenix.PubSub.broadcast(Canopy.PubSub, "process_discovery:events", {:discovery_event, event})

    Logger.info("[ProcessDiscovery] Workflow #{state.workflow_id} completed successfully")
  end

  defp broadcast_failure_event(state) do
    event = %{
      "workflow_id" => state.workflow_id,
      "event_type" => "discovery_failed",
      "timestamp" => DateTime.utc_now(),
      "error" => state.error,
      "duration_ms" => DateTime.diff(state.completed_at, state.started_at, :millisecond)
    }

    Phoenix.PubSub.broadcast(Canopy.PubSub, "process_discovery:events", {:discovery_event, event})

    Logger.error("[ProcessDiscovery] Workflow #{state.workflow_id} failed: #{state.error}")
  end

  defp workflow_name(workflow_id) do
    {:global, {:discovery_workflow, workflow_id}}
  end

  defp workflow_registry_lookup(workflow_id) do
    workflow_name(workflow_id)
  end
end
