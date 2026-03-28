defmodule Canopy.Autonomic.HealthAgent do
  @moduledoc """
  Health Agent - Polls all 5 systems for anomalies.

  Monitors:
  - Latency spikes
  - Error rates
  - Uptime status
  - System health across: pm4py-rust, BusinessOS, Canopy, OSA
  - OpenTelemetry tracing for distributed health checks

  Returns: %{status: "healthy"|"degraded"|"critical", alerts: [...], timestamp: ...}
  """
  require Logger
  require OpenTelemetry.Tracer

  @systems [
    {:pm4py_rust, "http://localhost:8090/healthz"},
    {:businessos, "http://localhost:8001/healthz"},
    {:canopy, "http://localhost:9089/healthz"},
    {:osa, "http://localhost:8089/healthz"}
  ]

  @latency_threshold_ms 1000

  def run(opts \\ []) do
    Logger.info("[HealthAgent] Polling systems for anomalies...")

    budget = opts[:budget] || 1000
    tier = opts[:tier] || :high

    OpenTelemetry.Tracer.with_span "health_agent.run", %{
      "budget" => budget,
      "tier" => inspect(tier),
      "systems_count" => length(@systems)
    } do
      start_time = System.monotonic_time(:millisecond)

      # Poll all systems
      health_results =
        @systems
        |> Enum.map(fn {system_name, _url} ->
          poll_system(system_name)
        end)

      # Detect anomalies
      anomalies = Enum.filter(health_results, &elem(&1, 1)[:anomaly])

      # Compile status
      status =
        cond do
          length(anomalies) >= 2 -> "critical"
          length(anomalies) == 1 -> "degraded"
          true -> "healthy"
        end

      elapsed = System.monotonic_time(:millisecond) - start_time

      result = %{
        status: status,
        alerts: Enum.map(anomalies, fn {system, data} -> {system, data} end),
        systems_checked: length(@systems),
        anomalies_found: length(anomalies),
        latency_ms: elapsed,
        budget_used: budget - (budget - elapsed),
        tier: tier,
        timestamp: DateTime.utc_now()
      }

      # Emit telemetry event for observability
      :telemetry.execute(
        [:agent, :run],
        %{latency_ms: elapsed, status: status},
        %{agent_name: "health_agent", tier: tier, budget_used: budget - elapsed}
      )

      Logger.info(
        "[HealthAgent] Health check complete. Status: #{status}, anomalies: #{length(anomalies)}"
      )

      result
    end
  end

  @doc """
  Poll a named system and return its health data.

  Returns `{system_name, %{latency_ms, error_rate, healthy, anomaly, status}}`.
  `error_rate` is 0.0 when healthy, 1.0 when unreachable.
  """
  def poll_system(system_name) do
    url = system_url(system_name)
    start = System.monotonic_time(:millisecond)

    case Req.get(url, receive_timeout: 5_000, retry: false) do
      {:ok, %{status: status_code}} ->
        latency = System.monotonic_time(:millisecond) - start
        healthy = status_code in 200..299
        error_rate = if healthy, do: 0.0, else: 1.0
        anomaly = latency > @latency_threshold_ms or not healthy

        {system_name,
         %{
           latency_ms: latency,
           error_rate: error_rate,
           healthy: healthy,
           anomaly: anomaly,
           status: if(healthy, do: "healthy", else: "degraded")
         }}

      {:error, reason} ->
        latency = System.monotonic_time(:millisecond) - start

        Logger.warning(
          "[HealthAgent] Error polling #{inspect(system_name)}: #{inspect(reason)}"
        )

        {system_name,
         %{
           latency_ms: latency,
           error_rate: 1.0,
           healthy: false,
           anomaly: true,
           status: "unreachable"
         }}
    end
  end

  # Map system atom to URL
  defp system_url(system_name) do
    case Enum.find(@systems, fn {name, _url} -> name == system_name end) do
      {_name, url} -> url
      nil -> "http://localhost:9999/healthz"
    end
  end
end
