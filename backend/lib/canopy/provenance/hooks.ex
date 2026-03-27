defmodule Canopy.Provenance.Hooks do
  @moduledoc """
  Integration hooks for provenance emission in Canopy agent workflows.

  Emits PROV-O triples to Oxigraph at key lifecycle points:
    - Agent task execution (activity)
    - Result/artifact generation (entity)
    - Task completion (derivation linking)

  Hooks are called from:
    - Canopy.Work (agent task execution)
    - Canopy.Agents (agent state changes)
    - Canopy.ExecutionWorkspace (workspace operations)

  Signal Theory: S=(hook,trigger,audit,event,rdf)
  """

  require Logger
  alias Canopy.Provenance.OxigraphEmitter

  @doc """
  Hook: Agent task started.

  Called when an agent begins executing a task.
  Emits PROV-O Activity triple.

  ## Parameters:
    - agent_id: ID of agent
    - task_id: unique task identifier
    - task_type: type of task (e.g., "execute_process", "analyze_data")
    - opts: optional map with :input, :params, etc.

  Returns :ok (always succeeds, failures are logged but not raised)
  """
  @spec on_task_start(String.t(), String.t(), String.t(), map()) :: :ok
  def on_task_start(agent_id, task_id, task_type, _opts \\ %{}) do
    activity_id = "#{agent_id}_task_#{task_id}"

    OxigraphEmitter.emit_activity(activity_id, %{
      agent_id: agent_id,
      action_type: task_type,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    :ok
  end

  @doc """
  Hook: Agent task completed successfully.

  Called when an agent task finishes with a result.
  Emits artifact and derivation triples.

  ## Parameters:
    - agent_id: ID of agent
    - task_id: task identifier
    - result: result/output (any term, will be converted to string)
    - opts: optional map with :artifact_type (default "result"), :name, :duration_ms, etc.

  Returns :ok
  """
  @spec on_task_complete(String.t(), String.t(), any(), map()) :: :ok
  def on_task_complete(agent_id, task_id, result, opts \\ %{}) do
    activity_id = "#{agent_id}_task_#{task_id}"
    artifact_id = "artifact_#{task_id}_#{:erlang.unique_integer([:positive])}"

    artifact_type = Map.get(opts, :artifact_type, "result")
    artifact_name = Map.get(opts, :name, "Task #{task_id} Result")
    duration_ms = Map.get(opts, :duration_ms, 0)

    # Emit artifact
    OxigraphEmitter.emit_artifact(artifact_id, %{
      artifact_type: artifact_type,
      name: artifact_name,
      source: "#{agent_id}_task"
    })

    # Emit derivation (artifact came from activity)
    OxigraphEmitter.emit_derivation(artifact_id, activity_id, %{
      role: "primary_output"
    })

    # Update activity with output and duration (emit updated activity)
    output_str = inspect(result, limit: 500)

    OxigraphEmitter.emit_activity("#{activity_id}_complete", %{
      agent_id: agent_id,
      action_type: "task_completion",
      duration_ms: duration_ms,
      status: "ok",
      output: output_str
    })

    :ok
  end

  @doc """
  Hook: Agent task failed.

  Called when an agent task encounters an error.
  Emits activity with error status.

  ## Parameters:
    - agent_id: ID of agent
    - task_id: task identifier
    - error: error term or message
    - opts: optional map with :duration_ms, :task_type, etc.

  Returns :ok
  """
  @spec on_task_error(String.t(), String.t(), any(), map()) :: :ok
  def on_task_error(agent_id, task_id, error, opts \\ %{}) do
    activity_id = "#{agent_id}_task_#{task_id}"
    duration_ms = Map.get(opts, :duration_ms, 0)
    task_type = Map.get(opts, :task_type, "task_execution")

    error_str = inspect(error, limit: 500)

    OxigraphEmitter.emit_activity("#{activity_id}_error", %{
      agent_id: agent_id,
      action_type: task_type,
      status: "error",
      duration_ms: duration_ms,
      output: "Error: #{error_str}"
    })

    :ok
  end

  @doc """
  Hook: Agent made a decision.

  Called when an autonomic agent (healing, compliance, etc.) makes a decision.
  Emits decision artifact and activity.

  ## Parameters:
    - agent_id: ID of autonomic agent
    - decision_type: type of decision (e.g., "healing", "compliance_action")
    - decision_data: map with decision details
    - opts: optional map with :confidence, :reasoning, etc.

  Returns :ok
  """
  @spec on_decision(String.t(), String.t(), map(), map()) :: :ok
  def on_decision(agent_id, decision_type, _decision_data, opts \\ %{}) do
    decision_id = "decision_#{agent_id}_#{:erlang.unique_integer([:positive])}"
    confidence = Map.get(opts, :confidence, 0.5)
    _reasoning = Map.get(opts, :reasoning, "Decision made by #{agent_id}")

    # Emit decision artifact
    decision_name = "#{decision_type} Decision by #{agent_id}"

    OxigraphEmitter.emit_artifact(decision_id, %{
      artifact_type: decision_type,
      name: decision_name,
      source: agent_id
    })

    # Emit decision-making activity
    OxigraphEmitter.emit_activity("#{decision_id}_activity", %{
      agent_id: agent_id,
      action_type: decision_type,
      status: "ok",
      output: "Decision made with confidence #{confidence}"
    })

    # Link decision to activity
    OxigraphEmitter.emit_derivation(decision_id, "#{decision_id}_activity", %{
      role: "decision"
    })

    :ok
  end

  @doc """
  Hook: Workspace execution started.

  Called when a Canopy workspace begins executing a workflow.
  Emits activity for workspace-level operation.

  ## Parameters:
    - workspace_id: ID of workspace
    - workflow_id: workflow identifier
    - opts: optional map with :agents, :description, etc.

  Returns :ok
  """
  @spec on_workflow_start(String.t(), String.t(), map()) :: :ok
  def on_workflow_start(workspace_id, workflow_id, opts \\ %{}) do
    activity_id = "workflow_#{workflow_id}"
    description = Map.get(opts, :description, "Workflow execution")

    OxigraphEmitter.emit_activity(activity_id, %{
      agent_id: "workspace_#{workspace_id}",
      action_type: "workflow_execution",
      input: description
    })

    :ok
  end

  @doc """
  Hook: Workspace execution completed.

  Called when workflow finishes.
  Emits workflow result artifact.

  ## Parameters:
    - workspace_id: workspace ID
    - workflow_id: workflow identifier
    - result_summary: map with workflow result data
    - opts: optional map with :duration_ms, :status, etc.

  Returns :ok
  """
  @spec on_workflow_complete(String.t(), String.t(), map(), map()) :: :ok
  def on_workflow_complete(workspace_id, workflow_id, result_summary, opts \\ %{}) do
    activity_id = "workflow_#{workflow_id}"
    artifact_id = "workflow_result_#{workflow_id}"
    duration_ms = Map.get(opts, :duration_ms, 0)
    status = Map.get(opts, :status, "ok")

    # Emit workflow result artifact
    OxigraphEmitter.emit_artifact(artifact_id, %{
      artifact_type: "workflow_result",
      name: "Workflow #{workflow_id} Result"
    })

    # Emit workflow completion activity
    OxigraphEmitter.emit_activity("#{activity_id}_complete", %{
      agent_id: "workspace_#{workspace_id}",
      action_type: "workflow_completion",
      status: status,
      duration_ms: duration_ms,
      output: inspect(result_summary, limit: 500)
    })

    # Link result to workflow activity
    OxigraphEmitter.emit_derivation(artifact_id, activity_id, %{
      role: "workflow_output"
    })

    :ok
  end

  @doc """
  Hook: Process model discovered or analyzed.

  Called when BusinessOS or process mining discovers a process model.
  Emits model artifact and traceability.

  ## Parameters:
    - source: source system (e.g., "businessos", "pm4py")
    - model_id: identifier for the process model
    - model_type: type of model (e.g., "bpmn", "petri_net")
    - opts: optional map with :name, :variant, :activities_count, etc.

  Returns :ok
  """
  @spec on_process_model_discovered(String.t(), String.t(), String.t(), map()) :: :ok
  def on_process_model_discovered(source, model_id, model_type, opts \\ %{}) do
    artifact_id = "model_#{model_id}"
    name = Map.get(opts, :name, "Process Model #{model_id}")

    # Emit model artifact
    OxigraphEmitter.emit_artifact(artifact_id, %{
      artifact_type: model_type,
      name: name,
      source: source
    })

    # Emit discovery activity
    OxigraphEmitter.emit_activity("discovery_#{model_id}", %{
      agent_id: "system_#{source}",
      action_type: "process_discovery",
      output: "Discovered #{model_type} model"
    })

    # Link model to discovery
    OxigraphEmitter.emit_derivation(artifact_id, "discovery_#{model_id}", %{
      role: "discovery_output"
    })

    :ok
  end

  @doc """
  Hook: Compliance check executed.

  Called when compliance agent runs a compliance check.
  Emits check activity and result artifact.

  ## Parameters:
    - framework: compliance framework (e.g., "SOC2", "HIPAA", "GDPR")
    - check_id: unique check identifier
    - passed: boolean indicating pass/fail
    - opts: optional map with :gaps, :severity, :resource_id, etc.

  Returns :ok
  """
  @spec on_compliance_check(String.t(), String.t(), boolean(), map()) :: :ok
  def on_compliance_check(framework, check_id, passed, opts \\ %{}) do
    activity_id = "compliance_check_#{check_id}"
    artifact_id = "compliance_result_#{check_id}"
    _gaps = Map.get(opts, :gaps, [])
    _severity = Map.get(opts, :severity, "medium")

    # Emit check activity
    status = if passed, do: "ok", else: "error"

    OxigraphEmitter.emit_activity(activity_id, %{
      agent_id: "compliance_agent",
      action_type: "compliance_check",
      status: status,
      output: "#{framework} check: #{if(passed, do: "PASSED", else: "FAILED")}"
    })

    # Emit result artifact
    OxigraphEmitter.emit_artifact(artifact_id, %{
      artifact_type: "compliance_result",
      name: "#{framework} Compliance Check Result"
    })

    # Link result to check
    OxigraphEmitter.emit_derivation(artifact_id, activity_id, %{
      role: "compliance_check_output"
    })

    :ok
  end

  @doc """
  Hook: Agent performance metric recorded.

  Called periodically to record agent performance.
  Emits activity tracking metrics.

  ## Parameters:
    - agent_id: agent identifier
    - metric_name: name of metric (e.g., "task_latency", "error_rate")
    - metric_value: numeric value
    - opts: optional map with :unit, :threshold, etc.

  Returns :ok
  """
  @spec on_metric_recorded(String.t(), String.t(), number(), map()) :: :ok
  def on_metric_recorded(agent_id, metric_name, metric_value, opts \\ %{}) do
    unit = Map.get(opts, :unit, "")
    threshold = Map.get(opts, :threshold, nil)

    activity_id = "metric_#{metric_name}_#{agent_id}"

    output =
      if threshold && metric_value > threshold do
        "#{metric_name}=#{metric_value}#{unit} (above threshold #{threshold})"
      else
        "#{metric_name}=#{metric_value}#{unit}"
      end

    OxigraphEmitter.emit_activity(activity_id, %{
      agent_id: agent_id,
      action_type: "metric_recording",
      status: "ok",
      output: output
    })

    :ok
  end
end
