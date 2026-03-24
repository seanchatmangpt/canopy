# Skill: integrate-result

Integrate agent execution results back into BusinessOS.

## Procedure

1. Receive agent result from orchestration
2. Determine target BusinessOS endpoint based on result type
3. POST result to BusinessOS
4. Update task status if applicable
5. Log execution metrics

## Result Type Routing

| Result Type | BusinessOS Endpoint |
|-------------|-------------------|
| CRM update | POST /api/crm/notes |
| Project update | PUT /api/projects/{id} |
| Task complete | PUT /api/tasks/{id}/status |
| Report | POST /api/documents |
| Compliance finding | POST /api/compliance/findings |
| App generated | POST /api/apps |

## Arguments

```json
{
  "result_type": "crm_update",
  "data": {"deal_id": "123", "new_stage": "qualified"},
  "session_id": "sdk-abc123"
}
```

## Returns

```json
{
  "integrated": true,
  "businessos_id": "note-456",
  "metrics": {"tokens_used": 1234, "duration_ms": 5678}
}
```
