# Engineering KPIs

## Why KPIs Matter at Principal Level

A principal engineer should be able to walk into any engineering review meeting and answer: "Is this system healthy? Is this team effective? Is this platform improving or degrading over time?"

KPIs give you that answer at a glance. They are the instrumentation of the engineering system — the equivalent of a car's dashboard. Not the destination, but the signals that tell you whether you're on track.

**Critical distinction**: KPIs are operational health monitors, not goal-setting tools. You maintain KPIs. You improve toward OKR targets.

---

## KPI Categories for Engineering

```
┌─────────────────────────────────────────────────────────────────┐
│  DELIVERY KPIs          │  RELIABILITY KPIs                     │
│  How fast we ship       │  How stable what we ship is           │
│                         │                                       │
│  • Deployment Frequency │  • Availability / Uptime              │
│  • Lead Time            │  • Error Rate                         │
│  • Cycle Time           │  • MTTR                               │
│  • Throughput           │  • Change Failure Rate                │
├─────────────────────────┼───────────────────────────────────────┤
│  QUALITY KPIs           │  TEAM HEALTH KPIs                     │
│  How correct what       │  How sustainably the team operates    │
│  we ship is             │                                       │
│  • Test coverage        │  • Velocity stability                 │
│  • Defect escape rate   │  • PR review turnaround               │
│  • Tech debt ratio      │  • On-call burden                     │
│  • Security CVE age     │  • Engineer satisfaction (eNPS)       │
└─────────────────────────┴───────────────────────────────────────┘
```

---

## Delivery KPIs

### Deployment Frequency

**Definition**: number of successful production deployments per service per week/day.

**Why it matters**: high frequency = small batches = low risk per deploy. Low frequency is a symptom of painful, risky deploys.

```
Measurement:
  Count of prod deploy events per service per time period.
  
Source: CD pipeline (GitHub Actions, Jenkins, CodeDeploy deployment events)

Targets (DORA bands):
  Elite:  Multiple per day
  High:   Weekly
  Medium: Monthly
  Low:    < Monthly
```

**How companies track it**:
- Google: Deployment frequency per service tracked in Borgmon/internal dashboards
- Amazon: Per-service deploy count tracked in internal deployment service; low-frequency services flagged to leadership
- Netflix: Spinnaker dashboards show deploys per service per day; cadence visible to all engineers

### Lead Time for Changes

**Definition**: time from first commit to that code running in production.

```
Measurement:
  Lead Time = Deploy Timestamp - First Commit Timestamp
  
Complexity: multi-commit PRs need the earliest commit. Squash merges simplify this.
  
Source: Git + deployment pipeline
Tool: LinearB, Sleuth, or custom (GitHub webhooks + deployment events)
```

**What to watch**:
- If lead time is > 1 week: where is the time? Review time (PR sitting)? Pipeline time? Manual approvals?
- If lead time spiked last week: a big PR was merged (batching risk) or a test suite slowed down

### Cycle Time

**Definition**: time from "in progress" (work started) to "deployed" (in production). Narrower than lead time — starts when the engineer picks up the work, not when the first commit is made.

```
Cycle Time = Deploy Time - Ticket "In Progress" Time

Phases:
  Coding time     = first commit - in-progress
  Review time     = first review request - last review approval
  Deploy time     = approved - deployed to prod
  
Target: elite teams have cycle time < 2 days for a typical feature story
```

**Cycle time breakdown** reveals where your process is broken:
- Coding time > 3 days per story: stories are too large, decompose them
- Review time > 1 day: review culture/capacity problem
- Deploy time > 4 hours after approval: manual gates, slow pipelines

---

## Reliability KPIs

### Service Availability (SLI/SLO)

**Definition**: percentage of time the service is performing within its defined SLO (e.g., p99 latency < 200ms, error rate < 0.1%).

```
Availability = (good requests / total requests) × 100

SLO: 99.9% availability → allows 43.8 min/month of "bad" requests
SLA: external commitment based on SLO

Measurement:
  sum(http_requests_total{status!~"5.."}) / sum(http_requests_total)
  
Dashboard: error rate over time, SLO burn rate
```

**At FAANG**: each service owns its SLO, published to a central registry. Teams are alerted when burn rate exceeds 2× (consuming budget faster than expected). Exceeding error budget triggers automatic deploy freeze.

### Error Rate

**Definition**: percentage of all requests that result in a server-side error (HTTP 5xx or application-level error).

```
Error Rate = (5xx responses / total responses) × 100

Healthy baseline:   < 0.1% for most services
Alert threshold:    > 0.5% sustained for 5 minutes
Page threshold:     > 1.0% for 2 minutes

Breakdown:
  - By endpoint: which specific endpoint is degraded?
  - By dependency: is the error in this service or upstream?
  - By region: is this a regional failure or global?
```

### MTTR (Mean Time to Recovery)

**Definition**: average time from first alert to service restored to SLO.

```
MTTR = sum(recovery_time - alert_time) / number_of_incidents

Targets:
  Elite:    < 1 hour
  High:     < 1 day
  
Components of MTTR:
  MTTD (Mean Time to Detect):   alert fires how quickly after failure begins?
  MTTI (Mean Time to Identify): from alert to knowing root cause
  MTTF (Mean Time to Fix):      from diagnosis to fix deployed/rolled back
```

**MTTD is the biggest lever**: if a failure affects users for 2 hours and you detect it at 90 minutes, the first 90 minutes are undetectable failure. Synthetic monitoring and user-journey checks reduce MTTD to < 1 minute.

### Change Failure Rate

**Definition**: percentage of production deployments that cause a degraded service or require a hotfix/rollback.

```
CFR = (deployments causing incidents / total deployments) × 100

Target: < 5% (elite DORA)

Source: correlate deployment events with incident creation in PagerDuty/OpsGenie
        within a 1–24 hour window of the deploy
        
Common causes of high CFR:
  - Large batches (many changes per deploy)
  - Insufficient test coverage
  - No canary / progressive delivery
  - Config changes not treated as deployments (they should be)
```

---

## Quality KPIs

### Test Coverage

**Definition**: percentage of production code exercised by automated tests.

```
Metric: line coverage % (minimum); branch coverage % (better)
Tool:   JaCoCo (Java), Istanbul (JS), Coverage.py (Python)

Targets:
  Line coverage:   > 80% for application code
  Branch coverage: > 70%
  Critical paths:  100% (payment, auth, data integrity)
  
Anti-pattern: 100% coverage with low-quality tests that don't assert correctness.
              Coverage is a floor check, not a ceiling goal.
```

**What to track**: coverage trends over time (delta per sprint), not just the current number. A stable coverage dropping 2% per sprint is a signal — new code isn't being tested.

### Defect Escape Rate

**Definition**: percentage of defects found in production vs. total defects found (production + pre-production).

```
Defect Escape Rate = (prod defects / (prod + pre-prod defects)) × 100

Target: < 15% escape rate (85% of bugs caught before prod)

A high escape rate means:
  - Test coverage gaps
  - Staging environment doesn't replicate prod
  - Code review is not effective at catching logic errors
```

### Technical Debt Ratio

**Definition**: ratio of remediation cost (time to fix all tech debt) to development cost (time to build the system from scratch).

```
Tech Debt Ratio = (remediation cost / development cost) × 100

Industry benchmark: < 5% is healthy; > 20% is a serious risk

Practical measurement:
  SonarQube: computes tech debt in hours based on code smells, violations, duplication
  Manual: count known tech debt issues × average fix time

Track:
  - Debt ratio trend (increasing = accelerating decay)
  - Debt by category: duplication, complexity, coverage, maintainability
  - Debt added per sprint vs. debt paid per sprint
```

### Security KPIs

| KPI | Target | Measurement |
|-----|--------|-------------|
| Critical CVE age | < 72 hours to remediate | Snyk/Dependabot alert creation → close timestamp |
| High CVE age | < 2 weeks | Same |
| SAST coverage | 100% of services | Pipeline config audit |
| Secrets in code incidents | 0 | GitHub secret scanning + GitGuardian alerts |
| SBOM freshness | < 24h | Last SBOM generation timestamp per service |

---

## KPI Dashboard Design

A principal engineer's engineering health dashboard at a glance:

```
┌─────────────────────────────────────────────────────────────┐
│  ENGINEERING HEALTH DASHBOARD          Week of 2026-06-09   │
├──────────────────┬──────────────────┬───────────────────────┤
│  DELIVERY        │  RELIABILITY     │  QUALITY              │
│                  │                  │                       │
│  Deploy Freq     │  Availability    │  Test Coverage        │
│  ████████ 4.2/d  │  ██████ 99.94%   │  ████████ 82%         │
│  ↑ vs 3.8 prev   │  ↓ vs 99.97%     │  → stable             │
│                  │                  │                       │
│  Lead Time       │  Error Rate      │  Defect Escape        │
│  ████ 18h avg    │  ██ 0.08%        │  ███ 12%              │
│  ↑ improving     │  → within SLO    │  ↑ improving          │
│                  │                  │                       │
│  Cycle Time      │  MTTR            │  CVE Age (Critical)   │
│  ██ 1.4d avg     │  █████ 42 min    │  ██ 48h avg           │
│  → stable        │  ↑ improving     │  ↑ improving          │
└──────────────────┴──────────────────┴───────────────────────┘

▲ = improving  ↓ = degrading  → = stable    █ = % to target
```

---

## FAANG Interview Callouts

**Q: An executive asks "how is engineering performing?" What 3 metrics do you show them?**

Frame for business impact, not technical operations:
1. **Lead Time for Changes**: "It takes us an average of 18 hours from code commit to production. Industry elite is < 1 hour. This means we're shipping features 18× slower than we could be."
2. **Change Failure Rate**: "8% of our deployments cause production incidents requiring rollback. Industry elite is < 5%. Each incident costs $X in engineering time and $Y in customer impact."
3. **MTTR**: "When something breaks, it takes us 2.5 hours to restore service. Industry elite is < 1 hour. We're losing 90+ minutes per incident versus best-in-class."

These connect technical health to business outcomes (revenue, time-to-market, customer trust) — the language executives actually respond to.

**Q: Your test coverage is 85% but defect escape rate is 30%. How do you explain this?**

Coverage measures breadth (lines executed), not quality (correctness verified). You can have 100% coverage with tests that never assert anything meaningful. 30% escape with 85% coverage means:
- Tests are verifying happy paths, not edge cases
- Production data shapes don't match test data
- Integration points (between services, with DBs) are not covered
- Contract between services has drifted without contract tests catching it

Fix: mutation testing (PIT for Java) — it measures whether your tests actually detect bugs, not just whether the code was executed. Target > 70% mutation score.
