defmodule Canopy.Mesh.SyncWorker do
  @moduledoc """
  Background job for periodic data mesh synchronization.

  Wakes every 5 minutes to sync mesh state from both OSA and BusinessOS,
  running both in parallel via Task.async.

  ## Armstrong Fault Tolerance

  - OSA failures escalate to supervisor after 5 consecutive errors (let-it-crash)
  - BOS failures are non-fatal: logged as :degraded, never crash the worker
  - All Task.await timeouts are inner_timeout + 5000ms (WvdA deadlock freedom)

  ## WvdA Soundness

  - All blocking operations have explicit timeout_ms
  - No infinite loops — all retries are bounded by @sync_interval_ms or 30s
  - BOS Task.await ceiling = @bos_kpi_timeout_ms + 5_000 (longest BOS call)
  """
  use GenServer

  require Logger

  alias Canopy.Mesh.Cache

  # 5 minutes
  @sync_interval_ms 5 * 60 * 1_000
  @osa_timeout_ms 30_000

  # WvdA: BOS endpoint timeouts (per plan Gap 1)
  @bos_kpi_timeout_ms 20_000

  # ── Public API ──────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_sync do
    GenServer.call(__MODULE__, :sync_now, @osa_timeout_ms + @bos_kpi_timeout_ms + 5_000)
  end

  def sync_status do
    GenServer.call(__MODULE__, :status, 5_000)
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Logger.info("[Mesh.SyncWorker] Starting background sync (interval: #{@sync_interval_ms}ms)")

    state = %{
      last_sync_at: nil,
      domains_synced: 0,
      entities_synced: 0,
      sync_errors: 0,
      next_sync_ms: @sync_interval_ms,
      last_bos_sync_at: nil,
      bos_sync_errors: 0,
      bos_status: :unknown
    }

    # Schedule first sync immediately
    Process.send_after(self(), :perform_sync, 100)

    {:ok, state}
  end

  @impl true
  def handle_info(:perform_sync, state) do
    Logger.debug("[Mesh.SyncWorker] Performing scheduled sync (OSA + BOS in parallel)")

    # Armstrong: BOS failure is non-fatal; OSA failure escalates after 5 errors
    osa_task = Task.async(fn -> sync_from_osa() end)
    bos_task = Task.async(fn -> sync_from_bos() end)

    # WvdA: outer await = inner timeout + 5000ms (deadlock freedom guarantee)
    osa_result = Task.await(osa_task, @osa_timeout_ms + 5_000)
    bos_result = Task.await(bos_task, @bos_kpi_timeout_ms + 5_000)

    new_state = apply_bos_result(state, bos_result)

    case osa_result do
      {:ok, result} ->
        new_state = %{
          new_state
          | last_sync_at: DateTime.utc_now(),
            domains_synced: result[:domains_synced] || 0,
            entities_synced: result[:entities_synced] || 0,
            sync_errors: 0
        }

        Logger.info(
          "[Mesh.SyncWorker] Sync completed: #{result[:domains_synced]} domains, " <>
            "#{result[:entities_synced]} entities, bos=#{new_state.bos_status}"
        )

        Process.send_after(self(), :perform_sync, @sync_interval_ms)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[Mesh.SyncWorker] OSA sync failed: #{inspect(reason)}")

        new_state = %{new_state | sync_errors: new_state.sync_errors + 1}

        Process.send_after(self(), :perform_sync, 30_000)

        # Armstrong: let-it-crash after 5 consecutive OSA failures
        if new_state.sync_errors >= 5 do
          raise "[Mesh.SyncWorker] Too many OSA sync failures (#{new_state.sync_errors}), escalating"
        end

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    Logger.info("[Mesh.SyncWorker] Manual sync requested")

    osa_task = Task.async(fn -> sync_from_osa() end)
    bos_task = Task.async(fn -> sync_from_bos() end)

    osa_result = Task.await(osa_task, @osa_timeout_ms + 5_000)
    bos_result = Task.await(bos_task, @bos_kpi_timeout_ms + 5_000)

    new_state = apply_bos_result(state, bos_result)

    case osa_result do
      {:ok, result} ->
        new_state = %{
          new_state
          | last_sync_at: DateTime.utc_now(),
            domains_synced: result[:domains_synced] || 0,
            entities_synced: result[:entities_synced] || 0,
            sync_errors: 0
        }

        {:reply, {:ok, Map.put(result, :bos_result, bos_result)}, new_state}

      {:error, reason} ->
        Logger.error("[Mesh.SyncWorker] Manual OSA sync failed: #{inspect(reason)}")
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      last_sync_at: state[:last_sync_at],
      domains_synced: state[:domains_synced],
      entities_synced: state[:entities_synced],
      sync_errors: state[:sync_errors],
      next_sync_in_ms: @sync_interval_ms,
      last_bos_sync_at: state[:last_bos_sync_at],
      bos_sync_errors: state[:bos_sync_errors],
      bos_status: state[:bos_status]
    }

    {:reply, status, state}
  end

  # ── Private: OSA Sync ───────────────────────────────────────────────

  defp sync_from_osa do
    Logger.debug("[Mesh.SyncWorker] Starting OSA sync")

    with {:ok, domains} <- fetch_domains_from_osa(),
         :ok <- update_cache_domains(domains),
         {:ok, entity_counts} <- fetch_entity_counts_from_osa(domains),
         :ok <- update_cache_entities(entity_counts) do
      {:ok,
       %{
         domains_synced: length(domains),
         entities_synced: Enum.sum(Enum.map(entity_counts, &(&1[:count] || 0)))
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_domains_from_osa do
    url = "#{osa_base_url()}/api/v1/mesh/domains"
    headers = build_headers()

    Logger.debug("[Mesh.SyncWorker] Fetching domains from #{url}")

    case Req.get(url, headers: headers, receive_timeout: @osa_timeout_ms) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        domains = body["domains"] || []
        Logger.debug("[Mesh.SyncWorker] Fetched #{length(domains)} domains")
        {:ok, domains}

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "[Mesh.SyncWorker] Domain fetch failed (status: #{status}): #{inspect(body)}"
        )

        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("[Mesh.SyncWorker] Domain fetch connection error: #{inspect(reason)}")
        {:error, {:connection_error, reason}}
    end
  end

  defp update_cache_domains(domains) do
    Logger.debug("[Mesh.SyncWorker] Updating cache with #{length(domains)} domains")

    Enum.each(domains, fn domain ->
      domain_name = domain["name"] || domain["domain_name"]
      owner = domain["owner"]
      tags = domain["tags"] || []

      if domain_name do
        Cache.put_domain(%{
          name: domain_name,
          owner: owner,
          tags: tags,
          cached_at: DateTime.utc_now()
        })
      end
    end)

    :ok
  end

  defp fetch_entity_counts_from_osa(domains) do
    Logger.debug("[Mesh.SyncWorker] Fetching entity counts for #{length(domains)} domains")

    counts =
      Enum.map(domains, fn domain ->
        domain_name = domain["name"] || domain["domain_name"]

        case fetch_domain_entities(domain_name) do
          {:ok, entities} ->
            %{
              domain: domain_name,
              count: length(entities)
            }

          {:error, _reason} ->
            %{
              domain: domain_name,
              count: 0
            }
        end
      end)

    {:ok, counts}
  end

  defp fetch_domain_entities(domain_name) do
    url = "#{osa_base_url()}/api/v1/mesh/discover"
    headers = build_headers()

    payload = %{
      "domain_name" => domain_name,
      "limit" => 100
    }

    case Req.post(url, json: payload, headers: headers, receive_timeout: @osa_timeout_ms) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        entities = body["entities"] || []
        {:ok, entities}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "[Mesh.SyncWorker] Entity fetch failed for #{domain_name} (status: #{status})"
        )

        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.warning(
          "[Mesh.SyncWorker] Entity fetch connection error for #{domain_name}: #{inspect(reason)}"
        )

        {:error, {:connection_error, reason}}
    end
  end

  defp update_cache_entities(entity_counts) do
    Logger.debug("[Mesh.SyncWorker] Updating entity counts: #{inspect(entity_counts)}")

    Enum.each(entity_counts, fn count ->
      Cache.put_entity_count(%{
        domain: count[:domain],
        count: count[:count],
        cached_at: DateTime.utc_now()
      })
    end)

    :ok
  end

  # ── Private: BOS Sync (non-fatal) ──────────────────────────────────

  # Armstrong: BOS failure is non-fatal — returns {:ok, _} with degraded status
  # or {:error, _} to trigger apply_bos_result degraded path.
  # All three endpoints are tried independently; partial success is acceptable.
  defp sync_from_bos do
    Logger.debug("[Mesh.SyncWorker] Starting BOS sync")

    alias Canopy.Adapters.BusinessOS

    status_result = BusinessOS.get_status()
    compliance_result = BusinessOS.get_compliance_status()
    kpis_result = BusinessOS.get_kpis()

    case status_result do
      {:ok, data} -> Cache.put_bos_status(data)
      {:error, _} -> :ok
    end

    case compliance_result do
      {:ok, data} -> Cache.put_compliance_status(data)
      {:error, _} -> :ok
    end

    case kpis_result do
      {:ok, data} -> Cache.put_kpis(data)
      {:error, _} -> :ok
    end

    bos_healthy = match?({:ok, _}, status_result)

    if bos_healthy do
      Logger.info("[Mesh.SyncWorker] BOS sync complete (healthy)")
      {:ok, %{bos_status: :healthy}}
    else
      Logger.warning(
        "[Mesh.SyncWorker] BOS sync degraded: #{inspect(status_result)}"
      )

      {:error, :bos_degraded}
    end
  end

  defp apply_bos_result(state, {:ok, result}) do
    %{
      state
      | last_bos_sync_at: DateTime.utc_now(),
        bos_sync_errors: 0,
        bos_status: result[:bos_status] || :healthy
    }
  end

  defp apply_bos_result(state, {:error, _reason}) do
    %{state | bos_sync_errors: state.bos_sync_errors + 1, bos_status: :degraded}
  end

  # ── Private: Common Helpers ─────────────────────────────────────────

  defp osa_base_url, do: Application.get_env(:canopy, :osa_url, "http://127.0.0.1:8089")

  defp build_headers do
    token = System.get_env("OSA_API_TOKEN", "")

    headers = [
      {"content-type", "application/json"},
      {"user-agent", "Canopy.Mesh.SyncWorker/1.0"}
    ]

    if token != "" do
      [{"authorization", "Bearer #{token}"} | headers]
    else
      headers
    end
  end
end
