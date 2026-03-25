# BusinessOS Discovery Webhook Integration Guide

## Overview

This guide describes how Canopy integrates with BusinessOS process discovery completion events via webhooks. When BusinessOS finishes discovering a process model, it sends a webhook that automatically creates an issue and dispatches it to the **Process Mining Monitor** agent for analysis.

## Architecture

```
BusinessOS (port 8001)
    ↓ POST /api/v1/hooks/{webhook_id}
Canopy Webhook Receiver
    ↓
IssueDispatcher (GenServer)
    ↓
Process Mining Monitor Agent
    ↓ (via OSA adapter)
Analysis + Recommendations
```

## Setup

### 1. Seed the Workflow

The `Process Mining` workspace, agent, and webhook are seeded automatically:

```bash
cd canopy/backend
mix run priv/repo/seeds/20260325_process_mining_workflow.exs
```

This creates:
- **Workspace:** "Process Mining" (`~/.canopy/process-mining`)
- **Agent:** "Process Mining Monitor" (slug: `process-mining-monitor`, role: `process_miner`)
- **Webhook:** "BusinessOS Discovery Complete" (incoming webhook)

### 2. Get the Webhook ID

From the seed output, note the webhook ID:

```
"BusinessOS Discovery Complete" webhook (8cc21493-7f24-4415-bb17-368a7c436960)

Agent will receive discoveries via POST /api/v1/hooks/8cc21493-7f24-4415-bb17-368a7c436960
```

### 3. Configure BusinessOS

Update BusinessOS discovery completion to POST to:

```
POST http://localhost:9089/api/v1/hooks/{webhook_id}
```

Example payload:

```json
{
  "model_id": "uuid-of-discovered-model",
  "algorithm": "heuristics",
  "activities_count": 42,
  "fitness_score": 0.95
}
```

## How It Works

### Webhook Handler: `Canopy.Webhooks.BusinessosDiscoveryWebhook`

Located in `/canopy/backend/lib/canopy/webhooks/businessos_discovery_webhook.ex`

**Key Features:**
1. **Idempotency:** Duplicate POSTs with the same `model_id` create only 1 issue
2. **Validation:** Checks for required fields and correct types
3. **Issue Creation:** Title = `"Process Model: {algorithm}"`, description = `model_id`
4. **Agent Assignment:** Automatically assigns issue to the process-mining-monitor agent
5. **Dispatch:** Issues assigned event triggers the IssueDispatcher

### Request Validation

All of these are **required** and must match their types:

| Field | Type | Example | Purpose |
|-------|------|---------|---------|
| `model_id` | string | `"abc-123-def"` | Unique identifier for the discovered model |
| `algorithm` | string | `"heuristics"` | Discovery algorithm used |
| `activities_count` | integer | `42` | Number of unique activities in the model |
| `fitness_score` | number (float) | `0.95` | Quality metric (0-1 scale) |

### Responses

**Success (200 OK):**
```json
{
  "ok": true,
  "delivery_id": "uuid-of-delivery-record",
  "issue_id": "uuid-of-created-issue",
  "agent_id": "uuid-of-assigned-agent"
}
```

**Error (5xx):**
Returns 500 if webhook handler fails. BusinessOS should retry. Common reasons:
- Workspace not found
- Agent "process-mining-monitor" not found in workspace
- Invalid payload (missing/wrong type fields)

## Testing

### 1. Unit Tests

```bash
cd canopy/backend
mix test test/canopy/webhooks/businessos_discovery_webhook_test.exs
```

**8 tests:**
- ✓ Creates issue when discovery completes
- ✓ Assigns issue to agent
- ✓ Idempotency (duplicate POSTs return same issue)
- ✓ Error: workspace not found
- ✓ Error: agent not found
- ✓ Error: invalid payload (missing fields)
- ✓ Error: invalid payload (wrong types)
- ✓ Populates agent_id in response

### 2. Manual Integration Test

```bash
# 1. Seed the workflow
cd canopy/backend
mix run priv/repo/seeds/20260325_process_mining_workflow.exs

# 2. Get the webhook ID from output (e.g., 8cc21493-7f24-4415-bb17-368a7c436960)

# 3. Test with curl
curl -X POST http://localhost:9089/api/v1/hooks/8cc21493-7f24-4415-bb17-368a7c436960 \
  -H "Content-Type: application/json" \
  -d '{
    "model_id": "test-model-001",
    "algorithm": "heuristics",
    "activities_count": 12,
    "fitness_score": 0.88
  }'

# 4. Verify issue was created
curl http://localhost:9089/api/v1/issues \
  -H "Authorization: Bearer <token>"

# 5. Check if it was assigned to process-mining-monitor agent
# Look for issue with title "Process Model: heuristics"
```

## Integration Points

### 1. Webhook Controller (`CanopyWeb.WebhookController`)

The `/api/v1/hooks/{webhook_id}` endpoint:
1. Verifies webhook secret (if configured)
2. Records delivery in WebhookDelivery table
3. **Routes to handler:** Calls `Canopy.Webhooks.BusinessosDiscoveryWebhook.handle_discovery_complete/2`
4. Broadcasts `webhook.received` event

### 2. IssueDispatcher (automatic)

When webhook handler calls `Canopy.Work.assign_issue/2`:
1. Issue is assigned to agent
2. PubSub broadcasts `issue.assigned` event
3. IssueDispatcher GenServer picks it up
4. Agent is dispatched via heartbeat (if agent is idle or active)

### 3. Process Mining Monitor Agent

Receives discovery model via heartbeat context. Can:
- Analyze model quality
- Generate recommendations
- Write results to workspace output directory

## File Structure

```
canopy/backend/
├── lib/canopy/webhooks/
│   └── businessos_discovery_webhook.ex          # Handler module (main logic)
├── lib/canopy_web/controllers/
│   └── webhook_controller.ex                     # Endpoint + routing (modified)
├── priv/repo/seeds/
│   └── 20260325_process_mining_workflow.exs     # Seed: workspace + agent + webhook
└── test/canopy/webhooks/
    └── businessos_discovery_webhook_test.exs     # 8 unit tests
```

## Troubleshooting

### Webhook 404s
- Verify webhook ID from seed output
- Check it exists in Canopy database: `Repo.get(Webhook, webhook_id)`
- Ensure port mapping: BusinessOS → Canopy port 9089

### Issues not being created
- Check webhook handler logs for error messages
- Verify "Process Mining" workspace exists
- Verify "process-mining-monitor" agent exists in that workspace

### Issues not being dispatched
- Check IssueDispatcher is running: `Repo.all(Canopy.IssueDispatcher.__info__(:functions))`
- Verify agent status is "idle" or "active" (not "paused", "offline", etc.)
- Check agent hasn't hit concurrent run limits

### JSON encoding errors
- Ensure `activities_count` is an integer (not a string "42")
- Ensure `fitness_score` is a number (not a string "0.95")
- Both are required fields

## Example: From Discovery to Agent Dispatch

1. **BusinessOS Discovery Completes**
   ```
   Discovered 42 activities, 0.95 fitness using heuristics algorithm
   ```

2. **POST Webhook**
   ```bash
   curl -X POST http://localhost:9089/api/v1/hooks/8cc21493-7f24-4415-bb17-368a7c436960 \
     -d '{"model_id":"model-123","algorithm":"heuristics","activities_count":42,"fitness_score":0.95}'
   ```

3. **Canopy Creates Issue**
   ```
   Issue {
     title: "Process Model: heuristics",
     description: "model-123",
     status: "backlog",
     priority: "high",
     workspace_id: "..."
   }
   ```

4. **IssueDispatcher Assigns & Dispatches**
   ```
   Issue assigned to: Process Mining Monitor (agent)
   PubSub broadcasts: issue.assigned
   IssueDispatcher picks up event
   Heartbeat spawned for agent with context containing model data
   ```

5. **Agent Analyzes**
   ```
   Process Mining Monitor receives context with:
   - issue.title = "Process Model: heuristics"
   - issue.description = "model-123"
   - workspace path

   Agent executes:
   - Validates fitness (0.95 = strong)
   - Generates analysis
   - Writes report to output/
   ```

## Notes

- **No authentication required** on webhook endpoint (uses webhook secret, not JWT)
- **Idempotent by design:** Safe to retry failed POSTs
- **Async dispatch:** Webhook returns 200 immediately; agent dispatch happens in background
- **Error handling:** Errors are logged; webhook returns 500 to trigger retries
- **Signal Theory Integration:** All outputs encode as S=(M,G,T,F,W) for signal quality gates

## Related Files

- **Webhook Handler:** `/canopy/backend/lib/canopy/webhooks/businessos_discovery_webhook.ex`
- **Tests:** `/canopy/backend/test/canopy/webhooks/businessos_discovery_webhook_test.exs`
- **Seed:** `/canopy/backend/priv/repo/seeds/20260325_process_mining_workflow.exs`
- **Endpoint:** `/canopy/backend/lib/canopy_web/router.ex` (line 277)
- **Controller:** `/canopy/backend/lib/canopy_web/controllers/webhook_controller.ex`
