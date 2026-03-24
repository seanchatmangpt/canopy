# Zero-Touch Compliance Skill

**Signal:** S=(data, inform, direct, json, compliance-evidence)

## Purpose

Implement continuous compliance as a byproduct of autonomous execution. Compliance is not a periodic project — it's a continuous byproduct of how agents work.

## The Problem

Compliance is a $200B industry that's 100% manual:
- SOC 2, HIPAA, SOX audits require months of preparation
- Regulations change faster than organizations can adapt
- Evidence gathering is reactive (when auditors request)

## The Solution

**Compliance is continuous.** Every agent action is cryptographically logged as it happens.

### Hash-Chain Audit Trail

Every action creates an immutable audit entry:

```json
{
  "sequence_number": 12345,
  "event_type": "task_approval|task_start|task_commit|rollback|data_access",
  "event_data": {
    "actor_id": "agent-id",
    "task_id": "task-id",
    "action": "what happened",
    "result": "outcome"
  },
  "event_timestamp": "ISO8601",
  "event_hash": "SHA256(event_data || event_timestamp)",
  "previous_hash": "SHA256(previous_entry)",
  "actor_signature": "RSA-SIGN(event_hash, actor_private_key)",
  "merkle_batch_id": 456,
  "merkle_tree_root": "SHA256(batch_entries)"
}
```

### Immutability Guarantee

**Cryptographic proof:** No entry can be modified without breaking the hash chain.

```
entry[N].previous_hash == SHA256(entry[N-1].event_hash)

If any entry is modified:
- event_hash changes
- previous_hash in entry[N+1] no longer matches
- Chain is broken → tampering detected
```

### Merkle Tree Batching

Every ~1000 entries, create a Merkle tree root:

```json
{
  "merkle_batch_id": 456,
  "entry_count": 1000,
  "merkle_tree_root": "SHA256 of all entry hashes",
  "root_signatures": [
    {"auditor_id": "auditor-1", "signature": "RSA-SIGN(root, key)"},
    {"auditor_id": "auditor-2", "signature": "RSA-SIGN(root, key)"},
    {"auditor_id": "auditor-3", "signature": "RSA-SIGN(root, key)"}
  ],
  "batch_timestamp": "ISO8601"
}
```

**f+1 signatures required** (f < n/3 Byzantine fault tolerance)

## Regulation Change Detection

Monitor regulatory feeds, auto-map to affected processes:

```json
{
  "regulation": "GDPR Article 17",
  "change_detected": "2026-03-24",
  "affected_processes": [
    {"process_id": "data-deletion", "impact": "high"},
    {"process_id": "user-consent", "impact": "medium"}
  ],
  "gap_analysis": {
    "current_state": "Data deletion takes 7 days",
    "required_state": "Data deletion within 30 days",
    "compliance": false
  },
  "remediation_tasks": [
    {"task_id": "accelerate-deletion", "priority": "high"}
  ]
}
```

## Compliance as Code

Policies enforced in L7 (Governance layer):

```yaml
# SOC 2 Type II Policy
policies:
  - name: "access-control"
    rule: "ALL actions must have actor_id and signature"
    enforcement: "REJECT if actor_signature missing"

  - name: "data-encryption"
    rule: "ALL sensitive data must be encrypted at rest"
    enforcement: "SCAN if encryption flag missing"

  - name: "change-management"
    rule: "ALL production changes require approval"
    enforcement: "BLOCK if approval_chain empty"
```

## Input

```json
{
  "agent_action": {
    "agent_id": "process-healer",
    "task_id": "fix-bottleneck-123",
    "action": "modify_workflow",
    "changes": {...},
    "timestamp": "ISO8601"
  }
}
```

## Output

```json
{
  "audit_entry": {
    "sequence_number": 12345,
    "event_hash": "sha256-hash",
    "previous_hash": "previous-sha256",
    "actor_signature": "signature-base64",
    "merkle_batch_id": 456
  },
  "compliance_check": {
    "soc2": "compliant",
    "gdpr": "compliant",
    "sox": "compliant"
  }
}
```

## S/N Quality Gate

Score ≥ 0.7 (GOOD) required:
- All hash chain links valid
- Actor signature verifiable
- Merkle root signed by f+1 auditors
- Policy compliance verified

## 80/20 Justification

- **20% effort:** Hash-chain audit trail exists in spec, just need to implement
- **80% value:** Eliminates $300K+ annual compliance costs per enterprise
- **Blue Ocean:** Continuous compliance doesn't exist as a product category

## Error Handling

| Condition | Action |
|-----------|--------|
| Hash chain broken | Escalate to security team, halt operations |
| Signature invalid | Reject action, log security event |
| Merkle root missing signatures | Delay commit until f+1 signatures obtained |
| Policy violation | Block action, notify policy owner |

## Storage

- **Primary:** BusinessOS `/api/compliance/audit` endpoint
- **Backup:** Immutable file system (WORM via NFS ACL)
- **Archive:** Monthly export to cold storage (S3 Glacier)

## Verification

Any auditor can independently verify:

```python
def verify_audit_log(start_seq, end_seq):
    entries = fetch_entries(start_seq, end_seq)

    for entry in entries:
        # Verify hash chain
        computed_hash = sha256(entry.event_data + entry.event_timestamp)
        assert computed_hash == entry.event_hash

        # Verify chain links
        assert entry.previous_hash == prev_hash

        # Verify actor signature
        assert verify_signature(entry.event_hash, entry.actor_signature, entry.actor_id)

    # Verify Merkle root
    computed_root = compute_merkle_root([e.event_hash for e in entries])
    assert computed_root == entries[0].merkle_tree_root

    # Verify auditor signatures
    assert len(entries[0].root_signatures) >= f + 1
    for sig in entries[0].root_signatures:
        assert verify_signature(computed_root, sig.signature, sig.auditor_id)

    return True  # All verifications passed
```

## References

- `/docs/FORTUNE500_AUTONOMOUS_SYSTEM_IDEAL.md` (Hash-chain audit trail spec)
- `/docs/superpowers/specs/2026-03-23-vision-2030-blue-ocean-innovations-design.md` (Innovation 3)
- `/canopy/protocol/signal-theory.md` (Wiener feedback loop)
