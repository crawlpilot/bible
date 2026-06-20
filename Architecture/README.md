# Architecture Decisions & Patterns

Formal architectural artifacts: ADRs, RFCs, distributed systems patterns. These represent the depth expected of a principal engineer.

## Sub-directories

| Folder | Contents |
|--------|----------|
| `decisions/` | Architecture Decision Records (ADRs) |
| `rfcs/` | RFC templates and worked examples |
| `diagrams/` | Architecture diagrams in Mermaid or PlantUML |
| `microservices/` | Service mesh, API gateway, service discovery, saga patterns |
| `distributed-systems/` | Consistency models, consensus (Raft/Paxos), replication, partitioning |
| `ddd/` | Domain-Driven Design — philosophy, strategic design, tactical patterns, hexagonal architecture, Event Storming, trade-offs |

## ADR Template

```markdown
# ADR-[NNN]: [Title]

**Status**: Proposed | Accepted | Superseded by ADR-XXX

## Context
What problem are we solving? What forces are at play?

## Decision
What did we decide?

## Consequences
What becomes easier? What becomes harder? What are the risks?

## Alternatives Considered
What else was evaluated and why was it rejected?
```

Use `/adr [decision]` with Claude to generate a complete ADR.

## ADR Index

| ADR | Title | Status |
|---|---|---|
| [ADR-001](decisions/adr-observability-stack-selection.md) | Observability Stack: OpenTelemetry + Grafana + Honeycomb | Accepted |
| [ADR-002](decisions/adr-kafka-parallel-consumer-lmax-rocksdb.md) | Kafka Parallel Consumer with LMAX Disruptor + RocksDB | Accepted |
| [ADR-003](decisions/adr-vm-vs-ec2-asg-vs-eks-deployment-platform.md) | Deployment Platform: VM vs EC2 ASG vs EKS | Accepted |
| [ADR-004](decisions/adr-cicd-dora-deployment-planning.md) | CI/CD Deployment Planning Aligned to DORA Metric SLAs | Accepted |
| [ADR-005](decisions/adr-vela-internal-registry-secrets-manager-migration.md) | Vela Build Pipeline + Internal Registry + AWS Secrets Manager Migration | Accepted |
