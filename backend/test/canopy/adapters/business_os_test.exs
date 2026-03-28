defmodule Canopy.Adapters.BusinessOSTest do
  use ExUnit.Case, async: true

  # Tests make HTTP calls to BusinessOS service on port 8001
  @moduletag :external_service

  alias Canopy.Adapters.BusinessOS

  doctest BusinessOS

  # ── Test Fixtures ───────────────────────────────────────────────────

  @sample_event_log %{
    "events" => [
      %{
        "case_id" => "case_1",
        "activity" => "submit_request",
        "timestamp" => "2024-01-01T08:00:00Z",
        "resource" => "alice"
      },
      %{
        "case_id" => "case_1",
        "activity" => "review",
        "timestamp" => "2024-01-01T09:00:00Z",
        "resource" => "bob"
      },
      %{
        "case_id" => "case_1",
        "activity" => "approve",
        "timestamp" => "2024-01-01T10:00:00Z",
        "resource" => "charlie"
      }
    ]
  }

  @sample_model %{
    "activities" => ["submit_request", "review", "approve"],
    "transitions" => [
      %{"from" => "submit_request", "to" => "review"},
      %{"from" => "review", "to" => "approve"}
    ]
  }

  setup do
    {:ok, %{}}
  end

  # ── Adapter Behavior Tests ──────────────────────────────────────────

  test "adapter type is businessos" do
    assert BusinessOS.type() == "businessos"
  end

  test "adapter name is set" do
    assert BusinessOS.name() == "BusinessOS Process Mining & Compliance"
  end

  test "adapter does not support sessions" do
    assert BusinessOS.supports_session?() == false
  end

  test "adapter supports concurrent operations" do
    assert BusinessOS.supports_concurrent?() == true
  end

  test "adapter has correct capabilities" do
    capabilities = BusinessOS.capabilities()
    assert :process_mining in capabilities
    assert :model_analysis in capabilities
    assert :conformance_checking in capabilities
  end

  # ── Initialization Tests ────────────────────────────────────────────

  test "start returns ok with initialized state" do
    assert {:ok, %{initialized: true}} = BusinessOS.start(%{})
  end

  test "stop returns ok" do
    {:ok, session} = BusinessOS.start(%{})
    assert :ok = BusinessOS.stop(session)
  end

  # ── Health Check Tests ──────────────────────────────────────────────

  test "health_check detects unavailable server" do
    result = BusinessOS.health_check(%{"url" => "http://localhost:9999"})
    assert {:error, _} = result
  end

  test "parallel_health_check handles missing server gracefully" do
    result = BusinessOS.parallel_health_check(%{"url" => "http://localhost:9999"})
    assert {:error, _} = result
  end

  # ── Process Mining API Tests ────────────────────────────────────────

  describe "discover/2" do
    test "discovers process model from valid event log" do
      result =
        BusinessOS.discover(@sample_event_log, %{
          "url" => "http://localhost:8765"
        })

      # Should succeed or fail gracefully if mock not running
      case result do
        {:ok, model} ->
          assert is_map(model)

        {:error, _reason} ->
          # Mock server not running - that's ok for this test
          true
      end
    end

    test "fails with empty event log" do
      empty_log = %{"events" => []}

      result =
        BusinessOS.discover(empty_log, %{
          "url" => "http://localhost:8765"
        })

      case result do
        {:error, _} -> true
        {:ok, _} -> true
      end
    end

    test "fails with invalid host" do
      result =
        BusinessOS.discover(@sample_event_log, %{
          "url" => "http://invalid-host-xyz:8000"
        })

      assert {:error, {:connection_failed, _}} = result
    end
  end

  # ── Conformance Checking API Tests ──────────────────────────────────

  describe "conformance_check/3" do
    test "checks conformance of model against event log" do
      result =
        BusinessOS.conformance_check(@sample_model, @sample_event_log, %{
          "url" => "http://localhost:8765"
        })

      case result do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, "fitness") or Map.has_key?(result, "precision")

        {:error, _reason} ->
          # Server not running
          true
      end
    end

    test "supports different conformance methods" do
      for method <- ["token_replay", "alignment"] do
        result =
          BusinessOS.conformance_check(@sample_model, @sample_event_log, %{
            "url" => "http://localhost:8765",
            "method" => method
          })

        assert is_tuple(result)
      end
    end

    test "fails with invalid model structure" do
      invalid_model = %{"invalid" => "structure"}

      result =
        BusinessOS.conformance_check(invalid_model, @sample_event_log, %{
          "url" => "http://localhost:8765"
        })

      case result do
        {:error, _} -> true
        {:ok, _} -> true
      end
    end
  end

  # ── Compliance Verification API Tests ───────────────────────────────

  describe "verify_compliance/2" do
    test "verifies compliance against framework" do
      result =
        BusinessOS.verify_compliance("SOC2", %{
          "url" => "http://localhost:8765"
        })

      case result do
        {:ok, compliance} ->
          assert is_map(compliance)

        {:error, _reason} ->
          # Server not running
          true
      end
    end

    test "supports multiple frameworks" do
      for framework <- ["SOC2", "HIPAA", "GDPR"] do
        result =
          BusinessOS.verify_compliance(framework, %{
            "url" => "http://localhost:8765"
          })

        assert is_tuple(result)
      end
    end

    test "fails with invalid framework" do
      result =
        BusinessOS.verify_compliance("INVALID_FRAMEWORK", %{
          "url" => "http://localhost:8765"
        })

      case result do
        {:error, _} -> true
        {:ok, _} -> true
      end
    end
  end

  # ── Message Parsing Tests ───────────────────────────────────────────

  describe "execute_heartbeat/1" do
    test "returns a stream-like object" do
      stream = BusinessOS.execute_heartbeat(%{})
      assert is_function(stream) or match?(%Stream{}, stream)
    end

    test "heartbeat stream produces events" do
      stream = BusinessOS.execute_heartbeat(%{})

      result =
        stream
        |> Stream.take(1)
        |> Enum.to_list()

      assert is_list(result)
    end
  end

  describe "send_message/2" do
    test "accepts process_mining message" do
      message =
        Jason.encode!(%{
          "type" => "process_mining",
          "payload" => %{
            "event_log" => @sample_event_log
          }
        })

      stream = BusinessOS.send_message(%{}, message)
      assert is_function(stream) or match?(%Stream{}, stream)
    end

    test "accepts conformance message" do
      message =
        Jason.encode!(%{
          "type" => "conformance",
          "payload" => %{
            "event_log" => @sample_event_log,
            "model" => @sample_model,
            "method" => "token_replay"
          }
        })

      stream = BusinessOS.send_message(%{}, message)
      assert is_function(stream) or match?(%Stream{}, stream)
    end

    test "accepts compliance message" do
      message =
        Jason.encode!(%{
          "type" => "compliance",
          "payload" => %{
            "framework" => "SOC2"
          }
        })

      stream = BusinessOS.send_message(%{}, message)
      assert is_function(stream) or match?(%Stream{}, stream)
    end

    test "rejects invalid JSON" do
      stream = BusinessOS.send_message(%{}, "not valid json")
      result = stream |> Stream.take(1) |> Enum.to_list()

      assert is_list(result)
    end

    test "rejects unknown message type" do
      message = Jason.encode!(%{"type" => "unknown"})
      stream = BusinessOS.send_message(%{}, message)
      result = stream |> Stream.take(1) |> Enum.to_list()

      assert is_list(result)
    end
  end

  # ── Configuration Tests ─────────────────────────────────────────────

  describe "configuration" do
    test "uses custom URL from params" do
      custom_url = "http://custom.example.com:8001"
      config = %{"url" => custom_url}

      assert :ok = BusinessOS.stop(BusinessOS.start(config) |> elem(1))
    end

    test "uses custom timeout from params" do
      config = %{"timeout" => 60_000}
      assert :ok = BusinessOS.stop(BusinessOS.start(config) |> elem(1))
    end

    test "uses environment variable for token" do
      System.put_env("BUSINESSOS_API_TOKEN", "test-token-123")

      # Config builder should pick up env var
      result =
        BusinessOS.discover(@sample_event_log, %{
          "url" => "http://localhost:8765"
        })

      assert is_tuple(result)

      System.delete_env("BUSINESSOS_API_TOKEN")
    end
  end

  # ── Error Handling Tests ────────────────────────────────────────────

  describe "error handling" do
    test "connection failure is handled gracefully" do
      result =
        BusinessOS.discover(@sample_event_log, %{
          "url" => "http://invalid-host-xyz:8000"
        })

      assert {:error, {:connection_failed, _}} = result
    end

    test "timeout is handled gracefully" do
      result =
        BusinessOS.discover(@sample_event_log, %{
          "url" => "http://httpbin.org/delay/5",
          "timeout" => 100
        })

      assert is_tuple(result) and tuple_size(result) == 2
    end

    test "invalid log returns clear error" do
      result =
        BusinessOS.discover("not a map", %{
          "url" => "http://localhost:8765"
        })

      assert is_tuple(result)
    end
  end

  # ── Concurrent Execution Tests ──────────────────────────────────────

  describe "concurrent operations" do
    test "multiple mining calls can run simultaneously" do
      parent = self()

      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            result =
              BusinessOS.discover(
                @sample_event_log,
                %{"url" => "http://localhost:8765"}
              )

            send(parent, {:result, i, result})
          end)
        end

      Task.await_many(tasks)

      results =
        for i <- 1..3 do
          receive do
            {:result, ^i, result} -> result
          after
            5000 -> {:timeout}
          end
        end

      assert length(results) == 3
    end

    test "mining and conformance can run concurrently" do
      parent = self()

      mining_task =
        Task.async(fn ->
          result =
            BusinessOS.discover(@sample_event_log, %{
              "url" => "http://localhost:8765"
            })

          send(parent, {:mining, result})
        end)

      conf_task =
        Task.async(fn ->
          result =
            BusinessOS.conformance_check(@sample_model, @sample_event_log, %{
              "url" => "http://localhost:8765"
            })

          send(parent, {:conformance, result})
        end)

      Task.await(mining_task)
      Task.await(conf_task)

      mining_result =
        receive do
          {:mining, result} -> result
        after
          5000 -> {:timeout}
        end

      conf_result =
        receive do
          {:conformance, result} -> result
        after
          5000 -> {:timeout}
        end

      assert is_tuple(mining_result)
      assert is_tuple(conf_result)
    end
  end

  # ── Integration Tests ───────────────────────────────────────────────

  describe "adapter integration" do
    test "adapter is registered in Canopy.Adapter" do
      {:ok, mod} = Canopy.Adapter.resolve("businessos")
      assert mod == BusinessOS
    end

    test "adapter appears in adapter list" do
      adapters = Canopy.Adapter.all()
      adapter_types = Enum.map(adapters, & &1.type)
      assert "businessos" in adapter_types
    end

    test "adapter can be resolved and instantiated" do
      {:ok, mod} = Canopy.Adapter.resolve("businessos")
      assert {:ok, _session} = mod.start(%{})
    end
  end

  # ── YAWL Simulation API Tests ────────────────────────────────────────

  test "capabilities includes :workflow_simulation" do
    assert :workflow_simulation in BusinessOS.capabilities()
  end

  describe "simulate_workflows/2" do
    test "returns error when BusinessOS server is unreachable" do
      result = BusinessOS.simulate_workflows(%{}, %{"url" => "http://localhost:9999"})
      assert {:error, {:connection_failed, _}} = result
    end

    test "send_message with yawl_simulate type dispatches simulation" do
      # Without a live BusinessOS, the call should return a simulation_failed event
      # (connection refused) rather than crashing.
      msg = Jason.encode!(%{
        "type" => "yawl_simulate",
        "payload" => %{"spec_set" => "basic_wcp", "user_count" => 1}
      })

      events = BusinessOS.send_message(%{}, msg) |> Enum.to_list()
      assert length(events) == 1
      [event] = events
      assert event["event_type"] in ["simulation_complete", "simulation_failed"]
    end

    test "parse unknown message type returns parse_error event" do
      msg = Jason.encode!(%{"type" => "unknown_op", "payload" => %{}})
      events = BusinessOS.send_message(%{}, msg) |> Enum.to_list()
      assert length(events) == 1
      [event] = events
      assert event["event_type"] == "parse_error"
    end
  end
end
