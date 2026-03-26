defmodule Canopy.Mesh.SyncWorker do
  @moduledoc """
  Background job for periodic data mesh synchronization.

  Wakes every 5 minutes to sync mesh state from OSA, updating the local cache
  with domain registrations, entity counts, and quality scores.

  Implements Armstrong supervision: crashes escalate to supervisor, no silent errors.
  Implements WvdA soundness: all operations have timeout_ms, no infinite loops.
  """
  use GenServer

  require Logger

  alias Canopy.Mesh.Cache

  # 5 minutes
  @sync_interval_ms 5 * 60 * 1000
  @osa_timeout_ms 30_000
  @osa_base_url System.get_env("OSA_API_URL", "http://127.0.0.1:8089")

  # ── Public API ──────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_sync do
    GenServer.call(__MODULE__, :sync_now, @osa_timeout_ms + 5000)
  end

  def sync_status do
    GenServer.call(__MODULE__, :status, 5000)
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
      next_sync_ms: @sync_interval_ms
    }

    # Schedule first sync immediately
    Process.send_after(self(), :perform_sync, 100)

    {:ok, state}
  end

  @impl true
  def handle_info(:perform_sync, state) do
    Logger.debug("[Mesh.SyncWorker] Performing scheduled sync")

    case sync_from_osa() do
      {:ok, result} ->
        new_state = %{
          state
          | last_sync_at: DateTime.utc_now(),
            domains_synced: result[:domains_synced] || 0,
            entities_synced: result[:entities_synced] || 0,
            sync_errors: 0
        }

        Logger.info(
          "[Mesh.SyncWorker] Sync completed: #{result[:domains_synced]} domains, " <>
            "#{result[:entities_synced]} entities"
        )

        # Schedule next sync
        Process.send_after(self(), :perform_sync, @sync_interval_ms)
        {:noreply, new_state}

      {:error, reason} ->
        # Let-it-crash: log and escalate to supervisor
        Logger.error("[Mesh.SyncWorker] Sync failed: #{inspect(reason)}")

        new_state = %{state | sync_errors: state.sync_errors + 1}

        # Retry after shorter interval on error
        Process.send_after(self(), :perform_sync, 30_000)

        # If too many errors, raise to trigger supervisor restart
        if new_state.sync_errors >= 5 do
          raise "[Mesh.SyncWorker] Too many sync failures (#{new_state.sync_errors}), escalating"
        end

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:sync_now, _from, state) do
    Logger.info("[Mesh.SyncWorker] Manual sync requested")

    case sync_from_osa() do
      {:ok, result} ->
        new_state = %{
          state
          | last_sync_at: DateTime.utc_now(),
            domains_synced: result[:domains_synced] || 0,
            entities_synced: result[:entities_synced] || 0,
            sync_errors: 0
        }

        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        Logger.error("[Mesh.SyncWorker] Manual sync failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      last_sync_at: state[:last_sync_at],
      domains_synced: state[:domains_synced],
      entities_synced: state[:entities_synced],
      sync_errors: state[:sync_errors],
      next_sync_in_ms: @sync_interval_ms
    }

    {:reply, status, state}
  end

  # ── Private Helpers ─────────────────────────────────────────────────

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
    url = "#{@osa_base_url}/api/v1/mesh/domains"
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
    url = "#{@osa_base_url}/api/v1/mesh/discover"
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
