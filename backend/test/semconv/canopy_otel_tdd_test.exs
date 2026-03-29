defmodule Canopy.Semconv.OtelTddTest do
  @moduledoc """
  Chicago TDD validation for Canopy OTel Weaver semconv constants.

  These tests validate that the heartbeat and adapter signals use schema-correct attribute names.
  Third proof layer: schema conformance via typed constants.

  Run with: mix test test/semconv/canopy_otel_tdd_test.exs --no-start
  """
  use ExUnit.Case, async: true

  alias OpenTelemetry.SemConv.Incubating.CanopyAttributes
  alias OpenTelemetry.SemConv.Incubating.WorkflowAttributes
  alias OpenTelemetry.SemConv.Incubating.A2aAttributes
  alias OpenTelemetry.SemConv.Incubating.HealingAttributes
  alias OpenTelemetry.SemConv.Incubating.BosAttributes
  alias Canopy.SemConv.SpanNames

  # ── Domain: Canopy (heartbeat + adapter) ───────────────────────────────────

  describe "CanopyAttributes — heartbeat and adapter keys" do
    @tag :unit
    test "canopy_heartbeat_tier key is correct OTel attribute name" do
      assert CanopyAttributes.canopy_heartbeat_tier() == :"canopy.heartbeat.tier"
    end

    @tag :unit
    test "canopy_adapter_name key is correct OTel attribute name" do
      assert CanopyAttributes.canopy_adapter_name() == :"canopy.adapter.name"
    end

    @tag :unit
    test "canopy_adapter_action key is correct OTel attribute name" do
      assert CanopyAttributes.canopy_adapter_action() == :"canopy.adapter.action"
    end

    @tag :unit
    test "canopy_budget_ms key is correct OTel attribute name" do
      assert CanopyAttributes.canopy_budget_ms() == :"canopy.budget.ms"
    end

    @tag :unit
    test "heartbeat tier critical value matches schema" do
      assert CanopyAttributes.canopy_heartbeat_tier_values().critical == :critical
    end

    @tag :unit
    test "heartbeat tier high value matches schema" do
      assert CanopyAttributes.canopy_heartbeat_tier_values().high == :high
    end

    @tag :unit
    test "heartbeat tier normal value matches schema" do
      assert CanopyAttributes.canopy_heartbeat_tier_values().normal == :normal
    end

    @tag :unit
    test "heartbeat tier low value matches schema" do
      assert CanopyAttributes.canopy_heartbeat_tier_values().low == :low
    end

    @tag :unit
    test "all 4 heartbeat tiers defined in schema" do
      values = CanopyAttributes.canopy_heartbeat_tier_values()
      assert map_size(values) == 4
    end
  end

  # ── Domain: Healing ────────────────────────────────────────────────────────

  describe "HealingAttributes — failure mode classification keys" do
    @tag :unit
    test "healing_failure_mode key is correct OTel attribute name" do
      assert HealingAttributes.healing_failure_mode() == :"healing.failure_mode"
    end

    @tag :unit
    test "healing_confidence key is correct OTel attribute name" do
      assert HealingAttributes.healing_confidence() == :"healing.confidence"
    end

    @tag :unit
    test "healing_mttr_ms key is correct OTel attribute name" do
      assert HealingAttributes.healing_mttr_ms() == :"healing.mttr_ms"
    end

    @tag :unit
    test "healing_agent_id key is correct OTel attribute name" do
      assert HealingAttributes.healing_agent_id() == :"healing.agent_id"
    end

    @tag :unit
    test "healing_recovery_action key is correct OTel attribute name" do
      assert HealingAttributes.healing_recovery_action() == :"healing.recovery_action"
    end

    @tag :unit
    test "healing_reflex_arc key is correct OTel attribute name" do
      assert HealingAttributes.healing_reflex_arc() == :"healing.reflex_arc"
    end

    @tag :unit
    test "healing failure mode deadlock value matches schema" do
      assert HealingAttributes.healing_failure_mode_values().deadlock == :deadlock
    end

    @tag :unit
    test "healing failure mode timeout value matches schema" do
      assert HealingAttributes.healing_failure_mode_values().timeout == :timeout
    end

    @tag :unit
    test "healing failure mode race_condition value matches schema" do
      assert HealingAttributes.healing_failure_mode_values().race_condition == :race_condition
    end

    @tag :unit
    test "healing failure mode stagnation value matches schema" do
      assert HealingAttributes.healing_failure_mode_values().stagnation == :stagnation
    end

    @tag :unit
    test "all 7 healing failure modes defined in schema" do
      values = HealingAttributes.healing_failure_mode_values()
      assert map_size(values) == 7
    end
  end

  # ── Domain: Workflow (YAWL) ────────────────────────────────────────────────

  describe "WorkflowAttributes — YAWL workflow patterns available in Canopy" do
    @tag :unit
    test "workflow_engine key is correct OTel attribute name" do
      assert WorkflowAttributes.workflow_engine() == :"workflow.engine"
    end

    @tag :unit
    test "workflow_id key is correct OTel attribute name" do
      assert WorkflowAttributes.workflow_id() == :"workflow.id"
    end

    @tag :unit
    test "workflow_name key is correct OTel attribute name" do
      assert WorkflowAttributes.workflow_name() == :"workflow.name"
    end

    @tag :unit
    test "workflow_pattern key is correct OTel attribute name" do
      assert WorkflowAttributes.workflow_pattern() == :"workflow.pattern"
    end

    @tag :unit
    test "workflow_state key is correct OTel attribute name" do
      assert WorkflowAttributes.workflow_state() == :"workflow.state"
    end

    @tag :unit
    test "workflow_step key is correct OTel attribute name" do
      assert WorkflowAttributes.workflow_step() == :"workflow.step"
    end

    @tag :unit
    test "workflow_engine canopy value matches schema" do
      assert WorkflowAttributes.workflow_engine_values().canopy == :canopy
    end

    @tag :unit
    test "workflow_pattern sequence value available" do
      assert WorkflowAttributes.workflow_pattern_values().sequence == :sequence
    end

    @tag :unit
    test "workflow_pattern parallel_split value available" do
      assert WorkflowAttributes.workflow_pattern_values().parallel_split == :parallel_split
    end

    @tag :unit
    test "workflow_state active value available" do
      assert WorkflowAttributes.workflow_state_values().active == :active
    end

    @tag :unit
    test "workflow_state completed value available" do
      assert WorkflowAttributes.workflow_state_values().completed == :completed
    end

    @tag :unit
    test "workflow_state failed value available" do
      assert WorkflowAttributes.workflow_state_values().failed == :failed
    end

    @tag :unit
    test "all YAWL workflow patterns defined in schema" do
      values = WorkflowAttributes.workflow_pattern_values()
      # Schema defines 23 YAWL patterns (not 8)
      assert map_size(values) == 23
    end
  end

  # ── Domain: BusinessOS (bos) ───────────────────────────────────────────────

  describe "BosAttributes — BusinessOS compliance and decision keys" do
    @tag :unit
    test "bos_compliance_framework key is correct OTel attribute name" do
      assert BosAttributes.bos_compliance_framework() == :"bos.compliance.framework"
    end

    @tag :unit
    test "bos_compliance_passed key is correct OTel attribute name" do
      assert BosAttributes.bos_compliance_passed() == :"bos.compliance.passed"
    end

    @tag :unit
    test "bos_compliance_rule_id key is correct OTel attribute name" do
      assert BosAttributes.bos_compliance_rule_id() == :"bos.compliance.rule_id"
    end

    @tag :unit
    test "bos_compliance_severity key is correct OTel attribute name" do
      assert BosAttributes.bos_compliance_severity() == :"bos.compliance.severity"
    end

    @tag :unit
    test "bos_decision_id key is correct OTel attribute name" do
      assert BosAttributes.bos_decision_id() == :"bos.decision.id"
    end

    @tag :unit
    test "bos_decision_type key is correct OTel attribute name" do
      assert BosAttributes.bos_decision_type() == :"bos.decision.type"
    end

    @tag :unit
    test "bos_workspace_id key is correct OTel attribute name" do
      assert BosAttributes.bos_workspace_id() == :"bos.workspace.id"
    end

    @tag :unit
    test "bos_workspace_name key is correct OTel attribute name" do
      assert BosAttributes.bos_workspace_name() == :"bos.workspace.name"
    end

    @tag :unit
    test "bos_agent_service key is correct OTel attribute name" do
      assert BosAttributes.bos_agent_service() == :"bos.agent.service"
    end

    @tag :unit
    test "bos compliance framework SOC2 value matches schema" do
      assert BosAttributes.bos_compliance_framework_values().soc2 == :SOC2
    end

    @tag :unit
    test "bos compliance framework HIPAA value matches schema" do
      assert BosAttributes.bos_compliance_framework_values().hipaa == :HIPAA
    end

    @tag :unit
    test "bos compliance severity critical value matches schema" do
      assert BosAttributes.bos_compliance_severity_values().critical == :critical
    end

    @tag :unit
    test "bos decision type architectural value matches schema" do
      assert BosAttributes.bos_decision_type_values().architectural == :architectural
    end

    @tag :unit
    test "all compliance frameworks defined in schema" do
      values = BosAttributes.bos_compliance_framework_values()
      # Schema defines 5 frameworks (SOC2, HIPAA, GDPR, SOX, CUSTOM)
      assert map_size(values) == 5
    end
  end

  # ── Domain: A2A (inter-system calls from Canopy) ───────────────────────────

  describe "A2aAttributes — inter-system calls from Canopy" do
    @tag :unit
    test "a2a_agent_id key is correct OTel attribute name" do
      assert A2aAttributes.a2a_agent_id() == :"a2a.agent.id"
    end

    @tag :unit
    test "a2a_source_service key is correct OTel attribute name" do
      assert A2aAttributes.a2a_source_service() == :"a2a.source.service"
    end

    @tag :unit
    test "a2a_target_service key is correct OTel attribute name" do
      assert A2aAttributes.a2a_target_service() == :"a2a.target.service"
    end

    @tag :unit
    test "a2a_operation key is correct OTel attribute name" do
      assert A2aAttributes.a2a_operation() == :"a2a.operation"
    end

    @tag :unit
    test "a2a_deal_id key is correct OTel attribute name" do
      assert A2aAttributes.a2a_deal_id() == :"a2a.deal.id"
    end
  end

  # ── Span names ─────────────────────────────────────────────────────────────

  describe "SpanNames — Canopy-domain span name constants" do
    @tag :unit
    test "canopy_heartbeat span name matches schema" do
      assert SpanNames.canopy_heartbeat() == "canopy.heartbeat"
    end

    @tag :unit
    test "canopy_adapter_call span name matches schema" do
      assert SpanNames.canopy_adapter_call() == "canopy.adapter_call"
    end

    @tag :unit
    test "workflow_execute span name matches schema" do
      assert SpanNames.workflow_execute() == "workflow.execute"
    end

    @tag :unit
    test "bos_compliance_check span name matches schema" do
      assert SpanNames.bos_compliance_check() == "bos.compliance.check"
    end

    @tag :unit
    test "healing_diagnosis span name matches schema" do
      assert SpanNames.healing_diagnosis() == "healing.diagnosis"
    end
  end
end
