# Sample Roadmap: Monolith → Microservices Migration

## Context

**Organization**: 500-engineer company, 10-year-old Rails monolith, 50M active users.

**Why migrate?**
- Deployment frequency: 1×/week max (entire monolith deploys together; one team's bug blocks all)
- Mean deploy time: 3.5 hours (full test suite + deploy to all regions)
- Scaling: entire monolith must scale even when only the payments service needs more capacity ($800K/year in wasted compute)
- Team autonomy: teams of 8 engineers each own 10–15 features but cannot deploy independently
- On-call: every incident requires knowing the full monolith (no bounded service ownership)

**Target state**:
- 20+ bounded microservices, each deployable independently
- Mean deploy time < 15 minutes per service
- Teams deploy their service without coordination with other teams
- Services scale independently; 60% reduction in compute waste

**What this roadmap is not**: a commitment to decompose everything. The strangler fig pattern means the monolith shrinks incrementally; some non-critical modules may remain in the monolith permanently if the cost of extraction exceeds the benefit.

---

## Migration Strategy: Strangler Fig Pattern

Do not rewrite the monolith. Extract services one domain at a time, routing traffic away from the monolith incrementally.

```
Phase 0: Before migration
  All traffic → Monolith → all domains

Phase 1: Extract first service
  Traffic → API Gateway ──► Monolith (most domains)
                       └──► Payment Service (new, extracted)

Phase 2: More extractions
  Traffic → API Gateway ──► Monolith (shrinking)
                       ├──► Payment Service
                       ├──► User Auth Service
                       └──► Search Service

Phase N: Monolith is vestigial
  Traffic → API Gateway ──► Service A, B, C ... N
                       └──► Monolith (non-critical legacy only)
```

**Why not rewrite?**
- Big-bang rewrites have a 70%+ failure rate on large systems (see: Netscape 6, HealthCare.gov v1)
- Strangler fig delivers value incrementally — each extracted service is in production in weeks, not years
- The monolith keeps running; there is no "cutover day" that can go catastrophically wrong

---

## Service Extraction Sequencing Criteria

Not all services should be extracted in the same order. Sequence by:

| Criterion | Weight | Rationale |
|-----------|--------|-----------|
| Business value of independent deployment | High | Highest ROI services extracted first |
| Domain boundary clarity | High | Well-bounded domains are cheaper to extract |
| Data coupling to other domains | High (inverse) | Highly coupled data = expensive to extract |
| Team ownership clarity | Medium | One team clearly owns this domain = smoother extraction |
| Blast radius if extraction fails | Medium (inverse) | Start with non-critical; build skill before touching payments |
| Dependency on shared libraries | Low | Can be refactored over time |

---

## Phase Structure

### Phase 0: Foundation (Months 1–3)

**Goal**: build the infrastructure that all future services will rely on. Do not extract any services yet.

**Work items**:

| Item | Detail |
|------|--------|
| API Gateway | Kong or AWS API Gateway — all traffic enters here; routing rules enable strangler fig pattern |
| Service template | Dockerfile, Kubernetes manifests, CI/CD pipeline, health check, logging/metrics instrumentation |
| Service registry | Backstage catalog for all current and future services |
| Observability stack | Distributed tracing (Jaeger), metrics (Prometheus), logs (ELK) — must exist before services do |
| Data isolation pattern | Decide: each service owns its DB schema. Define migration tooling (Flyway per service). |
| Contract testing | Pact or Spring Cloud Contract — prevent API incompatibilities as services multiply |
| Shared library strategy | What is shared (auth middleware, logging, retry clients)? Package as internal SDK. |

**Why Phase 0 first**: every service extraction reuses this foundation. Building it once, used 20+ times, is the highest-leverage investment.

**Risk**: teams get impatient and start extracting services before foundation is ready. This creates 20 different approaches to observability, secrets, and deployment. Enforce the sequence.

---

### Phase 1: Extract Low-Risk Boundary Services (Months 3–9)

**Criteria for Phase 1 candidates**: clear domain boundary, low data coupling, non-critical to revenue if degraded, one team clearly owns it.

**Selected services for Phase 1**:

```
1. Notification Service
   Rationale: purely outbound (email/SMS/push), no inbound dependencies, 
              one team owns it, monolith calls it via a single interface
   Complexity: LOW
   Data: owns its own notification_logs table (easy to extract)
   Team: Notifications team (6 engineers)
   
2. User Preferences Service
   Rationale: read-heavy, clear bounded context, 
              feature flags and settings — no revenue-critical path
   Complexity: LOW-MEDIUM
   Data: preferences table — some coupling with user table (solve with API contract)
   Team: Growth team (shared ownership, appoint DRI)
   
3. Search Service
   Rationale: Elasticsearch-backed, mostly read-only, 
              can fail gracefully (fall back to DB search)
   Complexity: MEDIUM
   Data: search index fully independent of monolith DB
   Team: Search team (8 engineers)
```

**Per-service extraction process**:

```
Step 1: Define the contract (API + events) — document before writing a line of code
Step 2: Build the new service using the Phase 0 service template
Step 3: Deploy new service to production (serving 0% traffic)
Step 4: Shadow mode — monolith handles requests, new service processes copies (compare responses)
Step 5: Canary — route 5% of traffic to new service, monitor error rate + latency
Step 6: Progressive rollout — 25% → 75% → 100%
Step 7: Monolith code path disabled (kept for 30-day rollback window)
Step 8: Monolith code deleted after 30 days of stable production traffic
```

**Step 4 (shadow mode) is non-negotiable** for anything touching user data. It catches behavioral differences before real users are affected.

---

### Phase 2: Extract Core Domain Services (Months 9–18)

**Criteria for Phase 2**: higher value, higher complexity, require data migration planning.

**Selected services for Phase 2**:

```
1. User Authentication / Authorization
   Rationale: every service needs auth; extracting it into a shared service 
              reduces duplication and creates a single policy enforcement point
   Complexity: HIGH (every part of the monolith depends on auth context)
   Data: users table, sessions table — massive, heavily coupled
   Approach: extract auth first at the API layer (new endpoints),
             migrate session storage to Redis, migrate users table last
   Team: Auth Platform team + all consuming teams (coordination intensive)
   Timeline: 4 months

2. Order Management Service
   Rationale: highest-traffic domain, scaling independently saves $300K/yr in compute
   Complexity: HIGH (complex state machine, many monolith touch points)
   Data: orders, order_items, order_history — requires careful dual-write phase
   Approach: expand-contract data migration; event-driven order state machine
   Team: Commerce team (10 engineers)
   Timeline: 5 months
   
3. Inventory / Catalog Service
   Rationale: read-heavy, can use read replica approach during migration
   Complexity: MEDIUM-HIGH
   Data: products, inventory tables — coupled with orders (foreign keys)
   Approach: break FK dependency first (application-level referential integrity),
             then extract
   Team: Catalog team (8 engineers)
   Timeline: 4 months
```

**Data migration pattern for Phase 2 (dual-write)**:

```
Week 1–4:   Expand — new service writes to its own DB; monolith still writes to shared DB
            Monolith reads from monolith DB (no change in production behavior)
            
Week 4–8:   Dual write — monolith writes to BOTH its DB AND new service's DB
            Consistency check job validates both are in sync
            
Week 8–12:  Read migration — route 10% of reads to new service; validate responses
            Progressively increase read % (25% → 75% → 100%)
            
Week 12–16: Write cutover — all writes go to new service; monolith reads from new service
            
Week 16+:   Contract — remove dual-write; monolith no longer owns this data
```

---

### Phase 3: Extract Revenue-Critical Services (Months 18–30)

**Only begin Phase 3 when**: Phase 1 and Phase 2 services have been stable in production for 3+ months, the team has demonstrated extraction competency, and observability is mature enough to detect subtle regressions.

**Selected services for Phase 3**:

```
1. Payment Processing Service
   Rationale: highest blast radius; extract last after team is expert at the process
   Complexity: VERY HIGH (PCI-DSS compliance, financial reconciliation, idempotency requirements)
   Data: payments, refunds, payment_methods — PCI data requires separate storage
   Special: requires dedicated security review, PCI-DSS scoping, external penetration test
   Team: Payments team (12 engineers) + external security consultant
   Timeline: 6 months

2. Pricing / Promotions Engine  
   Rationale: high business logic complexity, A/B testing requirements
   Complexity: HIGH
   Data: pricing rules, promotions — moderate coupling with orders
   Team: Revenue team (8 engineers)
   Timeline: 4 months
```

---

## Risk Register

| Risk | Phase | Probability | Impact | Mitigation |
|------|-------|-------------|--------|------------|
| Data consistency during dual-write | 2, 3 | Medium | High | Automated consistency check job; reconciliation alerts |
| Performance regression in new service vs. monolith | All | Medium | Medium | Shadow mode mandatory; performance baseline before cutover |
| Distributed tracing blind spots | All | High | Medium | Mandate OpenTelemetry in Phase 0 service template |
| Team resists extraction (prefers monolith) | 1, 2 | High | High | Show velocity improvement data from Phase 1 extractions |
| Shared DB becomes bottleneck during dual-write | 2, 3 | Medium | High | Connection pooling; read replica for dual-write reads; time-box dual-write to < 8 weeks |
| Contract drift between services | All | High | High | Pact contract tests in all service CI pipelines; break on contract violation |
| Monolith accrues new features during migration | All | Very High | High | Feature freeze on monolith domains being extracted; new features go into new services |

**Monolith feature freeze** is the most important cultural rule: **no new features are added to the portion of the monolith being extracted**. Without this, you are chasing a moving target. Enforce it with code ownership rules — new PRs in extraction-target modules require platform team approval.

---

## Success Metrics Per Phase

| Phase | Metric | Target |
|-------|--------|--------|
| Phase 0 | Service template available; all infra ready | Week 10 |
| Phase 1 | 3 services extracted and stable in prod | Month 9 |
| Phase 1 | Each extracted service deploys independently | Demonstrated ≥ 3 times each |
| Phase 2 | Auth service handling 100% of auth traffic | Month 18 |
| Phase 2 | Order management independent; compute cost reduced | Month 18 |
| Phase 3 | Payments service fully extracted; PCI scope reduced | Month 30 |
| Overall | 20+ services in production; monolith < 30% of original code | Month 30 |
| Overall | Deployment frequency per service: 5×/week (from 1×/week org-wide) | Month 30 |

---

## What Does NOT Get Extracted

| Module | Reason to Keep in Monolith |
|--------|---------------------------|
| Admin dashboard (internal tool) | Low value to extract; only used by 20 employees |
| Legacy reporting engine | Scheduled batch jobs; no user-facing SLO; rewrite in place during Phase 3 |
| Feature flag evaluation | Moving to external flag service (LaunchDarkly) — not worth extracting into its own microservice |
| Old file export pipeline | Rarely used; scheduled for deprecation after new export service in Phase 2 |

---

## FAANG Interview Callouts

**Q: How do you handle a database that has tables owned by 5 different future services, all with foreign key relationships?**

This is the hardest part of monolith decomposition. Sequence:

1. **Identify** the FK relationships — draw the data dependency graph
2. **Break FKs at the application layer** first: remove DB-level foreign keys, enforce referential integrity in code, add compensating validation
3. **Dual-write phase**: during extraction, write to both locations with a reconciliation job
4. **Accept eventual consistency**: distributed systems cannot have strong consistency across service boundaries. Determine which consistency model each relationship can tolerate (eventual OK for notifications, strong required for payments)
5. **Saga pattern** for multi-service transactions: choreography (event-driven) or orchestration (central coordinator) — pick based on complexity

Never try to maintain cross-service foreign keys. That's a distributed monolith — you've added the complexity of microservices without the benefits.

**Q: Six months into the migration, a VP says "this is taking too long and costing too much." How do you respond?**

Show the delivered value, not just the remaining work:

"We've extracted 3 services. The notification service now deploys 40× per week instead of being blocked by monolith release cycles. The search service scaled independently during last month's traffic spike, saving $60K vs. scaling the full monolith. The auth service extraction reduced cross-team coupling for 8 teams.

The remaining 17 services will deliver similar independence. The order management extraction alone is projected to reduce compute costs by $300K/year. At current velocity, the next 12 months will exceed the ROI of the first 6. What specific outcome are you not seeing that you expected by now?"

This reframes from "behind schedule" to "delivering on value" while opening the door to scope or priority adjustment.
