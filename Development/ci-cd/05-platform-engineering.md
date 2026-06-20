# Platform Engineering & Internal Developer Platform

## The Core Problem

At 500+ engineers, every team reinventing their CI/CD pipeline is:
- Expensive (500 engineers × 5% time on infra = 25 FTE of wasted capacity)
- Inconsistent (some teams have great pipelines, others have none)
- Risky (team with no observability is running blind in production)

**Platform engineering** solves this by treating the internal developer platform (IDP) as a product — with an SLO, a roadmap, and customers (your developers).

**Principal engineer framing**: designing the IDP architecture, the "golden path" opinionated workflow, and the self-service primitives is a staff/principal problem. It directly affects org-wide engineering velocity.

---

## The Internal Developer Platform (IDP)

An IDP is the collection of tools, services, and abstractions that let engineers focus on business logic instead of infrastructure.

```
                    ┌──────────────────────────────────────────┐
                    │         Developer Portal (Backstage)      │
                    │  Service catalog, docs, templates, APIs   │
                    └──────────────────────┬───────────────────┘
                                           │
            ┌──────────────────────────────┼──────────────────────────────┐
            │                             │                              │
   ┌────────▼──────────┐      ┌───────────▼───────────┐    ┌────────────▼───────────┐
   │  Golden Path CI   │      │  Self-Service Infra   │    │  Observability Stack   │
   │  (pre-built       │      │  (provision DB, queue,│    │  (metrics, logs,       │
   │   pipeline        │      │   cache via API/UI)   │    │   traces, alerts)      │
   │   templates)      │      └───────────────────────┘    └────────────────────────┘
   └───────────────────┘
```

---

## The Golden Path

A "golden path" is the opinionated, well-lit route through the platform. Using it means your service gets:
- CI pipeline with all quality gates configured
- Kubernetes deployment manifests
- Observability (logs, metrics, traces) wired up out of the box
- On-call rotation and alert routing
- RBAC and secrets management

**The goal**: a new engineer can have a production-ready service running in < 1 day, with zero infra expertise required.

```
Developer:  backstage new-service --template java-api --name payment-processor
Platform:   ✓ GitHub repo created with golden path Jenkinsfile
            ✓ Kubernetes namespace provisioned
            ✓ ArgoCD app created (GitOps)
            ✓ Prometheus metrics endpoint configured
            ✓ PagerDuty escalation policy created
            ✓ Datadog dashboard scaffolded
            ✓ Secrets store namespace created
            → First deploy: git push to trunk
```

### Golden path vs. paved path

- **Golden path**: one opinionated way. Teams are strongly encouraged to use it.
- **Paved path**: well-supported options. Teams choose from menu.

Prefer golden path when you need to move fast and have a clear best practice. Allow paved paths for legitimate specialization (e.g., data engineering pipelines look different from microservices).

---

## Platform Team Mandate

Platform teams serve engineering teams. Wrong mandate: "enforce compliance." Right mandate: "make the right way the easy way."

### Team Topologies (relevant)

```
Platform Team ─────────────────────── Stream-Aligned Teams (product teams)
(provides X-as-a-Service)              (consume platform primitives)

     │                                        │
     │  ← feedback loop (treat devs as       │
     │    customers, track adoption %)        │
     └────────────────────────────────────────┘
```

**Platform team OKR example**:
- Objective: Reduce time to first production deploy for new services
- KR1: New service → prod in < 4 hours (from 2 days)
- KR2: 90% of services using golden path pipeline (from 60%)
- KR3: Pipeline-related on-call interruptions < 2/week (from 8/week)

---

## Self-Service Infrastructure

At FAANG, engineers don't file tickets to provision a database. They declare what they need, and the platform provisions it.

### Approach 1: Infrastructure as Code + GitOps

```yaml
# teams/payment/infra/database.yaml
apiVersion: platform.company.com/v1
kind: PostgresDatabase
metadata:
  name: payment-db
  team: payment-team
spec:
  size: medium          # maps to RDS instance type
  region: us-east-1
  backup: daily
  replicas: 1
  version: "15"
```

Engineer opens a PR. Platform validates (size limits, naming conventions). Merge → Terraform applies → database provisioned. No ticket required.

### Approach 2: Service Catalog API

```bash
# Developer CLI
platform provision database \
  --type postgres \
  --name payment-db \
  --team payment \
  --size medium

# Response
Provisioning payment-db...
Estimated time: 3 minutes
Track: https://platform.company.com/provisioning/abc123
```

### Guardrails built into self-service

- Size quotas per team (can't provision 100 xlarge instances without approval)
- Required tags (team, cost center, environment)
- Automated cost attribution (infra bill visible per team)
- Security controls enforced at provisioning (encryption at rest, not optional)

---

## Developer Portal: Backstage

Backstage (open-source, Spotify-created, CNCF project) is the de facto standard for developer portals.

### Core features

```
Service Catalog:    Register all services, APIs, libraries with metadata
Software Templates: Scaffold new services from golden path templates
TechDocs:          Docs-as-code, served alongside the service
Search:            Find any service, API, team, runbook
```

### Why it matters at scale

With 1,000 services, finding "who owns this thing and where's the runbook" becomes a real problem. Backstage solves the discoverability problem without requiring everyone to maintain separate wikis.

---

## CI/CD Platform Architecture at Scale

### Challenge: 500 teams, 50,000 deploys/day

```
CI/CD Requirements:
- 50,000 pipeline runs/day
- Each run: 10 min average → 500k compute-minutes/day
- Peak: 5× average (deploy early in day, slow at night)
- Artifact storage: 50k artifacts/day, 90-day retention
```

### Architecture decisions

**Ephemeral CI agents** (not persistent VMs):
- Kubernetes-based CI (GitHub Actions + ARC, Jenkins + Kubernetes plugin)
- Agent spins up per job, terminates after
- Benefit: no state contamination, auto-scaling, cost proportional to use
- Cost: cold start per job (~30s). Mitigate with warm pools for common agent types.

**Distributed caching**:
```
Maven/Gradle cache     → S3 or GCS, keyed by dependency hash
Docker layer cache     → registry mirror, layer reuse across builds
Test result cache      → skip re-running tests if no code changes (Bazel/Gradle)
```

**Artifact lifecycle**:
```
Build → registry (immutable)
Deploy → referenced by digest, not tag
Retention: 90 days for non-prod, 1 year for prod releases, indefinite for major versions
Deletion: automated cleanup via lifecycle policy
```

---

## Platform Metrics (Treating Platform as a Product)

| Metric | Description | Target |
|--------|-------------|--------|
| Time to first deploy | New repo → first prod deploy | < 4 hours |
| Pipeline success rate | % of pipeline runs that succeed | > 95% |
| Mean pipeline duration | Avg time per run | < 15 min |
| Golden path adoption | % services using standard templates | > 85% |
| Self-service success rate | % infra requests fulfilled without human intervention | > 95% |
| Dev portal MAU | Monthly active users of Backstage | Trending up |
| Infra provisioning time | From request to ready | < 10 min for standard resources |

**Run quarterly developer experience surveys.** NPS for the platform is a leading indicator of adoption and problems.

---

## Common Platform Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Platform team as gatekeepers | Slow approvals, bottleneck, resentment | Self-service with automated guardrails |
| One-size-fits-all pipeline | Doesn't work for ML, data, mobile | Golden path + opt-out for special cases |
| Platform without customer focus | Build features nobody uses | OKRs tied to adoption, NPS, time-to-prod |
| Forced migration without migration support | Teams stranded on old tooling | Migration tooling + dedicated support window |
| Toil outsourced to platform | Platform becomes a manual ticket queue | Automate anything done > 5 times |

---

## FAANG Interview Callouts

**Q: How would you build a platform that lets 500 engineering teams deploy independently without coordination?**

Three pillars:
1. **Golden path templates**: enforce standards at scaffold time, not review time
2. **Automated quality gates**: tests, security scans, SLO checks — no human approval in the critical path
3. **Blast radius isolation**: services run in separate namespaces with network policies; one bad deploy can't impact another team

Org design matters too: platform team is funded as infrastructure, not as a cost center allocating to product teams. They ship like a product team (roadmap, OKRs, changelog).

**Q: A team says the golden path doesn't work for their ML pipeline. How do you handle it?**

Listen first — understand the gap. Options:
1. If multiple teams have this need → build ML pipeline template as a first-class golden path variant
2. If one team, niche use case → support a "paved path" with documented divergence and team ownership
3. If it's resistance to standards without technical justification → hold the line, bring data on why standards help

Never force a golden path that doesn't fit the use case. That drives teams to shadow infrastructure (self-managed clusters, personal AWS accounts) — worse than a managed divergence.

**Q: The platform team's pipeline has a bug that blocks all 500 teams from deploying. How do you handle it?**

This is why the platform itself needs an SLO (e.g., 99.9% pipeline availability). Response:
1. Immediate: communication blast to all eng teams, status page update
2. Mitigation: is there a workaround (manual deploy path)?
3. Fix: hot patch the pipeline definition, validate in shadow env first
4. Post-mortem: what testing would have caught this? Add it to platform's own pipeline

The platform team eating their own dog food (using the golden path for the platform itself) catches many of these issues before they reach customers.
