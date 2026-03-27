defmodule Canopy.Errors.WvdAError do
  @moduledoc """
  van der Aalst (WvdA) Soundness Violation errors for Canopy.

  Canopy's multi-agent coordination must be deadlock-free, liveness-guaranteed,
  and bounded. This module provides helpful error messages for violations
  in the heartbeat dispatch, agent coordination, and websocket management layers.

  See parent module: OptimalSystemAgent.Errors.WvdAError (OSA primary implementation)
  """

  defmodule HeartbeatDeadlock do
    @moduledoc """
    Heartbeat dispatch deadlock: agent blocked waiting for response.

    Canopy's heartbeat sends per-agent, per-tier budgets. If agent blocks
    without timeout, entire heartbeat round stalls.
    """
    defexception [:agent_id, :tier, :message]

    def new(agent_id, tier \\ :normal, message \\ "") do
      %__MODULE__{
        agent_id: agent_id,
        tier: tier,
        message:
          message ||
            "Heartbeat deadlock: agent #{agent_id} (tier=#{tier}) blocked without timeout. " <>
              "Fix: add timeout to agent handler. " <>
              "Example: {:reply, result, timeout: 5000}"
      }
    end

    def message(error) do
      error.message
    end
  end

  defmodule WebSocketLiveness do
    @moduledoc """
    WebSocket liveness violation: connection handler infinite loop.

    WebSocket connections must handle message receipt with explicit timeout
    to prevent handler thread starvation.
    """
    defexception [:connection_id, :message]

    def new(connection_id, message \\ "") do
      %__MODULE__{
        connection_id: connection_id,
        message:
          message ||
            "WebSocket liveness violation: connection #{connection_id} infinite loop. " <>
              "Fix: add receive timeout in handle_in. " <>
              "Example: receive do msg -> ... after 30000 -> close() end"
      }
    end

    def message(error) do
      error.message
    end
  end

  defmodule AgentQueueBoundedness do
    @moduledoc """
    Agent message queue unbounded: memory grows with pending tasks.

    Each agent has internal queue. If producer >> consumer, queue exhausts memory.
    """
    defexception [:agent_id, :queue_size, :message]

    def new(agent_id, queue_size, message \\ "") do
      %__MODULE__{
        agent_id: agent_id,
        queue_size: queue_size,
        message:
          message ||
            "Agent queue unbounded: #{agent_id} queue size=#{queue_size}. " <>
              "Fix: add max_queue_size with backpressure. " <>
              "Example: if queue_size > 1000 do return :backpressure end"
      }
    end

    def message(error) do
      error.message
    end
  end
end
