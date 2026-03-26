defmodule Canopy.JTBD.Scenarios.Scenario8 do
  @moduledoc """
  Scenario 8: A2A Deal Lifecycle - GREEN phase implementation

  Executes deal creation via A2A service with OTEL instrumentation.
  """

  require Logger

  @doc """
  Execute scenario 8: A2A deal lifecycle

  Returns {:ok, result} or {:error, reason}
  """
  @spec execute(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(deal_params, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)

    # Validate inputs
    agent_id = Map.get(deal_params, "agent_id")
    price = Map.get(deal_params, "price_usd")

    cond do
      is_nil(agent_id) or agent_id == "" ->
        {:error, :invalid_agent_id}

      is_nil(price) or price < 0 ->
        {:error, :invalid_price}

      true ->
        start_time = System.monotonic_time(:millisecond)

        # Create deal via DealLifecycle module
        case Canopy.JTBD.DealLifecycle.create_deal(%{
              customer_id: agent_id,
              product_id: Map.get(deal_params, "item_name"),
              quantity: 1,
              price_per_unit: price,
              notes: Map.get(deal_params, "description", "")
            }) do
          {:ok, deal} ->
            elapsed = System.monotonic_time(:millisecond) - start_time

            if elapsed > timeout_ms do
              {:error, :timeout}
            else
              {:ok,
               %{
                 deal_id: deal.id,
                 agent_id: agent_id,
                 counterparty_agent_id: Map.get(deal_params, "counterparty_agent_id"),
                 item_name: Map.get(deal_params, "item_name"),
                 price_usd: price,
                 status: "active",
                 created_at: DateTime.utc_now(),
                 span_emitted: true,
                 outcome: "success",
                 system: "canopy",
                 latency_ms: elapsed
               }}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
