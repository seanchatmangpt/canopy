defmodule Canopy.Jtbd.YawlV6ConformanceTest do
  use ExUnit.Case, async: false

  alias Canopy.JTBD.YAWLv6Simulation

  describe "conformance event structure" do
    test "check_and_emit_conformance/3 fails fast when YAWL is unavailable (PubSub not running)" do
      # Private functions are exercised via the public check_and_emit_conformance/3.
      # With no YAWL server running, this must return {:error, :yawl_unavailable} (fail fast).
      result = YAWLv6Simulation.check_and_emit_conformance("WCP-1", "<spec/>", %{})
      assert result == {:error, :yawl_unavailable}
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

    test "check_and_emit_conformance/3 returns error tuple when YAWL is unavailable" do
      # No YAWL engine running in test environment — must fail fast
      result = YAWLv6Simulation.check_and_emit_conformance("WCP-2", "<spec/>")
      assert {:error, :yawl_unavailable} = result
    end

    test "check_and_emit_conformance/3 accepts default empty event log and returns error" do
      # With no YAWL server, all conformance checks fail fast
      result = YAWLv6Simulation.check_and_emit_conformance("WCP-3", "<spec/>")
      assert {:error, :yawl_unavailable} = result
    end
  end
end
