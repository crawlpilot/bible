# DORA Metrics — Purpose, Usage, and Engineering Practices

## What DORA Is

DORA (DevOps Research and Assessment) is a research program started by Dr. Nicole Forsgren, Jez Humble, and Gene Kim. The research ran for 6+ years, surveyed 32,000+ professionals across 2,000+ organizations, and produced the landmark book *Accelerate* (2018).

**The core finding**: four metrics reliably predict both software delivery performance and organizational outcomes (revenue growth, market share, employee satisfaction). These four metrics are now the industry standard for measuring engineering effectiveness.

**Why it matters for principal engineers**: DORA metrics give you the language and data to make the case for engineering investments to non-technical leadership. "We need to reduce deployment friction" is an opinion. "Our lead time is 3 weeks vs. the industry elite of < 1 hour, which means we ship 50× fewer features per quarter" is a business case.

---

## The Four DORA Metrics

### 1. Deployment Frequency (DF)

**What it measures**: How often does your organization successfully release to production?

**Why it matters**: High frequency means small batches. Small batches mean smaller blast radius per deploy, faster feedback from users, and less risk per release. Low frequency is a symptom of pain — merges are scary, deploys are events, rollback is manual.

**Performance bands**:

| Band | Frequency | Typical profile |
|------|-----------|-----------------|
| Elite | On-demand (multiple deploys/day) | FAANG, mature cloud-native |
| High | Between once per week and once per month | Mid-size tech companies |
| Medium | Between once per month and once every 6 months | Enterprise with some modernization |
| Low | Fewer than once every 6 months | Legacy, heavyweight release processes |

**What drives low DF**:
- Long-lived feature branches (merge conflicts pile up)
- Manual testing required before deploy
- Release requires multiple team coordination
- Deploy = downtime (no zero-downtime mechanism)
- Fear of deploying — historically painful deploys

**What elite DF looks like (Amazon)**: Amazon deploys to production every 11.6 seconds on average across all services. Each of their ~3,000 microservices deploys independently. The 2-pizza team model directly enables this — no inter-team release coordination required.

---

### 2. Lead Time for Changes (LT)

**What it measures**: The time from a code commit to that code running in production.

```
Developer commits code
         │
         ▼
Code review + approval           ← often the biggest hidden delay
         │
         ▼
CI pipeline runs (build, test)
         │
         ▼
Deployed to staging
         │
         ▼
Acceptance testing
         │
         ▼
Deployed to production           ← clock stops here
```

**Performance bands**:

| Band | Lead Time |
|------|-----------|
| Elite | Less than 1 hour |
| High | Between 1 day and 1 week |
| Medium | Between 1 week and 1 month |
| Low | More than 6 months |

**What drives long lead time**:
- Slow code review cycles (PR sits waiting for 2 days)
- Manual QA / sign-off steps
- Nightly test runs instead of per-commit
- Environment provisioning delays (waiting 3 days for a staging environment)
- Change Advisory Board (CAB) approvals required for every deploy

**What elite LT looks like (Google)**: Google's Continuous Integration system runs hundreds of thousands of tests per day across its monorepo. Engineers get test results within minutes. Code review (Critique) is fast-paced — reviewers are expected to respond within a business day. Lead time for small changes: < 1 hour from commit to prod.

**The hidden component — review time**: In most organizations, 60–80% of lead time is a PR sitting in a queue, not pipeline execution. Fixing pipeline speed from 40 minutes to 20 minutes is much less impactful than cutting review turnaround from 48 hours to 4 hours.

---

### 3. Change Failure Rate (CFR)

**What it measures**: The percentage of deployments to production that result in a degraded service requiring remediation (hotfix, rollback, patch forward).

```
CFR = (deployments causing incidents) / (total deployments) × 100
```

**Performance bands**:

| Band | Change Failure Rate |
|------|---------------------|
| Elite | 0–5% |
| High | 5–10% |
| Medium | 10–15% |
| Low | > 15% |

**Important nuance**: elite organizations deploy more frequently AND have lower failure rates. High frequency does not cause high failure rate — it's the opposite. Small, frequent batches are lower risk than large, infrequent deploys.

**What drives high CFR**:
- Large deployment batches (accumulate risk)
- Poor test coverage (regression goes undetected)
- No canary/progressive delivery (full blast radius on every deploy)
- Insufficient staging environment (doesn't replicate prod load/config)
- Manual, inconsistent deployment process

**What elite CFR looks like (Netflix)**: Netflix's deployment system (Spinnaker + Kayenta) catches regressions automatically during canary analysis before they affect 100% of traffic. Their CFR is < 1% — not because their engineers are infallible, but because the system catches errors at 5% traffic before they become incidents.

---

### 4. Mean Time to Recovery (MTTR)

**What it measures**: How long it takes to restore service after a production incident (from first alert to full recovery).

**Performance bands**:

| Band | MTTR |
|------|------|
| Elite | Less than 1 hour |
| High | Less than 1 day |
| Medium | Between 1 day and 1 week |
| Low | More than 1 week |

**What drives long MTTR**:
- Alert fires but nobody notices (alert fatigue, missing on-call rotation)
- Slow diagnosis — no observability, no distributed tracing
- Slow rollback — no rollback mechanism, must "fix forward"
- Manual deployment of fix — same slow pipeline as feature work
- Approval required to roll back

**What elite MTTR looks like (Amazon, Meta)**: Automated rollback triggered by CloudWatch alarms / SLO violation — no human in the loop for the rollback decision. Detection-to-rollback under 5 minutes. Most MTTR is now "time to detect" not "time to fix."

---

## The DORA Relationships: Why These Four Together

The four metrics form two complementary pairs:

```
Throughput metrics (how fast you move):
  Deployment Frequency  +  Lead Time for Changes

Stability metrics (how reliable you are):
  Change Failure Rate  +  MTTR
```

**The key insight**: high-performing organizations score well on ALL FOUR simultaneously. There is no throughput-vs-stability trade-off at scale. The research disproves the common belief that "moving fast breaks things."

```
Common belief:         Fast ←──── trade-off ────→ Stable
DORA finding:          Fast ──────── and ─────────→ Stable (at elite level)
```

Why? Because the practices that enable high frequency (small batches, automated testing, feature flags, canary deploys) are the same practices that improve stability.

---

## How FAANG Companies Use DORA

### Amazon

**Organizational design around DORA**: The 2-pizza team model (6–10 engineers) with "you build it, you run it" ownership directly optimizes for Deployment Frequency and MTTR.

- **DF**: Each team deploys independently. No cross-team release coordination. Deployments every 11.6 seconds org-wide.
- **LT**: Service ownership means the team that writes the code also runs the pipeline. No handoff = no wait time.
- **CFR**: Automated canary (CodeDeploy traffic shifting) + CloudWatch alarm rollback. Small blast radius per deploy.
- **MTTR**: Each team owns their on-call rotation. The team that built it knows how to fix it fastest.

**Amazon's internal metric**: "Deployment frequency per team" is a leadership KPI. Teams with DF < daily are flagged for coaching. It's a proxy for "is this team stuck?"

### Google

**Bazel + TAP (Test Automation Platform)**: Google's build system (Bazel) and test platform (TAP) run millions of tests per day on a monorepo with billions of lines of code.

- **LT**: Bazel's dependency graph means only affected tests re-run per change — a 1-line change tests in minutes, not hours. Elite lead time is achievable despite monorepo scale.
- **CFR**: "Canary analysis" is built into their release tooling. Binary Authorization ensures only tested, attested code reaches prod.
- **MTTR**: Site Reliability Engineering (SRE) model: SLOs define acceptable reliability; error budget policy defines when to stop new releases and focus on reliability. SRE playbooks cover remediation for common failure modes — MTTR is a practice, not just a pipeline property.

**Google's contribution**: Google invented the SRE model, which directly addresses MTTR. Error budget as a deployment gate directly links CFR and DF — when CFR spikes, error budget burns, DF automatically slows.

### Meta

**Gatekeeper (feature flags at scale)**: Meta's core insight is that DF and CFR are decoupled via feature flags. They can deploy new code (high DF) while keeping new features off (low CFR exposure).

- **DF**: Meta deploys their entire web/mobile stack to 3B+ users multiple times per week.
- **CFR**: GateKeeper lets them roll back a feature (flag off) in seconds without a code deploy. A bad feature is a flag flip, not an incident.
- **MTTR**: "Push from Trunk" architecture — one deployable binary means a rollback is a version bump, not a complex cherry-pick.

### Netflix

**Chaos Engineering as MTTR practice**: Netflix deliberately injects failures (Chaos Monkey kills random production instances) to ensure their MTTR is low under real conditions, not just theoretically.

- **CFR + MTTR**: Canary analysis via Kayenta automatically fails a deploy if metrics regress during rollout. No human decision required.
- **DF**: Teams deploy independently. No "Netflix release day" — every team ships when ready.
- **Spinnaker**: Netflix's open-source CD platform explicitly tracks DF and CFR per service as first-class metrics in the deployment dashboard.

---

## How to Measure DORA in Practice

### What to instrument

**Deployment Frequency**:
```
Source: deployment events in your CD system
Measure: count of successful prod deploys per service per day/week
Tool: 
  - GitHub Actions: workflow_run events with conclusion=success to prod environment
  - Jenkins: build events with environment=production
  - Spinnaker: deployment events API
  - Datadog / DORA metrics dashboards in LinearB, Sleuth, Faros
```

**Lead Time for Changes**:
```
Source: Git commit timestamp + deployment timestamp
Measure: time from first commit on a PR to that commit deployed to prod
Complexity: merge commits vs. squash vs. rebase — pick one and be consistent

Tool:
  - LinearB: parses Git + deployment events automatically
  - Sleuth: GitHub + deployment integration
  - Custom: webhook on GitHub push + deployment webhook → delta in seconds
```

**Change Failure Rate**:
```
Source: deployment events + incident/rollback events
Measure: deployments that triggered a rollback or P1/P2 incident within 24h

Challenge: linking an incident to a specific deployment is non-trivial
Approach:
  1. Tag incidents with "caused by deployment" in PagerDuty/OpsGenie
  2. Cross-reference deployment timestamps with incident open times
  3. Accept ±10% imprecision — directional accuracy is good enough
```

**MTTR**:
```
Source: incident management system (PagerDuty, OpsGenie, Statuspage)
Measure: time from incident detected (first alert) to incident resolved
Key: "resolved" = service restored to SLO, not root cause fixed

Tool: PagerDuty Analytics, OpsGenie reports, custom via incident API
```

### Sample Measurement Stack

```
GitHub (source events)
  +
Deployment pipeline (deploy events — webhook or API)
  +
PagerDuty (incident events)
  │
  ▼
LinearB / Sleuth / Faros   ← aggregates all three, surfaces DORA dashboard
  │
  ▼
Weekly team review:
  - DF trending up or down?
  - LT increased? Which stage is growing?
  - CFR spike this week? Linked to which deploys?
  - MTTR outliers? Longest incident — what slowed resolution?
```

---

## Using DORA to Drive Engineering Decisions

### Diagnosing the bottleneck

DORA metrics tell you what is slow, not why. The why requires drilling down:

```
Low Deployment Frequency?
  → Is it slow pipeline? (check stage durations)
  → Is it slow review? (check PR open-to-merge time)
  → Is it fear? (check CFR — high CFR creates deploy fear)

Long Lead Time?
  → Break down: commit time, review time, pipeline time, deploy time
  → Review time usually dominates — fix with PR size limits, review SLOs

High Change Failure Rate?
  → Are failures clustered in one service or spread?
  → Are they correlated with large PRs? (measure: PR size vs. CFR)
  → Is there a test coverage gap in the area failing?

High MTTR?
  → Time to detect (alert delay) vs. time to diagnose (observability gap) vs. time to fix (rollback complexity)?
  → Each requires a different fix
```

### Making the case to leadership

| Metric | Business translation |
|--------|---------------------|
| Low DF (deploys/month) | Features take months to reach users → slower product iteration vs. competitors |
| Long LT (weeks) | Engineers spend weeks on in-flight work, context-switching tax is high |
| High CFR (>15%) | 1 in 7 deploys breaks prod — eng is spending time on incidents, not features |
| High MTTR (days) | When prod breaks, users experience hours of degraded service → trust erosion |

**Principal engineer usage**: use DORA data in eng planning to justify:
- "We need to invest in test automation" → back with CFR data
- "We need to migrate off manual release process" → back with LT data
- "We need to invest in observability" → back with MTTR data

---

## DORA Improvement Playbook

### Improving Deployment Frequency

| Practice | Impact | Effort |
|----------|--------|--------|
| Trunk-based development | High | Medium |
| Feature flags for incomplete work | High | Medium |
| Automated deployment (remove manual steps) | High | Low |
| Decouple service deploys (microservices) | Very High | High |
| Remove change approval board (CAB) for low-risk changes | High | High (org change) |

### Improving Lead Time

| Practice | Impact | Effort |
|----------|--------|--------|
| PR size limits (< 400 lines) | High | Low (policy) |
| Review turnaround SLO (< 4 hours) | Very High | Low (culture) |
| Faster CI (parallelize, cache) | Medium | Medium |
| Trunk-based dev (no branch divergence wait) | High | Medium |
| Async acceptance tests (don't block trunk) | Medium | Medium |

### Improving Change Failure Rate

| Practice | Impact | Effort |
|----------|--------|--------|
| Canary / progressive delivery | Very High | High |
| Automated integration tests | High | High |
| Contract tests (prevent API breakage) | High | Medium |
| Feature flags (decouple deploy from release) | Very High | Medium |
| Smaller deploy batches (frequent small = less risk) | High | Medium |

### Improving MTTR

| Practice | Impact | Effort |
|----------|--------|--------|
| Automated rollback on SLO violation | Very High | High |
| Distributed tracing (find root cause fast) | High | Medium |
| Runbook per alert (pre-authored diagnosis steps) | High | Low |
| On-call rotation with service ownership | High | Medium (org change) |
| Alert quality (reduce noise, tune thresholds) | High | Medium |

---

## Common Pitfalls When Adopting DORA

### 1. Measuring the wrong thing as a proxy

**Bad**: counting "number of PRs merged" as a proxy for DF. Engineers game it by splitting PRs artificially.

**Good**: count deployments to production. Only production deployments count.

### 2. Using DORA metrics as a performance review tool for individuals

DORA measures team and organizational performance. Using it to evaluate individual engineers creates perverse incentives: engineers avoid risky-but-necessary changes, game metrics, and lose trust.

**Amazon/Google policy**: DORA metrics are team health indicators, never individual KPIs.

### 3. Optimizing one metric at the expense of others

Pushing DF up by skipping tests will tank CFR. Pushing CFR down by adding manual approvals will tank LT and DF. The metrics are a system — optimize the system.

### 4. Treating DORA as a destination, not a compass

Elite bands are aspirational benchmarks, not mandatory targets. A team moving from "Low" to "Medium" in one quarter has improved. Don't set "achieve Elite" as a target for Q1 — use DORA to identify the highest-leverage constraint and fix that first.

---

## FAANG Interview Callouts

**Q: How would you use DORA metrics to identify the biggest bottleneck in a team's delivery pipeline?**

Measure all four. The one farthest from elite is usually the constraint. But cross-reference:
- If DF is low and LT is long → pipeline or process bottleneck (dig into stage timings + PR review time)
- If DF is high but CFR is high → deploying fast but breaking things (invest in testing, canary delivery)
- If CFR is low but MTTR is high → good prevention, poor recovery (invest in observability + runbooks)

The bottleneck analysis follows Theory of Constraints: fix the weakest link, then re-measure.

**Q: How do you increase deployment frequency without increasing change failure rate?**

Three mechanisms together:
1. **Smaller batches**: trunk-based dev + feature flags. Each deploy is a small, well-understood change.
2. **Automated gates**: canary analysis catches regressions before 100% traffic exposure.
3. **Decoupled release**: deploy to prod behind a flag; release to users separately. Deploy risk ≠ release risk.

This is exactly how Meta ships — high DF, low user-visible CFR because flags contain the blast radius.

**Q: A VP wants to use DORA metrics to compare team performance. Is that a good idea?**

Caution warranted. DORA metrics reflect system conditions, not just team skill:
- A team owning a 10-year-old monolith will have worse LT than a team on a greenfield service
- A team with 3 engineers vs. 12 will have different DF
- Comparing teams with different tech debt baselines is unfair

Better use: each team sets a baseline and measures improvement over time (quarter-over-quarter). Cross-team comparison only makes sense when controlling for tech stack, service age, and team size. Present this framing to the VP before data gets misused.
