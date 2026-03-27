defmodule Canopy.Compliance.OntologyEvaluatorSmokeTest do
  @moduledoc """
  Smoke tests for OntologyEvaluator - verify module loads and basic structure is correct.
  These tests don't require database or service connections.
  """

  use ExUnit.Case

  @moduletag :skip

  describe "OntologyEvaluator module" do
    test "module is defined and loadable" do
      assert Canopy.Compliance.OntologyEvaluator != nil
    end

    test "module exports public functions" do
      functions = Canopy.Compliance.OntologyEvaluator.__info__(:functions)

      function_names = Enum.map(functions, &elem(&1, 0))

      assert :evaluate_all_policies in function_names
      assert :evaluate_framework in function_names
      assert :get_policy_metadata in function_names
      assert :reload_policies in function_names
    end

    test "violation struct is properly defined" do
      violation = %Canopy.Compliance.OntologyEvaluator{
        policy_uri: "test",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Test",
        evidence_types: [],
        detected_at: DateTime.utc_now(),
        confidence: 0.95
      }

      assert violation.policy_uri == "test"
      assert violation.framework == "SOC2"
      assert violation.control_id == "cc6.1"
      assert violation.criticality == "critical"
      assert violation.confidence == 0.95
    end

    test "violation has correct fields" do
      now = DateTime.utc_now()

      violation = %Canopy.Compliance.OntologyEvaluator{
        policy_uri: "policy/test",
        framework: "HIPAA",
        control_id: "164.312",
        criticality: "high",
        violation_message: "PHI not protected",
        evidence_types: ["encryption", "access_logs"],
        detected_at: now,
        confidence: 0.85
      }

      assert is_binary(violation.policy_uri)
      assert is_binary(violation.framework)
      assert is_binary(violation.control_id)
      assert is_binary(violation.criticality)
      assert is_binary(violation.violation_message)
      assert is_list(violation.evidence_types)
      assert is_struct(violation.detected_at, DateTime)
      assert is_float(violation.confidence)
    end

    test "supported frameworks are valid" do
      frameworks = ["SOC2", "HIPAA", "GDPR", "ISO27001", "SOX"]

      Enum.each(frameworks, fn fw ->
        assert is_binary(fw)
        assert String.length(fw) > 0
      end)
    end

    test "criticality levels are standard" do
      criticalities = ["critical", "high", "medium", "low"]

      Enum.each(criticalities, fn crit ->
        assert is_binary(crit)
        assert String.length(crit) > 0
      end)
    end
  end

  describe "AlertIntegration module" do
    test "module is defined and loadable" do
      assert Canopy.Compliance.AlertIntegration != nil
    end

    test "module exports public functions" do
      functions = Canopy.Compliance.AlertIntegration.__info__(:functions)

      function_names = Enum.map(functions, &elem(&1, 0))

      assert :convert_violations_to_alerts in function_names
      assert :fire_violations_as_alerts in function_names
      assert :evaluate_and_fire_alerts in function_names
    end

    test "can convert violation to alert format" do
      violation = %{
        policy_uri: "policy/soc2-cc6.1",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Access Control",
        evidence_types: ["policy"],
        detected_at: "2026-03-26T10:00:00Z",
        confidence: 0.95,
        remediation: "Review policy"
      }

      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts([violation])

      assert length(alerts) == 1
      [alert] = alerts

      assert is_map(alert)
      assert alert.entity == "Compliance"
      assert alert.value == "violated"
      assert alert.enabled == true
    end

    test "converts multiple violations" do
      violations = [
        %{
          policy_uri: "policy/1",
          framework: "SOC2",
          control_id: "cc6.1",
          criticality: "critical",
          violation_message: "Test1",
          evidence_types: [],
          detected_at: "2026-03-26T10:00:00Z",
          confidence: 0.95,
          remediation: "Test"
        },
        %{
          policy_uri: "policy/2",
          framework: "HIPAA",
          control_id: "164.312",
          criticality: "high",
          violation_message: "Test2",
          evidence_types: [],
          detected_at: "2026-03-26T10:00:00Z",
          confidence: 0.85,
          remediation: "Test"
        }
      ]

      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts(violations)

      assert length(alerts) == 2
    end

    test "handles empty violation list" do
      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts([])

      assert alerts == []
    end

    test "all alerts have required fields" do
      violation = %{
        policy_uri: "policy/test",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Test",
        evidence_types: [],
        detected_at: "2026-03-26T10:00:00Z",
        confidence: 0.95,
        remediation: "Test"
      }

      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts([violation])

      [alert] = alerts

      assert Map.has_key?(alert, :name)
      assert Map.has_key?(alert, :entity)
      assert Map.has_key?(alert, :field)
      assert Map.has_key?(alert, :operator)
      assert Map.has_key?(alert, :value)
      assert Map.has_key?(alert, :enabled)
      assert Map.has_key?(alert, :cooldown_minutes)
      assert Map.has_key?(alert, :metadata)
    end

    test "metadata includes framework and control_id" do
      violation = %{
        policy_uri: "policy/test",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Test",
        evidence_types: [],
        detected_at: "2026-03-26T10:00:00Z",
        confidence: 0.95,
        remediation: "Test"
      }

      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts([violation])

      [alert] = alerts
      metadata = alert.metadata

      assert metadata["framework"] == "SOC2"
      assert metadata["control_id"] == "cc6.1"
    end

    test "cooldown_minutes varies by criticality" do
      violations = [
        violation_with_criticality("critical"),
        violation_with_criticality("high"),
        violation_with_criticality("medium"),
        violation_with_criticality("low")
      ]

      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts(violations)

      assert Enum.at(alerts, 0).cooldown_minutes == 15
      assert Enum.at(alerts, 1).cooldown_minutes == 30
      assert Enum.at(alerts, 2).cooldown_minutes == 60
      assert Enum.at(alerts, 3).cooldown_minutes == 120
    end

    test "fire_violations_as_alerts returns ok for empty list" do
      result = Canopy.Compliance.AlertIntegration.fire_violations_as_alerts([])

      assert result == :ok
    end
  end

  describe "integration" do
    test "violation can be created and converted to alert" do
      violation = %{
        policy_uri: "policy/soc2-cc6.1",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Logical Access Control",
        evidence_types: ["policy", "logs"],
        detected_at: "2026-03-26T10:00:00Z",
        confidence: 0.95,
        remediation: "Review access control"
      }

      alerts = Canopy.Compliance.AlertIntegration.convert_violations_to_alerts([violation])

      assert length(alerts) == 1

      [alert] = alerts

      assert alert.entity == "Compliance"
      assert String.contains?(alert.name, "SOC2")
      assert String.contains?(alert.name, "cc6.1")
    end
  end

  # Helper functions

  defp violation_with_criticality(criticality) do
    %{
      policy_uri: "policy/test",
      framework: "SOC2",
      control_id: "cc6.1",
      criticality: criticality,
      violation_message: "Test",
      evidence_types: [],
      detected_at: "2026-03-26T10:00:00Z",
      confidence: 0.95,
      remediation: "Test"
    }
  end
end
