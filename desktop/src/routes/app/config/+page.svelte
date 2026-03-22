<!-- src/routes/app/config/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import PageShell from '$lib/components/layout/PageShell.svelte';
  import { toastStore } from '$lib/stores/toasts.svelte';
  import { settings as settingsApi } from '$api/client';

  type InstanceConfig = {
    default_model: string;
    max_concurrent_agents: number;
    session_timeout_minutes: number;
    log_level: string;
    telemetry_enabled: boolean;
    budget_enforcement: boolean;
    activity_retention_days: number;
  };

  let config = $state<InstanceConfig | null>(null);
  let loading = $state(true);
  let saving = $state(false);
  let error = $state<string | null>(null);
  let dirty = $state(false);

  const LOG_LEVELS = ['debug', 'info', 'warn', 'error'];
  const MODELS = [
    'claude-opus-4-6',
    'claude-sonnet-4-6',
    'claude-haiku-4-5-20251001',
  ];

  onMount(async () => {
    try {
      const res = await settingsApi.get();
      config = res as unknown as InstanceConfig;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  });

  function update<K extends keyof InstanceConfig>(key: K, value: InstanceConfig[K]) {
    if (!config) return;
    config = { ...config, [key]: value };
    dirty = true;
  }

  async function handleSave() {
    if (!config || !dirty) return;
    saving = true;
    try {
      await settingsApi.update(config as Record<string, unknown>);
      dirty = false;
      toastStore.success('Configuration saved');
    } catch (e) {
      toastStore.error('Failed to save', (e as Error).message);
    } finally {
      saving = false;
    }
  }
</script>

<PageShell title="Configuration" subtitle="Instance-wide settings">
  {#snippet actions()}
    <button
      class="cfg-save-btn"
      onclick={handleSave}
      disabled={!dirty || saving}
    >
      {saving ? 'Saving…' : 'Save Changes'}
    </button>
  {/snippet}

  {#if loading}
    <div class="cfg-loading">Loading configuration…</div>
  {:else if error}
    <div class="cfg-error" role="alert">Failed to load: {error}</div>
  {:else if config}
    <div class="cfg-grid">
      <section class="cfg-section">
        <h3 class="cfg-section-title">Model & Agents</h3>

        <label class="cfg-field">
          <span class="cfg-label">Default Model</span>
          <select
            class="cfg-select"
            value={config.default_model}
            onchange={(e) => update('default_model', e.currentTarget.value)}
          >
            {#each MODELS as model}
              <option value={model}>{model}</option>
            {/each}
          </select>
        </label>

        <label class="cfg-field">
          <span class="cfg-label">Max Concurrent Agents</span>
          <input
            class="cfg-input"
            type="number"
            min="1"
            max="100"
            value={config.max_concurrent_agents}
            onchange={(e) => update('max_concurrent_agents', parseInt(e.currentTarget.value) || 10)}
          />
        </label>

        <label class="cfg-field">
          <span class="cfg-label">Session Timeout (minutes)</span>
          <input
            class="cfg-input"
            type="number"
            min="5"
            max="1440"
            value={config.session_timeout_minutes}
            onchange={(e) => update('session_timeout_minutes', parseInt(e.currentTarget.value) || 60)}
          />
        </label>
      </section>

      <section class="cfg-section">
        <h3 class="cfg-section-title">Logging & Telemetry</h3>

        <label class="cfg-field">
          <span class="cfg-label">Log Level</span>
          <select
            class="cfg-select"
            value={config.log_level}
            onchange={(e) => update('log_level', e.currentTarget.value)}
          >
            {#each LOG_LEVELS as level}
              <option value={level}>{level}</option>
            {/each}
          </select>
        </label>

        <label class="cfg-field cfg-toggle-field">
          <span class="cfg-label">Telemetry Enabled</span>
          <button
            class="cfg-toggle"
            class:cfg-toggle-on={config.telemetry_enabled}
            role="switch"
            aria-checked={config.telemetry_enabled}
            onclick={() => update('telemetry_enabled', !config!.telemetry_enabled)}
          >
            <span class="cfg-toggle-thumb"></span>
          </button>
        </label>

        <label class="cfg-field">
          <span class="cfg-label">Activity Retention (days)</span>
          <input
            class="cfg-input"
            type="number"
            min="1"
            max="365"
            value={config.activity_retention_days}
            onchange={(e) => update('activity_retention_days', parseInt(e.currentTarget.value) || 30)}
          />
        </label>
      </section>

      <section class="cfg-section">
        <h3 class="cfg-section-title">Budget & Enforcement</h3>

        <label class="cfg-field cfg-toggle-field">
          <span class="cfg-label">Budget Enforcement</span>
          <button
            class="cfg-toggle"
            class:cfg-toggle-on={config.budget_enforcement}
            role="switch"
            aria-checked={config.budget_enforcement}
            onclick={() => update('budget_enforcement', !config!.budget_enforcement)}
          >
            <span class="cfg-toggle-thumb"></span>
          </button>
        </label>
        <p class="cfg-hint">When enabled, agents are paused when they exceed their budget limits.</p>
      </section>
    </div>

    {#if dirty}
      <div class="cfg-dirty-bar">
        Unsaved changes
        <button class="cfg-save-btn cfg-save-btn-bar" onclick={handleSave} disabled={saving}>
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
    {/if}
  {/if}
</PageShell>

<style>
  .cfg-loading, .cfg-error {
    display: flex; align-items: center; justify-content: center;
    min-height: 200px; font-size: 13px; color: var(--dt3);
  }
  .cfg-error { color: var(--danger, #ef4444); }

  .cfg-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: 24px;
    padding: 4px 0;
  }

  .cfg-section {
    background: var(--dbg2);
    border: 1px solid var(--dbd);
    border-radius: var(--radius-lg, 12px);
    padding: 20px;
    display: flex; flex-direction: column; gap: 16px;
  }

  .cfg-section-title {
    font-size: 13px; font-weight: 600; color: var(--dt2);
    margin: 0 0 4px 0; text-transform: uppercase; letter-spacing: 0.5px;
  }

  .cfg-field {
    display: flex; flex-direction: column; gap: 6px;
  }

  .cfg-toggle-field {
    flex-direction: row; align-items: center; justify-content: space-between;
  }

  .cfg-label {
    font-size: 12px; color: var(--dt3); font-weight: 500;
  }

  .cfg-input, .cfg-select {
    background: var(--dbg3);
    border: 1px solid var(--dbd);
    border-radius: var(--radius-md, 8px);
    padding: 8px 12px;
    font-size: 13px;
    color: var(--dt);
    outline: none;
    transition: border-color 0.15s;
  }
  .cfg-input:focus, .cfg-select:focus {
    border-color: var(--accent, #6366f1);
  }

  .cfg-toggle {
    width: 40px; height: 22px;
    border-radius: 11px;
    background: var(--dbg3);
    border: 1px solid var(--dbd);
    padding: 2px;
    cursor: pointer;
    position: relative;
    transition: background 0.2s;
  }
  .cfg-toggle-on {
    background: var(--accent, #6366f1);
    border-color: var(--accent, #6366f1);
  }
  .cfg-toggle-thumb {
    display: block;
    width: 16px; height: 16px;
    border-radius: 50%;
    background: white;
    transition: transform 0.2s;
  }
  .cfg-toggle-on .cfg-toggle-thumb {
    transform: translateX(18px);
  }

  .cfg-hint {
    font-size: 11px; color: var(--dt4); margin: -8px 0 0 0; line-height: 1.5;
  }

  .cfg-save-btn {
    padding: 6px 16px;
    border-radius: var(--radius-md, 8px);
    background: var(--accent, #6366f1);
    color: white;
    font-size: 12px; font-weight: 600;
    border: none; cursor: pointer;
    transition: opacity 0.15s;
  }
  .cfg-save-btn:disabled {
    opacity: 0.5; cursor: not-allowed;
  }

  .cfg-dirty-bar {
    position: fixed;
    bottom: 16px;
    left: 50%;
    transform: translateX(-50%);
    background: var(--dbg2);
    border: 1px solid var(--accent, #6366f1);
    border-radius: var(--radius-lg, 12px);
    padding: 8px 16px;
    display: flex; align-items: center; gap: 12px;
    font-size: 12px; color: var(--dt2);
    box-shadow: 0 4px 24px rgba(0, 0, 0, 0.4);
    z-index: 100;
  }
  .cfg-save-btn-bar {
    padding: 4px 12px;
  }
</style>
