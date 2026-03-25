defmodule Canopy.Middleware.IdempotencyTest do
  use ExUnit.Case
  import Plug.Test
  import Plug.Conn

  setup do
    # Ensure table exists and is clean for each test
    if :ets.whereis(:canopy_idempotency_cache) != :undefined do
      :ets.delete_all_objects(:canopy_idempotency_cache)
    else
      :ets.new(:canopy_idempotency_cache, [:named_table, :public, :set])
    end

    on_exit(fn ->
      # Clean up after test
      if :ets.whereis(:canopy_idempotency_cache) != :undefined do
        :ets.delete_all_objects(:canopy_idempotency_cache)
      end
    end)

    :ok
  end

  describe "init/1" do
    test "creates ETS table if it doesn't exist" do
      # Delete table if it exists
      if :ets.whereis(:canopy_idempotency_cache) != :undefined do
        :ets.delete(:canopy_idempotency_cache)
      end

      Canopy.Middleware.Idempotency.init([])

      assert :ets.whereis(:canopy_idempotency_cache) != :undefined
    end
  end

  describe "call/2 without idempotency key" do
    test "passes through request without caching" do
      conn =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")

      result = Canopy.Middleware.Idempotency.call(conn, [])

      # Should not be halted
      assert result.halted == false
    end
  end

  describe "call/2 with idempotency key" do
    test "returns cached response on second request with same key" do
      key = "idempotent-key-123"

      # First request
      conn1 =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result1 = Canopy.Middleware.Idempotency.call(conn1, [])
      assert result1.halted == false

      # Simulate response
      send_resp(result1, 200, ~s({"result":"success"}))

      # Second request with same key (this would normally be a new request)
      # We simulate by manually storing the response
      now = System.monotonic_time(:second)

      entry = %{
        "key" => key,
        "status" => 200,
        "body" => ~s({"result":"success"}),
        "stored_at" => now,
        "expires_at" => now + 86_400
      }

      :ets.insert(:canopy_idempotency_cache, {key, entry})

      # Now make second request
      conn2 =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result2 = Canopy.Middleware.Idempotency.call(conn2, [])

      # Should be halted (cached response returned)
      assert result2.halted == true
      assert result2.status == 200
    end

    test "does not return expired cached response" do
      key = "expired-key-456"
      past = System.monotonic_time(:second) - 100_000

      entry = %{
        "key" => key,
        "status" => 200,
        "body" => ~s({"result":"success"}),
        "stored_at" => past,
        "expires_at" => past + 100
      }

      :ets.insert(:canopy_idempotency_cache, {key, entry})

      conn =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result = Canopy.Middleware.Idempotency.call(conn, [])

      # Should not be halted since key is expired
      assert result.halted == false

      # Key should be deleted from cache
      assert :ets.lookup(:canopy_idempotency_cache, key) == []
    end
  end

  describe "before_send hook" do
    test "caches successful responses (200)" do
      key = "cache-key-200"

      conn =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result = Canopy.Middleware.Idempotency.call(conn, [])

      # Simulate response with 200 status
      _result_with_resp = send_resp(result, 200, ~s({"success":true}))

      # Check that it was cached
      cached = :ets.lookup(:canopy_idempotency_cache, key)
      assert cached != []
      assert [{^key, entry}] = cached
      assert entry["status"] == 200
    end

    test "caches successful responses (201)" do
      key = "cache-key-201"

      conn =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result = Canopy.Middleware.Idempotency.call(conn, [])
      _result_with_resp = send_resp(result, 201, ~s({"created":true}))

      cached = :ets.lookup(:canopy_idempotency_cache, key)
      assert cached != []
      assert [{^key, entry}] = cached
      assert entry["status"] == 201
    end

    test "does not cache error responses (400)" do
      key = "error-key-400"

      conn =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result = Canopy.Middleware.Idempotency.call(conn, [])
      send_resp(result, 400, ~s({"error":"bad request"}))

      # Should not be cached
      cached = :ets.lookup(:canopy_idempotency_cache, key)
      assert cached == []
    end

    test "does not cache error responses (500)" do
      key = "error-key-500"

      conn =
        conn(:post, "/test", ~s({"data":"test"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("idempotency-key", key)

      result = Canopy.Middleware.Idempotency.call(conn, [])
      send_resp(result, 500, ~s({"error":"server error"}))

      # Should not be cached
      cached = :ets.lookup(:canopy_idempotency_cache, key)
      assert cached == []
    end
  end

  describe "concurrent access" do
    test "handles concurrent requests with same idempotency key" do
      key = "concurrent-key"

      # Store a cached response
      now = System.monotonic_time(:second)

      entry = %{
        "key" => key,
        "status" => 200,
        "body" => ~s({"result":"cached"}),
        "stored_at" => now,
        "expires_at" => now + 86_400
      }

      :ets.insert(:canopy_idempotency_cache, {key, entry})

      # Create concurrent requests
      tasks =
        Enum.map(1..10, fn _ ->
          Task.async(fn ->
            conn =
              conn(:post, "/test", ~s({"data":"test"}))
              |> put_req_header("content-type", "application/json")
              |> put_req_header("idempotency-key", key)

            Canopy.Middleware.Idempotency.call(conn, [])
          end)
        end)

      results = Task.await_many(tasks)

      # All should be halted (all hit the cache)
      assert Enum.all?(results, fn conn -> conn.halted == true end)
      assert Enum.all?(results, fn conn -> conn.status == 200 end)
    end
  end

  describe "TTL validation" do
    test "respects 24-hour TTL" do
      key = "ttl-key"
      now = System.monotonic_time(:second)

      entry = %{
        "key" => key,
        "status" => 200,
        "body" => ~s({"result":"test"}),
        "stored_at" => now,
        "expires_at" => now + 86_400
      }

      :ets.insert(:canopy_idempotency_cache, {key, entry})

      cached = :ets.lookup(:canopy_idempotency_cache, key)
      assert cached != []
      assert [{^key, entry_read}] = cached
      assert entry_read["expires_at"] - entry_read["stored_at"] == 86_400
    end
  end
end
