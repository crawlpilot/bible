# SLO Design Guide — Embedding Reliability into System Design

**Category**: HLD · Observability · Reliability Engineering
**Applies to**: Every system design interview answer; every production service design
**Reference**: *Observability Engineering* (Majors/Fong-Jones/Miranda); *Site Reliability Engineering* (Google SRE Book)

> "An SLO without an error budget policy is just a number. An error budget without an SLO is unmeasurable. Together, they are the language that makes reliability a first-class engineering conversation."

---

## Why SLOs Belong in Every HLD

Every system design at FAANG PE level must answer: "How do you know this system is working?" The correct answer is not "we'll add monitoring later." SLOs are the contract between your system and its users — they define what "working" means, make reliability measurable, and drive the trade-off conversation between feature velocity and stability.

At PE scope, you own the SLO framework for your domain, not just a single service.

---

## The SLI → SLO → Error Budget Chain

### SLI (Service Level Indicator)

A ratio: `good events / total events` measured over a time window.

**SLI must be measured from the user's perspective** — not from internal system health metrics.

| Bad SLI (system-internal) | Good SLI (user-facing) |
|--------------------------|----------------------|
| "CPU utilization < 80%" | "Checkout requests that return HTTP 2xx in < 2s" |
| "Database query P99 < 50ms" | "Search results returned in < 500ms as experienced by the client" |
| "Cache hit rate > 95%" | "Product page load time < 1s for 99% of users" |

**SLI formula**:
```
SLI = (count of good events in window) / (count of total events in window)

"Good event" definition for checkout:
  - HTTP response code: 2xx
  - Response time: < 2000ms (measured at load balancer, not application code)
  - No data corruption (checksum validation passes)

"Total events" = all checkout requests (excluding health check traffic, internal calls)
```

**Common SLI types**:

| SLI Type | Definition | Example |
|----------|-----------|---------|
| **Availability** | Fraction of requests that succeed | 99.9% of checkout requests return 2xx |
| **Latency** | Fraction of requests that complete within a threshold | 99% of search requests complete in < 500ms |
| **Quality** | Fraction of responses that are valid/complete | 99.5% of recommendation API responses return ≥ 3 results |
| **Freshness** | Fraction of data reads that return data updated within threshold | 99% of feed reads return data updated within 5 minutes |
| **Durability** | Fraction of writes that are successfully persisted and readable | 99.999% of committed writes are readable within 1 second |
| **Throughput** | Fraction of time the system can handle the required load | 99.9% of hours the system processes ≥ 10K RPS without queuing |

### SLO (Service Level Objective)

A target value for the SLI over a rolling time window.

```
SLO: "99.9% of checkout requests are good over a 30-day rolling window"

Decomposed:
  SLI:    (good checkout requests) / (total checkout requests)
  Target: 99.9%
  Window: 30-day rolling
```

**Window choice**:

| Window | Best For | Trade-off |
|--------|---------|-----------|
| 7-day rolling | Fast feedback; responds quickly to incidents | Small sample size; one bad day burns significant budget |
| 28/30-day rolling | Standard; smooths weekly traffic variation | Slower to detect sustained drift |
| Quarterly | Strategic planning; capacity SLOs | Too slow for operational alerting |

**Setting SLO targets — the right process**:
1. Measure your actual current SLI (baseline)
2. Identify what users actually need (from support tickets, NPS data, user research)
3. Set target slightly above your baseline if you're improving, or at baseline if maintaining
4. Do NOT set 99.999% without understanding the operational investment required

**SLO tightening**:
```
Month 1: Baseline measurement = 99.3% availability → Set SLO at 99.5% (aspirational but achievable)
Month 3: Consistently achieving 99.6% → Tighten SLO to 99.7%
Month 6: Achieving 99.8% → Tighten to 99.9%

Tighten SLOs incrementally. Each tightening requires reliability investment that must be planned.
```

### Error Budget

```
Error budget = 1 - SLO target

SLO: 99.9% → Error budget: 0.1%

In time units (30-day window):
  Total minutes = 30 × 24 × 60 = 43,200 minutes
  Error budget = 0.1% × 43,200 = 43.2 minutes of allowed downtime/errors per month

In request units (at 10K RPS, 30-day window):
  Total requests = 10,000 × 43,200 × 60 = 25.9 billion
  Error budget = 0.1% × 25.9B = 25.9 million allowed failed requests per month
```

**Error budget consumption tracking**:
```
Budget consumed this window =
  sum(bad events in window) / sum(total events in window)

Budget remaining =
  SLO error rate - current error rate
  = 0.001 - 0.0003  (if current error rate is 0.03%)
  = 0.0007 remaining
  = 70% of budget remaining
```

---

## Error Budget Policy

The written contract between engineering and product. Must be agreed upon before incidents happen.

### Standard Policy Table

| Budget Remaining | Eng Action | Product Action |
|-----------------|-----------|---------------|
| > 50% | Ship freely; invest in features; run chaos experiments | Propose features; expect normal velocity |
| 25–50% | Normal caution; require reliability review for high-risk changes | Flag features that require risky infrastructure changes |
| 10–25% | Elevated caution; peer review on all prod changes; no experiments | Deprioritize non-critical infrastructure work |
| < 10% | Freeze non-critical changes; reliability work only | Redirect capacity to reliability; delay non-critical launches |
| Exhausted | Incident mode: halt all non-critical changes; all capacity to reliability | Executive-level discussion on trade-offs |

### Escalation Triggers

```
Trigger: budget burned > 50% in first 10 days of window
Action:  Engineering lead review; re-examine recent changes; plan reliability sprint

Trigger: budget exhausted before end of window
Action:  Exec-level reliability review; potential feature freeze; SLO review (was target too aggressive?)

Trigger: budget never burns (always at 99%+ of budget remaining)
Action:  Consider tightening SLO; you may be over-engineering reliability at the cost of velocity
```

---

## SLO Design Patterns by System Type

### User-Facing API Service

```
Service: Checkout API
Traffic: 5K RPS peak, 1K RPS average

SLI-1: Availability
  Good event: HTTP 2xx response
  Total event: all checkout requests
  Exclusions: health check calls; internal retry traffic

SLO-1: 99.9% availability, 30-day rolling
  Error budget: 43.2 minutes/month

SLI-2: Latency
  Good event: checkout response in < 2000ms (measured at load balancer)
  Total event: all checkout requests
  Threshold: 2000ms (matches user experience research: >2s = significant abandonment)

SLO-2: 99% of checkouts complete in < 2s, 7-day rolling
  Error budget: 1% of requests = ~86,400 slow requests/day at 1K RPS average

SLI-3: Correctness
  Good event: checkout response that passes idempotency verification
    (charge matches requested amount; order record created; inventory decremented)
  Total event: all completed checkout requests
  Measurement: async validation job checks 1% sample within 30 seconds

SLO-3: 99.99% correctness, 30-day rolling
  (Financial transactions: correctness SLO tighter than availability SLO)
```

### Async Processing Pipeline

```
Service: Order fulfillment pipeline (Kafka → processing → inventory update)

SLI-1: Freshness
  Good event: order processed within 30 seconds of creation
  Total event: all orders created
  Measurement: timestamp diff between order.created_at and fulfillment.completed_at

SLO-1: 99% of orders fulfilled within 30 seconds, 7-day rolling

SLI-2: Throughput
  Good event: processing lag < 1 minute (consumer group lag < 60s of messages)
  Total event: each minute of operation
  Measurement: Kafka consumer group lag converted to seconds of lag

SLO-2: 99.5% of minutes have lag < 60 seconds, 7-day rolling

SLI-3: Completeness
  Good event: order successfully fulfilled (no dropped messages)
  Total event: all orders created in the window
  Measurement: count(fulfillment.completed) / count(order.created) per hour

SLO-3: 99.99% completeness, 30-day rolling (dropped orders = revenue loss)
```

### Storage / Database Service

```
Service: User profile store (DynamoDB-backed)

SLI-1: Read availability
  Good event: GetItem returns 200 within 50ms
  Total event: all GetItem requests
  SLO: 99.99% read availability, 30-day (tight — profile reads are on every request)

SLI-2: Write durability
  Good event: PutItem acknowledges AND item is readable within 1s (consistency check)
  Total event: all PutItem requests
  SLO: 99.999% write durability, 30-day (data loss is unacceptable)

SLI-3: Latency
  Good event: GetItem returns in < 20ms
  Total event: all GetItem requests
  SLO: 99.9% of reads in < 20ms, 7-day (p99 latency — acceptable for profile reads)
```

---

## Burn Rate Alerting — The Operational Implementation

### Burn Rate Formula

```
Burn rate = (current error rate) / (SLO error rate)

At SLO = 99.9% → SLO error rate = 0.001

If current error rate = 0.01 (1%) → burn rate = 10×
If current error rate = 0.1 (10%) → burn rate = 100×

Interpretation:
  Burn rate 1× = consuming budget at exactly the allowed rate (fine)
  Burn rate 10× = will exhaust monthly budget in 3 days
  Burn rate 14.4× = will exhaust monthly budget in 2 hours → PAGE
  Burn rate 720× = will exhaust monthly budget in 1 hour
```

### Multi-Window Alert Rules (Google Standard)

Alert when burn rate is sustained over **both** a long window and a short window simultaneously:

| Severity | Long window | Short window | Burn rate | Pages? |
|----------|------------|-------------|-----------|--------|
| **Critical (SEV-1 page)** | 1 hour | 5 minutes | 14.4× | Yes — exhausts budget in ~2h |
| **High (SEV-2 page)** | 6 hours | 30 minutes | 6× | Yes — exhausts budget in 5 days |
| **Warning (ticket)** | 3 days | 6 hours | 1× | No — just ticket + Slack notification |

**PromQL implementation**:
```promql
# Burn rate over 1h window (for page-level alert)
(
  sum(rate(http_requests_total{job="checkout", status=~"5.."}[1h]))
  /
  sum(rate(http_requests_total{job="checkout"}[1h]))
) / 0.001  # SLO error rate (1 - 0.999)
> 14.4  # Burn rate threshold for 2h exhaustion

# Combined with 5m window (short-term confirmation)
AND
(
  sum(rate(http_requests_total{job="checkout", status=~"5.."}[5m]))
  /
  sum(rate(http_requests_total{job="checkout"}[5m]))
) / 0.001
> 14.4
```

### Alert → Runbook → Escalation Chain

```
Alert fires: checkout_slo_burn_rate_critical
    │
    ▼
PagerDuty pages on-call engineer
    │
    ▼
Runbook: https://internal-docs/runbooks/checkout/slo-burn-rate.md
    │
    ▼
Step 1: Check Grafana SLO dashboard (link in alert)
Step 2: Check recent deploys (link to deploy log)
Step 3: Check trace query for error traces (link to pre-built query)
Step 4: If burn rate > 14.4× for > 15 min → escalate to Payments Platform TL
    │
    ▼
If unresolved in 30 min → escalate to Payments Platform EM + VP Engineering
```

---

## SLO in System Design Interview — Template Answer

When the interviewer asks "how do you monitor this system?", structure as:

```
"I'd define SLOs for each user-facing operation before building monitoring.

For [service name] at [scale]:

SLI-1 (Availability): [good event definition] / [total events]
SLO-1: [target]%, [window]-day rolling → Error budget: [X] minutes/month

SLI-2 (Latency): fraction of [operation] completing in < [threshold]ms at load balancer
SLO-2: [target]% in < [threshold]ms, [window]-day rolling

I'd alert on error budget burn rate, not raw error rate:
- 14.4× burn rate → page on-call immediately (exhausts budget in 2 hours)
- 6× burn rate → ticket + async notification (exhausts budget in 5 days)

The error budget policy determines what happens when budget is consumed:
- <10% remaining: freeze non-critical deploys
- Exhausted: all hands on reliability

Every alert links to a runbook with numbered diagnostic steps and pre-built trace queries.
Post-mortem required for all SEV-1 and above within 5 business days."
```

---

## SLO Design Checklist (for every HLD)

```
□ SLIs defined from user perspective — not internal system health
□ "Good event" definition is precise and measurable
□ Baseline SLI measured before setting SLO target
□ SLO set slightly above baseline, with a tightening plan
□ Error budget calculated in both time and request units
□ Error budget policy written and agreed between eng and product
□ Burn rate alerting configured with multi-window rules
□ Alert → runbook → escalation chain documented
□ SLO dashboard exists and is linked from alerts
□ SLO reviewed quarterly; tightened as reliability improves
```

---

## Common SLO Anti-Patterns

| Anti-pattern | Why It's Wrong | Correct Approach |
|-------------|---------------|-----------------|
| "100% uptime SLO" | Unachievable; eliminates error budget; creates hero culture | Start at 99.9%; tighten based on measured baseline |
| SLI measured from internal metrics ("DB query < 50ms") | Doesn't reflect user experience; missing network, load balancer, client layers | Measure at the outermost layer (load balancer or client) |
| Alert on raw error rate, not burn rate | A 2% error rate for 1 minute is fine; for 1 hour it's a SEV-1. Rate alone doesn't tell you. | Alert on burn rate with multi-window confirmation |
| Same SLO for all operations | Payment writes need 99.999% durability; analytics reads need 99.5% availability | Different operations have different user impact; separate SLOs |
| SLO set by managers, not engineers | Engineers must own what they agree to; otherwise it becomes a blame mechanism | Engineers set SLO targets; product agrees to the trade-off implications |
| No error budget policy | Error budget without policy is just a number; no mechanism to act on it | Write the policy before you need it; agree during reliability review |

---

## Reference: SLO Math Quick Sheet

```
Availability SLO → Downtime budget:
  99%    → 7.31 hours/month    (low-criticality internal tools)
  99.5%  → 3.65 hours/month
  99.9%  → 43.2 minutes/month (standard user-facing services)
  99.95% → 21.6 minutes/month
  99.99% → 4.32 minutes/month (critical payment/auth services)
  99.999%→ 25.9 seconds/month (financial infrastructure; very expensive)

Burn rate → time to budget exhaustion (30-day window):
  1×   → 30 days (normal consumption)
  2×   → 15 days
  6×   → 5 days   → ticket
  14.4×→ 2 hours  → page
  72×  → 10 hours  → SEV-0
  720× → 1 hour   → SEV-0 + exec alert
```
