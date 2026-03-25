import Config

# Canopy/config/weaver.exs — config for weaver live-check validation
#
# Loaded during test runs when WEAVER_LIVE_CHECK=true env var is set.
# This re-enables the OTLP batch processor (disabled in test.exs by default)
# so spans are exported to the Weaver receiver at WEAVER_OTLP_ENDPOINT.
#
# Usage:
#   WEAVER_LIVE_CHECK=true \
#   WEAVER_OTLP_ENDPOINT=http://localhost:4317 \
#   mix test

config :opentelemetry, :resource,
  service: [name: "canopy", version: "0.1.0"]

# Re-enable the batch span processor so spans are exported to Weaver.
# test.exs sets processors: [] — this overrides that to route to the live-check receiver.
config :opentelemetry,
  processors: [
    otel_batch_processor: %{
      exporter: {:opentelemetry_exporter, []}
    }
  ]

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: System.get_env("WEAVER_OTLP_ENDPOINT", "http://localhost:4317")
