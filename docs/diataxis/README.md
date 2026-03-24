# Canopy — Diátaxis Documentation

> **Open-source workspace protocol + command center.**
>
> Diátaxis documentation for Canopy — tutorials, how-to guides, explanations, and reference.

---

## About Canopy

Canopy is the execution engine and workspace protocol for AI-powered operations. It runs operations autonomously on heartbeat schedules, using Signal Theory for quality and YAWL patterns for coordination.

**Tech Stack**: Elixir 1.15 + Phoenix 1.8.5 backend + SvelteKit 2/Tauri 2 desktop

**Role in MIOSA Stack**: Layer 3 — Operations layer between Mission and OSA

---

## Diátaxis Documentation

### [Tutorials](../../docs/diataxis/tutorials/) — Learn by Doing

| Tutorial | What You'll Learn | Time |
|----------|-------------------|------|
| [Your First AI Operation](../../docs/diataxis/tutorials/first-operation.md) | Build complete Canopy workspace with agents | 30 min |
| [Signal Theory in Practice](../../docs/diataxis/tutorials/signal-theory-practice.md) | Quality-gated agent outputs | 45 min |
| [Building with YAWL Patterns](../../docs/diataxis/tutorials/yawl-patterns.md) | Sound multi-agent workflows | 60 min |

### [How-to Guides](../../docs/diataxis/how-to/) — Solve Problems

| Guide | Solves | Complexity |
|-------|--------|------------|
| [Add S/N Quality Gates](../../docs/diataxis/how-to/add-quality-gates.md) | Reject low-quality agent output | Intermediate |
| [Create Progressive Disclosure](../../docs/diataxis/how-to/progressive-disclosure.md) | Tiered context loading (L0/L1/L2) | Intermediate |
| [Map YAWL to Agents](../../docs/diataxis/how-to/yawl-agent-mapping.md) | Compile workflows to agent dispatch | Advanced |
| [Create Agent Handoffs](../../docs/diataxis/how-to/agent-handoffs.md) | Structured agent transitions | Beginner |
| [Debug Signal Classification](../../docs/diataxis/how-to/debug-signal-classification.md) | Fix S=(M,G,T,F,W) errors | Intermediate |

### [Explanation](../../docs/diataxis/explanation/) — Understand the System

| Explanation | Topic | Why It Matters |
|-------------|-------|----------------|
| [The Chatman Equation](../../docs/diataxis/explanation/chatman-equation.md) | A=μ(O) mathematical foundation | Coordination soundness |
| [Signal Theory Complete](../../docs/diataxis/explanation/signal-theory-complete.md) | 5-tuple encoding + 4 constraints | Output quality |
| [The 7-Layer Architecture](../../docs/diataxis/explanation/seven-layer-architecture.md) | Optimal Systems design | Canopy implements all 7 layers |
| [YAWL Soundness Theorem](../../docs/diataxis/explanation/yawl-soundness.md) | Workflow correctness proof | No deadlocks |
| [Progressive Disclosure Theory](../../docs/diataxis/explanation/progressive-disclosure.md) | Tiered loading mathematics | Token efficiency |

### [Reference](../../docs/diataxis/reference/) — Look Up Details

| Reference | Covers | Format |
|-----------|--------|--------|
| [Signal Format](../../docs/diataxis/reference/signal-format.md) | S=(M,G,T,F,W) specification | BNF grammar |
| [YAML Frontmatter](../../docs/diataxis/reference/yaml-frontmatter.md) | Agent/Skill/Workflow schemas | JSON Schema |
| [43 YAWL Patterns](../../docs/diataxis/reference/yawl-43-patterns.md) | Complete pattern catalog | Tables + diagrams |
| [Genre Catalog](../../docs/diataxis/reference/genre-catalog.md) | All Signal Theory genres | Usage guide |

---

## Canopy-Specific Documentation

### Core Architecture

| Topic | Diátaxis Docs | Canopy Docs |
|-------|---------------|-------------|
| **Workspace Protocol** | [7-Layer Architecture](../../docs/diataxis/explanation/seven-layer-architecture.md) | [Workspace Protocol](../protocol/README.md) |
| **Signal Integration** | [Signal Theory Complete](../../docs/diataxis/explanation/signal-theory-complete.md) | [Signal Integration](../architecture/signal-integration.md) |
| **Heartbeat System** | [Explanation: Feedback Loops](../../docs/diataxis/explanation/seven-layer-architecture.md) | [Heartbeat](../architecture/heartbeat.md) |
| **Progressive Disclosure** | [Progressive Disclosure Theory](../../docs/diataxis/explanation/progressive-disclosure.md) | [Tiered Loading](../architecture/tiered-loading.md) |
| **Workflows** | [43 YAWL Patterns](../../docs/diataxis/reference/yawl-43-patterns.md) | [Workflow Design](../guides/workflow-design.md) |

### Agent Development

| Topic | Diátaxis Docs | Canopy Docs |
|-------|---------------|-------------|
| **Agent Design** | [Tutorial: First Operation](../../docs/diataxis/tutorials/first-operation.md) | [Agent Design Guide](../guides/agent-design.md) |
| **Signal Encoding** | [Signal Format Reference](../../docs/diataxis/reference/signal-format.md) | [Agent Frontmatter](../protocol/agent-format.md) |
| **Quality Gates** | [How-to: Add Quality Gates](../../docs/diataxis/how-to/add-quality-gates.md) | [S/N Scoring](../architecture/signal-integration.md) |
| **Handoffs** | [How-to: Agent Handoffs](../../docs/diataxis/how-to/agent-handoffs.md) | [Handoff Templates](../guides/workflow-design.md) |

### Operation Development

| Topic | Diátaxis Docs | Canopy Docs |
|-------|---------------|-------------|
| **Company Setup** | [Explanation: Governance](../../docs/diataxis/explanation/seven-layer-architecture.md) | [Company Setup Guide](../guides/company-setup.md) |
| **Teams** | [Reference: YAML Frontmatter](../../docs/diataxis/reference/yaml-frontmatter.md) | [Team Format](../protocol/team-format.md) |
| **Projects** | [How-to: YAWL Agent Mapping](../../docs/diataxis/how-to/yawl-agent-mapping.md) | [Project Format](../protocol/project-format.md) |
| **Tasks** | [Reference: YAML Frontmatter](../../docs/diataxis/reference/yaml-frontmatter.md) | [Task Format](../protocol/task-format.md) |

---

## AGI-Level Connections

### Signal Theory in Canopy

Canopy implements Signal Theory as the quality layer:

```
┌─────────────────────────────────────────────────────────────┐
│                  SIGNAL THEORY LAYER                        │
│              S=(M,G,T,F,W) — Universal Encoding             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Agent Outputs ──→ S/N Quality Gate ──→ Reject/Transmit      │
│                                                               │
│  Dimensions:                                                  │
│  M = Mode (linguistic, visual, code, data, mixed)            │
│  G = Genre (spec, brief, report, plan, ...)                  │
│  T = Type (direct, inform, commit, decide, express)          │
│  F = Format (markdown, code, JSON, YAML)                     │
│  W = Structure (adr-template, review-checklist, ...)          │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### YAWL Patterns in Canopy

Canopy workflows map to YAWL patterns:

| YAWL Pattern | Canopy Implementation |
|--------------|----------------------|
| **Sequence** | Phase transitions (spec → build → review) |
| **Parallel Split** | Parallel agent activation |
| **Synchronization** | Multi-agent handoff completion |
| **Exclusive Choice** | Signal-based routing |
| **Multi-Choice** | Conditional agent activation |
| **Arbitrary Cycles** | Retry loops with escalation |

### The 7-Layer Architecture

Canopy implements all 7 layers of the Optimal System architecture:

| Layer | What | Canopy Implementation |
|-------|------|----------------------|
| **L1: Network** | Who connects to whom | `company.yaml`, `reportsTo`, `TEAM.md` |
| **L2: Signal** | Encoded intent | `signal:` fields, deliverable templates |
| **L3: Composition** | Internal structure | Agent bodies, SKILL.md steps |
| **L4: Interface** | How info surfaces | Progressive disclosure (L0/L1/L2) |
| **L5: Data** | Where it's stored | `agents/`, `skills/`, `teams/`, `tasks/` |
| **L6: Feedback** | Self-correction | Heartbeat, evidence gates, S/N gates |
| **L7: Governance** | Organizational purpose | `SYSTEM.md`, governance rules |

---

## Quick Start Paths

### For New Users

1. **Build your first operation**: [Tutorial](../../docs/diataxis/tutorials/first-operation.md)
2. **Learn Signal Theory**: [Tutorial](../../docs/diataxis/tutorials/signal-theory-practice.md)
3. **Understand workflows**: [YAWL Patterns Tutorial](../../docs/diataxis/tutorials/yawl-patterns.md)

### For Operation Builders

1. **Design agents**: [Agent Design Guide](../guides/agent-design.md)
2. **Create workflows**: [Workflow Design Guide](../guides/workflow-design.md)
3. **Add quality gates**: [How-to Guide](../../docs/diataxis/how-to/add-quality-gates.md)

### For Researchers

1. **Foundation theory**: [Signal Theory Complete](../../docs/diataxis/explanation/signal-theory-complete.md)
2. **Mathematical basis**: [The Chatman Equation](../../docs/diataxis/explanation/chatman-equation.md)
3. **Architecture**: [7-Layer Architecture](../../docs/diataxis/explanation/seven-layer-architecture.md)

---

## Cross-Project Links

- **Root Diátaxis**: [Main Documentation](../../docs/diataxis/README.md)
- **BusinessOS**: [BusinessOS Diátaxis](../../BusinessOS/docs/diataxis/README.md)
- **OSA**: [OSA Diátaxis](../../OSA/docs/diataxis/README.md)
- **Getting Started**: [Canopy Getting Started](../getting-started.md)

---

*Canopy Diátaxis Documentation — Part of the ChatmanGPT Knowledge System*
