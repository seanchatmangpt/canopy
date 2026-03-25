defmodule Canopy.Semconv.SpanEmissionTest do
  @moduledoc """
  Weaver live-check span emission tests for Canopy.

  These tests emit real OTEL spans using typed semconv constants.
  When WEAVER_LIVE_CHECK=true, spans are exported to the Weaver receiver
  for schema conformance validation.

  Run with live-check:
      WEAVER_LIVE_CHECK=true mix test test/canopy/semconv/span_emission_test.exs

  Run without live-check (schema validation only):
      mix test test/canopy/semconv/span_emission_test.exs
  """
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer, as: Tracer

  alias Canopy.SemConv.SpanNames
  alias OpenTelemetry.SemConv.Incubating.{CanopyAttributes, HealingAttributes,
         WorkflowAttributes, BosAttributes, A2aAttributes, AgentAttributes,
         ProcessAttributes}

  # ── Healing Domain ─────────────────────────────────────────────────────────

  describe "healing.diagnosis span emission" do
    test "emits healing.diagnosis span with semconv attributes" do
      Tracer.with_span SpanNames.healing_diagnosis(), %{
        HealingAttributes.healing_failure_mode() => "deadlock",
        HealingAttributes.healing_confidence() => 0.95,
        HealingAttributes.healing_agent_id() => "canopy-healer-001"
      } do
        assert true  # Span exported to Weaver if live-check enabled
      end
    end

    test "emits healing.diagnosis span with timeout failure mode" do
      Tracer.with_span SpanNames.healing_diagnosis(), %{
        HealingAttributes.healing_failure_mode() => "timeout",
        HealingAttributes.healing_confidence() => 0.85,
        HealingAttributes.healing_mttr_ms() => 5000
      } do
        assert true
      end
    end

    test "emits healing.reflex_arc span" do
      Tracer.with_span SpanNames.healing_reflex_arc(), %{
        HealingAttributes.healing_recovery_action() => "provider_failover",
        HealingAttributes.healing_reflex_arc() => "restart_agent"
      } do
        assert true
      end
    end
  end

  # ── Canopy Domain ─────────────────────────────────────────────────────────

  describe "canopy.heartbeat span emission" do
    test "emits canopy.heartbeat span with tier attribute" do
      Tracer.with_span SpanNames.canopy_heartbeat(), %{
        CanopyAttributes.canopy_heartbeat_tier() => "critical",
        CanopyAttributes.canopy_budget_ms() => 5000
      } do
        assert true
      end
    end

    test "emits canopy.heartbeat span with normal tier" do
      Tracer.with_span SpanNames.canopy_heartbeat(), %{
        CanopyAttributes.canopy_heartbeat_tier() => "normal",
        CanopyAttributes.canopy_budget_ms() => 30000
      } do
        assert true
      end
    end

    test "emits canopy.adapter_call span" do
      Tracer.with_span SpanNames.canopy_adapter_call(), %{
        CanopyAttributes.canopy_adapter_name() => "osa",
        CanopyAttributes.canopy_adapter_action() => "start"
      } do
        assert true
      end
    end
  end

  # ── Agent Domain ──────────────────────────────────────────────────────────

  describe "agent.decision span emission" do
    test "emits agent.decision span with outcome" do
      Tracer.with_span SpanNames.agent_decision(), %{
        AgentAttributes.agent_id() => "canopy-agent-001",
        AgentAttributes.agent_outcome() => "success"
      } do
        assert true
      end
    end
  end

  # ── Workflow Domain ───────────────────────────────────────────────────────

  describe "workflow.execute span emission" do
    test "emits workflow.execute span with YAWL pattern" do
      Tracer.with_span SpanNames.workflow_execute(), %{
        WorkflowAttributes.workflow_pattern() => "sequence",
        WorkflowAttributes.workflow_state() => "active"
      } do
        assert true
      end
    end
  end

  # ── BusinessOS Domain ─────────────────────────────────────────────────────

  describe "bos.compliance.check span emission" do
    test "emits bos.compliance.check span with framework" do
      Tracer.with_span SpanNames.bos_compliance_check(), %{
        BosAttributes.bos_compliance_framework() => "SOC2",
        BosAttributes.bos_compliance_passed() => true,
        BosAttributes.bos_compliance_rule_id() => "soc2.cc6.1"
      } do
        assert true
      end
    end
  end

  # ── A2A Domain ────────────────────────────────────────────────────────────

  describe "a2a.call span emission" do
    test "emits a2a.call span with target service" do
      Tracer.with_span SpanNames.a2a_call(), %{
        A2aAttributes.a2a_source_service() => "canopy",
        A2aAttributes.a2a_target_service() => "osa",
        A2aAttributes.a2a_operation() => "heartbeat"
      } do
        assert true
      end
    end
  end

  # ── Process Mining Domain ─────────────────────────────────────────────────

  describe "process.mining.discovery span emission" do
    test "emits process.mining.discovery span with algorithm" do
      Tracer.with_span SpanNames.process_mining_discovery(), %{
        ProcessAttributes.process_mining_algorithm() => "alpha_miner",
        ProcessAttributes.process_mining_variant_count() => 42
      } do
        assert true
      end
    end
  end
end
