defmodule Canopy.OCPM.Discovery do
  @moduledoc """
  Process discovery from event logs using OCPM algorithms via pm4py.

  This module provides an Elixir interface to OCPM (Object-Centric Process Mining)
  capabilities by wrapping the pm4py Python library. This leverages mature,
  well-tested process mining algorithms.

  ## Algorithms (via pm4py)

  ### Alpha Miner (discover_process_model/1)
  Discovers a process model by analyzing direct succession relations between
  activities in the event log. Implemented using pm4py's alpha miner.

  ### Heuristic Miner (detect_bottlenecks/2)
  Identifies bottlenecks by analyzing activity frequency and duration patterns.
  Implemented using pm4py's heuristic miner.

  ### Conformance Checking (find_deviations/2)
  Detects deviations by comparing event logs against the process model.
  Implemented using pm4py's alignment algorithms.

  ## Requirements

  - Python 3.8+
  - pm4py library: `pip install pm4py`

  ## Input Format

  Event logs should be a list of maps with:
  - `case_id` - String: The case identifier
  - `activity` - String: The activity performed
  - `timestamp` - DateTime: When the event occurred
  - `resource` - String: Who/what performed the activity
  - `attributes` - Map: Additional event attributes

  ## Output Format

  Process models are returned as maps with:
  - `nodes` - List of unique activity names
  - `edges` - Map of transitions: `%{"transitions" => [[from, to], ...]}`
  - `metadata` - Discovery metadata (algorithm, timestamp, event_count)
  """

  require Logger
  alias Canopy.OCPM.Pm4pyWrapper

  @doc """
  Discovers a process model from an event log using pm4py's Alpha miner.

  Delegates to Pm4pyWrapper which calls Python pm4py library.

  ## Parameters

  - `event_log`: List of event maps with case_id, activity, timestamp

  ## Returns

  - `{:ok, process_model}` with nodes, edges, metadata
  - `{:error, reason}` if discovery fails

  ## Examples

      iex> events = [
      ...>   %{case_id: "1", activity: "create", timestamp: ~U[2026-03-12 00:00:00Z]},
      ...>   %{case_id: "1", activity: "approve", timestamp: ~U[2026-03-13 00:00:00Z]}
      ...> ]
      iex> {:ok, model} = Discovery.discover_process_model(events)
      iex> model.nodes
      ["create", "approve"]
  """
  def discover_process_model(event_log) when is_list(event_log) do
    Logger.info(
      "[Discovery] Discovering process model from #{length(event_log)} events via pm4py"
    )

    Pm4pyWrapper.discover_process_model(event_log)
  end

  @doc """
  Detects bottlenecks using pm4py's heuristic miner.

  Delegates to Pm4pyWrapper which calls Python pm4py library.

  ## Parameters

  - `process_model`: Process model (unused by pm4py, re-analyzes log)
  - `event_log`: List of event maps

  ## Returns

  - `{:ok, bottlenecks}` - List of bottleneck maps
  - `{:error, reason}` if detection fails

  ## Examples

      iex> {:ok, model} = Discovery.discover_process_model(events)
      iex> {:ok, bottlenecks} = Discovery.detect_bottlenecks(model, events)
  """
  def detect_bottlenecks(_process_model, event_log) when is_list(event_log) do
    Logger.info("[Discovery] Analyzing #{length(event_log)} events for bottlenecks via pm4py")
    Pm4pyWrapper.detect_bottlenecks(event_log)
  end

  @doc """
  Finds deviations between event log and process model using pm4py.

  Delegates to Pm4pyWrapper which calls Python pm4py library.

  ## Parameters

  - `process_model`: Process model from discover_process_model/1
  - `event_log`: List of event maps

  ## Returns

  - `{:ok, deviations}` - List of deviation maps
  - `{:error, reason}` if checking fails

  ## Examples

      iex> {:ok, model} = Discovery.discover_process_model(events)
      iex> {:ok, deviations} = Discovery.find_deviations(model, events)
  """
  def find_deviations(process_model, event_log)
      when is_map(process_model) and is_list(event_log) do
    Logger.info("[Discovery] Checking conformance via pm4py")
    Pm4pyWrapper.find_deviations(event_log, process_model)
  end
end
