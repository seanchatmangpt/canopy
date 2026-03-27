# How-To: Debug an Agent Timeout

> **Problem:** Agent doesn't respond to heartbeat messages, just times out.
> **Time:** ~15 minutes to diagnosis, <5 minutes per fix attempt
> **Outcome:** Agent is unblocked and responding normally

---

## Symptom Checklist

Your agent timeout looks like this:

```
Heartbeat fires at 09:00
  ↓
Agent "backend-dev" is scheduled
  ↓
Heartbeat sends task: "implement_auth_service"
  ↓
[... 30 second silence ...]
  ↓
HTTP 504: timeout (agent never replied)
  ↓
Task marked as failed
  ↓
Next heartbeat, same agent, same timeout
```

The agent is **either crashed or stuck**.

---

## Step 1: Check Logs for Clues

### Option A: Docker logs (if running in container)

```bash
docker logs -f canopy-backend | grep -i "backend-dev\|error\|crash"
```

Look for:
- `[error]` — exception or runtime error
- `[crash]` — process died unexpectedly
- `GenServer terminating` — process exited
- `timeout` — operation took too long

### Option B: Local development logs

```bash
# Terminal where you ran `make backend`
tail -f backend/log/dev.log | grep -i "backend-dev\|error"

# Or check if agent is in logs at all
grep "backend-dev" backend/log/dev.log | tail -20
```

### Option C: Check system kernel messages (if everything is silent)

```bash
dmesg | tail -20
```

Look for: `Out of memory` — system killed your process.

---

## Step 2: Verify Agent Process Is Alive

### Check if agent supervisor started the process

Use `iex` (Elixir interactive shell):

```bash
cd canopy/backend

# Start interactive console
iex -S mix

# Check if your agent is running
iex> :observer.start()
# Opens GUI, look for your agent in the process tree

# Or via code:
iex> :sys.get_state(Canopy.Agents.BackendDev)
%{"config" => [...]}  # Success — agent is alive

iex> :sys.get_state(Canopy.Agents.BackendDev)
** (ArgumentError) could not find GenServer named Canopy.Agents.BackendDev
# Error — agent crashed or not registered
```

### Quick check: Is the agent in the supervision tree?

```bash
curl http://localhost:9089/api/health
```

If this fails, Canopy is down. Restart:
```bash
make backend
```

---

## Step 3: Test Agent Directly with curl

Don't use the heartbeat. Call the agent directly:

```bash
curl -X POST http://localhost:9089/api/agents/backend-dev/message \
  -H "Content-Type: application/json" \
  -H "Timeout: 5000" \
  -d '{
    "type": "implement",
    "task_id": "task-1",
    "payload": {"spec": "minimal test"}
  }' \
  --connect-timeout 5 \
  --max-time 10
```

Expected:
- **200 OK + response JSON** → agent is working
- **504 Gateway Timeout** → agent is stuck or slow
- **500 Internal Server Error** → agent crashed
- **Connection refused** → Canopy is down

---

## Step 4: Enable Debug Logging in Agent

If curl times out, the agent is stuck or slow. Add debug output:

**File:** `canopy/backend/lib/canopy/agents/backend_dev.ex`

Add logging at the entry point:

```elixir
def handle_message(message, state) do
  start_time = System.monotonic_time(:millisecond)

  Logger.info("[BackendDev] Received message: type=#{message.type}, task_id=#{message["task_id"]}")
  Logger.debug("[BackendDev] Full message: #{inspect(message)}")

  result =
    case message.type do
      "implement" ->
        Logger.info("[BackendDev] >>> Entering implement handler")
        try do
          handle_implement(message, state)
        after
          elapsed = System.monotonic_time(:millisecond) - start_time
          Logger.info("[BackendDev] <<< implement handler returned (#{elapsed}ms)")
        end

      _ ->
        Logger.warning("[BackendDev] Unknown message type: #{message.type}")
        {:error, :unknown_type}
    end

  elapsed_total = System.monotonic_time(:millisecond) - start_time
  Logger.info("[BackendDev] Total response time: #{elapsed_total}ms")
  result
end
```

**Recompile:**
```bash
cd canopy/backend
mix compile
```

**Restart backend and retest:**
```bash
# Ctrl+C to stop backend
make backend

# In another terminal, rerun curl
curl -X POST http://localhost:9089/api/agents/backend-dev/message \
  -H "Content-Type: application/json" \
  -d '{"type": "implement", "task_id": "task-1"}'
```

**Check logs:**
```bash
tail -f backend/log/dev.log | grep "BackendDev"

# You should see:
# [info] [BackendDev] Received message: type=implement, task_id=task-1
# [info] [BackendDev] >>> Entering implement handler
# [info] [BackendDev] <<< implement handler returned (234ms)
# [info] [BackendDev] Total response time: 245ms
```

If you don't see these logs, the agent isn't being called. Skip to **Step 5: Check Routing**.

---

## Step 5: Check Routing — Is the Request Reaching the Agent?

The HTTP request might never reach the agent. Check Canopy routing:

**File:** `canopy/backend/lib/canopy_web/controllers/agent_controller.ex`

Add debug logging:

```elixir
def message(conn, %{"agent_slug" => slug} = params) do
  Logger.info("[AgentController] Received message for agent: #{slug}")

  case find_agent_process(slug) do
    {:ok, pid} ->
      Logger.info("[AgentController] Found agent PID: #{inspect(pid)}")

      try do
        response = GenServer.call(pid, {:process, params}, 30_000)
        json(conn, response)
      catch
        :exit, reason ->
          Logger.error("[AgentController] GenServer.call exited: #{inspect(reason)}")
          json(conn, %{"error" => "timeout", "reason" => inspect(reason)}, status: 504)
      end

    {:error, reason} ->
      Logger.error("[AgentController] Agent not found: #{slug}, reason: #{inspect(reason)}")
      json(conn, %{"error" => "agent_not_found"}, status: 404)
  end
end
```

Restart and retest:
```bash
tail -f backend/log/dev.log | grep "AgentController"
```

You should see:
```
[info] [AgentController] Received message for agent: backend-dev
[info] [AgentController] Found agent PID: #PID<0.123.0>
[info] [BackendDev] Received message: ...
```

If you see "Agent not found", the agent slug is wrong or not registered.

---

## Step 6: Add Timeout Handler

If the agent is slow (>30 seconds), add a timeout + fallback:

**File:** `canopy/backend/lib/canopy/agents/backend_dev.ex`

```elixir
@timeout_ms 30_000
@fallback_timeout_ms 120_000

def handle_message(message, state) do
  # Set a watchdog timer
  {:ok, ref} = :timer.apply_after(@timeout_ms, __MODULE__, :watchdog_fired, [self()])

  result =
    try do
      do_handle_message(message, state)
    after
      :timer.cancel(ref)
    end

  result
end

defp do_handle_message(message, state) do
  case message.type do
    "implement" -> handle_implement_with_timeout(message, state)
    _ -> {:error, :unknown_type}
  end
end

# Watchdog fires if implementation takes >30s
def watchdog_fired(pid) do
  Logger.warning("[BackendDev] Watchdog: operation exceeded #{@timeout_ms}ms")
  send(pid, {:timeout, :watchdog})
end

def handle_info({:timeout, :watchdog}, state) do
  Logger.error("[BackendDev] Abandoning slow operation, returning fallback")
  {:ok, fallback_result(state)}
end

defp handle_implement_with_timeout(message, state) do
  # Instead of calling slow function directly, wrap it
  task = Task.Supervisor.async(Canopy.TaskSupervisor, fn ->
    handle_implement(message, state)
  end)

  case Task.yield(task, @timeout_ms) do
    {:ok, result} ->
      Logger.info("[BackendDev] Completed within timeout")
      result

    nil ->
      Logger.error("[BackendDev] Task exceeded #{@timeout_ms}ms, killing it")
      Task.shutdown(task)
      {:error, :timeout}
  end
end

defp fallback_result(state) do
  %{
    "status" => "fallback",
    "message" => "Operation timed out, returning partial result",
    "partial_work" => state["last_checkpoint"] || %{}
  }
end
```

---

## Step 7: Common Timeout Causes

### Cause 1: Synchronous I/O (File/Network Blocking)

**Wrong:**
```elixir
def handle_implement(message, state) do
  # This blocks! If file is slow or network hangs, entire agent hangs.
  content = File.read!("/large/file.txt")  # Could block for 10+ seconds
  {:ok, process(content)}
end
```

**Right:**
```elixir
def handle_implement(message, state) do
  # Use timeout on I/O
  case File.read("/large/file.txt") do
    {:ok, content} -> {:ok, process(content)}
    {:error, reason} -> {:error, reason}
  end
  # Or run in separate process with yield timeout (see Step 6)
end
```

### Cause 2: Infinite Loop (Unbounded Loop)

**Wrong:**
```elixir
def handle_implement(message, state) do
  # This could loop forever!
  loop_until_condition()
end

defp loop_until_condition() do
  case check_condition() do
    true -> :ok
    false -> loop_until_condition()  # Recursion never exits
  end
end
```

**Right:**
```elixir
defp loop_until_condition(attempts \\ 0) when attempts < 100 do
  case check_condition() do
    true -> :ok
    false -> loop_until_condition(attempts + 1)
  end
end
defp loop_until_condition(_), do: {:error, :max_retries}
```

### Cause 3: Database Query Timeout

**Wrong:**
```elixir
def handle_implement(message, state) do
  # Database query with no timeout
  result = Repo.all(query)  # Could hang if database is slow
  {:ok, result}
end
```

**Right:**
```elixir
def handle_implement(message, state) do
  query = from(t in Table, limit: 100)

  case Ecto.Repo.checkout(Repo, fn ->
    Repo.all(query)
  end) do
    {:ok, results} -> {:ok, results}
    {:error, _} = err -> err
  end
end
```

### Cause 4: External API Call (No Timeout)

**Wrong:**
```elixir
def handle_implement(message, state) do
  {:ok, response} = Req.post("https://external-api.com/slow-endpoint")
  {:ok, response.body}
end
```

**Right:**
```elixir
def handle_implement(message, state) do
  case Req.post("https://external-api.com/slow-endpoint",
    receive_timeout: 10_000,
    connect_timeout: 5_000
  ) do
    {:ok, response} -> {:ok, response.body}
    {:error, reason} -> {:error, reason}
  end
end
```

---

## Step 8: Verify the Fix

After making changes:

1. **Recompile:**
   ```bash
   cd canopy/backend
   mix compile
   ```

2. **Restart backend:**
   ```bash
   # Ctrl+C to stop
   make backend
   ```

3. **Test agent directly:**
   ```bash
   curl -X POST http://localhost:9089/api/agents/backend-dev/message \
     -H "Content-Type: application/json" \
     -d '{"type": "implement", "task_id": "test"}' \
     --max-time 5
   ```

4. **Check response time in logs:**
   ```bash
   grep "Total response time" backend/log/dev.log
   # Should show <5000ms for most operations
   ```

5. **Retest via heartbeat:**
   ```bash
   # Trigger next heartbeat cycle (or wait for schedule)
   curl -X POST http://localhost:9089/api/heartbeat
   ```

---

## Checklist: Agent Timeout Resolved

- [ ] Agent process is alive: `:observer.start()` or `iex> :sys.get_state(agent_mod)`
- [ ] Direct curl call succeeds: `curl ... --max-time 10` returns 200
- [ ] Logs show timing: `[info] Total response time: XXXms`
- [ ] No `[error]` messages in logs
- [ ] Timeout handlers in place (if needed for slow operations)
- [ ] I/O operations have explicit timeouts
- [ ] No unbounded loops
- [ ] Database queries are bounded
- [ ] External API calls use `receive_timeout`
- [ ] Heartbeat cycle succeeds without 504

---

## When All Else Fails: Full Restart

Sometimes the best fix is a clean restart:

```bash
# Stop backend
cd canopy/backend
mix stop

# Clean build
mix clean

# Recompile with warnings as errors
mix compile --warnings-as-errors

# Run migrations
mix ecto.migrate

# Start fresh
make backend

# Test
curl -X POST http://localhost:9089/api/agents/backend-dev/message ...
```

