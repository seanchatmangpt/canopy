defmodule Canopy.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Start Finch only if not already started (Req may start it automatically)
    finch_child = case Process.whereis(Req.Finch) do
      nil -> {Finch, name: Req.Finch, pools: %{:default => [size: 32]}}
      _pid -> nil
    end

    children = [
      CanopyWeb.Telemetry,
      Canopy.Repo,
      Canopy.BudgetEnforcer,
      {Phoenix.PubSub, name: Canopy.PubSub},
      Canopy.IssueDispatcher,
      Canopy.Mesh.SyncWorker,
      Canopy.Scheduler,
      {DynamicSupervisor, name: Canopy.AdapterSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: Canopy.HeartbeatRunner},
      {Task.Supervisor, name: Canopy.TaskSupervisor},
      {Task.Supervisor, name: :canopy_jtbd_loop_supervisor},
      Canopy.AlertEvaluator,
      Canopy.StaleCleanup,
      Canopy.IdempotencyCleanup,
      Canopy.Isolation.Validator,
      Canopy.Autonomic.Heartbeat,
      Canopy.Board.ConwayMonitor,
      Canopy.Ontology.Loader,
      Canopy.Ontology.Service,
      Canopy.Ontology.ToolRegistry,
      Canopy.JTBD.SelfPlayLoop,
      Canopy.Yawl.Client,
      Canopy.Bridges.YawlValidatorSupervisor,
      %{
        id: :canopy_consent_agent,
        start: {Agent, :start_link, [fn -> %{} end, [name: :canopy_consent_agent]]}
      }
    ]

    Application.put_env(:canopy, :consent_agent, :canopy_consent_agent)

    # Add Finch to children only if not already started
    children = if finch_child, do: children ++ [finch_child], else: children

    children = children ++ [CanopyWeb.Endpoint]

    # Create ETS tables for caches and metrics before endpoint starts (avoids TOCTOU race)
    Canopy.Mesh.Cache.init()
    Canopy.Autonomic.CircuitBreaker.init()
    Canopy.Autonomic.ExecutionLog.init()
    Canopy.Autonomic.ScheduleGovernor.init()
    :ets.new(:canopy_idempotency_cache, [:named_table, :set, :public, read_concurrency: true])

    # BOS intelligence cache: single-row overwrite, bounded memory.
    :ets.new(:canopy_bos_intelligence, [:named_table, :set, :public, read_concurrency: true])

    # Wave 12 metrics table: bounded LRU cache for iteration metrics (WvdA soundness)
    :ets.new(:jtbd_wave12_metrics, [
      :named_table,
      :set,
      :public,
      {:write_concurrency, false},
      {:read_concurrency, true}
    ])

    # YAWLv6 build tracker: store latest simulation/real build state
    Canopy.JTBD.YAWLv6BuildTracker.init()

    OpentelemetryPhoenix.setup()

    opts = [strategy: :one_for_one, name: Canopy.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, _pid} ->
        # Load schedules asynchronously via supervised task (Armstrong: supervised startup)
        Task.Supervisor.start_child(
          Canopy.TaskSupervisor,
          Canopy.Scheduler,
          :load_schedules,
          []
        )

      _ ->
        :ok
    end

    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    CanopyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
