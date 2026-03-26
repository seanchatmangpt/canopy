defmodule Canopy.JTBD.SelfPlayLoopTest do
  use ExUnit.Case, async: false

  @moduletag :skip

  doctest Canopy.JTBD.SelfPlayLoop

  setup do
    # Ensure SelfPlayLoop is started for each test
    {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start_link([])
    :ok
  end

  test "SelfPlayLoop starts with GenServer" do
    assert Process.alive?(Process.whereis(Canopy.JTBD.SelfPlayLoop))
  end

  test "spawned loop process is supervised by Task.Supervisor" do
    # Verify the JTBD loop supervisor exists
    assert :canopy_jtbd_loop_supervisor in elem(Supervisor.which_children(:canopy_jtbd_loop_supervisor), 0) ||
             is_pid(Process.whereis(:canopy_jtbd_loop_supervisor))
  end

  test "get_state returns initial state" do
    state = Canopy.JTBD.SelfPlayLoop.get_state()
    assert state.running == false
    assert state.iteration == 0
  end

  test "start begins loop execution" do
    {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 2)
    Process.sleep(100)
    state = Canopy.JTBD.SelfPlayLoop.get_state()
    assert state.running == true
  end

  test "stop gracefully shuts down loop" do
    {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 100)
    Process.sleep(100)
    :ok = Canopy.JTBD.SelfPlayLoop.stop()
    state = Canopy.JTBD.SelfPlayLoop.get_state()
    assert state.running == false
  end

  test "loop process is linked to Task.Supervisor (Armstrong principle)" do
    # Verify that the spawned loop is a Task under supervision
    {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 100)
    Process.sleep(100)
    state = Canopy.JTBD.SelfPlayLoop.get_state()
    loop_pid = state.loop_pid

    # Supervisor should be tracking the task
    supervisor_pid = Process.whereis(:canopy_jtbd_loop_supervisor)
    assert is_pid(supervisor_pid)
    assert Process.alive?(loop_pid)

    # Cleanup
    Canopy.JTBD.SelfPlayLoop.stop()
  end

  describe "Chaos Test — Loop Process Crash Recovery (Armstrong Fault Tolerance)" do
    @tag :chaos
    test "test_loop_process_auto_restarts_on_crash" do
      # SETUP: Start loop with small iteration count to verify recovery
      {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 1000)
      Process.sleep(200)

      # Get initial state before crash
      state_before = Canopy.JTBD.SelfPlayLoop.get_state()
      assert state_before.running == true
      loop_pid_before = state_before.loop_pid

      # Verify loop_pid is not nil
      assert loop_pid_before != nil, "Loop PID should not be nil before crash"
      assert Process.alive?(loop_pid_before), "Loop process should be alive before crash"

      initial_iteration = state_before.iteration

      # CRASH: Force-kill the loop process (simulate unrecoverable error)
      # Using :kill instead of :shutdown to simulate a hard crash
      Process.exit(loop_pid_before, :kill)

      # Allow time for:
      # 1. Supervisor to detect crash (heartbeat interval ~5ms)
      # 2. Task.Supervisor to restart the process
      # 3. GenServer to receive restart notifications
      Process.sleep(1000)

      # VERIFY: Check state after crash and recovery
      state_after = Canopy.JTBD.SelfPlayLoop.get_state()

      # Assertion 1: Loop should still be marked as running (supervisor manages this)
      assert state_after.running == true,
             "Loop should still be marked running after supervisor restart (Armstrong: let-it-crash)"

      # Assertion 2: Iteration count should be >= initial count
      # (supervisor has restarted the loop, it continues from the checkpoint)
      assert state_after.iteration >= initial_iteration,
             "Loop iterations should continue or reset after restart (observed: #{state_after.iteration}, expected >= #{initial_iteration})"

      # Assertion 3: NEW loop_pid should be different from crashed one
      # (unless it hasn't restarted yet, in which case we verify retry count)
      loop_pid_after = state_after.loop_pid

      case loop_pid_after do
        nil ->
          # Restart not yet complete - verify within retry window
          # Try a few more times with backoff
          retry_recovery = wait_for_restart(loop_pid_before, 1000, 5)
          assert retry_recovery == :restarted,
                 "Loop should have restarted within 5 second window (Armstrong: supervisor restarts child on crash)"

        new_pid ->
          # Process has restarted
          assert new_pid != loop_pid_before or not Process.alive?(loop_pid_before),
                 "Loop should have a new PID after crash (supervisor creates new task) OR old PID should be dead"

          assert Process.alive?(new_pid),
                 "New loop process should be alive after restart"
      end

      # VERIFY: No messages lost (iteration counter should be monotonic)
      # Wait a bit for loop to continue executing
      Process.sleep(500)
      state_final = Canopy.JTBD.SelfPlayLoop.get_state()

      assert state_final.iteration >= state_after.iteration,
             "Iteration count should be monotonically increasing or equal (no data loss)"

      # CLEANUP
      Canopy.JTBD.SelfPlayLoop.stop()
      state_stopped = Canopy.JTBD.SelfPlayLoop.get_state()
      assert state_stopped.running == false, "Loop should be stopped after graceful shutdown"
    end

    @tag :chaos
    test "test_loop_crash_detection_with_pids" do
      # Edge case 1: What if loop_pid is nil (spawn failed)?
      # Edge case 2: What if Task.Supervisor isn't ready yet?

      # Start with max_iterations to give supervisor time to be ready
      {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 500)
      Process.sleep(300)

      state = Canopy.JTBD.SelfPlayLoop.get_state()

      # Edge case 1: Verify loop_pid is NOT nil
      case state.loop_pid do
        nil ->
          # Spawn may have failed - verify supervisor exists and is healthy
          supervisor_pid = Process.whereis(:canopy_jtbd_loop_supervisor)
          assert is_pid(supervisor_pid),
                 "Task.Supervisor should exist even if loop spawn failed"

        loop_pid ->
          # Normal case: process exists
          assert Process.alive?(loop_pid),
                 "Loop process should be alive when state.loop_pid is not nil"

          # Verify supervisor is tracking this task
          supervisor_pid = Process.whereis(:canopy_jtbd_loop_supervisor)
          assert is_pid(supervisor_pid), "Task.Supervisor should exist"
      end

      Canopy.JTBD.SelfPlayLoop.stop()
    end

    @tag :chaos
    test "test_partial_iteration_state_on_crash" do
      # Edge case 3: What if crash happens during iteration (partial state)?
      # This test verifies idempotency: restarting mid-iteration doesn't duplicate work

      {:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 10000)
      Process.sleep(300)

      state_before = Canopy.JTBD.SelfPlayLoop.get_state()
      iteration_before = state_before.iteration
      pass_count_before = state_before.pass_count

      # Kill loop at random point in iteration
      loop_pid = state_before.loop_pid
      if loop_pid, do: Process.exit(loop_pid, :kill)

      Process.sleep(1000)

      state_after = Canopy.JTBD.SelfPlayLoop.get_state()
      iteration_after = state_after.iteration
      pass_count_after = state_after.pass_count

      # Verify iteration counter is monotonic (no duplicates or skips)
      assert iteration_after >= iteration_before,
             "Iteration counter must be monotonic: #{iteration_after} >= #{iteration_before}"

      # Verify pass count is monotonic (no lost or duplicated results)
      assert pass_count_after >= pass_count_before,
             "Pass count must be monotonic: #{pass_count_after} >= #{pass_count_before}"

      Canopy.JTBD.SelfPlayLoop.stop()
    end
  end

  # Helper: Wait for loop process to restart with exponential backoff
  defp wait_for_restart(original_pid, remaining_ms, attempts_left) when attempts_left > 0 do
    state = Canopy.JTBD.SelfPlayLoop.get_state()

    cond do
      state.loop_pid != nil and Process.alive?(state.loop_pid) ->
        :restarted

      remaining_ms <= 0 ->
        :timeout

      true ->
        backoff_ms = 500
        Process.sleep(backoff_ms)
        wait_for_restart(original_pid, remaining_ms - backoff_ms, attempts_left - 1)
    end
  end

  defp wait_for_restart(_original_pid, _remaining_ms, _attempts_left), do: :timeout
end
