defmodule Canopy.Telemetry.A2AHandler do
  @moduledoc """
  Telemetry handler bridging A2A.Plug telemetry events to OpenTelemetry spans.

  When attached, this module listens to telemetry events emitted by the `a2a`
  library (A2A.Plug) and creates corresponding OTEL spans with proper attributes
  from the ChatmanGPT semconv registry.

  ## Usage

  Call `attach/0` once after the supervisor has started:

      Canopy.Telemetry.A2AHandler.attach()

  ## Events Handled

  | Telemetry Event | OTEL Span | Kind |
  |-----------------|-----------|------|
  | `[:a2a, :message, :start/:stop]` | `a2a.message.receive` | server |
  | `[:a2a, :cancel, :start/:stop]` | `a2a.cancel` | client |
  | `[:a2a, :task, :start/:stop]` | `a2a.task.create` | server |

  ## Process Dictionary Pairing

  Start/stop events are paired via process dictionary keys `{:a2a_span, event_type}`.
  This is safe because A2A.Plug handles one request per process.
  """

  require Logger

  alias OpenTelemetry.SemConv.Incubating.A2aSpanNames
  alias OpenTelemetry.SemConv.Incubating.A2aAttributes

  @handler_id "canopy-a2a-telemetry-handler"

  @events [
    [:a2a, :message, :start],
    [:a2a, :message, :stop],
    [:a2a, :message, :exception],
    [:a2a, :cancel, :start],
    [:a2a, :cancel, :stop],
    [:a2a, :cancel, :exception],
    [:a2a, :task, :start],
    [:a2a, :task, :stop]
  ]

  @doc """
  Attach this handler to all A2A telemetry events.

  Safe to call multiple times — detaches the previous handler if already attached.
  """
  def attach do
    :telemetry.detach(@handler_id)

    :telemetry.attach_many(
      @handler_id,
      @events,
      &__MODULE__.handle_event/4,
      %{tracer: :opentelemetry.get_tracer(:canopy)}
    )
  end

  @doc false
  def handle_event([:a2a, :message, :start], _measurements, metadata, %{tracer: tracer}) do
    ctx = :otel_tracer.start_span(tracer, A2aSpanNames.a2a_message_receive(), %{kind: :server})
    Process.put({:a2a_span, :message}, ctx)

    :otel_span.set_attributes(ctx, %{
      A2aAttributes.a2a_operation() => Map.get(metadata, :method, "message/send"),
      A2aAttributes.a2a_agent_id() => "canopy"
    })
  end

  def handle_event([:a2a, :message, :stop], measurements, _metadata, _config) do
    with ctx when not is_nil(ctx) <- Process.get({:a2a_span, :message}) do
      duration_ms = native_to_ms(Map.get(measurements, :duration, 0))
      :otel_span.set_attributes(ctx, %{A2aAttributes.a2a_duration_ms() => duration_ms})
      :otel_span.set_status(ctx, :ok)
      :otel_span.end_span(ctx)
      Process.delete({:a2a_span, :message})
    end
  end

  def handle_event([:a2a, :message, :exception], _measurements, metadata, _config) do
    with ctx when not is_nil(ctx) <- Process.get({:a2a_span, :message}) do
      reason = Map.get(metadata, :reason, :unknown)
      :otel_span.set_status(ctx, :error, "A2A message exception: #{inspect(reason)}")
      :otel_span.end_span(ctx)
      Process.delete({:a2a_span, :message})
    end
  end

  def handle_event([:a2a, :cancel, :start], _measurements, metadata, %{tracer: tracer}) do
    ctx = :otel_tracer.start_span(tracer, A2aSpanNames.a2a_cancel(), %{kind: :client})
    Process.put({:a2a_span, :cancel}, ctx)

    :otel_span.set_attributes(ctx, %{
      A2aAttributes.a2a_operation() => "tasks/cancel",
      A2aAttributes.a2a_task_id() => Map.get(metadata, :task_id, "unknown")
    })
  end

  def handle_event([:a2a, :cancel, :stop], measurements, _metadata, _config) do
    with ctx when not is_nil(ctx) <- Process.get({:a2a_span, :cancel}) do
      duration_ms = native_to_ms(Map.get(measurements, :duration, 0))
      :otel_span.set_attributes(ctx, %{A2aAttributes.a2a_duration_ms() => duration_ms})
      :otel_span.set_status(ctx, :ok)
      :otel_span.end_span(ctx)
      Process.delete({:a2a_span, :cancel})
    end
  end

  def handle_event([:a2a, :cancel, :exception], _measurements, metadata, _config) do
    with ctx when not is_nil(ctx) <- Process.get({:a2a_span, :cancel}) do
      reason = Map.get(metadata, :reason, :unknown)
      :otel_span.set_status(ctx, :error, "A2A cancel exception: #{inspect(reason)}")
      :otel_span.end_span(ctx)
      Process.delete({:a2a_span, :cancel})
    end
  end

  def handle_event([:a2a, :task, :start], _measurements, metadata, %{tracer: tracer}) do
    ctx = :otel_tracer.start_span(tracer, A2aSpanNames.a2a_task_create(), %{kind: :server})
    Process.put({:a2a_span, :task}, ctx)

    :otel_span.set_attributes(ctx, %{
      A2aAttributes.a2a_operation() => "task.execute",
      A2aAttributes.a2a_task_id() => Map.get(metadata, :task_id, "unknown")
    })
  end

  def handle_event([:a2a, :task, :stop], measurements, _metadata, _config) do
    with ctx when not is_nil(ctx) <- Process.get({:a2a_span, :task}) do
      duration_ms = native_to_ms(Map.get(measurements, :duration, 0))
      :otel_span.set_attributes(ctx, %{A2aAttributes.a2a_duration_ms() => duration_ms})
      :otel_span.set_status(ctx, :ok)
      :otel_span.end_span(ctx)
      Process.delete({:a2a_span, :task})
    end
  end

  def handle_event(event, _measurements, _metadata, _config) do
    Logger.debug("[A2AHandler] Unhandled telemetry event: #{inspect(event)}")
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp native_to_ms(native_time) do
    System.convert_time_unit(native_time, :native, :millisecond)
  rescue
    _ -> 0
  end
end
