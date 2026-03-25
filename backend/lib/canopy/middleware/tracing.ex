defmodule Canopy.Middleware.Tracing do
  @moduledoc """
  Distributed tracing middleware for Canopy.

  Propagates W3C Trace Context across:
  - Canopy heartbeat operations
  - Canopy agent dispatch
  - Downstream to OSA and BusinessOS

  Traceparent format: 00-<trace_id>-<span_id>-<flags>
  """

  require Logger

  @hex_chars "0123456789abcdef"

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Extract traceparent from request headers.

  Returns {:ok, trace}
  """
  def extract_traceparent(headers) when is_map(headers) do
    case headers do
      %{"traceparent" => traceparent} when is_binary(traceparent) ->
        case parse_traceparent(traceparent) do
          {:ok, trace} -> {:ok, trace}
          :error -> {:ok, generate_trace()}
        end

      _ ->
        {:ok, generate_trace()}
    end
  end

  @doc """
  Create a span for Canopy operation.

  Returns {:ok, span}
  """
  def create_span(parent_trace, name, attributes \\ %{}) when is_map(attributes) do
    trace_id = if parent_trace, do: parent_trace.trace_id, else: generate_id(32)
    parent_span_id = if parent_trace, do: parent_trace.span_id, else: nil

    span = %{
      trace_id: trace_id,
      span_id: generate_id(16),
      parent_span_id: parent_span_id,
      name: name,
      attributes: attributes,
      start_time: DateTime.utc_now(),
      end_time: nil,
      duration_ms: 0,
      status: :running,
      service: "canopy"
    }

    {:ok, span}
  end

  @doc """
  End a span and record status.

  Returns {:ok, span}
  """
  def end_span(span, status) when is_map(span) do
    end_time = DateTime.utc_now()
    duration_ms = DateTime.diff(end_time, span.start_time, :millisecond)

    updated_span = %{
      span
      | end_time: end_time,
        duration_ms: max(0, duration_ms),
        status: status
    }

    {:ok, updated_span}
  end

  @doc """
  Propagate traceparent to downstream services.

  Returns {:ok, headers} with traceparent set
  """
  def propagate_to_downstream(span, headers) when is_map(span) and is_map(headers) do
    traceparent = encode_traceparent(span)
    {:ok, Map.put(headers, "traceparent", traceparent)}
  end

  @doc """
  Encode span as traceparent header.

  Format: 00-<trace_id>-<span_id>-<flags>
  """
  def encode_traceparent(trace_or_span) when is_map(trace_or_span) do
    trace_id = trace_or_span.trace_id
    span_id = trace_or_span.span_id
    flags = Map.get(trace_or_span, :flags, "01")

    "00-#{trace_id}-#{span_id}-#{flags}"
  end

  @doc """
  Record an operation detail on span.

  Returns {:ok, updated_span}
  """
  def record_operation(span, key, value) when is_map(span) do
    updated_attributes = Map.put(span.attributes || %{}, key, value)

    {:ok, %{span | attributes: updated_attributes}}
  end

  @doc """
  Reconstruct a complete trace from spans.

  Returns {:ok, trace}
  """
  def reconstruct_trace(spans) when is_list(spans) do
    case spans do
      [] ->
        {:ok, %{trace_id: nil, spans: []}}

      [first | _] ->
        organized = organize_spans(spans)

        {:ok, %{
          trace_id: first.trace_id,
          spans: organized,
          span_count: length(spans)
        }}
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp generate_trace do
    %{
      trace_id: generate_id(32),
      span_id: generate_id(16),
      flags: "01",
      start_time: DateTime.utc_now()
    }
  end

  defp generate_id(length) do
    1..length
    |> Enum.map(fn i -> String.at(@hex_chars, rem(i, String.length(@hex_chars))) end)
    |> Enum.join()
  end

  defp parse_traceparent(traceparent) when is_binary(traceparent) do
    case String.split(traceparent, "-") do
      ["00", trace_id, span_id, flags] when byte_size(trace_id) == 32 and byte_size(span_id) == 16 ->
        {:ok, %{trace_id: trace_id, span_id: span_id, flags: flags}}

      _ ->
        :error
    end
  end

  defp organize_spans(spans) do
    spans |> Enum.sort_by(fn s -> s.start_time || DateTime.utc_now() end)
  end
end
