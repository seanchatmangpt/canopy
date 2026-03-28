ExUnit.start(exclude: [:weaver_e2e, :integration, :external_binary, :external_service])

if Process.whereis(Canopy.Repo) != nil do
  Ecto.Adapters.SQL.Sandbox.mode(Canopy.Repo, :manual)
end
