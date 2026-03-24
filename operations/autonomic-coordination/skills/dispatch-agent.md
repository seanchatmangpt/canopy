# Skill: dispatch-agent

Dispatch OSA agents for specific tasks via the orchestration API.

## Agent Roles

| Role | Tier | Use Case |
|------|------|----------|
| health-monitor | utility | System health checks |
| crm-automation | specialist | CRM sync and reporting |
| project-coordinator | specialist | Project tracking |
| app-generator | elite | App generation |
| process-healer | specialist | Process repair |
| compliance-monitor | specialist | Compliance checking |
| businessos-gateway | specialist | BusinessOS API operations |
| researcher | specialist | Web research |

## Procedure

1. Parse task description
2. Select appropriate agent role
3. Determine tier based on task complexity
4. Call OSA orchestration: POST /api/v1/orchestrate
5. Stream results via SSE: GET /api/v1/stream/{session_id}
6. Return agent result

## Arguments

```json
{
  "role": "crm-automation",
  "message": "Sync pipeline deals and update stages",
  "tier": "specialist"
}
```

## Returns

```json
{
  "session_id": "sdk-abc123",
  "status": "completed",
  "result": "Updated 15 deals, 3 stage changes"
}
```
