defmodule Canopy.Board.ConwayChecker do
  @moduledoc """
  Conway's Law violation detection for agent communication boundaries.

  Conway's Law: boundary_time / cycle_time > 0.4 → structural violation
  (communication patterns don't match organizational structure)

  ## WvdA Soundness
  - Pure function: no side effects, fully deterministic
  - No division by zero: cycle_time == 0 guard returns safe default
  - Output bounded: conway_score in [0.0, ∞) by construction;
    valid inputs are cycle_time > 0 so score = boundary/cycle ≥ 0
  """

  @conway_threshold 0.4

  @doc """
  Check Conway's Law for a single agent boundary.

  Returns %{is_violation: bool, conway_score: float, boundary_time_ms: integer, cycle_time_ms: integer}

  ## Examples

      iex> Canopy.Board.ConwayChecker.check(50, 100)
      %{is_violation: true, conway_score: 0.5, boundary_time_ms: 50, cycle_time_ms: 100}

      iex> Canopy.Board.ConwayChecker.check(30, 100)
      %{is_violation: false, conway_score: 0.3, boundary_time_ms: 30, cycle_time_ms: 100}

      iex> Canopy.Board.ConwayChecker.check(50, 0)
      %{is_violation: false, conway_score: 0.0, boundary_time_ms: 0, cycle_time_ms: 0}
  """
  @spec check(non_neg_integer(), non_neg_integer()) :: %{
          is_violation: boolean(),
          conway_score: float(),
          boundary_time_ms: non_neg_integer(),
          cycle_time_ms: non_neg_integer()
        }
  def check(boundary_time_ms, cycle_time_ms) when cycle_time_ms > 0 do
    conway_score = boundary_time_ms / cycle_time_ms

    %{
      is_violation: conway_score > @conway_threshold,
      conway_score: conway_score,
      boundary_time_ms: boundary_time_ms,
      cycle_time_ms: cycle_time_ms
    }
  end

  # WvdA: guard against division by zero — return safe zero-score default
  def check(_boundary_time_ms, 0) do
    %{
      is_violation: false,
      conway_score: 0.0,
      boundary_time_ms: 0,
      cycle_time_ms: 0
    }
  end
end
