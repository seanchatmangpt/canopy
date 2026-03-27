defmodule Canopy.JTBD.Scenarios.Scenario5Test do
  use ExUnit.Case, async: false

  @workspace_id "test-workspace-5"

  describe "workspace_sync scenario" do
    @tag :jtbd
    @tag :requires_osa
    test "syncs workspace state from Canopy to OSA with outcome=success" do
      # RED: This test fails because Canopy.JTBD.Runner doesn't exist yet
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:workspace_sync, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert result.span_emitted == true
      assert result.system == :osa
      assert result.latency_ms < 1500
    end

    test "records workspace state sync lifecycle phases" do
      # RED: Scenario runner must track prepare → transfer → verify phases
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:workspace_sync, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert length(result.transitions) >= 3
      assert :prepare_sync in result.transitions
      assert :transfer_state in result.transitions
      assert :verify_consistency in result.transitions
    end

    test "captures workspace state snapshot and delta in span attributes" do
      # RED: Span must record workspace state hash and change count
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:workspace_sync, workspace_id: @workspace_id)

      assert result.span_attributes.workspace_id == @workspace_id
      assert is_binary(result.span_attributes.state_hash)
      assert is_integer(result.span_attributes.delta_count)
      assert result.span_attributes.delta_count >= 0
    end

    test "validates state consistency after sync" do
      # RED: Result must include consistency check status
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:workspace_sync, workspace_id: @workspace_id)

      assert result.span_attributes.consistency_check == :passed
      assert result.span_attributes.source_state_hash == result.span_attributes.target_state_hash
    end
  end
end
