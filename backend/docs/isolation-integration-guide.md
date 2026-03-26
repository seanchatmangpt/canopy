# Workspace Isolation Integration Guide

## Quick Start

The Workspace Isolation Validator is automatically started with the Canopy application. No additional configuration needed.

```bash
# Start Canopy (validator starts automatically)
iex -S mix phx.server

# Validate in iex
iex> Canopy.Isolation.Validator.validate_workspace("workspace-id-123")
{:ok, %{result: :pass, violations: []}}
```

## Integration Points

### 1. Agent Lifecycle (When Hiring/Firing Agents)

In `Canopy.Agents.create_agent/1`:

```elixir
def create_agent(attrs) do
  case %Agent{} |> Agent.changeset(attrs) |> Repo.insert() do
    {:ok, agent} ->
      # Agent created — register in isolation validator
      Canopy.Isolation.Validator.validate_workspace(agent.workspace_id)
      # Continue with existing logic...
    error -> error
  end
end
```

When deleting:

```elixir
def delete_agent(%Agent{} = agent) do
  Repo.delete(agent)
  |> tap(fn _result ->
    # Re-validate after deletion
    Canopy.Isolation.Validator.validate_workspace(agent.workspace_id)
  end)
end
```

### 2. Skill Registration (When Hiring Skills)

In `Canopy.Ontology.ToolRegistry` or agent skill assignment:

```elixir
def assign_skill(agent_id, skill_id) do
  {:ok, _} = AgentSkill.create(%{agent_id: agent_id, skill_id: skill_id})

  # Register tool in isolation system
  agent = Canopy.Agents.get_agent!(agent_id)
  Canopy.Isolation.Validator.register_tool(agent.workspace_id, skill_id)

  {:ok, agent}
end

def remove_skill(agent_id, skill_id) do
  AgentSkill.delete(agent_id, skill_id)

  # Unregister tool
  agent = Canopy.Agents.get_agent!(agent_id)
  Canopy.Isolation.Validator.unregister_tool(agent.workspace_id, skill_id)

  {:ok, agent}
end
```

### 3. Agent Memory/Context (When Storing Agent State)

In `Canopy.Adapters.OSA` or agent execution loop:

```elixir
def execute_agent(agent_id, task) do
  agent = Canopy.Agents.get_agent!(agent_id)

  # Store agent context in workspace-isolated memory
  Canopy.Isolation.Validator.store_memory(
    agent.workspace_id,
    "agent:#{agent_id}:context",
    %{current_task: task, status: "running"},
    ttl_ms: 60_000  # 1 minute TTL
  )

  # Execute task...
  result = execute_task(agent, task)

  # Update context
  Canopy.Isolation.Validator.store_memory(
    agent.workspace_id,
    "agent:#{agent_id}:context",
    %{current_task: task, status: "complete", result: result},
    ttl_ms: 60_000
  )

  result
end
```

### 4. Workspace Deletion (Cleanup)

In `Canopy.Workspaces.deactivate_workspace/1`:

```elixir
def deactivate_workspace(workspace_id) do
  # Deactivate workspace
  {:ok, _} = Canopy.WorkspaceIsolation.deactivate_workspace(workspace_id)

  # Clear isolation caches
  Canopy.Isolation.Validator.clear_violations(workspace_id)

  # Optionally: validate remaining workspaces
  Canopy.Isolation.Validator.validate_all_workspaces()

  {:ok, workspace_id}
end
```

### 5. Monitoring & Alerting

Set up telemetry handler in `Canopy.Telemetry`:

```elixir
defmodule Canopy.Telemetry do
  def attach_handlers do
    # ... existing handlers ...

    # Isolation check handler
    :telemetry.attach(
      "isolation_check_handler",
      [:canopy, :isolation, :check],
      &handle_isolation_check/4,
      nil
    )
  end

  defp handle_isolation_check(event, measurements, metadata, _config) do
    if metadata.result == :fail do
      Logger.warning("Isolation violation detected", %{
        workspace_id: metadata.workspace_id,
        violations: metadata.violations,
        measurements: measurements
      })

      # Alert ops team
      # send_alert(:isolation_violation, metadata)
    end
  end
end
```

### 6. API Endpoint (For Manual Validation)

In `CanopyWeb.WorkspaceController`:

```elixir
def validate_isolation(conn, %{"workspace_id" => workspace_id}) do
  with {:ok, workspace} <- Canopy.Workspaces.get_workspace(workspace_id),
       {:ok, report} <- Canopy.Isolation.Validator.validate_workspace(workspace_id) do
    conn
    |> put_status(:ok)
    |> json(report)
  else
    {:error, :not_found} ->
      conn
      |> put_status(:not_found)
      |> json(%{error: "workspace not found"})

    {:error, reason} ->
      conn
      |> put_status(:internal_server_error)
      |> json(%{error: inspect(reason)})
  end
end

# Route: GET /api/workspaces/:workspace_id/validate-isolation
```

### 7. Heartbeat Integration (Periodic Validation)

In `Canopy.Autonomic.Heartbeat`:

```elixir
def handle_heartbeat(workspace_id) do
  # ... existing heartbeat logic ...

  # Validate isolation as part of heartbeat
  {:ok, report} = Canopy.Isolation.Validator.validate_workspace(workspace_id)

  if report.result == :fail do
    Logger.warning("Workspace #{workspace_id} isolation check failed", %{
      violations: report.violations
    })
    # Escalate or trigger healing
  end

  # Continue...
end
```

## Common Patterns

### Pattern 1: Safe Agent Execution

```elixir
def safe_execute(agent_id, task) do
  agent = Canopy.Agents.get_agent!(agent_id)

  # Verify isolation before execution
  unless Canopy.Isolation.Validator.is_isolated?(agent.workspace_id) do
    raise "Workspace isolation violation — execution blocked"
  end

  # Execute with workspace context
  execute_with_context(agent, task)
end
```

### Pattern 2: Cross-Workspace Request Handling

```elixir
def process_workspace_request(user_id, workspace_id, request) do
  # 1. Verify user access
  unless Canopy.WorkspaceIsolation.can_access_workspace?(user_id, workspace_id) do
    {:error, :unauthorized}
  end

  # 2. Verify workspace isolation
  unless Canopy.Isolation.Validator.is_isolated?(workspace_id) do
    {:error, :isolation_violation}
  end

  # 3. Process request in workspace context
  execute_request(workspace_id, request)
end
```

### Pattern 3: Workspace Metrics

```elixir
def get_workspace_health(workspace_id) do
  {:ok, isolation_report} = Canopy.Isolation.Validator.validate_workspace(workspace_id)
  agent_count = Canopy.Isolation.Validator.get_agent_count(workspace_id)

  %{
    workspace_id: workspace_id,
    isolation_status: isolation_report.result,
    agent_count: agent_count,
    violations: isolation_report.violations,
    timestamp: isolation_report.timestamp
  }
end
```

### Pattern 4: Memory Context Management

```elixir
defmodule Canopy.ContextManager do
  @doc "Store request context in workspace memory"
  def store_context(workspace_id, request_id, context, ttl_ms \\ 300_000) do
    Canopy.Isolation.Validator.store_memory(
      workspace_id,
      "request:#{request_id}",
      context,
      ttl_ms
    )
  end

  @doc "Retrieve context (returns {:ok, ctx} or {:error, :expired})"
  def get_context(workspace_id, request_id) do
    Canopy.Isolation.Validator.get_memory(workspace_id, request_id)
  end

  @doc "Context available?"
  def context_available?(workspace_id, request_id) do
    case get_context(workspace_id, request_id) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end
```

## Testing Isolation

### Unit Test Pattern

```elixir
defmodule MyTest do
  use Canopy.DataCase

  test "operation respects workspace isolation" do
    ws1 = create_workspace("ws1")
    ws2 = create_workspace("ws2")

    agent1 = create_agent(ws1.id, "agent1")
    agent2 = create_agent(ws2.id, "agent2")

    # Both workspaces isolated
    assert Canopy.Isolation.Validator.is_isolated?(ws1.id)
    assert Canopy.Isolation.Validator.is_isolated?(ws2.id)

    # Register skill in ws1
    skill = create_skill(ws1.id, "skill1")
    Canopy.Isolation.Validator.register_tool(ws1.id, skill.id)

    # Agent in ws1 can access skill
    assert Canopy.Isolation.Validator.can_access_tool?(ws1.id, skill.id)

    # Agent in ws2 cannot access skill
    refute Canopy.Isolation.Validator.can_access_tool?(ws2.id, skill.id)
  end
end
```

### Integration Test Pattern

```elixir
defmodule MyIntegrationTest do
  use Canopy.DataCase

  test "concurrent operations maintain isolation" do
    ws1 = create_workspace("ws1")
    ws2 = create_workspace("ws2")

    tasks = [
      Task.async(fn ->
        # Store data in ws1
        Canopy.Isolation.Validator.store_memory(ws1.id, "key", "value1", 5000)
        {:ok, v} = Canopy.Isolation.Validator.get_memory(ws1.id, "key")
        v == "value1"
      end),
      Task.async(fn ->
        # Store data in ws2 (different value)
        Canopy.Isolation.Validator.store_memory(ws2.id, "key", "value2", 5000)
        {:ok, v} = Canopy.Isolation.Validator.get_memory(ws2.id, "key")
        v == "value2"
      end)
    ]

    results = Task.await_many(tasks, 10_000)
    assert Enum.all?(results, &Function.identity/1)
  end
end
```

## Troubleshooting

### Issue: Isolation violations detected

**Symptom:** `Isolation.Validator.validate_workspace/1` returns `:fail`

**Steps:**
1. Check violation types: `Canopy.Isolation.Validator.get_violations(workspace_id)`
2. Review the specific violation type (agent_leak, tool_access, etc.)
3. Debug the corresponding check function in `validator.ex`

### Issue: Memory store keys expiring too quickly

**Solution:** Increase TTL when storing:
```elixir
Canopy.Isolation.Validator.store_memory(ws_id, key, value, 600_000)  # 10 minutes
```

### Issue: Tools not registered in workspace

**Solution:** Call `register_tool` when assigning skills:
```elixir
defp assign_skill(agent_id, skill_id) do
  agent = Canopy.Agents.get_agent!(agent_id)
  # ... assign skill ...
  Canopy.Isolation.Validator.register_tool(agent.workspace_id, skill_id)
end
```

## Performance Tuning

### For high-frequency memory access:

```elixir
# Cache locally instead of querying ETS repeatedly
case Canopy.Isolation.Validator.get_memory(ws_id, key) do
  {:ok, value} ->
    # Process value (no further ETS lookups needed)
    {:ok, value}
  {:error, :not_found} ->
    # Compute and store
    result = compute(key)
    Canopy.Isolation.Validator.store_memory(ws_id, key, result, 60_000)
    {:ok, result}
end
```

### For high-frequency tool access checks:

```elixir
# Batch check multiple tools instead of individual calls
tools = ["tool1", "tool2", "tool3"]
allowed = Enum.filter(tools, fn tool_id ->
  Canopy.Isolation.Validator.can_access_tool?(ws_id, tool_id)
end)
```

## See Also

- `lib/canopy/isolation/validator.ex` — Implementation
- `test/canopy/isolation/validator_test.exs` — Test suite (20 tests)
- `lib/canopy/isolation/README.md` — Technical reference
