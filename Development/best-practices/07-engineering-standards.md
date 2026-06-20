# Engineering Standards — FAANG Production Practices

## Overview
Beyond individual best practices, FAANG engineering organisations operate on shared standards that make hundreds of engineers working in parallel produce coherent, maintainable systems. This document covers the cross-cutting engineering disciplines that principal engineers are expected to model and enforce: testing strategy, security-by-default, dependency management, documentation standards, incident management, and the development workflow disciplines that separate senior from principal engineer work.

---

## Testing Strategy

### Test Pyramid at FAANG Scale

```
              ┌──────────────┐
              │   E2E / UI    │  5–10%  — critical user journeys; CI runs weekly
              ├──────────────┤
              │  Integration  │  20–30% — repository tests, external adapter tests
              ├──────────────┤
              │    Contract   │  5–10%  — consumer-driven contracts (Pact)
              ├──────────────┤
              │     Unit      │  60–70% — fast; domain logic; no infrastructure
              └──────────────┘

Key metric: Unit tests run in < 30 seconds; full CI suite in < 10 minutes
```

### Testing Standards

| Test type | What it tests | Infrastructure | Speed | Coverage target |
|---|---|---|---|---|
| **Unit** | Domain model, business logic, algorithms | None (in-memory fakes) | < 1ms per test | 80%+ on new code |
| **Integration** | Database adapters, HTTP clients, message consumers | Real DB / real broker (Docker) | 100ms–5s | Key adapters covered |
| **Contract** | API contract between consumer and provider | Pact broker | 10ms (offline) | All inter-service calls |
| **E2E** | Full user journey | Full deployed environment | 30s–5min | 5–10 critical flows |

### Test Independence Rules

```java
// WRONG: tests depend on each other
@Test
void test1_create_order() { /* creates order with ID 123 */ }

@Test
void test2_submit_order() {
    // WRONG: assumes test1 ran first and left order ID 123
    submitService.submit(new OrderId("123"));
}

// CORRECT: each test creates its own state
@Test
void submit_order_transitions_to_submitted_status() {
    // Arrange: test owns its data
    OrderId id = createDraftOrder();
    
    // Act
    submitService.submit(id);
    
    // Assert
    assertThat(orderRepo.findById(id)).hasStatus(SUBMITTED);
    
    // Cleanup: either @Transactional rollback or explicit cleanup
}
```

### Test Naming: The Living Documentation Standard

```java
// Every test name should read as a specification:
// "should [expected behaviour] when [condition]"

@Test void should_reject_empty_order_when_submitting()
@Test void should_raise_OrderSubmitted_event_when_order_is_submitted()
@Test void should_charge_correct_amount_when_order_has_discount()
@Test void should_throw_InsufficientInventoryException_when_stock_is_zero()
```

---

## Security-by-Default Standards

### OWASP Top 10 Engineering Controls

| Threat | Engineering control |
|---|---|
| **A01 Broken Access Control** | Authorisation check at every API handler; deny by default; use RBAC/ABAC; integration tests for authorisation |
| **A02 Cryptographic Failures** | TLS everywhere (no HTTP); strong algorithms only (AES-256, RSA-2048+); secrets in Secrets Manager; never log sensitive data |
| **A03 Injection** | Parameterised queries; ORMs with parameter binding; input validation; never string-interpolate SQL or shell commands |
| **A04 Insecure Design** | Threat modelling for new features; security review for public APIs; principle of least privilege |
| **A05 Security Misconfiguration** | IaC for all infrastructure; no default credentials; security headers in all HTTP responses; remove unused features |
| **A06 Vulnerable Components** | Dependabot / Snyk in CI; block on critical CVEs; weekly dependency updates |
| **A07 Auth & Session Failures** | JWT with short expiry (15min access / 7d refresh); secure cookie flags; MFA for admin |
| **A08 Software Integrity Failures** | Signed artifacts; verified container images; supply chain security (SLSA) |
| **A09 Logging & Monitoring Failures** | Log all auth events; alert on anomalies; correlate across services |
| **A10 SSRF** | Validate all URLs; block internal IP ranges; use allowlists for outbound calls |

### Secure Coding Checklist

```java
// Input validation at API boundary
@PostMapping("/orders")
public ResponseEntity<OrderResponse> createOrder(@Valid @RequestBody CreateOrderRequest request) {
    // @Valid triggers Bean Validation — rejects invalid input before business logic
}

// Parameterised queries — never string interpolation
// WRONG:
String sql = "SELECT * FROM orders WHERE customer_id = '" + customerId + "'";  // SQL injection

// CORRECT:
String sql = "SELECT * FROM orders WHERE customer_id = ?";
jdbcTemplate.query(sql, customerId);

// Authorisation at the resource level, not just authentication
@GetMapping("/orders/{id}")
public ResponseEntity<OrderResponse> getOrder(@PathVariable String id, Principal principal) {
    Order order = orderService.findById(new OrderId(id));
    
    // WRONG: check only that user is authenticated
    // CORRECT: check that user owns this order
    if (!order.customerId().equals(principal.getName())) {
        throw new AccessDeniedException("Order " + id + " not found");
        // Return 403 Forbidden (disguised as 404 to prevent ID enumeration)
    }
    
    return ResponseEntity.ok(toResponse(order));
}
```

### Threat Modelling (STRIDE)

For new features with security implications:

| Threat | Description | Example | Mitigation |
|---|---|---|---|
| **Spoofing** | Impersonating another user | Forge JWT token | Strong signing key; short expiry; token rotation |
| **Tampering** | Modifying data in transit or at rest | Change order total | TLS; signed payloads; database integrity constraints |
| **Repudiation** | Denying you performed an action | "I didn't place that order" | Audit log; request signatures; immutable event log |
| **Information Disclosure** | Accessing data you shouldn't | Read another user's order | Authorisation checks; PII encryption; log masking |
| **Denial of Service** | Making the system unavailable | Flood API with requests | Rate limiting; circuit breakers; WAF |
| **Elevation of Privilege** | Getting more access than authorised | Regular user accesses admin API | RBAC; deny by default; privilege separation |

---

## Dependency Management Standards

### Dependency Review Criteria

Before adding a dependency, answer:

1. **Is it actively maintained?** (last commit < 6 months; responsive to CVEs)
2. **Is it necessary?** (could we implement the 20 lines we actually need without a library?)
3. **What is the transitive dependency tree?** (`mvn dependency:tree` / `gradle dependencies`)
4. **Does it have known CVEs?** (check Snyk, NVD)
5. **What is the license?** (MIT/Apache-2 OK; GPL may conflict with commercial use)

### Dependency Update Policy

```
Critical CVE (CVSS >= 9.0):   update within 48 hours; emergency patch if needed
High CVE (CVSS 7.0–8.9):     update within 1 sprint (2 weeks)
Medium CVE (CVSS 4.0–6.9):   update within 1 quarter
Low CVE (CVSS < 4.0):        update in next dependency batch update
Non-security updates:         batch monthly; minor version weekly via Dependabot
```

---

## Documentation Standards

### Code-Level Documentation Policy

**Default: no comments**. Code is self-documenting when:
- Names are accurate and descriptive
- Functions do one thing
- Abstractions match the domain

**Write a comment only for**:
- A non-obvious constraint or invariant: "The order of these two calls matters: X must be called before Y because Z"
- A workaround for an external bug: "This timeout is doubled because of Stripe's clock skew issue (STR-12345)"
- A subtle algorithm: explain the mathematical invariant, not what the loop does

### API Documentation (OpenAPI)

```yaml
# Every public API endpoint must have a complete OpenAPI spec
/orders/{id}/submit:
  post:
    summary: Submit an order for fulfilment
    description: |
      Transitions an order from DRAFT to SUBMITTED status.
      Payment authorisation is initiated asynchronously.
      Idempotent when called with the same Idempotency-Key header.
    parameters:
      - name: id
        in: path
        required: true
        schema:
          type: string
          pattern: '^ord_[a-zA-Z0-9]{8}$'
    requestBody:
      required: true
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/SubmitOrderRequest'
    responses:
      '202':
        description: Order submission accepted; processing asynchronously
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SubmitOrderResponse'
      '409':
        description: Order is not in DRAFT status
        content:
          application/problem+json:
            schema:
              $ref: '#/components/schemas/Problem'
```

### Architecture Decision Records (ADRs)

For every significant technical decision, an ADR must be written and merged:

```markdown
# ADR-0042: Use Cursor-Based Pagination for Orders API

**Status**: Accepted
**Date**: 2025-01-15

## Context
The Orders API /orders endpoint will return potentially millions of records.
Offset-based pagination degrades to O(N) for large offsets.
The client needs stable pagination that handles concurrent inserts correctly.

## Decision
Use cursor-based pagination (opaque base64-encoded cursor containing last ID + sort field)
rather than offset/limit pagination.

## Consequences
**Positive**: O(1) for any page position; stable under concurrent inserts; 
no "phantom row" problem.
**Negative**: Cannot jump to arbitrary page; total count not available 
without full scan; client must store cursor between requests.

## Alternatives Considered
Offset pagination: rejected for performance and stability reasons above.
Keyset pagination with exposed sort keys: rejected because exposing database IDs 
as cursors leaks implementation details.
```

---

## Incident Management Standards

### Severity Classification

| Severity | Customer impact | Examples | On-call response |
|---|---|---|---|
| **P1** | All users affected; core functionality down | Payment processing down; login broken; data loss | Page immediately; 5-min acknowledgement; all hands |
| **P2** | Significant user subset affected or core feature degraded | 30% error rate; search unavailable; slow checkout | Page on-call; 15-min acknowledgement |
| **P3** | Minor impact; workaround available | Non-critical feature broken; elevated latency (SLO not breached) | Slack notification; next business day |
| **P4** | No current user impact; potential future risk | Elevated error rate in test; dependency deprecation warning | JIRA ticket; sprint planning |

### Incident Response Lifecycle

```
Detection:    Automated alert → on-call pager (PagerDuty)
              OR customer report → support ticket → triage → page if P1/P2

Triage:       On-call acknowledges in PagerDuty
              Creates incident Slack channel: #incident-YYYY-MM-DD-short-description
              Posts initial status: "Investigating elevated error rate in payment service"
              Initial severity assessment within 5 minutes

Mitigation:   Priority: restore service, not find root cause
              Rollback if recent deploy (< 2 hours ago)
              Disable feature flag if feature-related
              Scale up if resource exhaustion
              
Communication:
              P1: status page update every 15 minutes
              P2: status page update every 30 minutes
              Internal: #incident channel updates; @oncall engineering group
              
Resolution:   All metrics back to baseline; error rate at SLO level
              Verify with 15-minute green window before declaring resolved
              Update status page with "Resolved"

Post-Incident:
              Blameless post-mortem within 48 hours for P1; 1 week for P2
              Timeline, root cause, contributing factors, action items
              Action items in JIRA with owner and due date
```

### Blameless Post-Mortem Format

```markdown
# Incident Post-Mortem: [Short Title]

**Severity**: P1  
**Date**: 2025-01-15  
**Duration**: 42 minutes (10:23 UTC – 11:05 UTC)  
**Author**: [incident commander]  
**Reviewers**: [team members]

## Impact
- 18% of checkout attempts failed (estimated ~240,000 failed transactions)
- 0 data loss events
- Revenue impact: ~$850k in failed transactions (not lost; users retried successfully post-resolution)

## Timeline
| UTC | Event |
|---|---|
| 10:21 | Deployment of payments-service v1.5.2 completed |
| 10:23 | PagerDuty alert: payment error rate > 1% |
| 10:25 | On-call acknowledges; incident channel created |
| 10:31 | Root cause identified: connection pool exhaustion |
| 10:47 | Rollback initiated |
| 11:05 | Error rate < 0.1%; incident resolved |

## Root Cause
Thread pool size was reduced from 50 to 10 in v1.5.2 as part of 
"resource optimisation." Under normal load, 10 threads were insufficient.

## Contributing Factors
- No load testing of the new thread pool configuration before production
- Alerting on thread pool saturation not in place
- Change was not flagged in review as performance-impacting

## What Went Well
- Alert fired within 2 minutes of deployment
- Root cause identified within 6 minutes of acknowledgement
- Rollback was clean and immediate

## Action Items
| Action | Owner | Due |
|---|---|---|
| Add thread pool saturation alert | Platform team | 2025-01-22 |
| Add load test gate to deployment pipeline for resource-impacting changes | DevOps | 2025-02-01 |
| Add PR checklist item for resource configuration changes | Engineering lead | 2025-01-17 |
```

---

## Development Workflow Standards

### Git Workflow

```
main ← production-deployed, always green
  ↑
feature/JIRA-1234-add-bulk-order-export ← short-lived (< 5 days)
  
Rules:
  - Branch from main; merge to main (trunk-based development preferred)
  - Feature branches live < 5 days; longer → feature flag or modular commits
  - No direct commits to main; all changes via pull request
  - Squash commits for small changes; rebase for meaningful commit history
  - Commit messages: [JIRA-1234] imperative sentence what the change does
  
Commit message format:
  [JIRA-1234] Add cursor-based pagination to orders API
  
  Switches from offset to cursor pagination to support the growing orders
  table (>10M rows). Offset queries were taking >2s at p99.
  
  Breaking change for pagination clients: offset/limit params are removed.
  Migration guide in JIRA-1234.
```

### Pull Request Standards

```markdown
## Pull Request Template

### What
[1-3 sentences: what does this change do?]

### Why
[1-3 sentences: what problem does it solve? Link to JIRA ticket]

### How
[Optional: explain non-obvious implementation decisions]

### Testing
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual testing steps: [describe how to verify the change]

### Rollout
- [ ] Feature flag: `new_bulk_export_enabled` (currently OFF)
- [ ] Database migration: non-blocking (no table locks)
- [ ] Backwards compatible with deployed version
- [ ] Metrics/alerts added for new functionality

### Links
- JIRA: [JIRA-1234]
- Design doc: [link]
- Related PRs: [link]
```

---

## On-Call and Production Readiness

### Production Readiness Checklist (before launching a new service)

```
Observability:
  ☐ RED metrics instrumented (rate, errors, duration)
  ☐ Distributed tracing enabled (OpenTelemetry)
  ☐ Structured logging with correlation IDs
  ☐ Health endpoints: /health/live, /health/ready
  ☐ Dashboards created (RED overview + dependency health)
  ☐ SLO defined and SLO burn rate alerts configured

Reliability:
  ☐ Circuit breakers on all external dependencies
  ☐ Retry with exponential backoff + jitter
  ☐ Timeout configured on all outbound calls
  ☐ Graceful shutdown (drains in-flight requests, closes connections)
  ☐ Horizontal scaling validated under load test

Security:
  ☐ Authentication required on all endpoints (allowlist exceptions documented)
  ☐ Authorisation checks at resource level
  ☐ Secrets in Secrets Manager (not environment variables set at deploy time)
  ☐ TLS on all communication
  ☐ No sensitive data in logs

Operations:
  ☐ On-call runbook written and linked from alert annotations
  ☐ Deployment runbook: deploy, verify, rollback procedure
  ☐ Data migration plan (if applicable): non-blocking; tested on production-size dataset
  ☐ Capacity estimate: expected RPS, storage growth, cost per month

Documentation:
  ☐ README with service purpose, architecture, local setup
  ☐ API documentation (OpenAPI spec)
  ☐ Architecture Decision Records for key decisions
  ☐ On-call runbooks
```

---

## Trade-offs

| Standard | Benefit | Cost | When to relax |
|---|---|---|---|
| **100% PR-based changes** | Reviewable history; quality gate | Slower for hotfixes | P1 incident: allow direct commit with post-incident review |
| **ADR for every decision** | Institutional memory; clear rationale | Time overhead | Minor decisions; follow-up tickets acceptable |
| **Blameless post-mortem for every P2+** | Learning culture; recurrence prevention | Time overhead (2–4 hours per incident) | — never skip for P1; P3/P4 → lightweight retro |
| **Test coverage gates (80%)** | Forces coverage discipline | Slows initial development | New services in early prototyping phase; define gate before GA launch |

---

## FAANG Interview Points

**"How do you build a culture of engineering excellence in a team that has accumulated significant technical debt?"**: Start with measurement, not opinion — run a codebase health assessment (coverage, lint violations, dependency age, MTTR). Present the data, not complaints. Then: three levers. First: create a 20% time budget for quality work — not a separate "tech debt sprint" (which gets cancelled) but integrated into every sprint. Second: use pull requests as teaching moments — the principal engineer's review comments model the standard. Third: make quality visible — add code quality metrics to team dashboards; celebrate improvements. The cultural shift from "we're too busy to fix it" to "quality is velocity" takes 6–12 months and requires management sponsorship.

**"How do you run an incident post-mortem that actually prevents recurrence?"**: Four elements. First: blameless framing — the goal is to understand the system, not punish individuals; people made reasonable decisions with the information they had. State this explicitly at the start. Second: accurate timeline — reconstruct from logs, not memory; what happened, not what should have happened. Third: contributing factors, not root cause — systems fail due to multiple concurrent factors; finding "the root cause" is usually wrong and stops the analysis too early. Fourth: action items with owners and due dates — not vague "we should add monitoring" but "Platform team adds thread pool saturation alert to order-service by January 22." Track completion in the next sprint review.

**"What's the minimum set of practices a new service team needs before going to production?"**: I use a production readiness checklist with four pillars. Observability: RED metrics, distributed tracing, structured logging with trace IDs, SLO-based alerting. Reliability: circuit breakers on all external deps, timeout on all outbound calls, graceful shutdown. Security: authentication on all endpoints, secrets in Secrets Manager, TLS everywhere, no PII in logs. Operations: on-call runbook linked from every alert, deployment/rollback procedure documented, load test done at 2× expected peak. A team that can check all 20 items is operationally ready. A team that can't explain one of the checklist items is a production incident waiting to happen.
