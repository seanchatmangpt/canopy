defmodule Canopy.JTBD.Scenarios.Scenario6Test do
  use ExUnit.Case, async: false

  @workspace_id "test-workspace-6"
  @num_validators 4

  describe "consensus_round scenario" do
    @tag :jtbd
    @tag :requires_osa
    test "completes HotStuff BFT consensus round with outcome=success" do
      # RED: This test fails because Canopy.JTBD.Runner doesn't exist yet
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:consensus_round, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert result.span_emitted == true
      assert result.system == :osa
      assert result.latency_ms < 3000
    end

    test "records HotStuff consensus phases: propose → prepare → commit → decide" do
      # RED: Scenario runner must track all HotStuff phases with validator participation
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:consensus_round, workspace_id: @workspace_id)

      assert result.outcome == :success
      assert length(result.transitions) >= 4
      assert :propose in result.transitions
      assert :prepare in result.transitions
      assert :commit in result.transitions
      assert :decide in result.transitions
    end

    test "captures consensus quorum and validator agreement in span" do
      # RED: Span must record quorum size and voting agreement
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:consensus_round, workspace_id: @workspace_id)

      assert result.span_attributes.quorum_size == @num_validators
      assert result.span_attributes.agreement_count >= trunc(@num_validators * 0.67)
      assert is_binary(result.span_attributes.block_hash)
      assert is_integer(result.span_attributes.round_number)
    end

    test "validates BFT safety: all validators agree on final block" do
      # RED: Result must show Byzantine fault tolerance guarantee
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:consensus_round, workspace_id: @workspace_id)

      assert result.span_attributes.bft_safety == :satisfied
      assert result.span_attributes.faulty_validators_tolerated == 1
      assert is_binary(result.span_attributes.consensus_proof)
    end
  end
end
