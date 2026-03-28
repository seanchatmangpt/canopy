defmodule CanopyWeb.BoardController do
  @moduledoc """
  Board Chair Intelligence Controller.

  Proxies board intelligence data from OSA (port 8089) to the Canopy
  SvelteKit frontend. The frontend renders the board briefing, highlights
  structural decisions required, and allows the board chair to record decisions.

  Routes:
    GET  /api/v1/board/briefing          — fetch latest briefing from OSA
    POST /api/v1/board/decision          — record a board decision via OSA
    GET  /api/v1/board/decisions         — list recorded decisions from OSA

  WvdA: All OSA calls have explicit timeouts. Degraded state returned on failure
  (never crashes the request). Decision feedback loop closes via POST /decision.

  Armstrong: OSA unavailability shows a degraded but functional response.
  No crashes. Upstream errors surfaced clearly to the client.
  """

  use CanopyWeb, :controller

  require Logger

  @briefing_timeout_ms 10_000
  @decision_timeout_ms 10_000
  @decisions_timeout_ms 5_000

  # ── GET /api/v1/board/briefing ───────────────────────────────────────────────

  @doc """
  Fetch the current board briefing from OSA.

  Returns the latest briefing text, structural issue count, and freshness status.
  If OSA is unavailable, returns a degraded response with `osa_available: false`.
  """
  def briefing(conn, _params) do
    case Req.get("#{osa_url()}/api/v1/board/briefing",
           headers: osa_headers(conn),
           receive_timeout: @briefing_timeout_ms
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        json(conn, %{
          osa_available: true,
          text: Map.get(body, "text", ""),
          generated_at: Map.get(body, "generated_at"),
          l3_freshness: Map.get(body, "l3_freshness", "unknown"),
          structural_issue_count: Map.get(body, "structural_issue_count", 0),
          has_structural_issues: Map.get(body, "has_structural_issues", false)
        })

      {:ok, %{status: 404, body: body}} ->
        message = Map.get(body, "error", "No briefing generated yet")

        conn
        |> put_status(404)
        |> json(%{
          osa_available: true,
          error: message,
          hint: Map.get(body, "hint", "Run BriefingGenerator.generate/0 in OSA")
        })

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[BoardController] OSA returned HTTP #{status} for /board/briefing")

        conn
        |> put_status(502)
        |> json(%{
          osa_available: false,
          error: "OSA returned unexpected status",
          osa_status: status,
          osa_body: body
        })

      {:error, reason} ->
        Logger.warning(
          "[BoardController] OSA unreachable for /board/briefing: #{inspect(reason)}"
        )

        conn
        |> put_status(503)
        |> json(%{
          osa_available: false,
          error: "OSA unavailable",
          reason: inspect(reason),
          hint: "Ensure OSA is running at #{osa_url()}"
        })
    end
  end

  # ── POST /api/v1/board/decision ──────────────────────────────────────────────

  @doc """
  Record a board chair decision via OSA.

  Body: {"department": "Engineering", "decision_type": "reorganize", "notes": "..."}
  Valid decision_types: reorganize | add_liaison | accept_constraint

  Returns the recorded decision confirmation from OSA.
  """
  def record_decision(conn, params) do
    department = Map.get(params, "department", "")
    decision_type = Map.get(params, "decision_type", "")
    notes = Map.get(params, "notes", "")

    cond do
      department == "" ->
        conn
        |> put_status(400)
        |> json(%{error: "department is required"})

      decision_type not in ["reorganize", "add_liaison", "accept_constraint"] ->
        conn
        |> put_status(400)
        |> json(%{
          error: "invalid decision_type",
          valid_types: ["reorganize", "add_liaison", "accept_constraint"]
        })

      true ->
        body = %{
          "department" => department,
          "decision_type" => decision_type,
          "notes" => notes
        }

        case Req.post("#{osa_url()}/api/v1/board/decision",
               json: body,
               headers: osa_headers(conn),
               receive_timeout: @decision_timeout_ms
             ) do
          {:ok, %{status: 200, body: resp_body}} ->
            Logger.info(
              "[BoardController] Decision recorded: dept=#{department} type=#{decision_type}"
            )

            json(conn, Map.put(resp_body, "osa_available", true))

          {:ok, %{status: status, body: resp_body}} ->
            Logger.warning("[BoardController] OSA returned HTTP #{status} for /board/decision")

            conn
            |> put_status(502)
            |> json(%{
              osa_available: false,
              error: "OSA returned unexpected status",
              osa_status: status,
              osa_body: resp_body
            })

          {:error, reason} ->
            Logger.warning(
              "[BoardController] OSA unreachable for /board/decision: #{inspect(reason)}"
            )

            conn
            |> put_status(503)
            |> json(%{
              osa_available: false,
              error: "OSA unavailable",
              reason: inspect(reason)
            })
        end
    end
  end

  # ── GET /api/v1/board/decisions ──────────────────────────────────────────────

  @doc """
  List recorded board decisions from OSA.

  Returns a list of decisions with department, type, notes, and recorded_at.
  Returns empty list if OSA is unavailable (degraded, not error).
  """
  def list_decisions(conn, _params) do
    case Req.get("#{osa_url()}/api/v1/board/decisions",
           headers: osa_headers(conn),
           receive_timeout: @decisions_timeout_ms
         ) do
      {:ok, %{status: 200, body: decisions}} when is_list(decisions) ->
        json(conn, %{
          osa_available: true,
          decisions: decisions,
          count: length(decisions)
        })

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # OSA may return a wrapped response
        decisions = Map.get(body, "decisions", [])

        json(conn, %{
          osa_available: true,
          decisions: decisions,
          count: length(decisions)
        })

      {:ok, %{status: status}} ->
        Logger.warning("[BoardController] OSA returned HTTP #{status} for /board/decisions")

        conn
        |> put_status(502)
        |> json(%{
          osa_available: false,
          error: "OSA returned unexpected status",
          osa_status: status,
          decisions: []
        })

      {:error, reason} ->
        Logger.warning(
          "[BoardController] OSA unreachable for /board/decisions: #{inspect(reason)}"
        )

        # Degraded: return empty list, not error — board UI still renders
        json(conn, %{
          osa_available: false,
          decisions: [],
          count: 0,
          hint: "OSA unavailable: #{inspect(reason)}"
        })
    end
  end

  # ── Private Helpers ──────────────────────────────────────────────────────────

  defp osa_url, do: Application.get_env(:canopy, :osa_url, "http://127.0.0.1:8089")

  defp osa_headers(conn) do
    base = [
      {"Content-Type", "application/json"},
      {"X-Correlation-ID", get_correlation_id(conn)}
    ]

    inject_traceparent(base)
  end

  defp get_correlation_id(conn) do
    case Plug.Conn.get_req_header(conn, "x-correlation-id") do
      [id | _] -> id
      [] -> :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    end
  end

  defp inject_traceparent(headers) do
    :otel_propagator_text_map.inject(headers, fn c, k, v -> [{k, v} | c] end)
  rescue
    _ -> headers
  end
end
