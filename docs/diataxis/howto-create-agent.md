# How-To: Create a New Agent in Canopy

> **Problem:** You need to add an agent that processes documents (or any task type).
> **Time:** ~20 minutes
> **Result:** Agent registered, scheduled, and ready to receive tasks

---

## Prerequisites

- Canopy backend running: `cd canopy && make backend` (or `make dev`)
- Basic understanding of workspace protocol (see `explanation-workspace-protocol.md`)
- Access to the Canopy codebase

---

## Step 1: Define the Agent in Workspace Manifest

Edit `canopy/operations/<operation>/AGENTS.md` (or create it if missing).

Example: Adding a Document Processor agent to `dev-shop`:

```markdown
# Dev Shop — Agent Roster

## Document Processor

**Slug:** `document-processor`
**Role:** Processes uploaded documents (PDFs, docx, markdown)
**Hired:** 2026-03-25
**Budget:** $200/month
**Schedule:** `0 9 * * *` (9am daily)
**Capabilities:**
  - Extract text from documents
  - Classify document type
  - Generate summaries
  - Route to appropriate team

**Skills:**
  - parse/SKILL.md
  - classify/SKILL.md
  - route/SKILL.md

**Success Metrics:**
  - 95%+ extraction accuracy
  - <10s per document
  - 0 errors on 100-page docs

**Delegable:** Yes (can hand off to qa-engineer for verification)
```

**Why this matters:** This manifest tells the workspace:
- When to wake the agent (schedule)
- What it can do (capabilities)
- How much it costs (budget)
- Who can receive its delegated work (delegable)

---

## Step 2: Create the Agent Module

**File:** `canopy/backend/lib/canopy/agents/document_processor.ex`

```elixir
defmodule Canopy.Agents.DocumentProcessor do
  @moduledoc """
  Document Processor agent.

  Handles document ingestion, parsing, classification, and routing.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Called when a heartbeat wakes this agent.

  Receives a list of tasks assigned to this agent.
  Returns results or delegation directives.
  """
  def handle_message(message, state) do
    Logger.info("[DocumentProcessor] Received message: #{inspect(message.type)}")

    case message.type do
      "parse_document" ->
        handle_parse_document(message, state)

      "classify_document" ->
        handle_classify_document(message, state)

      "route_document" ->
        handle_route_document(message, state)

      unknown ->
        Logger.warning("[DocumentProcessor] Unknown message type: #{unknown}")
        {:error, :unknown_message_type}
    end
  end

  # ── Message Handlers ────────────────────────────────────

  defp handle_parse_document(%{"payload" => %{"document_path" => path}} = msg, _state) do
    Logger.info("[DocumentProcessor] Parsing document: #{path}")

    # Simulate document parsing
    case File.read(path) do
      {:ok, content} ->
        {
          :ok,
          %{
            "status" => "parsed",
            "document_id" => msg["document_id"],
            "text_length" => byte_size(content),
            "extracted_at" => DateTime.utc_now()
          }
        }

      {:error, reason} ->
        Logger.error("[DocumentProcessor] Failed to parse: #{inspect(reason)}")

        {
          :error,
          %{
            "status" => "parse_failed",
            "document_id" => msg["document_id"],
            "reason" => inspect(reason)
          }
        }
    end
  end

  defp handle_classify_document(%{"payload" => %{"document_type" => type}} = msg, _state) do
    Logger.info("[DocumentProcessor] Classifying document as: #{type}")

    {
      :ok,
      %{
        "status" => "classified",
        "document_id" => msg["document_id"],
        "document_type" => type,
        "confidence" => 0.95
      }
    }
  end

  defp handle_route_document(%{"payload" => %{"recipient" => recipient}} = msg, _state) do
    Logger.info("[DocumentProcessor] Routing to: #{recipient}")

    {
      :ok,
      %{
        "status" => "routed",
        "document_id" => msg["document_id"],
        "routed_to" => recipient,
        "timestamp" => DateTime.utc_now()
      }
    }
  end

  # ── GenServer Callbacks ─────────────────────────────────

  @impl true
  def init(opts) do
    Logger.info("[DocumentProcessor] Starting up")
    {:ok, %{"config" => opts}}
  end

  @impl true
  def handle_call({:process, message}, _from, state) do
    result = handle_message(message, state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:async, message}, state) do
    Logger.info("[DocumentProcessor] Processing async: #{inspect(message.type)}")
    {:noreply, state}
  end
end
```

**Key patterns:**
- `start_link/1` — GenServer entry point
- `handle_message/2` — main work loop (called by heartbeat)
- Pattern matching on `message.type` — dispatches to specific handlers
- `{:ok, result}` or `{:error, reason}` — standard response format

---

## Step 3: Implement the GenServer Callbacks

Your agent is a GenServer (long-lived Elixir process).

Add these three callback implementations:

```elixir
@impl true
def init(opts) do
  state = %{
    "config" => opts,
    "processed_count" => 0,
    "error_count" => 0
  }
  {:ok, state}
end

@impl true
def handle_call({:process, message}, _from, state) do
  result = handle_message(message, state)

  # Track metrics
  state =
    case result do
      {:ok, _} -> update_in(state, ["processed_count"], &(&1 + 1))
      {:error, _} -> update_in(state, ["error_count"], &(&1 + 1))
    end

  {:reply, result, state}
end

@impl true
def handle_cast({:notify, msg}, state) do
  Logger.info("[DocumentProcessor] Notification: #{msg}")
  {:noreply, state}
end

def handle_info({:timeout, ref, :cleanup}, state) do
  Logger.info("[DocumentProcessor] Running cleanup")
  {:noreply, state}
end
```

---

## Step 4: Register in Supervisor

Edit `canopy/backend/lib/canopy/application.ex`

Find the supervision tree and add your agent:

```elixir
def start(_type, _args) do
  children = [
    CanopyWeb.Telemetry,
    Canopy.Repo,
    Phoenix.PubSub,

    # Your new agent
    {Canopy.Agents.DocumentProcessor, []},

    CanopyWeb.Endpoint
  ]

  opts = [strategy: :one_for_one, name: Canopy.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Why this matters:**
- If your agent crashes, the supervisor restarts it automatically
- All supervised processes are coordinated by OTP
- Heartbeat calls your agent only if it's alive

---

## Step 5: Add Tests

**File:** `canopy/backend/test/canopy/agents/document_processor_test.exs`

```elixir
defmodule Canopy.Agents.DocumentProcessorTest do
  use ExUnit.Case

  setup do
    {:ok, pid} = start_supervised(Canopy.Agents.DocumentProcessor)
    {:ok, agent: pid}
  end

  test "parses document successfully", %{agent: pid} do
    # Create a temporary document
    {:ok, temp_path} = Briefly.create()
    File.write!(temp_path, "Test document content")

    message = %{
      "type" => "parse_document",
      "document_id" => "doc-1",
      "payload" => %{"document_path" => temp_path}
    }

    result = GenServer.call(pid, {:process, message})

    assert {:ok, response} = result
    assert response["status"] == "parsed"
    assert response["document_id"] == "doc-1"
    assert response["text_length"] > 0
  end

  test "classifies document", %{agent: pid} do
    message = %{
      "type" => "classify_document",
      "document_id" => "doc-2",
      "payload" => %{"document_type" => "technical_spec"}
    }

    result = GenServer.call(pid, {:process, message})

    assert {:ok, response} = result
    assert response["status"] == "classified"
    assert response["confidence"] >= 0.8
  end

  test "handles unknown message type", %{agent: pid} do
    message = %{
      "type" => "unknown_operation",
      "document_id" => "doc-3",
      "payload" => %{}
    }

    result = GenServer.call(pid, {:process, message})

    assert {:error, :unknown_message_type} = result
  end
end
```

**Run tests:**
```bash
cd canopy/backend
mix test test/canopy/agents/document_processor_test.exs
```

---

## Step 6: Register Heartbeat Schedule

Add a cron schedule entry in `canopy/backend/priv/repo/seeds/seeds.exs` (or create a migration):

```elixir
# Define the agent
agent_attrs = %{
  "slug" => "document-processor",
  "name" => "Document Processor",
  "description" => "Processes documents: parsing, classification, routing",
  "role" => "document_processor",
  "is_active" => true,
  "capabilities" => ["parse", "classify", "route"],
  "budget_monthly_usd" => 200,
  "schedule_cron" => "0 9 * * *"  # 9am daily
}

{:ok, agent} = Canopy.Agents.create_agent(agent_attrs)
```

**Or register manually in the UI:**
```
POST /api/agents
{
  "slug": "document-processor",
  "name": "Document Processor",
  "schedule_cron": "0 9 * * *"
}
```

---

## Step 7: Test with HTTP

Restart Canopy and test via HTTP:

```bash
# Start the backend
cd canopy && make backend

# In another terminal, send a message to your agent
curl -X POST http://localhost:9089/api/agents/document-processor/message \
  -H "Content-Type: application/json" \
  -d '{
    "type": "parse_document",
    "document_id": "doc-1",
    "payload": {
      "document_path": "/tmp/test.txt"
    }
  }'
```

Expected response:
```json
{
  "status": "parsed",
  "document_id": "doc-1",
  "text_length": 123,
  "extracted_at": "2026-03-25T14:30:00Z"
}
```

---

## Step 8: Add to A2A Registry (Optional)

If other agents need to call your agent:

**File:** `canopy/backend/lib/canopy/agents/registry.ex`

```elixir
def discover_agent(slug) do
  case slug do
    "document-processor" ->
      {:ok, %{
        "name" => "Document Processor",
        "endpoint" => "http://localhost:9089/api/agents/document-processor/message",
        "capabilities" => ["parse", "classify", "route"],
        "timeout_ms" => 30_000
      }}

    _ -> {:error, :agent_not_found}
  end
end
```

Now other agents can call your agent via A2A:

```elixir
{:ok, response} = Canopy.Agents.A2AService.call_agent(
  "http://localhost:9089/api/agents/document-processor/message",
  %{"type" => "parse_document", "document_id" => "doc-1"}
)
```

---

## Checklist: Agent is Production-Ready

Before shipping, verify:

- [ ] Agent module created and compiles: `mix compile`
- [ ] Tests passing: `mix test test/canopy/agents/document_processor_test.exs`
- [ ] No compiler warnings: `mix compile --warnings-as-errors`
- [ ] Agent registered in supervisor (application.ex)
- [ ] Agent registered in heartbeat schedule (seeds or API)
- [ ] Manual HTTP test succeeds (curl test above)
- [ ] A2A registry updated (if agent is discoverable)
- [ ] AGENTS.md manifest updated
- [ ] Documentation added (capabilities, message types, examples)

---

## Troubleshooting

### Agent not waking on schedule
- Check: Is the cron schedule correct? `mix ecto.query "SELECT schedule_cron FROM agents WHERE slug = 'document-processor'"`
- Check: Is Canopy.Scheduler running? `mix osa.serve` should show "Scheduler started"
- Check: Restart scheduler: call `Canopy.Scheduler.load_schedules()`

### Agent crashes immediately
- Check: Logs — `docker logs -f canopy-backend` or `tail -f backend/log/dev.log`
- Check: Is the agent module valid? `iex -S mix` then `Canopy.Agents.DocumentProcessor.start_link([])`
- Check: Did you forget to add a callback? (init, handle_call, etc.)

### Message handling fails
- Check: Does message type match a handler clause? Add `_ -> {:error, :unknown_type}`
- Check: Are you returning `{:ok, result}` or `{:error, reason}`? (not bare atoms)
- Check: Test locally: `GenServer.call(pid, {:process, message})`

