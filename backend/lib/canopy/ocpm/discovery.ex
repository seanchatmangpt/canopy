defmodule Canopy.OCPM.Discovery do
  @moduledoc """
  Process discovery from event logs using OCPM algorithms.

  Primary path: BusinessOS HTTP API (port 8001) — delegates to pm4py-rust.
  Fallback path: local Pm4pyWrapper (Python subprocess) when BOS is unavailable.

  ## Strategy

  - `discover_process_model/1` — BOS-primary, pm4py fallback
  - `find_deviations/2`        — BOS-primary, pm4py fallback
  - `detect_bottlenecks/2`     — pm4py only (no BOS endpoint)

  ## WvdA Soundness

  All BOS calls are bounded by @bos_discovery_timeout_ms (30 s).
  Fallback is synchronous (avoids always spawning a Python subprocess on success path).

  ## Armstrong Fault Tolerance

  BOS failure is non-fatal: logs and falls back. pm4py failure propagates to caller.
  """

  require Logger

  alias Canopy.OCPM.Pm4pyWrapper
  alias Canopy.Adapters.BusinessOS

  # WvdA: hard timeout on BusinessOS discovery requests
  @bos_discovery_timeout_ms 30_000

  @doc """
  Discovers a process model from an event log.

  Attempts BusinessOS first (pm4py-rust backed). Falls back to local Pm4pyWrapper
  on any BOS connection error or timeout.

  Returns `{:ok, process_model}` or `{:error, reason}`.
  """
  def discover_process_model(event_log) when is_list(event_log) do
    Logger.info(
      "[Discovery] Discovering process model from #{length(event_log)} events (BOS-primary)"
    )

    params = %{"timeout" => @bos_discovery_timeout_ms}

    case BusinessOS.discover(event_log, params) do
      {:ok, bos_result} ->
        Logger.info("[Discovery] BOS discovery succeeded")
        {:ok, normalize_bos_discover_result(bos_result)}

      {:error, reason} ->
        Logger.warning(
          "[Discovery] BOS discovery failed (#{inspect(reason)}), falling back to pm4py"
        )

        Pm4pyWrapper.discover_process_model(event_log)
    end
  end

  @doc """
  Detects bottlenecks using pm4py's heuristic miner.

  No BusinessOS endpoint exists for this — always uses local pm4py.

  Returns `{:ok, bottlenecks}` or `{:error, reason}`.
  """
  def detect_bottlenecks(_process_model, event_log) when is_list(event_log) do
    Logger.info("[Discovery] Analyzing #{length(event_log)} events for bottlenecks via pm4py")
    Pm4pyWrapper.detect_bottlenecks(event_log)
  end

  @doc """
  Finds deviations between an event log and a process model.

  Attempts BusinessOS conformance check first (returns fitness + violations).
  Falls back to local Pm4pyWrapper alignment on any BOS failure.

  Returns `{:ok, deviations}` or `{:error, reason}`.
  """
  def find_deviations(process_model, event_log)
      when is_map(process_model) and is_list(event_log) do
    Logger.info("[Discovery] Checking conformance (BOS-primary)")

    params = %{"timeout" => @bos_discovery_timeout_ms}

    case BusinessOS.conformance_check(process_model, event_log, params) do
      {:ok, bos_result} ->
        Logger.info("[Discovery] BOS conformance succeeded")
        {:ok, normalize_bos_conformance_result(bos_result)}

      {:error, reason} ->
        Logger.warning(
          "[Discovery] BOS conformance failed (#{inspect(reason)}), falling back to pm4py"
        )

        Pm4pyWrapper.find_deviations(event_log, process_model)
    end
  end

  # ── Private: BOS Result Normalization ───────────────────────────────

  # Translate BusinessOS discover response → pm4py process model shape.
  # Callers (OCPM, healing, conformance checks) stay unchanged.
  defp normalize_bos_discover_result(bos_result) when is_map(bos_result) do
    nodes = bos_result["activities"] || bos_result["nodes"] || []
    transitions = bos_result["transitions"] || bos_result["edges"] || []

    %{
      nodes: nodes,
      edges: %{"transitions" => transitions},
      metadata: %{
        algorithm: bos_result["algorithm"] || "bos",
        fitness: bos_result["fitness"] || bos_result["fitness_score"],
        model_id: bos_result["model_id"],
        source: "businessos",
        event_count: bos_result["traces_count"] || 0
      }
    }
  end

  defp normalize_bos_discover_result(other), do: other

  # Translate BusinessOS conformance response → deviations list shape.
  # BOS returns {fitness, precision, violations}; pm4py returns a list of deviation maps.
  defp normalize_bos_conformance_result(bos_result) when is_map(bos_result) do
    fitness = bos_result["fitness"] || 0.0
    violations = bos_result["violations"] || []

    if violations != [] do
      Enum.map(violations, fn v ->
        %{"deviation" => v, "type" => "violation", "source" => "businessos"}
      end)
    else
      # Represent fitness gap as a synthetic deviation for compatibility
      if fitness < 1.0 do
        [
          %{
            "fitness" => fitness,
            "precision" => bos_result["precision"] || 0.0,
            "type" => "fitness_gap",
            "severity" => Float.round(1.0 - fitness, 4),
            "source" => "businessos"
          }
        ]
      else
        []
      end
    end
  end

  defp normalize_bos_conformance_result(_other), do: []
end
