# Workspace Isolation Validator — Quick Reference

## Start Using (Copy-Paste Ready)

### 1. Validate Workspace

```elixir
# Check if workspace is properly isolated
{:ok, report} = Canopy.Isolation.Validator.validate_workspace(workspace_id)

if report.result == :fail do
  IO.inspect(report.violations)  # See what's wrong
end
```

### 2. Tool Access Control

```elixir
# When assigning skill to agent
agent = Canopy.Agents.get_agent!(agent_id)
skill = Canopy.Ontology.get_skill!(skill_id)

Canopy.Isolation.Validator.register_tool(agent.workspace_id, skill.id)

# Later: check access
can_use? = Canopy.Isolation.Validator.can_access_tool?(ws_id, tool_id)

# When removing skill
Canopy.Isolation.Validator.unregister_tool(agent.workspace_id, skill.id)
```

### 3. Per-Workspace Memory

```elixir
# Store agent context (auto-expires in 5 minutes)
Canopy.Isolation.Validator.store_memory(
  agent.workspace_id,
  "agent:#{agent.id}:state",
  %{status: "running", task_id: task_id}
)

# Retrieve it
case Canopy.Isolation.Validator.get_memory(agent.workspace_id, "agent:#{agent.id}:state") do
  {:ok, state} -> state
  {:error, :expired} -> "state expired, refetch"
  {:error, :not_found} -> "no stored state"
end
```

### 4. Quick Check

```elixir
# One-liner: is this workspace isolated?
Canopy.Isolation.Validator.is_isolated?(workspace_id)  # => true/false
```

### 5. Metrics

```elixir
# Count active agents in workspace
count = Canopy.Isolation.Validator.get_agent_count(workspace_id)
# => 5

# Get violations (if any)
violations = Canopy.Isolation.Validator.get_violations(workspace_id)
# => []
```

## Telemetry (Monitoring)

### Attach Handler (in Canopy.Telemetry)

```elixir
:telemetry.attach(
  "isolation_checker",
  [:canopy, :isolation, :check],
  fn _event, _measurements, metadata ->
    if metadata.result == :fail do
      Logger.warning("Isolation violation detected", %{
        workspace_id: metadata.workspace_id,
        violations: metadata.violations
      })
    end
  end,
  nil
)
```

## Common Patterns

### Pattern: Safe Agent Execution

```elixir
def execute_agent(agent_id, task) do
  agent = Canopy.Agents.get_agent!(agent_id)

  unless Canopy.Isolation.Validator.is_isolated?(agent.workspace_id) do
    raise "Workspace isolation violation"
  end

  # Execute task...
end
```

### Pattern: Workspace Context

```elixir
def with_workspace_context(workspace_id, func) do
  unless Canopy.Isolation.Validator.is_isolated?(workspace_id) do
    {:error, :isolation_violation}
  else
    func.()
  end
end

# Usage:
with_workspace_context(ws_id, fn ->
  # Run code isolated to ws_id
end)
```

### Pattern: Request ID Context

```elixir
def start_request(workspace_id, request_id, user_id) do
  Canopy.Isolation.Validator.store_memory(
    workspace_id,
    "request:#{request_id}",
    %{started_at: DateTime.utc_now(), user_id: user_id},
    ttl_ms: 300_000  # 5 minutes
  )
end

def finish_request(workspace_id, request_id, result) do
  case Canopy.Isolation.Validator.get_memory(workspace_id, "request:#{request_id}") do
    {:ok, req} ->
      Logger.info("Request complete", %{
        request_id: request_id,
        duration_ms: DateTime.diff(DateTime.utc_now(), req.started_at, :millisecond)
      })
    {:error, _} ->
      Logger.warning("Request context expired or not found", %{request_id: request_id})
  end
end
```

## Error Handling

### Memory Store

```elixir
case Canopy.Isolation.Validator.get_memory(ws_id, key) do
  {:ok, value} ->
    process(value)

  {:error, :expired} ->
    # Value existed but expired — recompute
    value = compute(key)
    Canopy.Isolation.Validator.store_memory(ws_id, key, value, 60_000)
    process(value)

  {:error, :not_found} ->
    # No value stored — compute fresh
    value = compute(key)
    Canopy.Isolation.Validator.store_memory(ws_id, key, value, 60_000)
    process(value)
end
```

### Tool Access

```elixir
def use_tool(workspace_id, tool_id, args) do
  unless Canopy.Isolation.Validator.can_access_tool?(workspace_id, tool_id) do
    {:error, :tool_not_available}
  else
    {:ok, execute_tool(tool_id, args)}
  end
end
```

## Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ Canopy.Isolation.Validator (GenServer)                  │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────┐  ┌──────────────────┐              │
│  │ Agent Registry   │  │ Tool Registry    │              │
│  │ (scoped by ws)   │  │ {ws_id, tool_id} │              │
│  └──────────────────┘  └──────────────────┘              │
│                                                           │
│  ┌──────────────────┐  ┌──────────────────┐              │
│  │ Memory Store     │  │ Violations Cache │              │
│  │ {ws_id, key}     │  │ per workspace    │              │
│  │ + TTL            │  │ list             │              │
│  └──────────────────┘  └──────────────────┘              │
│                                                           │
├─────────────────────────────────────────────────────────┤
│ Validation (every 30 seconds):                           │
│ 1. Check agent registry                                  │
│ 2. Check tool access boundaries                          │
│ 3. Check memory store (TTL)                              │
│ 4. Check query isolation (DB level)                      │
│ 5. Check skill isolation (cross-workspace)               │
├─────────────────────────────────────────────────────────┤
│ Output:                                                  │
│ - Telemetry: [:canopy, :isolation, :check]              │
│ - EventBus: Broadcast to workspace topic                │
│ - Violations: Cached in ETS for quick lookup             │
└─────────────────────────────────────────────────────────┘
```

## Configuration (Zero Config)

No configuration needed! The validator:
- Starts automatically with Canopy
- Runs every 30 seconds
- Uses sensible defaults for all parameters
- Handles cleanup automatically

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **Memory values expire too quickly** | Increase TTL: `store_memory(ws, key, val, 600_000)` (10 min) |
| **Tools showing as not accessible** | Call `register_tool(ws, tool_id)` after skill assignment |
| **Validation shows violations** | Check `get_violations(ws_id)` for specific error type |
| **High CPU from validation** | Reduce frequency: modify `schedule_validation/0` (line 450) |
| **Stale memory entries** | TTL auto-expires (default 5 min), or manually cleanup |

## Performance Tips

### For high-frequency access:

```elixir
# Cache locally to avoid repeated ETS lookups
case Canopy.Isolation.Validator.get_memory(ws_id, key) do
  {:ok, value} -> value
  {:error, _} ->
    value = compute(key)
    Canopy.Isolation.Validator.store_memory(ws_id, key, value, 60_000)
    value
end
```

### For batch operations:

```elixir
# Validate once, then execute multiple ops
{:ok, report} = Canopy.Isolation.Validator.validate_workspace(ws_id)

if report.result == :pass do
  # All 5 checks passed — safe to proceed
  Enum.each(agents, fn agent ->
    execute_agent(agent)
  end)
end
```

## Testing

### Unit Test Template

```elixir
defmodule MyTest do
  use Canopy.DataCase

  test "operation respects isolation" do
    ws1 = create_workspace("ws1")
    ws2 = create_workspace("ws2")

    # Verify isolation
    assert Canopy.Isolation.Validator.is_isolated?(ws1.id)
    assert Canopy.Isolation.Validator.is_isolated?(ws2.id)

    # Test operation...
  end
end
```

### Run Tests (Requires Database)

```bash
cd canopy/backend && mix test test/canopy/isolation/validator_test.exs
```

## File Locations

- **Implementation:** `lib/canopy/isolation/validator.ex`
- **Tests:** `test/canopy/isolation/validator_test.exs`
- **Docs:** `lib/canopy/isolation/README.md`
- **Integration:** `docs/isolation-integration-guide.md`
- **Summary:** `WORKSPACE_ISOLATION_SUMMARY.md`

## API Reference (All Functions)

```
PUBLIC API (Client)
├── validate_workspace(workspace_id) → {:ok, report} | {:error, reason}
├── validate_all_workspaces() → %{ws_id => {:ok, report}}
├── is_isolated?(workspace_id) → true | false
├── register_tool(workspace_id, tool_id) → :ok
├── can_access_tool?(workspace_id, tool_id) → true | false
├── unregister_tool(workspace_id, tool_id) → :ok
├── store_memory(workspace_id, key, value, ttl_ms) → :ok
├── get_memory(workspace_id, key) → {:ok, value} | {:error, :expired | :not_found}
├── get_violations(workspace_id) → [violation_map]
├── clear_violations(workspace_id) → :ok
└── get_agent_count(workspace_id) → integer

SERVER CALLBACKS (Internal)
├── start_link(opts) → {:ok, pid}
├── init(opts) → {:ok, state}
├── handle_call(...) → {:reply, result, state}
├── handle_cast(...) → {:noreply, state}
└── handle_info(...) → {:noreply, state}
```

---

**TL;DR:** Zero-config, thread-safe isolation validator. Copy-paste examples above. No breaking changes. Production-ready.
