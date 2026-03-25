defmodule Canopy.Middleware.TracingTest do
  use ExUnit.Case
  alias Canopy.Middleware.Tracing

  describe "extract_traceparent/1" do
    test "extracts traceparent from request headers" do
      headers = %{
        "traceparent" => "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
      }

      {:ok, trace} = Tracing.extract_traceparent(headers)

      assert trace.trace_id == "0af7651916cd43dd8448eb211c80319c"
      assert trace.span_id == "b7ad6b7169203331"
      assert trace.flags == "01"
    end

    test "generates new trace when header missing" do
      {:ok, trace} = Tracing.extract_traceparent(%{})

      assert String.length(trace.trace_id) == 32
      assert String.length(trace.span_id) == 16
    end
  end

  describe "create_span/3" do
    test "creates span for heartbeat operation" do
      parent_trace = %{
        trace_id: "0af7651916cd43dd8448eb211c80319c",
        span_id: "b7ad6b7169203331",
        flags: "01"
      }

      {:ok, span} = Tracing.create_span(parent_trace, "heartbeat", %{agents: 5})

      assert span.trace_id == parent_trace.trace_id
      assert span.name == "heartbeat"
      assert span.attributes.agents == 5
    end

    test "creates span for agent dispatch" do
      parent_trace = %{
        trace_id: "abc1234567890def1234567890abcdef",
        span_id: "1234567890abcdef",
        flags: "01"
      }

      {:ok, span} = Tracing.create_span(parent_trace, "agent_dispatch", %{agent_id: "agent_1"})

      assert span.name == "agent_dispatch"
      assert span.attributes.agent_id == "agent_1"
    end
  end

  describe "end_span/2" do
    test "ends span and records duration" do
      parent_trace = %{
        trace_id: "1111111111111111111111111111111",
        span_id: "1111111111111111",
        flags: "01"
      }

      {:ok, span} = Tracing.create_span(parent_trace, "canopy_operation", %{})

      Process.sleep(10)

      {:ok, ended} = Tracing.end_span(span, :ok)

      assert ended.duration_ms > 0
      assert ended.status == :ok
    end
  end

  describe "propagate_to_downstream/2" do
    test "creates traceparent header for downstream service" do
      trace = %{
        trace_id: "0af7651916cd43dd8448eb211c80319c",
        span_id: "b7ad6b7169203331",
        flags: "01"
      }

      {:ok, span} = Tracing.create_span(trace, "canopy_service", %{})

      {:ok, headers} = Tracing.propagate_to_downstream(span, %{})

      assert Map.has_key?(headers, "traceparent")
      assert String.contains?(headers["traceparent"], trace.trace_id)
    end
  end

  describe "test_traceparent_propagation_canopy" do
    test "propagates traceparent from request through heartbeat to OSA" do
      # Canopy receives request with traceparent
      request_headers = %{
        "traceparent" => "00-deadbeefdeadbeefdeadbeefdeadbeef-cafebabecafebabe-01"
      }

      {:ok, canopy_trace} = Tracing.extract_traceparent(request_headers)

      # Canopy creates span for heartbeat
      {:ok, heartbeat_span} = Tracing.create_span(canopy_trace, "canopy_heartbeat", %{})

      # Canopy propagates to OSA
      {:ok, osa_headers} = Tracing.propagate_to_downstream(heartbeat_span, %{})

      # Verify traceparent is propagated
      {:ok, osa_trace} = Tracing.extract_traceparent(osa_headers)

      assert osa_trace.trace_id == canopy_trace.trace_id
    end
  end

  describe "test_span_creation_on_service_boundaries_canopy" do
    test "creates span on entry from BusinessOS" do
      parent_trace = %{
        trace_id: "2222222222222222222222222222222",
        span_id: "2222222222222222",
        flags: "01"
      }

      {:ok, span} = Tracing.create_span(parent_trace, "canopy_entry", %{source: "BusinessOS"})

      assert span.trace_id == parent_trace.trace_id
      assert span.attributes.source == "BusinessOS"
    end

    test "creates span on exit to OSA" do
      parent_trace = %{
        trace_id: "3333333333333333333333333333333",
        span_id: "3333333333333333",
        flags: "01"
      }

      {:ok, span} = Tracing.create_span(parent_trace, "canopy_exit_to_osa", %{})

      {:ok, ended} = Tracing.end_span(span, :ok)

      assert ended.status == :ok
    end
  end

  describe "test_trace_reconstruction_canopy" do
    test "reconstructs trace from Canopy operations" do
      trace_id = "44444444444444444444444444444444"

      spans = [
        %{
          trace_id: trace_id,
          span_id: "4444444444444444",
          name: "canopy_entry",
          parent_span_id: nil,
          start_time: DateTime.utc_now()
        },
        %{
          trace_id: trace_id,
          span_id: "5555555555555555",
          name: "canopy_heartbeat",
          parent_span_id: "4444444444444444",
          start_time: DateTime.utc_now()
        },
        %{
          trace_id: trace_id,
          span_id: "6666666666666666",
          name: "canopy_agent_dispatch",
          parent_span_id: "5555555555555555",
          start_time: DateTime.utc_now()
        }
      ]

      {:ok, trace} = Tracing.reconstruct_trace(spans)

      assert trace.trace_id == trace_id
      assert length(trace.spans) == 3
    end
  end

  describe "record_operation/3" do
    test "records operation details on span" do
      span = %{
        trace_id: "7777777777777777777777777777777",
        span_id: "7777777777777777",
        name: "operation",
        attributes: %{}
      }

      {:ok, updated} = Tracing.record_operation(span, "agent_count", 5)

      assert updated.attributes["agent_count"] == 5
    end
  end

  describe "encode_traceparent/1" do
    test "encodes to W3C Trace Context format" do
      trace = %{
        trace_id: "0af7651916cd43dd8448eb211c80319c",
        span_id: "b7ad6b7169203331",
        flags: "01"
      }

      encoded = Tracing.encode_traceparent(trace)

      assert encoded == "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
    end
  end
end
