# AWS EKS (Elastic Kubernetes Service)

## Overview
EKS is AWS's managed Kubernetes service. AWS manages the control plane (API server, etcd, scheduler, controller manager) with a 99.95% SLA. You manage the worker nodes (EC2 or Fargate) or use managed node groups (AWS manages EC2 lifecycle within your account).

**When to use EKS over ECS**: Kubernetes ecosystem requirement (Helm, Kustomize, service mesh, CRDs, RBAC), multi-cloud portability, existing Kubernetes expertise, or workloads needing advanced scheduling (GPU, topology spread, PodDisruptionBudgets).

---

## EKS Architecture

```
EKS Control Plane (AWS-managed, multi-AZ, in AWS VPC)
    ↓ Kubernetes API (via API Server endpoint)
Worker Nodes (in your VPC)
├── Managed Node Group 1 (m7g.xlarge × 3, across 3 AZs)
├── Managed Node Group 2 (g5.12xlarge × 2, GPU, single AZ)
└── Fargate Profile (serverless; for burst/batch pods)

Networking:
├── VPC CNI (aws-node daemonset): each pod gets a VPC IP (from ENI prefix delegation)
├── CoreDNS: cluster-internal DNS
└── kube-proxy: iptables rules for Service load balancing
```

---

## Node Provisioning Options

| Option | Management | Flexibility | Best for |
|---|---|---|---|
| **Managed Node Groups** | AWS manages EC2 lifecycle (launch, update, drain) | Instance type/size per group | Standard production workloads |
| **Self-managed nodes** | You manage ASG and EKS node bootstrapping | Full control | Custom AMI, kernel tuning, exotic configs |
| **Fargate profiles** | AWS manages nodes entirely; one pod per "node" | No node management; no DaemonSets | Burst capacity, batch, isolation-required workloads |
| **Karpenter** | Provisions/deprovisions EC2 directly based on pod needs | Any instance type, just-in-time | Cost-optimised, mixed-instance, fast scaling |

**Karpenter vs Cluster Autoscaler**:
| | Cluster Autoscaler | Karpenter |
|---|---|---|
| Speed | 1–3 min (CA → ASG → EC2 bootstrap) | 45–90s (CA → node ready) |
| Instance diversity | One type per node group | Any instance type; picks best fit |
| Bin packing | Good | Excellent (provisions exact fit node) |
| Spot support | Via ASG mixed instances | Native, per-node decision |
| Configuration | Node group per instance family | NodePool + NodeClass CRDs |
| **Recommendation** | Legacy; still used | **Preferred for new clusters** |

---

## Networking: VPC CNI

EKS uses the **AWS VPC CNI plugin** — each pod gets a real VPC IP address (not an overlay network). This has profound implications:

**IP address planning**:
- Each EC2 node can host pods equal to: `(ENIs on instance - 1) × IPs per ENI + 1`
- A `m5.large` has 3 ENIs × 10 IPs = 30 pod IPs minus overhead = ~22 pods max
- With **prefix delegation**: ENIs can get /28 prefixes (16 IPs each) → `m5.large` = 3 ENIs × 16 = 48 pod IPs → ~30 pods

**Subnet size for EKS**:
- Minimum /24 (251 IPs) per AZ for node subnets; /19 or larger recommended for large clusters
- Each node consumes IPs beyond just the pod count (VPC CNI buffer pool pre-allocates IPs)
- Recommendation: use a secondary CIDR (`100.64.0.0/10`) for pod IPs — separate from node CIDR

**Custom networking**: route pod traffic through a secondary VPC CIDR to avoid exhausting primary CIDR.

**NetworkPolicy**: by default, all pods can talk to all pods. Enable Kubernetes NetworkPolicy via:
- **VPC CNI NetworkPolicy controller** (native, no overlay needed, AWS-managed)
- **Calico** (open-source, more features)

---

## IAM for EKS: IRSA (IAM Roles for Service Accounts)

The correct way for pods to access AWS services — not EC2 instance roles.

**How it works**:
1. EKS cluster has an OIDC issuer URL
2. IAM role has a trust policy trusting the OIDC provider + specific ServiceAccount
3. Pod annotation references the IAM role
4. EKS token webhook injects a token into the pod; AWS SDK exchanges it for temporary credentials

```yaml
# ServiceAccount with IRSA annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payments-service
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/payments-service-role
---
# IAM trust policy (role side)
{
  "Principal": {"Federated": "arn:aws:iam::123456789:oidc-provider/oidc.eks.us-east-1.amazonaws.com/..."},
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/...:sub": "system:serviceaccount:production:payments-service"
    }
  }
}
```

Each pod gets a unique IAM role — perfect least privilege. Token rotates automatically. Never use node instance roles for pod-level AWS access.

---

## EKS Add-ons (AWS-managed)

| Add-on | Purpose | Key config |
|---|---|---|
| **VPC CNI (aws-vpc-cni)** | Pod networking | Enable prefix delegation; set `WARM_PREFIX_TARGET` |
| **CoreDNS** | Cluster DNS | Scale replicas for large clusters; node-local DNS cache |
| **kube-proxy** | Service networking (iptables) | Switch to IPVS for large clusters (>1,000 services) |
| **AWS EBS CSI Driver** | EBS persistent volumes for pods | Required for StatefulSets using EBS |
| **AWS EFS CSI Driver** | EFS shared persistent volumes | ReadWriteMany volumes for shared storage |
| **Load Balancer Controller** | Provision ALB/NLB from Ingress/Service | Replaces deprecated in-tree cloud controller |
| **ExternalDNS** | Create Route53 records from Services/Ingresses | Automates DNS management |
| **Cert-Manager** | TLS certificate management | ACME + Let's Encrypt + ACM PCA |
| **Secrets Store CSI Driver** | Mount Secrets Manager/SSM as files | Alternative to environment variable injection |

---

## Scaling

### Horizontal Pod Autoscaler (HPA)
Scales pod replicas based on CPU, memory, or custom metrics:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: payments-api}
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
  - type: External
    external:
      metric:
        name: sqs_messages_visible
        selector: {matchLabels: {queue: orders}}
      target: {type: AverageValue, averageValue: 10}
```

### Vertical Pod Autoscaler (VPA)
Recommends and optionally sets CPU/memory `requests` based on actual usage. Use in Recommendation mode first — do not auto-apply in production without testing (VPA restarts pods to apply new resource values).

### Cluster Autoscaler / Karpenter
Node scaling (see above). Karpenter: configure NodePool with instance type family, capacity type (Spot/On-Demand), and disruption budget.

---

## Storage

**EBS (via EBS CSI Driver)**:
- `ReadWriteOnce` — one pod on one node; for databases, stateful applications
- Dynamic provisioning via `StorageClass` with `gp3` volume type
- EBS volumes are AZ-specific — StatefulSet pods must schedule in the same AZ as their PVC

**EFS (via EFS CSI Driver)**:
- `ReadWriteMany` — multiple pods on multiple nodes share the same volume
- Cross-AZ shared storage; suitable for content management, shared config
- Higher latency than EBS; costs more per GB; no capacity planning needed

**S3 Mountpoint**:
- Mount S3 bucket as a filesystem inside a pod
- Sequential read-optimised; no random writes; for ML model serving, data processing

---

## EKS Security

### Pod Security
**Pod Security Admission (PSA)** — enforces pod security standards at namespace level:
- `privileged`: no restrictions (use for system components only)
- `baseline`: prevents most privilege escalation
- `restricted`: strongly hardened (no privilege, no hostPath, non-root required)

Apply `restricted` to application namespaces:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Network Security
- **NetworkPolicy**: deny all ingress/egress by default; allow only explicit paths
- **Service mesh (Istio/AWS App Mesh)**: mTLS between services, traffic policy, observability
- **Falco**: runtime threat detection — alerts on suspicious syscalls (shell in container, unexpected file write)

### Secrets Management
- Kubernetes Secrets are base64-encoded, not encrypted by default
- Enable **EKS envelope encryption** with KMS — encrypts etcd data at rest
- Use **Secrets Store CSI Driver** to mount Secrets Manager/SSM secrets as files (not env vars)
- **External Secrets Operator** — sync Secrets Manager to Kubernetes Secrets automatically

---

## Observability

**Metrics**: 
- Deploy **Prometheus + Grafana** (or Amazon Managed Prometheus / Managed Grafana)
- CloudWatch Container Insights: enabled via CloudWatch agent daemonset + Fluent Bit

**Logging**:
- **Fluent Bit DaemonSet** → CloudWatch Logs or Kinesis or OpenSearch
- Log by namespace, pod, and container for filtering

**Tracing**:
- AWS X-Ray Daemon DaemonSet or OpenTelemetry Collector
- Instrument applications with OpenTelemetry SDKs

**Key metrics to monitor**:
| Metric | Source | Alert condition |
|---|---|---|
| `kube_pod_status_phase` | kube-state-metrics | `Pending` pods sustained > 5 min → scheduling issue |
| `kube_deployment_status_replicas_unavailable` | kube-state-metrics | > 0 for production deployment |
| `node_cpu_utilization` | node-exporter | > 80% → add nodes |
| `container_oom_events_total` | cAdvisor | > 0 → increase memory limit |
| API server `apiserver_request_duration_seconds` | EKS control plane | P99 > 1s → API server load |
| `karpenter_nodes_total` | Karpenter | Unexpected changes → investigate disruptions |

---

## EKS Upgrade Strategy

EKS supports N-2 minor versions. AWS releases a new minor version every ~3 months and deprecates old versions on a 12-14 month cycle.

**Upgrade sequence**:
1. Update EKS cluster control plane (15-20 minute operation, zero downtime)
2. Update managed add-ons (VPC CNI, CoreDNS, kube-proxy) — one by one
3. Update managed node groups (rolling AMI update, like ASG Instance Refresh)
4. Verify application compatibility (check deprecated API versions)

**Breaking changes**: use `kubectl deprecations` (Pluto tool) before upgrading — finds API versions your manifests use that are removed in the new version.

---

## Best Practices

1. **Use IRSA** for all pod-level AWS access — not EC2 instance roles; precise least privilege per pod
2. **Enable prefix delegation** in VPC CNI — 3–4× more pod IPs per node
3. **Use Karpenter** over Cluster Autoscaler — faster, more flexible, better Spot handling
4. **Apply NetworkPolicy** to all production namespaces — default deny; explicit allow
5. **Use managed node groups** — AWS patches AMIs; you trigger rolling updates
6. **Encrypt etcd with KMS** — enable EKS envelope encryption on new and existing clusters
7. **Use Secrets Store CSI Driver** over Kubernetes Secrets for sensitive values — no base64-in-etcd storage
8. **Enable Pod Security Admission** in `restricted` mode for application namespaces
9. **Multi-AZ for all StatefulSets** — or accept single-AZ if EBS volume placement is constrained
10. **Upgrade cluster within N-2 versions** — don't let a cluster fall behind; security patches matter

---

## FAANG Interview Points

**"ECS vs EKS"**: See ecs.md comparison. Short: ECS for AWS-native simplicity; EKS for Kubernetes ecosystem and portability. Neither is technically superior — it's operational context.

**"How does pod-level IAM work in EKS?"**: IRSA: OIDC identity provider → IAM role trust policy scoped to specific ServiceAccount → pod annotated with role ARN → webhook injects token → AWS SDK exchanges token for temporary credentials. Zero credential in environment; per-pod isolation; no node-level blast radius.

**"How do you scale a Kubernetes cluster for a 10× traffic spike?"**: HPA scales pods (30-60s). Karpenter provisions nodes (45-90s). Pre-warm with Karpenter Disruption Budget to keep buffer nodes. For predictable spikes, schedule Karpenter `NodePool` expansion. Spot instances with multiple families for capacity availability.

**"How do you secure pod-to-pod traffic in EKS?"**: NetworkPolicy (default deny per namespace) + Service mesh (mTLS with Istio or App Mesh) for encryption in transit. Falco for runtime anomaly detection. Pod Security Admission for container capabilities restriction. IRSA for AWS resource isolation.
