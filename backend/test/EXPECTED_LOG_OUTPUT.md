# Expected Log Output During Chaos Test Execution

## Test Execution Flow & Logs

### Before Test Starts

```
Compiling 1 file (.ex)
Compiled successfully

ExUnit test runner starting...
```

---

## Test 1: `test_loop_process_auto_restarts_on_crash`

### Phase 1: SETUP (Lines 66-78)

**Test code:**
```elixir
{:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 1000)
Process.sleep(200)
state_before = Canopy.JTBD.SelfPlayLoop.get_state()
```

**Expected logs:**
```
[info] Wave 12 iteration 1: 7/10 scenarios passed (70.0%) in 245ms
[info] Attempting to run scenario: agent_decision_loop
[info] Attempting to run scenario: process_discovery
[info] Attempting to run scenario: compliance_check
[info] Attempting to run scenario: cross_system_handoff
[info] Attempting to run scenario: workspace_sync
[info] Attempting to run scenario: consensus_round
[info] Attempting to run scenario: healing_recovery
[info] Attempting to run scenario: a2a_deal_lifecycle
[info] Attempting to run scenario: mcp_tool_execution
[info] Attempting to run scenario: conformance_drift
```

**State snapshot:**
```
%{
  running: true,
  iteration: 1,
  loop_pid: #PID<0.1234.0>,
  pass_count: 7,
  fail_count: 3,
  pass_rate: 70.0
}
```

### Phase 2: CRASH (Line 82)

**Test code:**
```elixir
Process.exit(loop_pid_before, :kill)
# No log here — process dies immediately, no cleanup
Process.sleep(1000)
```

**What happens:**
- Loop process #PID<0.1234.0> receives :kill signal
- Process terminates immediately (no exception handler runs)
- Task.Supervisor detects dead task (within next heartbeat)
- Task.Supervisor callback restarts the task

**Expected logs (if supervisor is working):**
```
[warning] Task supervisor detected crash in async task
[info] Wave 12 iteration 2: 8/10 scenarios passed (80.0%) in 255ms ← New process continues!
[info] Attempting to run scenario: agent_decision_loop
[info] Attempting to run scenario: process_discovery
...
```

**What if supervisor is NOT working:**
```
(silence for 1000ms — no restart)
(no new iteration log)
```

### Phase 3: VERIFY RESTART (Lines 90-121)

**Test code:**
```elixir
state_after = Canopy.JTBD.SelfPlayLoop.get_state()
assert state_after.running == true
assert state_after.iteration >= initial_iteration
loop_pid_after = state_after.loop_pid
case loop_pid_after do
  nil -> wait_for_restart(loop_pid_before, 1000, 5)
  new_pid -> assert new_pid != loop_pid_before
end
```

**Expected state (PASS case):**
```
%{
  running: true,
  iteration: 2,           ← Incremented (old: 1)
  loop_pid: #PID<0.5678.0>, ← Different PID (old: #PID<0.1234.0>)
  pass_count: 15,         ← Accumulated from both iterations
  fail_count: 5,
  pass_rate: 75.0
}
```

**Assertion outputs:**
```
✓ assert state_after.running == true (line 94)
✓ assert state_after.iteration >= 1 (line 99)
✓ assert new_pid != loop_pid_before (line 116)
✓ assert Process.alive?(new_pid) (line 119)
```

### Phase 4: VERIFY CONTINUITY (Lines 125-129)

**Test code:**
```elixir
Process.sleep(500)
state_final = Canopy.JTBD.SelfPlayLoop.get_state()
assert state_final.iteration >= state_after.iteration
```

**Expected logs:**
```
[info] Wave 12 iteration 3: 9/10 scenarios passed (90.0%) in 260ms ← Loop continues
[info] Wave 12 iteration 4: 7/10 scenarios passed (70.0%) in 248ms ← And again
```

**Expected state:**
```
%{
  running: true,
  iteration: 4,           ← Further incremented
  loop_pid: #PID<0.5678.0>,
  pass_count: 31,
  fail_count: 9,
  pass_rate: 77.5
}
```

**Assertion output:**
```
✓ assert state_final.iteration >= 2 (line 128)
```

### Phase 5: CLEANUP (Lines 131-134)

**Test code:**
```elixir
Canopy.JTBD.SelfPlayLoop.stop()
state_stopped = Canopy.JTBD.SelfPlayLoop.get_state()
assert state_stopped.running == false
```

**Expected logs:**
```
[info] Wave 12 self-play loop shutdown initiated
```

**Expected state:**
```
%{
  running: false,
  iteration: 4,           ← Preserved
  loop_pid: nil,          ← Cleared
  pass_count: 31,         ← Preserved
  fail_count: 9,
  pass_rate: 77.5
}
```

**Assertion output:**
```
✓ assert state_stopped.running == false (line 134)
```

### Test 1 Summary

```
  test test_loop_process_auto_restarts_on_crash (6543ms)
    ✓ Loop started and executing (200ms)
    ✓ Loop killed with :kill signal (0ms)
    ✓ Supervisor detected crash (500ms)
    ✓ New loop process spawned (#PID<0.5678.0>)
    ✓ Iteration counter continued (4 vs initial 1)
    ✓ Pass count accumulated (31 total)
    ✓ Loop gracefully stopped
    ✓ Final state clean and correct
```

---

## Test 2: `test_loop_crash_detection_with_pids`

### Execution

**Test code:**
```elixir
{:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 500)
Process.sleep(300)
state = Canopy.JTBD.SelfPlayLoop.get_state()

case state.loop_pid do
  nil -> assert is_pid(Process.whereis(:canopy_jtbd_loop_supervisor))
  loop_pid -> assert Process.alive?(loop_pid)
end
```

**Expected logs:**
```
[info] Wave 12 iteration 1: 7/10 scenarios passed (70.0%) in 248ms
[info] Wave 12 iteration 2: 8/10 scenarios passed (80.0%) in 255ms
[info] Wave 12 iteration 3: 9/10 scenarios passed (90.0%) in 262ms
```

**Expected state:**
```
%{
  running: true,
  iteration: 3,
  loop_pid: #PID<0.1111.0>,  ← Not nil (normal case)
  pass_count: 24,
  fail_count: 6,
  pass_rate: 80.0
}
```

**Assertion output (normal case):**
```
✓ assert Process.alive?(#PID<0.1111.0>) == true (line 159)
✓ assert is_pid(#PID<0.9999.0>) == true (line 163) [supervisor]
```

**Or (edge case - nil PID):**
```
(if spawn failed - rare)
✓ assert is_pid(#PID<0.9999.0>) == true (line 154) [supervisor still exists]
```

### Test 2 Summary

```
  test test_loop_crash_detection_with_pids (1234ms)
    ✓ Loop started with 500 iterations
    ✓ Supervisor ready and registered
    ✓ Loop process is alive (normal case)
    ✓ Or supervisor exists despite nil PID (edge case)
    ✓ Loop stopped cleanly
```

---

## Test 3: `test_partial_iteration_state_on_crash`

### Phase 1: SETUP & INITIAL STATE

**Test code:**
```elixir
{:ok, _pid} = Canopy.JTBD.SelfPlayLoop.start(max_iterations: 10000)
Process.sleep(300)
state_before = Canopy.JTBD.SelfPlayLoop.get_state()
iteration_before = state_before.iteration
pass_count_before = state_before.pass_count
```

**Expected logs:**
```
[info] Wave 12 iteration 1: 7/10 scenarios passed (70.0%) in 248ms
[info] Wave 12 iteration 2: 8/10 scenarios passed (80.0%) in 255ms
[info] Wave 12 iteration 3: 9/10 scenarios passed (90.0%) in 262ms
```

**Captured state:**
```
iteration_before: 3
pass_count_before: 24
```

### Phase 2: CRASH AT RANDOM POINT

**Test code:**
```elixir
loop_pid = state_before.loop_pid  # #PID<0.2222.0>
if loop_pid, do: Process.exit(loop_pid, :kill)
Process.sleep(1000)
```

**What happens:**
- Loop might be:
  - In run_all_scenarios (mid-iteration)
  - In run_single_scenario (mid-scenario)
  - Between iterations (sleeping)

No log, process dies immediately.

### Phase 3: VERIFY IDEMPOTENCY

**Test code:**
```elixir
state_after = Canopy.JTBD.SelfPlayLoop.get_state()
iteration_after = state_after.iteration
pass_count_after = state_after.pass_count

assert iteration_after >= iteration_before  # 3 ≤ iteration_after
assert pass_count_after >= pass_count_before  # 24 ≤ pass_count_after
```

**Expected logs:**
```
[info] Wave 12 iteration 4: 8/10 scenarios passed (80.0%) in 259ms ← Restarted
[info] Wave 12 iteration 5: 7/10 scenarios passed (70.0%) in 251ms ← Continues
```

**Expected state:**
```
iteration_after: 5     (was 3, now 5)
pass_count_after: 40   (was 24, now 40)
```

**Assertion outputs:**
```
✓ assert 5 >= 3 (line 194)
✓ assert 40 >= 24 (line 198)
```

### Test 3 Summary

```
  test test_partial_iteration_state_on_crash (4567ms)
    ✓ Loop started with 10000 iterations (unbounded)
    ✓ Initial state captured: iteration=3, pass_count=24
    ✓ Loop killed at random point in iteration
    ✓ Supervisor restarted loop process
    ✓ Iteration counter is monotonic: 3 → 5 (no skip/duplicate)
    ✓ Pass count is monotonic: 24 → 40 (no loss/duplicate)
    ✓ Loop stopped cleanly
```

---

## Overall Test Summary

```
Chaos Test — Loop Process Crash Recovery (Armstrong Fault Tolerance)

  test test_loop_process_auto_restarts_on_crash (6543ms)
  test test_loop_crash_detection_with_pids (1234ms)
  test test_partial_iteration_state_on_crash (4567ms)

Finished in 12.3s
3 passed, 0 failed

Assertions: 15 total, 15 passed
Logs: 47 lines
Status: ✅ All Armstrong principles verified
```

---

## Failure Scenarios

### Scenario A: Supervisor Not Registered

**Test would fail at:**
```
✗ test_loop_process_auto_restarts_on_crash (line 94)
  Expected: true
  Actual: false
  Message: "Loop should still be marked running after supervisor restart"

  Reason: state_after.running is still false

  Logs show: (silence after crash — no restart)

  Diagnosis: Task.Supervisor not in application.ex supervision tree
```

### Scenario B: Iteration Counter Not Durable

**Test would fail at:**
```
✗ test_loop_process_auto_restarts_on_crash (line 99)
  Expected: >= 1
  Actual: 0
  Message: "Loop iterations should continue or reset after restart"

  Reason: Iteration counter lost after restart

  Diagnosis: Iteration stored in loop process, not GenServer state
             Need to move to GenServer handle_cast
```

### Scenario C: Timing Too Tight

**Test would fail randomly:**
```
✗ test_loop_process_auto_restarts_on_crash (line 116)
  Expected: true
  Actual: false
  Message: "Loop should have a new PID after crash"

  Reason: Restart takes >1000ms (race condition)

  Solution: Increase Process.sleep(1000) to Process.sleep(2000)
            Or use wait_for_restart(...) to poll with backoff
```

### Scenario D: Loop Function Bugs

**Test would fail at:**
```
✗ test_loop_process_auto_restarts_on_crash (line 119)
  Expected: true
  Actual: false
  Message: "New loop process should be alive after restart"

  Reason: New process crashes immediately (bug in run_loop/1)

  Logs show:
    [error] Exception in task #PID<0.5678.0>
    [error] FunctionClauseError: no function clause matching in ...

  Diagnosis: Defensive error handling missing in loop entry
```

---

## Performance Characteristics

### Expected Timing

| Component | Duration |
|-----------|----------|
| Single iteration (run all 10 scenarios) | 250-270ms |
| Test 1 (setup + crash + verify) | 6-7s |
| Test 2 (edge case checks) | 1-2s |
| Test 3 (idempotency) | 4-5s |
| **Total test suite** | **12-15s** |

### Resource Usage

| Resource | Typical | Max |
|----------|---------|-----|
| Processes spawned | 3-5 | 10 |
| Memory per test | 2-5MB | 50MB |
| File handles | <10 | <100 |

---

## Log Levels

Test output uses standard Elixir logging levels:

| Level | Prefix | Usage in This Test |
|-------|--------|-------------------|
| info | `[info]` | Iteration progress, normal operations |
| warning | `[warning]` | Supervisor restart detection (rare) |
| error | `[error]` | Only on test failure |

---

## Verification Checklist

After test completes, verify:

- [ ] All 3 tests passed (0 failures)
- [ ] Total runtime: 12-15s (not >30s timeout)
- [ ] Logs show at least 4 iterations per test
- [ ] No exception stack traces in output
- [ ] PID values are unique across restart (e.g., #PID<0.1234.0> ≠ #PID<0.5678.0>)
- [ ] Final state shows `running: false, loop_pid: nil` after cleanup

---

## Next Steps

If test passes:
1. ✅ Armstrong Let-It-Crash verified
2. ✅ Supervision Tree working
3. ✅ State durable across restarts
4. Ready for: OTEL span instrumentation, metrics collection, load testing

If test fails:
1. Read failure message carefully
2. Check logs for clues (silence, exceptions)
3. Consult debugging table in CHAOS_TEST_QUICK_REFERENCE.md
4. Apply fix (usually supervisor config or timing)
5. Re-run test
