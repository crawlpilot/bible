# ADR-004: Streamlining CI/CD Deployment Planning to Achieve Organisation DORA Metric SLAs

**Title**: Replace Ad-Hoc Deployment Planning and Manual Release Gates with a DORA-Instrumented Pipeline Governance Model  
**Status**: Accepted  
**Date**: 2026-06-14  
**Authors**: [Principal Engineer — Platform], [Staff Engineer — Developer Experience], [SRE Lead]  
**Reviewers**: [VP Engineering], [Director of Product], [Security Architect], [EM — Backend Platform]  
**Deciders**: [CTO], [VP Engineering]

---

## Context

### Current State

The organisation operates **47 services** across 6 product teams. CI/CD is handled by a mix of Jenkins pipelines (31 services), GitHub Actions workflows (12 services), and 4 services with no automated pipeline at all (manual SSH-based deploys). There is no shared deployment planning process, no centralised DORA measurement, and no enforcement of minimum quality gates before production deployment.

A DORA audit commissioned by the VP Engineering in Q1 2026 produced the following baseline:

| DORA Metric | Current (Q1 2026) | Elite Benchmark | Organisation SLA Target (Q3 2026) |
|---|---|---|---|
| **Deployment Frequency** | 1.3 deploys/service/month | Multiple per day | ≥ 4 deploys/service/week |
| **Lead Time for Changes** | 8.4 days (commit → production) | < 1 hour | < 4 hours |
| **Change Failure Rate** | 22% (1 in 5 deploys causes a rollback or incident) | 0–15% | < 10% |
| **MTTR (Mean Time to Recovery)** | 2h 47min (p50 for P1/P2 incidents) | < 1 hour | < 30 minutes |

The scores place the organisation in the **Low** DORA performance band. The board-level engineering KPI committed to VP Engineering is reaching the **High** band (on all four metrics) by Q3 2026, with a roadmap to **Elite** by Q1 2027.

### Root Causes Identified by the Audit

**Deployment Frequency is low because:**
- Releases are batched — teams accumulate 2–3 weeks of completed work before deploying ("release train" model inherited from monolith era, now applied to services that don't need it)
- Deploy pipelines require manual approval gates at 3 stages: post-build, post-staging, pre-production. Gate approvals average 6.2 hours of wait time per deploy
- 14 services share a single Jenkins server with a serialised build queue; peak queue time is 47 minutes
- No blue-green or canary deploy mechanism exists for 28 services; deploy = downtime, which creates social pressure to batch deployments to reduce user-visible disruption

**Lead Time is high because:**
- Code review SLAs are unenforced; median PR open-to-merge time is 4.1 days
- Staging environment is shared across all teams; environment conflicts and dependency flakiness add an average of 1.9 days of wait per PR
- Regression test suites run sequentially and average 68 minutes per run (full suite; no test splitting, no flaky test quarantine)
- The staging → production promotion step requires a "release manager" who coordinates across teams; this role exists only on Tuesdays and Thursdays (3 release windows per week)

**Change Failure Rate is high because:**
- No mandatory pre-production smoke tests (30% of services lack any post-deploy health check)
- No automated rollback; rollback requires a manual revert PR, a new build, and re-approval through the full gate sequence
- Feature flags are not used; every deploy is a full exposure to 100% of production traffic
- No canary stage; code either works in staging or hits all users simultaneously

**MTTR is high because:**
- Runbooks are stale or missing for 18 of 47 services
- Rollback procedure is undocumented; on-call engineers ad-hoc rollback each service differently
- No standardised one-click rollback mechanism; average rollback time is 41 minutes
- Incident response does not have a clear "rollback vs fix-forward" decision framework

### Trigger for This ADR

Three converging pressures forced a decision in Q2 2026:

1. **Revenue impact quantified**: Finance analysis showed that 22% CFR × average deploy size × 47 services × 1.3 deploys/month = approximately 4.7 customer-impacting incidents per month. Revenue impact per incident (estimated from cart abandonment, SLA credits, and support cost): $180K average. Monthly cost: ~$850K. DORA investment at Elite performance would reduce incident rate to < 0.5/month, a $780K/month saving.

2. **Engineering attrition**: 5 senior engineers cited "deploy process toil" in exit interviews in Q4 2025. Replacement cost per senior engineer: ~$200K (recruiting + ramp). Pipeline investment is competing against $1M in attrition cost.

3. **Board commitment**: The VP Engineering committed DORA High band as a Q3 2026 board KPI in the Q1 2026 earnings call. This decision now has executive visibility and a named owner.

---

## Decision

**Adopt a unified DORA-instrumented pipeline governance model** across all 47 services, replacing ad-hoc per-team pipelines with a shared deployment platform that enforces minimum quality gates, measures all four DORA metrics continuously, and provides automated rollback as a first-class capability.

The decision is structured across four pillars:

### Pillar 1: Pipeline Standardisation and Infrastructure

Migrate all 47 services to **GitHub Actions** (company-wide GitHub Enterprise licence is already in place). Retire the shared Jenkins server.

Introduce a **shared reusable workflow library** (`/.github/workflows/shared/`) that provides:

```
build.yml         → reproducible build with layer caching
test.yml          → parallelised test execution with flaky test quarantine
security.yml      → SAST (Semgrep), SCA (Snyk), container scan (Trivy)
promote.yml       → staging promotion with smoke test gate
canary.yml        → production canary: 5% traffic, 10-minute soak, auto-promote or rollback
rollback.yml      → one-click rollback to any previous successful deploy SHA
dora-emit.yml     → DORA metric event emission to centralised metrics store
```

Teams consume these via `uses:` references; they do not write pipeline logic. The platform team owns the shared workflows; teams own service-specific configuration.

### Pillar 2: Mandatory Quality Gates (Non-Bypassable)

The following gates are enforced at the platform level. No service may bypass them via `if: always()` or pipeline configuration override. Gate bypass requires a written ADR and VP Engineering sign-off.

| Gate | Stage | Pass Criterion | Failure Action |
|---|---|---|---|
| Build reproducibility | Post-build | Identical SHA built twice must produce identical artefact hash | Block; alert |
| Unit + integration test | Post-build | Test pass rate 100%; flaky tests quarantined, not blocking | Block on net-new failures |
| Code coverage delta | Post-build | Coverage must not decrease by > 2% from main branch | Block |
| SAST scan | Post-build | No new High or Critical severity findings | Block |
| SCA / dependency audit | Post-build | No newly introduced CVE with CVSS ≥ 7.0 | Block |
| Container image scan | Post-build | No Critical CVE in base image or dependencies | Block |
| Staging smoke test | Post-staging | 10 defined health endpoints return 200 within 5 seconds | Block |
| Staging integration test | Post-staging | Cross-service contract tests pass (Pact or equivalent) | Block |
| Canary health check | Post-canary | Error rate < baseline + 0.5%; p99 latency < baseline + 20% | Auto-rollback; alert on-call |
| Production smoke test | Post-deploy | Same 10 health endpoints return 200 within 5 seconds | Auto-rollback; page on-call |

**Rationale for non-bypassable gates:** The current 22% CFR is largely attributable to deploys that skipped one or more of the above checks. A gate that can be bypassed is not a gate — it is a suggestion. The cost of an occasional blocked deploy is trivially lower than the cost of a production incident.

### Pillar 3: Deployment Planning Process Reform

**Replace the release train with continuous deployment by default:**

Each service team operates under one of two deployment models:

| Model | Applies When | Mechanism |
|---|---|---|
| **Continuous Deploy (CD)** | Service has no hard external dependency on synchronised releases | Every merged PR deploys automatically through the gate sequence. No human approval step. |
| **Coordinated Deploy** | Service has a versioned external API contract or a cross-service schema migration | Manual approval required; deploy window must be booked in the shared deploy calendar. Max 48-hour booking-to-deploy window enforced. |

Target: ≥ 80% of services on Continuous Deploy model within 60 days of this ADR.

**Eliminate manual approval gates in the CD path:**

The existing three manual gates (post-build, post-staging, pre-production) are replaced by automated quality gates (Pillar 2). The only human approval remaining in the CD path is for Coordinated Deploy services during the booking window.

**The shared deploy calendar (for Coordinated Deploy):**
- Any team can book a deploy slot in the shared calendar with 24-hour lead time
- Maximum 3 coordinated deploys in any 2-hour window (prevents blast radius overlap)
- Emergency deploys (P1 fix) bypass the calendar but require Incident Commander sign-off

**Eliminate release windows:**
The Tuesday/Thursday release window model is abolished. Services on the CD model deploy on merge, 24/7. The release manager role is retired. Teams own their own deploy cadence within the quality gate constraints.

### Pillar 4: DORA Instrumentation and Governance

**DORA measurement infrastructure:**

All four DORA metrics are measured automatically by the `dora-emit.yml` shared workflow step, which emits structured events to a centralised time-series store (InfluxDB):

| Metric | Measurement Point | Event Type |
|---|---|---|
| Deployment Frequency | On every successful production deploy | `deploy.production.success` |
| Lead Time | From first commit SHA in the PR to production deploy timestamp | `deploy.leadtime.commit_to_prod` |
| Change Failure Rate | On any production rollback or P1/P2 incident with a deploy in the prior 24h | `incident.deploy_attributed` |
| MTTR | From `incident.declared` to `incident.resolved` (PagerDuty event bridge) | `incident.mttr` |

**DORA dashboard:**
- Live dashboard (Grafana) visible to all engineers, EMs, and the VP Engineering
- Team-level breakdown: each team sees their own DORA metrics and the org aggregate
- SLA breach alert: any team breaching their DORA SLA for two consecutive weeks triggers an automatic EM + PE review meeting

**DORA SLA targets (this ADR commits the following by Q3 2026):**

| Metric | Q2 2026 Baseline | Q3 2026 SLA (High Band) | Q1 2027 Target (Elite Band) |
|---|---|---|---|
| Deployment Frequency | 1.3/month | ≥ 4/week | Multiple/day |
| Lead Time | 8.4 days | < 4 hours | < 1 hour |
| Change Failure Rate | 22% | < 10% | < 5% |
| MTTR | 2h 47min | < 30 min | < 10 min |

**Weekly DORA review cadence:**
- Every Monday: automated DORA summary emailed to all EMs and PEs (per-team + org aggregate)
- Every 2 weeks: DORA review in the PE/EM sync; teams outside SLA present root cause and remediation plan
- Quarterly: VP Engineering reviews DORA trend vs board commitment; investment decisions made based on which metrics are lagging

---

## Rollout Plan

### Phase 1 (Weeks 1–4): Foundation
- Deploy shared GitHub Actions workflow library (`/.github/workflows/shared/`)
- Migrate 5 pilot services (one per product team; lowest-risk services selected)
- Stand up DORA instrumentation pipeline and Grafana dashboard
- Establish baseline DORA measurements for all 47 services

### Phase 2 (Weeks 5–10): Migration Wave 1
- Migrate remaining 42 services to GitHub Actions (Jenkins retirement)
- Enable mandatory quality gates for all migrated services
- Roll out canary deploy infrastructure (Argo Rollouts on EKS) for services with EKS workloads
- Train all tech leads on the shared workflow model and deploy calendar

### Phase 3 (Weeks 11–16): CD Adoption
- Classify all services as Continuous Deploy vs Coordinated Deploy
- Enable auto-deploy on merge for all CD-classified services
- Retire Tuesday/Thursday release windows; retire release manager role
- Achieve Q3 DORA SLA targets; review and close Phase 1 gaps

### Phase 4 (Ongoing): Elite Band Roadmap
- Investigate progressive delivery for canary targets > 5% (10% → 25% → 50% → 100% with automated promotion)
- Implement feature flag integration for all new features (LaunchDarkly or Unleash)
- Reduce test suite runtime to < 10 minutes via test splitting (Gradle test distribution or `pytest-xdist`)

---

## Consequences

### Positive

**Delivery velocity:**
- CD model eliminates 6.2 hours of average gate wait time per deploy
- Teams can iterate at the speed of CI, not at the speed of release coordination
- 4-day PR open-to-merge time is addressed via PR size norms (< 400 lines enforced by bot comment) and code review SLA automation (auto-assign reviewer after 4 hours idle)

**Reliability:**
- Automated gates eliminate the majority of the 22% CFR (estimated CFR reduction to 6–9% based on gate failure analysis against historical incidents)
- Automated rollback reduces MTTR from 2h 47min to an estimated 8–12 minutes for deploy-attributed incidents (rollback is a single pipeline trigger, not a manual revert PR)
- Canary deploys limit blast radius of any residual failures to 5% of production traffic during a 10-minute soak window

**Visibility:**
- DORA dashboard gives every team and every EM a real-time view of delivery health
- DORA-attributed incident root cause analysis replaces subjective post-mortem narratives with data

**Org-level alignment:**
- VP Engineering board commitment is backed by automated measurement; there is no ambiguity about whether SLAs are being met
- Teams are measured on the same metrics, enabling fair cross-team comparison and identification of which teams need platform investment

### Negative / Risks

**Migration disruption (Weeks 1–10):**
- Migrating 42 services from Jenkins to GitHub Actions carries integration risk for services with complex Groovy pipeline logic
- Mitigation: parallel pipeline execution for the first 2 weeks of each service migration; old pipeline remains available as fallback

**Automated gate friction:**
- Teams with historically low test coverage will have deploys blocked until coverage is raised
- This is intentional — the gate is enforcing a standard that should have been enforced earlier
- Mitigation: 30-day grace period for services with < 40% coverage; they must submit a test remediation plan in Week 1

**Canary infrastructure overhead:**
- Argo Rollouts requires EKS; 14 services are not yet on EKS (VM-based)
- These services will use a simplified blue-green model (Route 53 weighted routing) until EKS migration (ADR-003) completes
- Full canary capability for all 47 services: estimated Q4 2026

**Shared workflow coupling:**
- Centralising pipeline logic in a shared library creates a single point of failure: a breaking change in `shared/build.yml` can affect all 47 services simultaneously
- Mitigation: shared workflows are versioned (`uses: org/shared-workflows/build.yml@v2`); teams pin to a version; upgrades are opt-in with a deprecation window

**Velocity spike risk at CD adoption:**
- Moving from 1.3 deploys/month to multiple per day multiplies the opportunities for production impact
- Mitigation: quality gates are a prerequisite for CD adoption; no service moves to CD until all gates are passing on 5 consecutive builds

### Neutral

- The release manager role is retired. The 2 engineers in that role are redeployed to the platform team (Pillar 1 and Pillar 4 work).
- Per-team Jenkins configurations are deleted. Teams lose the ability to customise pipeline logic below the shared workflow abstraction boundary.

---

## Alternatives Considered

### Option A: Keep Jenkins; Add DORA Instrumentation Only

**Description:** Retain the existing Jenkins-based pipelines. Add DORA measurement as a reporting layer on top of the existing pipeline events. Make manual gates faster by introducing SLA timers (auto-approve after 2 hours if no rejection).

| Dimension | Assessment |
|---|---|
| Migration risk | None — no pipeline changes |
| DORA improvement | Lead Time improves modestly (auto-approve reduces gate wait from 6.2h to ~2h). Deployment Frequency unchanged. CFR unchanged. MTTR unchanged. |
| Achieves Q3 DORA SLA | No — lead time improves to ~4 days, not < 4 hours. CFR unchanged at 22%. |
| Engineering toil | Unchanged — Jenkins maintenance overhead remains |
| Cost | Low — only instrumentation effort (~3 engineer-weeks) |

**Rejected because:** Does not achieve the committed DORA SLA targets. Measuring without changing does not move the metrics. The board commitment requires High band by Q3; this option reaches Low+ at best.

---

### Option B: Adopt GitHub Actions + DORA Instrumentation; Keep Release Windows and Manual Gates

**Description:** Migrate to GitHub Actions for improved CI performance. Instrument DORA metrics. Keep the Tuesday/Thursday release window and three manual approval gates.

| Dimension | Assessment |
|---|---|
| Migration risk | Medium — Jenkins → GitHub Actions migration for 47 services |
| DORA improvement | Deployment Frequency improves slightly (faster CI → teams deploy more often within windows). Lead Time improves from 8.4 days to ~3–4 days (gate wait unchanged; CI is faster). CFR: modest improvement if CI quality gates are added. MTTR: unchanged. |
| Achieves Q3 DORA SLA | Partially — Deployment Frequency and Lead Time may reach SLA. CFR and MTTR remain outside SLA. |
| Engineering toil | Partially reduced — Jenkins toil eliminated; release coordination toil unchanged |

**Rejected because:** Retaining release windows and manual gates preserves the primary drivers of high lead time and low deployment frequency. The 4-hour lead time SLA requires eliminating human gate wait time, not just reducing CI execution time. The 22% CFR requires automated rollback and canary deploys, which cannot be added without the pipeline refactor this option defers.

---

### Option C: Adopt Full GitOps Model (ArgoCD, Pull-Based Deployment)

**Description:** Replace push-based CI/CD with a GitOps model: a Git repository is the system of record for desired production state; ArgoCD continuously reconciles production to match the repo.

| Dimension | Assessment |
|---|---|
| DORA alignment | Excellent — GitOps is designed for high deployment frequency; Lead Time can reach < 1 hour |
| Audit trail | Excellent — all production state changes are Git commits; complete history |
| Migration risk | High — requires significant change to how all 47 teams think about deployments; steep learning curve |
| EKS dependency | Hard dependency — GitOps with ArgoCD requires Kubernetes; 14 services are not on EKS |
| Timeline | 16+ weeks to migrate and train all teams; incompatible with Q3 SLA deadline |
| Operational complexity | High — ArgoCD, application manifests, image update automation (ArgoCD Image Updater) all require platform team investment |

**Not rejected permanently — deferred to Q1 2027 roadmap.** GitOps is the correct long-term target architecture for the organisation once ADR-003 (EKS migration) is complete. The Q3 DORA SLA must be achieved first with the lower-risk GitHub Actions model. This ADR's Pillar 1 pipeline design is intentionally compatible with a future GitOps adoption: the shared workflow output (container image + version tag) is exactly what ArgoCD Image Updater consumes.

---

### Option D: Adopt a Commercial Deployment Platform (Harness, Spinnaker, or Octopus Deploy)

**Description:** Replace in-house pipeline logic with a commercial deployment platform that includes DORA measurement, canary deploys, and approval workflows as SaaS features.

| Dimension | Assessment |
|---|---|
| Feature completeness | High — DORA measurement, canary, rollback are all built in |
| Time to value | Medium — integration still requires per-service configuration |
| Cost | Harness enterprise: ~$400K/year at current scale. Spinnaker: open-source but significant self-hosting cost. |
| Vendor lock-in | High — pipeline logic moves into vendor-proprietary configuration |
| Customisation | Limited — platform enforces its own deployment model; teams with non-standard requirements are constrained |
| Differentiation | Low — building and running deployment pipelines is not a differentiator for this business |

**Rejected because:** Cost is not justified relative to the GitHub Actions model (GitHub Enterprise is already paid; shared workflows are zero marginal cost). Vendor lock-in on deployment logic creates significant switching cost risk. The platform team has the capability to build and maintain the shared workflow model without ongoing licensing cost.

---

## Decision Criteria Trade-off Summary

| Criterion | Chosen (GitHub Actions + Shared Workflows) | Option A (Jenkins + Instrumentation) | Option B (GitHub Actions + Keep Gates) | Option C (GitOps) | Option D (Commercial Platform) |
|---|---|---|---|---|---|
| Achieves Q3 DORA SLAs | ✅ All 4 metrics | ❌ 0 of 4 | ⚠️ 2 of 4 | ✅ All 4 (but too slow) | ✅ All 4 |
| Migration risk | Medium | Very Low | Medium | High | Medium |
| Timeline (Q3 2026) | ✅ Feasible | ✅ Feasible | ⚠️ Partial | ❌ Too slow | ⚠️ Uncertain |
| Long-term architectural fit | ✅ GitOps-compatible | ❌ Dead end | ⚠️ Partial | ✅ Best fit | ⚠️ Lock-in risk |
| Cost | Low (existing licence) | Very Low | Low | Low (OSS) | High |
| Engineering toil reduction | High | None | Medium | Very High | Medium |

---

## FAANG Interview Framing

> **"Tell me about a time you drove a process or tooling change that had measurable impact on your team's delivery velocity."**

This ADR is the artefact behind that answer. Key beats to hit:

- **Problem in business terms**: 22% CFR × 47 services = ~$850K/month in incident cost; DORA Low band committed to improve to High band at board level
- **Root cause depth**: the CFR wasn't a people problem — it was a gates problem (manually bypassable) and a rollback problem (no automated mechanism)
- **Options and trade-offs**: four alternatives evaluated; one deferred to the 2027 roadmap (GitOps) rather than rejected, preserving architectural optionality
- **Systemic outcome**: the solution leaves behind a shared workflow library that all 47 teams consume — not a one-time fix but a platform that improves automatically as the library improves
- **Measurable commitment**: DORA SLA targets are specific, time-bound, and board-visible — not "improve our pipeline" but "< 10% CFR and < 4-hour lead time by Q3 2026"

> **"How do you get buy-in for large infrastructure changes?"**

- Finance quantification ($850K/month incident cost) converted an engineering concern into a business case
- DORA metrics gave the VP Engineering a language to take to the board (not "we need better pipelines" but "we are committed to reaching High DORA band by Q3")
- The rollout plan's Phase 1 pilot (5 services, one per team) gave every team a voice in the process before company-wide enforcement
- The 30-day grace period for low-coverage services showed the platform team was not imposing an instant punitive standard — it was helping teams reach the standard
