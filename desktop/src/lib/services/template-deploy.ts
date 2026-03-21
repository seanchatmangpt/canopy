// src/lib/services/template-deploy.ts
// Template deployment pipeline: scaffolds .canopy/ workspace via Tauri IPC,
// loads agents from filesystem or bundled data, and registers them.

import type { CanopyAgent } from "$api/types";
import { workspaceStore } from "$lib/stores/workspace.svelte";
import { agentsStore } from "$lib/stores/agents.svelte";
import { isTauri } from "$lib/utils/platform";

export interface DeployResult {
  success: boolean;
  workspaceId: string | null;
  agentCount: number;
  error?: string;
}

/**
 * Deploy a template to a new workspace.
 *
 * Desktop (Tauri) flow:
 *   1. Load agent definitions from bundled TS module
 *   2. Call scaffold_canopy_dir IPC → creates .canopy/agents/*.md on disk
 *   3. Create workspace entry via API
 *   4. Set active workspace
 *   5. Register agents into store + mock layer + backend
 *
 * Web fallback:
 *   1. Load agent definitions from bundled TS module
 *   2. Create workspace entry via API
 *   3. Set active workspace
 *   4. Register agents into store + mock layer
 */
export async function deployTemplate(
  templateId: string,
  templateName: string,
): Promise<DeployResult> {
  try {
    // Step 1: Load agents from bundled template module
    const agents = await loadBundledTemplate(templateId);

    // Step 2: Create workspace (API + local storage)
    const ws = await workspaceStore.createWorkspace(templateName);
    if (!ws) throw new Error("Failed to create workspace");

    // Step 3: Scaffold .canopy/ directory on disk via Tauri IPC
    if (isTauri() && agents.length > 0) {
      try {
        const { invoke } = await import("@tauri-apps/api/core");
        await invoke("scaffold_canopy_dir", {
          path: ws.path,
          name: templateName,
          description: `${templateName} workspace deployed from template.`,
          agents: agents.map((a) => ({
            id: a.name,
            name: a.display_name || a.name,
            emoji: a.avatar_emoji || "🤖",
            role: a.role,
            adapter: a.adapter.replace(/_/g, "-"), // Rust expects hyphenated
            model: a.model || null,
            skills: a.skills || [],
            system_prompt: a.system_prompt || null,
          })),
        });
      } catch {
        // scaffold_canopy_dir failed — agents still loaded from bundled data
      }
    }

    // Step 4: Set active workspace (triggers fetchAgents, scanAndLoadAgents)
    await workspaceStore.setActiveWorkspace(ws.id);

    // Step 5: Register agents (store + mock layer + backend persistence)
    if (agents.length > 0) {
      await registerAgents(agents);
    }

    return {
      success: true,
      workspaceId: ws.id,
      agentCount: agents.length,
    };
  } catch (e) {
    return {
      success: false,
      workspaceId: null,
      agentCount: 0,
      error: (e as Error).message,
    };
  }
}

/**
 * Load bundled template agent definitions via dynamic import.
 * Each template ships a module at:
 *   src/lib/api/mock/library/templates/{templateId}.ts
 * that exports its agents as both `default` and named `agents`.
 */
async function loadBundledTemplate(templateId: string): Promise<CanopyAgent[]> {
  try {
    const modules = import.meta.glob<{
      default: CanopyAgent[];
      agents?: CanopyAgent[];
    }>("../api/mock/library/templates/*.ts");

    // Vite key format varies by version — match by suffix to be safe
    const suffix = `/${templateId}.ts`;
    const matchKey = Object.keys(modules).find((k) => k.endsWith(suffix));
    const loader = matchKey ? modules[matchKey] : undefined;
    if (!loader) return [];

    const mod = await loader();
    return mod.agents ?? mod.default ?? [];
  } catch {
    return [];
  }
}

/**
 * Register agents for immediate display and persistence.
 *
 * 1. Inject into Svelte store for instant UI
 * 2. Lock store so fetchAgents() can't overwrite during transition
 * 3. Persist in mock layer (survives mode switches)
 * 4. Persist to real backend if available
 */
async function registerAgents(agents: CanopyAgent[]): Promise<void> {
  // Inject into store immediately
  agentsStore.agents = agents;
  agentsStore.lockForDeployment();

  // Persist in mock layer + backend
  try {
    const {
      isMockEnabled,
      getActiveWorkspaceId,
      agents: agentsApi,
    } = await import("$api/client");
    const wsId = getActiveWorkspaceId();

    // Always store in mock layer as fallback
    if (wsId) {
      const { setMockWorkspaceAgents } = await import("$api/mock/index");
      setMockWorkspaceAgents(wsId, agents);
    }

    // Also persist to real backend if available
    if (!isMockEnabled() && wsId) {
      await Promise.allSettled(
        agents.map((agent) =>
          agentsApi.create({
            workspace_id: wsId,
            slug: agent.name,
            name: agent.display_name || agent.name,
            display_name: agent.display_name,
            avatar_emoji: agent.avatar_emoji,
            role: agent.role,
            adapter: agent.adapter,
            model: agent.model,
            system_prompt: agent.system_prompt,
            config: agent.config,
            skills: agent.skills,
          }),
        ),
      );
    }
  } catch {
    // Store injection is sufficient
  }
}
