defmodule CanopyWeb.MeshController do
  @moduledoc """
  Phoenix controller for data mesh operations.

  Supports domain registration, discovery, lineage queries, and data quality
  checks via integration with OSA's mesh consumer.

  All operations are stateless and delegate to the OSA API.
  """
  use CanopyWeb, :controller

  require Logger

  @osa_timeout 30_000

  # ── Domain Registration ──────────────────────────────────────────────

  def register_domain(conn, params) do
    domain_name = params["domain_name"]
    owner = params["owner"]
    tags = params["tags"] || []
    description = params["description"] || ""

    cond do
      is_nil(domain_name) ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{domain_name: "required"}})

      is_nil(owner) ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{owner: "required"}})

      true ->
        payload = %{
          domain_name: domain_name,
          owner: owner,
          tags: tags,
          description: description,
          registered_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case call_osa_mesh("/mesh/domains/register", payload) do
          {:ok, response} ->
            Logger.info("[Mesh] Domain registered: #{domain_name}")

            conn
            |> put_status(201)
            |> json(%{
              domain: response
            })

          {:error, status, error_body} ->
            Logger.error("[Mesh] Domain registration failed: #{domain_name} (status: #{status})")

            conn
            |> put_status(status)
            |> json(%{error: "registration_failed", details: error_body})

          {:error, reason} ->
            Logger.error("[Mesh] Domain registration error: #{inspect(reason)}")

            conn
            |> put_status(503)
            |> json(%{error: "service_unavailable", reason: inspect(reason)})
        end
    end
  end

  # ── Data Discovery ──────────────────────────────────────────────────

  def discover(conn, params) do
    domain_name = params["domain_name"]
    entity_type = params["entity_type"] || ""
    limit = String.to_integer(params["limit"] || "100")
    offset = String.to_integer(params["offset"] || "0")

    cond do
      is_nil(domain_name) ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{domain_name: "required"}})

      limit > 1000 ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{limit: "maximum 1000"}})

      true ->
        payload = %{
          domain_name: domain_name,
          entity_type: entity_type,
          limit: limit,
          offset: offset
        }

        case call_osa_mesh("/mesh/discover", payload) do
          {:ok, response} ->
            Logger.info("[Mesh] Discovery completed: #{domain_name}, #{entity_type}")

            conn
            |> put_status(200)
            |> json(%{
              entities: response["entities"] || [],
              total: response["total"] || 0,
              domain: domain_name
            })

          {:error, status, error_body} ->
            Logger.error("[Mesh] Discovery failed: #{domain_name} (status: #{status})")

            conn
            |> put_status(status)
            |> json(%{error: "discovery_failed", details: error_body})

          {:error, reason} ->
            Logger.error("[Mesh] Discovery error: #{inspect(reason)}")

            conn
            |> put_status(503)
            |> json(%{error: "service_unavailable", reason: inspect(reason)})
        end
    end
  end

  # ── Data Lineage ────────────────────────────────────────────────────

  def lineage(conn, params) do
    entity_id = params["entity_id"]
    direction = params["direction"] || "both"
    depth = String.to_integer(params["depth"] || "3")

    cond do
      is_nil(entity_id) ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{entity_id: "required"}})

      direction not in ["upstream", "downstream", "both"] ->
        conn
        |> put_status(400)
        |> json(%{
          error: "validation_failed",
          details: %{direction: "must be upstream, downstream, or both"}
        })

      depth < 0 or depth > 10 ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{depth: "must be 0-10"}})

      true ->
        payload = %{
          entity_id: entity_id,
          direction: direction,
          depth: depth
        }

        case call_osa_mesh("/mesh/lineage", payload) do
          {:ok, response} ->
            Logger.info("[Mesh] Lineage computed: #{entity_id} (#{direction}, depth: #{depth})")

            conn
            |> put_status(200)
            |> json(%{
              entity_id: entity_id,
              lineage: response["lineage"] || %{},
              upstream: response["upstream"] || [],
              downstream: response["downstream"] || [],
              depth_reached: response["depth_reached"] || 0
            })

          {:error, status, error_body} ->
            Logger.error("[Mesh] Lineage computation failed: #{entity_id} (status: #{status})")

            conn
            |> put_status(status)
            |> json(%{error: "lineage_failed", details: error_body})

          {:error, reason} ->
            Logger.error("[Mesh] Lineage error: #{inspect(reason)}")

            conn
            |> put_status(503)
            |> json(%{error: "service_unavailable", reason: inspect(reason)})
        end
    end
  end

  # ── Data Quality ────────────────────────────────────────────────────

  def quality(conn, params) do
    entity_id = params["entity_id"]
    checks = params["checks"] || []

    cond do
      is_nil(entity_id) ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{entity_id: "required"}})

      not is_list(checks) ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: %{checks: "must be an array"}})

      true ->
        payload = %{
          entity_id: entity_id,
          checks: checks,
          evaluated_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        case call_osa_mesh("/mesh/quality", payload) do
          {:ok, response} ->
            Logger.info("[Mesh] Quality checks completed: #{entity_id}")

            conn
            |> put_status(200)
            |> json(%{
              entity_id: entity_id,
              checks_passed: response["checks_passed"] || 0,
              checks_failed: response["checks_failed"] || 0,
              total_checks: response["total_checks"] || 0,
              results: response["results"] || [],
              quality_score: response["quality_score"] || 0.0
            })

          {:error, status, error_body} ->
            Logger.error("[Mesh] Quality check failed: #{entity_id} (status: #{status})")

            conn
            |> put_status(status)
            |> json(%{error: "quality_check_failed", details: error_body})

          {:error, reason} ->
            Logger.error("[Mesh] Quality check error: #{inspect(reason)}")

            conn
            |> put_status(503)
            |> json(%{error: "service_unavailable", reason: inspect(reason)})
        end
    end
  end

  # ── Cache Status ────────────────────────────────────────────────────

  def cache_status(conn, _params) do
    case call_osa_mesh("/mesh/cache/status", %{}) do
      {:ok, response} ->
        conn
        |> put_status(200)
        |> json(%{
          cache_enabled: response["cache_enabled"] || false,
          domains_cached: response["domains_cached"] || 0,
          entities_cached: response["entities_cached"] || 0,
          last_sync: response["last_sync"],
          ttl_seconds: response["ttl_seconds"] || 3600
        })

      {:error, status, error_body} ->
        Logger.error("[Mesh] Cache status failed (status: #{status})")

        conn
        |> put_status(status)
        |> json(%{error: "cache_status_failed", details: error_body})

      {:error, reason} ->
        Logger.error("[Mesh] Cache status error: #{inspect(reason)}")

        conn
        |> put_status(503)
        |> json(%{error: "service_unavailable", reason: inspect(reason)})
    end
  end

  # ── Cache Invalidation ──────────────────────────────────────────────

  def invalidate_cache(conn, params) do
    domain_name = params["domain_name"]
    entity_id = params["entity_id"]

    payload =
      %{}
      |> maybe_put("domain_name", domain_name)
      |> maybe_put("entity_id", entity_id)

    case call_osa_mesh("/mesh/cache/invalidate", payload) do
      {:ok, _response} ->
        Logger.info("[Mesh] Cache invalidated: domain=#{domain_name}, entity=#{entity_id}")

        conn
        |> put_status(200)
        |> json(%{ok: true})

      {:error, status, error_body} ->
        Logger.error("[Mesh] Cache invalidation failed (status: #{status})")

        conn
        |> put_status(status)
        |> json(%{error: "invalidation_failed", details: error_body})

      {:error, reason} ->
        Logger.error("[Mesh] Cache invalidation error: #{inspect(reason)}")

        conn
        |> put_status(503)
        |> json(%{error: "service_unavailable", reason: inspect(reason)})
    end
  end

  # ── Private Helpers ─────────────────────────────────────────────────

  defp call_osa_mesh(path, payload) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{System.get_env("OSA_API_TOKEN", "")}"}
    ]

    url = "#{Application.get_env(:canopy, :osa_url, "http://127.0.0.1:8089")}#{path}"

    case Req.post(url, json: payload, headers: headers, receive_timeout: @osa_timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, status, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
