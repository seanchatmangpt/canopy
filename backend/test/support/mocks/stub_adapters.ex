defmodule Test.Mocks.StubAdapters do
  @moduledoc """
  Stub adapter implementations for testing.

  These adapters are intentionally incomplete and designed ONLY for testing
  purposes. They demonstrate the adapter interface but always return run.failed.

  Production systems must use real adapters (OSA, BusinessOS, etc.).
  """

  # ── Gemini Stub ─────────────────────────────────────────────────────────

  defmodule Gemini do
    @moduledoc """
    Gemini CLI adapter stub for testing.

    To implement a real Gemini adapter:
    1. Wrap the Gemini CLI tool or REST API
    2. Authenticate via GEMINI_API_KEY in config
    3. Spawn sessions using the Gemini generateContent endpoint
    4. Map responses to run.delta events matching Canopy.Adapter spec
    """

    @behaviour Canopy.Adapter

    @impl true
    def type, do: "gemini"

    @impl true
    def name, do: "Gemini CLI (Stub)"

    @impl true
    def supports_session?, do: true

    @impl true
    def supports_concurrent?, do: true

    @impl true
    def capabilities, do: [:chat, :code_execution]

    @impl true
    def start(_config), do: {:ok, %{status: :stub}}

    @impl true
    def stop(_), do: :ok

    @impl true
    def execute_heartbeat(_params), do: stub_stream()

    @impl true
    def send_message(_session, _message), do: stub_stream()

    defp stub_stream do
      Stream.resource(
        fn -> :once end,
        fn
          :once ->
            {[
               %{
                 event_type: "run.failed",
                 data: %{
                   "error" => "Gemini adapter is a stub (test-only)",
                   "adapter" => type(),
                   "hint" =>
                     "Implement real Gemini adapter by wrapping Gemini API. See module docs."
                 },
                 tokens: 0
               }
             ], :done}

          :done ->
            {:halt, :done}
        end,
        fn _ -> :ok end
      )
    end
  end

  # ── Cursor Stub ────────────────────────────────────────────────────────

  defmodule Cursor do
    @moduledoc """
    Cursor background agent adapter stub for testing.

    To implement a real Cursor adapter:
    1. Wire up Cursor background-agent API
    2. Authenticate via Cursor API key in config
    3. Open session over HTTP/WebSocket transport
    4. Stream run.delta events matching Canopy.Adapter spec
    """

    @behaviour Canopy.Adapter

    @impl true
    def type, do: "cursor"

    @impl true
    def name, do: "Cursor (Stub)"

    @impl true
    def supports_session?, do: true

    @impl true
    def supports_concurrent?, do: false

    @impl true
    def capabilities, do: [:chat, :code_execution, :file_edit]

    @impl true
    def start(_config), do: {:ok, %{status: :stub}}

    @impl true
    def stop(_), do: :ok

    @impl true
    def execute_heartbeat(_params), do: stub_stream()

    @impl true
    def send_message(_session, _message), do: stub_stream()

    defp stub_stream do
      Stream.resource(
        fn -> :once end,
        fn
          :once ->
            {[
               %{
                 event_type: "run.failed",
                 data: %{
                   "error" => "Cursor adapter is a stub (test-only)",
                   "adapter" => type(),
                   "hint" => "Implement real Cursor adapter. See module docs."
                 },
                 tokens: 0
               }
             ], :done}

          :done ->
            {:halt, :done}
        end,
        fn _ -> :ok end
      )
    end
  end

  # ── OpenClaw Stub ───────────────────────────────────────────────────────

  defmodule OpenClaw do
    @moduledoc """
    OpenClaw WebSocket adapter stub for testing.

    To implement a real OpenClaw adapter:
    1. Establish WebSocket connection to OpenClaw server
    2. Authenticate using OpenClaw API credentials in config
    3. Open persistent session over WebSocket transport
    4. Stream run.delta events matching Canopy.Adapter spec
    """

    @behaviour Canopy.Adapter

    @impl true
    def type, do: "openclaw"

    @impl true
    def name, do: "OpenClaw (Stub)"

    @impl true
    def supports_session?, do: true

    @impl true
    def supports_concurrent?, do: false

    @impl true
    def capabilities, do: [:chat, :tools]

    @impl true
    def start(_config), do: {:ok, %{status: :stub}}

    @impl true
    def stop(_), do: :ok

    @impl true
    def execute_heartbeat(_params), do: stub_stream()

    @impl true
    def send_message(_session, _message), do: stub_stream()

    defp stub_stream do
      Stream.resource(
        fn -> :once end,
        fn
          :once ->
            {[
               %{
                 event_type: "run.failed",
                 data: %{
                   "error" => "OpenClaw adapter is a stub (test-only)",
                   "adapter" => type(),
                   "hint" => "Implement real OpenClaw adapter. See module docs."
                 },
                 tokens: 0
               }
             ], :done}

          :done ->
            {:halt, :done}
        end,
        fn _ -> :ok end
      )
    end
  end
end
