defmodule Canopy.Adapters.A2A do
  @moduledoc """
  A2A Protocol adapter for Canopy.

  Implements the `Canopy.Adapter` behaviour to enable outbound A2A protocol
  communication with remote agents. Uses the `a2a` Hex library (v0.2.0)
  `A2A.Client` for all outbound calls.

  ## Behaviour

  - **Stateless**: no persistent session state; each `send_message` creates a fresh client
  - **Concurrent**: multiple calls can run simultaneously
  - **Capabilities**: chat, task_delegation, agent_discovery

  ## Configuration

  ```elixir
  %{
    "url" => "http://remote-agent:8080/a2a"  # required
  }
  ```

  ## OTEL Instrumentation

  All outbound calls emit `a2a.call` spans with `a2a.operation` attribute set.
  """

  @behaviour Canopy.Adapter

  require Logger

  alias OpenTelemetry.SemConv.Incubating.A2aSpanNames
  alias OpenTelemetry.SemConv.Incubating.A2aAttributes

  @default_timeout 30_000

  # ── Canopy.Adapter Callbacks ─────────────────────────────────────────────

  @impl Canopy.Adapter
  def type, do: "a2a"

  @impl Canopy.Adapter
  def name, do: "A2A Protocol"

  @impl Canopy.Adapter
  def supports_session?, do: false

  @impl Canopy.Adapter
  def supports_concurrent?, do: true

  @impl Canopy.Adapter
  def capabilities, do: [:chat, :task_delegation, :agent_discovery]

  @impl Canopy.Adapter
  def start(config) do
    tracer = :opentelemetry.get_tracer(:canopy)

    :otel_tracer.with_span(tracer, A2aSpanNames.a2a_call(), %{kind: :client}, fn span_ctx ->
      :otel_span.set_attributes(span_ctx, %{
        A2aAttributes.a2a_operation() => "discover"
      })

      url = Map.get(config, "url") || Map.get(config, :url)

      if is_nil(url) || url == "" do
        :otel_span.set_status(span_ctx, :error, "missing url config")
        {:error, {:missing_config, "url is required for A2A adapter"}}
      else
        client = A2A.Client.new(url, timeout: @default_timeout)

        case A2A.Client.discover(client) do
          {:ok, agent_card} ->
            :otel_span.set_attributes(span_ctx, %{A2aAttributes.a2a_agent_url() => url})
            :otel_span.set_status(span_ctx, :ok)
            {:ok, %{url: url, client: client, agent_card: agent_card}}

          {:error, reason} ->
            Logger.warning("[A2A Adapter] Discovery failed for #{url}: #{inspect(reason)}, continuing anyway")
            :otel_span.set_status(span_ctx, :ok)
            {:ok, %{url: url, client: client, agent_card: nil}}
        end
      end
    end)
  end

  @impl Canopy.Adapter
  def stop(_session), do: :ok

  @impl Canopy.Adapter
  def send_message(session, message) do
    tracer = :opentelemetry.get_tracer(:canopy)
    url = Map.get(session, :url, "")

    :otel_tracer.with_span(tracer, A2aSpanNames.a2a_call(), %{kind: :client}, fn span_ctx ->
      :otel_span.set_attributes(span_ctx, %{
        A2aAttributes.a2a_operation() => "message/send",
        A2aAttributes.a2a_agent_url() => url
      })

      client = Map.get(session, :client) || A2A.Client.new(url, timeout: @default_timeout)
      a2a_message = %{role: "user", parts: [%{text: message}]}

      Stream.resource(
        fn -> send_and_collect(client, a2a_message) end,
        fn
          {:ok, events} -> {events, :done}
          {:error, reason} ->
            {[%{event_type: "run.failed", data: %{error: inspect(reason)}, tokens: 0}], :done}
          :done -> {:halt, :done}
        end,
        fn _ ->
          :otel_span.set_status(span_ctx, :ok)
        end
      )
    end)
  end

  @impl Canopy.Adapter
  def execute_heartbeat(params) do
    tracer = :opentelemetry.get_tracer(:canopy)
    url = Map.get(params, "url") || Map.get(params, :url, "")
    message = Map.get(params, "message") || Map.get(params, :message, "heartbeat")

    :otel_tracer.with_span(tracer, A2aSpanNames.a2a_call(), %{kind: :client}, fn span_ctx ->
      :otel_span.set_attributes(span_ctx, %{
        A2aAttributes.a2a_operation() => "heartbeat",
        A2aAttributes.a2a_agent_url() => url
      })

      client = A2A.Client.new(url, timeout: @default_timeout)
      a2a_message = %{role: "user", parts: [%{text: message}]}

      case A2A.Client.send_message(client, a2a_message, []) do
        {:ok, _result} ->
          :otel_span.set_status(span_ctx, :ok)

          Stream.concat([
            [%{event_type: "run.output", data: %{output: "A2A heartbeat sent to #{url}"}, tokens: 0}],
            [%{event_type: "run.completed", data: %{}, tokens: 0}]
          ])

        {:error, reason} ->
          :otel_span.set_status(span_ctx, :error, inspect(reason))

          Stream.concat([
            [%{event_type: "run.failed", data: %{error: inspect(reason)}, tokens: 0}]
          ])
      end
    end)
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp send_and_collect(client, message) do
    case A2A.Client.send_message(client, message, []) do
      {:ok, result} ->
        events = result_to_events(result)
        {:ok, events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp result_to_events(result) when is_list(result) do
    Enum.flat_map(result, &result_to_events/1) ++
      [%{event_type: "run.completed", data: %{}, tokens: 0}]
  end

  defp result_to_events(%{"parts" => parts}) do
    Enum.map(parts, fn
      %{"text" => text} ->
        %{event_type: "run.output", data: %{output: text}, tokens: 0}

      part ->
        %{event_type: "run.output", data: part, tokens: 0}
    end)
  end

  defp result_to_events(result) when is_map(result) do
    [%{event_type: "run.output", data: result, tokens: 0},
     %{event_type: "run.completed", data: %{}, tokens: 0}]
  end

  defp result_to_events(_other) do
    [%{event_type: "run.completed", data: %{}, tokens: 0}]
  end
end
