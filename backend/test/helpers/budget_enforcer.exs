defmodule Canopy.Test.Helpers.BudgetEnforcer do
  @moduledoc """
  Armstrong Budget Constraints Helper for Canopy.

  Enforces that operations complete within time budgets.
  Prevents runaway heartbeat dispatch and backpressure buildup.

  ## Usage

      test "heartbeat dispatch respects time budget" do
        assert_within_budget(time_ms: 5000, fn ->
          Canopy.Heartbeat.dispatch(:signal, [])
        end)
      end

      test "operation exceeding budget is caught" do
        assert_raises AssertionError, fn ->
          assert_within_budget(time_ms: 100, fn ->
            :timer.sleep(500)
          end)
        end
      end
  """

  @spec assert_within_budget(keyword, (-> any)) :: any
  def assert_within_budget(opts, operation) when is_list(opts) and is_function(operation, 0) do
    time_budget_ms = Keyword.get(opts, :time_ms, :infinity)

    if time_budget_ms == :infinity do
      raise ArgumentError, "time_ms is required (Armstrong budget constraint)"
    end

    start_time = System.monotonic_time(:millisecond)

    result = operation.()

    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    if elapsed_ms > time_budget_ms do
      raise AssertionError,
        message:
          "Operation exceeded time budget: #{elapsed_ms}ms > #{time_budget_ms}ms (tier: #{tier_name(time_budget_ms)})"
    end

    result
  end

  @spec budget_tiers :: map
  def budget_tiers do
    %{
      critical: %{time_ms: 100},
      high: %{time_ms: 500},
      normal: %{time_ms: 5000},
      low: %{time_ms: 30000}
    }
  end

  @spec assert_tier_compliant(:critical | :high | :normal | :low, (-> any)) :: any
  def assert_tier_compliant(tier, operation) when is_atom(tier) and is_function(operation, 0) do
    tiers = budget_tiers()

    unless Map.has_key?(tiers, tier) do
      raise ArgumentError, "Unknown tier: #{inspect(tier)}"
    end

    budget = tiers[tier]
    assert_within_budget(budget, operation)
  end

  defp tier_name(ms) when ms <= 100, do: "critical"
  defp tier_name(ms) when ms <= 500, do: "high"
  defp tier_name(ms) when ms <= 5000, do: "normal"
  defp tier_name(_ms), do: "low"
end
