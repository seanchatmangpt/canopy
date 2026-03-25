defmodule CanopyWeb.RouterWorkspaceScopes do
  @moduledoc """
  Workspace-scoped route configuration for multi-workspace isolation.

  Defines scopes for all workspace-specific routes with path parameter `:workspace_id`.
  Used by CanopyWeb.Router to support both legacy routes and new multi-workspace routes.

  Example:
    scope "/:workspace_id", CanopyWeb do
      pipe_through [:api, :authenticated, :workspace_context]
      # All routes here are workspace-scoped
    end
  """

  defmacro workspace_scopes(routes) do
    quote do
      # Legacy routes (workspace context from JWT claims or query param)
      scope "/api/v1", CanopyWeb do
        pipe_through [:api, :authenticated, :workspace_context]

        resources "/workspaces", WorkspaceController, except: [:new, :edit] do
          post "/activate", WorkspaceController, :activate, as: :activate
          get "/agents", WorkspaceController, :agents, as: :agents
          get "/skills", WorkspaceController, :skills, as: :skills
          get "/config", WorkspaceController, :config, as: :config
          post "/members", WorkspaceController, :add_member, as: :add_member
          delete "/members/:user_id", WorkspaceController, :remove_member, as: :remove_member
          get "/members", WorkspaceController, :members, as: :members
        end

        # All existing routes with workspace isolation enforced
        resources "/agents", AgentController, except: [:new, :edit] do
          post "/wake", AgentController, :wake, as: :wake
          post "/sleep", AgentController, :sleep, as: :sleep
          post "/pause", AgentController, :pause, as: :pause
          post "/resume", AgentController, :resume, as: :resume
          post "/focus", AgentController, :focus, as: :focus
          post "/terminate", AgentController, :terminate, as: :terminate
          get "/runs", AgentController, :runs, as: :runs
          get "/inbox", AgentController, :inbox, as: :inbox
        end

        resources "/sessions", SessionController, only: [:index, :show, :delete] do
          get "/transcript", SessionController, :transcript, as: :transcript
          post "/message", SessionController, :message, as: :message
        end

        get "/schedules/queue", ScheduleController, :queue
        post "/schedules/wake-all", ScheduleController, :wake_all
        post "/schedules/pause-all", ScheduleController, :pause_all
        resources "/schedules", ScheduleController, except: [:new, :edit] do
          post "/trigger", ScheduleController, :trigger, as: :trigger
        end

        get "/costs/summary", CostController, :summary
        get "/costs/by-agent", CostController, :by_agent
        get "/costs/by-model", CostController, :by_model
        get "/costs/daily", CostController, :daily
        get "/costs/events", CostController, :events
        get "/budgets", BudgetController, :index
        put "/budgets/:scope_type/:scope_id", BudgetController, :upsert
        get "/budgets/incidents", BudgetController, :incidents
        post "/budgets/incidents/:id/resolve", BudgetController, :resolve

        post "/spawn", SpawnController, :create
        get "/spawn/active", SpawnController, :active
        delete "/spawn/:id", SpawnController, :kill
        get "/spawn/history", SpawnController, :history

        resources "/issues", IssueController, except: [:new, :edit] do
          post "/assign", IssueController, :assign, as: :assign
          resources "/comments", CommentController, only: [:index, :create]
          post "/checkout", IssueController, :checkout, as: :checkout
          post "/dispatch", IssueController, :dispatch, as: :dispatch
          post "/labels", IssueController, :add_label, as: :add_label
          delete "/labels/:label_id", IssueController, :remove_label, as: :remove_label
        end

        resources "/goals", GoalController, except: [:new, :edit] do
          get "/ancestry", GoalController, :ancestry, as: :ancestry
          post "/decompose", GoalController, :decompose, as: :decompose
        end

        resources "/projects", ProjectController, except: [:new, :edit] do
          get "/goals", ProjectController, :goals, as: :goals
          get "/workspaces", ProjectController, :workspaces, as: :workspaces
        end

        get "/documents", DocumentController, :index
        get "/document-revisions", DocumentController, :revisions
        get "/documents/*path", DocumentController, :show
        put "/documents/*path", DocumentController, :update
        delete "/documents/*path", DocumentController, :delete
        post "/documents", DocumentController, :create

        get "/inbox", InboxController, :index
        post "/inbox/read-all", InboxController, :read_all
        post "/inbox/:id/read", InboxController, :read
        post "/inbox/:id/action", InboxController, :perform_action

        get "/activity", ActivityController, :index
        get "/logs", LogController, :index

        get "/memory/search", MemoryController, :search
        get "/memory/namespaces", MemoryController, :namespaces
        resources "/memory", MemoryController, except: [:new, :edit]

        post "/signals/classify", SignalController, :classify
        get "/signals/feed", SignalController, :feed
        get "/signals/patterns", SignalController, :patterns
        get "/signals/stats", SignalController, :stats

        post "/skills/bulk-enable", SkillController, :bulk_enable
        post "/skills/bulk-disable", SkillController, :bulk_disable
        get "/skills/categories", SkillController, :categories
        post "/skills/import", SkillController, :import_skill
        resources "/skills", SkillController, only: [:index, :show] do
          post "/toggle", SkillController, :toggle, as: :toggle
          post "/inject", SkillController, :inject, as: :inject
        end

        post "/agents/:agent_id/skills/:skill_id", SkillController, :assign_to_agent
        delete "/agents/:agent_id/skills/:skill_id", SkillController, :remove_from_agent

        resources "/webhooks", WebhookController, except: [:new, :edit] do
          post "/test", WebhookController, :test, as: :test
          get "/deliveries", WebhookController, :deliveries, as: :deliveries
        end

        get "/alerts/rules", AlertController, :index_rules
        post "/alerts/rules", AlertController, :create_rule
        get "/alerts/rules/:id", AlertController, :show_rule
        patch "/alerts/rules/:id", AlertController, :update_rule
        delete "/alerts/rules/:id", AlertController, :delete_rule
        post "/alerts/evaluate", AlertController, :evaluate
        get "/alerts/history", AlertController, :history

        get "/integrations", IntegrationController, :index
        post "/integrations/pull-all", IntegrationController, :pull_all
        post "/integrations/:slug/connect", IntegrationController, :connect
        delete "/integrations/:slug", IntegrationController, :disconnect
        get "/integrations/:slug/status", IntegrationController, :status

        resources "/users", UserController, except: [:new, :edit]
        get "/audit", AuditController, :index

        resources "/gateways", GatewayController, only: [:index, :show, :create, :update, :delete] do
          post "/probe", GatewayController, :probe, as: :probe
        end

        get "/config", ConfigController, :show
        patch "/config", ConfigController, :update
        get "/templates", TemplateController, :index
        post "/templates", TemplateController, :create

        resources "/secrets", SecretController, except: [:new, :edit] do
          post "/rotate", SecretController, :rotate, as: :rotate
        end

        resources "/approvals", ApprovalController, except: [:new, :edit] do
          post "/approve", ApprovalController, :approve, as: :approve
          post "/reject", ApprovalController, :reject, as: :reject
          post "/comments", ApprovalController, :comment, as: :comments
        end

        resources "/divisions", DivisionController, except: [:new, :edit] do
          get "/departments", DivisionController, :departments, as: :departments
        end

        resources "/departments", DepartmentController, except: [:new, :edit] do
          get "/teams", DepartmentController, :teams, as: :teams
        end

        resources "/teams", TeamController, except: [:new, :edit] do
          get "/agents", TeamController, :agents, as: :agents
          post "/members", TeamController, :add_member, as: :members
          delete "/members/:agent_id", TeamController, :remove_member, as: :remove_member
        end

        get "/hierarchy", HierarchyController, :show

        resources "/invitations", InvitationController, only: [:index, :create]
        post "/invitations/:token/accept", InvitationController, :accept

        resources "/labels", LabelController, only: [:index, :create, :delete]

        get "/issues/:issue_id/attachments", AttachmentController, :index
        post "/issues/:issue_id/attachments", AttachmentController, :create
        delete "/issues/:issue_id/attachments/:id", AttachmentController, :delete

        get "/issues/:issue_id/work-products", WorkProductController, :index
        post "/work-products", WorkProductController, :create

        get "/config/revisions", ConfigRevisionController, :index
        post "/config/revisions/:id/restore", ConfigRevisionController, :restore

        get "/sidebar-badges", SidebarBadgeController, :show

        get "/access", AccessController, :index
        post "/access/assign", AccessController, :assign
        delete "/access/:id", AccessController, :revoke

        resources "/execution-workspaces", ExecutionWorkspaceController, only: [:index, :create, :delete]

        resources "/plugins", PluginController, except: [:new, :edit] do
          get "/logs", PluginController, :logs, as: :logs
        end
      end

      # SSE streaming endpoints
      scope "/api/v1", CanopyWeb do
        pipe_through [:streaming, :authenticated, :workspace_context]

        get "/activity/stream", ActivityController, :stream
        get "/logs/stream", LogController, :stream
        get "/sessions/:session_id/stream", SessionController, :stream
      end

      unquote(routes)
    end
  end
end
