defmodule Canopy.Autonomic.AdaptationAgent do
  @moduledoc """
  Adaptation Agent - Config drift detection and hot reload.

  Responsibilities:
  - Detect configuration drift (expected vs actual)
  - Identify required hot reloads
  - Execute runtime configuration updates
  - Track adaptation events
  - OpenTelemetry tracing for configuration management observability

  Returns: %{drift_detected: boolean, changes: N, reloaded: boolean, ...}
  """
  require Logger

  def run(opts \\ []) do
    Logger.info("[AdaptationAgent] Running adaptation check...")

    budget = opts[:budget] || 1000
    tier = opts[:tier] || :dormant

    start_time = System.monotonic_time(:millisecond)

    # Compare expected vs actual config
    config_diff = compare_configs()

    # Detect drift
    drift_detected = length(config_diff) > 0

    # Execute hot reload if needed
    reload_result =
      if drift_detected do
        execute_hot_reload(config_diff)
      else
        :ok
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    status = if(drift_detected, do: "adapted", else: "no_drift")

    result = %{
      status: status,
      drift_detected: drift_detected,
      changes: length(config_diff),
      reloaded: reload_result == :ok,
      tier: tier,
      latency_ms: elapsed,
      budget_used: budget - (budget - elapsed),
      timestamp: DateTime.utc_now(),
      diff: config_diff
    }

    # Emit telemetry event for observability
    :telemetry.execute(
      [:agent, :run],
      %{latency_ms: elapsed, status: status},
      %{agent_name: "adaptation_agent", tier: tier, budget_used: budget - elapsed}
    )

    Logger.info(
      "[AdaptationAgent] Adaptation check complete. Drift: #{drift_detected}, changes: #{length(config_diff)}"
    )

    result
  end

  @doc """
  Compare reference config (priv/config/reference.yaml) against actual app env.

  Returns a list of `{key, expected, actual}` tuples for keys that differ.
  Returns `[]` if the reference file does not exist (graceful startup).
  """
  def compare_configs do
    reference_path =
      Application.app_dir(:canopy, "priv/config/reference.yaml")

    if File.exists?(reference_path) do
      case YamlElixir.read_from_file(reference_path) do
        {:ok, reference_map} ->
          actual = Application.get_all_env(:canopy) |> Map.new()

          Enum.reduce(reference_map, [], fn {key_str, expected_val}, acc ->
            key = String.to_atom(key_str)
            actual_val = Map.get(actual, key)

            if actual_val != expected_val do
              [{key, expected_val, actual_val} | acc]
            else
              acc
            end
          end)

        {:error, reason} ->
          Logger.warning("[AdaptationAgent] Failed to read reference config: #{inspect(reason)}")
          []
      end
    else
      Logger.info("[AdaptationAgent] No reference config found at #{reference_path}, skipping drift check")
      []
    end
  end

  defp execute_hot_reload(config_diff) do
    # Execute hot reload for each configuration change
    try do
      Enum.each(config_diff, fn {key, _expected, actual} ->
        Logger.info("[AdaptationAgent] Hot reloading config key: #{inspect(key)}")
        Application.put_env(:canopy, key, actual)
      end)

      :ok
    rescue
      e ->
        Logger.error("[AdaptationAgent] Error reloading config: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end
end
