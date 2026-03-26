import Config

# OpenTelemetry SDK configuration
config :opentelemetry,
       :tracer,
       :global

# HTTP/protobuf OTLP (collector HTTP OTLP is usually port 4318; 4317 is gRPC).
config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

# Configure OpenTelemetry Phoenix integration
config :opentelemetry_phoenix,
  sampler: {:parent_based, {:trace_id_ratio_based, 1.0}}
