defmodule Canopy.Repo.Migrations.AddWorkspaceIsolationSupport do
  use Ecto.Migration

  def change do
    # Create workspace_users table for RBAC across multiple workspaces
    create table(:workspace_users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # "admin", "user", "viewer"
      add :role, :string, null: false, default: "member"

      timestamps()
    end

    create index(:workspace_users, [:workspace_id])
    create index(:workspace_users, [:user_id])
    create unique_index(:workspace_users, [:workspace_id, :user_id])

    # Add is_active field to Workspace for soft deletion
    alter table(:workspaces) do
      add :is_active, :boolean, default: true
      # "full", "shared", "public"
      add :isolation_level, :string, default: "full"
    end

    create index(:workspaces, [:organization_id, :is_active])
  end
end
