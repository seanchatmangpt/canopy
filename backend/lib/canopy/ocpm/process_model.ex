defmodule Canopy.OCPM.ProcessModel do
  @moduledoc """
  Process model storage and versioning.

  Stores discovered process models:
  - nodes: List of activities
  - edges: Transitions between activities
  - version: SemVer
  - discovered_at: DateTime

  Process models are the output of OCPM discovery algorithms
  (alpha miner, heuristic miner) and represent the discovered
  process structure from event logs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ocpm_process_models" do
    field :nodes, {:array, :string}, default: []
    field :edges, :map, default: %{}
    field :version, :string
    field :discovered_at, :utc_datetime

    belongs_to :workspace, Canopy.Schemas.Workspace
    belongs_to :agent, Canopy.Schemas.Agent

    timestamps()
  end

  def changeset(process_model, attrs) do
    process_model
    |> cast(attrs, [:nodes, :edges, :version, :discovered_at, :workspace_id, :agent_id])
    |> validate_required([:nodes, :edges, :version, :discovered_at, :workspace_id])
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/,
      message: "must be a valid SemVer string"
    )
    |> validate_nodes()
    |> validate_edges()
  end

  defp validate_nodes(changeset) do
    nodes = get_change(changeset, :nodes)

    if nodes && is_list(nodes) && length(nodes) > 0 do
      changeset
    else
      add_error(changeset, :nodes, "must be a non-empty list of activity names")
    end
  end

  defp validate_edges(changeset) do
    edges = get_change(changeset, :edges)

    if edges && is_map(edges) do
      # Edges should be stored as a map with "transitions" key
      # Example: %{"transitions" => [[{"from": "create"}, {"to": "approve"}], ...]}
      changeset
    else
      add_error(changeset, :edges, "must be a map containing transition data")
    end
  end
end
