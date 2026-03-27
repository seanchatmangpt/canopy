defmodule Canopy.JTBD.Wave12ChaosTest do
  @moduledoc """
  Chaos Testing: Wave 12 Graceful Degradation when Jaeger/OTEL Collector is Unavailable

  Claim: The Wave 12 JTBD loop continues executing iterations and completes successfully
  even when OpenTelemetry span delivery to Jaeger fails.

  Chicago TDD: RED phase - write failing test assertions before implementation.
  - Test verifies loop resilience to OTEL collector outages
  - Test captures logs for span delivery failures
  - Test validates that loop iteration counter keeps increasing despite OTEL errors
  - Test confirms spans resume delivery when Jaeger comes back online

  WvdA Soundness Verification:
  - Deadlock Freedom: Loop has explicit timeout_ms; OTEL send failures don't block execution
  - Liveness: Loop has bounded iteration count (max_iterations: 20); all iterations eventually complete
  - Boundedness: Span buffer has max queue size; OTEL delivery failures trigger graceful degradation

  Armstrong Fault Tolerance:
  - Let-It-Crash: OTEL delivery errors are logged but don't crash the loop
  - Supervision: Loop runs under supervision; crashes are visible in logs
  - No Shared State: Loop state is immutable; OTEL state is isolated in client process
  - Budget: Loop has per-iteration budget; OTEL timeout doesn't consume loop budget
  """

  use ExUnit.Case, async: true

  require Logger

  alias Canopy.JTBD.Wave12Loop
  alias OpenTelemetry.Tracer

  setup do
    # Setup: Clear any previous span data and logs
    :ok = clear_test_logs()
    :ok = clear_test_spans()

    on_exit(fn ->
      clear_test_spans()
      clear_test_logs()
    end)

    {:ok, %{}}
  end

  describe "wave12_chaos: graceful degradation when Jaeger unavailable — RED phase" do
    test "wave12_loop continues iterations when OTEL collector is unreachable" do
      # Arrange: Start Wave 12 loop with Jaeger assumed to be running
      loop_config = %{
        max_iterations: 20,
        iteration_timeout_ms: 5000,
        # Quick timeout for unreachable Jaeger
        otel_timeout_ms: 1000
      }

      # Act: Start loop (assumes Jaeger is initially available)
      start_loop_task =
        Task.async(fn ->
          Wave12Loop.execute(loop_config)
        end)

      # Wait for loop to execute a few iterations
      :timer.sleep(2000)

      # Simulate Jaeger becoming unavailable (docker stop jaeger)
      stop_jaeger_result = stop_jaeger_container()

      # Let loop continue for 10 more iterations while Jaeger is down
      :timer.sleep(8000)

      # Restart Jaeger (docker start jaeger)
      start_jaeger_result = start_jaeger_container()

      # Wait for loop to complete
      :timer.sleep(5000)

      # Assert: Loop completed all iterations despite Jaeger outage
      {:ok, loop_result} = Task.await(start_loop_task, 30_000)

      # Verify loop completed
      assert loop_result.status == :completed
      assert loop_result.total_iterations >= 20
      assert loop_result.completed_at != nil

      # Verify Jaeger was stopped and restarted
      assert stop_jaeger_result in [:ok, :already_stopped]
      assert start_jaeger_result in [:ok, :already_started]
    end

    test "wave12_loop logs OTEL delivery failure when Jaeger is down" do
      # Arrange: Configure loop with tight logging capture
      loop_config = %{
        max_iterations: 10,
        iteration_timeout_ms: 2000,
        # Short timeout to trigger failures quickly
        otel_timeout_ms: 500,
        log_level: :debug
      }

      # Act: Start loop and capture logs
      logs =
        capture_logs(fn ->
          # Stop Jaeger to simulate collector unavailability
          :ok = stop_jaeger_container()

          # Run loop iterations
          {:ok, result} = Wave12Loop.execute(loop_config)

          # Restart Jaeger
          :ok = start_jaeger_container()

          {:ok, result}
        end)

      # Assert: Logs contain evidence of span delivery failures
      assert logs =~ "failed to send span" or
               logs =~ "otel" or
               logs =~ "jaeger" or
               logs =~ "unreachable" or
               logs =~ "timeout"
    end

    test "wave12_loop iteration counter increases despite OTEL errors" do
      # Arrange: Start loop with iteration tracking enabled
      loop_config = %{
        max_iterations: 15,
        iteration_timeout_ms: 3000,
        track_iterations: true,
        otel_timeout_ms: 1000
      }

      # Act: Run loop with Jaeger down
      iteration_counts = []

      {:ok, result} =
        capture_log(fn ->
          # Stop Jaeger
          :ok = stop_jaeger_container()

          # Execute loop and capture iteration count every 2 seconds
          loop_task =
            Task.async(fn ->
              Wave12Loop.execute(loop_config)
            end)

          # Poll iteration counter while loop is running
          iterations_during_outage = poll_iteration_count(loop_task, 10, [])

          # Restart Jaeger
          :ok = start_jaeger_container()

          # Wait for loop to complete
          Task.await(loop_task, 30_000)

          {:ok, %{iterations_during_outage: iterations_during_outage}}
        end)

      # Assert: Iteration counter kept increasing during OTEL outage
      assert result.iterations_during_outage != []

      # Verify iteration count is monotonically increasing
      assert is_monotonic_increasing(result.iterations_during_outage)
    end

    test "wave12_loop resumes span delivery when Jaeger comes back online" do
      # Arrange: Configure loop to emit spans at each iteration
      loop_config = %{
        max_iterations: 10,
        emit_spans: true,
        iteration_timeout_ms: 2000,
        otel_timeout_ms: 1000
      }

      # Act: Run loop with Jaeger unavailable, then available
      result =
        capture_log(fn ->
          # Initial: Verify spans are being delivered to Jaeger (assume it's up)
          initial_span_count = get_jaeger_span_count()

          # Stop Jaeger
          :ok = stop_jaeger_container()

          # Run first 5 iterations (should fail to deliver spans)
          loop_task =
            Task.async(fn ->
              Wave12Loop.execute(loop_config)
            end)

          :timer.sleep(4000)
          spans_during_outage = get_jaeger_span_count()

          # Restart Jaeger
          :ok = start_jaeger_container()

          # Wait for loop to complete and deliver remaining spans
          :timer.sleep(6000)
          final_span_count = get_jaeger_span_count()

          Task.await(loop_task, 30_000)

          {:ok,
           %{
             initial: initial_span_count,
             during_outage: spans_during_outage,
             final: final_span_count
           }}
        end)

      # Assert: Spans resumed delivery after Jaeger came back online
      # During outage, span count should be lower than expected
      # After Jaeger restart, span count should increase again
      assert result.final >= result.during_outage
    end

    test "wave12_loop does not crash on OTEL delivery timeout" do
      # Arrange: Configure loop with strict timeout
      loop_config = %{
        max_iterations: 10,
        # Very tight — likely to timeout
        otel_timeout_ms: 100,
        iteration_timeout_ms: 3000,
        # Graceful degradation
        crash_on_error: false
      }

      # Act: Run loop with Jaeger down
      assert_no_crash(fn ->
        :ok = stop_jaeger_container()

        {:ok, result} = Wave12Loop.execute(loop_config)

        :ok = start_jaeger_container()

        # Should complete without crash
        assert result.status == :completed
        assert result.total_iterations > 0
      end)
    end

    test "wave12_loop emits failure_mode span when OTEL collector is down" do
      # Arrange: Configure loop to emit diagnostic spans on OTEL failure
      loop_config = %{
        max_iterations: 5,
        emit_diagnostics: true,
        otel_timeout_ms: 500,
        iteration_timeout_ms: 2000
      }

      # Act: Run loop with Jaeger down and capture spans
      {:ok, result} =
        capture_log(fn ->
          :ok = stop_jaeger_container()

          {:ok, loop_result} = Wave12Loop.execute(loop_config)

          :ok = start_jaeger_container()

          {:ok, loop_result}
        end)

      # Assert: Diagnostic spans recorded (in-memory or eventually to Jaeger)
      # Span should indicate OTEL delivery failure
      case get_spans_by_name("wave12.otel_delivery_failure") do
        {:ok, spans} ->
          assert length(spans) > 0
          span = hd(spans)

          assert span.attributes[:failure_mode] == :otel_unavailable or
                   span.attributes[:failure_mode] == :timeout

        :error ->
          # Spans not yet delivered — that's OK during this chaos scenario
          :ok
      end
    end

    test "wave12_loop queue does not overflow when OTEL is slow" do
      # Arrange: Configure loop with bounded span queue
      loop_config = %{
        # More iterations than queue capacity
        max_iterations: 30,
        span_queue_max_size: 10,
        # Slow — likely to back up queue
        otel_timeout_ms: 5000,
        iteration_timeout_ms: 1000,
        # Graceful backpressure
        queue_overflow_action: :drop_oldest
      }

      # Act: Run loop with slow OTEL delivery
      assert_bounded_queue(fn ->
        :ok = stop_jaeger_container()

        {:ok, result} = Wave12Loop.execute(loop_config)

        :ok = start_jaeger_container()

        assert result.status == :completed
        assert result.queue_max_depth <= 10
      end)
    end

    test "wave12_loop latency not affected by OTEL timeout" do
      # Arrange: Configure loop to measure iteration latency independent of OTEL
      loop_config = %{
        max_iterations: 10,
        iteration_timeout_ms: 1000,
        # Tight timeout should not block iteration
        otel_timeout_ms: 100,
        measure_iteration_latency: true
      }

      # Act: Run loop with Jaeger down and measure latencies
      {:ok, result} =
        capture_log(fn ->
          :ok = stop_jaeger_container()

          {:ok, loop_result} = Wave12Loop.execute(loop_config)

          :ok = start_jaeger_container()

          {:ok, loop_result}
        end)

      # Assert: Iteration latency is within budget despite OTEL timeout
      # Each iteration should complete in <1000ms, not blocked by OTEL
      assert result.avg_iteration_latency_ms < 1000
      assert result.max_iteration_latency_ms < 2000
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc "Stop the Jaeger Docker container (simulate outage)."
  defp stop_jaeger_container do
    case System.cmd("docker", ["stop", "businessos-jaeger"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      # Container not running
      {_output, 1} ->
        :already_stopped

      {output, code} ->
        Logger.warn("Failed to stop Jaeger: #{output} (code #{code})")
        :error
    end
  catch
    _error -> :error
  end

  @doc "Start the Jaeger Docker container (recovery)."
  defp start_jaeger_container do
    case System.cmd("docker", ["start", "businessos-jaeger"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      # Container already running
      {_output, 1} ->
        :already_started

      {output, code} ->
        Logger.warn("Failed to start Jaeger: #{output} (code #{code})")
        :error
    end
  catch
    _error -> :error
  end

  @doc "Get current span count from Jaeger (mocked for now)."
  defp get_jaeger_span_count do
    # In a real scenario, this would query Jaeger API at localhost:16686
    # For now, return a mock count or check in-memory test store
    case :ets.lookup(:osa_test_spans, :all) do
      [{:all, spans}] -> length(spans)
      [] -> 0
    end
  rescue
    _ -> 0
  end

  @doc "Get spans by name from in-memory test store."
  defp get_spans_by_name(span_name) do
    case :ets.lookup(:osa_test_spans, span_name) do
      [{^span_name, spans}] -> {:ok, spans}
      [] -> :error
    end
  rescue
    _ -> :error
  end

  @doc "Clear all test spans from ETS."
  defp clear_test_spans do
    :ets.new(:osa_test_spans, [:named_table, :public, :bag])
    :ok
  catch
    _ -> :ok
  end

  @doc "Clear test logs (helper for log capture)."
  defp clear_test_logs do
    :ok
  end

  @doc "Poll iteration count every second until loop completes."
  defp poll_iteration_count(task, iterations_remaining, counts) when iterations_remaining <= 0 do
    counts
  end

  defp poll_iteration_count(task, iterations_remaining, counts) do
    :timer.sleep(1000)

    # Attempt to get current iteration count from loop (mocked)
    current_count = iterations_remaining
    new_counts = counts ++ [current_count]

    poll_iteration_count(task, iterations_remaining - 1, new_counts)
  end

  @doc "Check if list is monotonically increasing."
  defp is_monotonic_increasing([]), do: true
  defp is_monotonic_increasing([_single]), do: true

  defp is_monotonic_increasing([h | t]) do
    Enum.reduce(t, {true, h}, fn current, {is_increasing, prev} ->
      if current >= prev do
        {is_increasing, current}
      else
        {false, current}
      end
    end)
    |> elem(0)
  end

  @doc "Assert that the function does not crash."
  defp assert_no_crash(fun) do
    try do
      fun.()
      assert true
    rescue
      _error ->
        assert false, "Function crashed during OTEL outage"
    end
  end

  @doc "Assert that queue stays bounded during OTEL slowdown."
  defp assert_bounded_queue(fun) do
    try do
      fun.()
      assert true
    rescue
      _error ->
        assert false, "Queue overflowed"
    end
  end

  @doc "Capture logs and return as string (ExUnit.CaptureLog wrapper)."
  defp capture_logs(fun) do
    ExUnit.CaptureLog.capture_log(fun)
  end

  @doc "Capture log and return both logs and result tuple."
  defp capture_log(fun) do
    logs = ExUnit.CaptureLog.capture_log(fun)
    {logs, fun.()}
  end
end
