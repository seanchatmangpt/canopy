defmodule Canopy.Schemas.WorkProduct do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "work_products" do
    field :title, :string
    field :product_type, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :issue, Canopy.Schemas.Issue
    belongs_to :session, Canopy.Schemas.Session
    belongs_to :agent, Canopy.Schemas.Agent
    belongs_to :workspace, Canopy.Schemas.Workspace

    timestamps()
  end

  def changeset(work_product, attrs) do
    work_product
    |> cast(attrs, [
      :title,
      :product_type,
      :content,
      :metadata,
      :issue_id,
      :session_id,
      :agent_id,
      :workspace_id
    ])
    |> validate_required([:title, :product_type])
  end
end
