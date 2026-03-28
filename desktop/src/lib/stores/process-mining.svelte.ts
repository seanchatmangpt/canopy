// src/lib/stores/process-mining.svelte.ts
// Svelte 5 Runes store for process mining data from BusinessOS.

import { processMining } from "$lib/api/client";
import type {
  ProcessMiningKPIs,
  ProcessDiscoveryParams,
  ProcessDiscoveryResult,
  ProcessMiningStatus,
} from "$api/types";

// ── State ─────────────────────────────────────────────────────────────────────

let kpis = $state<ProcessMiningKPIs | null>(null);
let status = $state<ProcessMiningStatus | null>(null);
let lastDiscovery = $state<ProcessDiscoveryResult | null>(null);
let loading = $state(false);
let discovering = $state(false);
let error = $state<string | null>(null);

// ── Derived ───────────────────────────────────────────────────────────────────

const bosAvailable = $derived(kpis?.businessos_available ?? status?.businessos_available ?? false);

const conformancePercent = $derived(
  kpis?.conformance_score != null ? Math.round(kpis.conformance_score * 100) : null,
);

// ── Actions ───────────────────────────────────────────────────────────────────

async function loadKPIs(params?: { workspace_id?: string }): Promise<void> {
  loading = true;
  error = null;
  try {
    kpis = await processMining.kpis(params);
  } catch (e) {
    error = e instanceof Error ? e.message : "Failed to load KPIs";
    kpis = {
      businessos_available: false,
      avg_cycle_time_hours: null,
      conformance_score: null,
      active_cases: null,
      bottleneck_activity: null,
      error: error,
    };
  } finally {
    loading = false;
  }
}

async function loadStatus(): Promise<void> {
  try {
    status = await processMining.status();
  } catch {
    status = { businessos_available: false, status: "unavailable" };
  }
}

async function runDiscovery(params: ProcessDiscoveryParams): Promise<ProcessDiscoveryResult | null> {
  discovering = true;
  error = null;
  try {
    const result = await processMining.discover(params);
    lastDiscovery = result;
    // Refresh KPIs after discovery to pick up new metrics
    await loadKPIs();
    return result;
  } catch (e) {
    error = e instanceof Error ? e.message : "Discovery failed";
    return null;
  } finally {
    discovering = false;
  }
}

// ── Export ────────────────────────────────────────────────────────────────────

export const processMiningStore = {
  get kpis() {
    return kpis;
  },
  get status() {
    return status;
  },
  get lastDiscovery() {
    return lastDiscovery;
  },
  get loading() {
    return loading;
  },
  get discovering() {
    return discovering;
  },
  get error() {
    return error;
  },
  get bosAvailable() {
    return bosAvailable;
  },
  get conformancePercent() {
    return conformancePercent;
  },
  loadKPIs,
  loadStatus,
  runDiscovery,
};
