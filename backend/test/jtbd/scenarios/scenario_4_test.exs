defmodule Canopy.JTBD.Scenarios.Scenario4Test do
  use ExUnit.Case, async: false

  @workspace_id "test-workspace-4"

  describe "cross_system_handoff scenario" do
    @tag :jtbd
    @tag :requires_osa
    @tag :requires_businessos
    test "completes Canopy→OSA→BusinessOS chain call with outcome=success" do
      # RED: This test fails because Canopy.JTBD.Runner doesn't exist yet
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:cross_system_handoff, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert result.span_emitted == true
      assert result.system == :businessos
      assert result.latency_ms < 2000
    end

    test "records chain handoff transitions across all three systems" do
      # RED: Scenario runner must track Canopy → OSA → BusinessOS transitions
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:cross_system_handoff, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert length(result.transitions) >= 3
      assert :canopy_initiate in result.transitions
      assert :osa_accept in result.transitions
      assert :businessos_complete in result.transitions
    end

    test "propagates cross-system context through all integration points" do
      # RED: Span must capture service chain and handoff context
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:cross_system_handoff, workspace_id: @workspace_id)

      assert result.span_attributes.source_service == "canopy"
      assert result.span_attributes.intermediate_service == "osa"
      assert result.span_attributes.target_service == "businessos"
      assert result.span_attributes.workspace_id == @workspace_id
      assert is_binary(result.span_attributes.trace_id)
    end

    test "maintains trace identity across system boundaries" do
      # RED: Same trace_id must flow through all three systems
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:cross_system_handoff, workspace_id: @workspace_id)

      assert is_binary(result.span_attributes.trace_id)
      assert String.length(result.span_attributes.trace_id) > 0
      assert result.span_attributes.span_id != nil
      assert result.span_attributes.parent_span_id != nil
    end
  end
end
