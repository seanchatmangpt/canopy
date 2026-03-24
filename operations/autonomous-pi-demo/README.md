# Autonomous Process Improvement Demo

**Version**: 1.0.0
**Status**: Ready for execution
**Last Updated**: 2026-03-23

## Quick Start

```bash
# From /Users/sac/chatmangpt/canopy directory

# 1. Start Canopy backend
make backend

# 2. In another terminal, run demo discovery
cd operations/autonomous-pi-demo

# 3. Execute OCPM discovery on invoice processing
canopy skills execute ocpm/discover_process \
  --event-log reference/event-log-samples/invoice_processing_events.csv \
  --output-format markdown

# 4. Design improvements based on findings
canopy skills execute ocpm/optimize_process \
  --discovery-result <previous-output>

# 5. Run consensus vote on proposal
canopy skills execute consensus/vote \
  --proposal-id <proposal-id>
```

## Overview

This workspace demonstrates **Autonomous Process Improvement (PI)** using:

- **OCPM**: Object-Centric Process Mining for discovery
- **Agent Fleet**: Multi-agent coordination for planning
- **BFT Consensus**: HotStuff-BFT for trustworthy decisions
- **Signal Theory**: S=(M,G,T,F,W) quality gates

## Demo Scenarios

### 1. Invoice Processing Optimization
- **Target**: 78% reduction in manual review time (45min → <10min p95)
- **Approach**: Automate low-value approvals, exception-based review
- **Quality Gate**: S/N ratio ≥10dB, 0 lost invoices

### 2. Customer Onboarding Acceleration
- **Target**: 90% reduction in touch time (5 days → <0.5 days)
- **Approach**: Template-based configuration, automated provisioning
- **Quality Gate**: S/N ratio ≥15dB, 100% data completeness

### 3. Compliance Reporting Automation
- **Target**: 100% automation (8 hours → 0 hours)
- **Approach**: Automated data pipelines, scheduled validation
- **Quality Gate**: S/N ratio ≥20dB, 0 compliance violations

## Workflow

The autonomous PI pipeline follows 5 stages:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Discovery (OCPM)                                              │
│    ├─ Alpha miner: Discover process model                       │
│    ├─ Heuristic miner: Detect bottlenecks                       │
│    └─ Conformance checking: Find deviations                     │
├─────────────────────────────────────────────────────────────────┤
│ 2. Planning (Agent Fleet)                                        │
│    ├─ Design improvements (automation, parallelization, etc.)    │
│    ├─ Quantify impact (time, cost, errors)                      │
│    └─ Generate BFT consensus proposal                           │
├─────────────────────────────────────────────────────────────────┤
│ 3. Execution (BFT Consensus)                                     │
│    ├─ Broadcast proposal to agent fleet                         │
│    ├─ Collect votes (APPROVE/REJECT)                            │
│    └─ Commit if supermajority (>66.7%) or reject                │
├─────────────────────────────────────────────────────────────────┤
│ 4. Validation (Signal Theory)                                    │
│    ├─ Collect new event logs                                    │
│    ├─ Calculate S/N ratio                                       │
│    └─ Verify quality gates                                      │
├─────────────────────────────────────────────────────────────────┤
│ 5. Iteration (Continuous Improvement)                           │
│    ├─ Evaluate results vs. targets                              │
│    ├─ Decide: continue or stabilize                             │
│    └─ Update process model version                              │
└─────────────────────────────────────────────────────────────────┘
```

## Agents

| Agent | ID | Role | Expertise |
|-------|-----|------|-----------|
| OCPM Discovery Agent | `ocpm-discovery` | Discovery Specialist | Alpha miner, heuristic miner, conformance checking |
| PI Optimization Agent | `pi-optimization` | Improvement Designer | Process design, impact analysis, proposal generation |
| Consensus Coordinator Agent | `consensus-coordinator` | Consensus Facilitator | HotStuff-BFT, vote tallying, audit trail |

## Skills

| Skill | Purpose | Input | Output |
|-------|---------|-------|--------|
| `ocpm/discover_process` | Run OCPM discovery | Event log | Process model + bottlenecks + deviations |
| `ocpm/optimize_process` | Design improvements | Discovery results | Improvement designs + impact analysis |
| `consensus/propose` | Generate proposal | Improvement design | BFT consensus proposal |
| `consensus/vote` | Execute voting | Proposal ID | Vote tally + commit/reject |

## Configuration

See `company.yaml` for:
- Budget (compute time, consensus rounds)
- Agent fleet composition (voters, weights)
- Scenario targets (baseline, improvement, quality gates)
- Consensus config (HotStuff-BFT, supermajority, audit log)

## Reference Materials

- **Event Log Samples** (`reference/event-log-samples/`): Synthetic event logs for demo scenarios
- **Process Models** (`reference/process-models/`): Example discovered models
- **Signal Theory** (`reference/signal-theory.md`): S=(M,G,T,F,W) encoding reference

## Success Metrics

Each scenario has specific targets:

| Scenario | Baseline | Target | Quality Gate |
|----------|----------|--------|--------------|
| Invoice Processing | 45min p95 | <10min p95 (78% reduction) | S/N ≥10dB, 0 loss |
| Customer Onboarding | 5 days | <0.5 days (90% reduction) | S/N ≥15dB, 100% complete |
| Compliance Reporting | 8 hours | 0 hours (100% automation) | S/N ≥20dB, 0 violations |

## Integration

This demo workspace integrates with:

- **Canopy OCPM**: `Canopy.OCPM.Discovery` for process mining
- **OSA Consensus**: `OptimalSystemAgent.Consensus.HotStuff` for BFT
- **OSA Workflows**: `OSA.Workflows.Definitions.AutonomousPI` for execution
- **Signal Classifier**: `OptimalSystemAgent.Signal.Classifier` for routing

## Troubleshooting

### OCPM Discovery Issues

**Problem**: "Insufficient data quality"
- **Solution**: Ensure event log has minimum 100 cases, <5% missing values

**Problem**: "No process model discovered"
- **Solution**: Check event log format (case_id, activity, timestamp required)

### Consensus Issues

**Problem**: "Supermajority not reached"
- **Solution**: Revise proposal based on reject feedback, resubmit

**Problem**: "Agent fleet too small"
- **Solution**: Minimum 3 agents required for BFT properties

### Validation Issues

**Problem**: "S/N ratio below threshold"
- **Solution**: Process may not be stable, collect more event data

**Problem**: "Data loss detected"
- **Solution**: Check implementation for data handling issues

## Next Steps

1. **Run Discovery**: Execute `ocpm/discover_process` on any scenario
2. **Design Improvements**: Execute `ocpm/optimize_process` on discovery results
3. **Vote on Proposal**: Execute `consensus/vote` to get fleet approval
4. **Implement & Validate**: Deploy improvement and measure S/N ratio
5. **Iterate**: Continue until targets met or stabilize

## Support

For issues or questions:
- Check `SYSTEM.md` for detailed workflow information
- Review agent definitions in `agents/` directory
- Consult skill documentation in `library/skills/` (from Canopy root)
- Reference Signal Theory guide in `reference/signal-theory.md`
