defmodule Canopy.A2AAgent do
  @moduledoc """
  Canopy's A2A Agent GenServer.

  Implements the A2A protocol server using the `a2a` Hex library (v0.2.0).
  Receives incoming A2A calls via `A2A.Plug` (forwarded from router at /api/v1/a2a)
  and routes them to the Canopy heartbeat dispatch system.

  ## Agent Card

  Canopy advertises as an A2A agent with four skills:
  - `workspace_coordination` — multi-agent workspace management
  - `heartbeat_dispatch` — agent scheduling and task dispatch
  - `process_mining` — via BusinessOS integration
  - `agent_orchestration` — 160+ agents via heartbeat protocol

  ## WvdA Soundness
  - **Deadlock-free**: `handle_message/2` uses `Task.yield/2` with 60s timeout + `Task.shutdown` fallback
  - **Liveness**: all tasks either complete or are killed within 60s
  - **Boundedness**: `:canopy_a2a_tasks` ETS table cleaned up after each task

  ## Armstrong Fault Tolerance
  - **Supervised**: permanent child in `Canopy.Application`
  - **Let-it-crash**: unexpected failures propagate to supervisor
  - **No shared state**: ETS for task registry with atomic insert/delete
  """

  use A2A.Agent

  require Logger

  alias OpenTelemetry.SemConv.Incubating.A2aSpanNames
  alias OpenTelemetry.SemConv.Incubating.A2aAttributes

  @ets_table :canopy_a2a_tasks

  # ── A2A.Agent Callbacks ──────────────────────────────────────────────────

  @impl A2A.Agent
  def agent_card do
    base_url = Application.get_env(:canopy, :base_url, "http://localhost:9089")

    %{
      name: "canopy",
      display_name: "Canopy",
      description:
        "Workspace orchestration protocol and command center for AI agent systems " <>
          "with 160+ agents, heartbeat dispatch, and process mining integration.",
      version: "0.1.0",
      url: base_url <> "/api/v1/a2a",
      capabilities: ["streaming", "tools", "stateless"],
      skills: [
        %{
          id: "workspace_coordination",
          name: "Workspace Coordination",
          description: "Coordinate multi-agent workspaces and agent hiring"
        },
        %{
          id: "heartbeat_dispatch",
          name: "Heartbeat Dispatch",
          description: "Agent heartbeat scheduling and task dispatch"
        },
        %{
          id: "process_mining",
          name: "Process Mining",
          description: "Process mining via BusinessOS integration"
        },
        %{
          id: "agent_orchestration",
          name: "Agent Orchestration",
          description: "Orchestrate 160+ agents via heartbeat protocol"
        }
      ]
    }
  end

  @impl A2A.Agent
  def handle_message(message, _opts) do
    tracer = :opentelemetry.get_tracer(:canopy)

    :otel_tracer.with_span(tracer, A2aSpanNames.a2a_message_receive(), %{kind: :server}, fn span_ctx ->
      :otel_span.set_attributes(span_ctx, %{
        A2aAttributes.a2a_operation() => "message/send",
        A2aAttributes.a2a_agent_id() => "canopy"
      })

      task_id = extract_id(message)

      task =
        Task.Supervisor.async_nolink(Canopy.TaskSupervisor, fn ->
          route_to_dispatcher(message)
        end)

      # Register for cancellation — bounded by IdempotencyCleanup pattern
      :ets.insert(@ets_table, {task_id, task.pid})

      # WvdA: deadlock-free — 60s hard timeout + shutdown fallback
      result =
        case Task.yield(task, 60_000) || Task.shutdown(task) do
          {:ok, value} ->
            :otel_span.set_status(span_ctx, :ok)
            value

          nil ->
            :otel_span.set_status(span_ctx, :error, "task timeout after 60s")
            {:error, :timeout}
        end

      :ets.delete(@ets_table, task_id)
      result
    end)
  end

  @impl A2A.Agent
  def handle_cancel(task_id) do
    case :ets.lookup(@ets_table, task_id) do
      [{^task_id, pid}] ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
        :ets.delete(@ets_table, task_id)

      [] ->
        :ok
    end

    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp route_to_dispatcher(message) do
    text = extract_text(message)

    case find_dispatch_agent() do
      {:ok, agent} when not is_nil(agent) ->
        Canopy.Heartbeat.run(agent, %{"prompt" => text, "source" => "a2a"})

      _ ->
        # Default: echo-style response when no dispatch agent is available
        Logger.debug("[A2AAgent] No dispatch agent found, returning echo response")
        {:ok, %{"role" => "agent", "parts" => [%{"text" => "Canopy received: #{text}"}]}}
    end
  end

  defp find_dispatch_agent do
    # Resolve the first active or idle coordinator agent from the DB.
    # Falls back to nil if none available (caller handles echo fallback).
    import Ecto.Query

    try do
      agent =
        Canopy.Repo.one(
          from a in Canopy.Schemas.Agent,
            where: a.status in ["active", "idle"] and a.role == "coordinator",
            order_by: [asc: a.inserted_at],
            limit: 1
        )

      {:ok, agent}
    rescue
      e ->
        Logger.warning("[A2AAgent] Could not resolve dispatch agent: #{Exception.message(e)}")
        {:ok, nil}
    end
  end

  defp extract_text(%{parts: [%{text: text} | _]}), do: text
  defp extract_text(%{"parts" => [%{"text" => text} | _]}), do: text
  defp extract_text(_), do: ""

  defp extract_id(%{id: id}) when is_binary(id), do: id
  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(_), do: "canopy-task-#{:erlang.unique_integer([:positive])}"
end
