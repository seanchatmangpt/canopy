# Skill: OCPM Discover Process

Discover process models, bottlenecks, and deviations from event logs using Object-Centric Process Mining.

## Overview

This skill runs the full OCPM discovery pipeline on event logs to extract process insights for autonomous process improvement.

## Prerequisites

- Event log in OCPM format (CSV or JSON)
- Required fields: case_id, activity, timestamp, resource
- Minimum 100 unique cases for reliable discovery

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| event_log_source | string | Yes | Path to event log file or workspace ID |
| output_format | string | No | Format for results: `json` (default) or `markdown` |
| include_bottlenecks | boolean | No | Run bottleneck detection (default: true) |
| include_deviations | boolean | No | Run conformance checking (default: true) |
| confidence_threshold | float | No | Minimum confidence for relations (default: 0.95) |

## Process

1. **Load Event Log**
   - Parse CSV/JSON event log
   - Validate required fields
   - Check data quality (missing values, chronological order)

2. **Run Alpha Miner**
   - Extract succession relations between activities
   - Build causal matrix
   - Discover process model (nodes + edges)

3. **Run Heuristic Miner** (if `include_bottlenecks=true`)
   - Analyze activity frequencies
   - Calculate duration distributions (p50, p95, p99)
   - Detect frequency, duration, and queue bottlenecks

4. **Run Conformance Checking** (if `include_deviations=true`)
   - Build transition set from discovered model
   - Check each case for deviations
   - Categorize deviations by severity

5. **Generate Report**
   - Synthesize all findings
   - Calculate impact metrics
   - Encode in Signal Theory format

## Output

### Signal Encoding
```
S=(discovery, process_model, alpha_miner, [json|markdown], nodes_edges)
S=(bottleneck, bottleneck_report, heuristic_miner, [json|markdown], bottleneck_list)
S=(deviation, conformance_report, conformance_check, [json|markdown], deviation_list)
```

### Return Format

```json
{
  "signal": {
    "mode": "discovery",
    "genre": "process_model",
    "type": "alpha_miner",
    "format": "json",
    "structure": "nodes_edges"
  },
  "process_model": {
    "nodes": ["activity1", "activity2", ...],
    "edges": {
      "activity1 -> activity2": {
        "frequency": 150,
        "confidence": 0.98
      }
    },
    "start_events": ["activity1"],
    "end_events": ["activityN"],
    "version": "1.0.0",
    "discovered_at": "2026-03-23T12:00:00Z"
  },
  "bottlenecks": [
    {
      "activity": "manual_approval",
      "type": "duration",
      "severity": "critical",
      "p95_duration_minutes": 45,
      "median_duration_minutes": 8,
      "impact": "appears in 80% of cases, 5.6x longer than median"
    }
  ],
  "deviations": [
    {
      "case_id": "case-123",
      "deviation_type": "missing_activity",
      "severity": "warning",
      "description": "Expected 'manager_approval' not found"
    }
  ],
  "metrics": {
    "total_cases": 1000,
    "unique_activities": 12,
    "confidence_interval": "95% CI: [0.94-0.99]",
    "sample_size": 1000
  }
}
```

## Quality Gates

- **Confidence**: All relations must have confidence ≥ 0.95
- **Sample Size**: Minimum 100 cases, ideally 500+
- **Data Quality**: <5% missing values, chronological timestamps

## Example Usage

```
Execute skill: ocpm/discover_process

Parameters:
{
  "event_log_source": "reference/event-log-samples/invoice_processing_events.csv",
  "output_format": "markdown",
  "include_bottlenecks": true,
  "include_deviations": true,
  "confidence_threshold": 0.95
}
```

## Integration

- **Input**: Event logs from Canopy heartbeat events, workflow execution logs, or manual uploads
- **Output**: Process model stored in `Canopy.OCPM.ProcessModel`, findings sent to PI Optimization Agent
- **Storage**: Discovered models persisted to database for version tracking
- **Routing**: Signal classifier routes outputs based on Mode/Genre/Type tags

## Next Steps

After discovery, use `ocpm/optimize_process` skill to design improvements based on findings.
