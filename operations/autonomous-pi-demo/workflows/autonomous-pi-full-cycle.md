# Workflow: Autonomous PI Full Cycle

End-to-end autonomous process improvement pipeline from discovery through iteration.

## Overview

This workflow orchestrates the complete 5-stage autonomous PI pipeline: OCPM discovery → improvement planning → BFT consensus → validation → iteration.

## Stages

### Stage 1: Discovery
**Objective**: Extract process insights from event logs

**Agent**: OCPM Discovery Agent (`ocpm-discovery`)

**Skills**:
- `ocpm/discover_process`

**Activities**:
1. Collect event logs from heartbeat or workflow execution
2. Run alpha miner to discover process model
3. Run heuristic miner to detect bottlenecks
4. Run conformance checking to find deviations
5. Generate discovery report with Signal Theory encoding

**Outputs**:
- Process model (nodes, edges, version)
- Bottleneck list (frequency, duration, queue)
- Deviation list (missing, extra, order violations)
- Signal-encoded findings

**Quality Gates**:
- Confidence interval ≥95%
- Sample size ≥100 cases
- Data quality <5% missing values

**Timeout**: 3600 seconds (1 hour)

---

### Stage 2: Planning
**Objective**: Design improvements and generate consensus proposal

**Agent**: PI Optimization Agent (`pi-optimization`)

**Skills**:
- `ocpm/optimize_process`
- `consensus/propose`

**Activities**:
1. Analyze discovery findings
2. Prioritize improvement opportunities (impact × feasibility)
3. Design improvements (automation, parallelization, elimination, streamlining)
4. Quantify impact (time savings, error reduction, cost savings)
5. Generate BFT consensus proposal

**Outputs**:
- Improvement designs (before/after comparison)
- Impact analysis (with 95% CI)
- BFT consensus proposal
- Rollback plan

**Quality Gates**:
- Each improvement cites specific OCPM finding
- Impact meets minimum threshold (10% improvement)
- Rollback plan is clear and executable

**Timeout**: 7200 seconds (2 hours)

---

### Stage 3: Execution
**Objective**: Achieve agent fleet consensus via BFT voting

**Agent**: Consensus Coordinator Agent (`consensus-coordinator`)

**Skills**:
- `consensus/vote`
- `consensus/commit`

**Activities**:
1. Broadcast proposal to agent fleet
2. Collect votes from all agents
3. Tally votes and check supermajority (>66.7%)
4. Verify fault tolerance (f < n/3)
5. Commit or reject proposal
6. Update audit trail

**Outputs**:
- Vote tally (approve/reject breakdown)
- Commit receipt or rejection feedback
- Audit trail entry with hash

**Quality Gates**:
- 100% agent participation
- Supermajority achieved (>66.7% approve)
- Fault tolerance within bounds (faulty ≤ ⌊(n-1)/3⌋)
- Audit trail hash verified

**Timeout**: 14400 seconds (4 hours)

---

### Stage 4: Validation
**Objective**: Verify improvement results with Signal Theory quality gates

**Agent**: OCPM Discovery Agent (`ocpm-discovery`) + PI Optimization Agent (`pi-optimization`)

**Skills**:
- `ocpm/discover_process`
- `signal/verify`

**Activities**:
1. Collect new event logs after implementation
2. Run OCPM discovery on improved process
3. Compare before/after metrics
4. Calculate Signal-to-Noise (S/N) ratio
5. Verify quality gates passed
6. Generate validation report

**Outputs**:
- New process model (version incremented)
- Before/after comparison
- S/N ratio measurement
- Validation report (pass/fail)

**Quality Gates**:
- S/N ratio ≥10dB (invoice processing)
- S/N ratio ≥15dB (customer onboarding)
- S/N ratio ≥20dB (compliance reporting)
- Zero data loss
- Audit trail complete

**Timeout**: 3600 seconds (1 hour)

---

### Stage 5: Iteration
**Objective**: Decide next iteration or stabilize

**Agent**: PI Optimization Agent (`pi-optimization`)

**Skills**:
- `ocpm/optimize_process`

**Activities**:
1. Evaluate validation results vs. targets
2. Assess remaining improvement opportunities
3. Decide: continue improvement or stabilize process
4. If continue: Return to Stage 2 with new findings
5. If stabilize: Archive process model and findings

**Outputs**:
- Iteration decision (continue/stabilize)
- Remaining opportunities (if any)
- Final process model version (if stabilized)
- Archive summary

**Quality Gates**:
- All targets met OR
- Maximum iterations (3) reached OR
- No further improvements >10% impact

**Timeout**: 1800 seconds (30 minutes)

---

## Workflow Configuration

```yaml
workflow_id: autonomous_pi
namespace: default
execution_timeout: 86400  # 24 hours max

stages:
  discovery:
    timeout: 3600
    retry_policy:
      max_attempts: 3
      initial_interval: 1s
      max_interval: 60s

  planning:
    timeout: 7200
    retry_policy:
      max_attempts: 3
      initial_interval: 1s
      max_interval: 60s

  execution:
    timeout: 14400
    retry_policy:
      max_attempts: 3
      initial_interval: 1s
      max_interval: 60s

  validation:
    timeout: 3600
    retry_policy:
      max_attempts: 3
      initial_interval: 1s
      max_interval: 60s

  iteration:
    timeout: 1800
    retry_policy:
      max_attempts: 3
      initial_interval: 1s
      max_interval: 60s

signals:
  - pause: Pause workflow for manual intervention
  - skip_stage: Skip to next stage
  - abort: Abort workflow execution
```

## Success Criteria

### Invoice Processing
- Baseline: 45min p95 → Target: <10min p95 (78% reduction)
- Quality Gate: S/N ratio ≥10dB, 0 lost invoices

### Customer Onboarding
- Baseline: 5 days → Target: <0.5 days (90% reduction)
- Quality Gate: S/N ratio ≥15dB, 100% data completeness

### Compliance Reporting
- Baseline: 8 hours → Target: 0 hours (100% automation)
- Quality Gate: S/N ratio ≥20dB, 0 compliance violations

## Usage

Execute this workflow via Canopy scheduler or Temporal adapter:

```
canopy workflows start autonomous-pi-full-cycle \
  --scenario invoice_processing \
  --event-log reference/event-log-samples/invoice_processing_events.csv
```

Or via Temporal:

```
OSA.Workflows.TemporalAdapter.start_workflow("autonomous_pi", %{
  "scenario" => "invoice_processing",
  "event_log_source" => "reference/event-log-samples/invoice_processing_events.csv"
})
```

## Monitoring

Track workflow progress via:
- Canopy dashboard (workflow status view)
- Temporal UI (workflow history)
- Signal Theory quality gates (validation results)

## Error Handling

Each stage has retry policy with exponential backoff:
- Max 3 attempts per stage
- Initial interval: 1 second
- Max interval: 60 seconds
- Backoff coefficient: 2.0

If stage fails after retries:
- Workflow pauses with error details
- Manual intervention via `pause` signal
- Resume or abort via signal

## Integration

- **Temporal**: Use `OSA.Workflows.TemporalAdapter` for durable execution
- **Signal Theory**: Use `OptimalSystemAgent.Signal.Classifier` for quality gating
- **OCPM**: Use `Canopy.OCPM.Discovery` for process mining
- **Consensus**: Use `OptimalSystemAgent.Consensus.HotStuff` for BFT voting
