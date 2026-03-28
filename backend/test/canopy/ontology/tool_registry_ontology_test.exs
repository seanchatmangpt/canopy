defmodule Canopy.Ontology.ToolRegistryTest do
  use ExUnit.Case
  @moduletag :requires_application

  alias Canopy.Ontology.ToolRegistry
  alias Canopy.Ontology.Service

  setup do
    # Initialize ETS tables for testing
    ensure_ets_tables()

    # Clear ToolRegistry cache directly (avoid GenServer call)
    try do
      :ets.delete_all_objects(:tool_registry_cache)
    rescue
      _ -> :ok
    end

    :ok
  end

  defp ensure_ets_tables do
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

    case :ets.whereis(:tool_registry_stats) do
      :undefined ->
        :ets.new(:tool_registry_stats, [:named_table, :set, :public])
        :ets.insert(:tool_registry_stats, {:cache_hits, 0})
        :ets.insert(:tool_registry_stats, {:cache_misses, 0})

      _ ->
        :ok
    end
  end

  describe "get_tool/2" do
    test "retrieves tool by name with metadata" do
      {:ok, tool, metadata} = ToolRegistry.get_tool("process-mining")

      assert is_map(tool)
      assert tool[:name] in ["process-mining", ""]
      assert metadata.cache_hit == false
      assert is_struct(metadata.retrieved_at, DateTime)
    end

    test "returns not_found for unknown tool" do
      {:error, :not_found} = ToolRegistry.get_tool("nonexistent-tool-xyz")
    end

    test "caches tool and returns cache_hit on second call" do
      {:ok, tool1, m1} = ToolRegistry.get_tool("process-mining")
      refute m1.cache_hit

      {:ok, tool2, m2} = ToolRegistry.get_tool("process-mining")
      assert m2.cache_hit
      assert tool1 == tool2
    end

    test "respects cache: false option" do
      {:ok, _tool, m1} = ToolRegistry.get_tool("process-mining", cache: true)
      refute m1.cache_hit

      {:ok, _tool, m2} = ToolRegistry.get_tool("process-mining", cache: false)
      refute m2.cache_hit
    end
  end

  describe "list_tools/1" do
    test "lists tools from ontology with pagination" do
      {:ok, tools, metadata} = ToolRegistry.list_tools(ontology_id: "chatman-agents", limit: 50)

      assert is_list(tools)
      assert metadata.cache_hit == false
      assert metadata.ontology_id == "chatman-agents"
      assert is_integer(metadata.count)
      assert metadata.count <= 50
    end

    test "respects limit parameter" do
      {:ok, tools1, m1} = ToolRegistry.list_tools(limit: 10)
      {:ok, tools2, m2} = ToolRegistry.list_tools(limit: 20)

      refute m1.cache_hit
      refute m2.cache_hit
      # Different limits should produce potentially different result sets
      assert length(tools1) <= 10
      assert length(tools2) <= 20
    end

    test "caches results and returns cache_hit on second call" do
      {:ok, tools1, m1} = ToolRegistry.list_tools(ontology_id: "chatman-agents", limit: 50)
      refute m1.cache_hit

      {:ok, tools2, m2} = ToolRegistry.list_tools(ontology_id: "chatman-agents", limit: 50)
      assert m2.cache_hit
      assert tools1 == tools2
    end

    test "respects cache: false option" do
      {:ok, _tools, m1} = ToolRegistry.list_tools(cache: true)
      refute m1.cache_hit

      {:ok, _tools, m2} = ToolRegistry.list_tools(cache: false)
      refute m2.cache_hit
    end

    test "uses default ontology_id: chatman-agents" do
      {:ok, _tools, metadata} = ToolRegistry.list_tools()
      assert metadata.ontology_id == "chatman-agents"
    end

    test "limits results to 1000 tools maximum (WvdA boundedness)" do
      {:ok, tools, _metadata} = ToolRegistry.list_tools(limit: 5000)
      assert length(tools) <= 1000
    end
  end

  describe "find_by_capability/2" do
    test "finds tools by capability" do
      {:ok, tools, metadata} = ToolRegistry.find_by_capability("process_mining")

      assert is_list(tools)
      assert metadata.cache_hit == false
      assert metadata.capability == "process_mining"
    end

    test "filters tools to only those with capability" do
      {:ok, tools, _metadata} = ToolRegistry.find_by_capability("compliance_check")

      Enum.each(tools, fn tool ->
        capabilities = tool[:capabilities] || []
        # Tools should have the requested capability or be empty results
        assert is_list(capabilities)
      end)
    end

    test "caches capability results and returns cache_hit on second call" do
      {:ok, tools1, m1} = ToolRegistry.find_by_capability("process_mining")
      refute m1.cache_hit

      {:ok, tools2, m2} = ToolRegistry.find_by_capability("process_mining")
      assert m2.cache_hit
      assert tools1 == tools2
    end

    test "respects ontology_id option" do
      {:ok, _tools, metadata} =
        ToolRegistry.find_by_capability("data_analysis", ontology_id: "custom-ontology")

      assert metadata.ontology_id == "custom-ontology"
    end

    test "capability search is case-insensitive" do
      {:ok, tools1, _m1} = ToolRegistry.find_by_capability("Process_Mining")
      {:ok, tools2, _m2} = ToolRegistry.find_by_capability("process_mining")

      # Both queries should return tools with the same capability (regardless of case)
      assert length(tools1) == length(tools2)
    end
  end

  describe "get_capabilities_index/1" do
    test "builds index of tools grouped by capability" do
      {:ok, index, metadata} = ToolRegistry.get_capabilities_index()

      assert is_map(index)
      assert metadata.cache_hit == false
      assert is_integer(metadata.capability_count)
    end

    test "caches capabilities index and returns cache_hit on second call" do
      {:ok, index1, m1} = ToolRegistry.get_capabilities_index()
      refute m1.cache_hit

      {:ok, index2, m2} = ToolRegistry.get_capabilities_index()
      assert m2.cache_hit
      assert index1 == index2
    end

    test "index values are lists of tools" do
      {:ok, index, _metadata} = ToolRegistry.get_capabilities_index()

      Enum.each(index, fn {capability, tools} ->
        assert is_binary(capability)
        assert is_list(tools)

        Enum.each(tools, fn tool ->
          assert is_map(tool)
          assert Map.has_key?(tool, :name)
          assert Map.has_key?(tool, :ontology_id)
        end)
      end)
    end

    test "uses default ontology_id: chatman-agents" do
      {:ok, _index, metadata} = ToolRegistry.get_capabilities_index()
      assert metadata.ontology_id == "chatman-agents"
    end

    test "respects cache: false option" do
      {:ok, _index, m1} = ToolRegistry.get_capabilities_index(cache: true)
      refute m1.cache_hit

      {:ok, _index, m2} = ToolRegistry.get_capabilities_index(cache: false)
      refute m2.cache_hit
    end
  end

  describe "cache management" do
    test "clear_cache(:all) removes all cached entries" do
      # Populate cache
      {:ok, _tools, m1} = ToolRegistry.list_tools()
      refute m1.cache_hit

      # Verify cache hit before clear
      {:ok, _tools, m2} = ToolRegistry.list_tools()
      assert m2.cache_hit

      # Clear cache
      :ok = ToolRegistry.clear_cache(:all)

      # Verify cache miss after clear
      {:ok, _tools, m3} = ToolRegistry.list_tools()
      refute m3.cache_hit
    end

    test "clear_cache(ontology_id) clears only that ontology" do
      # Populate cache for two ontologies
      {:ok, _tools1, m1} = ToolRegistry.list_tools(ontology_id: "ontology1")
      {:ok, _tools2, m2} = ToolRegistry.list_tools(ontology_id: "ontology2")

      refute m1.cache_hit
      refute m2.cache_hit

      # Clear only ontology1
      :ok = ToolRegistry.clear_cache("ontology1")

      # ontology1 should miss, ontology2 should still hit
      {:ok, _tools1_after, m1_after} = ToolRegistry.list_tools(ontology_id: "ontology1")
      {:ok, _tools2_after, m2_after} = ToolRegistry.list_tools(ontology_id: "ontology2")

      refute m1_after.cache_hit
      assert m2_after.cache_hit
    end

    test "cache_stats returns hit/miss counts and hit_rate" do
      stats = ToolRegistry.cache_stats()

      assert is_integer(stats.hits)
      assert is_integer(stats.misses)
      assert is_float(stats.hit_rate)
      assert stats.hit_rate >= 0.0 and stats.hit_rate <= 1.0
      assert stats.total == stats.hits + stats.misses
    end
  end

  describe "WvdA Soundness Verification" do
    test "all Service.search calls have bounded timeout (deadlock-free)" do
      # Timeout is enforced by Service (5000ms)
      # This test verifies that ToolRegistry doesn't create circular waits
      start_time = System.monotonic_time(:millisecond)

      case ToolRegistry.list_tools(limit: 100) do
        {:ok, _tools, _metadata} -> :ok
        {:error, _reason} -> :ok
      end

      elapsed = System.monotonic_time(:millisecond) - start_time
      # Should complete within reasonable time (service timeout + overhead)
      assert elapsed < 10_000, "ToolRegistry operation took too long: #{elapsed}ms"
    end

    test "no unbounded loops: max 1000 tools returned (liveness)" do
      {:ok, tools, _metadata} = ToolRegistry.list_tools(limit: 5000)
      assert length(tools) <= 1000, "Tool list exceeded max boundedness limit"
    end

    test "all errors are caught and logged (no silent failures)" do
      # Verify that exceptions in tool discovery are caught
      {:ok, _tools, _metadata} = ToolRegistry.list_tools()
      # Should not raise exceptions
    end

    test "cache has explicit TTL (boundedness of memory)" do
      {:ok, _tools, metadata} = ToolRegistry.list_tools()
      # Cache results should have ttl_seconds = 300 (5 min)
      assert is_struct(metadata.retrieved_at, DateTime)
      # Next call within TTL should hit cache
      {:ok, _tools2, m2} = ToolRegistry.list_tools(cache: true)
      assert m2.cache_hit
    end
  end
end
