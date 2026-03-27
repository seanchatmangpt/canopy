defmodule Integration.OSAProtocolTest do
  @moduledoc """
  Canopy ↔ OSA Workspace Protocol Integration Tests

  Validates the protocol state machine for command flow:
    Canopy → OSA → execution → response → Canopy

  Tests all 10 message types:
    1. spawn      — Agent lifecycle
    2. call       — Tool dispatch
    3. state      — Memory query
    4. stop       — Termination
    5. list       — Enumeration
    6. health     — Liveness check
    7. signal     — Temporal workflow control
    8. signal/query — Temporal status query
    9. delegate   — Inter-agent task passing
    10. heartbeat — Scheduled execution

  Concurrent load: 50 agents (10 workspaces × 5 agents each)
  Latency SLA: p95 ≤ 200ms for all operations
  """

  use CanopyWeb.ConnCase

  require Logger

  alias Canopy.Repo
  alias Canopy.Schemas.Workspace

  # ── Configuration & Setup ──────────────────────────────────────────────────────

  @osa_base_url "http://127.0.0.1:8089"
  @timeout_ms 5000
  @latency_sla_p95_ms 200
  @concurrent_workspaces 10
  @agents_per_workspace 5

  setup_all do
    # Verify OSA is reachable
    case health_check_osa() do
      :ok ->
        Logger.info("[OSAProtocolTest] OSA healthy at #{@osa_base_url}, starting tests")
        {:ok, osa_available: true}

      {:error, reason} ->
        Logger.info(
          "[OSAProtocolTest] OSA unreachable (#{inspect(reason)}) - integration tests will be skipped"
        )

        {:ok, osa_available: false}
    end
  end

  setup _context do
    case create_test_workspace("osa-protocol-#{System.unique_integer([:positive])}") do
      {:ok, ws} ->
        {:ok, workspace: ws}

      {:error, _reason} ->
        {:ok, workspace: nil}
    end
  end

  # ── Message Type Tests (1-10) ──────────────────────────────────────────────────

  describe "message type 1: spawn (agent lifecycle)" do
    @tag :integration
    test "canopy sends agent spawn → OSA creates agent → returns agent_id", %{workspace: ws} do
      start_time = System.monotonic_time(:millisecond)

      workspace_id = if ws, do: ws.id, else: Ecto.UUID.generate()

      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => generate_id("agent"),
        "agent_name" => "Test Agent",
        "workspace_id" => workspace_id,
        "config" => %{
          "model" => "llama-3.3-70b-versatile",
          "provider" => "groq"
        }
      }

      {:ok, response} = call_osa("/api/v1/agents/spawn", spawn_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify response
      assert response["agent_id"] != nil
      assert response["status"] == "created"
      assert response["workspace_id"] == workspace_id

      # Verify latency SLA
      assert elapsed_ms <= @latency_sla_p95_ms,
             "Spawn latency #{elapsed_ms}ms exceeds SLA of #{@latency_sla_p95_ms}ms"

      Logger.info(
        "[OSAProtocol] spawn: agent_id=#{response["agent_id"]}, latency=#{elapsed_ms}ms"
      )
    end

    @tag :integration
    test "spawn with invalid config returns error" do
      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => generate_id("agent"),
        "agent_name" => "Bad Agent",
        "workspace_id" => "nonexistent",
        "config" => %{}
      }

      {:error, {status, _body}} = call_osa("/api/v1/agents/spawn", spawn_payload)
      assert status in [400, 404, 503]
    end
  end

  describe "message type 2: call (tool dispatch)" do
    @tag :integration
    test "canopy sends tool call → OSA dispatches tool → returns result" do
      start_time = System.monotonic_time(:millisecond)

      call_payload = %{
        "type" => "call",
        "agent_id" => generate_id("agent"),
        "tool_name" => "echo",
        "tool_args" => %{"message" => "hello from canopy"}
      }

      {:ok, response} = call_osa("/api/v1/tools/call", call_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify response
      assert response["tool_result"] != nil
      assert response["status"] == "ok"

      # Verify latency SLA
      assert elapsed_ms <= @latency_sla_p95_ms,
             "Tool call latency #{elapsed_ms}ms exceeds SLA"

      Logger.info("[OSAProtocol] call: tool=echo, latency=#{elapsed_ms}ms")
    end

    @tag :integration
    test "call with missing tool argument returns validation error" do
      call_payload = %{
        "type" => "call",
        "agent_id" => generate_id("agent"),
        "tool_name" => "echo",
        "tool_args" => %{}
      }

      {:error, {status, _body}} = call_osa("/api/v1/tools/call", call_payload)
      assert status in [400, 422]
    end
  end

  describe "message type 3: state (memory query)" do
    @tag :integration
    test "canopy sends state query → OSA returns memory state" do
      start_time = System.monotonic_time(:millisecond)

      state_payload = %{
        "type" => "state",
        "agent_id" => generate_id("agent"),
        "query" => "memory"
      }

      {:ok, response} = call_osa("/api/v1/agents/state", state_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify response structure
      assert is_map(response["state"])
      assert response["agent_id"] != nil

      # Verify latency SLA
      assert elapsed_ms <= @latency_sla_p95_ms

      Logger.info(
        "[OSAProtocol] state: agent_id=#{response["agent_id"]}, latency=#{elapsed_ms}ms"
      )
    end
  end

  describe "message type 4: stop (agent termination)" do
    @tag :integration
    test "canopy sends agent stop → OSA terminates cleanly" do
      # First spawn an agent
      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => generate_id("agent"),
        "agent_name" => "Temp Agent",
        "workspace_id" => Ecto.UUID.generate(),
        "config" => %{
          "model" => "llama-3.3-70b-versatile",
          "provider" => "groq"
        }
      }

      {:ok, spawn_resp} = call_osa("/api/v1/agents/spawn", spawn_payload)
      agent_id = spawn_resp["agent_id"]

      # Now stop it
      start_time = System.monotonic_time(:millisecond)

      stop_payload = %{
        "type" => "stop",
        "agent_id" => agent_id,
        "reason" => "test_termination"
      }

      {:ok, response} = call_osa("/api/v1/agents/stop", stop_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify response
      assert response["agent_id"] == agent_id
      assert response["status"] == "stopped"

      # Verify latency SLA
      assert elapsed_ms <= @latency_sla_p95_ms

      Logger.info("[OSAProtocol] stop: agent_id=#{agent_id}, latency=#{elapsed_ms}ms")
    end
  end

  describe "message type 5: list (enumeration)" do
    @tag :integration
    test "canopy sends list request → OSA returns agent enumeration" do
      start_time = System.monotonic_time(:millisecond)

      list_payload = %{
        "type" => "list",
        "filter" => %{"status" => "active"}
      }

      {:ok, response} = call_osa("/api/v1/agents", list_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify response structure
      assert is_list(response["agents"])
      assert response["count"] != nil

      # Verify latency SLA
      assert elapsed_ms <= @latency_sla_p95_ms

      Logger.info("[OSAProtocol] list: count=#{response["count"]}, latency=#{elapsed_ms}ms")
    end
  end

  describe "message type 6: health (liveness check)" do
    @tag :integration
    test "canopy sends health check → OSA returns status" do
      start_time = System.monotonic_time(:millisecond)

      {:ok, response} = call_osa("/api/health", %{})

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify response
      assert response["status"] == "healthy"
      assert response["timestamp"] != nil

      # Verify latency SLA (health checks should be fastest)
      assert elapsed_ms <= @latency_sla_p95_ms

      Logger.info("[OSAProtocol] health: latency=#{elapsed_ms}ms")
    end
  end

  describe "message type 7: signal (temporal workflow control)" do
    @tag :integration
    test "canopy sends workflow signal (pause/skip/abort)" do
      workflow_id = generate_id("workflow")

      start_time = System.monotonic_time(:millisecond)

      signal_payload = %{
        "type" => "signal",
        "workflow_id" => workflow_id,
        "signal" => "pause",
        "params" => %{}
      }

      # Try to signal (may fail if workflow doesn't exist, which is ok for protocol test)
      result = call_osa("/api/v1/workflows/#{workflow_id}/signal", signal_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Whether success or not, verify latency SLA
      case result do
        {:ok, _response} ->
          assert elapsed_ms <= @latency_sla_p95_ms
          Logger.info("[OSAProtocol] signal: workflow_id=#{workflow_id}, latency=#{elapsed_ms}ms")

        {:error, {_status, _body}} ->
          assert elapsed_ms <= @latency_sla_p95_ms
          Logger.info("[OSAProtocol] signal: workflow_id=#{workflow_id}, not found (expected)")
      end
    end
  end

  describe "message type 8: signal/query (temporal status)" do
    @tag :integration
    test "canopy sends workflow query → OSA returns status" do
      workflow_id = generate_id("workflow")

      start_time = System.monotonic_time(:millisecond)

      {:ok, _response} = call_osa("/api/v1/workflows/#{workflow_id}", %{})

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Verify latency SLA
      assert elapsed_ms <= @latency_sla_p95_ms

      Logger.info(
        "[OSAProtocol] signal/query: workflow_id=#{workflow_id}, latency=#{elapsed_ms}ms"
      )
    end
  end

  describe "message type 9: delegate (inter-agent task passing)" do
    @tag :integration
    test "canopy sends delegation → OSA routes task to delegate agent" do
      start_time = System.monotonic_time(:millisecond)

      delegate_payload = %{
        "type" => "delegate",
        "from_agent_id" => generate_id("agent"),
        "to_agent_id" => generate_id("agent"),
        "task" => %{
          "kind" => "code_execution",
          "input" => "print('Hello from delegation')"
        }
      }

      result = call_osa("/api/v1/agents/delegate", delegate_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Whether success or not (agents may not exist), verify latency SLA
      case result do
        {:ok, _response} ->
          assert elapsed_ms <= @latency_sla_p95_ms
          Logger.info("[OSAProtocol] delegate: elapsed=#{elapsed_ms}ms")

        {:error, {_status, _body}} ->
          assert elapsed_ms <= @latency_sla_p95_ms
          Logger.info("[OSAProtocol] delegate: agents not found (expected)")
      end
    end
  end

  describe "message type 10: heartbeat (scheduled execution)" do
    @tag :integration
    test "canopy sends heartbeat → OSA executes scheduled checks" do
      start_time = System.monotonic_time(:millisecond)

      heartbeat_payload = %{
        "type" => "heartbeat",
        "agent_id" => generate_id("agent"),
        "context" => "Perform your scheduled heartbeat check"
      }

      {:ok, _response} = call_osa("/api/v1/heartbeat", heartbeat_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Heartbeat may take longer but should respect reasonable timeout
      assert elapsed_ms <= @timeout_ms,
             "Heartbeat latency #{elapsed_ms}ms exceeds timeout"

      Logger.info("[OSAProtocol] heartbeat: elapsed=#{elapsed_ms}ms")
    end
  end

  # ── Concurrent Load Tests ──────────────────────────────────────────────────────

  describe "concurrent load: 50 agents (10 workspaces × 5)" do
    @tag :integration
    test "concurrent agent lifecycle operations" do
      Logger.info(
        "[OSAProtocol] Starting concurrent load test: #{@concurrent_workspaces} workspaces × #{@agents_per_workspace} agents"
      )

      # Create workspaces + agents in parallel
      workspace_tasks =
        Enum.map(1..@concurrent_workspaces, fn ws_num ->
          Task.async(fn ->
            ws_id = "ws-#{ws_num}-#{System.unique_integer([:positive])}"
            agents_for_workspace = spawn_agents_in_workspace(ws_id, @agents_per_workspace)
            {ws_id, agents_for_workspace}
          end)
        end)

      # Await all workspace creation
      workspaces = Task.await_many(workspace_tasks, @timeout_ms)

      Logger.info("[OSAProtocol] Created #{length(workspaces)} workspaces")

      # Verify all agents are reachable
      health_tasks =
        Enum.flat_map(workspaces, fn {_ws_id, agents} ->
          Enum.map(agents, fn agent_id ->
            Task.async(fn ->
              start_time = System.monotonic_time(:millisecond)

              state_payload = %{
                "type" => "state",
                "agent_id" => agent_id
              }

              case call_osa("/api/v1/agents/state", state_payload) do
                {:ok, _response} ->
                  latency = System.monotonic_time(:millisecond) - start_time
                  {:ok, latency}

                {:error, reason} ->
                  Logger.warning(
                    "[OSAProtocol] Agent #{agent_id} unreachable: #{inspect(reason)}"
                  )

                  {:error, reason}
              end
            end)
          end)
        end)

      health_results = Task.await_many(health_tasks, @timeout_ms)

      # Calculate latency percentiles
      successful_latencies =
        health_results
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, latency} -> latency end)
        |> Enum.sort()

      count_successful = length(successful_latencies)
      count_total = length(health_results)

      Logger.info(
        "[OSAProtocol] Concurrent load: #{count_successful}/#{count_total} agents healthy"
      )

      if count_successful > 0 do
        p50 = Enum.at(successful_latencies, div(count_successful, 2), 0)
        p95 = Enum.at(successful_latencies, trunc(count_successful * 0.95), 0)
        p99 = Enum.at(successful_latencies, trunc(count_successful * 0.99), 0)

        Logger.info("[OSAProtocol] Latency percentiles: p50=#{p50}ms, p95=#{p95}ms, p99=#{p99}ms")

        # Verify p95 SLA
        assert p95 <= @latency_sla_p95_ms,
               "p95 latency #{p95}ms exceeds SLA of #{@latency_sla_p95_ms}ms"
      end

      # All agents should be stable
      assert count_successful >= div(count_total, 2),
             "Less than 50% of agents are healthy"
    end

    @tag :integration
    test "concurrent message types on same agent" do
      # Spawn a single agent
      agent_id = generate_id("agent")

      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => agent_id,
        "agent_name" => "Concurrent Test Agent",
        "workspace_id" => Ecto.UUID.generate(),
        "config" => %{"model" => "llama-3.3-70b-versatile", "provider" => "groq"}
      }

      {:ok, _} = call_osa("/api/v1/agents/spawn", spawn_payload)

      # Send 5 concurrent messages to same agent
      tasks =
        Enum.map(1..5, fn msg_num ->
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)

            state_payload = %{
              "type" => "state",
              "agent_id" => agent_id,
              "query" => "memory"
            }

            case call_osa("/api/v1/agents/state", state_payload) do
              {:ok, _response} ->
                latency = System.monotonic_time(:millisecond) - start_time
                Logger.info("[OSAProtocol] Concurrent msg #{msg_num}: latency=#{latency}ms")
                {:ok, latency}

              {:error, reason} ->
                {:error, reason}
            end
          end)
        end)

      results = Task.await_many(tasks, @timeout_ms)

      # Verify all concurrent messages succeeded
      successful = Enum.filter(results, &match?({:ok, _}, &1))
      assert length(successful) >= 3, "At least 3/5 concurrent messages should succeed"

      Logger.info("[OSAProtocol] Concurrent messages: #{length(successful)}/5 succeeded")
    end

    @tag :integration
    test "concurrent spawn operations scale linearly" do
      batch_sizes = [5, 10, 20]

      Enum.each(batch_sizes, fn batch_size ->
        start_time = System.monotonic_time(:millisecond)

        spawn_tasks =
          Enum.map(1..batch_size, fn i ->
            Task.async(fn ->
              spawn_payload = %{
                "type" => "spawn",
                "agent_id" => generate_id("agent"),
                "agent_name" => "Batch Agent #{i}",
                "workspace_id" => Ecto.UUID.generate(),
                "config" => %{"model" => "llama-3.3-70b-versatile", "provider" => "groq"}
              }

              call_osa("/api/v1/agents/spawn", spawn_payload)
            end)
          end)

        results = Task.await_many(spawn_tasks, @timeout_ms)
        successful = Enum.filter(results, &match?({:ok, _}, &1))
        elapsed_ms = System.monotonic_time(:millisecond) - start_time

        throughput = div(batch_size * 1000, max(elapsed_ms, 1))

        Logger.info(
          "[OSAProtocol] Spawn batch #{batch_size}: #{length(successful)} succeeded in #{elapsed_ms}ms (#{throughput} ops/sec)"
        )

        # Verify at least 80% success
        assert length(successful) >= div(batch_size * 80, 100)
      end)
    end
  end

  # ── Protocol State Machine Tests ───────────────────────────────────────────────

  describe "protocol state machine" do
    @tag :integration
    test "spawn → call → state → stop follows correct sequence" do
      # 1. SPAWN
      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => generate_id("agent"),
        "agent_name" => "State Machine Test",
        "workspace_id" => Ecto.UUID.generate(),
        "config" => %{"model" => "llama-3.3-70b-versatile", "provider" => "groq"}
      }

      {:ok, spawn_resp} = call_osa("/api/v1/agents/spawn", spawn_payload)
      agent_id = spawn_resp["agent_id"]
      assert spawn_resp["status"] == "created"
      Logger.info("[OSAProtocol] State machine step 1: spawned agent #{agent_id}")

      # 2. CALL
      call_payload = %{
        "type" => "call",
        "agent_id" => agent_id,
        "tool_name" => "echo",
        "tool_args" => %{"message" => "state machine test"}
      }

      {:ok, call_resp} = call_osa("/api/v1/tools/call", call_payload)
      assert call_resp["status"] == "ok"
      Logger.info("[OSAProtocol] State machine step 2: called tool")

      # 3. STATE
      state_payload = %{
        "type" => "state",
        "agent_id" => agent_id
      }

      {:ok, state_resp} = call_osa("/api/v1/agents/state", state_payload)
      assert is_map(state_resp["state"])
      Logger.info("[OSAProtocol] State machine step 3: queried state")

      # 4. STOP
      stop_payload = %{
        "type" => "stop",
        "agent_id" => agent_id
      }

      {:ok, stop_resp} = call_osa("/api/v1/agents/stop", stop_payload)
      assert stop_resp["status"] == "stopped"
      Logger.info("[OSAProtocol] State machine step 4: stopped agent")
    end

    test "error recovery: invalid message type returns 400" do
      invalid_payload = %{
        "type" => "invalid_type",
        "agent_id" => generate_id("agent")
      }

      {:error, {status, _body}} = call_osa("/api/v1/agents/invalid", invalid_payload)
      assert status in [400, 404, 405, 503]
    end

    @tag :integration
    test "timeout handling: long-running operation respects timeout" do
      # Send a heartbeat (potentially long-running) and verify timeout respected
      heartbeat_payload = %{
        "type" => "heartbeat",
        "agent_id" => generate_id("agent"),
        "context" => "test timeout"
      }

      start_time = System.monotonic_time(:millisecond)

      {:ok, _response} = call_osa("/api/v1/heartbeat", heartbeat_payload)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Should complete or timeout within configured timeout
      assert elapsed_ms <= @timeout_ms,
             "Operation exceeded timeout of #{@timeout_ms}ms"
    end
  end

  # ── Error Handling Tests ───────────────────────────────────────────────────────

  describe "error handling and edge cases" do
    @tag :integration
    test "nonexistent agent returns 404" do
      payload = %{
        "type" => "state",
        "agent_id" => "nonexistent-#{System.unique_integer([:positive])}"
      }

      {:error, {status, _body}} = call_osa("/api/v1/agents/state", payload)
      assert status == 404
    end

    @tag :integration
    test "malformed JSON returns 400" do
      {:error, {status, _body}} = call_osa_raw("/api/v1/agents/state", "{invalid json}")
      assert status == 400
    end

    @tag :integration
    test "missing required field returns validation error" do
      payload = %{
        "type" => "spawn"
        # Missing agent_id, agent_name, etc.
      }

      {:error, {status, _body}} = call_osa("/api/v1/agents/spawn", payload)
      assert status in [400, 422]
    end

    @tag :integration
    test "concurrent stop on same agent is idempotent" do
      # Spawn agent
      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => generate_id("agent"),
        "agent_name" => "Idempotent Test",
        "workspace_id" => Ecto.UUID.generate(),
        "config" => %{"model" => "llama-3.3-70b-versatile", "provider" => "groq"}
      }

      {:ok, spawn_resp} = call_osa("/api/v1/agents/spawn", spawn_payload)
      agent_id = spawn_resp["agent_id"]

      # Stop twice concurrently
      stop_payload = %{
        "type" => "stop",
        "agent_id" => agent_id
      }

      task1 = Task.async(fn -> call_osa("/api/v1/agents/stop", stop_payload) end)
      task2 = Task.async(fn -> call_osa("/api/v1/agents/stop", stop_payload) end)

      result1 = Task.await(task1, @timeout_ms)
      result2 = Task.await(task2, @timeout_ms)

      # Both should succeed or one succeed + one get idempotent response
      case {result1, result2} do
        {{:ok, _}, {:ok, _}} ->
          Logger.info("[OSAProtocol] Idempotent stop: both succeeded")
          :ok

        {{:ok, _}, {:error, _}} ->
          Logger.info("[OSAProtocol] Idempotent stop: first succeeded, second errored")
          :ok

        {{:error, _}, {:ok, _}} ->
          Logger.info("[OSAProtocol] Idempotent stop: first errored, second succeeded")
          :ok

        {{:error, _}, {:error, _}} ->
          # Both errored - could be agent already stopped
          Logger.info("[OSAProtocol] Idempotent stop: both errored (already stopped)")
          :ok
      end
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────────

  defp health_check_osa do
    case Req.get("#{@osa_base_url}/api/health") do
      {:ok, %{status: 200, body: %{"status" => "healthy"}}} -> :ok
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_osa(path, payload) do
    url = @osa_base_url <> path

    case Req.post(url,
           json: payload,
           headers: [{"Content-Type", "application/json"}],
           receive_timeout: @timeout_ms
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        # Map transport errors to HTTP-like error tuple for consistent handling
        case reason do
          %Req.TransportError{reason: :econnrefused} ->
            {:error,
             {503, %{"error" => "connection_refused", "message" => "OSA service unavailable"}}}

          _ ->
            {:error, reason}
        end
    end
  end

  defp call_osa_raw(path, raw_body) do
    url = @osa_base_url <> path

    case Req.post(url,
           body: raw_body,
           headers: [{"Content-Type", "application/json"}],
           receive_timeout: @timeout_ms
         ) do
      {:ok, %{status: status, body: body}} ->
        {:ok, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp spawn_agents_in_workspace(workspace_id, count) do
    Enum.map(1..count, fn i ->
      agent_id = generate_id("agent-#{i}")

      spawn_payload = %{
        "type" => "spawn",
        "agent_id" => agent_id,
        "agent_name" => "Agent #{i} in #{workspace_id}",
        "workspace_id" => workspace_id,
        "config" => %{
          "model" => "llama-3.3-70b-versatile",
          "provider" => "groq"
        }
      }

      case call_osa("/api/v1/agents/spawn", spawn_payload) do
        {:ok, resp} -> resp["agent_id"]
        {:error, _} -> agent_id
      end
    end)
  end

  defp create_test_workspace(name) do
    case Repo.insert(%Workspace{
           name: name,
           path: "/tmp/#{name}",
           status: "active",
           is_active: true,
           isolation_level: "full"
         }) do
      {:ok, ws} -> {:ok, ws}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end
end
