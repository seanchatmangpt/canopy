defmodule Canopy.Repo.Migrations.CreateOcpmProcessModels do
  use Ecto.Migration

  def change do
    create table(:ocpm_process_models, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :nodes, {:array, :string}, default: []
      add :edges, :map, default: "{}"
      add :version, :string, null: false
      add :discovered_at, :utc_datetime, null: false
      add :workspace_id, references(:workspaces, type: :binary_id), null: false
      add :agent_id, references(:agents, type: :binary_id)

      timestamps()
    end

    create index(:ocpm_process_models, [:workspace_id])
    create index(:ocpm_process_models, [:agent_id])
    create index(:ocpm_process_models, [:version])
    create index(:ocpm_process_models, [:discovered_at])
    create index(:ocpm_process_models, [:workspace_id, :version])
    create index(:ocpm_process_models, [:workspace_id, :discovered_at])
  end
end
