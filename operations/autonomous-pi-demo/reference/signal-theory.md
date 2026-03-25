# Signal Theory Reference

Signal Theory provides the universal encoding framework for agent outputs: **S=(M,G,T,F,W)**

## Encoding Structure

```
S = (Mode, Genre, Type, Format, Structure)
```

### Mode (M)
The operational mode of the signal.

| Mode | Description | Example Usage |
|------|-------------|---------------|
| `discovery` | Process mining and analysis | OCPM discovery outputs |
| `planning` | Improvement design and analysis | PI optimization proposals |
| `consensus` | Voting and governance | BFT consensus results |
| `execution` | Implementation and runtime | Workflow execution |
| `validation` | Quality gates and verification | S/N ratio measurements |
| `bottleneck` | Bottleneck detection | Heuristic miner outputs |
| `deviation` | Conformance checking | Deviation reports |

### Genre (G)
The content category of the signal.

| Genre | Description | Example Usage |
|-------|-------------|---------------|
| `process_model` | Discovered process structures | Alpha miner outputs |
| `bottleneck_report` | Bottleneck analysis | Heuristic miner outputs |
| `conformance_report` | Deviation analysis | Conformance checking |
| `improvement_design` | Proposed improvements | PI optimization designs |
| `impact_analysis` | Quantified impact estimates | Cost/time savings |
| `consensus_proposal` | BFT voting proposals | Consensus proposals |
| `vote` | Individual agent votes | Vote records |
| `proposal_result` | Tally outcomes | Approved/rejected |
| `audit_entry` | Audit trail entries | Hash-chain logs |

### Type (T)
The specific implementation or algorithm type.

| Type | Description | Example Usage |
|-------|-------------|---------------|
| `alpha_miner` | Alpha miner algorithm | Process model discovery |
| `heuristic_miner` | Heuristic miner | Bottleneck detection |
| `conformance_check` | Conformance checking | Deviation detection |
| `automation` | Automation improvements | Automated activities |
| `parallelization` | Parallel execution | Concurrent activities |
| `elimination` | Activity removal | Removed steps |
| `streamlining` | Process consolidation | Merged activities |
| `hotstuff_bft` | HotStuff-BFT protocol | Consensus voting |
| `supermajority_check` | Threshold verification | Vote tallying |
| `hash_chain` | Audit trail integrity | Audit logs |

### Format (F)
The serialization format.

| Format | Description | Example Usage |
|-------|-------------|---------------|
| `json` | JSON-structured data | API responses, storage |
| `markdown` | Human-readable documentation | Reports, documentation |
| `mermaid` | Diagram visualization | Process flow graphs |

### Structure (W)
The internal organization of the data.

| Structure | Description | Example Usage |
|----------|-------------|---------------|
| `nodes_edges` | Process model graph | Activity transitions |
| `bottleneck_list` | List of bottlenecks | Bottleneck reports |
| `deviation_list` | List of deviations | Conformance reports |
| `before_after` | Comparison format | Improvement designs |
| `impact_metrics` | Quantified estimates | Impact analysis |
| `proposal_content` | BFT proposal structure | Consensus proposals |
| `vote_record` | Individual vote | Voting records |
| `tally_result` | Vote aggregation | Consensus results |
| `audit_log` | Audit trail entries | Hash-chain logs |

## Complete Examples

### OCPM Discovery Output

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
    "nodes": ["receive", "validate", "approve", "pay"],
    "edges": {...},
    "version": "1.0.0"
  }
}
```

### Bottleneck Report

```json
{
  "signal": {
    "mode": "bottleneck",
    "genre": "bottleneck_report",
    "type": "heuristic_miner",
    "format": "json",
    "structure": "bottleneck_list"
  },
  "bottlenecks": [
    {
      "activity": "manual_review",
      "severity": "critical",
      "p95_duration_minutes": 45
    }
  ]
}
```

### Consensus Proposal

```json
{
  "signal": {
    "mode": "proposal",
    "genre": "consensus_proposal",
    "type": "automation",
    "format": "json",
    "structure": "proposal_content"
  },
  "proposal": {
    "type": "process_model",
    "workflow_id": "pi-invoice-123",
    "content": {...}
  }
}
```

### Vote Tally

```json
{
  "signal": {
    "mode": "tally",
    "genre": "proposal_result",
    "type": "hotstuff_bft",
    "format": "json",
    "structure": "tally_result"
  },
  "outcome": "APPROVED",
  "vote_breakdown": {...}
}
```

## Signal Classifier

Use `OptimalSystemAgent.Signal.Classifier` to route signals based on encoding:

```elixir
# Route discovery outputs to appropriate handler
case classifier.classify(signal) do
  %{mode: "discovery", genre: "process_model"} ->
    # Send to process model storage
  %{mode: "consensus", genre: "vote"} ->
    # Send to consensus tally
  _ ->
    # Default handler
end
```

## Quality Gates

Signal Theory encoding enables quality gates at each stage:

### Discovery Stage
- **Confidence Gate**: All relations ≥95% confidence
- **Sample Size Gate**: Minimum 100 cases
- **Data Quality Gate**: <5% missing values

### Planning Stage
- **Impact Gate**: Minimum 10% improvement required
- **Evidence Gate**: All claims cite OCPM findings
- **Rollback Gate**: Clear rollback plan required

### Consensus Stage
- **Participation Gate**: 100% agent participation
- **Supermajority Gate**: >66.7% approval required
- **Fault Tolerance Gate**: Faulty ≤ ⌊(n-1)/3⌋

### Validation Stage
- **S/N Ratio Gate**: S/N ≥10dB (invoice), ≥15dB (onboarding), ≥20dB (compliance)
- **Data Loss Gate**: Zero data loss
- **Audit Trail Gate**: Hash chain verified

## Signal-to-Noise (S/N) Ratio

Calculate S/N ratio for validation:

```
S/N (dB) = 10 × log10(μ² / σ²)

Where:
- μ = mean of improved process metric
- σ² = variance of improved process metric

Higher S/N = more consistent, reliable improvement
```

**Target S/N ratios**:
- Invoice processing: ≥10dB (10:1 signal-to-noise)
- Customer onboarding: ≥15dB (31:1 signal-to-noise)
- Compliance reporting: ≥20dB (100:1 signal-to-noise)

## Implementation

All agent outputs MUST include Signal Theory encoding:

```elixir
def encode_signal(mode, genre, type, format, structure) do
  %{
    signal: %{
      mode: mode,
      genre: genre,
      type: type,
      format: format,
      structure: structure
    }
  }
end
```

This enables:
1. **Routing**: Classifier routes to appropriate handlers
2. **Filtering**: Query signals by Mode/Genre/Type
3. **Validation**: Verify signal completeness
4. **Audit**: Track all signal types in system
