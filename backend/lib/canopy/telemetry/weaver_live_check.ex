defmodule Canopy.Telemetry.WeaverLiveCheck do
  @moduledoc false

  require OpenTelemetry.Tracer

  @doc """
  Tags the active span with `chatmangpt.run.correlation_id` when Weaver live-check is enabled.
  """
  def put_correlation_attribute do
    if System.get_env("WEAVER_LIVE_CHECK") == "true" do
      cid = System.get_env("CHATMANGPT_CORRELATION_ID") || ""
      OpenTelemetry.Tracer.set_attribute(:"chatmangpt.run.correlation_id", cid)
    end
  end
end
