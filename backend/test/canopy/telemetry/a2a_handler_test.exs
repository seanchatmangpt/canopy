defmodule Canopy.Telemetry.A2AHandlerTest do
  @moduledoc """
  Chicago TDD tests for Canopy.Telemetry.A2AHandler.

  Tests that the handler attaches correctly and processes telemetry events.
  """

  use ExUnit.Case, async: false

  alias Canopy.Telemetry.A2AHandler

  describe "attach/0" do
    test "attaches handler without raising" do
      assert :ok == A2AHandler.attach()
    end

    test "can be called multiple times (idempotent — detaches old handler first)" do
      assert :ok == A2AHandler.attach()
      assert :ok == A2AHandler.attach()
    end
  end

  describe "handle_event/4" do
    test "handles a2a message start event without raising" do
      A2AHandler.handle_event(
        [:a2a, :message, :start],
        %{},
        %{method: "message/send"},
        %{tracer: :opentelemetry.get_tracer(:canopy)}
      )

      # Clean up process dict
      Process.delete({:a2a_span, :message})
    end

    test "handles a2a message stop event without raising when no span in process dict" do
      # Ensure no span in process dict
      Process.delete({:a2a_span, :message})

      A2AHandler.handle_event(
        [:a2a, :message, :stop],
        %{duration: 1_000_000},
        %{},
        %{}
      )
    end

    test "handles a2a cancel start event without raising" do
      A2AHandler.handle_event(
        [:a2a, :cancel, :start],
        %{},
        %{task_id: "test-task-123"},
        %{tracer: :opentelemetry.get_tracer(:canopy)}
      )

      Process.delete({:a2a_span, :cancel})
    end

    test "handles unknown event without raising" do
      A2AHandler.handle_event(
        [:a2a, :unknown, :event],
        %{},
        %{},
        %{}
      )
    end
  end
end
