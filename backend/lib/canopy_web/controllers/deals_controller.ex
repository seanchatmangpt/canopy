defmodule CanopyWeb.DealsController do
  use CanopyWeb, :controller

  alias Canopy.Repo
  alias Canopy.Schemas.Deal
  alias Canopy.Deals.ContractTemplate
  import Ecto.Query

  @doc """
  List all deals in the workspace, with optional filtering.

  Query params:
  - status: filter by deal status
  - deal_type: filter by deal type
  - workspace_id: required, workspace scope
  """
  def index(conn, params) do
    workspace_id = params["workspace_id"]

    query = from d in Deal, order_by: [desc: d.inserted_at]

    query =
      if workspace_id,
        do: where(query, [d], d.workspace_id == ^workspace_id),
        else: query

    query =
      if params["status"],
        do: where(query, [d], d.status == ^params["status"]),
        else: query

    query =
      if params["deal_type"],
        do: where(query, [d], d.deal_type == ^params["deal_type"]),
        else: query

    deals =
      query
      |> Repo.all()
      |> Enum.map(&serialize/1)

    json(conn, %{deals: deals})
  end

  @doc """
  Create a new deal.

  Body params:
  - name: string, required
  - deal_type: string, required (simple_agreement, equity_agreement, loan_agreement, service_agreement)
  - description: string, optional
  - amount_cents: integer, optional
  - currency: string, default: USD
  - counterparty: string, optional
  - contract_template_id: uuid, optional
  - terms: map, optional
  - workspace_id: uuid, required
  - created_by_id: uuid, required
  """
  def create(conn, params) do
    changeset = Deal.changeset(%Deal{}, params)

    case Repo.insert(changeset) do
      {:ok, deal} ->
        conn |> put_status(201) |> json(%{deal: serialize(deal)})

      {:error, cs} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(cs)})
    end
  end

  @doc """
  Show a specific deal by ID.
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(Deal, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      deal ->
        json(conn, %{deal: serialize(deal)})
    end
  end

  @doc """
  Update a deal.

  Supports partial updates. Status transitions validated via transition_changeset.
  """
  def update(conn, %{"id" => id} = params) do
    case Repo.get(Deal, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      deal ->
        changeset =
          if new_status = params["status"] do
            Deal.transition_changeset(deal, new_status)
          else
            Deal.changeset(deal, params)
          end

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{deal: serialize(updated)})

          {:error, cs} ->
            conn
            |> put_status(422)
            |> json(%{error: "validation_failed", details: format_errors(cs)})
        end
    end
  end

  @doc """
  Delete a deal.

  Only draft deals can be deleted.
  """
  def delete(conn, %{"id" => id}) do
    case Repo.get(Deal, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      deal ->
        if deal.status == "draft" do
          Repo.delete!(deal)
          json(conn, %{ok: true})
        else
          conn
          |> put_status(422)
          |> json(%{
            error: "cannot_delete_non_draft",
            message: "Only draft deals can be deleted"
          })
        end
    end
  end

  @doc """
  Sign a deal (transition to signed status with timestamp).

  Sets started_at timestamp and transitions status to 'signed'.
  """
  def sign(conn, %{"id" => id}) do
    case Repo.get(Deal, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      deal ->
        changeset = Deal.sign_changeset(deal)

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{deal: serialize(updated)})

          {:error, cs} ->
            conn
            |> put_status(422)
            |> json(%{error: "sign_failed", details: format_errors(cs)})
        end
    end
  end

  @doc """
  Complete a deal (transition to completed status with timestamp).

  Sets completed_at timestamp and transitions status to 'completed'.
  """
  def complete(conn, %{"id" => id}) do
    case Repo.get(Deal, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not_found"})

      deal ->
        changeset = Deal.complete_changeset(deal)

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{deal: serialize(updated)})

          {:error, cs} ->
            conn
            |> put_status(422)
            |> json(%{error: "complete_failed", details: format_errors(cs)})
        end
    end
  end

  @doc """
  List available contract templates.

  Returns list of template keys and metadata.
  """
  def templates(conn, _params) do
    templates =
      ContractTemplate.list_templates()
      |> Enum.map(fn key ->
        case ContractTemplate.get_template(key) do
          {:ok, template} ->
            %{
              key: key,
              name: template.name,
              description: template.description
            }

          _ ->
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    json(conn, %{templates: templates})
  end

  @doc """
  Render a contract template with deal-specific terms.

  Body params:
  - template_key: string (e.g., "simple_agreement")
  - terms: map of deal-specific values
  """
  def render_contract(conn, params) do
    template_key = params["template_key"]
    terms = params["terms"] || %{}

    case ContractTemplate.render_template(template_key, terms) do
      {:ok, rendered} ->
        json(conn, %{contract: rendered})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "template_not_found"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason})
    end
  end

  @doc """
  Validate contract terms against template and FIBO constraints.

  Body params:
  - template_key: string
  - terms: map
  """
  def validate_contract(conn, params) do
    template_key = params["template_key"]
    terms = params["terms"] || %{}

    with {:ok, template} <- ContractTemplate.load_template(template_key),
         :ok <- ContractTemplate.validate_terms(template, terms),
         :ok <- ContractTemplate.validate_fibo_constraints(terms) do
      json(conn, %{valid: true})
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "template_not_found"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason, valid: false})
    end
  end

  # --- Private Helpers ---

  defp serialize(%Deal{} = deal) do
    %{
      id: deal.id,
      name: deal.name,
      description: deal.description,
      status: deal.status,
      deal_type: deal.deal_type,
      amount_cents: deal.amount_cents,
      currency: deal.currency,
      counterparty: deal.counterparty,
      contract_template_id: deal.contract_template_id,
      terms: deal.terms,
      metadata: deal.metadata,
      workspace_id: deal.workspace_id,
      created_by_id: deal.created_by_id,
      assigned_to_id: deal.assigned_to_id,
      started_at: deal.started_at,
      completed_at: deal.completed_at,
      inserted_at: deal.inserted_at,
      updated_at: deal.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
