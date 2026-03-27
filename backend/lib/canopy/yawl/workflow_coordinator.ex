defmodule Canopy.Yawl.WorkflowCoordinator do
  @moduledoc """
  High-level coordinator for YAWL workflow execution.

  Provides a single call to upload a specification and immediately launch a
  case, returning the resulting identifiers as a map so callers have everything
  they need to track or cancel the workflow later.

  ## Usage

      # From an XML string already in memory
      {:ok, %{spec_id: sid, case_id: cid}} =
        Canopy.Yawl.WorkflowCoordinator.coordinate_workflow(xml_string)

      # From a file on disk
      {:ok, %{spec_id: sid, case_id: cid}} =
        Canopy.Yawl.WorkflowCoordinator.coordinate_workflow_from_file("/path/to/spec.yawl")

  Errors from either step are propagated as `{:error, reason}` without
  attempting to roll back (YAWL has no transactional spec-upload semantics).
  """

  require Logger

  alias Canopy.Yawl.Client

  @doc """
  Upload `spec_xml` to the YAWL engine and immediately launch a case.

  Returns `{:ok, %{spec_id: String.t(), case_id: String.t()}}` on success, or
  `{:error, reason}` if either step fails.
  """
  @spec coordinate_workflow(String.t()) ::
          {:ok, %{spec_id: String.t(), case_id: String.t()}} | {:error, term()}
  def coordinate_workflow(spec_xml) when is_binary(spec_xml) do
    with {:ok, spec_id} <- Client.upload_spec(spec_xml),
         {:ok, case_id} <- Client.launch_case(spec_id) do
      Logger.info("[WorkflowCoordinator] Launched case — spec_id=#{spec_id} case_id=#{case_id}")
      {:ok, %{spec_id: spec_id, case_id: case_id}}
    else
      {:error, reason} = err ->
        Logger.warning("[WorkflowCoordinator] coordinate_workflow failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Read the YAWL specification from `file_path` and delegate to
  `coordinate_workflow/1`.

  Raises `File.Error` if the file cannot be read (consistent with `File.read!/1`).
  """
  @spec coordinate_workflow_from_file(String.t()) ::
          {:ok, %{spec_id: String.t(), case_id: String.t()}} | {:error, term()}
  def coordinate_workflow_from_file(file_path) when is_binary(file_path) do
    xml = File.read!(file_path)
    coordinate_workflow(xml)
  end
end
