defmodule Canopy.Schemas.WorkspaceUser do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspace_users" do
    field :role, :string, default: "member"

    belongs_to :workspace, Canopy.Schemas.Workspace
    belongs_to :user, Canopy.Schemas.User

    timestamps()
  end

  def changeset(workspace_user, attrs) do
    workspace_user
    |> cast(attrs, [:workspace_id, :user_id, :role])
    |> validate_required([:workspace_id, :user_id, :role])
    |> validate_inclusion(:role, ~w(admin user viewer))
    |> unique_constraint([:workspace_id, :user_id])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
  end
end
