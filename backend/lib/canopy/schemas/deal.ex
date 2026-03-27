defmodule Canopy.Schemas.Deal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "deals" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :deal_type, :string
    field :amount_cents, :integer, default: 0
    field :currency, :string, default: "USD"
    field :counterparty, :string
    field :contract_template_id, :binary_id
    field :terms, :map, default: %{}
    field :metadata, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :workspace, Canopy.Schemas.Workspace
    belongs_to :created_by, Canopy.Schemas.User, foreign_key: :created_by_id, type: :binary_id
    belongs_to :assigned_to, Canopy.Schemas.User, foreign_key: :assigned_to_id, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(deal, attrs) do
    deal
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :deal_type,
      :amount_cents,
      :currency,
      :counterparty,
      :contract_template_id,
      :terms,
      :metadata,
      :started_at,
      :completed_at,
      :workspace_id,
      :created_by_id,
      :assigned_to_id
    ])
    |> validate_required([:name, :deal_type, :workspace_id, :created_by_id])
    |> validate_inclusion(:status, [
      "draft",
      "negotiation",
      "approved",
      "signed",
      "active",
      "completed",
      "cancelled"
    ])
    |> validate_amount_format()
    |> validate_currency_format()
  end

  def transition_changeset(deal, new_status) do
    deal
    |> change(status: new_status)
    |> validate_inclusion(:status, [
      "draft",
      "negotiation",
      "approved",
      "signed",
      "active",
      "completed",
      "cancelled"
    ])
  end

  def sign_changeset(deal) do
    deal
    |> change(status: "signed", started_at: DateTime.utc_now())
  end

  def complete_changeset(deal) do
    deal
    |> change(status: "completed", completed_at: DateTime.utc_now())
  end

  defp validate_amount_format(changeset) do
    changeset
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
  end

  defp validate_currency_format(changeset) do
    validate_format(changeset, :currency, ~r/^[A-Z]{3}$/, message: "must be 3-letter ISO code")
  end
end
