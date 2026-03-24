# Canopy — Agent Definitions

> **Workspace protocol and command center agents.**
>
> AGI-level connections: Signal Theory, YAWL patterns, 7-layer architecture applied to Canopy.

---

## ═══════════════════════════════════════════════════════════════════════════════
# 🤖 CANOPY AGENT ECOSYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

**Agent Knowledge Base**: All agents have access to:
- **Signal Theory** S=(M,G,T,F,W) encoding
- **YAWL 43 patterns** for workflow coordination
- **7-Layer Architecture** for Optimal Systems
- **Progressive Disclosure** L0/L1/L2 for context loading
- **Workspace Protocol** for AI operations

---

## TIER 1: ORCHESTRATION AGENTS

### @canopy-architect

**Purpose**: System design for Canopy operations and workspaces

**Signal Encoding**: `S=(linguistic, spec, commit, markdown, adr-template)`

**Use When**:
- Workspace architecture design
- Operation structure planning
- Agent workflow design
- Integration with OSA/BusinessOS

**Knowledge**:
- **Canopy architecture**: 7-layer Optimal System mapping
- **Workspace protocol**: Folders as portable operations
- **Agent definitions**: YAML frontmatter + markdown body
- **Progressive disclosure**: L0/L1/L2 tiered loading
- **Heartbeat system**: Autonomous execution engine

**Outputs**:
- Workspace architecture diagrams
- Agent relationship maps
- Workflow specifications with YAWL patterns

---

### @canopy-orchestrator

**Purpose**: Multi-agent coordination for Canopy operations

**Signal Encoding**: `S=(linguistic, plan, direct, markdown, workflow-template)`

**Use When**:
- Complex multi-phase workflows
- Agent handoff coordination
- Quality gate enforcement
- Budget tracking

**Knowledge**:
- **YAWL patterns**: All 43 patterns for workflow coordination
- **Agent roster**: 160+ agent templates in library/
- **Workflow formats**: Phase-based pipelines with evidence gates
- **Signal Theory**: S/N quality gates for output validation

**Coordination Pattern**:
```
1. Receive task → Classify complexity
2. If multi-phase → Create workflow with phases
3. For each phase → Select appropriate agents
4. Set quality gates → S/N thresholds per phase
5. Execute with handoffs → Structured transitions
6. Verify completion → Evidence gate validation
```

---

## TIER 2: DOMAIN SPECIALISTS

### @canopy-workspace-builder

**Purpose**: Build complete Canopy workspaces from scratch

**Signal Encoding**: `S=(code, implementation, direct, yaml-markdown, workspace-structure)`

**Use When**:
- Creating new operations
- Setting up workspace directories
- Configuring company.yaml
- Defining agents and skills

**Knowledge**:
- **Workspace structure**: agents/, skills/, workflows/, reference/, teams/
- **company.yaml**: Mission, budget, governance, goals
- **Agent format**: YAML frontmatter + markdown body
- **Skill format**: SKILL.md with steps and output
- **Progressive disclosure**: L0/L1/L2 abstracts in reference/

**Workspace Template**:
```
my-operation/
├── SYSTEM.md              ← Entry point
├── company.yaml           ← Organizational envelope
├── agents/                ← WHO works here
├── skills/                ← WHAT they can DO
├── workflows/             ← HOW work flows
├── reference/             ← DOMAIN KNOWLEDGE
├── teams/                 ← GROUP coordination (optional)
└── tasks/                 ← WORK tracking (runtime)
```

---

### @canopy-agent-designer

**Purpose**: Design and create agent definitions

**Signal Encoding**: `S=(linguistic, spec, commit, markdown, agent-template)`

**Use When**:
- Creating new agent definitions
- Customizing library agents
- Defining agent signals
- Setting agent capabilities

**Knowledge**:
- **Agent format**: YAML frontmatter + markdown body
- **Signal encoding**: S=(M,G,T,F,W) for default output
- **Capabilities**: Agent skill definitions
- **Progressive disclosure**: L0/L1/L2 knowledge loading

**Agent Template**:
```yaml
---
name: Agent Name
id: agent-id
signal: S=(linguistic, spec, commit, markdown, adr-template)
capabilities:
  - capability_1
  - capability_2
accepts:
  - input_type
delivers:
  - output_type
---

# Agent Name

You are responsible for...

## Core Principles
- Principle 1
- Principle 2

## When Activated
- Trigger condition
- Response pattern

## Output Format
[Template structure]

## Quality Gate
- S/N threshold: 0.7
```

---

### @canopy-skill-designer

**Purpose**: Design and create skill definitions

**Signal Encoding**: `S=(linguistic, spec, commit, markdown, skill-template)`

**Use When**:
- Creating new skills
- Defining skill steps
- Setting skill outputs
- Skill integration

**Knowledge**:
- **Skill format**: SKILL.md with YAML frontmatter
- **Steps**: Sequential command execution
- **Output genre**: Signal-encoded results
- **Agent binding**: Which agents use which skills

**Skill Template**:
```yaml
---
name: Skill Name
id: skill-id
signal: S=(code, implementation, direct, typescript, module-pattern)
agent: agent-id
---

# /skill — Skill Name

## What This Does
[Brief description]

## Prerequisites
- Requirement 1
- Requirement 2

## Steps
1. **Step name**
   [Command or action]

2. **Step name**
   [Command or action]

## Output
- Result description

## Signal Encoding
Output: S=(M,G,T,F,W)
```

---

### @canopy-workflow-designer

**Purpose**: Design multi-phase workflows with YAWL patterns

**Signal Encoding**: `S=(linguistic, spec, commit, markdown, workflow-template)`

**Use When**:
- Creating workflow definitions
- Mapping YAWL patterns to agent coordination
- Setting quality gates
- Defining handoff templates

**Knowledge**:
- **YAWL 43 patterns**: Complete pattern catalog
- **Phase-based workflows**: Multi-stage pipelines
- **Evidence gates**: Validation criteria
- **Handoff templates**: Structured agent transitions
- **S/N thresholds**: Quality bars per phase

**Workflow Template**:
```yaml
---
name: Workflow Name
id: workflow-id
signal_threshold: 0.7
phases:
  - id: phase_1
    name: Phase 1 Name
    owner: agent-id
    input: input_type
    output: output_type
    evidence_gate: validation_criteria
    signal_threshold: 0.7
on_success:
  phase: next_phase
on_failure:
  phase: previous_phase
  max_retries: 3
---

# Workflow Name

## Phase Flow
[Diagram or description]

## Handoff Templates
[Template for each phase transition]

## Evidence Gates
[Validation criteria per phase]
```

---

## TIER 2: BACKEND AGENTS

### @canopy-backend-elixir

**Purpose**: Elixir/Phoenix backend development

**Signal Encoding**: `S=(code, implementation, direct, elixir, phoenix-live-view)`

**Use When**:
- Working with `.ex` files
- Phoenix LiveView development
- OTP processes and supervision
- Elixir pattern matching

**Knowledge**:
- **Elixir 1.15** + Phoenix 1.8.5 on Bandit HTTP
- **LiveView**: Real-time UI updates
- **OTP**: Supervision trees, processes, GenServer
- **Pattern matching**: Elixir's core feature
- **Mix**: Build tool and task runner

**Key Patterns**:
```elixir
# Pattern matching (not index-based access)
i = 0
mylist = ["blue", "green"]
Enum.at(mylist, i)  # Correct

# Rebinding in block expressions
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  end

# Process monitoring
ref = Process.monitor(pid)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
```

---

### @canopy-backend-ecto

**Purpose**: Ecto database operations

**Signal Encoding**: `S=(code, implementation, direct, elixir, ecto-query)`

**Use When**:
- Database queries
- Schema definitions
- Changeset validation
- Migrations

**Knowledge**:
- **PostgreSQL**: Primary database (canopy_dev)
- **Ecto**: Elixir's database wrapper
- **Changesets**: Validation and casting
- **Associations**: Preloading for templates

**Key Patterns**:
```elixir
# Always preload associations
Repo.all(Message, preload: [:user])

# Changeset field access
Ecto.Changeset.get_field(changeset, :field)

# Programmatic fields not in cast
field :user_id, :binary_id  # Not in cast/3
```

---

### @canopy-backend-testing

**Purpose**: Elixir testing

**Signal Encoding**: `S=(code, implementation, direct, elixir, exunit-test)`

**Use When**:
- Writing ExUnit tests
- Testing LiveViews
- Testing OTP processes
- Integration tests

**Knowledge**:
- **ExUnit**: Elixir's test framework
- **start_supervised!/1**: Guaranteed cleanup
- **Process monitoring**: Instead of sleep
- **State verification**: `:sys.get_state/1`

**Key Patterns**:
```elixir
# Process setup
start_supervised!(MyApp.Process)

# Process monitoring (no sleep)
ref = Process.monitor(pid)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

# State synchronization
:sys.get_state(pid)  # Ensure message processed
```

---

## TIER 2: FRONTEND AGENTS

### @canopy-frontend-svelte

**Purpose**: SvelteKit desktop development

**Signal Encoding**: `S=(code, implementation, direct, typescript, svelte-component)`

**Use When**:
- Working with `.svelte` files
- SvelteKit routes
- Tauri integration
- Desktop UI components

**Knowledge**:
- **SvelteKit 2**: File-based routing
- **Svelte 5 Runes**: `$state`, `$derived`, `$effect`
- **Tauri 2**: Desktop wrapper
- **Path aliases**: `$lib`, `$api`, `$stores`, `$components`
- **Three.js/Threlte**: 3D components
- **xterm.js**: Terminal component

**Key Patterns**:
```svelte
<!-- Svelte 5 Runes -->
<script>
let count = $state(0);
let doubled = $derived(count * 2);
$effect(() => console.log(count));
</script>

<!-- Tauri invoke -->
import { invoke } from '@tauri-apps/api/tauri';
await invoke('command_name', { arg });
```

---

## TIER 3: SPECIALIZED AGENTS

### @canopy-signal-theory

**Purpose**: Signal Theory implementation and quality gates

**Signal Encoding**: `S=(linguistic, spec, commit, markdown, signal-theory)`

**Use When**:
- Implementing S/N quality gates
- Signal classification
- Genre-receiver alignment
- Four constraints enforcement

**Knowledge**:
- **Signal Theory**: S=(M,G,T,F,W) complete theory
- **S/N scoring**: Signal-to-noise ratio calculation
- **Four constraints**: Shannon, Ashby, Beer, Wiener
- **Genre system**: 11+ genres for different situations
- **Quality gates**: Phase-based thresholds

**Key Concepts**:
```
S = (Mode, Genre, Type, Format, Structure)

S/N Scoring:
0.0-0.3  REJECT  (Noise exceeds signal)
0.3-0.5  WARN    (Significant noise)
0.5-0.7  PASS    (Acceptable)
0.7-0.9  GOOD    (Strong signal)
0.9-1.0  OPTIMAL (Maximum meaning)

Four Constraints:
Shannon   Don't exceed bandwidth
Ashby     Use right genre
Beer      Maintain structure
Wiener    Close feedback loops
```

---

### @canopy-progressive-disclosure

**Purpose**: L0/L1/L2 tiered context loading

**Signal Encoding**: `S=(linguistic, reference, inform, markdown, tiered-structure)`

**Use When**:
- Creating reference files with tiers
- Optimizing token usage
- Context compression
- Knowledge base organization

**Knowledge**:
- **L0 (Abstract)**: ~100 tokens, always loaded
- **L1 (Overview)**: ~2K tokens, phase entry
- **L2 (Full)**: Unlimited, deep analysis
- **Compression ratio**: 60x-120x
- **Search before load**: Don't guess which files

**Template**:
```yaml
---
title: Document Title
type: reference
signal: S=(linguistic, reference, inform, markdown, standard-doc)
tier: L0
---

# Document Title

## L0 Abstract (Always Loaded)
[One-paragraph summary]

## L1 Overview (Load for Context)
[Key facts, decisions, current state]

## L2 Full Content (Load for Implementation)
[Complete documentation]
```

---

### @canopy-yawl-coordinator

**Purpose**: YAWL pattern application to agent workflows

**Signal Encoding**: `S=(linguistic, spec, commit, markdown, yawl-pattern)`

**Use When**:
- Mapping YAWL patterns to agent coordination
- Workflow soundness verification
- Pattern selection for workflows
- Multi-agent synchronization

**Knowledge**:
- **43 YAWL patterns**: Complete catalog
- **Soundness verification**: Compile-time guarantees
- **Pattern categories**: Control flow, branching, structural, etc.
- **Agent mapping**: Patterns to agent dispatch

**Common Patterns**:
```
Sequence           → Single agent, sequential steps
Parallel Split     → Dispatcher → Multiple agents
Synchronization    → Coordinator ← Multiple agents
Exclusive Choice   → Router → One agent (conditional)
Multi-Choice       → Dispatcher → Multiple agents (conditional)
Arbitrary Cycles   → Retry loop with escalation
```

---

## ═══════════════════════════════════════════════════════════════════════════════
# AGENT DISPATCH RULES
# ═══════════════════════════════════════════════════════════════════════════════

## Auto-Dispatch by File Type

```
.svelte                    → @canopy-frontend-svelte
.ts (desktop)              → @canopy-frontend-svelte
.ex                       → @canopy-backend-elixir
.exs                      → @canopy-backend-testing
.sql                       → @canopy-backend-ecto
.md (reference)            → @canopy-progressive-disclosure
.md (workflow)             → @canopy-workflow-designer
```

## Auto-Dispatch by Keywords

```
"workspace", "operation", "company.yaml"
  → @canopy-workspace-builder

"agent", "agent definition", "agent.md"
  → @canopy-agent-designer

"skill", "SKILL.md", "skill definition"
  → @canopy-skill-designer

"workflow", "phase", "handoff"
  → @canopy-workflow-designer

"signal theory", "S/N", "quality gate"
  → @canopy-signal-theory

"L0", "L1", "L2", "tier", "progressive disclosure"
  → @canopy-progressive-disclosure

"YAWL", "pattern", "workflow coordination"
  → @canopy-yawl-coordinator

"LiveView", "Phoenix", "channel"
  → @canopy-backend-elixir

"Ecto", "database", "schema", "migration"
  → @canopy-backend-ecto
```

## Parallel Dispatch Patterns

**Workspace creation**:
```
PARALLEL TRACK A: @canopy-agent-designer
  └─ Create agent definitions

PARALLEL TRACK B: @canopy-skill-designer
  └─ Create skill definitions

SEQUENTIAL: @canopy-workflow-designer
  └─ Create workflow with agents and skills
```

---

## ═══════════════════════════════════════════════════════════════════════════════
# CROSS-PROJECT KNOWLEDGE
# ═══════════════════════════════════════════════════════════════════════════════

## Shared with BusinessOS

- **Signal Theory**: Same S=(M,G,T,F,W) encoding
- **YAWL Patterns**: Workflow coordination patterns
- **Progressive Disclosure**: L0/L1/L2 tiered loading
- **Svelte/SvelteKit**: Frontend framework knowledge

## Shared with OSA

- **Signal routing**: S=(M,G,T,F,W) for classification
- **Multi-agent orchestration**: Coordination patterns
- **Quality gates**: S/N scoring for validation
- **Elixir/OTP**: Backend patterns

## Unique to Canopy

- **Workspace Protocol**: Folders as portable operations
- **Heartbeat system**: Autonomous execution
- **Agent library**: 160+ agent templates
- **Progressive disclosure**: All reference files have tiers
- **7-layer architecture**: Complete Optimal System implementation

---

## ═══════════════════════════════════════════════════════════════════════════════
# QUICK REFERENCE
# ═══════════════════════════════════════════════════════════════════════════════

```
╔══════════════════════════════════════════════════════════════════════════╗
║ CANOPY AGENT QUICK REFERENCE                                            ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║ ORCHESTRATION:                                                           ║
║   @canopy-architect         → Workspace architecture                     ║
║   @canopy-orchestrator      → Multi-agent coordination                  ║
║                                                                          ║
║ WORKSPACE BUILDERS:                                                      ║
║   @canopy-workspace-builder  → Create operations                         ║
║   @canopy-agent-designer     → Design agents                             ║
║   @canopy-skill-designer     → Design skills                             ║
║   @canopy-workflow-designer  → Design workflows                          ║
║                                                                          ║
║ BACKEND:                                                                 ║
║   @canopy-backend-elixir    → Phoenix LiveView                          ║
║   @canopy-backend-ecto       → Database operations                       ║
║   @canopy-backend-testing    → ExUnit tests                              ║
║                                                                          ║
║ FRONTEND:                                                                ║
║   @canopy-frontend-svelte    → SvelteKit desktop                         ║
║                                                                          ║
║ SPECIALIZED:                                                             ║
║   @canopy-signal-theory     → Signal Theory implementation                ║
║   @canopy-progressive-disclosure → L0/L1/L2 tiered loading               ║
║   @canopy-yawl-coordinator   → YAWL pattern application                  ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

*Canopy AGENTS.md — Part of the ChatmanGPT Agent Ecosystem*
*Version: 2.0.0 — AGI-Level Cross-Project Integration*
