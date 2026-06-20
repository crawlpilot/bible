# Kubernetes — Complete Principal Engineer Reference

> **Type**: Container Orchestration Platform  
> **Core abstraction**: Desired-state reconciliation over containerised workloads  
> **Primary use cases**: Microservices at scale, batch processing, stateful distributed systems, internal PaaS

---

## Mental Model (Beginner Start Here)

Imagine you have 100 servers and 500 services to run on them. You don't want to manually decide which service runs on which server, restart services when they crash, or figure out how to split traffic during a deploy. Kubernetes (K8s) is the **operating system for your fleet of servers** — you declare *what* you want running and K8s figures out *where*, *when*, and *how* to run it, heal failures, and distribute load.

---

## 30-Second FAANG Interview Answer

> "Kubernetes is a declarative container orchestration system. You describe desired state in YAML; the control plane's reconciliation loops continuously drive actual state toward desired state. The API Server is the single source of truth stored in etcd. The Scheduler assigns pods to nodes; the kubelet on each node materialises that assignment. Everything is watch-based — no polling — which gives it sub-second reaction to failures at scale."

---

## When to Use Kubernetes

| Situation | Use K8s? | Reason |
|-----------|----------|--------|
| 10+ microservices with independent scaling needs | ✅ Yes | Service-level autoscaling, rolling deploys, isolation |
| Single monolith, one team | ❌ Overkill | ECS, Fly.io, or a single VM is far simpler |
| Stateful distributed systems (Kafka, Cassandra) | ✅ Yes (with care) | StatefulSet + PVC, but ops cost is real |
| Batch/ML training jobs | ✅ Yes | Job/CronJob, KEDA, GPU node pools |
| FaaS / event spikes (sub-100ms cold start matters) | ❌ Better alts | AWS Lambda, Cloud Run — not K8s native strength |
| Multi-cloud portability requirement | ✅ Yes | Uniform API across EKS / GKE / AKS |
| 2-engineer startup | ❌ Probably not | Cognitive overhead > benefit at small scale |

---

## Quick-Reference Card

| Term | One-Line Definition |
|------|---------------------|
| **Pod** | Smallest deployable unit; one or more containers sharing network + storage |
| **Node** | A VM or physical machine that runs pods |
| **Control Plane** | The "brain" — API Server, Scheduler, etcd, Controller Manager |
| **kubelet** | Agent on every node; materialises pod specs onto the container runtime |
| **Deployment** | Manages replica count + rolling updates for stateless workloads |
| **StatefulSet** | Ordered, stable-identity pods for stateful workloads (Kafka, DBs) |
| **Service** | Stable virtual IP + DNS name that load-balances to pod endpoints |
| **Ingress** | HTTP/S routing rules for external traffic into Services |
| **ConfigMap / Secret** | Externalised configuration and credentials injected into pods |
| **PersistentVolume (PV)** | A piece of durable storage provisioned from a StorageClass |
| **Namespace** | Soft multi-tenancy boundary inside a cluster |
| **Helm** | Package manager for K8s — bundles manifests into versioned charts |
| **RBAC** | Role-Based Access Control — who can do what on which resources |
| **HPA** | Horizontal Pod Autoscaler — scales replica count on metrics |
| **Karpenter** | Node autoscaler — provisions optimal EC2 instances for pending pods |

---

## Architecture Overview

```
┌─────────────────────────────── Kubernetes Cluster ─────────────────────────────────┐
│                                                                                     │
│  ┌──────────────────────── Control Plane ─────────────────────────┐                │
│  │                                                                 │                │
│  │  ┌─────────────┐  ┌──────────┐  ┌───────────────────────┐     │                │
│  │  │  API Server │  │  etcd    │  │  Controller Manager   │     │                │
│  │  │  (gateway)  │◄─┤  (state) │  │  (reconcile loops)    │     │                │
│  │  └──────┬──────┘  └──────────┘  └───────────────────────┘     │                │
│  │         │                       ┌───────────────────────┐     │                │
│  │         │                       │  Scheduler            │     │                │
│  │         │                       │  (pod → node binding) │     │                │
│  │         │                       └───────────────────────┘     │                │
│  └─────────┼───────────────────────────────────────────────────── ┘                │
│            │ watch / notify                                                         │
│  ┌─────────▼──────────────────────────────────────────────────────┐                │
│  │                        Worker Nodes                             │                │
│  │  ┌──────────────────────┐   ┌──────────────────────┐           │                │
│  │  │  Node 1              │   │  Node 2              │           │                │
│  │  │  kubelet  kube-proxy │   │  kubelet  kube-proxy │    ...    │                │
│  │  │  ┌─────┐ ┌─────┐    │   │  ┌─────┐ ┌─────┐    │           │                │
│  │  │  │Pod A│ │Pod B│    │   │  │Pod C│ │Pod D│    │           │                │
│  │  │  └─────┘ └─────┘    │   │  └─────┘ └─────┘    │           │                │
│  │  └──────────────────────┘   └──────────────────────┘           │                │
│  └────────────────────────────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## File Map

| File | What It Covers |
|------|----------------|
| [01-architecture.md](01-architecture.md) | Control plane internals, data plane, networking model (CNI), storage abstraction |
| [02-workloads-and-patterns.md](02-workloads-and-patterns.md) | Every workload type, Services, Ingress, ConfigMap/Secret, storage patterns |
| [03-helm-and-gitops.md](03-helm-and-gitops.md) | Helm chart structure + best practices, GitOps (ArgoCD/FluxCD), CI/CD integration |
| [04-production-guide.md](04-production-guide.md) | Resource management, autoscaling, RBAC, security hardening, upgrade strategy, production checklist |
| [05-debugging-and-operations.md](05-debugging-and-operations.md) | kubectl reference card, log viewing, debugging runbooks, essential tools |

---

## Kubernetes vs Alternatives

| Platform | Strength | Weakness | Choose When |
|----------|----------|----------|-------------|
| **Kubernetes** | Full control, extensible, multi-cloud | High ops complexity, steep learning curve | Large fleet, polyglot services, portability |
| **AWS ECS** | Tight AWS integration, simpler ops | AWS-only, less ecosystem | AWS-native shop, don't want K8s overhead |
| **HashiCorp Nomad** | Simpler, supports non-container workloads | Smaller ecosystem | Mixed VM + container fleets |
| **AWS Lambda / Cloud Run** | Zero infra management, instant scale | Cold starts, runtime limits, cost at steady load | Event-driven, spiky workloads |
| **Docker Compose** | Dead simple for local/small setups | Not production-grade | Dev environments only |

---

## Key Numbers (Production Reference)

| Metric | Value |
|--------|-------|
| Max nodes per cluster (upstream tested) | 5,000 nodes |
| Max pods per cluster | 150,000 pods |
| Max pods per node (default) | 110 pods |
| API Server response p99 (read) | < 1 second |
| etcd recommended max DB size | 8 GB |
| Typical pod startup time | 2–5 seconds (image cached), 10–30s (pull) |
| HPA react time (default) | 15–30 seconds |
| Karpenter node provision time (AWS) | ~45–90 seconds |

---

## Related Docs in This Repo

- [CloudArchitecture/aws/eks.md](../../CloudArchitecture/aws/eks.md) — EKS-specific: node groups, Fargate, IRSA, add-ons
- [Architecture/microservices/sidecar-pattern-envoy-otel-consul.md](../../Architecture/microservices/sidecar-pattern-envoy-otel-consul.md) — Sidecar + service mesh on K8s
- [CloudArchitecture/patterns/service-mesh.md](../../CloudArchitecture/patterns/service-mesh.md) — Istio / Linkerd architecture
