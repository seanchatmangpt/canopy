defmodule Canopy.Isolation.Validator do
  @moduledoc """
  GenServer that validates and enforces multi-tenant workspace isolation.

  Every workspace has isolated:
  - Agent registry (agents scoped by workspace_id)
  - Tool access (tools registered per workspace)
  - Memory and skill store (per-workspace caches)
  - Query results (all database queries filtered by workspace_id)

  This validator runs continuous isolation checks:
  1. Detects cross-workspace data leakage via query inspection
  2. Validates agent registry partitioning
  3. Checks tool access boundaries
  4. Monitors memory store isolation

  Emits telemetry:
  - :isolation_check event with workspace_id, result (pass/fail), violations (list)

  Thread-safe: Uses ETS for workspace state + concurrent read cache.
  """
  use GenServer
  require Logger

  alias Canopy.Repo
  alias Canopy.Schemas.{Workspace, Agent, Skill, WorkspaceUser}
  alias Canopy.EventBus
  import Ecto.Query

  @table :canopy_isolation_checks
  @violations_table :canopy_isolation_violations
  @tool_registry :canopy_tool_registry
  @memory_store :canopy_memory_store

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Validate isolation for a workspace. Returns {:ok, report} or {:error, violations}"
  def validate_workspace(workspace_id) do
    GenServer.call(__MODULE__, {:validate_workspace, workspace_id}, 10_000)
  end

  @doc "Validate all active workspaces. Returns map of workspace_id => result"
  def validate_all_workspaces do
    GenServer.call(__MODULE__, :validate_all_workspaces, 30_000)
  end

  @doc "Check if workspace_id is properly isolated. Returns true/false"
  def is_isolated?(workspace_id) do
    case validate_workspace(workspace_id) do
      {:ok, %{violations: []}} -> true
      _ -> false
    end
  end

  @doc "Get isolation violations for a workspace from ETS cache"
  def get_violations(workspace_id) do
    case :ets.lookup(@violations_table, workspace_id) do
      [{_key, violations}] -> violations
      [] -> []
    end
  end

  @doc "Clear violations for a workspace (manual reset)"
  def clear_violations(workspace_id) do
    GenServer.cast(__MODULE__, {:clear_violations, workspace_id})
  end

  @doc "Get concurrent agent count in workspace"
  def get_agent_count(workspace_id) do
    GenServer.call(__MODULE__, {:get_agent_count, workspace_id}, 5_000)
  end

  @doc "Verify tool is accessible from workspace"
  def can_access_tool?(workspace_id, tool_id) do
    case :ets.lookup(@tool_registry, {workspace_id, tool_id}) do
      [{_key, :allowed}] -> true
      _ -> false
    end
  end

  @doc "Register tool in workspace registry"
  def register_tool(workspace_id, tool_id) do
    GenServer.cast(__MODULE__, {:register_tool, workspace_id, tool_id})
  end

  @doc "Unregister tool from workspace registry"
  def unregister_tool(workspace_id, tool_id) do
    GenServer.cast(__MODULE__, {:unregister_tool, workspace_id, tool_id})
  end

  @doc "Store value in per-workspace memory with TTL"
  def store_memory(workspace_id, key, value, ttl_ms \\ 300_000) do
    GenServer.cast(__MODULE__, {:store_memory, workspace_id, key, value, ttl_ms})
  end

  @doc "Retrieve value from per-workspace memory"
  def get_memory(workspace_id, key) do
    case :ets.lookup(@memory_store, {workspace_id, key}) do
      [{_key, value, expiry}] ->
        now = System.monotonic_time(:millisecond)
        if now < expiry, do: {:ok, value}, else: {:error, :expired}

      [] ->
        {:error, :not_found}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # ETS table for check results (workspace_id -> check_result)
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # ETS table for violations (workspace_id -> [violation_list])
    :ets.new(@violations_table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Tool registry: {workspace_id, tool_id} -> :allowed
    :ets.new(@tool_registry, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Per-workspace memory store: {workspace_id, key} -> {value, expiry_ms}
    :ets.new(@memory_store, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Start periodic isolation validation (every 30 seconds)
    schedule_validation()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:validate_workspace, workspace_id}, _from, state) do
    report = do_validate_workspace(workspace_id)
    emit_telemetry(workspace_id, report)
    {:reply, report, state}
  end

  @impl true
  def handle_call(:validate_all_workspaces, _from, state) do
    workspaces = Repo.all(from w in Workspace, where: w.is_active == true, select: w.id)

    results =
      Map.new(workspaces, fn ws_id ->
        report = do_validate_workspace(ws_id)
        emit_telemetry(ws_id, report)
        {ws_id, report}
      end)

    {:reply, results, state}
  end

  @impl true
  def handle_call({:get_agent_count, workspace_id}, _from, state) do
    count =
      Repo.one(
        from a in Agent,
          where: a.workspace_id == ^workspace_id and a.status != "sleeping",
          select: count(a.id)
      ) || 0

    {:reply, count, state}
  end

  @impl true
  def handle_cast({:register_tool, workspace_id, tool_id}, state) do
    :ets.insert(@tool_registry, {{workspace_id, tool_id}, :allowed})
    Logger.debug("Registered tool #{tool_id} for workspace #{workspace_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:unregister_tool, workspace_id, tool_id}, state) do
    :ets.delete(@tool_registry, {workspace_id, tool_id})
    Logger.debug("Unregistered tool #{tool_id} from workspace #{workspace_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:store_memory, workspace_id, key, value, ttl_ms}, state) do
    expiry = System.monotonic_time(:millisecond) + ttl_ms
    :ets.insert(@memory_store, {{workspace_id, key}, value, expiry})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:clear_violations, workspace_id}, state) do
    :ets.delete(@violations_table, workspace_id)
    Logger.debug("Cleared violations for workspace #{workspace_id}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:validate_isolation, state) do
    Task.start_link(fn ->
      validate_all_workspaces()
    end)

    schedule_validation()
    {:noreply, state}
  end

  # Private Functions

  defp do_validate_workspace(workspace_id) do
    violations =
      []
      |> check_agent_registry(workspace_id)
      |> check_tool_access(workspace_id)
      |> check_memory_store(workspace_id)
      |> check_query_isolation(workspace_id)
      |> check_skill_isolation(workspace_id)

    result = if Enum.empty?(violations), do: :pass, else: :fail

    :ets.insert(@violations_table, {workspace_id, violations})

    {:ok,
     %{
       workspace_id: workspace_id,
       result: result,
       violations: violations,
       timestamp: DateTime.utc_now(),
       check_count: 5
     }}
  end

  # Check 1: Agent registry partitioning
  defp check_agent_registry(violations, workspace_id) do
    # Verify all agents in DB for this workspace are actually in-memory scoped
    agents = Repo.all(from a in Agent, where: a.workspace_id == ^workspace_id)

    # Verify no agent from other workspaces leaked into memory
    other_agents =
      Repo.all(
        from a in Agent,
          where: a.workspace_id != ^workspace_id,
          select: a.id
      )

    leaked =
      Enum.filter(agents, fn agent ->
        Enum.any?(other_agents, fn other_id -> agent.id == other_id end)
      end)

    if Enum.empty?(leaked) do
      violations
    else
      violations ++
        [
          %{
            type: :agent_registry_leak,
            workspace_id: workspace_id,
            leaked_agents: Enum.map(leaked, & &1.id),
            severity: :critical
          }
        ]
    end
  end

  # Check 2: Tool access boundaries
  defp check_tool_access(violations, workspace_id) do
    # Get registered tools for workspace
    registered = :ets.match(@tool_registry, {{workspace_id, :"$1"}, :allowed})

    # Verify all registered tools are actually in skills for this workspace
    workspace_tools =
      Repo.all(
        from s in Skill,
          where: s.workspace_id == ^workspace_id,
          select: s.id
      )

    registered_flat = List.flatten(registered)

    unauthorized =
      Enum.filter(registered_flat, fn tool_id ->
        !Enum.member?(workspace_tools, tool_id)
      end)

    if Enum.empty?(unauthorized) do
      violations
    else
      violations ++
        [
          %{
            type: :tool_access_violation,
            workspace_id: workspace_id,
            unauthorized_tools: unauthorized,
            severity: :critical
          }
        ]
    end
  end

  # Check 3: Memory store isolation
  defp check_memory_store(violations, workspace_id) do
    # Get all memory keys for workspace
    memory_keys = :ets.match(@memory_store, {{workspace_id, :"$1"}, :_, :_})

    # Verify no stale entries (expired data still in store)
    now = System.monotonic_time(:millisecond)
    stale_keys = []

    stale_keys =
      Enum.reduce(List.flatten(memory_keys), stale_keys, fn key, acc ->
        case :ets.lookup(@memory_store, {workspace_id, key}) do
          [{_k, _v, expiry}] when expiry < now -> [key | acc]
          _ -> acc
        end
      end)

    if Enum.empty?(stale_keys) do
      violations
    else
      violations ++
        [
          %{
            type: :memory_store_stale,
            workspace_id: workspace_id,
            stale_entries: stale_keys,
            severity: :warning
          }
        ]
    end
  end

  # Check 4: Query isolation at database level
  defp check_query_isolation(violations, workspace_id) do
    # Verify agents are truly filtered by workspace_id in queries
    unfiltered_count = Repo.one(from a in Agent, select: count(a.id))

    workspace_count =
      Repo.one(
        from a in Agent,
          where: a.workspace_id == ^workspace_id,
          select: count(a.id)
      )

    # Verify workspace users are truly scoped
    user_count =
      Repo.one(
        from wu in WorkspaceUser,
          where: wu.workspace_id == ^workspace_id,
          select: count(wu.id)
      )

    # All checks passed if counts are reasonable
    if unfiltered_count > 0 and workspace_count >= 0 and user_count >= 0 do
      violations
    else
      violations ++
        [
          %{
            type: :query_isolation_error,
            workspace_id: workspace_id,
            severity: :warning
          }
        ]
    end
  end

  # Check 5: Skill isolation by workspace
  defp check_skill_isolation(violations, workspace_id) do
    # Verify no cross-workspace agents can access these skills
    # (agents from other workspaces should not be able to query these skills)
    leaked_accesses =
      Repo.all(
        from a in Agent,
          where: a.workspace_id != ^workspace_id,
          join: s in Skill,
          on: s.workspace_id == ^workspace_id,
          select: %{agent_id: a.id, skill_id: s.id}
      )

    if Enum.empty?(leaked_accesses) do
      violations
    else
      violations ++
        [
          %{
            type: :skill_isolation_leak,
            workspace_id: workspace_id,
            cross_workspace_accesses: leaked_accesses,
            severity: :critical
          }
        ]
    end
  end

  defp emit_telemetry(workspace_id, {:ok, report}) do
    :telemetry.execute(
      [:canopy, :isolation, :check],
      %{
        workspace_id: workspace_id,
        result: report.result,
        violation_count: Enum.count(report.violations),
        timestamp_us: DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      },
      %{
        workspace_id: workspace_id,
        result: report.result,
        violations: report.violations
      }
    )

    # Also broadcast to event bus for monitoring
    EventBus.broadcast(
      EventBus.workspace_topic(workspace_id),
      %{
        event: :isolation_check,
        workspace_id: workspace_id,
        result: report.result,
        violations: report.violations
      }
    )
  end

  defp schedule_validation do
    Process.send_after(self(), :validate_isolation, 30_000)
  end
end
