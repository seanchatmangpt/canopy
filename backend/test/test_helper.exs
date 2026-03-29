# Chicago TDD: All tests run with full application started
# No --no-start mode - tests verify real behavior, not mocks
ExUnit.start(exclude: [:weaver_e2e, :external_binary, :external_service, :integration, :chaos, :pm4py_required])

Ecto.Adapters.SQL.Sandbox.mode(Canopy.Repo, :manual)
