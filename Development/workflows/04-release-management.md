# Release Management

## Why This Matters at Principal Engineer Level

Release management is the translation layer between "code merged" and "value delivered to users." At principal engineer level, you're expected to design the release process — not just follow it. That means defining the deployment strategy, rollback plan, feature flag lifecycle, release gates, and how the process scales to 50+ teams shipping independently without stepping on each other.

---

## Release Strategies

### 1. Continuous Deployment (CD)

Every merge to main triggers an automated deployment to production.

```
Code merged → CI passes → Deploy to prod (auto)
                              │
                         Feature flag gates user exposure
```

**Requirements:**
- Sub-10-minute CI pipeline
- Automated smoke tests post-deploy
- Feature flags for all incomplete/risky work
- Automated rollback on error rate spike

**Best for:** High-frequency SaaS (Stripe, Netflix, Uber)
**Not for:** Mobile apps, regulated industries, packaged software

---

### 2. Scheduled Releases (Release Train)

Releases cut on a fixed schedule (weekly, bi-weekly) regardless of feature completeness.

```
Week 1: Feature A merges to main (behind flag)
Week 2: Feature B merges to main (behind flag)
Week 2 Friday: Release train cuts — flags enabled for selected features
```

**Benefits:**
- Predictable cadence for QA, marketing, sales
- Incomplete features just miss the train (not a crisis)
- Clear coordination point for multi-team features

**Used by:** Shopify (weekly trains), Atlassian, most mobile teams

---

### 3. Manual Gated Releases

Release requires explicit human approval after automated checks.

```
CI passes → Staging deploy → QA signoff → PdM approval → Prod deploy
```

**When required:**
- Regulatory compliance (SOC2, HIPAA, PCI-DSS)
- High-blast-radius changes (pricing, billing, auth)
- Mobile app store releases
- Database schema migrations on P0 services

---

### 4. Canary Releases

Deploy to a small percentage of production traffic first, validate, then expand.

```
0%  → 1%  → 5%  → 20%  → 100%
    ▲       ▲       ▲       ▲
  5 min   30 min  2 hrs  24 hrs
  (SLO check at each gate)
```

**Automated rollback trigger:** Error rate rises > 2× baseline OR p99 latency > 500ms → auto-roll back to previous version.

**Implementation:**
- Service mesh (Istio, Envoy) for traffic splitting at the network layer
- Feature flag platform (LaunchDarkly, Flagr) for application-level targeting
- Deployment controller (Argo Rollouts, Spinnaker) for progressive delivery

---

### 5. Blue-Green Deployment

Two identical production environments. Traffic switches atomically.

```
Blue (v1) ◄── 100% traffic
Green (v2) ── 0% traffic  ← deploy here first

After validation:
Blue (v1) ── 0% traffic   ← keep warm for rollback
Green (v2) ◄── 100% traffic
```

**Rollback:** Point traffic back to Blue (< 30 seconds).
**Cost:** Double infrastructure during transition.
**Best for:** Stateless services, short transition windows.

---

## Release Gates (Automated Quality Gates)

Every release should pass automated gates before advancing:

```yaml
# Argo Rollouts analysis template
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: release-gate
spec:
  metrics:
  - name: error-rate
    interval: 5m
    successCondition: result[0] < 0.01   # < 1% error rate
    failureLimit: 3
    provider:
      prometheus:
        query: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m]))

  - name: p99-latency
    interval: 5m
    successCondition: result[0] < 0.5    # < 500ms
    provider:
      prometheus:
        query: |
          histogram_quantile(0.99, 
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

**Gate checklist:**
| Gate | Automated? | Blocking? |
|------|-----------|-----------|
| Unit + integration tests pass | Yes | Yes |
| Security scan (Snyk, Dependabot) | Yes | Yes (critical/high) |
| Performance regression check | Yes | Yes (> 20% degradation) |
| Database migration dry-run | Yes | Yes |
| Smoke tests in staging | Yes | Yes |
| SLO check (canary window) | Yes | Yes |
| PdM sign-off (feature releases) | No | For new features |
| Security review (auth changes) | No | Yes |

---

## Feature Flag Lifecycle

Feature flags decouple deployment from release. Every flag must have a lifecycle.

```
States: draft → dev → staging → canary → GA → cleanup

draft:    Flag created, code committed behind flag, not visible
dev:      Flag enabled in dev/sandbox environments
staging:  Flag enabled in staging, QA tests
canary:   Flag enabled for 1-5% of prod users
GA:       Flag enabled for 100% (or specific segment)
cleanup:  Flag removed from code, deleted from flag service
```

**Flag types:**
| Type | Lifetime | Example |
|------|----------|---------|
| Release flag | Days–weeks | New checkout flow |
| Experiment flag | Weeks | A/B test on button color |
| Ops flag | Permanent (kill switch) | Disable expensive feature under load |
| Permission flag | Permanent | Beta access for enterprise customers |

**Cleanup rule:** Release flags must be removed within 30 days of GA. Stale flags are technical debt — they add conditional branches, complicate testing, and mislead new engineers. Track flag age in LaunchDarkly or flag-service dashboard.

**Anti-pattern:** Feature flags used as permanent feature gating instead of proper RBAC. This creates invisible complexity — hundreds of flags, no one knows which are active.

---

## Rollback Strategy

Every deployment must have a documented rollback plan before it ships.

**Decision tree:**
```
Incident detected
    │
    ├─ Feature flag exists? → Disable flag (< 1 min, no deploy)
    │
    ├─ Stateless service? → Rollback to previous image version (Kubernetes: kubectl rollout undo)
    │
    ├─ Stateful change (DB schema)? → Forward-fix only (rollback may corrupt data)
    │
    └─ Data migration in flight? → Halt migration, assess damage, forward-fix
```

**Rollback SLOs:**
- Stateless service rollback: < 5 minutes
- Feature flag disable: < 1 minute
- Database migration rollback: case-by-case (often not possible — design migrations to be non-breaking)

**Database migration safety:**
- Never combine schema change + data migration in one deployment
- Pattern: (1) deploy backward-compatible schema change, (2) deploy code that uses new schema, (3) deploy cleanup of old schema
- This allows rollback at step 2 without breaking the DB

---

## Release Coordination at Scale (50+ Teams)

**Problem:** With 50 teams shipping independently, how do you prevent:
- Two teams shipping breaking changes to a shared service on the same day?
- A deploy window conflict (everyone deploys on Friday afternoon)?
- A shared dependency upgrade that breaks 5 services?

**Solutions:**

### 1. Deploy Freeze Windows
Defined periods with no deployments (before/after major holidays, during peak traffic):
```
Black Friday window: No deploys Nov 20 – Nov 30
Weekly freeze: No deploys Friday 4pm – Monday 9am
Incident freeze: No non-emergency deploys during P0/P1 incidents
```

### 2. Deployment Scheduling (Serialize High-Risk)
For database migrations or shared service changes:
- Book a deployment slot in a shared calendar
- SRE on-call is aware and standing by
- Other teams are notified via Slack

### 3. Dependency Change Protocol
When a shared library or platform service releases a breaking change:
- 6-week deprecation notice minimum
- Migration guide published in engineering portal
- Migration completion tracked per-team on a dashboard
- Old version sunset only when all consumers have migrated

### 4. Release Train (cross-team coordination)
For features that span multiple services:
- Nominate a release coordinator (usually the PM or tech lead)
- All services must be deployed and validated by T-0
- Go/no-go call 1 hour before launch with all team leads

---

## Release Communication

**Internal (engineering):**
```
#releases Slack channel — automated bot posts every prod deploy:
[14:32] 🚀 payment-service v2.4.1 deployed to prod
         PR: #1234 | Author: @alice
         Changes: Add retry logic for Stripe 429 responses
         Rollback: kubectl rollout undo deployment/payment-service
```

**External (customers):**
- Status page (statuspage.io) for incidents affecting customers
- Release notes for user-visible features (in-app notification or changelog)
- Pre-announced maintenance windows for planned downtime

---

## Interview Framing

**Q: Design a release process for a 50-team engineering org.**

> I'd build on three pillars: continuous deployment with feature flags as the default, release trains for cross-team coordination, and automated progressive delivery with rollback. Most teams ship to production on every merge — feature flags give them the ability to deploy code without exposing it. For features that span teams, we use a weekly or bi-weekly release train with a named coordinator. For high-risk changes (DB migrations, auth, pricing), I add a manual gate — PdM and SRE sign-off. Automated canary gates (error rate, latency SLOs) catch regressions before they hit all users. The entire system is self-serve — I don't want teams blocked on a release manager. SRE's job is to keep the pipeline healthy, not to approve individual deploys.

**Q: A release is broken in production. Walk me through your response.**

> First: is there a feature flag? Disable it immediately — don't wait to diagnose. If not: do we have an obvious rollback (stateless service, previous image)? Roll back first, ask questions second. If it's a database migration, rolling back may corrupt data — in that case we forward-fix while mitigating user impact. Throughout this process I'm: opening an incident bridge, paging the owning team, posting to #incidents every 10 minutes with status. After resolution, I'm writing a postmortem with a blameless review and actionable follow-ups — the goal is not to find who broke it but what in our system allowed it to break.
