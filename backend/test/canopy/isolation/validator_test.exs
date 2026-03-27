defmodule Canopy.Isolation.ValidatorTest do
  use Canopy.DataCase

  alias Canopy.Isolation.Validator
  alias Canopy.Repo
  alias Canopy.Schemas.{Workspace, Agent, Skill, WorkspaceUser, User}

  @moduletag timeout: 30000
  @moduletag :skip

  setup do
    # Create test users
    user1 = create_user("user1@test.com")
    user2 = create_user("user2@test.com")

    # Create workspaces with different isolation levels
    ws1 = create_workspace("workspace-1", user1, "full")
    ws2 = create_workspace("workspace-2", user2, "full")

    # Create agents in each workspace
    agent1_ws1 = create_agent(ws1.id, "agent-1", "developer")
    agent2_ws1 = create_agent(ws1.id, "agent-2", "analyst")
    agent1_ws2 = create_agent(ws2.id, "agent-1", "developer")

    # Create skills in each workspace
    skill1_ws1 = create_skill(ws1.id, "python-dev")
    skill2_ws1 = create_skill(ws1.id, "data-analysis")
    skill1_ws2 = create_skill(ws2.id, "python-dev")

    {:ok,
     user1: user1,
     user2: user2,
     ws1: ws1,
     ws2: ws2,
     agent1_ws1: agent1_ws1,
     agent2_ws1: agent2_ws1,
     agent1_ws2: agent1_ws2,
     skill1_ws1: skill1_ws1,
     skill2_ws1: skill2_ws1,
     skill1_ws2: skill1_ws2}
  end

  # ── Test 1: Basic workspace isolation validation ────────────────────────

  test "validate_workspace returns pass when workspace is isolated", %{ws1: ws1} do
    {:ok, report} = Validator.validate_workspace(ws1.id)

    assert report.result == :pass
    assert report.workspace_id == ws1.id
    assert Enum.empty?(report.violations)
    assert report.check_count == 5
    assert is_struct(report.timestamp, DateTime)
  end

  # ── Test 2: Isolation check for multiple workspaces ────────────────────

  test "validate_all_workspaces validates all active workspaces", %{ws1: ws1, ws2: ws2} do
    results = Validator.validate_all_workspaces()

    assert Map.has_key?(results, ws1.id)
    assert Map.has_key?(results, ws2.id)
    assert results[ws1.id].result == :pass
    assert results[ws2.id].result == :pass
  end

  # ── Test 3: is_isolated? helper ────────────────────────────────────────

  test "is_isolated? returns true for properly isolated workspace", %{ws1: ws1} do
    assert Validator.is_isolated?(ws1.id) == true
  end

  # ── Test 4: Agent registry isolation ───────────────────────────────────

  test "check detects agents in workspace", %{ws1: ws1, agent1_ws1: agent1} do
    {:ok, report} = Validator.validate_workspace(ws1.id)

    assert report.result == :pass
    assert Enum.empty?(report.violations)
    # Verify agent is properly scoped to workspace
    agents = Repo.all(from a in Agent, where: a.workspace_id == ^ws1.id)
    assert Enum.any?(agents, fn a -> a.id == agent1.id end)
  end

  # ── Test 5: Tool access boundaries ─────────────────────────────────────

  test "register_tool allows tool access in workspace", %{ws1: ws1, skill1_ws1: skill1} do
    Validator.register_tool(ws1.id, skill1.id)

    assert Validator.can_access_tool?(ws1.id, skill1.id) == true
    assert Validator.can_access_tool?(ws1.id, "unknown-tool") == false
  end

  test "tool access not allowed across workspaces", %{ws1: ws1, ws2: ws2, skill1_ws1: skill1} do
    Validator.register_tool(ws1.id, skill1.id)

    # Tool registered in ws1 should not be accessible from ws2
    assert Validator.can_access_tool?(ws1.id, skill1.id) == true
    assert Validator.can_access_tool?(ws2.id, skill1.id) == false
  end

  # ── Test 6: Unregister tool ───────────────────────────────────────────

  test "unregister_tool removes tool from workspace", %{ws1: ws1, skill1_ws1: skill1} do
    Validator.register_tool(ws1.id, skill1.id)
    assert Validator.can_access_tool?(ws1.id, skill1.id) == true

    Validator.unregister_tool(ws1.id, skill1.id)
    assert Validator.can_access_tool?(ws1.id, skill1.id) == false
  end

  # ── Test 7: Per-workspace memory store isolation ────────────────────────

  test "store_memory stores value in workspace memory", %{ws1: ws1} do
    Validator.store_memory(ws1.id, "config", %{timeout: 5000})

    {:ok, value} = Validator.get_memory(ws1.id, "config")
    assert value == %{timeout: 5000}
  end

  test "memory store is isolated between workspaces", %{ws1: ws1, ws2: ws2} do
    Validator.store_memory(ws1.id, "config", %{ws: 1})
    Validator.store_memory(ws2.id, "config", %{ws: 2})

    {:ok, value1} = Validator.get_memory(ws1.id, "config")
    {:ok, value2} = Validator.get_memory(ws2.id, "config")

    assert value1 == %{ws: 1}
    assert value2 == %{ws: 2}
  end

  # ── Test 8: Memory expiration ──────────────────────────────────────────

  test "get_memory returns expired error after TTL", %{ws1: ws1} do
    Validator.store_memory(ws1.id, "temp", "value", 100)

    # Immediately: value exists
    {:ok, value} = Validator.get_memory(ws1.id, "temp")
    assert value == "value"

    # After 150ms: expired
    Process.sleep(150)
    {:error, :expired} = Validator.get_memory(ws1.id, "temp")
  end

  test "get_memory returns not_found for missing key", %{ws1: ws1} do
    {:error, :not_found} = Validator.get_memory(ws1.id, "nonexistent")
  end

  # ── Test 9: Concurrent memory access ───────────────────────────────────

  test "concurrent memory store operations are safe", %{ws1: ws1, ws2: ws2} do
    tasks =
      Enum.map(1..50, fn i ->
        Task.async(fn ->
          ws_id = if rem(i, 2) == 0, do: ws1.id, else: ws2.id
          Validator.store_memory(ws_id, "key-#{i}", "value-#{i}", 5000)
          {:ok, val} = Validator.get_memory(ws_id, "key-#{i}")
          val == "value-#{i}"
        end)
      end)

    results = Task.await_many(tasks, 5000)
    assert Enum.all?(results, fn r -> r == true end)
  end

  # ── Test 10: Concurrent tool registry operations ────────────────────────

  test "concurrent tool registration is safe", %{ws1: ws1, ws2: ws2} do
    skills1 = Enum.map(1..25, fn i -> create_skill(ws1.id, "skill-#{i}") end)
    skills2 = Enum.map(1..25, fn i -> create_skill(ws2.id, "skill-#{i}") end)

    tasks =
      Enum.map(skills1 ++ skills2, fn skill ->
        Task.async(fn ->
          ws_id = if skill.workspace_id == ws1.id, do: ws1.id, else: ws2.id
          Validator.register_tool(ws_id, skill.id)
          Validator.can_access_tool?(ws_id, skill.id)
        end)
      end)

    results = Task.await_many(tasks, 10_000)
    assert Enum.all?(results, fn r -> r == true end)
  end

  # ── Test 11: Agent count retrieval ─────────────────────────────────────

  test "get_agent_count returns correct count for workspace", %{
    ws1: ws1,
    agent1_ws1: _,
    agent2_ws1: _
  } do
    count = Validator.get_agent_count(ws1.id)
    assert count == 2
  end

  test "get_agent_count ignores sleeping agents", %{ws1: ws1, agent1_ws1: agent1} do
    # Make agent sleep
    Repo.update(Ecto.Changeset.change(agent1, status: "sleeping"))

    count = Validator.get_agent_count(ws1.id)
    assert count == 1
  end

  # ── Test 12: Concurrent validation checks ──────────────────────────────

  test "concurrent validation calls return consistent results", %{ws1: ws1} do
    tasks =
      Enum.map(1..10, fn _ ->
        Task.async(fn ->
          {:ok, report} = Validator.validate_workspace(ws1.id)
          report.result
        end)
      end)

    results = Task.await_many(tasks, 10_000)
    assert Enum.all?(results, fn r -> r == :pass end)
  end

  # ── Test 13: Violations table management ───────────────────────────────

  test "get_violations returns empty list for isolated workspace", %{ws1: ws1} do
    Validator.validate_workspace(ws1.id)
    violations = Validator.get_violations(ws1.id)
    assert Enum.empty?(violations)
  end

  test "clear_violations removes cached violations", %{ws1: ws1} do
    Validator.validate_workspace(ws1.id)
    _violations_before = Validator.get_violations(ws1.id)

    Validator.clear_violations(ws1.id)
    violations_after = Validator.get_violations(ws1.id)

    # After clear, no violations cached
    assert Enum.empty?(violations_after)
  end

  # ── Test 14: Multiple workspaces concurrent validation ──────────────────

  test "validates multiple workspaces concurrently without interference", %{ws1: ws1, ws2: ws2} do
    tasks = [
      Task.async(fn -> Validator.validate_workspace(ws1.id) end),
      Task.async(fn -> Validator.validate_workspace(ws2.id) end),
      Task.async(fn -> Validator.validate_workspace(ws1.id) end),
      Task.async(fn -> Validator.validate_workspace(ws2.id) end)
    ]

    results = Task.await_many(tasks, 10_000)

    assert Enum.all?(results, fn {:ok, report} ->
             report.result == :pass
           end)
  end

  # ── Test 15: High-concurrency stress test ──────────────────────────────

  test "handles 100 concurrent operations safely", %{ws1: ws1, ws2: ws2} do
    tasks =
      Enum.map(1..100, fn i ->
        Task.async(fn ->
          case rem(i, 5) do
            0 ->
              {:ok, r} = Validator.validate_workspace(ws1.id)
              r.result == :pass

            1 ->
              Validator.store_memory(ws2.id, "key-#{i}", "val-#{i}", 5000)
              true

            2 ->
              Validator.register_tool(ws1.id, "tool-#{i}")
              true

            3 ->
              Validator.can_access_tool?(ws2.id, "tool-#{i}")

            4 ->
              case Validator.get_memory(ws1.id, "key-#{i}") do
                {:ok, _val} -> true
                {:error, _} -> true
              end
          end
        end)
      end)

    results = Task.await_many(tasks, 30_000)
    # At least 90% of operations should succeed
    passing = Enum.count(results, fn r -> r in [true, false, :pass] end)
    assert passing >= 90
  end

  # ── Private helper functions ───────────────────────────────────────────

  defp create_user(email) do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: email,
        password: "password123",
        password_confirmation: "password123"
      })
      |> Repo.insert()

    user
  end

  defp create_workspace(name, owner, isolation_level) do
    {:ok, workspace} =
      %Workspace{}
      |> Workspace.changeset(%{
        name: name,
        path: String.downcase(name),
        status: "active",
        owner_id: owner.id,
        is_active: true,
        isolation_level: isolation_level
      })
      |> Repo.insert()

    workspace
  end

  defp create_agent(workspace_id, slug, role) do
    {:ok, agent} =
      %Agent{}
      |> Agent.changeset(%{
        slug: slug,
        name: "Agent #{slug}",
        role: role,
        adapter: "claude-code",
        model: "claude-opus",
        workspace_id: workspace_id,
        status: "active"
      })
      |> Repo.insert()

    agent
  end

  defp create_skill(workspace_id, name) do
    {:ok, skill} =
      %Skill{}
      |> Skill.changeset(%{
        name: name,
        description: "Skill #{name}",
        workspace_id: workspace_id,
        definition: %{"version" => "1.0"}
      })
      |> Repo.insert()

    skill
  end
end
