defmodule CanopyWeb.DealsView do
  @moduledoc """
  View layer for deal rendering in Canopy.

  Provides serialization and presentation helpers for deal resources.
  """

  @doc """
  Serialize a deal for JSON response.

  Includes all deal attributes with proper formatting for API consumption.
  """
  def serialize_deal(deal) do
    %{
      id: deal.id,
      name: deal.name,
      description: deal.description,
      status: deal.status,
      deal_type: deal.deal_type,
      amount_cents: deal.amount_cents,
      currency: deal.currency,
      counterparty: deal.counterparty,
      contract_template_id: deal.contract_template_id,
      terms: deal.terms,
      metadata: deal.metadata,
      workspace_id: deal.workspace_id,
      created_by_id: deal.created_by_id,
      assigned_to_id: deal.assigned_to_id,
      started_at: deal.started_at,
      completed_at: deal.completed_at,
      inserted_at: deal.inserted_at,
      updated_at: deal.updated_at
    }
  end

  @doc """
  Format amount in cents as a decimal currency string.

  Example: 100000 cents -> "1000.00"
  """
  def format_amount(cents) when is_integer(cents) do
    :erlang.float_to_binary(cents / 100.0, decimals: 2)
  end

  def format_amount(_), do: "0.00"

  @doc """
  Get human-readable status label.
  """
  def status_label(status) do
    %{
      "draft" => "Draft",
      "negotiation" => "In Negotiation",
      "approved" => "Approved",
      "signed" => "Signed",
      "active" => "Active",
      "completed" => "Completed",
      "cancelled" => "Cancelled"
    }[status] || status
  end

  @doc """
  Get CSS class for status badge.
  """
  def status_badge_class(status) do
    case status do
      "draft" -> "badge-secondary"
      "negotiation" -> "badge-info"
      "approved" -> "badge-success"
      "signed" -> "badge-primary"
      "active" -> "badge-primary"
      "completed" -> "badge-success"
      "cancelled" -> "badge-danger"
      _ -> "badge-default"
    end
  end

  @doc """
  Get deal timeline for UI display.

  Returns list of events with timestamps.
  """
  def deal_timeline(deal) do
    []
    |> add_if(deal.inserted_at, "created", deal.inserted_at)
    |> add_if(deal.started_at, "signed", deal.started_at)
    |> add_if(deal.completed_at, "completed", deal.completed_at)
    |> Enum.sort_by(fn {_, ts} -> DateTime.to_unix(ts) end)
    |> Enum.map(fn {event, ts} -> %{event: event, timestamp: ts} end)
  end

  @doc """
  Render contract template summary.
  """
  def render_template_summary(template) do
    %{
      name: template.name,
      description: template.description,
      fields:
        Enum.map(template.fields, fn {name, type, opts} ->
          %{name: name, type: type, required: Keyword.get(opts, :required, false)}
        end)
    }
  end

  # Private helpers

  defp add_if(list, condition, _event, _timestamp) when is_nil(condition) do
    list
  end

  defp add_if(list, _condition, event, timestamp) do
    [{event, timestamp} | list]
  end
end
