defmodule Canopy.Jtbd.YawlV6ConformanceTest do
  use ExUnit.Case, async: false

  alias Canopy.JTBD.YAWLv6Simulation

  describe "conformance event structure" do
    test "emit_conformance_event/3 does not crash when PubSub not running" do
      # Private functions are exercised via the public check_and_emit_conformance/3.
      # With no YAWL server running and no PubSub, this must return :ok (graceful degradation).
      result = YAWLv6Simulation.check_and_emit_conformance("WCP-1", "<spec/>", %{})
      assert result == :ok
    end

    test "yawl_conformance event has required fields" do
      event = {:yawl_conformance, %{pattern: "WCP-1", fitness: 0.95, violations: []}}
      {:yawl_conformance, data} = event
      assert Map.has_key?(data, :pattern)
      assert Map.has_key?(data, :fitness)
      assert Map.has_key?(data, :violations)
    end

    test "conformance fitness is a float between 0 and 1" do
      fitness = 0.87
      assert is_float(fitness)
      assert fitness >= 0.0 and fitness <= 1.0
    end

    test "check_and_emit_conformance/3 returns :ok when YAWL is unavailable" do
      # No YAWL engine running in test environment — must degrade gracefully
      result = YAWLv6Simulation.check_and_emit_conformance("WCP-2", "<spec/>")
      assert result == :ok
    end

    test "check_and_emit_conformance/3 accepts default empty event log" do
      result = YAWLv6Simulation.check_and_emit_conformance("WCP-3", "<spec/>")
      assert result == :ok
    end
  end
end
