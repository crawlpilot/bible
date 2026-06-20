# Sprint to Production Workflow

## Why This Matters at Principal Engineer Level

The end-to-end workflow — from a product requirement to running code in production — is the operating system of your engineering organization. At principal engineer level, you are expected to design, optimize, and govern this workflow across multiple teams. A broken workflow manifests as: slow delivery, high defect rates, frequent rollbacks, on-call burnout, and poor morale. A healthy workflow produces predictable, sustainable delivery of value.

This document covers the full lifecycle: requirement → ticket → PR → CI → staging → canary → production → monitoring.

---

## The Full Delivery Lifecycle

```
PRODUCT IDEA
    │
    ▼
Requirement Clarification & Scoping (Product + PE)
    │
    ▼
Design (Design Doc / RFC if needed)
    │
    ▼
Sprint Planning & Ticket Creation
    │
    ▼
Implementation (Inner Loop: code → build → test → debug)
    │
    ▼
Pull Request + Code Review
    │
    ▼
Continuous Integration (CI)
    ├── Unit tests
    ├── Integration tests
    ├── Static analysis / linting
    ├── Security scan
    └── Build artifact
    │
    ▼
Deploy to Staging
    ├── End-to-end tests
    ├── QA sign-off (if applicable)
    └── Performance validation (if applicable)
    │
    ▼
Deploy to Production (Canary)
    ├── 1% traffic → observe for 15 min
    ├── 5% → observe
    ├── 25% → observe
    └── 100% → release complete
    │
    ▼
Post-Deploy Monitoring (30-60 min heightened vigilance)
    │
    ▼
Feature Flag Rollout (if dark-launched)
    │
    ▼
DONE — learning captured in retrospective
```

---

## Stage 1: Requirement to Ticket

### The INVEST Criteria for User Stories

Good tickets prevent misunderstandings that surface mid-implementation. At PE level, enforce these criteria in sprint planning:

| Criterion | Meaning | Bad Example | Good Example |
|-----------|---------|-------------|-------------|
| **I**ndependent | Story can be developed and delivered independently | "Checkout (requires payment, cart, inventory all done)" | "Display cart total (no external dependencies)" |
| **N**egotiable | Not a fixed contract; details can be discussed | "Exactly 3 font sizes on the confirmation page" | "Confirmation page shows order summary clearly" |
| **V**aluable | Delivers value to user or business | "Refactor CartService internals" | "Show estimated delivery date on checkout (reduces abandonment)" |
| **E**stimable | Team can estimate the effort | "Build AI recommendation engine" | "Add 'Recommended for you' section using existing recommendation API" |
| **S**mall | Fits in a sprint (typically ≤ 5 days) | "Build the entire payment flow" | "Add Stripe payment form component" |
| **T**estable | Can write acceptance criteria before implementation | "Make checkout better" | "Checkout completes in < 3 clicks on mobile" |

### Ticket Anatomy (Standard Format)

```markdown
## [TICKET-1234] Add coupon code redemption to checkout

**Type**: Feature  
**Size**: M (3 days)  
**Sprint**: 2024-Q1-Sprint-3  
**Assignee**: @alice  
**Epic**: Checkout Improvements  

### Problem / Context
Conversion rate analysis shows 12% of users who receive coupon codes abandon checkout because
there's no way to apply them. Support receives 50 tickets/week on this topic.

### Acceptance Criteria
- [ ] User can enter a coupon code in a text field on the checkout summary page
- [ ] Valid coupon: discount is applied immediately (< 500ms); total updates
- [ ] Invalid coupon: clear error message shown inline (not a modal)
- [ ] Expired coupon: distinct error message explaining expiry
- [ ] Coupon application is persisted across page refresh
- [ ] Coupon code is included in order creation payload and stored in DB

### Technical Notes
- Use existing `CouponService.validate(code)` and `CouponService.apply(code, cartId)`
- Discount calculation happens server-side (never trust client-side discount)
- Add `coupon_code` and `discount_amount_cents` to `orders` table (migration needed)

### Out of Scope
- Multi-coupon support (future ticket)
- Coupon management UI for admins (separate epic)

### Dependencies
- None (CouponService already exists)

### Testing
- Unit: CouponService validation logic
- Integration: cart + coupon application end-to-end
- QA: coupon happy path + expired + invalid scenarios
```

---

## Stage 2: Sprint Planning

### The Planning Ceremony at PE Level

Sprint planning is where commitment meets reality. PE-level concerns:

**1. Capacity accounting (do this before estimation)**
```
Team capacity calculation:
  Engineers on team: 6
  Sprint duration: 10 business days
  Theoretical capacity: 6 × 10 = 60 engineer-days

Deductions:
  - On-call toil (avg 1 day/sprint per on-call engineer): -2 days
  - Meetings overhead: -0.5 days/engineer: -3 days
  - Code review / unplanned: -0.5 days/engineer: -3 days
  - 1 engineer on PTO: -5 days
  - Tech debt allocation (20%): -9.4 days

Available capacity: 60 - 2 - 3 - 3 - 5 - 9.4 = 37.6 engineer-days
Commit to: ~35 days of work (buffer for unknowns)
```

**2. Definition of Done (DoD)**

Every team should have an explicit, agreed-upon DoD. Work is not "done" until all DoD criteria are met:

```
Definition of Done — [Team Name]:
□ Code implemented and self-reviewed
□ Unit tests written (coverage for new code ≥ 80%)
□ Integration tests cover the new functionality
□ PR reviewed and approved (2 reviewers for > 200 line changes)
□ CI passing (all checks green)
□ Staging deployed and smoke test passed
□ Observability: metrics, logs, alert/runbook updated if new failure modes introduced
□ Documentation: API docs updated if endpoints changed; README updated if new setup steps
□ Feature flag: new functionality behind a feature flag if risk level > LOW
□ Product owner accepted (for user-facing features)
□ No known critical/high bugs at time of merge
```

The DoD is enforced in code review and sprint review, not just as aspiration.

**3. Sprint goal**

Every sprint should have a single meaningful goal:  
"This sprint we can deploy coupon code redemption to 100% of users."  
Not: "This sprint we complete tickets 1234, 1235, 1236, 1237..."

The sprint goal focuses the team and provides a clear "is the sprint successful?" test.

---

## Stage 3: Implementation Workflow

### The Daily Development Flow (Trunk-Based)

```
Start of day:
  git pull origin main           # Stay current with trunk
  git log --oneline -10          # Understand what changed overnight

Feature implementation:
  git checkout -b feat/coupon-redemption-TICKET-1234  # Short-lived feature branch
  
  <write code in small commits>
  git add -p                     # Selective staging (never git add .)
  git commit -m "feat(checkout): add coupon code input field"
  git commit -m "feat(checkout): wire coupon validation API call"
  git commit -m "test(checkout): add unit tests for coupon validation edge cases"

Before pushing:
  make test-unit                 # Fast feedback: unit tests only
  make lint                      # Code style and static analysis
  git rebase origin/main         # Stay current; resolve conflicts early

Push and open PR:
  git push -u origin feat/coupon-redemption-TICKET-1234
  gh pr create --title "feat: add coupon code redemption to checkout" \
               --body "Closes TICKET-1234" --assignee @alice --label "feature"
```

**Branch lifetime target**: < 2 days. PRs open for more than 3 days are a workflow smell.

### Commit Message Standard

```
Format: <type>(<scope>): <description>

Types:
  feat:     A new feature (e.g., feat(checkout): add coupon redemption)
  fix:      A bug fix (e.g., fix(payments): handle Stripe timeout gracefully)
  refactor: Code change without behavior change
  test:     Adding or changing tests
  chore:    Build system, dependencies (e.g., chore(deps): upgrade spring-boot to 3.2.4)
  docs:     Documentation only
  perf:     Performance improvement
  security: Security fix

Rules:
  - Use imperative mood ("add" not "added" or "adds")
  - < 72 characters
  - Reference ticket number in body: "Closes TICKET-1234"
  - No "WIP" commits on main branch
```

---

## Stage 4: Code Review Workflow

### PR Author Responsibilities

**Before opening PR**:
```
□ Self-review: read every line of the diff as if you're the reviewer
□ PR description: what changes, why, how to test, what to look for
□ Link to ticket
□ Size: < 500 lines of production code (split if larger)
□ Tests included (unit + integration for the changed paths)
□ No known broken functionality at time of submission
```

**PR description template**:
```markdown
## What
[1-2 sentences: what does this PR do?]

## Why
[Link to ticket; brief context on why this change is needed]

## How to Test
[Step-by-step for reviewer to verify the change works]
1. Start local environment: `make dev`
2. Navigate to checkout with item in cart
3. Enter coupon code "SAVE10" → discount should apply
4. Enter "INVALID" → error message should appear

## Risk
[Low / Medium / High — and brief justification]
Feature flag: COUPON_REDEMPTION (off by default; enable in local env)

## Screenshots (if UI change)
[Before / After screenshots]

## Checklist
- [x] Unit tests added
- [x] Integration tests added  
- [x] Feature flag controls this change
- [x] No PII in logs
- [x] No hardcoded configs
```

### Reviewer Responsibilities

**Review SLA** (from PR opened to first substantive review):

| PR Size | SLA |
|---------|-----|
| XS (< 50 lines) | 2 hours |
| S (50-200 lines) | 4 hours |
| M (200-500 lines) | 8 hours (same business day) |
| L (500-1000 lines) | 2 business days |
| XL (> 1000 lines) | Split the PR — return to author |

**Review comment language**:

```
NIT: Use Optional.empty() instead of null here
     (minor; author's choice)

Q: Why did you choose HashMap over TreeMap here?
   (question; no change needed if answered)

SUG: We could extract this into a private method for testability
     (optional improvement; author's call)

REQ: This will cause a NPE if couponService.validate() returns null
     (required change before merge)

BLK: This bypasses the coupon authorization check — any user could apply
     any coupon. This needs to go through CouponAuthorizationService.
     (blocking; design must change)
```

---

## Stage 5: CI Pipeline

### Pipeline Stage Design

```
PR opened / commit pushed
         │
Stage 1: Fast checks (< 3 min — must pass before reviewer time is spent)
  │  ├── Compile / syntax check
  │  ├── Linting (checkstyle, spotbugs, eslint)
  │  ├── Unit tests (no external dependencies)
  │  └── Dependency security scan (Snyk/Dependabot)
  │
Stage 2: Integration tests (< 10 min — run in parallel with review)
  │  ├── Integration tests (with real DB / in-memory Kafka)
  │  ├── Contract tests (Pact)
  │  └── API schema validation
  │
Stage 3: Build and package (< 5 min)
  │  ├── Build container image
  │  ├── Push to registry with PR-specific tag
  │  └── Security scan of container image (Trivy)
  │
All stages pass → PR is mergeable (CI green gate)
```

**CI design principles**:
- Fail fast: put the fastest checks first; don't make engineers wait 30 minutes to discover a compile error
- Parallel stages: integration tests and code review happen simultaneously
- Deterministic: tests must produce the same result every run (no flaky tests)
- No hard-coded sleeps: use health check polling instead of `sleep(5000)`
- Reproducible: CI runs in same environment as production (same Docker base image)

---

## Stage 6: Staging Deployment

### Staging Environment Requirements

Staging is the last line of defense before production. It must be production-like enough to catch real problems.

```
Production-like properties:
□ Same Docker images (not a different build)
□ Same deployment configuration (k8s manifests, env vars)
□ Production-equivalent data volume (or proportional sample)
□ Same downstream service versions (or realistic stubs)
□ Same network topology (latency, segmentation)
□ Real authentication (not a bypass)

Not required to match production:
□ Instance count (can be smaller)
□ Complete data (can be sampled or synthetic)
□ External integrations (can use sandbox accounts)
```

**Staging validation gate**:
```
□ E2E smoke tests pass (critical user journeys)
□ New functionality verified by author (manual happy-path)
□ Performance check: no P99 regression > 10% vs. baseline
□ No new errors in logs compared to pre-deploy baseline
□ QA sign-off (for user-facing features with risk > LOW)
```

### Managing Staging Instability

Staging breakage is a common productivity killer. Root causes and fixes:

| Cause | Fix |
|-------|-----|
| Multiple teams deploying simultaneously | Deployment queue; one deployment at a time in staging |
| Staging data drift (diverged from prod schema) | Automated staging refresh weekly; Flyway migrations in staging |
| Flaky E2E tests | Fix or quarantine flaky tests; don't let them block deployments |
| Service dependency unavailable | Containerized test doubles; staging monitoring |
| Long staging queue | Multiple staging slots (staging-a, staging-b) for parallel teams |

---

## Stage 7: Production Deployment and Rollout

### Canary Deployment Protocol

```
Canary Gate 1: 1% traffic
  Deploy time: T+0
  Observe: 15 minutes
  Check: error rate, P99 latency vs. pre-deploy baseline
  Auto-promote if: error rate stable, latency stable
  Auto-rollback if: error rate > 2× baseline OR P99 > 1.5× baseline

Canary Gate 2: 5% traffic
  Observe: 15 minutes
  Same checks

Canary Gate 3: 25% traffic
  Observe: 15 minutes
  Same checks + business metrics if applicable (conversion rate, order success)

Canary Gate 4: 100% traffic
  Full rollout
  Observe: 30 minutes (heightened vigilance)

Total canary time: ~75 minutes from deployment start to 100% rollout
```

**Feature flag rollout** (for high-risk features deployed dark):

```
Dark launch: Feature deployed to 100% of machines; feature flag = OFF for all users

Rollout:
  Day 1: 1% of users (internal users / beta users)
  Day 2: 5% of users
  Day 3: 25% of users
  Week 2: 100% of users (if metrics healthy)

Flag states:
  OFF:      No users see the feature
  ALPHA:    Internal/flagged users only
  BETA:     Percentage rollout (0-100%)
  GA:       100% of users
  RETIRED:  Flag removed from code; feature is default behavior
```

---

## Stage 8: Post-Deploy Monitoring

### Heightened Vigilance Window

For 60 minutes after any production deployment, the deploying engineer monitors:

```
Deployment monitoring checklist:
□ Error rate: steady at pre-deploy baseline?
□ P99 latency: stable or improving?
□ SLO burn rate: not elevated?
□ Business metrics: conversion rate, order success rate stable? (if applicable)
□ Downstream impact: no increased error rate in downstream services?
□ Logs: no new error patterns appearing?

Success criteria:
  All metrics stable for 30 minutes post-deployment → deployment complete

Rollback trigger:
  Any metric outside acceptable range within 60 minutes → initiate rollback
```

### Deployment Annotation

Every production deployment should be annotated in your monitoring dashboards:

```
Grafana annotation (added automatically by CI/CD system):
  Time: [deploy time]
  Label: "Deploy: payment-service v2.4.1"
  Color: yellow (visible on all dashboards)

Value: Engineers can immediately correlate metric changes with deploys
       "Error rate spiked exactly at the deploy marker → rollback candidate"
```

---

## Workflow Metrics and Health

### Sprint Delivery Health

Track these in sprint retrospective:

| Metric | Target | Action if Missed |
|--------|--------|-----------------|
| Sprint goal achieved | ≥ 90% of sprints | Investigate capacity modeling or estimation accuracy |
| Committed work completed | ≥ 85% | Reduce commitment; improve estimation |
| Unplanned work | ≤ 15% of sprint capacity | Identify source; reduce interruptions or on-call toil |
| PR review time P95 | < 8 hours | Review culture; capacity; PR size |
| Deploy frequency | ≥ 1/day per team | CI/CD investment; feature flag adoption |
| Change failure rate | ≤ 15% | Test coverage; staging validation; canary |

### End-to-End Lead Time Breakdown

Measure where time is lost in the delivery pipeline:

```
Typical lead time breakdown (target: < 1 day for small changes):
  Requirement to ticket:      1 day (product refinement)
  Ticket to PR opened:        1-2 days (implementation)
  PR review time:             4-8 hours
  CI pipeline:                15-30 minutes
  Staging validation:         1-2 hours
  Canary to 100%:             75 minutes
  Feature flag rollout:       1-7 days

Total (excluding feature flag rollout): ~3-5 days for a medium feature

Principal engineer action: if any stage takes > 2× the target, investigate and fix
```

---

## FAANG Interview Framing

### "How do you design the delivery workflow for a team scaling from 5 to 50 engineers?"

> "At 5 engineers, a simple GitHub Flow with a shared main branch and manual deploys works fine. At 50, it breaks because you have conflicts between teams, flaky shared staging environments, and no visibility into what's causing production incidents. I'd design around three principles: independence, observability, and safety. Independence means each team can deploy without coordinating with other teams — this requires feature flags to decouple deploy from release, and service ownership that means one team's deploy doesn't break another team's service. Observability means every deploy is annotated in the monitoring system and automatic rollback fires within minutes of a regression. Safety means a canary gate that stops bad deploys before they reach 100% of users. Practically, this means investing in a solid CI/CD platform (Vela, GitHub Actions, or similar), a feature flag system (LaunchDarkly, Statsig), and automatic rollback based on SLO burn rate. The lead time from ticket to production should be measurable and under 3 days for a medium-sized change."

### "Walk me through how you'd roll out a high-risk change to production."

> "For a high-risk change — say, changing the payment processing logic — I'd use a combination of dark launch and canary rollout. The change is deployed to 100% of machines but behind a feature flag (dark launch), which means zero users are affected while I verify the deployment is healthy in production infrastructure. Then I roll out via the feature flag: 1% of users first (internal or beta users), observe payment success rates, latency, and error rates for 24 hours. If everything looks good, 5%, then 25%, then 100% over the course of a week. At each stage, the rollout is pausable and reversible — flipping the feature flag off instantly rolls back for all users without a code deployment. I define the rollback criteria upfront: if payment success rate drops below X%, or P99 latency increases by Y%, we roll back automatically or manually. I also align with the on-call team so there's heightened vigilance during each ramp-up step, and I communicate the rollout plan to stakeholders so nobody is surprised if I pause it."
