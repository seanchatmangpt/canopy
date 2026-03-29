defmodule Canopy.JTBD.YAWLv6Simulation do
  @moduledoc """
  YAWLv6 Refactor Simulation — deterministic, iteration-driven.

  Simulates the 14-module Java 26 YAWL engine refactor (aligned to real Maven structure).
  No real `mvnd` calls. Progress is driven by iteration number.

  ## Real Maven Modules (from /Users/sac/yawlv6/pom.xml)

  Phase 1 — Foundation (iterations 1-30):
    1. yawl-core       iterations  1-10  (191 tests, 2 known failures)
    2. yawl-webapp     iterations 11-20  (45 tests)

  Phase 2 — Services (iterations 21-130):
    3. yawl-persistence (resourceService)    iterations 21-33   (156 tests, 4 failures: Hibernate/JDBC)
    4. yawl-auth (workletService)            iterations 34-43   (89 tests)
    5. yawl-engine (monitorService)          iterations 44-68   (312 tests, 14 failures: virtual threads)
    6. yawl-scheduler (costService)          iterations 69-78   (67 tests)
    7. yawl-worklet (mailService)            iterations 79-93   (134 tests, 6 failures: WCP-14 deferred choice)
    8. yawl-resourcing (mailSender)          iterations 94-103  (203 tests)
    9. yawl-logging (digitalSignature)       iterations 104-110 (45 tests)

  Phase 3 — Monitoring (iterations 111-135):
   10. yawl-monitoring (documentStore)       iterations 111-120 (78 tests, 3 failures: JMX/Java 26 thread dump)
   11. yawl-transport (schedulingService)    iterations 121-128 (112 tests)
   12. yawl-notification (yawlSMSInvoker)    iterations 129-135 (56 tests)

  Phase 4 — Integration (iterations 136-160):
   13. yawl-a2a-agent (yawlWSInvoker)        iterations 136-148 (134 tests)
   14. yawl-process-mining (balancer)        iterations 149-160 (89 tests, 2 failures: OCEL 2.0 mapping)

  Total on completion: 1,511 tests, 1,480 passing, 31 known failures
  """

  @modules [
    # Phase 1 — Foundation
    %{
      name: "yawl-core",
      description: "Core YAWL workflow engine — 43 WCP pattern implementations",
      tests: 191,
      passing: 189,
      failures: 2,
      known_issues: ["WCP-18 milestone (Tier 4 — architectural gap)", "fiveConcurrentCases flaky"],
      start_iteration: 1,
      complete_iteration: 10,
      phase: :foundation
    },
    %{
      name: "yawl-webapp",
      description: "Servlet container webapp — Tomcat 10.1.x WAR deployment",
      tests: 45,
      passing: 45,
      failures: 0,
      known_issues: [],
      start_iteration: 11,
      complete_iteration: 20,
      phase: :foundation
    },
    # Phase 2 — Services (13 real Maven service modules)
    %{
      name: "resourceService",
      description: "Resource allocation — WCP-37-42 resource distribution patterns",
      tests: 156,
      passing: 152,
      failures: 4,
      known_issues: [
        "JDBC connection pool timeout under load",
        "Hibernate schema validation strict mode"
      ],
      start_iteration: 21,
      complete_iteration: 33,
      phase: :services
    },
    %{
      name: "workletService",
      description:
        "Dynamic subworkflow service — WCP-14 deferred choice, WCP-16 implicit termination",
      tests: 89,
      passing: 89,
      failures: 0,
      known_issues: [],
      start_iteration: 34,
      complete_iteration: 43,
      phase: :services
    },
    %{
      name: "monitorService",
      description: "Runtime execution engine — Java 26 virtual threads, records, sealed classes",
      tests: 312,
      passing: 298,
      failures: 14,
      known_issues: [
        "Virtual thread pinning in synchronized blocks (Java 26 requires carrier thread rebalancing)",
        "Record serialization compatibility with existing workflow definitions",
        "Sequenced collections API migration from ArrayList usage"
      ],
      start_iteration: 44,
      complete_iteration: 68,
      phase: :services
    },
    %{
      name: "costService",
      description: "Cron-based task scheduler — Quantum integration",
      tests: 67,
      passing: 67,
      failures: 0,
      known_issues: [],
      start_iteration: 69,
      complete_iteration: 78,
      phase: :services
    },
    %{
      name: "mailService",
      description: "Mail service integration — email notifications",
      tests: 134,
      passing: 128,
      failures: 6,
      known_issues: [
        "Dynamic subworkflow context propagation via scoped values (Java 26 JEP 429)",
        "WCP-14 deferred choice: external trigger race condition under high concurrency"
      ],
      start_iteration: 79,
      complete_iteration: 93,
      phase: :services
    },
    %{
      name: "mailSender",
      description: "Mail sender service — async email dispatch",
      tests: 203,
      passing: 203,
      failures: 0,
      known_issues: [],
      start_iteration: 94,
      complete_iteration: 103,
      phase: :services
    },
    %{
      name: "digitalSignature",
      description: "Digital signature service — document signing",
      tests: 45,
      passing: 45,
      failures: 0,
      known_issues: [],
      start_iteration: 104,
      complete_iteration: 110,
      phase: :services
    },
    # Phase 3 — Monitoring (3 real service modules)
    %{
      name: "documentStore",
      description: "Document storage service — cloud integration",
      tests: 78,
      passing: 75,
      failures: 3,
      known_issues: [
        "JMX MBean registration conflict with Java 26 management API changes",
        "Thread dump format changed in Java 26 (virtual thread representation)"
      ],
      start_iteration: 111,
      complete_iteration: 120,
      phase: :monitoring
    },
    %{
      name: "schedulingService",
      description: "Scheduling service — workflow task scheduling",
      tests: 112,
      passing: 112,
      failures: 0,
      known_issues: [],
      start_iteration: 121,
      complete_iteration: 128,
      phase: :monitoring
    },
    %{
      name: "yawlSMSInvoker",
      description: "SMS invoker service — SMS notifications",
      tests: 56,
      passing: 56,
      failures: 0,
      known_issues: [],
      start_iteration: 129,
      complete_iteration: 135,
      phase: :monitoring
    },
    # Phase 4 — Integration (2 real service modules)
    %{
      name: "yawlWSInvoker",
      description: "Web service invoker — SOAP/REST integration",
      tests: 134,
      passing: 134,
      failures: 0,
      known_issues: [],
      start_iteration: 136,
      complete_iteration: 148,
      phase: :integration
    },
    %{
      name: "balancer",
      description: "Load balancer service — process mining bridge",
      tests: 89,
      passing: 87,
      failures: 2,
      known_issues: [
        "OCEL 2.0 event log format mapping — object type registry alignment with pm4py-rust",
        "Petri net fitness threshold calibration for workflow variant detection"
      ],
      start_iteration: 149,
      complete_iteration: 160,
      phase: :integration
    }
  ]

  @total_iterations 160
  @total_modules length(@modules)

  @doc """
  Run a simulation checkpoint for the given iteration.

  Returns the same shape as the real mvnd runner:
    %{outcome, tests_passed, tests_failed, modules_complete, modules_total,
      current_phase, simulation: true, ...}
  """
  @spec checkpoint(non_neg_integer()) :: map()
  def checkpoint(iteration) do
    modules_status = Enum.map(@modules, &module_status(&1, iteration))

    complete = Enum.filter(modules_status, &(&1.sim_status == :complete))
    in_progress = Enum.find(modules_status, &(&1.sim_status == :building))

    total_passing = Enum.sum(Enum.map(complete, & &1.passing))
    total_tests = Enum.sum(Enum.map(complete, & &1.tests))

    # Add partial counts from in-progress module
    {partial_passing, partial_tests} =
      if in_progress do
        progress = module_progress(in_progress, iteration)
        {round(in_progress.passing * progress), round(in_progress.tests * progress)}
      else
        {0, 0}
      end

    modules_complete = length(complete)
    phase = current_phase(modules_status)
    refactor_complete = modules_complete == @total_modules

    %{
      outcome: if(refactor_complete, do: :complete, else: :in_progress),
      tests_passed: total_passing + partial_passing,
      tests_failed: total_tests - total_passing + (partial_tests - partial_passing),
      modules_complete: modules_complete,
      modules_total: @total_modules,
      current_phase: phase,
      in_progress_module: if(in_progress, do: in_progress.name, else: nil),
      percent_complete: Float.round(modules_complete / @total_modules * 100, 1),
      iteration: iteration,
      total_iterations_to_complete: @total_iterations,
      known_issues: known_issues_for_phase(modules_status, in_progress),
      simulation: true,
      projected_completion_iteration: @total_iterations
    }
  end

  @doc "Summary string for dashboard display"
  @spec summary_line(map()) :: String.t()
  def summary_line(%{simulation: true} = state) do
    status_icon =
      cond do
        state.outcome == :complete -> "✅"
        state.modules_complete >= 12 -> "🟡"
        state.modules_complete >= 6 -> "🔵"
        true -> "🔄"
      end

    progress_bar = progress_bar(state.modules_complete, state.modules_total)

    if state.outcome == :complete do
      "#{status_icon} COMPLETE #{progress_bar} #{state.modules_complete}/#{state.modules_total} modules | #{state.tests_passed}/#{state.tests_passed + state.tests_failed} tests passing"
    else
      in_prog =
        if state.in_progress_module, do: " | building: #{state.in_progress_module}", else: ""

      "#{status_icon} #{state.current_phase} #{progress_bar} #{state.modules_complete}/#{state.modules_total}#{in_prog} | #{state.percent_complete}%"
    end
  end

  # --- Private ---

  defp module_status(mod, iteration) do
    cond do
      iteration >= mod.complete_iteration ->
        Map.put(mod, :sim_status, :complete)

      iteration >= mod.start_iteration ->
        Map.put(mod, :sim_status, :building)

      true ->
        Map.put(mod, :sim_status, :queued)
    end
  end

  defp module_progress(mod, iteration) do
    span = mod.complete_iteration - mod.start_iteration
    elapsed = iteration - mod.start_iteration
    min(elapsed / span, 1.0)
  end

  defp current_phase(modules_status) do
    in_prog = Enum.find(modules_status, &(&1.sim_status == :building))
    if in_prog, do: in_prog.phase, else: :complete
  end

  defp known_issues_for_phase(modules_status, nil),
    do:
      Enum.flat_map(Enum.filter(modules_status, &(&1.sim_status == :complete)), & &1.known_issues)

  defp known_issues_for_phase(_modules_status, in_progress), do: in_progress.known_issues

  defp progress_bar(complete, total) do
    filled = round(complete / total * 10)
    empty = 10 - filled
    "[" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "]"
  end

  @doc false
  defp call_yawl_conformance(spec_xml, event_log_json) do
    url = Application.get_env(:canopy, :yawl_url, "http://localhost:8080")
    body = %{spec: spec_xml, event_log: event_log_json}

    case Req.post("#{url}/api/process-mining/conformance",
           json: body,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: response_body}} when is_map(response_body) ->
        {:ok,
         %{
           fitness: Map.get(response_body, "fitness", 0.0),
           violations: Map.get(response_body, "violations", []),
           is_sound: Map.get(response_body, "is_sound", false)
         }}

      {:ok, _response} ->
        {:error, :yawl_unavailable}

      {:error, _reason} ->
        {:error, :yawl_unavailable}
    end
  rescue
    ArgumentError ->
      # Req.Finch registry not started (--no-start mode)
      {:error, :yawl_unavailable}
  end

  @doc false
  defp emit_conformance_event(pattern, fitness, violations) do
    if Process.whereis(Canopy.PubSub) != nil do
      Phoenix.PubSub.broadcast(
        Canopy.PubSub,
        "yawl:conformance",
        {:yawl_conformance, %{pattern: pattern, fitness: fitness, violations: violations}}
      )
    end

    :ok
  end

  @doc """
  Run conformance check for a named YAWL pattern against the process mining REST API,
  then emit a Phoenix.PubSub event if PubSub is running.

  Returns `{:ok, conformance_result}` on success or `{:error, reason}` on failure.
  Fails fast if YAWL is unavailable (does not degrade gracefully).
  """
  @spec check_and_emit_conformance(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, atom()}
  def check_and_emit_conformance(pattern_name, spec_xml, event_log \\ %{}) do
    case call_yawl_conformance(spec_xml, event_log) do
      {:ok, %{fitness: fitness, violations: violations} = result} ->
        emit_conformance_event(pattern_name, fitness, violations)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
