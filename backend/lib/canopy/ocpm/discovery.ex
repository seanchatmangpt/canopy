defmodule Canopy.OCPM.Discovery do
  @moduledoc """
  Process discovery from event logs using OCPM algorithms.

  This module implements the core process mining algorithms for discovering
  process models from event logs, detecting bottlenecks, and performing
  conformance checking.

  ## Algorithms

  ### Alpha Miner (discover_process_model/1)
  Discovers a process model by analyzing direct succession relations between
  activities in the event log. The algorithm:
  1. Extracts all unique activities as nodes
  2. Identifies direct succession relations (A → B in same case)
  3. Builds edges from succession relations

  ### Heuristic Miner (detect_bottlenecks/2)
  Identifies bottlenecks by analyzing activity frequency and duration patterns:
  1. Calculates frequency of each activity
  2. Measures duration between activities
  3. Flags activities above thresholds as bottlenecks

  ### Conformance Checking (find_deviations/2)
  Detects deviations by comparing event logs against the process model:
  1. Traces each case through the model
  2. Flags transitions not defined in the model
  3. Returns deviation list with context

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

  @type bottleneck :: %{
          activity: String.t(),
          type: :frequency | :duration,
          value: number(),
          threshold: number(),
          severity: :low | :medium | :high
        }

  @type deviation :: %{
          case_id: String.t(),
          from: String.t() | nil,
          to: String.t(),
          reason: String.t(),
          timestamp: DateTime.t()
        }

  # Default thresholds for bottleneck detection
  # Activities with 2x average frequency
  @frequency_threshold 2.0
  # 24 hours in milliseconds
  @duration_threshold_ms 24 * 60 * 60 * 1000

  @doc """
  Discovers a process model from an event log using the Alpha Miner algorithm.

  The Alpha Miner analyzes direct succession relations to build a process model:
  1. Extracts all unique activities as nodes
  2. Finds direct succession (A → B in same case)
  3. Builds edges from succession relations

  ## Parameters

  - `event_log`: List of event maps with case_id, activity, timestamp

  ## Returns

  Process model map with nodes, edges, and metadata

  ## Examples

      iex> events = [
      ...>   %{case_id: "1", activity: "create", timestamp: ~U[2026-03-12 00:00:00Z]},
      ...>   %{case_id: "1", activity: "approve", timestamp: ~U[2026-03-13 00:00:00Z]}
      ...> ]
      iex> Discovery.discover_process_model(events)
      %{
        nodes: ["create", "approve"],
        edges: %{"transitions" => [["create", "approve"]]},
        metadata: %{...}
      }
  """
  @spec discover_process_model(event_log()) :: process_model()
  def discover_process_model([]) do
    Logger.warning("Alpha miner: empty event log provided")

    %{
      nodes: [],
      edges: %{"transitions" => []},
      metadata: %{
        algorithm: "alpha_miner",
        discovered_at: DateTime.utc_now(),
        event_count: 0,
        case_count: 0
      }
    }
  end

  def discover_process_model(event_log) when is_list(event_log) do
    Logger.info("Alpha miner: discovering process model from #{length(event_log)} events")

    # Step 1: Extract all unique activities as nodes
    nodes =
      event_log
      |> Enum.map(& &1.activity)
      |> Enum.uniq()
      |> Enum.sort()

    # Step 2: Find direct succession relations
    transitions = extract_succession_relations(event_log)

    # Step 3: Build process model
    model = %{
      nodes: nodes,
      edges: %{"transitions" => transitions},
      metadata: %{
        algorithm: "alpha_miner",
        discovered_at: DateTime.utc_now(),
        event_count: length(event_log),
        case_count: count_unique_cases(event_log)
      }
    }

    Logger.info(
      "Alpha miner: discovered model with #{length(nodes)} nodes and #{length(transitions)} transitions"
    )

    model
  end

  @doc """
  Detects bottlenecks in a process model using heuristic mining.

  Analyzes activity frequency and duration to identify potential bottlenecks:
  1. Calculates frequency of each activity
  2. Measures duration between activities
  3. Identifies activities above thresholds

  ## Parameters

  - `process_model`: Process model from discover_process_model/1
  - `event_log`: List of event maps

  ## Returns

  List of bottleneck maps with activity, type, value, threshold, and severity

  ## Examples

      iex> model = %{nodes: ["review"], edges: %{}, metadata: %{}}
      iex> events = [%{case_id: "1", activity: "review", timestamp: ~U[2026-03-12 00:00:00Z]}]
      iex> Discovery.detect_bottlenecks(model, events)
      []
  """
  @spec detect_bottlenecks(process_model(), event_log()) :: [bottleneck()]
  def detect_bottlenecks(%{nodes: []}, _event_log) do
    Logger.warning("Heuristic miner: empty process model provided")
    []
  end

  def detect_bottlenecks(process_model, event_log) when is_list(event_log) do
    Logger.info("Heuristic miner: analyzing #{length(event_log)} events for bottlenecks")

    # Detect frequency bottlenecks
    frequency_bottlenecks = detect_frequency_bottlenecks(event_log)

    # Detect duration bottlenecks
    duration_bottlenecks = detect_duration_bottlenecks(event_log)

    # Combine and deduplicate
    all_bottlenecks =
      (frequency_bottlenecks ++ duration_bottlenecks)
      |> Enum.uniq_by(fn b -> {b.activity, b.type} end)
      |> Enum.sort_by(fn b -> b.severity end, :desc)

    Logger.info("Heuristic miner: found #{length(all_bottlenecks)} bottlenecks")
    all_bottlenecks
  end

  @doc """
  Finds deviations between an event log and a process model.

  Performs conformance checking by tracing each case through the model:
  1. For each case, checks if activities follow valid edges
  2. Flags any transitions not in the model
  3. Returns deviation list with context

  ## Parameters

  - `process_model`: Process model from discover_process_model/1
  - `event_log`: List of event maps

  ## Returns

  List of deviation maps with case_id, from, to, reason, and timestamp

  ## Examples

      iex> model = %{nodes: ["create", "approve"], edges: %{"transitions" => [["create", "approve"]]}}
      iex> events = [
      ...>   %{case_id: "1", activity: "create", timestamp: ~U[2026-03-12 00:00:00Z]},
      ...>   %{case_id: "1", activity: "reject", timestamp: ~U[2026-03-13 00:00:00Z]}
      ...> ]
      iex> Discovery.find_deviations(model, events)
      [%{case_id: "1", from: "create", to: "reject", reason: "transition not in model", ...}]
  """
  @spec find_deviations(process_model(), event_log()) :: [deviation()]
  def find_deviations(%{edges: %{"transitions" => []}}, _event_log) do
    Logger.warning("Conformance checking: empty process model provided")
    []
  end

  def find_deviations(process_model, event_log) when is_list(event_log) do
    Logger.info("Conformance checking: analyzing #{length(event_log)} events")

    # Build valid transition set for fast lookup
    valid_transitions = build_transition_set(process_model)

    # Group events by case
    events_by_case = Enum.group_by(event_log, & &1.case_id)

    # Check each case for deviations
    deviations =
      events_by_case
      |> Enum.flat_map(fn {case_id, case_events} ->
        check_case_conformance(case_id, case_events, valid_transitions)
      end)

    Logger.info("Conformance checking: found #{length(deviations)} deviations")
    deviations
  end

  # Private helper functions

  # Extract direct succession relations from event log
  defp extract_succession_relations(event_log) do
    event_log
    |> Enum.group_by(& &1.case_id)
    |> Enum.flat_map(fn {_case_id, case_events} ->
      case_events
      |> Enum.sort_by(& &1.timestamp)
      |> extract_case_transitions()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Extract transitions from a single case's event sequence
  defp extract_case_transitions([]), do: []
  defp extract_case_transitions([_single]), do: []

  defp extract_case_transitions(events) do
    events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] -> [from.activity, to.activity] end)
  end

  # Count unique cases in event log
  defp count_unique_cases(event_log) do
    event_log
    |> Enum.map(& &1.case_id)
    |> Enum.uniq()
    |> length()
  end

  # Detect frequency-based bottlenecks
  defp detect_frequency_bottlenecks(event_log) do
    # Count frequency of each activity
    activity_counts = Enum.frequencies_by(event_log, & &1.activity)

    if map_size(activity_counts) == 0 do
      []
    else
      # Calculate average frequency
      avg_frequency =
        activity_counts
        |> Map.values()
        |> Enum.sum()
        |> Kernel./(map_size(activity_counts))

      # Find activities above threshold
      activity_counts
      |> Enum.filter(fn {_activity, count} ->
        count > avg_frequency * @frequency_threshold
      end)
      |> Enum.map(fn {activity, count} ->
        severity = calculate_severity(count, avg_frequency * @frequency_threshold)

        %{
          activity: activity,
          type: :frequency,
          value: count,
          threshold: avg_frequency * @frequency_threshold,
          severity: severity
        }
      end)
    end
  end

  # Detect duration-based bottlenecks
  defp detect_duration_bottlenecks(event_log) do
    event_log
    |> Enum.group_by(& &1.case_id)
    |> Enum.flat_map(fn {_case_id, case_events} ->
      calculate_case_durations(case_events)
    end)
    |> Enum.filter(fn %{duration_ms: duration} ->
      duration > @duration_threshold_ms
    end)
    |> Enum.map(fn %{activity: activity, duration_ms: duration} ->
      severity = calculate_severity(duration, @duration_threshold_ms)

      %{
        activity: activity,
        type: :duration,
        value: duration,
        threshold: @duration_threshold_ms,
        severity: severity
      }
    end)
  end

  # Calculate durations between activities in a case
  defp calculate_case_durations([]), do: []
  defp calculate_case_durations([_single]), do: []

  defp calculate_case_durations(events) do
    events
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      duration_ms = DateTime.diff(to.timestamp, from.timestamp, :millisecond)

      %{
        activity: from.activity,
        duration_ms: duration_ms
      }
    end)
  end

  # Build set of valid transitions from process model
  defp build_transition_set(%{edges: %{"transitions" => transitions}}) do
    transitions
    |> Enum.map(fn [from, to] -> {from, to} end)
    |> MapSet.new()
  end

  # Check a single case for conformance violations
  defp check_case_conformance(case_id, case_events, valid_transitions) do
    case_events
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [from, to] ->
      if {from.activity, to.activity} in valid_transitions do
        []
      else
        [
          %{
            case_id: case_id,
            from: from.activity,
            to: to.activity,
            reason: "transition not in model",
            timestamp: to.timestamp
          }
        ]
      end
    end)
  end

  # Calculate severity based on how much value exceeds threshold
  defp calculate_severity(value, threshold) do
    ratio = value / threshold

    cond do
      ratio >= 3.0 -> :high
      ratio >= 2.0 -> :medium
      true -> :low
    end
  end
end
