# Role: DevOps / Platform Engineer

## Core Identity

DevOps is not a role — it's a culture and set of practices. But in practice, most organizations have engineers whose primary domain is **the platform that other engineers build on**: CI/CD pipelines, infrastructure as code, developer tooling, container orchestration, secrets management, and the build/test/deploy lifecycle.

At FAANG scale, this role is often called **Platform Engineer**, **Infrastructure Engineer**, or **Developer Experience (DevEx) Engineer**. Their product is other engineers' productivity and system reliability — not end-user features.

---

## Primary Accountabilities

### 1. CI/CD Pipeline Design & Ownership
- Design, build, and maintain the continuous integration and delivery pipeline
- Ensure every commit triggers automated build → test → security scan → artifact publish
- Own deployment orchestration: blue-green, canary, rolling, traffic shifting
- Measure and optimize pipeline speed — every minute of CI time multiplies across all engineers
- Own deployment frequency and change failure rate (DORA metrics)

### 2. Infrastructure as Code (IaC)
- All infrastructure defined in code (Terraform, Pulumi, CDK, Helm)
- No manual resource creation in cloud consoles
- Own the IaC repository, module library, and review process
- Enforce environment parity: dev == staging == prod in configuration
- Manage Terraform state, remote backends, and workspace isolation

### 3. Container & Orchestration Platform
- Own the Kubernetes (or equivalent) cluster lifecycle: version upgrades, node pools, autoscaling policies
- Define container image standards: base images, vulnerability scanning, image registries
- Manage Helm chart library, operator deployments, and CRDs
- Set resource quotas, pod disruption budgets, and namespace policies

### 4. Developer Tooling & Inner Loop
- Own the local development experience: Docker Compose stacks, local K8s (kind/minikube/Tilt)
- Maintain internal CLI tools, scaffolding generators, and project templates
- Build and own feature flag systems, environment management, and dev/staging namespace allocation
- Measure and improve inner loop time: code → local run → feedback (target: < 60 seconds)

### 5. Secrets & Configuration Management
- Own secrets management: Vault, AWS Secrets Manager, GCP Secret Manager
- No secrets in code, no secrets in environment variables without rotation
- Own config management: ConfigMaps, external config stores, environment promotion pipelines
- Enforce least-privilege access to secrets across environments

### 6. Security & Compliance Automation
- Embed security into the pipeline (shift-left security): SAST, DAST, SCA, container scanning
- Own supply chain security: SBOM generation, dependency pinning, signing
- Enforce compliance guardrails: SOC2, PCI-DSS, GDPR controls as pipeline gates
- Manage vulnerability remediation SLA enforcement

### 7. Observability Infrastructure
- Own the observability stack: metrics (Prometheus/DataDog), logs (Elasticsearch/Splunk), traces (Jaeger/Tempo)
- Provide self-service dashboarding for development teams
- Manage observability data retention, cardinality limits, and costs
- Define instrumentation standards all services must implement

---

## DevOps vs Platform Engineering vs SRE

| Dimension | DevOps (Practice) | Platform Engineering | SRE |
|-----------|------------------|---------------------|-----|
| Focus | Cultural transformation, CI/CD | Internal developer platform (IDP) | Production reliability |
| Customer | Everyone | Other engineers | End users (via availability) |
| Deliverable | Faster delivery, fewer failures | Self-service platform capabilities | SLOs, incident response |
| Toil | Automate ops tasks | Automate engineering tasks | Automate on-call tasks |
| Key metric | DORA metrics | Developer experience, inner loop time | Error budget, MTTR |

---

## DORA Metrics — DevOps Owns These

| Metric | Elite (FAANG) | High | Medium | Low |
|--------|------------|------|--------|-----|
| Deployment Frequency | Multiple/day | Weekly | Monthly | Quarterly |
| Lead Time to Change | < 1 hour | < 1 week | < 1 month | > 1 month |
| Change Failure Rate | < 5% | 5–10% | 10–15% | > 15% |
| Time to Restore | < 1 hour | < 1 day | < 1 week | > 1 week |

---

## DevOps Artifacts

| Artifact | Purpose |
|----------|---------|
| CI Pipeline (YAML) | Reproducible build, test, scan, publish |
| Terraform Modules | Reusable, versioned infrastructure |
| Helm Charts | K8s application packaging |
| Runbook (automation) | Self-healing scripts triggered by alerts |
| IaC Policy (OPA/Sentinel) | Guardrails on infra changes |
| Developer Portal | Self-service for environments, secrets, scaffolding |
| Golden Path Template | Opinionated starting point for new services |

---

## Golden Path (Backstage / Internal Developer Portal)

The "golden path" is the DevOps team's highest-value deliverable at FAANG scale:

```
New Service Golden Path:
├── Project scaffolding (CLI: ./create-service --name foo --lang java)
├── Git repository with PR templates, CODEOWNERS, branch protection
├── CI/CD pipeline pre-wired (lint → test → build → scan → deploy)
├── Kubernetes manifests with default resource limits, HPA, PDB
├── Observability pre-instrumented (Prometheus metrics, Jaeger tracing, structured logs)
├── Secret management wired (Vault sidecar or ESO)
├── Feature flags integrated (LaunchDarkly, Unleash)
└── PRR checklist auto-generated based on service metadata
```

Teams that adopt the golden path launch 4-8x faster than teams that start from scratch.

---

## DevOps ↔ Principal Engineer Interface

### Platform as a Product
- Principal engineers treat the DevOps team's platform as a product and provide requirements
- "The build pipeline takes 45 minutes — it's blocking 80 engineers from getting fast feedback"
- "We need a canary deployment primitive that's self-service, not requiring platform team involvement"

### Architecture Decisions That DevOps Must Implement
- When a principal engineer designs a multi-region deployment strategy, DevOps must implement the Terraform and CI/CD changes
- Principal engineers must consult DevOps before finalizing architecture: "Can your platform support this deployment pattern?"
- Avoid architecture decisions that require heroic platform work with no prior consultation

### Standardization vs Flexibility
- DevOps pushes for standardization (golden path, fewer runtimes, fewer frameworks)
- Engineering teams push for flexibility (use any framework, any language)
- Principal engineers mediate: define where standardization is non-negotiable (security, observability) vs where teams have freedom (framework choice)

---

## CI/CD Pipeline Anatomy (Principal Must Know)

```
Commit Push
    │
    ▼
[Trigger: PR or merge to main]
    │
    ├─► Static Analysis
    │     ├── Linting (language-specific)
    │     ├── SAST (Semgrep, SonarQube, Checkmarx)
    │     └── License check
    │
    ├─► Unit Tests
    │     ├── Run in parallel by module
    │     ├── Coverage gate (≥ 80%)
    │     └── Mutation testing (optional)
    │
    ├─► Build & Package
    │     ├── Docker image build
    │     ├── Image vulnerability scan (Trivy, Snyk, Grype)
    │     └── SBOM generation
    │
    ├─► Integration Tests
    │     ├── Spin up dependencies (testcontainers)
    │     ├── Contract tests (Pact)
    │     └── API compatibility tests
    │
    ├─► Artifact Publish
    │     ├── Push to registry (ECR, GCR, Artifactory)
    │     └── Sign image (Cosign)
    │
    ├─► Deploy to Staging
    │     ├── Helm upgrade / ArgoCD sync
    │     ├── Smoke tests
    │     └── Performance baseline (k6, Gatling)
    │
    └─► Deploy to Production
          ├── Canary (1% → 10% → 50% → 100%)
          ├── Automated rollback on SLO breach
          └── Post-deploy smoke tests
```

---

## Infrastructure Patterns at Scale

### Multi-Environment Strategy
```
dev     → Per-engineer or per-PR ephemeral environments
staging → Long-lived, production-like, shared
canary  → 5% production traffic
prod    → Full traffic, multi-region
```

### Multi-Region IaC Pattern
```hcl
# Terraform: per-region module invocation
module "service_us_east_1" {
  source  = "./modules/service"
  region  = "us-east-1"
  replica = false  # primary
}

module "service_eu_west_1" {
  source  = "./modules/service"
  region  = "eu-west-1"
  replica = true  # replica, read-only
}
```

### Canary Release with Traffic Shifting
```yaml
# ArgoCD Rollout: canary strategy
strategy:
  canary:
    steps:
      - setWeight: 5
      - pause: {duration: 10m}
      - analysis:
          templates:
            - templateName: success-rate
          args:
            - name: service-name
              value: payment-service
      - setWeight: 50
      - pause: {duration: 10m}
      - setWeight: 100
    analysis:
      successCondition: "result[0] >= 0.99"
      failureLimit: 3
```

---

## Common DevOps Anti-Patterns

| Anti-Pattern | Impact | Remedy |
|-------------|--------|--------|
| Snowflake servers | Undocumented, unreproducible infra | IaC everything; immutable infrastructure |
| Long-lived feature branches | Merge conflicts, integration problems | Trunk-based development + feature flags |
| No rollback capability | Every deploy is a one-way door | Blue-green or canary with automated rollback |
| Manual secrets | Secret sprawl, rotation nightmares | Vault or cloud-native secrets management |
| Monolithic CI pipeline | Slow feedback, all-or-nothing | Parallel pipelines; only run what changed |
| Shared staging environment | Test pollution, flaky tests | Ephemeral environments per PR |
| No SLA on pipeline | Slow builds become accepted | Track and alert on pipeline duration regressions |

---

## Interview Angles for Principal Engineers

**"How would you design the CI/CD strategy for a team of 200 engineers?"**
- Start with DORA metrics as goals: deployment frequency > 10/day, lead time < 1 hour
- Golden path template for all new services
- Parallel pipeline stages; skip unchanged modules
- Canary deployments with automated SLO-based rollback
- Ephemeral environments per PR for integration testing

**"How do you manage infrastructure across 50 microservices?"**
- IaC module library: compute, networking, storage, messaging as versioned modules
- Internal developer portal (Backstage) for self-service provisioning
- Policy as code (OPA, Sentinel) for guardrails
- Cost allocation per service; show teams their cloud spend

**"How do you ensure security doesn't slow down delivery?"**
- Shift security left: SAST/SCA in CI, not as a separate gate after QA
- Automate vulnerability triage: critical CVEs block deploy, medium/low create tickets
- Security champions embedded in teams — DevOps provides the tools, champions drive adoption
