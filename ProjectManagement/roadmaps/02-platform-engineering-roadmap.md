# Sample Roadmap: Platform Engineering Team

## Context

**Organization**: 300-engineer product company, 25 product teams, AWS infrastructure.

**Current state (problems to solve)**:
- Mean deployment pipeline duration: 48 minutes (industry elite: < 10 min)
- Golden path adoption: 35% of services (60% running custom pipelines)
- On-call burden: 12 pages/week/engineer (healthy: < 5)
- Observability: logging only — no distributed tracing, no SLO dashboards
- Developer NPS for platform: -12 (healthy: > 30)
- New service time-to-first-deploy: 3 days (healthy: < 4 hours)

**Desired state (18 months)**:
- Mean pipeline duration < 12 minutes, 95th percentile < 20 minutes
- 90% golden path adoption across all services
- On-call burden < 3 pages/week/engineer
- Full observability stack: metrics + logs + traces + SLO dashboards
- Developer NPS > 35
- New service time-to-first-deploy < 4 hours (self-service, no tickets)

---

## Strategic Themes

| Theme | Rationale |
|-------|-----------|
| **Developer Velocity** | 48-min pipelines cost 300 engineers ~2 hours/day in wait time = $15M/yr in lost productivity |
| **Reliability** | 12 pages/week = engineers burning out; incidents eroding user trust |
| **Self-Service** | Platform team bottleneck: 60% of requests are provisioning tickets solvable by self-service |
| **Observability** | No SLO dashboards = teams don't know they're breaking their SLA until customers complain |

---

## Full 18-Month Roadmap

### NOW — H1 (Q1–Q2)

**Initiative 1: CI/CD Pipeline Overhaul**
- **Goal**: reduce mean pipeline from 48 → 20 minutes
- **Approach**: parallel test execution, Docker layer caching, dependency caching (Maven/Gradle), eliminate redundant stages
- **Owner**: Alice (Platform Lead)
- **Effort**: 3 engineers × 10 weeks
- **Success metric**: mean pipeline < 20 min for 80% of services using standard template
- **Dependencies**: none (can start immediately)
- **Risk**: legacy services with non-standard build tooling (Ant, custom scripts) — handle separately after core migration

**Initiative 2: Backstage Developer Portal — Phase 1**
- **Goal**: single place to discover all services, APIs, and runbooks; service onboarding in < 4 hours via template
- **Approach**: deploy Backstage, import existing service catalog from GitHub/PagerDuty, create 3 golden-path templates (Java API, Python worker, Go service)
- **Owner**: Bob (Platform Engineer)
- **Effort**: 2 engineers × 8 weeks
- **Success metric**: 100% of new services onboarded via Backstage template; service catalog 95% complete
- **Dependencies**: GitHub org access, PagerDuty API, AWS account list
- **Risk**: catalog data quality — many services have no README or owner metadata

**Initiative 3: Alert Noise Reduction Program**
- **Goal**: reduce on-call pages from 12/week to < 5/week
- **Approach**: audit all existing alerts, classify (actionable / informational / noise), remove or downgrade noise alerts, set proper thresholds via 30-day baseline
- **Owner**: Carol (SRE Lead)
- **Effort**: 2 engineers × 6 weeks
- **Success metric**: pages/week/engineer < 5; false positive rate < 5%
- **Dependencies**: access to all service alert configs (multi-team coordination required)
- **Risk**: teams may resist alert removal without understanding the noise problem

**Initiative 4: Secrets Management Standardization**
- **Goal**: eliminate hardcoded secrets; all services use Vault or AWS Secrets Manager
- **Approach**: audit current state, classify secrets by risk tier, migrate high-risk (prod DB creds, API keys) first, provide SDK + migration guide
- **Owner**: Dave (Security Platform)
- **Effort**: 2 engineers × 12 weeks (ongoing through H2)
- **Success metric**: 0 hardcoded secrets in production config; critical secret rotation automated
- **Dependencies**: security audit (in progress), Auth team for Vault namespace design

---

### NEXT — H2 (Q3–Q4)

**Initiative 5: Observability Platform**
- **Goal**: full-stack observability — metrics (Prometheus/Grafana), logs (existing ELK), traces (Jaeger/Tempo), SLO dashboards
- **Approach**: deploy Prometheus + Grafana, instrument top 30 services with OpenTelemetry, build SLO dashboard template, train teams
- **Owner**: Alice
- **Effort**: 4 engineers × 16 weeks
- **Success metric**: 30 critical services with distributed traces; SLO dashboard for all tier-1 services; mean MTTD from 45 min to < 5 min
- **Dependencies**: H1 golden path pipeline (instrumentation baked into template); Kubernetes (services need stable IPs for scrape targets)
- **Risk**: OpenTelemetry SDK adds ~5% overhead — validate with load testing before rollout

**Initiative 6: CI/CD Pipeline — Target State (< 12 min)**
- **Goal**: complete the pipeline optimization started in H1; reach < 12 min mean for all golden-path services
- **Approach**: H1 got to 20 min; H2 targets: incremental builds (Gradle/Bazel), test sharding across agents, artifact caching in S3, warm agent pools
- **Owner**: Bob
- **Effort**: 2 engineers × 8 weeks
- **Success metric**: mean pipeline < 12 min for 90% of services; p95 < 20 min
- **Dependencies**: H1 pipeline migration complete

**Initiative 7: Self-Service Infrastructure (Phase 1)**
- **Goal**: teams provision databases and queues without filing tickets to platform team
- **Approach**: infrastructure-as-code templates in Backstage (PostgreSQL, SQS, ElastiCache, S3), Terraform automation, cost guardrails
- **Owner**: Dave
- **Effort**: 3 engineers × 10 weeks
- **Success metric**: 80% of standard infra requests fulfilled via self-service (zero tickets); provisioning time < 10 minutes
- **Dependencies**: Backstage (H1 Initiative 2); Terraform modules for standard resources; IAM guardrails design
- **Risk**: teams over-provision without cost visibility; add cost dashboard to Backstage simultaneously

**Initiative 8: SLO Framework and Error Budget Gates**
- **Goal**: every tier-1 service has defined SLOs; automatic deploy gate when error budget is burning fast
- **Approach**: SLO template library, error budget calculation (Sloth/SLO generator), pipeline gate integration
- **Owner**: Carol
- **Effort**: 2 engineers × 8 weeks
- **Success metric**: 100% of tier-1 services with defined SLOs; 0 deploys proceed when error budget < 5%
- **Dependencies**: H2 observability platform (SLOs require metrics); H1 pipeline (gate integration)

---

### LATER — H3 (2027+)

*(Directional — not scheduled. Will be refined in Q4 planning.)*

**Capability: Service Mesh (Istio / Linkerd)**
- Zero-trust mTLS between all services, traffic management, circuit breaking at the mesh layer
- Pre-requisite: 100% Kubernetes adoption (H1 batch 1 + H2 batch 2 must complete)
- Rough effort: 4 engineers × 6 months

**Capability: Canary Delivery Platform**
- Automated progressive delivery with metric-based canary analysis (Argo Rollouts + Kayenta-style)
- Pre-requisite: H2 observability platform (canary analysis needs metrics)
- Rough effort: 3 engineers × 4 months

**Capability: FinOps / Cost Attribution**
- Per-team, per-service infrastructure cost dashboards; automated rightsizing recommendations
- Pre-requisite: H2 self-service infra (need consistent resource tagging)
- Rough effort: 2 engineers × 3 months

**Capability: Chaos Engineering Program**
- Controlled failure injection in staging (Chaos Monkey, Gremlin), gameday exercises
- Pre-requisite: H2 SLO framework (need SLOs to define "working" before injecting chaos)
- Rough effort: 2 engineers × 4 months (ongoing program)

---

## Dependency Graph

```
H1: Pipeline v1 ──────────────────────►  H2: Pipeline v2 (< 12 min)
         │
         └──────────────────────────────►  H2: SLO gates (pipeline integration)

H1: Backstage ────────────────────────►  H2: Self-service infra (runs in Backstage)

H1: Alert reduction ──────────────────►  H2: SLO framework (cleaner signal)

H2: Observability ────────────────────►  H3: Canary delivery (needs metrics)
                  ────────────────────►  H3: Chaos engineering (needs SLOs)

H1+H2: K8s adoption (external team) ──►  H3: Service mesh (needs 100% K8s)

H2: Self-service infra ───────────────►  H3: FinOps / cost attribution (needs tags)
```

---

## Resource Plan

```
Team composition: 8 engineers (Alice-lead, Bob, Carol-SRE, Dave-security, 4 platform eng)

Q1 allocation:
  Pipeline overhaul (Alice + 2 eng):   37.5%
  Backstage phase 1 (Bob + 1 eng):     25%
  Alert reduction (Carol + 1 eng):     25%
  Secrets mgmt (Dave):                 12.5%

Q2 allocation:
  Pipeline completion (Bob + 1 eng):   25%
  Secrets completion (Dave + 1 eng):   25%
  Backstage phase 2 (Alice + 1 eng):   25%
  Observability planning (Carol):      12.5%
  Capacity reserve (on-call/unplanned):12.5%

Q3–Q4 allocation:
  Observability (Alice + Carol + 2):   50%
  Self-service infra (Dave + 2):       37.5%
  SLO framework (Carol + 1):          12.5%

Total: 8 engineers × 4 quarters = 32 eng-quarters
H1 committed: 13 eng-quarters
H2 planned: 15 eng-quarters
H3 reserved: (will be staffed based on H2 completion)
```

---

## Risks and Mitigations

| Risk | Likelihood | Timeline Impact | Mitigation |
|------|------------|-----------------|------------|
| Product teams resist golden path adoption | High | +4–8 wks (H2) | Publish velocity benchmarks; teams on golden path demonstrably faster |
| Backstage catalog data is too incomplete to be useful at launch | Medium | +3 wks | Seed catalog from GitHub org + PagerDuty automation before launch |
| OpenTelemetry SDK performance overhead blocks observability rollout | Medium | +4 wks | Load test with 10% sample before org-wide mandate |
| Auth team cannot staff Vault namespace work in Q1 | High | +6 wks on secrets | Design Vault namespace to not require Auth team; only need key rotation API |
| K8s adoption by product teams slower than expected | Medium | H3 service mesh moves to 2028 | Run K8s adoption incentive program in parallel with migration team |

---

## Success Milestones

| Milestone | Target Date | Signal |
|-----------|-------------|--------|
| 50% of services on golden path pipeline | End of Q1 | Pipeline adoption tracking in Backstage |
| Mean deploy time < 20 min | End of Q1 | Pipeline duration P50 metric |
| Developer NPS > 10 | End of Q2 | Quarterly eNPS survey |
| On-call burden < 5 pages/wk | End of Q2 | PagerDuty weekly report |
| 100% new services via Backstage self-service | End of Q2 | Backstage service creation events |
| 30 services with distributed tracing | End of Q3 | Jaeger/Tempo coverage dashboard |
| All tier-1 services with SLO dashboards | End of Q4 | SLO registry completeness |
| Developer NPS > 35 | End of Q4 | Quarterly eNPS survey |

---

## What Is NOT on This Roadmap (and Why)

**Multi-cloud (Azure/GCP) portability**
Evaluated in Q4 last year. Decision: not cost-effective at current scale. AWS-only until we exceed $50M/year in AWS spend, at which point leverage outweighs migration cost. Revisit in 2027 annual planning.

**On-premise / hybrid cloud**
No compliance requirement mandating it. Would add 2+ years to every initiative. Revisit only if legal/compliance requires data residency outside cloud.

**Full monolith decomposition**
This is a product-eng initiative, not a platform initiative. Platform will provide the primitives (K8s, service mesh, observability) that enable decomposition — the decomposition itself is owned by each product team's principal engineer.

**Custom ML infrastructure (GPUs, training pipelines)**
Separate initiative owned by the ML Platform team. This roadmap covers general-purpose infrastructure. ML infra has distinct requirements and its own roadmap.
