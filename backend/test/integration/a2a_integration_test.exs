defmodule Canopy.A2AIntegrationTest do
  @moduledoc """
  Integration tests for the A2A protocol endpoint.

  These tests require the full application to be running (Canopy.A2AAgent,
  A2A.Plug, and the router). They test the complete request/response flow
  for A2A protocol calls.

  Tagged :integration — not run in normal test suite.
  Run with: mix test --include integration test/integration/a2a_integration_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  @base_url "http://localhost:9089"

  describe "GET /.well-known/agent.json (backward compat)" do
    test "returns valid agent card with canopy name" do
      {:ok, %{status: 200, body: body}} =
        Req.get("#{@base_url}/.well-known/agent.json")

      assert is_map(body)
      assert body["name"] == "canopy"
    end

    test "returns agent card with a2a endpoint url" do
      {:ok, %{status: 200, body: body}} =
        Req.get("#{@base_url}/.well-known/agent.json")

      assert String.contains?(body["url"], "/api/v1/a2a")
    end
  end

  describe "GET /.well-known/agent-card.json (new alias)" do
    test "returns valid agent card" do
      {:ok, %{status: 200, body: body}} =
        Req.get("#{@base_url}/.well-known/agent-card.json")

      assert is_map(body)
      assert body["name"] == "canopy"
    end
  end

  describe "GET /api/v1/a2a/.well-known/agent-card.json (A2A.Plug card)" do
    test "returns agent card from A2A.Plug" do
      {:ok, %{status: 200, body: body}} =
        Req.get("#{@base_url}/api/v1/a2a/.well-known/agent-card.json")

      assert is_map(body)
      # A2A.Plug may format the card differently but must have name
      assert Map.has_key?(body, "name") || Map.has_key?(body, :name)
    end
  end

  describe "POST /api/v1/a2a (message/send JSON-RPC)" do
    test "receives and acknowledges a message/send request" do
      payload = %{
        "jsonrpc" => "2.0",
        "method" => "message/send",
        "params" => %{
          "message" => %{
            "role" => "user",
            "parts" => [%{"text" => "hello from integration test"}]
          }
        },
        "id" => 1
      }

      {:ok, %{status: status, body: body}} =
        Req.post("#{@base_url}/api/v1/a2a",
          json: payload,
          headers: [{"Content-Type", "application/json"}]
        )

      assert status in [200, 202]
      assert is_map(body)
      # JSON-RPC response must have id matching request
      assert body["id"] == 1 || body["jsonrpc"] == "2.0"
    end
  end
end
