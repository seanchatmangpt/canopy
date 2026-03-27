defmodule Canopy.Autonomic.Heartbeat do
  @moduledoc """
  Autonomic nervous system heartbeat coordinator for Canopy.

  Dispatches 6 specialized autonomic agents on a scheduled interval:
  1. Health Agent - Polls all 5 systems for anomalies (latency, error rates, uptime)
  2. Healing Agent - Runs Process Healing on failed workflows
  3. Data Agent - Validates idempotency, consistency, freshness
  4. Compliance Agent - Checks audit trail gaps, missing signatures
  5. Learning Agent - Model retraining on new data
  6. Adaptation Agent - Config drift detection, hot reload

  Features:
  - Priority queue: health > healing > data > compliance > learning > adaptation
  - Budget enforcement: 6-tier hierarchy (critical, high, normal, low, batch, dormant)
  - No human dashboards: fully autonomic operation
  - Graceful error handling: one agent failure doesn't block others
  - OpenTelemetry tracing for distributed observability
  """
  require Logger
  require OpenTelemetry.Tracer

  @agent_order [
    :health_agent,
    :healing_agent,
    :data_agent,
    :compliance_agent,
    :learning_agent,
    :adaptation_agent
  ]

  @budget_tiers [:critical, :high, :normal, :low, :batch, :dormant]

  @default_budget_limit 10_000
  @default_agent_timeout 30_000

  # GenServer state key
  @state_key :autonomic_heartbeat_state

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def start_link(opts \\ []) do
    Agent.start_link(
      fn ->
        %{
          budget_limit: opts[:budget_limit] || @default_budget_limit,
          agent_timeout: opts[:agent_timeout] || @default_agent_timeout,
          last_tick: nil,
          dispatch_count: 0
        }
      end,
      name: @state_key
    )
  end

  @doc """
  Execute a single heartbeat tick: dispatch all 6 autonomic agents in priority order.

  Returns list of {agent_type, result} tuples.
  """
  def tick do
    Logger.info("[Autonomic] Heartbeat tick starting...")

    # Start OpenTelemetry span
    OpenTelemetry.Tracer.with_span "heartbeat.tick", %{
      "agent_count" => length(@agent_order),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    } do
      # Update state
      state = Agent.get(@state_key, & &1)
      new_dispatch_count = (state.dispatch_count || 0) + 1

      Agent.update(@state_key, fn s ->
        %{s | last_tick: DateTime.utc_now(), dispatch_count: new_dispatch_count}
      end)

      # Dispatch agents in priority order
      dispatch_results =
        @agent_order
        |> Enum.with_index()
        |> Enum.map(fn {agent_type, index} ->
          dispatch_agent(agent_type, index, state)
        end)

      Logger.info(
        "[Autonomic] Heartbeat tick complete. Dispatched #{length(dispatch_results)} agents."
      )

      dispatch_results
    end
  end

  @doc """
  Schedule the heartbeat to run on an interval.

  Default: every 5 minutes (critical), scaling to 60 minutes (dormant).

  This spawns a bounded supervised task that respects iteration limits
  to prevent unbounded loops (WvdA soundness: liveness guarantee).
  """
  def schedule(opts \\ []) do
    # 5 minutes default
    interval_ms = opts[:interval_ms] || 300_000
    # ~83 hours at 5min interval
    max_iterations = opts[:max_iterations] || 1_000

    # Spawn supervised task under Canopy.HeartbeatRunner Task.Supervisor
    # (Armstrong: supervised, let-it-crash; WvdA: bounded iteration)
    Task.Supervisor.start_child(
      Canopy.HeartbeatRunner,
      __MODULE__,
      :loop_heartbeat_supervised,
      [interval_ms, max_iterations, 0]
    )
  end

  @doc false
  def loop_heartbeat_supervised(interval_ms, max_iterations, iteration)
      when iteration < max_iterations do
    :timer.sleep(interval_ms)
    tick()
    loop_heartbeat_supervised(interval_ms, max_iterations, iteration + 1)
  end

  def loop_heartbeat_supervised(_interval_ms, max_iterations, _iteration) do
    Logger.warning(
      "[Autonomic] Heartbeat loop reached iteration limit #{max_iterations}, " <>
        "restarting. (Prevent unbounded loop per WvdA liveness)"
    )

    # Task supervisor will restart this if configured with :permanent restart strategy
    :ok
  end

  @doc """
  Get the current budget tiers.
  """
  def get_budget_tiers do
    @budget_tiers
  end

  @doc """
  Set the budget limit (in units).
  """
  def set_budget_limit(limit) do
    Agent.update(@state_key, fn s -> %{s | budget_limit: limit} end)
    :ok
  end

  @doc """
  Set the agent timeout (in milliseconds).
  """
  def set_agent_timeout(timeout_ms) do
    Agent.update(@state_key, fn s -> %{s | agent_timeout: timeout_ms} end)
    :ok
  end

  @doc """
  Get the current heartbeat state.
  """
  def get_state do
    Agent.get(@state_key, & &1)
  end

  # Private: dispatch a single agent
  defp dispatch_agent(agent_type, index, state) do
    Logger.info("[Autonomic] Dispatching #{inspect(agent_type)} (priority: #{index})")

    # Calculate budget allocation based on tier
    tier = Enum.at(@budget_tiers, rem(index, length(@budget_tiers)))
    budget = calculate_budget(tier, state.budget_limit)

    OpenTelemetry.Tracer.with_span "heartbeat.dispatch_agent", %{
      "agent_type" => inspect(agent_type),
      "priority_index" => index,
      "tier" => inspect(tier),
      "budget" => budget
    } do
      # Execute agent with timeout
      task =
        Task.async(fn ->
          try do
            run_agent(agent_type, %{budget: budget, tier: tier})
          catch
            :exit, reason ->
              Logger.error(
                "[Autonomic] Agent #{inspect(agent_type)} timed out: #{inspect(reason)}"
              )

              %{status: "timeout", agent_type: agent_type, tier: tier}

            kind, reason ->
              Logger.error(
                "[Autonomic] Agent #{inspect(agent_type)} error: #{inspect(kind)}: #{inspect(reason)}"
              )

              %{
                status: "error",
                agent_type: agent_type,
                error: "#{inspect(kind)}: #{inspect(reason)}"
              }
          end
        end)

      # Wait for result with timeout
      timeout_ms = state.agent_timeout || @default_agent_timeout

      case Task.yield(task, timeout_ms) do
        {:ok, result} ->
          {agent_type, result}

        nil ->
          # Task timed out, kill it
          Task.shutdown(task, :brutal_kill)

          Logger.warning(
            "[Autonomic] Agent #{inspect(agent_type)} exceeded timeout of #{timeout_ms}ms"
          )

          {agent_type, %{status: "timeout", agent_type: agent_type, timeout_ms: timeout_ms}}
      end
    end
  end

  # Private: calculate budget allocation for a tier
  defp calculate_budget(tier, total_budget) do
    case tier do
      :critical -> div(total_budget, 2)
      :high -> div(total_budget, 4)
      :normal -> div(total_budget, 8)
      :low -> div(total_budget, 16)
      :batch -> div(total_budget, 32)
      :dormant -> 0
    end
  end

  # Private: run a specific agent
  defp run_agent(:health_agent, opts) do
    Canopy.Autonomic.HealthAgent.run(opts)
  end

  defp run_agent(:healing_agent, opts) do
    Canopy.Autonomic.HealingAgent.run(opts)
  end

  defp run_agent(:data_agent, opts) do
    Canopy.Autonomic.DataAgent.run(opts)
  end

  defp run_agent(:compliance_agent, opts) do
    Canopy.Autonomic.ComplianceAgent.run(opts)
  end

  defp run_agent(:learning_agent, opts) do
    Canopy.Autonomic.LearningAgent.run(opts)
  end

  defp run_agent(:adaptation_agent, opts) do
    Canopy.Autonomic.AdaptationAgent.run(opts)
  end

  defp run_agent(unknown, _opts) do
    Logger.error("[Autonomic] Unknown agent type: #{inspect(unknown)}")
    %{status: "unknown_agent", agent_type: unknown}
  end
end
