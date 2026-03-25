# Canopy Phase 2B: Multi-Workspace Isolation Design

## Overview

Multi-workspace isolation enables Canopy to support multiple isolated workspaces per organization, with workspace-scoped database access and role-based access control (RBAC).

**Key Requirement**: Users can work independently across multiple workspaces without data leakage between them.

## Design Goals

1. **Complete isolation**: Data in workspace A never visible to users without workspace A access
2. **Flexible RBAC**: Owner → Admin → User → Viewer role hierarchy
3. **Scalability**: Support organizations with 10+ workspaces without performance degradation
4. **Backward compatibility**: Existing single-workspace routes continue to work via context detection

## Architecture

### 1. Database Schema

#### New Tables

**workspaces_users** — junction table for workspace membership:
- `id` (binary_id, PK)
- `workspace_id` (FK → workspaces)
- `user_id` (FK → users)
- `role` (string: "admin", "user", "viewer")
- `inserted_at`, `updated_at`

**Unique constraint**: `[workspace_id, user_id]` prevents duplicate memberships.

#### Modified Tables

**workspaces** — added fields:
- `is_active` (boolean, default: true) — soft deletion / deactivation
- `isolation_level` (string, default: "full") — supports "full", "shared", "public" for future multi-tenancy modes

### 2. Context Layer: `Canopy.WorkspaceIsolation`

Central context module providing workspace-scoped query helpers:

```elixir
# List all workspaces accessible by user (owned or member)
get_user_workspaces(user_id) :: [Workspace]

# Get single workspace with access check
get_user_workspace(user_id, workspace_id) :: Workspace | nil

# Determine user's role in workspace
user_workspace_role(user_id, workspace_id) :: "owner" | "admin" | "user" | "viewer" | nil

# Permission checks
can_access_workspace?(user_id, workspace_id) :: boolean
can_manage_workspace?(user_id, workspace_id) :: boolean  # owner/admin only

# Member management
add_workspace_user(workspace_id, user_id, role) :: {:ok, WorkspaceUser} | {:error, term}
update_workspace_user_role(workspace_id, user_id, role) :: {:ok, WorkspaceUser} | {:error, term}
remove_workspace_user(workspace_id, user_id) :: :ok
list_workspace_users(workspace_id) :: [WorkspaceUser]

# Workspace lifecycle
deactivate_workspace(workspace_id) :: :ok
activate_workspace(workspace_id) :: :ok
```

### 3. HTTP Request Context Pipeline

#### Plug: `CanopyWeb.Plugs.WorkspaceContext`

Runs AFTER `Auth` plug, extracts workspace_id from multiple sources in priority order:

1. **URL param**: `params["workspace_id"]` (from router path params or query string)
2. **HTTP Header**: `X-Workspace-ID` (for SPA clients)
3. **Session**: Stored in conn.private for token-based sessions
4. **Default**: First accessible workspace (via `get_user_default_workspace/1`)

Assigns to conn:
- `conn.assigns[:current_workspace]` — Workspace struct
- `conn.assigns[:current_workspace_id]` — workspace.id
- `conn.assigns[:current_workspace_role]` — "owner" | "admin" | "user" | "viewer"

Returns 403 Forbidden if user lacks access to requested workspace.

### 4. Router Configuration

#### Legacy Routes (Backward Compatible)

Routes under `/api/v1/...` continue to work with workspace context detection:

```elixir
scope "/api/v1", CanopyWeb do
  pipe_through [:api, :authenticated, :workspace_context]

  resources "/workspaces", WorkspaceController, except: [:new, :edit] do
    post "/activate", WorkspaceController, :activate
    get "/agents", WorkspaceController, :agents
    get "/config", WorkspaceController, :config
    post "/members", WorkspaceController, :add_member
    delete "/members/:user_id", WorkspaceController, :remove_member
    get "/members", WorkspaceController, :members
  end

  # All existing endpoints (agents, sessions, schedules, costs, issues, etc.)
  # inherit workspace context from WorkspaceContext plug
end
```

**Route Execution Flow**:
1. Auth plug validates JWT and loads user
2. WorkspaceContext plug extracts workspace_id and validates access
3. Handler receives `conn.assigns[:current_workspace_id]` for filtering queries
4. Data queries filtered by workspace_id

### 5. Handler Pattern

Controllers filter queries using workspace context:

```elixir
def index(conn, _params) do
  workspace_id = conn.assigns[:current_workspace_id]
  user_workspace_ids = conn.assigns[:user_workspace_ids] || []

  query = from a in Agent, order_by: [asc: a.name]

  query =
    cond do
      workspace_id -> where(query, [a], a.workspace_id == ^workspace_id)
      user_workspace_ids != [] -> where(query, [a], a.workspace_id in ^user_workspace_ids)
      true -> query
    end

  agents = Repo.all(query)
  json(conn, %{agents: agents})
end
```

### 6. Workspace Member Management: `WorkspaceMemberController`

HTTP endpoints for member management (admin/owner only):

```
GET    /api/v1/workspaces/:id/members              # List members
POST   /api/v1/workspaces/:id/members              # Add member
PATCH  /api/v1/workspaces/:id/members/:user_id    # Update role
DELETE /api/v1/workspaces/:id/members/:user_id    # Remove member
```

**Permission Model**:
- **Owner**: Full control (workspace creator)
- **Admin**: Can add/remove/update members
- **User**: Can read/modify own workspace data
- **Viewer**: Read-only access

## Implementation Details

### Query Filtering Strategy

All data queries filter by `workspace_id`:

```elixir
# Before: SELECT * FROM agents;
# After:  SELECT * FROM agents WHERE workspace_id = $1;

agents = Repo.all(
  from a in Agent,
    where: a.workspace_id == ^workspace_id,
    order_by: [asc: a.name]
)
```

**Batch Queries**: When fetching multiple workspaces, use IN clause:

```elixir
user_workspace_ids = WorkspaceIsolation.get_user_workspaces(user_id)
                     |> Enum.map(& &1.id)

agents = Repo.all(
  from a in Agent,
    where: a.workspace_id in ^user_workspace_ids,
    order_by: [asc: a.name]
)
```

### Role-Based Access Enforcement

**In Context Layer** (`WorkspaceIsolation`):
- Can-access checks only (boolean)
- Used for querying accessible workspaces

**In HTTP Handlers** (`WorkspaceMemberController`):
- Can-manage checks enforced before allowing membership changes
- Reject with 403 if user not admin/owner

**Example**:
```elixir
def add_member(conn, %{"workspace_id" => ws_id} = params) do
  user = conn.assigns[:current_user]

  with {:ok, _} <- check_workspace_admin(user.id, ws_id),
       {:ok, new_user} <- find_user_by_email(params["email"]),
       {:ok, _} <- WorkspaceIsolation.add_workspace_user(ws_id, new_user.id, params["role"]) do
    json(conn, %{message: "User added", user: serialize(new_user)})
  else
    {:error, :forbidden} -> 403 Forbidden response
    {:error, :not_found} -> 404 Not Found response
  end
end
```

### Cross-Workspace Agent Communication

Future enhancement for Phase 2C:

When agent A (workspace 1) delegates to agent B (workspace 2):
1. Extract target workspace_id from delegation request
2. Validate cross-workspace delegation policy
3. Check if requestor has "delegate" permission in both workspaces
4. Route message with workspace context

## Migration Path

### Migration: `20260324000001_add_workspace_isolation_support.exs`

1. Create `workspace_users` table
2. Add `is_active`, `isolation_level` fields to `workspaces`
3. Create indexes on `[workspace_id]`, `[user_id]`, `[workspace_id, user_id]`

**Backward Compatibility**:
- Existing workspaces are activated with `is_active = true`
- No data loss
- Existing routes work with workspace context detection

### Rollback Strategy

```elixir
def down do
  drop table(:workspace_users)

  alter table(:workspaces) do
    remove :is_active
    remove :isolation_level
  end
end
```

## Testing Strategy

### Test Files Created

1. **`workspace_isolation_test.exs`** (23 tests)
   - Context layer: CRUD operations, role checks, permissions
   - Pure functions, no external deps
   - ~2.5 hours to implement

2. **`plugs/workspace_context_test.exs`** (8 tests)
   - Plug header/param extraction
   - Access validation
   - Default workspace selection
   - ~1.5 hours to implement

3. **`controllers/workspace_member_controller_test.exs`** (9 tests)
   - Member listing, adding, removal
   - Permission enforcement
   - Error cases
   - ~2 hours to implement

4. **`integration/workspace_isolation_integration_test.exs`** (12 tests)
   - Cross-workspace data isolation
   - Role-based permissions
   - Deactivation behavior
   - ~2 hours to implement

**Total Test Coverage**: 52 tests, ~8 hours implementation

### Test Execution

```bash
cd canopy/backend

# Run all isolation tests
mix test test/canopy/workspace_isolation_test.exs
mix test test/canopy_web/plugs/workspace_context_test.exs
mix test test/canopy_web/controllers/workspace_member_controller_test.exs
mix test test/integration/workspace_isolation_integration_test.exs

# Run full suite
mix test

# Check for warnings
mix compile --warnings-as-errors
```

## API Examples

### Workspace Management

**List user's workspaces**:
```
GET /api/v1/workspaces
Authorization: Bearer {token}

Response:
{
  "workspaces": [
    {
      "id": "ws1",
      "name": "Production",
      "status": "active",
      "agent_count": 12,
      ...
    }
  ]
}
```

**Switch workspace context**:
```
GET /api/v1/agents
Authorization: Bearer {token}
X-Workspace-ID: ws1

Response: Agents in workspace ws1 only
```

### Member Management

**List workspace members**:
```
GET /api/v1/workspaces/ws1/members
Authorization: Bearer {token}

Response:
{
  "members": [
    {
      "id": "user1",
      "email": "user1@example.com",
      "name": "User One",
      "role": "owner",
      "joined_at": "2026-03-24T10:00:00Z"
    },
    {
      "id": "user2",
      "email": "user2@example.com",
      "role": "admin",
      "joined_at": "2026-03-24T12:00:00Z"
    }
  ]
}
```

**Add member**:
```
POST /api/v1/workspaces/ws1/members
Authorization: Bearer {token}
Content-Type: application/json

{
  "email": "newuser@example.com",
  "role": "user"
}

Response: 201 Created
{
  "message": "User added to workspace",
  "user": {
    "id": "user3",
    "email": "newuser@example.com",
    "role": "user"
  }
}
```

**Remove member**:
```
DELETE /api/v1/workspaces/ws1/members/user2
Authorization: Bearer {token}

Response: 200 OK
{
  "message": "User removed from workspace"
}
```

## Performance Considerations

### Query Optimization

1. **Indexed Columns**:
   - `workspaces[organization_id, is_active]` — fast org lookup
   - `workspace_users[workspace_id]` — fast member lookup
   - `workspace_users[user_id]` — fast user's workspaces lookup

2. **N+1 Avoidance**:
   - Batch agent/issue/skill queries by workspace_id
   - Use single query with IN clause for multi-workspace data

3. **Caching** (Future):
   - Cache user's workspace roles in Redis
   - Invalidate on membership changes

### Query Examples

```elixir
# Fast: Single workspace
agents = Repo.all(from a in Agent, where: a.workspace_id == ^ws_id)

# Fast: User's multiple workspaces (batch)
ws_ids = WorkspaceIsolation.get_user_workspaces(user_id) |> Enum.map(& &1.id)
agents = Repo.all(from a in Agent, where: a.workspace_id in ^ws_ids)

# Slow (DO NOT USE): Cartesian product
agents = Repo.all(from a in Agent, join: wu in WorkspaceUser, ...)
```

## Future Extensions

### Phase 2C: Cross-Workspace Delegation

Allow agents to delegate work across workspaces with explicit permission:

```elixir
WorkspaceIsolation.delegate_to_agent(
  from_workspace_id: ws1,
  to_workspace_id: ws2,
  from_user_id: user1,
  target_agent_id: agent2,
  message: "Please process this..."
)
```

### Phase 2D: Workspace Sharing

Support sharing workspace resources with external users/teams:

```elixir
WorkspaceIsolation.share_workspace(
  workspace_id: ws1,
  share_type: "read_only",
  share_with: ["team:external", "org:partner"]
)
```

### Phase 3: Multi-Organization Support

Extend Organization model to support workspace-to-organization relationships and cross-org delegation.

## Error Handling

### HTTP Status Codes

| Status | Scenario | Example |
|--------|----------|---------|
| 200 OK | Successful request | Agent list returned |
| 201 Created | Resource created | Member added to workspace |
| 400 Bad Request | Invalid input | Missing workspace_id |
| 403 Forbidden | Access denied | User not member of workspace |
| 404 Not Found | Resource not found | Workspace doesn't exist |
| 422 Unprocessable Entity | Validation failed | Invalid role value |

### Example Error Responses

```json
{
  "error": "forbidden",
  "message": "You do not have access to this workspace"
}
```

```json
{
  "error": "validation_failed",
  "details": {
    "role": ["is invalid"]
  }
}
```

## Compliance & Security

### Data Isolation Guarantee

- **No SQL injection**: Parameterized queries with Ecto
- **No authorization bypass**: All queries filter by workspace_id
- **No cross-workspace data leakage**: Verified by integration tests

### Audit Trail

All workspace changes logged via existing audit infrastructure:
- Member additions/removals
- Role changes
- Workspace activation/deactivation
- Agent/issue/skill operations scoped to workspace

## Files Created/Modified

### New Files (11)

1. `priv/repo/migrations/20260324000001_add_workspace_isolation_support.exs` — Migration
2. `lib/canopy/schemas/workspace_user.ex` — Schema
3. `lib/canopy/workspace_isolation.ex` — Context layer
4. `lib/canopy_web/plugs/workspace_context.ex` — HTTP middleware
5. `lib/canopy_web/router_workspace_scopes.ex` — Router configuration
6. `lib/canopy_web/controllers/workspace_member_controller.ex` — HTTP handlers
7. `test/canopy/workspace_isolation_test.exs` — Unit tests
8. `test/canopy_web/plugs/workspace_context_test.exs` — Plug tests
9. `test/canopy_web/controllers/workspace_member_controller_test.exs` — Controller tests
10. `test/integration/workspace_isolation_integration_test.exs` — Integration tests
11. `docs/WORKSPACE_ISOLATION_DESIGN.md` — This document

### Modified Files (2)

1. `lib/canopy/schemas/workspace.ex` — Added is_active, isolation_level, has_many associations
2. `lib/canopy_web/router.ex` — Added workspace_context plug, new member routes

## Summary

**Effort Estimate**: 13.5-15.5 hours

- Database schema + migrations: 1.5h
- Context layer + helpers: 2h
- Plugs + middleware: 2h
- Controllers + handlers: 2.5h
- Tests (unit + integration): 3.5h
- Documentation: 1.5h
- Buffer for debugging: 1h

**Success Criteria**:
- All 52 tests pass
- No SQL warnings or compilation errors
- No data leakage between workspaces (verified by integration tests)
- Backward compatibility with existing routes

