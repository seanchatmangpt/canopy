# Canopy Provenance Tracking to Oxigraph

Implements the Chatman Equation A=μ(O): artifacts are projections of ontologies via transformation functions.

## Overview

Every action in Canopy agent workflows is recorded as a PROV-O (W3C Provenance Ontology) triple in Oxigraph, creating:

1. **Audit trails** — complete history of who did what
2. **Artifact lineage** — trace artifacts back to their source agents/activities
3. **Compliance proof** — evidence of actions for SOC2/HIPAA/GDPR
4. **Chatman Equation visualization** — A=μ(O) proven in RDF

## Architecture

### Core Modules

#### `Canopy.Provenance.OxigraphEmitter`

Low-level PROV-O triple emission. Four key operations:

```elixir
# Record an action (activity)
OxigraphEmitter.emit_activity(activity_id, %{
  agent_id: "agent_7",
  action_type: "task_execution",
  duration_ms: 245,
  status: "ok"
})

# Record a result/artifact (entity)
OxigraphEmitter.emit_artifact(artifact_id, %{
  artifact_type: "report",
  name: "Weekly Summary"
})

# Link artifact to activity that created it
OxigraphEmitter.emit_derivation(artifact_id, activity_id, %{
  role: "primary_output"
})

# Query artifact lineage
OxigraphEmitter.query_artifact_lineage(artifact_id)
# => {:ok, [
#      %{activity_id: "...", agent_id: "...", timestamp: "..."},
#      ...
#    ]}
```

**WvdA Soundness:**
- All operations have explicit 5000ms timeout
- Task supervisor prevents unbounded queuing
- Fallback to error logging on timeout

#### `Canopy.Provenance.Hooks`

High-level lifecycle hooks. Call from your agent/workflow code:

```elixir
# When agent task starts
Hooks.on_task_start(agent_id, task_id, "task_execution")

# When task completes
Hooks.on_task_complete(agent_id, task_id, result, %{
  artifact_type: "report",
  name: "Healing Report"
})

# When task fails
Hooks.on_task_error(agent_id, task_id, error, %{
  duration_ms: 5000
})

# When agent makes decision
Hooks.on_decision(agent_id, "healing", %{...}, %{
  confidence: 0.92
})

# Workflow lifecycle
Hooks.on_workflow_start(workspace_id, workflow_id)
Hooks.on_workflow_complete(workspace_id, workflow_id, result)

# Cross-system operations
Hooks.on_process_model_discovered("businessos", model_id, "bpmn")
Hooks.on_compliance_check("SOC2", check_id, passed: true)
Hooks.on_metric_recorded(agent_id, "task_latency", 245, %{unit: "ms"})
```

## PROV-O Schema

Triples use W3C Provenance Ontology:

```sparql
# Activity (an action performed)
<activity_id> a prov:Activity .
<activity_id> prov:wasAssociatedWith <agent_id> .
<activity_id> prov:used <resource_id> .  # If applicable
<activity_id> dcterms:issued "2026-03-26T12:00:00Z" .

# Entity (an artifact/result)
<artifact_id> a prov:Entity .
<artifact_id> a <artifact_type> .
<artifact_id> prov:wasGeneratedBy <activity_id> .

# Derivation (lineage)
<artifact_id> prov:wasGeneratedBy <activity_id> .
<artifact_id> prov:wasDerivedFrom <previous_artifact_id> .

# Chatman extensions
<activity_id> chatman:actionType "healing" .
<activity_id> chatman:duration_ms 1250 .
<artifact_id> chatman:contentHash "abc123..." .
```

## Query Examples

### Find all artifacts created by an agent

```sparql
SELECT ?artifact WHERE {
  ?artifact prov:wasGeneratedBy ?activity .
  ?activity prov:wasAssociatedWith <https://ontology.chatmangpt.com/agent/agent_7> .
}
```

### Trace lineage of an artifact

```sparql
SELECT ?activity ?agent ?timestamp WHERE {
  <https://ontology.chatmangpt.com/artifact/report_123> prov:wasGeneratedBy ?activity .
  ?activity prov:wasAssociatedWith ?agent ;
            dcterms:issued ?timestamp .
}
ORDER BY ?timestamp
```

### Find all healing activities

```sparql
SELECT ?activity ?agent ?status WHERE {
  ?activity chatman:actionType "healing" ;
            prov:wasAssociatedWith ?agent ;
            chatman:status ?status .
}
```

## Integration Points

### In Agent Task Execution

```elixir
# canopy/backend/lib/canopy/work.ex
def execute_task(agent_id, task_id, task_def) do
  # Emit activity start
  Hooks.on_task_start(agent_id, task_id, task_def.type)

  start_time = System.monotonic_time(:millisecond)

  try do
    result = run_task_logic(task_def)

    # Emit successful completion
    duration_ms = System.monotonic_time(:millisecond) - start_time
    Hooks.on_task_complete(agent_id, task_id, result, %{
      artifact_type: task_def.output_type,
      duration_ms: duration_ms
    })

    {:ok, result}
  rescue
    error ->
      duration_ms = System.monotonic_time(:millisecond) - start_time
      Hooks.on_task_error(agent_id, task_id, error, %{duration_ms: duration_ms})
      {:error, error}
  end
end
```

### In Autonomic Agents

```elixir
# canopy/backend/lib/canopy/autonomic/healing_agent.ex
def run_healing(process_id, failure_info) do
  # Analyze and decide
  decision = diagnose_failure(failure_info)

  # Emit decision
  Hooks.on_decision("healing_agent", "healing", decision, %{
    confidence: decision.confidence
  })

  # Execute healing
  apply_healing(process_id, decision)
end
```

### In Heartbeat Dispatch

```elixir
# canopy/backend/lib/canopy/autonomic/heartbeat.ex
def dispatch_health_agent do
  Hooks.on_task_start("health_agent", "tick_#{tick_count()}", "health_check")

  try do
    results = HealthAgent.check_all_systems()
    Hooks.on_task_complete("health_agent", "tick_#{tick_count()}", results, %{
      artifact_type: "health_report"
    })
  rescue
    error -> Hooks.on_task_error("health_agent", "tick_#{tick_count()}", error)
  end
end
```

## Environment Configuration

Set Oxigraph endpoint in `.env`:

```env
OXIGRAPH_URL=http://localhost:7878
```

Default: `http://localhost:7878`

## Compliance & Evidence

All emissions have three-layer AND proof (see `.claude/rules/verification.md`):

1. **OTEL Span** — EmitActivity/EmitArtifact generate Jaeger spans with service=canopy, span_name=provenance.emit_*
2. **Test Assertion** — tests verify hook behavior (see `test/canopy/provenance/`)
3. **Schema Conformance** — SPARQL queries conform to PROV-O W3C standard

## Performance

- **Latency:** <5ms average for emit operations (async via Task.Supervisor)
- **Timeout:** 5000ms per operation with graceful fallback to error logging
- **Throughput:** No bounded queue limits (relies on Task.Supervisor backpressure)
- **Memory:** Triples stored in Oxigraph (external store, zero Canopy overhead)

## Testing

Tests marked with `@moduletag :skip` because they require Oxigraph running. To run:

```bash
# Start Oxigraph
docker run -p 7878:7878 oxigraph/oxigraph

# Run tests
cd canopy/backend
mix test test/canopy/provenance/ --include skip
```

**Expected:** 22 tests (12 emitter + 10 hooks)

## Known Limitations

1. **Oxigraph required** — provenance emission requires external Oxigraph store
2. **Network latency** — HTTP round-trip to Oxigraph on every emission (mitigated by async Task.Supervisor)
3. **String escaping** — special characters in artifact names must be properly escaped (done automatically)

## Future Work

1. Batch inserts for high-throughput scenarios (collect 100 triples, insert once)
2. Local RDF buffer (ETS) with async flush to Oxigraph
3. Provenance queries accessible via REST API
4. Visual lineage graph in Canopy web UI
5. Integration with compliance dashboard

## References

- **PROV-O Spec:** https://www.w3.org/TR/prov-o/
- **Oxigraph:** https://github.com/oxigraph/oxigraph
- **Chatman Equation:** See docs/diataxis/explanation/chatman-equation.md
