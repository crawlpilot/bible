# Trade-off: Synchronous vs Asynchronous Communication

**Category**: HLD · Service Communication · Architecture Decision  
**FAANG interview trigger**: "How would services communicate in your design?" / "What happens when Service B is down?" / "How do you handle high-volume events between services?"

---

## Context

The choice between synchronous (request-response) and asynchronous (event/message-based) communication is one of the most consequential architectural decisions in distributed systems. It affects latency, availability, throughput, consistency, and operational complexity — not just "which protocol to use."

At principal engineer level, the answer is never "use Kafka for everything" or "REST is fine." It's a nuanced analysis of the specific use case, failure modes, and consistency requirements.

---

## Definitions

**Synchronous communication**: the caller blocks until the response arrives. The caller and callee are temporally coupled. Examples: HTTP/REST, gRPC (unary), GraphQL.

**Asynchronous communication**: the caller sends a message and does not wait for a response. The systems are temporally decoupled. Examples: message queues (RabbitMQ, SQS), event streams (Kafka, Kinesis), event buses (EventBridge).

---

## Comparison

| Dimension | Synchronous (REST/gRPC) | Asynchronous (Kafka/SQS) |
|-----------|------------------------|-------------------------|
| **Coupling** | Temporal + spatial: caller needs callee up | Temporal only: callee can be down; spatial decoupled via broker |
| **Latency** | Low: response in milliseconds | Higher: broker round-trip adds 5–50ms; consumer processing lag adds more |
| **Throughput** | Bounded by callee capacity | Unbounded: broker absorbs bursts; consumers scale independently |
| **Backpressure** | Natural: slow callee slows caller (visible) | Hidden: lag accumulates in queue without blocking producers |
| **Consistency** | Strong: response confirms execution | Weaker: "message delivered" ≠ "message processed" |
| **Error handling** | Immediate: caller knows about failure synchronously | Eventual: dead-letter queues, retry queues, consumer-side error tracking |
| **Observability** | Easy: distributed trace spans, HTTP status codes | Harder: consumer lag, DLQ depth, per-partition offset tracking |
| **Complexity** | Low: HTTP is universal and simple | High: broker operations, consumer group coordination, offset management |
| **Ordering** | Natural in request-response | Kafka: per-partition ordering; SQS: no ordering (SQS FIFO: per-group) |
| **Exactly-once** | Idempotent API design gives effectively-once | Kafka transactions; SQS FIFO + deduplication window |

---

## When to Choose Synchronous (REST/gRPC)

**Choose synchronous when:**

1. **The caller needs the result to continue**: user-facing read requests (`GET /product/123`), authentication (`validate JWT`), payment authorization (`charge $50`). The response is required to render the next page or proceed with the transaction.

2. **Latency is the primary constraint**: user-facing APIs have P99 budgets of 50–200ms. Adding a message broker adds a round-trip that's hard to keep under 10ms — on top of the consumer processing time, which may happen asynchronously.

3. **Strong consistency is required**: "Did the order succeed?" must be answered with certainty. Asynchronous systems can only tell you "the order request was accepted" — not "the order was committed."

4. **The call graph is simple and shallow**: service A calls service B to get a result, uses it to call service C. A synchronous chain of 2–3 calls is fine. A synchronous fan-out of 20 downstream services is not (use async fan-out instead).

5. **Real-time feedback is UX-critical**: search-as-you-type, autocomplete, live pricing — these require a response in <100ms or the user experience degrades visibly.

**gRPC vs REST:**
- REST: universal, browser-compatible, human-readable, good for public APIs
- gRPC: binary encoding (Protobuf, 30–60% smaller), streaming support, strongly typed contracts, better for internal service-to-service at high volume

---

## When to Choose Asynchronous (Kafka/SQS/RabbitMQ)

**Choose asynchronous when:**

1. **The producer doesn't need to wait for the result**: "send a welcome email when a user registers" — the registration API doesn't need to wait for the email to be sent. Failure to send email is a background concern, not a registration failure.

2. **Traffic is bursty and the consumer is slower than the producer**: e-commerce checkout at peak → 100K orders/min; fraud analysis takes 500ms/order. An async queue absorbs the burst and lets fraud analysis work at its own pace. Without a queue, the checkout service would need to wait 500ms per order or fail.

3. **Multiple consumers need to react to the same event**: user signup event → send welcome email, add to CRM, provision trial, log to analytics. Each consumer subscribes to the same event independently. In synchronous design, you'd need to call all 4 services in sequence or fan-out, coupling the user signup to each downstream system.

4. **Temporal decoupling for availability**: if the downstream service (email, analytics) is down for maintenance, an async queue absorbs events during the downtime. The producer continues operating; the consumer processes the backlog when it recovers.

5. **Event sourcing or audit trail**: Kafka as a replayable event log allows rebuilding downstream state at any point. This is foundational for CQRS, event sourcing, and audit logging.

**Kafka vs SQS vs RabbitMQ:**

| Broker | Best For | Avoid When |
|--------|----------|------------|
| **Kafka** | High-throughput streams, replayable event log, multi-consumer fan-out, event sourcing | Low-volume (<1K msg/sec), simple queue semantics, fully managed preference |
| **SQS** | Decoupled microservices, AWS-native, simple queue, fully managed | Need replay, Kafka-compatible consumers, ordering across partitions |
| **SQS FIFO** | Ordered processing, exactly-once (with dedup window) | High throughput (3K msg/sec hard limit per queue) |
| **RabbitMQ** | Complex routing (exchange patterns), push-based delivery, lower latency | Extreme throughput, event sourcing, replayability |

---

## Failure Modes Comparison

### Synchronous Failure Modes
- **Callee is down**: caller gets a connection error. Caller must handle and retry.
- **Callee is slow**: caller times out. Without circuit breakers, slow callees cascade into caller failures.
- **Thundering herd on callee recovery**: if 1000 callers have been queuing retries, they all hit the callee simultaneously when it recovers.

**Mitigations**: circuit breaker (stop sending when callee is failing), exponential backoff with jitter (spread retries), bulkhead (limit concurrent calls to one service).

### Asynchronous Failure Modes
- **Consumer is down**: messages accumulate in the queue. When consumer recovers, it processes the backlog.
- **Message is unprocessable** (poison pill): without a dead-letter queue, the consumer retries forever, blocking other messages.
- **Queue fills up**: if the consumer can't keep up, the queue grows unboundedly. Kafka can retain for days (storage-bounded); SQS has a 14-day retention window.
- **Duplicate messages**: at-least-once delivery means consumers may see the same message twice. Consumers must be idempotent.

**Mitigations**: dead-letter queues (DLQ) for unprocessable messages, consumer lag monitoring, idempotent consumers, consumer group rebalancing.

---

## The Hybrid Pattern: Synchronous Front / Async Back

The most common FAANG architecture is synchronous for the user-facing path (because users need immediate feedback), async for the downstream processing (because those steps can happen after the response is sent).

**Example — Order Placement:**
```
User → POST /order → Order Service → PostgreSQL (synchronous, ACID)
                                   → Return 200 OK to user

[After response]:
Order Service → publish "order.created" event → Kafka
Fraud Service ← consume event → async fraud check
Inventory Service ← consume event → async inventory deduction
Notification Service ← consume event → send email
```

The user sees a 200 OK immediately. Fraud check, inventory deduction, and notification happen asynchronously. If fraud check fails, the order is later cancelled (compensating transaction) rather than blocking the checkout flow.

**When this pattern applies**: user-facing API where downstream processing can tolerate eventual consistency (seconds to minutes, not milliseconds).

**When this pattern does NOT apply**: financial transfers where the user needs to know immediately if the transfer succeeded or failed. Banking systems keep the entire transaction synchronous with immediate confirmation.

---

## Consistency Trade-offs

| Scenario | Pattern | Consistency |
|----------|---------|-------------|
| User-facing read | Sync REST | Strong |
| Payment authorization | Sync gRPC | Strong |
| Analytics event | Async Kafka | Eventual |
| Email notification | Async SQS | Eventual |
| Order → inventory deduction | Async Saga | Eventual with compensation |
| Multi-region replicate | Async replication | Eventual |

The Saga pattern is the primary approach for distributed transactions in async systems: break a multi-step transaction into steps, each publishing an event to the next step. On failure, issue compensating events to roll back completed steps. Consistency is eventual, not atomic.

---

## FAANG Interview Callouts

**Demonstrate this thinking:**
- "The checkout endpoint is synchronous — the user needs confirmation before leaving the page. But after we write the order to the DB and return 200, we publish an `order.created` event so fraud detection, inventory reservation, and notification all happen asynchronously without coupling to the checkout latency."
- "If I made fraud detection synchronous in the checkout path, we'd be adding 200–500ms of latency and making checkout reliability dependent on the fraud service's availability. That's the wrong coupling."
- "For the newsfeed generation, we use Kafka — a user's post fans out to potentially millions of follower feeds. That fan-out can't be synchronous because a single post from a celebrity might trigger 100M fan-out operations. We use async fan-out with consumer lag tolerated at the feed level."

**Red flags:**
- "I'll use Kafka for everything" — Kafka has real operational complexity; using it for a 10 RPS internal API is overkill
- Making all downstream calls synchronous in a high-throughput path
- Not mentioning what happens when the async consumer is down
- Not mentioning idempotency for at-least-once async consumers

**The key question to ask yourself in the interview**: "Does the caller need the result to proceed, or just the acknowledgment that the request was received?" If result → sync. If acknowledgment → async.
