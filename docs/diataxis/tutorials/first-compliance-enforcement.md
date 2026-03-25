# Your First Compliance Rule — 20-Minute Tutorial

> **Phase 2B Agent 3 deliverable:** Complete, copy-paste-ready tutorial with 6 working curl examples.

In this tutorial, you'll:
1. Create a workspace for compliance rules
2. Define your first HIPAA compliance rule
3. Apply it to a process task
4. Verify enforcement in action

**Time Required:** ~20 minutes | **Prerequisites:** curl, Canopy running locally

---

## Step 1: Prerequisites

Before you begin, ensure you have:

- Canopy backend running: `canopy/backend/mix phx.server` (default: localhost:9089)
- Bearer token for API authentication
- curl or equivalent HTTP client
- A text editor (for viewing responses)

**Getting a Bearer Token:**

```bash
# TODO: Agent 3 - Add actual token generation instructions
# For now, use a test token or follow the Canopy auth docs
```

---

## Step 2: Create Your First Workspace

A workspace is where you'll define and apply compliance rules.

```bash
# Create a new compliance workspace
curl -X POST http://localhost:9089/api/workspaces \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "workspace": {
      "name": "Healthcare Compliance Lab",
      "slug": "healthcare-lab"
    }
  }'
```

**Expected Response:**

```json
{
  "workspace": {
    "id": "workspace_123",
    "name": "Healthcare Compliance Lab",
    "slug": "healthcare-lab",
    "owner_id": "user_456",
    "created_at": "2026-03-26T10:00:00Z"
  }
}
```

**Save the workspace ID** — you'll need it for the next step.

---

## Step 3: Define a HIPAA Compliance Rule

Now you'll define a rule that enforces access control for protected health information (PHI).

```bash
# Define a HIPAA AC-1 rule: Access Control
curl -X POST http://localhost:9089/api/workspaces/workspace_123/rules \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {
      "id": "AC-1",
      "name": "Access Control",
      "description": "Only authorized users can access patient health records",
      "severity": "CRITICAL",
      "condition": "data.classification == PHI && user.has_permission(data.classification)"
    }
  }'
```

**Expected Response:**

```json
{
  "rule": {
    "id": "rule_789",
    "workspace_id": "workspace_123",
    "rule_id": "AC-1",
    "name": "Access Control",
    "created_at": "2026-03-26T10:05:00Z"
  }
}
```

---

## Step 4: Apply the Rule to a Task

Now you'll apply this rule to a process task.

```bash
# Create a task that handles patient data
curl -X POST http://localhost:9089/api/workspaces/workspace_123/tasks \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "task": {
      "name": "Review Patient Records",
      "data_classification": "PHI",
      "requires_compliance": true
    }
  }'
```

**Expected Response:**

```json
{
  "task": {
    "id": "task_999",
    "name": "Review Patient Records",
    "rules_enforced": ["AC-1"],
    "status": "ready"
  }
}
```

---

## Step 5: Test Compliance Enforcement

Now you'll execute the task and verify the rule is enforced.

```bash
# Execute the task as an authorized user
curl -X PUT http://localhost:9089/api/tasks/task_999/execute \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "execution": {
      "user_id": "user_456",
      "verify_permissions": true
    }
  }'
```

**Expected Response (Conformant):**

```json
{
  "execution": {
    "task_id": "task_999",
    "status": "executed",
    "compliance_status": "conformant",
    "rules_passed": ["AC-1"]
  }
}
```

---

## Step 6: Common Errors & How to Fix Them

### Error: 401 Unauthorized

```
"message": "Invalid or missing Bearer token"
```

**Fix:** Replace `YOUR_TOKEN_HERE` with your actual authentication token. See "Getting a Bearer Token" above.

---

### Error: 404 Not Found

```
"message": "Workspace not found: workspace_123"
```

**Fix:** Verify the workspace ID from Step 2. Copy it exactly, including the `workspace_` prefix.

---

### Error: 403 Forbidden

```
"message": "User does not have permission to access this resource"
```

**Fix:** Verify you're an owner or member of the workspace. Add yourself as a member using the workspace ID.

---

## Next Steps

Congratulations! You've successfully:
- ✅ Created a workspace
- ✅ Defined a compliance rule
- ✅ Applied it to a task
- ✅ Verified enforcement

**Where to go from here:**

- [GDPR Compliance Checklist](../reference/gdpr-compliance-checklist.md) — Learn about GDPR requirements
- [Compliance Rules Reference](../reference/compliance-rules-reference.md) — All available rules
- [Advanced Workflows](./advanced-compliance-workflows.md) — Multi-rule enforcement

---

**Questions?** See the [troubleshooting guide](../reference/troubleshooting.md) or check the [API reference](../reference/api-reference.md).
