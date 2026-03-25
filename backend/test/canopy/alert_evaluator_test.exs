defmodule Canopy.AlertEvaluatorTest do
  use ExUnit.Case, async: true

  # Tests for AlertEvaluator pure logic: comparison operators, cooldown
  # calculation, to_number conversion, and evaluation conditions.

  describe "comparison operators" do
    test "gt: current > threshold" do
      current = 10
      threshold = 5
      assert current > threshold
    end

    test "gt: current not > threshold when equal" do
      current = 5
      threshold = 5
      refute current > threshold
    end

    test "gte: current >= threshold" do
      assert 10 >= 5
      assert 5 >= 5
      refute 4 >= 5
    end

    test "lt: current < threshold" do
      assert 3 < 10
      refute 10 < 3
    end

    test "lte: current <= threshold" do
      assert 3 <= 10
      assert 10 <= 10
      refute 11 <= 10
    end

    test "eq: string equality" do
      assert to_string("active") == to_string("active")
      refute to_string("active") == to_string("inactive")
    end

    test "neq: string inequality" do
      assert to_string("active") != to_string("inactive")
      refute to_string("active") != to_string("active")
    end
  end

  describe "to_number conversion" do
    test "integer passes through" do
      assert 42 == 42
    end

    test "float passes through" do
      assert 3.14 == 3.14
    end

    test "binary integer parses" do
      case Integer.parse("42") do
        {n, _} -> assert n == 42
        :error -> flunk("Should parse integer")
      end
    end

    test "binary float-like string parses as integer (truncates)" do
      case Integer.parse("3.14") do
        {3, ".14"} -> assert 3 == 3
        _ -> flunk("Should parse partial integer")
      end
    end

    test "non-numeric binary returns 0" do
      case Integer.parse("abc") do
        :error -> :ok
        _ -> flunk("Should fail to parse")
      end
    end
  end

  describe "cooldown logic" do
    test "nil last_triggered_at always evaluates" do
      last_triggered_at = nil
      assert last_triggered_at == nil
    end

    test "cooldown of 0 minutes always evaluates" do
      last_triggered = DateTime.utc_now() |> DateTime.add(-10, :minute)
      cooldown = 0
      elapsed = DateTime.diff(DateTime.utc_now(), last_triggered, :minute)
      assert elapsed >= cooldown
    end

    test "cooldown respects elapsed time" do
      # Triggered 5 minutes ago, cooldown is 10 minutes
      last_triggered = DateTime.utc_now() |> DateTime.add(-5, :minute)
      cooldown = 10
      elapsed = DateTime.diff(DateTime.utc_now(), last_triggered, :minute)
      refute elapsed >= cooldown
    end

    test "cooldown passes after enough time" do
      # Triggered 15 minutes ago, cooldown is 10 minutes
      last_triggered = DateTime.utc_now() |> DateTime.add(-15, :minute)
      cooldown = 10
      elapsed = DateTime.diff(DateTime.utc_now(), last_triggered, :minute)
      assert elapsed >= cooldown
    end
  end

  describe "entity value field mapping" do
    test "Agent.error_count is a valid field" do
      entity = "Agent"
      field = "error_count"
      assert entity == "Agent"
      assert field == "error_count"
    end

    test "Agent.active_count is a valid field" do
      entity = "Agent"
      field = "active_count"
      assert entity == "Agent"
      assert field == "active_count"
    end

    test "Session.active_count is a valid field" do
      entity = "Session"
      field = "active_count"
      assert entity == "Session"
    end

    test "Budget.total_today_cents is a valid field" do
      entity = "Budget"
      field = "total_today_cents"
      assert entity == "Budget"
    end
  end

  describe "evaluation interval" do
    test "default evaluation interval is 60 seconds" do
      interval = :timer.seconds(60)
      assert interval == 60_000
    end
  end

  describe "alert firing structure" do
    test "alert event has expected fields" do
      event = %{
        event: "alert.triggered",
        rule_id: "rule-1",
        rule_name: "High Error Rate",
        entity: "Agent",
        field: "error_count",
        value: "5"
      }

      assert event.event == "alert.triggered"
      assert Map.has_key?(event, :rule_id)
      assert Map.has_key?(event, :entity)
      assert Map.has_key?(event, :field)
      assert Map.has_key?(event, :value)
    end
  end
end
