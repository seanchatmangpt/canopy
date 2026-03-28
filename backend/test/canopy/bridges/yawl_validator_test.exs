defmodule Canopy.Bridges.YawlValidatorTest do
  use ExUnit.Case, async: true

  alias Canopy.Bridges.YawlValidator

  # ── WCP-1: Sequence ───────────────────────────────────────────────────

  describe "WCP-1 Sequence classification" do
    test "sequential pipeline classified as WCP-1" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :b, deps: [:a]},
        %{id: :c, deps: [:b]}
      ]

      assert {:ok, %{pattern: :wcp_1, sound: true}} = YawlValidator.validate(pipeline)
    end

    test "single step pipeline classified as WCP-1" do
      pipeline = [%{id: :only, deps: []}]
      assert {:ok, %{pattern: :wcp_1, sound: true}} = YawlValidator.validate(pipeline)
    end

    test "long sequential chain classified as WCP-1" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :b, deps: [:a]},
        %{id: :c, deps: [:b]},
        %{id: :d, deps: [:c]},
        %{id: :e, deps: [:d]}
      ]

      assert {:ok, %{pattern: :wcp_1, sound: true}} = YawlValidator.validate(pipeline)
    end
  end

  # ── WCP-2/WCP-3: Parallel Split + Synchronization ──────────────────

  describe "WCP-2/WCP-3 Fork-Join classification" do
    test "fork-join pipeline classified as WCP-2/WCP-3" do
      pipeline = [
        %{id: :start, deps: []},
        %{id: :a, deps: [:start]},
        %{id: :b, deps: [:start]},
        %{id: :end, deps: [:a, :b]}
      ]

      assert {:ok, %{pattern: :wcp_2_3, sound: true}} = YawlValidator.validate(pipeline)
    end

    test "fork without join still classified as WCP-2/WCP-3" do
      pipeline = [
        %{id: :start, deps: []},
        %{id: :a, deps: [:start]},
        %{id: :b, deps: [:start]}
      ]

      assert {:ok, %{pattern: :wcp_2_3, sound: true}} = YawlValidator.validate(pipeline)
    end

    test "wide fork-join classified as WCP-2/WCP-3" do
      pipeline = [
        %{id: :start, deps: []},
        %{id: :a, deps: [:start]},
        %{id: :b, deps: [:start]},
        %{id: :c, deps: [:start]},
        %{id: :d, deps: [:start]},
        %{id: :end, deps: [:a, :b, :c, :d]}
      ]

      assert {:ok, %{pattern: :wcp_2_3, sound: true}} = YawlValidator.validate(pipeline)
    end
  end

  # ── WCP-4/WCP-5: Exclusive Choice + Simple Merge ───────────────────

  describe "WCP-4/WCP-5 Exclusive Choice classification" do
    test "exclusive choice classified as WCP-4/WCP-5" do
      pipeline = [
        %{id: :start, deps: [], choice: true},
        %{id: :path_a, deps: [:start]},
        %{id: :path_b, deps: [:start]},
        %{id: :end, deps: [:path_a, :path_b]}
      ]

      assert {:ok, %{pattern: :wcp_4_5, sound: true}} = YawlValidator.validate(pipeline)
    end

    test "choice attribute on intermediate node classified as WCP-4/WCP-5" do
      pipeline = [
        %{id: :start, deps: []},
        %{id: :decision, deps: [:start], choice: true},
        %{id: :yes, deps: [:decision]},
        %{id: :no, deps: [:decision]},
        %{id: :end, deps: [:yes, :no]}
      ]

      assert {:ok, %{pattern: :wcp_4_5, sound: true}} = YawlValidator.validate(pipeline)
    end
  end

  # ── Dead Activity Detection ─────────────────────────────────────────

  describe "dead activity detection (reachability)" do
    test "dead activity detected as unsound" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :b, deps: [:a]},
        # :orphan depends on :x which doesn't exist — but structure validation catches first.
        # Instead, test an island: a node whose deps are valid but unreachable from start.
        %{id: :c, deps: []},
        %{id: :d, deps: [:c]},
        # :island depends on :phantom which is a valid id but not connected to :a chain
        %{id: :island, deps: [:phantom]},
        %{id: :phantom, deps: [:island]}
      ]

      assert {:error, %{violations: violations}} = YawlValidator.validate(pipeline)
      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "dead activities" or violation_text =~ "cycle"
    end

    test "no start nodes detected as unsound" do
      # Every node has a dependency, forming a cycle
      pipeline = [
        %{id: :a, deps: [:c]},
        %{id: :b, deps: [:a]},
        %{id: :c, deps: [:b]}
      ]

      assert {:error, %{violations: violations}} = YawlValidator.validate(pipeline)
      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "no start nodes" or violation_text =~ "cycle"
    end
  end

  # ── Deadlock Detection ──────────────────────────────────────────────

  describe "deadlock detection" do
    test "deadlock detected as unsound" do
      # Create a cycle: a -> b -> c -> a
      pipeline = [
        %{id: :start, deps: []},
        %{id: :a, deps: [:start, :c]},
        %{id: :b, deps: [:a]},
        %{id: :c, deps: [:b]}
      ]

      assert {:error, %{violations: violations}} = YawlValidator.validate(pipeline)
      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "cycle"
    end

    test "undefined dependency detected" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :b, deps: [:nonexistent]}
      ]

      assert {:error, %{violations: violations}} = YawlValidator.validate(pipeline)
      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "undefined dependencies"
    end
  end

  # ── Bounded Parallelism ─────────────────────────────────────────────

  describe "bounded parallelism" do
    test "bounded parallelism enforced" do
      # Create a pipeline with 12 parallel branches (exceeds default max of 10)
      branches =
        for i <- 1..12 do
          %{id: :"branch_#{i}", deps: [:start]}
        end

      pipeline =
        [%{id: :start, deps: []}] ++
          branches ++
          [%{id: :end, deps: Enum.map(branches, & &1.id)}]

      assert {:error, %{violations: violations}} = YawlValidator.validate(pipeline)
      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "parallelism exceeds bound"
      assert violation_text =~ "12"
    end

    test "parallelism within bounds passes" do
      branches =
        for i <- 1..5 do
          %{id: :"branch_#{i}", deps: [:start]}
        end

      pipeline =
        [%{id: :start, deps: []}] ++
          branches ++
          [%{id: :end, deps: Enum.map(branches, & &1.id)}]

      assert {:ok, %{pattern: :wcp_2_3, sound: true}} = YawlValidator.validate(pipeline)
    end

    test "custom max_parallel respected" do
      branches =
        for i <- 1..4 do
          %{id: :"branch_#{i}", deps: [:start]}
        end

      pipeline =
        [%{id: :start, deps: []}] ++
          branches ++
          [%{id: :end, deps: Enum.map(branches, & &1.id)}]

      # With max_parallel: 3, 4 branches should fail
      assert {:error, %{violations: violations}} =
               YawlValidator.validate(pipeline, max_parallel: 3)

      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "parallelism exceeds bound"
    end

    test "custom max_parallel allows larger pipelines" do
      branches =
        for i <- 1..15 do
          %{id: :"branch_#{i}", deps: [:start]}
        end

      pipeline =
        [%{id: :start, deps: []}] ++
          branches ++
          [%{id: :end, deps: Enum.map(branches, & &1.id)}]

      assert {:ok, %{pattern: :wcp_2_3, sound: true}} =
               YawlValidator.validate(pipeline, max_parallel: 20)
    end
  end

  # ── Structure Validation ────────────────────────────────────────────

  describe "structure validation" do
    test "empty pipeline rejected" do
      assert {:error, %{violations: ["pipeline is empty"]}} = YawlValidator.validate([])
    end

    test "duplicate step ids rejected" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :a, deps: []}
      ]

      assert {:error, %{violations: violations}} = YawlValidator.validate(pipeline)
      violation_text = Enum.join(violations, " ")
      assert violation_text =~ "duplicate step ids"
    end
  end

  # ── classify/1 direct tests ─────────────────────────────────────────

  describe "classify/1" do
    test "returns :wcp_1 for linear pipeline" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :b, deps: [:a]}
      ]

      assert {:ok, :wcp_1} = YawlValidator.classify(pipeline)
    end

    test "returns :wcp_2_3 for fork-join" do
      pipeline = [
        %{id: :s, deps: []},
        %{id: :a, deps: [:s]},
        %{id: :b, deps: [:s]},
        %{id: :e, deps: [:a, :b]}
      ]

      assert {:ok, :wcp_2_3} = YawlValidator.classify(pipeline)
    end

    test "returns :wcp_4_5 for choice pattern" do
      pipeline = [
        %{id: :s, deps: [], choice: true},
        %{id: :a, deps: [:s]},
        %{id: :b, deps: [:s]}
      ]

      assert {:ok, :wcp_4_5} = YawlValidator.classify(pipeline)
    end
  end

  # ── check_soundness/2 direct tests ─────────────────────────────────

  describe "check_soundness/2" do
    test "sound pipeline returns {:ok, :sound}" do
      pipeline = [
        %{id: :a, deps: []},
        %{id: :b, deps: [:a]},
        %{id: :c, deps: [:b]}
      ]

      assert {:ok, :sound} = YawlValidator.check_soundness(pipeline)
    end

    test "unsound pipeline returns violations list" do
      pipeline = [
        %{id: :a, deps: [:b]},
        %{id: :b, deps: [:a]}
      ]

      assert {:error, %{violations: violations}} = YawlValidator.check_soundness(pipeline)
      assert length(violations) > 0
    end
  end
end
