# Modern / Enterprise Patterns

These patterns emerged from domain-driven design (DDD), microservices, and distributed systems practice. They are not in the original GoF catalogue but are first-class design vocabulary for FAANG principal engineer discussions.

## When to Reach for a Modern Pattern

- You need to decouple domain logic from data storage (Repository)
- Read and write workloads have different scaling or model requirements (CQRS)
- A business operation spans multiple services with no shared transaction (Saga)
- You need full audit trail or time-travel query capability (Event Sourcing)
- You need reliable event publishing without dual-write risk (Outbox)
- A downstream dependency fails and you must prevent cascade (Circuit Breaker)
- Business rules need to be composable and unit-testable (Specification)
- Bounded contexts need to react to each other without direct coupling (Domain Events)
- Multiple repositories must commit atomically (Unit of Work)
- A slow dependency must not exhaust shared resources and kill unrelated features (Bulkhead)
- Transient failures need automatic recovery without thundering herd retries (Retry with Backoff)
- A legacy system's data model must not pollute a new domain model (Anti-Corruption Layer)
- A legacy monolith needs incremental replacement without a big-bang rewrite (Strangler Fig)
- Work items need parallel processing across multiple worker instances (Competing Consumers)
- Expensive objects (DB connections, threads) must be reused across requests (Object Pool)
- A single logical request must fan out to multiple services and aggregate results (Scatter-Gather)
- A message consumer must handle broker redelivery without duplicate side effects (Idempotent Consumer)
- Unprocessable messages must be quarantined without blocking the main queue (Dead Letter Queue)

## Patterns in This Category

| Pattern | Intent | Complexity | Interview Frequency |
|---------|--------|-----------|---------------------|
| [Repository](24-repository.md) | Decouple domain from data access | Low | Common |
| [CQRS](25-cqrs.md) | Separate command and query responsibilities | High | Common |
| [Saga](26-saga.md) | Distributed transaction via events or orchestration | High | Common |
| [Event Sourcing](27-event-sourcing.md) | Store events, derive state | High | Common |
| [Outbox Pattern](28-outbox-pattern.md) | Reliable transactional event publishing | Medium | Common |
| [Circuit Breaker](29-circuit-breaker.md) | Detect failures and stop cascading | Medium | Common |
| [Specification](30-specification.md) | Composable business rule predicates | Medium | Occasional |
| [Domain Events](31-domain-events.md) | Bounded context integration via events | Medium | Common |
| [Unit of Work](32-unit-of-work.md) | Track and commit changes across repositories atomically | Medium | Occasional |
| [Bulkhead](33-bulkhead.md) | Isolate resource pools per dependency to prevent cascade | Medium | Common |
| [Retry with Backoff](34-retry-backoff.md) | Recover from transient failures with exponential backoff + jitter | Low | Common |
| [Anti-Corruption Layer](35-anti-corruption-layer.md) | Translate between bounded contexts to prevent model pollution | Medium | Common |
| [Strangler Fig](36-strangler-fig.md) | Incrementally replace a legacy system via routing façade | High | Common |
| [Competing Consumers](37-competing-consumers.md) | Distribute work across multiple queue consumers for parallel throughput | Medium | Common |
| [Object Pool](38-object-pool.md) | Pre-allocate and reuse expensive objects (DB connections, threads) | Medium | Common |
| [Scatter-Gather](39-scatter-gather.md) | Fan out to multiple services in parallel; aggregate responses into one result | Medium | Common |
| [Idempotent Consumer](40-idempotent-consumer.md) | Process at-least-once messages safely with a deduplication store | Medium | Common |
| [Dead Letter Queue](41-dead-letter-queue.md) | Quarantine unprocessable messages; prevent poison pills from blocking the queue | Low | Common |

## Key Distinction: Saga vs Event Sourcing vs Outbox

- **Saga**: manages a *multi-step distributed transaction* (coordination)
- **Event Sourcing**: stores *all state changes as events* (persistence model)
- **Outbox**: ensures a single service publishes events *reliably* (consistency guarantee)

These three are often used together: Saga drives the workflow; Event Sourcing stores the state; Outbox ensures events are published transactionally.

## Key Distinction: Circuit Breaker vs Bulkhead vs Retry

- **Circuit Breaker**: detects *sustained failure* and stops calling a broken service (fail fast)
- **Bulkhead**: *isolates resource pools* so a slow dependency can't starve other features
- **Retry with Backoff**: recovers from *transient failures* without overwhelming the retried service

These three form the resilience triad — in production systems, all three are applied together: Bulkhead limits concurrent load, Circuit Breaker detects when the service is down, Retry handles transient blips.

## Key Distinction: Object Pool vs Scatter-Gather vs Idempotent Consumer vs DLQ

- **Object Pool**: manages *reusable resources* (connections, threads) — resource lifecycle pattern
- **Scatter-Gather**: manages *parallel fan-out* to multiple services — request orchestration pattern
- **Idempotent Consumer**: makes *message consumers safe* under at-least-once delivery — reliability pattern
- **Dead Letter Queue**: *quarantines messages* that cannot be processed — fault isolation pattern

## Key Distinction: Anti-Corruption Layer vs Strangler Fig

- **Anti-Corruption Layer**: a *translation boundary* that prevents legacy concepts from entering your domain model
- **Strangler Fig**: a *migration strategy* that incrementally replaces a legacy system using routing

ACL and Strangler Fig are typically used together: the Strangler façade routes traffic; the ACL translates data between the old and new systems during the migration window.
