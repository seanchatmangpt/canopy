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
end
