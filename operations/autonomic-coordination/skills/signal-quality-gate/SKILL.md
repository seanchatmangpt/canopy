# Signal Theory Quality Gate Skill

**Signal:** S=(linguistic, report, direct, markdown, quality-report)

## Purpose

Apply Signal Theory S/N scoring to agent outputs. Reject outputs that fall below the quality threshold (default: 0.5).

## The 5 Dimensions

Every output is scored across 5 dimensions:

| Dimension | Weight | Scoring Criteria |
|-----------|--------|-----------------|
| **M** (Mode) | 20% | Mode matches receiver perception |
| **G** (Genre) | 20% | Genre matches situation type |
| **T** (Type) | 20% | Speech act achieves intended outcome |
| **F** (Format) | 20% | Format appropriate for channel |
| **W** (Structure) | 20% | Internal skeleton present and valid |

## Scoring Algorithm

```
S/N = (M_score + G_score + T_score + F_score + W_score) / 5
```

### Dimension Scoring

**M (Mode):**
- 1.0: Perfect match (visual → diagram, code → code)
- 0.7: Good match (visual → text with diagram reference)
- 0.3: Mismatch (visual → wall of text)
- 0.0: Complete failure

**G (Genre):**
- 1.0: Correct genre (spec for dev, brief for PM)
- 0.7: Acceptable alternative
- 0.3: Wrong genre
- 0.0: No genre detected

**T (Type):**
- 1.0: Speech act succeeds (direct → action taken)
- 0.7: Partial success
- 0.3: Speech act fails
- 0.0: Unclear intent

**F (Format):**
- 1.0: Optimal format (JSON for API, markdown for docs)
- 0.7: Acceptable
- 0.3: Suboptimal
- 0.0: Wrong format

**W (Structure):**
- 1.0: Complete template with all sections
- 0.7: Most sections present
- 0.3: Minimal structure
- 0.0: No structure

## Quality Gates

| Score Range | Verdict | Action |
|-------------|---------|--------|
| 0.9 - 1.0 | OPTIMAL | Accept immediately |
| 0.7 - 0.9 | GOOD | Accept |
| 0.5 - 0.7 | PASS | Accept with note |
| 0.3 - 0.5 | WARN | Return for revision |
| 0.0 - 0.3 | REJECT | Block, require rewrite |

## Failure Mode Detection

### Shannon Violations
- Output length > 2x minimum required
- Bandwidth overload detected
- **Fix:** Reduce, prioritize, batch

### Ashby Violations
- Genre mismatch for situation
- No appropriate genre exists
- **Fix:** Re-encode in correct genre or create new genre

### Beer Violations
- Orphaned logic (conclusion without evidence)
- Structure gaps
- **Fix:** Add missing sections, remove orphaned content

### Wiener Violations
- No confirmation loop
- Unclear if action was taken
- **Fix:** Add verification step

## Input

Agent output to validate:
```json
{
  "agent_id": "string",
  "output": "string",
  "signal_intent": {
    "M": "mode",
    "G": "genre",
    "T": "type",
    "F": "format",
    "W": "structure"
  },
  "receiver_context": {
    "receiver_type": "agent|human|system",
    "expected_genre": "string",
    "bandwidth": "high|medium|low"
  }
}
```

## Output

```json
{
  "score": number,
  "verdict": "OPTIMAL|GOOD|PASS|WARN|REJECT",
  "dimension_scores": {
    "M": number,
    "G": number,
    "T": number,
    "F": number,
    "W": number
  },
  "violations": [
    {
      "type": "SHANNON|ASHBY|BEER|WIENER",
      "description": "string",
      "fix": "string"
    }
  ],
  "recommendation": "string"
}
```

## Thresholds

Per-phase thresholds (configurable):
- **Analysis phase:** 0.5 (PASS)
- **Decision phase:** 0.7 (GOOD)
- **Execution phase:** 0.5 (PASS)
- **Governance phase:** 0.7 (GOOD)

## Usage

Invoke this skill after every agent output in the autonomous healing workflow:

```
1. Agent produces output
2. Call signal-quality-gate
3. If score < threshold: Return output to agent with rejection notice
4. If score ≥ threshold: Proceed to next phase
```

## References

- `/canopy/protocol/signal-theory.md`
- `/docs/synthesis/DOUBLE_HELIX_SIGNAL_THEORY_AND_CHATMAN_EQUATION.md`
- `/docs/synthesis/THREE_PIVOTS_SEVEN_LAYERS.md`
