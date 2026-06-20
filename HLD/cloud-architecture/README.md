# Cloud Architecture Patterns

Cloud-native design patterns used in FAANG principal engineer interviews. Each file covers a pattern at production depth: trade-offs, failure modes, and real-world adoption.

## Contents

| File | Pattern | Key Interview Signal |
|------|---------|---------------------|
| [multi-region-active-active.md](multi-region-active-active.md) | Multi-region active-active | Conflict resolution, RPO/RTO, data gravity |
| [event-driven-architecture.md](event-driven-architecture.md) | Event-driven / async messaging | Choreography vs orchestration, exactly-once |
| [serverless-architecture.md](serverless-architecture.md) | Serverless & FaaS | Cold start, stateless constraints, cost model |
| [cell-based-architecture.md](cell-based-architecture.md) | Cell-based / bulkhead | Blast radius isolation, noisy neighbor |
| [zero-downtime-deployments.md](zero-downtime-deployments.md) | Deployment strategies | Blue-green, canary, feature flags, schema migrations |

## When Cloud Architecture Comes Up in Interviews

**Availability questions**: "How do you achieve 99.99% uptime?" → multi-region active-active + cell-based isolation

**Scale questions**: "How do you handle traffic spikes?" → serverless autoscaling or cell-based horizontal partitioning

**Coupling questions**: "How do you decouple 30 microservices?" → event-driven architecture

**Reliability questions**: "How do you deploy to 100M users without downtime?" → canary + feature flags

**Cost questions**: "How do you optimize infra spend?" → serverless for spiky workloads, reserved capacity for steady-state

## FAANG Adoption Map

| Company | Primary Pattern | Source |
|---------|----------------|--------|
| Amazon AWS | Cell-based (AZ isolation) | AWS re:Invent talks, S3/DynamoDB architecture |
| Netflix | Multi-region active-active | Chaos Engineering blog, Hystrix/Zuul design |
| Stripe | Cell-based (Stripe Radar isolation) | Stripe engineering blog |
| Uber | Event-driven (Apache Kafka at core) | Uber Eng blog: Cherami, Kafka at scale |
| Meta | Multi-region active-active (TAO) | USENIX OSDI '13 paper |
| Google | Global Spanner + event-driven Pub/Sub | Spanner paper, Cloud Next talks |
