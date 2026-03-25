defmodule Canopy.Adapters.MCPServer do
  @moduledoc """
  GenServer that manages a connection to a single MCP (Model Context Protocol) server.

  Handles JSON-RPC 2.0 communication over two transports:
  - **stdio** — Spawns the MCP server as an Erlang Port and communicates via stdin/stdout
  - **http**  — Sends JSON-RPC 2.0 requests via HTTP POST using Req

  Lifecycle:
  1. `start_link/1` with transport config
  2. On init: sends `initialize` request, then `initialized` notification
  3. `list_tools/1` and `call_tool/3` for tool interaction
  """

  use GenServer

  require Logger

  @jsonrpc_version "2.0"
  @init_timeout 30_000
  @request_timeout 60_000

  # ── Client API ──────────────────────────────────────────────────────

  @doc """
  Starts the MCP server connection GenServer.

  ## Options

  For stdio transport:
    - `:transport` — `:stdio`
    - `:command` — command to spawn (e.g., `"npx"`)
    - `:args` — list of arguments
    - `:env` — environment variables map

  For HTTP transport:
    - `:transport` — `:http`
    - `:url` — MCP server URL
    - `:headers` — map of HTTP headers

  For WebSocket transport:
    - `:transport` — `:websocket`
    - `:url` — MCP server WebSocket URL (e.g., `"ws://localhost:3000/mcp"`)
    - `:headers` — map of HTTP headers (optional)
  """
  def start_link(opts) when is_map(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Lists all tools available on the MCP server.
  Returns a list of tool maps or `{:error, reason}`.
  """
  @spec list_tools(pid()) :: [map()] | {:error, term()}
  def list_tools(pid) do
    GenServer.call(pid, :list_tools, @request_timeout)
  end

  @doc """
  Calls a tool on the MCP server.

  ## Parameters
    - `pid` — GenServer pid
    - `tool_name` — name of the tool to call
    - `arguments` — map of tool arguments
  """
  @spec call_tool(pid(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def call_tool(pid, tool_name, arguments \\ %{}) do
    GenServer.call(pid, {:call_tool, tool_name, arguments}, @request_timeout)
  end

  # ── Server callbacks ────────────────────────────────────────────────

  @impl true
  def init(opts) do
    transport = Map.get(opts, :transport, :stdio)

    case initialize_transport(transport, opts) do
      {:ok, transport_state} ->
        case send_initialize(transport_state) do
          {:ok, server_info, new_state} ->
            Logger.info("[MCPServer] Initialized: #{inspect(server_info)}")
            {:ok, %{transport: transport, state: new_state, server_info: server_info}}

          {:error, reason} ->
            cleanup_transport(transport, transport_state)
            {:stop, {:initialization_failed, reason}}
        end

      {:error, reason} ->
        {:stop, {:transport_failed, reason}}
    end
  end

  @impl true
  def handle_call(:list_tools, _from, %{state: transport_state} = state) do
    case jsonrpc_request(transport_state, "tools/list", %{}) do
      {:ok, %{"tools" => tools}, new_state} ->
        {:reply, tools, %{state | state: new_state}}

      {:ok, response, new_state} ->
        Logger.warning("[MCPServer] Unexpected tools/list response: #{inspect(response)}")
        {:reply, [], %{state | state: new_state}}

      {:error, reason} ->
        Logger.error("[MCPServer] tools/list failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:call_tool, tool_name, arguments}, _from, %{state: transport_state} = state) do
    params = %{"name" => tool_name, "arguments" => arguments}

    case jsonrpc_request(transport_state, "tools/call", params) do
      {:ok, %{"content" => content}, new_state} ->
        {:reply, {:ok, content}, %{state | state: new_state}}

      {:ok, response, new_state} ->
        # Some servers return result at top level
        {:reply, {:ok, response}, %{state | state: new_state}}

      {:error, reason} ->
        Logger.error("[MCPServer] tools/call failed for #{tool_name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, %{transport: transport, state: transport_state}) do
    cleanup_transport(transport, transport_state)
  end

  def terminate(_reason, _state), do: :ok

  # ── Transport: stdio ────────────────────────────────────────────────

  defp initialize_transport(:stdio, opts) do
    command = Map.get(opts, :command, "npx")
    args = Map.get(opts, :args, [])
    env = Map.get(opts, :env, %{} || %{})

    port =
      Port.open({:spawn_executable, find_executable(command)},
        args: args,
        env: env |> Enum.to_list(),
        line: 1024 * 1024,
        use_stdio: true,
        stderr_to_stdout: false
      )

    # Give the process a moment to start
    Process.sleep(100)

    {:ok, %{port: port, pending_id: nil, buffer: ""}}
  end

  defp initialize_transport(:http, opts) do
    url = Map.get(opts, :url)
    headers = Map.get(opts, :headers, %{})

    if url do
      {:ok, %{url: url, headers: headers, request_id: 0}}
    else
      {:error, :missing_url}
    end
  end

  defp initialize_transport(:websocket, opts) do
    url = Map.get(opts, :url)
    headers = Map.get(opts, :headers, %{})

    if url do
      case Canopy.Transports.MCPWebsocket.init(%{url: url, headers: headers}) do
        {:ok, ws_state} ->
          {:ok, ws_state}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing_url}
    end
  end

  defp initialize_transport(transport, _opts) do
    {:error, {:unsupported_transport, transport}}
  end

  defp find_executable(command) do
    case System.find_executable(command) do
      nil -> command
      path -> String.to_charlist(path)
    end
  end

  # ── JSON-RPC communication ──────────────────────────────────────────

  defp send_initialize(%{port: _port} = state) do
    params = %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "canopy-mcp-adapter", "version" => "0.1.0"}
    }

    case jsonrpc_request(state, "initialize", params) do
      {:ok, response, new_state} ->
        # Send initialized notification (no response expected)
        jsonrpc_notify(new_state, "notifications/initialized", %{})
        {:ok, response, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_initialize(%{url: _url} = state) do
    params = %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "canopy-mcp-adapter", "version" => "0.1.0"}
    }

    case jsonrpc_request(state, "initialize", params) do
      {:ok, response, new_state} ->
        jsonrpc_notify(new_state, "notifications/initialized", %{})
        {:ok, response, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp jsonrpc_request(%{port: port} = state, method, params) do
    request_id = System.unique_integer([:positive])
    request = build_jsonrpc_request(request_id, method, params)
    request_json = Jason.encode!(request)

    send_port_data(port, request_json <> "\n")

    case wait_for_response(port, request_id, state, @init_timeout) do
      {:ok, result, buffer} ->
        {:ok, result, %{state | buffer: buffer, pending_id: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp jsonrpc_request(%{url: url, headers: headers} = state, method, params) do
    request_id = state[:request_id] || 0
    request = build_jsonrpc_request(request_id, method, params)

    req_headers =
      [{"Content-Type", "application/json"}] ++ Map.to_list(headers)

    case Req.post(url,
           json: request,
           headers: req_headers,
           receive_timeout: @request_timeout
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        case parse_jsonrpc_response(resp_body, request_id) do
          {:ok, result} ->
            new_state = %{state | request_id: request_id + 1}
            {:ok, result, new_state}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp jsonrpc_request(%{ws_pid: _ws_pid} = state, method, params) do
    case Canopy.Transports.MCPWebsocket.request(state, method, params) do
      {:ok, result, new_state} ->
        {:ok, result, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp jsonrpc_notify(%{port: _port}, _method, _params) do
    # For stdio, we could send a notification but it's fire-and-forget
    # The initialized notification is optional for many servers
    :ok
  end

  defp jsonrpc_notify(%{url: url, headers: headers}, method, params) do
    notification = build_jsonrpc_notification(method, params)

    req_headers =
      [{"Content-Type", "application/json"}] ++ Map.to_list(headers)

    Req.post(url, json: notification, headers: req_headers, receive_timeout: 5_000)

    :ok
  end

  defp jsonrpc_notify(%{ws_pid: _ws_pid} = state, method, params) do
    case Canopy.Transports.MCPWebsocket.notify(state, method, params) do
      :ok -> :ok
      {:error, reason} ->
        Logger.warning("[MCPServer] Notification send failed: #{inspect(reason)}")
        :ok
    end
  end

  # ── Stdio response handling ─────────────────────────────────────────

  defp wait_for_response(port, request_id, state, timeout) do
    receive do
      {^port, {:data, data}} ->
        new_buffer = state.buffer <> to_string(data)
        handle_port_data(new_buffer, port, request_id, timeout)

      {:EXIT, ^port, reason} ->
        {:error, {:port_exited, reason}}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp handle_port_data(buffer, port, request_id, timeout) do
    # Try to extract complete JSON-RPC messages (newline-delimited)
    case extract_json_lines(buffer) do
      {:ok, lines, remainder} ->
        case find_response_for_id(lines, request_id) do
          {:ok, result} ->
            {:ok, result, remainder}

          :not_found ->
            # Keep waiting for the right response
            wait_for_response(port, request_id, %{buffer: remainder}, timeout)
        end

      :incomplete ->
        wait_for_response(port, request_id, %{buffer: buffer}, timeout)
    end
  end

  defp extract_json_lines(buffer) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] when byte_size(line) > 0 ->
        case Jason.decode(String.trim(line)) do
          {:ok, decoded} ->
            case extract_json_lines(rest) do
              {:ok, more_lines, remainder} ->
                {:ok, [decoded | more_lines], remainder}

              :incomplete ->
                {:ok, [decoded], rest}
            end

          _ ->
            extract_json_lines(rest)
        end

      _ ->
        :incomplete
    end
  end

  defp find_response_for_id([], _request_id), do: :not_found

  defp find_response_for_id([%{"id" => id} = msg | _rest], request_id) when id == request_id do
    case msg do
      %{"result" => result} -> {:ok, result}
      %{"error" => error} -> {:error, {:jsonrpc_error, error}}
      _ -> {:ok, msg}
    end
  end

  defp find_response_for_id([_ | rest], request_id), do: find_response_for_id(rest, request_id)

  # ── HTTP response parsing ───────────────────────────────────────────

  defp parse_jsonrpc_response(body, expected_id) do
    case body do
      %{"result" => result, "id" => id} when id == expected_id ->
        {:ok, result}

      %{"error" => error, "id" => id} when id == expected_id ->
        {:error, {:jsonrpc_error, error}}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  # ── JSON-RPC message building ───────────────────────────────────────

  defp build_jsonrpc_request(id, method, params) do
    %{
      "jsonrpc" => @jsonrpc_version,
      "id" => id,
      "method" => method,
      "params" => params
    }
  end

  defp build_jsonrpc_notification(method, params) do
    %{
      "jsonrpc" => @jsonrpc_version,
      "method" => method,
      "params" => params
    }
  end

  # ── Cleanup ─────────────────────────────────────────────────────────

  defp cleanup_transport(:stdio, %{port: port}) do
    if is_port(port) do
      Port.close(port)
    end
  end

  defp cleanup_transport(:http, _state), do: :ok

  defp cleanup_transport(:websocket, state) do
    Canopy.Transports.MCPWebsocket.close(state)
  end

  defp cleanup_transport(_, _state), do: :ok

  defp send_port_data(port, data) do
    send(port, {self(), {:command, data}})
  end
end
