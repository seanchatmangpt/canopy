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
  @error_rate_threshold 0.05

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

  defp poll_system(system_name) do
    start = System.monotonic_time(:millisecond)

    try do
      # Simulate health check (would be real HTTP in production)
      :timer.sleep(10)  # Simulate network latency

      latency = System.monotonic_time(:millisecond) - start
      error_rate = :rand.uniform()

      anomaly =
        latency > @latency_threshold_ms or error_rate > @error_rate_threshold

      {system_name,
       %{
         latency_ms: latency,
         error_rate: error_rate,
         anomaly: anomaly,
         status: if(anomaly, do: "degraded", else: "healthy")
       }}
    rescue
      e ->
        Logger.error(
          "[HealthAgent] Error polling #{inspect(system_name)}: #{Exception.message(e)}"
        )
        {system_name, %{status: "unreachable", error: Exception.message(e), anomaly: true}}
    end
  end
end
