# Skill: health-check

Execute health checks on all system components.

## Endpoints

| System | URL | Expected |
|--------|-----|----------|
| OSA | GET http://localhost:9089/health | `{status: "ok"}` |
| BusinessOS | GET http://localhost:8001/api/health | `{status: "healthy"}` |
| Canopy | GET http://localhost:5200/health | `{status: "ok"}` |

## Procedure

1. Make HTTP GET to each endpoint with 5s timeout
2. Parse response JSON
3. If response != ok: attempt shell restart
4. Return structured status map

## Arguments

```json
{
  "systems": ["osa", "businessos", "canopy"]
}
```

## Returns

```json
{
  "osa": {"status": "ok", "uptime": 12345},
  "businessos": {"status": "down", "error": "connection refused"},
  "canopy": {"status": "ok", "uptime": 6789}
}
```
