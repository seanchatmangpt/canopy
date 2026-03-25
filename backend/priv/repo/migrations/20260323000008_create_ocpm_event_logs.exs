defmodule Canopy.Repo.Migrations.CreateOcpmEventLogs do
  use Ecto.Migration

  def change do
    create table(:ocpm_event_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :case_id, :string, null: false
      add :activity, :string, null: false
      add :timestamp, :utc_datetime, null: false
      add :resource, :string, null: false
      add :attributes, :map, default: "{}"
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :agent_id, references(:agents, type: :binary_id)

      timestamps()
    end

    create index(:ocpm_event_logs, [:workspace_id])
    create index(:ocpm_event_logs, [:case_id])
    create index(:ocpm_event_logs, [:activity])
    create index(:ocpm_event_logs, [:timestamp])
    create index(:ocpm_event_logs, [:resource])
    create index(:ocpm_event_logs, [:agent_id])
    create index(:ocpm_event_logs, [:workspace_id, :case_id])
    create index(:ocpm_event_logs, [:workspace_id, :timestamp])
  end
end
