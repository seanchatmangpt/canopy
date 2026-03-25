defmodule Canopy.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CanopyWeb.Telemetry,
      Canopy.Repo,
      Canopy.BudgetEnforcer,
      {Phoenix.PubSub, name: Canopy.PubSub},
      Canopy.IssueDispatcher,
      Canopy.Scheduler,
      {DynamicSupervisor, name: Canopy.AdapterSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Canopy.HeartbeatRunner},
      {Task.Supervisor, name: Canopy.TaskSupervisor},
      Canopy.AlertEvaluator,
      Canopy.StaleCleanup,
      Canopy.IdempotencyCleanup,
      Canopy.Autonomic.Heartbeat,
      CanopyWeb.Endpoint
    ]

    # Create ETS table for idempotency plug before endpoint starts (avoids TOCTOU race)
    :ets.new(:canopy_idempotency_cache, [:named_table, :set, :public, read_concurrency: true])

    opts = [strategy: :one_for_one, name: Canopy.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, _pid} ->
        # Load schedules asynchronously to avoid startup issues
        Task.start(fn -> Canopy.Scheduler.load_schedules() end)
      _ -> :ok
    end

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    CanopyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
