defmodule Canopy.Board.ConwayHeartbeatTest do
  use ExUnit.Case

  alias Canopy.Board.ConwayChecker
  alias OpenTelemetry.SemConv.Incubating.BoardSpanNames
  alias OpenTelemetry.SemConv.Incubating.BoardAttributes

  # Chicago TDD: each test name describes exactly what it proves.

  test "conway check detects violation when boundary exceeds 40% of cycle time" do
    # 50/100 = 0.5 > 0.4
    result = ConwayChecker.check(50, 100)
    assert result.is_violation == true
    assert_in_delta result.conway_score, 0.5, 0.001
  end

  test "conway check does not escalate when boundary is within normal range" do
    # 30/100 = 0.3 < 0.4
    result = ConwayChecker.check(30, 100)
    assert result.is_violation == false
    assert_in_delta result.conway_score, 0.3, 0.001
  end

  test "conway check handles zero cycle time without crash" do
    result = ConwayChecker.check(50, 0)
    assert result.is_violation == false
  end

  test "conway score is bounded between 0.0 and 1.0 for normal inputs" do
    result = ConwayChecker.check(80, 100)
    assert result.conway_score >= 0.0
    assert result.conway_score <= 1.0
  end

  test "conway check returns boundary_time_ms and cycle_time_ms in result" do
    result = ConwayChecker.check(40, 100)
    assert result.boundary_time_ms == 40
    assert result.cycle_time_ms == 100
  end

  test "conway check detects exact threshold boundary (0.4 is not a violation)" do
    # Exactly at threshold is NOT a violation (> 0.4, not >= 0.4)
    # 40/100 = 0.4 exactly
    result = ConwayChecker.check(40, 100)
    assert result.is_violation == false
    assert_in_delta result.conway_score, 0.4, 0.001
  end

  test "conway check detects violation just above threshold (0.401)" do
    # 41/100 = 0.41 > 0.4 → violation
    result = ConwayChecker.check(41, 100)
    assert result.is_violation == true
    assert result.conway_score > 0.4
  end

  test "board span name constant returns board.conway_check" do
    # Schema conformance: typed semconv constant used (compile error if removed)
    assert BoardSpanNames.board_conway_check() == "board.conway_check"
  end

  test "board attributes constants return correct atom keys" do
    # Schema conformance: typed constants enforced at compile time
    assert BoardAttributes.board_is_violation() == :"board.is_violation"
    assert BoardAttributes.board_conway_score() == :"board.conway_score"
    assert BoardAttributes.board_process_id() == :"board.process_id"
  end
end
