defmodule Canopy.OCPM.EventLog do
  @moduledoc """
  OCPM event log schema for process mining.

  Standardized event format for Object-Centric Process Mining:
  - case_id: String - The case identifier (e.g., invoice ID, customer ID)
  - activity: String - The activity performed (e.g., "approve", "review", "process")
  - timestamp: DateTime - When the event occurred
  - resource: String - Who/what performed the activity (agent ID or system name)
  - attributes: Map - Additional event attributes (flexible key-value pairs)

  Events are organized by case_id to enable process mining algorithms
  (alpha miner, heuristic miner, conformance checking).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ocpm_event_logs" do
    field :case_id, :string
    field :activity, :string
    field :timestamp, :utc_datetime
    field :resource, :string
    field :attributes, :map, default: %{}

    belongs_to :workspace, Canopy.Schemas.Workspace
    belongs_to :agent, Canopy.Schemas.Agent

    timestamps()
  end

  def changeset(event_log, attrs) do
    event_log
    |> cast(attrs, [:case_id, :activity, :timestamp, :resource, :attributes, :workspace_id, :agent_id])
    |> validate_required([:case_id, :activity, :timestamp, :resource, :workspace_id])
    |> validate_inclusion(:activity, get_valid_activities())
  end

  defp get_valid_activities do
    # Common process mining activities
    # This can be extended based on use case
    ~w(
      start create submit approve reject review process complete
      cancel hold resume assign reassign notify archive delete
    )
  end
end
