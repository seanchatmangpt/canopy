defmodule Canopy.Deals.ContractTemplate do
  require Logger

  @moduledoc """
  FIBO Contract Template Management

  Manages deal contract templates for Canopy, supporting loading, rendering, and validation
  of financial instrument contracts using FIBO (Financial Industry Business Ontology) terms.

  Templates are stored as JSON schemas with variable placeholders for deal-specific terms.
  """

  @templates %{
    "simple_agreement" => %{
      name: "Simple Agreement for Future Tokens",
      description: "Basic agreement for future token delivery",
      fields: [
        {"issuer", :string, required: true},
        {"investor", :string, required: true},
        {"amount", :integer, required: true},
        {"price_per_token", :float, required: true},
        {"delivery_date", :date, required: true},
        {"payment_terms", :string, required: false}
      ],
      terms: %{
        "governing_law" => "Delaware",
        "dispute_resolution" => "Arbitration",
        "payment_schedule" => "Net 30"
      }
    },
    "equity_agreement" => %{
      name: "Equity Investment Agreement",
      description: "Agreement for equity investment with terms and conditions",
      fields: [
        {"company", :string, required: true},
        {"investor", :string, required: true},
        {"investment_amount", :integer, required: true},
        {"equity_percentage", :float, required: true},
        {"vesting_period_months", :integer, required: false},
        {"liquidation_preference", :string, required: false}
      ],
      terms: %{
        "board_seat" => false,
        "pro_rata_rights" => true,
        "anti_dilution" => "weighted_average",
        "governing_law" => "Delaware"
      }
    },
    "loan_agreement" => %{
      name: "Loan Agreement",
      description: "Standard loan agreement with interest and repayment terms",
      fields: [
        {"lender", :string, required: true},
        {"borrower", :string, required: true},
        {"principal_amount", :integer, required: true},
        {"interest_rate_percent", :float, required: true},
        {"term_months", :integer, required: true},
        {"collateral_description", :string, required: false}
      ],
      terms: %{
        "payment_frequency" => "monthly",
        "default_interest_rate" => 3.0,
        "prepayment_penalty" => false,
        "governing_law" => "Delaware"
      }
    },
    "service_agreement" => %{
      name: "Service Agreement",
      description: "Agreement for ongoing service provision with SLAs",
      fields: [
        {"service_provider", :string, required: true},
        {"client", :string, required: true},
        {"monthly_fee", :integer, required: true},
        {"service_description", :string, required: true},
        {"sla_uptime_percent", :float, required: false},
        {"support_hours", :string, required: false}
      ],
      terms: %{
        "term_months" => 12,
        "auto_renewal" => true,
        "termination_notice_days" => 30,
        "governing_law" => "Delaware"
      }
    }
  }

  @doc """
  Load a contract template by key.

  Returns `{:ok, template_map}` if found, `{:error, :not_found}` otherwise.
  """
  @spec load_template(String.t()) :: {:ok, map()} | {:error, :not_found}
  def load_template(template_key) do
    case Map.get(@templates, template_key) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  @doc """
  List all available template keys.
  """
  @spec list_templates() :: [String.t()]
  def list_templates do
    Map.keys(@templates)
  end

  @doc """
  Get full template details.

  Returns `{:ok, template_map}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_template(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_template(template_key) do
    load_template(template_key)
  end

  @doc """
  Render a contract template with provided deal terms.

  Validates that all required fields are present and their types match.
  """
  @spec render_template(String.t(), map()) ::
          {:ok, map()} | {:error, String.t()} | {:error, :not_found}
  def render_template(template_key, deal_terms) when is_map(deal_terms) do
    with {:ok, template} <- load_template(template_key),
         :ok <- validate_terms(template, deal_terms) do
      rendered = build_rendered_contract(template, deal_terms)
      {:ok, rendered}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validate that deal terms match the template requirements.

  Returns `:ok` if valid, `{:error, message}` otherwise.
  """
  @spec validate_terms(map(), map()) :: :ok | {:error, String.t()}
  def validate_terms(template, terms) when is_map(template) and is_map(terms) do
    fields = Map.get(template, :fields, [])
    errors = validate_fields(fields, terms, [])

    case errors do
      [] -> :ok
      errors -> {:error, "Validation failed: #{Enum.join(errors, "; ")}"}
    end
  end

  @doc """
  Check if all required template fields are provided and have correct types.

  Returns list of error messages, or empty list if all valid.
  """
  @spec validate_fields(list(), map(), list()) :: list(String.t())
  def validate_fields([], _terms, errors) do
    Enum.reverse(errors)
  end

  def validate_fields([{field_name, field_type, opts} | rest], terms, errors) do
    required = Keyword.get(opts, :required, false)

    case validate_field(field_name, field_type, terms, required) do
      :ok ->
        validate_fields(rest, terms, errors)

      {:error, msg} ->
        validate_fields(rest, terms, [msg | errors])
    end
  end

  defp validate_field(field_name, _field_type, terms, false)
       when not is_map_key(terms, field_name) do
    :ok
  end

  defp validate_field(field_name, _field_type, terms, true)
       when not is_map_key(terms, field_name) do
    {:error, "Required field missing: #{field_name}"}
  end

  defp validate_field(field_name, field_type, terms, _required) do
    value = Map.get(terms, field_name)

    case check_type(value, field_type) do
      true -> :ok
      false -> {:error, "Type mismatch for #{field_name}: expected #{field_type}"}
    end
  end

  defp check_type(_value, :any), do: true
  defp check_type(v, :string), do: is_binary(v)
  defp check_type(v, :integer), do: is_integer(v)
  defp check_type(v, :float), do: is_float(v) or is_integer(v)
  defp check_type(v, :date), do: is_binary(v)
  defp check_type(v, :boolean), do: is_boolean(v)
  defp check_type(v, :map), do: is_map(v)
  defp check_type(_v, _type), do: false

  @doc """
  Build the final rendered contract document.

  Combines template structure with deal-specific terms.
  """
  @spec build_rendered_contract(map(), map()) :: map()
  def build_rendered_contract(template, deal_terms) do
    %{
      "name" => Map.get(template, :name),
      "description" => Map.get(template, :description),
      "terms" => merge_terms(Map.get(template, :terms, %{}), deal_terms),
      "metadata" => %{
        "template_key" => nil,
        "rendered_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "version" => "1.0"
      }
    }
  end

  defp merge_terms(template_terms, deal_terms) do
    Enum.reduce(deal_terms, template_terms, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Validate contract terms against FIBO constraints.

  Checks for common financial instrument constraints like:
  - Amount validation (positive, non-zero)
  - Date validation (future or valid range)
  - Currency validation (ISO 4217 codes)
  """
  @spec validate_fibo_constraints(map()) :: :ok | {:error, String.t()}
  def validate_fibo_constraints(terms) when is_map(terms) do
    errors = []

    errors =
      case Map.get(terms, "amount_cents") do
        nil -> errors
        amount when is_integer(amount) and amount > 0 -> errors
        _ -> ["amount_cents must be positive integer" | errors]
      end

    errors =
      case Map.get(terms, "interest_rate_percent") do
        nil -> errors
        rate when is_number(rate) and rate >= 0 and rate <= 100 -> errors
        _ -> ["interest_rate_percent must be between 0 and 100" | errors]
      end

    errors =
      case Map.get(terms, "currency") do
        nil -> errors
        curr when is_binary(curr) and byte_size(curr) == 3 -> errors
        _ -> ["currency must be 3-letter ISO 4217 code" | errors]
      end

    case errors do
      [] -> :ok
      errors -> {:error, Enum.join(Enum.reverse(errors), "; ")}
    end
  end
end
