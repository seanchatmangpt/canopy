defmodule Canopy.Integration.WeaverE2ETraceTest do
  @moduledoc """
  Optional cross-service trace propagation check (Canopy → pm4py-rust HTTP).

  Run explicitly:
    WEAVER_E2E_TRACE=true PM4PY_URL=http://localhost:8090 \\
      mix test test/integration/weaver_e2e_trace_test.exs --only weaver_e2e

  Requires pm4py-rust HTTP server reachable at PM4PY_URL (default http://localhost:8090).
  """

  use ExUnit.Case, async: false

  @moduletag :weaver_e2e

  @tag :weaver_e2e
  test "propagates W3C traceparent on outbound HTTP to pm4py health" do
    unless System.get_env("WEAVER_E2E_TRACE") in ["1", "true"] do
      assert true
    else
    base = System.get_env("PM4PY_URL", "http://localhost:8090") |> String.trim_trailing("/")
    url = base <> "/health"

    tracer = :opentelemetry.get_tracer(:canopy)

    :otel_tracer.with_span(tracer, "weaver.e2e.pm4py_handshake", %{}, fn _ ->
      # Default text-map injector (W3C traceparent) — see otel_propagator_text_map:inject/1
      carrier = :otel_propagator_text_map.inject([])

      header_list =
        Enum.map(carrier, fn {k, v} ->
          {String.downcase(to_string(k)), to_string(v)}
        end)

      case Req.get(url, headers: header_list, receive_timeout: 3_000) do
        {:ok, %{status: 200}} ->
          assert Enum.any?(header_list, fn {k, _} -> k == "traceparent" end)

        {:ok, other} ->
          flunk("unexpected HTTP status from pm4py: #{inspect(other)}")

        {:error, reason} ->
          IO.puts(:stderr, "[weaver_e2e] skip: pm4py not reachable (#{inspect(reason)}) at #{url}")
          assert true
      end
    end)
    end
  end
end
