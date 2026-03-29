defmodule Canopy.Bridges.YawlValidator do
  @moduledoc """
  Validates workspace pipeline topologies against YAWL Workflow Control Patterns (WCP).

  Takes a pipeline definition (list of steps with dependencies) and:

  1. Classifies the topology against WCP-1 through WCP-5
  2. Validates WvdA soundness (reachability, deadlock freedom, bounded parallelism)
  3. Optionally calls OSA's YAWL routes for deeper conformance checking

  ## Pipeline Format

      [
        %{id: :start, deps: []},
        %{id: :a, deps: [:start]},
        %{id: :b, deps: [:start]},
        %{id: :end, deps: [:a, :b]}
      ]

  ## WCP Pattern Classification

  - WCP-1 (Sequence): linear chain, each step has exactly one predecessor
  - WCP-2 (Parallel Split) + WCP-3 (Synchronization): fork-join topology
  - WCP-4 (Exclusive Choice) + WCP-5 (Simple Merge): choice topology
    (identified by steps with `choice: true` attribute)
  """

  require Logger

  @default_max_parallel 10
  @osa_conformance_url "http://localhost:8089/api/yawl/check-conformance"
  @osa_timeout_ms 3_000

  @type step :: %{
          required(:id) => atom(),
          required(:deps) => [atom()],
          optional(:choice) => boolean()
        }

  @type classification :: :wcp_1 | :wcp_2_3 | :wcp_4_5 | :mixed
  @type validation_result ::
          {:ok, %{pattern: classification(), sound: boolean()}}
          | {:error, %{violations: [String.t()]}}

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Validate a pipeline definition against WCP patterns and WvdA soundness.

  Options:
  - `:max_parallel` — maximum concurrent tasks allowed (default: 10)
  - `:check_osa` — whether to call OSA for deeper conformance (default: false)

  Returns `{:ok, %{pattern: pattern, sound: true}}` or
  `{:error, %{violations: [...]}}`.
  """
  @spec validate(list(step()), keyword()) :: validation_result()
  def validate(pipeline, opts \\ []) do
    max_parallel = Keyword.get(opts, :max_parallel, @default_max_parallel)
    check_osa = Keyword.get(opts, :check_osa, false)

    with :ok <- validate_structure(pipeline),
         {:ok, pattern} <- classify(pipeline),
         {:ok, _} <- check_soundness(pipeline, max_parallel) do
      result = %{pattern: pattern, sound: true}

      if check_osa do
        case check_osa_conformance(pipeline) do
          {:ok, osa_result} -> {:ok, Map.put(result, :osa_conformance, osa_result)}
          {:error, _reason} -> {:ok, result}
        end
      else
        {:ok, result}
      end
    end
  end

  @doc """
  Classify a pipeline topology into a WCP pattern.

  Returns `{:ok, pattern}` where pattern is one of:
  - `:wcp_1` — Sequence
  - `:wcp_2_3` — Parallel Split + Synchronization
  - `:wcp_4_5` — Exclusive Choice + Simple Merge
  - `:mixed` — Combination of patterns
  """
  @spec classify(list(step())) :: {:ok, classification()} | {:error, %{violations: [String.t()]}}
  def classify(pipeline) do
    has_fork = has_fork?(pipeline)
    has_join = has_join?(pipeline)
    has_choice = has_choice?(pipeline)

    pattern =
      cond do
        has_choice -> :wcp_4_5
        has_fork and has_join -> :wcp_2_3
        has_fork and not has_join -> :wcp_2_3
        not has_fork and not has_join and not has_choice -> :wcp_1
        true -> :mixed
      end

    {:ok, pattern}
  end

  @doc """
  Check WvdA soundness properties: reachability, deadlock freedom, boundedness.

  Returns `{:ok, :sound}` or `{:error, %{violations: [...]}}`.
  """
  @spec check_soundness(list(step()), non_neg_integer()) ::
          {:ok, :sound} | {:error, %{violations: [String.t()]}}
  def check_soundness(pipeline, max_parallel \\ @default_max_parallel) do
    violations =
      []
      |> check_reachability(pipeline)
      |> check_deadlock_freedom(pipeline)
      |> check_bounded_parallelism(pipeline, max_parallel)

    case violations do
      [] -> {:ok, :sound}
      _ -> {:error, %{violations: violations}}
    end
  end

  # ── Structure Validation ────────────────────────────────────────────

  defp validate_structure([]) do
    {:error, %{violations: ["pipeline is empty"]}}
  end

  defp validate_structure(pipeline) do
    ids = Enum.map(pipeline, & &1.id)
    all_deps = pipeline |> Enum.flat_map(& &1.deps) |> Enum.uniq()

    undefined = Enum.reject(all_deps, &(&1 in ids))

    duplicate_ids =
      ids
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> id end)

    violations =
      []
      |> then(fn acc ->
        if duplicate_ids != [] do
          ["duplicate step ids: #{inspect(duplicate_ids)}" | acc]
        else
          acc
        end
      end)
      |> then(fn acc ->
        if undefined != [] do
          ["undefined dependencies: #{inspect(undefined)}" | acc]
        else
          acc
        end
      end)

    case violations do
      [] -> :ok
      _ -> {:error, %{violations: violations}}
    end
  end

  # ── Pattern Detection ───────────────────────────────────────────────

  # A fork exists when a single step is depended on by 2+ successors
  defp has_fork?(pipeline) do
    successor_counts = build_successor_counts(pipeline)
    Enum.any?(successor_counts, fn {_id, count} -> count >= 2 end)
  end

  # A join exists when a step has 2+ dependencies
  defp has_join?(pipeline) do
    Enum.any?(pipeline, fn step -> length(step.deps) >= 2 end)
  end

  # A choice exists when any step has the `choice: true` attribute
  defp has_choice?(pipeline) do
    Enum.any?(pipeline, fn step -> Map.get(step, :choice, false) end)
  end

  defp build_successor_counts(pipeline) do
    pipeline
    |> Enum.flat_map(fn step -> Enum.map(step.deps, fn dep -> dep end) end)
    |> Enum.frequencies()
  end

  # ── Soundness Checks ────────────────────────────────────────────────

  # Check that all steps are reachable from start nodes (nodes with no deps)
  defp check_reachability(violations, pipeline) do
    start_nodes =
      pipeline
      |> Enum.filter(fn step -> step.deps == [] end)
      |> Enum.map(& &1.id)

    if start_nodes == [] do
      ["no start nodes found (all steps have dependencies — circular graph)" | violations]
    else
      reachable = bfs_reachable(start_nodes, pipeline)
      all_ids = MapSet.new(Enum.map(pipeline, & &1.id))
      unreachable = MapSet.difference(all_ids, reachable)

      if MapSet.size(unreachable) > 0 do
        dead = unreachable |> MapSet.to_list() |> Enum.sort()
        ["dead activities (unreachable from start): #{inspect(dead)}" | violations]
      else
        violations
      end
    end
  end

  # Check that all paths lead to completion (no dangling steps without successors
  # that aren't terminal nodes, and no cycles)
  defp check_deadlock_freedom(violations, pipeline) do
    # Build adjacency map: step_id -> list of successor step_ids
    successors = build_successors_map(pipeline)
    all_ids = Enum.map(pipeline, & &1.id)

    # Terminal nodes: steps that have no successors
    terminal_nodes =
      all_ids
      |> Enum.filter(fn id -> Map.get(successors, id, []) == [] end)

    # Check for cycles using DFS
    case detect_cycle(pipeline) do
      nil ->
        # No cycle. Check that every node can reach at least one terminal node.
        non_completing =
          all_ids
          |> Enum.reject(fn id -> id in terminal_nodes end)
          |> Enum.reject(fn id ->
            reachable = bfs_reachable([id], pipeline, :forward)
            Enum.any?(terminal_nodes, &(&1 in MapSet.to_list(reachable)))
          end)

        if non_completing != [] do
          ["potential deadlock: steps #{inspect(Enum.sort(non_completing))} cannot reach any terminal node" | violations]
        else
          violations
        end

      cycle ->
        ["cycle detected: #{inspect(cycle)}" | violations]
    end
  end

  # Check that maximum concurrent (parallel) tasks does not exceed limit
  defp check_bounded_parallelism(violations, pipeline, max_parallel) do
    max_width = compute_max_width(pipeline)

    if max_width > max_parallel do
      [
        "parallelism exceeds bound: #{max_width} concurrent tasks > max #{max_parallel}"
        | violations
      ]
    else
      violations
    end
  end

  # ── Graph Utilities ─────────────────────────────────────────────────

  # BFS from start_nodes following forward edges (deps -> successors)
  defp bfs_reachable(start_nodes, pipeline, direction \\ :forward) do
    adjacency =
      case direction do
        :forward -> build_successors_map(pipeline)
        :backward -> build_predecessors_map(pipeline)
      end

    bfs_loop(start_nodes, MapSet.new(start_nodes), adjacency)
  end

  defp bfs_loop([], visited, _adjacency), do: visited

  defp bfs_loop(queue, visited, adjacency) do
    next =
      queue
      |> Enum.flat_map(fn node -> Map.get(adjacency, node, []) end)
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.uniq()

    bfs_loop(next, MapSet.union(visited, MapSet.new(next)), adjacency)
  end

  # Build map: step_id -> [successor_ids]
  defp build_successors_map(pipeline) do
    pipeline
    |> Enum.reduce(%{}, fn step, acc ->
      Enum.reduce(step.deps, acc, fn dep, inner_acc ->
        Map.update(inner_acc, dep, [step.id], fn existing -> [step.id | existing] end)
      end)
    end)
  end

  # Build map: step_id -> [predecessor_ids] (same as deps)
  defp build_predecessors_map(pipeline) do
    pipeline
    |> Enum.reduce(%{}, fn step, acc ->
      Map.put(acc, step.id, step.deps)
    end)
  end

  # Detect cycle using iterative topological sort (Kahn's algorithm).
  # Returns nil if no cycle, or a list of step IDs in the cycle otherwise.
  defp detect_cycle(pipeline) do
    ids = Enum.map(pipeline, & &1.id)

    in_degree =
      ids
      |> Enum.reduce(%{}, fn id, acc -> Map.put(acc, id, 0) end)
      |> then(fn degrees ->
        Enum.reduce(pipeline, degrees, fn step, acc ->
          Map.put(acc, step.id, length(step.deps))
        end)
      end)

    successors = build_successors_map(pipeline)

    # Start with nodes that have in-degree 0
    queue = Enum.filter(ids, fn id -> Map.get(in_degree, id, 0) == 0 end)

    {_queue, remaining_degrees, processed_count} =
      kahn_loop(queue, in_degree, successors, 0)

    if processed_count < length(ids) do
      # Cycle exists — return IDs still with non-zero in-degree
      remaining_degrees
      |> Enum.filter(fn {_id, deg} -> deg > 0 end)
      |> Enum.map(fn {id, _deg} -> id end)
      |> Enum.sort()
    else
      nil
    end
  end

  defp kahn_loop([], degrees, _successors, count), do: {[], degrees, count}

  defp kahn_loop([node | rest], degrees, successors, count) do
    succs = Map.get(successors, node, [])

    {new_queue_additions, new_degrees} =
      Enum.reduce(succs, {[], degrees}, fn succ, {queue_acc, deg_acc} ->
        new_deg = Map.get(deg_acc, succ, 0) - 1
        updated = Map.put(deg_acc, succ, new_deg)

        if new_deg == 0 do
          {[succ | queue_acc], updated}
        else
          {queue_acc, updated}
        end
      end)

    kahn_loop(rest ++ new_queue_additions, new_degrees, successors, count + 1)
  end

  # Compute maximum width (max number of steps executable concurrently)
  # using topological level assignment.
  defp compute_max_width(pipeline) do
    ids = Enum.map(pipeline, & &1.id)
    deps_map = Map.new(pipeline, fn step -> {step.id, step.deps} end)
    successors = build_successors_map(pipeline)

    in_degree =
      ids
      |> Enum.reduce(%{}, fn id, acc -> Map.put(acc, id, length(Map.get(deps_map, id, []))) end)

    # Assign levels via BFS (topological order)
    queue = Enum.filter(ids, fn id -> Map.get(in_degree, id, 0) == 0 end)
    levels = Map.new(queue, fn id -> {id, 0} end)

    levels = assign_levels(queue, levels, successors, deps_map)

    # Count nodes per level, return max
    if map_size(levels) == 0 do
      0
    else
      levels
      |> Enum.group_by(fn {_id, level} -> level end)
      |> Enum.map(fn {_level, entries} -> length(entries) end)
      |> Enum.max(fn -> 0 end)
    end
  end

  defp assign_levels([], levels, _successors, _deps_map), do: levels

  defp assign_levels([node | rest], levels, successors, deps_map) do
    node_level = Map.get(levels, node, 0)
    succs = Map.get(successors, node, [])

    {new_ready, new_levels} =
      Enum.reduce(succs, {[], levels}, fn succ, {ready_acc, lvl_acc} ->
        succ_level = max(Map.get(lvl_acc, succ, 0), node_level + 1)
        updated_levels = Map.put(lvl_acc, succ, succ_level)

        # Check if all predecessors of succ have levels assigned
        succ_deps = Map.get(deps_map, succ, [])
        all_deps_assigned = Enum.all?(succ_deps, &Map.has_key?(updated_levels, &1))

        if all_deps_assigned and succ not in rest and succ not in ready_acc do
          {[succ | ready_acc], updated_levels}
        else
          {ready_acc, updated_levels}
        end
      end)

    assign_levels(rest ++ new_ready, new_levels, successors, deps_map)
  end

  # ── OSA Conformance (Optional) ──────────────────────────────────────

  defp check_osa_conformance(pipeline) do
    spec_xml = pipeline_to_simple_xml(pipeline)

    case Req.post(@osa_conformance_url,
           json: %{spec: spec_xml, pipeline: pipeline},
           receive_timeout: @osa_timeout_ms,
           connect_options: [timeout: @osa_timeout_ms]
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.debug("[YawlValidator] OSA conformance returned HTTP #{status}")
        {:error, :osa_error}

      {:error, reason} ->
        Logger.debug("[YawlValidator] OSA conformance unavailable: #{inspect(reason)}")
        {:error, :osa_unavailable}
    end
  rescue
    e ->
      Logger.debug("[YawlValidator] OSA conformance failed: #{Exception.message(e)}")
      {:error, :osa_unavailable}
  end

  defp pipeline_to_simple_xml(pipeline) do
    steps =
      pipeline
      |> Enum.map(fn step ->
        deps_str =
          step.deps
          |> Enum.map(&to_string/1)
          |> Enum.join(",")

        ~s(<step id="#{step.id}" deps="#{deps_str}"/>)
      end)
      |> Enum.join("\n    ")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <pipeline>
      #{steps}
    </pipeline>
    """
  end
end
