defmodule Canopy.Schemas.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspaces" do
    field :name, :string
    field :path, :string
    field :status, :string, default: "active"
    field :is_active, :boolean, default: true
    field :isolation_level, :string, default: "full"

    belongs_to :owner, Canopy.Schemas.User
    belongs_to :organization, Canopy.Schemas.Organization
    has_many :agents, Canopy.Schemas.Agent
    has_many :projects, Canopy.Schemas.Project
    has_many :issues, Canopy.Schemas.Issue
    has_many :skills, Canopy.Schemas.Skill
    has_many :workspace_users, Canopy.Schemas.WorkspaceUser, on_delete: :delete_all
    has_many :users, through: [:workspace_users, :user]

    timestamps()
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :path, :status, :owner_id, :organization_id, :is_active, :isolation_level])
    |> validate_required([:name, :path])
    |> validate_inclusion(:status, ~w(active archived))
    |> validate_inclusion(:isolation_level, ~w(full shared public))
  end
end
