# Skill: Consensus Propose

Generate and submit BFT consensus proposals for agent fleet voting.

## Overview

This skill creates formal BFT consensus proposals from improvement designs and submits them to the agent fleet for HotStuff-BFT voting.

## Prerequisites

- Completed improvement design from `ocpm/optimize_process` skill
- Agent fleet defined (minimum 3 agents for BFT properties)
- Proposal content validated (what, why, impact, risks, rollback)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| improvement_design | object | Yes | Output from ocpm/optimize_process skill |
| fleet_composition | array | Yes | List of agents in voting fleet |
| voting_timeout_seconds | integer | No | Maximum time for voting (default: 300) |
| supermajority_threshold | float | No | Approval threshold (default: 0.667 = 66.7%) |

## Process

1. **Validate Proposal**
   - Check all required fields present
   - Verify evidence links to OCPM discovery
   - Confirm rollback plan is clear
   - Ensure impact quantification is complete

2. **Generate Proposal ID**
   - Create unique workflow_id
   - Format: `pi-[process_type]-[timestamp]`
   - Check for duplicates

3. **Build Proposal Structure**
   - Type: `:process_model` | `:workflow` | `:decision`
   - Content: what, why, impact, risks, rollback
   - Proposer: agent_id
   - Status: `:pending`
   - Created_at: current timestamp

4. **Initialize Audit Trail**
   - Create audit log entry
   - Compute initial hash
   - Store in ETS table

5. **Broadcast to Fleet**
   - Send proposal to all agents
   - Set voting timeout
   - Track vote status

## Output

### Signal Encoding
```
S=(consensus, proposal_result, hotstuff_bft, json, proposal_content)
```

### Return Format

```json
{
  "signal": {
    "mode": "consensus",
    "genre": "proposal_result",
    "type": "hotstuff_bft",
    "format": "json",
    "structure": "proposal_content"
  },
  "proposal": {
    "type": "process_model",
    "workflow_id": "pi-invoice-1234567890",
    "proposer": "pi-optimization-agent",
    "content": {
      "what": "Automate invoice approval for amounts < $1000",
      "why": "Bottleneck #1: Manual approval takes 45min p95, 80% of cases",
      "impact": {
        "time_savings_percent": 82,
        "monthly_savings_usd": 6860,
        "confidence_interval": "95% CI: [220-266 hours]"
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
        "Restore manual review workflow"
      ]
    },
    "votes": {},
    "status": "pending",
    "created_at": "2026-03-23T12:00:00Z"
  },
  "fleet": {
    "agents": [
      {"id": "automation-engineer", "name": "Automation Engineer", "vote_weight": 1.0},
      {"id": "data-analyst", "name": "Data Analyst", "vote_weight": 1.0},
      {"id": "finance-expert", "name": "Finance Expert", "vote_weight": 1.5}
    ],
    "total_agents": 3,
    "supermajority_threshold": 0.667,
    "fault_tolerance": "f < 1"
  },
  "voting": {
    "deadline": "2026-03-23T12:05:00Z",
    "timeout_seconds": 300,
    "current_status": "collecting_votes"
  },
  "audit": {
    "sequence_number": 1,
    "entry_hash": "sha256:abc123...",
    "previous_hash": null
  }
}
```

## Validation Rules

1. **Completeness**: All required fields must be present
2. **Evidence**: Must cite specific OCPM discovery findings
3. **Impact**: Must include quantified metrics with confidence intervals
4. **Risks**: Must identify potential downsides and mitigations
5. **Rollback**: Must have clear reversion steps

## BFT Properties

- **Fault Tolerance**: f < n/3 (can tolerate up to ⌊(n-1)/3⌋ faulty agents)
- **Supermajority**: >66.7% approval required
- **Liveness**: System makes progress if ≥2/3 agents honest
- **Safety**: No conflicting commits if ≥2/3 agents honest

## Example Usage

```
Execute skill: consensus/propose

Parameters:
{
  "improvement_design": {
    "improvements": [...],
    "impact_analysis": {...}
  },
  "fleet_composition": [
    {"id": "automation-engineer", "vote_weight": 1.0},
    {"id": "data-analyst", "vote_weight": 1.0},
    {"id": "finance-expert", "vote_weight": 1.5}
  ],
  "voting_timeout_seconds": 300,
  "supermajority_threshold": 0.667
}
```

## Integration

- **Input**: Improvement designs from `ocpm/optimize_process`
- **Output**: Proposals broadcast to agent fleet
- **Storage**: ETS tables for proposals, views, audit log
- **Protocol**: HotStuff-BFT via `OptimalSystemAgent.Consensus.HotStuff`

## Next Steps

After proposal submission, use `consensus/vote` skill to collect votes and tally results.
