defmodule Canopy.Adapters.A2ATest do
  @moduledoc """
  Chicago TDD tests for Canopy.Adapters.A2A.

  Tests pure adapter metadata callbacks (type, name, capabilities) that
  don't require network connectivity. Integration tests for start/send_message
  are tagged :integration.
  """

  use ExUnit.Case, async: true

  alias Canopy.Adapters.A2A

  describe "type/0" do
    test "returns a2a string identifier" do
      assert A2A.type() == "a2a"
    end
  end

  describe "name/0" do
    test "returns A2A Protocol display name" do
      assert A2A.name() == "A2A Protocol"
    end
  end

  describe "supports_session?/0" do
    test "returns false — A2A adapter is stateless" do
      assert A2A.supports_session?() == false
    end
  end

  describe "supports_concurrent?/0" do
    test "returns true — multiple concurrent A2A calls allowed" do
      assert A2A.supports_concurrent?() == true
    end
  end

  describe "capabilities/0" do
    test "returns list of capabilities" do
      caps = A2A.capabilities()
      assert is_list(caps)
      assert length(caps) >= 3
    end

    test "includes chat capability" do
      assert :chat in A2A.capabilities()
    end

    test "includes task_delegation capability" do
      assert :task_delegation in A2A.capabilities()
    end

    test "includes agent_discovery capability" do
      assert :agent_discovery in A2A.capabilities()
    end
  end

  describe "stop/1" do
    test "returns :ok for any session" do
      assert :ok == A2A.stop(%{url: "http://example.com/a2a"})
      assert :ok == A2A.stop(%{})
    end
  end

  describe "start/1 — validation" do
    test "returns error when url is missing" do
      assert {:error, {:missing_config, _}} = A2A.start(%{})
    end

    test "returns error when url is empty string" do
      assert {:error, {:missing_config, _}} = A2A.start(%{"url" => ""})
    end

    @tag :integration
    test "returns ok with session when url is valid and agent is reachable" do
      # Requires a live A2A agent at the URL
      {:ok, session} = A2A.start(%{"url" => "http://localhost:9089/api/v1/a2a"})
      assert is_map(session)
      assert Map.has_key?(session, :url)
      assert Map.has_key?(session, :client)
    end
  end
end
