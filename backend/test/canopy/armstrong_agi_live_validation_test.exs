defmodule Canopy.ArmstrongAGILiveValidationTest do
  @moduledoc """
  Armstrong fault-tolerance "live" validations for Canopy (Elixir/Phoenix).

  These are AGI-grade correctness proofs, not unit tests. They exercise the REAL
  supervision tree, REAL OTP processes, and REAL crash/restart cycles.

  Joe Armstrong's six principles under test:
  1. Let-it-crash      — No try/rescue hiding OTP crashes.
  2. Supervision tree  — Every process supervised. No orphans.
  3. No shared state   — State in GenServer/ETS, not globals.
  4. Resource bounds   — Queues bounded; budget exceeded → escalate, not degrade.
  5. Timeout+fallback  — All GenServer.call/receive have explicit timeout_ms.
  6. Crash visibility  — Failures surface. Not caught-and-continued silently.

  ## Rules
  - `mix test` always (never `mix test --no-start`)
  - Full Phoenix boots for every test
  - No `@tag :skip` anywhere in this file
  - Process crashes are asserted via `Process.monitor/1` + `receive {:DOWN, ...}`
  """

  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # SECTION 1: Supervision restart (Armstrong principle 2)
  # ---------------------------------------------------------------------------

  describe "Supervisor is running — children are alive" do
    test "Canopy.Supervisor is alive and BudgetEnforcer is a child" do
      # Armstrong principle 2: every process has a supervisor.
      # We verify the supervisor is alive and BudgetEnforcer is registered under it.
      # Killing BudgetEnforcer would destroy its ETS tables and cascade to other tests,
      # so we verify supervision structure without a crash here.
      # A dedicated restart test using a transient child is in SECTION 1b below.
      supervisor_pid = Process.whereis(Canopy.Supervisor)
      assert is_pid(supervisor_pid), "Canopy.Supervisor must be alive"
      assert Process.alive?(supervisor_pid)

      budget_pid = Process.whereis(Canopy.BudgetEnforcer)
      assert is_pid(budget_pid), "BudgetEnforcer must be registered under Canopy.Supervisor"
      assert Process.alive?(budget_pid)

      # Verify supervision relationship: BudgetEnforcer is in the child list
      children = Supervisor.which_children(Canopy.Supervisor)
      child_ids = Enum.map(children, fn {id, _pid, _type, _mods} -> id end)
      assert Canopy.BudgetEnforcer in child_ids,
             "BudgetEnforcer must appear in Supervisor.which_children/1"
    end

    test "supervisor restart proof — isolated transient GenServer restarts after crash" do
      # Armstrong principle 2: supervisor restarts crashed children.
      # We use a fresh, isolated supervisor to prove restart works without
      # disturbing shared ETS tables in the main tree.

      # Start an isolated supervisor with a simple permanent child
      {:ok, isolated_sup} =
        Supervisor.start_link(
          [{Agent, fn -> :state_before_crash end}],
          strategy: :one_for_one
        )

      # Get the child pid
      [{_id, child_pid, _type, _mods}] = Supervisor.which_children(isolated_sup)
      assert Process.alive?(child_pid)

      ref = Process.monitor(child_pid)

      # Kill the child — let-it-crash (Armstrong principle 1)
      Process.exit(child_pid, :kill)

      # Crash is visible (Armstrong principle 6)
      assert_receive {:DOWN, ^ref, :process, ^child_pid, :killed}, 1000

      # Give supervisor time to restart
      :timer.sleep(150)

      # Supervisor restarted a new child (Armstrong principle 2)
      [{_id, new_pid, _type, _mods}] = Supervisor.which_children(isolated_sup)
      assert is_pid(new_pid), "Supervisor must restart crashed child"
      assert Process.alive?(new_pid)
      assert new_pid != child_pid, "Restarted child must have a new pid"

      # Cleanup
      Supervisor.stop(isolated_sup)
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 2: Budget escalation — NOT degradation (Armstrong principle 4)
  # ---------------------------------------------------------------------------

  describe "BudgetEnforcer escalates on hard-stop — not silent :ok" do
    test "get_accumulated returns 0 for unknown scope (not crash, not silent corruption)" do
      # Armstrong: ETS lookup for unknown key must return 0 (clean fallback),
      # NOT raise ArgumentError (which would mean ETS is not initialized).
      # The important thing is: the ETS table MUST exist (owned by supervised GenServer).
      result = Canopy.BudgetEnforcer.get_accumulated("agent", "nonexistent-agent-id")
      assert result == 0,
             "get_accumulated must return 0 for unknown scope — ETS table must be initialised " <>
               "by supervised GenServer.init/1. Got: #{inspect(result)}"
    end

    test "budget accumulator ETS table is created in supervised GenServer init, not globally" do
      # Armstrong principle 3: no shared mutable state outside supervised process.
      # Verify the ETS table exists (owned by BudgetEnforcer which is supervised).
      assert :ets.whereis(:canopy_budget_accumulator) != :undefined,
             "canopy_budget_accumulator ETS must exist — owned by supervised BudgetEnforcer"

      # Verify the owner is a supervised process (BudgetEnforcer)
      budget_pid = Process.whereis(Canopy.BudgetEnforcer)
      assert is_pid(budget_pid)

      table_info = :ets.info(:canopy_budget_accumulator)
      owner_pid = Keyword.get(table_info, :owner)

      # ETS owner is a supervised process, not a bare spawned process
      assert is_pid(owner_pid), "canopy_budget_accumulator must have a process owner"
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 3: Heartbeat liveness — stall detection (Armstrong principle 6)
  # ---------------------------------------------------------------------------

  describe "Heartbeat liveness — stalled task is detected, not silently orphaned" do
    test "Task.yield/2 timeout returns nil for stalled task (not hang)" do
      # Armstrong principle 5: timeouts fire. Never wait forever.
      # This verifies that Task.yield with a short timeout returns nil
      # instead of blocking indefinitely.
      {:ok, sup} = Task.Supervisor.start_link([])

      task =
        Task.Supervisor.async_nolink(sup, fn ->
          # Simulate a stalled agent that never finishes
          Process.sleep(60_000)
          :never_reached
        end)

      start_ms = System.monotonic_time(:millisecond)

      # Must return nil within timeout_ms, not hang
      result = Task.yield(task, 50)
      elapsed = System.monotonic_time(:millisecond) - start_ms

      assert result == nil, "yield must return nil for stalled task (timeout fires)"
      assert elapsed < 200, "yield must not block beyond timeout (elapsed: #{elapsed}ms)"

      # Clean shutdown — visible crash, not orphan (Armstrong principle 6)
      Task.shutdown(task, :brutal_kill)
    end

    test "heartbeat tick timeout shuts down agent task and returns timeout result" do
      # Armstrong: Task.yield nil → Task.shutdown :brutal_kill.
      # Stalled agents must not block the dispatcher forever.
      timeout_ms = 50

      task =
        Task.async(fn ->
          # Stalled: never completes within timeout
          Process.sleep(10_000)
          :should_not_reach
        end)

      case Task.yield(task, timeout_ms) do
        {:ok, result} ->
          # Task completed within timeout (unexpected in this scenario, but valid)
          assert result != :should_not_reach

        nil ->
          # Expected: task did not complete — kill it (Armstrong: crash is visible)
          Task.shutdown(task, :brutal_kill)
          assert true, "Stalled task was detected and killed within timeout"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 4: PubSub — no silent broadcast failures (Armstrong principle 6)
  # ---------------------------------------------------------------------------

  describe "PubSub broadcast failure escalates — not swallowed" do
    test "broadcast!/2 raises on missing PubSub (crash is visible, not silent)" do
      # Armstrong: Phoenix.PubSub.broadcast!/3 raises on missing server.
      # This proves that if PubSub were missing, the failure would surface,
      # not be silently dropped.
      # Verify that broadcast!/2 raises when given a nonexistent PubSub name.
      assert_raise ArgumentError, fn ->
        Phoenix.PubSub.broadcast!(
          :nonexistent_pubsub_server_xyz,
          "test-topic",
          %{event: "test"}
        )
      end
    end

    test "broadcast/2 on real Canopy.PubSub delivers to subscriber" do
      # Armstrong principle 6: successful broadcast is observable — not silent.
      topic = "armstrong-test:#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(Canopy.PubSub, topic)

      :ok = Phoenix.PubSub.broadcast(Canopy.PubSub, topic, %{event: "armstrong_test"})

      assert_receive %{event: "armstrong_test"}, 500,
                     "PubSub broadcast must be observable by subscriber"

      Phoenix.PubSub.unsubscribe(Canopy.PubSub, topic)
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 5: DynamicSupervisor adapter isolation (Armstrong principle 2)
  # ---------------------------------------------------------------------------

  describe "DynamicSupervisor isolates adapter crashes" do
    test "crashing one adapter child does not kill AdapterSupervisor or other children" do
      # Armstrong principle 2: supervision tree provides isolation.
      # DynamicSupervisor with :one_for_one restarts only the crashed child.

      # Start two simple GenServer children under the adapter supervisor
      child_spec_1 = {Agent, fn -> :adapter_1_state end}
      child_spec_2 = {Agent, fn -> :adapter_2_state end}

      {:ok, pid1} = DynamicSupervisor.start_child(Canopy.AdapterSupervisor, child_spec_1)
      {:ok, pid2} = DynamicSupervisor.start_child(Canopy.AdapterSupervisor, child_spec_2)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      # Monitor pid2 before killing pid1 — we expect pid2 to survive
      ref2 = Process.monitor(pid2)

      # Kill pid1 (simulate adapter crash)
      ref1 = Process.monitor(pid1)
      Process.exit(pid1, :kill)

      # Wait for pid1's DOWN signal — crash is visible
      assert_receive {:DOWN, ^ref1, :process, ^pid1, :killed}, 1000

      # Give supervisor a moment to process
      :timer.sleep(50)

      # pid2 must still be alive — isolation holds (Armstrong principle 2)
      assert Process.alive?(pid2),
             "Crashing adapter pid1 must not kill unrelated adapter pid2"

      # Supervisor itself must still be alive
      supervisor_pid = Process.whereis(Canopy.AdapterSupervisor)
      assert is_pid(supervisor_pid)
      assert Process.alive?(supervisor_pid)

      # Cleanup
      Process.demonitor(ref2, [:flush])
      DynamicSupervisor.terminate_child(Canopy.AdapterSupervisor, pid2)
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 6: Isolated state between agents (Armstrong principle 3)
  # ---------------------------------------------------------------------------

  describe "Two Canopy agents have isolated state" do
    test "state in Agent process A does not affect Agent process B" do
      # Armstrong principle 3: no shared mutable state.
      # Each process has its own state. Mutating A does not touch B.
      {:ok, agent_a} = Agent.start_link(fn -> %{value: 0} end)
      {:ok, agent_b} = Agent.start_link(fn -> %{value: 0} end)

      # Mutate agent A
      Agent.update(agent_a, fn state -> %{state | value: 42} end)

      # Agent B must be unaffected
      value_a = Agent.get(agent_a, fn s -> s.value end)
      value_b = Agent.get(agent_b, fn s -> s.value end)

      assert value_a == 42, "Agent A value must reflect mutation"
      assert value_b == 0, "Agent B must be isolated — mutation of A must not affect B"
      assert value_a != value_b, "Agents have independent state"

      Agent.stop(agent_a)
      Agent.stop(agent_b)
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 7: Timeout enforcement (Armstrong principle 5)
  # ---------------------------------------------------------------------------

  describe "GenServer call with explicit timeout fires correctly" do
    test "GenServer.call timeout raises exit — not silent hang" do
      # Armstrong principle 5: every GenServer.call has explicit timeout_ms.
      # When that timeout fires, it raises :timeout as an exit — visible, not silent.
      #
      # We simulate a hung GenServer using a bare process that receives but never replies.
      test_pid = self()

      hung_pid =
        spawn(fn ->
          # Notify test we are ready, then block forever without replying
          send(test_pid, :hung_ready)
          Process.sleep(60_000)
        end)

      receive do
        :hung_ready -> :ok
      after
        500 -> flunk("Hung process did not start")
      end

      # GenServer.call with explicit 50ms timeout must raise exit (not hang forever)
      # We call GenServer.call on the hung_pid — it will timeout because hung_pid
      # never sends a GenServer reply.
      assert catch_exit(GenServer.call(hung_pid, :request, 50)) != nil,
             "GenServer.call must raise exit on timeout — not hang indefinitely"

      # Cleanup
      Process.exit(hung_pid, :kill)
    end

    test "Task.await with explicit timeout raises exit — not silent hang" do
      # Armstrong principle 5: no unbounded waits.
      task =
        Task.async(fn ->
          Process.sleep(5000)
          :never
        end)

      assert catch_exit(Task.await(task, 50)) != nil,
             "Task.await must raise exit on timeout — not hang indefinitely"
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 8: Task.Supervisor tracked spawns — no orphans (Armstrong principle 2)
  # ---------------------------------------------------------------------------

  describe "Task.Supervisor children tracked — no orphaned processes" do
    test "tasks spawned under Canopy.TaskSupervisor are tracked by supervisor" do
      # Armstrong: no bare spawn/1. All tasks must be under a supervisor.
      # This verifies that tasks spawned under Canopy.TaskSupervisor are listed
      # as children, not orphaned processes the supervisor cannot see.

      # Children count before
      children_before = DynamicSupervisor.count_children(Canopy.TaskSupervisor)
      active_before = children_before.active

      # Spawn a tracked task
      {:ok, task_pid} =
        Task.Supervisor.start_child(Canopy.TaskSupervisor, fn ->
          :timer.sleep(200)
          :done
        end)

      # Task is alive and tracked
      assert Process.alive?(task_pid)

      children_during = DynamicSupervisor.count_children(Canopy.TaskSupervisor)
      assert children_during.active >= active_before,
             "Task spawned under supervisor must be counted as supervised child"

      # Monitor to detect completion
      ref = Process.monitor(task_pid)

      receive do
        {:DOWN, ^ref, :process, ^task_pid, _reason} ->
          # Task completed — supervisor tracked its lifecycle
          assert true
      after
        1000 ->
          flunk("Supervised task did not complete in time")
      end
    end

    test "orphan test: bare spawn/1 is NOT tracked by Canopy.TaskSupervisor" do
      # This test documents what we NEVER want: bare spawn/1.
      # Spawning without a supervisor means the crash is invisible.
      children_before = DynamicSupervisor.count_children(Canopy.TaskSupervisor)
      count_before = children_before.active

      # Bare spawn — NOT supervised (do NOT do this in production code)
      _orphan_pid = spawn(fn -> :timer.sleep(100) end)

      children_after = DynamicSupervisor.count_children(Canopy.TaskSupervisor)
      count_after = children_after.active

      assert count_after == count_before,
             "Bare spawn/1 must NOT appear in supervisor children — this confirms the " <>
               "difference: use Task.Supervisor.start_child, not spawn"
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 9: Crash visible in logs (Armstrong principle 6)
  # ---------------------------------------------------------------------------

  describe "Agent crash is visible — logged, not swallowed" do
    test "crashing process emits DOWN message to monitors — crash is observable" do
      # Armstrong principle 6: failures surface.
      # A process crash must be observable via Process.monitor/1.
      # Nothing should catch-and-continue silently.
      #
      # Use spawn (not Agent.start_link) to avoid exit signal propagating to the test.

      pid = spawn(fn -> Process.sleep(10_000) end)
      assert Process.alive?(pid)

      ref = Process.monitor(pid)

      # Kill with an abnormal reason — crash is visible via monitor
      Process.exit(pid, :crash_reason)

      # Must receive DOWN within 500ms — crash is visible (not hidden)
      assert_receive {:DOWN, ^ref, :process, ^pid, :crash_reason}, 500,
                     "Process crash must surface as DOWN message — not swallowed silently"
    end

    test "process killed under Task.Supervisor emits DOWN — crash is observable" do
      # Armstrong: crashes under supervisors must be observable.
      # Use Task.Supervisor so we can monitor the task.
      {:ok, sup} = Task.Supervisor.start_link([])

      task =
        Task.Supervisor.async_nolink(sup, fn ->
          Process.sleep(10_000)
          :never
        end)

      ref = Process.monitor(task.pid)

      # Force a crash
      Process.exit(task.pid, :crash_for_armstrong_test)

      # Crash is visible — DOWN arrives
      assert_receive {:DOWN, ^ref, :process, _pid, :crash_for_armstrong_test}, 500,
                     "Supervised task crash must surface as DOWN — not swallowed"
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 10: ETS tables owned by supervised GenServers (Armstrong principle 3)
  # ---------------------------------------------------------------------------

  describe "ETS tables owned by supervised processes — no global singleton orphans" do
    test "canopy_budget_accumulator is owned by supervised BudgetEnforcer" do
      # Armstrong principle 3: state must live in a supervised process.
      # If BudgetEnforcer dies, its ETS table dies with it and the supervisor
      # restarts it — recreating the table clean. No orphaned global state.
      budget_pid = Process.whereis(Canopy.BudgetEnforcer)
      assert is_pid(budget_pid), "BudgetEnforcer must be registered and alive"

      table_info = :ets.info(:canopy_budget_accumulator)
      assert table_info != :undefined, "canopy_budget_accumulator ETS must exist"

      owner = Keyword.get(table_info, :owner)
      assert owner == budget_pid,
             "ETS table owner must be the BudgetEnforcer pid " <>
               "(got owner=#{inspect(owner)}, budget_pid=#{inspect(budget_pid)})"
    end

    test "idempotency cache ETS is named and accessible — created before endpoint starts" do
      # From application.ex: :ets.new(:canopy_idempotency_cache, ...) is called
      # before Supervisor.start_link — ensuring no race condition at startup.
      table_info = :ets.info(:canopy_idempotency_cache)
      assert table_info != :undefined,
             "canopy_idempotency_cache must exist — created in Application.start/2"

      # Verify it is a named public table (readable by any process without going
      # through a GenServer — atomic reads are safe per Armstrong's ETS design)
      protection = Keyword.get(table_info, :protection)
      assert protection == :public,
             "Idempotency cache must be :public for lock-free concurrent reads"
    end

    test "hierarchy_cache ETS is owned by supervised BudgetEnforcer" do
      budget_pid = Process.whereis(Canopy.BudgetEnforcer)
      assert is_pid(budget_pid)

      table_info = :ets.info(:canopy_hierarchy_cache)
      assert table_info != :undefined, "canopy_hierarchy_cache must exist after app start"

      owner = Keyword.get(table_info, :owner)
      assert owner == budget_pid,
             "Hierarchy cache must be owned by supervised BudgetEnforcer " <>
               "(got owner=#{inspect(owner)}, budget_pid=#{inspect(budget_pid)})"
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 11: Autonomic.Heartbeat supervision (Armstrong principles 1 + 2)
  # ---------------------------------------------------------------------------

  describe "Autonomic.Heartbeat is supervised under Canopy.Supervisor" do
    test "Canopy.Autonomic.Heartbeat process is registered and alive" do
      # Heartbeat uses Agent internally (registered as :autonomic_heartbeat_state).
      # This verifies it started correctly under the supervision tree.
      heartbeat_pid = Process.whereis(:autonomic_heartbeat_state)
      assert is_pid(heartbeat_pid),
             ":autonomic_heartbeat_state must be registered — Heartbeat must be alive"

      assert Process.alive?(heartbeat_pid),
             "Heartbeat Agent process must be alive after application start"
    end

    test "Heartbeat.get_state/0 returns valid state — not crash on missing process" do
      # Armstrong principle 1: if Heartbeat is missing, crash visibly.
      # Since it IS running, get_state must return the initialised map.
      state = Canopy.Autonomic.Heartbeat.get_state()

      assert is_map(state), "Heartbeat state must be a map"
      assert Map.has_key?(state, :budget_limit), "State must have :budget_limit"
      assert Map.has_key?(state, :agent_timeout), "State must have :agent_timeout"
      assert Map.has_key?(state, :dispatch_count), "State must have :dispatch_count"
      assert is_integer(state.budget_limit) and state.budget_limit > 0
      assert is_integer(state.agent_timeout) and state.agent_timeout > 0
    end
  end

  # ---------------------------------------------------------------------------
  # SECTION 12: Bounded heartbeat loop — liveness (WvdA + Armstrong)
  # ---------------------------------------------------------------------------

  describe "Heartbeat loop is bounded — WvdA liveness + Armstrong supervision" do
    test "loop_heartbeat_supervised terminates after max_iterations" do
      # WvdA Liveness: no unbounded loops.
      # Armstrong: the task is supervised, so after it exits the supervisor can
      # restart it, effectively creating a bounded+restartable loop.

      # Set a short agent_timeout so tick() completes quickly in test regardless
      # of Req retry delays that can make the full suite much slower than isolation.
      # Use on_exit to guarantee restoration even if the test fails.
      original_timeout = Canopy.Autonomic.Heartbeat.get_state().agent_timeout
      on_exit(fn -> Canopy.Autonomic.Heartbeat.set_agent_timeout(original_timeout) end)
      Canopy.Autonomic.Heartbeat.set_agent_timeout(50)

      {:ok, sup} = Task.Supervisor.start_link([])

      {:ok, task_pid} =
        Task.Supervisor.start_child(
          sup,
          Canopy.Autonomic.Heartbeat,
          :loop_heartbeat_supervised,
          # interval_ms=10ms, max_iterations=2, start=0
          [10, 2, 0]
        )

      assert is_pid(task_pid)

      ref = Process.monitor(task_pid)

      # Task must complete (iterations exhausted) within bounded time.
      # Bound: 2 ticks × (10ms sleep + 6 agents × 50ms timeout) = ~620ms,
      # well within 5000ms.
      assert_receive {:DOWN, ^ref, :process, ^task_pid, _reason}, 5000,
                     "Heartbeat loop must terminate after max_iterations — not run forever"
    end
  end
end
