defmodule Canopy.Adapters.BusinessOS do
  @moduledoc """
  BusinessOS adapter for Canopy workflow orchestration.

  Connects to BusinessOS HTTP API to enable process mining, model analysis, and
  conformance checking within Canopy workflows. Supports:
  - Process discovery and analysis
  - Model conformance checking
  - Compliance verification
  - Health checks and monitoring

  Configuration:
    url: HTTP base URL (default: http://127.0.0.1:8001)
    timeout: Request timeout in milliseconds (default: 30000)
    token: Authorization Bearer token (from env: BUSINESSOS_API_TOKEN)
  """
  @behaviour Canopy.Adapter

  require Logger

  @default_url "http://127.0.0.1:8001"
  @default_timeout 30_000

  @impl true
  def type, do: "businessos"

  @impl true
  def name, do: "BusinessOS Process Mining & Compliance"

  @impl true
  def supports_session?, do: false

  @impl true
  def supports_concurrent?, do: true

  @impl true
  def capabilities, do: [:process_mining, :model_analysis, :conformance_checking, :workflow_simulation]

  # ── Public API ──────────────────────────────────────────────────────

  @impl true
  def start(_config) do
    Logger.info("[BusinessOS Adapter] Initialized (stateless)")
    {:ok, %{initialized: true}}
  end

  @impl true
  def stop(_session) do
    :ok
  end

  @impl true
  def execute_heartbeat(params) do
    # Create span for BusinessOS heartbeat operation
    {:ok, span} = Canopy.Middleware.Tracing.create_span(nil, "businessos.heartbeat", %{
      url: params["url"] || @default_url
    })

    Stream.resource(
      fn ->
        params
      end,
      fn params ->
        case parallel_health_check(params, span) do
          {:ok, status} ->
            Canopy.Middleware.Tracing.end_span(span, :ok)

            event = %{
              "event_type" => "health_check",
              "data" => status,
              "tokens" => 75
            }

            {[event], params}

          {:error, reason} ->
            Canopy.Middleware.Tracing.end_span(span, :error)

            event = %{
              "event_type" => "health_check_failed",
              "data" => %{"error" => reason, "timestamp" => DateTime.utc_now()},
              "tokens" => 75
            }

            {[event], params}
        end
      end,
      fn _params -> :ok end
    )
  end

  @impl true
  def send_message(_session, message) when is_binary(message) do
    event =
      case parse_message(message) do
        {:process_mining, payload} ->
          {status, data} =
            case discover(payload["event_log"], payload) do
              {:ok, model} -> {"mining_complete", model}
              {:error, reason} -> {"mining_failed", %{"error" => inspect(reason)}}
            end

          %{
            "event_type" => status,
            "data" => data,
            "tokens" => 500
          }

        {:conformance, payload} ->
          {status, data} =
            case conformance_check(payload["model"], payload["event_log"], payload) do
              {:ok, result} -> {"conformance_complete", result}
              {:error, reason} -> {"conformance_failed", %{"error" => inspect(reason)}}
            end

          %{
            "event_type" => status,
            "data" => data,
            "tokens" => 300
          }

        {:compliance, payload} ->
          {status, data} =
            case verify_compliance(payload["framework"], payload) do
              {:ok, result} -> {"compliance_verified", result}
              {:error, reason} -> {"compliance_failed", %{"error" => inspect(reason)}}
            end

          %{
            "event_type" => status,
            "data" => data,
            "tokens" => 200
          }

        {:yawl_simulate, payload} ->
          {status, data} =
            case simulate_workflows(payload, payload) do
              {:ok, result} -> {"simulation_complete", result}
              {:error, reason} -> {"simulation_failed", %{"error" => inspect(reason)}}
            end

          %{
            "event_type" => status,
            "data" => data,
            "tokens" => 300
          }

        {:error, reason} ->
          %{
            "event_type" => "parse_error",
            "data" => %{"error" => reason},
            "tokens" => 100
          }
      end

    Stream.concat([event])
  end

  def send_message(_session, _message) do
    event = %{
      "event_type" => "parse_error",
      "data" => %{"error" => "Invalid message format"},
      "tokens" => 100
    }

    Stream.concat([event])
  end

  # ── Process Mining API ───────────────────────────────────────────────

  @doc """
  Discover a process model from an event log using BusinessOS.

  Returns {:ok, model_json} or {:error, reason}
  """
  def discover(event_log, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    # Create span for process discovery
    {:ok, span} = Canopy.Middleware.Tracing.create_span(nil, "businessos.discover", %{
      url: url,
      include_variants: true,
      include_statistics: true
    })

    payload = %{
      "event_log" => event_log,
      "include_variants" => true,
      "include_statistics" => true
    }

    case make_request("POST", "#{url}/api/bos/discover", payload, params, timeout) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        Canopy.Middleware.Tracing.end_span(span, :ok)
        Logger.info("[BusinessOS] Process discovery succeeded")
        {:ok, resp_body}

      {:ok, %{status: 400, body: resp_body}} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        {:error, {:invalid_log, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        {:error, {:discovery_failed, resp_body["error"]}}

      {:error, reason} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        Logger.error("[BusinessOS] Process discovery failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Conformance Checking API ────────────────────────────────────────

  @doc """
  Check conformance of a process model against an event log.

  Returns {:ok, {fitness, precision}} or {:error, reason}
  """
  def conformance_check(model, event_log, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    # Create span for conformance checking
    {:ok, span} = Canopy.Middleware.Tracing.create_span(nil, "businessos.conformance_check", %{
      url: url,
      method: params["method"] || "token_replay"
    })

    payload = %{
      "model" => model,
      "event_log" => event_log,
      "method" => params["method"] || "token_replay"
    }

    case make_request("POST", "#{url}/api/bos/conformance", payload, params, timeout) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        fitness = resp_body["fitness"] || 0.0
        precision = resp_body["precision"] || 0.0
        Canopy.Middleware.Tracing.record_operation(span, :fitness, fitness)
        Canopy.Middleware.Tracing.record_operation(span, :precision, precision)
        Canopy.Middleware.Tracing.end_span(span, :ok)
        Logger.info("[BusinessOS] Conformance check: fitness=#{fitness}, precision=#{precision}")
        {:ok, %{"fitness" => fitness, "precision" => precision}}

      {:ok, %{status: 400, body: resp_body}} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        {:error, {:invalid_input, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        {:error, {:conformance_failed, resp_body["error"]}}

      {:error, reason} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        Logger.error("[BusinessOS] Conformance check failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Compliance Verification API ─────────────────────────────────────

  @doc """
  Verify compliance against a framework (SOC2, HIPAA, GDPR, etc).

  Returns {:ok, compliance_result} or {:error, reason}
  """
  def verify_compliance(framework, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    # Create span for compliance verification
    {:ok, span} = Canopy.Middleware.Tracing.create_span(nil, "businessos.verify_compliance", %{
      url: url,
      framework: framework
    })

    payload = %{
      "framework" => framework,
      "include_gaps" => true,
      "include_evidence" => true
    }

    case make_request("POST", "#{url}/api/bos/compliance/verify", payload, params, timeout) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        Canopy.Middleware.Tracing.end_span(span, :ok)
        Logger.info("[BusinessOS] Compliance verification succeeded for #{framework}")
        {:ok, resp_body}

      {:ok, %{status: 400, body: resp_body}} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        {:error, {:invalid_framework, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        {:error, {:verification_failed, resp_body["error"]}}

      {:error, reason} ->
        Canopy.Middleware.Tracing.end_span(span, :error)
        Logger.error("[BusinessOS] Compliance verification failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Health Check ────────────────────────────────────────────────────

  @doc """
  Check health status of BusinessOS server.
  """
  def health_check(params \\ %{}, trace_headers \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    case make_request("GET", "#{url}/api/health", nil, params, timeout, trace_headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        Logger.debug("[BusinessOS] Health check OK")
        {:ok, resp_body["status"] || "healthy"}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc """
  Parallel health checks: status endpoint + discovery capability.

  Used by heartbeat to validate both availability and functionality.
  Includes traceparent injection for distributed tracing.
  """
  def parallel_health_check(params \\ %{}, span \\ nil) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    # Inject traceparent into request headers
    headers_with_trace = if span do
      {:ok, headers} = Canopy.Middleware.Tracing.propagate_to_downstream(span, %{})
      headers
    else
      %{}
    end

    # Start two parallel checks: status and discover endpoint
    status_task =
      Task.async(fn ->
        health_check(params, headers_with_trace)
      end)

    discover_task =
      Task.async(fn ->
        case make_request("GET", "#{url}/api/bos/status", nil, params, timeout, headers_with_trace) do
          {:ok, %{status: 200, body: resp_body}} ->
            {:ok, resp_body}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end)

    # Wait for both with timeout
    case Task.yield_many([status_task, discover_task], timeout) do
      [{:ok, {:ok, status}}, {:ok, {:ok, discover_status}}] ->
        {:ok,
         %{
           "status" => status,
           "discover_status" => discover_status,
           "timestamp" => DateTime.utc_now()
         }}

      _other ->
        {:error, "Health check timeout or failure"}
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp make_request(method, url, body, params, timeout, trace_headers \\ %{}) do
    headers = build_headers(params, trace_headers)

    case method do
      "GET" ->
        Req.get(url,
          headers: headers,
          receive_timeout: timeout,
          retry: :transient,
          max_retries: 2
        )

      "POST" ->
        Req.post(url,
          json: body,
          headers: headers,
          receive_timeout: timeout,
          retry: :transient,
          max_retries: 2
        )

      _ ->
        {:error, :invalid_method}
    end
  end

  defp build_headers(params, trace_headers) do
    token = params["token"] || System.get_env("BUSINESSOS_API_TOKEN") || ""

    base = [
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"}
    ]

    # Add traceparent headers if provided
    base =
      if map_size(trace_headers) > 0 do
        trace_list =
          trace_headers
          |> Enum.map(fn {k, v} -> {k, v} end)

        trace_list ++ base
      else
        base
      end

    base
  end

  defp parse_message(msg) when is_binary(msg) do
    case Jason.decode(msg) do
      {:ok, data} -> parse_message(data)
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end

  defp parse_message(msg) when is_map(msg) do
    case msg do
      %{"type" => "process_mining", "payload" => payload} -> {:process_mining, payload}
      %{"type" => "conformance", "payload" => payload} -> {:conformance, payload}
      %{"type" => "compliance", "payload" => payload} -> {:compliance, payload}
      %{"type" => "yawl_simulate", "payload" => payload} -> {:yawl_simulate, payload}
      _ -> {:error, "Unknown message type"}
    end
  end

  defp parse_message(_), do: {:error, "Invalid message format"}

  # ── YAWL Workflow Simulation API ────────────────────────────────────

  @doc """
  Run concurrent YAWL user simulations via BusinessOS → OSA pipeline.

  BusinessOS proxies the request to OSA's POST /api/v1/yawl/simulate, which
  runs the `OptimalSystemAgent.Yawl.Simulator` with N concurrent Tasks.

  ## Options (all optional, as map keys)

  | Key              | Default      | Description                                    |
  |------------------|--------------|------------------------------------------------|
  | `"spec_set"`     | `"basic_wcp"` | `"basic_wcp"`, `"wcp_patterns"`, `"real_data"`, `"all"` |
  | `"user_count"`   | `3`          | Number of concurrent simulated users           |
  | `"timeout_ms"`   | `30000`      | Per-user budget in milliseconds                |
  | `"max_steps"`    | `50`         | Drain-loop iteration limit per user            |
  | `"max_concurrency"` | `10`     | OSA Task.async_stream cap                      |

  Returns `{:ok, result_map}` or `{:error, reason}`.

  ## Example

      {:ok, result} = BusinessOS.simulate_workflows(%{"spec_set" => "basic_wcp", "user_count" => 5})
      result["completed_count"]  # => 5
      result["summary"]          # => "spec_set=basic_wcp users=5 completed=5 ..."
  """
  @spec simulate_workflows(map(), map()) :: {:ok, map()} | {:error, term()}
  def simulate_workflows(payload \\ %{}, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = (payload["timeout_ms"] || 30_000) * 2 + 10_000

    body = %{
      "spec_set" => payload["spec_set"] || "basic_wcp",
      "user_count" => payload["user_count"] || 3,
      "timeout_ms" => payload["timeout_ms"] || 30_000,
      "max_steps" => payload["max_steps"] || 50,
      "max_concurrency" => payload["max_concurrency"] || 10
    }

    case make_request("POST", "#{url}/api/yawl/simulate", body, params, timeout) do
      {:ok, %{status: 200, body: resp_body}} ->
        Logger.info(
          "[BusinessOS] YAWL simulation complete: #{resp_body["summary"]}"
        )
        {:ok, resp_body}

      {:ok, %{status: 502, body: resp_body}} ->
        {:error, {:osa_unavailable, resp_body["error"]}}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:simulation_failed, status, resp_body}}

      {:error, reason} ->
        Logger.error("[BusinessOS] YAWL simulate request failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── LinkedIn RevOps API ──────────────────────────────────────────────

  @doc """
  Score qualified contacts for ICP (Ideal Customer Profile).

  Calls BusinessOS LinkedIn integration to score all contacts and return count
  of those meeting the minimum score threshold.

  Returns {:ok, %{"qualified" => count, "total_contacts" => count}} or {:error, reason}
  """
  def icp_score_contacts(min_score \\ 0.7, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    case make_request(
           "POST",
           "#{url}/api/linkedin/icp-score?min_score=#{min_score}",
           nil,
           params,
           timeout
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        Logger.info("[BusinessOS] ICP scoring completed: qualified=#{resp_body["qualified"]}")
        {:ok, resp_body}

      {:ok, %{status: 400, body: resp_body}} ->
        {:error, {:invalid_params, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        {:error, {:scoring_failed, resp_body["error"]}}

      {:error, reason} ->
        Logger.error("[BusinessOS] ICP scoring failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Queue outreach steps for qualified contacts.

  Calls BusinessOS LinkedIn integration to enroll contacts in an outreach
  sequence, respecting rate limits (max 5 messages per contact per day).

  Returns {:ok, %{"queued" => count, "skipped" => count}} or {:error, reason}
  """
  def queue_outreach_step(sequence_id, min_score \\ 0.7, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    payload = %{
      "sequence_id" => sequence_id,
      "min_score" => min_score,
      "target_count" => params["target_count"] || 100
    }

    case make_request("POST", "#{url}/api/linkedin/outreach/enroll", payload, params, timeout) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        Logger.info(
          "[BusinessOS] Outreach queued: enrolled=#{resp_body["enrolled"]}, skipped=#{resp_body["skipped"]}"
        )

        {:ok, resp_body}

      {:ok, %{status: 400, body: resp_body}} ->
        {:error, {:invalid_params, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        {:error, {:enrollment_failed, resp_body["error"]}}

      {:error, reason} ->
        Logger.error("[BusinessOS] Outreach enrollment failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end
end
