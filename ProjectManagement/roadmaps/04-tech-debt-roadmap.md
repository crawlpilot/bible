# Tech Debt Roadmap — Making the Case and Executing

## The Core Problem

Technical debt is invisible to non-engineers until it causes an incident. Making the case for a tech debt roadmap requires translating invisible technical risk into visible business risk — in language executives act on.

"Our codebase has high cyclomatic complexity" gets dismissed.
"Our checkout service averages 3 incidents per month driven by a single 4,000-line class with no tests, costing $180K/year in engineer time and user trust" gets a budget.

---

## Classifying Tech Debt

Not all debt is equal. Prioritize by business impact, not technical purity.

### The Debt Taxonomy

| Type | Description | Example |
|------|-------------|---------|
| **Reliability Debt** | Code / architecture that causes or amplifies incidents | Single points of failure, no retry logic, shared mutable state |
| **Velocity Debt** | Slows feature development — every new feature requires 3× more work because of existing complexity | God classes, tangled dependencies, no tests |
| **Security Debt** | Known vulnerabilities, compliance gaps, attack surface | Outdated dependencies with CVEs, unencrypted data at rest, no secrets rotation |
| **Operational Debt** | Makes running the system harder — on-call burden, manual toil | No dashboards, manual deployments, cryptic error messages |
| **Architectural Debt** | System design that blocks scaling or creates cascading failures | Synchronous chains, no circuit breakers, shared mutable DB |

**Prioritization rule**: Reliability > Security > Velocity > Operational > Architectural.

Reliability and Security debt have the potential for immediate, severe business impact. Architectural debt compounds over years.

---

## Step 1: Audit and Quantify

A debt roadmap must start with data. Opinion-based debt prioritization becomes political; data-based prioritization is defensible.

### Technical audit

```bash
# Code quality signals (run these per service/module)

# 1. Cyclomatic complexity (Java: Checkstyle, JS: ESLint complexity rule)
checkstyle -c /google_checks.xml src/  

# 2. Test coverage
mvn jacoco:report
# Threshold: < 60% = high risk, 60–80% = medium, > 80% = good

# 3. Duplication rate
cpd --minimum-tokens 100 --files src/  # PMD Copy/Paste Detector

# 4. Dependency vulnerabilities
mvn dependency-check:check
# Surface: CVEs by severity (Critical/High/Medium)

# 5. Dead code
grep -r "TODO\|FIXME\|HACK\|DEPRECATED" src/ | wc -l  # quick signal
# Deeper: unused imports, dead code paths via IDE analysis

# 6. Package age
mvn versions:display-dependency-updates
```

### Business impact mapping

For each piece of identified debt, map to a business impact:

```
Debt Item: Payment service has no circuit breaker for downstream payment provider
  
Technical fact:   When payment provider is slow (latency > 2s), our service thread 
                  pool saturates in 30 seconds, causing full service unavailability
  
Business impact:  3 incidents in the last 6 months
                  Each incident: avg 45 min × $4K/min revenue impact = $180K
                  Total: ~$540K attributable to this single debt item
                  
Remediation cost: 2 engineers × 2 weeks = $25K
  
ROI: $540K saved / $25K invested = 21.6× ROI
     Payback period: < 1 month
```

This math is what gets a VP's attention. Run it for your top 10 debt items.

---

## Step 2: Build the Debt Register

A debt register is a living document that tracks all known debt items, their business impact, and their remediation status. It is the primary input to the tech debt roadmap.

### Debt Register Template

```markdown
| ID   | Debt Item | Type | Service | Business Impact | Incident Count (6m) | Remediation Cost | RICE Score | Status |
|------|-----------|------|---------|-----------------|---------------------|------------------|------------|--------|
| TD-01 | No circuit breaker on payment provider calls | Reliability | Payment | $540K/yr | 3 | 2 wks | 8,640 | Planned Q1 |
| TD-02 | Session token stored in plaintext in Redis | Security | Auth | P1 if exploited | 0 | 3 wks | 6,200 | Planned Q1 |
| TD-03 | OrderProcessor god class (4,200 lines, 12% coverage) | Velocity | Orders | 2× slower feature dev | 1 | 8 wks | 2,100 | Planned Q2 |
| TD-04 | Synchronous call chain: UI→API→Inventory→Pricing→Orders | Architectural | Multiple | Cascading failure risk | 2 | 16 wks | 950 | H2 |
| TD-05 | Dependency on Log4j 2.14.1 (CVE-2021-44228) | Security | Search | Critical CVE | 0 | 1 wk | Mandatory | URGENT |
| TD-06 | 45-min deploy pipeline (no caching) | Operational | All | $15M/yr lost dev time | 0 | 10 wks | 2,400 | Planned Q1 |
```

### RICE Score for Tech Debt

Apply RICE to debt items the same way you apply it to features:
- **Reach**: how many users or engineers are impacted?
- **Impact**: how severely does this affect reliability, velocity, or security?
- **Confidence**: how certain are we that fixing this solves the problem?
- **Effort**: person-weeks to remediate

Items with a "Mandatory" flag (active CVEs, compliance violations) bypass RICE — they must be fixed within the SLA regardless of score.

---

## Step 3: The Tech Debt Roadmap

### Annual structure: the 20% rule

Healthy debt management reserves a consistent percentage of engineering capacity for debt remediation each sprint.

**Industry norm**: 15–20% of sprint capacity for tech debt and engineering excellence.

**At FAANG**: Google and Amazon have formal programs — "20% time" historically at Google; Amazon has "two-pizza team engineering health" practice where teams track their debt ratio quarterly.

**How to frame 20% to product stakeholders**:
> "We're reserving 20% of sprint capacity for engineering health work. This is what keeps our feature delivery velocity sustainable — without it, we'll spend increasingly more time on incidents and workarounds. The alternative is to not reserve it, and watch our velocity decline 5% per quarter as debt compounds."

### Sample 12-month tech debt roadmap

```
THEME 1: RELIABILITY (Months 1–6)
Priority: highest — each item causes measurable revenue loss

  Q1:  TD-01 — Circuit breaker for payment provider        2 wks  ($540K/yr savings)
  Q1:  TD-02 — Session token encryption                    3 wks  (security compliance)
  Q1:  TD-06 — CI/CD pipeline optimization                10 wks  (velocity improvement)
  Q2:  TD-08 — Retry + timeout standards for all tier-1    4 wks  (resilience)
  Q2:  TD-09 — Eliminate synchronous call chain (async)    6 wks  (cascade failure risk)

THEME 2: SECURITY (Month 1 — ongoing)
Mandatory: CVE remediation is continuous, not scheduled

  Ongoing:   Critical CVEs: remediated within 72 hours (SLA)
  Ongoing:   High CVEs: remediated within 2 weeks (SLA)
  Q1:        Secrets rotation automation for production     3 wks
  Q2:        SBOM pipeline integration for all services     2 wks
  Q3:        Penetration test + remediation cycle           6 wks

THEME 3: VELOCITY (Months 4–9)
Focus: code quality improvements that compound over time

  Q2:  TD-03 — OrderProcessor decomposition (8 wks)
       Split into: OrderValidator, OrderPricer, OrderFulfiller, OrderNotifier
       Coverage target: 80% (from 12%)
  Q3:  Top 5 most-edited files — refactor + test
       (Pareto: 20% of files account for 80% of change friction)
  Q3:  Eliminate top 10 duplication clusters (DRY priority list from CPD)
  Q4:  Dependency upgrade sprint — all dependencies to latest stable

THEME 4: ARCHITECTURAL (Months 9–12)
Focus: structural changes that unlock future velocity

  Q3–Q4:  TD-04 — Async event-driven order pipeline (16 wks)
           Replace synchronous chain with Kafka event stream
           This is the highest-effort item; sequence after team has built async experience
  Q4:  Define service ownership boundaries (prep for potential decomposition)
```

---

## Communicating Tech Debt to Executives

### The "debt as business risk" frame

Never present tech debt as a technical problem. Always frame it as a business problem with a technical solution.

**Wrong framing** (gets dismissed):
> "Our codebase has accumulated significant technical debt over the past 4 years. We need to allocate time to refactoring or code quality will continue to decline."

**Right framing** (gets budget):
> "Our current payment and order infrastructure caused 6 P1 incidents last year, costing an estimated $1.1M in engineering time and customer impact. The root cause traces to three specific architecture decisions made in 2019 that we can remediate in one quarter. Not addressing these creates a 40% probability of a major incident in the next 6 months — based on our incident rate trajectory."

### The debt interest metaphor

Debt compounds like financial debt. Use this framing with non-technical stakeholders:

```
Year 1: $500K tech debt accumulated (feature shortcuts taken to hit launch)
Year 2: Debt "interest" — engineers spend 10% more time on maintenance
Year 3: "Interest" grows to 20% — 2 engineers effectively working full-time on maintenance
Year 4: "Interest" grows to 35% — velocity has declined 35% compared to Year 1
Year 5: Technical bankruptcy — more time on maintenance than features; 
        hiring engineers who quit due to poor code quality
        
Prevention cost (15% capacity reserved in Year 1–3): 
  ~$300K/year in "payments"
  
Remediation cost (Year 5):
  $2–4M for multi-year re-platform + lost engineer productivity + attrition
```

This is the curve that makes non-technical leaders act.

### One-page executive debt summary

```
TECHNICAL HEALTH REPORT — Q2 2026
Engineering Leadership | Confidential

HEADLINE: Critical reliability debt in payment and auth infrastructure 
          carries $1.1M/year in incident cost. Remediation plan: $220K, 
          Q1–Q2, payback period 2.5 months.

TOP 3 RISKS:
  1. Payment service: no circuit breaker [TD-01]
     Risk: full service outage when payment provider is slow
     Cost if unaddressed: $540K/year (based on 6-month incident history)
     Fix cost: $25K | Timeline: 2 weeks

  2. Auth service: plaintext session tokens in Redis [TD-02]
     Risk: session hijacking if Redis is compromised
     Cost if unaddressed: regulatory fine risk ($500K–$2M depending on scope)
     Fix cost: $35K | Timeline: 3 weeks

  3. Deploy pipeline: 48-minute mean duration [TD-06]
     Cost: 300 engineers × 2 hrs/day wait × $150/hr = $90K/day = $22M/yr
     (Even 50% reduction = $11M/year saved)
     Fix cost: $120K | Timeline: 10 weeks

INVESTMENT REQUESTED:
  Q1–Q2 debt remediation: 4 engineers × 12 weeks = $220K total
  Expected return: $1.1M/year in incident reduction + $11M/year velocity improvement
  12-month ROI: 55×
```

---

## Tech Debt Sprint Patterns

### Pattern 1: Continuous 20% reservation

Every sprint, 20% of capacity is reserved for debt items from the register. Debt is treated as a first-class citizen of the backlog alongside feature work.

**Pros**: consistent, sustainable, no "big bang" debt cleanup events
**Cons**: slow progress on large architectural debt items (need bigger blocks)

### Pattern 2: Dedicated debt sprints (quarterly)

One sprint per quarter is fully dedicated to tech debt. No new features.

**Pros**: allows larger, more cohesive refactors; team focus
**Cons**: product feels every quarter there's a "nothing ships" sprint; context switching cost

### Pattern 3: Alternating feature / engineering sprints

Alternate between feature sprints and engineering sprints (1:1 or 2:1 ratio).

**Pros**: predictable rhythm; engineers know when they'll get to improve things
**Cons**: may not match business urgency (can't pause features for 2 weeks when a launch is approaching)

**Recommendation**: use Pattern 1 as the baseline, Pattern 3 for critical debt that needs larger blocks. Reserve Pattern 2 (full engineering quarter) only for extreme situations — it is politically costly.

---

## FAANG Interview Callouts

**Q: Your team has been asked to ship 3 new features in Q1. You know the underlying service will break under load because of an architectural bottleneck. How do you handle this?**

Name the risk explicitly, quantify it, and force a decision:

"We can ship all 3 features in Q1. However, based on the load testing we ran last quarter, the order service's synchronous pricing call chain will saturate at ~3,000 concurrent users. Our Q1 growth projections suggest we'll hit that threshold in week 8 of Q2. I recommend we either:
A) Ship 2 features in Q1 and use the freed capacity to add the async queue before reaching the limit, or
B) Ship all 3 and plan a high-priority Q2 Week 1 engineering sprint for the fix — accepting the risk of a Q2 incident window

Which trade-off does the business want to make?"

This is a decision for the business, not engineering. Your job is to make the risk visible and quantified, then let the right people decide.

**Q: A new VP asks "why does it take 3 days to add a simple field to the checkout form?" How do you explain it and what do you commit to?**

Diagnose, explain, commit:
1. **Diagnose live** (not in the meeting): "Let me trace the actual path — code change → review → pipeline → staging → prod. I'll have specific numbers by tomorrow."

2. **Explain with data**: "The 3 days breaks down as: 4 hours engineering, 16 hours in PR review queue (one reviewer is a bottleneck), 36 hours pipeline (48-min pipeline × retries). The coding itself is trivial. The system around it is slow."

3. **Commit to specific improvement**: "In Q1, we're reducing the pipeline to < 12 minutes and establishing a review turnaround SLO of 4 hours. That reduces '3 days' to '4 hours' for this type of change. I'll show you the metrics at the end of Q1."

Never defend the current state. Explain it, own the improvement, and give a timeline.
