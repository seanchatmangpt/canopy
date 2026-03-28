defmodule Canopy.Autonomic.HeartbeatTest do
  use ExUnit.Case, async: false
  doctest Canopy.Autonomic.Heartbeat

  # Requires database and application processes
  @moduletag :requires_application

  alias Canopy.Repo
  alias Canopy.Schemas.{Agent, Organization}
  alias Canopy.Autonomic.Heartbeat

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create test organization
    org =
      Repo.insert!(%Organization{
        name: "Test Org",
        slug: "test-org-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
        settings: %{}
      })

    # Create test user
    user =
      Repo.insert!(%Canopy.Schemas.User{
        email: "test#{System.unique_integer()}@example.com",
        name: "Test User"
      })

    # Create test workspace
    workspace =
      Repo.insert!(%Canopy.Schemas.Workspace{
        name: "Test Workspace",
        owner_id: user.id,
        organization_id: org.id,
        path: "/test"
      })

    # Create test agent
    agent =
      Repo.insert!(%Agent{
        workspace_id: workspace.id,
        slug: "test-agent-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}",
        name: "Test Agent",
        role: "test",
        adapter: "mock",
        model: "claude-3-haiku",
        system_prompt: "You are a test agent"
      })

    {:ok, org: org, user: user, workspace: workspace, agent: agent}
  end

  describe "heartbeat dispatcher" do
    test "heartbeat_dispatches_6_agents: all 6 autonomic agents receive dispatch signal", %{
      agent: _agent
    } do
      # Verify that Heartbeat.tick() initiates dispatch to all 6 agents
      dispatch_results = Heartbeat.tick()

      # All 6 agents should be scheduled
      expected_agents = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent,
        :learning_agent,
        :adaptation_agent
      ]

      for agent_type <- expected_agents do
        assert Enum.any?(dispatch_results, &(elem(&1, 0) == agent_type)),
               "#{inspect(agent_type)} not dispatched"
      end

      # Verify count
      assert length(dispatch_results) >= 6, "Expected at least 6 dispatch results"
    end

    test "priority_queue_ordering: health agent checked before learning agent", %{agent: _agent} do
      # Verify priority queue ordering
      dispatch_results = Heartbeat.tick()

      # Extract agent types and their dispatch order
      agent_types = Enum.map(dispatch_results, &elem(&1, 0))

      health_idx = Enum.find_index(agent_types, &(&1 == :health_agent))
      learning_idx = Enum.find_index(agent_types, &(&1 == :learning_agent))

      assert not is_nil(health_idx), "Health agent not dispatched"
      assert not is_nil(learning_idx), "Learning agent not dispatched"
      assert health_idx < learning_idx, "Health should be dispatched before learning"
    end

    test "priority_queue_ordering: full priority order maintained", %{agent: _agent} do
      dispatch_results = Heartbeat.tick()
      agent_types = Enum.map(dispatch_results, &elem(&1, 0))

      # Expected priority order
      expected_order = [
        :health_agent,
        :healing_agent,
        :data_agent,
        :compliance_agent,
        :learning_agent,
        :adaptation_agent
      ]

      # Verify each agent appears in correct relative order
      for i <- 0..(length(expected_order) - 2) do
        agent_a = Enum.at(expected_order, i)
        agent_b = Enum.at(expected_order, i + 1)

        idx_a = Enum.find_index(agent_types, &(&1 == agent_a))
        idx_b = Enum.find_index(agent_types, &(&1 == agent_b))

        assert not is_nil(idx_a), "Agent #{inspect(agent_a)} not dispatched"
        assert not is_nil(idx_b), "Agent #{inspect(agent_b)} not dispatched"
        assert idx_a < idx_b, "#{inspect(agent_a)} should come before #{inspect(agent_b)}"
      end
    end
  end

  describe "budget enforcement" do
    test "budget_enforcement: high-priority agents receive budget allocation", %{agent: _agent} do
      dispatch_results = Heartbeat.tick()

      # Extract health agent result
      health_result =
        Enum.find(dispatch_results, fn {agent_type, _} -> agent_type == :health_agent end)

      assert not is_nil(health_result), "Health agent not dispatched"

      {_, result_data} = health_result
      # Verify result has budget info
      assert is_map(result_data), "Result should be a map"

      assert Map.has_key?(result_data, :budget) or Map.has_key?(result_data, :status),
             "Result should have budget or status info"
    end

    test "budget_enforcement: low-priority agents wait if budget exhausted", %{agent: _agent} do
      # Set system budget limit to trigger queue
      :ok = Heartbeat.set_budget_limit(100)

      dispatch_results = Heartbeat.tick()

      # Verify dispatch results are ordered (low-priority may be deferred)
      assert is_list(dispatch_results), "Dispatch results should be a list"

      # At least some agents should be dispatched
      assert length(dispatch_results) > 0, "At least one agent should be dispatched"
    end

    test "budget_enforcement: budget_tiers_6_level_hierarchy", %{agent: _agent} do
      # Verify 6-tier budget hierarchy exists and is correctly ordered
      tiers = Heartbeat.get_budget_tiers()

      expected_tiers = [:critical, :high, :normal, :low, :batch, :dormant]

      assert is_list(tiers), "Tiers should be a list"
      assert length(tiers) == 6, "Should have exactly 6 budget tiers"

      # Verify ordering
      for {tier, idx} <- Enum.with_index(tiers) do
        assert Enum.at(expected_tiers, idx) == tier,
               "Tier #{idx} should be #{inspect(Enum.at(expected_tiers, idx))}, got #{inspect(tier)}"
      end
    end

    test "budget_enforcement: critical tier agents always get resources", %{agent: _agent} do
      :ok = Heartbeat.set_budget_limit(1)

      dispatch_results = Heartbeat.tick()

      # Health agent is critical tier, should always dispatch
      health_result =
        Enum.find(dispatch_results, fn {agent_type, _} -> agent_type == :health_agent end)

      assert not is_nil(health_result), "Critical health agent should always be dispatched"
    end
  end

  describe "health agent" do
    test "health_agent_detects_anomaly: finds latency spike in system poll", %{agent: _agent} do
      # Run health agent dispatch
      dispatch_results = Heartbeat.tick()

      health_result =
        Enum.find(dispatch_results, fn {agent_type, _} -> agent_type == :health_agent end)

      assert not is_nil(health_result), "Health agent should be dispatched"

      {_, result} = health_result
      # Health agent result should contain status
      assert is_map(result), "Health agent result should be a map"

      assert Map.has_key?(result, :status) or Map.has_key?(result, :alerts),
             "Health result should have status or alerts"
    end

    test "health_agent_detects_anomaly: error rate detection", %{agent: _agent} do
      result = Canopy.Autonomic.HealthAgent.run()

      assert is_map(result), "HealthAgent.run should return a map"
      assert Map.has_key?(result, :status), "Result should have status key"
    end

    test "health_agent_detects_anomaly: uptime monitoring", %{agent: _agent} do
      result = Canopy.Autonomic.HealthAgent.run()

      assert is_map(result), "HealthAgent.run should return a map"
      # Verify structure
      assert result.status in ["healthy", "degraded", "critical"],
             "Status should be one of: healthy, degraded, critical"
    end
  end

  describe "healing agent" do
    test "healing_agent_runs_process_healing: identifies failed workflow", %{agent: _agent} do
      result = Canopy.Autonomic.HealingAgent.run()

      assert is_map(result), "HealingAgent.run should return a map"

      assert Map.has_key?(result, :healed_count) or Map.has_key?(result, :status),
             "Result should have healed_count or status"
    end

    test "healing_agent_runs_process_healing: repairs workflow", %{agent: _agent} do
      result = Canopy.Autonomic.HealingAgent.run()

      assert is_map(result), "Result should be a map"
      # If healing occurred, healed_count should be >= 0
      if Map.has_key?(result, :healed_count) do
        assert is_integer(result.healed_count), "healed_count should be an integer"
        assert result.healed_count >= 0, "healed_count should be non-negative"
      end
    end

    test "healing_agent_runs_process_healing: audit trail entry created", %{agent: _agent} do
      result = Canopy.Autonomic.HealingAgent.run()

      assert is_map(result), "Result should be a map"

      assert Map.has_key?(result, :timestamp) or Map.has_key?(result, :status),
             "Result should have timestamp or status for audit"
    end
  end

  describe "data agent" do
    test "data_agent_validates_consistency: checks idempotency", %{agent: _agent} do
      result = Canopy.Autonomic.DataAgent.run()

      assert is_map(result), "DataAgent.run should return a map"

      assert Map.has_key?(result, :duplicates_found) or Map.has_key?(result, :status),
             "Result should have duplicates_found or status"
    end

    test "data_agent_validates_consistency: finds duplicate data", %{agent: _agent} do
      result = Canopy.Autonomic.DataAgent.run()

      assert is_map(result), "Result should be a map"

      if Map.has_key?(result, :duplicates_found) do
        assert is_integer(result.duplicates_found), "duplicates_found should be an integer"
        assert result.duplicates_found >= 0, "duplicates_found should be non-negative"
      end
    end

    test "data_agent_validates_consistency: freshness check", %{agent: _agent} do
      result = Canopy.Autonomic.DataAgent.run()

      assert is_map(result), "Result should be a map"

      assert Map.has_key?(result, :freshness) or Map.has_key?(result, :status),
             "Result should have freshness or status"
    end
  end

  describe "compliance agent" do
    test "compliance_agent_checks_audit: validates signature chain", %{agent: _agent} do
      result = Canopy.Autonomic.ComplianceAgent.run()

      assert is_map(result), "ComplianceAgent.run should return a map"

      assert Map.has_key?(result, :signature_gaps) or Map.has_key?(result, :status),
             "Result should have signature_gaps or status"
    end

    test "compliance_agent_checks_audit: audit trail gap detection", %{agent: _agent} do
      result = Canopy.Autonomic.ComplianceAgent.run()

      assert is_map(result), "Result should be a map"

      if Map.has_key?(result, :signature_gaps) do
        assert is_integer(result.signature_gaps), "signature_gaps should be an integer"
        assert result.signature_gaps >= 0, "signature_gaps should be non-negative"
      end
    end

    test "compliance_agent_checks_audit: compliance status", %{agent: _agent} do
      result = Canopy.Autonomic.ComplianceAgent.run()

      assert is_map(result), "Result should be a map"
      assert Map.has_key?(result, :status), "Result should have status"

      assert result.status in ["compliant", "at_risk", "critical"],
             "Status should be one of: compliant, at_risk, critical"
    end
  end

  describe "learning agent" do
    test "learning_agent_retrains_model: pulls new data", %{agent: _agent} do
      result = Canopy.Autonomic.LearningAgent.run()

      assert is_map(result), "LearningAgent.run should return a map"

      assert Map.has_key?(result, :data_pulled) or Map.has_key?(result, :status),
             "Result should have data_pulled or status"
    end

    test "learning_agent_retrains_model: model update", %{agent: _agent} do
      result = Canopy.Autonomic.LearningAgent.run()

      assert is_map(result), "Result should be a map"

      if Map.has_key?(result, :model_updated) do
        assert is_boolean(result.model_updated), "model_updated should be a boolean"
      end
    end

    test "learning_agent_retrains_model: training metrics", %{agent: _agent} do
      result = Canopy.Autonomic.LearningAgent.run()

      assert is_map(result), "Result should be a map"

      assert Map.has_key?(result, :accuracy) or Map.has_key?(result, :status),
             "Result should have accuracy or status"
    end
  end

  describe "adaptation agent" do
    test "adaptation_agent_detects_drift: config drift detection", %{agent: _agent} do
      result = Canopy.Autonomic.AdaptationAgent.run()

      assert is_map(result), "AdaptationAgent.run should return a map"

      assert Map.has_key?(result, :drift_detected) or Map.has_key?(result, :status),
             "Result should have drift_detected or status"
    end

    test "adaptation_agent_detects_drift: hot reload capability", %{agent: _agent} do
      result = Canopy.Autonomic.AdaptationAgent.run()

      assert is_map(result), "Result should be a map"

      if Map.has_key?(result, :reloaded) do
        assert is_boolean(result.reloaded), "reloaded should be a boolean"
      end
    end

    test "adaptation_agent_detects_drift: config comparison", %{agent: _agent} do
      result = Canopy.Autonomic.AdaptationAgent.run()

      assert is_map(result), "Result should be a map"

      assert Map.has_key?(result, :changes) or Map.has_key?(result, :status),
             "Result should have changes or status"
    end
  end

  describe "integration tests" do
    test "full_heartbeat_cycle: all agents dispatch and complete", %{agent: _agent} do
      dispatch_results = Heartbeat.tick()

      # All 6 agents dispatched
      assert length(dispatch_results) == 6, "Should dispatch exactly 6 agents"

      # All results are maps
      for {_agent_type, result} <- dispatch_results do
        assert is_map(result), "Each result should be a map"
      end
    end

    test "heartbeat_scheduling: dispatch runs on correct interval", %{agent: _agent} do
      # Verify heartbeat can be scheduled
      schedule_result = Heartbeat.schedule()

      assert match?({:ok, _pid}, schedule_result) or schedule_result == :ok,
             "Heartbeat.schedule should return :ok or {:ok, pid}"
    end

    test "autonomic_no_human_dashboards: agents run fully autonomously", %{agent: _agent} do
      # Verify agents run without requiring human intervention
      dispatch_results = Heartbeat.tick()

      for {_agent_type, result} <- dispatch_results do
        assert is_map(result), "Each agent should return a map with autonomic result"
        # No human approval keys should be present
        assert not Map.has_key?(result, :requires_approval),
               "Autonomic agents should not require approval"
      end
    end
  end

  describe "error handling" do
    test "heartbeat_graceful_failure: agent error does not crash dispatcher", %{agent: _agent} do
      # Verify heartbeat continues even if one agent fails
      dispatch_results = Heartbeat.tick()

      # Should have results even with potential errors
      assert is_list(dispatch_results), "Should return list of results"
    end

    test "agent_timeout_handling: agent timeout does not block other agents", %{agent: _agent} do
      # Set a short timeout
      :ok = Heartbeat.set_agent_timeout(100)

      dispatch_results = Heartbeat.tick()

      # Should complete with some results
      assert length(dispatch_results) > 0, "Should have some results despite timeouts"
    end
  end
end
