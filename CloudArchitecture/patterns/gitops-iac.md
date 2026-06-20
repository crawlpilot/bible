# GitOps & Infrastructure as Code (IaC) Patterns

## Overview
GitOps is an operating model where the desired state of infrastructure and applications is declared in Git. The Git repository is the single source of truth. Automated processes continuously reconcile the actual state of the system with the desired state in Git. Every change — to infrastructure or application — goes through a pull request.

IaC (Infrastructure as Code) is the prerequisite: infrastructure defined as code, versionable, reviewable, testable.

---

## IaC Tools: Decision Matrix

| Tool | Model | Language | Best for |
|---|---|---|---|
| **Terraform** | Declarative (desired state) | HCL | Multi-cloud; most widely adopted; rich provider ecosystem |
| **AWS CDK** | Imperative + declarative | TypeScript, Python, Java, Go | AWS-native; programmatic constructs; L3 abstractions |
| **CloudFormation** | Declarative | YAML/JSON | AWS-native; tight service integration; no additional tooling |
| **Pulumi** | Imperative | TypeScript, Python, Go, Java | Programmatic; real language; multi-cloud |
| **Ansible** | Procedural (configuration management) | YAML | VM configuration, OS-level; not for infrastructure provisioning |

**Recommendation by context**:
- Multi-cloud or large existing Terraform ecosystem → **Terraform**
- AWS-only, engineering team prefers real code over DSL → **CDK**
- Tight CloudFormation integration (Service Catalog, Stack Sets) → **CloudFormation**
- Complex logic requiring full programming language → **Pulumi**

---

## Terraform: Core Patterns

### State Management
```hcl
# Remote state backend (required for team use)
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-prod"
    key            = "services/payments/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"   # DynamoDB for state locking
  }
}
```

**Never use local state in production.** S3 backend with DynamoDB locking prevents concurrent apply conflicts.

### Module Structure
```
infrastructure/
├── modules/
│   ├── vpc/           # Reusable VPC module
│   ├── ecs-service/   # Standard ECS service pattern
│   └── rds-aurora/    # Aurora database module
├── environments/
│   ├── prod/
│   │   ├── main.tf    # Composes modules for prod
│   │   └── terraform.tfvars
│   └── staging/
│       ├── main.tf
│       └── terraform.tfvars
```

**DRY via modules**: every environment uses the same module. The difference is the variable values (`instance_count=10` in prod, `instance_count=2` in staging).

### Workspace vs Directory-per-Environment
| Approach | Pros | Cons |
|---|---|---|
| **Directory per environment** | Complete isolation; different backends | Code duplication (mitigated by modules) |
| **Terraform Workspaces** | Single codebase, multiple state files | Same backend; less isolation; confusing for teams |
| **Recommendation** | Directory per environment with shared modules | More files, clearer blast radius |

### `terraform plan` in CI/CD
```yaml
# GitHub Actions example
- name: Terraform Plan
  run: terraform plan -out=planfile
  
- name: Post plan to PR
  uses: github-actions/terraform-plan-comment@v1
  with:
    plan-file: planfile
    
- name: Terraform Apply (on merge to main)
  if: github.ref == 'refs/heads/main'
  run: terraform apply planfile
```

Plan output posted as a PR comment — reviewers see exactly what will change before approving.

---

## AWS CDK: Core Patterns

### Constructs: L1, L2, L3
```typescript
// L1: CloudFormation resource (low-level, verbose)
new cfn.CfnBucket(this, 'Bucket', { bucketName: 'my-bucket', versioningConfiguration: { status: 'Enabled' } });

// L2: Opinionated AWS construct (best practices built in)
new s3.Bucket(this, 'Bucket', { versioned: true, encryption: s3.BucketEncryption.S3_MANAGED });

// L3: Pattern construct (composition of multiple resources)
new patterns.ApplicationLoadBalancedFargateService(this, 'Service', {
  cluster: cluster,
  cpu: 512, memoryLimitMiB: 1024,
  image: ecs.ContainerImage.fromEcr(repository),
  publicLoadBalancer: true
});
```

**Create L3 constructs** for your organisation's standard patterns (compliant S3 bucket, standard ECS service, RDS with secrets rotation). Enforce standards through the construct's defaults and prevent misconfiguration through the construct's API.

### CDK Aspects (Policy-as-Code)
```typescript
// Enforce all S3 buckets have versioning enabled
class EnforceS3Versioning implements cdk.IAspect {
  visit(node: cdk.IConstruct) {
    if (node instanceof s3.Bucket) {
      if (!node.versioned) {
        cdk.Annotations.of(node).addError('S3 bucket must have versioning enabled');
      }
    }
  }
}
cdk.Aspects.of(app).add(new EnforceS3Versioning());
```

CDK Aspects traverse the entire construct tree and can validate, warn, or error. Use for: enforcing encryption, tagging requirements, or security baseline compliance.

---

## GitOps: The Operating Model

### Core Loop
```
Engineer writes code → opens PR → automated checks run
  ↓ (PR approved and merged)
Git repo (desired state updated)
  ↓
GitOps controller detects divergence
  ↓
Controller applies changes to reconcile actual state = desired state
  ↓
Controller reports status back to Git
```

The controller is the key actor — it continuously watches Git and the live system, and drives reconciliation.

### GitOps for Infrastructure (Terraform)
```
Git repo (Terraform code) → Atlantis / Terraform Cloud / GitHub Actions
    ↓ PR opened
    → `terraform plan` runs automatically → plan posted as comment
    ↓ PR approved + merged
    → `terraform apply` runs → infra updated
    → Terraform state updated in S3
    → Slack/Teams notification: "prod ECS service updated"
```

**Atlantis**: open-source Terraform automation tool. Runs plan on PR comment (`atlantis plan`), runs apply on merge or comment (`atlantis apply`). Self-hosted on EC2/EKS.

### GitOps for Applications (Kubernetes)
**ArgoCD** and **Flux** are the two dominant GitOps controllers for Kubernetes:

| | ArgoCD | Flux |
|---|---|---|
| UI | Rich web UI; visual diff | CLI + Grafana dashboard |
| Multi-cluster | Yes (ArgoCD manages multiple clusters) | Yes |
| Config format | Helm, Kustomize, raw YAML | Helm, Kustomize, raw YAML |
| Push vs Pull | Pull (controller watches Git) | Pull |
| Notifications | Slack, PagerDuty, email | Slack, email |
| **Use when** | Team wants visual UI; multi-cluster management | Lightweight; CLI-focused team |

```yaml
# ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: payments-api, namespace: argocd}
spec:
  source:
    repoURL: https://github.com/myorg/k8s-config
    path: services/payments-api
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: payments
  syncPolicy:
    automated:
      prune: true      # delete resources removed from Git
      selfHeal: true   # re-apply if someone manually changes the cluster
```

`selfHeal: true` is the GitOps guarantee — manual changes to the cluster are automatically reverted. Git is the source of truth; the cluster reflects Git.

---

## Repository Structure Patterns

### Mono-Repo (Single Repository for All Config)
```
infra-config/
├── services/
│   ├── payments/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml
│   └── orders/
│       ├── deployment.yaml
│       └── ...
├── platform/
│   ├── monitoring/
│   └── networking/
└── environments/
    ├── prod/kustomization.yaml
    └── staging/kustomization.yaml
```

**Pros**: one PR changes multiple services; easy cross-service dependency tracking
**Cons**: PR blast radius is the entire platform; merge conflicts; CODEOWNERS required for access control

### Poly-Repo (Config Co-Located with App Code)
```
payments-service/   (app code + K8s manifests + Terraform)
orders-service/     (app code + K8s manifests + Terraform)
```

**Pros**: team autonomy; deploy independently; small PRs
**Cons**: cross-service changes need multiple PRs; no easy "what's deployed everywhere" view

### Hybrid (Application Code + Separate Config Repo)
```
payments-service/   (application code only)
infra-config/       (Kubernetes manifests for all services)
terraform-infra/    (Terraform for all infrastructure)
```

**Pros**: clean separation of "what the app does" vs "how it's deployed"; config changes don't trigger CI/CD test suites
**Cons**: dependency tracking requires tooling

**Recommendation**: hybrid for most orgs. ArgoCD/Flux watches the config repo; app CI pipelines update the config repo with new image tags.

---

## Progressive Delivery in GitOps

GitOps + feature flags + traffic splitting:

**Flagger** (integrates with ArgoCD/Flux): automates canary deployments by shifting traffic and watching metrics.

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata: {name: payments-api}
spec:
  targetRef: {kind: Deployment, name: payments-api}
  service:
    port: 8080
  analysis:
    interval: 1m
    threshold: 5          # fail after 5 consecutive metric failures
    maxWeight: 50         # max 50% of traffic to canary
    stepWeight: 10        # increase 10% per interval
    metrics:
    - name: request-success-rate
      thresholdRange: {min: 99}    # rollback if success rate < 99%
    - name: request-duration
      thresholdRange: {max: 500}   # rollback if P99 > 500ms
```

Flagger automatically:
1. Deploys new version alongside stable version
2. Shifts 10% of traffic per minute to canary
3. Checks metrics after each shift
4. Promotes to 100% if healthy; rollbacks automatically if not

---

## Security in GitOps

**Branch protection rules** (required):
- Require PR reviews (minimum 2 approvers for infrastructure changes)
- Require passing CI checks before merge
- Restrict direct push to `main` branch
- Require signed commits (GPG)

**CODEOWNERS**: automatic PR review requirements based on changed paths:
```
# .github/CODEOWNERS
/infrastructure/prod/**    @platform-team @security-team
/services/payments/**      @payments-team
```

**Secret management in GitOps**: never commit secrets to Git. Options:
- **Sealed Secrets** (Kubernetes): encrypt secret with cluster public key; only the cluster can decrypt → safe to commit encrypted form
- **External Secrets Operator**: sync from Secrets Manager/Vault to Kubernetes Secrets; only the reference is in Git, not the value
- **SOPS**: encrypt YAML files with KMS/age/GPG; decrypt at apply time

---

## Observability for IaC/GitOps

| What to monitor | How |
|---|---|
| Drift detection | Terraform plan in CI on schedule; alert if plan shows unexpected changes |
| ArgoCD sync status | ArgoCD Prometheus metrics: `argocd_app_sync_status` |
| Failed deployments | ArgoCD notifications → Slack/PagerDuty on sync failure |
| Infra cost estimation | Infracost in Terraform PRs: shows cost impact of each change |
| Config compliance | Checkov / tfsec / cfn-guard in CI pipeline: block insecure infra changes |

---

## Best Practices

1. **Everything in Git** — no manual console changes in production; if it's not in Git, it doesn't exist
2. **Never commit state files** — Terraform state in S3 with DynamoDB locking; not in Git
3. **Module everything** — create organisation modules for standard patterns; prevent teams from reinventing (insecurely) from scratch
4. **PR-only workflow** — direct apply to production never allowed; always through reviewed PR
5. **`terraform plan` in every PR** — post the plan as a comment; humans must verify before approving
6. **Self-healing enabled in ArgoCD** — manual cluster changes are reverted; Git is always the truth
7. **Separate config repos from app repos** — app CI updates image tags in config repo; GitOps controller deploys
8. **Drift detection on a schedule** — run `terraform plan` nightly against prod; alert if drift detected
9. **Cost estimation in IaC PRs** — Infracost shows `$300/month increase` before the PR is merged; prevents surprise bills
10. **Tag everything from IaC** — `terraform` managed tag, `repo`, `team`, `environment` on every resource; enables cost allocation and audit

---

## FAANG Interview Points

**"How do you manage 500 microservices' Kubernetes configurations?"**: Hybrid repo: each service owns its code; shared config repo (ArgoCD watches it). Kustomize overlays for environment-specific config (prod vs staging). CODEOWNERS per service directory. ArgoCD ApplicationSet generates one ArgoCD Application per service from a single template. Flagger for progressive delivery.

**"How do you prevent configuration drift in a large AWS environment?"**: Terraform with remote state + drift detection (nightly `terraform plan` → CloudWatch alert if non-empty output). AWS Config rules detect compliance drift. ArgoCD `selfHeal: true` prevents manual Kubernetes cluster changes. CloudTrail alert on console resource modifications for resources tagged `terraform-managed: true`.

**"IaC security — how do you prevent teams from creating insecure infrastructure?"**: tfsec/Checkov in CI pipeline blocks PRs with CIS benchmark violations (public S3 buckets, unencrypted EBS, unrestricted SG). CDK L3 constructs bake in security defaults. SCPs in AWS Organizations prevent resource creation regardless of IaC (last line of defence). IAM permissions boundaries cap what Terraform roles can create.
