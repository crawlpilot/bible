# Cloud Architecture Patterns

Design philosophies, deployment strategies, and cross-cutting architectural patterns for cloud-native systems at FAANG scale.

---

## Pattern Index

| Pattern | File | When to reach for it |
|---|---|---|
| **Hub-and-Spoke** | [hub-and-spoke.md](hub-and-spoke.md) | Multi-VPC networking; AWS Organizations account structure; centralised egress/inspection |
| **Serverless** | [serverless.md](serverless.md) | Unpredictable or spiky workloads; event-driven processing; operational overhead reduction |
| **Event-Driven Architecture** | [event-driven-architecture.md](event-driven-architecture.md) | Decoupled microservices; asynchronous workflows; audit trail; fan-out at scale |
| **Cell-Based Architecture** | [cell-based-architecture.md](cell-based-architecture.md) | Blast-radius containment; fault isolation; progressive deployments at FAANG scale |
| **Multi-Tenant SaaS** | [multi-tenant-saas.md](multi-tenant-saas.md) | Building B2B SaaS products; tenant isolation; noisy-neighbour prevention |
| **Strangler Fig** | [strangler-fig.md](strangler-fig.md) | Incrementally migrating a monolith to microservices without big-bang rewrites |
| **Data Mesh** | [data-mesh.md](data-mesh.md) | Decentralised data ownership at scale; eliminating central data team bottleneck |
| **Zero Trust Security** | [zero-trust-security.md](zero-trust-security.md) | Cloud security without a perimeter; identity-based access; mTLS everywhere |
| **GitOps & IaC** | [gitops-iac.md](gitops-iac.md) | Infrastructure automation; audit trail; drift prevention; PR-based change control |
| **Resilience Patterns** | [resilience-patterns.md](resilience-patterns.md) | Tolerating failure: retry, circuit breaker, bulkhead, timeout, fallback, multi-AZ |
| **Service Mesh** | [service-mesh.md](service-mesh.md) | Service-to-service mTLS; traffic management; observability without code changes |

---

## Quick Decision Guide

### "How do I structure my AWS accounts?"
→ [Hub-and-Spoke](hub-and-spoke.md) — AWS Organizations + Control Tower + Transit Gateway for network topology

### "How do I migrate off my monolith?"
→ [Strangler Fig](strangler-fig.md) — incremental extraction, ALB routing, Anti-Corruption Layer

### "How do I build for scale and fault isolation?"
→ [Cell-Based Architecture](cell-based-architecture.md) — one cell per shard of users/tenants; blast radius ≤ one cell

### "How do I run a SaaS product for multiple enterprise customers?"
→ [Multi-Tenant SaaS](multi-tenant-saas.md) — Silo/Pool/Bridge models; tenant isolation; GDPR crypto-shredding

### "How do I decouple my services and handle async workflows?"
→ [Event-Driven Architecture](event-driven-architecture.md) — choreography vs orchestration; EventBridge vs Kafka; schema evolution

### "How do I secure my services with zero implicit trust?"
→ [Zero Trust Security](zero-trust-security.md) — IRSA + mTLS + micro-segmentation + GuardDuty auto-response

### "How do I make my system survive failures?"
→ [Resilience Patterns](resilience-patterns.md) — circuit breaker, bulkhead, retry with jitter, multi-AZ, chaos engineering

### "How do I manage infrastructure changes safely?"
→ [GitOps & IaC](gitops-iac.md) — Terraform + ArgoCD + PR-based workflow + drift detection

### "How do I handle service-to-service communication concerns uniformly?"
→ [Service Mesh](service-mesh.md) — Istio/Linkerd for mTLS, retries, circuit breaking, distributed tracing

### "How do I build a data platform for 50 teams?"
→ [Data Mesh](data-mesh.md) — domain-owned data products; Lake Formation; self-serve platform; federated governance

---

## Patterns by Concern

### Networking & Infrastructure
- [Hub-and-Spoke](hub-and-spoke.md) — VPC topology and account structure
- [Zero Trust Security](zero-trust-security.md) — identity-based micro-segmentation
- [Service Mesh](service-mesh.md) — east-west traffic control

### Application Architecture
- [Serverless](serverless.md) — function-based compute model
- [Event-Driven Architecture](event-driven-architecture.md) — async messaging and event choreography
- [Resilience Patterns](resilience-patterns.md) — failure tolerance primitives

### Organisational & Scale Patterns
- [Cell-Based Architecture](cell-based-architecture.md) — fault domain isolation
- [Multi-Tenant SaaS](multi-tenant-saas.md) — tenant isolation models
- [Strangler Fig](strangler-fig.md) — monolith migration strategy

### Data & Analytics
- [Data Mesh](data-mesh.md) — decentralised data ownership

### Engineering Operations
- [GitOps & IaC](gitops-iac.md) — infrastructure automation and audit

---

## Cross-Cutting Concerns Matrix

| Concern | Primary pattern | Supporting patterns |
|---|---|---|
| **Fault isolation** | Cell-Based Architecture | Resilience Patterns, Serverless |
| **Security posture** | Zero Trust Security | Service Mesh (mTLS), Hub-and-Spoke (network segmentation) |
| **Decoupling** | Event-Driven Architecture | Strangler Fig, Serverless |
| **Observability** | Service Mesh | Resilience Patterns (health checks), GitOps (drift detection) |
| **Multi-tenancy** | Multi-Tenant SaaS | Cell-Based Architecture, Zero Trust |
| **Migration** | Strangler Fig | Event-Driven Architecture (EDA as decoupling mechanism) |
| **Cost optimisation** | Serverless | Cell-Based Architecture (right-sized cells) |
| **Compliance / audit** | Zero Trust Security | GitOps & IaC, Data Mesh (data governance) |

---

## Related Sections

- [CloudArchitecture/aws/](../aws/README.md) — AWS service deep-dives (the building blocks these patterns use)
- [Architecture/distributed-systems/](../../Architecture/distributed-systems/) — Consistency models, consensus, replication
- [LLD/design-patterns/modern/](../../LLD/design-patterns/modern/) — CQRS, Saga, Outbox, Domain Events
- [Books/summaries/enterprise-integration-patterns-hohpe-woolf.md](../../Books/summaries/enterprise-integration-patterns-hohpe-woolf.md) — Messaging pattern catalog
