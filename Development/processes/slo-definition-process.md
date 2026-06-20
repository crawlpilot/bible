# SLO Definition and Management Process

**Category**: Engineering Operations · Reliability · Service Contracts  
**Audience**: Principal / Staff Engineers owning reliability standards and SLO culture  
**Related**: [Observability & CI](observability-incident-continuous-improvement.md) · [PRR](production-readiness-review.md)

> "An SLO is not a performance target. It is a business contract: the minimum level of reliability that makes the product worth using. Set it too tight and you burn budget on noise. Set it too loose and you're not detecting real user pain. The calibration is the skill."

---

## The SLO Hierarchy

```
SLA (Service Level Agreement)
  └── Legal/contractual commitment to external customers
  └── Typically expressed as monthly uptime percentage
  └── Has financial penalties for breach
  └── Example: "99.9% uptime per calendar month, measured as HTTP 200 rate"

SLO (Service Level Objective)
  └── Internal engineering target — tighter than SLA
  └── Measured over rolling windows (28-day or 30-day)
  └── Breach triggers engineering action, not legal action
  └── Example: "99.95% success rate over 28 days"

SLI (Service Level Indicator)
  └── The actual metric being measured
  └── Ratio of good events to total events
  └── Example: "(requests with status 200-499) / (all requests)"

Error Budget
  └── 1 - SLO = the allowable failure fraction
  └── Example: 99.95% SLO → 0.05% error budget → 21.6 min/month
```

---

## Step 1: Define the SLI

### What Makes a Good SLI?

A good SLI measures what users actually experience. The test: if the SLI is healthy, are users happy? If the SLI is unhealthy, are users suffering?

**SLI categories**:

| Category | Measures | Use When |
|----------|---------|----------|
| **Availability** | Was the service up? Can users reach it? | All services |
| **Latency** | Was the response fast enough to be useful? | Request-serving systems |
| **Correctness** | Did the service return the right answer? | Data processing, ML, financial systems |
| **Freshness** | Was the data recent enough? | Pipelines, caches, dashboards |
| **Coverage** | Did the service process all expected work? | Batch jobs, event consumers |
| **Throughput** | Was the capacity high enough? | Streaming systems, bulk APIs |

### SLI Formulas by Service Type

**Request-serving service (most common)**:
```
Availability SLI = (requests returning 2xx or 4xx) / (all requests)
Latency SLI      = (requests completing in < Xms) / (all requests)

Why exclude 5xx from latency SLI: a failed request has no useful latency.
Why include 4xx in availability: 4xx means the service responded; user error, not service error.
Why exclude 429 (rate limit) from error rate: this is intended behavior, not failure.
```

**Pipeline / data processing service**:
```
Freshness SLI = (pipeline outputs produced within X minutes of input) / (all pipeline outputs)
Coverage SLI  = (records successfully processed) / (records submitted for processing)
Correctness SLI = (records with correct output) / (records processed)
                  [requires golden dataset for comparison]
```

**Storage service (database, object store)**:
```
Durability SLI = (bytes written and retrievable) / (bytes written)
Availability SLI = (successful read + write operations) / (all operations)
```

**Message queue / event streaming**:
```
Delivery SLI = (messages delivered within X minutes of publication) / (messages published)
```

### SLI Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| SLI on internal metrics (CPU %) | Does not measure user experience | Use RED metrics: error rate, latency |
| Availability = "server is running" | Server up ≠ users can use it | Measure user-facing request success rate |
| Averaging latency | Hides tail latency pain | Use P95 or P99 latency |
| Single-window measurement | Month-end SLO gaming | Rolling 28-day window |
| SLI on test traffic | Synthetic tests miss real user paths | Measure real user traffic |

---

## Step 2: Set the SLO Target

### How Tight Should the SLO Be?

Start by asking: **what level of reliability makes the product worth using?**

| Product Type | Typical SLO Range | Reasoning |
|-------------|-------------------|-----------|
| Payment processing | 99.95–99.99% | Every error is a lost transaction; regulatory implications |
| User authentication | 99.9–99.99% | Auth unavailable = all users locked out |
| Core CRUD API | 99.5–99.9% | User-visible but retryable; some tolerance |
| Recommendation engine | 99.0–99.5% | Degradation (show defaults) is acceptable |
| Batch analytics pipeline | 99.0–99.5% | Not real-time; freshness window provides tolerance |
| Internal developer tooling | 99.0% | Engineers tolerate degradation better than end-users |

**Calibration heuristic**:
1. Start with historical reliability: what has the service actually achieved over the past 90 days?
2. Set the SLO to be slightly tighter than current reality (creates improvement pressure without constant breach)
3. If the service has never been at 99.9%, don't start with 99.9% — start at 99.5% and tighten quarterly

### The Error Budget Implication Table

Always compute the error budget in human-understandable units before agreeing to an SLO target:

| SLO | Monthly Error Budget | Weekly | Daily |
|-----|---------------------|--------|-------|
| 90.0% | 43h 12m | 10h 48m | 2h 24m |
| 95.0% | 21h 36m | 5h 24m | 1h 12m |
| 99.0% | 7h 12m | 1h 48m | 10m 4s |
| 99.5% | 3h 36m | 54m | 7m 12s |
| 99.9% | 43m 12s | 10m 4s | 1m 26s |
| 99.95% | 21m 36s | 5m 2s | 43s |
| 99.99% | 4m 19s | 1m 1s | 8.6s |

**Reality check**: At 99.9%, you have 43 minutes per month. A single incident that takes 45 minutes to mitigate consumes 104% of your monthly budget. Does your team have the incident response capability to reliably mitigate in < 30 minutes?

### SLO Negotiation: Engineering ↔ Business

SLOs require agreement between engineering (who is bound by the SLO) and business/product (who defines what users need).

**Negotiation framework**:

```
Business: "We need five nines — 99.999%."
Engineering: "99.999% gives us a monthly budget of 26 seconds. One deploy takes 3 minutes.
              We physically cannot deploy without burning 100% of the budget.
              What reliability level do users actually need? Let's look at support ticket data
              and churn data — at what reliability level do users leave or complain?"

Business: "Users start complaining when it's down more than 5 minutes in a week."
Engineering: "5 minutes per week is 99.95% weekly. Our SLO should be 99.9% monthly,
              which gives us 43 minutes/month and allows us to operate at the reliability
              users actually need, without burning budget on deployments."
```

**Signals to use in SLO calibration**:
- Support ticket volume as a function of availability
- User churn correlation with incident frequency/duration
- Competitor reliability benchmarks (SLAs they publish)
- Regulatory or contractual requirements

---

## Step 3: Define the Measurement Window

### Rolling vs. Calendar Window

| Window Type | Pros | Cons | Use When |
|-------------|------|------|----------|
| **Rolling 28-day** | Always reflects recent behavior; no "reset" at month end | Harder to explain to business | Most services (Google SRE recommendation) |
| **Calendar month** | Simple for SLA reporting; easy to understand | End-of-month behavior can be gamed; incidents near month-end have outsized impact | SLA reporting for contracts |
| **Rolling 7-day** | Fast feedback on recent changes | Too short to reflect trend; noisy | Development environments, canary stages |

**Recommendation**: Measure SLI over rolling 28-day; report SLO compliance on calendar month to align with SLA contracts.

---

## Step 4: Configure Alerts

See [Observability & CI — SLO-Based Alerting](observability-incident-continuous-improvement.md) for burn rate alert configuration.

**Alert tier summary**:

```
Tier 1 (wake someone up): burn rate > 14.4× over 1h — budget gone in 2h
Tier 2 (urgent, same day): burn rate > 6× over 6h — budget gone in 5 days  
Tier 3 (sprint planning): burn rate > 1× over 3 days — trending to exhaustion
```

---

## Step 5: Publish and Socialize

An SLO is only effective if it is known, visible, and enforced.

```
Publication checklist:
□ SLO documented in the service's README or wiki page
□ SLO dashboard accessible to: engineering, product, support, EM/leadership
□ Error budget status included in weekly team standup
□ SLO status shared in engineering-wide reliability report (monthly)
□ On-call rotation and product team receive budget burn alerts
```

**Error budget policy** — enforce these behaviors based on budget status:

| Error Budget Remaining | Engineering Policy |
|----------------------|-------------------|
| > 50% | Full feature and deployment velocity |
| 25–50% | Flag risky deployments; no new unproven dependencies |
| 10–25% | Reliability work prioritized over features; EM conversation required for new risk |
| < 10% | Deploy freeze (except reliability fixes); executive notification |
| 0% (exhausted) | Full freeze; mandatory reliability sprint; SLO review and possible re-calibration |

---

## SLO Review Cadence

### Monthly SLO Review (30 min)

**Agenda**:
1. Error budget status: how much budget remains for each service?
2. Budget velocity: at current burn rate, will we exhaust before month end?
3. Incident-by-incident review: what caused budget consumption?
4. Alert review: did alerts fire appropriately? Were there silent failures?
5. SLO calibration: are any SLOs no longer calibrated to user needs?

**Questions to answer each month**:
- Which services are burning budget fastest?
- Are we burning budget due to incidents or due to normal operational variance?
- Are users complaining at our current reliability level? (If not, SLO might be too tight)
- Are any SLOs too loose? (If we've never been close to breach, the SLO might not be protecting users)

### Quarterly SLO Calibration

Review whether the SLO target itself is correct:

| Signal | Action |
|--------|--------|
| SLO breached 3+ months in a row | Either improve reliability OR loosen SLO — the target is not achievable at current investment |
| Error budget never consumed | Tighten the SLO — you're holding yourself to a lower bar than necessary |
| User complaints despite green SLO | SLI is not measuring what users experience — redefine the SLI |
| SLA breach despite green SLO | SLO is looser than SLA — tighten SLO to create early warning before SLA breach |

---

## Multi-Service SLO Composition

When a user request passes through multiple services, the end-to-end SLO is constrained by the product of component SLOs.

```
If service A has SLO of 99.9% and service B has SLO of 99.9%:
End-to-end availability = 99.9% × 99.9% = 99.8%

If user path touches 5 services each at 99.9%:
End-to-end = 99.9%^5 = 99.5%

Implication: each component service must have a TIGHTER SLO than the end-to-end target.
For a 99.9% end-to-end SLO across 5 services: each service needs ~99.98% SLO.
```

**Architecture implication**: The more synchronous services in a critical path, the harder it is to achieve a given end-to-end SLO. This is a design argument for:
- Async/event-driven over synchronous for non-critical-path operations
- Reducing service count in critical paths (avoid microservice decomposition that multiplies failure surface)
- Caching to reduce live dependency count

---

## Common SLO Mistakes

| Mistake | Impact | Correction |
|---------|--------|------------|
| SLO on synthetic monitoring only | Real user errors not caught | SLO must measure real traffic |
| SLO on mean latency | Tail latency pain hidden | SLO on P95 or P99 |
| Setting SLO and forgetting it | SLO drifts out of calibration | Quarterly calibration reviews |
| Single SLO for multi-tier traffic | Critical path degraded but bulk SLO healthy | Separate SLOs for: critical path, bulk, premium tier |
| 100% SLO target | Impossible; creates perverse incentives | 100% is not achievable; define the real minimum |
| SLO that nobody reads | No behavioral change | Error budget dashboard visible, weekly review enforced |

---

## FAANG Interview Framing

**"How do you define SLOs for a new service?"**

> "I start by asking what level of reliability makes the product worth using — not what's technically achievable. I look at user complaint data, churn data, and the product requirements. From there I define an SLI — a ratio of good events to total events that directly measures what users experience, not a proxy metric like CPU. I set the SLO slightly tighter than current measured reliability to create improvement pressure, then compute the error budget and gut-check it: can our team actually mitigate incidents in time to stay within this budget? I align the SLO with the product and business teams before finalizing, because an SLO nobody owns is just a number on a dashboard. After launch, I run monthly reviews to see if the SLO is still calibrated — SLOs that are never at risk of breach are too loose, and SLOs that are constantly breached need either investment or renegotiation."

**"What do you do when a team exhausts their error budget?"**

> "An exhausted error budget triggers a reliability sprint: feature work is frozen, and the team focuses on the root causes that consumed the budget. We review the post-mortems from the incidents that burned the most budget and identify the systemic patterns — usually it's one or two repeating incident classes. The goal of the reliability sprint is to close those gaps: better detection, faster mitigation, or architectural changes that eliminate the failure mode. After the sprint, we review whether the SLO target itself is realistic given the service's architecture — if we can't hold 99.9% without burning our team out, maybe we need to invest in making the service structurally more reliable, or honestly renegotiate the target with the business."
