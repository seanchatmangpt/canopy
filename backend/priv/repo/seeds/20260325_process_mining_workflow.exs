# Process Mining Workflow — Agent & Webhook Seed
#
# Seeds a "Process Mining Monitor" agent and associates it with the
# BusinessOS discovery webhook. When BusinessOS discovery completes,
# the webhook fires, creates an issue, and dispatches this agent.
#
# Idempotent: safe to re-run. Existing records are skipped or updated.
#
# Run with:
#   mix run priv/repo/seeds/20260325_process_mining_workflow.exs
#
# After seeding, set CANOPY_WEBHOOK_URL in BusinessOS .env:
#   CANOPY_WEBHOOK_URL=http://localhost:9089/api/v1/hooks/<webhook_id>
# (The webhook ID is printed at the end of this script.)

alias Canopy.Repo
alias Canopy.Schemas.{Workspace, Agent, Webhook}

IO.puts("\n=== Seeding Process Mining Workflow ===\n")

# ---------------------------------------------------------------------------
# 1. Workspace
# ---------------------------------------------------------------------------

IO.puts("[1/3] Workspace...")

workspace_attrs = %{
  name: "Process Mining",
  path: Path.expand("~/.canopy/process-mining"),
  status: "active"
}

workspace =
  case Repo.get_by(Workspace, name: "Process Mining") do
    nil ->
      %Workspace{}
      |> Workspace.changeset(workspace_attrs)
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("    \"Process Mining\" (#{workspace.id})")

# ---------------------------------------------------------------------------
# 2. Agent: Process Mining Monitor
# ---------------------------------------------------------------------------

IO.puts("[2/3] Agent...")

agent_attrs = %{
  workspace_id: workspace.id,
  slug: "process-mining-monitor",
  name: "Process Mining Monitor",
  role: "process_miner",
  adapter: "osa",
  model: "openai/gpt-oss-20b",
  status: "idle",
  avatar_emoji: "⛏️",
  trigger: :manual,
  config: %{
    "url" => "http://localhost:9089",
    "provider" => "groq",
    "working_dir" => workspace.path
  },
  system_prompt: """
  You analyze process discovery models from BusinessOS.

  When you receive a model from BusinessOS, you will get:
  - model_id: unique identifier for the discovered model
  - algorithm: discovery algorithm used (heuristics, inductive, alphabetic)
  - activities_count: number of unique activities in the model
  - fitness_score: how well the model fits the event log (-1.0 = pending, 0-1 = actual)

  ## Your Tasks
  1. **Validate Model Quality**
     - fitness_score ≥ 0.85: strong fitness
     - fitness_score 0.70-0.85: acceptable fitness
     - fitness_score < 0.70: needs investigation
     - fitness_score == -1.0: model is freshly discovered, fitness not yet computed

  2. **Analyze Model Structure**
     - Count process flows (paths through the model)
     - Identify bottlenecks and decision points
     - Check for sound structure (no deadlocks)

  3. **Generate Report**
     - Summary of model quality
     - Key metrics and insights
     - Recommendations for process improvement
     - Any anomalies detected

  4. **Store Analysis**
     - Write report to workspace output/ directory
     - Name: discovery-{model_id}-{algorithm}-{timestamp}.md
     - Include model metadata and quality assessment
  """
}

agent =
  case Repo.get_by(Agent, workspace_id: workspace.id, slug: "process-mining-monitor") do
    nil ->
      %Agent{}
      |> Agent.changeset(agent_attrs)
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("    \"Process Mining Monitor\" (#{agent.id})")

# ---------------------------------------------------------------------------
# 3. Webhook: BusinessOS Discovery Complete
# ---------------------------------------------------------------------------
# Two-step upsert:
# Step 1 — insert with placeholder URL (self-heal pattern: idempotent)
# Step 2 — update to canonical URL using the real webhook.id
# ---------------------------------------------------------------------------

IO.puts("[3/3] Webhook...")

webhook =
  case Repo.get_by(Webhook, workspace_id: workspace.id, name: "BusinessOS Discovery Complete") do
    nil ->
      placeholder_attrs = %{
        workspace_id: workspace.id,
        name: "BusinessOS Discovery Complete",
        webhook_type: "incoming",
        # Placeholder: will be updated to real URL in step 2
        url: "http://localhost:9089/api/v1/hooks/pending",
        events: ["discovery.complete"],
        secret: nil,
        enabled: true
      }

      %Webhook{}
      |> Webhook.changeset(placeholder_attrs)
      |> Repo.insert!()

    existing ->
      existing
  end

# Step 2: update to canonical Phoenix URL using real webhook.id
canonical_url = "http://localhost:9089/api/v1/hooks/#{webhook.id}"

unless webhook.url == canonical_url do
  webhook
  |> Webhook.changeset(%{url: canonical_url})
  |> Repo.update!()

  IO.puts("    Updated webhook URL to #{canonical_url}")
end

IO.puts("    \"BusinessOS Discovery Complete\" webhook (#{webhook.id})")
IO.puts("\n✓ Process Mining workflow seeded successfully")
IO.puts("\nSet this in BusinessOS .env to activate the webhook:")
IO.puts("  CANOPY_WEBHOOK_URL=#{canonical_url}")
IO.puts("\nAgent will receive discoveries via POST /api/v1/hooks/#{webhook.id}")
