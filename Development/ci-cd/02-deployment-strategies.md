# Deployment Strategies

## The Core Problem

Every deployment is a controlled risk. You're changing production state while real users are sending requests. The question is not *if* something will go wrong, but *how quickly can you detect and recover.*

**Principal framing**: choose a deployment strategy based on:
- **Blast radius** if it fails (how many users are affected?)
- **Detection speed** (how fast do you know it's bad?)
- **Recovery time** (how fast can you revert?)
- **Infrastructure cost** (how much extra capacity does this require?)

---

## Strategy Comparison Matrix

| Strategy | Blast Radius | Detection Speed | Recovery Time | Infra Cost | Complexity |
|----------|-------------|-----------------|---------------|------------|------------|
| Recreate (stop → start) | 100% | Fast | Minutes (redeploy) | Low | Very Low |
| Rolling Update | Partial (grows over time) | Slow | Minutes (stop rollout) | Low | Low |
| Blue-Green | 0% until cutover, then 100% | Fast (after cutover) | Seconds (DNS/LB flip) | 2× capacity | Medium |
| Canary | % of traffic | Fast | Seconds (re-route traffic) | Low overhead | High |
| Shadow/Dark Launch | 0% (no user impact) | N/A | N/A (offline) | 2× processing | High |
| A/B Testing | % of users (by segment) | Slow (need stats significance) | Moderate | Low overhead | Very High |

---

## Recreate (Big Bang)

```
v1 ─────────── DOWN ─── v2 ────────────
                  │
              downtime window
```

**When to use**: dev/staging environments, services with no users during maintenance window, data migrations that require schema exclusivity.

**Never use in production** unless you have a legitimate maintenance window and users are notified. Even then, design toward zero-downtime.

---

## Rolling Update

```
t=0:  [v1][v1][v1][v1][v1]  (5 replicas)
t=1:  [v2][v1][v1][v1][v1]  (1 upgraded)
t=2:  [v2][v2][v1][v1][v1]
t=3:  [v2][v2][v2][v1][v1]
t=4:  [v2][v2][v2][v2][v1]
t=5:  [v2][v2][v2][v2][v2]  (done)
```

**Key parameters** (Kubernetes):
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%       # how many extra pods during rollout
    maxUnavailable: 0   # never reduce below desired count (zero-downtime)
```

**Problem**: during rollout, v1 and v2 serve traffic simultaneously. Your API must be **backward compatible** for the duration of the rollout. This is often the hardest constraint.

**API compatibility rules during rolling deploy**:
- Adding a new field: safe (consumers ignore unknown fields)
- Removing a field: unsafe — some v1 pods may still be running
- Changing field semantics: unsafe
- Adding a new endpoint: safe
- Removing an endpoint: unsafe

**Rollback**: `kubectl rollout undo` — triggers a rolling update back to v1. Fast, but not instantaneous.

---

## Blue-Green Deployment

```
                         ┌─────────────┐
                    ┌──► │  BLUE (v1)  │ ◄── currently live
Load Balancer       │    └─────────────┘
(DNS / LB rule)    ─┤
                    │    ┌─────────────┐
                    └──► │ GREEN (v2)  │ ◄── deploy & warm up here
                         └─────────────┘
                                │
                   flip LB ─────┘   ← atomic, ~0ms
```

**Steps**:
1. Deploy v2 to green (blue still serves 100% traffic)
2. Run smoke tests, warm up caches, verify health checks on green
3. Flip load balancer to green (atomic, sub-second)
4. Keep blue alive for rollback window (15–60 minutes)
5. Decommission blue

**Rollback**: flip LB back to blue. Seconds. No redeploy needed.

**Key challenges**:

1. **Database migrations**: if v2 has schema changes, v1 (kept for rollback) must still work against the new schema. Solution: expand-contract pattern.
   - Expand: add new column (nullable), both v1/v2 can read/write
   - Migrate: backfill data
   - Contract: remove old column only after v1 is decommissioned

2. **Session affinity**: if sessions are server-side (sticky sessions), flipping LB drops in-flight sessions. Solution: externalize session state to Redis.

3. **Cost**: requires 2× capacity. At Google/Amazon scale, this is non-trivial. Mitigate with canary (smaller % at 2× cost).

---

## Canary Deployment

Named after the "canary in a coal mine" — send a small % of traffic to new version, detect problems before full rollout.

```
          ┌─────────────────────────────────┐
          │         Load Balancer           │
          └────────────┬────────────────────┘
                       │
           ┌───────────┼───────────┐
           │           │           │
          95%          5%          │
           │           │           │
      ┌────▼───┐   ┌───▼────┐     │
      │  v1    │   │  v2    │     │
      │(stable)│   │(canary)│     │
      └────────┘   └────────┘     │
                                  │
                     monitor for N minutes
                     if metrics OK → increase %
                     if metrics bad → re-route to 0%
```

### Traffic splitting mechanisms

**Weight-based** (Kubernetes + Istio):
```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
spec:
  http:
  - route:
    - destination:
        host: payment-service
        subset: v1
      weight: 95
    - destination:
        host: payment-service
        subset: v2
      weight: 5
```

**Header-based** (internal testing before any % rollout):
```yaml
# Route requests with X-Canary: true to v2
match:
- headers:
    x-canary:
      exact: "true"
```

### Canary Analysis (Netflix Kayenta model)

Automated comparison: canary metrics vs. baseline (v1 at same traffic %).

Metrics to compare:
- Error rate (HTTP 5xx)
- Latency p99, p50
- Business KPIs (checkout success rate, search click-through)
- Saturation (CPU, memory, thread pool)

Decision logic:
```
canary_score = weighted_sum(metric_pass_rate)
if canary_score >= threshold:
    promote canary → next traffic %
elif canary_score <= fail_threshold:
    rollback immediately
else:
    hold, alert on-call
```

**At FAANG scale**: canary analysis is fully automated. Engineers define the success criteria; the system executes the rollout. Human gates only for high-risk changes (schema migrations, external API changes).

---

## Shadow Deployment (Dark Launch)

```
                    ┌────────────────┐
User → LB → v1 ──► │  Real Response │
              │     └────────────────┘
              │
              └──── fork request ──► v2 (async, response discarded)
                                      │
                                      ▼
                               Compare behavior,
                               log discrepancies
```

**Use case**: validate behavior of new service before it handles real traffic. Used heavily at:
- Payment systems (verify new checkout service handles all request shapes)
- Search algorithm changes (compare ranking quality before exposing)
- Database migration validation (compare query results between old/new schema)

**Cost**: doubles processing load. Use only for validation periods (hours to days), not indefinitely.

**Tooling**: Diffy (Twitter/open source), custom middleware.

---

## A/B Testing vs. Feature Flags vs. Canary

These are often confused. They serve different purposes:

| | A/B Testing | Feature Flags | Canary |
|---|---|---|---|
| Purpose | Measure user behavior difference | Control code path | Validate deployment safety |
| Targeting | User segment (random, cohort) | User/group/percentage | Infrastructure % |
| Owner | Product/data team | Engineering + PM | Platform/SRE |
| Duration | Days to weeks (stats significance) | Hours to permanent | Hours to days |
| Rollback | Remove variant | Toggle off | Re-route traffic |
| Metric | Business KPI (conversion, revenue) | Technical (errors) + business | Technical (errors, latency) |

**Key insight**: a single release often uses all three simultaneously:
- Canary deployment validates the new binary is safe (technical)
- Feature flag gates the new feature to 10% of users (product)
- A/B test measures if the new feature improves conversion (business)

---

## Database Migration in Zero-Downtime Deployments

The hardest part of zero-downtime deploys. Schema changes must be backward-compatible across deploy windows.

### Expand-Contract Pattern

**Scenario**: rename column `user_name` → `display_name`.

```
Phase 1 — Expand (deploy v2 with dual-write):
  - Add column `display_name` (nullable)
  - App writes to BOTH `user_name` AND `display_name`
  - App reads from `user_name` (backwards compatible)

Phase 2 — Migrate:
  - Backfill: UPDATE users SET display_name = user_name WHERE display_name IS NULL
  - App reads from `display_name` (v2 fully live)

Phase 3 — Contract (after v1 fully decommissioned):
  - Remove `user_name` column
  - Drop dual-write logic
```

**Rule**: the expand phase must be deployed and fully rolled out before the contract phase begins. Never do both in one deploy.

---

## Rollback Strategy by Deployment Type

| Strategy | Rollback Mechanism | Time to Rollback | Risk |
|----------|-------------------|------------------|------|
| Rolling Update | `kubectl rollout undo` | 1–5 min | Medium (partial rollback state) |
| Blue-Green | Flip LB back | Seconds | Low |
| Canary | Route 0% to canary | Seconds | Low |
| Recreate | Redeploy v1 image | 2–10 min | High (downtime) |

**Principle**: rollback must be faster than fixing forward. If you can't roll back in < 5 minutes, your deployment strategy is too risky for production.

---

## FAANG Interview Callouts

**Q: How does Google deploy to 100+ data centers with zero downtime?**

- Immutable container images built once from trunk
- Borg (GKE predecessor) manages rolling deploys across clusters
- Canary: one cluster → region → global, automated health checks at each step
- Binary Authorization: only signed, attested images can be deployed to prod

**Q: Meta deploys to 3B users. How?**

- Feature flags (GateKeeper) are the core mechanism — code ships days before users see it
- "Push from Trunk": single deployable binary, feature flags control behavior
- Gated rollout: 0.1% → 1% → 10% → 50% → 100%, automated on error rate + latency

**Q: A canary rollout detected elevated error rates but the SLO wasn't breached. Do you continue?**

This is a judgment call a principal engineer owns:
- What's the trend? Error rate stable or growing?
- What's the p99 latency doing?
- Is the error rate correlated with the new code path or a dependency?
- What's the cost of rollback vs. cost of continued rollout?

If the error rate is stable and within acceptable bounds for the traffic %, continue with closer monitoring. If trending up, rollback and investigate. Never roll forward on ambiguous signal for a high-blast-radius service (payments, auth).
