base_excludes = [:weaver_e2e, :integration, :external_binary, :external_service]

# When running with --no-start, also exclude tests that need the application
excludes =
  if Process.whereis(Canopy.Repo) == nil do
    base_excludes ++ [:requires_application]
  else
    base_excludes
  end

ExUnit.start(exclude: excludes)

if Process.whereis(Canopy.Repo) != nil do
  Ecto.Adapters.SQL.Sandbox.mode(Canopy.Repo, :manual)
end
