defmodule Canopy.Repo.Migrations.CreateAuditTrailEvents do
  use Ecto.Migration

  def change do
    create table(:audit_trail_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :workspace_id, :binary_id, null: false
      add :user_id, :binary_id, null: false
      add :event_type, :string, null: false
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id, null: false
      add :result, :string, null: false
      add :metadata, :map, default: %{}
      add :hash, :string
      add :parent_event_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    create index(:audit_trail_events, [:workspace_id])
    create index(:audit_trail_events, [:user_id])
    create index(:audit_trail_events, [:resource_id])
    create index(:audit_trail_events, [:event_type])
    create index(:audit_trail_events, [:inserted_at])
  end
end
