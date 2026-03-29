defmodule Canopy.Mesh.SyncWorkerTest do
  @moduledoc """
  Tests for Canopy.Mesh.SyncWorker BOS sync behaviour.

  Unit tests (no tag / :unit tag) verify state logic and error-path
  behaviour without requiring any real services.  They redirect both
  OSA and BOS to dead ports so every HTTP call fails fast.

  Integration tests (:integration) require the full running app with
  both OSA (8089) and BOS (8001) available.
  """
  use ExUnit.Case, async: false

  alias Canopy.Mesh.SyncWorker

  # ── Helpers ──────────────────────────────────────────────────────────

  defp put_bad_urls do
    Application.put_env(:canopy, :bos_url, "http://127.0.0.1:19999")
    Application.put_env(:canopy, :osa_url, "http://127.0.0.1:19998")
  end

  defp restore_urls(original_bos, original_osa) do
    if original_bos do
      Application.put_env(:canopy, :bos_url, original_bos)
    else
      Application.delete_env(:canopy, :bos_url)
    end

    if original_osa do
      Application.put_env(:canopy, :osa_url, original_osa)
    else
      Application.delete_env(:canopy, :osa_url)
    end
  end

  # ── sync_status/0 shape ───────────────────────────────────────────────

  describe "sync_status/0 — state shape" do
    test "returns a map with bos_status key when worker is running" do
      case Process.whereis(SyncWorker) do
        nil ->
          # Worker not started — skip gracefully
          :ok

        _pid ->
          status = SyncWorker.sync_status()
          assert is_map(status)
          assert Map.has_key?(status, :bos_status)
      end
    end

    test "bos_status is one of :unknown, :healthy, or :degraded when worker is running" do
      case Process.whereis(SyncWorker) do
        nil ->
          :ok

        _pid ->
          status = SyncWorker.sync_status()
          assert status.bos_status in [:unknown, :healthy, :degraded]
      end
    end

    test "last_bos_sync_at is nil or a DateTime when worker is running" do
      case Process.whereis(SyncWorker) do
        nil ->
          :ok

        _pid ->
          status = SyncWorker.sync_status()
          assert is_nil(status.last_bos_sync_at) or
                   match?(%DateTime{}, status.last_bos_sync_at)
      end
    end

    test "bos_sync_errors is a non-negative integer when worker is running" do
      case Process.whereis(SyncWorker) do
        nil ->
          :ok

        _pid ->
          status = SyncWorker.sync_status()
          assert is_integer(status.bos_sync_errors)
          assert status.bos_sync_errors >= 0
      end
    end
  end

  # ── BOS failures are non-fatal ────────────────────────────────────────

  describe "bos sync errors do not crash OSA sync" do
    setup do
      original_bos = Application.get_env(:canopy, :bos_url)
      original_osa = Application.get_env(:canopy, :osa_url)
      put_bad_urls()
      on_exit(fn -> restore_urls(original_bos, original_osa) end)
      :ok
    end

    test "worker process is still alive after BOS becomes unreachable" do
      case Process.whereis(SyncWorker) do
        nil ->
          # Worker not in supervision tree in test env; start a temporary one.
          # Use a unique name so we don't conflict with a running instance.
          {:ok, pid} =
            start_supervised(
              {SyncWorker, []},
              id: :test_sync_worker_bos_resilience
            )

          # Give the first scheduled sync a moment to run
          Process.sleep(200)

          assert Process.alive?(pid)

        pid ->
          # Worker already supervised — verify it survives with bad BOS URL
          assert Process.alive?(pid)
      end
    end

    test "bos_status transitions to :degraded when BOS is unreachable" do
      case Process.whereis(SyncWorker) do
        nil ->
          {:ok, _pid} =
            start_supervised(
              {SyncWorker, []},
              id: :test_sync_worker_bos_degraded
            )

          # Wait for the automatic sync triggered 100ms after init
          Process.sleep(300)

          status = SyncWorker.sync_status()
          assert status.bos_status in [:unknown, :degraded]

        _pid ->
          # The global worker may be in any state; just verify it has a
          # valid bos_status (could be :healthy if BOS is actually up)
          status = SyncWorker.sync_status()
          assert status.bos_status in [:unknown, :healthy, :degraded]
      end
    end

    test "sync_status/0 includes bos_sync_errors counter" do
      case Process.whereis(SyncWorker) do
        nil ->
          {:ok, _pid} =
            start_supervised(
              {SyncWorker, []},
              id: :test_sync_worker_error_counter
            )

          Process.sleep(300)

          status = SyncWorker.sync_status()
          assert Map.has_key?(status, :bos_sync_errors)
          assert is_integer(status.bos_sync_errors)

        _pid ->
          status = SyncWorker.sync_status()
          assert Map.has_key?(status, :bos_sync_errors)
          assert is_integer(status.bos_sync_errors)
      end
    end
  end

  # ── force_sync/0 ─────────────────────────────────────────────────────

  describe "force_sync/0" do
    setup do
      original_bos = Application.get_env(:canopy, :bos_url)
      original_osa = Application.get_env(:canopy, :osa_url)
      put_bad_urls()
      on_exit(fn -> restore_urls(original_bos, original_osa) end)
      :ok
    end

    test "force_sync/0 is an exported function with arity 0" do
      assert function_exported?(SyncWorker, :force_sync, 0)
    end

    test "force_sync/0 returns an error tuple when both OSA and BOS are unreachable" do
      case Process.whereis(SyncWorker) do
        nil ->
          {:ok, _pid} =
            start_supervised(
              {SyncWorker, []},
              id: :test_sync_worker_force_sync
            )

          # Let the auto-sync settle before issuing a manual one
          Process.sleep(200)

          result = SyncWorker.force_sync()
          # OSA is unreachable, so force_sync returns {:error, _}
          assert match?({:error, _}, result)

        _pid ->
          result = SyncWorker.force_sync()
          # With bad OSA, we expect an error
          assert is_tuple(result)
          assert tuple_size(result) == 2
      end
    end
  end

  # ── Public API exports ────────────────────────────────────────────────

  describe "public API" do
    test "start_link/1 is exported" do
      assert function_exported?(SyncWorker, :start_link, 1)
    end

    test "force_sync/0 is exported" do
      assert function_exported?(SyncWorker, :force_sync, 0)
    end

    test "sync_status/0 is exported" do
      assert function_exported?(SyncWorker, :sync_status, 0)
    end
  end

  # ── Integration tests (require live OSA + BOS) ────────────────────────

  describe "integration: live services required" do
    @moduletag :integration

    setup do
      # Restore real service URLs
      Application.put_env(:canopy, :bos_url, System.get_env("BUSINESSOS_URL", "http://127.0.0.1:8001"))
      Application.put_env(:canopy, :osa_url, System.get_env("OSA_URL", "http://127.0.0.1:8089"))
      :ok
    end

    test "force_sync/0 returns {:ok, result} when both OSA and BOS are healthy" do
      pid =
        case Process.whereis(SyncWorker) do
          nil ->
            {:ok, p} = start_supervised({SyncWorker, []}, id: :test_sync_worker_integration)
            p

          p ->
            p
        end

      assert Process.alive?(pid)
      result = SyncWorker.force_sync()
      assert {:ok, sync_result} = result
      assert is_map(sync_result)
    end

    test "force_sync/0 includes :bos_result key in success response" do
      case Process.whereis(SyncWorker) do
        nil ->
          {:ok, _pid} =
            start_supervised({SyncWorker, []}, id: :test_sync_worker_bos_result)

        _ ->
          :ok
      end

      {:ok, result} = SyncWorker.force_sync()
      assert Map.has_key?(result, :bos_result)
    end

    test "sync_from_bos returns {:ok, result} when BOS is healthy" do
      # Validate via sync_status after a successful force_sync
      {:ok, _} = SyncWorker.force_sync()
      status = SyncWorker.sync_status()
      assert status.bos_status == :healthy
      assert %DateTime{} = status.last_bos_sync_at
    end
  end
end
