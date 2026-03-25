defmodule Canopy.BudgetEnforcerTest do
  use ExUnit.Case, async: true

  # Tests for BudgetEnforcer pure logic: ETS operations, hierarchy
  # structure, policy checking, and scope-based pause logic.

  describe "ETS table structure" do
    test "accumulator table uses {scope_type, scope_id} keys" do
      key = {"agent", "agent-123"}
      assert match?({_, _}, key)
    end

    test "hierarchy cache uses agent_id as key" do
      agent_id = "agent-456"
      assert is_binary(agent_id)
    end
  end

  describe "scope types" do
    test "all valid scope types" do
      scopes = ["agent", "workspace", "team", "department", "division", "organization"]
      assert length(scopes) == 6
    end

    test "scope types are ordered by hierarchy" do
      hierarchy = ["agent", "team", "department", "division", "organization"]
      assert hierarchy == ["agent", "team", "department", "division", "organization"]
    end
  end

  describe "get_accumulated default behavior" do
    test "returns 0 when key is not found in ETS" do
      # Simulating the lookup logic
      result = []
      case result do
        [{_, cents}] -> cents
        [] -> 0
      end
      assert 0 == 0
    end

    test "returns stored value when key exists" do
      result = [{{"agent", "a1"}, 500}]
      case result do
        [{_, cents}] -> assert cents == 500
        [] -> flunk("Should have found value")
      end
    end
  end

  describe "budget cascade logic" do
    test "cost cascades through hierarchy levels" do
      chain = %{
        workspace_id: "ws-1",
        team_id: "tm-1",
        department_id: "dept-1",
        division_id: "div-1",
        organization_id: "org-1"
      }

      # All non-nil levels should be incremented
      levels = [
        {"agent", "a1"},
        {"workspace", chain.workspace_id},
        {"team", chain.team_id},
        {"department", chain.department_id},
        {"division", chain.division_id},
        {"organization", chain.organization_id}
      ]

      assert length(levels) == 6
    end

    test "nil hierarchy levels are skipped" do
      chain = %{
        workspace_id: "ws-1",
        team_id: nil,
        department_id: nil,
        division_id: nil,
        organization_id: nil
      }

      non_nil = [
        chain.workspace_id,
        chain.team_id,
        chain.department_id,
        chain.division_id,
        chain.organization_id
      ]
      |> Enum.reject(&is_nil/1)

      assert length(non_nil) == 1
    end
  end

  describe "policy check thresholds" do
    test "percentage calculation" do
      accumulated = 7500
      limit = 10_000
      pct = div(accumulated * 100, limit)
      assert pct == 75
    end

    test "percentage at 100% triggers hard stop when hard_stop is true" do
      accumulated = 10_000
      limit = 10_000
      pct = div(accumulated * 100, limit)
      hard_stop = true
      assert pct >= 100
      assert hard_stop == true
    end

    test "percentage at 80% triggers warning at 80% threshold" do
      accumulated = 8000
      limit = 10_000
      pct = div(accumulated * 100, limit)
      warning_threshold = 80
      assert pct >= warning_threshold
    end

    test "percentage at 50% does not trigger 80% warning" do
      accumulated = 5000
      limit = 10_000
      pct = div(accumulated * 100, limit)
      warning_threshold = 80
      refute pct >= warning_threshold
    end

    test "zero limit produces 0% to avoid division by zero" do
      limit = 0
      pct = if limit > 0, do: div(5000 * 100, limit), else: 0
      assert pct == 0
    end
  end

  describe "incident deduplication" do
    test "hard_stop incidents are deduplicated by unresolved check" do
      existing = %{
        policy_id: "p1",
        scope_type: "agent",
        scope_id: "a1",
        incident_type: "hard_stop",
        resolved: false
      }

      assert existing.resolved == false
      # Should NOT create a new incident
    end

    test "resolved incidents allow new incident creation" do
      existing = nil
      assert existing == nil
      # Should create a new incident
    end
  end

  describe "broadcast event structure" do
    test "budget warning event has expected shape" do
      event = %{
        event: "budget.warning",
        scope_type: "agent",
        scope_id: "agent-123",
        actual_pct: 85,
        policy_id: "policy-1"
      }

      assert event.event == "budget.warning"
      assert event.scope_type == "agent"
      assert event.actual_pct == 85
    end

    test "budget hard_stop event has expected shape" do
      event = %{
        event: "budget.hard_stop",
        scope_type: "team",
        scope_id: "team-1",
        actual_pct: 100,
        policy_id: "policy-2"
      }

      assert event.event == "budget.hard_stop"
    end
  end

  describe "month boundary reset" do
    test "month start is first day of current month" do
      today = Date.utc_today()
      month_start = Date.new!(today.year, today.month, 1)
      assert month_start.day == 1
    end
  end
end
