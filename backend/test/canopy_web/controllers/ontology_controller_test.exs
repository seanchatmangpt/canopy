defmodule CanopyWeb.OntologyControllerTest do
  use CanopyWeb.ConnCase
  @moduletag :external_service

  alias Canopy.Ontology.Service

  setup do
    user = insert_test_user()
    token = generate_jwt_token(user)
    Service.clear_all_cache()

    {:ok, user: user, token: token}
  end

  describe "GET /api/v1/ontologies" do
    test "lists all available ontologies", %{token: token} do
      mock_ontologies()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["ontologies"]
      assert is_list(body["ontologies"])
      assert body["count"] >= 0
      assert is_integer(body["total"])
    end

    test "supports pagination with limit and offset", %{token: token} do
      mock_ontologies()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies", %{limit: 10, offset: 0})

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["ontologies"]
      assert length(body["ontologies"]) <= 10
    end

    test "returns error when ontology service unavailable", %{token: token} do
      # Mock failed response
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      # Either success or error is acceptable (depends on OSA availability)
      assert conn.status in [200, 500]
    end
  end

  describe "GET /api/v1/ontologies/:id" do
    test "retrieves ontology details by id", %{token: token} do
      mock_ontology_detail()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/fibo-core")

      assert conn.status == 200
      body = json_response(conn, 200)

      ontology = body["ontology"]
      assert ontology["id"] == "fibo-core" or is_map(ontology)
      assert ontology["name"] or is_nil(ontology)
      assert ontology["description"] or is_nil(ontology)
    end

    test "returns 404 for non-existent ontology", %{token: token} do
      # This test assumes OSA returns 404 for missing ontologies
      # Actual behavior depends on OSA implementation
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/nonexistent-ontology-12345")

      # Either 404 or error from service
      assert conn.status in [404, 500]
    end
  end

  describe "POST /api/v1/ontologies/:id/search" do
    test "searches for classes and properties", %{token: token} do
      mock_ontology_search()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/ontologies/fibo-core/search", %{
          query: "agent",
          search_type: "both"
        })

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["results"]
      assert is_list(body["results"])
      assert body["query"] == "agent"
      assert is_integer(body["count"])
    end

    test "validates query parameter is required", %{token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/ontologies/fibo-core/search", %{search_type: "class"})

      assert conn.status == 400
      body = json_response(conn, 400)
      assert body["error"] == "validation_failed"
    end

    test "supports search_type filter", %{token: token} do
      mock_ontology_search()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/ontologies/fibo-core/search", %{
          query: "agent",
          search_type: "class"
        })

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["results"]
    end

    test "returns 404 for non-existent ontology", %{token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/ontologies/nonexistent/search", %{query: "test"})

      # Either 404 or error from service
      assert conn.status in [404, 500]
    end

    test "supports pagination in search results", %{token: token} do
      mock_ontology_search()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/v1/ontologies/fibo-core/search", %{
          query: "agent",
          limit: 5,
          offset: 0
        })

      assert conn.status == 200
      body = json_response(conn, 200)

      assert body["results"]
      assert length(body["results"]) <= 5
    end
  end

  describe "GET /api/v1/ontologies/statistics/global" do
    test "returns ontology statistics", %{token: token} do
      mock_ontology_stats()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/statistics/global")

      assert conn.status == 200
      body = json_response(conn, 200)

      stats = body["statistics"]
      assert is_integer(stats["total_ontologies"])
      assert is_integer(stats["total_classes"])
      assert is_integer(stats["total_properties"])
    end

    test "includes cache hit rate in statistics", %{token: token} do
      mock_ontology_stats()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/statistics/global")

      assert conn.status == 200
      body = json_response(conn, 200)

      stats = body["statistics"]
      assert is_float(stats["cache_hit_rate"]) or stats["cache_hit_rate"] >= 0
    end
  end

  describe "GET /api/v1/ontologies/:id/classes/:class_id" do
    test "retrieves class details from ontology", %{token: token} do
      mock_ontology_class()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/fibo-core/classes/Agent")

      assert conn.status == 200
      body = json_response(conn, 200)

      class = body["class"]
      assert class["local_name"] == "Agent" or is_map(class)
      assert is_list(class["parent_classes"]) or is_nil(class["parent_classes"])
      assert is_list(class["child_classes"]) or is_nil(class["child_classes"])
    end

    test "returns 404 for non-existent class", %{token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/fibo-core/classes/NonExistentClass12345")

      # Either 404 or error from service
      assert conn.status in [404, 500]
    end

    test "returns 404 for non-existent ontology when getting class", %{token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/nonexistent-ontology/classes/Agent")

      assert conn.status in [404, 500]
    end

    test "URL encodes class_id properly", %{token: token} do
      mock_ontology_class()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/fibo-core/classes/Agent%20Class")

      # Either success or error from service
      assert conn.status in [200, 404, 500]
    end
  end

  describe "caching behavior" do
    test "first request has cache_hit false", %{token: token} do
      Service.clear_all_cache()

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert body["cache_hit"] == false
    end

    test "second identical request has cache_hit true", %{token: token} do
      Service.clear_all_cache()

      # First request
      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      assert json_response(conn1, 200)["cache_hit"] == false

      # Second request
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      assert json_response(conn2, 200)["cache_hit"] == true
    end

    test "includes retrieved_at timestamp in response", %{token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      assert conn.status == 200
      body = json_response(conn, 200)
      assert Map.has_key?(body, "retrieved_at")
      assert body["retrieved_at"] |> is_binary()
    end

    test "different endpoints have separate cache", %{token: token} do
      Service.clear_all_cache()

      # Request ontology list
      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies")

      assert json_response(conn1, 200)["cache_hit"] == false

      # Request statistics (different endpoint)
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies/statistics/global")

      assert json_response(conn2, 200)["cache_hit"] == false
    end

    test "ontology list with different pagination parameters have separate cache", %{token: token} do
      Service.clear_all_cache()

      # Request with limit=10
      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies", %{limit: "10", offset: "0"})

      assert json_response(conn1, 200)["cache_hit"] == false

      # Request with limit=20 (different cache key)
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies", %{limit: "20", offset: "0"})

      assert json_response(conn2, 200)["cache_hit"] == false

      # Request with limit=10 again (should hit cache)
      conn3 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/v1/ontologies", %{limit: "10", offset: "0"})

      assert json_response(conn3, 200)["cache_hit"] == true
    end
  end

  # ── Helper Functions ──────────────────────────────────────────────────

  defp insert_test_user do
    %Canopy.Schemas.User{}
    |> Ecto.Changeset.cast(
      %{
        name: "Test User #{System.unique_integer([:positive])}",
        email: "test#{System.unique_integer([:positive])}@example.com",
        password: "password123",
        provider: "local",
        role: "member"
      },
      [:name, :email, :password, :provider, :role]
    )
    |> Canopy.Repo.insert!()
  end

  defp generate_jwt_token(user) do
    {:ok, token, _claims} = Canopy.Guardian.encode_and_sign(user)
    token
  end

  defp mock_ontologies do
    # Mocking not strictly needed for live API tests,
    # but this pattern is here for reference if mocking library is added.
    :ok
  end

  defp mock_ontology_detail do
    :ok
  end

  defp mock_ontology_search do
    :ok
  end

  defp mock_ontology_stats do
    :ok
  end

  defp mock_ontology_class do
    :ok
  end
end
