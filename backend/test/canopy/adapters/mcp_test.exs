defmodule Canopy.Adapters.MCPTest do
  use ExUnit.Case, async: true

  alias Canopy.Adapters.MCP

  describe "behaviour contract" do
    test "type/0 returns 'mcp'" do
      assert MCP.type() == "mcp"
    end

    test "name/0 returns 'MCP'" do
      assert MCP.name() == "MCP"
    end

    test "supports_session?/0 returns true" do
      assert MCP.supports_session?() == true
    end

    test "supports_concurrent?/0 returns true" do
      assert MCP.supports_concurrent?() == true
    end

    test "capabilities/0 returns expected list" do
      caps = MCP.capabilities()
      assert :tools in caps
      assert :resources in caps
      assert :prompts in caps
    end
  end

  describe "start/1 with unknown transport" do
    test "returns error for unknown transport" do
      assert {:error, {:unknown_transport, "websocket"}} =
               MCP.start(%{"transport" => "websocket"})
    end
  end

  describe "start/1 with HTTP transport" do
    test "returns error when url is missing" do
      assert_raise RuntimeError, ~r/requires 'url'/, fn ->
        MCP.start(%{"transport" => "http"})
      end
    end
  end

  describe "stop/1" do
    test "returns :ok for a map without a pid" do
      assert MCP.stop(%{}) == :ok
    end

    test "returns :ok for a session with a dead pid" do
      dead_pid = spawn(fn -> :ok end)
      # Wait for process to die
      Process.monitor(dead_pid)
      receive do
        {:DOWN, _, :process, ^dead_pid, _} -> :ok
      end

      assert MCP.stop(%{pid: dead_pid, transport: :stdio}) == :ok
    end
  end

  describe "execute_heartbeat/1" do
    test "returns error stream when session is missing" do
      events = MCP.execute_heartbeat(%{}) |> Enum.to_list()

      assert [%{event_type: "run.failed"}] = events
      assert events |> hd() |> get_in([:data, "error"]) =~ "not connected"
    end

    test "returns error stream when session pid is dead" do
      dead_pid = spawn(fn -> :ok end)
      Process.monitor(dead_pid)
      receive do
        {:DOWN, _, :process, ^dead_pid, _} -> :ok
      end

      session = %{pid: dead_pid, server_name: "test", transport: :stdio}
      events = MCP.execute_heartbeat(%{"session" => session}) |> Enum.to_list()

      assert [%{event_type: "run.failed"}] = events
    end
  end

  describe "send_message/2" do
    test "returns error stream when message is not a tool call" do
      session = %{pid: self(), tools: [], transport: :stdio}

      events = MCP.send_message(session, "hello world") |> Enum.to_list()

      assert [%{event_type: "run.failed"}] = events
    end

    test "returns error stream for unknown tool" do
      session = %{pid: self(), tools: [%{"name" => "known_tool"}], transport: :stdio}
      message = Jason.encode!(%{"tool_name" => "unknown_tool", "arguments" => %{}})

      events = MCP.send_message(session, message) |> Enum.to_list()

      assert [%{event_type: "run.failed"}] = events
    end

    test "parses tool call from JSON message" do
      session = %{pid: self(), tools: [%{"name" => "read_file"}], transport: :stdio}
      message = Jason.encode!(%{"tool_name" => "read_file", "arguments" => %{"path" => "/tmp"}})

      # Will fail at GenServer.call since self() isn't a real MCPServer,
      # but we can test the parsing worked by checking it attempts the call
      assert catch_error(MCP.send_message(session, message) |> Enum.to_list())
    end

    test "accepts map message directly" do
      session = %{pid: self(), tools: [%{"name" => "read_file"}], transport: :stdio}
      message = %{"tool_name" => "read_file", "arguments" => %{"path" => "/tmp"}}

      # Parsing succeeds; GenServer.call fails since self() is not a real MCPServer
      assert catch_error(MCP.send_message(session, message) |> Enum.to_list())
    end
  end

  describe "parse_tool_call (via send_message)" do
    test "supports 'name' key for tool name" do
      session = %{pid: self(), tools: [%{"name" => "my_tool"}], transport: :stdio}
      message = Jason.encode!(%{"name" => "my_tool", "arguments" => %{}})

      assert catch_error(MCP.send_message(session, message) |> Enum.to_list())
    end

    test "supports 'tool' key for tool name" do
      session = %{pid: self(), tools: [%{"name" => "my_tool"}], transport: :stdio}
      message = Jason.encode!(%{"tool" => "my_tool", "args" => %{}})

      assert catch_error(MCP.send_message(session, message) |> Enum.to_list())
    end

    test "supports 'input' key for arguments" do
      session = %{pid: self(), tools: [%{"name" => "my_tool"}], transport: :stdio}
      message = Jason.encode!(%{"tool_name" => "my_tool", "input" => %{"key" => "val"}})

      assert catch_error(MCP.send_message(session, message) |> Enum.to_list())
    end

    test "returns error for missing tool name" do
      session = %{pid: self(), tools: [%{"name" => "my_tool"}], transport: :stdio}
      message = Jason.encode!(%{"arguments" => %{}})

      events = MCP.send_message(session, message) |> Enum.to_list()
      assert [%{event_type: "run.failed"}] = events
    end
  end
end
