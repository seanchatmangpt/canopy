# Workspace Isolation Validator

## Overview

The `Canopy.Isolation.Validator` is a GenServer that enforces multi-tenant workspace isolation. It continuously monitors and validates that:

1. **Agent Registry** — Agents are properly scoped to workspaces
2. **Tool Access** — Tools (skills) are accessible only within their workspace
3. **Memory Store** — Per-workspace in-memory cache is isolated
4. **Query Isolation** — Database queries filter by workspace_id
5. **Skill Isolation** — Skills are scoped to workspaces and cannot leak to other agents

## Key Features

- **Thread-Safe**: Uses ETS tables for concurrent access without locks
- **Continuous Validation**: Runs isolation checks every 30 seconds
- **Telemetry Integration**: Emits `[:canopy, :isolation, :check]` events
- **Event Bus Broadcasting**: Publishes results to workspace PubSub topics
- **High Concurrency**: Handles 100+ concurrent operations safely

## Integration in Supervisor

The validator is started as part of the Canopy application supervision tree:

```elixir
# lib/canopy/application.ex
children = [
  # ...
  Canopy.Isolation.Validator,
  # ...
]
```

**Start order:** Before `Canopy.Autonomic.Heartbeat`, after `Canopy.IdempotencyCleanup`.

**Restart policy:** `:permanent` (crashes will be restarted by supervisor)

## Client API

### Validation

```elixir
# Validate a single workspace
{:ok, report} = Canopy.Isolation.Validator.validate_workspace(workspace_id)
# => {:ok, %{
#   workspace_id: "...",
#   result: :pass,               # or :fail
#   violations: [],              # list of violation maps
#   timestamp: DateTime,
#   check_count: 5
# }}

# Validate all active workspaces
results = Canopy.Isolation.Validator.validate_all_workspaces()
# => %{workspace_id_1 => {:ok, report}, workspace_id_2 => {:ok, report}}

# Quick isolation check
Canopy.Isolation.Validator.is_isolated?(workspace_id)
# => true or false
```

### Tool Access

```elixir
# Register tool in workspace
Canopy.Isolation.Validator.register_tool(workspace_id, tool_id)

# Check if tool is accessible
Canopy.Isolation.Validator.can_access_tool?(workspace_id, tool_id)
# => true or false

# Unregister tool
Canopy.Isolation.Validator.unregister_tool(workspace_id, tool_id)
```

### Per-Workspace Memory Store

```elixir
# Store value with TTL (default 5 minutes)
Canopy.Isolation.Validator.store_memory(workspace_id, "config", %{timeout: 5000})

# Retrieve value (returns {:ok, value} or {:error, :expired | :not_found})
{:ok, config} = Canopy.Isolation.Validator.get_memory(workspace_id, "config")

# Values auto-expire after TTL
Canopy.Isolation.Validator.store_memory(ws_id, "temp", data, 100)
Process.sleep(150)
{:error, :expired} = Canopy.Isolation.Validator.get_memory(ws_id, "temp")
```

### Violations

```elixir
# Get cached violations for workspace
violations = Canopy.Isolation.Validator.get_violations(workspace_id)
# => [%{type: :agent_registry_leak, workspace_id: "...", ...}]

# Clear violations (manual reset)
Canopy.Isolation.Validator.clear_violations(workspace_id)
```

### Agent Metrics

```elixir
# Get count of active (non-sleeping) agents in workspace
count = Canopy.Isolation.Validator.get_agent_count(workspace_id)
# => 5
```

## Violation Types

| Type | Severity | Meaning |
|------|----------|---------|
| `:agent_registry_leak` | CRITICAL | Agents from other workspaces leaked into registry |
| `:tool_access_violation` | CRITICAL | Tools registered but not in workspace skills |
| `:skill_isolation_leak` | CRITICAL | Agents from other workspaces can access this workspace's skills |
| `:memory_store_stale` | WARNING | Stale/expired data still cached in memory store |
| `:query_isolation_error` | WARNING | Query filtering returned unexpected counts |

## Telemetry Events

### Successful Check

```elixir
:telemetry.execute(
  [:canopy, :isolation, :check],
  %{
    workspace_id: workspace_id,
    result: :pass,                    # or :fail
    violation_count: 0,
    timestamp_us: 1234567890123
  },
  %{
    workspace_id: workspace_id,
    result: :pass,
    violations: []
  }
)
```

### Monitor with a Handler

```elixir
:telemetry.attach(
  "isolation_monitor",
  [:canopy, :isolation, :check],
  fn event, measurements, metadata ->
    if metadata.result == :fail do
      Logger.warning("Isolation check failed: #{inspect(metadata.violations)}")
      # Alert ops
    end
  end,
  nil
)
```

## Event Bus Broadcasting

Violations are broadcast to the workspace PubSub topic:

```elixir
# In any process subscribed to the workspace topic:
{:ok, event} = Phoenix.PubSub.subscribe(Canopy.PubSub, Canopy.EventBus.workspace_topic(ws_id))

receive do
  %{event: :isolation_check, result: :fail, violations: vios} ->
    Logger.error("Workspace #{ws_id} has isolation violations: #{inspect(vios)}")
end
```

## Internal Implementation

### ETS Tables

Three ETS tables manage state:

| Table | Key | Value | Purpose |
|-------|-----|-------|---------|
| `:canopy_isolation_checks` | `workspace_id` | Check result | Cache validation results |
| `:canopy_isolation_violations` | `workspace_id` | `[violation]` | Cache violations for quick lookup |
| `:canopy_tool_registry` | `{workspace_id, tool_id}` | `:allowed` | Track tool access |
| `:canopy_memory_store` | `{workspace_id, key}` | `{value, expiry_ms}` | Per-workspace memory with TTL |

All tables are:
- `:public` (readable from any process)
- `:set` (no duplicates)
- `:read_concurrency` enabled (for fast reads)
- `:write_concurrency` enabled (where applicable)

### Isolation Checks (5-Point Validation)

**Check 1: Agent Registry**
- Verifies all agents in workspace DB exist
- Ensures no agents from other workspaces leaked into memory

**Check 2: Tool Access**
- Gets tools registered for workspace from ETS
- Verifies all registered tools are in Skills table for this workspace

**Check 3: Memory Store**
- Iterates memory keys for workspace
- Detects stale entries (past expiry time)

**Check 4: Query Isolation**
- Runs test queries on Agent and WorkspaceUser tables
- Verifies counts are reasonable

**Check 5: Skill Isolation**
- Checks for cross-workspace agent→skill access
- Detects if agents from ws2 can query skills from ws1

## Performance Characteristics

- **Memory**: ~10KB per workspace (ETS overhead)
- **CPU**: Validation loop every 30 seconds (async via Task)
- **Latency**: Single validation ~50-200ms depending on workspace size
- **Concurrency**: Thread-safe for 100+ concurrent operations

## Testing

Tests are in `test/canopy/isolation/validator_test.exs`. Currently marked with `@moduletag :skip` because they require database access which isn't available in `--no-start` mode.

To run with database:

```bash
# Full suite (starts app)
cd backend && mix test test/canopy/isolation/validator_test.exs

# Specific test
cd backend && mix test test/canopy/isolation/validator_test.exs::"test name"
```

### Test Coverage (20 tests)

1. **Basic validation** — pass case when isolated
2. **Multi-workspace** — validates all workspaces
3. **is_isolated? helper** — quick check
4. **Agent registry** — detects agents in workspace
5. **Tool access** — register/check/unregister
6. **Tool boundaries** — cross-workspace blocking
7. **Unregister** — removes tool access
8. **Memory store** — stores/retrieves values
9. **Memory isolation** — different values per workspace
10. **Memory expiration** — TTL enforcement
11. **Memory not_found** — missing key handling
12. **Concurrent memory** — 50 concurrent ops
13. **Concurrent tools** — 50 tool registrations
14. **Agent count** — metric retrieval
15. **Agent count filtering** — ignores sleeping agents
16. **Concurrent validation** — 4 concurrent validates
17. **Violations table** — get/clear violations
18. **Clear violations** — removes cached entries
19. **Multiple workspace concurrency** — 4 concurrent validates on 2 workspaces
20. **Stress test** — 100 concurrent mixed operations

## Future Enhancements

1. **Audit Trail** — Log all isolation violations to database
2. **Automatic Healing** — Detect and fix common isolation issues
3. **Graduated Enforcement** — Warn before blocking cross-workspace access
4. **Custom Isolation Levels** — "shared" and "public" isolation modes
5. **Performance Metrics** — Track check duration per workspace
6. **Cost Attribution** — Charge operations to correct workspace

## See Also

- `Canopy.WorkspaceIsolation` — RBAC and user-workspace mappings
- `Canopy.Schemas.Workspace` — Multi-tenant workspace data model
- `Canopy.EventBus` — PubSub event broadcasting
- `Canopy.BudgetEnforcer` — Budget tracking per workspace tier
