# ADR-003: Deployment Platform — Virtual Machines vs EC2 Auto Scaling Groups vs Amazon EKS

**Title**: Migrate Workloads from Manually Managed Virtual Machines to Amazon EKS for Operational Centralisation, Automated Patching, and Developer Velocity  
**Status**: Accepted  
**Date**: 2026-06-06  
**Authors**: [Principal Engineer — Platform], [SRE Lead]  
**Reviewers**: [VP Engineering], [Staff Engineer — Infrastructure], [Security Architect]  
**Deciders**: [CTO], [VP Engineering]

---

## Context

### Current State

The organisation currently runs **200+ services** across **1,400 long-lived EC2 virtual machines** provisioned via Terraform and managed individually. Services are deployed using a mix of:
- SSH + Ansible playbooks (legacy services, ~40%)
- AMI baking with Packer + Launch Templates (newer services, ~35%)
- Docker on EC2 without orchestration (recent containerised services, ~25%)

This has produced the following operational profile over the past 12 months:

| Problem | Observed Impact |
|---------|----------------|
| **OS patching lag** | Average time from CVE disclosure to patch: 47 days. Security team SLA: 14 days. |
| **Developer machine provisioning** | New service environment setup: 3–5 days (Terraform PR → AMI bake → manual DNS). |
| **Stranded capacity** | Average VM utilisation: 18% CPU, 22% memory. Reserved Instances pre-purchased for peak load sit mostly idle. |
| **Configuration drift** | 23% of VMs deviate from their "golden" AMI within 90 days of launch (SSH access, manual hotfixes, local config changes). |
| **Incident MTTR** | p50 MTTR: 48 minutes. Primary driver: identifying which VMs are healthy, draining traffic, replacing. No standard mechanism. |
| **Developer burden** | 6 hours/engineer/month spent on machine-level tasks: SSH debugging, disk space cleanup, log rotation failures, OOM kills not surfaced in alerts. |
| **Scaling latency** | EC2 instance warm-up (AMI launch + service start): 4–8 minutes. SLA for burst capacity: 2 minutes. |

### Trigger for This ADR

Three converging pressures forced a decision:

1. **CVE-2024-6387 (OpenSSH "regreSSHion")**: patching 1,400 VMs took 11 days and required 4 engineers working in parallel. The security team issued a formal finding that the current patching process is incompatible with the 14-day SLA.
2. **Cost audit**: AWS Compute Optimizer identified $2.1M/year in overprovisioned EC2 capacity (Reserved Instances mismatched to actual workload shapes).
3. **Engineering velocity**: exit interviews from 3 senior engineers cited "infra toil" as a contributing factor to departure.

### Scope of This Decision

This ADR covers the **deployment platform** for stateless and lightly stateful application workloads (web APIs, stream processors, background workers, cron jobs). It explicitly excludes:
- Stateful databases (Cassandra, PostgreSQL, Redis) — separate ADR
- GPU-based ML training workloads — separate ADR
- Edge CDN functions — separate ADR

---

## Evaluated Options

### Option A: Continue with Manually Managed Virtual Machines (Status Quo)

**Description**: Keep the current model. Incrementally improve tooling: better Ansible playbooks, automated AMI rotation via a nightly pipeline, better monitoring.

**What changes**:
- Introduce AWS Systems Manager (SSM) Patch Manager to automate OS patch application
- Rotate AMIs quarterly via a CI pipeline (Packer → AMI → Terraform rolling update)
- Introduce Instance Refresh on existing Launch Templates with a configurable warm-up policy

### Option B: EC2 Auto Scaling Groups (ASG) with Immutable Infrastructure

**Description**: Adopt strict immutable infrastructure. No SSH access to production. All changes via AMI replacement. Auto Scaling Groups with instance refresh for rolling deployments. Spot integration for cost.

**What changes**:
- No SSH access to production; all debugging via SSM Session Manager (no open ports)
- AMI baked via Packer CI on every release; ASG performs instance refresh (rolling replacement)
- Mixed instance policy: On-Demand (base) + Spot (burst capacity)
- ALB/NLB target group health checks drive automatic instance replacement
- CloudWatch Agent + Fluent Bit ship logs/metrics; no local SSH debugging

### Option C: Amazon EKS (Elastic Kubernetes Service)

**Description**: Containerise all workloads. Deploy via EKS with managed node groups (Bottlerocket AMI, EKS auto-patched). Introduce GitOps (Argo CD) for declarative, auditable deployments.

**What changes**:
- All workloads containerised (Docker); no machine-level concerns for developers
- EKS Managed Node Groups: AWS patches node AMIs, drains nodes, replaces — zero developer involvement
- Horizontal Pod Autoscaler (HPA) + Cluster Autoscaler (or Karpenter) for bin-packing and right-sizing
- Argo CD as GitOps controller: deployment = git commit to manifests repo
- Service mesh (AWS App Mesh or Istio) for mTLS, traffic shifting, observability

---

## Decision

**Adopt Amazon EKS (Option C)** as the target deployment platform, with a phased migration over 18 months.

EC2 ASG (Option B) was shortlisted as an intermediate state — services that cannot be containerised in phase 1 will run on immutable ASGs with SSM-based access, migrating to EKS in phase 2.

---

## Detailed Comparison

### 1. OS Patching and Security Compliance

| Dimension | VM (Status Quo) | EC2 ASG (Immutable) | EKS Managed Node Groups |
|-----------|----------------|--------------------|-----------------------|
| **Patching mechanism** | Manual Ansible + SSM Patch Manager | AMI rotation via Packer CI + Instance Refresh | AWS patches node AMI; EKS performs managed node group upgrade |
| **Developer involvement** | High (engineers trigger patches, monitor rollout) | Medium (CI pipeline triggers; engineer monitors) | **Zero** — AWS manages the node layer |
| **Patch rollout time (1,400 nodes)** | 11 days (observed) | 4–6 hours (parallel instance refresh) | 2–4 hours (AWS-managed rolling node upgrade) |
| **Time-to-patch (CVE → production)** | 47 days (observed) | 3–5 days (AMI bake CI + refresh) | **1–2 days** (AWS releases patched AMI; trigger upgrade) |
| **Configuration drift risk** | High (SSH access allows drift) | None (immutable; SSH disabled) | **None** (containers are immutable; nodes are replaced not patched in place) |
| **Compliance auditability** | Low (who ran what, when?) | Medium (CI pipeline logs) | **High** (EKS upgrade history, node group events, Argo CD audit trail) |

**EKS advantage**: Developers never think about the OS. Node patching is a `eksctl upgrade nodegroup` command or an Argo CD / Terraform apply. The developer experience is entirely at the container and manifest level.

---

### 2. Developer Experience and Cognitive Load

| Dimension | VM (Status Quo) | EC2 ASG | EKS |
|-----------|----------------|---------|-----|
| **New service environment** | 3–5 days (Terraform PR, AMI bake, DNS) | 1–2 days (Packer + ASG Terraform module) | **< 4 hours** (copy a Helm chart / k8s manifest template; deploy via Argo CD) |
| **Deployment mechanism** | SSH + Ansible or AMI bake | AMI bake + Instance Refresh (rolling) | `kubectl apply` or git push → Argo CD sync |
| **Debugging production issues** | SSH into machine | SSM Session Manager; CloudWatch Logs | `kubectl logs`, `kubectl exec`, distributed tracing; no machine-level access needed |
| **Rollback** | Re-deploy old AMI (minutes) | Revert instance refresh (minutes) | Argo CD rollback (seconds — git revert → sync) |
| **Local development parity** | Low (developer laptop ≠ VM) | Low (dev ≠ AMI) | **High** (Docker/kind/minikube; same containers locally and in prod) |
| **Secret management** | SSM Parameter Store / Ansible Vault (manual) | SSM Parameter Store (automated) | AWS Secrets Manager + External Secrets Operator (auto-sync to k8s secrets) |
| **Machine-level toil per engineer** | 6 hrs/month | 1–2 hrs/month | **< 15 min/month** (no machine-level concerns) |

**EKS advantage**: The abstraction layer eliminates the entire class of machine-level problems (disk full, OOM on the host, SSH key rotation, OS-level dependency conflicts). Developers operate at the service level only.

---

### 3. Resource Utilisation and Cost

| Dimension | VM (Status Quo) | EC2 ASG | EKS + Karpenter |
|-----------|----------------|---------|-----------------|
| **Average CPU utilisation** | 18% | 25–35% (right-sized AMI types) | **55–70%** (bin-packing multiple pods per node) |
| **Average memory utilisation** | 22% | 30–40% | **60–75%** (Kubernetes requests/limits enforce packing) |
| **Scaling granularity** | VM (large step, 4–8 min warm-up) | VM (3–5 min warm-up with baked AMI) | **Pod (seconds) + Node (< 2 min with Karpenter)** |
| **Spot instance utilisation** | Manual (risky — SSH state loss) | Supported (mixed instance policy) | **Natively supported** (Karpenter + pod disruption budgets) |
| **Reserved Instance efficiency** | Low (purchased for peak; idle at baseline) | Medium (right-size commitments) | **High** (Compute Savings Plans span instance types; Karpenter selects cheapest available type) |
| **Estimated cost reduction** | — | 20–30% vs status quo | **40–60% vs status quo** |

**Karpenter** (EKS node provisioner) selects the cheapest available EC2 instance type for each pod's resource request, uses Spot where disruption-tolerant, and consolidates underutilised nodes automatically. This is structurally impossible with VM-per-service deployments.

---

### 4. Scaling and Availability

| Dimension | VM (Status Quo) | EC2 ASG | EKS |
|-----------|----------------|---------|-----|
| **Horizontal scaling time** | 4–8 min (AMI launch + service start) | 3–5 min (baked AMI reduces start time) | **< 30s for pods** (image already pulled); **< 2 min for new nodes (Karpenter)** |
| **Rolling deployment** | Manual (Ansible serial batches) | ASG Instance Refresh (rolling %) | Kubernetes rolling update (configurable: maxSurge, maxUnavailable) |
| **Zero-downtime deployment** | Risky (requires ALB deregistration scripting) | Supported (ALB + health checks + drain) | **Native** (readiness probes + preStop hook + pod disruption budget) |
| **Multi-AZ distribution** | Manual (Terraform spread) | Supported (ASG AZ rebalancing) | **Native** (topology spread constraints) |
| **Disruption handling** | High blast radius (VM failure = service down) | Medium (ASG replaces failed instances) | **Low** (pod is rescheduled in seconds; PodDisruptionBudget prevents simultaneous evictions) |
| **Traffic draining on scale-in** | Manual or ALB deregistration delay | Supported (lifecycle hook + deregistration delay) | **Native** (preStop hook + terminationGracePeriodSeconds) |

---

### 5. Observability and Incident Response

| Dimension | VM (Status Quo) | EC2 ASG | EKS |
|-----------|----------------|---------|-----|
| **Log collection** | Varied (some CloudWatch Agent, some SSH-pulled) | CloudWatch Agent + Fluent Bit (standardised) | **Fluent Bit DaemonSet → CloudWatch/OpenSearch** (uniform across all pods) |
| **Metrics** | CloudWatch custom metrics (inconsistent namespace) | CloudWatch Agent (standardised) | **Prometheus + Grafana** (kube-state-metrics, node-exporter, application metrics via ServiceMonitor) |
| **Distributed tracing** | Inconsistent; not all services instrumented | Inconsistent | **AWS X-Ray / OpenTelemetry** (enforced via service mesh sidecar injection) |
| **Incident debugging** | SSH into machine, inspect files, run commands | SSM Session Manager; CloudWatch Logs | `kubectl describe pod`, `kubectl logs`, events timeline — **no machine access needed** |
| **MTTR (incident resolution)** | 48 min (observed) | 25–35 min (estimated) | **< 15 min** (fast pod replacement; rich observability; automated self-healing) |
| **Self-healing** | CloudWatch + Auto Recovery (VM level) | ASG health check + replacement | **Native** (liveness probe → container restart; readiness probe → traffic exclusion; k8s controller loop) |

---

### 6. Operational Centralisation

A key non-functional driver for EKS is **centralising** all operational concerns that are currently duplicated across every team:

| Concern | VM Model (Per-Team) | EKS Model (Centralised) |
|---------|--------------------|-----------------------|
| **OS patching** | Each team runs own Ansible / AMI pipeline | Platform team manages single EKS node group upgrade |
| **Log shipping** | Each team configures CloudWatch Agent differently | Single Fluent Bit DaemonSet config, managed by platform |
| **Secrets management** | Each team integrates SSM differently | External Secrets Operator: one pattern, all teams |
| **Service discovery** | Route 53 / hardcoded hostnames | CoreDNS + Kubernetes Services (automatic, namespace-scoped) |
| **TLS / mTLS** | Each team configures ACM / nginx SSL differently | Cert-manager (platform-managed) + service mesh mTLS |
| **Deployment pipeline** | Each team has own CI/CD scripts | Argo CD: one controller, all teams; git is the source of truth |
| **Ingress / load balancing** | Each team manages ALB Terraform | AWS Load Balancer Controller + Ingress objects (declarative) |
| **Resource quotas** | No enforcement; services can OOM the host | Kubernetes ResourceQuota + LimitRange per namespace |
| **Network policy** | Security group per service (managed by team) | Kubernetes NetworkPolicy (centralised; enforced by Calico/VPC CNI) |

**Centralisation payoff**: Instead of 50 teams each solving the same 9 problems, the platform team solves each problem once, and teams consume the solution declaratively.

---

### 7. Trade-offs and Costs of EKS

EKS is not free of trade-offs. These are explicitly acknowledged:

| Cost / Risk | Severity | Mitigation |
|-------------|---------|-----------|
| **Learning curve**: Kubernetes is complex; teams unfamiliar with pods, services, ingress, RBAC | High (first 6 months) | Mandatory internal training; platform team provides golden path Helm charts and runbooks; dedicated migration support squad |
| **Stateful workloads are harder**: databases, queues with local disk are not natural in k8s | Medium | Excluded from scope (separate ADR); keep stateful workloads on managed services (RDS, ElastiCache, MSK) |
| **Networking complexity**: VPC CNI, security groups for pods, service mesh add layers | Medium | Platform team owns networking; developers use Services/Ingress abstractions only |
| **Cost of control plane**: EKS charges $0.10/hr per cluster (~$876/yr) | Low | Amortised across 200 services; negligible vs compute cost savings |
| **Debugging is different**: `kubectl exec` replaces SSH; ephemeral containers for live debugging | Medium | New runbooks; kubectl-debug tooling; log-based debugging encouraged as the primary mode |
| **Blast radius of misconfiguration**: bad Argo CD sync can affect many services | Medium | Progressive delivery (Argo Rollouts): canary + automated rollback on error rate spike; PR reviews for manifest changes |
| **Image supply chain**: container images introduce new attack surface (base image CVEs) | Medium | ECR image scanning (on push); Trivy in CI pipeline; Kyverno admission controller blocks images with HIGH/CRITICAL CVEs |

---

## Consequences

### Positive Consequences

1. **OS patching SLA compliance**: patching 1,400 nodes reduces from 47 days to 1–2 days; no developer involvement required.
2. **Scaling latency**: burst capacity from 4–8 minutes (VM cold start) to < 30 seconds (pod scheduling) + < 2 minutes (Karpenter node provisioning) for new node.
3. **Resource cost reduction**: estimated 40–60% reduction in EC2 spend via bin-packing, Spot utilisation, and Karpenter consolidation (~$1.2–1.8M/year on current spend).
4. **Developer toil elimination**: 6 hrs/engineer/month → < 15 min. At 150 engineers, this is 870 engineer-hours/month recovered (~$1.5M/year at blended rate).
5. **Operational centralisation**: 9 per-team operational concerns centralised into platform-managed solutions; enables 3-person platform team to support 50 product teams.
6. **Zero-downtime deployments by default**: readiness probes, PodDisruptionBudgets, and rolling update strategy are the default — not an engineering project per service.
7. **Environment parity**: developers run the same containers locally (Docker Compose / kind) as in production — eliminates "works on my machine" class of incidents.
8. **Auditability**: every deployment is a git commit in the manifests repo; Argo CD records who synced what and when — meets SOC 2 Type II change management requirements.

### Negative Consequences (Accepted)

1. **18-month migration**: incremental migration means operating two platforms in parallel. Operational overhead increases during transition.
2. **Kubernetes expertise gap**: team must invest in training. Estimated 3 months to baseline competence for engineers unfamiliar with k8s.
3. **Stateful workloads remain on VMs/ASGs**: databases and stateful services not in scope; creates a hybrid environment that persists indefinitely.
4. **Argo CD is a new single point of operational failure**: if Argo CD is misconfigured, deployments fail across all teams. Mitigated by HA Argo CD deployment + automated health checks.

---

## Migration Plan

### Phase 1 (Months 1–6): Foundation and Pilot

- Stand up EKS clusters (prod, staging, dev) with Managed Node Groups (Bottlerocket, Graviton)
- Deploy platform components: Argo CD, Karpenter, External Secrets Operator, Fluent Bit, Prometheus/Grafana, AWS Load Balancer Controller, Cert-manager
- Migrate 10 stateless pilot services (high-traffic, low-risk) with dedicated migration support
- Establish golden path: Helm chart templates, Dockerfile standards, CI pipeline integration
- Publish internal runbooks: `kubectl` basics, debugging pods, reading Grafana dashboards

### Phase 2 (Months 7–12): Broad Migration

- Migrate remaining stateless services (target: 80% of services by month 12)
- Services that cannot be containerised run on immutable EC2 ASGs (Option B interim state)
- Decommission Ansible; all deployments via Argo CD
- Roll out Argo Rollouts for canary + automated rollback on all critical services
- Introduce Kyverno admission policies: image CVE blocking, required labels, resource limits enforcement

### Phase 3 (Months 13–18): Consolidation and Optimisation

- Migrate remaining 20% of services (long-tail legacy)
- Decommission legacy VM fleet
- Enable Karpenter consolidation: automatic bin-packing and node termination
- Introduce spot interruption handling (Karpenter node termination handler)
- Cost optimisation: Compute Savings Plans commit based on stable baseline; Spot for burst
- Security hardening: Pod Security Admission (restricted profile), network policies for all namespaces

---

## Alternatives Considered and Rejected

### Option A: Status Quo with Incremental Improvements (Rejected)

**Reason for rejection**: SSM Patch Manager can automate patch application but does not reduce the 47-day mean time to patch — that is driven by release coordination overhead and fear of breaking changes. Configuration drift is not addressable without full immutability. Utilisation improvement is structurally limited — a VM per service is inherently wasteful. The root problems are architectural, not tooling.

### Option B: EC2 ASG with Immutable Infrastructure (Rejected as primary; accepted as interim)

**Reason for primary rejection**: Immutable ASGs solve patching (AMI rotation) and drift (no SSH). But they do not solve:
- **Bin-packing**: one service per ASG still wastes ~60–70% of each instance
- **Scaling latency**: AMI launch is faster than Ansible but still 3–5 min vs Kubernetes seconds
- **Centralisation**: each ASG is independently managed; no unified control plane for logs, secrets, ingress, resource quotas
- **Developer experience**: developers still think in terms of instances; no standardised manifest format

ASGs are retained as an **interim state** for workloads that cannot be containerised in Phase 1.

### Option D: ECS (Elastic Container Service) Instead of EKS (Rejected)

ECS was evaluated as a simpler AWS-native alternative to Kubernetes.

| Dimension | ECS (Fargate) | EKS |
|-----------|--------------|-----|
| Operational overhead | Lower (no control plane to manage) | Higher (EKS control plane, but AWS-managed) |
| Ecosystem / portability | AWS-only; limited tooling | Kubernetes standard; vast ecosystem (Argo, Karpenter, Prometheus, Istio) |
| Advanced scheduling | Limited | Rich: affinity, tolerations, topology spread, PriorityClass |
| GitOps | Possible (but tooling is immature vs k8s) | Native (Argo CD is the k8s-native standard) |
| Long-term portability | Vendor lock-in | Portable to any k8s (GKE, AKS, on-prem) |
| Team expertise investment | ECS-specific | Transferable across industry |

**Rejected**: ECS Fargate would reduce operational overhead further, but at the cost of ecosystem richness and long-term portability. The engineering organisation's industry context (engineers from and hiring to k8s-fluent backgrounds) makes EKS expertise more valuable than ECS specialisation. Additionally, Karpenter's bin-packing efficiency is not available in ECS.

---

## Decision Criteria Scoring

> Scale: 1 (poor) → 5 (excellent)

| Criterion | Weight | VM Status Quo | EC2 ASG | EKS |
|-----------|--------|:------------:|:-------:|:---:|
| OS patching compliance (14-day SLA) | 25% | 1 | 3 | **5** |
| Developer experience / toil reduction | 20% | 1 | 3 | **5** |
| Resource cost efficiency | 20% | 1 | 3 | **5** |
| Scaling speed (burst latency) | 15% | 2 | 3 | **5** |
| Operational centralisation | 10% | 1 | 2 | **5** |
| Migration complexity / risk | 10% | 5 | 4 | **2** |
| **Weighted score** | | **1.5** | **3.0** | **4.6** |

Migration complexity is EKS's lowest score — acknowledged and addressed via the phased plan and platform team investment.

---

## FAANG Interview Callout

> "This is a classic build-vs-operate trade-off at the infrastructure layer. The VM model optimises for familiarity but imposes O(N) operational overhead as N services grow — every new service is a new set of patching, scaling, and monitoring concerns. EKS shifts the model to O(1): the platform team solves each operational concern once (patching, log shipping, ingress, secret sync) and every service inherits the solution by running on the platform. The key insight is that developer time spent on machine-level concerns is hidden cost — it doesn't show up on the infrastructure bill but it shows up in velocity and retention. The risk of EKS is the learning curve and the stateful workload gap — which is why a phased migration with a pilot cohort is critical. You don't migrate everything on day one; you prove the pattern with 10 services, build the golden path, then scale the migration."

---

## Related ADRs and References

| Resource | Relationship |
|----------|-------------|
| ADR-002: Kafka Consumer Topology | Kafka consumers are candidate workloads for Phase 1 EKS migration |
| ADR-004 (future): Stateful Workload Strategy | Databases, Redis, Kafka brokers — excluded from this ADR |
| [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/) | Authoritative reference for EKS configuration |
| Karpenter documentation | Node provisioning and consolidation |
| Argo CD documentation | GitOps controller |
| "Kubernetes Patterns" — Ibryam & Huß | Reference for pod lifecycle, health probe, resource patterns |
