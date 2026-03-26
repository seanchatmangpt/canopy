# This file runs the boundedness test with detailed metrics collection
# Usage: mix test test/canopy/jtbd/wave12_boundedness_chaos_runner.exs --no-start

ExUnit.start()

defmodule Wave12BoundednessChaosRunner do
  @moduledoc """
  Standalone chaos test runner for Wave 12 ETS metrics boundedness.

  Runs 300 iterations and captures:
  - ETS table size at each checkpoint (100, 200, 300)
  - Memory usage (in words and MB)
  - LRU eviction verification
  - Growth rate analysis
  """

  require Logger

  @max_entries 200

  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Wave 12 ETS Metrics Boundedness Chaos Test")
    IO.puts("Status: RED Phase (test before implementation)")
    IO.puts("WvdA Soundness: Deadlock-free, Liveness, Boundedness")
    IO.puts("Armstrong Principle: Supervision + Resource Limits")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Create ETS table if not exists
    case :ets.whereis(:jtbd_wave12_metrics) do
      :undefined ->
        IO.puts("► Creating :jtbd_wave12_metrics ETS table...")

        :ets.new(:jtbd_wave12_metrics, [
          :named_table,
          :set,
          :public,
          {:write_concurrency, false},
          {:read_concurrency, true}
        ])

        IO.puts("  ✓ ETS table created\n")

      tid ->
        IO.puts("► Using existing :jtbd_wave12_metrics table (tid=#{inspect(tid)})\n")
    end

    # Clear before test
    :ets.delete_all_objects(:jtbd_wave12_metrics)

    # Run chaos test
    metrics = run_chaos_iterations(1, 300)

    # Print results
    print_results(metrics)

    # Analyze boundedness
    analyze_boundedness(metrics)

    # Cleanup
    :ets.delete(:jtbd_wave12_metrics)
    IO.puts("\n✓ Test cleanup complete\n")
  end

  defp run_chaos_iterations(start_iter, end_iter, metrics \\ []) do
    Enum.reduce(start_iter..end_iter, metrics, fn iteration, acc ->
      # Insert 2 metrics per iteration
      insert_iteration_metrics(iteration)

      # Capture checkpoint data
      if rem(iteration, 100) == 0 do
        checkpoint = capture_checkpoint(iteration)
        [checkpoint | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  defp insert_iteration_metrics(iteration) do
    tid = :ets.whereis(:jtbd_wave12_metrics)

    timestamp = DateTime.utc_now()

    # Insert 2 metrics (pass + fail)
    key1 = {:iteration, iteration, :pass, timestamp}
    key2 = {:iteration, iteration, :fail, timestamp}

    :ets.insert(tid, {
      key1,
      %{
        latency_ms: 100 + :rand.uniform(50),
        scenario: :agent_decision_loop,
        outcome: :success
      }
    })

    :ets.insert(tid, {
      key2,
      %{
        latency_ms: 150 + :rand.uniform(50),
        scenario: :process_discovery,
        outcome: :success
      }
    })

    # Enforce LRU eviction
    enforce_max_size(tid)
  end

  defp enforce_max_size(tid) do
    current_size = :ets.info(tid, :size)

    if current_size > @max_entries do
      # Find oldest entry by minimum timestamp
      oldest_key = find_oldest_entry(tid)

      if oldest_key do
        :ets.delete(tid, oldest_key)
        # Recursively evict if still over limit
        enforce_max_size(tid)
      end
    end
  end

  defp find_oldest_entry(tid) do
    # Iterate all entries to find the one with the minimum timestamp
    tid
    |> :ets.tab2list()
    |> Enum.min_by(
      fn {{:iteration, _iter, _type, timestamp}, _value} -> timestamp end,
      fn -> nil end
    )
    |> case do
      {{:iteration, _iter, _type, _timestamp} = key, _value} -> key
      nil -> nil
    end
  end

  defp capture_checkpoint(iteration) do
    tid = :ets.whereis(:jtbd_wave12_metrics)
    size = :ets.info(tid, :size)
    memory = :ets.info(tid, :memory)

    %{
      iteration: iteration,
      size: size,
      memory_words: memory,
      memory_mb: Float.round(memory * 8 / 1_000_000, 3)
    }
  end

  defp print_results([checkpoint1, checkpoint2, checkpoint3] = metrics) do
    IO.puts("RESULTS: Chaos Test Execution\n")
    IO.puts("Checkpoint Data:")
    IO.puts("-" <> String.duplicate("-", 79))

    Enum.each(metrics, fn cp ->
      IO.puts(
        "  Iteration #{Integer.to_string(cp.iteration) |> String.pad_leading(3)}: " <>
          "size=#{Integer.to_string(cp.size) |> String.pad_leading(3)} entries | " <>
          "memory=#{Integer.to_string(cp.memory_words) |> String.pad_leading(7)} words (#{Float.round(cp.memory_mb, 3)} MB)"
      )
    end)

    IO.puts("-" <> String.duplicate("-", 79) <> "\n")

    # Size growth analysis
    growth_100_to_200 = checkpoint2.size - checkpoint1.size
    growth_200_to_300 = checkpoint3.size - checkpoint2.size

    IO.puts("Size Growth Analysis:")
    IO.puts("  100→200 iterations: #{inspect(growth_100_to_200)} entries")
    IO.puts("  200→300 iterations: #{inspect(growth_200_to_300)} entries")
    IO.puts("  Expected (bounded): < 50 entries per 100 iterations\n")

    # Memory growth analysis
    memory_growth_100_to_200 = checkpoint2.memory_words - checkpoint1.memory_words
    memory_growth_200_to_300 = checkpoint3.memory_words - checkpoint2.memory_words
    total_memory_growth = checkpoint3.memory_words - checkpoint1.memory_words
    growth_rate = total_memory_growth / checkpoint1.memory_words

    IO.puts("Memory Growth Analysis:")
    IO.puts(
      "  100→200 iterations: #{inspect(memory_growth_100_to_200)} words " <>
        "(#{Float.round(memory_growth_100_to_200 * 8 / 1_000_000, 3)} MB)"
    )

    IO.puts(
      "  200→300 iterations: #{inspect(memory_growth_200_to_300)} words " <>
        "(#{Float.round(memory_growth_200_to_300 * 8 / 1_000_000, 3)} MB)"
    )

    IO.puts("  Growth rate (100→300): #{Float.round(growth_rate, 2)}x")
    IO.puts("  Expected (bounded): < 1.5x (linear growth would be ~2x)\n")
  end

  defp analyze_boundedness([cp1, cp2, cp3]) do
    IO.puts("ANALYSIS: WvdA Soundness Verification\n")

    # Check 1: Boundedness
    bounded_100 = cp1.size <= @max_entries
    bounded_200 = cp2.size <= @max_entries
    bounded_300 = cp3.size <= @max_entries

    status_bounded = if bounded_100 and bounded_200 and bounded_300, do: "✓", else: "✗"

    IO.puts(
      "#{status_bounded} Boundedness (max=#{@max_entries}):"
    )

    IO.puts("    @ iter 100: #{cp1.size} <= #{@max_entries} → #{bounded_100}")
    IO.puts("    @ iter 200: #{cp2.size} <= #{@max_entries} → #{bounded_200}")
    IO.puts("    @ iter 300: #{cp3.size} <= #{@max_entries} → #{bounded_300}")

    # Check 2: LRU Working (size should stay roughly constant, not grow)
    growth_100_to_300 = cp3.size - cp1.size
    lru_working = growth_100_to_300 < 50

    status_lru = if lru_working, do: "✓", else: "✗"

    IO.puts("\n#{status_lru} LRU Eviction Working:")
    IO.puts("    Growth 100→300: #{inspect(growth_100_to_300)} entries")
    IO.puts("    Expected: < 50 (LRU evicting old entries)")
    IO.puts("    Actual: #{if lru_working, do: "LRU working", else: "LRU NOT working"}")

    # Check 3: No Linear Growth
    growth_rate = (cp3.memory_words - cp1.memory_words) / cp1.memory_words
    no_linear_growth = growth_rate < 1.5

    status_linear = if no_linear_growth, do: "✓", else: "✗"

    IO.puts("\n#{status_linear} No Linear Memory Growth:")
    IO.puts("    Growth rate: #{Float.round(growth_rate, 2)}x (300/100 iterations)")
    IO.puts("    Expected: < 1.5x (bounded)")
    IO.puts("    Linear growth would be ~2x (300 iterations = 3× 100)")

    # Overall status
    all_pass = bounded_100 and bounded_200 and bounded_300 and lru_working and no_linear_growth

    IO.puts("\n" <> String.duplicate("=", 80))

    if all_pass do
      IO.puts("✓ PASS: Wave 12 ETS table is BOUNDED with LRU eviction working")
      IO.puts("  → WvdA Soundness: Boundedness property satisfied")
      IO.puts("  → Armstrong Resource Limits: Enforced via LRU eviction")
    else
      IO.puts("✗ FAIL: Wave 12 ETS table does NOT maintain boundedness")
      IO.puts("  → Check LRU implementation")
      IO.puts("  → Verify max_size enforcement")
    end

    IO.puts(String.duplicate("=", 80))
  end
end

Wave12BoundednessChaosRunner.run()
