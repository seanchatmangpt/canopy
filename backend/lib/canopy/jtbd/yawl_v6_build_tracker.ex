defmodule Canopy.JTBD.YAWLv6BuildTracker do
  @moduledoc """
  YAWLv6 Build State Tracker — ETS-backed real build tracking.

  Maintains the latest YAWLv6 simulation/real build state in an ETS table.
  Used by runner.ex to persist state, and by dashboard.ex to display it.
  """

  @doc """
  Initialize the YAWLv6 tracker ETS table.

  Called from Canopy.Application supervision tree.
  """
  def init do
    :ets.new(:yawlv6_latest, [:set, :public, :named_table])
  end

  @doc """
  Get the current YAWLv6 build state.

  Returns the last state set via set_state/1, or nil if not yet set.
  """
  @spec get_state :: map() | nil
  def get_state do
    case :ets.lookup(:yawlv6_latest, :state) do
      [{:state, state}] -> state
      [] -> nil
    end
  end

  @doc """
  Store the current YAWLv6 build state.

  State map typically contains:
    - modules: list of module status maps
    - iteration: current iteration number
    - last_real_build_at: DateTime of last real mvnd build (nil if simulate mode)
    - mode: :simulate or :real
  """
  @spec set_state(map()) :: true
  def set_state(state) do
    :ets.insert(:yawlv6_latest, {:state, state})
  end

  @doc """
  Clear all stored state (for testing).
  """
  @spec clear :: true
  def clear do
    :ets.delete_all_objects(:yawlv6_latest)
  end
end
