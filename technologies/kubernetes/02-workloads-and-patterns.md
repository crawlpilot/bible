# Kubernetes Workloads & Networking Patterns

---

## Mental Model (Beginner)

Think of a **Pod** as a single virtual computer that holds your application. A **Deployment** is like hiring a staffing agency — you say "I always want 3 copies of this app running" and the agency makes sure that's always true, even if one quits. A **Service** is your app's permanent phone number — it never changes even as individual pods come and go.

---

## Workload Objects

### Pod — The Atomic Unit

A Pod is the smallest deployable unit in Kubernetes. It wraps one or more containers that:
- Share the same **network namespace** (same IP, can talk via `localhost`)
- Share the same **PID namespace** (optional, off by default)
- Can share **volumes** (mounted into each container)

**Never create bare Pods in production** — they are not rescheduled if the node fails. Always use a higher-level controller (Deployment, StatefulSet, etc.).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  containers:
  - name: app
    image: my-app:1.2.3
    ports:
    - containerPort: 8080
    resources:
      requests:
        cpu: "250m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
    readinessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 15
      failureThreshold: 3
```

### Multi-Container Pod Patterns

| Pattern | Containers | Purpose | Example |
|---------|-----------|---------|---------|
| **Sidecar** | app + helper | Augment app functionality | Envoy proxy, log shipper, secrets reloader |
| **Init container** | init (sequential, then app) | One-time setup before app starts | DB migration, wait-for-dependency, cert fetch |
| **Ephemeral container** | injected at runtime | Debugging live pods | `kubectl debug`, adding netshoot to a pod |
| **Ambassador** | app + proxy | Proxy outbound traffic | Route DB calls through a connection pool proxy |

**Init vs Sidecar for setup**: Use init containers for tasks that must complete before the app starts (schema migration). Use sidecar for ongoing tasks that run alongside the app (metrics scraping). Kubernetes 1.29+ supports native sidecar containers with `restartPolicy: Always` in init container spec — these start before app containers and survive restarts.

---

### Deployment — Stateless Workloads

**Beginner**: "Run N replicas of my app, replace one at a time during updates."

**What it manages**: Creates and owns a ReplicaSet. On update, creates a new ReplicaSet and gradually shifts pods from old to new.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-service
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0      # Never reduce below 3 during rollout
      maxSurge: 1            # Allow up to 4 pods during rollout
  template:
    metadata:
      labels:
        app: my-service
    spec:
      containers:
      - name: app
        image: my-service:2.0.0
        ...
```

**Rollout strategies**:
| Strategy | Behaviour | Use Case |
|----------|-----------|---------|
| `RollingUpdate` (default) | Gradually replace old pods with new | Zero-downtime deploys for stateless services |
| `Recreate` | Kill all old pods first, then create new | When two versions cannot coexist (DB migrations with breaking schema) |
| Blue/Green (manual) | Switch Service selector to new Deployment | Instant cutover, easy rollback |
| Canary (via Argo Rollouts / Flagger) | Route small % traffic to new version | Risk-limited progressive delivery |

---

### StatefulSet — Stateful Workloads

**Beginner**: "Like a Deployment, but each pod has a permanent name and its own persistent disk."

**Key guarantees**:
- **Stable network identity**: `pod-0`, `pod-1`, `pod-2` — names never change
- **Stable storage**: each pod gets its own PVC, not shared
- **Ordered start/stop**: pods start in order (0→1→2) and stop in reverse (2→1→0)
- **Ordered updates**: default rolling update updates from highest ordinal down

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
spec:
  serviceName: kafka-headless   # Required: headless service for DNS
  replicas: 3
  selector:
    matchLabels:
      app: kafka
  template:
    spec:
      containers:
      - name: kafka
        image: confluentinc/cp-kafka:7.5.0
        volumeMounts:
        - name: data
          mountPath: /var/kafka-data
  volumeClaimTemplates:         # Each pod gets its own PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp3
      resources:
        requests:
          storage: 500Gi
```

**Headless service**: `clusterIP: None` — gives each pod a stable DNS name: `kafka-0.kafka-headless.default.svc.cluster.local`. Required for peer discovery in Kafka/Cassandra/ZooKeeper.

**When to use StatefulSet vs Deployment**:
| | Deployment | StatefulSet |
|--|-----------|------------|
| Pod identity | Random suffix | Stable ordinal (pod-0, pod-1) |
| Storage | Shared or none | Per-pod PVC |
| Scale order | Any order | Sequential |
| Use for | APIs, web servers, workers | Kafka, Cassandra, ZooKeeper, Redis Sentinel |

---

### DaemonSet — One Pod Per Node

Ensures exactly one pod runs on every (or selected) node. Pods are added automatically as nodes join the cluster.

**Use cases**: log collectors (Fluentd, Filebeat), node metrics exporters (node-exporter), CNI plugins, security agents (Falco), kube-proxy.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.7.0
        ports:
        - containerPort: 9100
```

---

### Job & CronJob — Batch Workloads

**Job**: Run a task to completion. Pod is retried on failure up to `backoffLimit`. Completed pods are kept for log inspection (clean up with `ttlSecondsAfterFinished`).

**CronJob**: Wraps a Job with a cron schedule. Manages Job creation; configure `concurrencyPolicy` (`Allow`, `Forbid`, `Replace`) for overlap handling.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report-generator
spec:
  schedule: "0 2 * * *"          # 2am daily
  concurrencyPolicy: Forbid      # Skip if previous run still active
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: reporter
            image: report-generator:1.0.0
```

---

## Networking Objects

### Service — Stable Endpoint for Pods

A Service provides a stable virtual IP (ClusterIP) and DNS name that load-balances to pods matching its label selector. Pods can come and go; the Service IP never changes.

**Service types**:

| Type | Reachable From | How | Use Case |
|------|---------------|-----|---------|
| `ClusterIP` (default) | Inside cluster only | Virtual IP via iptables/IPVS | Service-to-service calls |
| `NodePort` | External (via any node IP) | Node opens port 30000–32767 | Dev/testing, on-prem without LB |
| `LoadBalancer` | External | Cloud provisions LB (ELB, GLB) | Production external ingress for a single service |
| `ExternalName` | Inside cluster | DNS CNAME alias | Route to external service by DNS name |
| `Headless` (ClusterIP: None) | Inside cluster | DNS returns pod IPs directly | StatefulSet peer discovery, client-side LB |

```yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-service
spec:
  selector:
    app: payment-service
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
```

**kube-proxy modes**:
- `iptables` (default): O(n) rule matching — degrades at 10k+ services
- `IPVS`: O(1) hash-table lookup — required for large clusters (1000+ services)
- `eBPF` (Cilium): bypasses kernel networking stack entirely — best performance

---

### Ingress — HTTP Routing

Ingress routes external HTTP/HTTPS traffic to Services based on host and path rules.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls-cert
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /users
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 80
      - path: /orders
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 80
```

**Ingress controller options**:
| Controller | Strengths | Weaknesses |
|-----------|----------|-----------|
| **NGINX Ingress** | Mature, widely used, rich annotations | Configuration via annotations is messy at scale |
| **AWS ALB Ingress (aws-load-balancer-controller)** | Native ALB, WAF integration, target group binding | AWS-only |
| **Traefik** | Auto-discovery, Let's Encrypt, dashboard | Less battle-tested at very large scale |
| **Kong / APISIX** | API Gateway features (auth, rate limit, transform) | More complex to operate |

**Gateway API** (successor to Ingress): More expressive, role-oriented (GatewayClass → Gateway → HTTPRoute). Now GA in K8s 1.28+. Prefer for new deployments.

---

### NetworkPolicy — Pod-Level Firewall

By default, all pods can reach all pods. NetworkPolicy lets you restrict this.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payment-isolation
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - port: 5432
```

**Principal-level**: NetworkPolicy is enforced by the CNI plugin — Flannel does NOT support it. Calico and Cilium do. Cilium additionally supports L7 policies (e.g., "only allow HTTP GET to /api/v1").

---

## Configuration Objects

### ConfigMap — Externalised Config

Stores non-secret configuration as key-value pairs or files. Inject as environment variables or volume mounts.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
  config.yaml: |
    database:
      pool_size: 10
      timeout: 30s
```

**Mounting as file** (recommended for config files; allows hot-reload in some apps):
```yaml
volumeMounts:
- name: config
  mountPath: /etc/app/config.yaml
  subPath: config.yaml
volumes:
- name: config
  configMap:
    name: app-config
```

**Hot-reload gotcha**: When a ConfigMap is updated and mounted as a volume, the file is updated (with a ~1-2 minute propagation delay via kubelet sync). Environment variables from ConfigMaps are NOT updated without a pod restart.

### Secret — Sensitive Configuration

Same structure as ConfigMap but base64-encoded and (optionally) encrypted at rest in etcd. By default, Secrets are just base64 — not encrypted unless you configure an encryption provider (KMS, AWS KMS envelope encryption).

**Best practices**:
- Never put secrets in Helm `values.yaml` checked into git
- Use **External Secrets Operator** (syncs from AWS Secrets Manager, Vault, GCP Secret Manager)
- Use **Sealed Secrets** (Bitnami) for encrypting secrets before committing to git
- Mount as volume, not env var — env vars are visible in `/proc/<pid>/environ`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  username: dXNlcm5hbWU=   # base64("username")
  password: cGFzc3dvcmQ=   # base64("password")
```

---

## Storage Patterns

### Volume Types by Use Case

| Use Case | Volume Type | Notes |
|----------|------------|-------|
| Ephemeral scratch space shared between containers | `emptyDir` | Deleted when pod is deleted |
| Node-local data (node-exporter, log collectors) | `hostPath` | Dangerous — gives pod access to host FS |
| Persistent app data | `PersistentVolumeClaim` | Survives pod restarts, backed by cloud disk |
| Configuration files | `configMap` / `secret` | Read-only; hot-reload on update (volume mount) |
| Multiple pods reading same data | `PVC (RWX)` + NFS/EFS | ReadWriteMany requires shared filesystem |
| Service account token for API access | `projected` (serviceAccountToken) | Auto-mounted; audience-bound, expiring |

### Dynamic Provisioning Flow

```
Developer                   K8s Control Plane               Cloud Provider
    │                              │                               │
    │  kubectl apply PVC           │                               │
    ├─────────────────────────────►│                               │
    │                              │  PVC.storageClass = "gp3"     │
    │                              │  Look up StorageClass         │
    │                              │  provisioner: ebs.csi.aws.com │
    │                              ├──────────────────────────────►│
    │                              │                               │ CreateVolume
    │                              │                               │ (80Gi gp3 EBS)
    │                              │◄──────────────────────────────┤
    │                              │  vol-0abc123 created          │
    │                              │  Create PV, bind to PVC       │
    │  PVC status: Bound           │                               │
    │◄─────────────────────────────┤                               │
```

---

## Probe Reference

| Probe | Purpose | Failure Action |
|-------|---------|---------------|
| `readinessProbe` | "Is this pod ready to receive traffic?" | Remove from Service endpoints — no traffic sent |
| `livenessProbe` | "Is this pod still alive / not deadlocked?" | Restart the container |
| `startupProbe` | "Has the app finished initialising?" | Disables liveness/readiness checks until startup succeeds; prevents premature restart of slow-starting apps |

**Critical nuance**: `livenessProbe` failure = **container restart** (respects `restartPolicy`). Do NOT make liveness probes check external dependencies (DB, downstream APIs) — if your DB goes down, you don't want all pods to restart simultaneously. Liveness should only check internal process health (e.g., `GET /ping` that returns 200 if the JVM/process is alive).

---

## FAANG Interview Callouts

**Q: "When would you use StatefulSet over Deployment for Kafka on K8s?"**
> Kafka brokers require stable network identities for inter-broker replication (brokers reference each other by hostname) and per-broker persistent log storage. StatefulSet provides both: `kafka-0.kafka-headless.svc.cluster.local` never changes, and each broker gets its own `PVC` that survives pod restarts. A Deployment would assign random pod names and share or lose storage on reschedule.

**Q: "How does a Service actually route traffic to pods?"**
> The Endpoints controller watches pods matching the Service's label selector and writes their IPs to an EndpointSlice object. `kube-proxy` on each node watches these EndpointSlices and programs iptables DNAT rules: any packet destined for the ClusterIP is NAT'd to one of the endpoint IPs using random selection (or IPVS round-robin). The routing is entirely local to each node — no centralised proxy.

**Q: "What's the difference between requests and limits, and why does it matter?"**
> `requests` = what the Scheduler uses to find a node with enough headroom — it's a reservation. `limits` = the hard cap enforced by cgroups. A pod can burst above its CPU request up to its CPU limit, but will be **throttled** (not killed) at the limit. For memory, exceeding the limit causes an **OOM kill**. Running without requests means the Scheduler makes no guarantees about placement; running without limits means a noisy-neighbour pod can starve everything on the node.
