# Roadmap Fundamentals

## What a Technical Roadmap Is

A technical roadmap is a strategic plan that communicates:
- **What** work will be done (initiatives, not tasks)
- **Why** it matters (business or technical rationale)
- **When** (roughly — horizons, not exact dates)
- **In what order** (sequencing driven by dependencies and risk)
- **What trade-offs** were made (what is explicitly not on the roadmap)

It is the answer to: "Where is this platform/system/team going over the next 6–18 months, and how do you know that's the right direction?"

---

## Types of Technical Roadmaps

| Type | Owner | Audience | Horizon | Focus |
|------|-------|----------|---------|-------|
| **Product Roadmap** | PM + Principal Eng | Execs, customers | 6–18 months | Features, user outcomes |
| **Platform/Infra Roadmap** | Principal Eng / Staff | Engineering org | 6–18 months | Developer experience, reliability, scalability |
| **Migration Roadmap** | Principal Eng | Execs + affected teams | 3–24 months | System transitions, re-platforming |
| **Tech Debt Roadmap** | Principal Eng / TL | EM + Execs | 3–12 months | Risk reduction, maintainability |
| **Architecture Roadmap** | Principal Eng | Engineers + Architects | 12–36 months | System evolution, capability building |

Principal engineers typically own **platform, migration, tech debt, and architecture** roadmaps. They contribute heavily to product roadmaps (feasibility, sequencing, technical risk).

---

## The Three Horizons Model

Borrowed from McKinsey's Three Horizons framework, adapted for engineering:

```
HORIZON 1: Now (0–3 months)
  High confidence. Committed work. Teams are executing.
  Specific: named projects, owners, measurable outcomes.
  Accuracy expectation: ±20%

HORIZON 2: Next (3–9 months)
  Medium confidence. Planned but not yet designed.
  Approximate: initiative-level, not task-level.
  Accuracy expectation: ±50%

HORIZON 3: Later (9–18 months)
  Low confidence. Direction, not plans.
  Aspirational: problems to solve, capabilities to build.
  Accuracy expectation: ±100–200% (the cone of uncertainty)
```

**Key principle**: do NOT put H3 items on a timeline. They are strategic intent, not scheduled work. The moment you put a date on an 18-month item, stakeholders treat it as a commitment.

```
Roadmap visual:

│── H1 (Now) ──────│─── H2 (Next) ──────────│──── H3 (Later) ─────────│
│ High detail      │ Medium detail           │ Low detail               │
│ Committed        │ Probable                │ Aspirational             │
│                  │                         │                          │
│ ■■■ Kubernetes   │ ▒▒▒▒▒▒ Observability   │ ░░░░░░░░ Service Mesh   │
│ migration - batch│ platform                │ investigation            │
│ 1                │                         │                          │
│ ■■ CI/CD golden  │ ▒▒▒▒ Self-service      │ ░░░░░░ Cost attribution  │
│ path             │ secrets mgmt            │ system                   │
```

---

## Components of a Strong Technical Roadmap

### 1. Context and Problem Statement

Before listing initiatives, answer:
- What is the current state of the system/platform?
- What is failing or insufficient about it?
- What is the desired future state?
- What drives the urgency or priority?

**Example**:
> "Today, each of our 200 product teams manages their own deployment infrastructure. This results in 40+ different pipeline configurations, 8-hour mean deployment times, and 3 P1 incidents per week caused by pipeline misconfiguration. The goal over the next 18 months is to consolidate onto a golden-path platform that gives every team sub-15-minute deployments with zero infra expertise required."

This context makes every subsequent initiative legible — each one is clearly serving the stated goal.

### 2. Strategic Bets (Themes)

Group initiatives under 3–5 strategic themes. Themes make the roadmap scannable and explain the "why" for each cluster of work.

**Example themes for a platform team**:
- **Developer Velocity**: faster pipelines, self-service tools, golden paths
- **Reliability**: SLOs, automated rollback, chaos engineering
- **Security**: SBOM, secret scanning, zero-trust networking
- **Cost Efficiency**: resource rightsizing, shared infra, auto-scaling

Every initiative on the roadmap maps to one (primary) theme.

### 3. Initiatives, Not Tasks

Roadmaps live at initiative level — not sprint-level tasks.

```
Wrong level (too granular):
  - "Fix flaky test in payment service checkout suite"
  - "Update Kubernetes version from 1.28 to 1.30"
  - "Add retry logic to order processor"

Right level (initiative):
  - "Migrate all services to Kubernetes 1.30 (security + feature requirements)"
  - "Establish test reliability program: quarantine flaky tests, track flakiness rate"
  - "Implement resilience patterns (retry, circuit breaker) across tier-1 services"
```

### 4. Dependencies and Sequencing

A roadmap without explicit sequencing is a wishlist. Dependencies drive order.

```
Types of dependencies to surface:
  Technical: "Service mesh cannot be implemented until all services are on K8s"
  Team: "Self-service secrets requires Auth team to expose their Vault namespace API"
  External: "Data residency compliance required before EU rollout"
  Infrastructure: "Observability platform must exist before SLO monitoring is possible"

Representation:
  ── Kubernetes migration ──────────────────────────────►
                                  │
                                  └─── Service mesh (H3) — depends on K8s migration
  ── Observability platform ──────────────►
                                         │
                                         └─── SLO monitoring ── depends on obs platform
```

### 5. Resource Requirements

Each initiative needs an honest capacity estimate:

```
Initiative               | Teams Needed | Est. Duration | Headcount
─────────────────────────┼──────────────┼───────────────┼───────────
K8s migration (batch 1)  | Platform     | 3 months      | 4 eng
Golden path CI/CD        | Platform     | 2 months      | 3 eng
Self-service secrets      | Platform+Auth| 2 months      | 2+2 eng
Observability platform   | Platform+SRE | 4 months      | 3+2 eng
```

If the sum exceeds team capacity — that is the most important thing the roadmap communicates. Without this, roadmaps are wish lists.

### 6. Risks and Mitigations

A roadmap without risks is not credible. Name the top 3–5 risks upfront:

```
| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Product teams resist golden path migration | High | Delays H2 work | Incentive: teams on golden path get 10× faster pipelines |
| Auth team cannot staff self-service secrets in Q3 | Medium | Delays security initiative | Pre-engage in Q1; have fallback design without Auth |
| Kubernetes 1.30 upgrade breaks legacy services | Medium | Delays K8s migration | Compatibility test matrix; rollback plan per service |
```

### 7. What Is NOT on the Roadmap (and Why)

The most underrated section. Explicitly listing what was considered and deprioritized:
- Prevents re-opening debates at every planning cycle
- Shows rigor (you considered it, not ignored it)
- Sets expectations clearly

**Example**:
> "**Not on this roadmap**: Multi-cloud portability. Evaluated in H1 planning. Decision: AWS-only is sufficient for the next 18 months given our scale and team expertise. Will revisit in 2027 annual planning if AWS cost trajectory or vendor risk changes."

---

## Roadmap Formats

### Now / Next / Later (most common for product and platform)

```
NOW (Q1–Q2)                NEXT (Q3–Q4)              LATER (2027+)
────────────────────────   ──────────────────────     ──────────────────
■ K8s migration batch 1    ▒ K8s migration batch 2    ░ Service mesh
■ Golden path CI/CD v1     ▒ Self-service secrets      ░ Cost attribution
■ Alert noise reduction    ▒ SLO dashboard             ░ FinOps platform
■ Backstage launch         ▒ Canary delivery           ░ Multi-region HA
```

**Advantages**: fast to read, no false date precision, easy to update as priorities shift.
**Disadvantages**: no sequencing visible, no dependencies, no resource requirements.

### Timeline Roadmap (Gantt-style, for dependency-heavy migrations)

```
         Jan  Feb  Mar  Apr  May  Jun  Jul  Aug  Sep  Oct
K8s      [──batch 1──][──batch 2──][──────batch 3──────]
Backstage [──────────]
Obs.                  [──────────────────────]
SLO                                    [─────────────────]
Secrets              [────────]
Canary                              [────────────────────]
```

**Advantages**: shows parallelism, sequencing, dependencies, and rough duration clearly.
**Disadvantages**: false precision invites date commitments; expensive to maintain when priorities shift.

**Use Gantt for**: migration roadmaps, multi-team initiatives with hard dependencies, anything with a regulatory or launch date.
**Use Now/Next/Later for**: platform strategy, annual planning, anything exploratory.

### Outcome-Based Roadmap (for executive audiences)

Organized by business outcome, not initiative:

```
OUTCOME: Ship features 5× faster
  H1: Golden path CI/CD — reduces mean deploy time from 45 min to 10 min
  H2: Canary delivery — eliminates manual deploy approvals
  H3: Self-service environments — eliminates env provisioning bottleneck

OUTCOME: Achieve 99.9% platform reliability
  H1: Alert noise reduction — on-call burden from 11 pages/wk to 3
  H2: SLO dashboard + error budget gates — deploys blocked on budget burn
  H3: Chaos engineering program — proactive resilience validation
```

**Best for**: QBRs, board updates, executive strategy alignment. Engineers need the initiative view; executives need the outcome view.

---

## Roadmap Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Date-everything in H3 | Creates false commitments 12 months out | Use Now/Next/Later; add dates only to H1 |
| Initiative per team member | Roadmap becomes a task list | Stay at initiative level; teams own projects within initiatives |
| No "not doing" list | Every meeting reopens old debates | Always include explicit deprioritization decisions |
| Roadmap never updated | Goes stale; loses credibility | Quarterly review cycle minimum; ad-hoc updates when major context shifts |
| No resource math | Capacity overcommit by 2× | Always sum effort estimates against team capacity |
| Beautiful Gantt, no owner per initiative | Accountability diffuse | Every initiative has a named DRI (Directly Responsible Individual) |

---

## FAANG Interview Callouts

**Q: How do you build a technical roadmap when the product roadmap keeps changing?**

Decouple the technical roadmap from the product roadmap at the infrastructure layer. Product features come and go; the platform capabilities needed to deliver them have longer arcs.

Structure the technical roadmap around capabilities, not features:
- "We will have the observability stack to support any new product initiative" is a stable goal
- "We will build observability for Feature X" is a fragile goal that disappears when Feature X is deprioritized

The technical roadmap declares what foundational capabilities will exist by when. Product teams then build features on those capabilities. This makes the technical roadmap durable across product strategy changes.

**Q: Three VPs each think their initiative should be the top priority on your platform roadmap. How do you decide?**

Make the decision framework explicit before applying it:
1. What are the org-level OKRs this quarter? Which VP's initiative is most aligned?
2. Apply RICE scoring across all three initiatives using consistent inputs
3. Identify dependencies: does one initiative unlock the others? (It should go first)
4. Assess risk: which initiative has the highest cost of delay?

Present the scoring in a shared document with all three VPs present. The goal is for the decision to be made by the data, not by whoever argues loudest. If the ranking is still contested after scoring — that's an escalation for the common manager of all three VPs, not a political negotiation you should be stuck in.
