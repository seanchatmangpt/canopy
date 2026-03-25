# Canopy — Claude Code Configuration

> Workspace orchestration protocol and command center for AI agent systems.
> Elixir 1.15 + Phoenix 1.8.5 backend, SvelteKit 2 + Tauri 2 desktop.

## Build Commands

```bash
make setup          # deps.get + ecto.setup + npm install
make dev            # Start backend (:9089) + desktop (:5200)
make test           # mix test + npm run test
make check          # svelte-check + mix compile --warnings-as-errors
make backend        # Phoenix server only
make desktop        # SvelteKit dev server only
make build          # Production Tauri bundle
make doctor         # Check prerequisites and ports
```

## Test Commands

```bash
cd backend && mix test                              # All backend tests
cd backend && mix test test/path/to_test.exs        # Single file
cd desktop && npm run test                          # Frontend tests
cd desktop && npx vitest run src/path/to/file.test.ts  # Single file
```

Pre-commit runs: `compile --warnings-as-errors` + `deps.unlock --unused` + `format` + `test`.

## Ports

| Service | Port |
|---------|------|
| Phoenix backend | 9089 |
| SvelteKit desktop | 5200 |
| OSA integration | 8089 |
| BusinessOS integration | 8001 |

## Code Standards

### Elixir
- `mix format` enforced. No compilation warnings.
- OTP patterns: proper supervision trees, GenServer for stateful processes.
- ETS for in-memory caches (see `:canopy_idempotency_cache`).
- Jason encoding: use plain maps `%{"key" => val}` for JSON, not keyword lists.
- Auth: Guardian JWT + Bcrypt.

### SvelteKit / Tauri
- Svelte 5 Runes: `$state`, `$derived`, `$effect`. No `createEventDispatcher`.
- Callback props, not event dispatchers.
- TypeScript strict mode. No `any` type.

## Architecture

### Supervision Tree (application.ex)

```
Canopy.Supervisor (one_for_one)
  +-- CanopyWeb.Telemetry
  +-- Canopy.Repo
  +-- Canopy.BudgetEnforcer
  +-- Phoenix.PubSub
  +-- Canopy.IssueDispatcher
  +-- Canopy.Scheduler (Quantum cron)
  +-- Canopy.AdapterSupervisor (DynamicSupervisor)
  +-- Canopy.HeartbeatRunner (Task.Supervisor)
  +-- Canopy.TaskSupervisor
  +-- Canopy.AlertEvaluator
  +-- Canopy.StaleCleanup
  +-- Canopy.IdempotencyCleanup
  +-- CanopyWeb.Endpoint (Bandit HTTP)
```

### Adapter Behavior (`Canopy.Adapter`)

All runtime adapters implement this behavior. Key callbacks:

```elixir
@callback type() :: String.t()
@callback name() :: String.t()
@callback start(config :: map()) :: {:ok, session :: map()} | {:error, term()}
@callback stop(session :: map()) :: :ok | {:error, term()}
@callback execute_heartbeat(params :: map()) :: Enumerable.t()
@callback send_message(session :: map(), message :: String.t()) :: Enumerable.t()
@callback supports_session?() :: boolean()
@callback supports_concurrent?() :: boolean()
@callback capabilities() :: [atom()]
```

Implementations: `adapters/osa.ex`, `adapters/business_os.ex`, `adapters/claude_code.ex`,
`adapters/codex.ex`, `adapters/cursor.ex`, `adapters/gemini.ex`, `adapters/mcp.ex`,
`adapters/mcp_server.ex`, `adapters/bash.ex`, `adapters/http.ex`, `adapters/openclaw.ex`.

### Key Systems

- **Agent System** — 160+ agents, hired from markdown manifests, coordinated via tasks
- **Heartbeat Protocol** — Agents wake on schedule, check tasks, execute, delegate, sleep
- **OCPM** — Organizational Capability Process Mining via OSA integration
- **A2A Service** — Agent-to-agent communication (`agents/a2a_service.ex`)
- **MCP Integration** — Model Context Protocol server/client (`adapters/mcp.ex`, `adapters/mcp_server.ex`)
- **Budget Enforcer** — Three-tier: visibility (always), soft alert (80%), hard stop (100%)
- **Progressive Disclosure** — L0/L1/L2 tiers for token-efficient context loading

### Workspace Protocol

```
L0  SYSTEM.md + company.yaml       (~2K tokens, always loaded)
L1  agents/ + skills/              (~2K tokens per item, on demand)
L2  reference/ + workflows/ + spec/ (full content, deep context)
L3  engine/                        (invisible, 0 tokens)
```

## Environment

Required in `backend/.env`:
```
DATABASE_URL=postgres://localhost/canopy_dev
SECRET_KEY_BASE=...
GUARDIAN_SECRET_KEY=...
```

Adapter credentials go in `.env.local` (never committed).

## Cross-System Integration: BusinessOS

### Adapter

**File:** `backend/lib/canopy/adapters/business_os.ex`

Implements `Canopy.Adapter` behavior. Stateless (no sessions), supports concurrency.

**Capabilities:** `[:process_mining, :model_analysis, :conformance_checking]`

**API Endpoints (called on BusinessOS at port 8001):**

| Operation | Method | Path | Purpose |
|-----------|--------|------|---------|
| Process discovery | POST | `/api/bos/discover` | Discover process models from event logs |
| Conformance check | POST | `/api/bos/conformance` | Check fitness/precision against a model |
| Compliance verify | POST | `/api/bos/compliance/verify` | Verify SOC2/HIPAA/GDPR compliance |
| Health check | GET | `/api/health` | Server availability |
| Discovery status | GET | `/api/bos/status` | Discovery engine status |

**Auth:** Bearer token via `BUSINESSOS_API_TOKEN` env var. Set in `backend/.env` or deployment secrets.

**Message types** (JSON via `send_message/2`):

```json
{"type": "process_mining", "payload": {"event_log": "..."}}
{"type": "conformance", "payload": {"model": "...", "event_log": "..."}}
{"type": "compliance", "payload": {"framework": "SOC2"}}
```

### Webhook: Discovery Completion

BusinessOS posts discovery results back to Canopy:

```
POST /api/v1/hooks/{webhook_id}
```

Handled by `CanopyWeb.WebhookController.receive/2`. Webhook module:
`backend/lib/canopy/webhooks/businessos_discovery_webhook.ex`.

### Seed Agents

Seed file: `backend/priv/repo/seeds/20260325_businessos_agents.exs`

Creates 2 agents in a "BusinessOS Integration" workspace:

| Agent | Slug | Schedule | Purpose |
|-------|------|----------|---------|
| Process Mining Monitor | `process-mining-monitor` | `*/10 * * * *` | Discovers process models, detects drift, generates summaries |
| BusinessOS Conformance Checker | `bos-conformance-checker` | `0 */6 * * *` | Runs conformance checks, verifies SOC2/HIPAA/GDPR compliance |

Run seed: `mix run priv/repo/seeds/20260325_businessos_agents.exs`

After seeding, restart the app or call `Canopy.Scheduler.load_schedules/0` to register cron jobs.

### Connected Systems

| System | Port | Integration |
|--------|------|-------------|
| BusinessOS | 8001 | Adapter + webhook (this section) |
| OSA | 8089 | Adapter (`adapters/osa.ex`) |
