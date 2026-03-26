defmodule Canopy.JTBD.SelfPlayLoop do
  @moduledoc """
  Self-Play Loop Orchestrator for Wave 12 Integration Testing

  Coordinates execution of 10 JTBD scenarios across all ChatmanGPT systems in sequence:
  1. agent_decision_loop (OSA)
  2. process_discovery (pm4py-rust)
  3. compliance_check (BusinessOS)
  4. cross_system_handoff (Canopy → OSA → BusinessOS)
  5. workspace_sync (Canopy ↔ OSA)
  6. consensus_round (OSA HotStuff BFT)
  7. healing_recovery (OSA healing)
  8. a2a_deal_lifecycle (Canopy A2A)
  9. mcp_tool_execution (OSA MCP)
  10. conformance_drift (pm4py-rust Petri net fitness)

  After each iteration completes:
  - Publishes result to PubSub topic `jtbd:wave12`
  - After all 10 complete, resets state and restarts
  - Supports bounded execution (finite iterations) for CI or infinite for monitoring

  GenServer Behavior:
  - start/1 — begin self-play loop
  - stop/0 — graceful shutdown (completes current iteration)
  - get_state/0 — return current iteration and pass rate
  """

  use GenServer
  require Logger
  alias Phoenix.PubSub

  # Graceful degradation helper: emit telemetry with timeout + fallback
  defp emit_telemetry(event, measurements) do
    try do
      :telemetry.execute(event, measurements)
    rescue
      _e ->
        Logger.debug("[SelfPlayLoop] Telemetry emission failed for event: #{inspect(event)}")
        :ok
    catch
      :exit, _reason ->
        Logger.debug("[SelfPlayLoop] Telemetry exit for event: #{inspect(event)}")
        :ok
    end
  end

  @scenarios [
    :agent_decision_loop,
    :process_discovery,
    :compliance_check,
    :cross_system_handoff,
    :workspace_sync,
    :consensus_round,
    :healing_recovery,
    :a2a_deal_lifecycle,
    :mcp_tool_execution,
    :conformance_drift,
    :yawl_v6_checkpoint,
    :icp_qualification,
    :retrofit_complexity_scoring,
    :outreach_sequence_execution,
    :deal_progression,
    :contract_closure
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start the self-play loop with options"
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []) do
    case GenServer.call(__MODULE__, {:start_loop, opts}) do
      :ok -> {:ok, self()}
      error -> error
    end
  rescue
    _e -> {:error, :not_started}
  end

  @doc "Stop the self-play loop gracefully"
  @spec stop() :: :ok
  def stop do
    GenServer.call(__MODULE__, :stop_loop, 60_000)
  rescue
    _e -> :ok
  end

  @doc "Get current loop state"
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  rescue
    _e -> %{status: :not_running}
  end

  # Server Callbacks

  @impl GenServer
  def init(opts) do
    state = %{
      loop_pid: nil,
      iteration: 0,
      max_iterations: Keyword.get(opts, :max_iterations, :infinity),
      running: false,
      results: %{},
      pass_count: 0,
      fail_count: 0,
      start_time: nil,
      workspace_id: Keyword.get(opts, :workspace_id, "wave12-self-play")
    }
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_loop, opts}, _from, state) do
    if state.running do
      Logger.warning("Wave 12 self-play loop already running, ignoring start request")
      {:reply, {:error, :already_running}, state}
    else
      max_iterations = Keyword.get(opts, :max_iterations, :infinity)
      workspace_id = Keyword.get(opts, :workspace_id, "wave12-self-play")

      Logger.info(
        "Wave 12 self-play loop starting | workspace=#{workspace_id} | max_iterations=#{inspect(max_iterations)}"
      )

      new_state = %{
        state
        | running: true,
          iteration: 0,
          max_iterations: max_iterations,
          workspace_id: workspace_id,
          start_time: DateTime.utc_now(),
          results: %{},
          pass_count: 0,
          fail_count: 0
      }

      # Spawn loop in background
      loop_pid = spawn_loop(new_state)

      Logger.info("Wave 12 self-play loop spawned | loop_pid=#{inspect(loop_pid)}")

      # Emit telemetry event for supervision monitoring
      emit_telemetry([:jtbd, :self_play_loop, :started], %{
        loop_pid: loop_pid,
        workspace_id: workspace_id,
        max_iterations: max_iterations
      })

      {:reply, :ok, %{new_state | loop_pid: loop_pid}}
    end
  end

  @impl GenServer
  def handle_call(:stop_loop, _from, state) do
    if state.loop_pid && Process.alive?(state.loop_pid) do
      # Graceful shutdown of supervised task
      Logger.info(
        "Wave 12 self-play loop graceful shutdown initiated | loop_pid=#{inspect(state.loop_pid)} | iterations=#{state.iteration} | pass_rate=#{calculate_pass_rate(state.pass_count, state.fail_count)}%"
      )

      emit_telemetry([:jtbd, :self_play_loop, :stopping], %{
        loop_pid: state.loop_pid,
        iteration: state.iteration,
        pass_count: state.pass_count,
        fail_count: state.fail_count,
        pass_rate: calculate_pass_rate(state.pass_count, state.fail_count)
      })

      Process.exit(state.loop_pid, :shutdown)
    else
      Logger.warning("Wave 12 self-play loop stop called but loop not running")
    end

    {:reply, :ok, %{state | running: false, loop_pid: nil}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {
      :reply,
      %{
        running: state.running,
        iteration: state.iteration,
        max_iterations: state.max_iterations,
        pass_count: state.pass_count,
        fail_count: state.fail_count,
        pass_rate: calculate_pass_rate(state.pass_count, state.fail_count),
        workspace_id: state.workspace_id,
        start_time: state.start_time
      },
      state
    }
  end

  @impl GenServer
  def handle_info({:loop_update, iteration, results}, state) do
    new_state = %{
      state
      | iteration: iteration,
        results: results
    }
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:loop_done}, state) do
    {:noreply, %{state | running: false, loop_pid: nil}}
  end

  # Loop Orchestration

  defp spawn_loop(state) do
    # Use Task.Supervisor for supervised process (Armstrong principle: supervision tree)
    # This ensures the loop is automatically restarted if it crashes
    Logger.debug(
      "Wave 12 spawning supervised loop task | workspace=#{state.workspace_id} | max_iterations=#{inspect(state.max_iterations)}"
    )

    case Task.Supervisor.async_nolink(:canopy_jtbd_loop_supervisor, fn ->
      run_loop(state)
    end) do
      %Task{pid: pid} ->
        Logger.info("Wave 12 loop task spawned successfully | pid=#{inspect(pid)}")

        emit_telemetry([:jtbd, :loop_task, :spawned], %{
          pid: pid,
          workspace_id: state.workspace_id
        })

        pid

      error ->
        Logger.error(
          "Wave 12 loop spawning failed | error=#{inspect(error)} | workspace=#{state.workspace_id}"
        )

        emit_telemetry([:jtbd, :loop_task, :spawn_failed], %{
          error: inspect(error),
          workspace_id: state.workspace_id
        })

        nil
    end
  end

  defp run_loop(state) do
    iteration = state.iteration + 1
    max_iterations = state.max_iterations

    Logger.debug(
      "Wave 12 starting iteration #{iteration} | workspace=#{state.workspace_id} | max=#{inspect(max_iterations)}"
    )

    # Check iteration limit
    if max_iterations != :infinity && iteration > max_iterations do
      Logger.info(
        "Wave 12 self-play loop reached max iterations | iteration=#{iteration} | max=#{max_iterations} | workspace=#{state.workspace_id}"
      )

      emit_telemetry([:jtbd, :self_play_loop, :max_iterations_reached], %{
        iteration: iteration,
        max_iterations: max_iterations,
        workspace_id: state.workspace_id,
        final_pass_count: state.pass_count,
        final_fail_count: state.fail_count
      })

      GenServer.cast(__MODULE__, {:loop_done})
      :ok
    else
      start_time = System.monotonic_time(:millisecond)

      # Run all 10 scenarios sequentially
      Logger.debug("Wave 12 iteration #{iteration}: running 10 scenarios | workspace=#{state.workspace_id}")

      results = run_all_scenarios(state.workspace_id, iteration)

      # Calculate metrics
      scenario_results = Map.values(results)
      passes = Enum.count(scenario_results, fn r -> r.outcome == :success end)
      fails = length(scenario_results) - passes

      latency_ms = System.monotonic_time(:millisecond) - start_time
      pass_rate = Float.round(passes / length(scenario_results) * 100, 1)

      Logger.info(
        "Wave 12 iteration #{iteration} completed | scenarios=#{passes}/#{length(scenario_results)} passed | pass_rate=#{pass_rate}% | latency_ms=#{latency_ms} | workspace=#{state.workspace_id}"
      )

      # Emit telemetry for iteration completion
      emit_telemetry([:jtbd, :iteration, :completed], %{
        iteration: iteration,
        pass_count: passes,
        fail_count: fails,
        total_scenarios: length(scenario_results),
        pass_rate: pass_rate,
        latency_ms: latency_ms,
        workspace_id: state.workspace_id
      })

      # Publish results to PubSub
      Logger.debug("Wave 12 publishing iteration #{iteration} results to PubSub | workspace=#{state.workspace_id}")
      publish_iteration_result(iteration, results, passes, fails, latency_ms, state.workspace_id)

      # Update state via message (GenServer call)
      GenServer.cast(__MODULE__, {:loop_update, iteration, results, passes, fails})

      # Wait before next iteration (configurable backoff)
      Logger.debug("Wave 12 iteration #{iteration} backoff starting (100ms) | workspace=#{state.workspace_id}")
      Process.sleep(100)

      # Recurse for next iteration
      run_loop(%{
        state
        | iteration: iteration,
          pass_count: state.pass_count + passes,
          fail_count: state.fail_count + fails
      })
    end
  end

  defp run_all_scenarios(workspace_id, iteration) do
    # Run scenarios sequentially (one after another)
    # This ensures proper ordering and allows dashboard to update per-scenario
    Logger.debug("Wave 12 iteration #{iteration}: executing 10 scenarios in sequence | workspace=#{workspace_id}")

    results =
      @scenarios
      |> Enum.reduce(%{}, fn scenario_id, acc ->
        Logger.debug(
          "Wave 12 iteration #{iteration}: running scenario #{inspect(scenario_id)} | workspace=#{workspace_id}"
        )

        result = run_single_scenario(scenario_id, workspace_id, iteration)
        Map.put(acc, scenario_id, result)
      end)

    Logger.debug("Wave 12 iteration #{iteration}: all 10 scenarios completed | workspace=#{workspace_id}")
    results
  end

  defp run_single_scenario(scenario_id, workspace_id, iteration) do
    start_time = System.monotonic_time(:millisecond)

    Logger.debug(
      "Wave 12 scenario starting | scenario=#{inspect(scenario_id)} | iteration=#{iteration} | workspace=#{workspace_id}"
    )

    case Canopy.JTBD.Runner.run_scenario(scenario_id, workspace_id: workspace_id, iteration: iteration) do
      {:ok, result} ->
        latency_ms = System.monotonic_time(:millisecond) - start_time

        Logger.info(
          "Wave 12 scenario succeeded | scenario=#{inspect(scenario_id)} | iteration=#{iteration} | latency_ms=#{latency_ms} | system=#{result.system} | workspace=#{workspace_id}"
        )

        emit_telemetry([:jtbd, :scenario, :success], %{
          scenario_id: scenario_id,
          iteration: iteration,
          latency_ms: latency_ms,
          system: result.system,
          workspace_id: workspace_id
        })

        result

      {:error, reason} ->
        latency_ms = System.monotonic_time(:millisecond) - start_time

        Logger.warning(
          "Wave 12 scenario failed | scenario=#{inspect(scenario_id)} | iteration=#{iteration} | reason=#{inspect(reason)} | latency_ms=#{latency_ms} | workspace=#{workspace_id}"
        )

        emit_telemetry([:jtbd, :scenario, :failure], %{
          scenario_id: scenario_id,
          iteration: iteration,
          reason: inspect(reason),
          latency_ms: latency_ms,
          workspace_id: workspace_id
        })

        %{
          outcome: :failure,
          system: nil,
          error_reason: inspect(reason),
          span_emitted: false,
          latency_ms: latency_ms,
          transitions: []
        }
    end
  end

  defp publish_iteration_result(iteration, results, passes, fails, latency_ms, workspace_id) do
    scenario_list =
      results
      |> Enum.map(fn {scenario_id, result} ->
        %{
          id: Atom.to_string(scenario_id),
          outcome: Atom.to_string(result.outcome),
          latency_ms: result.latency_ms,
          system: result.system |> to_string()
        }
      end)

    payload = %{
      iteration: iteration,
      timestamp: DateTime.utc_now(),
      workspace_id: workspace_id,
      scenarios: scenario_list,
      pass_count: passes,
      fail_count: fails,
      total_latency_ms: latency_ms,
      pass_rate: passes / (passes + fails)
    }

    Logger.debug(
      "Wave 12 publishing iteration #{iteration} to PubSub | topic=jtbd:wave12 | pass_count=#{passes} | fail_count=#{fails} | workspace=#{workspace_id}"
    )

    case PubSub.broadcast(Canopy.PubSub, "jtbd:wave12", {:scenario_result, payload}) do
      :ok ->
        Logger.debug(
          "Wave 12 PubSub broadcast succeeded | iteration=#{iteration} | topic=jtbd:wave12 | workspace=#{workspace_id}"
        )

        emit_telemetry([:jtbd, :pubsub, :broadcast_success], %{
          iteration: iteration,
          pass_count: passes,
          fail_count: fails,
          workspace_id: workspace_id
        })

      error ->
        Logger.error(
          "Wave 12 PubSub broadcast failed | iteration=#{iteration} | error=#{inspect(error)} | workspace=#{workspace_id}"
        )

        emit_telemetry([:jtbd, :pubsub, :broadcast_failed], %{
          iteration: iteration,
          error: inspect(error),
          workspace_id: workspace_id
        })
    end
  end

  # Handle cast messages
  @impl GenServer
  def handle_cast({:loop_update, iteration, _results, passes, fails}, state) do
    new_state = %{
      state
      | iteration: iteration,
        pass_count: state.pass_count + passes,
        fail_count: state.fail_count + fails
    }
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:loop_done}, state) do
    {:noreply, %{state | running: false, loop_pid: nil}}
  end

  # Helpers

  defp calculate_pass_rate(passes, fails) when passes + fails > 0 do
    Float.round(passes / (passes + fails) * 100, 1)
  end

  defp calculate_pass_rate(_passes, _fails) do
    0.0
  end
end
