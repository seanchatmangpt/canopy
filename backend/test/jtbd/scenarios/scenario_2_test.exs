defmodule Canopy.JTBD.Scenarios.Scenario2Test do
  use ExUnit.Case, async: false

  @event_log_path "test/fixtures/event_logs/simple_order_process.csv"
  @workspace_id "workspace_scenario_2_test"

  describe "process_discovery scenario" do
    @describetag :jtbd
    @describetag :requires_pm4py
    test "returns Petri net event log with places and transitions" do
      # RED: This test fails because Canopy.JTBD.Runner doesn't exist yet
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:process_discovery, workspace_id: @workspace_id, event_log: @event_log_path)

      assert result.outcome == :success
      assert result.span_emitted == true
      assert result.system == :pm4py_rust
      assert result.latency_ms < 2000
    end

    test "emits process_mining.discovery span with model_format=pnml" do
      # RED: pm4py-rust must return PNML-formatted Petri net model
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:process_discovery, workspace_id: @workspace_id, event_log: @event_log_path)

      assert result.outcome == :success
      assert result.span_attributes.model_format == "pnml"
      assert result.model != nil
      assert is_binary(result.model)
    end

    test "captures mining engine stats (place_count, transition_count, fitness)" do
      # RED: Discovery must report structural metrics and quality metrics
      {:ok, result} = Canopy.JTBD.Runner.run_scenario(:process_discovery, workspace_id: @workspace_id, event_log: @event_log_path)

      assert result.outcome == :success
      assert result.span_attributes.place_count > 0
      assert result.span_attributes.transition_count > 0
      assert result.span_attributes.fitness >= 0.0
      assert result.span_attributes.fitness <= 1.0
    end
  end
end
