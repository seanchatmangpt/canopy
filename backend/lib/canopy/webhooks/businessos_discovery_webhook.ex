defmodule Canopy.Webhooks.BusinessosDiscoveryWebhook do
  @moduledoc """
  Handles incoming webhooks from BusinessOS discovery completion events.

  When a process discovery completes in BusinessOS, it POSTs to this webhook handler,
  which creates an Issue in Canopy and automatically dispatches it to the
  process-mining-monitor agent.

  ## Webhook Format

      POST /api/v1/hooks/:webhook_id
      {
        "model_id": "uuid",
        "algorithm": "heuristics|inductive|alphabetic",
        "activities_count": 42,
        "fitness_score": -1.0   # -1.0 = not-yet-computed sentinel; [0,1] = actual fitness
      }

  ## Behavior

  - Idempotent: duplicate POSTs with same model_id create only 1 issue
  - fitness_score >= -1.0 is accepted (-1.0 is the not-yet-computed sentinel from BOS)
  - Writes discovery result to Oxigraph L0 (non-blocking, non-fatal)
  - Signals OSA inference chain to re-materialize L1-L3 (non-blocking, non-fatal)
  - On error: returns `{:error, reason}` (caller returns 500 → BusinessOS retries)
  - On success: returns `{:ok, %{issue_id: uuid, agent_id: uuid}}`
  """

  require Logger

  alias Canopy.Repo
  alias Canopy.Schemas.{Issue, Workspace, Agent}
  alias Canopy.OCPM.OxigraphWriter

  @osa_url Application.compile_env(:canopy, :osa_url, "http://127.0.0.1:8089")
  @osa_invalidate_timeout_ms 5_000

  @doc """
  Process a discovery completion webhook from BusinessOS.

  Returns:
    `{:ok, %{issue_id: uuid, agent_id: uuid}}` on success
    `{:error, reason}` on failure
  """
  @spec handle_discovery_complete(workspace_id :: binary, payload :: map) ::
          {:ok, map} | {:error, term}
  def handle_discovery_complete(workspace_id, %{
        "model_id" => model_id,
        "algorithm" => algorithm,
        "activities_count" => activities_count,
        "fitness_score" => fitness_score
      })
      when is_binary(model_id) and is_binary(algorithm) and is_integer(activities_count) and
             is_number(fitness_score) and fitness_score >= -1.0 do
    with {:ok, _workspace} <- fetch_workspace(workspace_id),
         {:ok, issue} <-
           create_or_get_issue(workspace_id, model_id, algorithm, activities_count, fitness_score),
         {:ok, agent} <- fetch_process_mining_agent(workspace_id),
         {:ok, _assigned} <- Canopy.Work.assign_issue(issue, agent.id) do
      Logger.info(
        "[BusinessOS Webhook] Discovery complete — issue=#{issue.id} agent=#{agent.id} model=#{model_id}"
      )

      # Write to Oxigraph L0 (non-blocking, non-fatal — Armstrong let-it-crash boundary)
      Task.start(fn ->
        metadata = %{
          algorithm: algorithm,
          fitness: fitness_score,
          activities_count: activities_count
        }

        case OxigraphWriter.write_discovery_result(model_id, "unknown", metadata) do
          {:ok, _} ->
            Logger.debug("[BusinessOS Webhook] L0 triple written for model=#{model_id}")

          {:error, :oxigraph_unavailable} ->
            Logger.warning("[BusinessOS Webhook] Oxigraph unavailable — L0 sync deferred")
        end
      end)

      # Signal OSA to re-materialize L1-L3 (non-blocking, non-fatal)
      Task.start(fn ->
        url = "#{osa_url()}/api/v1/ontology/inference-chain/invalidate"

        case Req.post(url,
               json: %{"from_level" => "l0"},
               receive_timeout: @osa_invalidate_timeout_ms
             ) do
          {:ok, %{status: 200}} ->
            Logger.debug("[BusinessOS Webhook] OSA inference chain invalidated from L0")

          other ->
            Logger.warning(
              "[BusinessOS Webhook] OSA inference chain invalidation failed: #{inspect(other)}"
            )
        end
      end)

      {:ok, %{issue_id: issue.id, agent_id: agent.id}}
    else
      {:error, reason} ->
        Logger.warning("[BusinessOS Webhook] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def handle_discovery_complete(_workspace_id, payload) do
    Logger.warning("[BusinessOS Webhook] Invalid payload: #{inspect(payload)}")
    {:error, :invalid_payload}
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp fetch_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      nil -> {:error, :workspace_not_found}
      ws -> {:ok, ws}
    end
  end

  defp create_or_get_issue(workspace_id, model_id, algorithm, _activities_count, _fitness_score) do
    case Repo.get_by(Issue, workspace_id: workspace_id, description: model_id) do
      %Issue{} = existing ->
        {:ok, existing}

      nil ->
        attrs = %{
          title: "Process Model: #{algorithm}",
          description: model_id,
          status: "backlog",
          priority: "high",
          workspace_id: workspace_id
        }

        case Canopy.Work.create_issue(attrs) do
          {:ok, issue} ->
            Logger.info("[BusinessOS Webhook] Created issue=#{issue.id} for model=#{model_id}")
            {:ok, issue}

          error ->
            error
        end
    end
  end

  defp fetch_process_mining_agent(workspace_id) do
    case Repo.get_by(Agent, workspace_id: workspace_id, slug: "process-mining-monitor") do
      nil ->
        Logger.warning(
          "[BusinessOS Webhook] Agent 'process-mining-monitor' not found in workspace=#{workspace_id}"
        )

        {:error, :agent_not_found}

      agent ->
        {:ok, agent}
    end
  end

  defp osa_url do
    Application.get_env(:canopy, :osa_url, @osa_url)
  end
end
