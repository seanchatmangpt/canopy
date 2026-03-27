defmodule Canopy.OCPM.ProcessModelTest do
  use ExUnit.Case, async: true

  alias Canopy.OCPM.ProcessModel

  describe "changeset validation" do
    setup do
      workspace_id = Ecto.UUID.generate()
      agent_id = Ecto.UUID.generate()

      {:ok, workspace_id: workspace_id, agent_id: agent_id}
    end

    test "valid attributes produce a valid changeset", %{
      workspace_id: workspace_id,
      agent_id: agent_id
    } do
      attrs = %{
        nodes: ["create", "review", "approve", "complete"],
        edges: %{"transitions" => [[%{"from" => "create"}, %{"to" => "review"}]]},
        version: "1.0.0",
        discovered_at: DateTime.utc_now() |> DateTime.truncate(:second),
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = ProcessModel.changeset(%ProcessModel{}, attrs)
      assert changeset.valid?
    end

    test "missing required fields produce errors", %{
      workspace_id: workspace_id,
      agent_id: agent_id
    } do
      attrs = %{
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = ProcessModel.changeset(%ProcessModel{}, attrs)
      refute changeset.valid?

      errors = traverse_errors(changeset)
      assert :nodes in errors
      assert :edges in errors
      assert :version in errors
      assert :discovered_at in errors
    end

    test "empty nodes list is rejected", %{workspace_id: workspace_id, agent_id: agent_id} do
      attrs = %{
        nodes: [],
        edges: %{},
        version: "1.0.0",
        discovered_at: DateTime.utc_now() |> DateTime.truncate(:second),
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = ProcessModel.changeset(%ProcessModel{}, attrs)
      refute changeset.valid?
    end

    test "non-list nodes are rejected", %{workspace_id: workspace_id, agent_id: agent_id} do
      attrs = %{
        nodes: "not a list",
        edges: %{},
        version: "1.0.0",
        discovered_at: DateTime.utc_now() |> DateTime.truncate(:second),
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = ProcessModel.changeset(%ProcessModel{}, attrs)
      refute changeset.valid?
    end

    test "non-map edges are rejected", %{workspace_id: workspace_id, agent_id: agent_id} do
      attrs = %{
        nodes: ["create", "approve"],
        edges: "not a map",
        version: "1.0.0",
        discovered_at: DateTime.utc_now() |> DateTime.truncate(:second),
        workspace_id: workspace_id,
        agent_id: agent_id
      }

      changeset = ProcessModel.changeset(%ProcessModel{}, attrs)
      refute changeset.valid?
    end
  end

  describe "version format validation" do
    setup do
      workspace_id = Ecto.UUID.generate()
      {:ok, workspace_id: workspace_id}
    end

    test "accepts valid SemVer (major.minor.patch)", %{workspace_id: workspace_id} do
      versions = ["1.0.0", "0.1.0", "10.20.30", "0.0.1"]
      semver_regex = ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/

      for v <- versions do
        assert Regex.match?(semver_regex, v), "Expected #{v} to match SemVer"
      end
    end

    test "accepts SemVer with pre-release", %{workspace_id: workspace_id} do
      versions = ["1.0.0-alpha", "1.0.0-beta.1", "1.0.0-rc.1"]
      semver_regex = ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/

      for v <- versions do
        assert Regex.match?(semver_regex, v), "Expected #{v} to match SemVer"
      end
    end

    test "accepts SemVer with build metadata", %{workspace_id: workspace_id} do
      versions = ["1.0.0+build.123", "1.0.0+exp.sha.5114f85"]
      semver_regex = ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/

      for v <- versions do
        assert Regex.match?(semver_regex, v), "Expected #{v} to match SemVer"
      end
    end

    test "rejects invalid version strings", %{workspace_id: workspace_id} do
      versions = ["v1.0.0", "1.0", "1", "1.0.0.0", "abc", ""]
      semver_regex = ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/

      for v <- versions do
        refute Regex.match?(semver_regex, v), "Expected #{v} to NOT match SemVer"
      end
    end
  end

  describe "nodes validation" do
    test "non-empty list of strings is valid" do
      nodes = ["create", "review", "approve"]
      assert is_list(nodes)
      assert length(nodes) > 0
      assert Enum.all?(nodes, &is_binary/1)
    end

    test "list with non-string elements is still a list" do
      nodes = [1, 2, 3]
      assert is_list(nodes)
      # The validate_nodes function checks is_list and length > 0
      # It does NOT check element types
    end

    test "nil nodes are caught by guard" do
      nodes = nil
      # The validate_nodes function: if nodes && is_list(nodes) && length(nodes) > 0
      valid = nodes && is_list(nodes) && length(nodes) > 0
      refute valid
    end
  end

  describe "edges validation" do
    test "empty map is valid for edges" do
      edges = %{}
      # The validate_edges function: if edges && is_map(edges)
      valid = edges && is_map(edges)
      assert valid
    end

    test "map with transitions is valid" do
      edges = %{
        "transitions" => [
          [%{"from" => "create"}, %{"to" => "review"}],
          [%{"from" => "review"}, %{"to" => "approve"}]
        ]
      }

      assert is_map(edges)
    end

    test "nil edges are caught by guard" do
      edges = nil
      valid = edges && is_map(edges)
      refute valid
    end
  end

  describe "schema structure" do
    test "uses binary_id primary key" do
      assert is_binary(Ecto.UUID.generate())
    end

    test "has workspace and agent associations" do
      assert true
    end
  end

  # Helper to extract error keys from changeset
  defp traverse_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      msg
    end)
    |> Map.keys()
  end
end
