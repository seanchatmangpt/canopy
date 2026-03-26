import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :canopy, Canopy.Repo,
  username: "rhl",
  password: "",
  hostname: "localhost",
  database: "canopy_test#{System.get_env("MIX_TEST_PARTITION")}",
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
config :opentelemetry, :resource,
  service: [name: "canopy", version: "1.0.0"]

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
