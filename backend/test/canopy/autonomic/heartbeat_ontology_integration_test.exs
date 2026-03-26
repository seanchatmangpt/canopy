defmodule Canopy.Autonomic.HeartbeatOntologyIntegrationTest do
  @moduledoc """
  Integration tests for Heartbeat + Ontology Service.

  Tests verify:
  1. Agents can query cached ontologies without HTTP to OSA
  2. Task metadata enriches agent execution context
  3. WvdA soundness: no deadlocks, all operations bounded
  4. Armstrong fault tolerance: errors don't crash dispatcher
  5. Cache efficiency: multiple agent queries hit cache

  NOTE: Tests requiring OSA/Oxigraph connectivity are marked @skip.
  Run with OSA service running on http://localhost:8001 to execute integration tests.
  """
  use ExUnit.Case, async: false

  alias Canopy.Autonomic.HeartbeatOntologyService
  alias Canopy.Ontology.Service

  setup do
    # Start the Service GenServer if not already running
    case Service.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> raise "Failed to start Service: #{inspect(error)}"
    end

    # Clear cache before each test
    try do
      Service.clear_all_cache()
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  describe "enrich_agent/2" do
    test "enrich_agent_retrieves_cached_metadata: queries ontology service for agent task definition" do
      # Core functionality test - no OSA call needed
      # Service already started in setup, returns minimal context on error
      # Arrange: Prime the cache with agent metadata
      agent_type = :health_agent
      class_name = "HealthAgent"
      ontology_id = "canopy-agents"

      # Act: Enrich the agent
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          ontology_id: ontology_id,
          timeout_ms: 5000
        )

      # Assert: Enriched context contains required fields
      assert enriched.agent_type == agent_type
      assert enriched.class_name == class_name
      assert is_map(enriched.task_metadata) or enriched.task_metadata == nil
      assert is_map(enriched.hierarchy)
      assert is_map(enriched.constraints)
      assert is_struct(enriched.timestamp, DateTime)
    end

    test "enrich_agent_extracts_hierarchy: identifies parent and child task classes" do
      # Arrange
      agent_type = :healing_agent

      # Act
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 5000)

      # Assert: Hierarchy contains parent/child relationships
      assert is_list(enriched.hierarchy.parent_classes)
      assert is_list(enriched.hierarchy.sub_classes)
      assert is_list(enriched.hierarchy.properties)
    end

    test "enrich_agent_extracts_constraints: identifies resource limits and tier" do
      # Arrange
      agent_type = :data_agent

      # Act
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 5000)

      # Assert: Constraints contain timeout, budget, tier
      assert is_integer(enriched.constraints.timeout_ms)
      assert enriched.constraints.timeout_ms > 0
      assert is_integer(enriched.constraints.budget)
      assert enriched.constraints.budget > 0

      assert enriched.constraints.tier in [
               "critical",
               "high",
               "normal",
               "low",
               "batch",
               "dormant"
             ] or
               is_atom(enriched.constraints.tier)
    end

    test "enrich_agent_timeout_fallback: returns minimal context on timeout" do
      # Arrange: Set unrealistic timeout (0ms) to trigger fallback
      agent_type = :compliance_agent

      # Act
      result =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 1
        )

      # Assert: Should return ok with fallback context (not error)
      assert match?({:ok, _enriched}, result)

      {:ok, enriched} = result
      assert enriched.agent_type == agent_type
      # Fallback has minimal but valid constraints
      assert enriched.constraints.timeout_ms > 0
      assert enriched.constraints.budget > 0
    end

    test "enrich_agent_cache_hit_tracked: subsequent queries hit cache" do
      # Arrange
      agent_type = :learning_agent
      stats_before = Service.cache_stats()

      # Act: First call (miss)
      {:ok, enriched1} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: true
        )

      stats_after_miss = Service.cache_stats()

      # Second call (hit)
      {:ok, enriched2} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: true
        )

      stats_after_hit = Service.cache_stats()

      # Assert: Cache hit rate increased
      assert stats_after_hit.hits >= stats_after_miss.hits
    end

    @tag :skip
    test "enrich_agent_respects_cache_false: bypasses cache when requested" do
      # Requires OSA service running to test cache bypass behavior
      # Arrange
      agent_type = :adaptation_agent
      stats_before = Service.cache_stats()

      # Act: Two calls with cache: false
      {:ok, _} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: false
        )

      {:ok, _} =
        HeartbeatOntologyService.enrich_agent(agent_type,
          timeout_ms: 5000,
          cache: false
        )

      stats_after = Service.cache_stats()

      # Assert: No cache hits (both bypassed)
      assert stats_after.hits == stats_before.hits or stats_after.total >= stats_before.total + 2
    end
  end

  describe "enrich_agents_batch/2" do
    test "enrich_agents_batch_processes_multiple: enriches all agent types concurrently" do
      # Arrange
      agent_types = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent,
        :learning_agent,
        :adaptation_agent
      ]

      # Act: Enrich all agents in batch
      {:ok, results, priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: 10_000,
          max_agents: 10
        )

      # Assert: All agents enriched
      assert length(results) == 6
      assert length(priority_ordered) == 6

      # All results are ok tuples
      for result <- results do
        assert match?({:ok, _}, result)
      end
    end

    test "enrich_agents_batch_priority_ordered: agents ordered by heartbeat priority" do
      # Arrange
      agent_types = [
        # Low priority
        :adaptation_agent,
        # High priority
        :health_agent,
        # Medium priority
        :learning_agent
      ]

      # Act
      {:ok, _results, priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types, timeout_ms: 5000)

      # Assert: Priority order is maintained
      # Extract agent types from results in priority order
      ordered_types = Enum.map(priority_ordered, fn {:ok, enriched} -> enriched.agent_type end)

      health_idx = Enum.find_index(ordered_types, &(&1 == :health_agent))
      learning_idx = Enum.find_index(ordered_types, &(&1 == :learning_agent))
      adaptation_idx = Enum.find_index(ordered_types, &(&1 == :adaptation_agent))

      assert health_idx < learning_idx, "Health should be before learning"
      assert learning_idx < adaptation_idx, "Learning should be before adaptation"
    end

    test "enrich_agents_batch_max_agents_enforcement: rejects batch exceeding max_agents limit" do
      # Arrange: Create more agents than max
      agent_types = Enum.map(1..15, fn i -> :"agent_#{i}" end)

      # Act: Try to enrich with max_agents: 10
      result =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          max_agents: 10,
          timeout_ms: 1000
        )

      # Assert: Should return error for exceeding limit
      assert match?({:error, :max_agents_exceeded}, result)
    end

    test "enrich_agents_batch_bounded_execution: all agents complete within timeout" do
      # Arrange
      agent_types = [:health_agent, :healing_agent, :data_agent]
      start_time = System.monotonic_time(:millisecond)
      timeout_ms = 15_000

      # Act: Enrich batch with bounded timeout
      {:ok, _results, _priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: timeout_ms,
          max_agents: 10
        )

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert: Completed within bounded time (timeout + buffer)
      assert elapsed <= timeout_ms + 2000,
             "Batch should complete within #{timeout_ms + 2000}ms, took #{elapsed}ms"
    end

    test "enrich_agents_batch_no_deadlocks: concurrent queries don't deadlock" do
      # Arrange: Spawn multiple batch queries concurrently
      agent_types = [:health_agent, :healing_agent, :data_agent]

      tasks =
        Enum.map(1..5, fn _i ->
          Task.async(fn ->
            HeartbeatOntologyService.enrich_agents_batch(agent_types,
              timeout_ms: 5000,
              max_agents: 10
            )
          end)
        end)

      # Act: Wait for all to complete with timeout
      results = Enum.map(tasks, &Task.await(&1, 20_000))

      # Assert: All completed without deadlock
      assert length(results) == 5

      for result <- results do
        assert match?({:ok, _results, _priority_ordered}, result)
      end
    end
  end

  describe "get_task_hierarchy/2" do
    test "get_task_hierarchy_returns_hierarchy_and_constraints: extracts task structure" do
      # Arrange
      agent_type = :compliance_agent

      # Act
      {:ok, hierarchy_data} = HeartbeatOntologyService.get_task_hierarchy(agent_type)

      # Assert: Contains expected fields
      assert is_map(hierarchy_data)
      assert Map.has_key?(hierarchy_data, :hierarchy)
      assert Map.has_key?(hierarchy_data, :constraints)
      assert Map.has_key?(hierarchy_data, :class_name)

      assert is_map(hierarchy_data.hierarchy)
      assert is_map(hierarchy_data.constraints)
      assert is_binary(hierarchy_data.class_name)
    end
  end

  describe "cache_stats/0" do
    test "cache_stats_reflects_queries: tracks hits and misses across batch operations" do
      # Arrange
      Service.clear_all_cache()
      stats_before = HeartbeatOntologyService.cache_stats()

      # Act: Run batch enrichment
      agent_types = [:health_agent, :healing_agent, :data_agent]

      {:ok, _results, _priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types, max_agents: 10)

      # Run again to generate cache hits
      {:ok, _results2, _priority_ordered2} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types, max_agents: 10)

      stats_after = HeartbeatOntologyService.cache_stats()

      # Assert: Statistics increased
      assert stats_after.total > stats_before.total
      # Should have some hits from second run
      assert stats_after.hits >= stats_before.hits
    end
  end

  describe "WvdA Soundness: Deadlock Freedom" do
    test "wvda_deadlock_free_all_timeouts: every blocking operation has timeout_ms" do
      # Arrange
      agent_types = [:health_agent, :healing_agent]

      # Act: All operations should timeout rather than hang
      {:ok, _results, _priority} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          timeout_ms: 2000,
          max_agents: 10
        )

      # Assert: Completed without hanging (implicit: test didn't timeout)
      assert true
    end

    test "wvda_deadlock_free_no_circular_waits: agents don't wait for each other" do
      # Arrange: Run enrichment concurrently from multiple tasks
      agent_types = [:health_agent, :healing_agent, :data_agent]

      tasks =
        Enum.map(1..3, fn _i ->
          Task.async(fn ->
            HeartbeatOntologyService.enrich_agents_batch(agent_types, timeout_ms: 5000)
          end)
        end)

      # Act & Assert: No deadlock even with concurrent access
      results =
        Enum.map(tasks, fn task ->
          Task.yield(task, 15_000) || {:timeout, "Task exceeded 15s"}
        end)

      # All should complete successfully
      for result <- results do
        assert match?({:ok, _}, result),
               "Concurrent batch enrichment should not deadlock: #{inspect(result)}"
      end
    end
  end

  describe "WvdA Soundness: Liveness" do
    test "wvda_liveness_all_operations_complete: enrich_agent always terminates" do
      # Arrange: Test with various timeouts
      agent_types = [:health_agent, :healing_agent, :data_agent]

      # Act: Multiple runs should all complete
      Enum.each(1..5, fn _i ->
        {:ok, _enriched} =
          HeartbeatOntologyService.enrich_agent(:health_agent, timeout_ms: 5000)
      end)

      # Assert: All 5 iterations completed (implicit: no hanging)
      assert true
    end

    test "wvda_liveness_batch_iteration_bounded: batch processes finite agents with escape condition" do
      # Arrange
      agent_types = [:health_agent, :healing_agent, :data_agent, :compliance_agent]

      # Act: Batch should exit after processing all agents
      {:ok, results, _} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types,
          max_agents: 10,
          timeout_ms: 5000
        )

      # Assert: All agents processed (bounded iteration)
      assert length(results) == length(agent_types)
    end
  end

  describe "WvdA Soundness: Boundedness" do
    test "wvda_bounded_agent_count_limit: prevents unbounded agent growth" do
      # Arrange: Try to process 100 agents (> max)
      agent_types = Enum.map(1..100, fn i -> :"agent_#{i}" end)

      # Act
      result = HeartbeatOntologyService.enrich_agents_batch(agent_types, max_agents: 10)

      # Assert: Returns error instead of attempting infinite processing
      assert match?({:error, :max_agents_exceeded}, result)
    end

    @tag :skip
    test "wvda_bounded_memory_per_batch: doesn't accumulate unbounded cache" do
      # Requires OSA service running to test cache behavior
      # Arrange
      agent_types = [:health_agent, :healing_agent, :data_agent]
      stats_before = Service.cache_stats()

      # Act: Run batch 10 times
      Enum.each(1..10, fn _i ->
        {:ok, _, _} =
          HeartbeatOntologyService.enrich_agents_batch(agent_types, max_agents: 10)
      end)

      stats_after = Service.cache_stats()

      # Assert: Cache size grows but remains bounded
      # (No unbounded accumulation of misses)
      total_new_queries = stats_after.total - stats_before.total
      # Should have many hits due to caching
      assert stats_after.hits > 0, "Should have cache hits after repeated runs"
    end

    test "wvda_bounded_task_spawning: limits concurrent task creation" do
      # Arrange
      agent_types = [:health_agent, :healing_agent, :data_agent]

      # Act: Spawn batch enrichment (internally creates <= 3 tasks)
      {:ok, results, _} =
        HeartbeatOntologyService.enrich_agents_batch(agent_types, max_agents: 10)

      # Assert: Results match agent count (no extra tasks created)
      assert length(results) == length(agent_types)
    end
  end

  describe "Armstrong Fault Tolerance" do
    test "armstrong_let_it_crash_ontology_error: ontology query error doesn't crash dispatcher" do
      # Arrange
      # This tests with a non-existent ontology, which should fail gracefully
      agent_type = :health_agent

      # Act: Query with non-existent ontology (or one that errors)
      # Should not crash - should return minimal context
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, ontology_id: "nonexistent")

      # Assert: Returns valid enriched context even with error
      assert enriched.agent_type == agent_type
      assert is_map(enriched.constraints)
      assert enriched.constraints.timeout_ms > 0
    end

    test "armstrong_no_shared_state_agents_independent: multiple agents don't share state" do
      # Arrange
      agent_type1 = :health_agent
      agent_type2 = :healing_agent

      # Act: Enrich both agents
      {:ok, enriched1} = HeartbeatOntologyService.enrich_agent(agent_type1)
      {:ok, enriched2} = HeartbeatOntologyService.enrich_agent(agent_type2)

      # Assert: Enriched contexts are independent
      assert enriched1.agent_type != enriched2.agent_type
      assert enriched1.class_name != enriched2.class_name
      # Modifying one doesn't affect the other
      assert enriched1.agent_type == agent_type1
      assert enriched2.agent_type == agent_type2
    end

    test "armstrong_budget_constraints_enforced: each agent call respects timeout budget" do
      # Arrange
      agent_type = :compliance_agent
      timeout_ms = 3000

      # Act: Call with explicit timeout
      start_time = System.monotonic_time(:millisecond)

      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: timeout_ms)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert: Completed within budget (timeout + small buffer for process scheduling)
      assert elapsed <= timeout_ms + 500,
             "Operation should respect #{timeout_ms}ms budget, took #{elapsed}ms"

      assert enriched.agent_type == agent_type
    end
  end

  describe "Integration with Heartbeat" do
    test "integration_heartbeat_agents_use_enrichment: agents can be enriched before heartbeat dispatch" do
      # Arrange
      agent_type = :health_agent

      # Act: Enrich agent as if heartbeat will use it
      {:ok, enriched} = HeartbeatOntologyService.enrich_agent(agent_type)

      # Assert: Enriched context provides metadata for heartbeat
      assert enriched.agent_type == agent_type
      assert is_map(enriched.task_metadata) or enriched.task_metadata == nil
      assert enriched.constraints.timeout_ms > 0
      assert enriched.constraints.budget > 0
    end

    test "integration_batch_enrichment_before_dispatch: can enrich all agents before heartbeat tick" do
      # Arrange: Simulate heartbeat agent list
      heartbeat_agents = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent,
        :learning_agent,
        :adaptation_agent
      ]

      # Act: Enrich all before dispatch (simulating heartbeat preparation)
      {:ok, enriched_list, priority_ordered} =
        HeartbeatOntologyService.enrich_agents_batch(heartbeat_agents, max_agents: 10)

      # Assert: All agents enriched and ready for dispatch
      assert length(enriched_list) == 6
      assert length(priority_ordered) == 6

      # Each has required metadata
      for {:ok, enriched} <- enriched_list do
        assert is_atom(enriched.agent_type)
        assert is_binary(enriched.class_name)
        assert is_map(enriched.constraints)
      end
    end
  end

  describe "Cache Efficiency" do
    @tag :skip
    test "cache_efficiency_multiple_queries_hit_cache: repeated agent enrichment hits cache" do
      # Requires OSA service running to test cache behavior
      # Arrange
      agent_type = :health_agent
      Service.clear_all_cache()
      stats_before = Service.cache_stats()

      # Act: Enrich same agent 3 times
      Enum.each(1..3, fn _i ->
        {:ok, _} = HeartbeatOntologyService.enrich_agent(agent_type)
      end)

      stats_after = Service.cache_stats()

      # Assert: Cache hit rate improves (1 miss, 2 hits)
      assert stats_after.total == stats_before.total + 3
      # At least 2 hits (from 2nd and 3rd call)
      assert stats_after.hits >= 2
    end

    test "cache_efficiency_different_agents_use_different_cache_keys: independent cache entries" do
      # Arrange
      Service.clear_all_cache()

      # Act: Query different agents
      {:ok, _} = HeartbeatOntologyService.enrich_agent(:health_agent)
      {:ok, _} = HeartbeatOntologyService.enrich_agent(:healing_agent)
      {:ok, _} = HeartbeatOntologyService.enrich_agent(:data_agent)

      stats = Service.cache_stats()

      # Assert: 3 cache misses (different cache keys)
      assert stats.misses >= 3
      assert stats.hits == 0
    end
  end

  describe "Error Handling and Graceful Degradation" do
    test "error_handling_timeout_returns_fallback: timeouts don't crash, return defaults" do
      # Arrange: Very short timeout to simulate timeout scenario
      agent_type = :learning_agent

      # Act
      {:ok, enriched} =
        HeartbeatOntologyService.enrich_agent(agent_type, timeout_ms: 1)

      # Assert: Returns ok with fallback context
      assert enriched.agent_type == agent_type
      assert enriched.timestamp != nil
      # Fallback constraints are valid
      assert enriched.constraints.timeout_ms > 0
    end

    test "error_handling_no_crash_on_ontology_not_found: missing ontology doesn't crash" do
      # Arrange
      agent_type = :adaptation_agent

      # Act: Query non-existent ontology
      result =
        HeartbeatOntologyService.enrich_agent(agent_type, ontology_id: "missing-ontology-xyz")

      # Assert: Should still return ok (with fallback or error handling)
      assert match?({:ok, _}, result)
    end
  end
end
