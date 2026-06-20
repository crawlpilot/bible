# Role: Tech Lead / Lead Engineer

## Core Identity

The Tech Lead (TL) owns **technical quality and direction within a team**. They are the senior-most technical voice for a specific team or project — not the whole org. The TL translates technical strategy into engineering decisions, makes day-to-day architecture calls, reviews code for quality, and mentors the team toward technical excellence.

The TL is different from the Principal Engineer: the TL is embedded in one team's execution; the Principal Engineer operates across multiple teams at a strategic level.

At FAANG, TL is often an individual contributor role at the Senior (L5) or Staff (L6) level who takes on tech leadership responsibilities either formally or informally.

---

## Primary Accountabilities

### 1. Technical Direction for the Team
- Own the technical vision for the team's domain — 1-2 year horizon
- Make or facilitate design decisions for all significant work on the team
- Ensure the team's technical choices are consistent with org-wide architecture
- Identify technical risks in the team's roadmap before they become incidents

### 2. Design Review & Sign-Off
- Review all significant design docs before implementation starts
- Facilitate design review meetings: challenge assumptions, surface alternatives
- Ensure designs account for: scale, failure modes, observability, security
- Be the voice of quality — reject designs that will create long-term debt without justification

### 3. Code Review Standards
- Set the code review bar for the team
- Review critical changes (hot paths, security-sensitive, data model changes)
- Build a culture where every engineer reviews, not just the TL
- Keep review turnaround < 24 hours to avoid blocking delivery

### 4. Technical Mentorship
- Be the go-to for engineers who are stuck on hard technical problems
- Run tech talks, architecture walkthroughs, and knowledge-sharing sessions
- Review code with junior engineers in pair-programming sessions
- Identify skill gaps in the team and drive learning plans

### 5. Cross-Team Technical Coordination
- Represent the team in cross-team technical discussions
- Negotiate API contracts and integration points with other teams
- Flag when the team's work is blocked by or dependent on another team's decisions
- Escalate to Principal Engineers when decisions exceed the team's scope

### 6. Technical Debt Management
- Maintain the team's technical debt backlog
- Prioritize debt reduction against feature work in sprint planning
- Propose and lead refactoring initiatives with clear ROI
- Prevent new debt: push back on shortcuts in design and code review

---

## Tech Lead vs Principal Engineer vs Senior Engineer

| Dimension | Tech Lead | Principal Engineer | Senior Engineer |
|-----------|-----------|-------------------|----------------|
| Scope | One team | Multiple teams / org | One team (deep contributor) |
| Horizon | 6-12 months (sprint to quarter) | 1-3 years (strategic) | Sprint to quarter |
| Design | All significant designs for team | Cross-team, org-wide architecture | Own component or service designs |
| Code Review | Sets bar, reviews critical paths | Reviews when strategic, not all PRs | Reviews peer PRs |
| Mentorship | Team-focused | Cross-team, multiplies TLs | Mentors junior engineers |
| Cross-functional | Represents team in meetings | Shapes PM/EM/Exec decisions | Consulted occasionally |
| Org influence | Team | Division or org | Team |

---

## The TL-M (Tech Lead Manager) Role

Some orgs combine TL + EM into one "Tech Lead Manager" (TLM). This is common at early-stage startups and some FAANG teams:

**Pros**: No coordination overhead between TL and EM; single owner of team direction

**Cons**:
- TLMs lose depth on both dimensions — mediocre manager AND mediocre technical leader
- People conversations require different brain than architecture conversations
- At > 6 engineers, TLM rarely works well
- FAANG preference: split the roles

**Principal Engineer stance**: Advocate for TL/EM split when team is > 4 engineers. The cost of poorly done people management (attrition, disengagement) exceeds the coordination cost of two roles.

---

## Tech Lead Artifacts

| Artifact | Purpose |
|----------|---------|
| Technical Design Docs | Significant feature and component designs |
| ADR (Architecture Decision Record) | Team-scope decisions with rationale |
| Code Review Guidelines | Team-specific standards and checklists |
| Tech Debt Backlog | Prioritized list of known tech debt with impact |
| Team Technical Roadmap | 6-12 month view of technical evolution |
| Runbook Library | Operational procedures for the team's services |
| Onboarding Technical Guide | How to set up and understand the team's systems |

---

## Design Doc Template (TL-Owned)

```markdown
# Design: [Feature/System Name]

## Problem Statement
One paragraph: what is broken or missing, and why it matters at scale.

## Requirements
- Functional: what the system must do
- Non-functional: latency, throughput, availability, consistency

## Out of Scope
Explicitly list what this design does NOT address.

## Proposed Design
- Architecture diagram (Mermaid)
- Component responsibilities
- Data model changes
- API contract changes

## Alternatives Considered
| Option | Pros | Cons | Why Rejected |

## Failure Modes
What breaks when each component fails? What's the recovery path?

## Rollout Plan
How does this ship safely? Feature flags? Canary? Rollback procedure?

## Open Questions
Questions that need resolution before or during implementation.
```

---

## TL ↔ Principal Engineer Interface

### When TL Escalates to Principal
- Design crosses team boundaries and will constrain other teams
- Architectural decision creates an org-wide precedent
- Technology choice conflicts with the org's platform strategy
- Technical risk is too large for one team to assess independently

### When Principal Consults TL
- Principal needs team-specific context for a cross-org design
- Principal is designing an API or platform that the team will consume
- Principal needs a realistic feasibility assessment from the team implementing it
- Principal is calibrating team technical bar for hiring or promotions

### When They Should Co-Author
- RFC documents that define how multiple teams interact
- Major platform migration plans (e.g., moving from Kafka to Kinesis)
- Service mesh or cross-cutting concern adoption

---

## TL Anti-Patterns

| Anti-Pattern | Symptom | Impact |
|-------------|---------|--------|
| **Heroic TL** | TL reviews all PRs, makes all decisions | Single point of failure; team doesn't grow |
| **Design by committee** | All engineers must agree on every decision | Slow, exhausting, no clear owner |
| **Ivory tower TL** | TL designs but never codes | Impractical designs; loses team respect |
| **Bottleneck reviews** | TL is the only reviewer; PRs sit for days | Delivery slows; team frustrated |
| **Technical purity over delivery** | Refactors everything; never ships | PM-Engineering trust breaks down |
| **Avoids conflict** | Lets bad designs through to preserve relationships | Debt accumulates; incident risk grows |
| **Hoards context** | Only TL understands the system | Bus factor 1; attrition is catastrophic |

---

## How to Grow Engineers as TL

### The 70-20-10 Learning Model
- **70%**: Learn by doing — challenging assignments slightly above comfort zone
- **20%**: Learn from others — code review feedback, pair programming, mentorship
- **10%**: Formal learning — books, courses, tech talks

### Stretch Assignments
Map each engineer's growth area to an upcoming piece of work:
| Engineer Level | Growth Area | Stretch Assignment |
|---------------|-------------|-------------------|
| Junior → Mid | Own a service end-to-end | Lead implementation of new microservice |
| Mid → Senior | System-level thinking | Own the design doc for a new feature |
| Senior → Staff | Cross-team influence | Lead integration with another team's API |

### Feedback Timing
- Immediate: small code review comments, in the moment
- Weekly: 1:1 with TL (TL often does this separate from EM 1:1)
- Quarterly: formal feedback input for performance cycle

---

## FAANG TL Patterns

### Google
- TL role is formal: designated TL per project in TVC (template)
- TLs write PRDs together with PMs in "Product + Engineering" pair
- TL is often the hiring committee member for the team

### Amazon
- Bar Raiser is separate from TL — TL runs the interview loop but isn't the Bar Raiser
- Single-threaded ownership: TL is often the "service owner" who is the technical DRI
- TL writes the technical narrative in the 6-page document for leadership review

### Meta
- TL at Meta is often called "Tech Lead" informally but is just a Senior/Staff Engineer taking on leadership
- Strong culture of "disagree and commit" — TL facilitates decision, team commits
- TL participates in "Technical Design Reviews" (TDR) — structured design review process

---

## Interview Angles for Principal Engineers

**"How do you empower a Tech Lead without undermining them?"**
- I set the stage — share the strategic context and constraints
- TL makes the design call within that context; I don't override their design without strong justification
- When I do disagree, I do it in the design review, not in a Slack side-channel
- I champion the TL's decisions upward — I'm their amplifier, not their auditor

**"What do you do when a Tech Lead proposes a design you think is wrong?"**
- I engage in the design doc, not in a 1:1 — transparency is a virtue
- I ask clarifying questions before stating disagreement: "Have you considered what happens at 10x traffic?"
- I present alternatives with explicit trade-offs — not just "this is wrong"
- If I override, I own it: "I'm making this call, here's my reasoning, TL had a valid alternative"

**"How do you identify that a team needs a Tech Lead they don't currently have?"**
- Symptoms: inconsistent code quality, engineers blocked on design questions, repeated architectural debt
- I help the EM identify who's ready for TL responsibilities
- I sponsor the candidate — help them build the skills and visibility
- I don't fill the TL void myself; I create the conditions for one to emerge
