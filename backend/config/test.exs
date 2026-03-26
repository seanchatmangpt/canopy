import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Local dev defaults (user `rhl`); CI overrides via POSTGRES_* / DATABASE_* (see .github/workflows/weaver-live-check.yml).
db_user = System.get_env("POSTGRES_USER") || System.get_env("DATABASE_USER") || "rhl"
db_pass = System.get_env("POSTGRES_PASSWORD") || System.get_env("DATABASE_PASSWORD") || ""
db_host = System.get_env("POSTGRES_HOST") || System.get_env("DATABASE_HOST") || "localhost"
db_base = System.get_env("POSTGRES_DB") || "canopy_test"
db_name = "#{db_base}#{System.get_env("MIX_TEST_PARTITION") || ""}"

config :canopy, Canopy.Repo,
  username: db_user,
  password: db_pass,
  hostname: db_host,
  database: db_name,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :canopy, CanopyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hGWbjAGuPwUJwljbt0gus/fwEUhHa4lP5D980bnFfGh6aI8+VoVsGCmsPETBq/0T",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# OpenTelemetry (test): no export by default — avoids connection errors to :4317 when no collector.
# Weaver live-check: gRPC OTLP to WEAVER_OTLP_ENDPOINT (same receiver as OSA / pm4py-rust).
config :opentelemetry, :resource, service: [name: "canopy", version: "1.0.0"]

config :opentelemetry, tracer: :global

if System.get_env("WEAVER_LIVE_CHECK") == "true" do
  config :opentelemetry,
    traces_exporter: :otlp,
    processors: [
      otel_simple_processor: %{
        exporter: {:opentelemetry_exporter, %{}}
      }
    ]

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_endpoint: System.get_env("WEAVER_OTLP_ENDPOINT", "http://localhost:4317")
else
  config :opentelemetry,
    traces_exporter: :none,
    processors: [
      otel_batch_processor: %{
        exporter: {:opentelemetry_exporter, %{}}
      }
    ]
end
