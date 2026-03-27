defmodule CanopyWeb.OntologyController do
  @moduledoc """
  Phoenix controller for ontology management.

  Provides HTTP endpoints for:
  - Listing available ontologies
  - Retrieving ontology details
  - Searching ontology classes and properties
  - Getting statistics about loaded ontologies

  Delegates to OSA ontology registry via HTTP API.
  """
  use CanopyWeb, :controller

  require Logger

  alias Canopy.Ontology.Service

  @doc """
  GET /api/v1/ontologies

  List all available ontologies with basic metadata.

  Query params:
    - workspace_id (optional): Filter by workspace
    - limit (optional, default 50): Max results
    - offset (optional, default 0): Pagination offset

  Response:
    {
      "ontologies": [
        {
          "id": "fibo-core",
          "name": "FIBO Core",
          "description": "Financial Industry Business Ontology Core",
          "version": "2.0.0",
          "class_count": 456,
          "property_count": 1200,
          "loaded_at": "2026-03-26T10:00:00Z"
        }
      ],
      "count": 15,
      "total": 42
    }
  """
  def index(conn, params) do
    limit = String.to_integer(params["limit"] || "50")
    offset = String.to_integer(params["offset"] || "0")

    case Service.list_ontologies(limit: limit, offset: offset) do
      {:ok, ontologies, total, metadata} ->
        json(conn, %{
          ontologies: Enum.map(ontologies, &serialize_ontology/1),
          count: length(ontologies),
          total: total,
          cache_hit: metadata.cache_hit,
          retrieved_at: metadata.retrieved_at
        })

      {:error, reason} ->
        Logger.error("Failed to list ontologies: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "ontology_service_unavailable", details: inspect(reason)})
    end
  end

  @doc """
  GET /api/v1/ontologies/:id

  Retrieve detailed information about a specific ontology.

  Path params:
    - id: Ontology identifier (e.g., "fibo-core")

  Response:
    {
      "ontology": {
        "id": "fibo-core",
        "name": "FIBO Core",
        "description": "...",
        "version": "2.0.0",
        "iri": "https://spec.edmcouncil.org/fibo/ontology/master/2023Q3/",
        "namespace": "https://spec.edmcouncil.org/fibo/ontology/master/...",
        "class_count": 456,
        "property_count": 1200,
        "loaded_at": "2026-03-26T10:00:00Z",
        "top_classes": ["Entity", "Event", "Agent"],
        "import_closures": ["fibo-foundation", "fibo-utils"]
      }
    }
  """
  def show(conn, %{"id" => ontology_id}) do
    case Service.get_ontology(ontology_id) do
      {:ok, ontology, metadata} ->
        json(conn, %{
          ontology: serialize_ontology_detail(ontology),
          cache_hit: metadata.cache_hit,
          retrieved_at: metadata.retrieved_at
        })

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "not_found", message: "Ontology #{ontology_id} not found"})

      {:error, reason} ->
        Logger.error("Failed to get ontology #{ontology_id}: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "ontology_service_unavailable", details: inspect(reason)})
    end
  end

  @doc """
  POST /api/v1/ontologies/:id/search

  Search for classes and properties in an ontology.

  Path params:
    - id: Ontology identifier

  Request body:
    {
      "query": "agent",
      "search_type": "class|property|both",
      "limit": 20,
      "offset": 0
    }

  Response:
    {
      "results": [
        {
          "type": "class",
          "name": "Agent",
          "iri": "https://...",
          "description": "An entity capable of action",
          "parents": ["Entity"],
          "children": ["Person", "Organization"],
          "properties": ["hasName", "hasRole"]
        }
      ],
      "count": 5,
      "query": "agent"
    }
  """
  def search(conn, %{"id" => ontology_id} = params) do
    query = params["query"] || ""
    search_type = params["search_type"] || "both"
    limit = String.to_integer(params["limit"] || "20")
    offset = String.to_integer(params["offset"] || "0")

    if String.trim(query) == "" do
      conn
      |> put_status(400)
      |> json(%{error: "validation_failed", message: "query parameter required"})
    else
      case Service.search(ontology_id, query,
             type: search_type,
             limit: limit,
             offset: offset
           ) do
        {:ok, results, metadata} ->
          json(conn, %{
            results: Enum.map(results, &serialize_search_result/1),
            count: length(results),
            query: query,
            cache_hit: metadata.cache_hit,
            retrieved_at: metadata.retrieved_at
          })

        {:error, :not_found} ->
          conn
          |> put_status(404)
          |> json(%{error: "not_found", message: "Ontology #{ontology_id} not found"})

        {:error, reason} ->
          Logger.error("Search failed in #{ontology_id}: #{inspect(reason)}")

          conn
          |> put_status(500)
          |> json(%{error: "search_failed", details: inspect(reason)})
      end
    end
  end

  @doc """
  GET /api/v1/ontologies/statistics/global

  Get aggregate statistics across all loaded ontologies.

  Response:
    {
      "statistics": {
        "total_ontologies": 15,
        "total_classes": 4250,
        "total_properties": 8900,
        "total_individuals": 1200,
        "last_updated": "2026-03-26T10:00:00Z",
        "cache_hits": 25430,
        "cache_misses": 234,
        "cache_hit_rate": 0.991
      }
    }
  """
  def statistics(conn, _params) do
    case Service.get_statistics() do
      {:ok, stats, metadata} ->
        json(conn, %{
          statistics: serialize_statistics(stats),
          cache_hit: metadata.cache_hit,
          retrieved_at: metadata.retrieved_at
        })

      {:error, reason} ->
        Logger.error("Failed to get ontology statistics: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "statistics_unavailable", details: inspect(reason)})
    end
  end

  @doc """
  GET /api/v1/ontologies/:id/classes/:class_id

  Retrieve detailed information about a specific ontology class.

  Path params:
    - id: Ontology identifier
    - class_id: Class IRI or local name

  Response:
    {
      "class": {
        "iri": "https://...",
        "local_name": "Agent",
        "description": "...",
        "is_deprecated": false,
        "parent_classes": ["Entity"],
        "child_classes": ["Person", "Organization"],
        "disjoint_classes": [],
        "equivalent_classes": [],
        "properties": ["hasName", "hasRole"]
      }
    }
  """
  def get_class(conn, %{"id" => ontology_id, "class_id" => class_id}) do
    case Service.get_class(ontology_id, class_id) do
      {:ok, class_info, metadata} ->
        json(conn, %{
          class: serialize_class(class_info),
          cache_hit: metadata.cache_hit,
          retrieved_at: metadata.retrieved_at
        })

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{
          error: "not_found",
          message: "Class #{class_id} not found in ontology #{ontology_id}"
        })

      {:error, reason} ->
        Logger.error("Failed to get class #{class_id}: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "class_lookup_failed", details: inspect(reason)})
    end
  end

  # ── Private Serializers ──────────────────────────────────────────────────

  defp serialize_ontology(ontology) do
    %{
      "id" => Map.get(ontology, :id) || Map.get(ontology, "id"),
      "name" => Map.get(ontology, :name) || Map.get(ontology, "name"),
      "description" => Map.get(ontology, :description) || Map.get(ontology, "description"),
      "version" => Map.get(ontology, :version) || Map.get(ontology, "version"),
      "class_count" => Map.get(ontology, :class_count) || Map.get(ontology, "class_count") || 0,
      "property_count" =>
        Map.get(ontology, :property_count) || Map.get(ontology, "property_count") || 0,
      "loaded_at" => Map.get(ontology, :loaded_at) || Map.get(ontology, "loaded_at")
    }
  end

  defp serialize_ontology_detail(ontology) do
    serialize_ontology(ontology)
    |> Map.merge(%{
      "iri" => Map.get(ontology, :iri) || Map.get(ontology, "iri"),
      "namespace" => Map.get(ontology, :namespace) || Map.get(ontology, "namespace"),
      "top_classes" => Map.get(ontology, :top_classes) || Map.get(ontology, "top_classes") || [],
      "import_closures" =>
        Map.get(ontology, :import_closures) || Map.get(ontology, "import_closures") || []
    })
  end

  defp serialize_search_result(result) do
    %{
      "type" => Map.get(result, :type) || Map.get(result, "type"),
      "name" => Map.get(result, :name) || Map.get(result, "name"),
      "iri" => Map.get(result, :iri) || Map.get(result, "iri"),
      "description" => Map.get(result, :description) || Map.get(result, "description"),
      "parents" => Map.get(result, :parents) || Map.get(result, "parents") || [],
      "children" => Map.get(result, :children) || Map.get(result, "children") || [],
      "properties" => Map.get(result, :properties) || Map.get(result, "properties") || []
    }
  end

  defp serialize_class(class_info) do
    %{
      "iri" => Map.get(class_info, :iri) || Map.get(class_info, "iri"),
      "local_name" => Map.get(class_info, :local_name) || Map.get(class_info, "local_name"),
      "description" => Map.get(class_info, :description) || Map.get(class_info, "description"),
      "is_deprecated" =>
        Map.get(class_info, :is_deprecated) || Map.get(class_info, "is_deprecated") || false,
      "parent_classes" =>
        Map.get(class_info, :parent_classes) || Map.get(class_info, "parent_classes") || [],
      "child_classes" =>
        Map.get(class_info, :child_classes) || Map.get(class_info, "child_classes") || [],
      "disjoint_classes" =>
        Map.get(class_info, :disjoint_classes) || Map.get(class_info, "disjoint_classes") || [],
      "equivalent_classes" =>
        Map.get(class_info, :equivalent_classes) || Map.get(class_info, "equivalent_classes") ||
          [],
      "properties" => Map.get(class_info, :properties) || Map.get(class_info, "properties") || []
    }
  end

  defp serialize_statistics(stats) do
    %{
      "total_ontologies" =>
        Map.get(stats, :total_ontologies) || Map.get(stats, "total_ontologies") || 0,
      "total_classes" => Map.get(stats, :total_classes) || Map.get(stats, "total_classes") || 0,
      "total_properties" =>
        Map.get(stats, :total_properties) || Map.get(stats, "total_properties") || 0,
      "total_individuals" =>
        Map.get(stats, :total_individuals) || Map.get(stats, "total_individuals") || 0,
      "last_updated" => Map.get(stats, :last_updated) || Map.get(stats, "last_updated"),
      "cache_hits" => Map.get(stats, :cache_hits) || Map.get(stats, "cache_hits") || 0,
      "cache_misses" => Map.get(stats, :cache_misses) || Map.get(stats, "cache_misses") || 0,
      "cache_hit_rate" =>
        Map.get(stats, :cache_hit_rate) || Map.get(stats, "cache_hit_rate") || 0.0
    }
  end
end
