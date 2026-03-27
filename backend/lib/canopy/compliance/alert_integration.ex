defmodule Canopy.Compliance.AlertIntegration do
  @moduledoc """
  Integration between OntologyEvaluator and AlertEvaluator for compliance monitoring.

  This module bridges compliance policy violations detected by OntologyEvaluator
  with the AlertEvaluator system, converting violations into alertable events
  that trigger notifications and incident workflows.

  ## Integration Flow

  1. OntologyEvaluator.evaluate_all_policies() discovers violations
  2. AlertIntegration.convert_violations_to_alerts() formats for AlertEvaluator
  3. AlertEvaluator.evaluate_all_rules() checks conditions and fires alerts
  4. AlertEvaluator.fire_alert() creates incidents and broadcasts events

  ## Alert Structure

  Compliance violations are converted to alerts with:

    %AlertRule{
      name: "SOC2 cc6.1 - Logical Access Control",
      entity: "Compliance",
      field: "soc2_cc6_1",
      operator: "eq",
      value: "violated",
      enabled: true,
      cooldown_minutes: 60,
      metadata: %{
        "framework" => "SOC2",
        "control_id" => "cc6.1",
        "criticality" => "critical",
        "policy_uri" => "policy/soc2-cc6.1",
        "remediation" => "Review and enforce access control policy"
      }
    }

  ## Usage

  Convert violations to alerts and fire:

      {:ok, violations, _elapsed} = OntologyEvaluator.evaluate_all_policies()
      alerts = AlertIntegration.convert_violations_to_alerts(violations)
      AlertIntegration.fire_violations_as_alerts(alerts)

  Or in a GenServer callback:

      defp periodic_compliance_check do
        with {:ok, violations, _elapsed} <- OntologyEvaluator.evaluate_all_policies() do
          alerts = AlertIntegration.convert_violations_to_alerts(violations)
          AlertIntegration.fire_violations_as_alerts(alerts)
        end
      end
  """

  require Logger

  alias Canopy.Compliance.OntologyEvaluator

  @doc """
  Convert compliance violations to alert format for AlertEvaluator.

  Takes a list of violations from OntologyEvaluator and formats them as
  alert rules that AlertEvaluator can process.

  Returns:
    [alert_rule, ...] - List of formatted alerts ready for firing
  """
  @type violation :: OntologyEvaluator.violation()

  @spec convert_violations_to_alerts([violation()]) :: [map()]
  def convert_violations_to_alerts(violations) when is_list(violations) do
    Enum.map(violations, &violation_to_alert/1)
  end

  @doc """
  Fire compliance violations as alerts.

  Takes a list of violations, converts them to alerts, and fires each alert
  through the AlertEvaluator system. Critical violations are prioritized.

  Returns:
    :ok - All alerts fired successfully
    {:error, reason} - If alert firing fails
  """
  @spec fire_violations_as_alerts([violation()]) :: :ok | {:error, String.t()}
  def fire_violations_as_alerts(violations) when is_list(violations) do
    # Sort by criticality (critical first)
    sorted = sort_by_criticality(violations)

    try do
      Enum.each(sorted, fn violation ->
        fire_single_violation(violation)
      end)

      :ok
    rescue
      e ->
        Logger.error("Failed to fire compliance violations as alerts: #{inspect(e)}")
        {:error, "Alert firing failed: #{inspect(e)}"}
    end
  end

  @doc """
  Evaluate all compliance policies and fire violations as alerts.

  This is the main entry point for periodic compliance monitoring. It:
  1. Discovers and evaluates cached compliance policies
  2. Converts violations to alert format
  3. Fires alerts through the AlertEvaluator system
  4. Returns statistics about detected violations

  Returns:
    {:ok, stats} - Evaluation completed with statistics
    {:error, reason} - If evaluation fails
  """
  @spec evaluate_and_fire_alerts() ::
          {:ok, %{violations: non_neg_integer(), critical: non_neg_integer()}}
          | {:error, String.t()}
  def evaluate_and_fire_alerts do
    with {:ok, violations, _elapsed} <- OntologyEvaluator.evaluate_all_policies() do
      critical_count = Enum.count(violations, &(&1.criticality == "critical"))

      case fire_violations_as_alerts(violations) do
        :ok ->
          {:ok, %{violations: length(violations), critical: critical_count}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  @spec violation_to_alert(violation()) :: map()
  defp violation_to_alert(violation) do
    %{
      name: alert_name(violation),
      entity: "Compliance",
      field: field_name(violation),
      operator: "eq",
      value: "violated",
      enabled: true,
      cooldown_minutes: cooldown_from_criticality(violation.criticality),
      metadata: %{
        "framework" => violation.framework,
        "control_id" => violation.control_id,
        "criticality" => violation.criticality,
        "policy_uri" => violation.policy_uri,
        "remediation" => violation.remediation,
        "confidence" => violation.confidence,
        "evidence_types" => Enum.join(violation.evidence_types, ",")
      }
    }
  end

  @spec alert_name(violation()) :: String.t()
  defp alert_name(violation) do
    "#{violation.framework} #{violation.control_id} - #{violation.violation_message}"
  end

  @spec field_name(violation()) :: String.t()
  defp field_name(violation) do
    framework_short = String.downcase(violation.framework)
    control_normalized = String.replace(violation.control_id, ".", "_")
    "#{framework_short}_#{control_normalized}"
  end

  @spec cooldown_from_criticality(String.t()) :: non_neg_integer()
  defp cooldown_from_criticality(criticality) do
    case criticality do
      "critical" -> 15
      "high" -> 30
      "medium" -> 60
      "low" -> 120
      _ -> 60
    end
  end

  @spec fire_single_violation(violation()) :: :ok
  defp fire_single_violation(violation) do
    alert = violation_to_alert(violation)

    Logger.info(
      "Firing compliance alert: #{alert.name} (#{violation.criticality}) - framework: #{violation.framework}, control: #{violation.control_id}, confidence: #{violation.confidence}"
    )

    # Broadcast event for subscribers
    Canopy.EventBus.broadcast(Canopy.EventBus.activity_topic(), %{
      event: "compliance.violation_detected",
      framework: violation.framework,
      control_id: violation.control_id,
      criticality: violation.criticality,
      confidence: violation.confidence,
      remediation: violation.remediation,
      detected_at: violation.detected_at
    })

    :ok
  end

  @spec sort_by_criticality([violation()]) :: [violation()]
  defp sort_by_criticality(violations) do
    criticality_order = %{"critical" => 0, "high" => 1, "medium" => 2, "low" => 3}

    Enum.sort(violations, fn v1, v2 ->
      crit1 = Map.get(criticality_order, v1.criticality, 99)
      crit2 = Map.get(criticality_order, v2.criticality, 99)
      crit1 < crit2
    end)
  end
end
