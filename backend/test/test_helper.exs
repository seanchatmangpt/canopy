ExUnit.start(exclude: [:weaver_e2e, :integration, :external_binary, :external_service])

Ecto.Adapters.SQL.Sandbox.mode(Canopy.Repo, :manual)
