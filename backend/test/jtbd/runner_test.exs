defmodule Canopy.JTBD.RunnerTest do
  use ExUnit.Case, async: false

  @workspace_id "runner-unit-test"

  describe "run_scenario/2 dispatch" do
    @tag :jtbd
    test "returns {:error, {:unknown_scenario, id}} for unrecognised scenario" do
      assert {:error, {:unknown_scenario, :does_not_exist}} ==
               Canopy.JTBD.Runner.run_scenario(:does_not_exist, workspace_id: @workspace_id)
    end

    @tag :jtbd
    test "injects latency_ms into the result map" do
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:compliance_check, workspace_id: @workspace_id)

      assert is_integer(result.latency_ms)
      assert result.latency_ms >= 0
    end

    @tag :jtbd
    test "accepts timeout_ms opt without crashing" do
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:compliance_check,
          workspace_id: @workspace_id,
          timeout_ms: 10_000
        )

      assert result.outcome == :success
    end

    @tag :jtbd
    test "accepts iteration opt and returns a result" do
      {:ok, result} =
        Canopy.JTBD.Runner.run_scenario(:compliance_check,
          workspace_id: @workspace_id,
          iteration: 3
        )

      assert result.outcome == :success
    end
  end
end
