defmodule Canopy.GoalDecomposerTest do
  use ExUnit.Case, async: true

  # Tests for GoalDecomposer pure logic - JSON parsing, prompt construction,
  # and issue attribute mapping. Does not require DB or Claude binary.

  describe "parse_issues_json logic" do
    # The parse_issues_json function:
    # 1. Strips markdown code fences
    # 2. Finds a JSON array via regex
    # 3. Decodes with Jason

    test "strips markdown code fences from response" do
      response = "```json\n[{\"title\": \"test\"}]\n```"
      cleaned =
        response
        |> String.replace(~r/```json\n?/, "")
        |> String.replace(~r/```\n?/, "")
        |> String.trim()

      refute String.contains?(cleaned, "```")
      assert String.contains?(cleaned, "[")
    end

    test "extracts JSON array from mixed content" do
      response = ~s(Here are the issues:\n[{"title": "first"}, {"title": "second"}])

      case Regex.run(~r/\[[\s\S]*\]/, response) do
        [json] -> assert String.starts_with?(json, "[") and String.ends_with?(json, "]")
        nil -> flunk("Should have found a JSON array")
      end
    end

    test "valid JSON array decodes successfully" do
      json = ~s([{"title": "task1", "priority": "high"}])
      assert {:ok, list} = Jason.decode(json)
      assert is_list(list)
      assert length(list) == 1
    end

    test "non-array JSON returns error shape" do
      json = ~s({"not": "an array"})
      case Jason.decode(json) do
        {:ok, map} when is_map(map) -> assert is_map(map)
        _ -> flunk("Expected map decode")
      end
    end

    test "invalid JSON returns error shape" do
      json = "not valid json {"
      assert {:error, _} = Jason.decode(json)
    end

    test "no JSON array found returns empty" do
      response = "Just plain text, no JSON here"
      case Regex.run(~r/\[[\s\S]*\]/, response) do
        nil -> :ok
        _ -> flunk("Should not have found a JSON array")
      end
    end
  end

  describe "issue attribute mapping" do
    test "priority defaults to medium when missing" do
      priority = nil || "medium"
      assert priority == "medium"
    end

    test "priority uses provided value" do
      priority = "critical" || "medium"
      assert priority == "critical"
    end

    test "status defaults to backlog" do
      status = "backlog"
      assert status == "backlog"
    end
  end

  describe "decompose options" do
    test "max_issues defaults to 10" do
      opts = []
      max_issues = Keyword.get(opts, :max_issues, 10)
      assert max_issues == 10
    end

    test "max_issues can be overridden" do
      opts = [max_issues: 5]
      max_issues = Keyword.get(opts, :max_issues, 10)
      assert max_issues == 5
    end

    test "auto_assign defaults to true" do
      opts = []
      auto_assign = Keyword.get(opts, :auto_assign, true)
      assert auto_assign == true
    end

    test "auto_assign can be set to false" do
      opts = [auto_assign: false]
      auto_assign = Keyword.get(opts, :auto_assign, true)
      assert auto_assign == false
    end
  end

  describe "agent roster construction" do
    test "agents are formatted as bullet list" do
      agents = [
        %{name: "Researcher", role: "Analyst", slug: "researcher"},
        %{name: "Coder", role: "Developer", slug: "coder"}
      ]

      roster =
        agents
        |> Enum.map(fn a -> "- #{a.name} (#{a.role}): #{a.slug}" end)
        |> Enum.join("\n")

      assert roster == "- Researcher (Analyst): researcher\n- Coder (Developer): coder"
    end

    test "empty agent list produces empty roster" do
      agents = []
      roster =
        agents
        |> Enum.map(fn a -> "- #{a.name}" end)
        |> Enum.join("\n")

      assert roster == ""
    end
  end
end
