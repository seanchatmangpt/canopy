defmodule Canopy.Ontology.AdapterTools do
  @moduledoc """
  Integration layer between Canopy.Adapter and Canopy.Ontology.ToolRegistry.

  Adapters can query tool registry to discover available tools and capabilities
  instead of relying on hardcoded tool definitions.

  Example:
    {:ok, tools, _metadata} = AdapterTools.list_adapter_tools("osa")
    {:ok, tool, _metadata} = AdapterTools.get_adapter_tool("osa", "process-mining")
  """

  require Logger

  alias Canopy.Ontology.ToolRegistry

  @doc """
  List all tools available for a specific adapter.

  Returns:
    {:ok, [tools], metadata}
    {:error, reason}

  Options:
    - cache: use cache if available (default true)
    - limit: max results (default 100)
  """
  def list_adapter_tools(adapter_type, opts \\ []) do
    ontology_id = adapter_ontology_id(adapter_type)

    ToolRegistry.list_tools(
      Keyword.merge(opts,
        ontology_id: ontology_id,
        limit: Keyword.get(opts, :limit, 100)
      )
    )
  end

  @doc """
  Get a specific tool for an adapter.

  Returns:
    {:ok, tool, metadata}
    {:error, :not_found}
    {:error, reason}
  """
  def get_adapter_tool(adapter_type, tool_name, opts \\ []) do
    # First try to get the tool globally
    case ToolRegistry.get_tool(tool_name, cache: Keyword.get(opts, :cache, true)) do
      {:ok, tool, metadata} ->
        # Verify the tool supports the adapter type (if adapter constraint exists)
        if tool_supports_adapter?(tool, adapter_type) do
          {:ok, tool, metadata}
        else
          Logger.warning("Tool #{tool_name} does not support adapter #{adapter_type}")
          {:error, {:unsupported_adapter, adapter_type}}
        end

      error ->
        error
    end
  end

  @doc """
  Find tools by capability for an adapter.

  Returns:
    {:ok, [tools], metadata}
    {:error, reason}
  """
  def find_tools_by_capability(adapter_type, capability, opts \\ []) do
    ontology_id = adapter_ontology_id(adapter_type)

    ToolRegistry.find_by_capability(capability,
      Keyword.merge(opts, ontology_id: ontology_id)
    )
  end

  @doc """
  Get all capabilities available for an adapter.

  Returns:
    {:ok, capability_index, metadata}
    {:error, reason}

  Capability index: %{
    "process_mining" => [tools],
    "compliance_check" => [tools],
    ...
  }
  """
  def get_adapter_capabilities(adapter_type, opts \\ []) do
    ontology_id = adapter_ontology_id(adapter_type)

    ToolRegistry.get_capabilities_index(
      Keyword.merge(opts, ontology_id: ontology_id)
    )
  end

  @doc """
  Check if a tool is available for an adapter.

  Returns:
    true | false
  """
  def tool_available?(adapter_type, tool_name) do
    case get_adapter_tool(adapter_type, tool_name, cache: true) do
      {:ok, _tool, _metadata} -> true
      _ -> false
    end
  end

  # Private Helpers

  defp adapter_ontology_id("osa"), do: "osa-agents"
  defp adapter_ontology_id("claude-code"), do: "claude-code-agents"
  defp adapter_ontology_id("businessos"), do: "businessos-agents"
  defp adapter_ontology_id("mcp"), do: "mcp-agents"
  defp adapter_ontology_id(_), do: "chatman-agents"

  defp tool_supports_adapter?(tool, adapter_type) do
    # Check if tool has adapter constraints
    constraints = tool[:constraints] || %{}
    supported_adapters = constraints["supported_adapters"] || []

    # If no constraints, assume universal support
    if Enum.empty?(supported_adapters) do
      true
    else
      Enum.any?(supported_adapters, fn adapter ->
        String.downcase(to_string(adapter)) == String.downcase(adapter_type)
      end)
    end
  end
end
