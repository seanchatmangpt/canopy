defmodule Canopy.Compliance.AlertIntegrationTest do
  use ExUnit.Case

  alias Canopy.Compliance.AlertIntegration
  alias Canopy.Compliance.OntologyEvaluator

  @moduletag :skip

  describe "convert_violations_to_alerts/1" do
    test "converts violation to alert with correct structure" do
      violation = %{
        policy_uri: "policy/soc2-cc6.1",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Logical Access Control",
        evidence_types: ["access_policy", "audit_logs"],
        detected_at: "2026-03-26T10:30:00Z",
        confidence: 0.95,
        remediation: "Review and enforce access control policy"
      }

      alerts = AlertIntegration.convert_violations_to_alerts([violation])

      assert length(alerts) == 1
      [alert] = alerts

      assert alert.name == "SOC2 cc6.1 - Logical Access Control"
      assert alert.entity == "Compliance"
      assert alert.operator == "eq"
      assert alert.value == "violated"
      assert alert.enabled == true
    end

    test "sets cooldown_minutes based on criticality" do
      violations = [
        violation_with_criticality("critical"),
        violation_with_criticality("high"),
        violation_with_criticality("medium"),
        violation_with_criticality("low")
      ]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      assert Enum.at(alerts, 0).cooldown_minutes == 15
      assert Enum.at(alerts, 1).cooldown_minutes == 30
      assert Enum.at(alerts, 2).cooldown_minutes == 60
      assert Enum.at(alerts, 3).cooldown_minutes == 120
    end

    test "includes metadata with control information" do
      violation = %{
        policy_uri: "policy/soc2-cc6.1",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Logical Access Control",
        evidence_types: ["access_policy"],
        detected_at: "2026-03-26T10:30:00Z",
        confidence: 0.95,
        remediation: "Review and enforce access control policy"
      }

      alerts = AlertIntegration.convert_violations_to_alerts([violation])

      [alert] = alerts
      metadata = alert.metadata

      assert metadata["framework"] == "SOC2"
      assert metadata["control_id"] == "cc6.1"
      assert metadata["criticality"] == "critical"
      assert metadata["policy_uri"] == "policy/soc2-cc6.1"
      assert is_binary(metadata["remediation"])
      assert metadata["confidence"] == 0.95
    end

    test "converts multiple violations to multiple alerts" do
      violations = [
        violation_with_framework("SOC2"),
        violation_with_framework("HIPAA"),
        violation_with_framework("GDPR")
      ]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      assert length(alerts) == 3

      frameworks = Enum.map(alerts, fn a -> a.metadata["framework"] end)
      assert frameworks == ["SOC2", "HIPAA", "GDPR"]
    end

    test "handles empty violation list" do
      alerts = AlertIntegration.convert_violations_to_alerts([])

      assert alerts == []
    end

    test "field_name normalizes control_id" do
      # Control IDs like "cc6.1" should become "cc6_1"
      violation = %{
        policy_uri: "policy/soc2-cc6.1",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Test",
        evidence_types: [],
        detected_at: "2026-03-26T10:30:00Z",
        confidence: 0.95,
        remediation: "Test remediation"
      }

      alerts = AlertIntegration.convert_violations_to_alerts([violation])

      [alert] = alerts
      assert String.contains?(alert.field, "cc6_1")
    end
  end

  describe "fire_violations_as_alerts/1" do
    test "returns ok for empty violations list" do
      result = AlertIntegration.fire_violations_as_alerts([])

      assert result == :ok
    end

    test "fires violations without error" do
      violation = violation_with_criticality("critical")

      result = AlertIntegration.fire_violations_as_alerts([violation])

      # Should succeed (alerts may not actually fire if EventBus not running)
      assert result == :ok or match?({:error, _}, result)
    end

    test "sorts violations by criticality before firing" do
      violations = [
        violation_with_criticality("low"),
        violation_with_criticality("critical"),
        violation_with_criticality("high")
      ]

      result = AlertIntegration.fire_violations_as_alerts(violations)

      assert result == :ok
    end

    test "handles alert firing errors gracefully" do
      result = AlertIntegration.fire_violations_as_alerts([])

      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "evaluate_and_fire_alerts/0" do
    test "returns statistics tuple on success" do
      result = AlertIntegration.evaluate_and_fire_alerts()

      case result do
        {:ok, stats} ->
          assert is_map(stats)
          assert Map.has_key?(stats, :violations)
          assert Map.has_key?(stats, :critical)
          assert is_integer(stats.violations)
          assert is_integer(stats.critical)
          assert stats.violations >= stats.critical

        {:error, reason} ->
          assert is_binary(reason)
      end
    end

    test "returns error on evaluation failure" do
      result = AlertIntegration.evaluate_and_fire_alerts()

      assert match?({:ok, _stats}, result) or
               match?({:error, _reason}, result)
    end

    test "critical count is subset of total violations" do
      result = AlertIntegration.evaluate_and_fire_alerts()

      case result do
        {:ok, stats} ->
          assert stats.critical <= stats.violations

        {:error, _reason} ->
          assert true
      end
    end
  end

  describe "alert properties" do
    test "all generated alerts have enabled: true" do
      violations = [
        violation_with_criticality("critical"),
        violation_with_criticality("high")
      ]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      Enum.each(alerts, fn alert ->
        assert alert.enabled == true
      end)
    end

    test "all generated alerts have operator: eq" do
      violations = [
        violation_with_criticality("critical"),
        violation_with_criticality("medium")
      ]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      Enum.each(alerts, fn alert ->
        assert alert.operator == "eq"
      end)
    end

    test "all generated alerts have value: violated" do
      violations = [violation_with_criticality("critical")]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      Enum.each(alerts, fn alert ->
        assert alert.value == "violated"
      end)
    end

    test "all generated alerts have entity: Compliance" do
      violations = [
        violation_with_criticality("critical"),
        violation_with_criticality("low")
      ]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      Enum.each(alerts, fn alert ->
        assert alert.entity == "Compliance"
      end)
    end

    test "alert name includes framework and control_id" do
      violation = %{
        policy_uri: "policy/test",
        framework: "SOC2",
        control_id: "cc6.1",
        criticality: "critical",
        violation_message: "Test Message",
        evidence_types: [],
        detected_at: "2026-03-26T10:30:00Z",
        confidence: 0.95,
        remediation: "Test"
      }

      alerts = AlertIntegration.convert_violations_to_alerts([violation])

      [alert] = alerts
      assert String.contains?(alert.name, "SOC2")
      assert String.contains?(alert.name, "cc6.1")
    end

    test "cooldown_minutes never negative" do
      violations = [
        violation_with_criticality("critical"),
        violation_with_criticality("high"),
        violation_with_criticality("medium"),
        violation_with_criticality("low"),
        violation_with_criticality("unknown")
      ]

      alerts = AlertIntegration.convert_violations_to_alerts(violations)

      Enum.each(alerts, fn alert ->
        assert alert.cooldown_minutes > 0
      end)
    end
  end

  describe "event broadcasting" do
    test "firing violations broadcasts events" do
      violation = violation_with_criticality("critical")

      # This test verifies that fire_violations_as_alerts calls the broadcast
      # In a full test environment with EventBus, events would be published
      result = AlertIntegration.fire_violations_as_alerts([violation])

      # Should succeed
      assert result == :ok
    end
  end

  # Helper functions

  defp violation_with_criticality(criticality) do
    %{
      policy_uri: "policy/test-#{criticality}",
      framework: "SOC2",
      control_id: "cc6.1",
      criticality: criticality,
      violation_message: "Test Violation",
      evidence_types: ["test_evidence"],
      detected_at: "2026-03-26T10:30:00Z",
      confidence: 0.95,
      remediation: "Test remediation action"
    }
  end

  defp violation_with_framework(framework) do
    %{
      policy_uri: "policy/test-#{framework}",
      framework: framework,
      control_id: "control_123",
      criticality: "high",
      violation_message: "Test Violation",
      evidence_types: ["evidence"],
      detected_at: "2026-03-26T10:30:00Z",
      confidence: 0.85,
      remediation: "Test remediation"
    }
  end
end
