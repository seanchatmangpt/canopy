defmodule Canopy.JTBD.Scenarios.Scenario1Test do
  use ExUnit.Case, async: false

  @workspace_id "test-workspace-1"

  describe "agent_decision_loop scenario" do
    @describetag :jtbd
    @describetag :requires_osa
    test "emits jtbd.scenario span with outcome=success" do
      # RED: This test fails because Canopy.JTBD.Runner doesn't exist yet
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:agent_decision_loop, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert result.span_emitted == true
      assert result.system == :osa
      assert result.latency_ms < 500
    end

    test "records ReAct loop completion with all step transitions" do
      # RED: Scenario runner must track ReAct loop phases (observe → think → act → conclude)
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:agent_decision_loop, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert length(result.transitions) >= 4
      assert :observe in result.transitions
      assert :think in result.transitions
      assert :act in result.transitions
      assert :conclude in result.transitions
    end

    test "propagates OSA service context to span attributes" do
      # RED: Span must capture OSA service identifier and session context
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:agent_decision_loop, workspace_id: @workspace_id)

      assert result.span_attributes.service == "osa"
      assert result.span_attributes.workspace_id == @workspace_id
      assert result.span_attributes.agent_id != nil
      assert is_binary(result.span_attributes.trace_id)
    end
  end
end
