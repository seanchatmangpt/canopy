import Ecto.Query

alias Canopy.Repo

alias Canopy.Schemas.{
  User,
  Workspace,
  Agent,
  Schedule,
  Project,
  Goal,
  Issue,
  BudgetPolicy,
  Skill,
  ActivityEvent,
  Integration,
  Organization,
  OrganizationMembership,
  Secret,
  Label,
  Approval,
  Plugin,
  Template
}

IO.puts("\n=== Canopy Dev Seeds ===\n")

# ---------------------------------------------------------------------------
# SECTION 1: Users
# ---------------------------------------------------------------------------

IO.puts("[1/10] Users...")

Repo.insert(
  User.changeset(%User{}, %{
    name: "Roberto Luna",
    email: "admin@canopy.dev",
    password: "canopy123",
    role: "admin"
  }),
  on_conflict: :nothing,
  conflict_target: :email
)

Repo.insert(
  User.changeset(%User{}, %{
    name: "Dev User",
    email: "dev@canopy.dev",
    password: "canopy123",
    role: "member"
  }),
  on_conflict: :nothing,
  conflict_target: :email
)

admin = Repo.get_by!(User, email: "admin@canopy.dev")
_dev_user = Repo.get_by!(User, email: "dev@canopy.dev")

IO.puts("    admin@canopy.dev (admin), dev@canopy.dev (member)")

# ---------------------------------------------------------------------------
# SECTION 2: Workspace
# ---------------------------------------------------------------------------

IO.puts("[2/10] Workspace...")

Repo.insert(
  Workspace.changeset(%Workspace{}, %{
    name: "OSA Development",
    path: Path.expand("~/.canopy/default"),
    status: "active",
    owner_id: admin.id
  }),
  on_conflict: :nothing
)

workspace = Repo.one!(from w in Workspace, where: w.owner_id == ^admin.id, limit: 1)

IO.puts("    \"OSA Development\" (#{workspace.id})")

# ---------------------------------------------------------------------------
# SECTION 3: Agents
# ---------------------------------------------------------------------------

IO.puts("[3/10] Agents...")

# Orchestrator must be inserted first so subordinates can reference its id.
unless Repo.exists?(
         from a in Agent, where: a.workspace_id == ^workspace.id and a.slug == "orchestrator"
       ) do
  Repo.insert!(
    Agent.changeset(%Agent{}, %{
      slug: "orchestrator",
      name: "Orchestrator",
      role: "orchestrator",
      adapter: "osa",
      model: "claude-opus-4-6",
      status: "idle",
      reports_to: nil,
      workspace_id: workspace.id
    })
  )
end

orchestrator = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "orchestrator")

subordinate_agents = [
  %{
    slug: "researcher",
    name: "Research Agent",
    role: "researcher",
    adapter: "claude-code",
    model: "claude-sonnet-4-6",
    status: "sleeping",
    reports_to: orchestrator.id
  },
  %{
    slug: "developer",
    name: "Developer Agent",
    role: "developer",
    adapter: "claude-code",
    model: "claude-sonnet-4-6",
    status: "sleeping",
    reports_to: orchestrator.id
  },
  %{
    slug: "reviewer",
    name: "Code Reviewer",
    role: "reviewer",
    adapter: "claude-code",
    model: "claude-sonnet-4-6",
    status: "sleeping",
    reports_to: orchestrator.id
  },
  %{
    slug: "devops",
    name: "DevOps Agent",
    role: "devops",
    adapter: "bash",
    model: "bash",
    status: "sleeping",
    reports_to: orchestrator.id
  },
  %{
    slug: "api-monitor",
    name: "API Monitor",
    role: "monitor",
    adapter: "http",
    model: "http",
    status: "sleeping",
    reports_to: orchestrator.id
  }
]

for attrs <- subordinate_agents do
  unless Repo.exists?(
           from a in Agent, where: a.workspace_id == ^workspace.id and a.slug == ^attrs.slug
         ) do
    Repo.insert!(Agent.changeset(%Agent{}, Map.put(attrs, :workspace_id, workspace.id)))
  end
end

developer = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "developer")
reviewer = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "reviewer")
devops = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "devops")
researcher = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "researcher")

IO.puts(
  "    6 agents: orchestrator (osa), researcher, developer, reviewer (claude-code), devops (bash), api-monitor (http)"
)

# ---------------------------------------------------------------------------
# SECTION 3.5: Autonomic Coordination Agents (Vision 2030)
# ---------------------------------------------------------------------------

IO.puts("[3.5/10] Autonomic Coordination Agents...")

autonomic_agents = [
  %{
    slug: "health-monitor",
    name: "Health Monitor",
    role: "health_monitor",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "💓",
    config: %{
      "url" => "http://localhost:8089",
      "provider" => "groq",
      "working_dir" => Path.expand("~/.canopy/default")
    },
    system_prompt: """
    You monitor the health of all system components every 5 minutes.

    ## Systems to Monitor
    - OSA: GET /api/v1/health (port 8089)
    - BusinessOS: GET /api/health (port 8001)
    - Canopy: GET /healthz (port 9089)

    ## Procedure
    1. Call each health endpoint
    2. If any system is down: log failure, attempt restart via shell_execute
    3. Report status to autonomic coordinator
    """,
    reports_to: orchestrator.id
  },
  %{
    slug: "crm-automation",
    name: "CRM Automation",
    role: "crm_automation",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "📊",
    config: %{
      "url" => "http://localhost:8089",
      "provider" => "groq",
      "working_dir" => Path.expand("~/.canopy/default")
    },
    system_prompt: """
    You manage CRM operations autonomously every 15 minutes.

    ## Operations
    - Pipeline Sync: Fetch deals, update stages based on activity
    - Lead Scoring: Score new leads by company size, industry, activity
    - Report Generation: Daily pipeline summary, weekly win/loss analysis
    - Data Quality: Check duplicates, validate emails, flag incomplete records
    """,
    reports_to: orchestrator.id
  },
  %{
    slug: "project-coordinator",
    name: "Project Coordinator",
    role: "project_coordinator",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "📋",
    config: %{
      "url" => "http://localhost:8089",
      "provider" => "groq",
      "working_dir" => Path.expand("~/.canopy/default")
    },
    system_prompt: """
    You coordinate project management operations every 30 minutes.

    ## Operations
    - Progress Tracking: Check task completion, identify blockers
    - Task Assignment: Match unassigned tasks to team capacity
    - Status Reports: Generate project summaries with milestones, risks, blockers
    - Deadline Management: Flag tasks due within 48 hours
    """,
    reports_to: orchestrator.id
  },
  %{
    slug: "app-generator",
    name: "App Generator",
    role: "app_generator",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "sleeping",
    avatar_emoji: "🚀",
    config: %{
      "url" => "http://localhost:8089",
      "provider" => "groq",
      "working_dir" => Path.expand("~/.canopy/default")
    },
    system_prompt: """
    You generate BusinessOS apps via OSA templates when triggered by webhook.

    ## Operations
    - Receive app request via webhook
    - Generate app structure using templates
    - Create app via BusinessOS API
    - Notify stakeholders
    """,
    reports_to: orchestrator.id
  },
  %{
    slug: "process-healer",
    name: "Process Healer",
    role: "process_healer",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "sleeping",
    avatar_emoji: "🔧",
    config: %{
      "url" => "http://localhost:8089",
      "provider" => "groq",
      "working_dir" => Path.expand("~/.canopy/default")
    },
    system_prompt: """
    You diagnose and fix broken processes when anomalies are detected.

    ## Operations
    - Receive anomaly trigger
    - Diagnose root cause using OSA process intelligence
    - Apply fix via appropriate tools
    - Verify resolution
    """,
    reports_to: orchestrator.id
  },
  %{
    slug: "compliance-monitor",
    name: "Compliance Monitor",
    role: "compliance_monitor",
    adapter: "osa",
    model: "openai/gpt-oss-20b",
    status: "idle",
    avatar_emoji: "✅",
    config: %{
      "url" => "http://localhost:8089",
      "provider" => "groq",
      "working_dir" => Path.expand("~/.canopy/default")
    },
    system_prompt: """
    You perform continuous compliance checking every 6 hours.

    ## Operations
    - Check audit trail integrity via OSA
    - Verify compliance gaps for SOC2, HIPAA, GDPR
    - Collect evidence for compliance domains
    - Generate remediation tasks for gaps
    """,
    reports_to: orchestrator.id
  }
]

for attrs <- autonomic_agents do
  unless Repo.exists?(
           from a in Agent, where: a.workspace_id == ^workspace.id and a.slug == ^attrs.slug
         ) do
    Repo.insert!(Agent.changeset(%Agent{}, Map.put(attrs, :workspace_id, workspace.id)))
  end
end

health_monitor = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "health-monitor")
crm_automation = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "crm-automation")
project_coordinator = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "project-coordinator")
compliance_monitor = Repo.get_by!(Agent, workspace_id: workspace.id, slug: "compliance-monitor")

IO.puts(
  "    6 autonomic agents: health-monitor, crm-automation, project-coordinator, app-generator, process-healer, compliance-monitor"
)

# ---------------------------------------------------------------------------
# SECTION 4: Schedules
# ---------------------------------------------------------------------------

IO.puts("[4/10] Schedules...")

schedules = [
  %{
    name: "Morning standup",
    cron_expression: "0 9 * * 1-5",
    context:
      "Run daily standup: summarize yesterday's completed issues, flag blockers, list today's priorities.",
    enabled: false,
    workspace_id: workspace.id,
    agent_id: researcher.id
  },
  %{
    name: "Nightly code review",
    cron_expression: "0 2 * * *",
    context: "Review all pull requests opened today. Post review comments and summary report.",
    enabled: false,
    workspace_id: workspace.id,
    agent_id: reviewer.id
  },
  %{
    name: "Infrastructure check",
    cron_expression: "*/30 * * * *",
    context:
      "Check service health endpoints, disk usage, and container status. Alert on anomalies.",
    enabled: false,
    workspace_id: workspace.id,
    agent_id: devops.id
  }
]

for attrs <- schedules do
  unless Repo.exists?(
           from s in Schedule, where: s.workspace_id == ^workspace.id and s.name == ^attrs.name
         ) do
    Repo.insert!(Schedule.changeset(%Schedule{}, attrs))
  end
end

IO.puts(
  "    3 schedules (all disabled): morning standup, nightly code review, infrastructure check"
)

# Autonomic Coordination Schedules (Vision 2030)
autonomic_schedules = [
  %{
    name: "Health Check",
    cron_expression: "*/5 * * * *",
    context: "Check OSA, BusinessOS, Canopy health endpoints. Auto-restart failed services.",
    enabled: true,
    timezone: "UTC",
    workspace_id: workspace.id,
    agent_id: health_monitor.id
  },
  %{
    name: "CRM Pipeline Sync",
    cron_expression: "*/15 * * * *",
    context: "Sync CRM deals, score new leads, generate pipeline summary.",
    enabled: true,
    timezone: "UTC",
    workspace_id: workspace.id,
    agent_id: crm_automation.id
  },
  %{
    name: "Project Status Check",
    cron_expression: "*/30 * * * *",
    context: "Track project progress, assign tasks, generate status reports.",
    enabled: true,
    timezone: "UTC",
    workspace_id: workspace.id,
    agent_id: project_coordinator.id
  },
  %{
    name: "Compliance Scan",
    cron_expression: "0 */6 * * *",
    context: "Verify audit trail integrity, check compliance gaps, collect evidence.",
    enabled: true,
    timezone: "UTC",
    workspace_id: workspace.id,
    agent_id: compliance_monitor.id
  }
]

for attrs <- autonomic_schedules do
  unless Repo.exists?(
           from s in Schedule, where: s.workspace_id == ^workspace.id and s.name == ^attrs.name
         ) do
    Repo.insert!(Schedule.changeset(%Schedule{}, attrs))
  end
end

IO.puts(
  "    4 autonomic schedules (enabled): health-check (5min), crm-sync (15min), project-status (30min), compliance-scan (6hr)"
)

# ---------------------------------------------------------------------------
# SECTION 5: Projects
# ---------------------------------------------------------------------------

IO.puts("[5/10] Projects...")

unless Repo.exists?(
         from p in Project, where: p.workspace_id == ^workspace.id and p.name == "Canopy Platform"
       ) do
  Repo.insert!(%Project{
    name: "Canopy Platform",
    description: "The Canopy Command Center desktop application and backend API.",
    status: "active",
    workspace_id: workspace.id
  })
end

unless Repo.exists?(
         from p in Project, where: p.workspace_id == ^workspace.id and p.name == "Infrastructure"
       ) do
  Repo.insert!(%Project{
    name: "Infrastructure",
    description: "CI/CD pipelines, deployment automation, and monitoring setup.",
    status: "active",
    workspace_id: workspace.id
  })
end

canopy_project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Canopy Platform")
infra_project = Repo.get_by!(Project, workspace_id: workspace.id, name: "Infrastructure")

IO.puts("    2 projects: \"Canopy Platform\", \"Infrastructure\"")

# ---------------------------------------------------------------------------
# SECTION 6: Goals
# ---------------------------------------------------------------------------

IO.puts("[6/10] Goals...")

unless Repo.exists?(
         from g in Goal, where: g.workspace_id == ^workspace.id and g.title == "Launch MVP"
       ) do
  Repo.insert!(%Goal{
    title: "Launch MVP",
    description:
      "Ship the first production-ready release of Canopy with core agent management features.",
    status: "active",
    workspace_id: workspace.id,
    project_id: canopy_project.id
  })
end

launch_mvp = Repo.get_by!(Goal, workspace_id: workspace.id, title: "Launch MVP")

unless Repo.exists?(
         from g in Goal,
           where: g.workspace_id == ^workspace.id and g.title == "Implement Adapter System"
       ) do
  Repo.insert!(%Goal{
    title: "Implement Adapter System",
    description:
      "Build the pluggable adapter layer supporting osa, claude-code, bash, http, and codex adapters.",
    status: "active",
    workspace_id: workspace.id,
    project_id: canopy_project.id,
    parent_id: launch_mvp.id
  })
end

unless Repo.exists?(
         from g in Goal, where: g.workspace_id == ^workspace.id and g.title == "Setup CI/CD"
       ) do
  Repo.insert!(%Goal{
    title: "Setup CI/CD",
    description: "Automated build, test, and deployment pipeline via GitHub Actions.",
    status: "active",
    workspace_id: workspace.id,
    project_id: infra_project.id
  })
end

unless Repo.exists?(
         from g in Goal, where: g.workspace_id == ^workspace.id and g.title == "Security Audit"
       ) do
  Repo.insert!(%Goal{
    title: "Security Audit",
    description: "OWASP Top 10 review, JWT hardening, tenant isolation validation.",
    status: "active",
    workspace_id: workspace.id,
    project_id: infra_project.id
  })
end

IO.puts("    4 goals: Launch MVP, Implement Adapter System (child), Setup CI/CD, Security Audit")

# ---------------------------------------------------------------------------
# SECTION 7: Issues
# ---------------------------------------------------------------------------

IO.puts("[7/10] Issues...")

adapter_goal = Repo.get_by!(Goal, workspace_id: workspace.id, title: "Implement Adapter System")
cicd_goal = Repo.get_by!(Goal, workspace_id: workspace.id, title: "Setup CI/CD")
security_goal = Repo.get_by!(Goal, workspace_id: workspace.id, title: "Security Audit")

issues = [
  %{
    title: "Implement OSA adapter",
    description:
      "Wire up the OSA adapter to the agent execution engine. Support tool calling and streaming responses.",
    status: "todo",
    priority: "high",
    workspace_id: workspace.id,
    project_id: canopy_project.id,
    goal_id: adapter_goal.id,
    assignee_id: developer.id
  },
  %{
    title: "Write integration tests",
    description:
      "Integration test suite covering adapter execution, session lifecycle, and budget enforcement.",
    status: "backlog",
    priority: "medium",
    workspace_id: workspace.id,
    project_id: canopy_project.id,
    goal_id: adapter_goal.id
  },
  %{
    title: "Fix SSE connection drops",
    description:
      "SSE stream disconnects after ~30s under load. Suspected Bandit keepalive timeout misconfiguration.",
    status: "in_progress",
    priority: "critical",
    workspace_id: workspace.id,
    project_id: canopy_project.id,
    goal_id: launch_mvp.id,
    assignee_id: developer.id
  },
  %{
    title: "Add budget enforcement UI",
    description:
      "Budget policy editor in the Canopy UI: set monthly limits, warning thresholds, and view spend history.",
    status: "todo",
    priority: "medium",
    workspace_id: workspace.id,
    project_id: canopy_project.id,
    goal_id: launch_mvp.id
  },
  %{
    title: "Review auth flow",
    description:
      "Audit JWT issuance, refresh token rotation, and Guardian plug configuration for production readiness.",
    status: "in_review",
    priority: "high",
    workspace_id: workspace.id,
    project_id: infra_project.id,
    goal_id: security_goal.id,
    assignee_id: reviewer.id
  },
  %{
    title: "Setup monitoring dashboards",
    description:
      "Grafana dashboards for agent session throughput, budget burn rate, and BEAM VM health metrics.",
    status: "backlog",
    priority: "low",
    workspace_id: workspace.id,
    project_id: infra_project.id,
    goal_id: cicd_goal.id,
    assignee_id: devops.id
  }
]

for attrs <- issues do
  unless Repo.exists?(
           from i in Issue, where: i.workspace_id == ^workspace.id and i.title == ^attrs.title
         ) do
    Repo.insert!(Issue.changeset(%Issue{}, attrs))
  end
end

IO.puts("    6 issues: 2 todo, 1 in_progress (critical), 1 in_review, 2 backlog")

# ---------------------------------------------------------------------------
# SECTION 8: Budget Policies
# ---------------------------------------------------------------------------

IO.puts("[8/10] Budget policies...")

unless Repo.exists?(
         from b in BudgetPolicy, where: b.scope_type == "agent" and b.scope_id == ^orchestrator.id
       ) do
  Repo.insert!(
    BudgetPolicy.changeset(%BudgetPolicy{}, %{
      scope_type: "agent",
      scope_id: orchestrator.id,
      monthly_limit_cents: 5_000,
      warning_threshold_pct: 80,
      hard_stop: true
    })
  )
end

unless Repo.exists?(
         from b in BudgetPolicy,
           where: b.scope_type == "workspace" and b.scope_id == ^workspace.id
       ) do
  Repo.insert!(
    BudgetPolicy.changeset(%BudgetPolicy{}, %{
      scope_type: "workspace",
      scope_id: workspace.id,
      monthly_limit_cents: 20_000,
      warning_threshold_pct: 70,
      hard_stop: true
    })
  )
end

IO.puts("    2 policies: orchestrator $50/mo (80% warn), workspace $200/mo (70% warn)")

# ---------------------------------------------------------------------------
# SECTION 9: Skills
# ---------------------------------------------------------------------------

IO.puts("[9/10] Skills...")

skills = [
  %{
    name: "Code Generation",
    description: "Generate, refactor, and review source code across multiple languages.",
    category: "Development",
    enabled: true,
    trigger_rules: %{keywords: ["implement", "write", "refactor", "generate code"]},
    workspace_id: workspace.id
  },
  %{
    name: "Web Search",
    description: "Search the web for documentation, research papers, and technical references.",
    category: "Research",
    enabled: true,
    trigger_rules: %{keywords: ["search", "find", "look up", "research"]},
    workspace_id: workspace.id
  },
  %{
    name: "PR Review",
    description: "Review pull requests for correctness, security, and style adherence.",
    category: "Development",
    enabled: true,
    trigger_rules: %{keywords: ["review", "PR", "pull request", "LGTM"]},
    workspace_id: workspace.id
  },
  %{
    name: "Deployment",
    description: "Deploy services to staging and production via automated pipelines.",
    category: "Operations",
    enabled: false,
    trigger_rules: %{keywords: ["deploy", "release", "rollout", "ship"]},
    workspace_id: workspace.id
  }
]

for attrs <- skills do
  unless Repo.exists?(
           from s in Skill, where: s.workspace_id == ^workspace.id and s.name == ^attrs.name
         ) do
    Repo.insert!(Skill.changeset(%Skill{}, attrs))
  end
end

IO.puts("    4 skills: Code Generation, Web Search, PR Review (enabled), Deployment (disabled)")

# ---------------------------------------------------------------------------
# SECTION 10: Activity Events
# ---------------------------------------------------------------------------

IO.puts("[10/10] Activity events & integrations...")

now = DateTime.utc_now() |> DateTime.truncate(:second)

activity_seeds = [
  %{
    event_type: "agent.hired",
    message: "Agent 'Orchestrator' added to workspace OSA Development.",
    level: "info",
    metadata: %{agent_slug: "orchestrator", adapter: "osa"},
    workspace_id: workspace.id,
    agent_id: orchestrator.id,
    inserted_at: DateTime.add(now, -86_400 * 5, :second)
  },
  %{
    event_type: "agent.hired",
    message: "Agent 'Developer Agent' added to workspace OSA Development.",
    level: "info",
    metadata: %{agent_slug: "developer", adapter: "claude-code"},
    workspace_id: workspace.id,
    agent_id: developer.id,
    inserted_at: DateTime.add(now, -86_400 * 4, :second)
  },
  %{
    event_type: "session.completed",
    message: "Orchestrator completed session: architecture planning for Canopy adapter system.",
    level: "info",
    metadata: %{duration_ms: 42_300, tokens_used: 18_400},
    workspace_id: workspace.id,
    agent_id: orchestrator.id,
    inserted_at: DateTime.add(now, -86_400 * 3, :second)
  },
  %{
    event_type: "session.completed",
    message: "Developer Agent completed session: implemented OSA adapter scaffold.",
    level: "info",
    metadata: %{duration_ms: 91_200, tokens_used: 34_750},
    workspace_id: workspace.id,
    agent_id: developer.id,
    inserted_at: DateTime.add(now, -86_400 * 2, :second)
  },
  %{
    event_type: "budget.warning",
    message: "Workspace budget at 72% of monthly limit ($144 / $200).",
    level: "warn",
    metadata: %{spent_cents: 14_400, limit_cents: 20_000, pct: 72},
    workspace_id: workspace.id,
    inserted_at: DateTime.add(now, -86_400, :second)
  },
  %{
    event_type: "issue.status_changed",
    message: "Issue 'Fix SSE connection drops' moved to in_progress by Developer Agent.",
    level: "info",
    metadata: %{
      from_status: "todo",
      to_status: "in_progress",
      issue_title: "Fix SSE connection drops"
    },
    workspace_id: workspace.id,
    agent_id: developer.id,
    inserted_at: DateTime.add(now, -3_600 * 6, :second)
  },
  %{
    event_type: "session.started",
    message: "Code Reviewer started review session for auth flow issue.",
    level: "info",
    metadata: %{issue_title: "Review auth flow"},
    workspace_id: workspace.id,
    agent_id: reviewer.id,
    inserted_at: DateTime.add(now, -3_600 * 2, :second)
  },
  %{
    event_type: "agent.error",
    message: "API Monitor failed health check: endpoint /api/health returned 503.",
    level: "error",
    metadata: %{endpoint: "/api/health", status_code: 503, retry_count: 3},
    workspace_id: workspace.id,
    inserted_at: DateTime.add(now, -1_800, :second)
  }
]

for attrs <- activity_seeds do
  Repo.insert!(
    ActivityEvent.changeset(%ActivityEvent{}, Map.drop(attrs, [:inserted_at]))
    |> Ecto.Changeset.put_change(:inserted_at, attrs.inserted_at),
    on_conflict: :nothing
  )
end

# ---------------------------------------------------------------------------
# Integrations
# ---------------------------------------------------------------------------

integrations = [
  %{
    slug: "anthropic",
    name: "Anthropic",
    category: "AI Provider",
    config: %{api_key_set: true, default_model: "claude-opus-4-6"},
    connected: true,
    workspace_id: workspace.id,
    last_synced_at: DateTime.add(now, -3_600, :second)
  },
  %{
    slug: "github",
    name: "GitHub",
    category: "Version Control",
    config: %{},
    connected: false,
    workspace_id: workspace.id
  }
]

for attrs <- integrations do
  unless Repo.exists?(
           from i in Integration, where: i.workspace_id == ^workspace.id and i.slug == ^attrs.slug
         ) do
    Repo.insert!(
      Integration.changeset(%Integration{}, Map.drop(attrs, [:last_synced_at]))
      |> then(fn cs ->
        case Map.get(attrs, :last_synced_at) do
          nil -> cs
          ts -> Ecto.Changeset.put_change(cs, :last_synced_at, ts)
        end
      end)
    )
  end
end

IO.puts("    8 activity events, 2 integrations (anthropic connected, github disconnected)")

# ---------------------------------------------------------------------------
# SECTION 11: Organizations
# ---------------------------------------------------------------------------

IO.puts("[11/17] Organizations...")

unless Repo.exists?(from o in Organization, where: o.slug == "miosa-labs") do
  Repo.insert!(
    Organization.changeset(%Organization{}, %{
      name: "MIOSA Labs",
      slug: "miosa-labs",
      plan: "enterprise",
      settings: %{billing_email: "billing@miosa.ai", timezone: "America/Los_Angeles"}
    })
  )
end

unless Repo.exists?(from o in Organization, where: o.slug == "acme-corp") do
  Repo.insert!(
    Organization.changeset(%Organization{}, %{
      name: "Acme Corp",
      slug: "acme-corp",
      plan: "pro",
      settings: %{billing_email: "billing@acme.com", timezone: "America/New_York"}
    })
  )
end

miosa_org = Repo.get_by!(Organization, slug: "miosa-labs")
acme_org = Repo.get_by!(Organization, slug: "acme-corp")

IO.puts("    MIOSA Labs (enterprise), Acme Corp (pro)")

# ---------------------------------------------------------------------------
# SECTION 12: Organization Memberships
# ---------------------------------------------------------------------------

IO.puts("[12/17] Organization memberships...")

unless Repo.exists?(
         from m in OrganizationMembership,
           where: m.organization_id == ^miosa_org.id and m.user_id == ^admin.id
       ) do
  Repo.insert!(
    OrganizationMembership.changeset(%OrganizationMembership{}, %{
      organization_id: miosa_org.id,
      user_id: admin.id,
      role: "owner"
    })
  )
end

unless Repo.exists?(
         from m in OrganizationMembership,
           where: m.organization_id == ^acme_org.id and m.user_id == ^admin.id
       ) do
  Repo.insert!(
    OrganizationMembership.changeset(%OrganizationMembership{}, %{
      organization_id: acme_org.id,
      user_id: admin.id,
      role: "admin"
    })
  )
end

IO.puts("    admin@canopy.dev: owner of MIOSA Labs, admin of Acme Corp")

# ---------------------------------------------------------------------------
# SECTION 13: Secrets
# ---------------------------------------------------------------------------

IO.puts("[13/17] Secrets...")

secrets = [
  %{
    name: "OpenAI API Key",
    key: "OPENAI_API_KEY",
    encrypted_value: "enc_***_redacted",
    provider: "openai",
    workspace_id: workspace.id,
    created_by: admin.id
  },
  %{
    name: "GitHub Token",
    key: "GITHUB_TOKEN",
    encrypted_value: "enc_***_redacted",
    provider: "github",
    workspace_id: workspace.id,
    created_by: admin.id
  },
  %{
    name: "Anthropic Key",
    key: "ANTHROPIC_API_KEY",
    encrypted_value: "enc_***_redacted",
    provider: "anthropic",
    workspace_id: workspace.id,
    created_by: admin.id
  },
  %{
    name: "Groq API Key",
    key: "GROQ_API_KEY",
    encrypted_value: "enc_***_redacted",
    provider: "groq",
    workspace_id: workspace.id,
    created_by: admin.id
  }
]

for attrs <- secrets do
  unless Repo.exists?(
           from s in Secret, where: s.workspace_id == ^workspace.id and s.key == ^attrs.key
         ) do
    Repo.insert!(Secret.changeset(%Secret{}, attrs))
  end
end

IO.puts("    4 secrets: OPENAI_API_KEY, GITHUB_TOKEN, ANTHROPIC_API_KEY, GROQ_API_KEY")

# ---------------------------------------------------------------------------
# SECTION 14: Labels
# ---------------------------------------------------------------------------

IO.puts("[14/17] Labels...")

labels = [
  %{name: "bug", color: "#ef4444", workspace_id: workspace.id},
  %{name: "feature", color: "#3b82f6", workspace_id: workspace.id},
  %{name: "urgent", color: "#f97316", workspace_id: workspace.id},
  %{name: "documentation", color: "#22c55e", workspace_id: workspace.id},
  %{name: "enhancement", color: "#8b5cf6", workspace_id: workspace.id}
]

for attrs <- labels do
  unless Repo.exists?(
           from l in Label, where: l.workspace_id == ^workspace.id and l.name == ^attrs.name
         ) do
    Repo.insert!(Label.changeset(%Label{}, attrs))
  end
end

IO.puts(
  "    5 labels: bug (red), feature (blue), urgent (orange), documentation (green), enhancement (purple)"
)

# ---------------------------------------------------------------------------
# SECTION 15: Approvals
# ---------------------------------------------------------------------------

IO.puts("[15/17] Approvals...")

unless Repo.exists?(
         from a in Approval,
           where: a.workspace_id == ^workspace.id and a.title == "Deploy v2.1 to production"
       ) do
  Repo.insert!(
    Approval.changeset(%Approval{}, %{
      title: "Deploy v2.1 to production",
      description:
        "Requesting approval to deploy Canopy v2.1 to the production environment. Includes adapter system, budget UI, and SSE fixes.",
      status: "pending",
      context: %{version: "2.1.0", environment: "production", risk: "medium"},
      requested_by: orchestrator.id,
      reviewer_id: admin.id,
      workspace_id: workspace.id,
      expires_at:
        DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), 86_400 * 3, :second)
    })
  )
end

unless Repo.exists?(
         from a in Approval,
           where: a.workspace_id == ^workspace.id and a.title == "Update agent budget limits"
       ) do
  Repo.insert!(
    Approval.changeset(%Approval{}, %{
      title: "Update agent budget limits",
      description:
        "Increase orchestrator monthly budget from $50 to $100 to accommodate higher session volume.",
      status: "approved",
      decision: "approved",
      decision_comment:
        "Approved. Usage has been consistently hitting the old cap. $100 ceiling is reasonable.",
      context: %{old_limit_cents: 5_000, new_limit_cents: 10_000, scope: "agent"},
      requested_by: orchestrator.id,
      reviewer_id: admin.id,
      workspace_id: workspace.id
    })
  )
end

IO.puts(
  "    2 approvals: \"Deploy v2.1 to production\" (pending), \"Update agent budget limits\" (approved)"
)

# ---------------------------------------------------------------------------
# SECTION 16: Plugins
# ---------------------------------------------------------------------------

IO.puts("[16/17] Plugins...")

plugins = [
  %{
    slug: "github",
    name: "GitHub",
    version: "1.0.0",
    enabled: true,
    config: %{webhook_secret_set: true, default_branch: "main"},
    workspace_id: workspace.id
  },
  %{
    slug: "slack",
    name: "Slack",
    version: "1.2.0",
    enabled: true,
    config: %{
      channel: "#canopy-alerts",
      notify_on: ["session.completed", "budget.warning", "agent.error"]
    },
    workspace_id: workspace.id
  },
  %{
    slug: "jira",
    name: "Jira",
    version: "0.9.0",
    enabled: false,
    config: %{project_key: "CAN", sync_issues: false},
    workspace_id: workspace.id
  }
]

for attrs <- plugins do
  unless Repo.exists?(
           from p in Plugin, where: p.workspace_id == ^workspace.id and p.slug == ^attrs.slug
         ) do
    Repo.insert!(Plugin.changeset(%Plugin{}, attrs))
  end
end

IO.puts(
  "    3 plugins: github (v1.0.0, enabled), slack (v1.2.0, enabled), jira (v0.9.0, disabled)"
)

# ---------------------------------------------------------------------------
# SECTION 17: Templates
# ---------------------------------------------------------------------------

IO.puts("[17/17] Templates...")

unless Repo.exists?(from t in Template, where: t.name == "Full-Stack Development Team") do
  Repo.insert!(
    Template.changeset(%Template{}, %{
      name: "Full-Stack Development Team",
      description:
        "A complete dev team setup with orchestrator, frontend, backend, reviewer, and devops agents. Includes code generation, PR review, and deployment skills.",
      category: "development",
      is_builtin: true,
      agents: [
        %{name: "orchestrator", role: "orchestrator", adapter: "osa", model: "claude-opus-4-6"},
        %{
          name: "frontend",
          role: "developer",
          adapter: "claude-code",
          model: "claude-sonnet-4-6"
        },
        %{name: "backend", role: "developer", adapter: "claude-code", model: "claude-sonnet-4-6"},
        %{name: "reviewer", role: "reviewer", adapter: "claude-code", model: "claude-sonnet-4-6"},
        %{name: "devops", role: "devops", adapter: "bash", model: "bash"}
      ],
      skills: [
        %{name: "code_generation", enabled: true},
        %{name: "pr_review", enabled: true},
        %{name: "deployment", enabled: false},
        %{name: "web_search", enabled: true}
      ],
      schedules: [
        %{name: "nightly_review", cron: "0 2 * * *", agent: "reviewer", enabled: false}
      ]
    })
  )
end

unless Repo.exists?(from t in Template, where: t.name == "Research Assistant") do
  Repo.insert!(
    Template.changeset(%Template{}, %{
      name: "Research Assistant",
      description:
        "A focused research team: one orchestrator coordinating a researcher and a writer. Optimised for document synthesis, literature review, and report generation.",
      category: "research",
      is_builtin: true,
      agents: [
        %{name: "orchestrator", role: "orchestrator", adapter: "osa", model: "claude-opus-4-6"},
        %{
          name: "researcher",
          role: "researcher",
          adapter: "claude-code",
          model: "claude-sonnet-4-6"
        },
        %{name: "writer", role: "writer", adapter: "claude-code", model: "claude-sonnet-4-6"}
      ],
      skills: [
        %{name: "web_search", enabled: true},
        %{name: "code_generation", enabled: false}
      ],
      schedules: []
    })
  )
end

IO.puts("    2 built-in templates: \"Full-Stack Development Team\", \"Research Assistant\"")

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

IO.puts("""

=== Seed complete ===

  Users         admin@canopy.dev (admin), dev@canopy.dev (member)
  Workspace     \"OSA Development\"
  Agents        12 (orchestrator, researcher, developer, reviewer, devops, api-monitor,
               health-monitor, crm-automation, project-coordinator, app-generator,
               process-healer, compliance-monitor)
  Schedules     7  (3 disabled + 4 autonomic enabled)
  Projects      2  (Canopy Platform, Infrastructure)
  Goals         4  (Launch MVP + child, Setup CI/CD, Security Audit)
  Issues        6  (todo x2, in_progress x1, in_review x1, backlog x2)
  Budgets       2  (agent $50/mo, workspace $200/mo)
  Skills        4  (3 enabled, 1 disabled)
  Events        8  activity entries
  Integrations  2  (anthropic connected, github disconnected)
  Orgs          2  (MIOSA Labs enterprise, Acme Corp pro)
  Memberships   2  (admin: owner of MIOSA Labs, admin of Acme Corp)
  Secrets       4  (OPENAI_API_KEY, GITHUB_TOKEN, ANTHROPIC_API_KEY, GROQ_API_KEY)
  Labels        5  (bug, feature, urgent, documentation, enhancement)
  Approvals     2  (1 pending, 1 approved)
  Plugins       3  (github enabled, slack enabled, jira disabled)
  Templates     2  (Full-Stack Development Team, Research Assistant)

  Vision 2030   Autonomic Coordination Agents seeded (4 schedules active)
""")
