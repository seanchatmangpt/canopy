// src/lib/stores/compliance-dashboard.svelte.ts
// Svelte 5 Runes store for compliance dashboard data from BusinessOS.

import { compliance } from "$lib/api/client";
import type { ComplianceDashboardStatus, ComplianceFrameworkStatus } from "$api/types";

// ── State ─────────────────────────────────────────────────────────────────────

let dashboardStatus = $state<ComplianceDashboardStatus | null>(null);
let loading = $state(false);
let error = $state<string | null>(null);

// ── Derived ───────────────────────────────────────────────────────────────────

const bosAvailable = $derived(dashboardStatus?.businessos_available ?? false);

const overallPercent = $derived(
  dashboardStatus?.overall_score != null ? Math.round(dashboardStatus.overall_score * 100) : null,
);

const criticalFrameworks = $derived(
  (dashboardStatus?.frameworks ?? []).filter(
    (f: ComplianceFrameworkStatus) => f.status === "non_compliant",
  ),
);

const isCompliant = $derived(dashboardStatus?.status === "compliant");

// ── Actions ───────────────────────────────────────────────────────────────────

async function loadStatus(params?: { workspace_id?: string }): Promise<void> {
  loading = true;
  error = null;
  try {
    dashboardStatus = await compliance.status(params);
  } catch (e) {
    error = e instanceof Error ? e.message : "Failed to load compliance status";
    dashboardStatus = {
      businessos_available: false,
      overall_score: 0,
      status: "unavailable",
      frameworks: [],
      last_checked_at: null,
      error: error,
    };
  } finally {
    loading = false;
  }
}

// ── Export ────────────────────────────────────────────────────────────────────

export const complianceDashboardStore = {
  get dashboardStatus() {
    return dashboardStatus;
  },
  get loading() {
    return loading;
  },
  get error() {
    return error;
  },
  get bosAvailable() {
    return bosAvailable;
  },
  get overallPercent() {
    return overallPercent;
  },
  get criticalFrameworks() {
    return criticalFrameworks;
  },
  get isCompliant() {
    return isCompliant;
  },
  loadStatus,
};
