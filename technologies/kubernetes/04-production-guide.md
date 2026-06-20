# Kubernetes Production Guide — Scaling, Security, Reliability & Upgrades

---

## Mental Model (Beginner)

Running Kubernetes in production is like running a large office building. You need fire exits (PodDisruptionBudget), security badges (RBAC), building codes (PodSecurity policies), HVAC capacity planning (resource requests/limits), and an evacuation plan for when you renovate floors (node upgrades). This guide covers all of it.

---

## Resource Management

### Requests vs Limits — The Most Important Distinction

```
CPU Request  = scheduler reservation (guaranteed headroom on the node)
CPU Limit    = cgroup throttle ceiling (process is slowed, not killed)
Memory Request = scheduler reservation
Memory Limit   = cgroup OOM kill threshold (process is killed immediately)
```

**Why this matters in production**:

| Scenario | What Happens |
|----------|-------------|
| Pod has CPU request but no limit | Pod can burst to full node CPU — risky for noisy neighbours |
| Pod hits CPU limit | `cpu_throttled_seconds` increases; response latency rises silently |
| Pod hits memory limit | Container is OOMKilled (exit code 137); pod restarts |
| Pod has no requests | Scheduler places it anywhere (doesn't know if node has room); node may overcommit |
| Pod has no requests AND no limits | `BestEffort` QoS — first evicted under node memory pressure |

### QoS Classes

Kubernetes assigns a QoS class based on requests/limits:

| QoS Class | Condition | Eviction Priority |
|-----------|-----------|------------------|
| `Guaranteed` | Every container has request == limit (cpu AND memory) | Evicted last |
| `Burstable` | At least one container has a request set (but request ≠ limit) | Evicted after BestEffort |
| `BestEffort` | No requests or limits set at all | Evicted first |

**Production rule**: All workloads in production should be `Guaranteed` or `Burstable`. Never deploy `BestEffort` pods to production namespaces.

### LimitRange — Namespace-Level Defaults

Automatically injects default requests/limits into pods that don't specify them:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
  - type: Container
    default:           # Applied when limits not specified
      cpu: 500m
      memory: 512Mi
    defaultRequest:    # Applied when requests not specified
      cpu: 100m
      memory: 128Mi
    max:               # Hard ceiling any container can request
      cpu: "4"
      memory: 4Gi
    min:
      cpu: 50m
      memory: 64Mi
```

### ResourceQuota — Namespace Budget

Caps total resource consumption per namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    limits.cpu: "200"
    limits.memory: 400Gi
    count/pods: "500"
    count/services: "100"
    count/persistentvolumeclaims: "50"
```

---

## Autoscaling

### HPA — Horizontal Pod Autoscaler

Scales **replica count** based on metrics. Queries metrics-server (for CPU/memory) or a custom metrics adapter.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-service
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70    # Target 70% of CPU request
  - type: Resource
    resource:
      name: memory
      target:
        type: AverageValue
        averageValue: 400Mi
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300    # Don't scale down for 5 min after scale-up
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60               # Scale down at most 10% per minute
    scaleUp:
      stabilizationWindowSeconds: 0     # Scale up immediately
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15               # Double replicas every 15s if needed
```

**HPA gotchas**:
- HPA and manual replica count conflict — never set `replicas` in the Deployment when HPA manages it (or it will fight ArgoCD sync)
- CPU-based HPA requires `requests.cpu` to be set — HPA calculates `actual cpu / cpu request`
- Default reaction time is ~15–30s (scrape interval + stabilization window)

### VPA — Vertical Pod Autoscaler

Adjusts **CPU and memory requests** for pods based on historical usage. Three modes:

| Mode | Behaviour | Use Case |
|------|-----------|---------|
| `Off` | Recommends only (shows in VPA status) | Capacity planning, right-sizing |
| `Initial` | Sets requests only on new pods | Safe for stateless services |
| `Auto` | Updates requests + evicts pods to apply | Use with caution — causes pod restarts |

**Production rule**: Use VPA in `Off` mode for recommendations. Do NOT use VPA + HPA on the same Deployment (they fight over replica count and request sizes). Exception: KEDA replaces HPA, allowing VPA to manage requests alongside it.

### KEDA — Event-Driven Autoscaling

Scales based on external event sources: Kafka consumer lag, SQS queue depth, Prometheus metrics, Redis list length, cron schedule.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
spec:
  scaleTargetRef:
    name: order-processor
  minReplicaCount: 1
  maxReplicaCount: 100
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka:9092
      consumerGroup: order-processors
      topic: orders
      lagThreshold: "100"       # 1 replica per 100 messages of lag
  - type: cron
    metadata:
      timezone: "America/New_York"
      start: "0 9 * * 1-5"     # Scale up weekday mornings
      end: "0 18 * * 1-5"
      desiredReplicas: "10"
```

### Cluster Autoscaler vs Karpenter

| | Cluster Autoscaler | Karpenter |
|--|-------------------|-----------|
| Approach | Scales pre-defined node groups | Provisions nodes directly via cloud API |
| Speed | 3–5 min (group warmup) | ~30–90 seconds (EC2 launch directly) |
| Instance selection | Fixed instance type per node group | Selects best instance for pending pods' requirements |
| Spot support | Manual configuration per node group | Native first-class spot support |
| Cost optimisation | Manual bin-packing tuning | Automatic — matches instance size to pod needs |
| Consolidation | Scale down empty nodes | Proactive consolidation (moves pods to fewer nodes) |
| Cloud support | All clouds | AWS-native (Azure/GCP in beta) |
| Best for | Existing clusters with defined node groups | New AWS clusters wanting best cost + speed |

**Karpenter NodePool example**:
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1
        kind: EC2NodeClass
        name: default
      requirements:
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c", "m", "r"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
```

---

## RBAC — Role-Based Access Control

### Objects

```
ServiceAccount  ──► RoleBinding  ──► Role           (namespace-scoped)
                └─► ClusterRoleBinding ──► ClusterRole  (cluster-scoped)
```

- **Role**: grants permissions within a namespace
- **ClusterRole**: grants permissions cluster-wide or can be bound namespace-scoped via RoleBinding
- **ServiceAccount**: identity for pods (automatically mounted as a token)
- **RoleBinding**: binds a Role/ClusterRole to subjects (users, groups, ServiceAccounts) within a namespace
- **ClusterRoleBinding**: binds cluster-wide

### Least-Privilege ServiceAccount Pattern

```yaml
# Create dedicated ServiceAccount (don't use default)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-processor
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/order-processor  # IRSA
---
# Narrow Role — only what the pod needs
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: order-processor-role
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "watch", "list"]
  resourceNames: ["order-config"]    # Specific resource, not all configmaps
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: order-processor-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: order-processor
  namespace: production
roleRef:
  kind: Role
  name: order-processor-role
  apiGroup: rbac.authorization.k8s.io
```

**IRSA (IAM Roles for Service Accounts)**: On EKS, annotate a ServiceAccount with an IAM role ARN. The pod gets short-lived AWS credentials via OIDC federation. No long-lived AWS access keys in environment variables. This is the production pattern for any pod needing AWS access.

---

## Security Hardening

### Pod Security Standards

Kubernetes 1.25+ uses `PodSecurity` admission controller (replaces deprecated PodSecurityPolicy). Apply per-namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted    # Block non-compliant pods
    pod-security.kubernetes.io/audit: restricted      # Log violations
    pod-security.kubernetes.io/warn: restricted       # Warn in kubectl output
```

| Profile | Restrictions |
|---------|-------------|
| `privileged` | No restrictions (system namespaces: kube-system, CNI) |
| `baseline` | Disallows privileged containers, host networking/PID/IPC, most host path mounts |
| `restricted` | Baseline + requires non-root, drops all capabilities, read-only root FS, seccomp required |

### securityContext — Container Hardening

```yaml
spec:
  securityContext:
    runAsNonRoot: true          # Container image must have USER set
    runAsUser: 1000
    fsGroup: 2000               # Volume files owned by this group
    seccompProfile:
      type: RuntimeDefault      # Use container runtime's default seccomp profile
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false   # Cannot gain more privileges than parent
      readOnlyRootFilesystem: true      # Filesystem is read-only (write to volumes)
      capabilities:
        drop:
        - ALL                          # Drop all Linux capabilities
        add:
        - NET_BIND_SERVICE             # Only add back what you need
```

### Image Security

```
Build time:
  - Pin to digest, not tag: my-image@sha256:abc123 (tags are mutable)
  - Scan with Trivy, Snyk, or Grype in CI — fail on CRITICAL
  - Use distroless or Alpine base images (fewer attack surfaces)
  - Run as non-root user in Dockerfile: USER 1000

Runtime (Cluster):
  - ImagePullPolicy: Always (for :latest) or IfNotPresent (for SHA-pinned)
  - OPA Gatekeeper / Kyverno policy: reject images from untrusted registries
  - Falco DaemonSet: runtime anomaly detection (unexpected syscalls, exec in container)
```

---

## Reliability Patterns

### PodDisruptionBudget — Voluntary Disruption Protection

Limits how many pods can be unavailable during voluntary disruptions (node drains, upgrades):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-service-pdb
spec:
  selector:
    matchLabels:
      app: my-service
  minAvailable: 2           # Always keep at least 2 pods running
  # OR:
  # maxUnavailable: 1       # At most 1 pod unavailable at a time
```

**Production rule**: Every production Deployment with `replicas >= 2` should have a PDB. Without it, a `kubectl drain` can evict all pods simultaneously.

### Topology Spread Constraints — Spread Pods Across AZs

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1                                      # Max difference between any two AZs
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule               # Hard constraint
    labelSelector:
      matchLabels:
        app: my-service
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname            # Also spread across nodes
    whenUnsatisfiable: ScheduleAnyway             # Soft constraint
    labelSelector:
      matchLabels:
        app: my-service
```

### Anti-Affinity — Prevent Co-location

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:    # Hard rule
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values: ["my-service"]
        topologyKey: kubernetes.io/hostname              # No two pods on same node
```

**Spread Constraints vs Anti-Affinity**:
- `topologySpreadConstraints` is more flexible — controls the *distribution* across zones/nodes
- `podAntiAffinity` with `required` is a hard binary rule — useful for "never co-locate" but can cause scheduling failures if nodes are limited

---

## Cluster Upgrade Strategy

### Version Skew Policy

| Component | Supported skew |
|-----------|---------------|
| kubelet vs API Server | kubelet can be N-2 older than API Server |
| kubectl vs API Server | kubectl can be N+1 older or newer |
| Control plane components | Must all be same version |
| Add-ons (CoreDNS, etc.) | Check compatibility matrix per addon |

### Control Plane Upgrade

```bash
# 1. Check available versions
kubeadm upgrade plan

# 2. Upgrade control plane (one version at a time, never skip minor versions)
kubeadm upgrade apply v1.29.0

# 3. Update kubelet + kubectl on control plane nodes
apt-get update && apt-get install -y kubelet=1.29.0-00 kubectl=1.29.0-00
systemctl daemon-reload && systemctl restart kubelet
```

### Worker Node Upgrade

```bash
# 1. Cordon: mark node unschedulable (no new pods land here)
kubectl cordon node-1

# 2. Drain: evict existing pods gracefully (respects PDB)
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data --timeout=300s

# 3. Upgrade kubelet on the node
# (SSH to node, apt-get install kubelet=1.29.0-00, systemctl restart kubelet)

# 4. Uncordon: allow new pods to schedule here again
kubectl uncordon node-1

# 5. Verify
kubectl get nodes   # Should show new version
```

**Rolling node upgrade pattern**: Upgrade nodes one at a time (or in small batches if PDB allows). On EKS with Karpenter, create new NodePool with the new AMI version, then cordon/drain old nodes — Karpenter automatically launches new nodes.

---

## Production Readiness Checklist

| # | Check | Why |
|---|-------|-----|
| 1 | `resources.requests` set on all containers | Scheduler needs this to place pods correctly |
| 2 | `resources.limits` set on all containers | Prevent noisy-neighbour OOM |
| 3 | `readinessProbe` configured | Prevents traffic to starting pods |
| 4 | `livenessProbe` configured | Restarts deadlocked processes |
| 5 | `startupProbe` for slow-starting apps | Prevents premature liveness kills during init |
| 6 | `replicas >= 2` for all stateless services | Single replica = single point of failure |
| 7 | `PodDisruptionBudget` defined | Protect against drain/upgrade taking all pods |
| 8 | `topologySpreadConstraints` across AZs | Survive AZ outage |
| 9 | `podAntiAffinity` across nodes | Survive node failure |
| 10 | `imagePullPolicy: IfNotPresent` with SHA-pinned tags | Avoid unnecessary pulls; deterministic deploys |
| 11 | `readOnlyRootFilesystem: true` | Prevent runtime file modification |
| 12 | `runAsNonRoot: true` | No root process in container |
| 13 | `allowPrivilegeEscalation: false` | No sudo/suid escalation |
| 14 | `capabilities: drop: [ALL]` | Remove all Linux capabilities |
| 15 | Dedicated `ServiceAccount` per workload | Least-privilege identity |
| 16 | `NetworkPolicy` restricting ingress/egress | Microsegmentation |
| 17 | Secrets via External Secrets Operator | No plaintext secrets in manifests |
| 18 | HPA configured (or KEDA) | Handle traffic spikes |
| 19 | `terminationGracePeriodSeconds` tuned | Graceful shutdown (default 30s — increase for slow apps) |
| 20 | Resource quotas set per namespace | Prevent one team consuming all cluster resources |

---

## Common Production Incidents & Root Causes

| Symptom | Likely Cause | Investigation |
|---------|-------------|---------------|
| Pod `OOMKilled` (exit 137) | Memory limit too low OR memory leak | `kubectl top pods`, `kubectl describe pod` — check `lastState.terminated.reason` |
| Pod `CrashLoopBackOff` | App crash on startup | `kubectl logs <pod> --previous` — see last run's logs |
| `Pending` pod, never schedules | Insufficient CPU/memory on nodes OR taint/affinity mismatch | `kubectl describe pod` — Events section shows reason |
| Service endpoints empty | Readiness probe failing on all pods | `kubectl get endpoints <svc>`, `kubectl describe pod` for probe failures |
| HPA not scaling | Metrics not available (no metrics-server) OR pods already at maxReplicas | `kubectl describe hpa` — shows current/target metrics |
| Node `NotReady` | kubelet crash, disk pressure, memory pressure | `kubectl describe node`, check node conditions |
| `ImagePullBackOff` | Wrong image tag, registry auth failure | `kubectl describe pod` — Events show exact error |
| Slow DNS resolution | ndots:5 causing many NXDOMAIN lookups | `kubectl exec -- cat /etc/resolv.conf`, use FQDN or ndots:2 |

---

## FAANG Interview Callouts

**Q: "How would you ensure zero-downtime deploys for a stateless microservice?"**
> 1. **replicas >= 2** — rolling update keeps one available
> 2. **PDB `minAvailable: 1`** — protects against concurrent voluntary disruptions
> 3. **`readinessProbe`** — new pods only receive traffic once healthy
> 4. **`maxUnavailable: 0, maxSurge: 1`** in RollingUpdate strategy — never reduces below requested replicas
> 5. **`terminationGracePeriodSeconds`** tuned to drain in-flight requests (use `preStop` sleep if needed)
> 6. **HPA** with a warm floor — `minReplicas` covers baseline so scale-up isn't needed mid-deploy
> This is the pattern Netflix uses for their services on K8s — they call it "always available" rolling deploys.

**Q: "How do you prevent a badly-written service from taking down other services on the same cluster?"**
> Four layers of isolation:
> 1. **ResourceQuota per namespace** — caps total CPU/memory that team can consume
> 2. **LimitRange** — injects default limits if developers forget to set them
> 3. **Network policies** — blast radius is contained; a compromised pod can't reach unrelated services
> 4. **Node isolation via taints/tolerations** — critical services on dedicated node pools, shielded from noisy workloads
> At Google (GKE), tenant isolation uses per-team node pools with Workload Identity for IAM boundaries.
