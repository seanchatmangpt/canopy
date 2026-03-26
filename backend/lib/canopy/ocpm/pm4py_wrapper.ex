defmodule Canopy.OCPM.Pm4pyWrapper do
  @moduledoc """
  Wrapper around pm4py Python library for process mining.

  This module provides an Elixir interface to pm4py by calling a Python
  script that performs OCPM operations. This leverages the mature,
  well-tested pm4py library instead of maintaining our own implementations.

  ## Requirements

  - Python 3.8+
  - pm4py library: `pip install pm4py`

  ## Architecture

  ```
  Elixir ──System.cmd──▶ Python ──pm4py──▶ Results
         (JSON)          (JSON)
  ```

  ## Usage

      events = [%{case_id: "1", activity: "approve", timestamp: ...}]
      {:ok, model} = Pm4pyWrapper.discover_process_model(events)
  """

  require Logger

  @pm4py_script Path.join(:code.priv_dir(:canopy), "pm4py_wrapper.py")

  @type event_log :: [
          %{
            case_id: String.t(),
            activity: String.t(),
            timestamp: DateTime.t(),
            resource: String.t(),
            attributes: map()
          }
        ]

  @type process_model :: %{
          nodes: [String.t()],
          edges: %{String.t() => [[String.t()]]},
          metadata: map()
        }

  @doc """
  Discover a process model using pm4py's Alpha miner implementation.

  ## Parameters

  - `event_log`: List of event maps with case_id, activity, timestamp, resource, attributes

  ## Returns

  - `{:ok, process_model}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> events = [
      ...>   %{case_id: "1", activity: "create", timestamp: ~U[2026-03-12 00:00:00Z], resource: "agent-1", attributes: %{}},
      ...>   %{case_id: "1", activity: "approve", timestamp: ~U[2026-03-13 00:00:00Z], resource: "agent-2", attributes: %{}}
      ...> ]
      iex> {:ok, model} = Pm4pyWrapper.discover_process_model(events)
      iex> model.nodes
      ["create", "approve"]
  """
  @spec discover_process_model(event_log()) :: {:ok, process_model()} | {:error, term()}
  def discover_process_model([]) do
    Logger.warning("[Pm4pyWrapper] Empty event log provided")
    {:ok, empty_process_model()}
  end

  def discover_process_model(event_log) when is_list(event_log) do
    Logger.info("[Pm4pyWrapper] Discovering process model from #{length(event_log)} events")

    input = %{
      "events" => format_events_for_python(event_log)
    }

    case run_pm4py("discover", input) do
      {:ok, result} when is_map(result) ->
        model = %{
          nodes: Map.get(result, "nodes", []),
          edges: Map.get(result, "edges", %{}),
          metadata: Map.get(result, "metadata", %{})
        }

        Logger.info("[Pm4pyWrapper] Discovered model with #{length(model.nodes)} nodes")

        {:ok, model}

      {:error, reason} ->
        Logger.error("[Pm4pyWrapper] Discovery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Detect bottlenecks using pm4py's heuristic miner implementation.

  ## Parameters

  - `event_log`: List of event maps

  ## Returns

  - `{:ok, bottlenecks}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> events = [%{case_id: "1", activity: "review", ...}]
      iex> {:ok, bottlenecks} = Pm4pyWrapper.detect_bottlenecks(events)
  """
  @spec detect_bottlenecks(event_log()) :: {:ok, list(map())} | {:error, term()}
  def detect_bottlenecks([]) do
    Logger.warning("[Pm4pyWrapper] Empty event log for bottleneck detection")
    {:ok, []}
  end

  def detect_bottlenecks(event_log) when is_list(event_log) do
    Logger.info("[Pm4pyWrapper] Analyzing #{length(event_log)} events for bottlenecks")

    input = %{
      "events" => format_events_for_python(event_log)
    }

    case run_pm4py("bottlenecks", input) do
      {:ok, result} when is_map(result) ->
        bottlenecks = Map.get(result, "bottlenecks", [])
        _metadata = Map.get(result, "metadata", %{})

        Logger.info("[Pm4pyWrapper] Found #{length(bottlenecks)} bottlenecks")

        {:ok, bottlenecks}

      {:error, reason} ->
        Logger.error("[Pm4pyWrapper] Bottleneck detection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Check conformance using pm4py's alignment algorithms.

  ## Parameters

  - `event_log`: List of event maps
  - `process_model`: Process model from discover_process_model/1

  ## Returns

  - `{:ok, deviations}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> {:ok, model} = Pm4pyWrapper.discover_process_model(events)
      iex> {:ok, deviations} = Pm4pyWrapper.find_deviations(events, model)
  """
  @spec find_deviations(event_log(), process_model()) :: {:ok, list(map())} | {:error, term()}
  def find_deviations([], _process_model) do
    Logger.warning("[Pm4pyWrapper] Empty event log for conformance checking")
    {:ok, []}
  end

  def find_deviations(event_log, process_model)
      when is_list(event_log) and is_map(process_model) do
    Logger.info("[Pm4pyWrapper] Checking conformance of #{length(event_log)} events")

    input = %{
      "events" => format_events_for_python(event_log),
      "process_model" => process_model
    }

    case run_pm4py("conformance", input) do
      {:ok, result} when is_map(result) ->
        deviations = Map.get(result, "deviations", [])
        _metadata = Map.get(result, "metadata", %{})

        Logger.info("[Pm4pyWrapper] Found #{length(deviations)} deviations")

        {:ok, deviations}

      {:error, reason} ->
        Logger.error("[Pm4pyWrapper] Conformance checking failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp run_pm4py(command, input_map) do
    json_input = Jason.encode!(input_map)

    case System.cmd("python3", [@pm4py_script, command, json_input],
           stderr_to_stdout: true,
           cd: Path.dirname(@pm4py_script)
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, result} when is_map(result) ->
            if Map.has_key?(result, "error") do
              {:error, result["error"]}
            else
              {:ok, result}
            end

          {:ok, result} ->
            {:ok, %{"result" => result}}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {output, exit_code} when exit_code > 0 ->
        Logger.error("[Pm4pyWrapper] Python script failed (exit #{exit_code}): #{output}")
        {:error, {:python_error, exit_code, output}}
    end
  rescue
    _e in [File.Error] ->
      Logger.error("[Pm4pyWrapper] Python script not found: #{@pm4py_script}")
      {:error, :script_not_found}

    e ->
      Logger.error("[Pm4pyWrapper] Unexpected error: #{Exception.message(e)}")
      {:error, {:unexpected_error, Exception.message(e)}}
  end

  defp format_events_for_python(event_log) do
    Enum.map(event_log, fn event ->
      %{
        "case_id" => event[:case_id] || event.case_id,
        "activity" => event[:activity] || event.activity,
        "timestamp" => format_timestamp(event[:timestamp] || event.timestamp),
        "resource" => event[:resource] || event.resource || "unknown",
        "attributes" => event[:attributes] || event.attributes || %{}
      }
    end)
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_timestamp(str) when is_binary(str), do: str
  defp format_timestamp(_), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp empty_process_model do
    %{
      nodes: [],
      edges: %{"transitions" => []},
      metadata: %{
        algorithm: "alpha_miner_pm4py",
        discovered_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        event_count: 0,
        case_count: 0
      }
    }
  end
end
