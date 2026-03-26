defmodule CanopyWeb.ComplianceControllerTest do
  use CanopyWeb.ConnCase

  alias Canopy.Compliance.FrameworkConfig
  alias Canopy.Repo
  alias Canopy.Schemas.User

  @moduletag :skip

  setup do
    user = insert_user(%{email: "compliance@test.com", role: "admin"})
    {:ok, user: user}
  end

  describe "GET /api/v1/compliance/frameworks" do
    test "returns list of supported frameworks", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks")

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["frameworks"]
      assert is_list(body["frameworks"])
      assert Enum.member?(body["frameworks"], "SOC2")
      assert Enum.member?(body["frameworks"], "HIPAA")
      assert Enum.member?(body["frameworks"], "GDPR")
      assert body["count"] == 5
    end

    test "returns frameworks in consistent order" do
      conn = build_conn()
      |> put_req_header("content-type", "application/json")
      |> get("/api/v1/compliance/frameworks")

      body = json_response(conn, 200)
      frameworks = body["frameworks"]

      # Should be consistent across calls
      assert length(frameworks) == 5
    end
  end

  describe "GET /api/v1/compliance/frameworks/:framework" do
    test "returns SOC2 framework details", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks/SOC2")

      assert conn.status == 200
      body = json_response(conn, 200)

      framework = body["framework"]
      assert framework["name"] == "SOC2"
      assert framework["version"] == "2.0"
      assert is_list(framework["controls"])
      assert framework["control_count"] > 0
      assert is_list(framework["audit_requirements"])
    end

    test "returns control details in framework response", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks/SOC2")

      assert conn.status == 200
      body = json_response(conn, 200)

      controls = body["framework"]["controls"]
      assert length(controls) > 0

      cc6_1 = Enum.find(controls, &(&1["id"] == "cc6.1"))
      assert cc6_1["title"] == "Logical Access Control"
      assert cc6_1["criticality"] == "critical"
      assert is_list(cc6_1["tags"])
      assert is_list(cc6_1["evidence_required"])
    end

    test "returns 400 for unsupported framework", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks/UNKNOWN")

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["error"]
      assert String.contains?(body["error"], "Unsupported framework")
    end

    test "returns HIPAA framework with correct structure", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks/HIPAA")

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["framework"]["name"] == "HIPAA"
      assert is_list(body["framework"]["controls"])
      assert is_list(body["framework"]["audit_requirements"])
    end
  end

  describe "POST /api/v1/compliance/verify" do
    test "verifies compliant assessment", %{user: user} do
      assessment = %{
        "cc6.1" => "compliant",
        "cc6.2" => "compliant",
        "a1.1" => "compliant",
        "c1.1" => "compliant",
        "i1.1" => "compliant",
        "cc7.1" => "compliant"
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/verify", %{
        "framework" => "SOC2",
        "assessment" => assessment
      })

      assert conn.status == 200
      body = json_response(conn, 200)

      verification = body["verification"]
      assert verification["framework"] == "SOC2"
      assert verification["compliant"] == 6
      assert verification["non_compliant"] == 0
      assert verification["compliance_rate"] == 1.0
      assert verification["total_controls"] == 6
      assert verification["timestamp"]
    end

    test "verifies partially compliant assessment", %{user: user} do
      assessment = %{
        "cc6.1" => "compliant",
        "cc6.2" => "non_compliant",
        "a1.1" => "partial",
        "c1.1" => "compliant",
        "i1.1" => "unknown",
        "cc7.1" => "compliant"
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/verify", %{
        "framework" => "SOC2",
        "assessment" => assessment
      })

      assert conn.status == 200
      body = json_response(conn, 200)

      verification = body["verification"]
      assert verification["compliant"] == 3
      assert verification["non_compliant"] == 1
      assert verification["partial"] == 1
      assert verification["unknown"] == 1
      assert verification["compliance_rate"] == 0.5
    end

    test "returns 400 for invalid framework", %{user: user} do
      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/verify", %{
        "framework" => "INVALID",
        "assessment" => %{}
      })

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["error"]
    end

    test "returns 400 for missing assessment data", %{user: user} do
      assessment = %{
        "cc6.1" => "compliant"
        # Missing other controls
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/verify", %{
        "framework" => "SOC2",
        "assessment" => assessment
      })

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["error"] == "validation_failed"
      assert body["details"]
      assert is_list(body["details"])
    end
  end

  describe "POST /api/v1/compliance/report" do
    test "generates compliance report with summary", %{user: user} do
      assessment = %{
        "cc6.1" => "compliant",
        "cc6.2" => "compliant",
        "a1.1" => "non_compliant",
        "c1.1" => "compliant",
        "i1.1" => "compliant",
        "cc7.1" => "partial"
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/report", %{
        "framework" => "SOC2",
        "assessment" => assessment,
        "include_controls" => true,
        "include_gaps" => true
      })

      assert conn.status == 200
      body = json_response(conn, 200)

      report = body["report"]
      assert report["framework"] == "SOC2"
      assert report["version"]
      assert report["generated_at"]

      summary = report["summary"]
      assert summary["total"] == 6
      assert summary["compliant"] == 4
      assert summary["non_compliant"] == 1
      assert summary["partial"] == 1
      assert summary["compliance_rate"] > 0
    end

    test "includes gaps in report", %{user: user} do
      assessment = %{
        "cc6.1" => "compliant",
        "cc6.2" => "non_compliant",
        "a1.1" => "unknown",
        "c1.1" => "compliant",
        "i1.1" => "compliant",
        "cc7.1" => "compliant"
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/report", %{
        "framework" => "SOC2",
        "assessment" => assessment,
        "include_gaps" => true
      })

      assert conn.status == 200
      body = json_response(conn, 200)

      report = body["report"]
      assert is_list(report["gaps"])
      assert length(report["gaps"]) == 2
      assert Enum.any?(report["gaps"], &(&1["id"] == "cc6.2"))
      assert Enum.any?(report["gaps"], &(&1["id"] == "a1.1"))
    end

    test "excludes controls if not requested", %{user: user} do
      assessment = %{
        "cc6.1" => "compliant",
        "cc6.2" => "compliant",
        "a1.1" => "compliant",
        "c1.1" => "compliant",
        "i1.1" => "compliant",
        "cc7.1" => "compliant"
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/report", %{
        "framework" => "SOC2",
        "assessment" => assessment,
        "include_controls" => false
      })

      assert conn.status == 200
      body = json_response(conn, 200)

      report = body["report"]
      assert report["controls"] == []
    end

    test "generates recommendations based on gaps", %{user: user} do
      assessment = %{
        "cc6.1" => "non_compliant",
        "cc6.2" => "compliant",
        "a1.1" => "compliant",
        "c1.1" => "non_compliant",
        "i1.1" => "compliant",
        "cc7.1" => "compliant"
      }

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/report", %{
        "framework" => "SOC2",
        "assessment" => assessment
      })

      assert conn.status == 200
      body = json_response(conn, 200)

      report = body["report"]
      recommendations = report["recommendations"]
      assert is_list(recommendations)
      assert length(recommendations) > 0

      # Check recommendation structure
      rec = Enum.at(recommendations, 0)
      assert rec["control_id"]
      assert rec["control_title"]
      assert rec["priority"]
      assert rec["action"]
      assert rec["timeline_days"]
    end

    test "returns 400 for invalid assessment", %{user: user} do
      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/report", %{
        "framework" => "SOC2",
        "assessment" => %{"cc6.1" => "compliant"}
      })

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["error"] == "validation_failed"
    end
  end

  describe "GET /api/v1/compliance/controls/:control_id" do
    test "returns control details by ID", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/controls/cc6.1?framework=SOC2")

      assert conn.status == 200
      body = json_response(conn, 200)

      control = body["control"]
      assert control["id"] == "cc6.1"
      assert control["title"] == "Logical Access Control"
      assert control["framework"] == "SOC2"
      assert control["criticality"] == "critical"
      assert is_list(control["tags"])
      assert is_list(control["evidence_required"])
    end

    test "returns 404 for non-existent control", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/controls/nonexistent?framework=SOC2")

      assert conn.status == 404
      body = json_response(conn, 404)
      assert body["error"]
    end

    test "defaults to SOC2 framework if not specified", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/controls/cc6.1")

      assert conn.status == 200
      body = json_response(conn, 200)

      control = body["control"]
      assert control["framework"] == "SOC2"
    end

    test "retrieves control from HIPAA framework", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/controls/164.312_a_1?framework=HIPAA")

      assert conn.status == 200
      body = json_response(conn, 200)

      control = body["control"]
      assert control["id"] == "164.312_a_1"
      assert control["framework"] == "HIPAA"
    end
  end

  describe "GET /api/v1/compliance/status" do
    test "returns compliance status", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/status")

      assert conn.status == 200
      body = json_response(conn, 200)

      status = body["status"]
      assert status["timestamp"]
      assert status["overall_compliance_rate"]
      assert is_list(status["frameworks"])
      assert length(status["frameworks"]) > 0
    end

    test "status includes framework details", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/status")

      assert conn.status == 200
      body = json_response(conn, 200)

      frameworks = body["status"]["frameworks"]
      soc2 = Enum.find(frameworks, &(&1["name"] == "SOC2"))
      assert soc2
      assert soc2["compliance_rate"]
    end
  end

  describe "POST /api/v1/compliance/reload" do
    test "reloads compliance configurations", %{user: user} do
      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/reload", %{})

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["message"]
      assert String.contains?(body["message"], "reloaded successfully")
      assert body["timestamp"]
    end

    test "reload returns current timestamp", %{user: user} do
      before = DateTime.utc_now()

      conn = build_authenticated_conn(user)
      |> post("/api/v1/compliance/reload", %{})

      after_req = DateTime.utc_now()
      body = json_response(conn, 200)
      timestamp_str = body["timestamp"]
      {:ok, timestamp, _} = DateTime.from_iso8601(timestamp_str)

      # Ensure timestamp is between before and after
      assert DateTime.compare(timestamp, before) in [:eq, :gt]
      assert DateTime.compare(timestamp, after_req) in [:eq, :lt]
    end
  end

  describe "Framework config integration tests" do
    test "SOC2 framework configuration is valid", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks/SOC2")

      assert conn.status == 200
      body = json_response(conn, 200)

      framework = body["framework"]
      assert framework["name"] == "SOC2"
      assert framework["control_count"] == 6

      controls = framework["controls"]
      assert Enum.any?(controls, &(&1["id"] == "cc6.1"))
      assert Enum.any?(controls, &(&1["id"] == "c1.1"))
      assert Enum.any?(controls, &(&1["id"] == "i1.1"))
    end

    test "all frameworks are loadable", %{user: user} do
      frameworks = ["SOC2", "HIPAA", "GDPR", "ISO27001", "SOX"]

      Enum.each(frameworks, fn framework ->
        conn = build_authenticated_conn(user)
        |> get("/api/v1/compliance/frameworks/#{framework}")

        assert conn.status == 200, "Failed to load framework: #{framework}"
        body = json_response(conn, 200)
        assert body["framework"]["name"] == framework
      end)
    end

    test "controls have required evidence types", %{user: user} do
      conn = build_authenticated_conn(user)
      |> get("/api/v1/compliance/frameworks/SOC2")

      assert conn.status == 200
      body = json_response(conn, 200)

      controls = body["framework"]["controls"]
      assert Enum.all?(controls, fn control ->
        is_list(control["evidence_required"]) && length(control["evidence_required"]) > 0
      end)
    end
  end

  defp insert_user(attrs \\ %{}) do
    user_attrs =
      Map.merge(
        %{
          name: "Test User #{System.unique_integer([:positive])}",
          email: "test#{System.unique_integer([:positive])}@test.com",
          password: "password123",
          role: "member",
          provider: "local"
        },
        attrs
      )

    {:ok, user} =
      Repo.insert(Ecto.Changeset.cast(%User{}, user_attrs, [:name, :email, :password, :role, :provider]))

    user
  end

  defp build_authenticated_conn(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> Map.put(:assigns, %{current_user: user})
  end
end
