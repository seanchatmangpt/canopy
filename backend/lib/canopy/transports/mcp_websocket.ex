defmodule Canopy.Transports.MCPWebsocket do
  @moduledoc """
  WebSocket transport for MCP (Model Context Protocol) server communication.

  Establishes a persistent WebSocket connection to an MCP server and provides
  JSON-RPC 2.0 request/response handling over that connection.

  ## State Structure

  ```elixir
  %{
    ws_pid: pid(),                    # WebSocket connection process
    request_id: integer(),            # Counter for JSON-RPC request IDs
    pending: %{id => {from, timeout}} # Pending requests awaiting response
  }
  ```
  """

  require Logger

  @doc """
  Initialize a WebSocket transport connection to an MCP server.

  ## Options

    - `:url` — WebSocket URL to connect to (required, e.g., "ws://localhost:3000/mcp")
    - `:headers` — map of HTTP headers (optional)
    - `:timeout_ms` — connection timeout in milliseconds (default: 30000)

  ## Returns

  `{:ok, state}` with transport state map, or `{:error, reason}`
  """
  def init(opts) do
    url = Map.get(opts, :url)
    headers = Map.get(opts, :headers, %{})
    timeout_ms = Map.get(opts, :timeout_ms, 30_000)

    case validate_url(url) do
      :ok ->
        connect_websocket(url, headers, timeout_ms)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_url(nil), do: {:error, :missing_url}

  defp validate_url(url) when is_binary(url) do
    if String.starts_with?(url, ["ws://", "wss://"]) do
      :ok
    else
      {:error, :invalid_websocket_url}
    end
  end

  defp validate_url(_), do: {:error, :invalid_url}

  @doc """
  Send a JSON-RPC 2.0 request and wait for response.

  ## Parameters

    - `state` — transport state
    - `method` — JSON-RPC method name
    - `params` — JSON-RPC params (map or list)

  ## Returns

  `{:ok, result, new_state}` or `{:error, reason}`
  """
  def request(state, method, params) do
    request_id = state.request_id + 1
    new_state = %{state | request_id: request_id}

    message = %{
      "jsonrpc" => "2.0",
      "id" => request_id,
      "method" => method,
      "params" => params
    }

    case send_websocket_message(state.ws_pid, message) do
      :ok ->
        case wait_for_response(request_id, new_state, 60_000) do
          {:ok, result, final_state} ->
            {:ok, result, final_state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:send_failed, reason}}
    end
  end

  @doc """
  Send a JSON-RPC 2.0 notification (fire-and-forget, no response expected).

  ## Parameters

    - `state` — transport state
    - `method` — JSON-RPC method name
    - `params` — JSON-RPC params (map or list)

  ## Returns

  `:ok` or `{:error, reason}`
  """
  def notify(state, method, params) do
    message = %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }

    send_websocket_message(state.ws_pid, message)
  end

  @doc """
  Close the WebSocket connection and cleanup.

  ## Parameters

    - `state` — transport state

  ## Returns

  `:ok`
  """
  def close(state) do
    if is_pid(state.ws_pid) and Process.alive?(state.ws_pid) do
      try do
        Process.exit(state.ws_pid, :kill)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # ─── Private: WebSocket Connection ──────────────────────────────────────

  defp connect_websocket(url, headers, timeout_ms) do
    case :websocket_client.start_link(
           String.to_charlist(url),
           __MODULE__,
           %{handler_pid: self(), headers: headers},
           recv_timeout: timeout_ms,
           close_timeout: timeout_ms
         ) do
      {:ok, ws_pid} ->
        # Wait for connection confirmation from handler callback
        receive do
          {:websocket_connected, ^ws_pid} ->
            {:ok, %{ws_pid: ws_pid, request_id: 0, pending: %{}}}

          {:websocket_error, ^ws_pid, reason} ->
            {:error, {:connection_failed, reason}}
        after
          timeout_ms ->
            Process.exit(ws_pid, :kill)
            {:error, :connection_timeout}
        end

      {:error, reason} ->
        {:error, {:websocket_error, reason}}
    end
  end

  defp send_websocket_message(ws_pid, message) do
    json = Jason.encode!(message)

    try do
      :websocket_client.send(ws_pid, {:text, json})
      :ok
    rescue
      e ->
        {:error, {:send_failed, inspect(e)}}
    end
  end

  defp wait_for_response(request_id, state, timeout_ms) do
    receive do
      {:mcp_response, ^request_id, response} ->
        {:ok, response, state}

      {:mcp_error, ^request_id, error} ->
        {:error, {:jsonrpc_error, error}}

      {:websocket_closed, _reason} ->
        {:error, :connection_closed}
    after
      timeout_ms ->
        {:error, :timeout}
    end
  end

  # ─── WebSocket Handler Callbacks ────────────────────────────────────────

  @doc """
  WebSocket client callback: connection opened.
  """
  def onopen(_req, state) do
    send(state.handler_pid, {:websocket_connected, self()})
    state
  end

  @doc """
  WebSocket client callback: message received.
  """
  def onmessage({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        handle_mcp_message(decoded, state)

      {:error, reason} ->
        Logger.warning("[MCPWebsocket] Failed to decode JSON: #{inspect(reason)}")
        state
    end
  end

  def onmessage({:binary, _data}, state) do
    Logger.warning("[MCPWebsocket] Received binary frame, ignoring")
    state
  end

  @doc """
  WebSocket client callback: connection closed.
  """
  def onclose(reason, state) do
    Logger.info("[MCPWebsocket] Connection closed: #{inspect(reason)}")
    send(state.handler_pid, {:websocket_closed, reason})
    state
  end

  @doc """
  WebSocket client callback: error occurred.
  """
  def onerrror(reason, state) do
    Logger.error("[MCPWebsocket] WebSocket error: #{inspect(reason)}")
    send(state.handler_pid, {:websocket_error, self(), reason})
    state
  end

  # ─── Message Handling ──────────────────────────────────────────────────

  defp handle_mcp_message(msg, state) do
    case msg do
      %{"id" => id, "result" => result} ->
        # Response to a request
        send(state.handler_pid, {:mcp_response, id, result})
        state

      %{"id" => id, "error" => error} ->
        # Error response to a request
        send(state.handler_pid, {:mcp_error, id, error})
        state

      %{"method" => method, "params" => _params} ->
        # Server-initiated notification
        Logger.info("[MCPWebsocket] Received notification: #{method}")
        state

      other ->
        Logger.warning("[MCPWebsocket] Received unexpected message: #{inspect(other)}")
        state
    end
  end
end
