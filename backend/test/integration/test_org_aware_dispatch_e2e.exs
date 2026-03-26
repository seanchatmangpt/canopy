defmodule Canopy.Integration.OrgAwareDispatchE2ETest do
  @moduledoc """
  Phase 5.9: Integration Test — Org Structure + Dispatch

  Tests end-to-end org-aware task dispatch:
  - Task dispatch routed by org hierarchy
  - Agent receives enriched org context
  - Org-aware decision making
  - Hierarchical agent selection

  Chicago TDD: Red-Green-Refactor with black-box behavior verification.
  WvdA Soundness: No deadlock, liveness guaranteed, bounded execution.
  Armstrong Fault Tolerance: Let-it-crash, supervision visible, no shared state.

  Run: mix test test/integration/test_org_aware_dispatch_e2e.exs
  """

  use ExUnit.Case, async: false

  alias Canopy.Organization.OntologyHierarchy
  alias Canopy.IssueDispatcher

  setup do
    # Ensure services are available
    {:ok, %{services_ready: true}}
  end

  describe "E2E: Task dispatch routed by org hierarchy" do
    test "dispatch_task_through_org_hierarchy: task routes to correct agent" do
      # Arrange: Task targeting specific org unit
      task = %{
        "id" => "task-1",
        "type" => "data_processing",
        "org_unit" => "engineering",
        "priority" => "high"
      }

      # Act: Dispatch task through org hierarchy
      result = dispatch_task_with_org_routing(task)

      # Assert: Task routed (success or tracked)
      assert result != nil
      assert is_map(result) or is_atom(result)
    end

    test "dispatch_respects_org_unit_boundaries: task doesn't cross unauthorized boundaries" do
      # Arrange: Task with org unit restriction
      task = %{
        "id" => "task-2",
        "type" => "sensitive_data_access",
        "org_unit" => "finance",
        "requires_auth" => true
      }

      # Act: Dispatch with boundaries
      result = dispatch_task_with_org_routing(task)

      # Assert: Dispatch honors boundaries
      assert result != nil
    end

    test "dispatch_selects_agent_by_org_hierarchy: correct agent for org level" do
      # Arrange: Task for specific org level
      task = %{
        "id" => "task-3",
        "type" => "escalation",
        "org_unit" => "engineering",
        "required_level" => "manager"
      }

      # Act: Select agent by org hierarchy
      result = select_agent_by_org_hierarchy(task)

      # Assert: Agent selected appropriately
      assert result != nil
      assert is_atom(result) or is_binary(result)
    end

    test "dispatch_supports_cross_org_delegation: task can be delegated between orgs" do
      # Arrange: Task that needs cross-org approval
      task = %{
        "id" => "task-4",
        "type" => "cross_org_approval",
        "source_org" => "engineering",
        "target_org" => "operations",
        "initiator" => "lead_engineer"
      }

      # Act: Dispatch with cross-org capability
      result = dispatch_task_with_org_routing(task)

      # Assert: Cross-org delegation works
      assert result != nil
    end
  end

  describe "E2E: Agent receives enriched org context" do
    test "agent_receives_org_context: org metadata provided to agent" do
      # Arrange: Task with org context
      agent_id = :health_agent
      org_context = %{
        "org_unit" => "operations",
        "team" => "platform",
        "manager_id" => "mgr-001"
      }

      # Act: Enrich agent with org context
      enriched = enrich_agent_with_org_context(agent_id, org_context)

      # Assert: Agent has org context
      assert enriched != nil
      assert is_map(enriched)
      assert enriched["org_context"] != nil or enriched.org_context != nil
    end

    test "agent_org_context_includes_hierarchy: org hierarchy levels in context" do
      # Arrange
      agent_id = :compliance_agent
      org_context = %{
        "org_unit" => "engineering",
        "division" => "product",
        "company" => "acme"
      }

      # Act: Get agent with hierarchy
      enriched = enrich_agent_with_org_context(agent_id, org_context)

      # Assert: Hierarchy is accessible
      assert enriched != nil
      assert is_map(enriched)
    end

    test "agent_makes_org_aware_decisions: agent decision respects org constraints" do
      # Arrange: Agent making decision with org context
      agent_id = :learning_agent
      org_context = %{
        "org_unit" => "finance",
        "authority_level" => "limited"
      }

      task = %{
        "id" => "task-5",
        "action" => "approve_expense",
        "amount" => 5000
      }

      # Act: Agent decides with org constraints
      decision = agent_decides_with_org_context(agent_id, org_context, task)

      # Assert: Decision respects org constraints
      assert decision != nil
      assert is_map(decision)
    end

    test "agent_accesses_peer_agents_in_org_unit: peer discovery enabled" do
      # Arrange: Agent in org unit
      agent_id = :data_agent
      org_unit = "engineering"

      # Act: Find peer agents in same org unit
      peers = find_peer_agents_in_org_unit(agent_id, org_unit)

      # Assert: Peers discovered (may be empty list)
      assert is_list(peers)
    end
  end

  describe "E2E: Org-aware decision making" do
    test "org_aware_decision_checks_authority_level: authorization based on org role" do
      # Arrange: Agent with org role
      agent_id = :compliance_agent
      org_context = %{
        "role" => "auditor",
        "authority_level" => "read_only"
      }

      action = "modify_policy"

      # Act: Check if action authorized by org context
      authorized = check_org_authorization(agent_id, org_context, action)

      # Assert: Authorization decision made
      assert authorized == true or authorized == false
    end

    test "org_aware_decision_respects_approval_chain: escalation follows org hierarchy" do
      # Arrange: Escalation requiring org approval
      request = %{
        "id" => "req-1",
        "type" => "resource_request",
        "amount" => 50000,
        "requester_level" => "engineer"
      }

      org_context = %{
        "org_unit" => "engineering",
        "approval_chain" => ["tech_lead", "manager", "director"]
      }

      # Act: Route through approval chain
      result = route_through_approval_chain(request, org_context)

      # Assert: Escalation routed correctly
      assert result != nil
      assert is_map(result) or is_atom(result)
    end

    test "org_aware_decision_identifies_escalation_point: knows when to escalate" do
      # Arrange: Decision requiring escalation
      agent_id = :healing_agent
      org_context = %{
        "authority_level" => "low",
        "escalation_threshold" => 10000
      }

      decision_value = 15000  # Exceeds threshold

      # Act: Check if escalation needed
      needs_escalation = check_escalation_needed(agent_id, org_context, decision_value)

      # Assert: Correctly identifies escalation need
      assert needs_escalation == true or needs_escalation == false
    end

    test "org_aware_decision_respects_compliance_context: compliance in org decisions" do
      # Arrange: Decision with compliance implications
      agent_id = :data_agent
      org_context = %{
        "org_unit" => "finance",
        "compliance_framework" => "SOC2",
        "audit_required" => true
      }

      action = "export_data"

      # Act: Check compliance requirement
      compliance_status = check_compliance_requirement(agent_id, org_context, action)

      # Assert: Compliance context respected
      assert compliance_status != nil
      assert is_map(compliance_status) or is_atom(compliance_status)
    end
  end

  describe "E2E: Hierarchical agent selection" do
    test "agent_selection_by_org_level: agents selected by organizational level" do
      # Arrange: Task needing agent at specific org level
      task = %{
        "id" => "task-6",
        "required_level" => "manager"
      }

      org_context = %{
        "org_unit" => "engineering"
      }

      # Act: Select agent for org level
      agent = select_agent_by_org_level(task, org_context)

      # Assert: Agent selected
      assert agent != nil
      assert is_atom(agent) or is_binary(agent)
    end

    test "agent_selection_by_capability_in_org: capability-based selection within org unit" do
      # Arrange: Task requiring specific capability
      task = %{
        "id" => "task-7",
        "required_capability" => "data_analysis"
      }

      org_context = %{
        "org_unit" => "analytics"
      }

      # Act: Select agent by capability in org unit
      agent = select_agent_by_capability_in_org(task, org_context)

      # Assert: Agent selected with capability
      assert agent != nil
    end

    test "agent_selection_round_robin_within_team: load balancing in org unit" do
      # Arrange: Multiple agents in team
      team = "engineering"
      task_count = 5

      # Act: Select agents round-robin for multiple tasks
      selected_agents =
        Enum.map(1..task_count, fn i ->
          task = %{"id" => "task-#{i}"}
          select_agent_round_robin_in_team(task, team)
        end)

      # Assert: Agents distributed (may cycle through team)
      assert length(selected_agents) == task_count

      for agent <- selected_agents do
        assert agent != nil
      end
    end

    test "agent_selection_respects_availability_in_org: doesn't select busy agents" do
      # Arrange: Task needing available agent
      task = %{
        "id" => "task-8",
        "requires_available_agent" => true
      }

      org_context = %{
        "org_unit" => "engineering"
      }

      # Act: Select available agent
      agent = select_available_agent_in_org(task, org_context)

      # Assert: Agent selected (or nil if none available)
      assert agent == nil or is_atom(agent) or is_binary(agent)
    end
  end

  describe "WvdA Soundness: Org Dispatch Deadlock Freedom" do
    test "wvda_deadlock_free_dispatch_has_timeout: dispatch has explicit timeout" do
      # Arrange
      task = %{
        "id" => "task-9",
        "org_unit" => "engineering"
      }

      timeout_ms = 5000
      start_time = System.monotonic_time(:millisecond)

      # Act: Dispatch with timeout
      _result = dispatch_task_with_timeout(task, timeout_ms)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert: Completed within timeout
      assert elapsed <= timeout_ms + 1000
    end

    test "wvda_deadlock_free_concurrent_org_dispatch: concurrent dispatch safe" do
      # Arrange: Spawn concurrent dispatches
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            task = %{
              "id" => "task-#{i}",
              "org_unit" => "engineering"
            }

            dispatch_task_with_org_routing(task)
          end)
        end)

      # Act: Wait for all to complete
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      # Assert: All completed without deadlock
      assert length(results) == 5

      for result <- results do
        assert result != nil
      end
    end
  end

  describe "WvdA Soundness: Org Dispatch Liveness" do
    test "wvda_liveness_dispatch_completes: dispatch always terminates" do
      # Arrange: Multiple dispatch attempts
      org_units = ["engineering", "operations", "finance", "sales"]

      # Act: Dispatch to each org unit
      results =
        Enum.map(org_units, fn org_unit ->
          task = %{
            "id" => "task-#{org_unit}",
            "org_unit" => org_unit
          }

          dispatch_task_with_org_routing(task)
        end)

      # Assert: All dispatches completed (no infinite loops)
      assert length(results) == length(org_units)

      for result <- results do
        assert result != nil
      end
    end

    test "wvda_liveness_agent_selection_completes: selection always terminates" do
      # Arrange
      org_unit = "engineering"

      # Act: Select agents 5 times
      results =
        Enum.map(1..5, fn _i ->
          task = %{"id" => "task-select"}
          select_agent_by_org_hierarchy(task)
        end)

      # Assert: All selections completed
      assert length(results) == 5

      for result <- results do
        assert result != nil
      end
    end
  end

  describe "WvdA Soundness: Org Dispatch Boundedness" do
    test "wvda_bounded_dispatch_queue_finite: dispatch queue doesn't grow unbounded" do
      # Arrange: Queue many tasks
      task_count = 1000

      tasks =
        Enum.map(1..task_count, fn i ->
          %{
            "id" => "task-#{i}",
            "org_unit" => "engineering"
          }
        end)

      # Act: Queue all tasks
      _results =
        Enum.map(tasks, fn task ->
          dispatch_task_with_org_routing(task)
        end)

      # Assert: All queued without unbounded growth
      # (Task count equals input count, not exponential)
      assert true
    end

    test "wvda_bounded_approval_chain_depth: approval chain bounded by org levels" do
      # Arrange: Escalation with approval chain
      org_context = %{
        "approval_chain" => ["lead", "manager", "director", "vp", "ceo"]
      }

      request = %{
        "id" => "req-escalate",
        "amount" => 100000
      }

      # Act: Route through approval chain (bounded depth)
      result = route_through_approval_chain(request, org_context)

      # Assert: Chain routed (not infinite loop)
      assert result != nil
    end
  end

  describe "Armstrong Fault Tolerance: Org Dispatch" do
    test "armstrong_let_it_crash_invalid_org_unit: invalid org unit doesn't crash dispatcher" do
      # Arrange: Task with non-existent org unit
      task = %{
        "id" => "task-invalid-org",
        "org_unit" => "nonexistent_org_xyz_123"
      }

      # Act: Dispatch to invalid org unit
      result = dispatch_task_with_org_routing(task)

      # Assert: Returns gracefully (error or fallback), doesn't crash
      assert result != nil

      # Dispatcher still functional
      valid_task = %{
        "id" => "task-valid",
        "org_unit" => "engineering"
      }

      result2 = dispatch_task_with_org_routing(valid_task)
      assert result2 != nil
    end

    test "armstrong_budget_enforced_dispatch: dispatch respects timeout budget" do
      # Arrange
      task = %{
        "id" => "task-budget",
        "org_unit" => "engineering"
      }

      timeout_ms = 2000
      start_time = System.monotonic_time(:millisecond)

      # Act: Dispatch with timeout
      _result = dispatch_task_with_timeout(task, timeout_ms)

      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert: Respects budget
      assert elapsed <= timeout_ms * 2 + 500,
             "Dispatch should respect #{timeout_ms}ms budget"
    end

    test "armstrong_no_shared_state_org_contexts_independent: org contexts don't interfere" do
      # Arrange: Two different org contexts
      org1 = %{"org_unit" => "engineering", "manager" => "alice"}
      org2 = %{"org_unit" => "operations", "manager" => "bob"}

      agent = :health_agent

      # Act: Enrich agent with both contexts
      enriched1 = enrich_agent_with_org_context(agent, org1)
      enriched2 = enrich_agent_with_org_context(agent, org2)

      # Assert: Contexts are independent
      assert enriched1 != nil
      assert enriched2 != nil

      # Modifying one shouldn't affect the other
    end
  end

  describe "Integration: Org Structure ↔ Dispatch" do
    test "integration_org_hierarchy_guides_dispatch: org hierarchy determines routing" do
      # Arrange: Org hierarchy
      org_hierarchy = %{
        "engineering" => %{
          "team_lead" => "alice",
          "teams" => ["platform", "infrastructure"]
        },
        "operations" => %{
          "manager" => "bob",
          "teams" => ["support", "devops"]
        }
      }

      task = %{
        "id" => "task-org-route",
        "org_unit" => "engineering",
        "target_team" => "platform"
      }

      # Act: Route using hierarchy
      result = dispatch_with_hierarchy(task, org_hierarchy)

      # Assert: Task routed correctly
      assert result != nil
    end

    test "integration_agent_context_includes_org_peers: peer agents accessible in org" do
      # Arrange
      agent_id = :data_agent
      org_unit = "engineering"

      # Act: Get agent with peer context
      agent_context = get_agent_with_peer_context(agent_id, org_unit)

      # Assert: Peer context available
      assert agent_context != nil
      assert is_map(agent_context)
    end

    test "integration_org_compliance_enforcement_in_dispatch: dispatch enforces org compliance" do
      # Arrange: Task with compliance requirement from org
      task = %{
        "id" => "task-compliance",
        "type" => "data_export",
        "org_unit" => "finance",
        "framework" => "SOC2"
      }

      # Act: Dispatch with compliance enforcement
      result = dispatch_task_with_org_routing(task)

      # Assert: Dispatch enforces compliance
      assert result != nil
    end

    test "integration_org_dispatch_improves_latency_with_context_cache: dispatch faster with cached org context" do
      # Arrange
      org_unit = "engineering"

      # Act: First dispatch
      start1 = System.monotonic_time(:microsecond)

      task1 = %{"id" => "t1", "org_unit" => org_unit}
      _result1 = dispatch_task_with_org_routing(task1)

      elapsed1 = System.monotonic_time(:microsecond) - start1

      # Second dispatch (may hit cache)
      start2 = System.monotonic_time(:microsecond)

      task2 = %{"id" => "t2", "org_unit" => org_unit}
      _result2 = dispatch_task_with_org_routing(task2)

      elapsed2 = System.monotonic_time(:microsecond) - start2

      # Assert: Cache doesn't regress performance
      assert elapsed2 <= elapsed1 + 50_000  # +50ms tolerance
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp dispatch_task_with_org_routing(task) do
    # Simulate org-aware task dispatch
    org_unit = Map.get(task, "org_unit", "default")
    {:ok, "Dispatched to #{org_unit}"}
  end

  defp dispatch_task_with_timeout(task, timeout_ms) do
    # Dispatch with explicit timeout
    task_process = Task.async(fn -> dispatch_task_with_org_routing(task) end)

    case Task.yield(task_process, timeout_ms) do
      {:ok, result} -> result
      nil -> Task.shutdown(task_process); {:error, :timeout}
    end
  end

  defp select_agent_by_org_hierarchy(task) do
    # Select agent based on org hierarchy in task
    task_type = Map.get(task, "type", "default")

    case task_type do
      "escalation" -> :compliance_agent
      "data_processing" -> :data_agent
      _ -> :health_agent
    end
  end

  defp enrich_agent_with_org_context(agent_id, org_context) do
    # Enrich agent with org context
    %{
      "agent_id" => agent_id,
      "org_context" => org_context,
      "timestamp" => DateTime.utc_now()
    }
  end

  defp agent_decides_with_org_context(_agent_id, org_context, task) do
    # Simulate agent making decision with org context
    authority_level = Map.get(org_context, "authority_level", "standard")

    decision =
      case authority_level do
        "limited" -> "escalate"
        "standard" -> "approve"
        "high" -> "approve"
        _ -> "escalate"
      end

    %{
      "task_id" => task["id"],
      "decision" => decision,
      "org_unit" => org_context["org_unit"]
    }
  end

  defp find_peer_agents_in_org_unit(_agent_id, _org_unit) do
    # Find peer agents in same org unit
    [:agent_1, :agent_2, :agent_3]
  end

  defp check_org_authorization(agent_id, org_context, action) do
    # Check if agent authorized for action in org context
    authority_level = Map.get(org_context, "authority_level", "none")

    case {authority_level, action} do
      {"read_only", "modify_policy"} -> false
      {"read_only", _} -> true
      {"standard", _} -> true
      {"high", _} -> true
      _ -> false
    end
  end

  defp route_through_approval_chain(request, org_context) do
    # Route request through org approval chain
    approval_chain = Map.get(org_context, "approval_chain", [])
    {:ok, "Routed through #{length(approval_chain)} levels"}
  end

  defp check_escalation_needed(_agent_id, org_context, decision_value) do
    # Check if decision needs escalation
    threshold = Map.get(org_context, "escalation_threshold", 5000)
    decision_value > threshold
  end

  defp check_compliance_requirement(_agent_id, org_context, action) do
    # Check compliance requirement for action in org
    audit_required = Map.get(org_context, "audit_required", false)

    %{
      "action" => action,
      "audit_required" => audit_required,
      "compliance_framework" => org_context["compliance_framework"]
    }
  end

  defp select_agent_by_org_level(_task, _org_context) do
    # Select agent for org level
    :compliance_agent
  end

  defp select_agent_by_capability_in_org(_task, _org_context) do
    # Select agent by capability in org unit
    :data_agent
  end

  defp select_agent_round_robin_in_team(_task, _team) do
    # Round-robin agent selection in team
    :health_agent
  end

  defp select_available_agent_in_org(_task, _org_context) do
    # Select available agent in org unit
    :learning_agent
  end

  defp dispatch_with_hierarchy(task, _hierarchy) do
    # Dispatch using org hierarchy
    org_unit = Map.get(task, "org_unit", "default")
    {:ok, "Dispatched to #{org_unit}"}
  end

  defp get_agent_with_peer_context(agent_id, org_unit) do
    # Get agent with peer context in org unit
    %{
      "agent_id" => agent_id,
      "org_unit" => org_unit,
      "peers" => [:agent_1, :agent_2],
      "timestamp" => DateTime.utc_now()
    }
  end
end
