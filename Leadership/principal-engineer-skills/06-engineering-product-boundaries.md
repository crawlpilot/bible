# Engineering vs Product Boundaries: Ownership, Conflict Resolution, and Communication

**Category:** Principal Engineer Skills · Cross-Functional Leadership · Engineering-Product Partnership  
**Framework:** WHAT vs HOW · DACI · Error Budget · Tech Debt Budget · Options-and-Trade-offs  
**Interview context:** "How do you work with your PM?" · "Describe a time eng and product disagreed." · "How do you handle roadmap conflicts?" · "Who owns technical decisions in your team?"

> "The PM owns the problem. The engineer owns the solution. The best partnerships happen when both sides understand that distinction — and respect where it blurs."

---

## Why This Matters at Principal Engineer Level

A senior engineer operates mostly inside engineering. They attend planning, take tickets, and occasionally push back on scope. A principal engineer operates at the seam between engineering and product. They are expected to:

- Translate business goals into technical constraints — and technical constraints into business language
- Hold the architectural line without being adversarial
- Negotiate timelines, headcount, and debt paydown at the roadmap level
- Own the engineering side of launch readiness, reliability, and quality — jointly with product, not in spite of product

FAANG interviewers at the PE level probe this boundary in every behavioural round. The question "tell me about a conflict with a PM" is really asking: *do you understand whose decisions are whose, can you hold your position under pressure, and can you do it without destroying the relationship?*

**Direct interview mapping:**

| Interview Question | Section |
|---|---|
| "How do you work with PMs on technical trade-offs?" | §2 (Ownership), §4 (DACI) |
| "How do you handle roadmap conflicts?" | §5b, §5c |
| "Tell me about a time you pushed back on a product decision" | §5a, §5d, §5e |
| "How do you manage tech debt vs feature velocity?" | §5a, §9 |
| "Who owns SLOs on your team?" | §8 |
| "How do you communicate architecture decisions to non-engineers?" | §6a, §6d |
| "How do you align on priorities across eng and product?" | §7, §11 |
| "Tell me about a time you influenced a decision you didn't control" | §4, §5e |

---

## Section 2 — Defining the Boundary: Who Owns What

### The Core Demarcation: WHAT vs HOW

The single most useful mental model for the eng/product boundary:

```
Product owns WHAT:  which problem to solve, for which users, by when, and how success is measured
Engineering owns HOW:  which technology, which architecture, which trade-offs to make in the solution space
```

This sounds simple. It breaks down constantly in practice because:
- Timeline is stated as WHAT ("ship by Q3") but is constrained by HOW ("Q3 is impossible given the current architecture")
- Quality is unstated WHAT (users expect it) but owned by HOW
- Build vs Buy is a WHAT (strategic capability) masquerading as a HOW (technical implementation)

The PE's job is to make these boundary blurs visible, not pretend they don't exist.

### The Ownership Matrix

| Decision | Hard Owner (final call) | Soft Owner (required input) | Common Misattribution |
|---|---|---|---|
| Which problem to solve | Product | Engineering | Eng sometimes self-assigns problems without PM buy-in |
| Product requirements | Product | Engineering (feasibility) | PM writes requirements without eng input on constraints |
| Architecture | Engineering | Product (timeline/cost impact) | PM overrides arch decision citing business urgency |
| Technology selection | Engineering | Product (strategic alignment) | PM mandates a vendor for business reasons without eng review |
| Timeline | Both | Both | PM announces dates without eng capacity input |
| Scope / MVP definition | Both | Both | Either side unilaterally expands or collapses scope |
| Quality bar / testing standards | Engineering | Product (risk appetite) | PM deprioritises testing tickets |
| SLO targets | Both | Both | Eng sets SLOs without PM input on customer expectations |
| Error budget drawdown | Product (when to spend) | Engineering (how much exists) | Eng freezes features without PM involvement |
| Incident escalation | Engineering (technical) | Product (user communication) | Eng runs incident without keeping PM informed |
| Build vs Buy | Both | Both | Eng decides to build without PM timeline buy-in |
| API contracts with partner teams | Engineering | Product (partner relationship) | PM agrees to integration without eng reviewing feasibility |
| Technical debt prioritisation | Engineering | Product (budget approval) | Eng asks for debt sprint without business framing |
| Feature flag / rollout strategy | Engineering | Product (user exposure plan) | PM sets rollout % without understanding blast radius |
| On-call rotation | Engineering | Product (on-call load awareness) | PM is unaware of on-call tax on engineering capacity |
| Hiring / headcount plan | Both (EM primarily) | Product (roadmap driving need) | Headcount requested without PM alignment on roadmap |
| Post-mortem action items | Engineering | Product (items affecting users) | Purely internal post-mortem; PM not informed |
| Success metrics / KPIs | Product | Engineering (technical feasibility of measurement) | Eng implements metrics PM never asked for |
| Data model | Engineering | Product (entity definitions must reflect domain) | Eng models data without PM validating the domain model |
| Security / compliance requirements | Engineering | Product (compliance is a product constraint) | Security debt deprioritised because PM didn't flag compliance risk |

### Hard vs Soft Ownership

**Hard ownership (decision rights):** You make the call. You can be overridden by escalation, but absent escalation the decision is yours.

**Soft ownership (input rights):** You must be consulted and your input must be genuinely considered. Your input doesn't guarantee the outcome, but a decision made without your input can be reversed.

**PE rule of thumb:** Protect your hard ownership aggressively. Never let PM make a HOW decision without engineering input, even when the pressure is high. Concede gracefully on soft-ownership disputes — that's not the hill to die on.

---

## Section 3 — Intra-Team Ownership Model

### DRI: Directly Responsible Individual

Popularised by Apple. The DRI is the single person accountable for an outcome — not a committee, not a team, not a shared responsibility. The DRI does not have to do all the work. They have to ensure it gets done.

**DRI assignment by domain:**

| Domain | DRI | Backup |
|---|---|---|
| Service reliability and on-call | Eng lead for the service | Team's SRE partner |
| Feature delivery for a sprint | Assigned engineer | Tech lead |
| Architecture decision | Principal engineer / tech lead | Staff engineer |
| External API contract | Tech lead | PM (for business terms) |
| Incident resolution | Incident commander (rotating) | Eng manager |
| Post-mortem publication | Incident DRI | EM |
| Roadmap item delivery | PM | EM |
| Technical debt items | Eng lead | Tech lead |

**The accountability rule:** if two people are listed as equally responsible for an outcome, nobody is responsible. When a deliverable slips, the DRI is the person the question lands with — not the team.

### Service Ownership Chain

```
CODEOWNERS file
    ↓ defines who reviews PRs
Team ownership (JIRA project, Slack channel, runbook)
    ↓ defines who is paged and who responds
Roadmap ownership (team backlog in planning tool)
    ↓ defines who prioritises the next feature or debt item
On-call rotation
    ↓ defines who is responsible when it breaks at 3am
```

Every service should have a clear answer to: "If this breaks at 3am and causes user impact, who do we call?" If the answer is "the team" — the ownership model is broken.

### The Tech Lead as Product Proxy

In the absence of a PM for technical decisions, the tech lead or PE holds the product context:
- They must know the user impact of every technical trade-off
- They translate technical risk into user outcomes ("if this database is under-indexed, search latency hits 5 seconds — that's a 30% session abandonment rate")
- They can make intra-sprint trade-offs that don't require PM involvement, within the agreed scope and quality bar

**When the PE speaks for product (appropriate):**
- Technical implementation details where the PM has delegated
- Intra-sprint scope decisions within agreed boundaries
- Trade-offs between technical approaches with equivalent user outcomes

**When the PE must not speak for product (inappropriate):**
- Changing the user-facing behaviour of a feature without PM sign-off
- Adjusting the timeline commitment without PM knowledge
- Deprioritising a PM-owned backlog item without PM approval

### Shared Ownership Anti-Patterns

| Anti-pattern | Symptom | Fix |
|---|---|---|
| Committee ownership | "The team owns this" — no individual name | Assign a DRI for every deliverable |
| Anyone can touch this | No CODEOWNERS, any team merges to any service | CODEOWNERS + required review enforcement |
| Diffuse accountability | Bug filed, all teams say "not ours" | Service map with explicit team tags |
| Inherited ownership | Service has no active owner; original team disbanded | Ownership handover process with a 30-day dual-ownership window |
| Temporary ownership | "We'll sort out ownership after launch" | Ownership must be assigned before the service goes to production |

---

## Section 4 — The DACI Framework for Cross-Functional Decisions

### DACI Roles

| Role | Definition | Who typically fills it |
|---|---|---|
| **D — Driver** | Owns the process: gathers input, drives to a decision, ensures it is documented and communicated | PE or tech lead for technical decisions; PM for product decisions |
| **A — Approver** | Has final decision authority; can veto | EM/Director for engineering; PM/GPM for product; joint for boundary decisions |
| **C — Contributor** | Must be consulted; their input is considered but not determinative | Adjacent team tech leads, SRE, Security, Data |
| **I — Informed** | Must be notified of the decision; no input required | Other stakeholders, dependent teams, leadership |

### Decision Type Taxonomy

Use reversibility and impact to decide how much process the decision needs:

```
                    HIGH IMPACT
                         │
  Irreversible           │           Irreversible
  Low Impact             │           High Impact
  (lightweight DACI)     │           (full DACI + RFC + exec sign-off)
  ─────────────────────────────────────────────────────
  Reversible             │           Reversible
  Low Impact             │           High Impact
  (delegate to DRI)      │           (lightweight DACI + ADR)
                         │
                    LOW IMPACT
```

**Examples:**

| Decision | Quadrant | Process |
|---|---|---|
| Rename an internal API endpoint | Reversible / Low | Delegate to DRI |
| Add a feature flag | Reversible / High | Lightweight DACI + ADR |
| Migrate from MySQL to Cassandra | Irreversible / High | Full DACI + RFC + exec sign-off |
| Deprecate an internal library | Irreversible / Low | Lightweight DACI + migration doc |

### Who Has Final Call

The most important DACI question is always: who is the Approver?

**PM is Approver for:**
- Which user problem to solve
- Which features ship in this quarter
- What the user experience of a feature is
- What success looks like (KPIs, metrics)

**Engineering (PE/EM) is Approver for:**
- How the solution is built
- Which technology is used
- What the architecture is
- What the quality bar is (test coverage, SLO targets)
- When it is safe to deploy

**Joint approval required for:**
- Timeline commitments (PM owns scope; Eng owns capacity)
- SLO targets (Eng proposes; PM accepts based on customer expectations)
- Build vs Buy (PM owns strategic direction; Eng owns technical feasibility)
- Major technical migrations that affect user-visible behaviour

### Escalation Triggers

Move from team-level DACI to leadership involvement when:
- The decision has been debated for > 2 planning cycles without resolution
- The disagreement is on fundamental values (speed vs quality), not facts
- The decision requires resources (headcount, budget) above the team's authority
- One party is blocking and will not commit to a trial/experiment

**Escalation framing (not "they won't listen"):**

> "We've evaluated three approaches. Eng prefers Option A for reliability reasons; PM prefers Option B for time-to-market. We're aligned that the right framing is: if we choose B, we accept [risk X] and will address it in Q3. We need leadership to make the call on which risk profile is acceptable."

This is a decision request, not a complaint.

---

## Section 5 — Conflict Resolution Strategies

### 5a. Feature Velocity vs Technical Debt

The most common and most persistent conflict at the eng/product boundary.

**The root cause:** PM's incentive is feature delivery (that's what they're measured on). Engineering's concern is system health (which nobody measures until it causes an incident). The system creates the conflict — it's not a people problem.

**The 20% Engineering Headroom Principle (Google/Spotify model):**

Reserve 20% of every sprint for engineering-initiated work: tech debt paydown, infrastructure improvements, tooling, and reliability. This is non-negotiable and is established at the team level agreement, not re-negotiated sprint by sprint.

How to establish it:
1. Make it explicit in the team's working agreement
2. Frame it as insurance: "20% now prevents a 100% halt when the system breaks"
3. Track what gets done with it — make the value visible to PM quarterly

**Framing tech debt in business language:**

| Engineering language | Business language |
|---|---|
| "High cyclomatic complexity" | "Takes 3x longer to add features to this area" |
| "No integration tests" | "Each deploy carries a 15% risk of regressions finding users" |
| "Database under-indexed" | "Search latency will hit 5s at 2x current user volume — that's Q2's projected load" |
| "Monolithic deployment" | "Every deploy is all-or-nothing: a bug in feature A forces a rollback of features B and C" |
| "No circuit breaker on payment gateway" | "When the gateway has a 5-minute outage, our checkout fails for the full outage duration instead of recovering in 30 seconds" |

**Tech Debt Triage:**

| Level | Definition | Timeline |
|---|---|---|
| Critical | Blocks the next milestone or is a live incident risk | Address immediately, with or without PM approval |
| High | Compounds interest: gets more expensive each sprint it's deferred | Include in next quarterly planning; negotiate budget |
| Medium | Increasing friction but not compounding | Batch with related feature work |
| Low | Cosmetic, low-impact | Document and schedule when convenient |

**Negotiating a Debt Sprint:**

Never ask for "a sprint to clean things up." Always present:
1. The specific debt items with business-language impact
2. The cost of not addressing them (risk, slower future velocity, incident probability)
3. The benefit of addressing them (what becomes faster, what risk is removed)
4. A concrete ask: "I need 2 engineer-sprints to resolve the top 3 critical items, which reduces our deploy rollback rate from 20% to ~2%."

---

### 5b. Timeline Conflicts

**The commitment trap — avoid it:**

The classic trap: PM announces a date to stakeholders. Eng says "we can't do it." Both are now defending positions, not solving a problem. The date is anchored; every conversation is about whether to miss it.

**The options-and-trade-offs pattern (before the date is announced):**

When PM brings a target date, respond with options, not a yes/no:

> "Here are three ways to approach Q3:
> - Option A: Ship all features as scoped. Requires 2 additional engineers or a 6-week slip.
> - Option B: Ship the MVP (features 1, 2, 3) by Q3. Features 4 and 5 ship in Q4.
> - Option C: Ship all features by Q3 with reduced reliability: no canary deployment, limited testing. I'd assign a 25% regression risk to this option."

This moves the conversation from "can we hit the date?" to "which trade-off do you want to make?" — which is a business decision, not an engineering constraint.

**The Iron Triangle: pick two**

```
         SCOPE
          / \
         /   \
      TIME — QUALITY
```

Every timeline negotiation is about which vertex is fixed and which is variable. Make this explicit:
- "We can fix scope and quality — timeline moves to Q4."
- "We can fix timeline and scope — quality drops; we accept regression risk."
- "We can fix timeline and quality — scope drops; we ship the MVP."

A PM who insists all three are fixed is not making a product decision — they're making a wish. Your job is to make the triangle visible.

---

### 5c. Prioritisation Conflicts

**When the PM backlog and engineering-identified work collide:**

Don't fight for space in the PM's backlog. Establish a parallel engineering backlog as a first-class planning artefact. In quarterly planning, both backlogs are reviewed; the final sprint plan draws from both within the agreed capacity split (e.g., 80% PM backlog / 20% eng backlog).

**The tech debt ticket format that PMs actually approve:**

```
Title:        Reduce payment service deploy risk
Priority:     P1 — Pre-Q3 (before next major launch)
Business Impact:  Current deploy failure rate: 18%. Each failure requires 
                  30-minute rollback. At Q3 launch scale (projected 5 deploys/week),
                  that's 2.7 hours/week of deploy-induced downtime.
Engineering Work:  Add blue-green deploy for payment service: 3 engineer-days.
Expected Outcome: Failure rate → ~2%. Zero-downtime deploys enabled.
Risk of Deferral: If deferred past Q3 launch, first major deploy failure 
                  will occur during peak traffic. MTTR estimate: 45-90 minutes.
```

A ticket written this way competes with feature tickets on equal terms. A ticket that says "refactor payment service deploy pipeline" does not.

**Reliability / SLO work as product work:**

SLO breaches are user experiences. An availability incident at 99.5% uptime means 4.4 hours of user-facing downtime per year. That is a product problem, not just an engineering problem.

Frame reliability work as: "Our current SLO is 99.9%. We're tracking at 99.7%. That's 2.6 hours of user-facing downtime per year we owe users. This migration removes the primary failure mode. It belongs in the product roadmap because it directly affects the user experience."

---

### 5d. Architecture Conflicts

**When PM wants a 3rd-party tool, eng wants to build:**

Neither preference is inherently right. Use the Build vs Buy framework (§10) to make the decision based on evidence, not preference. The PE's role is to drive the evaluation, not to win the argument.

**When business requirements are technically infeasible as stated:**

The wrong response: "We can't do that."
The right response: "As stated, that requirement would take 8 months. Here's why. Here's what we could build in Q3 that solves 80% of the problem: [alternative]. Is there something about the 20% that's non-negotiable, or can we shape the requirement?"

**The "no, but here's what we can do" formula:**

Every technical "no" should come with a concrete alternative. A standalone "no" from an engineer is an obstacle. A "no, but here's what we can do and when" is problem-solving.

Format:
1. Acknowledge what the PM is trying to achieve (user goal, business outcome)
2. State the constraint that makes the exact request infeasible
3. Offer the alternative that meets the goal within the constraint
4. Get confirmation that the alternative is acceptable

---

### 5e. Escalation Paths

**When to escalate vs when to absorb:**

Absorb if:
- The stakes are low and the cost of the conflict exceeds the cost of conceding
- You've been heard and can live with the outcome even if you disagree
- You're unsure enough that you might be wrong — "disagree and commit" applies

Escalate if:
- The decision carries serious technical risk that you've documented and been ignored
- The decision sets a precedent that will be hard to unwind
- There's a safety, security, or compliance concern
- You've exhausted team-level resolution after 2+ attempts

**How to escalate without burning the relationship:**

Wrong: "The PM won't listen to me, so I'm going to my director."

Right: "We've had a productive debate on this at the team level. We're genuinely aligned on the goal, but not on the approach. I think this decision warrants a broader perspective. Can we get 30 minutes with [EM + PM manager] to walk through the two options and get a call?"

Frame it as seeking input, not seeking a ruling. The shared goal is always the north star.

**The dual escalation:**

The cleanest escalation involves both the engineering manager AND the PM manager in the same conversation, with a pre-prepared trade-off document. This prevents the pattern where each manager hears only their side's framing and the conflict escalates further.

**Disagree and Commit:**

Once a decision is made through legitimate process (DACI, escalation, or consent), commit to it publicly and fully — even if you voted against it. Half-hearted execution of a decision you opposed is a worse outcome than the decision itself.

The PE who says "I still think this is wrong, but we decided to do it, so here's how we're doing it as well as possible" is more valuable than the PE who implements the decision poorly and is vindicated when it fails.

---

## Section 6 — Communication Practices, Channels, and Cadences

### 6a. Async Written Communication

**The Weekly Engineering Update:**

One paragraph, every Friday, shared with PM, EM, and any stakeholder. Format:

```
This week: [what shipped or was completed]
Next week: [what's planned]
Risks/Blockers: [anything that threatens next week's plan]
Decisions needed: [anything requiring PM or stakeholder input this week]
```

This eliminates the Monday "what did you do last week?" conversation and gives PM visibility without requiring a meeting.

**RFC Distribution:**

| Stage | Who gets notified | What they receive |
|---|---|---|
| Draft | Tech lead, adjacent eng teams | Full RFC; seeking technical input |
| Proposal | PM, EM, partner team leads | Executive summary + decision request |
| Approved | All stakeholders, dependent teams | Final decision + implementation timeline |
| Implemented | Full team, PM | ADR link; RFC closed |

**ADR as a Product Artefact:**

Every architecture decision record should have a non-technical summary at the top:

```markdown
## Non-Technical Summary (for PM/Stakeholders)
We are switching our cache layer from Redis to a managed AWS ElastiCache cluster.
Impact on product: none (invisible to users).
Impact on timeline: 2-day migration, no feature work disrupted.
Impact on cost: +$800/month; eliminates 4 hours/month of on-call overhead.
Reason: Redis self-management is consuming on-call capacity we need for feature work.
```

This gives PM enough context to ask informed questions without needing to understand distributed caching internals.

---

### 6b. Sync Ceremonies (Eng + Product Together)

**Sprint/Iteration Planning:**

- Input from both: PM brings prioritised backlog; Eng brings capacity and tech debt backlog
- Output: committed sprint scope with stated assumptions and risks
- Engineering must state — in the meeting, on the record — any risks to the committed scope. Not after the meeting, not in Slack, not in a comment on a ticket.

**Design Review:**

PM attends for requirement validation only:
- "Does this design solve the problem I described?"
- "Is there a user scenario I didn't account for?"

PM does NOT attend to approve technical approaches. If PM has concerns about a technical choice, they state the concern as a user or business concern ("this approach will make it hard to support X in the future") — not as a technical veto ("we should use Y instead").

**Pre-Mortem (before major launches):**

Joint session, 1 hour, 2-3 weeks before launch:
1. Assume the launch failed. Write down what went wrong.
2. Eng contributes: what could go wrong technically?
3. PM contributes: what could go wrong from a user or business perspective?
4. Prioritise the top 3 risks and assign owners.

This is the highest-leverage risk activity in the eng/product relationship. One hour before launch catches what months of planning misses.

**Post-Mortem:**

PM is always present. Two principles:
1. The post-mortem is a system analysis, not a blame assignment. "Engineering caused the outage" and "PM caused the outage" are both wrong framings. "Our deployment process lacked a circuit breaker that would have caught this before it affected users" is the right framing.
2. Action items are assigned to individuals, not to teams. The PM owns communication-process improvements; Eng owns technical process improvements.

**Quarterly Roadmap Review:**

- Technical constraints must appear on the roadmap slides alongside feature commitments
- Format: "Q3 roadmap: [Feature A, Feature B, Feature C] assuming [Platform migration completes by Q2, on-call load stays below 20% of sprint capacity]"
- If the assumption is violated, the roadmap revision is automatic — not a new negotiation

---

### 6c. Communication Anti-Patterns

| Anti-pattern | Why It Damages the Relationship | Fix |
|---|---|---|
| Presenting technical decisions as fait accompli | PM feels excluded from decisions that affect their product | Loop PM in at RFC draft stage, not announcement stage |
| Surprising PM with delays at sprint review | PM has been managing stakeholder expectations on a date that is now wrong | Surface risks at mid-sprint check-in, not end-of-sprint demo |
| Engineering-only incident comms | PM finds out about user impact from stakeholders before from the team | PM is looped in within 15 minutes of P1 declaration |
| Sync overload | Every question becomes a meeting; both sides resent the overhead | Default to async for information-sharing; sync only for decisions |
| Slack as a decision log | Decisions made in chat are lost, misremembered, and relitigated | Any decision with consequences gets a written summary, linked from the ticket |
| Technical jargon in cross-functional updates | PM can't explain eng constraints to their stakeholders | Every technical update has a one-sentence non-technical translation |
| Asymmetric information | Eng knows the full risk picture; PM knows only the committed date | Full risk register shared with PM at quarterly planning |

---

### 6d. Stakeholder Communication Matrix

| Stakeholder | Channel | Cadence | Content | Format |
|---|---|---|---|---|
| Direct PM partner | Slack DM + weekly sync | Daily async; weekly sync | Detailed status, blockers, decisions needed | Conversational |
| Group PM / Director PM | Email or doc | Bi-weekly | Milestone status, risks, asks | Bullet summary |
| Engineering Manager | Slack + 1:1 | Daily async; weekly 1:1 | Capacity, blockers, headcount needs | Conversational |
| Engineering Director | Written update | Weekly | Org-level risks, cross-team dependencies | 1-page doc |
| Partner team tech leads | RFC comments + Slack | Per RFC, per incident | Technical dependency changes, API changes | RFC / ADR |
| Executive stakeholders | Exec summary email | Monthly or per milestone | Business impact, key risks, what you need | 3-bullet max |

**Incident Communication to PM During an Active Incident:**

```
T+0:   Page goes out. PM notified via Slack: "P1 incident in payment service. 
       User impact: checkout failing for ~10% of users. Eng investigating."

T+15:  Update: "Root cause identified: config change in last deploy. Rollback 
       in progress. ETA to resolution: ~10 minutes."

T+30:  Update: "Resolved. All users restored. Post-mortem scheduled for Thursday."

Post:  PM receives draft post-mortem 48 hours later for review before publication.
```

PM should never find out about a P1 from a user, a stakeholder, or a dashboard. They should know from the team first.

---

## Section 7 — Planning Horizon Alignment

The deepest structural cause of eng/product friction is mismatched planning horizons.

### Time Horizons by Role

| Horizon | Engineering Concern | Product Concern |
|---|---|---|
| 2-3 years | Architecture direction, platform capability, major migrations | Company strategy, market positioning |
| 6-12 months | Platform investments, technical enablers, org structure | Annual roadmap, major feature bets |
| 3 months | Feature delivery, tech debt within sprint capacity | Quarterly OKRs |
| 2-4 weeks | Sprint execution, incidents, immediate blockers | Sprint delivery |
| Now | On-call, production issues | User-reported bugs |

### The Misalignment Failure Mode

PE spending all their time in the "now" and "2-4 weeks" horizon is a career stall and a team liability. It means architectural risks in the 6-12 month range are invisible until they become production problems.

### Injecting Technical Constraints into Quarterly Planning

The PE must show up at quarterly planning with a written technical constraint document:

```markdown
## Technical Constraints for Q3 Planning

### Hard Constraints (these will cause Q3 features to slip if not addressed)
1. DB capacity: At projected Q3 user load, read IOPS exceed current RDS capacity.
   Mitigation: Read replica + query optimisation (est. 3 eng-weeks, must complete by Week 4 of Q3).

2. Deployment frequency bottleneck: Current deploy pipeline supports max 2 deploys/day.
   Q3 roadmap requires 5 feature teams deploying independently.
   Mitigation: Split deploy pipeline by service (est. 2 eng-weeks, Q2 prerequisite).

### Platform Investments Required in Q3 (enabling Q4 roadmap)
1. Service mesh rollout: Required for Q4's multi-region expansion.
   Cost: 4 eng-weeks in Q3.

### Technical Debt Risk Register
1. Payment service: single-threaded request handling will fail at 3x current concurrency.
   Trigger: Projected to hit threshold in Q4 at current growth rate.
```

This document makes technical constraints a first-class input to product planning — not a post-hoc excuse for slippage.

---

## Section 8 — Reliability and SLO Ownership

### Who Sets SLOs

**Engineering proposes, PM accepts — jointly owned.**

The process:
1. Eng measures current reliability baseline (p99 latency, availability, error rate)
2. Eng proposes SLO targets based on what the system can currently sustain and what improvement is realistic
3. PM provides input: "our enterprise customers require 99.95% availability per contract"
4. Joint decision: SLO is set at the level that meets customer need within technical feasibility
5. If the target is above what the current system can support, the gap becomes a roadmap item

**SLOs must not be set unilaterally by either side:**
- Eng-only SLOs: may be achievable technically but misaligned with customer expectations or contractual obligations
- PM-only SLOs: may be the right customer promise but technically impossible without investment not yet planned

### Error Budget Ownership

```
Error Budget = 1 - SLO
Example: 99.9% availability SLO → 0.1% error budget → 43.8 minutes of downtime per month allowed

Engineering owns: how much budget exists and how much has been spent
Product owns: decisions about how to spend remaining budget
```

**Error budget decision matrix:**

| Budget Status | Feature Deployments | Explanation |
|---|---|---|
| >50% remaining | Green — normal deployment velocity | Risk headroom is sufficient |
| 25-50% remaining | Yellow — deploy with heightened review | Approaching constraint |
| <25% remaining | Orange — escalated review required; PM sign-off on each deploy | High risk; PM must be informed |
| Exhausted | Red — feature freeze; reliability work only | SLO is being violated; PM ownership required |

**Feature freeze is a joint decision:**

When the error budget is exhausted, the engineering team does not unilaterally freeze features. The PM is informed and a joint decision is made:
- Accept the feature freeze and invest in reliability
- Negotiate a revised SLO with stakeholders (if the SLO was aspirational)
- Accept the SLO breach and communicate it to affected customers (PM-owned communication)

### On-Call as a Product Concern

On-call load directly reduces engineering capacity for feature work. This must be visible to PM:

```
Sprint capacity model:
Total eng capacity: 10 engineer-sprints
On-call tax (last 4 weeks average): 1.5 engineer-sprints
Available for planned work: 8.5 engineer-sprints
Available for PM backlog: 6.8 engineer-sprints (80% of available)
Available for eng backlog: 1.7 engineer-sprints (20% of available)
```

If on-call load is increasing sprint over sprint, that is a product concern — it means less feature velocity per sprint. The PM has a direct interest in reliability investment.

---

## Section 9 — The Tech Debt Budget

### The 20% Rule

Reserve 20% of every sprint for engineering-owned work. This is not negotiable sprint by sprint — it is a team working agreement reviewed quarterly.

What belongs in the 20%:
- Tech debt paydown (from triage — critical and high items only unless cycle available)
- Infrastructure improvements (CI/CD speed, test reliability, observability)
- Tooling (developer experience improvements)
- Security patching and dependency upgrades
- Architecture runway (enabling work for next quarter's features)

What does NOT belong in the 20%:
- Feature work the PM deprioritised (put it in the PM backlog)
- Exploratory work with no clear connection to near-term goals
- "Rewrite X because I don't like how it was built"

### Communicating the Budget to PM

Establish it once, at team level, at the start of the quarter:

> "Our team's working agreement includes 20% eng headroom each sprint. This is not negotiable sprint by sprint — the PM decides how the other 80% is spent. Here's what we did with the 20% last quarter and what we plan for next quarter. This is what prevented [specific incidents or slowdowns]."

Track it visibly. Show PM what was accomplished with it. When PM sees that the 20% produced "reduced deploy time from 45 to 8 minutes, which enables your Q3 parallel-track delivery strategy" — they stop seeing it as overhead.

### Tech Debt Criteria: Feature vs Tech Health

| Work type | Counts as tech debt | Counts as feature |
|---|---|---|
| Fix a bug users reported | No | Yes (bug fix) |
| Fix a bug users haven't reported but will | Yes | No |
| Rewrite a service to improve performance | Yes | No |
| Add observability to a dark service | Yes | No |
| Build a new API endpoint | No | Yes |
| Refactor internal module for testability | Yes | No |
| Add integration tests for existing feature | Yes | No |
| Migrate to a new database (same functionality) | Yes | No |

---

## Section 10 — Build vs Buy: The Joint Decision Framework

### The Decision Test

Before evaluating any specific tool, answer these four questions:

| Question | Build Signal | Buy Signal |
|---|---|---|
| Does this capability differentiate our product? | Yes → build | No → buy |
| Do we have the expertise to build and maintain it? | Yes, available | No, or too expensive to acquire |
| Is vendor lock-in acceptable at this dependency level? | Lock-in is prohibitive | Lock-in is acceptable |
| What's the total cost of ownership over 3 years? | Build is competitive | Buy is significantly cheaper |

**The differentiation test is the most important.** Core business logic that is unique to your domain should almost always be built. Commodity capabilities (email sending, authentication, billing, storage, search) should almost always be bought.

### Total Cost of Ownership: Build vs Buy

**Build costs (often underestimated):**
- Initial development time (engineer-weeks)
- Ongoing maintenance (security patches, dependency updates)
- On-call burden (this is your system; you own its incidents)
- Feature parity with the vendor solution you didn't buy
- Team knowledge concentration (single expert becomes a bus factor)

**Buy costs (often underestimated):**
- Integration development time
- Migration cost if you switch vendors later (lock-in tax)
- Vendor support SLA gap vs your SLO requirement
- Data residency and compliance constraints
- Price increases over contract renewals

### Decision Ownership

| Phase | Owner | Action |
|---|---|---|
| Identify the need | PM | States the capability requirement |
| Evaluate options | PE/Tech lead | Produces build vs buy analysis |
| Recommend | PE | Recommends option with trade-off table |
| Decide | PM + PE jointly | Business + technical sign-off |
| Implement | Engineering | PE owns technical execution |

The anti-pattern: engineering builds a custom solution to a commodity problem because "we can do it better" — without PM buy-in on the time cost. The other anti-pattern: PM selects a vendor on a business trip and presents it to engineering as decided — without feasibility review.

---

## Section 11 — North Star Metrics Alignment

### DORA Metrics as Product Metrics

The four DORA metrics are engineering health indicators — but they are also product delivery indicators. PM should care about all four:

| DORA Metric | Engineering Reading | Product Reading |
|---|---|---|
| Deployment Frequency | How often we ship | How fast we can respond to user feedback |
| Lead Time for Changes | How long from code-complete to user | How quickly features reach users after build |
| Change Failure Rate | % of deploys causing incidents | % of releases that hurt users |
| MTTR | How fast we recover from incidents | How long users are affected when something breaks |

**Elite DORA performance (Google/Amazon benchmark):**
- Deploy frequency: multiple times per day
- Lead time: < 1 hour
- Change failure rate: 0-15%
- MTTR: < 1 hour

### The Shared Dashboard

Eng and PM should look at the same operational dashboard. When PM asks "how are we doing?" the answer should not require translating between an engineering metrics page and a product metrics page.

Shared dashboard minimum:
- Availability SLO current period vs target
- Error budget remaining (visual — like a fuel gauge)
- p99 latency current vs SLO target
- Deployment frequency (this week vs 4-week average)
- Open incident count by severity

### When to Push Back on a Metric

Not all metrics PM selects are good proxies for what they actually want to measure:

| PM asks for | What they actually want | Better metric |
|---|---|---|
| Lines of code shipped | Engineering throughput | Lead time for features |
| Number of bug tickets closed | Code quality improvement | Change failure rate |
| Number of PRs merged | Team productivity | Deployment frequency + feature cycle time |
| 100% test coverage | Reliability | Change failure rate + MTTR |

The PE's role: when asked to instrument or report on a proxy metric, raise the concern. "We can measure that. I want to flag that [this metric] can be gamed without improving the underlying outcome. The metric that better captures what you care about is [better metric]. Should we use both?"

---

## Section 12 — What PEs Commonly Miss

### The Influence Gap

The PE who is technically right but can't get PM to prioritise the work has an influence problem, not a technical problem. The most common failure mode: the PE presents the problem in engineering terms. The PM hears "engineering overhead." Nobody acts.

The fix: **reframe every engineering concern as a user or business outcome.** Not "our authentication service has no rate limiting" but "an attacker can brute-force any user account in under 60 seconds; our breach detection would take 4 hours to alert." The same fact, reframed as a risk the PM can explain to their VP, will get prioritised.

### The "Brilliant Jerk" Failure Mode

The PE who is always technically correct and whose presence in meetings engineers dread. They win the argument and lose the relationship. Every political capital withdrawal from a PM relationship is a tax on future influence.

**Signs you're drifting this direction:**
- PM starts excluding engineering from early-stage product discussions
- PM goes directly to EM to get "permission" to build something
- Other engineers tell you what the PM "really thinks" instead of the PM telling you directly
- You're rarely wrong about technical things; you're also rarely thanked

**The fix:** celebrate PM decisions that worked. Acknowledge when a product bet you were sceptical of paid off. Disagree in private and align in public. Credit the PM's problem identification, not just your solution.

### Attribution Matters

When a feature ships successfully: "The PM identified exactly the right user problem — that's why this landed well." When the architecture holds under load: "The team executed the reliability investment we made together." Shared wins produce shared investment in the relationship.

### The "Users Don't Care About That" Trap

The PM's most common counter to technical investment requests. Sometimes true. Often wrong.

**Counter-framework:**
- "Users don't care about test coverage" → True. Users care about whether their checkout breaks. Test coverage is how we ensure it doesn't.
- "Users don't care about our database" → True. Users care about page load time. The database is what makes page load time 200ms vs 4 seconds.
- "Users don't care about our CI pipeline" → True. Users care about whether their feature request shows up in two weeks or two months. The pipeline is what makes two weeks possible.

The translation: always one hop. "Users don't care about X. Users do care about Y. X is the engineering reason we can deliver Y."

### When to Let a Bad Decision Happen

Not every battle is worth fighting. A PE who relitigates every suboptimal decision loses standing to be heard on the ones that matter. The cost-benefit analysis:

**Fight hard:**
- Decisions with serious safety, security, or compliance implications
- Decisions that create technical debt that will cost significantly more than the current save
- Decisions that set a precedent making the next bad decision easier to make
- Decisions you'll be responsible for operating in production

**Let it go:**
- Styling/UX choices you disagree with
- Technology choices that are suboptimal but not harmful
- Prioritisation calls where you have a preference but not a strong technical opinion
- Decisions where you're uncertain enough that you might be wrong

### Write It Down Immediately

Every verbal agreement between eng and product decays at different rates in each person's memory. The PE who sends a Slack message after every conversation — "just confirming: we agreed to [decision], which means [implication], by [date]" — is not being bureaucratic. They're preventing the single most common source of eng/product conflict: misremembered agreements.

---

## SSTAR Interview Patterns

### Scenario 1: "Tell me about a time you pushed back on a product decision"

**Frame:**
- **S:** PM wanted to launch a new user-facing feature with no read replica, projecting 3x read load on primary DB post-launch
- **St:** Quantify the risk in user terms → negotiate a solution that doesn't miss the launch
- **T:** Own the technical constraint communication; propose an alternative
- **A:** Presented a risk document (not a verbal objection): "At 3x read load, p99 query latency hits 4.2 seconds; checkout abandonment rises ~35%. Read replica takes 3 engineer-days. We can still hit the launch date if we start Monday."
- **R:** PM approved the 3 engineer-days; launched on time; p99 stayed at 180ms under actual load

**PE calibration signal:** You quantified the user impact (not just the technical problem), offered a solution with a concrete timeline, and resolved the conflict without escalation.

---

### Scenario 2: "How do you manage technical debt alongside product delivery?"

**Frame:**
- **S:** Inherited a team where 100% of sprints went to features; on-call load had grown to 30% of capacity
- **St:** Establish a sustainable working agreement; make the debt visible in business terms
- **T:** Negotiate a 20% eng headroom agreement; build a debt triage system
- **A:** Created a debt impact register (each item with user/business consequence). Presented to PM: "At current on-call load, we're shipping at 70% effective capacity. Addressing the top 3 items restores us to 95%. I need 3 sprints and 20% headroom per sprint going forward."
- **R:** On-call load dropped from 30% to 8% over 2 quarters; effective delivery velocity increased 25%

**PE calibration signal:** You solved a systemic problem (the working agreement), not just a one-off debt item.

---

### Scenario 3: "Tell me about a time you had to say no to a PM and how you handled it"

**Frame:**
- **S:** PM committed to a customer that a new API integration would ship in 6 weeks; actual estimate was 14 weeks due to undocumented dependency on a legacy service
- **St:** Don't say "we can't do it." Say "here's the constraint; here's what we can do instead."
- **T:** Communicate the constraint early (Week 1, not Week 6); propose options
- **A:** Wrote a one-page options doc: (a) 14-week full integration, (b) 6-week webhook-based workaround with known limitations, (c) 8-week integration if one engineer is redeployed. PM chose option (b) for the customer's immediate need and roadmapped option (a) for Q3.
- **R:** Customer received a working (if limited) integration in 6 weeks; full integration shipped in Q3; PM relationship intact because the constraint was communicated in Week 1, not Week 5.

**PE calibration signal:** Early communication + options (not a binary yes/no) + preservation of the relationship = principal-level conflict resolution.

---

## Quick Reference: The Most Common Conflicts and the Right Move

| Conflict | Wrong Move | Right Move |
|---|---|---|
| PM announces a date without eng input | Agree and then miss it | Surface the constraint immediately with options |
| PM deprioritises tech debt | Accept it silently until incident | Frame as business risk; request budget in next planning |
| PM selects a vendor without eng review | Quietly implement a bad choice | Request a 1-week technical evaluation before commitment |
| Eng and PM disagree on priority | Argue without data | Quantify both options in business terms; request a decision |
| PM asks for features after SLO breach | Ship the features | Present error budget status; request joint decision on freeze |
| Timeline slips mid-sprint | Tell PM at sprint review | Surface at mid-sprint check-in with options |
| Incident occurs during PM's product launch | Manage it without telling PM | Notify PM within 15 minutes; include in post-mortem |
| PM sets SLOs without eng input | Accept infeasible targets | Request a joint SLO-setting session with current baseline data |
