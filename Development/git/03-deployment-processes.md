# Deployment Processes — Principal Engineer Depth

> Deployment is where Git meets production. This file covers the pipeline between a merged PR and a running service: environments, promotion gates, rollback, and the operational patterns FAANG companies use to ship safely at scale.

---

## 1. The Deployment Pipeline Model

```
Code merged to main
       │
       ▼
  ┌─────────┐    ┌─────────────┐    ┌──────────────┐    ┌──────────┐
  │  Build  │───▶│    Test     │───▶│    Stage     │───▶│  Prod    │
  │ (< 5m)  │    │ (< 15m)    │    │  (canary 1%) │    │ (100%)   │
  └─────────┘    └─────────────┘    └──────────────┘    └──────────┘
       │                │                  │                  │
   artifact          unit +            smoke +            full traffic
  published         integration        synthetic         monitoring
                     tests               tests
```

**Key principle:** Every stage must be a quality gate — if a stage fails, the pipeline stops. Never promote a broken artifact.

---

## 2. Environments

### Standard Environment Topology

| Environment | Purpose | Who deploys | Traffic | Data |
|-------------|---------|-------------|---------|------|
| **dev** | Developer sandboxes | Auto on branch push | None | Mocked / synthetic |
| **ci** | Automated testing | CI system | None | Ephemeral test data |
| **staging** | Pre-production validation | Auto on main merge | Mirrored synthetic | Anonymized prod copy |
| **canary** | Risk mitigation | Auto, gated by staging | 1–5% real users | Real prod data |
| **production** | Serves users | Auto, gated by canary | 100% | Real prod data |

### Promotion Gates

Each promotion requires:
1. **Artifact version match** — staging and prod deploy the exact same Docker image (by SHA, not tag)
2. **Automated tests pass** — unit, integration, smoke, contract
3. **Observability baseline** — error rate < threshold, p99 latency < SLO, no anomaly alerts
4. **Human approval** (optional, for high-risk changes) — senior engineer or release manager approves promotion

```yaml
# Example: GitHub Actions promotion gate
promote-to-production:
  needs: [deploy-staging, validate-staging]
  environment:
    name: production
    url: https://api.example.com
  steps:
    - name: Check staging error rate
      run: |
        ERROR_RATE=$(datadog-metrics get "service.error.rate" --env staging --last 15m)
        if [ "$ERROR_RATE" -gt "0.01" ]; then
          echo "Error rate $ERROR_RATE exceeds threshold, blocking promotion"
          exit 1
        fi
    - name: Deploy to production
      run: kubectl set image deployment/api api=$IMAGE_SHA
```

---

## 3. Deployment Strategies

### 3.1 Rolling Deployment (Default)

```
Before: [v1][v1][v1][v1][v1][v1]
Step 1: [v2][v1][v1][v1][v1][v1]
Step 2: [v2][v2][v1][v1][v1][v1]
...
After:  [v2][v2][v2][v2][v2][v2]
```

- Kubernetes default (`RollingUpdate` strategy)
- Gradual replacement of pods; no extra infrastructure cost
- Traffic is live throughout — good and bad pods serve simultaneously
- **Risk:** If v2 is bad, some requests hit it before you notice. Mixed-version traffic during rollout can cause issues if v1 and v2 are incompatible (schema changes, API contract breaks)

**When to use:** Stateless services with backward-compatible changes.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%          # create up to 25% extra pods during rollout
    maxUnavailable: 0      # never take pods down before new ones are ready
```

### 3.2 Blue/Green Deployment

```
Blue (v1): [v1][v1][v1]  ← currently serving 100% traffic
Green (v2): [v2][v2][v2] ← warm, idle, tested

Switch load balancer: Blue ← → Green

Blue (v1): [v1][v1][v1]  ← idle (kept for rollback)
Green (v2): [v2][v2][v2] ← now serving 100% traffic
```

- Zero-downtime cutover
- Instant rollback: flip load balancer back
- **Cost:** Double the infrastructure during deployment
- **Risk:** Database migrations — both versions must handle the current schema simultaneously; need backward-compatible schema changes

**When to use:** High-traffic services where gradual rollout risk is too high, or when instant rollback is required by SLA.

### 3.3 Canary Deployment

```
[Router]
  ├── 99% → [v1][v1][v1][v1][v1]  (stable)
  └──  1% → [v2]                   (canary)
```

Gradually shift traffic: 1% → 5% → 25% → 50% → 100%, with automated health checks at each step.

- Real user traffic validates new version
- Blast radius is contained
- Can A/B test performance improvements with real traffic
- **Risk:** 1% of users hit the bad version before detection. Mitigation: route canary to internal users first, then beta users, then general population.

**Automated progression example:**
```yaml
canary:
  steps:
    - setWeight: 1
    - pause: {duration: 5m}
    - analysis:              # auto-check before proceeding
        templates: [error-rate, latency-p99]
        threshold:
          successCondition: "result[0] < 0.01 && result[1] < 200"
    - setWeight: 10
    - pause: {duration: 10m}
    - setWeight: 25
    - pause: {duration: 10m}
    - setWeight: 100
```

**FAANG example:** Netflix uses canary deployments for every service change. Their Spinnaker pipelines automate the traffic shift with Kayenta (automated canary analysis using statistical comparison of canary vs baseline metrics).

### 3.4 Feature Flags (Dark Launches)

Decouple deploy from release. Code ships to 100% of servers but is off by default.

```java
if (flagService.isEnabled("new-payment-flow", userId)) {
    return newPaymentService.process(request);
} else {
    return legacyPaymentService.process(request);
}
```

**Flag rollout progression:**
```
Internal users (1%) → Beta users (5%) → 10% → 50% → 100%
                ↓ at each step: monitor error rate, latency, business metrics
```

**Tools:** LaunchDarkly, Statsig, Unleash, Flipt (open-source), Growthbook.

**Why principal engineers care about this:** Feature flags are the answer to "how do you ship incomplete features without a long-lived branch?" They're also the mechanism for:
- **Kill switches** — turn off a bad feature without a deploy
- **A/B testing** — measure impact before full rollout
- **Operational toggles** — disable expensive operations under load
- **Percentage rollouts** — gradual exposure to control blast radius

---

## 4. Rollback Strategies

### 4.1 Forward-Fix (Preferred)

Fix the bug in a new commit, deploy the fix. Simpler than rollback in most cases.

**When to forward-fix:**
- Bug is in application logic, not a data corruption issue
- Fix is fast (< 30 minutes to write, test, and deploy)
- Database migrations are already applied (rollback would require reversing migration)

### 4.2 Image Rollback

```bash
# Kubernetes: roll back to previous deployment
kubectl rollout undo deployment/api

# Roll back to a specific revision
kubectl rollout history deployment/api
kubectl rollout undo deployment/api --to-revision=3

# Verify rollback
kubectl rollout status deployment/api
```

**When to image-rollback:**
- Catastrophic failure (5xx rate > 10%, service down)
- No time to diagnose and fix
- No database migrations involved

### 4.3 Database Migration Rollback

The hard case. Forward-only migrations are safest:

```
v1: table has column `status VARCHAR(10)`
Migration: ALTER TABLE orders ADD COLUMN status_v2 VARCHAR(50)
v2: reads status_v2, writes to both status and status_v2
v3: reads status_v2 only, stops writing to status
Migration: DROP COLUMN status (safe now — v3 doesn't use it)
```

**Expand-Contract pattern:**
1. **Expand:** Add new column/table, old code still works
2. **Migrate:** Dual-write to old and new; backfill historical data
3. **Contract:** Remove old column once all services use new

This pattern makes database changes zero-downtime and rollback-safe at any stage.

### 4.4 Feature Flag Rollback (Fastest)

If the change is behind a feature flag, disable the flag. No deployment needed.

```bash
# LaunchDarkly CLI
launchdarkly flag update new-payment-flow --off

# Or: Statsig dynamic config override
statsig.overrideGate("new-payment-flow", false, userId="*")
```

---

## 5. CI/CD Pipeline Design

### 5.1 Pipeline Stages

```yaml
# Example: GitHub Actions multi-stage pipeline
stages:
  build:
    - checkout
    - compile
    - docker build + push (tag: git SHA)
    
  test:
    - unit tests (parallel, sharded)
    - integration tests (against test containers)
    - contract tests (Pact)
    - security scan (Snyk, Trivy)
    
  deploy-staging:
    - update Kubernetes manifests (image SHA)
    - wait for rollout
    - smoke tests
    - synthetic monitoring baseline
    
  deploy-canary:
    - update canary weight to 1%
    - automated canary analysis (15 min)
    - promote to 10%, 50%, 100%
    
  deploy-production:
    - requires manual approval for large changes
    - blue/green switch or rolling update
    - post-deploy validation
    - alert on error rate spike
```

### 5.2 Build Artifact Immutability

**Rule:** Build once, deploy everywhere. The same artifact (Docker image, JAR, binary) that passed CI should be what gets deployed to production, without rebuilding.

```bash
# Tag images by git SHA — never by "latest" or branch name
IMAGE="registry.example.com/api:$(git rev-parse HEAD)"
docker build -t $IMAGE .
docker push $IMAGE

# Promote: update the Kubernetes manifest to point to this SHA
# Never rebuild the image for staging → prod promotion
```

**Why:** Rebuilding introduces variability (different dependency versions, different compile-time values). Immutable artifacts guarantee "what you tested is what you ship."

### 5.3 GitOps

Treat infrastructure as code in Git. Deployments happen by merging to the infra repo, not by running CLI commands.

```
┌─────────────────────┐      ┌─────────────────────┐
│   Application Repo  │      │   Config/Infra Repo  │
│                     │      │                     │
│  PR merged → image  │─────▶│  Bump image tag in  │
│  built + pushed     │      │  values.yaml → PR   │
└─────────────────────┘      └──────────┬──────────┘
                                         │ merged
                                         ▼
                              ┌─────────────────────┐
                              │   ArgoCD / Flux     │
                              │   syncs cluster to  │
                              │   repo state        │
                              └─────────────────────┘
```

**Tools:** ArgoCD, Flux, Tekton.

**Benefits:** Full audit trail of what was deployed when (Git history). Rollback = revert the manifest PR. Disaster recovery = recreate cluster from Git state.

---

## 6. DORA Metrics — How You Measure Deployment Health

| Metric | Elite (FAANG) | High | Medium | Low |
|--------|--------------|------|--------|-----|
| **Deployment frequency** | Multiple/day | Daily–weekly | Weekly–monthly | Monthly+ |
| **Lead time for changes** | < 1 hour | 1 day – 1 week | 1–6 months | > 6 months |
| **Change failure rate** | < 5% | 5–10% | 10–15% | > 15% |
| **Time to restore** | < 1 hour | < 1 day | < 1 week | > 1 week |

**How to use in interviews:** These are the four metrics Google DevOps Research (DORA) identified as predictive of organizational performance. Use them when asked "how do you know your deployment process is working?" — don't just say "we have CI/CD," say "we track deployment frequency and change failure rate; our goal is > 10 deploys/day and < 5% CFR."

---

## 7. Common Deployment Failure Modes

| Failure | Root cause | Prevention |
|---------|-----------|-----------|
| Config mismatch between envs | Env-specific config baked into image | Externalize config (env vars, ConfigMaps, Secrets Manager) |
| Works in staging, breaks in prod | Different load, different data volumes | Load test in staging; use prod traffic mirroring (shadow mode) |
| Slow rollback | Manual steps, unclear runbook | Automate rollback; test it quarterly (chaos engineering) |
| Database migration blocks deployment | Long-running ALTER TABLE locks table | Online schema change tools (pt-online-schema-change, gh-ost); expand-contract pattern |
| Deployment causes cascading failure | New version has resource leak | Canary + automated rollback on error rate threshold |
| "Works on my machine" | Local env diverges from prod | Dev containers (devcontainer), parity checks |

---

## 8. Monorepo Deployment Considerations

When all services live in one repo:

- **Build only what changed:** Bazel, Nx, Turborepo — compute affected services from the diff
- **Deploy only affected services:** CI computes the dependency graph; upstream changes trigger downstream deploys
- **Independent deployment despite shared code:** Each service has its own Dockerfile and deployment pipeline; shared library changes trigger all dependent service pipelines

**Example:**
```bash
# Determine changed services
CHANGED=$(bazel query "rdeps(//..., set($(git diff --name-only HEAD^ HEAD | tr '\n' ' ')))")

# Deploy only changed services
for service in $CHANGED; do
  trigger-deploy $service
done
```

---

## 9. Security in Deployment

- **Signed commits + images:** Use `cosign` to sign Docker images; verify signature before deploy
- **SBOM (Software Bill of Materials):** Generate on build, attach to image; required for SLSA Level 2+
- **Secrets management:** Never in Git. Use AWS Secrets Manager, HashiCorp Vault, or GCP Secret Manager. Inject at runtime, not build time
- **Least-privilege CI:** CI service account has write access only to its own ECR repo, not all repos
- **Supply chain security (SLSA):** Levels 1–4 define how much you can trust a build artifact came from the expected source code

---

## FAANG Interview Callouts

**"Walk me through how you'd deploy a change to a service that handles 10M requests/day with no downtime."**
→ Canary deployment. Build immutable image (tagged by git SHA). Deploy to staging, run smoke tests. Shift 1% of prod traffic to canary, monitor error rate and p99 latency for 15 minutes via automated analysis (Kayenta/Grafana). If clean, progress 1→10→50→100%. If threshold breached at any step, automated rollback via ArgoCD. Zero downtime because old pods serve until new ones are healthy.

**"How do you handle a production incident caused by a bad deploy?"**
→ First: is the change behind a feature flag? Turn it off immediately (fastest, no deploy needed). If not: is it a stateless change? `kubectl rollout undo` — takes ~2 minutes. If database migration was involved: forward-fix is safer than reversing the migration. Simultaneously: page on-call, start incident bridge, post to status page. Post-incident: add automated rollback trigger to pipeline so next time it's automatic.

**"Your team is merging 50 PRs/day. How do you keep deployments stable?"**
→ Trunk-based development + feature flags for incomplete features. Every PR triggers its own CI + staging deploy. Main is always green (branch protection + required CI). Production deployments are automated with canary analysis. DORA metrics reviewed weekly — if change failure rate climbs above 5%, we slow down and invest in test coverage. The goal is to make deploying boring.
