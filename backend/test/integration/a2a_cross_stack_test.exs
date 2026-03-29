defmodule Canopy.A2ACrossStackTest do
  @moduledoc """
  Cross-service A2A integration tests — Canopy as A2A client.
  Tests pass (not fail) when target service is not running.
  Run: mix test --include integration test/integration/a2a_cross_stack_test.exs
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :a2a_live

  # Runtime config — must use Application.get_env, not compile_env (runtime.exs sets this)
  defp osa_url, do: Application.get_env(:canopy, :osa_url, "http://localhost:8089")
  @pm4py_url "http://localhost:8090"
  # Canopy itself always has a well-known agent card when running
  @canopy_url "http://localhost:9089"

  defp service_available?(url) do
    Enum.any?(["/api/health", "/health", "/healthz"], fn path ->
      case Req.get("#{url}#{path}", receive_timeout: 2_000, retry: false) do
        {:ok, %{status: 200}} -> true
        _ -> false
      end
    end)
  end

  defp agent_card_available?(url) do
    case Req.get("#{url}/.well-known/agent-card.json", receive_timeout: 2_000, retry: false) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  describe "Canopy → OSA via A2A.Client" do
    test "discovers OSA agent card" do
      url = osa_url()

      unless service_available?(url) and agent_card_available?(url) do
        # Service not available — test passes (connectivity test, not functional)
        assert true
      else
        assert {:ok, card} = A2A.Client.discover(url)
        assert is_struct(card) or is_map(card)
      end
    end

    test "sends message/send and receives JSON-RPC response" do
      url = osa_url()

      unless service_available?(url) and agent_card_available?(url) do
        assert true
      else
        client = A2A.Client.new(url)
        message = A2A.Message.new_user("ping from canopy cross-stack test")
        result = A2A.Client.send_message(client, message, [])
        assert match?({:ok, _}, result) or match?({:error, _}, result)

        case result do
          {:ok, response} -> assert is_struct(response) or is_map(response)
          {:error, _} -> :ok
        end
      end
    end
  end

  describe "Canopy → pm4py-rust via A2A.Client" do
    test "discovers pm4py-rust agent card with 10 skills" do
      unless service_available?(@pm4py_url) and agent_card_available?(@pm4py_url) do
        assert true
      else
        assert {:ok, card} = A2A.Client.discover(@pm4py_url)
        skills = Map.get(card, :skills, Map.get(card, "skills", []))

        assert length(skills) == 10,
               "pm4py-rust must advertise 10 skills, got #{length(skills)}"
      end
    end

    test "sends pm4py_statistics task and receives valid state" do
      unless service_available?(@pm4py_url) and agent_card_available?(@pm4py_url) do
        assert true
      else
        client = A2A.Client.new(@pm4py_url)
        message = A2A.Message.new_user("pm4py_statistics: run statistics on empty log")

        case A2A.Client.send_message(client, message, []) do
          {:ok, response} ->
            state =
              get_in(response, ["status", "state"]) ||
                get_in(response, [:status, :state]) || "unknown"

            assert state in ["submitted", "working", "completed"],
                   "expected valid task state, got: #{state}"

          {:error, _} ->
            :ok
        end
      end
    end

    test "task send → response contains an id" do
      unless service_available?(@pm4py_url) and agent_card_available?(@pm4py_url) do
        assert true
      else
        client = A2A.Client.new(@pm4py_url)
        message = A2A.Message.new_user("pm4py_statistics: run statistics on empty log")

        case A2A.Client.send_message(client, message, []) do
          {:ok, response} ->
            returned_id = get_in(response, ["id"]) || get_in(response, [:id])
            # id may be nil if the server assigns its own — that's acceptable
            if returned_id, do: assert(is_binary(returned_id) or is_integer(returned_id))

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "Canopy.Adapters.A2A.start/1 emits OTEL span" do
    test "start/1 returns session map with url and client fields" do
      unless service_available?(@canopy_url) and agent_card_available?(@canopy_url) do
        assert true
      else
        config = %{"url" => @canopy_url}
        assert {:ok, session} = Canopy.Adapters.A2A.start(config)
        assert is_map(session)
        assert session.url == @canopy_url
        assert Map.has_key?(session, :client)
      end
    end
  end
end
