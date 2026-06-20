# SSTAR: Leading an Org-Wide Monolith-to-Microservices Migration

**Category**: Leadership · Architecture · Technical Strategy · Principal Engineer Scope  
**Framework**: SSTAR (Situation → Strategy → Task → Action → Result)  
**Interview context**: "Tell me about a time you drove a large-scale architectural change" / "Describe a migration you led that affected multiple teams" / "How do you decompose a legacy system without halting product delivery?"

> At PE level, this question tests your ability to architect under constraints, align stakeholders across org boundaries, and de-risk a multi-year initiative without stopping the business.

---

## Why Migration Leadership is a PE-Level SSTAR

A migration SSTAR at PE scope demonstrates:
- **Architectural judgment**: you knew when NOT to migrate and shaped the scope accordingly
- **Risk management**: you designed a rollout that allowed rollback at every phase
- **Influence without authority**: you aligned product, infrastructure, and 6+ engineering teams without being their manager
- **Org-level change management**: you addressed the human side — training, ownership, on-call responsibilities
- **Systems thinking**: you built the platform that made the next migration faster for everyone

---

## SSTAR — Core Story: Order Management Decomposition

### S — Situation

*"At [Company], I was the Staff Engineer for our Commerce Platform — responsible for the backend services powering a $1.8B/year GMV e-commerce platform. Our primary system was a 7-year-old Java monolith: 2.1 million lines of code, 14 teams deploying into the same artifact, 3-hour CI builds, and weekly 'deploy freeze' periods because coordinating 14 teams on a single release was operationally unmanageable.*

*We were shipping features in 3–6 weeks that competitors shipped in days. Three separate teams had built their own shadow services outside the monolith because the monolith's release cycle was blocking them. We had divergent data models, no clear ownership, and a 40% engineer churn rate on the two teams most entangled with the core order management domain.*

*The VP of Engineering had approved a microservices initiative 2 years earlier that had spent $2M and delivered nothing deployable — the previous team had tried to boil the ocean and failed. There was deep organizational scepticism about whether a decomposition was achievable at all."*

---

### ST — Strategy

*"My strategy was explicitly not 'rewrite the monolith' — that's what the previous initiative had failed at. Instead, I proposed Strangler Fig: identify the highest-value seam, carve it out while leaving the monolith running, and prove the pattern once before scaling it.*

*I chose the Order Management Service (OMS) as the first extraction — not because it was the easiest, but because it had the clearest domain boundary (orders had one bounded context with well-defined events), the highest team demand (4 teams were blocked on OMS release cycles), and a product team sponsor who was willing to co-fund the initiative.*

*The second half of my strategy was to treat the infrastructure as a product: build the scaffolding, service template, deployment pipeline, and observability baseline once, then let each team own their own extraction. My role was to create the migration platform, not to perform every migration myself. If I did the migrations, we'd extract 3 services in 2 years. If I built the platform, teams would extract 20 services in the same window."*

---

### T — Task

*"My responsibility was: (1) define the domain decomposition strategy and identify the first extraction target, (2) architect the OMS extraction end-to-end including the strangler fig proxy layer and dual-write period, (3) build the service scaffolding and migration runbook that any team could follow, (4) align product, infrastructure, and security stakeholders on the migration plan, and (5) present the business case to the VP of Engineering and secure investment for a dedicated migration team."*

---

### A — Action

**Phase 1 — Domain mapping and stakeholder alignment (Weeks 1–6):**

*"I ran a 4-week event storming exercise across the monolith's 12 core domains. I invited not just engineers but product managers and QA leads — the domain model needed to reflect business events, not just technical artifacts. Output: a domain map showing 12 bounded contexts, 47 aggregates, and a heat map of coupling between domains.*

*I used the coupling heat map to disqualify the tempting candidates. Order Search felt easy to extract — it had a clear read model — but it was tightly coupled to the product catalog and inventory domain through 14 synchronous call chains. Extracting it first would have required touching 3 other domains simultaneously.*

*OMS had coupling through 8 call chains, but 6 of them were one-directional (callers reading order state) and could be replaced with event subscriptions. The remaining 2 were write paths — those needed the proxy layer.*

*I wrote and circulated an RFC: 'Order Management Service Extraction — Phase 1 Architecture.' I got 67 comments across 3 rounds. The security team flagged that the dual-write pattern needed audit log deduplication. The data platform team asked for event schema governance. Both concerns were valid — I incorporated them into the design and credited the reviewers publicly. That goodwill was important when I needed their cooperation during execution."*

**Phase 2 — OMS extraction (Weeks 7–24):**

*"I spent 2 weeks writing the strangler fig proxy layer — a routing middleware that intercepted all order writes in the monolith and replicated them to the new OMS in parallel, with the monolith as the source of truth during the dark launch period. Shadow reads ran against OMS for 6 weeks; we compared results against monolith reads and logged discrepancies.*

*At week 18, OMS was receiving 100% of production writes in shadow mode with a 0.003% discrepancy rate (all reconciled to clock skew in distributed transactions). I proposed the first traffic shift: 5% of order reads to OMS with a feature flag. We ran at 5% for 3 days, then moved to 25%, 50%, 100% over 2 weeks. At each threshold I reviewed latency, error rate, and discrepancy metrics before proceeding.*

*At week 24, OMS was fully live. We disabled the proxy layer and removed the monolith's order write path. The monolith lost 180,000 lines of code."*

**Phase 3 — Scaling the pattern (Weeks 25–52):**

*"The OMS extraction produced three artifacts I open-sourced internally: (1) a service scaffold with CI/CD, observability, and contract tests pre-wired, (2) a migration runbook covering domain mapping → RFC → dark launch → traffic shift → decommission, and (3) a migration office hours slot I held every Thursday.*

*I trained 4 engineering leads on the pattern. Within 6 months, 3 additional teams had independently started their own extractions using the scaffold. I reviewed their RFCs, attended their go/no-go reviews, and provided technical guidance — but they owned the work.*

*When the Inventory Service extraction hit a blocking issue — a circular dependency between inventory and pricing that neither team's owners had noticed during domain mapping — I facilitated a cross-team ADR session that defined a domain event contract as the resolution. That session became the template for how we resolve cross-domain coupling conflicts going forward."*

---

### R — Result

*"At the 12-month mark: 5 services extracted from the monolith, representing 340,000 lines of code. CI build time for the remaining monolith dropped from 3 hours to 1 hour 20 minutes (smaller artifact).*

*The teams who had extracted services reported feature delivery cycle time dropping from 3–6 weeks to 4–8 days. The OMS team went from 1 deploy per week to 12 deploys per week in the first month of independence.*

*Engineer attrition on the two highest-churn teams dropped from 40% to 12% over the following year. In exit interviews, the previous top reason for leaving had been 'inability to ship features independently' — that reason disappeared from exit interview data.*

*The migration platform (scaffold + runbook + RFC template) became the standard for new service creation across the org. Even teams not extracting from the monolith used it for greenfield services. It was officially adopted as the company's service template 8 months after I published it.*

*The VP of Engineering cited the OMS extraction in the company's engineering blog as the model for how to de-risk large-scale architectural change."*

---

## Coaching Notes — What Interviewers Are Looking For

| Dimension | PE-Level Signal | Mid-Level Signal |
|-----------|----------------|-----------------|
| **Scope selection** | Chose OMS for business value + domain clarity + coupling analysis — not ease | Chose "easiest service to extract first" |
| **Risk management** | Strangler fig + dark launch + 6-week shadow read + graduated traffic shifts | Big-bang cutover or prototype-only approach |
| **Leverage** | Built migration platform so 4 teams could independently execute | Personally performed every extraction |
| **RFC process** | 67 comments, incorporated security + data platform concerns | Wrote the doc, got 3 approvals, shipped it |
| **Org impact** | Attrition dropped; pattern adopted company-wide; cited in eng blog | Extracted 5 services successfully |

---

## Common Follow-up Questions

**"How did you decide what to extract first?"**
> "I used three criteria in priority order: coupling complexity (lower coupling = safer first extraction), team demand (who was most blocked by the monolith's release cycle), and product sponsorship (who would fund developer time). OMS scored highest on all three. I explicitly ruled out 'easiest to extract' as a criterion — easy doesn't build organizational confidence; demonstrably valuable does."

**"How did you handle the teams that didn't want to migrate?"**
> "I didn't push them. The migration was opt-in. My pitch was: here's what OMS shipping 12×/week looks like vs. your current 1×/week. Here's the scaffold that makes standing up your own service a 2-day task instead of a 3-month infrastructure project. The teams that were most blocked on shipping moved first. The teams with less pain moved later. Trying to mandate migration for teams who don't feel the pain creates compliance without commitment — the worst possible outcome for a migration that requires team ownership."

**"What did you do when the previous $2M initiative had failed?"**
> "The first thing I did was read the post-mortem from the previous initiative. The primary failure mode was scope: they tried to design the final-state microservices architecture before extracting anything. They spent 18 months in planning and never deployed to production. My response to organizational scepticism was: we're not going to plan the whole thing — we're going to extract one service in 24 weeks, measure it, and let the results decide whether to continue. I explicitly scoped the Phase 1 investment to prove the pattern, not to commit to the full migration."
