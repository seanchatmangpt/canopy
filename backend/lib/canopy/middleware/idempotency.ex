defmodule Canopy.Middleware.Idempotency do
  @moduledoc """
  Idempotency middleware for Phoenix — prevents duplicate processing of requests.

  Checks for an `Idempotency-Key` header. If present and a cached response exists,
  returns the cached response immediately. Otherwise, allows the request to proceed
  and caches the response before sending.

  Usage in router:
      defmodule CanopyWeb.Router do
        pipeline :api do
          plug Canopy.Middleware.Idempotency
        end
      end

  Clients should include:
      Idempotency-Key: unique-key-per-request

  TTL: 24 hours per cached response.
  """

  require Logger

  @table :canopy_idempotency_cache
  @ttl_seconds 86_400  # 24 hours

  def init(_opts) do
    # Ensure the ETS table exists
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    []
  end

  def call(conn, _opts) do
    # Ensure table exists
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    idempotency_key = Plug.Conn.get_req_header(conn, "idempotency-key")

    case idempotency_key do
      [] ->
        # No idempotency key, proceed normally
        conn

      [key | _] when is_binary(key) ->
        # Check cache
        case get_cached(key) do
          nil ->
            # No cached response, proceed and cache the result
            cache_response(conn, key)

          cached_response ->
            # Return cached response immediately
            Logger.debug("Idempotency cache hit", key: key)

            conn
            |> Plug.Conn.send_resp(
              cached_response["status"],
              Jason.encode!(cached_response["body"])
            )
            |> Plug.Conn.halt()
        end
    end
  end

  # -- Private ----------------------------------------------------------------

  defp get_cached(key) do
    now = System.monotonic_time(:second)

    case :ets.lookup(@table, key) do
      [] ->
        nil

      [{^key, entry}] ->
        if entry["expires_at"] > now do
          entry
        else
          # Delete expired entry
          :ets.delete(@table, key)
          nil
        end
    end
  end

  defp cache_response(conn, key) do
    # Register a hook to capture the response before it's sent
    Plug.Conn.register_before_send(conn, fn response_conn ->
      case response_conn.status do
        status when status in [200, 201, 204] ->
          # Cache successful responses only
          entry = %{
            "key" => key,
            "status" => status,
            "body" => response_conn.resp_body || "",
            "stored_at" => System.monotonic_time(:second),
            "expires_at" => System.monotonic_time(:second) + @ttl_seconds
          }

          :ets.insert(@table, {key, entry})
          Logger.debug("Idempotency key cached", key: key, status: status)

        _status ->
          # Don't cache error responses
          :ok
      end

      response_conn
    end)
  end
end
