defmodule Canopy.Ontology.Client do
  @moduledoc """
  HTTP client for communicating with OSA's ontology registry.

  Handles requests to OSA's ontology API endpoints with timeout and error handling.
  Caches ontology metadata locally via `Canopy.Ontology.Loader`.
  """
  require Logger

  @doc """
  List all available ontologies with pagination.

  Options:
    - limit: Max results (default 50)
    - offset: Pagination offset (default 0)

  Returns:
    {:ok, [ontologies], total_count}
    {:error, reason}
  """
  def list_ontologies(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    osa_url = osa_base_url()

    case Req.get("#{osa_url}/api/v1/ontologies", params: [limit: limit, offset: offset]) do
      {:ok, %{status: 200, body: %{"ontologies" => ontologies, "total" => total}}} ->
        {:ok, ontologies, total}

      {:ok, %{status: status, body: body}} ->
        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to list ontologies from OSA: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Get detailed information about a specific ontology.

  Args:
    ontology_id: Ontology identifier (e.g., "fibo-core")

  Returns:
    {:ok, ontology_map}
    {:error, reason}
  """
  def get_ontology(ontology_id) do
    osa_url = osa_base_url()

    case Req.get("#{osa_url}/api/v1/ontologies/#{ontology_id}") do
      {:ok, %{status: 200, body: %{"ontology" => ontology}}} ->
        {:ok, ontology}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} when is_integer(status) ->
        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to get ontology #{ontology_id}: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Search for classes and properties in an ontology.

  Args:
    ontology_id: Ontology identifier
    query: Search term
    opts: Options including:
      - type: "class", "property", or "both" (default: "both")
      - limit: Max results (default: 20)
      - offset: Pagination offset (default: 0)

  Returns:
    {:ok, [results]}
    {:error, reason}
  """
  def search(ontology_id, query, opts \\ []) do
    search_type = Keyword.get(opts, :type, "both")
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    osa_url = osa_base_url()

    body = %{
      "query" => query,
      "search_type" => search_type,
      "limit" => limit,
      "offset" => offset
    }

    case Req.post("#{osa_url}/api/v1/ontologies/#{ontology_id}/search", json: body) do
      {:ok, %{status: 200, body: %{"results" => results}}} ->
        {:ok, results}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("Search failed in ontology #{ontology_id}: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Get detailed information about a specific class in an ontology.

  Args:
    ontology_id: Ontology identifier
    class_id: Class IRI or local name

  Returns:
    {:ok, class_info_map}
    {:error, reason}
  """
  def get_class(ontology_id, class_id) do
    osa_url = osa_base_url()
    encoded_class_id = URI.encode_www_form(class_id)

    case Req.get("#{osa_url}/api/v1/ontologies/#{ontology_id}/classes/#{encoded_class_id}") do
      {:ok, %{status: 200, body: %{"class" => class_info}}} ->
        {:ok, class_info}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} when is_integer(status) ->
        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to get class #{class_id}: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Get aggregate statistics across all loaded ontologies.

  Returns:
    {:ok, stats_map}
    {:error, reason}
  """
  def get_statistics do
    osa_url = osa_base_url()

    case Req.get("#{osa_url}/api/v1/ontologies/statistics") do
      {:ok, %{status: 200, body: %{"statistics" => stats}}} ->
        {:ok, stats}

      {:ok, %{status: status, body: body}} ->
        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to get ontology statistics: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc """
  Reload ontologies from OSA registry.

  Used when ontologies are updated on the OSA side.

  Returns:
    :ok
    {:error, reason}
  """
  def reload_ontologies do
    osa_url = osa_base_url()

    case Req.post("#{osa_url}/api/v1/ontologies/reload", json: %{}) do
      {:ok, %{status: 200}} ->
        Logger.info("Ontologies reloaded from OSA")
        :ok

      {:ok, %{status: status, body: body}} when is_integer(status) ->
        Logger.error("Failed to reload ontologies: #{status} #{inspect(body)}")
        {:error, {:osa_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to reload ontologies: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # ── Private Helpers ──────────────────────────────────────────────────────

  defp osa_base_url do
    System.get_env("OSA_URL") || "http://127.0.0.1:8089"
  end
end
