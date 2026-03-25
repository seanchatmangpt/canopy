# BusinessOS Integration Workspace — Agent Seed
#
# Seeds 2 BusinessOS process mining + compliance agents into a dedicated workspace.
# These agents coordinate with BusinessOS for:
# - Process model discovery and analysis
# - Conformance checking against discovered models
# - Continuous compliance verification (SOC2, HIPAA, GDPR)
#
# Idempotent: safe to re-run. Existing records are skipped.
#
# Run with:
#   mix run priv/repo/seeds/20260325_businessos_agents.exs

import Ecto.Query

alias Canopy.Repo
alias Canopy.Schemas.{Workspace, Agent, Schedule}

IO.puts("\n=== Seeding BusinessOS Integration Workspace ===\n")

# ---------------------------------------------------------------------------
# 1. Workspace
# ---------------------------------------------------------------------------

IO.puts("[1/3] Workspace...")

workspace_attrs = %{
  name: "BusinessOS Integration",
  path: Path.expand("~/.canopy/businessos-integration"),
  status: "active"
}

workspace =
  case Repo.get_by(Workspace, name: "BusinessOS Integration") do
    nil ->
      %Workspace{}
      |> Workspace.changeset(workspace_attrs)
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("    \"BusinessOS Integration\" (#{workspace.id})")

# ---------------------------------------------------------------------------
# 2. Agents
# ---------------------------------------------------------------------------

IO.puts("[2/3] Agents...")

# Try to find orchestrator from OSA Development workspace
orchestrator =
  case Repo.get_by(Workspace, name: "OSA Development") do
    nil -> nil
    osa_ws -> Repo.get_by(Agent, workspace_id: osa_ws.id, slug: "orchestrator")
  end

orchestrator_id = if orchestrator, do: orchestrator.id, else: nil

agent_definitions = [
  %{
    slug: "process-mining-monitor",
    name: "Process Mining Monitor",
    role: "process_mining_monitor",
    adapter: "businessos",
    model: "llama-3.3-70b-versatile",
    status: "idle",
    avatar_emoji: "⛏️",
    trigger: :scheduled,
    schedule: "*/10 * * * *",
    config: %{
      "url" => "http://localhost:8001",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You monitor business process discovery and model analysis every 10 minutes.

    ## Operations
    - Connect to BusinessOS via adapter
    - Discover process models from recent event logs
    - Analyze model quality metrics (fitness, complexity)
    - Alert if process drift detected (>10% change from baseline)
    - Generate process summary reports

    ## Integration Points
    - BusinessOS HTTP: /api/bos/discover, /api/bos/status
    - OSA Process Mining: forward analysis results
    """
  },
  %{
    slug: "bos-conformance-checker",
    name: "BusinessOS Conformance Checker",
    role: "conformance_checker",
    adapter: "businessos",
    model: "llama-3.3-70b-versatile",
    status: "idle",
    avatar_emoji: "✅",
    trigger: :scheduled,
    schedule: "0 */6 * * *",
    config: %{
      "url" => "http://localhost:8001",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You verify process conformance and compliance every 6 hours.

    ## Operations
    - Fetch discovered process models from BusinessOS
    - Run conformance checks (fitness, precision scoring)
    - Verify compliance against:
      * SOC2 Type II controls
      * HIPAA Privacy Rule (if applicable)
      * GDPR data handling requirements
    - Flag non-conforming processes for remediation
    - Generate compliance evidence artifacts

    ## Integration Points
    - BusinessOS HTTP: /api/bos/conformance, /api/bos/compliance/verify
    - OSA Compliance: report gaps and evidence
    - Canopy Alerts: escalate critical conformance failures
    """
  }
]

# Insert agents and build a slug -> agent lookup map.
agents_by_slug =
  for defn <- agent_definitions, into: %{} do
    slug = defn.slug

    agent =
      case Repo.get_by(Agent, workspace_id: workspace.id, slug: slug) do
        nil ->
          attrs =
            defn
            |> Map.drop([:trigger, :schedule])
            |> Map.put(:workspace_id, workspace.id)
            |> Map.put(:reports_to, orchestrator_id)

          %Agent{}
          |> Agent.changeset(attrs)
          |> Repo.insert!()

        existing ->
          existing
      end

    {slug, agent}
  end

agent_slugs = Map.keys(agents_by_slug)
IO.puts("    #{length(agent_slugs)} agents: #{Enum.join(agent_slugs, ", ")}")

# ---------------------------------------------------------------------------
# 3. Schedules
# ---------------------------------------------------------------------------

IO.puts("[3/3] Schedules...")

schedule_definitions = [
  %{
    slug: "process-mining-monitor",
    name: "Process Model Discovery",
    cron_expression: "*/10 * * * *",
    context: "Discover process models from BusinessOS event logs. Analyze fitness, complexity, variants. Alert on drift.",
    enabled: true
  },
  %{
    slug: "bos-conformance-checker",
    name: "Conformance & Compliance Check",
    cron_expression: "0 */6 * * *",
    context: "Run conformance checks (fitness/precision). Verify SOC2/HIPAA/GDPR compliance. Generate evidence.",
    enabled: true
  }
]

for sched_defn <- schedule_definitions do
  agent = Map.fetch!(agents_by_slug, sched_defn.slug)

  unless Repo.exists?(from s in Schedule, where: s.workspace_id == ^workspace.id and s.name == ^sched_defn.name) do
    %Schedule{}
    |> Schedule.changeset(%{
      name: sched_defn.name,
      cron_expression: sched_defn.cron_expression,
      context: sched_defn.context,
      enabled: sched_defn.enabled,
      timezone: "UTC",
      workspace_id: workspace.id,
      agent_id: agent.id
    })
    |> Repo.insert!()

    IO.puts("    Created schedule: #{sched_defn.name} (#{sched_defn.cron_expression}) -> #{sched_defn.slug}")
  end
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

IO.puts("""

=== BusinessOS Integration Seed Complete ===

  Workspace     "BusinessOS Integration" (#{workspace.id})
  Agents        2 (process-mining-monitor, bos-conformance-checker)
  Schedules     2 (enabled)
                   - Process Model Discovery        */10 * * * * -> process-mining-monitor
                   - Conformance & Compliance Check 0 */6 * * *   -> bos-conformance-checker

  Features
    - Process discovery & analysis via BusinessOS /api/bos/discover
    - Conformance checking: fitness, precision, variant analysis
    - Compliance verification: SOC2 Type II, HIPAA, GDPR
    - Real-time drift detection & alerting
    - Evidence artifact generation

  NOTE: Run `Canopy.Scheduler.load_schedules/0` (or restart the application)
        to register the new schedules with the Quantum cron scheduler.

  NOTE: Requires BUSINESSOS_API_TOKEN environment variable for Bearer auth.
        Set in backend/.env or deployment secrets.
""")
