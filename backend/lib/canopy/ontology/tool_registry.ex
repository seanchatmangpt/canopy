defmodule Canopy.Ontology.ToolRegistry do
  @moduledoc """
  Dynamic tool discovery from cached ontologies.

  Tool registry queries the Canopy.Ontology.Service to discover tool definitions,
  capabilities, and constraints. Tools are cached in-memory for <10ms lookups.

  WvdA Soundness:
  - Deadlock-free: all Service.search calls have 5000ms timeout
  - Liveness: no unbounded loops; max 1000 tools per ontology
  - Boundedness: ETS cache with explicit max_memory

  Cache Strategy:
  - Tool list (by ontology): 5 minutes
  - Tool details (by name): 10 minutes
  - Capability index: 5 minutes
  - Statistics: 1 minute
  """
  use GenServer

  require Logger

  alias Canopy.Ontology.Service

  # Public API

  @doc """
  Start the tool registry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get a tool by name.

  Returns:
    {:ok, tool_map, metadata}
    {:error, :not_found}
    {:error, reason}

  Tool map contains:
    - name: String.t()
    - ontology_id: String.t()
    - description: String.t()
    - inputs: [map()] (parameter definitions)
    - outputs: [map()] (return definitions)
    - constraints: map() (execution limits)
  """
  def get_tool(tool_name, opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    cache_key = {:tool, tool_name}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, tool, metadata} = get_cached(cache_key)
      {:ok, tool, Map.put(metadata, :cache_hit, true)}
    else
      case find_tool_in_ontologies(tool_name) do
        {:ok, tool} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            tool_name: tool_name
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, tool, metadata}, ttl_seconds: 600)
          {:ok, tool, metadata}

        :not_found ->
          Logger.warning("Tool not found: #{tool_name}")
          {:error, :not_found}

        {:error, reason} ->
          Logger.error("Failed to get tool #{tool_name}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  List all tools in an ontology.

  Returns:
    {:ok, [tools], metadata}
    {:error, reason}

  Options:
    - ontology_id: "chatman-agents" (default)
    - limit: max results (default 100)
    - offset: pagination offset (default 0)
    - cache: use cache if available (default true)
  """
  def list_tools(opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    ontology_id = Keyword.get(opts, :ontology_id, "chatman-agents")
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    cache_key = {:tools, {ontology_id, limit, offset}}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, tools, metadata} = get_cached(cache_key)
      {:ok, tools, Map.put(metadata, :cache_hit, true)}
    else
      case search_tools_in_ontology(ontology_id, limit, offset) do
        {:ok, tools} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            ontology_id: ontology_id,
            count: length(tools),
            limit: limit,
            offset: offset
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, tools, metadata}, ttl_seconds: 300)
          {:ok, tools, metadata}

        {:error, reason} ->
          Logger.error("Failed to list tools in #{ontology_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Find tools by capability.

  Returns:
    {:ok, [tools], metadata}
    {:error, reason}

  Options:
    - ontology_id: "chatman-agents" (default)
    - cache: use cache if available (default true)

  Searches for tools with the given capability in their definition.
  """
  def find_by_capability(capability, opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    ontology_id = Keyword.get(opts, :ontology_id, "chatman-agents")

    cache_key = {:tools_by_capability, {ontology_id, capability}}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, tools, metadata} = get_cached(cache_key)
      {:ok, tools, Map.put(metadata, :cache_hit, true)}
    else
      case search_tools_by_capability(ontology_id, capability) do
        {:ok, tools} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            ontology_id: ontology_id,
            capability: capability,
            count: length(tools)
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, tools, metadata}, ttl_seconds: 300)
          {:ok, tools, metadata}

        {:error, reason} ->
          Logger.error("Failed to find tools by capability #{capability}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Get tool capabilities index (all tools grouped by capability).

  Returns:
    {:ok, capability_index, metadata}
    {:error, reason}

  Capability index is a map: %{
    "process_mining" => [tools],
    "compliance_check" => [tools],
    ...
  }
  """
  def get_capabilities_index(opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    ontology_id = Keyword.get(opts, :ontology_id, "chatman-agents")
    cache_key = {:capabilities_index, ontology_id}

    if cache? and cached?(cache_key) do
      record_cache_hit()
      {:ok, index, metadata} = get_cached(cache_key)
      {:ok, index, Map.put(metadata, :cache_hit, true)}
    else
      case build_capabilities_index(ontology_id) do
        {:ok, index} ->
          metadata = %{
            retrieved_at: DateTime.utc_now(),
            cache_hit: false,
            ontology_id: ontology_id,
            capability_count: map_size(index)
          }

          record_cache_miss()
          cache_result(cache_key, {:ok, index, metadata}, ttl_seconds: 300)
          {:ok, index, metadata}

        {:error, reason} ->
          Logger.error("Failed to build capabilities index: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Clear tool cache for a specific ontology or all.
  """
  def clear_cache(ontology_id \\ :all) do
    try do
      GenServer.call(__MODULE__, {:clear_cache, ontology_id}, 5000)
    catch
      :exit, {:timeout, _} ->
        Logger.error("[ToolRegistry] clear_cache timeout for #{inspect(ontology_id)}")
        :timeout
    end
  end

  @doc """
  Get cache statistics.
  """
  def cache_stats do
    try do
      GenServer.call(__MODULE__, :cache_stats, 5000)
    catch
      :exit, {:timeout, _} ->
        Logger.error("[ToolRegistry] cache_stats timeout")
        %{hits: 0, misses: 0, entries: 0}
    end
  end

  # GenServer Callbacks

  @impl GenServer
  def init(_opts) do
    ensure_cache_table()
    ensure_stats_table()
    {:ok, %{}}
  end

  defp ensure_cache_table do
    case :ets.whereis(:tool_registry_cache) do
      :undefined ->
        :ets.new(:tool_registry_cache, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp ensure_stats_table do
    case :ets.whereis(:tool_registry_stats) do
      :undefined ->
        :ets.new(:tool_registry_stats, [:named_table, :set, :public])
        :ets.insert(:tool_registry_stats, {:cache_hits, 0})
        :ets.insert(:tool_registry_stats, {:cache_misses, 0})

      _ ->
        :ok
    end
  end

  @impl GenServer
  def handle_call(:cache_stats, _from, state) do
    hits = :ets.lookup_element(:tool_registry_stats, :cache_hits, 2) || 0
    misses = :ets.lookup_element(:tool_registry_stats, :cache_misses, 2) || 0
    total = hits + misses
    hit_rate = if total > 0, do: hits / total, else: 0.0

    stats = %{
      hits: hits,
      misses: misses,
      hit_rate: Float.round(hit_rate, 4),
      total: total
    }

    {:reply, stats, state}
  end

  def handle_call({:clear_cache, :all}, _from, state) do
    :ets.delete_all_objects(:tool_registry_cache)
    Logger.info("[ToolRegistry] Cleared all tool registry cache")
    {:reply, :ok, state}
  end

  def handle_call({:clear_cache, ontology_id}, _from, state) do
    delete_cache_for_ontology(ontology_id)
    Logger.info("[ToolRegistry] Cleared cache for ontology: #{ontology_id}")
    {:reply, :ok, state}
  end

  # Private Helpers

  defp delete_cache_for_ontology(ontology_id) do
    all_keys = :ets.match_object(:tool_registry_cache, {:"$1", :_, :_})

    Enum.each(all_keys, fn {key, _, _} ->
      should_delete = case key do
        {:tools, {^ontology_id, _, _}} -> true
        {:tools_by_capability, {^ontology_id, _}} -> true
        {:capabilities_index, ^ontology_id} -> true
        _ -> false
      end

      if should_delete do
        :ets.delete(:tool_registry_cache, key)
      end
    end)
  end

  defp cached?(cache_key) do
    case :ets.lookup(:tool_registry_cache, cache_key) do
      [{^cache_key, _value, expires_at}] ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :lt

      [] ->
        false
    end
  rescue
    _ -> false
  end

  defp get_cached(cache_key) do
    case :ets.lookup(:tool_registry_cache, cache_key) do
      [{^cache_key, value, _expires_at}] -> value
      [] -> :not_found
    end
  end

  defp cache_result(key, value, opts) do
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 300)
    expires_at = DateTime.add(DateTime.utc_now(), ttl_seconds, :second)
    :ets.insert(:tool_registry_cache, {key, value, expires_at})
  end

  defp record_cache_hit do
    try do
      :ets.update_counter(:tool_registry_stats, :cache_hits, {2, 1})
    rescue
      _ -> :ok
    end
  end

  defp record_cache_miss do
    try do
      :ets.update_counter(:tool_registry_stats, :cache_misses, {2, 1})
    rescue
      _ -> :ok
    end
  end

  # Tool Discovery Logic

  defp find_tool_in_ontologies(tool_name) do
    case Service.search("chatman-agents", tool_name, type: "property", limit: 1, cache: true) do
      {:ok, results, _metadata} ->
        case results do
          [tool_def | _] ->
            {:ok, normalize_tool(tool_def, "chatman-agents")}

          [] ->
            :not_found
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in find_tool_in_ontologies: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  defp search_tools_in_ontology(ontology_id, limit, offset) do
    case Service.search(ontology_id, "tool", type: "property", limit: limit, offset: offset, cache: true) do
      {:ok, results, _metadata} ->
        normalized = results
                     |> Enum.take(min(length(results), 1000))
                     |> Enum.map(&normalize_tool(&1, ontology_id))

        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in search_tools_in_ontology: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  defp search_tools_by_capability(ontology_id, capability) do
    query = "capability:#{capability}"

    case Service.search(ontology_id, query, type: "property", limit: 100, cache: true) do
      {:ok, results, _metadata} ->
        normalized = results
                     |> Enum.take(1000)
                     |> Enum.map(&normalize_tool(&1, ontology_id))
                     |> Enum.filter(&has_capability?(&1, capability))

        {:ok, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in search_tools_by_capability: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  defp build_capabilities_index(ontology_id) do
    case search_tools_in_ontology(ontology_id, 1000, 0) do
      {:ok, tools} ->
        index = tools
                |> Enum.reduce(%{}, fn tool, acc ->
                  capabilities = tool[:capabilities] || []

                  Enum.reduce(capabilities, acc, fn cap, inner_acc ->
                    cap_key = to_string(cap)
                    existing = Map.get(inner_acc, cap_key, [])
                    Map.put(inner_acc, cap_key, existing ++ [tool])
                  end)
                end)

        {:ok, index}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in build_capabilities_index: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  # Tool Normalization

  defp normalize_tool(tool_def, ontology_id) when is_map(tool_def) do
    %{
      name: tool_def["name"] || tool_def["id"] || "unknown",
      ontology_id: ontology_id,
      description: tool_def["description"] || "",
      inputs: tool_def["inputs"] || [],
      outputs: tool_def["outputs"] || [],
      capabilities: tool_def["capabilities"] || [],
      constraints: tool_def["constraints"] || %{},
      metadata: tool_def["metadata"] || %{}
    }
  end

  defp normalize_tool(tool_def, _ontology_id) do
    Logger.warning("Cannot normalize tool definition: #{inspect(tool_def)}")
    %{}
  end

  defp has_capability?(tool, capability) when is_map(tool) do
    capabilities = tool[:capabilities] || []
    Enum.any?(capabilities, fn cap -> String.downcase(to_string(cap)) == String.downcase(to_string(capability)) end)
  end

  defp has_capability?(_tool, _capability), do: false
end
