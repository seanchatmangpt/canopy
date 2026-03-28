defmodule CanopyWeb.ProcessMiningController do
  @moduledoc """
  Process Mining Controller — proxies to BusinessOS (port 8001).

  Routes:
    GET  /api/v1/process-mining/kpis     — BusinessOS POST /api/pm4py/dashboard-kpi
    POST /api/v1/process-mining/discover — BusinessOS POST /api/bos/discover
    GET  /api/v1/process-mining/status   — BusinessOS GET /api/bos/status

  WvdA: all BOS calls have explicit timeouts. Returns `businessos_available: false`
  on BOS downtime — never crashes the request. Frontend degrades gracefully.

  Armstrong: BOS unavailability is surfaced clearly; no silent swallowing.
  """

  use CanopyWeb, :controller

  require Logger

  @kpi_timeout_ms 25_000
  @discover_timeout_ms 60_000
  @status_timeout_ms 10_000

  # ── GET /api/v1/process-mining/kpis ─────────────────────────────────────────

  @doc """
  Fetch process mining KPIs from BusinessOS.

  Proxies to POST /api/pm4py/dashboard-kpi (POST because BOS expects a body).
  Returns `businessos_available: false` if BOS is down.
  """
  def kpis(conn, params) do
    body = Map.take(params, ["workspace_id", "department", "time_range"])

    case Req.post(bos_url("/api/pm4py/dashboard-kpi"),
           json: body,
           receive_timeout: @kpi_timeout_ms,
           retry: false
         ) do
      {:ok, %{status: 200, body: bos_body}} when is_map(bos_body) ->
        json(conn, Map.merge(%{businessos_available: true}, bos_body))

      {:ok, %{status: status, body: bos_body}} ->
        Logger.warning("[ProcessMiningController] BOS KPIs returned #{status}")

        conn
        |> put_status(status)
        |> json(%{
          businessos_available: true,
          error: Map.get(bos_body, "error", "upstream_error"),
          status: status
        })

      {:error, reason} ->
        Logger.warning("[ProcessMiningController] BOS unavailable for KPIs: #{inspect(reason)}")

        json(conn, %{
          businessos_available: false,
          avg_cycle_time_hours: nil,
          conformance_score: nil,
          active_cases: nil,
          bottleneck_activity: nil,
          error: "BusinessOS unavailable"
        })
    end
  end

  # ── POST /api/v1/process-mining/discover ────────────────────────────────────

  @doc """
  Trigger process discovery via BusinessOS.

  Proxies to POST /api/bos/discover. Accepts `log_path` and `algorithm` in body.
  Long timeout (60s) — pm4py-rust discovery can be slow for large logs.
  """
  def discover(conn, params) do
    body =
      params
      |> Map.take(["log_path", "algorithm", "workspace_id"])
      |> Map.put_new("algorithm", "alpha")

    case Req.post(bos_url("/api/bos/discover"),
           json: body,
           receive_timeout: @discover_timeout_ms,
           retry: false
         ) do
      {:ok, %{status: 200, body: bos_body}} when is_map(bos_body) ->
        json(conn, Map.merge(%{businessos_available: true}, bos_body))

      {:ok, %{status: 202, body: bos_body}} ->
        conn
        |> put_status(202)
        |> json(Map.merge(%{businessos_available: true}, bos_body))

      {:ok, %{status: status, body: bos_body}} ->
        Logger.warning("[ProcessMiningController] BOS discover returned #{status}")

        conn
        |> put_status(status)
        |> json(%{
          businessos_available: true,
          error: Map.get(bos_body, "error", "upstream_error")
        })

      {:error, reason} ->
        Logger.warning("[ProcessMiningController] BOS unavailable for discover: #{inspect(reason)}")

        conn
        |> put_status(503)
        |> json(%{
          businessos_available: false,
          error: "BusinessOS unavailable"
        })
    end
  end

  # ── GET /api/v1/process-mining/status ───────────────────────────────────────

  @doc """
  Fetch BusinessOS discovery engine status.

  Proxies to GET /api/bos/status. Returns degraded status if BOS is down.
  """
  def status(conn, _params) do
    case Req.get(bos_url("/api/bos/status"),
           receive_timeout: @status_timeout_ms,
           retry: false
         ) do
      {:ok, %{status: 200, body: bos_body}} when is_map(bos_body) ->
        json(conn, Map.merge(%{businessos_available: true}, bos_body))

      {:ok, %{status: status, body: bos_body}} ->
        conn
        |> put_status(status)
        |> json(%{
          businessos_available: true,
          status: Map.get(bos_body, "status", "unknown"),
          error: Map.get(bos_body, "error")
        })

      {:error, reason} ->
        Logger.warning("[ProcessMiningController] BOS unavailable for status: #{inspect(reason)}")

        json(conn, %{
          businessos_available: false,
          status: "unavailable",
          error: "BusinessOS unavailable"
        })
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp bos_url(path) do
    base = Application.get_env(:canopy, :bos_url, "http://127.0.0.1:8001")
    base <> path
  end
end
