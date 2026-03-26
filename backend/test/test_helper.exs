ExUnit.start(exclude: [:weaver_e2e])

# Only set up Ecto sandbox if the repo is started
if Process.whereis(Canopy.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(Canopy.Repo, :manual)
end
