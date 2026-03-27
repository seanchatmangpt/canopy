defmodule Canopy.Telemetry.WeaverLiveCheck do
  @moduledoc false

  require Logger
  require OpenTelemetry.Tracer

  @doc """
  Tags the active span with `chatmangpt.run.correlation_id`.

  Always sets the attribute — no longer gated on WEAVER_LIVE_CHECK env var.
  Reads correlation ID from process dictionary, then CHATMANGPT_CORRELATION_ID env var,
  then generates a random fallback. Stores the ID in the process dictionary so
  subsequent calls within the same process share the same correlation ID.
  """
  def put_correlation_attribute do
    cid = get_or_create_correlation_id()
    OpenTelemetry.Tracer.set_attribute(:"chatmangpt.run.correlation_id", cid)
  rescue
    e ->
      Logger.warning("[WeaverLiveCheck] Failed to set correlation attribute: #{Exception.message(e)}")
      :ok
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp get_or_create_correlation_id do
    case Process.get(:chatmangpt_correlation_id) do
      nil ->
        id = System.get_env("CHATMANGPT_CORRELATION_ID") || generate_id()
        Process.put(:chatmangpt_correlation_id, id)
        id

      id ->
        id
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
