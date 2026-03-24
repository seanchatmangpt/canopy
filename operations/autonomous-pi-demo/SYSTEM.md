# Autonomous Process Improvement Demo

## Purpose

This workspace demonstrates the full **Autonomous Process Improvement (PI)** pipeline using OCPM discovery, agent fleet coordination, BFT consensus, and Signal Theory quality gates.

## Demo Scenarios

This workspace showcases three real-world process improvement scenarios:

1. **Invoice Processing** — Target: 80% reduction in manual review time
2. **Customer Onboarding** — Target: 90% reduction in touch time
3. **Compliance Reporting** — Target: 100% automation (eliminate manual work)

## Workflow

The autonomous PI pipeline follows this 5-stage workflow:

```
1. Discovery (OCPM)
   ├─ Alpha miner discovers process model from event logs
   ├─ Heuristic miner detects bottlenecks
   └─ Conformance checking finds deviations

2. Planning (Agent Fleet)
   ├─ PI Optimization Agent designs improvements
   ├─ Impact analysis quantifies benefits
   └─ BFT consensus proposal generated

3. Execution (BFT Consensus)
   ├─ Agent fleet votes on proposal (HotStuff-BFT)
   ├─ Supermajority (>66.7%) required for approval
   └─ Approved changes proceed to implementation

4. Validation (Signal Theory)
   ├─ Measure S/N ratio of improved process
   ├─ Verify quality gates passed
   └─ Generate improvement report

5. Iteration (Continuous Improvement)
   ├─ Evaluate results vs. targets
   ├─ Decide next iteration (continue or stabilize)
   └─ Update process model version
```

## Getting Started

1. **Review demo data**: Check `reference/event-log-samples/` for synthetic event logs
2. **Run discovery**: Execute skill `ocpm/discover_process` on any scenario
3. **Design improvements**: Execute skill `ocpm/optimize_process` to create proposals
4. **Vote on consensus**: Coordinate agent fleet voting via `consensus/vote`
5. **Validate results**: Check Signal Theory quality gates via `signal/verify`

## Agents

- **OCPM Discovery Agent** (`library/agents/operations/ocpm-discovery.md`)
  - Discovers process models from event logs
  - Detects bottlenecks and deviations
  - Encodes findings in Signal Theory format

- **PI Optimization Agent** (`library/agents/operations/pi-optimization.md`)
  - Designs process improvements
  - Quantifies impact (time, cost, errors)
  - Generates BFT consensus proposals

- **Consensus Coordinator Agent** (`agents/consensus-coordinator.md`)
  - Facilitates HotStuff-BFT voting
  - Tallies votes and checks supermajority
  - Commits or rejects proposals

## Skills

- **`ocpm/discover_process`** (`skills/ocpm/discover_process.md`)
  - Run OCPM discovery on event logs
  - Generate process model, bottlenecks, deviations

- **`ocpm/optimize_process`** (`skills/ocpm/optimize_process.md`)
  - Design improvements based on discovery findings
  - Create impact analysis and proposals

- **`consensus/propose`** (`skills/consensus/propose.md`)
  - Generate BFT consensus proposals
  - Specify voting criteria and thresholds

- **`consensus/vote`** (`skills/consensus/vote.md`)
  - Execute HotStuff-BFT voting protocol
  - Commit or reject based on supermajority

## Workflows

- **`autonomous-pi-full-cycle`** (`workflows/autonomous-pi-full-cycle.md`)
  - End-to-end autonomous PI pipeline
  - All 5 stages: discovery → iteration

## Reference Materials

- **Event Log Samples** (`reference/event-log-samples/`)
  - Synthetic event logs for demo scenarios
  - CSV format with OCPM standard fields

- **Process Model Examples** (`reference/process-models/`)
  - Example discovered process models
  - Before/after comparisons

- **Signal Theory Guide** (`reference/signal-theory.md`)
  - S=(M,G,T,F,W) encoding reference
  - Quality gate specifications

## Success Metrics

Each demo scenario has specific success targets:

### Invoice Processing
- **Baseline**: 45min p95 manual review time
- **Target**: <10min p95 (78% reduction)
- **Quality Gate**: S/N ratio >10dB, 0 lost invoices

### Customer Onboarding
- **Baseline**: 5 business days touch time
- **Target**: <0.5 business days (90% reduction)
- **Quality Gate**: S/N ratio >15dB, 100% data completeness

### Compliance Reporting
- **Baseline**: 8 hours manual preparation
- **Target**: 0 hours (100% automation)
- **Quality Gate**: S/N ratio >20dB, 0 compliance violations

## Configuration

See `company.yaml` for:
- Budget (compute time for discovery/consensus)
- Agent fleet composition (voters for consensus)
- Mission (demo objectives and success criteria)
