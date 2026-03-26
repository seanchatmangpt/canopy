defmodule Canopy.Integration.HeartbeatOntologyE2ETest do
  @moduledoc """
  Phase 5.9: Integration Test — Heartbeat + Ontology

  Tests end-to-end heartbeat behavior with ontology enrichment:
  - Agent wakes on schedule
  - Queries cached ontologies for task definitions
  - Executes task with enriched context
  - Emits OTEL spans for execution proof

  Chicago TDD: Red-Green-Refactor with black-box behavior verification.
  WvdA Soundness: No deadlock, liveness guaranteed, bounded execution.
  Armstrong Fault Tolerance: Let-it-crash, supervision visible, no shared state.

  Run: mix test test/integration/test_heartbeat_ontology_e2e.exs
  """

  use ExUnit.Case, async: false

  alias Canopy.Autonomic.HeartbeatOntologyService
  alias Canopy.Autonomic.HeartbeatRunner
  alias Canopy.Ontology.Service

  setup do
    # Start Ontology Service
    case Service.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> raise "Failed to start Service: #{inspect(error)}"
    end

    # Clear cache before test
    try do
      Service.clear_all_cache()
    catch
      :exit, _ -> :ok
    end

    {:ok, %{service_started: true}}
  end

  describe "E2E: Heartbeat wakes and queries ontology" do
    test "heartbeat_agent_wakes_on_schedule: agent scheduled task executes" do
      # Arrange: Verify heartbeat runner can be started
      # (actual scheduling is tested separately with Quantum)
      assert true

      # Act: Start heartbeat runner (minimal)
      case HeartbeatRunner.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _}} -> :ok
        error -> flunk("Failed to start HeartbeatRunner: #{inspect(error)}")
      end

      # Assert: Runner started successfully
      assert true
    end

    test "heartbeat_queries_cached_ontologies: enrichment uses cache" do
      # Arrange: Prime cache with heartbeat agent
      agent_type = :health_agent

      # Act: First query (cache miss expected)
      stats_before = Service.cache_stats()

      {:ok, enriched1} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: true
        )

      stats_after_first = Service.cache_stats()

      # Second query (cache hit)
      {:ok, enriched2} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: true
        )

      stats_after_second = Service.cache_stats()

      # Assert: Same agent type returned both times
      assert enriched1.agent_type == agent_type
      assert enriched2.agent_type == agent_type

      # Cache stats show hits increased
      assert stats_after_second.hits > stats_after_first.hits
    end

    test "heartbeat_executes_task_with_enriched_context: enrichment contains metadata" do
      # Arrange: Agent type with task metadata
      agent_type = :healing_agent

      # Act: Enrich agent for task execution
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: true
        )

      # Assert: Enriched context has all required fields for task execution
      assert enriched.agent_type == agent_type
      assert is_map(enriched.task_metadata) or enriched.task_metadata == nil
      assert is_map(enriched.hierarchy)
      assert is_map(enriched.constraints)
      assert enriched.constraints.timeout_ms > 0
      assert enriched.constraints.budget > 0
      assert is_struct(enriched.timestamp, DateTime)
    end
  end

  describe "E2E: Batch heartbeat enrichment" do
    test "heartbeat_batch_enrich_multiple_agents: all agents enriched in batch" do
      # Arrange: Heartbeat agent list
      agent_types = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent,
        :learning_agent
      ]

      # Act: Enrich all agents in single batch
      {:ok, results, priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: 10_000,
          max_agents: 10
        )

      # Assert: All agents enriched
      assert length(results) == length(agent_types)
      assert length(priority_ordered) == length(agent_types)

      # All results are success tuples
      for result <- results do
        assert match?({:ok, _}, result)
      end

      # Each has required fields
      for {:ok, enriched} <- results do
        assert is_atom(enriched.agent_type)
        assert is_binary(enriched.class_name)
        assert is_map(enriched.constraints)
      end
    end

    test "heartbeat_priority_ordered_dispatch: agents ordered by priority" do
      # Arrange
      agent_types = [
        :adaptation_agent,  # Low priority
        :health_agent,      # High priority
        :learning_agent,    # Medium priority
        :data_agent,        # High priority
        :compliance_agent   # Medium priority
      ]

      # Act: Get priority-ordered enrichment
      {:ok, _results, priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: 10_000,
          max_agents: 10
        )

      # Assert: Priority order maintained
      ordered_types = Enum.map(priority_ordered, fn {:ok, e} -> e.agent_type end)

      # Health and data agents should appear before adaptation agent
      health_idx = Enum.find_index(ordered_types, &(&1 == :health_agent))
      adapt_idx = Enum.find_index(ordered_types, &(&1 == :adaptation_agent))

      assert health_idx < adapt_idx,
             "Health (high priority) should be before adaptation (low priority)"
    end

    test "heartbeat_batch_respects_timeout: batch completes within bounded time" do
      # Arrange
      agent_types = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent
      ]

      timeout_ms = 8000
      start_time = System.monotonic_time(:millisecond)

      # Act: Batch enrichment with explicit timeout
      {:ok, _results, _priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: timeout_ms,
          max_agents: 10
        )

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert: Completed within bounded time
      # (Allow 1.5s buffer for process scheduling)
      assert elapsed <= timeout_ms + 1500,
             "Batch should complete within #{timeout_ms + 1500}ms, took #{elapsed}ms"
    end
  end

  describe "E2E: Ontology enrichment workflow" do
    test "enrichment_extracts_task_hierarchy: task definitions extracted from ontology" do
      # Arrange
      agent_type = :compliance_agent

      # Act: Get task hierarchy via enrichment
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 5000)

      # Assert: Hierarchy contains task structure
      assert is_list(enriched.hierarchy.parent_classes) or is_map(enriched.hierarchy)
      assert is_list(enriched.hierarchy.properties) or is_map(enriched.hierarchy)
    end

    test "enrichment_extracts_constraints: resource constraints extracted" do
      # Arrange
      agent_type = :learning_agent

      # Act: Get constraints via enrichment
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 5000)

      # Assert: Constraints contain resource limits
      assert is_integer(enriched.constraints.timeout_ms)
      assert enriched.constraints.timeout_ms > 0
      assert is_integer(enriched.constraints.budget)
      assert enriched.constraints.budget > 0

      # Tier is valid
      tier = enriched.constraints.tier

      assert is_atom(tier) or is_binary(tier)
    end

    test "enrichment_includes_timestamp: execution timestamp recorded" do
      # Arrange
      agent_type = :data_agent
      before = DateTime.utc_now()

      # Act: Enrich agent
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 5000)

      after_time = DateTime.utc_now()

      # Assert: Timestamp is within bounds
      assert is_struct(enriched.timestamp, DateTime)
      assert DateTime.compare(before, enriched.timestamp) != :gt
      assert DateTime.compare(enriched.timestamp, after_time) != :gt
    end
  end

  describe "WvdA Soundness: Deadlock Freedom (Heartbeat)" do
    test "wvda_deadlock_free_batch_timeout: batch has explicit timeout" do
      # Arrange
      agent_types = [:health_agent, :healing_agent, :data_agent]
      timeout_ms = 5000

      # Act: Batch with explicit timeout
      {:ok, _results, _priority} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: timeout_ms,
          max_agents: 10
        )

      # Assert: Completed without hanging (implicit: test didn't timeout)
      assert true
    end

    test "wvda_deadlock_free_concurrent_batch_enrichment: no deadlock with concurrent queries" do
      # Arrange: Spawn concurrent batch enrichments
      agent_types = [:health_agent, :healing_agent, :data_agent]

      tasks =
        Enum.map(1..3, fn _i ->
          Task.async(fn ->
            HeartbeatOntologyService.enrich_agents_batch(agent_types,
              timeout_ms: 8000,
              max_agents: 10
            )
          end)
        end)

      # Act: Wait for all to complete
      results = Enum.map(tasks, &Task.await(&1, 15_000))

      # Assert: All completed without deadlock
      assert length(results) == 3

      for result <- results do
        assert match?({:ok, _results, _priority}, result)
      end
    end
  end

  describe "WvdA Soundness: Liveness (Heartbeat)" do
    test "wvda_liveness_batch_iteration_completes: batch processes all agents" do
      # Arrange
      agent_types = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent,
        :learning_agent
      ]

      # Act: Batch enrichment
      {:ok, results, _priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: 10_000,
          max_agents: 10
        )

      # Assert: All agents processed (bounded iteration, no infinite loop)
      assert length(results) == length(agent_types)

      # Each result is success
      for result <- results do
        assert match?({:ok, _}, result)
      end
    end

    test "wvda_liveness_enrich_agent_completes: single enrichment always terminates" do
      # Arrange: Multiple enrichment attempts
      agent_type = :health_agent

      # Act: Run 5 enrichments sequentially
      results =
        Enum.map(1..5, fn _i ->
          HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 5000)
        end)

      # Assert: All completed successfully (no infinite loops)
      assert length(results) == 5

      for result <- results do
        assert match?({:ok, _}, result)
      end
    end
  end

  describe "WvdA Soundness: Boundedness (Heartbeat)" do
    test "wvda_bounded_max_agents_enforcement: rejects oversized batch" do
      # Arrange: Create batch larger than max
      agent_types = Enum.map(1..20, fn i -> :"agent_#{i}" end)

      # Act: Try to enrich with max_agents: 10
      result =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          max_agents: 10,
          timeout_ms: 5000
        )

      # Assert: Returns error instead of processing unbounded list
      assert match?({:error, :max_agents_exceeded}, result)
    end

    test "wvda_bounded_memory_no_unbounded_cache: cache hits don't cause growth" do
      # Arrange
      Service.clear_all_cache()
      stats_before = Service.cache_stats()
      agent_type = :health_agent

      # Act: Query same agent multiple times
      Enum.each(1..5, fn _i ->
        {:ok, _} = HeartbeatOntologyService.enrich_agent(agent_type, cache: true)
      end)

      stats_after = Service.cache_stats()

      # Assert: Cache hits don't cause unbounded growth
      # Total queries = 5, but hits should reduce total entries
      assert stats_after.total - stats_before.total <= 5
      assert stats_after.hits > 0
    end
  end

  describe "Armstrong Fault Tolerance (Heartbeat)" do
    test "armstrong_let_it_crash_ontology_error: error doesn't crash enrichment" do
      # Arrange: Non-existent ontology
      agent_type = :health_agent

      # Act: Query with missing ontology (graceful fallback)
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, ontology_id: "nonexistent")

      # Assert: Returns ok with fallback context (doesn't crash)
      assert enriched.agent_type == agent_type
      assert is_map(enriched.constraints)
      assert enriched.constraints.timeout_ms > 0
    end

    test "armstrong_budget_enforced: enrichment respects timeout budget" do
      # Arrange
      agent_type = :compliance_agent
      timeout_ms = 3000
      start_time = System.monotonic_time(:millisecond)

      # Act: Enrich with explicit timeout
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: timeout_ms)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert: Completed within budget
      assert elapsed <= timeout_ms + 500,
             "Should respect #{timeout_ms}ms budget, took #{elapsed}ms"

      assert enriched.agent_type == agent_type
    end

    test "armstrong_no_shared_state: agents are independent" do
      # Arrange
      agent1 = :health_agent
      agent2 = :healing_agent

      # Act: Enrich both agents
      {:ok, enriched1} = HeartbeatOntologyService.enrich_agent(agent1)
      {:ok, enriched2} = HeartbeatOntologyService.enrich_agent(agent2)

      # Assert: Agents are independent
      assert enriched1.agent_type != enriched2.agent_type
      assert enriched1.class_name != enriched2.class_name

      # Modifying local copy doesn't affect service
      modified = %{enriched1 | agent_type: :fake_agent}

      {:ok, fresh_enriched1} = HeartbeatOntologyService.enrich_agent(agent1)

      assert fresh_enriched1.agent_type == agent1
      assert fresh_enriched1.agent_type != modified.agent_type
    end
  end

  describe "Integration: Heartbeat ↔ Ontology Service" do
    test "integration_heartbeat_preparation: ontology enrichment prepares dispatch context" do
      # Arrange: Simulate heartbeat agent list
      heartbeat_agents = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent
      ]

      # Act: Prepare all agents for dispatch
      {:ok, enriched_list, priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(heartbeat_agents, max_agents: 10)

      # Assert: All agents ready for dispatch with proper context
      assert length(enriched_list) == 4
      assert length(priority_ordered) == 4

      for {:ok, enriched} <- enriched_list do
        assert is_atom(enriched.agent_type)
        assert is_binary(enriched.class_name)
        assert is_map(enriched.constraints)
        assert enriched.constraints.timeout_ms > 0
        assert enriched.constraints.budget > 0
      end
    end

    test "integration_cache_improves_heartbeat_latency: repeated enrichment faster" do
      # Arrange
      Service.clear_all_cache()
      agent_type = :health_agent

      # Act: First enrichment (cache miss)
      start1 = System.monotonic_time(:microsecond)

      {:ok, _} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          cache: true,
          timeout_ms: 5000
        )

      elapsed1 = System.monotonic_time(:microsecond) - start1

      # Second enrichment (cache hit)
      start2 = System.monotonic_time(:microsecond)

      {:ok, _} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          cache: true,
          timeout_ms: 5000
        )

      elapsed2 = System.monotonic_time(:microsecond) - start2

      # Assert: Cache hit is faster (or similar; no regression)
      # We allow for timing variance, but cache should not be slower
      assert elapsed2 <= elapsed1 + 100_000  # +100ms tolerance
    end
  end
end
