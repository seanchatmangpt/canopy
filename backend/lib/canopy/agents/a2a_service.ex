defmodule Canopy.Agents.A2AService do
  @moduledoc """
  A2A (Agent-to-Agent) service for Canopy.

  Provides HTTP-based agent-to-agent communication following the A2A protocol
  specification. Agents can discover each other via a registry, exchange
  messages, and negotiate task delegation.

  This module implements A2A communication directly using Req (already in deps).
  When the `a2a` library is added to deps, this module will be refactored to
  wrap it.

  ## A2A Protocol Overview

  - **Agent Card** — Describes an agent's capabilities, skills, and endpoint
  - **Message** — A task request or response between agents
  - **Task** — A unit of work that can be delegated between agents
  - **Registry** — A directory of discoverable agent cards
  """

  require Logger

  @default_timeout 30_000

  # ── Agent Communication ─────────────────────────────────────────────

  @doc """
  Sends a message to another agent via its A2A endpoint.

  ## Parameters
    - `agent_url` — The agent's A2A endpoint URL
    - `message` — Map containing the message payload
    - `opts` — Options:
      - `:timeout` — request timeout in ms (default 30_000)
      - `:headers` — additional HTTP headers

  ## Returns
    - `{:ok, response}` on success
    - `{:error, reason}` on failure
  """
  @spec call_agent(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call_agent(agent_url, message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    extra_headers = Keyword.get(opts, :headers, %{})

    req_headers =
      [
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ] ++ Map.to_list(extra_headers)

    payload = %{
      "jsonrpc" => "2.0",
      "method" => "message/send",
      "params" => message,
      "id" => System.unique_integer([:positive])
    }

    Logger.debug("[A2AService] Calling agent at #{agent_url}")

    start_time = System.monotonic_time(:millisecond)

    case Req.post(agent_url,
           json: payload,
           headers: req_headers,
           receive_timeout: timeout
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        latency_ms = System.monotonic_time(:millisecond) - start_time
        Logger.debug("[A2AService] Received response from #{agent_url} in #{latency_ms}ms")

        # Emit OTEL span for successful A2A call
        tracer = :opentelemetry.get_tracer(:canopy)

        :otel_tracer.with_span(tracer, "jtbd.a2a.call", %{}, fn span_ctx ->
          :otel_span.set_attributes(span_ctx, %{
            "agent_url" => agent_url,
            "status" => "ok",
            "duration_ms" => latency_ms,
            "message_type" => Map.get(message, "type", "unknown")
          })
        end)

        {:ok, normalize_response(resp_body)}

      {:ok, %{status: status, body: resp_body}} ->
        latency_ms = System.monotonic_time(:millisecond) - start_time

        Logger.warning(
          "[A2AService] Agent #{agent_url} returned #{status}: #{inspect(resp_body)}"
        )

        # Emit error OTEL span
        tracer = :opentelemetry.get_tracer(:canopy)

        :otel_tracer.with_span(tracer, "jtbd.a2a.call", %{}, fn span_ctx ->
          :otel_span.set_attributes(span_ctx, %{
            "agent_url" => agent_url,
            "status" => "error",
            "http_status" => status,
            "duration_ms" => latency_ms
          })

          :otel_span.set_status(span_ctx, :error, "HTTP #{status}")
        end)

        {:error, {:agent_error, status, resp_body}}

      {:error, reason} ->
        latency_ms = System.monotonic_time(:millisecond) - start_time
        Logger.error("[A2AService] Failed to reach agent #{agent_url}: #{inspect(reason)}")

        # Emit timeout/connection error OTEL span
        tracer = :opentelemetry.get_tracer(:canopy)

        :otel_tracer.with_span(tracer, "jtbd.a2a.call", %{}, fn span_ctx ->
          :otel_span.set_attributes(span_ctx, %{
            "agent_url" => agent_url,
            "status" => "error",
            "error_type" => inspect(reason),
            "duration_ms" => latency_ms
          })

          :otel_span.set_status(span_ctx, :error, "Connection failed")
        end)

        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Sends a task to another agent for execution.

  ## Parameters
    - `agent_url` — The agent's A2A endpoint URL
    - `task` — Map describing the task (must include "kind" and "input")
    - `opts` — Same options as `call_agent/3`

  ## Returns
    - `{:ok, task_result}` on success
    - `{:error, reason}` on failure
  """
  @spec send_task(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def send_task(agent_url, task, opts \\ []) do
    payload = %{
      "kind" => "task",
      "taskId" => Map.get(task, "taskId") || generate_task_id(),
      "input" => Map.get(task, "input", task)
    }

    call_agent(agent_url, payload, opts)
  end

  # ── Agent Discovery ─────────────────────────────────────────────────

  @doc """
  Discovers available agents from a registry.

  ## Parameters
    - `registry_url` — The A2A registry endpoint URL
    - `opts` — Options:
      - `:timeout` — request timeout in ms
      - `:headers` — additional HTTP headers
      - `:filters` — map of filters (e.g., %{"capability" => "code_review"})

  ## Returns
    - `{:ok, agent_cards}` — list of agent card maps
    - `{:error, reason}`
  """
  @spec discover_agents(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def discover_agents(registry_url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    extra_headers = Keyword.get(opts, :headers, %{})
    filters = Keyword.get(opts, :filters, %{})

    req_headers =
      [{"Accept", "application/json"}] ++ Map.to_list(extra_headers)

    params =
      if map_size(filters) > 0 do
        Map.put(filters, "limit", Map.get(filters, "limit", 50))
      else
        %{"limit" => 50}
      end

    Logger.debug("[A2AService] Discovering agents from #{registry_url}")

    case Req.get("#{registry_url}/agents",
           params: params,
           headers: req_headers,
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        agents = parse_agent_cards(resp_body)
        Logger.debug("[A2AService] Discovered #{length(agents)} agents")
        {:ok, agents}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:registry_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Fetches the agent card for a specific agent.

  ## Parameters
    - `agent_url` — The agent's A2A endpoint URL (card is at `/agent-card` or the root)

  ## Returns
    - `{:ok, agent_card}` — map describing the agent
    - `{:error, reason}`
  """
  @spec get_agent_card(String.t()) :: {:ok, map()} | {:error, term()}
  def get_agent_card(agent_url) do
    card_url = String.trim_trailing(agent_url, "/") <> "/.well-known/agent.json"

    Logger.debug("[A2AService] Fetching agent card from #{card_url}")

    case Req.get(card_url,
           headers: [{"Accept", "application/json"}],
           receive_timeout: @default_timeout
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        {:ok, normalize_agent_card(resp_body)}

      {:ok, %{status: status}} ->
        # Try fallback: the root URL might serve the card
        case Req.get(agent_url,
               headers: [{"Accept", "application/json"}],
               receive_timeout: @default_timeout
             ) do
          {:ok, %{status: 200, body: resp_body}} ->
            {:ok, normalize_agent_card(resp_body)}

          _ ->
            {:error, {:card_not_found, status}}
        end

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp normalize_response(%{"result" => result}), do: result
  defp normalize_response(response) when is_map(response), do: response

  defp normalize_agent_card(%{"name" => _} = card), do: card
  defp normalize_agent_card(%{"agent" => agent}) when is_map(agent), do: agent

  defp normalize_agent_card(other) do
    Logger.warning("[A2AService] Unexpected agent card format: #{inspect(other)}")
    other
  end

  defp parse_agent_cards(%{"agents" => agents}) when is_list(agents), do: agents
  defp parse_agent_cards(agents) when is_list(agents), do: agents

  defp parse_agent_cards(%{"data" => data}) do
    parse_agent_cards(data)
  end

  defp parse_agent_cards(_other), do: []

  defp generate_task_id do
    "task-#{:erlang.unique_integer([:positive])}"
  end
end
