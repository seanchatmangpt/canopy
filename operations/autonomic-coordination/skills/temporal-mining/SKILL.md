# Temporal Process Mining Skill

**Signal:** S=(data, inform, direct, json, temporal-metrics)

## Purpose

Shift from descriptive process mining ("what happened?") to **predictive process intelligence** ("what will happen?"). Track process velocity, trajectory, and early warning signals.

## The Problem

Process mining answers "what happened?" (descriptive). Nobody answers:
- "What's changing?" (diagnostic)
- "What will happen?" (predictive)
- "What's stagnating?" (evolutionary pressure)

## The Solution

**Temporal process mining** — track the velocity and trajectory of process change over time.

## Process Velocity

How fast are processes evolving?

```json
{
  "process_id": "invoice-processing",
  "velocity_metrics": {
    "commits_per_week": 12,
    "pattern_changes_per_month": 3,
    "sop_updates_per_quarter": 2,
    "velocity_class": "high"  // stagnant, low, medium, high, volatile
  },
  "velocity_trend": "accelerating"  // decelerating, stable, accelerating
}
```

**Velocity Classes:**
- **Stagnant:** < 1 commit/month (process is rotting)
- **Low:** 1-4 commits/month (slow evolution)
- **Medium:** 4-8 commits/month (healthy evolution)
- **High:** 8-16 commits/month (rapid improvement)
- **Volatile:** > 16 commits/month (instability risk)

## Change Prediction

Given current trajectory, what will the process look like in 6 months?

```json
{
  "process_id": "deal-flow",
  "current_state": {
    "cycle_time_hours": 36,
    "bottlenecks": ["lead-qualification"],
    "efficiency_score": 0.65
  },
  "trajectory": {
    "trend": "improving",
    "rate": "+0.05 efficiency per month",
    "projection_6mo": {
      "cycle_time_hours": 24,
      "efficiency_score": 0.85,
      "confidence": 0.78
    }
  }
}
```

## Early Warning Detection

Detect process degradation **before** it impacts KPIs:

```json
{
  "early_warning": {
    "process_id": "customer-onboarding",
    "warning_type": "velocity_degradation",
    "severity": "medium",
    "signal": {
      "current_velocity": "high → medium",
      "time_to_impact": "3-4 weeks",
      "predicted_impact": "+15% cycle time",
      "recommended_action": "Review bottleneck: data-entry-step-3"
    }
  }
}
```

**Warning Types:**
1. **Velocity Degradation:** Process commits declining
2. **Bottleneck Emergence:** New bottleneck forming
3. **Pattern Drift:** Process deviating from YAWL specification
4. **Stagnation:** No improvements in 90+ days

## Evolutionary Pressure

Which processes are "stagnating" (low velocity = high risk)?

```json
{
  "stagnation_analysis": {
    "processes": [
      {
        "process_id": "expense-approval",
        "last_commit": "2025-12-15",
        "days_stagnant": 98,
        "stagnation_risk": "critical",
        "recommended_action": "Assign process owner, initiate improvement"
      },
      {
        "process_id": "hiring-onboarding",
        "last_commit": "2026-03-01",
        "days_stagnant": 23,
        "stagnation_risk": "medium",
        "recommended_action": "Monitor, schedule review if >60 days"
      }
    ]
  }
}
```

## Intervention Scheduling

Schedule process improvements when change velocity is low:

```json
{
  "intervention_schedule": {
    "week_of_2026_03_24": {
      "safe_to_modify": [
        {"process_id": "lead-qualification", "reason": "velocity=low, low risk"}
      ],
      "avoid_modifying": [
        {"process_id": "payment-processing", "reason": "velocity=high, high risk"}
      ]
    }
  }
}
```

**Rule:** Only modify processes when velocity is low or stable. Never modify when volatile.

## Time-Series Storage

Store process metrics over time for trend analysis:

```sql
CREATE TABLE process_metrics_history (
  process_id VARCHAR(256),
  timestamp TIMESTAMPTZ NOT NULL,
  cycle_time_p50 FLOAT,
  cycle_time_p95 FLOAT,
  bottleneck_count INTEGER,
  efficiency_score FLOAT,
  commits_this_week INTEGER,
  velocity_class VARCHAR(20),
  PRIMARY KEY (process_id, timestamp)
);

CREATE INDEX idx_process_time ON process_metrics_history(process_id, timestamp DESC);
```

## Input

```json
{
  "process_id": "string",
  "time_window": {
    "start": "ISO8601",
    "end": "ISO8601"
  },
  "analysis_type": "velocity|prediction|early_warning|stagnation|schedule"
}
```

## Output

```json
{
  "process_id": "string",
  "analysis_type": "string",
  "timestamp": "ISO8601",
  "results": {
    "velocity": {"class": "medium", "trend": "stable"},
    "prediction": {"6mo_efficiency": 0.85, "confidence": 0.78},
    "early_warnings": [],
    "stagnation_risk": "low",
    "safe_to_modify": true
  }
}
```

## S/N Quality Gate

Score ≥ 0.7 (GOOD) required:
- All metrics quantified (no qualitative assessments without data)
- Time series data sufficient (≥ 4 weeks of data)
- Confidence intervals provided for predictions
- Actionable recommendations (not just observations)

## 80/20 Justification

- **20% effort:** Extend existing OCPM analysis with time-series comparison
- **80% value:** Shifts from reactive fixing to proactive optimization
- **Blue Ocean:** Predictive process intelligence doesn't exist as a product

## Error Handling

| Condition | Action |
|-----------|--------|
| Insufficient historical data (< 4 weeks) | Return descriptive only, no prediction |
| High variance in metrics | Lower confidence interval, flag as unstable |
| Process not found | Return error, suggest valid process IDs |

## Storage

- **Metrics:** BusinessOS `/api/processes/metrics/history`
- **Predictions:** `/memory/temporal-mining/predictions/{process_id}/{date}.json`
- **Warnings:** BusinessOS `/api/processes/warnings` (trigger alerts)

## Integration

- **Trigger:** Weekly analysis (every Monday morning)
- **Input Source:** BusinessOS `/api/processes/events` (historical)
- **Output Target:** Process healer (early warnings), Self-evolving-org (stagnation)
- **Dashboard:** BusinessOS process health view (velocity, warnings, predictions)

## Metrics to Track

| Metric | Target | Measurement |
|--------|--------|-------------|
| Early warning accuracy | >80% | Warnings that materialize into issues |
| Prediction confidence | >0.7 | Average confidence of 6mo predictions |
| Stagnation detected | 5-10 per quarter | Processes needing attention |
| Safe intervention rate | >90% | Interventions that don't cause degradation |

## References

- `/docs/superpowers/specs/2026-03-23-vision-2030-blue-ocean-innovations-design.md` (Innovation 7)
- `/docs/synthesis/THREE_PIVOTS_SEVEN_LAYERS.md` (Process mining as 7-layer system)
- OCPM temporal mining research papers
