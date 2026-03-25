import Config

# OpenTelemetry SDK configuration
config :opentelemetry,
  :tracer,
  :global

# Configure OpenTelemetry exporter to send traces to Jaeger/OTLP collector
config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "http://localhost:4317"

# Configure OpenTelemetry Phoenix integration
config :opentelemetry_phoenix,
  sampler: {:parent_based, {:trace_id_ratio_based, 1.0}}
