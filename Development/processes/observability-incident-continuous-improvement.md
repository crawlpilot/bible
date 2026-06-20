# Observability → Incident Management → Continuous Improvement

**Category**: Engineering Operations · SRE · Team Practices  
**Audience**: Principal / Staff Engineers driving org-wide observability culture  
**Related**: [Incident Response Playbook](incident-response-playbook.md) · [Observability & Monitoring](../best-practices/04-observability-monitoring.md) · [Post-Mortem Template](post-mortem-template.md)

> "Observability is not a tool you buy — it is a team discipline you build. Insights flow from instrumented systems. Diagnostics require rich context. Alerts are only as good as the process that answers them. The loop closes only when every incident feeds learning back into the system."

---

## The Continuous Improvement Loop

```
                     ┌─────────────────────────────────────┐
                     │           Production System          │
                     │  (instrumented, observable)          │
                     └──────────────┬──────────────────────┘
                                    │ emits signals
                     ┌──────────────▼──────────────────────┐
                     │         Observability Layer          │
                     │  Metrics · Logs · Traces · Events    │
                     └──┬───────────────────────┬──────────┘
                        │ anomaly / threshold   │ on-demand
                        ▼                       ▼ during incident
              ┌─────────────────┐    ┌──────────────────────┐
              │  Alert fires    │    │  Diagnostic workflow  │
              │  (actionable,   │    │  (trace → log →       │
              │   low-noise)    │    │   metric correlation) │
              └────────┬────────┘    └──────────┬───────────┘
                       │                        │
                       ▼                        ▼
              ┌────────────────────────────────────────────┐
              │         Incident Management Cycle           │
              │  Detect → Triage → Mitigate → Resolve       │
              └─────────────────────┬──────────────────────┘
                                    │ closure
                                    ▼
              ┌────────────────────────────────────────────┐
              │        Blameless Post-Mortem               │
              │  What happened · Why · What we learned      │
              └─────────────────────┬──────────────────────┘
                                    │ action items
                                    ▼
              ┌────────────────────────────────────────────┐
              │       Continuous Improvement Actions        │
              │  Better alerts · Runbooks · Code fixes ·   │
              │  Architecture changes · SLO refinements     │
              └─────────────────────┬──────────────────────┘
                                    │ deployed back to
                                    └──────► Production System
```

---

## Part 1: Building Observable Systems

### The Instrumentation Contract

Observable systems are not born — they are designed. A principal engineer's job is to establish the instrumentation contract that every service must satisfy before it ships.

**Minimum viable observability (MVO) checklist**:

| Signal | What must exist | Tooling |
|--------|----------------|---------|
| **Health endpoint** | `GET /health` returns 200 + dependency status | All services |
| **Request metrics** | Rate, error rate, latency (RED method) per endpoint | Prometheus / CloudWatch / Datadog |
| **Dependency metrics** | Each downstream call: latency + error rate | OTel auto-instrumentation |
| **Structured logs** | JSON, with `trace_id`, `span_id`, `service`, `severity` | Logback / structlog / zerolog |
| **Distributed trace** | W3C TraceContext headers propagated; spans for every external call | OpenTelemetry SDK |
| **Custom business metric** | ≥1 metric per business capability (orders/s, payment success rate) | App-level instrumentation |
| **Startup/shutdown logs** | Config values (not secrets) logged on startup | App initialization |
| **Build metadata** | `version`, `commit_sha`, `deploy_time` exposed in health endpoint | CI/CD injection |

**Gate**: Services that do not satisfy MVO do not deploy to production. This is enforced in the CD pipeline, not by convention.

### The Three Pillars — Team Contract

| Pillar | Team responsibility | What principal engineer must enforce |
|--------|-------------------|-------------------------------------|
| **Metrics** | Every team instruments RED (Rate, Errors, Duration) + USE (Utilization, Saturation, Errors) for infra | Dashboards reviewed in sprint reviews; thresholds in code review |
| **Logs** | Structured logs at the right level; correlation IDs; no sensitive data | Log sampling policy; log-level discipline (no `debug` in production at default) |
| **Traces** | OTel propagation end-to-end; span naming conventions followed | Trace coverage > 95% of external calls; sampling rate agreed per service |

### OpenTelemetry as the Single Instrumentation Layer

Instrument once; route to any backend. This is the architecture decision that prevents vendor lock-in and eliminates re-instrumentation when changing observability vendors.

```
Application Code
      │
      ▼
OpenTelemetry SDK (language-specific: Java, Python, Go, Node)
      │
      ▼
OTel Collector (sidecar or standalone)
      │
      ├──► Prometheus (metrics) → Grafana
      ├──► Jaeger / Tempo (traces) → Grafana
      ├──► Elasticsearch / Loki (logs) → Grafana
      └──► Datadog / Dynatrace / Honeycomb (commercial)
```

**Team practice**: New services use OTel SDK from day one. Existing services migrate incrementally — one pillar at a time (traces first, then metrics, then logs correlation).

---

## Part 2: Diagnostic Practices

### The Diagnostic Workflow (During an Incident)

When an alert fires, the responder needs to answer four questions fast:

```
1. WHAT is broken?     → Dashboards, alert context, error rate
2. WHERE is it broken? → Distributed trace, service topology
3. WHEN did it start?  → Deployment correlation, metric timeline
4. WHY did it break?   → Logs, traces, change events, error details
```

**Structured diagnostic path**:

```
Alert fires (e.g., "payment-service error rate > 1% for 5 min")
       │
Step 1: Open alert runbook link (embedded in alert body)
       │
Step 2: Check the 3-panel dashboard (rate / error rate / latency)
       │  ├── Is it all endpoints or one? → narrow to endpoint
       │  └── Is latency high too? → dependency problem likely
       │
Step 3: Find a failing trace (link in alert or trace query by error=true)
       │  └── Which span is failing? → points to the broken dependency
       │
Step 4: Drill to logs for that service + time window
       │  └── Look for: exception type, upstream IP, db query, 3rd party response
       │
Step 5: Check recent deployments and config changes (CMDB / deployment history)
       │  └── Did a deploy happen in the 30 min before the error spike?
       │
Step 6: Check infra metrics (CPU, memory, connection pool exhaustion, disk)
       │
Step 7: Correlate with dependencies (is downstream X also erroring?)
```

### Correlation Is the Core Skill

Every log entry must contain a `trace_id` and `request_id`. Every trace must link to associated logs. Without this, you are debugging three disconnected datasets.

**Log entry structure**:
```json
{
  "timestamp": "2024-01-15T10:23:45.123Z",
  "severity": "ERROR",
  "service": "payment-service",
  "version": "2.4.1",
  "commit_sha": "abc1234",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "request_id": "req-8f2d4a",
  "user_id": "u-12345",
  "message": "Payment gateway timeout",
  "error": {
    "type": "ConnectionTimeoutException",
    "message": "Connect to stripe.com:443 timed out after 5000ms",
    "stack_trace": "..."
  },
  "context": {
    "amount": 99.99,
    "currency": "USD",
    "gateway": "stripe",
    "attempt": 2
  }
}
```

**What this enables**: From a single log line, click `trace_id` → see the full distributed trace. Click `span_id` → see all logs for that span. Click `commit_sha` → see the code that was running. No tab-switching, no time-window hunting.

### Runbooks as Diagnostics Codified

Every alert must have a runbook. A runbook is not documentation — it is executable procedure.

**Runbook anatomy**:

```markdown
# Alert: payment-service-error-rate-high

## What this means
Error rate for payment-service exceeds 1% sustained over 5 minutes.
SLO impact: At 1% error rate, 30-day error budget burns in ~48 hours.

## Immediate check
1. Open [payment-service dashboard](#link)
2. Check which endpoint is erroring (breakdown by `endpoint` label)
3. Check if Stripe status page shows incidents: https://status.stripe.com

## Most common causes + fixes
| Symptom | Cause | Fix |
|---------|-------|-----|
| All endpoints + Stripe latency spike | Stripe API degraded | Enable fallback payment processor (runbook: #stripe-fallback) |
| Single endpoint + connection pool full | DB connection exhaustion | Restart 1 instance → watch for recovery; then investigate pool leak |
| 401s from payment-service to fraud-api | fraud-api token rotated | Check fraud-api secret in Vault; rotate payment-service secret |
| Spike right after deploy | Code regression | Roll back via [rollback runbook](#link) |

## Escalation
- 10 min: No resolution → page payment-service team lead
- 20 min: → SEV-1, page VP Engineering
```

**Runbook quality bar**: A junior engineer on-call for the first time should be able to resolve the most common causes using the runbook alone.

---

## Part 3: Alerts — Design and Anti-Patterns

### Alerting Philosophy

**Principle 1: Alert on symptoms, not causes.**  
A user doesn't care that CPU is at 90%. They care that the checkout page is timing out. Alert on the thing users experience; instrument causes for diagnostic context.

```
BAD:  "CPU > 80% on payment-service-pod-7"
GOOD: "payment-service error rate > 0.1% for 5 minutes"

BAD:  "Kafka consumer lag > 10,000"
GOOD: "order-processing latency P95 > 3 seconds for 10 minutes"
```

**Principle 2: Every alert must be actionable.**  
If a human receives an alert and there is no action they can take, the alert is noise. Every alert must either: (a) require immediate human action, or (b) auto-remediate and notify asynchronously.

**Principle 3: Alert on SLO burn rate, not thresholds.**  
Threshold alerts (`error rate > 1%`) misfire. A 1% error rate at 1 RPS (1 error) is different from 1% at 10,000 RPS (100 errors). SLO burn rate alerts detect real user impact.

**Principle 4: Minimize alert volume.**  
Alert fatigue kills incident response. Target: the average on-call engineer handles ≤ 2 actionable pages per 12-hour on-call shift. Track and enforce this.

### SLO-Based Alerting (Google SRE Model)

**Definitions**:
- **SLI** (Service Level Indicator): A metric that measures what users experience. E.g., `success_rate = (non-5xx requests) / (total requests)`.
- **SLO** (Service Level Objective): The target. E.g., `success_rate ≥ 99.9% over 30 days`.
- **Error Budget**: The allowable failures. 99.9% SLO = 0.1% budget = 43.2 min/month.
- **Burn Rate**: How fast the error budget is being consumed. 1× = consuming at the rate that exactly exhausts budget in 30 days.

**Multi-window, multi-burn-rate alerting** (the Google SRE recommendation):

```
Alert Tier 1 (Page immediately):
  Condition: Burn rate > 14.4× over last 1h AND > 14.4× over last 5min
  Meaning: At this rate, 100% of 30-day error budget consumed in 2 hours
  Action: Immediate incident response, SEV-1

Alert Tier 2 (Page within 15 min):
  Condition: Burn rate > 6× over last 6h AND > 6× over last 30min
  Meaning: Budget fully consumed in 5 days
  Action: Investigate urgently, may not wake on-call but must not wait until morning

Alert Tier 3 (Ticket, business hours):
  Condition: Burn rate > 1× over last 3 days
  Meaning: At this rate, budget will exhaust before month end
  Action: Investigate and fix within sprint; discuss in next SLO review
```

**Why two windows**: Short window catches sudden spikes. Long window catches slow burns that short windows miss.

### Alerting Anti-Patterns to Eliminate

| Anti-Pattern | Impact | Fix |
|-------------|--------|-----|
| **Alert flapping** | Alert fires and resolves repeatedly; trains engineers to ignore it | Add hysteresis (hold alert for N minutes before resolving) |
| **Alert storm** | One failure causes 50 alerts to fire simultaneously | Alert grouping + inhibition rules (alert on cause, suppress symptom alerts) |
| **Stale alerts** | Alert exists but service is decommissioned or metric no longer emitted | Quarterly alert audit; ownership enforced |
| **No runbook** | Engineers page-to-nowhere; spend 10 min figuring out what the alert means | Require runbook link in every alert definition |
| **Threshold without context** | "CPU > 80%" — so what? | Replace with SLO burn rate or user-impact metric |
| **Alert on mean** | Mean hides P99; 1% of users could have 10× latency while mean looks fine | Alert on P99 latency, not average |
| **Alert on every deployment** | Transient spike after deploy causes false alarm | Add deploy annotation + 10-min grace period |
| **Different teams, same alert** | 3 teams get the same alert; nobody owns it | Each alert has exactly one owning team in alert metadata |

### Alert Metadata Standard

Every alert definition must include:

```yaml
alert: PaymentServiceErrorRateHigh
annotations:
  summary: "Payment service error rate exceeds SLO burn threshold"
  runbook_url: "https://wiki.internal/runbooks/payment-service-error-rate"
  dashboard_url: "https://grafana.internal/d/payment-service"
  severity: "critical"
  team: "payments"
  slo: "payment-service-availability"
  impact: "Users unable to complete checkout"
labels:
  service: payment-service
  environment: production
  tier: "1"
```

---

## Part 4: Incident Management Cycle

### Detection → Triage → Mitigate → Resolve

**Phase 1: Detection (target < 2 min)**

```
Automatic (preferred):
  Alert fires → PagerDuty/OpsGenie routes to on-call → Slack incident channel created automatically

Manual (fallback):
  User report → Support ticket → Triage → Escalate to engineering if SLO impact

Early detection indicators (catch before it pages):
  - SLO burn rate Tier 3 alerts (trending to budget exhaustion)
  - Anomaly detection (Datadog, Grafana ML bands)
  - Canary deployment error rate (catch regressions before 100% traffic)
```

**Phase 2: Triage (target < 5 min for SEV-1)**

Triage answers one question: **what is the user impact and is it getting better or worse?**

```
Incident Commander (IC) actions in first 5 minutes:
1. Declare severity (use framework from incident-response-playbook.md)
2. Open incident channel: #inc-YYYY-MM-DD-{service}-{short-description}
3. Assign roles: IC · Communications Lead · Technical Lead
4. Assess: blast radius (how many users, which features) + trajectory (worsening/stable/improving)
5. Start incident timeline in shared doc (timestamp every action)
```

**Phase 3: Mitigate (restore service before root cause)**

```
Mitigation ≠ fix.

Mitigation options (fastest to slowest):
  1. Rollback: fastest if a recent deploy is the cause (< 5 min)
  2. Feature flag off: disable the broken feature (< 1 min if flags in place)
  3. Traffic shift: route away from degraded AZ/region (< 2 min with load balancer)
  4. Scale out: if capacity is the cause (< 5 min with auto-scaling)
  5. Throttle upstream: protect a degraded downstream with rate limiting
  6. Manual workaround: communicate to users + support (if no automated fix)
  7. Fix and deploy: last resort (slowest; CI/CD time)
```

**MTTR decomposition**:
```
MTTR = Time to Detect + Time to Respond + Time to Mitigate + Time to Verify

Target decomposition (SEV-1):
  Detect:   < 2 min (SLO burn rate alert, 5-min window)
  Respond:  < 5 min (IC assigned, channel open)
  Mitigate: < 30 min (rollback or flag off)
  Verify:   < 15 min (confirm error rate returning to normal)

Total MTTR target SEV-1: < 52 min
```

**Phase 4: Resolve**

Resolution criteria — all of:
- User-facing error rate back within SLO
- No new alerts firing for > 15 min
- Root cause identified (even if fix not deployed yet)
- Monitoring confirmed (dashboard shows stable, not just one data point)
- Stakeholder comms sent (if external users affected)

```
Post-resolution actions (same day):
1. Close incident, record resolution timestamp
2. Send final stakeholder update ("resolved at T, caused by X, post-mortem scheduled")
3. File post-mortem issue (due within 5 business days for SEV-1/SEV-2)
4. Create tracking ticket for permanent fix (if mitigation was a workaround)
```

### Communication During Incidents

**Internal** (Slack incident channel):
```
T+0:00  [IC] Incident declared: SEV-1 - payment errors above SLO. Blast radius: ~15% of checkout attempts failing.
T+0:02  [IC] Roles: IC=Alice, Comms=Bob, Tech Lead=Carol
T+0:05  [TL] Tracing shows failures in payment-gateway → stripe-adapter. Stripe latency 8s (normal 200ms).
T+0:08  [IC] Stripe status page: "Investigating elevated API error rates"
T+0:10  [TL] Enabling fallback processor (Adyen). ETA 3 min.
T+0:13  [TL] Fallback enabled for 20% of traffic. Monitoring error rate.
T+0:18  [TL] Error rate declining. 0.8% → 0.3% → 0.1%. Routing 100% to Adyen.
T+0:25  [IC] Error rate back within SLO (<0.1%). Monitoring.
T+0:40  [IC] Stable 15 min. Incident resolved. Post-mortem due EOD Friday.
```

**External** (status page, every 15–30 min during SEV-0/SEV-1):
```
[10:05] Investigating reports of payment failures. Engineering team engaged.
[10:20] We have identified the cause (upstream payment provider degradation) and are implementing a fix.
[10:40] Issue resolved. All payments are processing normally. A post-incident report will be published within 48 hours.
```

**Rule**: Never go silent for > 30 min during an active SEV-1. Silence breeds customer distrust more than the outage itself.

---

## Part 5: Blameless Post-Mortems

### Why Blameless?

Systems fail because of system conditions — not because an engineer is incompetent or careless. A blameless post-mortem investigates the conditions that made failure possible and the conditions that made failure inevitable.

**If your post-mortem names a person as the root cause, you have failed the post-mortem.**

The correct framing:
```
BAD:  "Alice deployed a broken config that caused the outage."
GOOD: "A broken config was deployable because (1) config validation was not part of CI, 
       (2) staging does not mirror production config schema, 
       (3) no automated rollback triggered because the error manifested 20 minutes post-deploy 
       (outside the automatic rollback window). 
       Alice's action was a proximate cause; the system conditions were the root cause."
```

### The Post-Mortem Process

**Timeline**:
- SEV-0/SEV-1: Post-mortem due within 5 business days
- SEV-2: Post-mortem due within 10 business days
- SEV-3: Optional; recommended if pattern is emerging

**Facilitation**:
- Facilitator is a senior engineer NOT directly involved in the incident (neutral party)
- All key responders attend (30–60 min meeting)
- Meeting recorded for async attendees
- No attribution language; review for blame-language before publishing

**Five-Why drill-down**:

```
Incident: Payment service returned 500s for 35 minutes.

Why #1: The database connection pool was exhausted.
Why #2: A new query (deployed at T-20min) held transactions open for 30s each.
Why #3: The query was not tested against production data volume (test DB = 10K rows, prod = 500M rows).
Why #4: Our staging environment is not data-proportional to production.
Why #5: We have never had a process for data-proportional load testing before production deploys.

Root cause: No pre-production performance validation for database queries at production scale.
```

Each "why" is a system condition, not a person's decision.

### Action Items — the Only Output That Matters

A post-mortem with no action items is retrospection, not improvement. Every action item must be:

| Field | Requirement |
|-------|-------------|
| **Owner** | A named individual (not a team) |
| **Due date** | Specific date (not "next sprint") |
| **Priority** | P0 (blocks next deploy), P1 (this sprint), P2 (this quarter) |
| **Success metric** | How do we know it's done and working? |

**Action item categories** (think in layers):

```
Layer 1: Immediate fix (prevents recurrence of this exact issue)
  → "Add connection timeout of 5s to new query. Owner: Bob. Due: today."

Layer 2: Detection improvement (catch this faster next time)
  → "Add alert for connection pool utilization > 70%. Owner: Carol. Due: Mon."

Layer 3: Process improvement (prevent the class of issue)
  → "Add performance test to CI pipeline that runs against prod-scale data sample. Owner: Dave. Due: 2 weeks."

Layer 4: Architecture improvement (eliminate the failure mode)
  → "Spike: evaluate read replica routing so reporting queries don't contend with OLTP pool. Owner: Alice. Due: 1 month."
```

### Post-Mortem Template Skeleton

```markdown
# Post-Mortem: [Service] [Brief Description] — [Date]

**Severity**: SEV-1  
**Duration**: 35 minutes (10:05 – 10:40)  
**Impact**: 15% of checkout attempts failed; ~4,200 affected transactions  
**Authors**: [names]  
**Status**: Action items in progress

## Summary
[2–3 sentences a VP can read. What happened, how long, impact.]

## Timeline
| Time | Event |
|------|-------|
| T-20min | Deploy #4321 to payment-service containing new query |
| T+0:00  | Alert: PaymentServiceErrorRate fires at 14.4× burn |
| ...     | ...  |
| T+35min | Service restored; error rate < SLO |

## Root Cause Analysis
[Five-why drill. System conditions. No blame.]

## What Went Well
- Alert fired within 2 minutes (target met)
- Fallback processor activated in 8 minutes
- Communication cadence maintained every 15 min

## What Could Have Been Better
- Staging DB is not data-proportional (missed this query's performance)
- Runbook did not have the Adyen fallback procedure documented

## Action Items
| Action | Owner | Due | Priority |
|--------|-------|-----|----------|
| Add connection timeout to query | Bob | 2024-01-16 | P0 |
| Alert on connection pool > 70% | Carol | 2024-01-17 | P1 |
| Add data-proportional performance test to CI | Dave | 2024-01-26 | P1 |
| Update runbook with Adyen fallback procedure | Alice | 2024-01-19 | P1 |

## Follow-up Review
Scheduled: 2024-02-15 sprint review — verify all action items closed.
```

---

## Part 6: Continuous Improvement Practices

### The SLO Review Cadence

SLOs are not set once and forgotten. They are living contracts between engineering and the business.

**Monthly SLO review agenda** (30 min, all team leads):

1. **Error budget status**: How much budget remains for each SLO this month?
2. **Burn rate review**: Any services burning budget faster than 1×?
3. **Alert effectiveness**: How many alerts fired? How many were actionable?
4. **SLO calibration**: Are any SLOs too tight (constantly burning budget with no user complaints)? Too loose (users complaining but SLO shows green)?
5. **Next month forecast**: Based on planned changes (big deploy, high-traffic event), adjust error budget reserves.

**Error budget policy**:

| Budget remaining | Engineering response |
|-----------------|---------------------|
| > 50% | Full feature velocity |
| 25–50% | Slow down risky deployments; no new dependencies |
| 10–25% | Reliability work takes priority; feature work paused for the service |
| < 10% | Freeze: no deployments until budget replenishes or SLO adjusted |
| 0% (exhausted) | Incident review required; stakeholder conversation; SLO renegotiation |

This policy turns SLOs from aspirational targets into real engineering constraints that affect sprint planning.

### On-Call Health Metrics

Track these to prevent on-call burnout — the silent killer of reliability culture:

| Metric | Target | Action if exceeded |
|--------|--------|-------------------|
| **Pages per on-call shift** (12h) | ≤ 2 actionable | Alert audit; eliminate noisy alerts |
| **Pages during sleep hours** (10pm–7am) | ≤ 1 per week per engineer | Escalation path review; automation |
| **Alert acknowledgment time** | < 5 min (P95) | Is alert routing correct? Are escalation paths working? |
| **% of alerts auto-resolved** (no human action) | < 20% | Alerts that auto-resolve are likely not actionable — remove them |
| **% of alerts with runbook opened** | > 80% | Runbook discovery issue; embed link in alert body |
| **On-call escalations** | < 1 per week | Improve runbooks; reduce complexity |

**Quarterly on-call retrospective**:
- Present on-call metrics to team
- Vote on top 3 noisiest/most painful alerts
- Sprint allocation: dedicate ≥ 20% of sprint to reliability work when on-call health is poor

### Toil Reduction

Toil = manual, repetitive operational work that scales with traffic/incidents and provides no lasting value.

**Examples of toil to eliminate**:

| Toil | Automated replacement |
|------|-----------------------|
| Manually restart service when memory leak occurs | Kubernetes liveness probe → automatic restart + alert |
| Manually scale up DB when traffic spikes | Aurora auto-scaling or DynamoDB on-demand mode |
| Manually clear stuck jobs in queue | DLQ with Lambda re-drive automation |
| Copy-paste deployment steps from runbook | Automated deployment pipeline; runbook is only for edge cases |
| Manually check 5 dashboards during incident | Composite alert with auto-investigation report |
| Rotate secrets on a calendar reminder | Secrets Manager automatic rotation |

**Target**: On-call toil < 50% of on-call time. If > 50% is spent on toil, the team cannot spend time on detection/prevention improvements — a death spiral.

### Chaos Engineering (Proactive Reliability)

Don't wait for production to surface failure modes. Inject failures in controlled experiments to validate your observability and incident response.

**Chaos engineering maturity levels**:

| Level | What you test | Example |
|-------|-------------|---------|
| 1. Instance failure | Can we handle loss of one instance? | Kill a pod in Kubernetes; verify zero user impact |
| 2. Dependency failure | What happens when X fails? | Return 500s from payment gateway mock; verify circuit breaker opens |
| 3. Latency injection | Does slow X cause cascading timeouts? | Add 3s latency to auth service; verify timeout propagation |
| 4. Region failure | Can we operate with one region? | Simulate AZ outage; verify failover |
| 5. Data store failure | What happens when DB is unavailable? | Read replica failure; primary failover test |

**Team practice**: Run at least one chaos experiment per quarter per critical service. Document results. Every "surprise" in a chaos experiment is a reliability debt.

### Reliability Review in Architecture Reviews

New features and architectures must include a reliability section before approval:

**Reliability review checklist**:

```
□ How does this fail? List the top 3 failure modes.
□ What observability exists? (Metrics, logs, traces planned?)
□ What alerts will be added? (SLO impact identified?)
□ What is the runbook for each failure mode?
□ How is this rolled out? (Feature flag, canary, incremental?)
□ What is the rollback plan? (< 10 min is the target)
□ Does this change our SLO dependencies? (New downstream → new failure surface)
□ What is the blast radius if this fails entirely?
□ Is there a circuit breaker / graceful degradation?
□ Has a load test been run at production scale?
```

**This review is non-negotiable for SEV-1-class systems.** A principal engineer owns enforcing this gate across teams.

---

## Part 7: Tooling Reference

### The Observable System Stack

```
Instrumentation:
  Code → OpenTelemetry SDK → OTel Collector

Storage:
  Metrics:  Prometheus (self-hosted) | Datadog | CloudWatch | Azure Monitor
  Logs:     Elasticsearch/OpenSearch | Loki | CloudWatch Logs | Splunk
  Traces:   Jaeger | Zipkin | Tempo | Datadog APM | X-Ray | App Insights

Visualization:
  Dashboards: Grafana | Datadog | CloudWatch Dashboards
  Traces:     Grafana Tempo | Jaeger UI | Datadog APM

Alerting:
  Alert manager: Prometheus Alertmanager | Datadog Alerts | CloudWatch Alarms
  Routing:       PagerDuty | OpsGenie | VictorOps
  Notifications: Slack | Teams | Email | SMS

Incident Management:
  Incident bridge: PagerDuty | Incident.io | FireHydrant
  Communication:   Statuspage.io | Atlassian Statuspage
  Post-mortem:     Blameless | Confluence (template) | GitHub Issues

Chaos Engineering:
  Kubernetes: Chaos Monkey | Chaos Mesh | Litmus
  AWS:        AWS Fault Injection Simulator (FIS)
  Network:    Toxiproxy (latency injection in dev/staging)
```

### Observability Cost Management

Observability tooling is not free. At FAANG scale, log ingestion alone can run millions per year.

| Control | Mechanism |
|---------|----------|
| **Log sampling** | Debug/info logs sampled at 10%; error logs at 100% |
| **Trace sampling** | Adaptive sampling; high-error requests always sampled |
| **Metric cardinality** | Avoid high-cardinality labels (user_id, request_id as Prometheus labels = cardinality explosion) |
| **Log retention tiers** | Hot (7 days) → warm (30 days) → cold archive (1 year) |
| **Alert deduplication** | Grouping + inhibition prevents redundant ingestion from alert storms |

**Cardinality anti-pattern** (Prometheus / time-series DB):
```
BAD:  http_requests_total{user_id="u-12345", path="/api/v1/orders"}
      → N unique users = N time series = cardinality explosion

GOOD: http_requests_total{service="orders-api", status="200", endpoint="/api/v1/orders"}
      → Bounded label values; no explosion
```

---

## FAANG Interview Angles

### "How do you build a culture of observability?"

> "I treat observability as a shipping requirement, not a backlog item. MVO (Minimum Viable Observability) is a deploy gate — services without health endpoints, RED metrics, and structured logs with trace correlation don't ship. I socialize the standard through architecture reviews and code review feedback, not through mandates. The cultural shift happens when engineers stop being woken up at 3am because they can't diagnose their own service — then they instrument proactively."

### "How do you reduce MTTR?"

> "MTTR has four components: detect, respond, mitigate, verify. I attack each separately. For detection: SLO burn rate alerts with 1-hour windows catch issues before they're widespread. For response: PagerDuty auto-creates the incident channel and links the runbook — no hunting. For mitigation: every critical service has a rollback path that takes < 10 minutes (feature flags, deploy rollback, traffic routing). For verification: I alert on 'is it resolved' not just 'did the fix happen' — the alert resolves when error rate drops, not when the engineer closes the ticket."

### "Walk me through a major incident you handled."

Structure using SSTAR:
- **Situation**: Scale, severity, business impact
- **Strategy**: How I structured the response (IC roles, communication cadence, diagnostic approach)
- **Task**: What I personally owned (decision to rollback, stakeholder comms, post-mortem)
- **Action**: Specific steps taken with timestamps
- **Result**: MTTR achieved, error budget impact, what changed permanently

### "How do you prevent alert fatigue?"

> "I apply two rules: every alert must be actionable, and every alert must have an owner. Every quarter, we audit alerts: count pages-per-on-call-shift and any alert that auto-resolves without human action is a candidate for removal. The test I apply to every alert: 'If this fires at 3am, can the on-call engineer take an action that fixes it within 30 minutes?' If no, either automate the fix or remove the alert and monitor asynchronously."

---

> **Principal Engineer Framing**: "At the PE level, observability is not a technical implementation — it is an organizational capability. My job is to ensure that when something breaks, anyone on the team can understand what is broken, why it is broken, and how to fix it, without depending on the person who wrote the code. That requires instrumentation standards, diagnostic culture, blameless learning, and continuous investment in reliability work even when features are calling. The test of a mature observability culture is not whether the best engineers can debug — it is whether the newest engineer can handle a SEV-1 alone at 2am using runbooks and dashboards."
