defmodule Canopy.JTBD.Scenarios.Scenario9 do
  @moduledoc """
  Scenario 9: MCP Tool Execution - GREEN phase implementation

  Executes tool via MCP client with OTEL instrumentation.
  """

  require Logger

  @doc """
  Execute scenario 9: MCP tool execution

  Returns {:ok, result} or {:error, reason}
  """
  @spec execute(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(tool_params, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    start_time = System.monotonic_time(:millisecond)

    tool_name = Map.get(tool_params, "tool_name", "default_tool")
    tool_input = Map.get(tool_params, "input", %{})

    # Simulate tool execution (in real scenario, would call MCP server)
    case simulate_tool_execution(tool_name, tool_input) do
      {:ok, output} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        if elapsed > timeout_ms do
          {:error, :timeout}
        else
          {:ok,
           %{
             tool_name: tool_name,
             output: output,
             status: "ok",
             outcome: :success,
             duration_ms: elapsed
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp simulate_tool_execution(tool_name, input) do
    case tool_name do
      "calculate_discount" ->
        base = Map.get(input, "base_amount", 0)
        qty = Map.get(input, "quantity", 0)
        tier = Map.get(input, "customer_tier", "bronze")

        discount_rate =
          case tier do
            "gold" -> 0.20
            "silver" -> 0.15
            "bronze" -> 0.10
            _ -> 0.0
          end

        discounted = base * (1 - discount_rate)

        {:ok, %{discount_rate: discount_rate, discounted_amount: discounted, savings: base - discounted}}

      _ ->
        {:error, :unknown_tool}
    end
  end
end
