<!-- src/lib/components/process-mining/ProcessMiningDashboard.svelte -->
<script lang="ts">
  import { processMiningStore } from '$lib/stores/process-mining.svelte';
  import type { ProcessDiscoveryParams } from '$api/types';

  let logPath = $state('');
  let algorithm = $state<'alpha' | 'heuristics' | 'inductive'>('alpha');

  async function handleDiscover() {
    if (!logPath.trim()) return;
    const params: ProcessDiscoveryParams = { log_path: logPath, algorithm };
    await processMiningStore.runDiscovery(params);
  }
</script>

<div class="pm-dashboard">
  <!-- Header -->
  <div class="pm-header">
    <h1 class="pm-title">Process Mining</h1>
    {#if !processMiningStore.bosAvailable}
      <span class="pm-badge pm-badge-offline">BusinessOS offline</span>
    {:else}
      <span class="pm-badge pm-badge-online">BusinessOS connected</span>
    {/if}
  </div>

  <!-- KPI Cards -->
  <div class="pm-kpis">
    <!-- Cycle Time -->
    <div class="pm-kpi">
      <span class="pm-kpi-label">Avg Cycle Time</span>
      {#if processMiningStore.kpis?.avg_cycle_time_hours != null}
        <span class="pm-kpi-value">
          {processMiningStore.kpis.avg_cycle_time_hours.toFixed(1)}
          <span class="pm-kpi-unit">hrs</span>
        </span>
      {:else}
        <span class="pm-kpi-empty">—</span>
      {/if}
    </div>

    <!-- Conformance Score -->
    <div class="pm-kpi">
      <span class="pm-kpi-label">Conformance</span>
      {#if processMiningStore.conformancePercent != null}
        <span class="pm-kpi-value" class:pm-kpi-warn={processMiningStore.conformancePercent < 70}>
          {processMiningStore.conformancePercent}
          <span class="pm-kpi-unit">%</span>
        </span>
        <!-- Conformance ring (SVG) -->
        <svg class="pm-ring" viewBox="0 0 36 36" aria-hidden="true">
          <circle cx="18" cy="18" r="15.9" fill="none" stroke="var(--border-default)" stroke-width="2.5" />
          <circle
            cx="18" cy="18" r="15.9" fill="none"
            stroke={processMiningStore.conformancePercent >= 70 ? 'var(--accent-success)' : 'var(--accent-warning)'}
            stroke-width="2.5"
            stroke-dasharray="{(processMiningStore.conformancePercent / 100) * 100} 100"
            stroke-linecap="round"
            transform="rotate(-90 18 18)"
          />
        </svg>
      {:else}
        <span class="pm-kpi-empty">—</span>
      {/if}
    </div>

    <!-- Active Cases -->
    <div class="pm-kpi">
      <span class="pm-kpi-label">Active Cases</span>
      {#if processMiningStore.kpis?.active_cases != null}
        <span class="pm-kpi-value">
          {processMiningStore.kpis.active_cases.toLocaleString()}
        </span>
      {:else}
        <span class="pm-kpi-empty">—</span>
      {/if}
    </div>

    <!-- Bottleneck -->
    <div class="pm-kpi pm-kpi-wide">
      <span class="pm-kpi-label">Bottleneck Activity</span>
      {#if processMiningStore.kpis?.bottleneck_activity}
        <span class="pm-kpi-value pm-kpi-text">{processMiningStore.kpis.bottleneck_activity}</span>
      {:else}
        <span class="pm-kpi-empty">—</span>
      {/if}
    </div>
  </div>

  <!-- Discovery Panel -->
  <div class="pm-discovery">
    <h2 class="pm-section-title">Run Discovery</h2>
    <div class="pm-discovery-form">
      <input
        class="pm-input"
        type="text"
        placeholder="Event log path (e.g. /data/log.json)"
        bind:value={logPath}
        disabled={!processMiningStore.bosAvailable || processMiningStore.discovering}
      />
      <select class="pm-select" bind:value={algorithm} disabled={!processMiningStore.bosAvailable || processMiningStore.discovering}>
        <option value="alpha">Alpha Miner</option>
        <option value="heuristics">Heuristics Miner</option>
        <option value="inductive">Inductive Miner</option>
      </select>
      <button
        class="pm-btn"
        onclick={handleDiscover}
        disabled={!processMiningStore.bosAvailable || processMiningStore.discovering || !logPath.trim()}
      >
        {processMiningStore.discovering ? 'Discovering…' : 'Discover'}
      </button>
    </div>

    {#if processMiningStore.error}
      <p class="pm-error">{processMiningStore.error}</p>
    {/if}

    {#if processMiningStore.lastDiscovery}
      {@const d = processMiningStore.lastDiscovery}
      <div class="pm-result">
        <span class="pm-result-row"><strong>Model ID:</strong> {d.model_id}</span>
        <span class="pm-result-row"><strong>Algorithm:</strong> {d.algorithm}</span>
        <span class="pm-result-row"><strong>Places:</strong> {d.places} &middot; <strong>Transitions:</strong> {d.transitions} &middot; <strong>Arcs:</strong> {d.arcs}</span>
        <span class="pm-result-row"><strong>Latency:</strong> {d.latency_ms}ms</span>
      </div>
    {/if}
  </div>
</div>

<style>
  .pm-dashboard {
    display: flex;
    flex-direction: column;
    gap: 24px;
    padding: 24px;
    max-width: 900px;
  }

  .pm-header {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .pm-title {
    font-size: 20px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .pm-badge {
    font-size: 11px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: 99px;
  }

  .pm-badge-online {
    background: rgba(34, 197, 94, 0.15);
    color: var(--accent-success, #22c55e);
  }

  .pm-badge-offline {
    background: rgba(239, 68, 68, 0.1);
    color: var(--accent-error, #ef4444);
  }

  .pm-kpis {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 12px;
  }

  .pm-kpi {
    background: var(--glass-bg);
    border: 1px solid var(--glass-border);
    border-radius: var(--radius-md);
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 6px;
    position: relative;
  }

  .pm-kpi-wide {
    grid-column: span 2;
  }

  .pm-kpi-label {
    font-size: 11px;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .pm-kpi-value {
    font-size: 28px;
    font-weight: 700;
    color: var(--text-primary);
    line-height: 1;
  }

  .pm-kpi-unit {
    font-size: 14px;
    font-weight: 400;
    color: var(--text-secondary);
  }

  .pm-kpi-warn {
    color: var(--accent-warning, #f59e0b);
  }

  .pm-kpi-text {
    font-size: 16px;
    font-weight: 500;
  }

  .pm-kpi-empty {
    font-size: 24px;
    color: var(--text-muted);
  }

  .pm-ring {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 36px;
    height: 36px;
  }

  .pm-section-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 12px;
  }

  .pm-discovery {
    background: var(--glass-bg);
    border: 1px solid var(--glass-border);
    border-radius: var(--radius-md);
    padding: 20px;
  }

  .pm-discovery-form {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }

  .pm-input {
    flex: 1;
    min-width: 200px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    padding: 7px 10px;
    font-size: 13px;
    color: var(--text-primary);
    outline: none;
  }

  .pm-input:focus {
    border-color: var(--accent-primary);
  }

  .pm-select {
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    padding: 7px 10px;
    font-size: 13px;
    color: var(--text-primary);
    outline: none;
  }

  .pm-btn {
    background: var(--accent-primary);
    color: white;
    border: none;
    border-radius: var(--radius-sm);
    padding: 7px 16px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    white-space: nowrap;
  }

  .pm-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .pm-error {
    margin: 10px 0 0;
    font-size: 12px;
    color: var(--accent-error, #ef4444);
  }

  .pm-result {
    margin-top: 14px;
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-sm);
    padding: 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .pm-result-row {
    font-size: 12px;
    color: var(--text-secondary);
  }
</style>
