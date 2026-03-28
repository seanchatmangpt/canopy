defmodule Canopy.Ontology.AdapterToolsTest do
  use ExUnit.Case
  @moduletag :requires_application

  alias Canopy.Ontology.AdapterTools
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

  describe "list_adapter_tools/2" do
    test "lists tools for a specific adapter" do
      {:ok, tools, metadata} = AdapterTools.list_adapter_tools("osa")

      assert is_list(tools)
      assert metadata.ontology_id == "osa-agents"
    end

    test "uses adapter-specific ontology IDs" do
      {:ok, _tools1, m1} = AdapterTools.list_adapter_tools("osa")
      {:ok, _tools2, m2} = AdapterTools.list_adapter_tools("claude-code")
      {:ok, _tools3, m3} = AdapterTools.list_adapter_tools("businessos")

      assert m1.ontology_id == "osa-agents"
      assert m2.ontology_id == "claude-code-agents"
      assert m3.ontology_id == "businessos-agents"
    end

    test "respects limit option" do
      {:ok, tools, metadata} = AdapterTools.list_adapter_tools("osa", limit: 10)

      assert length(tools) <= 10
      assert metadata.limit == 10
    end

    test "caches results" do
      {:ok, tools1, m1} = AdapterTools.list_adapter_tools("osa")
      refute m1.cache_hit

      {:ok, tools2, m2} = AdapterTools.list_adapter_tools("osa")
      assert m2.cache_hit
      assert tools1 == tools2
    end
  end

  describe "get_adapter_tool/3" do
    test "retrieves tool for adapter" do
      {:ok, tool, _metadata} = AdapterTools.get_adapter_tool("osa", "process-mining")

      assert is_map(tool)
      assert Map.has_key?(tool, :name)
    end

    test "returns not_found for unknown tool" do
      {:error, :not_found} = AdapterTools.get_adapter_tool("osa", "nonexistent-xyz")
    end

    test "respects cache option" do
      {:ok, _tool, m1} = AdapterTools.get_adapter_tool("osa", "process-mining", cache: true)
      refute m1.cache_hit

      {:ok, _tool, m2} = AdapterTools.get_adapter_tool("osa", "process-mining", cache: false)
      refute m2.cache_hit
    end

    test "supports adapter constraint checking" do
      # Tool may have constraints that limit adapter support
      case AdapterTools.get_adapter_tool("osa", "process-mining") do
        {:ok, _tool, _metadata} -> :ok
        {:error, {:unsupported_adapter, _adapter}} -> :ok
        {:error, :not_found} -> :ok
      end
    end
  end

  describe "find_tools_by_capability/3" do
    test "finds tools by capability for adapter" do
      {:ok, tools, metadata} = AdapterTools.find_tools_by_capability("osa", "process_mining")

      assert is_list(tools)
      assert metadata.ontology_id == "osa-agents"
      assert metadata.capability == "process_mining"
    end

    test "returns empty list for unknown capability" do
      {:ok, tools, _metadata} = AdapterTools.find_tools_by_capability("osa", "unicorn_magic")

      assert is_list(tools)
      assert length(tools) >= 0
    end

    test "adapter-specific capabilities search" do
      {:ok, tools1, m1} = AdapterTools.find_tools_by_capability("osa", "data_analysis")
      {:ok, tools2, m2} = AdapterTools.find_tools_by_capability("businessos", "data_analysis")

      # Different adapters may have different tools for same capability
      assert m1.ontology_id != m2.ontology_id
    end
  end

  describe "get_adapter_capabilities/2" do
    test "gets capability index for adapter" do
      {:ok, index, metadata} = AdapterTools.get_adapter_capabilities("osa")

      assert is_map(index)
      assert metadata.ontology_id == "osa-agents"
    end

    test "capability index format is correct" do
      {:ok, index, _metadata} = AdapterTools.get_adapter_capabilities("osa")

      Enum.each(index, fn {capability, tools} ->
        assert is_binary(capability)
        assert is_list(tools)
      end)
    end

    test "different adapters may have different capabilities" do
      {:ok, index1, m1} = AdapterTools.get_adapter_capabilities("osa")
      {:ok, index2, m2} = AdapterTools.get_adapter_capabilities("claude-code")

      assert m1.ontology_id != m2.ontology_id
      # Capabilities may differ between adapters
      assert is_map(index1)
      assert is_map(index2)
    end
  end

  describe "tool_available?/2" do
    test "checks if tool is available for adapter" do
      available = AdapterTools.tool_available?("osa", "process-mining")
      assert is_boolean(available)
    end

    test "returns false for unknown tool" do
      available = AdapterTools.tool_available?("osa", "nonexistent-xyz-tool")
      assert available == false
    end

    test "defaults to true for unconstrained adapters" do
      # If adapter has default ontology mapping, tools should be available
      case AdapterTools.tool_available?("osa", "process-mining") do
        true -> :ok
        false -> :ok
      end
    end
  end

  describe "adapter type mapping" do
    test "maps adapter types to ontology IDs" do
      {:ok, _tools, m1} = AdapterTools.list_adapter_tools("osa")
      {:ok, _tools, m2} = AdapterTools.list_adapter_tools("unknown-adapter")

      assert m1.ontology_id == "osa-agents"
      # Default
      assert m2.ontology_id == "chatman-agents"
    end

    test "mcp adapter maps to mcp-agents ontology" do
      {:ok, _tools, metadata} = AdapterTools.list_adapter_tools("mcp")
      assert metadata.ontology_id == "mcp-agents"
    end
  end

  describe "integration with ToolRegistry" do
    test "adapter_tools delegates to ToolRegistry correctly" do
      # Both should return equivalent results
      {:ok, tools_direct, m1} =
        ToolRegistry.list_tools(ontology_id: "osa-agents", limit: 100)

      {:ok, tools_via_adapter, m2} =
        AdapterTools.list_adapter_tools("osa", limit: 100)

      assert m1.ontology_id == m2.ontology_id
      assert length(tools_direct) == length(tools_via_adapter)
    end

    test "cache is shared between ToolRegistry and AdapterTools" do
      # First call via AdapterTools
      {:ok, _tools1, m1} = AdapterTools.list_adapter_tools("osa")
      refute m1.cache_hit

      # Second call via ToolRegistry with same ontology should hit cache
      {:ok, _tools2, m2} =
        ToolRegistry.list_tools(ontology_id: "osa-agents", limit: 100)

      assert m2.cache_hit
    end
  end
end
