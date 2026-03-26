defmodule Canopy.JTBD.Scenarios.Scenario10 do
  @moduledoc """
  Scenario 10: Conformance Drift - GREEN phase implementation

  Calculates Petri net fitness with OTEL instrumentation.
  """

  require Logger

  @doc """
  Execute scenario 10: Conformance drift detection

  Returns {:ok, result} or {:error, reason}
  """
  @spec execute(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(conformance_params, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 3000)
    start_time = System.monotonic_time(:millisecond)

    event_log = Map.get(conformance_params, "event_log", %{events: []})
    model = Map.get(conformance_params, "model", %{places: [], transitions: [], arcs: []})

    case Canopy.JTBD.ConformanceDrift.calculate_fitness(event_log, model) do
      {:ok, fitness_result} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        if elapsed > timeout_ms do
          {:error, :timeout}
        else
          {:ok,
           %{
             fitness_score: fitness_result.fitness_score,
             precision: fitness_result.precision,
             recall: fitness_result.recall,
             status: "ok",
             outcome: :success,
             duration_ms: elapsed
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
