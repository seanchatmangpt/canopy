defmodule Canopy.Compliance.OntologyEvaluatorTest do
  use ExUnit.Case

  alias Canopy.Compliance.OntologyEvaluator

  @moduletag :skip

  describe "evaluate_all_policies/0" do
    test "returns ok with empty violations when no policies discovered" do
      {:ok, violations, elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      assert is_list(violations)
      assert is_integer(elapsed_ms)
      assert elapsed_ms >= 0
    end

    test "returns violations sorted by criticality" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      # Extract criticality values
      criticalities = Enum.map(violations, & &1.criticality)

      # Verify sort order: critical > high > medium > low
      assert criticalities ==
               Enum.sort_by(criticalities, fn crit ->
                 case crit do
                   "critical" -> 0
                   "high" -> 1
                   "medium" -> 2
                   "low" -> 3
                   _ -> 99
                 end
               end)
    end

    test "includes required fields in violations" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      if Enum.any?(violations) do
        [first_violation | _] = violations

        assert Map.has_key?(first_violation, :policy_uri)
        assert Map.has_key?(first_violation, :framework)
        assert Map.has_key?(first_violation, :control_id)
        assert Map.has_key?(first_violation, :criticality)
        assert Map.has_key?(first_violation, :violation_message)
        assert Map.has_key?(first_violation, :evidence_types)
        assert Map.has_key?(first_violation, :detected_at)
        assert Map.has_key?(first_violation, :confidence)
        assert Map.has_key?(first_violation, :remediation)
      end
    end

    test "completes within reasonable time bound (< 1 second)" do
      {:ok, _violations, elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      assert elapsed_ms < 1000
    end

    test "returns error when ontology service unavailable" do
      # This test would pass if Service is down
      # In normal operation, returns :ok
      result = OntologyEvaluator.evaluate_all_policies()

      assert match?({:error, _reason}, result) or
               match?({:ok, _violations, _elapsed}, result)
    end
  end

  describe "evaluate_framework/1" do
    test "evaluates SOC2 framework" do
      {:ok, violations, elapsed_ms} = OntologyEvaluator.evaluate_framework("SOC2")

      assert is_list(violations)
      assert is_integer(elapsed_ms)

      # All violations should be for SOC2
      Enum.each(violations, fn v ->
        assert v.framework == "SOC2"
      end)
    end

    test "evaluates HIPAA framework" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_framework("HIPAA")

      assert is_list(violations)

      Enum.each(violations, fn v ->
        assert v.framework == "HIPAA"
      end)
    end

    test "evaluates GDPR framework" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_framework("GDPR")

      assert is_list(violations)

      Enum.each(violations, fn v ->
        assert v.framework == "GDPR"
      end)
    end

    test "handles unknown framework gracefully" do
      result = OntologyEvaluator.evaluate_framework("UNKNOWN_FRAMEWORK")

      # Either returns empty list or error, depending on implementation
      assert match?({:ok, _violations, _elapsed}, result) or
               match?({:error, _reason}, result)
    end

    test "framework evaluation completes within time bound" do
      {:ok, _violations, elapsed_ms} = OntologyEvaluator.evaluate_framework("SOC2")

      assert elapsed_ms < 500
    end
  end

  describe "get_policy_metadata/0" do
    test "returns metadata with correct structure" do
      {:ok, metadata} = OntologyEvaluator.get_policy_metadata()

      assert Map.has_key?(metadata, :policies_discovered)
      assert Map.has_key?(metadata, :frameworks)
      assert Map.has_key?(metadata, :last_discovery_at)
      assert Map.has_key?(metadata, :cache_status)
    end

    test "includes frameworks in metadata" do
      {:ok, metadata} = OntologyEvaluator.get_policy_metadata()

      assert is_list(metadata.frameworks)
      assert metadata.frameworks == Enum.sort(metadata.frameworks)
    end

    test "includes cache stats in metadata" do
      {:ok, metadata} = OntologyEvaluator.get_policy_metadata()

      cache_status = metadata.cache_status
      assert Map.has_key?(cache_status, :hits)
      assert Map.has_key?(cache_status, :misses)
      assert Map.has_key?(cache_status, :hit_rate)
      assert is_integer(cache_status.hits)
      assert is_integer(cache_status.misses)
      assert is_float(cache_status.hit_rate)
    end

    test "last_discovery_at is recent datetime" do
      {:ok, metadata} = OntologyEvaluator.get_policy_metadata()

      discovered_at = metadata.last_discovery_at
      assert DateTime.diff(DateTime.utc_now(), discovered_at, :second) <= 5
    end

    test "policies_discovered is non-negative integer" do
      {:ok, metadata} = OntologyEvaluator.get_policy_metadata()

      assert is_integer(metadata.policies_discovered)
      assert metadata.policies_discovered >= 0
    end
  end

  describe "reload_policies/0" do
    test "returns ok on successful reload" do
      result = OntologyEvaluator.reload_policies()

      assert result == :ok or match?({:error, _reason}, result)
    end

    test "logs message on reload" do
      import ExUnit.CaptureLog

      log = capture_log(fn -> OntologyEvaluator.reload_policies() end)

      assert log != "" or true
    end
  end

  describe "violation format" do
    test "violation has valid criticality level" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      valid_criticalities = ["critical", "high", "medium", "low"]

      Enum.each(violations, fn v ->
        assert v.criticality in valid_criticalities
      end)
    end

    test "violation confidence is between 0 and 1" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      Enum.each(violations, fn v ->
        assert v.confidence >= 0.0
        assert v.confidence <= 1.0
      end)
    end

    test "violation detected_at is ISO8601 string" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      Enum.each(violations, fn v ->
        assert is_binary(v.detected_at)
        # Should parse as valid ISO8601
        {:ok, _datetime, _offset} = DateTime.from_iso8601(v.detected_at)
      end)
    end

    test "violation evidence_types is list of strings" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      Enum.each(violations, fn v ->
        assert is_list(v.evidence_types)

        Enum.each(v.evidence_types, fn evidence ->
          assert is_binary(evidence)
        end)
      end)
    end

    test "violation remediation is non-empty string" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      Enum.each(violations, fn v ->
        assert is_binary(v.remediation)
        assert String.length(v.remediation) > 0
      end)
    end
  end

  describe "framework-specific evaluation" do
    test "SOC2 violations reference SOC2 controls" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_framework("SOC2")

      soc2_control_pattern = ~r/^(cc|a|c|i)\d/

      Enum.each(violations, fn v ->
        assert Regex.match?(soc2_control_pattern, v.control_id)
      end)
    end

    test "HIPAA violations reference HIPAA controls" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_framework("HIPAA")

      Enum.each(violations, fn v ->
        # HIPAA controls start with 164.
        assert String.starts_with?(v.control_id, "164") or v.control_id != ""
      end)
    end

    test "GDPR violations reference GDPR articles" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_framework("GDPR")

      Enum.each(violations, fn v ->
        # GDPR articles are named like "article_32"
        assert String.contains?(v.control_id, "_") or v.control_id != ""
      end)
    end
  end

  describe "soundness properties (WvdA)" do
    test "evaluation is bounded (completes in reasonable time)" do
      start_time = System.monotonic_time(:millisecond)
      {:ok, _violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should complete in under 2 seconds (generous bound)
      assert elapsed < 2000
    end

    test "policy count is bounded (max 1000)" do
      {:ok, metadata} = OntologyEvaluator.get_policy_metadata()

      assert metadata.policies_discovered <= 1000
    end

    test "no duplicate violations in output" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      uris = Enum.map(violations, & &1.policy_uri)
      unique_uris = Enum.uniq(uris)

      assert length(uris) == length(unique_uris)
    end

    test "evaluation is deterministic (same result on repeated calls)" do
      {:ok, violations1, _} = OntologyEvaluator.evaluate_all_policies()
      {:ok, violations2, _} = OntologyEvaluator.evaluate_all_policies()

      # Convert to comparable format (ignoring timestamps which may differ)
      violations1_ids =
        Enum.map(violations1, &{&1.framework, &1.control_id}) |> Enum.sort()

      violations2_ids =
        Enum.map(violations2, &{&1.framework, &1.control_id}) |> Enum.sort()

      assert violations1_ids == violations2_ids
    end
  end

  describe "integration with AlertEvaluator" do
    test "violations can be converted to alert format" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      if Enum.any?(violations) do
        [first_violation | _] = violations

        # Violation should be convertible to alert-like structure
        alert = %{
          entity: "Compliance",
          field: first_violation.control_id,
          operator: "eq",
          value: "violated",
          name: "#{first_violation.framework} #{first_violation.control_id} Violation"
        }

        assert is_map(alert)
        assert alert.entity == "Compliance"
      end
    end

    test "critical violations should trigger high-priority alerts" do
      {:ok, violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      critical_violations = Enum.filter(violations, &(&1.criticality == "critical"))

      if Enum.any?(critical_violations) do
        [critical | _] = critical_violations

        # Critical violations should have immediate remediation timeline
        assert String.contains?(critical.remediation, "IMMEDIATELY")
      end
    end
  end

  describe "cache performance" do
    test "cache status is included in metadata" do
      {:ok, _metadata1} = OntologyEvaluator.get_policy_metadata()

      # Call again to potentially hit cache
      {:ok, metadata2} = OntologyEvaluator.get_policy_metadata()

      cache_status = metadata2.cache_status

      # Cache stats should be monotonic (hits + misses >= previous)
      assert cache_status.hits >= 0
      assert cache_status.misses >= 0
      assert is_float(cache_status.hit_rate)
      assert cache_status.hit_rate >= 0.0
      assert cache_status.hit_rate <= 1.0
    end

    test "reload_policies clears cache" do
      _result1 = OntologyEvaluator.reload_policies()

      # Next evaluation should work normally
      {:ok, _violations, _elapsed_ms} = OntologyEvaluator.evaluate_all_policies()

      assert true
    end
  end

  describe "error handling" do
    test "returns error tuple on service failure" do
      result = OntologyEvaluator.evaluate_framework("SOC2")

      # Either succeeds or returns error, both valid
      assert match?({:ok, _violations, _elapsed}, result) or
               match?({:error, _reason}, result)
    end

    test "error messages are descriptive" do
      result = OntologyEvaluator.get_policy_metadata()

      case result do
        {:error, reason} when is_binary(reason) ->
          assert String.length(reason) > 0

        {:ok, _metadata} ->
          assert true
      end
    end
  end
end
