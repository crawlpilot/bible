# Event-Driven Architecture (EDA) Pattern

## Overview
Event-Driven Architecture is a design philosophy where components communicate by producing and consuming events — immutable records of things that happened — rather than through direct synchronous calls. Services are decoupled in time (producer doesn't wait for consumers), in space (producer doesn't know who the consumers are), and in failure domain (consumer failure doesn't affect producer).

**The fundamental shift**: instead of asking "what should I call?" you ask "what happened, and who cares?"

---

## Core Concepts

| Concept | Definition |
|---|---|
| **Event** | An immutable fact that something happened: `OrderPlaced`, `PaymentProcessed`, `UserSignedUp` |
| **Event producer** | The service that emits the event. Has no knowledge of consumers. |
| **Event consumer** | A service that reacts to events it has subscribed to |
| **Event channel** | The infrastructure through which events flow: Kafka topic, SNS topic, EventBridge bus |
| **Event schema** | The structure of the event payload. A contract between producers and consumers. |
| **Event store** | Persistent log of all events (Kafka, EventStoreDB) — enables replay |
| **Event stream** | An ordered, replayable sequence of events (Kafka topic, Kinesis stream) |
| **Event notification** | A lightweight event carrying only the fact, no payload (SNS) |
| **Event-carried state transfer** | Events carry full entity state — consumers don't need to call back |

---

## EDA Styles

### 1. Event Notification
Producer fires a small notification: "user 123 was updated". Consumers call back to get the current state.
- Simple; consumers always see latest state
- Consumer is tightly coupled to producer's read API (synchronous callback dependency)
- Good for: simple notifications where consumer needs current state anyway (cache invalidation)

### 2. Event-Carried State Transfer
Producer includes the full entity state in the event: `{user_id, name, email, status, updated_at}`. Consumers update their own local copy.
- Fully decoupled — no callback to producer
- Consumer state is eventually consistent with producer
- Good for: microservices maintaining their own read-optimised copy of foreign data

### 3. Event Sourcing
The event log IS the source of truth. Current state is computed by replaying all events.
- Complete audit trail; temporal queries; replayability
- Higher complexity; snapshot management; large event volumes
- Good for: financial ledgers, audit-required systems, systems needing time-travel queries

---

## Choreography vs Orchestration

The central architectural decision in EDA.

### Choreography
Each service reacts independently to events. No central coordinator.

```
OrderService publishes OrderPlaced
  ↓
InventoryService receives OrderPlaced → reserves stock → publishes StockReserved
  ↓
PaymentService receives StockReserved → charges card → publishes PaymentCharged
  ↓
ShippingService receives PaymentCharged → creates shipment → publishes ShipmentCreated
```

**Pros**: highly decoupled; each service independently deployable; no single point of failure
**Cons**: workflow state distributed across services; debugging requires reconstructing from event log; adding a new step requires finding the right event to subscribe to; hard to see the "big picture"

### Orchestration
A central orchestrator drives each step and knows the full workflow.

```
OrderOrchestrator (Step Functions):
  1. Call InventoryService.reserve()
  2. On success → Call PaymentService.charge()
  3. On success → Call ShippingService.create()
  4. On any failure → Call CompensationService.rollback()
```

**Pros**: visible workflow state; easy to add steps; explicit failure handling; audit trail built-in
**Cons**: orchestrator is a coupling point; single point of failure if orchestrator is unavailable

**Decision rule**:
| Use choreography when | Use orchestration when |
|---|---|
| Loose coupling is paramount | Workflow visibility is required (compliance, audit) |
| Steps are simple and stable | Complex branching and compensation logic |
| Teams own their reaction independently | Long-running workflows (minutes to days) |
| High throughput, low latency | Human approval steps required |

---

## Event Schema Design

Schema design is the most consequential decision in EDA — it's a public API contract.

### Envelope Pattern (CloudEvents)
```json
{
  "specversion": "1.0",
  "type": "com.mycompany.order.placed",
  "source": "/orders-service",
  "id": "uuid-v4-here",
  "time": "2024-01-15T10:00:00Z",
  "datacontenttype": "application/json",
  "data": {
    "order_id": "ord-123",
    "user_id": "usr-456",
    "total_amount": 99.99,
    "currency": "USD",
    "items": [...]
  }
}
```

**Schema evolution rules** (in order of safety):
1. **Add optional fields**: always backward compatible
2. **Mark fields deprecated** (don't remove yet): add `_deprecated` suffix + documentation
3. **Remove fields**: breaking change — requires version bump or dual-publish period
4. **Change field type**: always breaking
5. **Rename fields**: always breaking

### Dual Publishing During Migration
When you must make a breaking schema change:
```
Phase 1: Publish to both v1 topic and v2 topic (producer dual-publish)
Phase 2: Migrate all consumers to v2 topic
Phase 3: Stop publishing to v1 topic
```

---

## EDA Cloud Implementations

### AWS: EventBridge (Event Bus)
Best for: AWS-native event routing with complex rules, schema registry, and replay.

```
Services → PutEvents → EventBridge custom bus
                         ↓ Rule: {source: "orders-service", detail-type: "OrderPlaced"}
                         → SQS queue (inventory service)
                         → Lambda (fraud check)
                         → Kinesis Firehose (analytics)
                         → EventBridge bus in account B (cross-account)
```

Features: schema discovery, archive and replay, content-based routing with JSONPath rules.

### AWS: SNS + SQS (Classic Fan-Out)
Best for: high-throughput fan-out, durable delivery.

```
Producer → SNS Topic → SQS Queue A (consumer A, with DLQ)
                     → SQS Queue B (consumer B, with DLQ)
                     → Lambda C (real-time processing)
```

### AWS: Kinesis / MSK (Event Streaming)
Best for: high-throughput, replayable, ordered event streams.

```
Producers (many) → Kafka Topic (partitioned by entity_id)
                   → Consumer Group A (downstream service)
                   → Consumer Group B (analytics)
                   → Consumer Group C (audit log → S3)
```

**Replay** is the key differentiator: Kafka retains events for days/weeks/forever. SNS/SQS don't replay once consumed.

---

## Eventual Consistency Management

EDA introduces eventual consistency — after a producer publishes an event, consumers may not process it for milliseconds to seconds. This is usually fine but requires careful design.

### Patterns for consistency management

**Optimistic UI**: update the UI immediately (assume success), reconcile if event consumption later fails.
```
User clicks "Place Order" → UI shows "Order Placed" → event published
→ If consumer fails → UI reconciles with final state from polling
```

**Polling for status**: for user-facing workflows, return a job ID and poll for completion.
```
POST /orders → 202 Accepted + {job_id: "xyz"}
GET /orders/status/xyz → {status: "processing"} or {status: "complete", order_id: "123"}
```

**Saga compensation**: if an event consumer fails after partial processing, emit a compensating event.
```
PaymentFailed event → InventoryService receives → releases reservation → publishes StockReleased
```

**Read-your-writes**: if a user creates a resource and immediately reads it, the read model may not have the event yet. Solution: read from the command-side store (source of truth) for the user's own writes; read from the event-driven read model for others' data.

---

## Event Sourcing Deep-Dive

Event Sourcing stores every state change as an immutable event. Current state = replay of all events.

### Benefits
- Complete audit trail — every state transition is recorded
- Time-travel queries: "what was the order status at 2:30pm on Jan 15?"
- Replayability: rebuild any read model from scratch by replaying events
- Event-driven integration: the event store is the integration backbone

### Challenges
| Challenge | Mitigation |
|---|---|
| Event volume growth | Snapshots at checkpoints (store snapshot + events since snapshot) |
| Schema evolution | Upcasters (transform old events to current schema at read time) |
| Read performance | CQRS: build optimised read models from event stream |
| Query complexity | Pre-compute read models for common queries; keep event store for writes only |
| Eventual consistency | Read models lag behind command model; design UI accordingly |

### Event Store on AWS
```
Write path: API → Lambda → append event to DynamoDB (partition key: aggregate_id, sort key: sequence_number)
                          → publish event to Kinesis/EventBridge for downstream consumers

Read path: Lambda reads all events for aggregate_id from DynamoDB, replays to current state
         → or read from pre-built read model in ElastiCache/DynamoDB/OpenSearch
```

---

## CQRS (Command Query Responsibility Segregation)

CQRS separates the model for writing (commands) from the model for reading (queries). Often used with Event Sourcing.

```
Command side: API → Command handler → validates → persists to write model (normalised DB or event store)
                                                 → publishes event

Query side: Event consumer → updates read model (denormalised, query-optimised)
            API → Query handler → reads from read model (DynamoDB, OpenSearch, Redis)
```

**Benefits**: write model optimised for consistency and validation; read model optimised for query performance. Scale read and write independently.

**Cost**: two models to maintain; eventual consistency between them.

**When CQRS is overkill**: most CRUD applications don't need CQRS. Use when: read/write ratio is very asymmetric; complex domain logic on writes; different teams own read vs write paths.

---

## EDA Observability

Distributed event flows are harder to observe than synchronous calls. Required tooling:

| Challenge | Solution |
|---|---|
| "What happened to my order?" | Correlation ID propagated through all events; search CloudWatch Logs |
| "Where is the event now?" | Distributed tracing (X-Ray); trace spans from producer through consumers |
| "Is a consumer falling behind?" | Kinesis iterator age; SQS `ApproximateAgeOfOldestMessage` |
| "Why did this event fail?" | DLQ + structured error logging with original event + exception |
| "What was the system state at time T?" | Event store + replay; or event archive (EventBridge, Kafka) |

**Correlation ID pattern**: the first service in a flow generates a UUID. Every downstream service extracts it from the event header and propagates it in its own events and logs. All events in one flow share the same correlation ID — searchable across services.

---

## Trade-offs Summary

| Dimension | Event-Driven | Request-Response (REST/gRPC) |
|---|---|---|
| **Coupling** | Low — producer/consumer independent | High — direct dependency |
| **Latency** | Higher (async processing) | Low (synchronous) |
| **Consistency** | Eventual | Strong (within transaction) |
| **Scalability** | Excellent — consumers scale independently | Bounded by synchronous chain |
| **Failure isolation** | High — consumer failure doesn't affect producer | Low — failure propagates to caller |
| **Complexity** | High — distributed state, debugging harder | Low — familiar request/response |
| **Auditability** | Excellent (event log) | Requires explicit audit logging |
| **Use when** | Loose coupling required; async acceptable; fan-out; audit | User-facing, requires immediate response |

---

## Best Practices

1. **Design events as immutable facts** — `OrderPlaced`, not `CreateOrder`. Past tense; data-centric.
2. **Separate event notification from event-carried state transfer** — choose the right style per use case
3. **Version events explicitly** — in topic name (`orders-v2`) or schema registry; never silently change schema
4. **Propagate correlation IDs** across all event headers — non-negotiable for debuggability
5. **Dead-letter queues for every consumer** — failures must be captured and alertable
6. **Use Schema Registry** (Confluent, AWS Glue, EventBridge) — enforce compatibility at publish time
7. **Idempotent consumers** — at-least-once delivery is the norm; design consumers to be safe when called twice
8. **Event replay capability** — use Kafka or EventBridge Archive; being able to replay is priceless during incidents
9. **Don't put commands in pub-sub topics** — commands have exactly one receiver; use point-to-point (SQS)
10. **Bounded context alignment** — event topics should align with domain bounded contexts, not service boundaries

---

## FAANG Interview Points

**"Design an order management system"**: OrderService publishes `OrderPlaced` to Kafka. InventoryService consumes → reserves → publishes `StockReserved`. PaymentService consumes → charges → publishes `PaymentProcessed`. All events stored in Kafka (replay). Step Functions orchestrates compensation if any step fails. Correlation ID in every event. X-Ray tracing across all services.

**"How do you handle schema evolution in Kafka?"**: Confluent Schema Registry with BACKWARD compatibility. New consumers can read old events; old consumers can read new events. Additive-only schema changes without bumping version. Breaking changes require dual-publish period with v1 and v2 topics in parallel, consumer migration, then deprecate v1.

**"Choreography vs orchestration for a payment refund?"**: Orchestration. Refunds are complex (partial refund, dispute-triggered, admin-triggered, automatic), long-running (bank processing takes hours), require explicit audit trail (compliance), and need human approval for large amounts. Step Functions with `.waitForTaskToken` for bank ACK and human approval gates.
