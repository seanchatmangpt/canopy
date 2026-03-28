defmodule Canopy.Bridges.YawlValidatorSupervisor do
  @moduledoc """
  Supervisor for YAWL validation workers.

  Armstrong principle: every worker is supervised. This supervisor manages
  Task-based validation workers under a DynamicSupervisor so that a failing
  validation never crashes the parent application.

  ## Usage

  Start validation tasks via the supervisor:

      Canopy.Bridges.YawlValidatorSupervisor.validate_async(pipeline, opts)

  The supervisor is started as part of the Canopy application supervision tree.
  """

  use DynamicSupervisor
  require Logger

  @max_children 20
  @task_timeout_ms 5_000

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: @max_children
    )
  end

  @doc """
  Run a pipeline validation asynchronously under supervision.

  Returns `{:ok, task}` where `task` is an awaitable Task, or
  `{:error, :max_children}` if the supervisor is at capacity.

  The caller is responsible for awaiting the task with a timeout:

      {:ok, task} = YawlValidatorSupervisor.validate_async(pipeline)
      result = Task.await(task, 5_000)
  """
  @spec validate_async(list(map()), keyword()) :: {:ok, Task.t()} | {:error, :max_children}
  def validate_async(pipeline, opts \\ []) do
    task_spec = %{
      id: make_ref(),
      start:
        {Task, :start_link,
         [fn -> Canopy.Bridges.YawlValidator.validate(pipeline, opts) end]},
      restart: :temporary,
      shutdown: @task_timeout_ms
    }

    case DynamicSupervisor.start_child(__MODULE__, task_spec) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        {:ok, %Task{pid: pid, ref: ref, owner: self(), mfa: {Canopy.Bridges.YawlValidator, :validate, [pipeline, opts]}}}

      {:error, :max_children} ->
        Logger.warning(
          "[YawlValidatorSupervisor] At capacity (#{@max_children} children), rejecting validation"
        )

        {:error, :max_children}
    end
  end
end
