# AWS EventBridge — Deep Dive

## Overview

EventBridge is a serverless event bus that connects AWS services, SaaS applications, and your own microservices using events. It's the evolution of CloudWatch Events, extended with custom event buses, schema registry, event replay, cross-account routing, and Pipes.

**Mental model:** EventBridge is a smart router — producers publish events to a bus, rules match events to targets. No polling, no persistent queue. Targets receive events pushed to them.

---

## Core Components

```
Event Producers
  AWS Services (S3, EC2, GuardDuty, CodePipeline, etc.)
  SaaS Partners (Datadog, Zendesk, Shopify, etc.)
  Custom apps (PutEvents API)
        ↓
[Event Bus]  ←── Rules ──→ Targets (Lambda, SQS, SNS, Step Functions, API GW, Kinesis, etc.)
```

| Component | Role |
|-----------|------|
| **Event Bus** | Channel that receives events. Default (AWS service events), custom, or partner |
| **Rule** | Matches events by pattern, sends matching events to ≤5 targets |
| **Target** | Where matched events are sent (Lambda, SQS, etc.) |
| **Event** | JSON payload with source, detail-type, and detail fields |
| **Schema Registry** | Discovers and stores event schemas; generates typed client code |
| **Archive & Replay** | Store events, replay historical events to a bus |
| **EventBridge Pipes** | Point-to-point integration: source → filter → enrich → target |
| **EventBridge Scheduler** | Cron and rate-based scheduling with DLQ support |
| **Global Endpoints** | Active-active cross-region event bus for DR |

---

## Event Structure

```json
{
  "version": "0",
  "id": "uuid",
  "source": "com.mycompany.orders",
  "account": "123456789012",
  "time": "2026-06-12T10:30:00Z",
  "region": "us-east-1",
  "detail-type": "OrderPlaced",
  "detail": {
    "orderId": "ORD-123",
    "userId": "USER-456",
    "amount": 99.99,
    "currency": "USD"
  }
}
```

- `source`: identifies the producer (use reverse-DNS convention for custom events)
- `detail-type`: human-readable event type — used heavily in rules
- `detail`: arbitrary JSON — the event payload
- Max event size: **256 KB**

---

## Event Rules & Pattern Matching

Rules use **content-based filtering** — match on any field in the event:

```json
{
  "source": ["com.mycompany.orders"],
  "detail-type": ["OrderPlaced"],
  "detail": {
    "amount": [{"numeric": [">", 1000]}],
    "currency": ["USD", "EUR"]
  }
}
```

Supported matching operators:
| Operator | Example |
|----------|---------|
| Exact match | `"status": ["FAILED"]` |
| Prefix | `"source": [{"prefix": "com.mycompany"}]` |
| Numeric comparison | `"amount": [{"numeric": [">=", 100, "<", 1000]}]` |
| Exists / not exists | `"promoCode": [{"exists": false}]` |
| Anything-but | `"env": [{"anything-but": ["dev", "test"]}]` |
| IP address (CIDR) | `"ip": [{"cidr": "10.0.0.0/8"}]` |
| Wildcards (2023+) | `"path": [{"wildcard": "/api/*/orders"}]` |

Rules are evaluated in parallel — multiple rules can match the same event. Cost: $1/million matched rules evaluated.

---

## EventBridge Pipes

**Point-to-point integration** with optional filtering and enrichment:

```
Source              Filter          Enrich              Target
(SQS / Kinesis /    (optional:      (optional:          (Lambda / SQS /
 DynamoDB Streams /  event pattern   Lambda / API GW /   SNS / Step Fn /
 Kafka / MSK)        matching)       EventBridge API     API GW / etc.)
                                     Destination)
```

**vs Rules:** Pipes are 1:1 (one source, one target). Rules are 1:N (one bus, N targets via N rules). Pipes support sources that require polling (SQS, Kinesis, DynamoDB Streams); Rules don't.

**Key use case:** Replace Lambda-as-glue. If you have a Lambda that reads from SQS, filters, transforms, and writes to another service — a Pipe can do this with zero code.

```
SQS → Pipe → [filter: status=PAID] → [enrich: Lambda adds user data] → Step Functions
```

---

## EventBridge Scheduler

Replaces CloudWatch Events scheduled rules + provides:
- **Cron** and **rate** expressions
- **One-time** schedule (run at a specific datetime)
- **Flexible time window** (start at 2pm ± 15 min to spread load)
- **DLQ support** — if target invocation fails, route to SQS DLQ
- **Retry policy** — up to 185 retries over 24h
- Target: anything Scheduler supports (Lambda, SQS, Step Functions, ECS tasks, Kinesis, SageMaker, etc.)

**vs CloudWatch Events rate/cron rules:** Scheduler is the replacement — supports one-time schedules, flexible windows, DLQ, and scales to millions of schedules. CloudWatch Events cron rules are limited and should not be used for new work.

---

## Schema Registry

EventBridge discovers event schemas automatically (from events on the bus) or you can register manually:

```
Schema: com.mycompany.orders@OrderPlaced
  {
    "type": "object",
    "properties": {
      "orderId": {"type": "string"},
      "amount": {"type": "number"},
      ...
    }
  }
```

- Generate **typed binding code** (Java, Python, TypeScript) — the generated code serializes/deserializes events to/from your schema
- Schema versioning — track evolution of your event contracts
- OpenAPI 3.0 compatible

---

## Archive & Replay

```
Archive: Bus → all events (or filtered) → archive storage (indefinite or TTL)
Replay:  Select archive + time range → re-deliver events to bus → rules process them
```

**Use cases:**
- Replay events after fixing a bug in a consumer (consumer was down or had a bug; re-process past events)
- Audit: retain all events for compliance
- Testing: replay production events against new consumers
- DR: archive in one region, replay to another region's bus on disaster

Cost: $0.023/GB stored per month + $0.10/million replayed events.

---

## Cross-Account & Cross-Region Event Routing

```
Account A (producer)                Account B (consumer)
Custom Bus ──── resource policy ──→ Custom Bus in Account B
                                         ↓ rules
                                       Lambda
```

- Each bus has a **resource-based policy** — grant other accounts (or org) permission to `PutEvents`
- Cross-region: use a rule with a bus in another region as the target
- **Global Endpoints** (2023): two buses in two regions, Route 53 routes producers to the healthy region automatically — used for active-active event publishing with automatic failover

---

## EventBridge vs SNS vs SQS vs Kinesis

| Dimension | EventBridge | SNS | SQS | Kinesis |
|-----------|-------------|-----|-----|---------|
| Delivery | Push | Push | Pull | Pull |
| Message retention | 24h (Archive: indefinite) | None | 14 days | 1–365 days |
| Ordering | No | No (FIFO: limited) | No (FIFO: limited) | Per-shard |
| Throughput | Soft: 10k events/s default | High | High | High (sharded) |
| Filtering | Content-based (rich) | Attribute-based | Message filtering | None (client-side) |
| Fan-out | Yes (N targets per rule) | Yes (N subscriptions) | No (one consumer) | No (one group per shard) |
| Replay | Yes (Archive) | No | No | Yes (retention window) |
| Schema registry | Yes | No | No | No |
| Sources | AWS services, SaaS, custom | Custom, AWS services | Custom | Custom |
| Dead-letter | Per-rule | Per-subscription | Built-in | Per-shard |
| Cost | $1/million matched | $0.50/million | $0.40/million | $0.015/shard/hour |

**Decision guide:**
- **EventBridge:** event-driven integration between services, AWS service events, SaaS events, schema-driven development, content-based routing to multiple targets
- **SNS:** simple fan-out to N consumers with attribute filtering; mobile push notifications
- **SQS:** decoupling, buffering, at-least-once delivery to a single consumer group; load leveling
- **Kinesis:** ordered event stream, replay within retention window, multiple consumers each reading all events (analytics + application consumers simultaneously)

---

## EventBridge Targets

A single rule can route to up to 5 targets simultaneously:

| Target | Notes |
|--------|-------|
| Lambda | Synchronous invocation; max 6 MB payload |
| SQS (Standard/FIFO) | Good for buffering; FIFO uses MessageGroupId from event |
| SNS | Fan-out from EventBridge |
| Step Functions | Start execution with event as input |
| API Gateway / API Destination | HTTP POST to external APIs (SaaS webhooks, etc.) |
| Kinesis Data Streams | Partition key configurable from event fields |
| ECS Task | Launch a Fargate task with event as input |
| EventBridge bus | Cross-account or cross-region forwarding |
| CodePipeline | Trigger a pipeline |

**API Destinations** (HTTP targets): Connect EventBridge to any external API with OAuth2/API key auth. Useful for pushing events to Salesforce, Zendesk, or any REST endpoint without a Lambda intermediary.

---

## Error Handling & Reliability

### At-Least-Once Delivery
EventBridge guarantees at-least-once delivery. Design consumers to be **idempotent** (use `event.id` as a deduplication key).

### Dead-Letter Queues
Each target can have its own DLQ (SQS queue):
```json
{
  "DeadLetterConfig": {
    "Arn": "arn:aws:sqs:us-east-1:123:my-dlq"
  }
}
```

### Retry Policy (per target)
- Max retries: 185
- Max duration: 86,400 seconds (24h)
- Exponential backoff between retries

### Event delivery failure causes
- Target throttled or unavailable
- Target permissions misconfigured (IAM role missing or wrong)
- Event exceeds target payload limit
- Target error (Lambda throws, SQS full)

---

## Observability

| Metric | Alarm | Meaning |
|--------|-------|---------|
| `FailedInvocations` | >0 | Rules failing to deliver to targets |
| `MatchedEvents` | Baseline deviation | Traffic spike or drop |
| `ThrottledRules` | >0 | EventBridge throughput limit hit |
| `DeadLetterInvocations` | >0 | Events routed to DLQ — investigate |

Use CloudWatch Contributor Insights for EventBridge to identify top event sources/types driving volume.

---

## Event-Driven Architecture Patterns

### Choreography (EventBridge-native)
```
OrderService → OrderPlaced event → Bus
  → InventoryService (rule) → InventoryReserved event
  → ShippingService (rule) → ShipmentCreated event
  → NotificationService (rule)
```
Pros: loose coupling, independent deployability
Cons: hard to track end-to-end flow; failure handling distributed across services

### Orchestration (Step Functions + EventBridge)
```
EventBridge rule (OrderPlaced) → triggers Step Functions
  Step Functions orchestrates: ReserveInventory → ProcessPayment → CreateShipment → Notify
```
Pros: centralized workflow visibility, clear error handling
Cons: coupling to orchestrator

**FAANG recommendation:** Choreography for independent, parallel side-effects (notifications, analytics). Orchestration for sequential, transactional workflows (order fulfillment with rollback).

---

## FAANG Interview Callouts

**"Design a microservices event bus for an e-commerce platform"**
→ Custom EventBridge bus (`ecommerce-prod`). Each service publishes typed events (`OrderPlaced`, `PaymentFailed`, `InventoryLow`). Schema Registry enforces contracts. Content-based rules route to downstream services. Archive all events for 30 days (audit + replay). Dead-letter to SQS per target.

**"EventBridge vs Kafka (MSK) — when do you pick which?"**
→ EventBridge: cross-service integration, AWS service events, SaaS integration, when teams own different services and don't want a shared infrastructure dependency. Kafka/MSK: high-throughput ordered streaming, multiple consumers each reading the full stream, replay beyond 24h without archiving, complex consumer group coordination. EventBridge throughput (10k/s soft) is 10-100× lower than Kafka.

**"How do you build a saga with EventBridge?"**
→ Choreography saga: each service listens for prior service's event and emits its own. Compensating transactions on failure event. Problem: tracing the saga across services is hard. Better: Step Functions Saga pattern (orchestrated) with EventBridge triggering the Step Functions execution.

**"How do you handle schema evolution without breaking consumers?"**
→ Schema Registry + backward-compatible changes (add optional fields, never remove or rename). Use schema versioning. Pin consumers to a specific schema version. When a breaking change is needed: publish a new event type (`OrderPlacedV2`), run both in parallel during migration, deprecate the old version.

**"How would you implement event replay after a downstream service bug?"**
→ Enable Archive on the EventBridge bus (filter to relevant events or all). When bug is fixed, create a Replay: select archive, time range of impacted events, target bus. Events re-flow through existing rules to the fixed consumer. Cost: replay bandwidth at $0.10/million events.
