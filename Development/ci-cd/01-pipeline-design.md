# CI/CD Pipeline Design

## The Core Problem

A naive pipeline is a linear script: build → test → deploy. At scale, that breaks because:
- 500 engineers commit concurrently — sequential pipelines become the bottleneck
- A 30-minute test suite makes trunk unstable (everyone waits or works around it)
- Flaky tests create false signal — engineers learn to ignore failures
- No artifact traceability — you can't answer "what exact code is in prod right now?"

**Principal engineer framing**: the CI/CD pipeline is infrastructure. It needs an SLO, an owner, and an architecture review like any production system.

---

## Pipeline Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 4: RELEASE (Traffic control — feature flags, canary)     │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 3: DEPLOY (Environment promotion — staging → prod)       │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 2: ARTIFACT (Build once, deploy many — immutable image)  │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 1: VERIFY (Fast feedback — compile, lint, unit tests)    │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 0: COMMIT (Pre-commit hooks, branch policy)              │
└─────────────────────────────────────────────────────────────────┘
```

**Key invariant**: each layer produces an immutable artifact that the next layer consumes. Never rebuild from source at deploy time.

---

## Stage Design: Speed vs. Confidence

### Stage 1 — Commit Stage (< 5 minutes SLO)

Goal: kill obviously broken commits fast.

```yaml
stages:
  - compile               # fail immediately on syntax/type errors
  - lint                  # style, static analysis (spotbugs, checkstyle)
  - unit-tests            # in-memory, no I/O, fast
  - package               # produce versioned artifact (jar/image)
```

**Failure here**: block the author immediately. No one else is impacted.

**Anti-patterns**:
- Running integration tests here (too slow, too fragile)
- Not parallelizing across modules
- Re-downloading dependencies every run (cache them)

### Stage 2 — Acceptance Stage (< 20 minutes SLO)

Goal: verify the artifact behaves correctly end-to-end.

```yaml
stages:
  - spin-up-test-env      # ephemeral env from the artifact built in Stage 1
  - integration-tests     # real DB, real message broker, fake external services
  - contract-tests        # Pact or Spring Cloud Contract — API compatibility
  - performance-baseline  # p99 latency regression check vs. last green build
```

**Key decisions**:
- Ephemeral environments (spin up/down per build) vs. shared long-lived — prefer ephemeral to eliminate env contamination
- Parallelism: fan out test suites across N agents

### Stage 3 — Artifact Registry

```
artifact = git-sha + branch + build-number + timestamp
image:   registry.company.com/service:v1.2.3-abc1234
manifest: sbom.json (software bill of materials)
```

Tag with Git SHA, never `latest`. `latest` is undefined in production.

### Stage 4 — Environment Promotion

```
trunk → staging (auto)
staging → canary (auto, if staging passes SLO gate)
canary → production (auto or manual gate based on risk tier)
```

---

## Trunk-Based Development vs. Feature Branches

| | Trunk-Based | Long-lived Feature Branches |
|---|---|---|
| Integration pain | Continuous, small | Big bang at merge |
| CI feedback loop | Immediate | Delayed until branch merges |
| Deployment frequency | High | Low (tied to branch lifecycle) |
| Required discipline | Feature flags for incomplete work | None (just don't merge) |
| At scale (500+ engineers) | Works well | Merge conflicts become tax |
| DORA correlation | Elite performers | Medium/Low performers |

**Recommendation**: Trunk-based development + feature flags for incomplete features. This is the Google, Meta, and Amazon model.

**Enabling practices**:
1. **Short-lived branches**: < 1 day lifespan, then merge to trunk behind a flag
2. **Branch by abstraction**: refactor in place on trunk without breaking API contract
3. **Expand-contract pattern**: for breaking changes — add new → migrate consumers → remove old

---

## Test Strategy: The Pyramid

```
                    /\
                   /  \
                  / E2E \        ~5%  — slow, fragile, high value only for critical paths
                 /────────\
                /Integration\    ~20% — real dependencies, ephemeral envs
               /──────────────\
              /   Unit Tests    \  ~75% — fast, isolated, deterministic
             /──────────────────\
```

**Principal insight**: The pyramid is often inverted in legacy systems (heavy E2E, no unit tests). Fixing it is a 6-month architectural initiative, not a sprint task. Lead it with data: measure test execution time, flakiness rate, and failure-to-defect signal ratio.

### Flaky Test Management

Flaky tests are worse than no tests — they train engineers to ignore CI red.

Remediation strategy:
1. **Quarantine**: move flaky tests to a separate suite, don't block trunk
2. **Track**: flakiness rate dashboard per test, per team
3. **SLO for test health**: e.g., no suite > 2% flakiness before sprint end
4. **Root cause**: most flakiness = timing dependencies, shared state, external I/O

---

## Pipeline as Code: Key Principles

### 1. Version-controlled pipeline definition
Pipeline config lives in the repo (`Jenkinsfile`, `.github/workflows/`, `.gitlab-ci.yml`). Pipeline changes go through PR review like application code.

### 2. Parameterized, not scripted
Prefer declarative pipelines (YAML-driven) over imperative scripts. Scripts become unmaintainable; declarative pipelines are auditable.

### 3. DRY via shared libraries / reusable workflows
```yaml
# GitHub Actions example
jobs:
  build:
    uses: org/shared-workflows/.github/workflows/java-build.yml@main
    with:
      java-version: '21'
      run-integration-tests: true
```

Centralize boilerplate. Each team shouldn't rewrite build logic.

### 4. Secrets management
Never hardcode secrets. Use:
- HashiCorp Vault (FAANG-grade)
- AWS Secrets Manager / GCP Secret Manager
- CI/CD platform secrets (GitHub Actions secrets, Kubernetes Secrets)

Rotate secrets automatically. Alert on age > policy threshold.

---

## Artifact Management

### Immutable artifacts

```
Build time:  git-sha → Docker image (tagged with sha)
Deploy time: pull image by sha, NOT by tag
Prod:        running sha is auditable → maps back to exact commit
```

Never allow rebuilding from source at deploy time. If you rebuild, you can't guarantee what you're shipping.

### Software Bill of Materials (SBOM)

At FAANG scale, you need to answer "are we running Log4j 2.14.1?" within minutes of a zero-day. SBOM enables this.

```bash
# Generate during build
syft <image> -o cyclonedx-json > sbom.json

# Query
grype sbom:sbom.json --fail-on critical
```

---

## Monitoring the Pipeline Itself

The pipeline is infrastructure — it needs its own observability.

| Metric | Threshold (example) | Action |
|--------|---------------------|--------|
| Mean build duration | Baseline + 20% | Alert, investigate |
| Pipeline success rate | < 95% | Incident |
| Queue depth | > 50 jobs pending | Scale CI agents |
| Flakiness rate | > 2% per suite | Quarantine failing tests |
| Artifact build age | > 24h for a given commit | Notify committer |

---

## Tool Ecosystem: Same Pipeline in 3 Tools

The same 4-stage pipeline expressed in Jenkins, GitHub Actions, and GitLab CI — compare syntax and mental model side by side.

### Stage model being implemented

```
Commit → Unit Test → Build Image → Deploy Staging → [gate] → Deploy Prod
```

### Jenkins (Declarative)

```groovy
pipeline {
    agent { kubernetes { yaml podYaml() } }
    stages {
        stage('Unit Test')     { steps { container('maven') { sh 'mvn -B verify' } } }
        stage('Build Image')   { steps { container('kaniko') { sh buildImageCmd() } } }
        stage('Deploy Staging'){ when { branch 'main' }
                                 steps { sh 'helm upgrade --install svc ./helm -n staging' } }
        stage('Prod Gate')     { input { message 'Deploy to prod?' } }
        stage('Deploy Prod')   { when { branch 'main' }
                                 steps { sh 'helm upgrade --install svc ./helm -n prod' } }
    }
}
```

**Jenkins gate**: `input` step — blocks pipeline, notifies via plugin (Slack, email), requires human click in Jenkins UI.

### GitHub Actions

```yaml
jobs:
  unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: '21', cache: maven }
      - run: mvn -B verify

  build-image:
    needs: unit-test
    runs-on: ubuntu-latest
    steps:
      - uses: docker/build-push-action@v5
        with: { push: true, tags: ghcr.io/org/svc:${{ github.sha }} }

  deploy-staging:
    needs: build-image
    environment: staging                # GitHub environment protection
    runs-on: ubuntu-latest
    steps:
      - run: helm upgrade --install svc ./helm -n staging

  deploy-production:
    needs: deploy-staging
    environment: production             # GitHub environment: requires reviewer approval
    runs-on: ubuntu-latest
    steps:
      - run: helm upgrade --install svc ./helm -n prod
```

**GitHub Actions gate**: `environment: production` + protection rule requiring a named reviewer to approve in GitHub UI before job runs.

### AWS CodePipeline + CodeDeploy

```yaml
# Pipeline stages in CloudFormation (abbreviated)
Stages:
  - Name: Build
    Actions:
      - Provider: CodeBuild          # mvn verify + docker build + push to ECR

  - Name: DeployStaging
    Actions:
      - Provider: CodeDeployToECS
        DeploymentGroupName: staging-dg

  - Name: ProductionApproval
    Actions:
      - Provider: Manual             # SNS notification → approval link in AWS console

  - Name: DeployProduction
    Actions:
      - Provider: CodeDeployToECS
        DeploymentGroupName: prod-dg
        # CodeDeploy config: ECSCanary10Percent5Minutes
```

**CodeDeploy gate**: native `Manual` action — sends SNS email/SMS with approve/reject link; no additional tooling needed.

### Key Differences at a Glance

| Aspect | Jenkins | GitHub Actions | AWS CodePipeline |
|--------|---------|----------------|------------------|
| Pipeline definition | Groovy DSL (Jenkinsfile) | YAML (.github/workflows/) | CloudFormation / console |
| Parallelism | `parallel {}` block | `needs` DAG | Parallel actions in a stage |
| Approval gate | `input` step | Environment protection rule | `Manual` action provider |
| Secret storage | Jenkins Credential Store | GitHub Secrets (org/repo) | AWS Secrets Manager / Parameter Store |
| Caching | Plugin (S3 cache, local) | `actions/cache` or built-in | CodeBuild local + S3 cache |
| Docker build | Kaniko (in K8s agent) | `docker/build-push-action` | CodeBuild native Docker |
| Code reuse | Shared Library (Groovy) | Reusable Workflows | No equivalent — copy-paste |
| Failure notification | Post block + plugin | `if: failure()` step | EventBridge → SNS |

---

## FAANG Interview Callouts

**Q: How would you design a CI system for a 500-engineer org where deployments are taking 2 hours?**

Diagnosis first:
1. Measure where time is spent (build vs. test vs. wait time)
2. If wait time > 30%: add CI agents, investigate queue depth
3. If test time > 60%: parallelization, test sharding, move to acceptance stage
4. If build time > 20%: incremental builds, layer caching, Bazel/Gradle daemon

Then fix:
- Parallelize test execution (JUnit parallel runner, Gradle `--parallel`)
- Shard slow suites across agents
- Move integration tests to Stage 2 (run async, don't block trunk)
- Cache: Docker layer cache, Maven/Gradle dependency cache, `~/.m2` cached in agent

**Q: How do you ensure only tested artifacts reach production?**

Immutable artifact + pipeline-enforced promotion:
- Build once, tag with Git SHA
- Artifact is promoted (not rebuilt) through environments
- Production deploys only accept artifacts with a "staging-passed" attestation
- Cryptographic signing (Sigstore/cosign) proves the artifact wasn't tampered with

**Q: A deployment broke prod at 2am. How do you design to prevent it next time?**

→ See [04-release-gates-and-slos.md](04-release-gates-and-slos.md) for SLO-gated progressive delivery.
