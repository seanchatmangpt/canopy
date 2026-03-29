defmodule Canopy.A2AAgentTest do
  @moduledoc """
  Chicago TDD tests for Canopy.A2AAgent.

  Tests pure callbacks (agent_card/0, handle_cancel/1) that don't require
  the full OTP application. Integration tests are tagged :integration.
  """

  use ExUnit.Case, async: true

  @ets_table :canopy_a2a_tasks

  setup do
    # Ensure ETS table exists for cancel tests
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    end

    :ok
  end

  describe "agent_card/0" do
    test "returns card with canopy agent name" do
      card = Canopy.A2AAgent.agent_card()
      assert card.name == "canopy"
    end

    test "card url ends with /api/v1/a2a" do
      card = Canopy.A2AAgent.agent_card()
      assert String.ends_with?(card.url, "/api/v1/a2a")
    end

    test "card includes exactly 4 skills" do
      card = Canopy.A2AAgent.agent_card()
      assert length(card.skills) == 4
    end

    test "card includes workspace_coordination skill" do
      card = Canopy.A2AAgent.agent_card()
      skill_ids = Enum.map(card.skills, & &1.id)
      assert "workspace_coordination" in skill_ids
    end

    test "card includes heartbeat_dispatch skill" do
      card = Canopy.A2AAgent.agent_card()
      skill_ids = Enum.map(card.skills, & &1.id)
      assert "heartbeat_dispatch" in skill_ids
    end

    test "card includes process_mining skill" do
      card = Canopy.A2AAgent.agent_card()
      skill_ids = Enum.map(card.skills, & &1.id)
      assert "process_mining" in skill_ids
    end

    test "card includes agent_orchestration skill" do
      card = Canopy.A2AAgent.agent_card()
      skill_ids = Enum.map(card.skills, & &1.id)
      assert "agent_orchestration" in skill_ids
    end

    test "card uses base_url from application config" do
      original = Application.get_env(:canopy, :base_url)

      Application.put_env(:canopy, :base_url, "http://custom-host:9999")

      try do
        card = Canopy.A2AAgent.agent_card()
        assert String.starts_with?(card.url, "http://custom-host:9999")
      after
        if original do
          Application.put_env(:canopy, :base_url, original)
        else
          Application.delete_env(:canopy, :base_url)
        end
      end
    end

    test "card has display_name Canopy" do
      card = Canopy.A2AAgent.agent_card()
      assert card.display_name == "Canopy"
    end

    test "card has capabilities list" do
      card = Canopy.A2AAgent.agent_card()
      assert is_list(card.capabilities)
      assert length(card.capabilities) > 0
    end
  end

  describe "handle_cancel/1" do
    test "returns :ok for unknown task id" do
      assert :ok == Canopy.A2AAgent.handle_cancel("nonexistent-task-#{System.unique_integer([:positive])}")
    end

    test "returns :ok after canceling registered task" do
      task_id = "test-task-#{System.unique_integer([:positive])}"
      # Simulate a registered task with a short-lived process
      {:ok, pid} = Task.start(fn -> Process.sleep(5000) end)
      :ets.insert(@ets_table, {task_id, pid})

      assert :ok == Canopy.A2AAgent.handle_cancel(task_id)
      assert :ets.lookup(@ets_table, task_id) == []
    end

    test "removes task from ETS on cancel" do
      task_id = "cancel-test-#{System.unique_integer([:positive])}"
      {:ok, pid} = Task.start(fn -> Process.sleep(5000) end)
      :ets.insert(@ets_table, {task_id, pid})

      Canopy.A2AAgent.handle_cancel(task_id)

      refute :ets.member(@ets_table, task_id)
    end
  end
end
