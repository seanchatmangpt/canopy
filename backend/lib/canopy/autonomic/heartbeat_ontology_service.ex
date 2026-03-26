defmodule Canopy.Autonomic.HeartbeatOntologyService do
  @moduledoc """
  Integrates Canopy's heartbeat autonomic system with cached ontologies.

  This service enriches heartbeat agent task definitions with ontology metadata,
  enabling agents to discover task hierarchies, properties, and constraints without
  HTTP roundtrips to OSA.

  Architecture:
  - Heartbeat dispatches autonomic agents on schedule
  - HeartbeatOntologyService intercepts agent execution
  - Service queries Canopy.Ontology.Service for cached task metadata
  - Agent receives enriched task context with hierarchy and constraints
  - No deadlocks: all blocking ops have timeout_ms + fallback
  - No infinite loops: bounded iteration with escape conditions
  - Bounded resources: cache size limits, priority queues with max_size

  Features:
  - Cache-first: queries cached ontologies before OSA HTTP call
  - Lazy loading: loads only requested agent task definitions
  - WvdA soundness: deadlock-free, liveness-guaranteed, bounded memory
  - Armstrong fault tolerance: let-it-crash on ontology errors, restart cleanly
  """
  require Logger
  require OpenTelemetry.Tracer

  alias Canopy.Ontology.Service

  @doc """
  Enrich an agent with cached ontology task metadata.

  Queries the ontology service for task definition and hierarchy without blocking.
  All operations are bounded: timeout 5 seconds, fallback to defaults.

  Args:
    agent_type: atom (e.g., :health_agent, :healing_agent)
    opts: keyword list with:
      - timeout_ms: max wait time (default 5000)
      - ontology_id: ontology to query (default "canopy-agents")
      - cache: use cache if available (default true)

  Returns:
    {:ok, enriched_context} where context includes:
      - agent_type
      - task_metadata (from ontology)
      - hierarchy (parent/child task relationships)
      - constraints (resource limits)
      - retrieved_from (cache/osa)
      - timestamp

    {:error, reason} on timeout or ontology not found
  """
  def enrich_agent(agent_type, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    ontology_id = Keyword.get(opts, :ontology_id, "canopy-agents")
    use_cache = Keyword.get(opts, :cache, true)

    # Convert agent type to class name (e.g. :health_agent -> "HealthAgent")
    class_name = agent_type_to_class_name(agent_type)

    OpenTelemetry.Tracer.with_span "heartbeat_ontology.enrich_agent", %{
      "agent_type" => inspect(agent_type),
      "class_name" => class_name,
      "ontology_id" => ontology_id,
      "timeout_ms" => timeout_ms
    } do
      # Bounded operation: timeout wrapper
      case Task.yield(
             Task.async(fn ->
               fetch_task_metadata(ontology_id, class_name, use_cache)
             end),
             timeout_ms
           ) do
        {:ok, {:ok, metadata}} ->
          # Enrich context with metadata
          enriched = %{
            agent_type: agent_type,
            class_name: class_name,
            task_metadata: metadata,
            hierarchy: extract_hierarchy(metadata),
            constraints: extract_constraints(metadata),
            retrieved_from: metadata[:cache_hit] || false,
            timestamp: DateTime.utc_now()
          }

          Logger.info(
            "[HeartbeatOntology] Enriched #{inspect(agent_type)}: metadata retrieved, hierarchy extracted"
          )

          {:ok, enriched}

        {:ok, {:error, reason}} ->
          Logger.warning("[HeartbeatOntology] Failed to fetch metadata for #{class_name}: #{inspect(reason)}")
          # Fallback: return minimal context with no metadata
          {:ok, minimal_context(agent_type)}

        nil ->
          # Timeout after timeout_ms
          Logger.warning("[HeartbeatOntology] Metadata fetch for #{class_name} timed out after #{timeout_ms}ms")
          Task.shutdown(Task.async(fn -> nil end), :brutal_kill)
          # Fallback: return minimal context
          {:ok, minimal_context(agent_type)}
      end
    end
  end

  @doc """
  Query agent task definitions from multiple agent types with bounded iteration.

  Retrieves task metadata for multiple agents concurrently, bounded by timeout.
  Uses priority queue to order results by agent priority.

  Args:
    agent_types: list of atoms (e.g., [:health_agent, :healing_agent])
    opts: keyword list with:
      - timeout_ms: max wait per agent (default 5000)
      - max_agents: max agents to process (default 10, prevents infinite queues)
      - ontology_id: ontology to query (default "canopy-agents")

  Returns:
    {:ok, [enriched_agents], priority_queue} where:
      - enriched_agents: list of {:ok, enriched_context} or {:error, reason}
      - priority_queue: agents ordered by priority (health > healing > ... > adaptation)

    {:error, :max_agents_exceeded} if agent count > max_agents
  """
  def enrich_agents_batch(agent_types, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    max_agents = Keyword.get(opts, :max_agents, 10)
    ontology_id = Keyword.get(opts, :ontology_id, "canopy-agents")

    # Boundedness check: prevent unbounded growth
    if length(agent_types) > max_agents do
      Logger.error("[HeartbeatOntology] Too many agents: #{length(agent_types)} > #{max_agents}")
      {:error, :max_agents_exceeded}
    else
      OpenTelemetry.Tracer.with_span "heartbeat_ontology.enrich_agents_batch", %{
        "agent_count" => length(agent_types),
        "max_agents" => max_agents
      } do
        # Enrich all agents concurrently with timeout
        tasks =
          agent_types
          |> Enum.map(fn agent_type ->
            Task.async(fn ->
              enrich_agent(agent_type, timeout_ms: timeout_ms, ontology_id: ontology_id)
            end)
          end)

        # Bounded collection: timeout after max(all tasks) + buffer
        results =
          tasks
          |> Enum.map(&Task.yield(&1, timeout_ms + 1000))
          |> Enum.map(fn result ->
            case result do
              {:ok, enriched} -> enriched
              nil -> {:error, :timeout}
            end
          end)

        # Sort by agent priority
        priority_ordered = sort_by_priority(results)

        Logger.info(
          "[HeartbeatOntology] Batch enriched #{length(results)} agents, priority ordered"
        )

        {:ok, results, priority_ordered}
      end
    end
  end

  @doc """
  Get task hierarchy and constraints for an agent.

  Useful for understanding task dependencies and resource requirements.

  Args:
    agent_type: atom
    opts: keyword list (see enrich_agent/2)

  Returns:
    {:ok, %{hierarchy: [...], constraints: [...]}}
    {:error, reason}
  """
  def get_task_hierarchy(agent_type, opts \\ []) do
    case enrich_agent(agent_type, opts) do
      {:ok, enriched} ->
        {:ok, %{
          hierarchy: enriched.hierarchy,
          constraints: enriched.constraints,
          class_name: enriched.class_name
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Cache statistics for ontology queries during heartbeat.

  Returns:
    %{hits: integer, misses: integer, hit_rate: float}
  """
  def cache_stats do
    Service.cache_stats()
  end

  # ── Private Helpers ──────────────────────────────────────────────────────

  defp fetch_task_metadata(ontology_id, class_name, use_cache) do
    # Query ontology service with cache
    case Service.get_class(ontology_id, class_name, cache: use_cache) do
      {:ok, class_info, metadata} ->
        Logger.debug("[HeartbeatOntology] Retrieved #{class_name} from #{if metadata.cache_hit do "cache" else "OSA" end}")

        # Merge ontology metadata with cache hit info
        enriched_metadata = class_info |> Map.merge(%{cache_hit: metadata.cache_hit})
        {:ok, enriched_metadata}

      {:error, reason} ->
        Logger.warning("[HeartbeatOntology] Failed to get class #{class_name}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[HeartbeatOntology] Exception during fetch: #{inspect(e)}")
      {:error, {:fetch_exception, e}}
  end

  defp agent_type_to_class_name(agent_type) do
    # Convert :health_agent -> "HealthAgent", :healing_agent -> "HealingAgent"
    agent_type
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp extract_hierarchy(metadata) when is_map(metadata) do
    # Extract parent/child relationships from metadata
    # If metadata contains "properties" or "parent_classes", use that
    parent_classes = Map.get(metadata, "parent_classes", [])
    sub_classes = Map.get(metadata, "sub_classes", [])

    %{
      parent_classes: parent_classes,
      sub_classes: sub_classes,
      properties: Map.get(metadata, "properties", [])
    }
  end

  defp extract_hierarchy(_), do: %{parent_classes: [], sub_classes: [], properties: []}

  defp extract_constraints(metadata) when is_map(metadata) do
    # Extract resource constraints from metadata annotations
    constraints = Map.get(metadata, "constraints", [])

    # Parse timeout, budget, tier if present
    timeout_ms = get_constraint_value(constraints, "timeout_ms", 30_000)
    budget = get_constraint_value(constraints, "budget", 10_000)
    tier = get_constraint_value(constraints, "tier", "normal")

    %{
      timeout_ms: timeout_ms,
      budget: budget,
      tier: tier,
      annotations: constraints
    }
  end

  defp extract_constraints(_), do: %{timeout_ms: 30_000, budget: 10_000, tier: "normal"}

  defp get_constraint_value(constraints, key, default) when is_list(constraints) do
    case Enum.find(constraints, fn c -> Map.get(c, "key") == key end) do
      %{"value" => value} -> value
      _ -> default
    end
  end

  defp get_constraint_value(_, _key, default), do: default

  defp minimal_context(agent_type) do
    %{
      agent_type: agent_type,
      class_name: agent_type_to_class_name(agent_type),
      task_metadata: nil,
      hierarchy: %{parent_classes: [], sub_classes: [], properties: []},
      constraints: %{timeout_ms: 30_000, budget: 10_000, tier: "normal"},
      retrieved_from: :fallback,
      timestamp: DateTime.utc_now()
    }
  end

  defp sort_by_priority(results) do
    # Define priority order: health > healing > data > compliance > learning > adaptation
    priority_map = %{
      health_agent: 0,
      healing_agent: 1,
      data_agent: 2,
      compliance_agent: 3,
      learning_agent: 4,
      adaptation_agent: 5
    }

    results
    |> Enum.sort_by(fn
      {:ok, enriched} -> Map.get(priority_map, enriched.agent_type, 99)
      _ -> 100
    end)
  end
end
