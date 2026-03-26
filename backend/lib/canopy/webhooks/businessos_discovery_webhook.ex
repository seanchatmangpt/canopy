defmodule Canopy.Webhooks.BusinessosDiscoveryWebhook do
  @moduledoc """
  Handles incoming webhooks from BusinessOS discovery completion events.

  When a process discovery completes in BusinessOS, it POSTs to this webhook handler,
  which creates an Issue in Canopy and automatically dispatches it to the
  process-mining-monitor agent.

  Webhook Format:
    POST /api/v1/hooks/:webhook_id
    {
      "model_id": "uuid",
      "algorithm": "heuristics|inductive|alphabetic",
      "activities_count": 42,
      "fitness_score": 0.95
    }

  Behavior:
  - Idempotent: duplicate POSTs with same model_id create only 1 issue
  - On error: returns 500 (lets BusinessOS retry)
  - On success: returns 200 with issue_id and agent_id
  """

  require Logger
  alias Canopy.Repo
  alias Canopy.Schemas.{Issue, Workspace, Agent}

  @doc """
  Process a discovery completion webhook from BusinessOS.

  Returns:
    {:ok, %{issue_id: uuid, agent_id: uuid}} on success
    {:error, reason} on failure
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
             is_number(fitness_score) do
    with {:ok, _workspace} <- fetch_workspace(workspace_id),
         {:ok, issue} <-
           create_or_get_issue(workspace_id, model_id, algorithm, activities_count, fitness_score),
         {:ok, agent} <- fetch_process_mining_agent(workspace_id),
         {:ok, _assigned} <- Canopy.Work.assign_issue(issue, agent.id) do
      Logger.info(
        "[BusinessOS Webhook] Discovery complete — issue=#{issue.id} agent=#{agent.id} model=#{model_id}"
      )

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

  # ─────────────────────────────────────────────────────────────────────────────
  # Private
  # ─────────────────────────────────────────────────────────────────────────────

  defp fetch_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      nil -> {:error, :workspace_not_found}
      ws -> {:ok, ws}
    end
  end

  defp create_or_get_issue(workspace_id, model_id, algorithm, _activities_count, _fitness_score) do
    # Check if we already have an issue for this model (idempotency)
    case Repo.get_by(Issue, workspace_id: workspace_id, description: model_id) do
      %Issue{} = existing ->
        {:ok, existing}

      nil ->
        # Create new issue with model data in description
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
end
