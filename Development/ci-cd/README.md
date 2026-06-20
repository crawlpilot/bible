# CI/CD — Pipeline Design & Deployment Engineering

> Principal engineer scope: not "how do I write a Jenkinsfile" but "how do I design a deployment system that lets 500 engineers ship safely 100× per day."

---

## Contents

| File | Topic |
|------|-------|
| [01-pipeline-design.md](01-pipeline-design.md) | Pipeline architecture, stages, trunk-based development, DORA metrics, same pipeline in Jenkins/GitHub Actions/CodePipeline |
| [02-deployment-strategies.md](02-deployment-strategies.md) | Blue-green, canary, rolling, feature flags — when to use each |
| [03-feature-flags.md](03-feature-flags.md) | Flag systems design, lifecycle management, kill switches |
| [04-release-gates-and-slos.md](04-release-gates-and-slos.md) | Automated quality gates, SLO-based progressive delivery |
| [05-platform-engineering.md](05-platform-engineering.md) | Internal developer platform, golden path, self-service infra |
| [06-ci-cd-tools-comparison.md](06-ci-cd-tools-comparison.md) | Jenkins, GitHub Actions, AWS CodeDeploy/CodePipeline, GitLab CI, ArgoCD — advantages, disadvantages, trade-offs, real config examples |
| [07-dora-metrics.md](07-dora-metrics.md) | DORA metrics deep-dive — purpose, measurement, how Amazon/Google/Meta/Netflix use them, improvement playbook, pitfalls |

---

## Mental Model: The Deployment Value Stream

```
Code Commit → Build → Test → Artifact → Deploy → Observe → Release
     │          │       │        │          │         │         │
   trunk      fast    multi    immutable  automated  metrics  traffic
   based      <5m     layer    image      stages     first     split
```

The goal at principal scope: **maximize deployment frequency while minimizing MTTR and change failure rate.**

---

## DORA Metrics — The North Star

| Metric | Elite | High | Medium | Low |
|--------|-------|------|--------|-----|
| Deployment Frequency | On-demand (multiple/day) | Weekly | Monthly | < Monthly |
| Lead Time for Changes | < 1 hour | 1 day–1 week | 1 week–1 month | > 1 month |
| Change Failure Rate | 0–5% | 5–10% | 10–15% | > 15% |
| MTTR | < 1 hour | < 1 day | < 1 week | > 1 week |

**Elite = FAANG bar.** If your pipeline can't support this, it's a principal-level problem to fix.

---

## Key Trade-offs at a Glance

| Decision | Option A | Option B | Recommendation |
|----------|----------|----------|----------------|
| Branching | Feature branches (long-lived) | Trunk-based dev | Trunk-based at scale |
| Deployment unit | Monolith per team | Microservice per service | Match org structure (Conway's Law) |
| Rollout control | Manual gates | Automated SLO gates | Automated with human escape hatch |
| Config management | Baked into image | Externalized (ConfigMap/Secrets) | Always externalize |
| Environments | Many (dev/qa/stage/prod) | Few (trunk/prod) | Fewer with better observability |

---

## FAANG Interview Callouts

- **Google**: "How does Borg/GKE enable zero-downtime deploys at 1B+ users?" → immutable containers + rolling updates + readiness probes
- **Meta**: "How do you ship to 3B users safely?" → feature flags at the core of every release, not bolted on
- **Amazon**: "Two-pizza team, one-click deploy" → each team owns their pipeline, platform team provides primitives
- **Netflix**: "Canary analysis with Kayenta" → automated metric comparison between baseline and canary to gate progression
