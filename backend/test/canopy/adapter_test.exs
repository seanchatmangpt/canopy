defmodule Canopy.AdapterTest do
  use ExUnit.Case, async: true

  alias Canopy.Adapter

  describe "resolve/1" do
    test "resolves 'osa' to Canopy.Adapters.OSA" do
      assert {:ok, Canopy.Adapters.OSA} = Adapter.resolve("osa")
    end

    test "resolves 'claude-code' to Canopy.Adapters.ClaudeCode" do
      assert {:ok, Canopy.Adapters.ClaudeCode} = Adapter.resolve("claude-code")
    end

    test "resolves 'codex' to Canopy.Adapters.Codex" do
      assert {:ok, Canopy.Adapters.Codex} = Adapter.resolve("codex")
    end

    test "resolves 'bash' to Canopy.Adapters.Bash" do
      assert {:ok, Canopy.Adapters.Bash} = Adapter.resolve("bash")
    end

    test "resolves 'http' to Canopy.Adapters.HTTP" do
      assert {:ok, Canopy.Adapters.HTTP} = Adapter.resolve("http")
    end

    test "resolves 'pm4py-rust' to Canopy.Adapters.PM4pyRust" do
      assert {:ok, Canopy.Adapters.PM4pyRust} = Adapter.resolve("pm4py-rust")
    end

    test "resolves 'businessos' to Canopy.Adapters.BusinessOS" do
      assert {:ok, Canopy.Adapters.BusinessOS} = Adapter.resolve("businessos")
    end

    test "resolves 'mcp' to Canopy.Adapters.MCP" do
      assert {:ok, Canopy.Adapters.MCP} = Adapter.resolve("mcp")
    end

    test "returns error for unknown adapter type" do
      assert {:error, {:unknown_adapter, "nonexistent"}} = Adapter.resolve("nonexistent")
    end

    test "returns error for empty string" do
      assert {:error, {:unknown_adapter, ""}} = Adapter.resolve("")
    end

    test "returns error for nil" do
      assert {:error, {:unknown_adapter, nil}} = Adapter.resolve(nil)
    end
  end

  describe "all/0" do
    test "returns a list of adapter metadata maps" do
      adapters = Adapter.all()
      assert is_list(adapters)
      assert length(adapters) == 8
    end

    test "each adapter has required metadata fields" do
      for adapter <- Adapter.all() do
        assert Map.has_key?(adapter, :type), "Missing :type in #{inspect(adapter)}"
        assert Map.has_key?(adapter, :name), "Missing :name in #{inspect(adapter)}"

        assert Map.has_key?(adapter, :supports_session),
               "Missing :supports_session in #{inspect(adapter)}"

        assert Map.has_key?(adapter, :supports_concurrent),
               "Missing :supports_concurrent in #{inspect(adapter)}"

        assert Map.has_key?(adapter, :capabilities),
               "Missing :capabilities in #{inspect(adapter)}"
      end
    end

    test "includes MCP adapter" do
      adapters = Adapter.all()
      mcp = Enum.find(adapters, fn a -> a.type == "mcp" end)
      assert mcp != nil
      assert mcp.name == "MCP"
    end

    test "includes OSA adapter" do
      adapters = Adapter.all()
      osa = Enum.find(adapters, fn a -> a.type == "osa" end)
      assert osa != nil
    end

    test "all types have string type and name" do
      for adapter <- Adapter.all() do
        assert is_binary(adapter.type)
        assert is_binary(adapter.name)
      end
    end

    test "all capabilities are lists" do
      for adapter <- Adapter.all() do
        assert is_list(adapter.capabilities)
      end
    end
  end
end
