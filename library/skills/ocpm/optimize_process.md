# Skill: OCPM Optimize Process

Design process improvements based on OCPM discovery findings and generate BFT consensus proposals.

## Overview

This skill analyzes OCPM discovery outputs (process models, bottlenecks, deviations) to design targeted process improvements with quantified impact analysis.

## Prerequisites

- Completed OCPM discovery (process model + bottlenecks + deviations)
- Identified improvement opportunities from discovery findings
- Target metrics for improvement (time savings, error reduction)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| discovery_result | object | Yes | Output from ocpm/discover_process skill |
| improvement_type | string | No | Focus area: `automation`, `parallelization`, `elimination`, `streamlining`, or `auto` (default) |
| max_improvements | integer | No | Maximum number of improvements to design (default: 5) |
| impact_threshold | float | No | Minimum impact threshold (default: 0.10 = 10% improvement) |
| include_proposal | boolean | No | Generate BFT consensus proposal (default: true) |

## Process

1. **Analyze Discovery Findings**
   - Review bottleneck list (sorted by severity/impact)
   - Review deviation report (sorted by frequency)
   - Identify improvement opportunities

2. **Prioritize Opportunities**
   - Score each opportunity: impact × feasibility
   - Apply 80/20 principle (focus on top 20% of opportunities)
   - Filter by impact_threshold parameter

3. **Design Improvements**
   - Choose approach for each opportunity:
     - **Automation**: Manual rule-based decisions → automated
     - **Parallelization**: Sequential independent activities → concurrent
     - **Elimination**: Non-value-added steps → removed
     - **Streamlining**: Multi-step processes → consolidated
   - Create "after" process model
   - Specify changes (add/remove/modify activities)

4. **Quantify Impact**
   - Calculate time savings (p95 based)
   - Estimate error reduction
   - Compute cost savings (time × rate + error reduction × cost)
   - Determine 95% confidence intervals

5. **Generate Proposal** (if `include_proposal=true`)
   - Build BFT consensus proposal structure
   - Include evidence from OCPM discovery
   - Specify rollback plan
   - Encode in Signal Theory format

## Output

### Signal Encoding
```
S=(planning, improvement_design, [automation|parallelization|elimination|streamlining], json, before_after)
S=(planning, impact_analysis, [automation|parallelization|elimination|streamlining], json, impact_metrics)
S=(proposal, consensus_proposal, process_model, json, proposal_content)
```

### Return Format

```json
{
  "signal": {
    "mode": "planning",
    "genre": "improvement_design",
    "type": "automation",
    "format": "json",
    "structure": "before_after"
  },
  "improvements": [
    {
      "name": "Automate Invoice Approval",
      "type": "automation",
      "priority": 1,
      "before": {
        "activities": ["manual_review", "manager_approval"],
        "p95_duration_minutes": 45,
        "manual_effort_percent": 80
      },
      "after": {
        "activities": ["auto_approve", "exception_review"],
        "estimated_p95_duration_minutes": 8,
        "manual_effort_percent": 15
      },
      "changes": {
        "remove": ["manual_review"],
        "add": [
          {
            "name": "auto_approve",
            "spec": "Approve invoices < $1000 automatically"
          }
        ],
        "modify": []
      },
      "evidence": {
        "source": "Bottleneck Report #1",
        "bottleneck_id": "manual_approval",
        "current_metrics": {
          "p95_duration_minutes": 45,
          "frequency_percent": 80,
          "failure_rate": 0.05
        }
      }
    }
  ],
  "impact_analysis": {
    "time_savings": {
      "current_p95_minutes": 45,
      "estimated_p95_minutes": 8,
      "reduction_percent": 82,
      "monthly_hours_saved": 243,
      "confidence_interval_95": "[220-266 hours]"
    },
    "error_reduction": {
      "current_error_rate": 0.05,
      "estimated_error_rate": 0.01,
      "monthly_errors_prevented": 40,
      "confidence_interval_95": "[35-45 errors]"
    },
    "cost_savings": {
      "time_savings_monthly_usd": 4860,
      "error_reduction_monthly_usd": 2000,
      "total_monthly_savings_usd": 6860,
      "roi_timeline_months": 2
    }
  },
  "proposal": {
    "type": "process_model",
    "workflow_id": "pi-invoice-1234567890",
    "content": {
      "what": "Automate invoice approval for amounts < $1000",
      "why": "Bottleneck #1: Manual approval takes 45min p95, appears in 80% of cases",
      "impact": {
        "time_savings_percent": 82,
        "monthly_savings_usd": 6860
      },
      "risks": [
        {
          "description": "Auto-approval may accept invalid invoices",
          "probability": "low",
          "mitigation": "Post-approval audit sampling"
        }
      ],
      "rollback": [
        "Disable auto-approval rule",
        "Restore manual review workflow",
        "Revert process model to version 1.0.0"
      ]
    }
  }
}
```

## Design Principles

1. **YAGNI**: Only address issues actually found in OCPM discovery
2. **80/20**: Focus on changes that deliver 80% of value with 20% effort
3. **Incremental**: Small, reversible changes (not full redesigns)
4. **Evidence-Based**: Every change links to specific discovery finding

## Impact Estimation Formulas

**Time Savings**:
```
monthly_hours_saved = (old_p95 - new_p95) / 60 × daily_cases × 22_days
```

**Error Reduction**:
```
monthly_errors_saved = (old_error_rate - new_error_rate) × (daily_cases × 22)
```

**Cost Savings**:
```
total_savings = (monthly_hours_saved × hourly_rate) + (monthly_errors_saved × cost_per_error)
```

## Example Usage

```
Execute skill: ocpm/optimize_process

Parameters:
{
  "discovery_result": {
    "process_model": {...},
    "bottlenecks": [...],
    "deviations": [...]
  },
  "improvement_type": "auto",
  "max_improvements": 3,
  "impact_threshold": 0.10,
  "include_proposal": true
}
```

## Quality Gates

- **Evidence**: Every improvement must cite specific OCPM finding
- **Impact**: Must meet minimum impact_threshold (default 10%)
- **Feasibility**: Implementation must be technically feasible
- **Rollback**: Must have clear rollback plan

## Integration

- **Input**: Discovery results from `ocpm/discover_process` skill
- **Output**: BFT proposals sent to Consensus Coordinator Agent
- **Storage**: Improvements tracked in process model version history
- **Routing**: Signal classifier routes to consensus/vote skill

## Next Steps

After proposal generation, use `consensus/vote` skill to execute BFT consensus on the proposal.
