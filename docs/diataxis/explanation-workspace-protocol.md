# Understanding the Canopy Workspace Protocol

> **Learning goal:** Grok Canopy's agent coordination model in 15 minutes.
> **Level:** Conceptual (no implementation details)
> **Time:** ~15 min read

---

## What Is a Workspace?

A **workspace** is a shared stage where agents coordinate their work.

Think of it like a physical workspace:
- Multiple people (agents) work together
- They share tools, documents, and a communication protocol
- They signal each other when work is ready
- They observe what others are doing

In Canopy, this shared stage has three layers:

| Layer | What | Who Sees | Lifetime |
|-------|------|----------|----------|
| **L0** | Project identity, team structure, mission | Always loaded | Session start → session end |
| **L1** | Individual agent capabilities, their tasks | On demand | When agent is active |
| **L2** | Deep context, historical records, reference docs | On demand | Full project history |

---

## The Mental Model: Agents ↔ Workspace ↔ Protocol

```
┌─────────────────────────────────────────────────────────────┐
│                      WORKSPACE                               │
│                  (shared coordination stage)                 │
│                                                               │
│  company.yaml (L0)          heartbeat (signal)              │
│  └─ org structure           └─ agents wake up               │
│  └─ mission                 └─ check tasks                  │
│  └─ budget                  └─ execute work                 │
│  └─ governance              └─ signal completion            │
│                                                               │
│  agents/ (L1)               protocol                        │
│  └─ agent definitions       └─ JSON-RPC messages           │
│  └─ capabilities            └─ MCP (tool integration)      │
│  └─ schedules               └─ A2A (agent-to-agent)        │
│                                                               │
│  reference/ (L2)            feedback loop                    │
│  └─ decision docs           └─ verify execution             │
│  └─ runbooks                └─ adjust course                │
│  └─ example workflows       └─ audit trail                  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
         ↑                             ↑
       agents                      heartbeat
       work here                  wakes them
```

**Key insight:** Agents don't talk to each other directly. They communicate through the workspace via **heartbeat cycles** and **messages**.

---

## Step 1: Draw Your Mental Model

Before reading code, draw this on paper:

```
Start: Agent wakes up
  ↓
Read: What tasks are assigned to me?  (check workspace)
  ↓
Do: Execute the task
  ↓
Signal: Task done, here's the result  (update workspace)
  ↓
Wait: Sleep until next heartbeat
  ↓
(repeat)
```

This is the entire coordination loop. Everything else is detail.

---

## Step 2: The Workspace Entry Point — `company.yaml`

Every workspace starts with an organizational envelope:

```yaml
name: Dev Shop
slug: dev-shop
mission: Ship reliable software on time.

budget:
  monthly_usd: 8000
  per_agent_usd: 1200
  enforcement: warning  # warn at 80%, hard stop at 100%

governance:
  board_approval_required:
    - new_agent_hire
    - budget_increase_pct: 20
  escalation_chain:
    - tech-lead
    - board
```

**What this tells an agent:**
- "I'm part of Dev Shop"
- "Our mission is to ship reliable software"
- "I have $1200 budget per month"
- "If budget hits 80%, someone gets a warning"
- "New agents need tech-lead + board approval"

This is **L0 — always loaded**. No agent wakes up without knowing the mission and rules.

---

## Step 3: Agent Definitions — Workspace Structure

When agents are "hired," they're defined in the workspace:

```
canopy/operations/dev-shop/
├── company.yaml              ← org envelope
├── agents/
│   ├── architect.md          ← agent definition
│   ├── backend-dev.md
│   ├── frontend-dev.md
│   ├── qa-engineer.md
│   └── tech-lead.md
├── skills/
│   ├── build/SKILL.md        ← reusable task definition
│   ├── test/SKILL.md
│   ├── deploy/SKILL.md
│   └── review/SKILL.md
├── reference/
│   ├── patterns.md           ← decision docs
│   ├── standards.md
│   └── ci-cd.md
└── workflows/
    ├── feature-cycle.md      ← orchestration template
    └── bug-fix.md
```

**What this structure means:**
- **agents/** = "Who works here?" (identity + capabilities)
- **skills/** = "What can they do?" (reusable task templates)
- **reference/** = "What do they know?" (shared knowledge base)
- **workflows/** = "How do they work together?" (orchestration)

---

## Step 4: The Heartbeat — How Agents Wake Up

Agents don't run continuously. They sleep and wake on a **schedule**:

```
Time: 10:00 AM
  ↓
Heartbeat fires: "It's 10:00 AM"
  ↓
All agents wake up
  ↓
Each agent checks: "Do I have work?"
  ↓
Agents with work execute, others sleep
  ↓
Heartbeat completes
  ↓
All agents sleep until next heartbeat
```

**Example schedule** (cron format):

```
architect       0 8 * * *         (8am daily — plan the day)
backend-dev     */30 8-18 * * *   (every 30min, 8am-6pm — active hours)
qa-engineer     0 17 * * *        (5pm daily — run test suite)
tech-lead       0 18 * * *        (6pm daily — review PRs)
```

This is **passive execution** — no agent "sleeps busy-waiting." They only consume resources when the heartbeat wakes them.

---

## Step 5: Task Routing — Agent Receives Signal

When the heartbeat wakes an agent, it says:

```json
{
  "heartbeat_id": "2026-03-25T10:00:00Z",
  "agent_id": "architect",
  "tasks": [
    {
      "id": "task-1",
      "type": "design",
      "title": "Design auth system architecture",
      "context": { ... },
      "deadline": "2026-03-25T17:00:00Z",
      "delegable": true
    }
  ]
}
```

The agent reads this signal and decides:
- "I'll execute task-1" → calls its own implementation
- "This is too urgent, delegate to tech-lead" → sends A2A message
- "I lack expertise, reject task" → signals back with error

---

## Step 6: Communication Protocol — JSON-RPC + MCP

Canopy uses two protocols:

### JSON-RPC (Agent-to-Agent)
Agents call each other via HTTP + JSON-RPC:

```json
POST /api/agents/backend-dev/message
{
  "jsonrpc": "2.0",
  "method": "message/send",
  "params": {
    "from": "architect",
    "task": "implement_auth_service",
    "context": { ... }
  },
  "id": 1
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "status": "accepted",
    "delegate_to": "backend-dev",
    "eid": "task-1"
  },
  "id": 1
}
```

### MCP (Tool Integration)
Agents use **Model Context Protocol** to access tools (code editor, shell, APIs):

```
Agent → [MCP Client] → Tool Server (stdio/HTTP)
  ↑                        ↑
  reads responses          exposes capabilities
```

Example: Agent needs to run tests.
```
Agent: "I need to run tests"
  ↓
MCP Server: "I can do that. Call shell/run_command"
  ↓
Agent: shell/run_command("mix test")
  ↓
MCP Server: returns test results
```

**Key difference:**
- **JSON-RPC** = agent-to-agent (horizontal)
- **MCP** = agent-to-tools (vertical)

---

## Step 7: Progressive Disclosure — Context Efficiency

Agents don't load all context upfront. They load in tiers:

```
MEMORY BUDGET: 128K tokens (max per agent per session)

Tier 0 (always loaded): company.yaml + agent definition
  └─ ~2K tokens
  └─ "What's our mission? What am I hired for?"

Tier 1 (on demand): skills/ + recent decisions
  └─ ~2K tokens per task
  └─ "What are the steps? What have we decided?"

Tier 2 (deep dive): full reference docs + history
  └─ Unlimited
  └─ "Show me all prior decisions, full specs"
```

This means:
- **Quick coordination** — L0/L1 queries are instant
- **Deep work** — L2 available when needed
- **Bounded memory** — agents don't hallucinate context they haven't loaded

---

## Step 8: The Feedback Loop — Verification

After an agent completes work, the workspace verifies:

```
Agent: "Task complete, here's the result"
  ↓
Workspace checks:
  - Did you emit an OTEL span? (execution proof)
  - Are tests passing? (behavior proof)
  - Does output match the schema? (validity check)
  ↓
If all pass: accept result, record evidence
If any fail:  signal error, agent retries or delegates
```

This is **evidence-based coordination** — claims require proof before acceptance.

---

## The 7-Layer Map (Optional Deep Dive)

For reference, here's how Canopy's workspace maps to the 7-layer architecture:

| Layer | What | Canopy Implements |
|-------|------|-------------------|
| **L1: Network** | Who connects | `company.yaml` org structure + agent roster |
| **L2: Signal** | Encoded intent | Heartbeat messages + A2A protocol |
| **L3: Composition** | Internal structure | Agent behavior + task decomposition |
| **L4: Interface** | Info surfaces | Progressive disclosure (L0/L1/L2) |
| **L5: Data** | Storage substrate | agents/, skills/, reference/, workflows/ |
| **L6: Feedback** | Self-correction | Evidence gates + heartbeat cycle |
| **L7: Governance** | Purpose | company.yaml policies + escalation chains |

---

## Summary: The Workspace Protocol in 30 Seconds

1. **Workspace** = shared coordination stage (company.yaml + agents)
2. **Heartbeat** = schedule that wakes agents on demand
3. **Tasks** = work items routed to agents
4. **JSON-RPC** = agent-to-agent communication
5. **MCP** = agent-to-tool integration
6. **Progressive disclosure** = efficient context loading (L0/L1/L2)
7. **Feedback** = evidence gates that verify results

---

## Next Steps

- **Shallow:** Read `canopy/operations/dev-shop/SYSTEM.md` (15 min) — see an example workspace
- **Medium:** Study `canopy/architecture/heartbeat.md` (30 min) — understand the wakeup cycle
- **Deep:** Read `canopy/backend/lib/canopy/agents/` (2 hours) — see implementation

