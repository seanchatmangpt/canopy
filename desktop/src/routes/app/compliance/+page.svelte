<!-- src/routes/app/compliance/+page.svelte -->
<script lang="ts">
  import { onMount } from 'svelte';
  import ComplianceDashboard from '$lib/components/compliance/ComplianceDashboard.svelte';
  import { complianceDashboardStore } from '$lib/stores/compliance-dashboard.svelte';

  onMount(() => {
    complianceDashboardStore.loadStatus();
  });
</script>

<svelte:head>
  <title>Compliance — Canopy</title>
</svelte:head>

<ComplianceDashboard />
