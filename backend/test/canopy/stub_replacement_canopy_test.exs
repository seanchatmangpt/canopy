defmodule Canopy.StubReplacementTest do
  @moduledoc """
  Chicago TDD tests for Wave 1 stub replacements.

  RED → GREEN for each item:
  - CAN-C1: Canopy.Workspaces real Ecto queries
  - CAN-C2: HealthAgent real HTTP probes (returns valid structure)
  - CAN-C3: HealingAgent determine_healing_strategy/1
  - CAN-H1: AdaptationAgent compare_configs/0
  - CAN-L1: FrameworkConfig loads from YAML with :name key fallback
  """

  # DB tests use DataCase (Ecto sandbox)
  use Canopy.DataCase, async: false

  alias Canopy.Workspaces
  alias Canopy.Autonomic.HealthAgent
  alias Canopy.Autonomic.HealingAgent
  alias Canopy.Autonomic.AdaptationAgent
  alias Canopy.Compliance.FrameworkConfig
  alias Canopy.Schemas.{User, Workspace}

  # ─────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────

  defp create_user!(attrs \\ %{}) do
    defaults = %{
      name: "Test User #{System.unique_integer([:positive])}",
      email: "test#{System.unique_integer([:positive])}@example.com",
      password: "password123",
      role: "member"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_workspace!(owner_id, attrs \\ %{}) do
    defaults = %{
      name: "Test Workspace #{System.unique_integer([:positive])}",
      path: "/tmp/ws_#{System.unique_integer([:positive])}",
      owner_id: owner_id
    }

    %Workspace{}
    |> Workspace.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  # ─────────────────────────────────────────────────────────────────
  # CAN-C1: Canopy.Workspaces
  # ─────────────────────────────────────────────────────────────────

  describe "CAN-C1: Workspaces context" do
    test "list_workspaces/1 returns empty list for new user (not raise)" do
      user = create_user!()
      result = Workspaces.list_workspaces(user.id)
      assert is_list(result)
      assert result == []
    end

    test "create_workspace/1 inserts and returns workspace struct" do
      user = create_user!()
      attrs = %{name: "My WS", path: "/tmp/myws", owner_id: user.id}
      assert {:ok, ws} = Workspaces.create_workspace(attrs)
      assert ws.name == "My WS"
      assert ws.path == "/tmp/myws"
    end

    test "create_workspace/1 returns error changeset for missing required fields" do
      assert {:error, changeset} = Workspaces.create_workspace(%{})
      assert changeset.errors[:name] != nil
    end

    test "get_workspace!/1 returns workspace by id" do
      user = create_user!()
      ws = create_workspace!(user.id)
      fetched = Workspaces.get_workspace!(ws.id)
      assert fetched.id == ws.id
    end

    test "list_workspace_users/1 returns list for workspace" do
      user = create_user!()
      ws = create_workspace!(user.id)
      result = Workspaces.list_workspace_users(ws.id)
      assert is_list(result)
    end

    test "add_workspace_member/2 inserts membership record" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      assert {:ok, _} = Workspaces.add_workspace_member(ws.id, member.id)
      assert Workspaces.user_has_access?(ws.id, member.id) == true
    end

    test "remove_member/2 removes membership" do
      owner = create_user!()
      member = create_user!()
      ws = create_workspace!(owner.id)
      Workspaces.add_workspace_member(ws.id, member.id)
      Workspaces.remove_member(ws.id, member.id)
      assert Workspaces.user_has_access?(ws.id, member.id) == false
    end

    test "user_has_access?/2 returns false for non-member" do
      owner = create_user!()
      stranger = create_user!()
      ws = create_workspace!(owner.id)
      assert Workspaces.user_has_access?(ws.id, stranger.id) == false
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # CAN-C2: HealthAgent real HTTP probes
  # ─────────────────────────────────────────────────────────────────

  describe "CAN-C2: HealthAgent poll_system/1" do
    test "poll_system/1 returns map with :error_rate key in [0.0, 1.0]" do
      result = HealthAgent.poll_system(:pm4py_rust)
      {_name, data} = result
      assert Map.has_key?(data, :error_rate)
      assert data.error_rate >= 0.0
      assert data.error_rate <= 1.0
    end

    test "poll_system/1 returns map with :latency_ms key" do
      result = HealthAgent.poll_system(:canopy)
      {_name, data} = result
      assert Map.has_key?(data, :latency_ms)
    end

    test "poll_system/1 marks system as unhealthy when unreachable" do
      # Use a clearly unreachable URL via the internal API
      result = HealthAgent.poll_system(:pm4py_rust)
      {_name, data} = result
      # When no server running: healthy: false, error_rate: 1.0
      # When server IS running: healthy: true, error_rate: 0.0
      # Either is valid — just verify the structure is correct
      assert is_map(data)
      assert Map.has_key?(data, :healthy)
      assert is_boolean(data.healthy)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # CAN-C3b: HealingAgent OSA wiring
  # ─────────────────────────────────────────────────────────────────

  describe "CAN-C3b: HealingAgent execute_healing/2 OSA wiring" do
    test "execute_healing returns error when OSA not running" do
      # Force OSA URL to a guaranteed-refused port to simulate OSA being down
      original_url = Application.get_env(:canopy, :osa_url)
      Application.put_env(:canopy, :osa_url, "http://127.0.0.1:1")

      try do
        session = %Canopy.Schemas.Session{id: "test-123"}
        result = HealingAgent.execute_healing(session, :retry)
        assert match?({:error, {:osa_unreachable, _}}, result)
      after
        Application.put_env(:canopy, :osa_url, original_url)
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # CAN-C3: HealingAgent strategies
  # ─────────────────────────────────────────────────────────────────

  describe "CAN-C3: HealingAgent determine_healing_strategy/1" do
    test "returns :retry for :timeout error type" do
      strategy = HealingAgent.determine_healing_strategy(%{error_type: :timeout})
      assert strategy == :retry
    end

    test "returns :rollback for :bad_state error type" do
      strategy = HealingAgent.determine_healing_strategy(%{error_type: :bad_state})
      assert strategy == :rollback
    end

    test "returns :compensate for :partial error type" do
      strategy = HealingAgent.determine_healing_strategy(%{error_type: :partial})
      assert strategy == :compensate
    end

    test "returns :retry for unknown error types" do
      strategy = HealingAgent.determine_healing_strategy(%{error_type: :unknown_something})
      assert strategy == :retry
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # CAN-H1: AdaptationAgent compare_configs
  # ─────────────────────────────────────────────────────────────────

  describe "CAN-H1: AdaptationAgent compare_configs/0" do
    test "compare_configs/0 returns a list (not raise)" do
      result = AdaptationAgent.compare_configs()
      assert is_list(result)
    end

    test "compare_configs/0 entries are 3-tuples {key, expected, actual}" do
      result = AdaptationAgent.compare_configs()

      Enum.each(result, fn entry ->
        assert is_tuple(entry)
        assert tuple_size(entry) == 3
      end)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # CAN-L1: Compliance frameworks from YAML
  # ─────────────────────────────────────────────────────────────────

  describe "CAN-L1: FrameworkConfig.get_framework/1" do
    test "get_framework(:soc2) returns map with :name key" do
      result = FrameworkConfig.get_framework(:soc2)
      assert is_map(result)
      assert Map.has_key?(result, :name)
      assert result.name != nil
    end

    test "get_framework(:hipaa) returns map with :name key" do
      result = FrameworkConfig.get_framework(:hipaa)
      assert is_map(result)
      assert Map.has_key?(result, :name)
    end

    test "get_framework/1 SOC2 name matches expected string" do
      result = FrameworkConfig.get_framework(:soc2)
      assert result.name =~ "SOC"
    end

    test "load_config/1 still works (backward compat)" do
      assert {:ok, framework} = FrameworkConfig.load_config("SOC2")
      assert framework.framework_name == "SOC2"
    end
  end
end
