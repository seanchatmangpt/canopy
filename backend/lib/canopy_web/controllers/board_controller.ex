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
  @intelligence_timeout_ms 10_000

  @bos_intelligence_table :canopy_bos_intelligence

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

  # ── POST /api/v1/bos/intelligence ────────────────────────────────────────────

  @doc """
  Receive board intelligence from BusinessOS and forward to OSA.

  Body: {"health_summary": 0.9, "conformance_score": 0.85, "top_risk": "...",
         "conway_violations": 0, "case_count": 42, "handoff_count": 10, "source": "business_os"}

  Validated fields: health_summary [0,1], conformance_score [0,1],
                    top_risk (non-empty string), conway_violations (int ≥ 0).

  On success: forwards to OSA POST /api/v1/board/intelligence and stores in ETS.
  On OSA unavailable: stores in ETS, returns 202 Accepted (degraded, not error).
  On invalid payload: returns 422 Unprocessable Entity.
  """
  def ingest_intelligence(conn, params) do
    with {:ok, intel} <- validate_intelligence(params) do
      # Store in ETS immediately (single-row overwrite, bounded memory).
      received_at = DateTime.utc_now() |> DateTime.to_iso8601()
      ets_payload = Map.merge(intel, %{
        "intelligence_source" => "business_os",
        "intelligence_received_at" => received_at
      })
      if :ets.whereis(@bos_intelligence_table) != :undefined do
        :ets.insert(@bos_intelligence_table, {:latest, ets_payload})
      end

      # Forward to OSA — degraded if unavailable (Armstrong: let-it-continue).
      osa_body = Map.merge(intel, %{
        "intelligence_source" => "business_os",
        "intelligence_received_at" => received_at
      })

      case Req.post("#{osa_url()}/api/v1/board/intelligence",
             json: osa_body,
             headers: osa_headers(conn),
             receive_timeout: @intelligence_timeout_ms
           ) do
        {:ok, %{status: status}} when status in [200, 201, 202] ->
          Logger.info("[BoardController] Intelligence forwarded to OSA, status=#{status}")

          conn
          |> put_status(200)
          |> json(%{
            status: "accepted",
            intelligence_source: "business_os",
            osa_available: true
          })

        {:ok, %{status: status, body: body}} ->
          Logger.warning("[BoardController] OSA returned HTTP #{status} for /board/intelligence")

          conn
          |> put_status(202)
          |> json(%{
            status: "stored",
            intelligence_source: "business_os",
            osa_available: false,
            osa_status: status,
            hint: inspect(body)
          })

        {:error, reason} ->
          Logger.warning("[BoardController] OSA unreachable for intelligence push: #{inspect(reason)}")

          conn
          |> put_status(202)
          |> json(%{
            status: "stored",
            intelligence_source: "business_os",
            osa_available: false,
            reason: inspect(reason)
          })
      end
    else
      {:error, errors} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: errors})
    end
  end

  # ── GET /api/v1/bos/intelligence ─────────────────────────────────────────────

  @doc "Return the latest cached intelligence from ETS."
  def bos_intelligence_status(conn, _params) do
    result =
      if :ets.whereis(@bos_intelligence_table) != :undefined do
        case :ets.lookup(@bos_intelligence_table, :latest) do
          [{:latest, payload}] -> %{available: true, payload: payload}
          [] -> %{available: false, hint: "No intelligence received yet"}
        end
      else
        %{available: false, hint: "ETS table not initialised"}
      end

    json(conn, result)
  end

  # ── Private Helpers ──────────────────────────────────────────────────────────

  defp validate_intelligence(params) do
    errors = []

    errors =
      case Map.get(params, "health_summary") do
        v when is_number(v) and v >= 0 and v <= 1 -> errors
        nil -> ["health_summary is required" | errors]
        _ -> ["health_summary must be a float in [0, 1]" | errors]
      end

    errors =
      case Map.get(params, "conformance_score") do
        v when is_number(v) and v >= 0 and v <= 1 -> errors
        nil -> ["conformance_score is required" | errors]
        _ -> ["conformance_score must be a float in [0, 1]" | errors]
      end

    errors =
      case Map.get(params, "top_risk") do
        v when is_binary(v) and byte_size(v) > 0 -> errors
        nil -> ["top_risk is required" | errors]
        _ -> ["top_risk must be a non-empty string" | errors]
      end

    errors =
      case Map.get(params, "conway_violations") do
        v when is_integer(v) and v >= 0 -> errors
        nil -> ["conway_violations is required" | errors]
        _ -> ["conway_violations must be a non-negative integer" | errors]
      end

    if errors == [] do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

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
