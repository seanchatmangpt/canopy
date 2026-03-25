defmodule Canopy.Adapters.MCP do
  @moduledoc """
  MCP (Model Context Protocol) adapter — connects to MCP servers and exposes
  their tools, resources, and prompts as Canopy agent capabilities.

  Supports two transports:
  - **stdio** — Spawns an MCP server process via Erlang Port
  - **http**  — Connects to a remote MCP server via HTTP (JSON-RPC 2.0)

  The session map contains:
      %{
        pid: pid(),
        server_name: String.t(),
        tools: [map()],
        resources: [map()],
        prompts: [map()],
        transport: :stdio | :http
      }
  """
  @behaviour Canopy.Adapter

  require Logger

  @default_transport "stdio"
  @default_command "npx"
  @default_args ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]

  @impl true
  def type, do: "mcp"

  @impl true
  def name, do: "MCP"

  @impl true
  def supports_session?, do: true

  @impl true
  def supports_concurrent?, do: true

  @impl true
  def capabilities, do: [:tools, :resources, :prompts]

  # ── Public API ──────────────────────────────────────────────────────

  @impl true
  def start(config) do
    transport = config["transport"] || @default_transport

    case transport do
      "stdio" -> start_stdio(config)
      "http" -> start_http(config)
      other -> {:error, {:unknown_transport, other}}
    end
  end

  @impl true
  def stop(%{pid: pid, transport: transport}) do
    if is_pid(pid) and Process.alive?(pid) do
      GenServer.stop(pid, :normal, 5_000)
    end

    Logger.info("[MCP Adapter] Stopped #{transport} server connection")
    :ok
  end

  def stop(_session), do: :ok

  @impl true
  def execute_heartbeat(params) do
    session = params["session"]

    if session && is_pid(session[:pid]) && Process.alive?(session[:pid]) do
      tools = Canopy.Adapters.MCPServer.list_tools(session[:pid])

      event = %{
        event_type: "run.output",
        data: %{
          "status" => "connected",
          "server" => session[:server_name],
          "tools_count" => length(tools),
          "tools" => Enum.map(tools, & &1["name"]),
          "transport" => Atom.to_string(session[:transport])
        },
        tokens: 0
      }

      Stream.resource(
        fn -> :once end,
        fn
          :once ->
            {[event, %{event_type: "run.completed", data: %{"status" => "ok"}, tokens: 0}], :done}

          :done ->
            {:halt, :done}
        end,
        fn _ -> :ok end
      )
    else
      error_stream("MCP server not connected or pid is dead")
    end
  end

  @impl true
  def send_message(%{pid: pid, tools: tools} = _session, message) do
    case parse_tool_call(message, tools) do
      {:ok, tool_name, arguments} ->
        case Canopy.Adapters.MCPServer.call_tool(pid, tool_name, arguments) do
          {:ok, result} ->
            content = format_tool_result(result)

            Stream.resource(
              fn -> :once end,
              fn
                :once ->
                  {[
                     %{
                       event_type: "run.delta",
                       data: %{"content" => content},
                       tokens: 0
                     },
                     %{
                       event_type: "run.completed",
                       data: %{"status" => "ok", "tool" => tool_name},
                       tokens: 0
                     }
                   ], :done}

                :done ->
                  {:halt, :done}
              end,
              fn _ -> :ok end
            )

          {:error, reason} ->
            error_stream("MCP tool call failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        error_stream("Failed to parse tool call: #{inspect(reason)}")
    end
  end

  # ── Private: Transport startup ──────────────────────────────────────

  defp start_stdio(config) do
    command = config["command"] || @default_command
    args = config["args"] || @default_args
    server_name = config["server_name"] || "#{command} #{Enum.join(args, " ")}"

    start_opts = %{
      transport: :stdio,
      command: command,
      args: args,
      env: config["env"] || %{}
    }

    case Canopy.Adapters.MCPServer.start_link(start_opts) do
      {:ok, pid} ->
        case discover_server_capabilities(pid, server_name, :stdio) do
          {:ok, session} ->
            Logger.info("[MCP Adapter] Connected to #{server_name} via stdio")
            {:ok, session}

          {:error, reason} ->
            GenServer.stop(pid, :normal, 5_000)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:stdio_launch_failed, reason}}
    end
  end

  defp start_http(config) do
    url = config["url"] || raise "MCP HTTP adapter requires 'url' in config"
    server_name = config["server_name"] || url

    start_opts = %{
      transport: :http,
      url: url,
      headers: config["headers"] || %{}
    }

    case Canopy.Adapters.MCPServer.start_link(start_opts) do
      {:ok, pid} ->
        case discover_server_capabilities(pid, server_name, :http) do
          {:ok, session} ->
            Logger.info("[MCP Adapter] Connected to #{server_name} via HTTP")
            {:ok, session}

          {:error, reason} ->
            GenServer.stop(pid, :normal, 5_000)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:http_connection_failed, reason}}
    end
  end

  defp discover_server_capabilities(pid, server_name, transport) do
    case Canopy.Adapters.MCPServer.list_tools(pid) do
      tools when is_list(tools) ->
        {:ok,
         %{
           pid: pid,
           server_name: server_name,
           tools: tools,
           transport: transport
         }}

      {:error, reason} ->
        {:error, {:capability_discovery_failed, reason}}
    end
  end

  # ── Private: Message parsing ────────────────────────────────────────

  defp parse_tool_call(message, tools) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, decoded} when is_map(decoded) ->
        extract_tool_and_args(decoded, tools)

      _ ->
        # Treat plain text as a request to list available tools
        {:error, :not_a_tool_call}
    end
  end

  defp parse_tool_call(message, tools) when is_map(message) do
    extract_tool_and_args(message, tools)
  end

  defp extract_tool_and_args(decoded, tools) do
    tool_name = decoded["tool_name"] || decoded["name"] || decoded["tool"]

    if tool_name do
      arguments = decoded["arguments"] || decoded["args"] || decoded["input"] || %{}

      known_names = Enum.map(tools, & &1["name"])

      if tool_name in known_names do
        {:ok, tool_name, arguments}
      else
        {:error, {:unknown_tool, tool_name, known_names}}
      end
    else
      {:error, :missing_tool_name}
    end
  end

  defp format_tool_result(result) when is_list(result) do
    result
    |> Enum.map(&format_content_block/1)
    |> Enum.join("\n")
  end

  defp format_tool_result(result) when is_map(result) do
    Jason.encode_to_iodata!(result)
  end

  defp format_tool_result(result) when is_binary(result), do: result

  defp format_content_block(%{"type" => "text", "text" => text}), do: text
  defp format_content_block(%{"text" => text}), do: text
  defp format_content_block(other), do: Jason.encode_to_iodata!(other)

  defp error_stream(message) do
    Stream.resource(
      fn -> :once end,
      fn
        :once ->
          {[
             %{
               event_type: "run.failed",
               data: %{"error" => message},
               tokens: 0
             }
           ], :done}

        :done ->
          {:halt, :done}
      end,
      fn _ -> :ok end
    )
  end
end
