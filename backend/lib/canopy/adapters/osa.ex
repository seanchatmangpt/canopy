defmodule Canopy.Adapters.OSA do
  @moduledoc """
  OSA adapter — connects to a running OptimalSystemAgent instance via HTTP API.

  Streams SSE events back as adapter events. Supports provider configuration
  (Groq, Anthropic, OpenAI, etc.) and shared secret authentication.
  """
  @behaviour Canopy.Adapter

  require Logger

  @default_url "http://127.0.0.1:9089"
  @default_provider "groq"
  @default_model "llama-3.3-70b-versatile"

  @impl true
  def type, do: "osa"

  @impl true
  def name, do: "OSA Agent"

  @impl true
  def supports_session?, do: true

  @impl true
  def supports_concurrent?, do: true

  @impl true
  def capabilities, do: [:chat, :tools, :code_execution, :web_search, :memory, :delegation]

  # ── Public API ──────────────────────────────────────────────────────

  @impl true
  def start(config) do
    base_url = config["url"] || @default_url
    provider = config["provider"] || @default_provider
    model = config["model"] || @default_model
    user_id = config["user_id"] || "canopy-agent"

    headers = build_headers(config)

    body =
      %{}
      |> maybe_put("user_id", user_id)
      |> maybe_put("provider", provider)
      |> maybe_put("model", model)

    case Req.post("#{base_url}/api/v1/sessions", json: body, headers: headers) do
      {:ok, %{status: status, body: resp_body}} when status in 200..201 ->
        session_id = resp_body["id"] || get_in(resp_body, ["session", "id"])

        if session_id do
          Logger.info("[OSA Adapter] Session created: #{session_id} (#{provider}/#{model})")

          {:ok,
           %{
             session_id: session_id,
             base_url: base_url,
             provider: provider,
             model: model
           }}
        else
          {:error, {:osa_error, status, resp_body}}
        end

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:osa_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  @impl true
  def stop(%{base_url: base_url, session_id: session_id}) do
    headers = build_headers(%{})

    case Req.delete("#{base_url}/api/v1/sessions/#{session_id}", headers: headers) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def execute_heartbeat(params) do
    base_url = params["url"] || @default_url
    agent_context = params["context"] || "Perform your scheduled heartbeat check."
    provider = params["provider"] || @default_provider
    model = params["model"] || @default_model
    user_id = params["agent_id"] || "canopy-heartbeat"

    headers = build_headers(params)

    body =
      %{}
      |> maybe_put("user_id", user_id)
      |> maybe_put("message", agent_context)
      |> maybe_put("provider", provider)
      |> maybe_put("model", model)

    Stream.resource(
      fn ->
        case Req.post("#{base_url}/api/v1/sessions", json: body, headers: headers) do
          {:ok, %{status: s, body: resp_body}} when s in 200..201 ->
            session_id = resp_body["id"] || get_in(resp_body, ["session", "id"])

            if session_id do
              {:ok, task} = start_sse("#{base_url}/api/v1/sessions/#{session_id}/stream", headers)
              {task, session_id, base_url}
            else
              {:error, nil, nil}
            end

          _ ->
            {:error, nil, nil}
        end
      end,
      fn
        {:error, _, _} = state ->
          {:halt, state}

        {task, session_id, base_url} ->
          case receive_sse_event(task, 30_000) do
            {:ok, event} ->
              {[event], {task, session_id, base_url}}

            :done ->
              {:halt, {task, session_id, base_url}}

            {:error, _reason} ->
              {:halt, {task, session_id, base_url}}
          end
      end,
      fn
        {:error, _, _} ->
          :ok

        {_task, session_id, base_url} ->
          Req.delete("#{base_url}/api/v1/sessions/#{session_id}", headers: headers)
          :ok
      end
    )
  end

  @impl true
  def send_message(%{base_url: base_url, session_id: session_id}, message) do
    headers = build_headers(%{})

    Req.post("#{base_url}/api/v1/sessions/#{session_id}/message",
      json: %{message: message},
      headers: headers
    )

    Stream.resource(
      fn ->
        {:ok, task} = start_sse("#{base_url}/api/v1/sessions/#{session_id}/stream", headers)
        task
      end,
      fn task ->
        case receive_sse_event(task, 30_000) do
          {:ok, event} -> {[event], task}
          :done -> {:halt, task}
          {:error, _} -> {:halt, task}
        end
      end,
      fn _task -> :ok end
    )
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp build_headers(config) do
    base = [{"Content-Type", "application/json"}]

    case config["shared_secret"] || System.get_env("OSA_SHARED_SECRET") do
      nil -> base
      secret -> [{"X-Shared-Secret", secret} | base]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # ── SSE helpers ─────────────────────────────────────────────────────

  defp start_sse(url, headers) do
    task =
      Task.async(fn ->
        Req.get(url, headers: headers, into: :self, receive_timeout: 120_000)
      end)

    {:ok, task}
  end

  defp receive_sse_event(task, timeout) do
    receive do
      {ref, {:data, data}} when ref == task.ref ->
        case parse_sse(data) do
          %{"event_type" => "done"} -> :done
          event -> {:ok, event}
        end

      {ref, :done} when ref == task.ref ->
        :done
    after
      timeout -> {:error, :timeout}
    end
  end

  defp parse_sse(raw) do
    raw
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ": ", parts: 2) do
        ["event", value] ->
          Map.put(acc, "event_type", String.trim(value))

        ["data", value] ->
          case Jason.decode(String.trim(value)) do
            {:ok, data} -> Map.merge(acc, %{"data" => data})
            _ -> Map.put(acc, "data", %{"raw" => String.trim(value)})
          end

        _ ->
          acc
      end
    end)
  end
end
