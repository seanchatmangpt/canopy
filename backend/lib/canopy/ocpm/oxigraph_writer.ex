defmodule Canopy.OCPM.OxigraphWriter do
  @moduledoc """
  Writes process discovery results into Oxigraph L0 via SPARQL UPDATE.

  Called after a BusinessOS discovery webhook arrives. Ensures the L0 named
  graph in Oxigraph reflects real discovery outcomes, enabling the L1→L2→L3
  SPARQL materialization chain to produce accurate board intelligence.

  ## WvdA Soundness

  - All HTTP calls bounded by @oxigraph_timeout_ms (10 s)
  - Oxigraph unavailability is non-fatal: caller logs warning and continues

  ## Canonical Namespace

  bos: <https://chatmangpt.com/ontology/businessos/>
  L0 named graph: <https://chatmangpt.com/ontology/businessos/l0>
  """

  require Logger

  @oxigraph_timeout_ms 10_000
  @l0_graph "https://chatmangpt.com/ontology/businessos/l0"
  @bos_ns "https://chatmangpt.com/ontology/businessos/"
  @data_ns "https://chatmangpt.com/data/discovery/"

  @doc """
  Write a discovery result triple into the Oxigraph L0 named graph.

  ## Parameters

  - `model_id`   — unique model identifier (used as subject URI)
  - `department` — department name (bos:department predicate)
  - `metadata`   — map with `:algorithm`, `:fitness`, `:activities_count`, `:traces_count`

  ## Returns

  `{:ok, 1}` on success, `{:error, :oxigraph_unavailable}` on any failure.
  """
  @spec write_discovery_result(String.t(), String.t(), map()) ::
          {:ok, 1} | {:error, :oxigraph_unavailable}
  def write_discovery_result(model_id, department, metadata \\ %{}) do
    sparql = build_sparql_update(model_id, department, metadata)
    url = "#{oxigraph_url()}/update"

    case Req.post(url,
           body: sparql,
           headers: [{"content-type", "application/sparql-update"}],
           receive_timeout: @oxigraph_timeout_ms
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("[OxigraphWriter] L0 triple written for model=#{model_id}")
        {:ok, 1}

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "[OxigraphWriter] Oxigraph returned HTTP #{status}: #{inspect(body)}"
        )

        {:error, :oxigraph_unavailable}

      {:error, reason} ->
        Logger.warning("[OxigraphWriter] Oxigraph unreachable: #{inspect(reason)}")
        {:error, :oxigraph_unavailable}
    end
  rescue
    _ -> {:error, :oxigraph_unavailable}
  end

  # ── Private ──────────────────────────────────────────────────────────

  defp build_sparql_update(model_id, department, metadata) do
    subject_uri = "#{@data_ns}#{URI.encode(model_id)}"
    algorithm = metadata[:algorithm] || metadata["algorithm"] || "unknown"
    fitness = metadata[:fitness] || metadata["fitness"] || -1.0
    activities = metadata[:activities_count] || metadata["activities_count"] || 0
    traces = metadata[:traces_count] || metadata["traces_count"] || 0
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    PREFIX bos: <#{@bos_ns}>
    PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
    PREFIX prov: <http://www.w3.org/ns/prov#>

    INSERT DATA {
      GRAPH <#{@l0_graph}> {
        <#{subject_uri}> a bos:ProcessDiscoveryResult ;
          bos:modelId #{sparql_string(model_id)} ;
          bos:department #{sparql_string(department)} ;
          bos:algorithm #{sparql_string(algorithm)} ;
          bos:fitnessScore "#{fitness}"^^xsd:decimal ;
          bos:activitiesCount "#{activities}"^^xsd:integer ;
          bos:tracesCount "#{traces}"^^xsd:integer ;
          prov:generatedAtTime "#{now}"^^xsd:dateTime .
      }
    }
    """
  end

  defp sparql_string(value) when is_binary(value) do
    escaped = String.replace(value, "\"", "\\\"")
    "\"#{escaped}\""
  end

  defp sparql_string(value), do: sparql_string(to_string(value))

  defp oxigraph_url do
    System.get_env("OXIGRAPH_URL", "http://localhost:7878")
  end
end
