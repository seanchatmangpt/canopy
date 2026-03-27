defmodule Canopy.SemConv.WorkflowAttributes do
  @moduledoc """
  Canopy semantic convention attributes for YAWL workflow integration.

  Defines the eight core YAWL workflow control-flow patterns (WCP-1 through WCP-8)
  as OTel attribute constants for use in Canopy spans and metrics.

  These are Canopy-namespaced aliases for the underlying
  `OpenTelemetry.SemConv.Incubating.WorkflowAttributes` module, scoped to the
  patterns actively used by the Canopy/YAWL integration.
  """

  @doc "OTel attribute key for the workflow engine."
  @spec workflow_engine() :: :"workflow.engine"
  def workflow_engine, do: :"workflow.engine"

  @doc "OTel attribute key for the workflow instance identifier."
  @spec workflow_id() :: :"workflow.id"
  def workflow_id, do: :"workflow.id"

  @doc "OTel attribute key for the human-readable workflow definition name."
  @spec workflow_name() :: :"workflow.name"
  def workflow_name, do: :"workflow.name"

  @doc "OTel attribute key for the YAWL workflow control-flow pattern."
  @spec workflow_pattern() :: :"workflow.pattern"
  def workflow_pattern, do: :"workflow.pattern"

  @doc "OTel attribute key for the workflow execution state."
  @spec workflow_state() :: :"workflow.state"
  def workflow_state, do: :"workflow.state"

  @doc "OTel attribute key for the current step or activity name within the workflow."
  @spec workflow_step() :: :"workflow.step"
  def workflow_step, do: :"workflow.step"

  @doc """
  Enumerated values for `workflow.engine`.

  | Key | Value |
  |-----|-------|
  | `canopy` | `:canopy` |
  | `yawl` | `:yawl` |
  | `business_os` | `:business_os` |
  """
  @spec workflow_engine_values() :: %{canopy: :canopy, yawl: :yawl, business_os: :business_os}
  def workflow_engine_values do
    %{
      canopy: :canopy,
      yawl: :yawl,
      business_os: :business_os
    }
  end

  @doc """
  Enumerated values for `workflow.pattern` — the eight core YAWL workflow
  control-flow patterns (WCP-1 through WCP-8).

  | Key | Value |
  |-----|-------|
  | `sequence` | `:sequence` |
  | `parallel_split` | `:parallel_split` |
  | `synchronization` | `:synchronization` |
  | `exclusive_choice` | `:exclusive_choice` |
  | `simple_merge` | `:simple_merge` |
  | `multi_choice` | `:multi_choice` |
  | `structured_loop` | `:structured_loop` |
  | `deferred_choice` | `:deferred_choice` |
  """
  @spec workflow_pattern_values() :: %{
          sequence: :sequence,
          parallel_split: :parallel_split,
          synchronization: :synchronization,
          exclusive_choice: :exclusive_choice,
          simple_merge: :simple_merge,
          multi_choice: :multi_choice,
          structured_loop: :structured_loop,
          deferred_choice: :deferred_choice
        }
  def workflow_pattern_values do
    %{
      sequence: :sequence,
      parallel_split: :parallel_split,
      synchronization: :synchronization,
      exclusive_choice: :exclusive_choice,
      simple_merge: :simple_merge,
      multi_choice: :multi_choice,
      structured_loop: :structured_loop,
      deferred_choice: :deferred_choice
    }
  end

  @doc """
  Enumerated values for `workflow.state`.

  | Key | Value |
  |-----|-------|
  | `pending` | `:pending` |
  | `active` | `:active` |
  | `completed` | `:completed` |
  | `failed` | `:failed` |
  | `cancelled` | `:cancelled` |
  | `suspended` | `:suspended` |
  """
  @spec workflow_state_values() :: %{
          pending: :pending,
          active: :active,
          completed: :completed,
          failed: :failed,
          cancelled: :cancelled,
          suspended: :suspended
        }
  def workflow_state_values do
    %{
      pending: :pending,
      active: :active,
      completed: :completed,
      failed: :failed,
      cancelled: :cancelled,
      suspended: :suspended
    }
  end
end
