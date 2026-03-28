defmodule CanopyWeb.WellKnownController do
  use CanopyWeb, :controller

  @doc """
  GET /.well-known/agent.json

  Returns the A2A-standard agent discovery card for Canopy.
  This endpoint enables other systems (OSA, BusinessOS, pm4py-rust)
  to discover Canopy as an A2A agent.
  """
  def agent_card(conn, _params) do
    version =
      case Application.spec(:canopy, :vsn) do
        nil -> "1.0.0"
        vsn -> to_string(vsn)
      end

    card = %{
      name: "canopy",
      display_name: "Canopy",
      description:
        "Workspace orchestration protocol and command center for AI agent systems " <>
          "with 160+ agents, heartbeat dispatch, and process mining integration.",
      version: version,
      url: "http://localhost:9089/api/v1/a2a",
      capabilities: ["streaming", "tools", "stateless"],
      skills: [
        %{
          name: "workspace_coordination",
          description: "Coordinate multi-agent workspaces and agent hiring"
        },
        %{
          name: "heartbeat_dispatch",
          description: "Agent heartbeat scheduling and task dispatch"
        },
        %{
          name: "process_mining",
          description: "Process mining via BusinessOS integration"
        },
        %{
          name: "agent_orchestration",
          description: "Orchestrate 160+ agents via heartbeat protocol"
        }
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(card)
  end
end
