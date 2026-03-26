defmodule Canopy.JTBD.YAWLv6Simulation do
  @moduledoc """
  YAWLv6 Refactor Simulation — deterministic, iteration-driven.

  Simulates the 16-module Java 26 YAWL engine refactor.
  No real `mvnd` calls. Progress is driven by iteration number.

  ## Module Timeline (176 iterations = full refactor)

  Phase 1 — Foundation (iterations 1-30):
    1. yawl-core       iterations  1-10  (191 tests, 2 known failures)
    2. yawl-webapp     iterations 11-20  (45 tests)
    3. yawl-api        iterations 21-30  (78 tests)

  Phase 2 — Services (iterations 31-130):
    4. yawl-persistence iterations 31-45  (156 tests, 4 failures: Hibernate/JDBC)
    5. yawl-auth        iterations 46-55  (89 tests)
    6. yawl-engine      iterations 56-80  (312 tests, 14 failures: virtual threads)
    7. yawl-scheduler   iterations 81-90  (67 tests)
    8. yawl-worklet     iterations 91-105 (134 tests, 6 failures: WCP-14 deferred choice)
    9. yawl-resourcing  iterations 106-115 (203 tests)
   10. yawl-logging     iterations 116-122 (45 tests)

  Phase 3 — Monitoring (iterations 123-148):
   11. yawl-monitoring  iterations 123-132 (78 tests, 3 failures: JMX/Java 26 thread dump)
   12. yawl-transport   iterations 133-140 (112 tests)
   13. yawl-notification iterations 141-148 (56 tests)

  Phase 4 — Integration (iterations 149-176):
   14. yawl-process-mining  iterations 149-158 (89 tests, 2 failures: OCEL 2.0 mapping)
   15. yawl-a2a-agent       iterations 159-167 (134 tests)
   16. yawl-node-mcp        iterations 168-176 (78 tests)

  Total on completion: 1,871 tests, 1,840 passing, 31 known failures
  """

  @modules [
    # Phase 1 — Foundation
    %{
      name: "yawl-core",
      description: "Core YAWL workflow engine — 43 WCP pattern implementations",
      tests: 191, passing: 189, failures: 2,
      known_issues: ["WCP-18 milestone (Tier 4 — architectural gap)", "fiveConcurrentCases flaky"],
      start_iteration: 1, complete_iteration: 10,
      phase: :foundation
    },
    %{
      name: "yawl-webapp",
      description: "Servlet container webapp — Tomcat 10.1.x WAR deployment",
      tests: 45, passing: 45, failures: 0,
      known_issues: [],
      start_iteration: 11, complete_iteration: 20,
      phase: :foundation
    },
    %{
      name: "yawl-api",
      description: "Public REST API — workflow lifecycle endpoints",
      tests: 78, passing: 78, failures: 0,
      known_issues: [],
      start_iteration: 21, complete_iteration: 30,
      phase: :foundation
    },
    # Phase 2 — Services
    %{
      name: "yawl-persistence",
      description: "JPA/Hibernate persistence layer — PostgreSQL + H2",
      tests: 156, passing: 152, failures: 4,
      known_issues: ["JDBC connection pool timeout under load", "Hibernate schema validation strict mode"],
      start_iteration: 31, complete_iteration: 45,
      phase: :services
    },
    %{
      name: "yawl-auth",
      description: "Authentication + authorization — JWT + role-based access",
      tests: 89, passing: 89, failures: 0,
      known_issues: [],
      start_iteration: 46, complete_iteration: 55,
      phase: :services
    },
    %{
      name: "yawl-engine",
      description: "Runtime execution engine — Java 26 virtual threads, records, sealed classes",
      tests: 312, passing: 298, failures: 14,
      known_issues: [
        "Virtual thread pinning in synchronized blocks (Java 26 requires carrier thread rebalancing)",
        "Record serialization compatibility with existing workflow definitions",
        "Sequenced collections API migration from ArrayList usage"
      ],
      start_iteration: 56, complete_iteration: 80,
      phase: :services
    },
    %{
      name: "yawl-scheduler",
      description: "Cron-based task scheduler — Quantum integration",
      tests: 67, passing: 67, failures: 0,
      known_issues: [],
      start_iteration: 81, complete_iteration: 90,
      phase: :services
    },
    %{
      name: "yawl-worklet",
      description: "Dynamic subworkflow service — WCP-14 deferred choice, WCP-16 implicit termination",
      tests: 134, passing: 128, failures: 6,
      known_issues: [
        "Dynamic subworkflow context propagation via scoped values (Java 26 JEP 429)",
        "WCP-14 deferred choice: external trigger race condition under high concurrency"
      ],
      start_iteration: 91, complete_iteration: 105,
      phase: :services
    },
    %{
      name: "yawl-resourcing",
      description: "Resource allocation — WCP-37-42 resource distribution patterns",
      tests: 203, passing: 203, failures: 0,
      known_issues: [],
      start_iteration: 106, complete_iteration: 115,
      phase: :services
    },
    %{
      name: "yawl-logging",
      description: "Structured audit logging — PROV-O trace generation",
      tests: 45, passing: 45, failures: 0,
      known_issues: [],
      start_iteration: 116, complete_iteration: 122,
      phase: :services
    },
    # Phase 3 — Monitoring
    %{
      name: "yawl-monitoring",
      description: "JMX metrics + health checks — Java 26 thread dump format",
      tests: 78, passing: 75, failures: 3,
      known_issues: [
        "JMX MBean registration conflict with Java 26 management API changes",
        "Thread dump format changed in Java 26 (virtual thread representation)"
      ],
      start_iteration: 123, complete_iteration: 132,
      phase: :monitoring
    },
    %{
      name: "yawl-transport",
      description: "HTTP/WebSocket transport layer — Jakarta EE 10 migration",
      tests: 112, passing: 112, failures: 0,
      known_issues: [],
      start_iteration: 133, complete_iteration: 140,
      phase: :monitoring
    },
    %{
      name: "yawl-notification",
      description: "Event notification service — PubSub + webhook dispatch",
      tests: 56, passing: 56, failures: 0,
      known_issues: [],
      start_iteration: 141, complete_iteration: 148,
      phase: :monitoring
    },
    # Phase 4 — Integration (new capabilities)
    %{
      name: "yawl-process-mining",
      description: "OCPM integration — pm4py-rust bridge, OCEL 2.0 event log export",
      tests: 89, passing: 87, failures: 2,
      known_issues: [
        "OCEL 2.0 event log format mapping — object type registry alignment with pm4py-rust",
        "Petri net fitness threshold calibration for workflow variant detection"
      ],
      start_iteration: 149, complete_iteration: 158,
      phase: :integration
    },
    %{
      name: "yawl-a2a-agent",
      description: "A2A protocol agent — deal lifecycle, negotiation, Canopy integration",
      tests: 134, passing: 134, failures: 0,
      known_issues: [],
      start_iteration: 159, complete_iteration: 167,
      phase: :integration
    },
    %{
      name: "yawl-node-mcp",
      description: "MCP server — YAWL workflow tools exposed as MCP tools for OSA",
      tests: 78, passing: 78, failures: 0,
      known_issues: [],
      start_iteration: 168, complete_iteration: 176,
      phase: :integration
    }
  ]

  @total_iterations 176
  @total_modules length(@modules)
  @total_tests Enum.sum(Enum.map(@modules, & &1.tests))
  @total_passing Enum.sum(Enum.map(@modules, & &1.passing))

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
      tests_failed: (total_tests - total_passing) + (partial_tests - partial_passing),
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
    status_icon = cond do
      state.outcome == :complete -> "✅"
      state.modules_complete >= 12 -> "🟡"
      state.modules_complete >= 6 -> "🔵"
      true -> "🔄"
    end

    progress_bar = progress_bar(state.modules_complete, state.modules_total)

    if state.outcome == :complete do
      "#{status_icon} COMPLETE #{progress_bar} #{state.modules_complete}/#{state.modules_total} modules | #{state.tests_passed}/#{state.tests_passed + state.tests_failed} tests passing"
    else
      in_prog = if state.in_progress_module, do: " | building: #{state.in_progress_module}", else: ""
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

  defp known_issues_for_phase(modules_status, nil), do:
    Enum.flat_map(Enum.filter(modules_status, &(&1.sim_status == :complete)), & &1.known_issues)

  defp known_issues_for_phase(_modules_status, in_progress), do:
    in_progress.known_issues

  defp progress_bar(complete, total) do
    filled = round(complete / total * 10)
    empty = 10 - filled
    "[" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "]"
  end
end
