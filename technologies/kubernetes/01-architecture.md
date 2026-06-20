# Kubernetes Architecture — Control Plane, Data Plane, Networking, Storage

---

## Mental Model (Beginner)

Think of Kubernetes like a **very smart restaurant manager**.

- The **menu** (your YAML files) describes what dishes should be available and in what quantities.
- The **manager** (Control Plane) reads the menu, assigns tasks to kitchen staff, and continuously checks that reality matches the menu.
- The **kitchen staff** (Worker Nodes / kubelet) actually prepare the dishes (run containers).
- If a dish falls off the pass (a pod crashes), the manager immediately orders another one — you don't have to call anyone.

The fundamental principle: **declare desired state → K8s reconciles actual state toward it, forever.**

---

## The Reconciliation Loop (Core Mental Model)

Every controller in Kubernetes runs the same loop:

```
┌─────────────────────────────────────────────────────────┐
│                   Reconciliation Loop                    │
│                                                         │
│   1. Watch API Server for resource changes              │
│   2. Read desired state from spec                       │
│   3. Read actual state from cluster                     │
│   4. Compute diff                                       │
│   5. Take minimal action to close the gap               │
│   6. Update status subresource                          │
│   7. Go to 1                                            │
└─────────────────────────────────────────────────────────┘
```

This is not polling — controllers use the **watch API** (server-sent events over HTTP/2), so reaction latency is typically under 100ms for in-cluster events.

---

## Control Plane Components

```
┌────────────────────────────── Control Plane ──────────────────────────────┐
│                                                                            │
│   kubectl / CI ──► ┌──────────────────────────────────────────────────┐   │
│   External APIs     │            kube-apiserver                        │   │
│                     │  • REST + Watch endpoints for all K8s objects   │   │
│                     │  • AuthN (certs, OIDC, tokens)                  │   │
│                     │  • AuthZ (RBAC, webhooks)                       │   │
│                     │  • Admission controllers (mutating, validating) │   │
│                     └──────────────────────┬───────────────────────── ┘   │
│                                            │ read/write                   │
│                              ┌─────────────▼──────────────┐               │
│                              │         etcd               │               │
│                              │  Raft-based, strongly      │               │
│                              │  consistent KV store       │               │
│                              │  (cluster's single source  │               │
│                              │   of truth)                │               │
│                              └────────────────────────────┘               │
│                                                                            │
│   ┌──────────────────────────┐   ┌──────────────────────────────────────┐ │
│   │   kube-scheduler         │   │   kube-controller-manager            │ │
│   │                          │   │                                      │ │
│   │  Watches for unbound     │   │  Runs all built-in controllers:      │ │
│   │  pods (no nodeName set)  │   │  • ReplicaSet controller             │ │
│   │  Scores nodes on:        │   │  • Deployment controller             │ │
│   │  • resource fit          │   │  • Node lifecycle controller         │ │
│   │  • affinity/anti-        │   │  • Endpoints controller              │ │
│   │    affinity              │   │  • Namespace controller              │ │
│   │  • taints/tolerations    │   │  • ServiceAccount controller         │ │
│   │  • topology spread       │   │  ... (30+ controllers)               │ │
│   │  Binds pod → node        │   │                                      │ │
│   └──────────────────────────┘   └──────────────────────────────────────┘ │
│                                                                            │
│   ┌──────────────────────────────────────────────────────────────────────┐ │
│   │   cloud-controller-manager (optional, cloud-provider specific)       │ │
│   │   Manages: LoadBalancer provisioning, Node lifecycle (AWS/GCP/Azure) │ │
│   └──────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────┘
```

### kube-apiserver — The Gateway

**What it does**: Every mutation to cluster state goes through the API Server. It validates, authorises, admits, and then writes to etcd. All other components watch the API Server for changes — they never watch etcd directly.

**Admission controller pipeline** (principal-level):
```
Request ──► AuthN ──► AuthZ ──► Mutating Admission ──► Object Validation ──► Validating Admission ──► etcd write
```

Key admission controllers:
- `MutatingAdmissionWebhook` — inject sidecars, set default labels
- `ValidatingAdmissionWebhook` — enforce policy (OPA/Gatekeeper, Kyverno)
- `PodSecurity` — enforce pod security standards (replaces deprecated PSP)
- `LimitRanger` — apply default resource requests/limits
- `ResourceQuota` — enforce namespace-level resource budgets

**Failure blast radius**: If the API Server goes down, **no new state changes** can be made. Existing running pods continue normally — kubelet has a local cache. This is why HA control planes run 3 API Server replicas behind a load balancer.

### etcd — The Source of Truth

**What it is**: A distributed key-value store using the Raft consensus algorithm. Every K8s object (pod, service, secret, etc.) is stored here as a protobuf blob.

**Key properties**:
- **Strongly consistent**: reads always reflect the latest committed write (Raft quorum)
- **Watch-native**: clients get pushed notifications on key changes
- **Not for large data**: max recommended DB size is 8 GB; individual values capped at 1.5 MB

**Quorum**: For a 3-node etcd cluster, you need 2 nodes alive to accept writes. For 5 nodes, you need 3. Always run an odd number of etcd members.

| etcd cluster size | Fault tolerance |
|------------------|-----------------|
| 1 (dev only) | 0 failures |
| 3 | 1 failure |
| 5 | 2 failures |
| 7 | 3 failures (diminishing returns) |

**FAANG callout**: etcd is the most critical component. At Google, GKE runs dedicated etcd clusters with automated snapshotting every 5 minutes. Compaction and defrag must be run periodically — a full etcd causes API Server to stop accepting writes.

### kube-scheduler

**What it does**: Watches for pods with no `nodeName` set, scores all feasible nodes, and binds the pod to the highest-scoring node by writing `nodeName` to the pod spec.

**Scheduling cycle**:
1. **Filtering** — eliminate nodes that cannot run the pod (resource pressure, taints, affinity rules, port conflicts)
2. **Scoring** — rank remaining nodes on: `LeastAllocated`, `NodeAffinity`, `InterPodAffinity`, `ImageLocality`, topology spread
3. **Binding** — write the binding to the API Server

**Principal-level nuance**: The scheduler only makes the binding decision — it does not start the container. The kubelet on the target node picks up the binding via a watch and materialises it.

### kube-controller-manager

Runs ~30 reconciliation controllers in a single binary. Each is a separate goroutine watching the API Server.

**Most important controllers to know**:
- **Deployment controller**: creates/updates ReplicaSets for rolling deploys
- **ReplicaSet controller**: ensures the right number of pod replicas exist
- **Node lifecycle controller**: marks nodes `NotReady` after missed heartbeats; evicts pods
- **Endpoints controller**: updates Service endpoint slices as pods come/go
- **HPA controller**: scales Deployments based on metrics from metrics-server or custom adapters

---

## Data Plane (Worker Node)

```
┌─────────────────────────────── Worker Node ───────────────────────────────┐
│                                                                            │
│   ┌──────────────────────────────────────────────────────────────────┐    │
│   │  kubelet                                                         │    │
│   │  • Watches API Server for pods assigned to this node            │    │
│   │  • Calls CRI (containerd/CRI-O) to start/stop containers        │    │
│   │  • Runs readiness/liveness/startup probes                        │    │
│   │  • Reports node/pod status back to API Server                   │    │
│   │  • Manages volume mounts (calls CSI driver)                     │    │
│   └──────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│   ┌──────────────────────────────────────────────────────────────────┐    │
│   │  kube-proxy                                                      │    │
│   │  • Programs iptables (or IPVS) rules for Service virtual IPs    │    │
│   │  • Watches EndpointSlices; updates rules as pods change         │    │
│   │  Note: with eBPF CNIs (Cilium), kube-proxy can be replaced      │    │
│   └──────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│   ┌──────────────────────────────────────────────────────────────────┐    │
│   │  Container Runtime (containerd / CRI-O)                          │    │
│   │  • Implements CRI (Container Runtime Interface)                  │    │
│   │  • Pulls images from registry, manages namespaces/cgroups        │    │
│   └──────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│   ┌──────────────────────────────────────────────────────────────────┐    │
│   │  CNI Plugin (Calico / Cilium / Flannel / AWS VPC CNI)            │    │
│   │  • Assigns pod IP address                                        │    │
│   │  • Programs network routes for pod-to-pod communication          │    │
│   └──────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘
```

**Failure blast radius of kubelet crash**: Pods on that node continue running (containers are managed by containerd, not kubelet). But liveness probes stop, pod status goes stale, and new pods cannot be scheduled to or from that node until kubelet recovers or the node is replaced.

---

## Networking Model

### The Flat Network Contract

Kubernetes enforces a strict networking model:
1. Every pod gets a unique cluster-routable IP address
2. Any pod can reach any other pod **by IP** without NAT
3. Nodes can reach any pod IP
4. Pods see their own IP as the same IP that others use to reach them (no SNAT)

This is implemented by CNI plugins. Without NetworkPolicy, all pods can talk to all pods — it is a flat, trusted network by default.

### CNI Plugin Comparison

| CNI | Mechanism | NetworkPolicy | Performance | Key Differentiator |
|-----|-----------|---------------|-------------|-------------------|
| **Calico** | iptables or eBPF | ✅ Full | High | Mature, enterprise support, BGP routing option |
| **Cilium** | eBPF (bypasses iptables) | ✅ Full + L7 | Highest | eBPF native, Hubble observability, kube-proxy replacement |
| **Flannel** | VXLAN overlay | ❌ None | Medium | Simplest to operate, no policy support |
| **AWS VPC CNI** | Native VPC IPs per pod | ✅ (via Calico) | Highest (no overlay) | Pod IPs are real ENI IPs; Security Groups for pods |
| **WeaveNet** | VXLAN overlay | ✅ | Medium | Simple multi-host, encrypted overlay option |

**Principal-level recommendation**: Use **Cilium** for new clusters — eBPF removes the iptables bottleneck (iptables is O(n) rules), gives you L7 NetworkPolicy, and Hubble provides flow-level observability at near-zero cost. Use **AWS VPC CNI** on EKS when you need Security Groups per pod for compliance.

### DNS Resolution

CoreDNS runs as a Deployment in `kube-system`. Every pod's `/etc/resolv.conf` points to the CoreDNS ClusterIP.

DNS resolution pattern for a service:
```
<service>.<namespace>.svc.cluster.local
```

Short names resolve via search domains: `<service>` → `<service>.<current-namespace>.svc.cluster.local` → `<service>.svc.cluster.local` → `<service>.cluster.local`

**Production gotcha**: Each unresolvable short name causes up to 5 DNS queries (one per search domain). For high-QPS services, use fully qualified names or configure `ndots:2` to reduce DNS overhead.

---

## Storage Model

```
Developer writes:          StorageClass          PersistentVolume (PV)
  PVC (claim)    ──────►  (provisioner)  ──────►  (actual disk: EBS/GCE PD/NFS)
  "I need 50Gi                │
   ReadWriteOnce"             │ dynamically provisions
                              ▼
                         AWS: gp3 EBS volume
                         GCP: Persistent Disk
                         Azure: Managed Disk
                         On-prem: Ceph/NFS/Longhorn
```

### Access Modes

| Mode | Abbreviation | Meaning |
|------|-------------|---------|
| ReadWriteOnce | RWO | One node can mount read-write. Most block storage (EBS, GCE PD) |
| ReadOnlyMany | ROX | Many nodes can mount read-only |
| ReadWriteMany | RWX | Many nodes can mount read-write. Requires NFS/EFS/Ceph/Longhorn |
| ReadWriteOncePod | RWOP | Only one *pod* can mount (added in K8s 1.22) |

**Principal-level insight**: EBS (AWS) is RWO only — a StatefulSet using EBS PVCs cannot be moved to a different AZ without recreating the volume. This is why Kafka/Cassandra on K8s typically use topology constraints to pin replicas to specific AZs and use per-AZ StorageClasses.

### CSI (Container Storage Interface)

CSI replaced the old in-tree volume plugins. Every major storage provider now ships a CSI driver. Key operations:
- **CreateVolume / DeleteVolume** — lifecycle management
- **NodeStageVolume** — attach to node (e.g., attach EBS to EC2)
- **NodePublishVolume** — mount into pod's filesystem

---

## Object Hierarchy

```
Cluster
  └── Namespace (soft boundary: default, kube-system, production, staging)
        ├── Workloads: Pod, Deployment, StatefulSet, DaemonSet, Job, CronJob
        ├── Networking: Service, Ingress, NetworkPolicy
        ├── Config: ConfigMap, Secret
        ├── Storage: PersistentVolumeClaim
        └── Access: ServiceAccount, Role, RoleBinding

Cluster-scoped (no namespace):
  ├── Node, PersistentVolume, StorageClass, Namespace
  └── ClusterRole, ClusterRoleBinding, IngressClass
```

---

## Control Plane HA Setup

For production, always run:
- **3 control plane nodes** (API Server + Controller Manager + Scheduler each, only one CM/Scheduler active — leader election)
- **3-node etcd** cluster (can be co-located with control plane or dedicated)
- **Load balancer** in front of API Server endpoints

```
                    ┌────────────────┐
  kubectl ─────────►│   LB (NLB/ALB) │
                    └───────┬────────┘
               ┌────────────┼────────────┐
               ▼            ▼            ▼
          ┌────────┐  ┌────────┐  ┌────────┐
          │  CP-1  │  │  CP-2  │  │  CP-3  │
          │ apisvr │  │ apisvr │  │ apisvr │
          │  etcd  │◄─┤  etcd  │◄─┤  etcd  │  (Raft quorum)
          │ sched* │  │ sched  │  │ sched  │  (* = leader)
          └────────┘  └────────┘  └────────┘
```

---

## FAANG Interview Callouts

**Q: "How does Kubernetes handle a node failure?"**
> 1. Kubelet on the failed node stops sending heartbeats to API Server.
> 2. `kube-controller-manager`'s **Node Lifecycle Controller** marks the node `NotReady` after `node-monitor-grace-period` (default 40s).
> 3. After `pod-eviction-timeout` (default 5 minutes), it taints the node with `node.kubernetes.io/unreachable:NoExecute`.
> 4. Pods with `tolerationSeconds` exhausted are evicted (deleted from the node's pod list).
> 5. Deployments/ReplicaSets immediately schedule replacement pods on healthy nodes.
> Total pod recovery time: ~5–7 minutes with defaults. Tunable down to ~60s for latency-sensitive services.

**Q: "What is the API Server and why is it stateless?"**
> The API Server stores no state locally — all state lives in etcd. This means you can run N replicas behind a load balancer with no leader election. Any replica can handle any request. This is the key to horizontal scaling of the control plane.

**Q: "How does the Scheduler know a pod needs scheduling?"**
> It watches the API Server for pods with `spec.nodeName == ""`. The watch is a long-lived HTTP/2 connection; the API Server pushes events. There is no polling. This is the same pattern for all controllers — the entire control plane is event-driven.
