defmodule Canopy.JTBD.Scenarios.Scenario3Test do
  use ExUnit.Case, async: false

  @workspace_id "test-workspace-3"

  describe "compliance_check scenario" do
    @describetag :jtbd
    @describetag :requires_businessos
    test "returns compliance status with framework coverage" do
      # RED: This test fails because Canopy.JTBD.Runner doesn't exist yet
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:compliance_check, workspace_id: @workspace_id, framework: :soc2)

      assert result.outcome == :success
      assert result.span_emitted == true
      assert result.system == :businessos
      assert result.latency_ms < 1000
    end

    test "emits compliance.check span with soc2 and gdpr status" do
      # RED: BusinessOS must return status for SOC2, HIPAA, GDPR compliance
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:compliance_check, workspace_id: @workspace_id, framework: :soc2)

      assert result.outcome == :success
      assert result.span_attributes.framework == "soc2"
      assert result.span_attributes.compliance_status in [:compliant, :non_compliant, :partial]
      assert is_binary(result.span_attributes.last_audit_date)
    end

    test "captures audit findings count and remediation status" do
      # RED: Compliance check must return gap count and remediation tracking
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:compliance_check, workspace_id: @workspace_id, framework: :soc2)

      assert result.outcome == :success
      assert is_integer(result.span_attributes.findings_count)
      assert result.span_attributes.findings_count >= 0
      assert result.span_attributes.remediation_progress >= 0.0
      assert result.span_attributes.remediation_progress <= 1.0
    end
  end
end
