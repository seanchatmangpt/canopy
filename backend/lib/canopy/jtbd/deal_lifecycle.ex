defmodule Canopy.JTBD.DealLifecycle do
  @moduledoc """
  JTBD Scenario 8: A2A Deal Lifecycle

  Canopy A2A service creates and manages deal lifecycle across systems.
  Emits OTEL spans with deal creation, negotiation, and closure phases.

  Chicago TDD GREEN phase: Minimal implementation to pass tests.
  """

  require Logger
  require OpenTelemetry.Tracer
  alias OpenTelemetry.Tracer

  @doc """
  Create a deal via A2A service.

  Returns {:ok, deal} or {:error, reason}.
  Emits OTEL span with deal creation details.
  """
  def create_deal(deal_request) do
    start_time = System.monotonic_time(:millisecond)

    # Validate deal request
    case validate_deal_request(deal_request) do
      :ok ->
        # Start root span
        root_ctx = Tracer.start_span("jtbd.a2a.deal.create")
        Canopy.Telemetry.WeaverLiveCheck.put_correlation_attribute()

        try do
          # Create deal
          deal = %{
            id: "deal_#{System.unique_integer([:positive])}",
            customer_id: deal_request.customer_id,
            product_id: deal_request.product_id,
            quantity: deal_request.quantity,
            price_per_unit: deal_request.price_per_unit,
            total_amount: deal_request.quantity * deal_request.price_per_unit,
            status: "created",
            created_at: DateTime.utc_now(),
            notes: Map.get(deal_request, :notes, "")
          }

          # Emit OTEL span with attributes
          span_attributes = %{
            "deal_id" => deal.id,
            "customer_id" => deal.customer_id,
            "product_id" => deal.product_id,
            "quantity" => deal.quantity,
            "total_amount" => deal.total_amount,
            "status" => "ok"
          }

          # Record span attributes
          Enum.each(span_attributes, fn {key, value} ->
            key_atom = String.to_atom(key)
            Tracer.set_attribute(key_atom, value)
          end)

          latency = System.monotonic_time(:millisecond) - start_time
          Tracer.set_attribute(:duration_ms, latency)

          Logger.info("Deal #{deal.id} created for customer #{deal.customer_id} in #{latency}ms")

          {:ok, deal}
        catch
          _type, _reason ->
            Tracer.set_attribute(:status, "error")
            {:error, :deal_creation_failed}
        after
          Tracer.end_span(root_ctx)
        end

      {:error, reason} ->
        Logger.warning("Deal creation validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper: Validate deal request
  defp validate_deal_request(deal_request) do
    cond do
      not Map.has_key?(deal_request, :customer_id) or deal_request.customer_id == nil ->
        {:error, :missing_customer_id}

      not Map.has_key?(deal_request, :product_id) or deal_request.product_id == nil ->
        {:error, :missing_product_id}

      not Map.has_key?(deal_request, :quantity) or deal_request.quantity <= 0 ->
        {:error, :invalid_quantity}

      not Map.has_key?(deal_request, :price_per_unit) or deal_request.price_per_unit <= 0 ->
        {:error, :invalid_price}

      true ->
        :ok
    end
  end
end
