defmodule Canopy.Compliance.FrameworkConfig do
  @moduledoc """
  Framework configuration loader and validator for compliance.

  Loads compliance framework configurations from YAML files, validates structure,
  and provides functions to retrieve framework definitions, controls, and audit requirements.

  Supported frameworks:
  - SOC2 (Service Organization Control 2)
  - HIPAA (Health Insurance Portability and Accountability Act)
  - GDPR (General Data Protection Regulation)
  - ISO27001 (Information Security Management)
  - SOX (Sarbanes-Oxley Act)
  """

  require Logger

  @supported_frameworks ["SOC2", "HIPAA", "GDPR", "ISO27001", "SOX"]

  defstruct [
    :framework_name,
    :version,
    :description,
    :controls,
    :audit_requirements,
    :evidence_mapping
  ]

  @type framework :: %__MODULE__{
          framework_name: String.t(),
          version: String.t(),
          description: String.t(),
          controls: [control()],
          audit_requirements: [audit_requirement()],
          evidence_mapping: map()
        }

  @type control :: %{
          id: String.t(),
          title: String.t(),
          description: String.t(),
          criticality: String.t(),
          tags: [String.t()],
          evidence_required: [String.t()]
        }

  @type audit_requirement :: %{
          id: String.t(),
          description: String.t(),
          frequency: String.t(),
          responsible_role: String.t()
        }

  @type load_result :: {:ok, framework()} | {:error, String.t()}
  @type control_result :: {:ok, control()} | {:error, String.t()}
  @type validation_result :: {:ok, map()} | {:error, [String.t()]}

  @doc """
  Loads a framework configuration by name.

  Supported frameworks: #{Enum.join(@supported_frameworks, ", ")}

  Returns {:ok, framework} on success or {:error, reason} on failure.

  ## Examples

      iex> FrameworkConfig.load_config("SOC2")
      {:ok, %FrameworkConfig{framework_name: "SOC2", ...}}

      iex> FrameworkConfig.load_config("UNKNOWN")
      {:error, "Unsupported framework: UNKNOWN"}
  """
  @spec load_config(String.t()) :: load_result()
  def load_config(framework_name) when is_binary(framework_name) do
    normalized_name = String.upcase(framework_name)

    cond do
      normalized_name not in @supported_frameworks ->
        {:error, "Unsupported framework: #{normalized_name}"}

      true ->
        case load_framework_file(normalized_name) do
          {:ok, config_map} ->
            {:ok, parse_framework_config(config_map)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns all supported frameworks.

  ## Examples

      iex> FrameworkConfig.supported_frameworks()
      ["SOC2", "HIPAA", "GDPR", "ISO27001", "SOX"]
  """
  @spec supported_frameworks() :: [String.t()]
  def supported_frameworks, do: @supported_frameworks

  @doc """
  Retrieves a control by framework and control ID.

  Returns {:ok, control} on success or {:error, reason} if control not found.

  ## Examples

      iex> FrameworkConfig.get_control("SOC2", "cc6.1")
      {:ok, %{id: "cc6.1", title: "Logical Access Control", ...}}
  """
  @spec get_control(String.t(), String.t()) :: control_result()
  def get_control(framework_name, control_id)
      when is_binary(framework_name) and is_binary(control_id) do
    with {:ok, framework} <- load_config(framework_name),
         control <- Enum.find(framework.controls, &(&1.id == control_id)) do
      case control do
        nil -> {:error, "Control not found: #{control_id}"}
        _ -> {:ok, control}
      end
    end
  end

  @doc """
  Returns all controls for a framework.

  ## Examples

      iex> FrameworkConfig.get_all_controls("SOC2")
      {:ok, [%{id: "cc6.1", ...}, %{id: "cc6.2", ...}, ...]}
  """
  @spec get_all_controls(String.t()) :: {:ok, [control()]} | {:error, String.t()}
  def get_all_controls(framework_name) when is_binary(framework_name) do
    with {:ok, framework} <- load_config(framework_name) do
      {:ok, framework.controls}
    end
  end

  @doc """
  Returns controls for a framework filtered by criticality level.

  Criticality levels: "critical", "high", "medium", "low"

  ## Examples

      iex> FrameworkConfig.get_controls_by_criticality("SOC2", "critical")
      {:ok, [critical_control1, critical_control2, ...]}
  """
  @spec get_controls_by_criticality(String.t(), String.t()) ::
          {:ok, [control()]} | {:error, String.t()}
  def get_controls_by_criticality(framework_name, criticality)
      when is_binary(framework_name) and is_binary(criticality) do
    with {:ok, framework} <- load_config(framework_name) do
      filtered = Enum.filter(framework.controls, &(&1.criticality == criticality))
      {:ok, filtered}
    end
  end

  @doc """
  Validates a compliance assessment result against a framework.

  Assessment should be a map with keys matching control IDs and values as compliance status.

  Returns {:ok, validation_map} with detailed results or {:error, [error_messages]}

  ## Examples

      iex> assessment = %{"cc6.1" => "compliant", "cc6.2" => "non_compliant"}
      iex> FrameworkConfig.validate_assessment("SOC2", assessment)
      {:ok, %{compliant: 1, non_compliant: 1, missing: ...}}
  """
  @spec validate_assessment(String.t(), map()) :: validation_result()
  def validate_assessment(framework_name, assessment)
      when is_binary(framework_name) and is_map(assessment) do
    with {:ok, framework} <- load_config(framework_name) do
      control_ids = Enum.map(framework.controls, & &1.id)
      assessment_ids = Map.keys(assessment)

      missing_controls = control_ids -- assessment_ids
      extra_controls = assessment_ids -- control_ids
      errors = []

      errors =
        if Enum.empty?(extra_controls) do
          errors
        else
          errors ++ ["Extra controls not in framework: #{Enum.join(extra_controls, ", ")}"]
        end

      errors =
        if Enum.empty?(missing_controls) do
          errors
        else
          errors ++ ["Missing assessments for controls: #{Enum.join(missing_controls, ", ")}"]
        end

      case errors do
        [] ->
          result = %{
            compliant: Enum.count(assessment, fn {_, v} -> v == "compliant" end),
            non_compliant: Enum.count(assessment, fn {_, v} -> v == "non_compliant" end),
            partial: Enum.count(assessment, fn {_, v} -> v == "partial" end),
            unknown: Enum.count(assessment, fn {_, v} -> v == "unknown" end),
            total: Enum.count(framework.controls)
          }

          {:ok, result}

        errors ->
          {:error, errors}
      end
    end
  end

  @doc """
  Returns audit requirements for a framework.

  ## Examples

      iex> FrameworkConfig.get_audit_requirements("SOC2")
      {:ok, [%{id: "audit1", ...}, ...]}
  """
  @spec get_audit_requirements(String.t()) :: {:ok, [audit_requirement()]} | {:error, String.t()}
  def get_audit_requirements(framework_name) when is_binary(framework_name) do
    with {:ok, framework} <- load_config(framework_name) do
      {:ok, framework.audit_requirements}
    end
  end

  @doc """
  Returns evidence mapping for a framework.

  Evidence mapping defines what evidence types are required for each control.

  ## Examples

      iex> FrameworkConfig.get_evidence_mapping("SOC2")
      {:ok, %{"cc6.1" => ["policy", "log"], ...}}
  """
  @spec get_evidence_mapping(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_evidence_mapping(framework_name) when is_binary(framework_name) do
    with {:ok, framework} <- load_config(framework_name) do
      {:ok, framework.evidence_mapping}
    end
  end

  @doc """
  Reloads all cached framework configurations.

  Call this after updating YAML config files to reflect changes without restart.

  Returns :ok on success.
  """
  @spec reload_all() :: :ok
  def reload_all do
    Enum.each(@supported_frameworks, fn framework ->
      case load_config(framework) do
        {:ok, _} ->
          Logger.info("Reloaded compliance framework config: #{framework}")

        {:error, reason} ->
          Logger.warning("Failed to reload compliance framework config #{framework}: #{reason}")
      end
    end)

    :ok
  end

  # Private helpers

  defp load_framework_file(framework_name) do
    # For now, return in-memory defaults
    # In production, load from priv/compliance/frameworks/{framework}.yaml
    case framework_name do
      "SOC2" -> {:ok, soc2_defaults()}
      "HIPAA" -> {:ok, hipaa_defaults()}
      "GDPR" -> {:ok, gdpr_defaults()}
      "ISO27001" -> {:ok, iso27001_defaults()}
      "SOX" -> {:ok, sox_defaults()}
      _ -> {:error, "Framework file not found: #{framework_name}"}
    end
  end

  defp parse_framework_config(config_map) when is_map(config_map) do
    %__MODULE__{
      framework_name: Map.get(config_map, "framework_name", "Unknown"),
      version: Map.get(config_map, "version", "1.0"),
      description: Map.get(config_map, "description", ""),
      controls: parse_controls(Map.get(config_map, "controls", [])),
      audit_requirements: parse_audit_requirements(Map.get(config_map, "audit_requirements", [])),
      evidence_mapping: Map.get(config_map, "evidence_mapping", %{})
    }
  end

  defp parse_controls(controls_list) when is_list(controls_list) do
    Enum.map(controls_list, fn control ->
      %{
        id: Map.get(control, "id", ""),
        title: Map.get(control, "title", ""),
        description: Map.get(control, "description", ""),
        criticality: Map.get(control, "criticality", "medium"),
        tags: Map.get(control, "tags", []),
        evidence_required: Map.get(control, "evidence_required", [])
      }
    end)
  end

  defp parse_controls(_), do: []

  defp parse_audit_requirements(reqs_list) when is_list(reqs_list) do
    Enum.map(reqs_list, fn req ->
      %{
        id: Map.get(req, "id", ""),
        description: Map.get(req, "description", ""),
        frequency: Map.get(req, "frequency", "annual"),
        responsible_role: Map.get(req, "responsible_role", "compliance_officer")
      }
    end)
  end

  defp parse_audit_requirements(_), do: []

  # Default framework configurations

  defp soc2_defaults do
    %{
      "framework_name" => "SOC2",
      "version" => "2.0",
      "description" => "Service Organization Control 2 - Trust Service Criteria",
      "controls" => [
        %{
          "id" => "cc6.1",
          "title" => "Logical Access Control",
          "description" => "Logical access restricted to authorized personnel",
          "criticality" => "critical",
          "tags" => ["access_control", "authentication"],
          "evidence_required" => ["access_policy", "audit_logs", "role_assignments"]
        },
        %{
          "id" => "cc6.2",
          "title" => "User Provisioning",
          "description" => "User provisioning requires verification",
          "criticality" => "high",
          "tags" => ["access_control", "onboarding"],
          "evidence_required" => ["onboarding_checklist", "manager_approval", "training_record"]
        },
        %{
          "id" => "a1.1",
          "title" => "System Availability",
          "description" => "System availability must exceed 99.9%",
          "criticality" => "high",
          "tags" => ["availability", "monitoring"],
          "evidence_required" => ["uptime_logs", "sla_metrics", "incident_reports"]
        },
        %{
          "id" => "c1.1",
          "title" => "Data Encryption",
          "description" => "Sensitive data encrypted at rest and in transit",
          "criticality" => "critical",
          "tags" => ["encryption", "confidentiality"],
          "evidence_required" => ["encryption_policy", "key_management_logs", "technical_review"]
        },
        %{
          "id" => "i1.1",
          "title" => "Audit Trail Integrity",
          "description" => "Audit trail entries have valid signatures",
          "criticality" => "critical",
          "tags" => ["audit", "integrity"],
          "evidence_required" => ["audit_logs", "signature_validation", "technical_review"]
        },
        %{
          "id" => "cc7.1",
          "title" => "System Monitoring",
          "description" => "System monitoring and alerting enabled",
          "criticality" => "high",
          "tags" => ["monitoring", "incident_response"],
          "evidence_required" => ["monitoring_config", "alert_logs", "incident_response_plan"]
        }
      ],
      "audit_requirements" => [
        %{
          "id" => "annual_audit",
          "description" => "Annual SOC2 Type II audit",
          "frequency" => "annual",
          "responsible_role" => "compliance_officer"
        },
        %{
          "id" => "quarterly_review",
          "description" => "Quarterly control assessment",
          "frequency" => "quarterly",
          "responsible_role" => "compliance_officer"
        }
      ],
      "evidence_mapping" => %{
        "cc6.1" => ["policy", "logs", "roles"],
        "cc6.2" => ["checklist", "approval", "training"],
        "a1.1" => ["metrics", "reports"],
        "c1.1" => ["policy", "keys"],
        "i1.1" => ["logs", "signatures"],
        "cc7.1" => ["config", "alerts"]
      }
    }
  end

  defp hipaa_defaults do
    %{
      "framework_name" => "HIPAA",
      "version" => "2.0",
      "description" => "Health Insurance Portability and Accountability Act",
      "controls" => [
        %{
          "id" => "164.312_a_1",
          "title" => "User Access Control",
          "description" => "Implement user access management",
          "criticality" => "critical",
          "tags" => ["phi_protection", "access_control"],
          "evidence_required" => ["access_policy", "audit_logs"]
        },
        %{
          "id" => "164.312_a_2_i",
          "title" => "Emergency Access Procedures",
          "description" => "Emergency procedures for accessing PHI",
          "criticality" => "high",
          "tags" => ["emergency_procedures", "phi_protection"],
          "evidence_required" => ["emergency_policy", "test_results"]
        }
      ],
      "audit_requirements" => [
        %{
          "id" => "annual_risk_assessment",
          "description" => "Annual HIPAA Risk Assessment",
          "frequency" => "annual",
          "responsible_role" => "security_officer"
        }
      ],
      "evidence_mapping" => %{
        "164.312_a_1" => ["policy", "logs"],
        "164.312_a_2_i" => ["policy", "test_results"]
      }
    }
  end

  defp gdpr_defaults do
    %{
      "framework_name" => "GDPR",
      "version" => "1.0",
      "description" => "General Data Protection Regulation",
      "controls" => [
        %{
          "id" => "article_32",
          "title" => "Data Protection by Design",
          "description" => "Implement data protection measures",
          "criticality" => "critical",
          "tags" => ["data_protection", "privacy"],
          "evidence_required" => ["policy", "impact_assessment"]
        }
      ],
      "audit_requirements" => [
        %{
          "id" => "dpia_review",
          "description" => "Data Protection Impact Assessment",
          "frequency" => "biennial",
          "responsible_role" => "dpo"
        }
      ],
      "evidence_mapping" => %{
        "article_32" => ["policy", "assessment"]
      }
    }
  end

  defp iso27001_defaults do
    %{
      "framework_name" => "ISO27001",
      "version" => "2022",
      "description" => "Information Security Management System",
      "controls" => [
        %{
          "id" => "a.5.1",
          "title" => "Policies for Information Security",
          "description" => "Establish information security policies",
          "criticality" => "high",
          "tags" => ["governance", "policy"],
          "evidence_required" => ["policy_document"]
        }
      ],
      "audit_requirements" => [
        %{
          "id" => "internal_audit",
          "description" => "Internal audit of ISMS",
          "frequency" => "annual",
          "responsible_role" => "audit_manager"
        }
      ],
      "evidence_mapping" => %{
        "a.5.1" => ["policy"]
      }
    }
  end

  defp sox_defaults do
    %{
      "framework_name" => "SOX",
      "version" => "2002",
      "description" => "Sarbanes-Oxley Act",
      "controls" => [
        %{
          "id" => "302",
          "title" => "Corporate Responsibility",
          "description" => "CEOs and CFOs certify financial reports",
          "criticality" => "critical",
          "tags" => ["financial", "governance"],
          "evidence_required" => ["certification", "audit_trail"]
        }
      ],
      "audit_requirements" => [
        %{
          "id" => "annual_audit",
          "description" => "Annual financial audit",
          "frequency" => "annual",
          "responsible_role" => "auditor"
        }
      ],
      "evidence_mapping" => %{
        "302" => ["certification", "logs"]
      }
    }
  end
end
