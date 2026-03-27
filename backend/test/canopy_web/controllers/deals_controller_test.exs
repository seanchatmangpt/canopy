defmodule CanopyWeb.DealsControllerTest do
  use CanopyWeb.ConnCase

  alias Canopy.Repo
  alias Canopy.Schemas.Deal
  alias Canopy.Schemas.Workspace
  alias Canopy.Schemas.User

  @moduletag :skip

  setup do
    user = insert_user()
    workspace = insert_workspace(user)
    {:ok, user: user, workspace: workspace}
  end

  describe "index/2" do
    test "lists all deals in workspace", %{conn: conn, workspace: workspace, user: user} do
      deal1 = insert_deal(workspace, user, %{"name" => "Deal 1"})
      deal2 = insert_deal(workspace, user, %{"name" => "Deal 2"})

      conn = get(conn, ~p"/api/v1/deals?workspace_id=#{workspace.id}")

      assert json_response(conn, 200)["deals"]
             |> Enum.map(& &1["id"])
             |> Enum.sort() == [deal1.id, deal2.id] |> Enum.sort()
    end

    test "filters deals by status", %{conn: conn, workspace: workspace, user: user} do
      deal_draft = insert_deal(workspace, user, %{"name" => "Draft", "status" => "draft"})
      _deal_signed = insert_deal(workspace, user, %{"name" => "Signed", "status" => "signed"})

      conn =
        get(conn, ~p"/api/v1/deals?workspace_id=#{workspace.id}&status=draft")

      deals = json_response(conn, 200)["deals"]
      assert length(deals) == 1
      assert hd(deals)["id"] == deal_draft.id
    end

    test "filters deals by deal_type", %{conn: conn, workspace: workspace, user: user} do
      insert_deal(workspace, user, %{"name" => "Simple", "deal_type" => "simple_agreement"})
      insert_deal(workspace, user, %{"name" => "Equity", "deal_type" => "equity_agreement"})

      conn =
        get(conn, ~p"/api/v1/deals?workspace_id=#{workspace.id}&deal_type=simple_agreement")

      deals = json_response(conn, 200)["deals"]
      assert length(deals) == 1
      assert hd(deals)["deal_type"] == "simple_agreement"
    end
  end

  describe "create/2" do
    test "creates a new deal", %{conn: conn, workspace: workspace, user: user} do
      deal_params = %{
        "name" => "New Deal",
        "deal_type" => "simple_agreement",
        "description" => "Test deal",
        "amount_cents" => 100_000,
        "currency" => "USD",
        "counterparty" => "ACME Corp",
        "workspace_id" => workspace.id,
        "created_by_id" => user.id
      }

      conn = post(conn, ~p"/api/v1/deals", deal_params)

      assert response = json_response(conn, 201)
      assert response["deal"]["name"] == "New Deal"
      assert response["deal"]["status"] == "draft"
      assert response["deal"]["amount_cents"] == 100_000
    end

    test "returns validation error on missing required fields", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/deals", %{
          "name" => "Incomplete"
        })

      assert json_response(conn, 422)["error"] == "validation_failed"
    end

    test "validates currency format", %{conn: conn, workspace: workspace, user: user} do
      deal_params = %{
        "name" => "Bad Currency",
        "deal_type" => "simple_agreement",
        "currency" => "INVALID",
        "workspace_id" => workspace.id,
        "created_by_id" => user.id
      }

      conn = post(conn, ~p"/api/v1/deals", deal_params)

      assert json_response(conn, 422)["error"] == "validation_failed"
    end

    test "accepts optional fields", %{conn: conn, workspace: workspace, user: user} do
      deal_params = %{
        "name" => "Deal with metadata",
        "deal_type" => "loan_agreement",
        "workspace_id" => workspace.id,
        "created_by_id" => user.id,
        "metadata" => %{"key" => "value"}
      }

      conn = post(conn, ~p"/api/v1/deals", deal_params)

      assert response = json_response(conn, 201)
      assert response["deal"]["metadata"]["key"] == "value"
    end
  end

  describe "show/2" do
    test "shows a specific deal", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user)

      conn = get(conn, ~p"/api/v1/deals/#{deal.id}")

      assert response = json_response(conn, 200)
      assert response["deal"]["id"] == deal.id
      assert response["deal"]["name"] == deal.name
    end

    test "returns 404 for non-existent deal", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/deals/00000000-0000-0000-0000-000000000000")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "update/2" do
    test "updates a deal", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user)

      update_params = %{
        "name" => "Updated Deal Name",
        "description" => "New description"
      }

      conn = put(conn, ~p"/api/v1/deals/#{deal.id}", update_params)

      assert response = json_response(conn, 200)
      assert response["deal"]["name"] == "Updated Deal Name"
      assert response["deal"]["description"] == "New description"
    end

    test "transitions deal status", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user, %{"status" => "draft"})

      conn = put(conn, ~p"/api/v1/deals/#{deal.id}", %{"status" => "negotiation"})

      assert response = json_response(conn, 200)
      assert response["deal"]["status"] == "negotiation"
    end

    test "validates status transition", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user)

      conn = put(conn, ~p"/api/v1/deals/#{deal.id}", %{"status" => "invalid_status"})

      assert json_response(conn, 422)["error"] == "validation_failed"
    end

    test "returns 404 for non-existent deal", %{conn: conn} do
      conn =
        put(conn, ~p"/api/v1/deals/00000000-0000-0000-0000-000000000000", %{
          "name" => "Updated"
        })

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "delete/2" do
    test "deletes a draft deal", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user, %{"status" => "draft"})

      conn = delete(conn, ~p"/api/v1/deals/#{deal.id}")

      assert json_response(conn, 200)["ok"] == true
      assert Repo.get(Deal, deal.id) == nil
    end

    test "prevents deletion of non-draft deal", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user, %{"status" => "signed"})

      conn = delete(conn, ~p"/api/v1/deals/#{deal.id}")

      assert json_response(conn, 422)["error"] == "cannot_delete_non_draft"
      assert Repo.get(Deal, deal.id) != nil
    end

    test "returns 404 for non-existent deal", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/deals/00000000-0000-0000-0000-000000000000")

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "sign/2" do
    test "signs a deal and sets started_at", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user, %{"status" => "approved"})

      conn = post(conn, ~p"/api/v1/deals/#{deal.id}/sign", %{})

      assert response = json_response(conn, 200)
      assert response["deal"]["status"] == "signed"
      assert response["deal"]["started_at"] != nil
    end

    test "returns 404 for non-existent deal", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/deals/00000000-0000-0000-0000-000000000000/sign", %{})

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "complete/2" do
    test "completes a deal and sets completed_at", %{conn: conn, workspace: workspace, user: user} do
      deal = insert_deal(workspace, user, %{"status" => "active"})

      conn = post(conn, ~p"/api/v1/deals/#{deal.id}/complete", %{})

      assert response = json_response(conn, 200)
      assert response["deal"]["status"] == "completed"
      assert response["deal"]["completed_at"] != nil
    end

    test "returns 404 for non-existent deal", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/deals/00000000-0000-0000-0000-000000000000/complete", %{})

      assert json_response(conn, 404)["error"] == "not_found"
    end
  end

  describe "templates/2" do
    test "lists available contract templates", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/deals/templates")

      assert response = json_response(conn, 200)
      templates = response["templates"]
      assert length(templates) > 0
      assert Enum.any?(templates, fn t -> t["key"] == "simple_agreement" end)
      assert Enum.any?(templates, fn t -> t["key"] == "equity_agreement" end)
      assert Enum.any?(templates, fn t -> t["key"] == "loan_agreement" end)
      assert Enum.any?(templates, fn t -> t["key"] == "service_agreement" end)
    end

    test "template metadata is correct", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/deals/templates")

      templates = json_response(conn, 200)["templates"]
      template = Enum.find(templates, fn t -> t["key"] == "simple_agreement" end)

      assert template["name"] == "Simple Agreement for Future Tokens"
      assert template["description"] != nil
    end
  end

  describe "render_contract/2" do
    test "renders a contract template with terms", %{conn: conn} do
      render_params = %{
        "template_key" => "simple_agreement",
        "terms" => %{
          "issuer" => "Alice",
          "investor" => "Bob",
          "amount" => 1000,
          "price_per_token" => 10.5,
          "delivery_date" => "2026-12-31"
        }
      }

      conn = post(conn, ~p"/api/v1/deals/render-contract", render_params)

      assert response = json_response(conn, 200)
      assert response["contract"]["name"] != nil
      assert response["contract"]["terms"]["issuer"] == "Alice"
    end

    test "returns 404 for non-existent template", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/deals/render-contract", %{
          "template_key" => "nonexistent",
          "terms" => %{}
        })

      assert json_response(conn, 404)["error"] == "template_not_found"
    end

    test "validates template requirements before rendering", %{conn: conn} do
      render_params = %{
        "template_key" => "simple_agreement",
        "terms" => %{
          "issuer" => "Alice"
        }
      }

      conn = post(conn, ~p"/api/v1/deals/render-contract", render_params)

      assert json_response(conn, 422)["error"] != nil
    end
  end

  describe "validate_contract/2" do
    test "validates contract terms against template", %{conn: conn} do
      validate_params = %{
        "template_key" => "loan_agreement",
        "terms" => %{
          "lender" => "Bank ABC",
          "borrower" => "Company XYZ",
          "principal_amount" => 500_000,
          "interest_rate_percent" => 5.5,
          "term_months" => 60
        }
      }

      conn = post(conn, ~p"/api/v1/deals/validate-contract", validate_params)

      assert response = json_response(conn, 200)
      assert response["valid"] == true
    end

    test "rejects invalid interest rate", %{conn: conn} do
      validate_params = %{
        "template_key" => "loan_agreement",
        "terms" => %{
          "lender" => "Bank ABC",
          "borrower" => "Company XYZ",
          "principal_amount" => 500_000,
          "interest_rate_percent" => 150.0,
          "term_months" => 60
        }
      }

      conn = post(conn, ~p"/api/v1/deals/validate-contract", validate_params)

      assert response = json_response(conn, 422)
      assert response["valid"] == false
    end

    test "validates required fields", %{conn: conn} do
      validate_params = %{
        "template_key" => "equity_agreement",
        "terms" => %{
          "company" => "Startup Inc"
        }
      }

      conn = post(conn, ~p"/api/v1/deals/validate-contract", validate_params)

      assert response = json_response(conn, 422)
      assert response["valid"] == false
      assert response["error"] != nil
    end
  end

  # --- Private Helpers ---

  defp insert_user do
    {:ok, user} =
      Repo.insert(%User{
        email: "test#{System.unique_integer()}@example.com",
        password_hash: "hash",
        name: "Test User"
      })

    user
  end

  defp insert_workspace(user) do
    {:ok, workspace} =
      Repo.insert(%Workspace{
        name: "Test Workspace",
        owner_id: user.id
      })

    workspace
  end

  defp insert_deal(workspace, user, attrs \\ %{}) do
    defaults = %{
      "name" => "Test Deal",
      "deal_type" => "simple_agreement",
      "status" => "draft",
      "amount_cents" => 100_000,
      "currency" => "USD",
      "workspace_id" => workspace.id,
      "created_by_id" => user.id
    }

    attrs = Map.merge(defaults, attrs)

    {:ok, deal} =
      Deal.changeset(%Deal{}, attrs)
      |> Repo.insert()

    deal
  end
end
