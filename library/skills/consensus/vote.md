# Skill: Consensus Vote

Execute HotStuff-BFT voting protocol and tally results for agent fleet consensus.

## Overview

This skill manages the BFT voting process: collects votes from agents, checks supermajority threshold, and commits or rejects proposals based on fleet decision.

## Prerequisites

- Active proposal with status `:pending`
- Agent fleet defined (minimum 3 agents)
- Voting period not expired

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| proposal_id | string | Yes | Workflow ID of proposal to vote on |
| agent_votes | array | No | Pre-collected votes (if voting manually) |
| wait_for_votes | boolean | No | Wait for all votes before tallying (default: true) |
| timeout_seconds | integer | No | Maximum wait time (default: 300) |

## Process

1. **Verify Proposal**
   - Check proposal exists and is `:pending`
   - Verify voting period not expired
   - Confirm fleet composition

2. **Collect Votes**
   - Receive votes from each agent
   - Validate vote format (APPROVE | REJECT)
   - Record each vote in audit log
   - Check for timeout

3. **Tally Results**
   - Count approve vs. reject votes
   - Calculate supermajority: `approve_count / total_votes > 0.667`
   - Check fault tolerance: `faulty <= floor((n-1)/3)`
   - Determine outcome: APPROVED or REJECTED

4. **Execute Decision**
   - If APPROVED:
     - Execute proposal (trigger implementation)
     - Update proposal status to `:approved`
     - Record commit in audit log
     - Return commit receipt
   - If REJECTED:
     - Return proposal with feedback
     - Update proposal status to `:rejected`
     - Record rejection in audit log

5. **Verify Audit Trail**
   - Compute hash chain integrity
   - Validate all entries link correctly
   - Return audit hash for verification

## Output

### Signal Encoding
```
S=(tally, proposal_result, hotstuff_bft, json, tally_result)
S=(consensus, audit_entry, hash_chain, json, audit_log)
```

### Return Format (APPROVED)

```json
{
  "signal": {
    "mode": "tally",
    "genre": "proposal_result",
    "type": "hotstuff_bft",
    "format": "json",
    "structure": "tally_result"
  },
  "proposal_id": "pi-invoice-1234567890",
  "outcome": "APPROVED",
  "voting_summary": {
    "total_agents": 3,
    "votes_received": 3,
    "participation_percent": 100,
    "voting_duration_seconds": 245
  },
  "vote_breakdown": {
    "approve": {
      "count": 3,
      "percent": 100,
      "votes": [
        {
          "agent_id": "automation-engineer",
          "vote": "APPROVE",
          "reasoning": "Clear automation opportunity with strong evidence",
          "timestamp": "2026-03-23T12:01:30Z"
        },
        {
          "agent_id": "data-analyst",
          "vote": "APPROVE",
          "reasoning": "Impact quantification is solid, 95% CI acceptable",
          "timestamp": "2026-03-23T12:02:15Z"
        },
        {
          "agent_id": "finance-expert",
          "vote": "APPROVE",
          "reasoning": "Risk mitigation plan is adequate, rollback is clear",
          "timestamp": "2026-03-23T12:03:00Z"
        }
      ]
    },
    "reject": {
      "count": 0,
      "percent": 0,
      "votes": []
    }
  },
  "supermajority_calculation": {
    "approve_count": 3,
    "total_votes": 3,
    "approve_ratio": 1.0,
    "threshold": 0.667,
    "result": "1.0 > 0.667 = TRUE"
  },
  "fault_tolerance_check": {
    "fleet_size": 3,
    "max_faulty": 1,
    "faulty_agents": 0,
    "safe": "0 <= 1 = TRUE"
  },
  "commit_receipt": {
    "committed_at": "2026-03-23T12:04:05Z",
    "executor": "consensus-coordinator",
    "implementation_status": "triggered",
    "audit_hash": "sha256:def456...",
    "sequence_number": 5
  },
  "next_steps": [
    "Execute proposal implementation",
    "Monitor implementation progress",
    "Validate results against expected impact"
  ]
}
```

### Return Format (REJECTED)

```json
{
  "signal": {
    "mode": "tally",
    "genre": "proposal_result",
    "type": "hotstuff_bft",
    "format": "json",
    "structure": "tally_result"
  },
  "proposal_id": "pi-invoice-1234567890",
  "outcome": "REJECTED",
  "reason": "supermajority_not_met",
  "voting_summary": {
    "total_agents": 3,
    "votes_received": 3,
    "participation_percent": 100,
    "voting_duration_seconds": 180
  },
  "vote_breakdown": {
    "approve": {
      "count": 1,
      "percent": 33.3,
      "votes": [
        {
          "agent_id": "automation-engineer",
          "vote": "APPROVE",
          "reasoning": "Good automation candidate",
          "timestamp": "2026-03-23T12:01:00Z"
        }
      ]
    },
    "reject": {
      "count": 2,
      "percent": 66.7,
      "votes": [
        {
          "agent_id": "finance-expert",
          "vote": "REJECT",
          "reasoning": "Risk mitigation insufficient - need stronger controls",
          "timestamp": "2026-03-23T12:01:45Z"
        },
        {
          "agent_id": "compliance-expert",
          "vote": "REJECT",
          "reasoning": "Audit trail requirements not fully addressed",
          "timestamp": "2026-03-23T12:02:30Z"
        }
      ]
    }
  },
  "supermajority_calculation": {
    "approve_count": 1,
    "total_votes": 3,
    "approve_ratio": 0.333,
    "threshold": 0.667,
    "result": "0.333 > 0.667 = FALSE"
  },
  "feedback": {
    "key_concerns": [
      "Risk mitigation insufficient (finance-expert)",
      "Audit trail requirements not addressed (compliance-expert)"
    ],
    "suggested_revisions": [
      "Add pre-approval validation controls",
      "Strengthen audit trail logging",
      "Include post-approval audit sampling"
    ]
  },
  "next_steps": [
    "Revise proposal based on feedback",
    "Resubmit as new proposal with new workflow_id",
    "Schedule new vote cycle"
  ]
}
```

## Voting Rules

1. **Participation**: All agents must vote (100% required)
2. **Format**: Votes must be `APPROVE:` or `REJECT:` with reasoning
3. **Timeout**: Votes not received after timeout are counted as REJECT
4. **Threshold**: Supermajority of >66.7% required for approval
5. **Tie-breaking**: Exact threshold (66.7%) results in REJECT

## Fault Tolerance

- **3 agents**: Can tolerate 1 faulty
- **7 agents**: Can tolerate 2 faulty
- **10 agents**: Can tolerate 3 faulty

Faulty agents = those voting incorrectly or not voting at all.

## Example Usage

```
Execute skill: consensus/vote

Parameters:
{
  "proposal_id": "pi-invoice-1234567890",
  "wait_for_votes": true,
  "timeout_seconds": 300
}
```

## Quality Gates

- **Participation**: 100% of agents must vote
- **Supermajority**: >66.7% approval required
- **Fault Tolerance**: Faulty agents ≤ ⌊(n-1)/3⌋
- **Audit Trail**: Hash chain must verify

## Integration

- **Input**: Active proposals from `consensus/propose`
- **Output**: Commit/reject results to PI Optimization Agent
- **Storage**: ETS tables for proposals, audit log
- **Protocol**: HotStuff-BFT via `OptimalSystemAgent.Consensus.HotStuff`

## Next Steps

- **If APPROVED**: Execute implementation, validate with Signal Theory quality gates
- **If REJECTED**: Revise proposal based on feedback, resubmit
