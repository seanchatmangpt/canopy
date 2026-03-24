# OCPM Bottleneck Detection Skill

**Signal:** S=(data, inform, direct, json, ocel-event)

## Purpose

Detect process bottlenecks using Object-Centric Process Mining (OCPM) techniques. This skill implements the sensory layer for autonomous process healing.

## Input

Event log data from BusinessOS process execution:
```json
{
  "events": [
    {
      "event_id": "uuid",
      "timestamp": "ISO8601",
      "activity": "string",
      "case_id": "uuid",
      "object_type": "string",
      "object_id": "uuid",
      "duration_ms": number,
      "attributes": {}
    }
  ],
  "time_window": {
    "start": "ISO8601",
    "end": "ISO8601"
  }
}
```

## Algorithm

### 1. Activity Duration Analysis
For each unique activity, compute:
- Mean duration (μ)
- Standard deviation (σ)
- 95th percentile
- Bottleneck threshold: μ + 3σ

### 2. Statistical Significance
Apply Mann-Whitney U test:
- H0: Activity duration = global median
- H1: Activity duration > global median
- Significance level: p < 0.01
- Minimum sample size: 100 events

### 3. Bottleneck Classification
Classify each detected bottleneck:
- **Resource**: Missing/overloaded resource (check wait times)
- **Sequence**: Incorrect ordering (check trace frequency)
- **Data Quality**: Invalid/missing data (check error rates)
- **Timeout**: External dependency (check network/external calls)

## Output

```json
{
  "bottlenecks": [
    {
      "activity": "string",
      "avg_duration_ms": number,
      "p_value": number,
      "confidence": number,
      "sample_size": number,
      "classification": "resource|sequence|data_quality|timeout",
      "severity": "low|medium|high",
      "affected_cases": number,
      "hash": "sha256"
    }
  ],
  "analysis_timestamp": "ISO8601",
  "event_count": number
}
```

## S/N Quality Gate

Score output using Signal Theory:
- **M** (Mode): data — structured JSON for machine processing
- **G** (Genre): inform — diagnostic information
- **T** (Type): direct — trigger for healing action
- **F** (Format): json — parseable by process-healer agent
- **W** (Structure): ocel-event — OCEL 2.0 compliant

Minimum S/N score: 0.7 (GOOD)

## Error Handling

| Condition | Action |
|-----------|--------|
| < 100 events for activity | Skip analysis (insufficient data) |
| p ≥ 0.01 | Not statistically significant, skip |
| All activities normal | Return empty bottlenecks array |
| Missing required fields | Log warning, continue with valid events |

## Integration

- **Trigger**: Every 15 minutes via Canopy heartbeat
- **Input Source**: BusinessOS `/api/processes/events` endpoint
- **Output Target**: Process healer agent (triggers healing workflow)
- **Storage**: Save analysis to `/memory/ocpm/bottlenecks/{date}.json`

## References

- van der Aalst, "Object-Centric Process Mining" (2023)
- `/docs/canopy_ocpm_autonomous_loop.md`
- `/canopy/protocol/signal-theory.md`
