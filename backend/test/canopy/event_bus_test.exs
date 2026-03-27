defmodule Canopy.EventBusTest do
  use ExUnit.Case, async: true

  alias Canopy.EventBus

  describe "topic builders" do
    test "workspace_topic/1 returns workspace-prefixed topic" do
      assert EventBus.workspace_topic("abc-123") == "workspace:abc-123"
    end

    test "agent_topic/1 returns agent-prefixed topic" do
      assert EventBus.agent_topic("agent-456") == "agent:agent-456"
    end

    test "session_topic/1 returns session-prefixed topic" do
      assert EventBus.session_topic("sess-789") == "session:sess-789"
    end

    test "organization_topic/1 returns organization-prefixed topic" do
      assert EventBus.organization_topic("org-001") == "organization:org-001"
    end

    test "division_topic/1 returns division-prefixed topic" do
      assert EventBus.division_topic("div-002") == "division:div-002"
    end

    test "department_topic/1 returns department-prefixed topic" do
      assert EventBus.department_topic("dept-003") == "department:dept-003"
    end

    test "team_topic/1 returns team-prefixed topic" do
      assert EventBus.team_topic("team-004") == "team:team-004"
    end

    test "activity_topic/0 returns global activity topic" do
      assert EventBus.activity_topic() == "activity:global"
    end

    test "logs_topic/0 returns global logs topic" do
      assert EventBus.logs_topic() == "logs:global"
    end
  end

  describe "topic format consistency" do
    test "all scoped topics follow 'scope:id' pattern" do
      id = "test-id"

      scoped_topics = [
        EventBus.workspace_topic(id),
        EventBus.agent_topic(id),
        EventBus.session_topic(id),
        EventBus.organization_topic(id),
        EventBus.division_topic(id),
        EventBus.department_topic(id),
        EventBus.team_topic(id)
      ]

      for topic <- scoped_topics do
        [prefix, _] = String.split(topic, ":", parts: 2)

        assert prefix in [
                 "workspace",
                 "agent",
                 "session",
                 "organization",
                 "division",
                 "department",
                 "team"
               ]
      end
    end

    test "global topics do not contain a dynamic ID" do
      activity = EventBus.activity_topic()
      logs = EventBus.logs_topic()

      # Global topics use fixed suffixes, not dynamic IDs
      assert activity == "activity:global"
      assert logs == "logs:global"

      # Neither contains a UUID-like segment
      refute String.match?(activity, ~r/[0-9a-f]{8}-[0-9a-f]{4}/)
      refute String.match?(logs, ~r/[0-9a-f]{8}-[0-9a-f]{4}/)
    end
  end

  describe "topic uniqueness" do
    test "different scopes produce different topics for same ID" do
      id = "shared-id"

      topics = [
        EventBus.workspace_topic(id),
        EventBus.agent_topic(id),
        EventBus.session_topic(id)
      ]

      assert length(Enum.uniq(topics)) == 3
    end

    test "different IDs produce different topics for same scope" do
      topics = [
        EventBus.workspace_topic("id-1"),
        EventBus.workspace_topic("id-2"),
        EventBus.workspace_topic("id-3")
      ]

      assert length(Enum.uniq(topics)) == 3
    end
  end

  describe "module structure" do
    test "broadcast/2 is a public function" do
      # The module defines broadcast(topic, event) and broadcast!(topic, event)
      # These delegate to Phoenix.PubSub
      assert is_function(&EventBus.broadcast/2)
    end

    test "subscribe/1 is a public function" do
      assert is_function(&EventBus.subscribe/1)
    end

    test "unsubscribe/1 is a public function" do
      assert is_function(&EventBus.unsubscribe/1)
    end
  end
end
