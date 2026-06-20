# Observability Engineering
**Authors**: Charity Majors, Liz Fong-Jones, George Miranda
**Publisher**: O'Reilly Media, 2022
**Category**: Site Reliability Engineering · Production Systems · Distributed Systems Operations

> "Observability is not a feature you bolt on after the fact. It is a property of the system you build from the beginning. A system is observable if you can understand its internal state from its external outputs alone — without having to ship new code."

---

## Why This Book Matters for FAANG PE Interviews

At principal engineer level, you are evaluated not just on whether you can design a system — but on whether you can operate it. Every system you design in an interview should have an observability section, because a system that cannot be debugged in production is not production-ready.

This book is the authoritative treatment of **production observability** at scale. It is the source of the concepts your interviewers will expect you to know: SLOs, error budgets, structured events, distributed tracing, high-cardinality querying, and blameless post-mortems.

**Direct interview mapping**:
- "How would you monitor this system?" → Four golden signals, SLI/SLO/error budget, burn rate alerting
- "Walk me through how you'd debug a latency issue in production" → Trace-first debugging, high-cardinality queries, waterfall analysis
- "How do you ensure reliability?" → Error budget policy, canary analysis, automated rollback on SLO burn
- "Tell me about an incident you led" → SSTAR + post-mortem structure + blameless culture
- "How do you build a culture of reliability?" → SLO culture, on-call rotation design, runbook standards

---

## TL;DR — 3 Ideas to Internalize

1. **Monitoring tells you that something is wrong; observability tells you why** — monitoring is pre-aggregated metrics for known failure modes; observability is the ability to ask arbitrary questions of production state, including for failure modes no one anticipated.
2. **The unit of observability is the wide structured event** — one event per request, carrying all relevant context fields (user_id, trace_id, feature_flag_variant, duration_ms, error_type). Pre-aggregated metrics destroy the dimensions you need to debug.
3. **SLOs create a shared language for reliability** — error budgets give product the explicit authority to trade reliability investment for feature velocity, making reliability a first-class engineering and product conversation, not just an ops concern.

---

## Part 1 — The Path to Observability

### What Observability Is (and Is Not)

**The control systems definition**: A system is observable if its internal state can be inferred from its external outputs. Applied to software: can you understand what any individual request did, end-to-end, from the telemetry your system emits?

**What monitoring is**: A system of pre-defined metrics, dashboards, and alert thresholds built around *known* failure modes. Monitoring works well when you've seen the failure before.

**What monitoring cannot do**: Answer questions about failure modes you didn't anticipate. At scale and with the complexity of modern distributed systems, most interesting failures are novel combinations of circumstances — they don't trigger pre-defined alerts, or they trigger too late.

**The observability question**: "Can I understand what is happening in my system, for any arbitrary user, at any point in time, without shipping new code?"

If the answer is yes → observable.
If the answer is "I'd have to add more logging/metrics for that" → not observable.

### The Cardinality Problem with Traditional Monitoring

Traditional time-series databases (Prometheus, Graphite, InfluxDB) store data as metric name + label set → time series of values.

```
http_request_duration_seconds{service="checkout", endpoint="/order", status="200"} = [...]
```

**The cardinality cliff**: Every unique label combination is a separate time series. Adding `user_id` as a label would create millions of time series — most monitoring systems crash or OOM at ~10M time series. So monitoring dashboards cannot segment by user_id, order_id, session_id, experiment_variant, or any other high-cardinality field.

**Why this matters**: The most actionable bugs are specific — "users on iOS 17 with 3+ items in cart who use Apple Pay are getting timeouts." You cannot surface this with pre-aggregated metrics.

**The high-cardinality solution**: Don't pre-aggregate. Store raw structured events. Query them at read time. This is the architectural premise of tools like Honeycomb — a columnar event store with full GROUP BY capability across any field, at query time.

---

## Part 2 — Structured Events as the Foundation

### Wide Structured Events

A **wide structured event** is a single JSON object emitted per unit of work (request, job, transaction), containing every field relevant to understanding that work.

**Narrow event** (traditional log line — bad):
```
2024-01-15 14:23:01 ERROR payment-service: timeout processing order
```

**Wide structured event** (observable — good):
```json
{
  "timestamp": "2024-01-15T14:23:01.234Z",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "service": "payment-service",
  "version": "2.3.4",
  "env": "production",
  "region": "us-east-1",
  "user_id": "user-789012",
  "session_id": "sess-abc123",
  "order_id": "order-456789",
  "amount_usd": 847.50,
  "cart_item_count": 12,
  "user_country": "US",
  "user_plan_tier": "premium",
  "payment_provider": "stripe",
  "payment_method_type": "apple_pay",
  "feature_flag_checkout_v2": true,
  "duration_ms": 3042,
  "error": true,
  "error_type": "upstream_timeout",
  "http_status": 504,
  "retry_attempt": 2,
  "db_query_count": 3,
  "db_duration_ms": 18,
  "cache_hit": false,
  "stripe_api_duration_ms": 2998,
  "stripe_error_code": "request_timeout"
}
```

This single event answers: Which user? Which order? What amount? Which plan tier? Which payment provider and method? Was a feature flag enabled? How long did the Stripe call take? Was the cache warm?

### Building Wide Events Incrementally

The wide event is constructed throughout the request lifecycle, not at a single point:

```python
# Middleware layer — adds common request context
event = {
    "trace_id": get_trace_id(),
    "service": "payment-service",
    "version": os.getenv("SERVICE_VERSION"),
    "region": os.getenv("AWS_REGION"),
    "user_id": request.user.id,
    "session_id": request.session_id,
}

# Business logic — adds domain context
event.update({
    "order_id": order.id,
    "amount_usd": order.total,
    "cart_item_count": len(order.items),
    "payment_provider": payment.provider,
})

# After operation — adds outcome
event.update({
    "duration_ms": elapsed_ms,
    "http_status": response.status_code,
    "error": response.is_error,
    "db_query_count": db.query_count,
    "stripe_api_duration_ms": stripe_call_duration,
})

# At request end — emit the complete event
telemetry.emit(event)
```

**The pattern**: Build up context throughout; emit once at the end. Never emit partial events mid-request (they create phantom signals).

---

## Part 3 — Distributed Tracing

### Trace Anatomy

A **trace** is a directed acyclic graph of **spans**, connected by parent-child relationships, all sharing a `trace_id`. Each span is a wide structured event for one unit of work.

```
trace_id: 4bf92f3577b34da6a3ce929d0e0e4736
│
├── Span: API Gateway [12ms]  (root: span_id=aaa, parent=none)
│
└── Span: OrderService.processOrder [835ms]  (span_id=bbb, parent=aaa)
    ├── Span: InventoryService.reserve [43ms]  (span_id=ccc, parent=bbb)
    │   └── Span: Redis.SET [2ms]  (span_id=ddd, parent=ccc)
    │
    └── Span: PaymentService.charge [789ms]  (span_id=eee, parent=bbb)
        ├── Span: PostgreSQL.SELECT [7ms]  (span_id=fff, parent=eee)
        ├── Span: Stripe.POST /charges [771ms] ← BOTTLENECK  (span_id=ggg, parent=eee)
        └── Span: PostgreSQL.INSERT [11ms]  (span_id=hhh, parent=eee)
```

**Trace context propagation** (W3C standard):
```
HTTP Header: traceparent: 00-{trace_id}-{parent_span_id}-{flags}
```
Every service reads this header, creates a child span with the given parent_span_id, and forwards the header to downstream calls.

### Trace-First Debugging Workflow

When an alert fires:
1. Find a representative trace for the failing request (search by error=true, duration > threshold)
2. Open the waterfall view — visually identify the widest span (the bottleneck)
3. Click into that span — read the structured event fields for context
4. Compare a slow trace with a fast trace — what fields differ?
5. Form a hypothesis from the diff; test it

This replaces: SSH to a prod host → grep through logs → mentally reconstruct request flow.

### Sampling Strategies

At 50K RPS, storing every trace is cost-prohibitive. Sampling keeps a representative subset.

**Head-based sampling** (decision at trace entry):
- Simple: random N% at the entry point; propagate the decision downstream
- Weakness: a 1% sample misses 99% of P999 (rare slow) requests

**Tail-based sampling** (decision after trace completes):
- Buffer all spans until the root span completes (knowing total duration + error status)
- Keep all traces with error=true or duration > P95 threshold
- Sample normal, fast traces at 1–10%
- Requires a trace aggregation buffer (the OTel Collector with tail sampling processor)
- Strongly preferred by Majors/Fong-Jones — preserves the interesting events

**Exemplar-based sampling**:
- Store one trace per histogram latency bucket (one P50, one P95, one P99, one P999)
- Minimal storage; representative across the distribution
- Prometheus exemplars: attaches a trace_id to a specific histogram observation

---

## Part 4 — SLOs, Error Budgets, and Alerting

### SLI → SLO → Error Budget Chain

**SLI (Service Level Indicator)**:
- A ratio: `good events / total events` over a time window
- "Good checkout request" = HTTP 2xx response in < 2 seconds
- "Good" must be defined from the user's perspective, not the system's internals

**SLO (Service Level Objective)**:
- A target for the SLI: "99.9% of checkout requests are good over a 30-day rolling window"
- Start by measuring your current SLI before setting the target — "we achieve 99.7% today, we'll target 99.9%"
- Do not set 99.999% targets without understanding the operational investment required

**Error Budget**:
```
Error budget = 1 - SLO target
99.9% SLO → 0.1% error budget → 43.8 minutes/month

Budget remaining = budget - budget consumed so far this window
Budget consumed = (1 - current SLI) × window duration
```

**Error budget policy**: The written contract between engineering and product about what happens when the budget is consumed:

| Budget State | Action |
|-------------|--------|
| > 50% remaining | Feature velocity: ship freely |
| 10–50% remaining | Caution: increase review bar on reliability-affecting changes |
| < 10% remaining | Reliability focus: freeze non-critical deploys; prioritize stability work |
| Exhausted | Incident mode: halt all non-critical changes; all capacity to reliability |

### Burn Rate Alerting

Alert on the *rate* at which the error budget is consumed, not the absolute remaining budget. Burn rate tells you how fast you'll exhaust the budget.

```
Burn rate = current error rate / SLO error rate

If SLO = 99.9% → SLO error rate = 0.1%
If current error rate = 1.44% → burn rate = 1.44 / 0.1 = 14.4×
At 14.4× burn rate: will exhaust monthly budget in 30 days / 14.4 = ~2 hours → PAGE IMMEDIATELY

If current error rate = 0.6% → burn rate = 6×
At 6× burn rate: will exhaust monthly budget in 5 days → ticket + async notification
```

**Multi-window alerting** (reduces false positives):
- Alert only when burn rate is sustained over BOTH a short window (5min) and a long window (1h)
- Short window only: transient spike → false positive
- Long window only: slow burn may take too long to alert
- Both: sustained degradation → real problem

### SLO Culture vs Traditional Uptime Culture

| Traditional | SLO Culture |
|------------|-------------|
| "We must achieve 100% uptime" | "We have 43.8 minutes of error budget per month — let's be deliberate about how we spend it" |
| Reliability is ops' problem | Reliability is a shared product and engineering concern |
| Postmortems are blame sessions | Error budget: product explicitly chose to spend it on a risky feature |
| Alerts at arbitrary thresholds | Alerts when user experience is measurably degraded relative to the SLO |
| Hero culture (firefighting) | Systematic elimination of reliability debt |

---

## Part 5 — On-Call and Incident Response

### On-Call Philosophy

The authors argue strongly: **the people who write the code should be on-call for it.** This is not punitive — it creates a feedback loop that makes code observable by design.

When an engineer is on-call for their own code, they feel the pain of:
- Missing runbooks (they write them)
- Alert noise from non-actionable alerts (they tune thresholds)
- Dashboards that don't explain what's wrong (they add tracing)
- Toil from manual interventions (they automate it)

Without this feedback loop, observability is an afterthought added by ops after engineers have shipped and moved on.

### Incident Severity Framework

| Level | Impact | Response |
|-------|--------|---------|
| SEV-0 | Complete outage; all users affected; zero functionality | Immediate; CEO-level communication |
| SEV-1 | Major degradation; >20% users impacted; SLO exhausted | Paged on-call within 5 minutes |
| SEV-2 | Partial degradation; <20% users; SLO at risk | Paged within 30 minutes |
| SEV-3 | Minor; workaround available; no SLO impact | Business hours |
| SEV-4 | Cosmetic | Next sprint |

### Incident Roles

**Incident Commander (IC)**: Owns the incident process. Coordinates roles. Communicates status. Declares resolution. Does NOT do technical investigation — context switching destroys coordination effectiveness.

**Technical Lead (TL)**: Owns the investigation and mitigation. Forms hypotheses, runs tests, executes changes. Does NOT write status updates (IC's job).

**Comms Lead**: Writes external status page updates and internal stakeholder notifications. Paces communication cadence.

**Scribe**: Documents the timeline in real time. Records: what was done, when, by whom, what the outcome was. Enables accurate post-mortem reconstruction.

### The Mitigation Hierarchy

Always mitigate before fully understanding root cause. MTTR (Mean Time to Restore) is the priority.

```
1. Rollback deploy (< 5 min if CI/CD is mature)
2. Disable feature flag (< 1 min)
3. Traffic shift (route away from affected region/instance)
4. Circuit breaker / graceful degradation on failing dependency
5. Scale up (if cause is resource saturation)
6. Hotfix and deploy (30+ min — last resort during active incident)
```

**Anti-patterns**:
- "I need to understand the root cause before I mitigate" — no. Restore service first.
- Debugging in production with exploratory code changes — this widens the blast radius
- Not checking for recent changes first — the first diagnostic question is always "what changed?"

---

## Part 6 — Post-Mortem Documentation

### Blameless Post-Mortem Culture

The post-mortem assumes: engineers acted with the best information they had, within the system they inherited. If a human error caused an incident, the system allowed that error to cause damage — fix the system.

**Blameless** does not mean **consequences-free**. Engineers are accountable for the quality of their post-mortems and their follow-through on action items. Blameless means: no shaming, no firing, no attribution of malicious intent.

**Why blamelessness matters at scale**: If engineers fear blame, they under-report near-misses, hide mistakes, and avoid owning high-risk systems. The result is a culture where organizational learning stops. Blameless post-mortems are a prerequisite for reliability improvement.

### Post-Mortem Structure (Production Standard)

```markdown
## Impact
- Users affected (N users, N%, or specific cohort)
- Revenue impact ($X estimated)
- SLO: [SLO name] burned [X%] of monthly error budget
- External: Status page posted? Customer escalations?

## Timeline (timestamped, factual, chronological)
| Time (UTC) | Event |
|-----------|-------|
| HH:MM | [what happened, by whom, outcome] |

## Root Cause
[One precise paragraph. The technical change + the gap in process/testing that allowed it to reach production.]

## Contributing Factors
[Bulleted list: systemic issues that contributed. Each factor is a potential action item.]

## Action Items
| Action | Owner | Due Date | Priority |
|--------|-------|----------|----------|
| [specific, testable action] | @person | YYYY-MM-DD | P1/P2/P3 |

## What Went Well
[Celebrate things that worked: fast rollback, good alert coverage, clear communication, trace-first debugging.]

## Lessons Learned
[2-3 key takeaways. Generalizable beyond this specific incident.]
```

**Quality bar for action items**:
- Specific: "Add Stripe latency simulation (P95=400ms, P99=1200ms) to staging" — not "improve testing"
- Owned: one named person — not "payment team"
- Dated: deadline — not "soon"
- Testable: you can verify it was done — not "be more careful"

### Runbook Standards

A runbook is an operational document attached to an alert. Every production alert must have one.

**Runbook must contain**:
1. What does this alert mean? (in plain English, non-technical translation)
2. Immediate actions — numbered, ordered, actionable
3. Diagnostic queries — ready to paste into your observability tools
4. Common causes and their resolutions
5. Escalation path — who to call if unresolved in N minutes
6. Links to related runbooks

**Runbook anti-patterns**:
- Written by someone who has never been on-call for this alert
- Broken links (worse than no runbook — false confidence)
- "Check the dashboard" without saying which dashboard or what to look for
- No escalation path — on-call engineer hits a wall and doesn't know who to call

---

## Part 7 — Observability Culture and Organization

### The Observability Maturity Model

| Level | Characteristics |
|-------|----------------|
| **0: No observability** | Debugging requires SSH to production; `grep` through log files; "it works on my machine" |
| **1: Basic monitoring** | Uptime checks; CPU/memory alerts; application error rate metrics |
| **2: Structured logging** | JSON logs; log aggregation (ELK/Loki); basic querying by service and status |
| **3: Distributed tracing** | Trace context propagated; waterfall view for request debugging; latency attribution |
| **4: High-cardinality observability** | Wide structured events; arbitrary GROUP BY at query time; unknown failures debuggable |
| **5: Proactive reliability** | SLOs with error budgets; burn rate alerting; canary analysis; chaos engineering |

FAANG PE expectation: own the Level 4 → Level 5 journey for your team or organization.

### Observability-Driven Development

The authors advocate writing instrumentation alongside features, not retroactively after incidents:

1. **Before shipping**: Define what "working" looks like — what SLI will you measure?
2. **During development**: Instrument the feature with structured events; test in staging with real observability tooling (not print statements)
3. **Canary deploy**: Ship to 1% of traffic; run SLO query; if burn rate is normal for 30 minutes, proceed
4. **Post-launch**: Check your SLI for the first week; verify no regression

**The feedback loop**: Engineers who operate their own code in production improve their instrumentation continuously. Engineers who throw code over the wall to ops never develop this skill.

### SLO as a Conversation Framework

SLOs work as an organizational tool because they make reliability a quantified, explicit conversation:

- **Engineering → Product**: "We have 43.8 minutes of error budget for the month. Shipping the new payment flow has a 30% chance of causing an outage that burns 20 minutes of budget. Do we want to spend that?"
- **Product → Engineering**: "The new payment flow is Q3's top priority. We accept the reliability risk. Make sure you can roll back in under 5 minutes."
- **Engineering → Leadership**: "We've burned 95% of our error budget in the first 10 days of the month. We need to freeze feature work and invest in the payment service stability."

This is a fundamentally different conversation from "the system was down for 20 minutes." SLOs translate reliability into the language of risk, trade-offs, and business decisions.

---

## Key Concepts — Interview Quick Reference

### Observability vs Monitoring
- Monitoring: pre-aggregated metrics for known failure modes
- Observability: arbitrary questions about any production state, including novel failures
- Key property: can you debug a failure you've never seen before, without shipping new code?

### The Wide Structured Event
- One event per request; emitted at request end
- Carries all relevant context: user_id, trace_id, order_id, feature flags, duration, error type
- High-cardinality fields are first-class citizens — not split off into separate metric labels

### Distributed Tracing
- trace_id: unique per end-to-end request; shared across all spans
- span_id: unique per unit of work; carries parent_span_id for causality
- W3C traceparent header: propagated across all service hops
- Tail-based sampling: preferred — samples based on complete trace outcome

### SLI / SLO / Error Budget
- SLI: good events / total events (success rate, P99 latency)
- SLO: target for SLI over rolling window (99.9% success, 30-day)
- Error budget: 1 - SLO target (0.1% → 43.8 min/month)
- Burn rate: current error rate / SLO error rate (14.4× → page immediately)

### Incident Response
1. Scope (who, what, where)
2. Correlate (what changed in the last 30 min)
3. Trace-first (identify the failing/slow span)
4. Mitigate (rollback first; understand later)
5. Verify restoration (SLO metrics back to normal for 15+ min)
6. Communicate (status page at T+5, T+15, T+30, resolution)

### Post-Mortem
- Timeline (timestamped, factual) → root cause (single precise statement) → contributing factors → action items (specific, owned, dated) → what went well → lessons learned
- Blameless: the system is the defendant, not the engineer
- Action items that are vague ("improve testing") are not action items

### Four Golden Signals
- Latency, Traffic, Errors, Saturation
- Always measure successful vs error latency separately
- Saturation: queue depth and connection pool utilization, not just CPU

---

## FAANG Interview Application Phrases

1. **"I'd instrument this service with OpenTelemetry, propagate W3C TraceContext across all downstream calls, and use tail-based sampling at 100% for errors and 10% for normal traffic — ensuring every failure mode is debuggable without pre-knowing what to look for."**

2. **"I'd define the SLO from the user's perspective: 99.9% of checkout requests complete successfully in under 2s, over a 30-day rolling window. I'd alert on burn rate — 14.4× burn rate pages the on-call immediately, because at that rate we exhaust the monthly budget in 2 hours."**

3. **"The first question in any incident is: what changed in the last 30 minutes? Not 'what could be wrong' — the answer is always the most recent change. Then I open traces for the affected requests and find the slow or failing span. MTTR beats root-cause-first: restore service, then understand."**

4. **"Post-mortems are blameless but not consequences-free. The system is the defendant. Action items must be specific ('add Stripe latency mock to staging' not 'improve testing'), owned by one person, and dated. A vague action item is a closed loop that doesn't close."**

5. **"Every alert in production must have a runbook. Not a link to the source code — a numbered list of diagnostic steps, ready-to-paste queries, common cause-resolution pairs, and an escalation path. If the on-call has to figure out what the alert means, the runbook failed."**

---

## Connections to This Repository

| Topic | Related Folder | Connection |
|-------|---------------|-----------|
| SLO design in system architecture | [HLD/designs/](../../HLD/designs/) | Every HLD should include SLI/SLO definition |
| Incident management process | [Development/processes/](../../Development/processes/) | Incident response playbook |
| Post-mortem template | [Development/processes/](../../Development/processes/) | Standard template for incident documentation |
| SSTAR with incident leadership | [Leadership/sstar-examples/](../../Leadership/sstar-examples/) | Incident commander experience → PE behavioral story |
| ADR: Observability stack selection | [Architecture/decisions/](../../Architecture/decisions/) | "Why we chose Honeycomb over Datadog" ADR |
| Observability for ML systems | [AI/ml-systems/](../../AI/ml-systems/) | Model performance monitoring, data drift detection |

**Complementary Reading**:
- *Site Reliability Engineering* (Google SRE book) — SLO/SLI framework origin; Chapter 4 is essential
- *The SRE Workbook* (Google) — Practical implementation of SRE practices
- *Designing Data-Intensive Applications* (Kleppmann, Chapter 1) — Maintainability and operability as system properties
- *Release It!* (Nygard) — Production-readiness patterns: circuit breakers, bulkheads, timeouts
