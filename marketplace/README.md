# Canopy Agent Marketplace

**The App Store for Autonomous Agent Skills**

> Publish skills. Earn revenue. Scale automation.

---

## Purpose

First agent marketplace with:
- **Per-execution pricing** via Stripe MPP
- **90% creator revenue share**
- **Signal Theory quality scoring** (S/N gates)
- **Budget enforcement** (no surprise bills)

---

## Quick Start

### Publish a Skill

```bash
canopy marketplace publish \
  --skill library/skills/development/test/SKILL.md \
  --price 0.05 \
  --category development
```

### Browse Marketplace

```bash
canopy marketplace list --category development
canopy marketplace get skill-id-here
canopy marketplace install skill-id-here --workspace my-workspace
```

### Track Revenue

```bash
canopy marketplace dashboard --creator chatmangpt
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CANOPY MARKETPLACE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Publisher Layer                    Consumer Layer              │
│  ┌──────────────┐                  ┌──────────────┐            │
│  | Upload       |                  | Browse       │            │
│  | Validate     |                  | Search       │            │
│  | Price        |                  | Install      │            │
│  └──────┬───────┘                  └──────┬───────┘            │
│         │                                 │                     │
│         ▼                                 ▼                     │
│  ┌──────────────┐                  ┌──────────────┐            │
│  | Quality Gate |                  | Budget Enforce│           │
│  | S/N scoring  |                  | Usage limits  │            │
│  | Security     |                  | Per-exec cost │            │
│  └──────┬───────┘                  └──────┬───────┘            │
│         │                                 │                     │
│         ▼                                 ▼                     │
│  ┌──────────────┐                  ┌──────────────┐            │
│  | Registry     |◄───────────────►│ Execution    │            │
│  | Skill index  │   Stripe MPP    | Auto-pay     │            │
│  | Versioning   │   Revenue share | Usage track  │            │
│  └──────────────┘                  └──────────────┘            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
canopy/marketplace/
├── README.md              (this file)
├── api/
│   ├── publish.go         (publish skill endpoint)
│   ├── list.go            (browse marketplace)
│   ├── install.go         (add skill to workspace)
│   └── billing.go         (Stripe MPP integration)
├── registry/
│   ├── skill.go           (skill metadata)
│   ├── version.go         (version management)
│   └── index.go           (search & discovery)
├── quality/
│   ├── signal_gate.go     (S/N scoring)
│   ├── security.go        (malicious pattern detection)
│   └── tests.go           (test validation)
└── publishers/
    ├── dashboard.go       (revenue analytics)
    ├── payout.go          (Stripe MPP payouts)
    └── stats.go           (usage metrics)
```

---

## Skill Metadata

Every published skill includes:

```yaml
---
name: test
version: 1.0.0
author: chatmangpt
author_id: pub-abc123
pricing:
  model: per_execution
  cost_usd: 0.05
  free_tier: 100
tier: specialist
tools_required: [file_read, file_write]
compliance: []
tags: [development, testing]
quality_score:
  s_n_ratio: 0.87
  rank: excellent
---
```

---

## Pricing Model

| Tier | Price Per Execution | Use Case |
|------|---------------------|----------|
| **Free** | $0 | Open source, community |
| **Professional** | $0.01–$1.00 | Specialized skills |
| **Enterprise** | $1.00–$10.00 | Premium capabilities |

**Revenue Share:**
- Creators: 90%
- Platform: 10%

---

## Quality Gates

### Signal Theory S/N Scoring

```go
type QualityScore struct {
    SNRatio    float64  // 0.0 to 1.0
    Rank       string   // "optimal", "good", "pass"
    Factors    struct {
        SuccessRate     float64
        UserSatisfaction float64
        ErrorRate       float64
        Efficiency      float64
    }
}
```

### Approval Thresholds

- **≥ 0.9 (OPTIMAL)**: Featured placement
- **≥ 0.7 (GOOD)**: Approved
- **< 0.7 (PASS)**: Return to publisher

---

## Stripe MPP Integration

### Payment Flow

```
1. Workspace subscribes to skill
2. Stripe MPP payment method authorized
3. Each execution: charge price_usd
4. Publisher receives: 90% real-time payout
5. Platform retains: 10% fee
```

### Configuration

```yaml
stripe_mpp:
  api_version: "2026-03-24"
  payment_method_types:
    - "usdc"
    - "usdc_balance"
  micro_debit:
    max_amount_usd: 10.0
    require_confirmation: false
  payouts:
    frequency: "daily"
    minimum_threshold: 10.0
```

---

## API Endpoints

### Publisher APIs

```
POST   /api/marketplace/publish
GET    /api/marketplace/my-skills
GET    /api/marketplace/revenue
GET    /api/marketplace/stats/{skill_id}
```

### Consumer APIs

```
GET    /api/marketplace/browse
GET    /api/marketplace/skills/{skill_id}
POST   /api/marketplace/install
GET    /api/marketplace/installed
```

---

## Success Metrics

| Metric | Target | Timeline |
|--------|--------|----------|
| Skills published | 200+ | 12 months |
| Active sellers | 50+ | 12 months |
| Monthly executions | 100K+ | 12 months |
| GMV | $50K/month | 18 months |
| Platform revenue | $5K/month | 18 months |

---

## Competitive Advantage

| Platform | Agent Commerce | Revenue Sharing | Quality Scoring |
|----------|---------------|-----------------|-----------------|
| LangChain Hub | ❌ No | N/A | GitHub stars |
| CrewAI Store | ❌ No | N/A | None |
| **Canopy Marketplace** | ✅ **Yes** | **90% creator** | **Signal Theory S/N** |

---

## References

- `/docs/superpowers/specs/2026-03-23-agent-marketplace-design.md` — Full design spec
- `/canopy/library/skills/` — Existing skill library
- Stripe MPP docs — https://stripe.com/docs/machine-payments

---

*Canopy Agent Marketplace — Phase 3 Implementation*
*Created: 2026-03-24*
