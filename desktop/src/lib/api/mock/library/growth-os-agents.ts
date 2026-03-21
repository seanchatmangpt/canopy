// Growth OS agent definitions for deploy injection
import type { CanopyAgent } from "../../types";

const now = new Date().toISOString();
const zero = { input: 0, output: 0, cache_read: 0, cache_write: 0 } as const;

function agent(
  id: string,
  name: string,
  emoji: string,
  role: string,
  division: string,
  skills: string[] = [],
): CanopyAgent {
  return {
    id: `gro-${id}`,
    name: id,
    display_name: name,
    avatar_emoji: emoji,
    role,
    status: "idle",
    adapter: "claude_code",
    model: "claude-sonnet-4-20250514",
    system_prompt: `${name} — ${division} division agent for the Growth OS.`,
    config: { division },
    skills,
    schedule_id: null,
    budget_policy_id: null,
    current_task: null,
    last_active_at: now,
    token_usage_today: { ...zero },
    cost_today_cents: 0,
    created_at: now,
    updated_at: now,
  };
}

export const GROWTH_OS_AGENTS: CanopyAgent[] = [
  // ── Growth Director ──
  agent("growth-director", "Growth Director", "🧭", "orchestrator", "core", [
    "research",
    "define-niche",
    "build-icp",
    "design-offer",
    "extract-voice",
  ]),

  // ── Foundations ──
  agent("research", "Research Agent", "🔍", "analyst", "foundations", [
    "research",
  ]),
  agent(
    "niche-architect",
    "Niche Architect",
    "🎯",
    "strategist",
    "foundations",
    ["define-niche"],
  ),
  agent("icp-builder", "ICP Builder", "👤", "analyst", "foundations", [
    "build-icp",
  ]),
  agent(
    "offer-architect",
    "Offer Architect",
    "🏗️",
    "strategist",
    "foundations",
    ["design-offer"],
  ),
  agent(
    "brand-voice",
    "Brand Voice Extractor",
    "🎙️",
    "analyst",
    "foundations",
    ["extract-voice"],
  ),

  // ── Marketing ──
  agent(
    "content-strategist",
    "Content Strategist",
    "📅",
    "strategist",
    "marketing",
    ["content-calendar", "repurpose"],
  ),
  agent("youtube", "YouTube Agent", "🎬", "creator", "marketing", [
    "youtube-script",
  ]),
  agent("short-form", "Short-Form Agent", "📱", "creator", "marketing", [
    "short-form",
  ]),
  agent("stories", "Story Sequence Agent", "📸", "creator", "marketing", [
    "story-sequence",
  ]),
  agent("twitter", "Twitter/X Agent", "🐦", "creator", "marketing", [
    "twitter-thread",
  ]),
  agent("linkedin", "LinkedIn Agent", "💼", "creator", "marketing", [
    "linkedin-post",
  ]),
  agent("paid-ads", "Paid Ads Agent", "💰", "strategist", "marketing", [
    "ad-creative",
  ]),
  agent("seo-blog", "SEO/Blog Agent", "✍️", "creator", "marketing", [
    "blog-post",
  ]),
  agent(
    "marketing-assets",
    "Marketing Assets Agent",
    "🎨",
    "creator",
    "marketing",
    ["marketing-asset"],
  ),
  agent("podcast", "Podcast Agent", "🎙️", "creator", "marketing", [
    "podcast-outline",
  ]),

  // ── Nurture ──
  agent(
    "email-sequence",
    "Email Sequence Agent",
    "✉️",
    "architect",
    "nurture",
    ["email-sequence"],
  ),
  agent("lead-magnet", "Lead Magnet Agent", "🧲", "creator", "nurture", [
    "lead-magnet",
  ]),
  agent("community", "Community Agent", "🤝", "strategist", "nurture", [
    "community-content",
  ]),
  agent("webinar", "Webinar/Challenge Agent", "🎓", "architect", "nurture", [
    "webinar-script",
  ]),
  agent("sms", "SMS Agent", "💬", "creator", "nurture", ["sms-sequence"]),

  // ── Sales ──
  agent("vsl-builder", "VSL Builder", "🎥", "architect", "sales", [
    "build-vsl",
  ]),
  agent("funnel-assets", "Funnel Assets Agent", "🔄", "architect", "sales", [
    "build-funnel",
  ]),
  agent("sales-scripts", "Sales Script Agent", "📝", "architect", "sales", [
    "sales-script",
    "objections",
  ]),
  agent("dm-sales", "DM Sales Agent", "💬", "strategist", "sales", [
    "dm-sequence",
  ]),
  agent("call-prep", "Call Prep Agent", "📋", "analyst", "sales", [
    "call-prep",
  ]),
  agent("proposal", "Proposal Agent", "📑", "architect", "sales", ["proposal"]),
  agent("crm-automation", "CRM Automation Agent", "⚙️", "engineer", "sales", [
    "crm-update",
  ]),

  // ── Launch ──
  agent("launch-manager", "Launch Manager", "🚀", "strategist", "launch", [
    "plan-launch",
  ]),
  agent("post-launch", "Post-Launch Analyst", "📊", "analyst", "launch", [
    "launch-report",
  ]),

  // ── Scale ──
  agent("sop-builder", "SOP Builder", "📋", "architect", "scale", [
    "build-sop",
  ]),
  agent("team-builder", "Team Builder", "👥", "strategist", "scale", [
    "hiring-brief",
  ]),
  agent("competitor", "Competitor Agent", "🏆", "analyst", "scale", [
    "competitor-intel",
  ]),
  agent("financial", "Financial Agent", "💹", "analyst", "scale", [
    "revenue-report",
  ]),
  agent("retention", "Client Retention Agent", "❤️", "strategist", "scale", [
    "retention-check",
  ]),
  agent("case-study", "Case Study Agent", "📖", "creator", "scale", [
    "case-study",
  ]),
];
