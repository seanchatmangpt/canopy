# Skill: process-webhook

Process incoming BusinessOS webhook events from OSA's ETS store.

## Event Types

| Event | Action |
|-------|--------|
| `workflow.completed` | Log completion, check for follow-up tasks |
| `build.progress` | Update progress tracking in BusinessOS |
| `app.generated` | Log app generation, notify stakeholders |
| `process.anomaly` | Trigger process-healer agent |
| `error` | Trigger self-healing via OSA healing orchestrator |

## Procedure

1. Fetch events from OSA: GET /webhooks/businessos/events
2. Process each unprocessed event
3. For each event:
   a. Classify event type
   b. Execute appropriate action
   c. Mark event as processed
4. Return summary of actions taken

## Arguments

```json
{
  "max_events": 50,
  "event_types": ["all"]
}
```

## Returns

```json
{
  "processed": 12,
  "actions_taken": ["logged_completion", "triggered_healing"],
  "errors": []
}
```
