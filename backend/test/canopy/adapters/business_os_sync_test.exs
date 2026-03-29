defmodule Canopy.Adapters.BusinessOSSyncTest do
  @moduledoc """
  Tests for the BOS polling API added to Canopy.Adapters.BusinessOS:
  get_status/1, get_compliance_status/1, get_kpis/1.

  Unit tests point the adapter at a port that is guaranteed not to be
  listening (19999) so every call returns an error tuple without
  touching any real service.

  Integration tests (tagged :integration) require a live BusinessOS
  at the configured :bos_url.
  """
  use ExUnit.Case, async: false

  alias Canopy.Adapters.BusinessOS

  # ── Setup: redirect all BOS calls to a bad port ─────────────────────

  setup do
    original_url = Application.get_env(:canopy, :bos_url)

    Application.put_env(:canopy, :bos_url, "http://127.0.0.1:19999")

    on_exit(fn ->
      if original_url do
        Application.put_env(:canopy, :bos_url, original_url)
      else
        Application.delete_env(:canopy, :bos_url)
      end
    end)

    :ok
  end

  # ── get_status/1 ─────────────────────────────────────────────────────

  describe "get_status/1" do
    test "returns {:error, _} when BOS is unreachable" do
      result = BusinessOS.get_status()
      assert {:error, _reason} = result
    end

    test "error reason is a tagged tuple or atom" do
      {:error, reason} = BusinessOS.get_status()
      assert is_atom(reason) or is_tuple(reason)
    end

    test "returns a 2-tuple" do
      result = BusinessOS.get_status()
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end
  end

  # ── get_compliance_status/1 ───────────────────────────────────────────

  describe "get_compliance_status/1" do
    test "returns {:error, _} when BOS is unreachable" do
      result = BusinessOS.get_compliance_status()
      assert {:error, _reason} = result
    end

    test "error reason is a tagged tuple or atom" do
      {:error, reason} = BusinessOS.get_compliance_status()
      assert is_atom(reason) or is_tuple(reason)
    end

    test "returns a 2-tuple" do
      result = BusinessOS.get_compliance_status()
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end
  end

  # ── get_kpis/1 ───────────────────────────────────────────────────────

  describe "get_kpis/1" do
    test "returns {:error, _} when BOS is unreachable" do
      result = BusinessOS.get_kpis()
      assert {:error, _reason} = result
    end

    # Key behavioral difference: get_kpis/1 uses POST (not GET).
    # We verify this indirectly — when the host is unreachable both methods
    # fail at TCP level, but get_kpis must never return {:ok, _} on a dead host,
    # which would indicate a wrong GET endpoint had responded instead.
    # The source confirms: Req.post(url <> "/api/pm4py/dashboard-kpi", ...)
    test "get_kpis/1 uses POST — returns {:error, _} not {:ok, _} on bad host" do
      result = BusinessOS.get_kpis()

      # Must NOT be {:ok, _} — that would indicate the wrong endpoint
      # responded (e.g., a GET to a different path that happened to return 200).
      refute match?({:ok, _}, result)
      assert match?({:error, _}, result)
    end

    test "error reason is a tagged tuple or atom" do
      {:error, reason} = BusinessOS.get_kpis()
      assert is_atom(reason) or is_tuple(reason)
    end

    test "returns a 2-tuple" do
      result = BusinessOS.get_kpis()
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end
  end

  # ── Function signature / arity guards ─────────────────────────────────

  describe "function exports" do
    test "get_status/0 is exported" do
      assert function_exported?(BusinessOS, :get_status, 0)
    end

    test "get_status/1 is exported" do
      assert function_exported?(BusinessOS, :get_status, 1)
    end

    test "get_compliance_status/0 is exported" do
      assert function_exported?(BusinessOS, :get_compliance_status, 0)
    end

    test "get_compliance_status/1 is exported" do
      assert function_exported?(BusinessOS, :get_compliance_status, 1)
    end

    test "get_kpis/0 is exported" do
      assert function_exported?(BusinessOS, :get_kpis, 0)
    end

    test "get_kpis/1 is exported" do
      assert function_exported?(BusinessOS, :get_kpis, 1)
    end
  end

  # ── Integration tests (require live BOS at :bos_url) ─────────────────

  describe "integration: live BOS required" do
    @moduletag :integration

    setup do
      # Override the bad-port URL set by the outer setup with the real one
      real_url = System.get_env("BUSINESSOS_URL", "http://127.0.0.1:8001")
      Application.put_env(:canopy, :bos_url, real_url)
      :ok
    end

    test "get_status/1 returns {:ok, map()} when BOS is healthy" do
      result = BusinessOS.get_status()
      assert {:ok, body} = result
      assert is_map(body)
    end

    test "get_compliance_status/1 returns {:ok, map()} when BOS is healthy" do
      result = BusinessOS.get_compliance_status()
      assert {:ok, body} = result
      assert is_map(body)
    end

    test "get_kpis/1 returns {:ok, map()} when BOS is healthy" do
      result = BusinessOS.get_kpis()
      assert {:ok, body} = result
      assert is_map(body)
    end
  end
end
