# Autonomic Coordination Workspace — Agent & Schedule Seed
#
# Seeds the 6 Vision 2030 autonomic-coordination agents and their cron
# schedules into a dedicated "Autonomic Coordination" workspace.
#
# Idempotent: safe to re-run. Existing records are skipped.
#
# Run with:
#   mix run priv/repo/seeds/20260324_autonomic_coordination.exs

import Ecto.Query

alias Canopy.Repo
alias Canopy.Schemas.{Workspace, Agent, Schedule}

IO.puts("\n=== Seeding Autonomic Coordination Workspace ===\n")

# ---------------------------------------------------------------------------
# 1. Workspace
# ---------------------------------------------------------------------------

IO.puts("[1/3] Workspace...")

workspace_attrs = %{
  name: "Autonomic Coordination",
  path: Path.expand("~/.canopy/autonomic-coordination"),
  status: "active"
}

workspace =
  case Repo.get_by(Workspace, name: "Autonomic Coordination") do
    nil ->
      %Workspace{}
      |> Workspace.changeset(workspace_attrs)
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("    \"Autonomic Coordination\" (#{workspace.id})")

# ---------------------------------------------------------------------------
# 2. Agents
# ---------------------------------------------------------------------------

IO.puts("[2/3] Agents...")

# All agents report to the orchestrator in the OSA Development workspace.
# If that orchestrator does not exist, we fall back to nil (no reports_to).
orchestrator =
  case Repo.get_by(Workspace, name: "OSA Development") do
    nil -> nil
    osa_ws -> Repo.get_by(Agent, workspace_id: osa_ws.id, slug: "orchestrator")
  end

orchestrator_id = if orchestrator, do: orchestrator.id, else: nil

agent_definitions = [
  %{
    slug: "health-monitor",
    name: "Health Monitor",
    role: "health_monitor",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "\u{1F493}",
    trigger: :scheduled,
    schedule: "*/5 * * * *",
    config: %{
      "url" => "http://localhost:9089",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You monitor the health of all system components every 5 minutes.

    ## Systems to Monitor
    - OSA: GET /health (port 9089)
    - BusinessOS: GET /api/health (port 8001)
    - Canopy: GET /health (port 5200)

    ## Procedure
    1. Call each health endpoint
    2. If any system is down: log failure, attempt restart via shell_execute
    3. Report status to autonomic coordinator
    """
  },
  %{
    slug: "crm-automation",
    name: "CRM Automation",
    role: "crm_automation",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "\u{1F4CA}",
    trigger: :scheduled,
    schedule: "*/15 * * * *",
    config: %{
      "url" => "http://localhost:9089",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You manage CRM operations autonomously every 15 minutes.

    ## Operations
    - Pipeline Sync: Fetch deals, update stages based on activity
    - Lead Scoring: Score new leads by company size, industry, activity
    - Report Generation: Daily pipeline summary, weekly win/loss analysis
    - Data Quality: Check duplicates, validate emails, flag incomplete records
    """
  },
  %{
    slug: "project-coordinator",
    name: "Project Coordinator",
    role: "project_coordinator",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "\u{1F4CB}",
    trigger: :scheduled,
    schedule: "*/30 * * * *",
    config: %{
      "url" => "http://localhost:9089",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You coordinate project management operations every 30 minutes.

    ## Operations
    - Progress Tracking: Check task completion, identify blockers
    - Task Assignment: Match unassigned tasks to team capacity
    - Status Reports: Generate project summaries with milestones, risks, blockers
    - Deadline Management: Flag tasks due within 48 hours
    """
  },
  %{
    slug: "app-generator",
    name: "App Generator",
    role: "app_generator",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "sleeping",
    avatar_emoji: "\u{1F680}",
    trigger: :webhook,
    schedule: nil,
    config: %{
      "url" => "http://localhost:9089",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You generate BusinessOS apps via OSA templates when triggered by webhook.

    ## Operations
    - Receive app request via webhook
    - Generate app structure using templates
    - Create app via BusinessOS API
    - Notify stakeholders
    """
  },
  %{
    slug: "process-healer",
    name: "Process Healer",
    role: "process_healer",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "sleeping",
    avatar_emoji: "\u{1F527}",
    trigger: :anomaly,
    schedule: nil,
    config: %{
      "url" => "http://localhost:9089",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You diagnose and fix broken processes when anomalies are detected.

    ## Operations
    - Receive anomaly trigger
    - Diagnose root cause using OSA process intelligence
    - Apply fix via appropriate tools
    - Verify resolution
    """
  },
  %{
    slug: "compliance-monitor",
    name: "Compliance Monitor",
    role: "compliance_monitor",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "\u2705",
    trigger: :scheduled,
    schedule: "0 */6 * * *",
    config: %{
      "url" => "http://localhost:9089",
      "provider" => "groq",
      "working_dir" => workspace.path
    },
    system_prompt: """
    You perform continuous compliance checking every 6 hours.

    ## Operations
    - Check audit trail integrity via OSA
    - Verify compliance gaps for SOC2, HIPAA, GDPR
    - Collect evidence for compliance domains
    - Generate remediation tasks for gaps
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
# 3. Schedules (only for scheduled agents, not webhook/anomaly-triggered)
# ---------------------------------------------------------------------------

IO.puts("[3/3] Schedules...")

schedule_definitions = [
  %{
    slug: "health-monitor",
    name: "Health Check",
    cron_expression: "*/5 * * * *",
    context: "Check OSA, BusinessOS, Canopy health endpoints. Auto-restart failed services.",
    enabled: true
  },
  %{
    slug: "crm-automation",
    name: "CRM Pipeline Sync",
    cron_expression: "*/15 * * * *",
    context: "Sync CRM deals, score new leads, generate pipeline summary.",
    enabled: true
  },
  %{
    slug: "project-coordinator",
    name: "Project Status Check",
    cron_expression: "*/30 * * * *",
    context: "Track project progress, assign tasks, generate status reports.",
    enabled: true
  },
  %{
    slug: "compliance-monitor",
    name: "Compliance Scan",
    cron_expression: "0 */6 * * *",
    context: "Verify audit trail integrity, check compliance gaps, collect evidence.",
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

=== Autonomic Coordination Seed Complete ===

  Workspace     "Autonomic Coordination" (#{workspace.id})
  Agents        6 (health-monitor, crm-automation, project-coordinator,
                 app-generator, process-healer, compliance-monitor)
  Schedules     4 (enabled)
                   - Health Check         */5 * * * *     -> health-monitor
                   - CRM Pipeline Sync    */15 * * * *     -> crm-automation
                   - Project Status Check */30 * * * *     -> project-coordinator
                   - Compliance Scan      0 */6 * * *      -> compliance-monitor
  Event-driven  2 (no cron schedule)
                   - App Generator        webhook-triggered
                   - Process Healer       anomaly-triggered

  NOTE: Run `Canopy.Scheduler.load_schedules/0` (or restart the application)
        to register the new schedules with the Quantum cron scheduler.
""")
