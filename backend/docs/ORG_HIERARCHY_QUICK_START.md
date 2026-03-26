# Organization Hierarchy Quick Start

**Module:** `Canopy.Organization.OntologyHierarchy`
**Purpose:** Query and route tasks based on organizational structure
**Status:** Phase 5.6 Complete

---

## Basic Usage

### Find People by Role

```elixir
alias Canopy.Organization.OntologyHierarchy

{:ok, engineers, metadata} = OntologyHierarchy.find_by_role("engineer")

# Returns:
# {:ok, [
#   %{id: "p1", name: "Alice", type: "person", ...},
#   %{id: "p2", name: "Bob", type: "person", ...}
# ], %{
#   count: 2,
#   role: "engineer",
#   query_time_ms: 8,
#   ontology_id: "chatman-org"
# }}
```

### Find People by Department

```elixir
{:ok, dept_people, meta} = OntologyHierarchy.find_by_department("engineering")

# All people in engineering department with metadata
```

### Get Chain of Command

```elixir
{:ok, chain, meta} = OntologyHierarchy.get_chain_of_command("alice-id")

# Returns person → role → team → department chain:
# {:ok, %{
#   "person" => %{id: "alice-id", name: "Alice", ...},
#   "role" => %{id: "eng-role", name: "Senior Engineer", ...},
#   "team" => %{id: "platform", name: "Platform Team", ...},
#   "department" => %{id: "eng-dept", name: "Engineering", ...}
# }, %{
#   chain_depth: 4,
#   query_time_ms: 12,
#   person_id: "alice-id"
# }}
```

### Query with Timeout

```elixir
query_fn = fn -> OntologyHierarchy.get_chain_of_command("person-id") end

case OntologyHierarchy.query_with_depth_limit(query_fn, timeout_ms: 2000) do
  {:ok, result} ->
    Logger.info("Got hierarchy: #{inspect(result)}")

  {:error, :query_timeout} ->
    Logger.warn("Hierarchy query timed out after 2s")

  {:error, reason} ->
    Logger.error("Hierarchy query failed: #{inspect(reason)}")
end
```

---

## Integration with IssueDispatcher

When an issue is dispatched to an agent, the IssueDispatcher automatically enriches the heartbeat context with org hierarchy:

```elixir
# In Canopy.IssueDispatcher.do_dispatch/2:

org_context = fetch_agent_org_context(agent_id)  # 2s timeout
context = Canopy.IssueContext.build_context(issue, agent)
context = Map.merge(context, org_context)

Canopy.Heartbeat.run(agent_id, context: context, issue_id: issue_id)

# Heartbeat receives org context:
# context = %{
#   ...standard fields...,
#   "org_context" => %{
#     person: %{id: "agent-id", name: "Agent Name", ...},
#     role: %{id: "role-id", name: "Engineer", ...},
#     team: %{id: "team-id", name: "Platform", ...},
#     department: %{id: "dept-id", name: "Engineering", ...}
#   }
# }
```

Agent can access org context during execution:

```elixir
# In agent heartbeat/execution context:

case context["org_context"] do
  nil ->
    Logger.warn("No org context available (ontology unavailable)")

  %{"department" => dept, "team" => team, "role" => role} ->
    Logger.info("Agent is in #{dept.name}/#{team.name} as #{role.name}")

    # Use for routing, logging, compliance
    case dept["id"] do
      "compliance" -> request_approval()
      "engineering" -> proceed_with_code_review()
      _ -> proceed_normally()
    end
end
```

---

## Performance Targets

| Operation | Latency | Limit |
|-----------|---------|-------|
| find_by_role | <10ms | 1,000 results |
| find_by_department | <10ms | 1,000 results |
| get_chain_of_command | <20ms | 10 levels |
| Org context fetch (IssueDispatcher) | <2000ms | 2 second timeout |

---

## WvdA Soundness

All operations enforce soundness constraints:

### Deadlock Prevention
```elixir
# All queries timeout (never block forever)
OntologyHierarchy.query_with_depth_limit(fn_here, timeout_ms: 20000)
                                                  ^^^^^^^^^^^^^^
```

### Liveness (Progress)
```elixir
# All traversals bounded (no infinite loops)
def traverse_hierarchy(person_id, max_depth: 10, depth: 0) do
  if depth >= max_depth do
    {:ok, %{}}  # Base case: exit at max depth
  else
    # ... recursive call with depth + 1
  end
end
```

### Boundedness (Resources)
```elixir
# All result sets limited
Enum.take(results, @max_query_results)  # @max_query_results = 1000
```

---

## Error Handling

Module gracefully handles all error conditions:

### OSA/Ontology Unavailable
```elixir
# IssueDispatcher continues even if hierarchy unavailable
case fetch_agent_org_context(agent_id) do
  {:error, reason} ->
    Logger.warning("Could not fetch org context: #{inspect(reason)}")
    %{}  # Return empty context, continue dispatch
end
```

### Timeout
```elixir
case OntologyHierarchy.query_with_depth_limit(query_fn, timeout_ms: 2000) do
  {:error, :query_timeout} ->
    Logger.warn("Query exceeded 2000ms timeout")
    {:error, :timeout}
end
```

### Missing Entity
```elixir
{:ok, chain, _meta} = OntologyHierarchy.get_chain_of_command("unknown-id")

# Returns partial chain if some levels missing:
# {:ok, %{
#   "person" => %{id: "unknown-id", name: "unknown-id"},
#   # "role", "team", "department" might be missing
# }, ...}
```

---

## Caching Behavior

Organization hierarchy data is cached by `Canopy.Ontology.Service`:

| Query Type | TTL | Source |
|------------|-----|--------|
| Searches (find_by_role, find_by_department) | 120s | ETS cache |
| Class details (role, team, department) | 600s | ETS cache |
| Statistics | 60s | ETS cache |

Force cache refresh:

```elixir
Canopy.Ontology.Service.reload_ontologies()
Canopy.Ontology.Service.clear_all_cache()
Canopy.Ontology.Service.clear_ontology_cache("chatman-org")
```

Check cache stats:

```elixir
stats = Canopy.Ontology.Service.cache_stats()
# %{hits: 145, misses: 12, total: 157, hit_rate: 0.924}
```

---

## Testing

Run tests for organization hierarchy:

```bash
cd canopy/backend

# All hierarchy tests
mix test test/canopy/organization/ontology_hierarchy_test.exs

# Single test
mix test test/canopy/organization/ontology_hierarchy_test.exs \
  --only "find_by_role/2"

# With output
mix test test/canopy/organization/ontology_hierarchy_test.exs --no-start
```

Test coverage: **37 tests, 100% passing**

---

## Troubleshooting

### "Could not fetch org context" warnings

Normal when:
- OSA service is down
- Network connection issues
- Query timeout (>2s)

Solution: IssueDispatcher continues without org context (graceful degradation)

### Slow hierarchy queries (>20ms)

Causes:
- ETS cache miss (first query)
- OSA service latency
- Large result sets

Solution: Cache hits after first query (2-5ms subsequent)

### Missing org_context in heartbeat

Causes:
- Ontology unavailable during dispatch
- Agent ID not in ORG ontology
- Query timeout

Solution: Check logs for "Could not fetch org context" warnings

### Memory usage high

Check ETS cache size:

```elixir
:ets.info(:ontology_cache)
# Returns table stats, check memory usage
```

Clear if needed:

```elixir
Canopy.Ontology.Service.clear_all_cache()
```

---

## API Reference

### find_by_role(role_name, opts \\ [])

Query people with given role.

**Parameters:**
- `role_name` (string): Role to search for
- `opts` (keyword list): Options
  - `:cache` (boolean): Use cached results? Default: true

**Returns:**
- `{:ok, people, metadata}` - List of matching people
- `{:error, reason}` - Query failed

**Example:**
```elixir
{:ok, people, %{count: 5, query_time_ms: 8}} =
  find_by_role("engineer")
```

---

### find_by_department(department_name, opts \\ [])

Query people in given department.

**Parameters:**
- `department_name` (string): Department to search for
- `opts` (keyword list): Options
  - `:cache` (boolean): Use cached results? Default: true

**Returns:**
- `{:ok, people, metadata}` - List of matching people
- `{:error, reason}` - Query failed

**Example:**
```elixir
{:ok, eng_team, _} = find_by_department("engineering")
```

---

### get_chain_of_command(person_id, opts \\ [])

Get chain from person up through role, team, department.

**Parameters:**
- `person_id` (string): Person ID to start from
- `opts` (keyword list): Options
  - `:max_depth` (integer): Max traversal depth. Default: 10

**Returns:**
- `{:ok, chain_map, metadata}` - Chain with person, role, team, department
- `{:error, reason}` - Query failed

**Example:**
```elixir
{:ok, %{"person" => p, "role" => r, "team" => t, "department" => d}, _} =
  get_chain_of_command("alice-id", max_depth: 5)
```

---

### build_complete_hierarchy(opts \\ [])

Build complete org hierarchy (expensive operation).

**Parameters:**
- `opts` (keyword list): Options
  - `:max_depth` (integer): Max traversal depth. Default: 10

**Returns:**
- `{:ok, hierarchy_map, metadata}` - Full hierarchy structure
- `{:error, reason}` - Query failed

**Example:**
```elixir
{:ok, hierarchy, %{departments_count: 8}} =
  build_complete_hierarchy()
```

---

### query_with_depth_limit(query_fn, opts \\ [])

Execute any query function with timeout and depth limit.

**Parameters:**
- `query_fn` (function): 0-arity function returning query result
- `opts` (keyword list): Options
  - `:max_depth` (integer): Max traversal depth. Default: 10
  - `:timeout_ms` (integer): Query timeout in ms. Default: 20000

**Returns:**
- `{:ok, result}` - Query succeeded
- `{:error, :query_timeout}` - Query exceeded timeout
- `{:error, reason}` - Query failed

**Example:**
```elixir
query_fn = fn ->
  Service.search("chatman-org", "engineer", type: "class")
end

case query_with_depth_limit(query_fn, timeout_ms: 5000) do
  {:ok, results} -> handle(results)
  {:error, :query_timeout} -> escalate()
end
```

---

## Related Modules

- `Canopy.Ontology.Service` - Caching layer
- `Canopy.IssueDispatcher` - Task dispatch integration
- `Canopy.Heartbeat` - Agent execution receives org context

---

**Last Updated:** 2026-03-26
**Phase:** 5.6 (Organization Structure Awareness)
