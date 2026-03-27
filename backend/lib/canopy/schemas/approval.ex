defmodule Canopy.Schemas.Approval do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "approvals" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :decision, :string
    field :decision_comment, :string
    field :context, :map
    field :expires_at, :utc_datetime

    belongs_to :requested_by_agent, Canopy.Schemas.Agent, foreign_key: :requested_by
    belongs_to :reviewer, Canopy.Schemas.User
    belongs_to :workspace, Canopy.Schemas.Workspace
    has_many :approval_comments, Canopy.Schemas.ApprovalComment

    timestamps()
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [
      :title,
      :description,
      :status,
      :decision,
      :decision_comment,
      :context,
      :expires_at,
      :requested_by,
      :reviewer_id,
      :workspace_id
    ])
    |> validate_required([:title, :status])
    |> validate_inclusion(:status, ~w(pending approved rejected cancelled))
  end
end
