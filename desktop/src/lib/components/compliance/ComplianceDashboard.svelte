<!-- src/lib/components/compliance/ComplianceDashboard.svelte -->
<script lang="ts">
  import { complianceDashboardStore } from '$lib/stores/compliance-dashboard.svelte';
  import type { ComplianceFrameworkStatus } from '$api/types';

  const STATUS_COLOR: Record<string, string> = {
    compliant: 'var(--accent-success, #22c55e)',
    partial: 'var(--accent-warning, #f59e0b)',
    non_compliant: 'var(--accent-error, #ef4444)',
    unavailable: 'var(--text-muted)',
  };
</script>

<div class="cd-dashboard">
  <!-- Header -->
  <div class="cd-header">
    <h1 class="cd-title">Compliance</h1>
    {#if !complianceDashboardStore.bosAvailable}
      <span class="cd-badge cd-badge-offline">BusinessOS offline</span>
    {:else if complianceDashboardStore.isCompliant}
      <span class="cd-badge cd-badge-compliant">Compliant</span>
    {:else}
      <span class="cd-badge cd-badge-warn">Review required</span>
    {/if}
  </div>

  {#if complianceDashboardStore.loading}
    <p class="cd-loading">Loading compliance status…</p>
  {:else if complianceDashboardStore.error && !complianceDashboardStore.bosAvailable}
    <div class="cd-unavailable">
      <p>BusinessOS is unavailable. Compliance data cannot be loaded.</p>
      <p class="cd-error-detail">{complianceDashboardStore.error}</p>
    </div>
  {:else}
    <!-- Overall Score -->
    <div class="cd-overall">
      <div class="cd-score-ring">
        <svg viewBox="0 0 64 64" aria-label="Overall compliance score">
          <circle cx="32" cy="32" r="27" fill="none" stroke="var(--border-default)" stroke-width="5" />
          {#if complianceDashboardStore.overallPercent != null}
            <circle
              cx="32" cy="32" r="27" fill="none"
              stroke={STATUS_COLOR[complianceDashboardStore.dashboardStatus?.status ?? 'unavailable']}
              stroke-width="5"
              stroke-dasharray="{(complianceDashboardStore.overallPercent / 100) * 169.6} 169.6"
              stroke-linecap="round"
              transform="rotate(-90 32 32)"
            />
          {/if}
          <text x="32" y="37" text-anchor="middle" font-size="14" font-weight="700" fill="var(--text-primary)">
            {complianceDashboardStore.overallPercent ?? '—'}
          </text>
        </svg>
      </div>
      <div class="cd-score-info">
        <span class="cd-score-label">Overall Score</span>
        <span class="cd-score-status"
          style="color: {STATUS_COLOR[complianceDashboardStore.dashboardStatus?.status ?? 'unavailable']}">
          {complianceDashboardStore.dashboardStatus?.status?.replace('_', ' ') ?? 'Unknown'}
        </span>
        {#if complianceDashboardStore.dashboardStatus?.last_checked_at}
          <span class="cd-checked-at">
            Last checked: {new Date(complianceDashboardStore.dashboardStatus.last_checked_at).toLocaleString()}
          </span>
        {/if}
      </div>
    </div>

    <!-- Framework Progress Bars -->
    {#if complianceDashboardStore.dashboardStatus?.frameworks?.length}
      <div class="cd-frameworks">
        <h2 class="cd-section-title">Frameworks</h2>
        {#each complianceDashboardStore.dashboardStatus.frameworks as fw (fw.framework)}
          {@const pct = fw.total > 0 ? Math.round((fw.passed / fw.total) * 100) : 0}
          <div class="cd-fw-row">
            <span class="cd-fw-name">{fw.framework}</span>
            <div class="cd-fw-bar-wrap">
              <div
                class="cd-fw-bar"
                style="width: {pct}%; background: {STATUS_COLOR[fw.status]}"
                role="progressbar"
                aria-valuenow={pct}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-label="{fw.framework} compliance: {pct}%"
              ></div>
            </div>
            <span class="cd-fw-pct" style="color: {STATUS_COLOR[fw.status]}">{pct}%</span>
            <span class="cd-fw-detail">{fw.passed}/{fw.total}</span>
          </div>
        {/each}
      </div>
    {/if}

    <!-- Critical Issues -->
    {#if complianceDashboardStore.criticalFrameworks.length > 0}
      <div class="cd-critical">
        <h2 class="cd-section-title cd-critical-title">Non-Compliant Frameworks</h2>
        <ul class="cd-critical-list">
          {#each complianceDashboardStore.criticalFrameworks as fw (fw.framework)}
            <li class="cd-critical-item">
              <span class="cd-critical-badge">{fw.framework}</span>
              <span class="cd-critical-detail">{fw.failed} control{fw.failed !== 1 ? 's' : ''} failing</span>
            </li>
          {/each}
        </ul>
      </div>
    {/if}
  {/if}
</div>

<style>
  .cd-dashboard {
    display: flex;
    flex-direction: column;
    gap: 24px;
    padding: 24px;
    max-width: 860px;
  }

  .cd-header {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .cd-title {
    font-size: 20px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .cd-badge {
    font-size: 11px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: 99px;
  }

  .cd-badge-compliant {
    background: rgba(34, 197, 94, 0.15);
    color: var(--accent-success, #22c55e);
  }

  .cd-badge-warn {
    background: rgba(245, 158, 11, 0.15);
    color: var(--accent-warning, #f59e0b);
  }

  .cd-badge-offline {
    background: rgba(239, 68, 68, 0.1);
    color: var(--accent-error, #ef4444);
  }

  .cd-loading,
  .cd-unavailable {
    color: var(--text-secondary);
    font-size: 13px;
  }

  .cd-error-detail {
    color: var(--accent-error, #ef4444);
    font-size: 12px;
    margin-top: 4px;
  }

  .cd-overall {
    display: flex;
    align-items: center;
    gap: 20px;
    background: var(--glass-bg);
    border: 1px solid var(--glass-border);
    border-radius: var(--radius-md);
    padding: 20px;
  }

  .cd-score-ring {
    width: 80px;
    height: 80px;
    flex-shrink: 0;
  }

  .cd-score-ring svg {
    width: 100%;
    height: 100%;
  }

  .cd-score-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .cd-score-label {
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-secondary);
  }

  .cd-score-status {
    font-size: 18px;
    font-weight: 700;
    text-transform: capitalize;
  }

  .cd-checked-at {
    font-size: 11px;
    color: var(--text-muted);
  }

  .cd-section-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 12px;
  }

  .cd-frameworks {
    background: var(--glass-bg);
    border: 1px solid var(--glass-border);
    border-radius: var(--radius-md);
    padding: 20px;
  }

  .cd-fw-row {
    display: grid;
    grid-template-columns: 80px 1fr 44px 48px;
    align-items: center;
    gap: 10px;
    margin-bottom: 10px;
  }

  .cd-fw-name {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .cd-fw-bar-wrap {
    height: 8px;
    background: var(--border-default);
    border-radius: 4px;
    overflow: hidden;
  }

  .cd-fw-bar {
    height: 100%;
    border-radius: 4px;
    transition: width 0.3s ease;
  }

  .cd-fw-pct {
    font-size: 12px;
    font-weight: 600;
    text-align: right;
  }

  .cd-fw-detail {
    font-size: 11px;
    color: var(--text-muted);
    text-align: right;
  }

  .cd-critical {
    background: rgba(239, 68, 68, 0.05);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: var(--radius-md);
    padding: 16px;
  }

  .cd-critical-title {
    color: var(--accent-error, #ef4444);
  }

  .cd-critical-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .cd-critical-item {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .cd-critical-badge {
    font-size: 11px;
    font-weight: 600;
    background: rgba(239, 68, 68, 0.15);
    color: var(--accent-error, #ef4444);
    padding: 2px 7px;
    border-radius: 99px;
  }

  .cd-critical-detail {
    font-size: 12px;
    color: var(--text-secondary);
  }
</style>
