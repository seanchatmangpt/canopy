defmodule Canopy.Repo.Migrations.CreateDeals do
  use Ecto.Migration

  def change do
    create table(:deals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "draft", null: false
      add :deal_type, :string, null: false
      add :amount_cents, :integer, default: 0
      add :currency, :string, default: "USD"
      add :counterparty, :string
      add :contract_template_id, :binary_id
      add :terms, :map, default: %{}
      add :metadata, :map, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      add :workspace_id, :binary_id, null: false
      add :created_by_id, :binary_id, null: false
      add :assigned_to_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:deals, [:workspace_id])
    create index(:deals, [:status])
    create index(:deals, [:deal_type])
    create index(:deals, [:created_by_id])
    create index(:deals, [:assigned_to_id])
    create index(:deals, [:inserted_at])
  end
end
