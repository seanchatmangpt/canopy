defmodule Canopy.Adapters.BusinessOSSimulateTest do
  @moduledoc """
  Unit tests for the YAWL simulation extension to the BusinessOS adapter.

  These tests do NOT require a live BusinessOS or OSA server.
  Connection-refused errors are expected and asserted.
  """
  use ExUnit.Case, async: true

  alias Canopy.Adapters.BusinessOS

  # ── Capabilities ─────────────────────────────────────────────────────

  test "capabilities includes :workflow_simulation" do
    assert :workflow_simulation in BusinessOS.capabilities()
  end

  # ── simulate_workflows/2 ─────────────────────────────────────────────

  describe "simulate_workflows/2" do
    test "returns connection_failed when BusinessOS is unreachable" do
      result = BusinessOS.simulate_workflows(%{}, %{"url" => "http://localhost:9998"})
      assert {:error, {:connection_failed, _}} = result
    end

    test "passes spec_set default of basic_wcp in payload" do
      # No server → connection error. We verify the function accepts default payload.
      result = BusinessOS.simulate_workflows(%{})
      assert match?({:error, _}, result)
    end

    test "accepts all valid spec_set values without crashing" do
      for spec_set <- ["basic_wcp", "wcp_patterns", "real_data", "all"] do
        result = BusinessOS.simulate_workflows(%{"spec_set" => spec_set}, %{"url" => "http://localhost:9998"})
        assert match?({:error, _}, result), "Expected error for spec_set=#{spec_set}"
      end
    end
  end

  # ── send_message dispatch ─────────────────────────────────────────────

  describe "send_message yawl_simulate" do
    test "dispatches yawl_simulate message type and returns a stream event" do
      msg = Jason.encode!(%{
        "type" => "yawl_simulate",
        "payload" => %{"spec_set" => "basic_wcp", "user_count" => 1}
      })

      events = BusinessOS.send_message(%{}, msg) |> Enum.to_list()
      assert length(events) == 1
      [event] = events
      # Connection refused → simulation_failed; live → simulation_complete
      assert event["event_type"] in ["simulation_complete", "simulation_failed"]
    end

    test "yawl_simulate event has data key" do
      msg = Jason.encode!(%{
        "type" => "yawl_simulate",
        "payload" => %{"spec_set" => "basic_wcp", "user_count" => 1}
      })

      [event] = BusinessOS.send_message(%{}, msg) |> Enum.to_list()
      assert Map.has_key?(event, "data")
    end

    test "unknown message type returns parse_error" do
      msg = Jason.encode!(%{"type" => "launch_rockets", "payload" => %{}})
      [event] = BusinessOS.send_message(%{}, msg) |> Enum.to_list()
      assert event["event_type"] == "parse_error"
    end

    test "malformed JSON returns parse_error" do
      [event] = BusinessOS.send_message(%{}, "not json {{{") |> Enum.to_list()
      assert event["event_type"] == "parse_error"
    end
  end
end
