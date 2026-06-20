# Production Readiness Review (PRR)

**Category**: Engineering Operations · Launch Excellence · Service Lifecycle  
**Audience**: Principal / Staff Engineers owning service launches and reliability standards  
**Related**: [Incident Response Playbook](incident-response-playbook.md) · [Observability & CI](observability-incident-continuous-improvement.md)

> "A PRR is a structured gate that answers one question: if this service fails in production tomorrow, can we detect it, diagnose it, and fix it in time to meet our SLOs? If the answer is no, the service is not ready."

---

## What Is a Production Readiness Review?

A PRR is a pre-launch gate conducted for every new service and significant capability change. It verifies that the system has the observability, operational procedures, dependency contracts, and failure handling needed to be operated safely in production.

**When a PRR is required**:

| Scenario | PRR Required? |
|----------|--------------|
| New production service | Yes — full PRR |
| Major feature adding new critical path dependencies | Yes — full PRR |
| Significant traffic increase (>5× current load) | Yes — capacity + failure mode sections |
| New external customer-facing API | Yes — full PRR |
| Internal tooling with no user SLO impact | No — lightweight readiness checklist only |
| Bug fix to existing service | No |

**PRR owner**: The principal or staff engineer responsible for the service. A PRR is not a form to fill — it is a structured conversation between the service owner and the SRE/platform team.

---

## PRR Dimensions

### 1. Architecture and Design

**Goal**: Confirm the design is sound before operational habits are built around a broken architecture.

```
□ Architecture diagram reviewed and approved
□ Data flow documented (what data enters, where it's stored, where it exits)
□ Single points of failure identified and either eliminated or accepted with justification
□ Critical path identified: which calls are in the critical path? What is the latency budget per hop?
□ Dependencies inventoried:
  - What services does this call? (synchronous dependencies)
  - What services consume from this? (downstream impact on failure)
  - What queues, databases, caches does this use?
□ SLO defined for the service (see: SLO Definition Process)
□ Failure modes documented: what happens when each dependency fails?
□ Graceful degradation designed: what is the degraded-but-functional state?
□ Blast radius scoped: if this service fails entirely, what user functionality is lost?
```

**Architecture anti-patterns to catch at PRR**:

| Anti-Pattern | Why It Fails | Mitigation |
|-------------|-------------|------------|
| Synchronous fanout | One request triggers 10+ downstream calls; latency compounds | Async events or caching |
| Shared database between services | Schema changes in one service break another | Service-owned data stores |
| Chatty service (N+1 pattern) | Per-item API calls on lists don't scale | Batch APIs |
| No timeout configured | Slow dependency hangs thread pool | Every external call has a timeout |
| Retry without backoff | Thundering herd on dependency failure | Exponential backoff with jitter |
| Missing circuit breaker | Cascading failure when dependency degrades | Circuit breaker on every external call |

---

### 2. Observability

**Goal**: Confirm the service can be understood from signals alone — without SSH access or source code knowledge.

```
Metrics (required before launch):
□ RED metrics instrumented:
  - Rate: requests per second (total, by endpoint, by status code)
  - Errors: error rate (total, 4xx, 5xx, by endpoint)
  - Duration: P50, P95, P99, P999 latency by endpoint
□ USE metrics for infrastructure:
  - Utilization: CPU%, memory%, disk I/O%, network I/O%
  - Saturation: queue depth, thread pool utilization, connection pool usage
  - Errors: disk errors, OOM kills, restart count
□ Business metrics: ≥1 metric that directly measures business value
  (e.g., orders processed/min, registrations/min, documents indexed/min)
□ Dependency health metrics:
  - Latency and error rate per downstream call
  - Circuit breaker state exposed as a metric
□ Dashboards created:
  - Overview dashboard: RED + USE for the service
  - Dependency dashboard: health of each downstream dependency
  - SLO dashboard: current error budget, burn rate, remaining budget

Logs (required before launch):
□ Structured JSON logs (no unstructured log.Printf)
□ Log fields: timestamp, severity, service, version, trace_id, span_id, request_id
□ Application error logged with: error type, message, relevant context (no PII)
□ Sensitive data confirmed NOT in logs (PII, credentials, payment details)
□ Log levels configured correctly (INFO for normal operations, no DEBUG in production)
□ Log sampling policy defined (debug: 1%, info: 10%, warn/error: 100%)

Traces (required before launch):
□ OpenTelemetry instrumentation added
□ W3C TraceContext headers propagated to all downstream calls
□ Span created for every external call (DB, cache, API, message queue)
□ Span attributes include context useful for debugging (user segment, feature flag, etc.)
□ Traces verified to appear in trace backend for a sample request
□ Sampling rate agreed (default: 10% head-based + 100% for errors)
```

**Minimum Viable Observability gate**: Validate by running a trace through the system and confirming you can answer: Where is the latency? Which dependency is failing? What user was affected?

---

### 3. Alerting and On-Call Readiness

**Goal**: Confirm someone will be woken up if the service fails, and they will know what to do.

```
SLO Alerts:
□ SLI defined and instrumented (what metric represents user experience)
□ SLO agreed with product/business (e.g., 99.9% success rate over 30 days)
□ Multi-window burn rate alerts configured:
  - Tier 1 (page): burn rate > 14.4× over 1h (100% of budget in 2h)
  - Tier 2 (urgent ticket): burn rate > 6× over 6h (100% of budget in 5 days)
  - Tier 3 (sprint): burn rate > 1× over 3 days

Runbooks:
□ Runbook created for every alerting scenario
□ Runbook includes: what the alert means, top 3 causes, fix for each cause, escalation path
□ Runbook link embedded in alert definition (alert fires → runbook link included)
□ Runbook reviewed by at least 2 engineers who will be on-call

On-Call Coverage:
□ Service assigned to an on-call rotation
□ Escalation path defined: primary → secondary → engineering manager → PE/Staff
□ All on-call engineers trained on the service before it launches
□ On-call dry run: simulate an alert and verify the runbook works end-to-end
□ PagerDuty schedule configured; escalation policies verified
```

---

### 4. Capacity and Performance

**Goal**: Confirm the service can handle production traffic, including peak and growth scenarios.

```
Capacity Planning:
□ QPS estimate at launch (P50 day, P95 day, peak hour)
□ QPS at 6 months and 12 months growth projections
□ Resource requirements per instance (CPU, memory) at expected load
□ Instance count for P50 load, P95 load, with headroom
□ Database: rows, storage, IOPS projections at 6 months and 12 months
□ Queue: expected throughput, max lag before SLO impact

Performance Testing:
□ Load test run at 2× expected P95 traffic
□ Soak test run at P50 traffic for 24+ hours (identifies memory leaks, GC pressure)
□ Latency P99 at load within latency budget
□ No errors under normal load (< 0.01% error rate at P95 traffic)
□ Degradation behavior confirmed: at 150% load, does service degrade gracefully or collapse?

Scaling Strategy:
□ Horizontal scaling verified: adding more instances distributes load correctly
□ Auto-scaling policy configured: scale-out trigger, scale-in trigger, min/max instances
□ Database: connection pooling configured; max connections set below DB limit
□ Cache: cache hit rate at expected load; cold start behavior acceptable
□ Queue: consumer scaling policy aligned with producer throughput
```

**Load test standard**: Test until the system breaks, then document at what threshold it breaks and what the failure mode is. This determines the capacity ceiling and informs auto-scaling policy.

---

### 5. Reliability and Failure Handling

**Goal**: Confirm the service handles failures predictably, contains blast radius, and has a tested recovery path.

```
Dependency Failure Handling:
□ Every synchronous downstream call has:
  - Timeout configured (not the framework default)
  - Retry with exponential backoff and jitter
  - Circuit breaker (open after N failures, half-open probe after M seconds)
  - Fallback behavior (serve from cache, return degraded response, fail open/closed per risk)

Data Durability:
□ Write operations: confirmed durable (ack after fsync, not just in memory)
□ Eventual consistency risks documented: what can users see inconsistently and for how long?
□ Data loss scenarios documented: what is the maximum data loss on crash (RPO)?

Recovery:
□ Rollback tested: deploying previous version succeeds and restores previous behavior
□ Recovery time from full restart measured (cold start time)
□ Database: failover to replica tested; failover time measured
□ Multi-region: failover to secondary region tested (if applicable)

Testing:
□ Unit test coverage ≥ 70% for critical paths
□ Integration tests cover happy path + top 3 failure modes
□ Chaos test performed: killed an instance; verified auto-recovery
□ Data: database failover tested; confirmed application reconnects within SLO

```

---

### 6. Security and Compliance

**Goal**: Confirm the service meets the security requirements for its data classification.

```
Authentication and Authorization:
□ All endpoints authenticated (no unauthenticated paths unless explicitly public)
□ Authorization model documented (who can do what)
□ Least privilege: service account has only permissions it needs
□ No shared credentials with other services

Data Handling:
□ Data classification assigned: Public / Internal / Confidential / Restricted
□ PII inventory: what personal data is stored or processed?
□ Encryption at rest: database, object storage
□ Encryption in transit: TLS 1.2+ for all connections; mTLS for service-to-service
□ No credentials in code or config files (use secrets management)
□ No PII in logs (verified in log review step)

Compliance:
□ GDPR/CCPA: is this service subject to data subject rights? Deletion flow designed?
□ PCI DSS: does this service touch payment data? PCI scope reviewed?
□ Audit logging: is access to sensitive data logged with who, what, when?
□ Penetration test: required for services processing payment, health, or auth data

Dependency Security:
□ Dependencies scanned for known CVEs
□ Container image scanned (if containerized)
□ No critical or high CVEs in dependencies at launch
```

---

### 7. Launch and Rollout Plan

**Goal**: Confirm the service can be launched safely with a clear rollback plan.

```
Launch Strategy:
□ Feature flag: can the service be disabled without a deploy?
□ Traffic ramp: launch plan (0% → 1% → 5% → 25% → 100%, with criteria for each step)
□ SLO monitoring: which metrics to watch during ramp
□ Automatic rollback: is rollback triggered automatically if error rate spikes?
□ Human gate: who approves each traffic ramp step?

Communication:
□ Stakeholders notified of launch timing
□ Support team briefed on new feature behavior and known limitations
□ Status page updated if this is a public-facing launch
□ On-call team notified: heightened awareness window for 24h after launch

Post-Launch Checklist (24h after launch):
□ Error rate reviewed: within SLO?
□ Latency reviewed: within target?
□ Resource usage reviewed: CPU/memory within projections?
□ No unexpected error patterns in logs
□ No on-call alerts fired (or if they did, root cause addressed)

Post-Launch Checklist (7 days after launch):
□ SLO error budget: how much consumed in week 1?
□ Capacity projections: actual vs. projected resource usage
□ Alert tuning: any alerts too noisy or too quiet?
□ Runbook gaps: anything that happened that wasn't covered?
□ PRR retrospective: what did the PRR miss? Update the PRR template.
```

---

## PRR Process

### Timeline

```
T-4 weeks: PRR doc created by service owner; shared with SRE/platform team
T-3 weeks: SRE review of architecture and failure modes; feedback provided
T-2 weeks: Load testing completed; observability implemented; feedback addressed
T-1 week:  PRR review meeting (60 min): service owner + SRE + PE/Staff
            Outcome: Approved / Conditionally Approved (with P1 blockers) / Rejected
T-0:        Launch with monitoring
T+7 days:  Post-launch review
```

### PRR Meeting Agenda (60 minutes)

```
0-5 min:   Service owner walks through architecture diagram
5-15 min:  Failure mode review: "What are the top 3 ways this service can fail?"
15-25 min: Observability demo: "Show me a trace through the system. Show me the error rate dashboard."
25-35 min: Runbook walkthrough: "Walk me through what you'd do if this alert fires at 3am."
35-45 min: Load test results: "Show me the performance under 2× expected load."
45-55 min: Security and compliance sign-off
55-60 min: Decision: Approved / Conditional / Rejected; blockers documented
```

### PRR Outcomes

| Outcome | Meaning | Next Step |
|---------|---------|-----------|
| **Approved** | All criteria met | Launch on schedule |
| **Conditionally Approved** | P2/P3 gaps exist; no blockers | Launch with documented follow-up items due within 2 weeks |
| **Approved with P1 blocker** | One or more blockers that must be fixed before launch | Fix blockers; abbreviated re-review |
| **Rejected** | Fundamental gaps in observability, reliability, or security | Significant work needed; re-review in 2-4 weeks |

---

## PRR for Existing Services (Brownfield)

When inheriting or significantly changing an existing service, run a lightweight PRR:

```
Brownfield PRR checklist:
□ Is there an existing runbook? Is it accurate?
□ Is there an SLO defined? Is it being measured?
□ Are alerts configured? Are they actionable?
□ What are the top 3 failure modes? Are they handled?
□ When was the last incident? Was there a post-mortem?
□ What is the current on-call toil level? Is it sustainable?
```

---

## FAANG Interview Framing

**"How do you ensure a new service is ready for production?"**

> "We use a Production Readiness Review as a formal gate. The PRR has six dimensions: architecture soundness, observability completeness, alerting readiness, capacity validation, reliability testing, and security sign-off. I've learned that the most common gaps at launch are missing runbooks — the service has alerts but no documented fix procedure — and untested failure modes, where the circuit breaker is configured but nobody verified it actually opens when the dependency fails. The PRR catches these before users do. For a principal engineer, the PRR is also a forcing function: you can't launch a service you can't explain to someone else. If you can't describe the top three failure modes and what happens to users in each case, the service isn't ready."
