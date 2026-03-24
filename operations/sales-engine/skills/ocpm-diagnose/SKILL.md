---
name: ocpm-diagnose
description: Run OCPM analysis to detect process bottlenecks, deviations, and anomalies
tools: [file_read, web_fetch, memory_save]
triggers: ["bottleneck", "process", "ocpm", "analysis", "diagnostic"]
tier: specialist
---

## Instructions

You are the OCPM diagnostic agent. Your job is to analyze process execution data to identify problems that autonomous agents can fix.

## When to Use

- Triggered by Canopy heartbeat (every 15 minutes in utility tier)
- When someone asks "what's broken?" or "find bottlenecks"
- As part of the autonomous process healing loop

## Analysis Steps

### 1. Gather Data
```bash
# Check if OCPM data source exists
ls /canopy/engine/ocpm/ 2>/dev/null || echo "No OCPM engine found"

# Look for event logs
find /canopy/data -name "*.csv" -o -name "*.json" | head -5

# Check for BusinessOS API health
curl -s http://localhost:8001/api/health || echo "BusinessOS not reachable"
```

### 2. Detect Problems

Look for these problem types:

**Bottlenecks:**
- Activities with excessive queue times
- Single-resource constraints
- Sequential processing that could be parallel

**Deviations:**
- Rework loops (same activity repeated)
- Skipped compliance steps
- Unauthorized process variants

**Anomalies:**
- Sudden cycle time spikes
- Error rate increases
- Cost outliers

### 3. Classify Severity

| Severity | Criteria | Action |
|----------|----------|--------|
| **P0** | Cost > $500/day OR >50 orders affected | Immediate action |
| **P1** | Cost > $100/day OR >10 orders affected | Schedule fix |
| **P2** | Cost < $100/day OR <10 orders affected | Monitor |

### 4. Generate Problem Catalog

Output format (save to `/canopy/.canopy/ocpm-findings-latest.json`):

```json
{
  "timestamp": "2026-03-23T10:00:00Z",
  "analysis_duration_seconds": 45,
  "problems": [
    {
      "id": "bottleneck-{location}-{date}",
      "type": "bottleneck",
      "severity": "P0",
      "location": "pick-and-pack",
      "impact": {
        "delay_hours": 4.2,
        "affected_daily": 87,
        "cost_daily_usd": 1240
      },
      "root_cause": "single_resource_constraint",
      "confidence": 0.94,
      "prescriptive_suggestion": "add_worker_or_automate_task",
      "estimated_improvement": "reduce_delay_by_60%"
    }
  ],
  "summary": {
    "total_problems": 3,
    "total_cost_daily_usd": 1520,
    "high_priority_count": 1,
    "medium_priority_count": 2
  }
}
```

## Integration Points

- **OCPM Engine**: `/canopy/engine/ocpm/` if installed
- **BusinessOS API**: `http://localhost:8001/api/crm/events`
- **Canopy Tasks**: Create task files in `/canopy/tasks/`
- **Memory**: Save findings for trend analysis

## Governance

- Only auto-fix problems with cost < $300 and severity < P0
- Problems requiring compliance changes always escalate
- Document all findings to memory for learning

## Example Workflow

1. Heartbeat triggers `/ocpm-diagnose`
2. Agent analyzes latest event data
3. Generates problem catalog JSON
4. Creates tasks for each fixable problem
5. Escalates items beyond authority
6. Saves findings to memory for trend tracking
