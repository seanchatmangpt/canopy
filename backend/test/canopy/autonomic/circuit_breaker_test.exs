defmodule Canopy.Autonomic.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias Canopy.Autonomic.CircuitBreaker

  setup do
    CircuitBreaker.init()
    on_exit(fn -> :ets.delete_all_objects(:canopy_circuit_breaker) end)
    :ok
  end

  describe "state transitions" do
    test "three_failures_open_circuit" do
      service = :test_service_open

      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)

      assert CircuitBreaker.state(service) == :open
    end

    test "open_circuit_rejects_without_cooldown" do
      service = :test_service_reject

      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)

      assert CircuitBreaker.state(service) == :open

      result = CircuitBreaker.call(service, fn -> :should_not_run end, 1_000)

      assert result == {:error, :circuit_open}
    end

    test "half_open_success_closes_circuit" do
      service = :test_service_half_open

      # Open the circuit by recording 3 failures
      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)

      assert CircuitBreaker.state(service) == :open

      # Manually insert a :half_open row to bypass the 60s cooldown
      :ets.insert(:canopy_circuit_breaker, {service, :half_open, 0, nil})

      assert CircuitBreaker.state(service) == :half_open

      # One success must close the circuit
      CircuitBreaker.record_success(service)

      assert CircuitBreaker.state(service) == :closed
    end
  end

  describe "reset/1" do
    test "reset/1 clears circuit state" do
      service = :test_service_reset

      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)
      CircuitBreaker.record_failure(service)

      assert CircuitBreaker.state(service) == :open

      CircuitBreaker.reset(service)

      assert CircuitBreaker.state(service) == :closed
    end
  end

  describe "call/3" do
    test "call/3 executes function when circuit closed" do
      service = :test_service_call_closed

      result = CircuitBreaker.call(service, fn -> {:ok, :executed} end, 1_000)

      assert result == {:ok, :executed}
    end

    test "call/3 returns {:error, :timeout} on slow function" do
      service = :test_service_call_timeout

      result =
        CircuitBreaker.call(
          service,
          fn ->
            Process.sleep(500)
            :too_late
          end,
          50
        )

      assert result == {:error, :timeout}
    end
  end
end
