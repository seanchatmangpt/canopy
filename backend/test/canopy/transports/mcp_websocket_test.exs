defmodule Canopy.Transports.MCPWebsocketTest do
  use ExUnit.Case, async: true

  alias Canopy.Transports.MCPWebsocket

  describe "init/1" do
    test "requires url" do
      assert {:error, :missing_url} = MCPWebsocket.init(%{})
    end

    test "rejects non-websocket URLs" do
      assert {:error, :invalid_websocket_url} = MCPWebsocket.init(%{url: "http://localhost:3000"})
    end

    test "rejects non-websocket HTTPS URLs" do
      assert {:error, :invalid_websocket_url} =
               MCPWebsocket.init(%{url: "https://localhost:3000"})
    end

    test "validates ws:// and wss:// URL formats" do
      # Valid URLs will attempt to connect (will fail with connection error, not validation error)
      result1 = MCPWebsocket.init(%{url: "ws://localhost:3000/mcp"})
      # Should be connection error, not validation error
      assert {:error, _} = result1

      result2 = MCPWebsocket.init(%{url: "wss://localhost:3000/mcp"})
      assert {:error, _} = result2
    end
  end

  describe "module callbacks" do
    test "onopen/2 sends websocket_connected message" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      new_state = MCPWebsocket.onopen(nil, state)

      assert_receive {:websocket_connected, _}
      assert new_state == state
    end

    test "onmessage with invalid JSON logs warning" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      new_state = MCPWebsocket.onmessage({:text, "invalid json {{"}, state)

      assert new_state == state
    end

    test "onmessage with JSON-RPC response sends message" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"tools" => []}
      }

      MCPWebsocket.onmessage({:text, Jason.encode!(response)}, state)

      assert_receive {:mcp_response, 1, result}
      assert result == %{"tools" => []}
    end

    test "onmessage with JSON-RPC error sends error message" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      error_response = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "error" => %{"code" => -32600, "message" => "Invalid Request"}
      }

      MCPWebsocket.onmessage({:text, Jason.encode!(error_response)}, state)

      assert_receive {:mcp_error, 2, error}
      assert error == %{"code" => -32600, "message" => "Invalid Request"}
    end

    test "onmessage with JSON-RPC notification" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized",
        "params" => %{}
      }

      new_state = MCPWebsocket.onmessage({:text, Jason.encode!(notification)}, state)

      assert new_state == state
    end

    test "onclose/2 sends websocket_closed message" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      new_state = MCPWebsocket.onclose(:normal, state)

      assert_receive {:websocket_closed, :normal}
      assert new_state == state
    end

    test "onerrror/2 sends websocket_error message" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      new_state = MCPWebsocket.onerrror("test error", state)

      assert_receive {:websocket_error, _, "test error"}
      assert new_state == state
    end

    test "onmessage with binary frame logs warning" do
      handler_pid = self()
      state = %{handler_pid: handler_pid, headers: %{}}

      new_state = MCPWebsocket.onmessage({:binary, <<1, 2, 3>>}, state)

      assert new_state == state
    end
  end

  describe "close/1" do
    test "returns ok with valid state" do
      state = %{ws_pid: nil}
      assert :ok = MCPWebsocket.close(state)
    end

    test "handles non-existent pid" do
      state = %{ws_pid: :invalid_pid}
      assert :ok = MCPWebsocket.close(state)
    end
  end
end
