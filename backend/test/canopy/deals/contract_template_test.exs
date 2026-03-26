defmodule Canopy.Deals.ContractTemplateTest do
  use ExUnit.Case

  alias Canopy.Deals.ContractTemplate

  describe "load_template/1" do
    test "loads simple_agreement template" do
      {:ok, template} = ContractTemplate.load_template("simple_agreement")
      assert template.name == "Simple Agreement for Future Tokens"
    end

    test "loads equity_agreement template" do
      {:ok, template} = ContractTemplate.load_template("equity_agreement")
      assert template.name == "Equity Investment Agreement"
    end

    test "loads loan_agreement template" do
      {:ok, template} = ContractTemplate.load_template("loan_agreement")
      assert template.name == "Loan Agreement"
    end

    test "loads service_agreement template" do
      {:ok, template} = ContractTemplate.load_template("service_agreement")
      assert template.name == "Service Agreement"
    end

    test "returns error for non-existent template" do
      assert ContractTemplate.load_template("nonexistent") == {:error, :not_found}
    end
  end

  describe "list_templates/0" do
    test "returns list of all template keys" do
      templates = ContractTemplate.list_templates()
      assert length(templates) == 4
      assert "simple_agreement" in templates
      assert "equity_agreement" in templates
      assert "loan_agreement" in templates
      assert "service_agreement" in templates
    end
  end

  describe "get_template/1" do
    test "returns same result as load_template" do
      {:ok, loaded} = ContractTemplate.load_template("simple_agreement")
      {:ok, gotten} = ContractTemplate.get_template("simple_agreement")
      assert loaded == gotten
    end
  end

  describe "validate_terms/2" do
    test "validates required fields present" do
      template = %{
        name: "Test",
        fields: [
          {"field1", :string, required: true},
          {"field2", :string, required: false}
        ]
      }

      terms = %{"field1" => "value1"}
      assert :ok = ContractTemplate.validate_terms(template, terms)
    end

    test "returns error when required field missing" do
      template = %{
        name: "Test",
        fields: [
          {"field1", :string, required: true}
        ]
      }

      terms = %{}
      assert {:error, _msg} = ContractTemplate.validate_terms(template, terms)
    end

    test "validates field types" do
      template = %{
        name: "Test",
        fields: [
          {"amount", :integer, required: true}
        ]
      }

      terms = %{"amount" => 1000}
      assert :ok = ContractTemplate.validate_terms(template, terms)

      terms_invalid = %{"amount" => "not_an_int"}
      assert {:error, _msg} = ContractTemplate.validate_terms(template, terms_invalid)
    end

    test "accepts float for numeric fields" do
      template = %{
        name: "Test",
        fields: [
          {"rate", :float, required: true}
        ]
      }

      terms = %{"rate" => 5.5}
      assert :ok = ContractTemplate.validate_terms(template, terms)

      terms_int = %{"rate" => 5}
      assert :ok = ContractTemplate.validate_terms(template, terms_int)
    end
  end

  describe "validate_fields/3" do
    test "validates all fields in list" do
      fields = [
        {"name", :string, required: true},
        {"amount", :integer, required: true},
        {"active", :boolean, required: false}
      ]

      terms = %{"name" => "Test", "amount" => 100}
      errors = ContractTemplate.validate_fields(fields, terms, [])
      assert errors == []
    end

    test "collects multiple validation errors" do
      fields = [
        {"name", :string, required: true},
        {"amount", :integer, required: true}
      ]

      terms = %{}
      errors = ContractTemplate.validate_fields(fields, terms, [])
      assert length(errors) == 2
    end

    test "allows optional fields to be missing" do
      fields = [
        {"name", :string, required: true},
        {"notes", :string, required: false}
      ]

      terms = %{"name" => "Test"}
      errors = ContractTemplate.validate_fields(fields, terms, [])
      assert errors == []
    end
  end

  describe "render_template/2" do
    test "renders simple_agreement with valid terms" do
      terms = %{
        "issuer" => "Alice Inc",
        "investor" => "Bob Corp",
        "amount" => 1000,
        "price_per_token" => 10.5,
        "delivery_date" => "2026-12-31"
      }

      {:ok, rendered} = ContractTemplate.render_template("simple_agreement", terms)
      assert rendered["name"] == "Simple Agreement for Future Tokens"
      assert rendered["terms"]["issuer"] == "Alice Inc"
      assert rendered["metadata"]["template_key"] == nil
      assert rendered["metadata"]["version"] == "1.0"
    end

    test "returns error when required fields missing" do
      terms = %{"issuer" => "Alice"}

      {:error, msg} = ContractTemplate.render_template("simple_agreement", terms)
      assert msg =~ "Validation failed: Required field missing"
      assert msg =~ "investor"
    end

    test "merges deal terms with template terms" do
      terms = %{
        "issuer" => "Alice",
        "investor" => "Bob",
        "amount" => 500,
        "price_per_token" => 20.0,
        "delivery_date" => "2027-06-30",
        "custom_field" => "custom_value"
      }

      {:ok, rendered} = ContractTemplate.render_template("simple_agreement", terms)
      assert rendered["terms"]["custom_field"] == "custom_value"
      assert rendered["terms"]["governing_law"] == "Delaware"
    end

    test "returns not_found for invalid template key" do
      assert ContractTemplate.render_template("invalid", %{}) ==
               {:error, :not_found}
    end
  end

  describe "build_rendered_contract/2" do
    test "builds contract with timestamp" do
      template = %{
        name: "Test Contract",
        description: "Test description",
        terms: %{"governing_law" => "Delaware"}
      }

      terms = %{"amount" => 1000}

      rendered = ContractTemplate.build_rendered_contract(template, terms)

      assert rendered["name"] == "Test Contract"
      assert rendered["description"] == "Test description"
      assert rendered["terms"]["governing_law"] == "Delaware"
      assert rendered["terms"]["amount"] == 1000
      assert rendered["metadata"]["rendered_at"] != nil
      assert rendered["metadata"]["version"] == "1.0"
    end
  end

  describe "validate_fibo_constraints/1" do
    test "accepts valid amounts and interest rates" do
      terms = %{
        "amount_cents" => 100_000,
        "interest_rate_percent" => 5.5,
        "currency" => "USD"
      }

      assert :ok = ContractTemplate.validate_fibo_constraints(terms)
    end

    test "rejects negative amounts" do
      terms = %{"amount_cents" => -1000}
      assert {:error, msg} = ContractTemplate.validate_fibo_constraints(terms)
      assert msg =~ "amount_cents must be positive"
    end

    test "rejects zero amounts" do
      terms = %{"amount_cents" => 0}
      assert {:error, msg} = ContractTemplate.validate_fibo_constraints(terms)
      assert msg =~ "amount_cents must be positive"
    end

    test "rejects interest rate > 100" do
      terms = %{"interest_rate_percent" => 150.0}
      assert {:error, msg} = ContractTemplate.validate_fibo_constraints(terms)
      assert msg =~ "interest_rate_percent must be between 0 and 100"
    end

    test "rejects invalid currency format" do
      terms = %{"currency" => "INVALID"}
      assert {:error, msg} = ContractTemplate.validate_fibo_constraints(terms)
      assert msg =~ "currency must be 3-letter ISO 4217 code"
    end

    test "accepts valid interest rate of 0" do
      terms = %{"interest_rate_percent" => 0}
      assert :ok = ContractTemplate.validate_fibo_constraints(terms)
    end

    test "accepts valid interest rate of 100" do
      terms = %{"interest_rate_percent" => 100}
      assert :ok = ContractTemplate.validate_fibo_constraints(terms)
    end

    test "ignores missing optional fields" do
      terms = %{}
      assert :ok = ContractTemplate.validate_fibo_constraints(terms)
    end

    test "collects multiple constraint violations" do
      terms = %{
        "amount_cents" => -100,
        "interest_rate_percent" => 150.0,
        "currency" => "INVALID"
      }

      assert {:error, msg} = ContractTemplate.validate_fibo_constraints(terms)
      assert msg =~ "amount_cents"
      assert msg =~ "interest_rate_percent"
      assert msg =~ "currency"
    end
  end

  describe "loan_agreement template" do
    test "has required fields" do
      {:ok, template} = ContractTemplate.load_template("loan_agreement")
      field_names = Enum.map(template.fields, fn {name, _, _} -> name end)

      assert "lender" in field_names
      assert "borrower" in field_names
      assert "principal_amount" in field_names
      assert "interest_rate_percent" in field_names
      assert "term_months" in field_names
    end

    test "renders with valid loan terms" do
      terms = %{
        "lender" => "Bank ABC",
        "borrower" => "Company XYZ",
        "principal_amount" => 500_000,
        "interest_rate_percent" => 5.5,
        "term_months" => 60
      }

      {:ok, rendered} = ContractTemplate.render_template("loan_agreement", terms)
      assert rendered["terms"]["lender"] == "Bank ABC"
      assert rendered["terms"]["payment_frequency"] == "monthly"
    end
  end

  describe "equity_agreement template" do
    test "has required fields" do
      {:ok, template} = ContractTemplate.load_template("equity_agreement")
      field_names = Enum.map(template.fields, fn {name, _, _} -> name end)

      assert "company" in field_names
      assert "investor" in field_names
      assert "investment_amount" in field_names
      assert "equity_percentage" in field_names
    end

    test "renders with equity terms" do
      terms = %{
        "company" => "Tech Startup",
        "investor" => "VC Fund",
        "investment_amount" => 1_000_000,
        "equity_percentage" => 10.0
      }

      {:ok, rendered} = ContractTemplate.render_template("equity_agreement", terms)
      assert rendered["terms"]["company"] == "Tech Startup"
      assert rendered["terms"]["pro_rata_rights"] == true
    end
  end
end
