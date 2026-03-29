<!-- src/routes/app/process-mining/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import ProcessMiningDashboard from '$lib/components/process-mining/ProcessMiningDashboard.svelte';
  import { processMiningStore } from '$lib/stores/process-mining.svelte';

  onMount(async () => {
    await Promise.all([
      processMiningStore.loadKPIs(),
      processMiningStore.loadStatus(),
    ]);
  });
</script>

<svelte:head>
  <title>Process Mining — Canopy</title>
</svelte:head>

<ProcessMiningDashboard />
