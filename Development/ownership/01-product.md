# Role: Product Manager / Product Owner

## Core Identity

The Product Manager owns **why** and **what**. They are accountable for the product's business outcomes — not how the code is written or the system is architected. In healthy orgs, PMs and engineers are **peers in decision-making**, not a hierarchy.

At FAANG scale, PMs operate on 6–18 month roadmap horizons, coordinate across multiple engineering teams, and translate between user signals, business strategy, and engineering capacity.

---

## Primary Accountabilities

### 1. Product Strategy & Roadmap
- Define and own the product vision aligned to company strategy
- Prioritize the backlog using frameworks: RICE, ICE, MoSCoW, opportunity scoring
- Manage roadmap against OKRs and KPIs
- Say **no** to features that don't serve the strategy — this is as important as saying yes

### 2. Requirements & Discovery
- Conduct user research, A/B test analysis, customer interviews
- Write PRDs (Product Requirements Documents) — crisp, outcome-oriented, not solution-prescriptive
- Define acceptance criteria that engineers can unambiguously test
- Translate business requirements into epics and user stories

### 3. Stakeholder Management
- Represent the product to executives, sales, marketing, legal, and ops
- Manage conflicting priorities across teams and orgs
- Communicate roadmap changes and trade-offs upward and outward
- Align cross-functional partners before engineering starts (not during)

### 4. Metrics & Business Outcomes
- Define and own north star metric and supporting metrics per feature
- Run post-launch analysis: did the feature move the metric?
- Set experiment hypotheses and success criteria for A/B tests
- Own conversion funnels, retention curves, and activation rates

### 5. Go-to-Market Coordination
- Coordinate launch timing with marketing, sales, and support
- Define phased rollout strategy (internal → beta → GA)
- Write launch briefs and internal FAQs

---

## What PMs Do NOT Own

| Not PM's | Owned By |
|----------|----------|
| Technical architecture decisions | Principal/Staff Engineer |
| Sprint-level task estimation | Engineering team |
| Incident response | Operations / SRE |
| Deployment pipeline | DevOps / Platform |
| Code quality standards | Tech Lead / Senior Engineer |
| Team health and performance | Engineering Manager |

---

## PM Artifacts

| Artifact | Purpose |
|----------|---------|
| PRD | Requirements, acceptance criteria, non-goals |
| OKR | Quarterly outcomes the product must deliver |
| Roadmap | 6-18 month feature plan with priorities |
| A/B Test Brief | Hypothesis, metric, sample size, rollout % |
| Launch Plan | Coordination doc for GTM readiness |
| Post-Launch Analysis | Did we move the metric? What's next? |

---

## PM ↔ Principal Engineer Interface

The PM is the principal engineer's **closest partner** for:

- **Problem framing**: PMs bring "users can't find X"; principal engineers translate to "search index is stale because write path bypasses the indexer"
- **Build vs buy vs partner decisions**: PM owns the business case; Principal owns the technical feasibility and risk
- **Technical debt trade-offs**: Principal engineers must convince PMs why paying tech debt now prevents user-facing failures at scale — requires business language, not engineering jargon
- **Long-term vs short-term**: PMs are often quarter-pressured; principal engineers must defend long-term architectural choices with data

### When to Push Back on PM
A principal engineer should push back when:
1. A PRD is solution-prescriptive (PM says "add a Redis cache" instead of "reduce P99 latency to < 50ms")
2. Scope creep inflates technical risk without a commensurate business outcome increase
3. A feature requires architectural decisions that create irreversible constraints
4. The PM's success metric doesn't capture systemic risk (e.g., optimizing CTR while ignoring data pipeline reliability)

**How to push back**: Bring data, offer alternatives, never just say no. Frame as "to achieve your outcome, here's what changes and why."

---

## FAANG PM Nuances

### Amazon
- PMs write the "Working Backwards" doc — a press release + FAQ written *before* engineering starts
- Engineers review the PR/FAQ and challenge assumptions before a line of code is written
- PMs own the customer experience, engineers own the mechanism

### Google
- PMs are called PMs but engineers hold significant influence via design docs (TDDs/TDs)
- 20% rule historically allowed engineers to innovate outside PM direction
- Data is the authority — PMs and engineers both argue from experiment results

### Meta
- "Move fast and break things" historically made PMs aggressive on timeline; engineers had to self-advocate for quality
- Post-2020 Meta places stronger emphasis on PM-Eng joint accountability for integrity/safety signals

### Netflix
- Freedom + Responsibility: PMs have high autonomy but own outcomes completely
- Small teams (2-pizza) — PM-Eng ratio is roughly 1:8 to 1:12
- No traditional project managers; PMs + EMs share coordination work

---

## Common PM Anti-Patterns (That Engineers Must Navigate)

| Anti-Pattern | Impact | How Principal Engineers Respond |
|-------------|--------|--------------------------------|
| **Solution-prescriptive PRD** | Constrains architecture before problem is understood | Reframe PRD to problem statement; propose solution in design doc |
| **Scope creep mid-sprint** | Breaks delivery commitments, creates rework | Escalate to EM, document trade-off, require formal scope change |
| **Metric shopping** | Launches look successful but harm key health indicators | Propose composite metric; add counter-metrics to launch criteria |
| **Death march estimation** | Timeline set before engineering input | Require engineering to estimate first; surface risk with data |
| **Big bang launches** | Risk concentrated at one moment | Propose phased rollout with feature flags and kill switches |

---

## Interview Angles for Principal Engineers

**"Tell me about a time you disagreed with a PM on product direction."**
- Frame: PM wanted feature X; you surfaced that the architecture would create Y risk at Z scale
- Action: Proposed alternative that met the PM's business outcome with lower technical risk
- Result: Built consensus through data, not authority

**"How do you influence without authority when PM has competing priorities?"**
- Build a shared vocabulary around metrics the PM cares about
- Make the cost of inaction visible (not abstract — "this will cause 30% P99 degradation at 2x traffic")
- Offer a menu of options with trade-offs, let PM choose — you've already scoped the safe paths

**"How do you balance PM's roadmap pressure with technical debt?"**
- Quantify the debt in business terms: "we are shipping 40% slower because of X"
- Propose a deal: "give me 1 sprint of debt reduction; I'll give back 2 sprints of velocity"
- Show a trend — velocity charts declining over 3 quarters make the case better than abstract arguments
