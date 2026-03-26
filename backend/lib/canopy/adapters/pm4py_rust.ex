defmodule Canopy.Adapters.PM4pyRust do
  @moduledoc """
  PM4py-rust adapter for Canopy workflow orchestration.

  Connects to pm4py-rust HTTP API to enable process discovery and conformance checking
  within Canopy workflows. Supports:
  - Event log upload and validation
  - Process discovery (Alpha, Inductive miners)
  - Conformance checking against discovered models
  - Health checks and automatic failover

  Configuration:
    url: HTTP base URL (default: http://127.0.0.1:8000)
    timeout: Request timeout in milliseconds (default: 30000)
  """
  @behaviour Canopy.Adapter

  require Logger

  @default_url "http://127.0.0.1:8000"
  @default_timeout 30_000

  @impl true
  def type, do: "pm4py-rust"

  @impl true
  def name, do: "PM4py-rust Process Mining"

  @impl true
  def supports_session?, do: false

  @impl true
  def supports_concurrent?, do: true

  @impl true
  def capabilities, do: [:process_discovery, :conformance_checking, :statistics]

  # ── Public API ──────────────────────────────────────────────────────

  @impl true
  def start(_config) do
    # PM4py-rust doesn't require sessions (stateless HTTP API)
    Logger.info("[PM4py-rust Adapter] Initialized (stateless)")
    {:ok, %{initialized: true}}
  end

  @impl true
  def stop(_session) do
    # No cleanup needed for stateless adapter
    :ok
  end

  @impl true
  def execute_heartbeat(params) do
    Stream.resource(
      fn ->
        params
      end,
      fn params ->
        case health_check(params) do
          {:ok, status} ->
            event = %{
              "event_type" => "health_check",
              "data" => %{"status" => status, "timestamp" => DateTime.utc_now()},
              "tokens" => 50
            }

            {[event], params}

          {:error, reason} ->
            event = %{
              "event_type" => "health_check_failed",
              "data" => %{"error" => reason, "timestamp" => DateTime.utc_now()},
              "tokens" => 50
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
        {:discovery, payload} ->
          {status, data} =
            case discover(payload["event_log"], payload["algorithm"] || "alpha", payload) do
              {:ok, model} -> {"discovery_complete", model}
              {:error, reason} -> {"discovery_failed", %{"error" => inspect(reason)}}
            end

          %{
            "event_type" => status,
            "data" => data,
            "tokens" => 500
          }

        {:conformance, payload} ->
          {status, data} =
            case conformance(
                   payload["event_log"],
                   payload["model"],
                   payload["method"] || "token_replay",
                   payload
                 ) do
              {:ok, {fitness, precision}} ->
                {"conformance_complete", %{"fitness" => fitness, "precision" => precision}}

              {:error, reason} ->
                {"conformance_failed", %{"error" => inspect(reason)}}
            end

          %{
            "event_type" => status,
            "data" => data,
            "tokens" => 200
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

  # ── Discovery API ───────────────────────────────────────────────────

  @doc """
  Discover a process model from an event log.

  Returns {:ok, model_json} or {:error, reason}
  """
  def discover(event_log, algorithm \\ "alpha", params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    # Convert event log to request format
    payload = %{
      "event_log" => event_log,
      "variant" => algorithm
    }

    case Req.post("#{url}/api/v1/discover",
           json: payload,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        Logger.info("[PM4py-rust] Discovery succeeded with #{algorithm} miner")
        {:ok, resp_body}

      {:ok, %{status: 400, body: resp_body}} ->
        {:error, {:invalid_log, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        {:error, {:discovery_failed, resp_body["error"]}}

      {:error, reason} ->
        Logger.error("[PM4py-rust] Discovery failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Conformance API ─────────────────────────────────────────────────

  @doc """
  Check conformance of event log against a process model.

  Returns {:ok, {fitness, precision}} or {:error, reason}
  """
  def conformance(event_log, model, method \\ "token_replay", params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    payload = %{
      "event_log" => event_log,
      "petri_net" => model,
      "method" => method
    }

    case Req.post("#{url}/api/v1/conformance",
           json: payload,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        fitness = resp_body["fitness"] || 0.0
        precision = resp_body["precision"] || 0.0
        Logger.info("[PM4py-rust] Conformance check: fitness=#{fitness}, precision=#{precision}")
        {:ok, {fitness, precision}}

      {:ok, %{status: 400, body: resp_body}} ->
        {:error, {:invalid_input, resp_body["error"]}}

      {:ok, %{status: 500, body: resp_body}} ->
        {:error, {:conformance_failed, resp_body["error"]}}

      {:error, reason} ->
        Logger.error("[PM4py-rust] Conformance check failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Health Check ────────────────────────────────────────────────────

  @doc """
  Check health status of pm4py-rust HTTP server.
  """
  def health_check(params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    case Req.get("#{url}/health", receive_timeout: timeout) do
      {:ok, %{status: 200, body: resp_body}} ->
        Logger.debug("[PM4py-rust] Health check OK")
        {:ok, resp_body["status"] || "healthy"}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # ── Statistics API ──────────────────────────────────────────────────

  @doc """
  Get statistics about an event log.
  """
  def statistics(event_log, params \\ %{}) do
    url = params["url"] || @default_url
    timeout = params["timeout"] || @default_timeout

    payload = %{
      "event_log" => event_log,
      "include_variants" => true,
      "include_resource_metrics" => true,
      "include_bottlenecks" => true
    }

    case Req.post("#{url}/api/v1/statistics",
           json: payload,
           receive_timeout: timeout
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        {:ok, resp_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp parse_message(msg) when is_binary(msg) do
    case Jason.decode(msg) do
      {:ok, data} ->
        case data do
          %{"type" => "discovery", "payload" => payload} -> {:discovery, payload}
          %{"type" => "conformance", "payload" => payload} -> {:conformance, payload}
          _ -> {:error, "Unknown message type"}
        end

      {:error, _} ->
        {:error, "Invalid JSON"}
    end
  end

  defp parse_message(msg) when is_map(msg) do
    case msg do
      %{"type" => "discovery", "payload" => payload} -> {:discovery, payload}
      %{"type" => "conformance", "payload" => payload} -> {:conformance, payload}
      _ -> {:error, "Unknown message type"}
    end
  end

  defp parse_message(_), do: {:error, "Invalid message format"}
end
