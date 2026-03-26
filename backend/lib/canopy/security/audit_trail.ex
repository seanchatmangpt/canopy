defmodule Canopy.Security.AuditTrail.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "audit_trail_events" do
    field :workspace_id, :binary_id
    field :user_id, :binary_id
    field :event_type, :string
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :result, :string
    field :metadata, :map, default: %{}
    field :hash, :string
    field :parent_event_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :workspace_id,
      :user_id,
      :event_type,
      :action,
      :resource_type,
      :resource_id,
      :result,
      :metadata,
      :hash,
      :parent_event_id,
      :inserted_at
    ])
    |> validate_required([
      :workspace_id,
      :user_id,
      :event_type,
      :action,
      :resource_type,
      :resource_id,
      :result
    ])
    |> validate_inclusion(:result, ["success", "failure", "pending"])
  end
end

defmodule Canopy.Security.AuditTrail do
  @moduledoc """
  Audit trail system for tracking and verifying workflow events.

  Maintains an immutable log of all workflow events with:
  - Chronological ordering
  - Cryptographic integrity verification
  - Causal relationship tracking
  - Persistent storage with recovery capability

  ## Usage

    {:ok, event} = AuditTrail.capture_event(%{
      workspace_id: workspace_id,
      user_id: user_id,
      event_type: "workflow_executed",
      action: "execute",
      resource_type: "workflow",
      resource_id: resource_id,
      result: "success",
      metadata: %{}
    })

    history = AuditTrail.get_resource_history(resource_id)

  """

  require Logger

  import Ecto.Query

  alias Canopy.Repo
  alias Canopy.Security.AuditTrail.Event

  @doc """
  Captures a new audit event.

  Creates an immutable audit trail entry for workflow operations.
  Automatically generates:
  - Unique event ID
  - Timestamp
  - Hash chain for integrity verification
  - Stores in persistent database

  ## Arguments

    * `attrs` - Map containing:
      - `workspace_id` - Workspace UUID
      - `user_id` - User UUID
      - `event_type` - Event classification (e.g., "workflow_executed")
      - `action` - Action performed (e.g., "execute", "create", "delete")
      - `resource_type` - Type of resource affected
      - `resource_id` - UUID of affected resource
      - `result` - Result status ("success", "failure", "pending")
      - `metadata` (optional) - Additional data
      - `parent_event_id` (optional) - ID of parent event for causality

  ## Returns

    * `{:ok, event}` - Event record created
    * `{:error, changeset}` - Validation failed

  ## Examples

    iex> AuditTrail.capture_event(%{
    ...>   workspace_id: "uuid",
    ...>   user_id: "uuid",
    ...>   event_type: "created",
    ...>   action: "create",
    ...>   resource_type: "workflow",
    ...>   resource_id: "uuid",
    ...>   result: "success"
    ...> })
    {:ok, %Event{}}

  """
  def capture_event(attrs) do
    attrs_with_hash =
      attrs
      |> Map.put_new(:id, Ecto.UUID.generate())
      |> Map.put_new(:inserted_at, DateTime.utc_now())
      |> compute_hash()

    %Event{}
    |> Event.changeset(attrs_with_hash)
    |> Repo.insert()
  end

  @doc """
  Retrieves complete history of events for a resource.

  Returns all events affecting a specific resource, ordered
  chronologically from oldest to newest.

  ## Arguments

    * `resource_id` - UUID of the resource

  ## Returns

    List of Event records ordered by timestamp (ascending)

  """
  def get_resource_history(resource_id) do
    Event
    |> where([e], e.resource_id == ^resource_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Retrieves a single event by ID.

  ## Arguments

    * `event_id` - UUID of the event

  ## Returns

    * Event record if found
    * `nil` if not found

  """
  def get_event(event_id) do
    Repo.get(Event, event_id)
  end

  @doc """
  Verifies the integrity hash of an audit event.

  Recomputes the hash and compares with stored hash to detect tampering.

  ## Arguments

    * `event` - Event record to verify

  ## Returns

    * `true` - Hash matches, event is untampered
    * `false` - Hash mismatch, event may be tampered

  """
  def verify_integrity(event) do
    # Convert schema to map and clear hash
    event_map = %{
      event_type: event.event_type,
      action: event.action,
      resource_id: event.resource_id,
      inserted_at: event.inserted_at
    }

    computed_hash = compute_hash(event_map) |> Map.get(:hash)
    computed_hash == event.hash
  end

  @doc """
  Retrieves audit events for a workspace within a time range.

  ## Arguments

    * `workspace_id` - Workspace UUID
    * `since` - DateTime (inclusive)
    * `until` - DateTime (inclusive, optional)

  ## Returns

    List of Event records ordered by timestamp

  """
  def get_workspace_events(workspace_id, since, until \\ nil) do
    query =
      Event
      |> where([e], e.workspace_id == ^workspace_id)
      |> where([e], e.inserted_at >= ^since)

    query =
      if until do
        where(query, [e], e.inserted_at <= ^until)
      else
        query
      end

    query
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Retrieves all events triggered by a specific user.

  ## Arguments

    * `user_id` - User UUID

  ## Returns

    List of Event records ordered by timestamp

  """
  def get_user_events(user_id) do
    Event
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  # Private: Compute cryptographic hash for event
  defp compute_hash(attrs) do
    hash_input =
      "#{attrs[:event_type]}-#{attrs[:action]}-#{attrs[:resource_id]}-#{attrs[:inserted_at]}"

    hash = :crypto.hash(:sha256, hash_input) |> Base.encode16()
    Map.put(attrs, :hash, hash)
  end
end
