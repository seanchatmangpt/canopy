defmodule Canopy.Yawl.Client do
  @moduledoc """
  GenServer HTTP client for the YAWL engine (Interface A).

  Wraps all calls to the YAWL engine REST API and provides a simple circuit
  breaker: after 3 consecutive failures the circuit opens and all calls return
  `{:error, :circuit_open}` immediately. The circuit resets automatically after
  30 seconds or on the first successful call.

  Configuration
  -------------
  Set `YAWL_ENGINE_URL` in the environment (default: `http://localhost:8080`).

  Public API
  ----------
  All functions are synchronous `GenServer.call/2` wrappers:

      Canopy.Yawl.Client.upload_spec(xml_string)   → {:ok, spec_id} | {:error, reason}
      Canopy.Yawl.Client.launch_case(spec_id)       → {:ok, case_id} | {:error, reason}
      Canopy.Yawl.Client.cancel_case(case_id)       → :ok | {:error, reason}
      Canopy.Yawl.Client.get_case_state(case_id)    → {:ok, state_xml} | {:error, reason}
      Canopy.Yawl.Client.health_check()             → {:ok, :up} | {:error, :down}
  """

  use GenServer
  require Logger

  @default_engine_url "http://localhost:8080"
  @failure_threshold 3
  @circuit_reset_ms 30_000
  @call_timeout 15_000

  # ── Child spec ───────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ── Public API ────────────────────────────────────────────────────────────────

  @doc "Upload a YAWL specification XML string. Returns `{:ok, spec_id}` on success."
  def upload_spec(xml_string) do
    GenServer.call(__MODULE__, {:upload_spec, xml_string}, @call_timeout)
  end

  @doc "Launch a case for the given spec_id. Returns `{:ok, case_id}` on success."
  def launch_case(spec_id) do
    GenServer.call(__MODULE__, {:launch_case, spec_id}, @call_timeout)
  end

  @doc "Cancel a running case by case_id. Returns `:ok` on success."
  def cancel_case(case_id) do
    GenServer.call(__MODULE__, {:cancel_case, case_id}, @call_timeout)
  end

  @doc "Get the current state XML for a running case."
  def get_case_state(case_id) do
    GenServer.call(__MODULE__, {:get_case_state, case_id}, @call_timeout)
  end

  @doc "Check whether the YAWL engine is reachable."
  def health_check do
    GenServer.call(__MODULE__, :health_check, @call_timeout)
  end

  # ── Server callbacks ──────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    engine_url = System.get_env("YAWL_ENGINE_URL", @default_engine_url)

    state = %{
      engine_url: engine_url,
      circuit_state: :closed,
      failure_count: 0,
      circuit_opened_at: nil
    }

    Logger.info("[Yawl.Client] Started — engine_url=#{engine_url}")
    {:ok, state}
  end

  @impl true
  def handle_call(_request, _from, %{circuit_state: :open} = state) do
    # Check whether the reset window has elapsed
    state = maybe_reset_circuit(state)

    case state.circuit_state do
      :open ->
        {:reply, {:error, :circuit_open}, state}

      :closed ->
        # Circuit just reset — retry is the caller's responsibility; return open
        # error this turn so the caller can re-invoke cleanly.
        {:reply, {:error, :circuit_open}, state}
    end
  end

  def handle_call({:upload_spec, xml_string}, _from, state) do
    result =
      post_form(state.engine_url, "/ia", %{
        "action" => "upload",
        "specXML" => xml_string
      })
      |> parse_response()

    {reply, state} = handle_result(result, state)
    {:reply, reply, state}
  end

  def handle_call({:launch_case, spec_id}, _from, state) do
    result =
      post_form(state.engine_url, "/ia", %{
        "action" => "launchCase",
        "specID" => spec_id
      })
      |> parse_response()

    {reply, state} = handle_result(result, state)
    {:reply, reply, state}
  end

  def handle_call({:cancel_case, case_id}, _from, state) do
    result =
      post_form(state.engine_url, "/ia", %{
        "action" => "cancelCase",
        "caseID" => case_id
      })
      |> parse_response()

    {reply, state} =
      case handle_result(result, state) do
        {{:ok, _value}, new_state} -> {:ok, new_state}
        other -> other
      end

    {:reply, reply, state}
  end

  def handle_call({:get_case_state, case_id}, _from, state) do
    result =
      get_request(state.engine_url, "/ia", %{
        "action" => "getCaseState",
        "caseID" => case_id
      })
      |> parse_response()

    {reply, state} = handle_result(result, state)
    {:reply, reply, state}
  end

  def handle_call(:health_check, _from, state) do
    result =
      case get_request(state.engine_url, "/health", %{}) do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok, :up}

        {:ok, _} ->
          {:error, :down}

        {:error, _reason} ->
          {:error, :down}
      end

    state =
      case result do
        {:ok, :up} -> record_success(state)
        {:error, _} -> record_failure(state)
      end

    {:reply, result, state}
  end

  # ── HTTP helpers ──────────────────────────────────────────────────────────────

  defp post_form(base_url, path, params) do
    url = base_url <> path

    case Req.post(url, form: params, connect_options: [timeout: 5_000], receive_timeout: 10_000) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_request(base_url, path, params) do
    url = base_url <> path

    case Req.get(url, params: params, connect_options: [timeout: 5_000], receive_timeout: 10_000) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Response parsing ──────────────────────────────────────────────────────────

  # YAWL Interface A returns plain XML bodies of the form:
  #   <success>value</success>
  #   <failure>reason</failure>
  # We use String.contains? / simple capture rather than pulling in a full XML
  # parser, since the YAWL response bodies are short and well-structured.

  defp parse_response({:error, reason}) do
    {:error, reason}
  end

  defp parse_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    body_str = to_string(body)

    cond do
      String.contains?(body_str, "<failure>") ->
        reason = extract_tag(body_str, "failure")
        {:error, reason}

      String.contains?(body_str, "<success>") ->
        value = extract_tag(body_str, "success")
        {:ok, value}

      # Health endpoint or empty-body success
      body_str == "" or body_str == "true" ->
        {:ok, body_str}

      true ->
        # Return the raw body when no recognised envelope
        {:ok, body_str}
    end
  end

  defp parse_response({:ok, %{status: status}}) do
    {:error, "HTTP #{status}"}
  end

  # Extract text between <tag>…</tag> (first occurrence, non-greedy).
  defp extract_tag(body, tag) do
    pattern = ~r/<#{tag}>(.*?)<\/#{tag}>/s

    case Regex.run(pattern, body, capture: :all_but_first) do
      [value] -> String.trim(value)
      nil -> body
    end
  end

  # ── Circuit breaker helpers ───────────────────────────────────────────────────

  defp handle_result({:ok, value}, state) do
    {{:ok, value}, record_success(state)}
  end

  defp handle_result({:error, reason}, state) do
    {{:error, reason}, record_failure(state)}
  end

  defp record_success(state) do
    %{state | circuit_state: :closed, failure_count: 0, circuit_opened_at: nil}
  end

  defp record_failure(%{failure_count: count} = state) do
    new_count = count + 1

    if new_count >= @failure_threshold do
      Logger.warning("[Yawl.Client] Circuit opened after #{new_count} consecutive failures")

      %{
        state
        | circuit_state: :open,
          failure_count: new_count,
          circuit_opened_at: System.monotonic_time(:millisecond)
      }
    else
      %{state | failure_count: new_count}
    end
  end

  defp maybe_reset_circuit(%{circuit_opened_at: opened_at} = state) when not is_nil(opened_at) do
    elapsed = System.monotonic_time(:millisecond) - opened_at

    if elapsed >= @circuit_reset_ms do
      Logger.info("[Yawl.Client] Circuit reset after #{elapsed}ms — returning to :closed")
      %{state | circuit_state: :closed, failure_count: 0, circuit_opened_at: nil}
    else
      state
    end
  end

  defp maybe_reset_circuit(state), do: state
end
