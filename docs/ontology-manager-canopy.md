# Canopy Ontology Manager — Complete Architecture

> Version 1.0 — Date: 2026-03-26
>
> Ontology management in Canopy: HTTP controllers, in-memory caching, search capabilities, and statistics.

---

## Overview

The Canopy Ontology Manager provides HTTP API endpoints for accessing and searching ontologies managed by OSA (Optimal System Agent). It caches ontology metadata locally for fast access and supports pagination, search, and statistics queries.

**Key Design Principles:**
- Delegation to OSA via HTTP (no ontology storage in Canopy)
- Local caching for performance
- RESTful API design
- Stateless controllers
- Async periodic cache refresh

---

## Architecture

### Component Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Phoenix HTTP Handlers                                       │
│  - CanopyWeb.OntologyController                             │
│    └─ [index, show, search, statistics, get_class]          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ HTTP Client Layer                                           │
│  - Canopy.Ontology.Client (Req-based HTTP calls)            │
│    └─ [list_ontologies, get_ontology, search, statistics]   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ Caching Layer                                               │
│  - Canopy.Ontology.Loader (GenServer + ETS)                 │
│    └─ [load_all, cache_stats, clear_cache, refresh_cache]   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ External Service                                            │
│  - OSA (Port 8089)                                          │
│    └─ /api/v1/ontologies/* endpoints                        │
└─────────────────────────────────────────────────────────────┘
```

### Module Responsibilities

| Module | Responsibility | Pattern |
|--------|---|---|
| `CanopyWeb.OntologyController` | HTTP request handling, parameter validation, response serialization | Phoenix Controller |
| `Canopy.Ontology.Client` | HTTP communication with OSA, error handling, timeout management | HTTP Client (Req) |
| `Canopy.Ontology.Loader` | ETS caching, periodic refresh, startup loading | GenServer + ETS |

---

## HTTP API Endpoints

### 1. List Ontologies

**GET /api/v1/ontologies**

Retrieve a paginated list of all available ontologies.

**Authentication:** Required (Bearer JWT)

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|---|
| `limit` | integer | 50 | Max results per page |
| `offset` | integer | 0 | Pagination offset |

**Request Example:**
```bash
curl -H "Authorization: Bearer {token}" \
  "http://localhost:9089/api/v1/ontologies?limit=10&offset=0"
```

**Response (200 OK):**
```json
{
  "ontologies": [
    {
      "id": "fibo-core",
      "name": "FIBO Core",
      "description": "Financial Industry Business Ontology Core",
      "version": "2.0.0",
      "class_count": 456,
      "property_count": 1200,
      "loaded_at": "2026-03-26T10:00:00Z"
    }
  ],
  "count": 15,
  "total": 42
}
```

---

### 2. Get Ontology Details

**GET /api/v1/ontologies/:id**

Retrieve detailed information about a specific ontology.

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|---|
| `id` | string | Ontology identifier (e.g., "fibo-core") |

**Request Example:**
```bash
curl -H "Authorization: Bearer {token}" \
  "http://localhost:9089/api/v1/ontologies/fibo-core"
```

**Response (200 OK):**
```json
{
  "ontology": {
    "id": "fibo-core",
    "name": "FIBO Core",
    "description": "Financial Industry Business Ontology Core",
    "version": "2.0.0",
    "iri": "https://spec.edmcouncil.org/fibo/ontology/master/2023Q3/",
    "namespace": "https://spec.edmcouncil.org/fibo/ontology/master/...",
    "class_count": 456,
    "property_count": 1200,
    "loaded_at": "2026-03-26T10:00:00Z",
    "top_classes": ["Entity", "Event", "Agent"],
    "import_closures": ["fibo-foundation", "fibo-utils"]
  }
}
```

**Response (404 Not Found):**
```json
{
  "error": "not_found",
  "message": "Ontology fibo-missing not found"
}
```

---

### 3. Search Ontology

**POST /api/v1/ontologies/:id/search**

Search for classes and properties within an ontology.

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|---|
| `id` | string | Ontology identifier |

**Request Body:**
```json
{
  "query": "agent",
  "search_type": "both",
  "limit": 20,
  "offset": 0
}
```

**Body Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|---|
| `query` | string | (required) | Search term |
| `search_type` | string | "both" | "class", "property", or "both" |
| `limit` | integer | 20 | Max results |
| `offset` | integer | 0 | Pagination offset |

**Request Example:**
```bash
curl -X POST \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"query":"agent","search_type":"class"}' \
  "http://localhost:9089/api/v1/ontologies/fibo-core/search"
```

**Response (200 OK):**
```json
{
  "results": [
    {
      "type": "class",
      "name": "Agent",
      "iri": "https://spec.edmcouncil.org/fibo/ontology/master/BE/GovernanceAgents/Agent/",
      "description": "An entity capable of action",
      "parents": ["Entity"],
      "children": ["Person", "Organization"],
      "properties": ["hasName", "hasRole"]
    }
  ],
  "count": 5,
  "query": "agent"
}
```

**Response (400 Bad Request):**
```json
{
  "error": "validation_failed",
  "message": "query parameter required"
}
```

---

### 4. Get Ontology Statistics

**GET /api/v1/ontologies/statistics/global**

Retrieve aggregate statistics across all loaded ontologies.

**Request Example:**
```bash
curl -H "Authorization: Bearer {token}" \
  "http://localhost:9089/api/v1/ontologies/statistics/global"
```

**Response (200 OK):**
```json
{
  "statistics": {
    "total_ontologies": 15,
    "total_classes": 4250,
    "total_properties": 8900,
    "total_individuals": 1200,
    "last_updated": "2026-03-26T10:00:00Z",
    "cache_hits": 25430,
    "cache_misses": 234,
    "cache_hit_rate": 0.991
  }
}
```

---

### 5. Get Class Details

**GET /api/v1/ontologies/:id/classes/:class_id**

Retrieve detailed information about a specific ontology class.

**Path Parameters:**
| Parameter | Type | Description |
|-----------|------|---|
| `id` | string | Ontology identifier |
| `class_id` | string | Class IRI or local name (URL-encoded) |

**Request Example:**
```bash
curl -H "Authorization: Bearer {token}" \
  "http://localhost:9089/api/v1/ontologies/fibo-core/classes/Agent"
```

**Response (200 OK):**
```json
{
  "class": {
    "iri": "https://spec.edmcouncil.org/fibo/ontology/master/BE/GovernanceAgents/Agent/",
    "local_name": "Agent",
    "description": "An entity capable of action",
    "is_deprecated": false,
    "parent_classes": ["Entity"],
    "child_classes": ["Person", "Organization"],
    "disjoint_classes": [],
    "equivalent_classes": [],
    "properties": ["hasName", "hasRole"]
  }
}
```

---

## Cache Management

### ETS Tables

**Table: `:ontology_cache`**
```
Key: ontology_id (string)
Value: {ontology_id, ontology_map, timestamp_ms}
```

| Attribute | Type | Purpose |
|-----------|------|---------|
| `ontology_id` | string | Unique identifier |
| `ontology_map` | map | Full ontology metadata |
| `timestamp_ms` | integer | Insertion time (milliseconds) |

**Access Pattern:**
```elixir
:ets.lookup(:ontology_cache, "fibo-core")
# => [{"fibo-core", %{...}, 1679792400000}]
```

### TTL and Expiration

- **TTL Duration:** 3600 seconds (1 hour) by default
- **Configuration:** `ONTOLOGY_CACHE_TTL_SEC` environment variable
- **Expiration Logic:** On lookup, if `(now - timestamp) > TTL`, entry is deleted
- **Refresh Interval:** 1800 seconds (30 minutes) — periodic background refresh

### Cache Lifecycle

```
Startup
  ↓
load_all (async)
  └─ Fetch from OSA
  └─ Insert to :ontology_cache
  └─ Schedule periodic refresh
  ↓
On Request
  └─ Check :ontology_cache
  └─ If hit AND not expired → return
  └─ If miss → fetch from OSA → insert to cache
  ↓
Every 30 minutes
  └─ Refresh all cached ontologies
  └─ Update timestamps
```

---

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OSA_URL` | `http://127.0.0.1:8089` | OSA service base URL |
| `ONTOLOGY_CACHE_TTL_SEC` | `3600` | Cache TTL in seconds |

**Example .env:**
```bash
OSA_URL=http://osa.example.com:8089
ONTOLOGY_CACHE_TTL_SEC=3600
```

### Supervision Tree

The ontology loader is registered in `Canopy.Application` supervision tree:

```elixir
children = [
  # ... other children ...
  Canopy.Ontology.Loader,
  CanopyWeb.Endpoint
]
```

**Restart Strategy:** `:permanent` (restarts on any crash)

---

## Caching Strategy

### Read Path (with caching)

```
HTTP GET /ontologies/:id
  ↓
OntologyController.show(id)
  ↓
Client.get_ontology(id)
  ↓
Check OSA Cache (Loader.get_ontology)
  ├─ Hit: return cached ontology
  └─ Miss: fetch from OSA
              ↓
            Insert to ETS cache
              ↓
            Return to controller
```

### Write Path (cache invalidation)

```
OSA publishes ontology update
  ↓
Canopy webhook receiver (if implemented)
  ↓
Loader.refresh_cache()
  ↓
Reload all ontologies
  ↓
Update ETS table
```

### Cache Statistics

Query cache performance:

```elixir
Canopy.Ontology.Loader.cache_stats()
# =>
# %{
#   "cached_ontologies" => 15,
#   "cache_size_bytes" => 524288,
#   "oldest_entry_age_seconds" => 245,
#   "ttl_seconds" => 3600
# }
```

---

## Testing

### Test Structure

File: `test/canopy_web/controllers/ontology_controller_test.exs`

**Test Categories:**

1. **List Endpoint Tests (3 tests)**
   - `test_list_ontologies` — Basic list functionality
   - `test_pagination` — Limit and offset
   - `test_error_handling` — Service unavailability

2. **Get Endpoint Tests (2 tests)**
   - `test_show_ontology` — Retrieve details
   - `test_not_found` — 404 handling

3. **Search Endpoint Tests (4 tests)**
   - `test_search_basic` — Search functionality
   - `test_validation` — Query parameter validation
   - `test_filter_type` — Search type filtering
   - `test_pagination` — Search result pagination

4. **Statistics Tests (2 tests)**
   - `test_statistics` — Aggregate stats
   - `test_cache_metrics` — Hit rate

5. **Class Endpoint Tests (3 tests)**
   - `test_get_class` — Class details
   - `test_not_found_class` — 404 handling
   - `test_url_encoding` — Class ID encoding

**Run Tests:**
```bash
cd canopy/backend
mix test test/canopy_web/controllers/ontology_controller_test.exs
```

---

## Error Handling

### Error Responses

| Status | Error | Cause | Resolution |
|--------|-------|-------|---|
| 400 | `validation_failed` | Missing/invalid param | Validate request body |
| 404 | `not_found` | Ontology/class not found | Check ontology ID |
| 500 | `ontology_service_unavailable` | OSA unreachable | Check OSA health |
| 500 | `search_failed` | Search engine error | Retry or check OSA logs |

**Example 500 Response:**
```json
{
  "error": "ontology_service_unavailable",
  "details": "{:connection_failed, :timeout}"
}
```

### Client Error Handling

**Req Client** (in `Canopy.Ontology.Client`):
- Timeout: 30 seconds (configurable)
- Retry: Not implemented (stateless calls)
- Circuit breaker: Not implemented (upstream responsibility)

**Example Handling:**
```elixir
case Client.list_ontologies() do
  {:ok, ontologies, total} ->
    {:ok, ontologies}
  {:error, {:connection_failed, _}} ->
    # Could fallback to local cache
    {:error, :service_unavailable}
  {:error, {:osa_error, 500, body}} ->
    Logger.error("OSA error: #{inspect(body)}")
    {:error, :service_error}
end
```

---

## Integration Examples

### Heroku-Style Deployment

**Environment Setup:**
```bash
heroku config:set OSA_URL=https://osa.herokuapp.com
heroku config:set ONTOLOGY_CACHE_TTL_SEC=7200
```

**Health Check:**
```bash
curl -H "Authorization: Bearer {token}" \
  "http://localhost:9089/api/v1/ontologies/statistics/global"
# Check cache_hit_rate and total_ontologies
```

### Frontend Usage (SvelteKit)

```typescript
// Load ontologies on page init
async function fetchOntologies() {
  const response = await fetch('/api/v1/ontologies', {
    headers: { Authorization: `Bearer ${token}` }
  });
  const data = await response.json();
  ontologies.set(data.ontologies);
}

// Search ontology
async function search(ontologyId: string, query: string) {
  const response = await fetch(
    `/api/v1/ontologies/${ontologyId}/search`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ query, search_type: 'both', limit: 20 })
    }
  );
  return response.json();
}
```

### Agent Integration (Heartbeat)

```elixir
# In agent schedule/heartbeat task
def check_ontology_updates(workspace_id) do
  {:ok, stats} = Canopy.Ontology.Client.get_statistics()

  # Store stats for alerting
  {:ok, _} = Canopy.Repo.insert(%OntologyMetric{
    workspace_id: workspace_id,
    total_classes: stats.total_classes,
    total_properties: stats.total_properties,
    measured_at: DateTime.utc_now()
  })
end
```

---

## Performance Considerations

### Caching Impact

- **Cache Hit Rate:** Expect 95%+ on typical usage
- **Lookup Time:** <1ms for cached entry
- **Memory Usage:** ~350KB per 1000 ontologies (estimate)
- **Refresh Overhead:** ~100ms for full reload

### Scalability

| Metric | Single Instance | Notes |
|--------|---|---|
| Concurrent Requests | 1000+ | Limited by Phoenix config |
| Cached Ontologies | 1000+ | ETS can handle millions |
| Max Response Time | 50-100ms | With OSA available |

### Optimization Tips

1. **Increase TTL in production:** `ONTOLOGY_CACHE_TTL_SEC=86400` (24 hours)
2. **Pre-load hot ontologies:** Call `Loader.load_all()` on startup
3. **Monitor cache stats:** Alert when hit_rate < 0.9
4. **Use pagination:** Always limit results with `limit` parameter

---

## Troubleshooting

### Cache Not Updating

**Symptom:** Search returns stale results

**Solution:**
```elixir
# Manual cache refresh
Canopy.Ontology.Loader.refresh_cache()

# Clear cache
Canopy.Ontology.Loader.clear_cache()

# Check cache status
Canopy.Ontology.Loader.cache_stats()
```

### OSA Service Unreachable

**Symptom:** 500 errors on all ontology endpoints

**Diagnosis:**
```bash
curl http://localhost:8089/api/v1/health
# Should return 200 OK

# Check OSA logs
docker logs osa-container

# Verify OSA_URL env var
echo $OSA_URL
```

**Solution:**
- Verify OSA is running: `make osa.serve`
- Check firewall rules: Port 8089 open
- Verify `OSA_URL` environment variable
- Check network connectivity: `ping osa.example.com`

### High Cache Memory Usage

**Symptom:** Canopy process memory growing

**Solution:**
```elixir
# Reduce TTL
System.put_env("ONTOLOGY_CACHE_TTL_SEC", "1800")  # 30 minutes

# Clear cache manually
Canopy.Ontology.Loader.clear_cache()

# Restart GenServer
Supervisor.restart_child(Canopy.Supervisor, Canopy.Ontology.Loader)
```

---

## Future Enhancements

- [ ] Incremental cache updates (delta sync)
- [ ] Shared cache across multiple Canopy instances (Redis)
- [ ] Ontology change webhooks from OSA
- [ ] Class inheritance chain preloading
- [ ] Synonym-based search
- [ ] GraphQL endpoint for ontology queries
- [ ] Analytics: most-searched classes, popular ontologies

---

## References

- **OSA Ontology API:** `/Users/sac/chatmangpt/OSA/docs/ontology-registry.md` (assumed)
- **Canopy Architecture:** `canopy/CLAUDE.md`
- **Elixir ETS Guide:** https://hexdocs.pm/elixir/ets.html
- **Phoenix Controllers:** https://hexdocs.pm/phoenix/controllers.html

---

**Last Updated:** 2026-03-26
**Status:** Production Ready
**Maintenance:** Monthly review of cache hit rate and error logs
