# 28. Outbox Pattern
**Category**: Modern / Enterprise  
**GoF**: No (microservices integration pattern)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Guarantee that a database write and a message publication are either both done or both not done, by writing the message to an "outbox" table in the same transaction as the domain object, then publishing asynchronously.

---

## Problem It Solves

`OrderService.placeOrder()` writes the order to PostgreSQL and then calls `kafkaProducer.send(OrderPlacedEvent)`. If Kafka is unavailable or crashes between the two: the order is persisted but the event is never published — inventory is never decremented, the user never gets a confirmation email, analytics never tracks the order. The dual-write problem. Outbox solves it by treating the event as data: write to `outbox` table in the same DB transaction as the order, then poll and publish from the outbox.

## Structure (Participants)

```
  OrderService.placeOrder()
  ┌───────────────────────────────────────────┐
  │ BEGIN TRANSACTION                         │
  │   INSERT INTO orders (...)                │← domain write
  │   INSERT INTO outbox (event, status=PENDING)│← event write
  │ COMMIT                                    │
  └───────────────────────────────────────────┘
                    │
         OutboxPoller (separate process)
  ┌───────────────────────────────────────────┐
  │ SELECT * FROM outbox WHERE status=PENDING  │
  │ FOR EACH event:                            │
  │   kafkaProducer.send(event)               │
  │   UPDATE outbox SET status=PUBLISHED       │
  └───────────────────────────────────────────┘
                    │
             Kafka Topic
             order-events
```

Key participants:
- **Outbox Table**: a table in the same database, same schema, transactionally consistent with domain tables
- **Domain Service** (`OrderService`): writes domain object + outbox entry in one ACID transaction
- **Outbox Poller** / **Relay**: separate process that reads PENDING outbox entries, publishes to Kafka, marks as PUBLISHED
- **Message Broker** (Kafka): receives events with at-least-once delivery guarantee

---

## Real-World Use Case: Reliable Order Event Publishing

An order service writes to PostgreSQL and needs to publish `OrderPlaced` events to Kafka for downstream consumers (inventory, email, analytics). With Outbox, the order and event are written atomically. The outbox poller publishes independently — if Kafka is down, events accumulate in outbox and are published when Kafka recovers.

### Implementation

```java
// Outbox entry — written in same transaction as domain object
@Entity
@Table(name = "outbox")
public class OutboxEntry {
    @Id
    private String messageId;          // idempotency key for Kafka
    private String aggregateType;      // "ORDER"
    private String aggregateId;        // orderId
    private String eventType;          // "OrderPlaced"
    private String payload;            // JSON-serialized event
    private String topic;              // Kafka topic
    private OutboxStatus status;       // PENDING | PUBLISHED | FAILED
    private Instant createdAt;
    private Instant publishedAt;
    private int retryCount;
}

public enum OutboxStatus { PENDING, PUBLISHED, FAILED }

// Repository for outbox
public interface OutboxRepository {
    void save(OutboxEntry entry);
    List<OutboxEntry> findPending(int batchSize);
    void markPublished(String messageId);
    void markFailed(String messageId, String error);
    void incrementRetryCount(String messageId);
}

// Domain service — writes order + outbox in one transaction
@Service
@Transactional
public class OrderService {
    private final OrderRepository orderRepo;
    private final OutboxRepository outboxRepo;
    private final ObjectMapper objectMapper;

    public Order placeOrder(OrderRequest request, User user) {
        // Domain write
        Order order = new Order(request, user);
        orderRepo.save(order);

        // Outbox write — SAME transaction
        OrderPlacedEvent event = new OrderPlacedEvent(order, user, Instant.now());
        OutboxEntry outboxEntry = OutboxEntry.builder()
            .messageId(UUID.randomUUID().toString())
            .aggregateType("ORDER")
            .aggregateId(order.id())
            .eventType("OrderPlaced")
            .payload(objectMapper.writeValueAsString(event))
            .topic("order-events")
            .status(OutboxStatus.PENDING)
            .createdAt(Instant.now())
            .retryCount(0)
            .build();
        outboxRepo.save(outboxEntry);

        // If transaction commits: both order row and outbox row exist
        // If transaction rolls back: neither exists
        // Kafka NOT called here — no dual-write
        return order;
    }
}

// Outbox poller — runs in a separate thread/pod, outside the main transaction
@Component
public class OutboxPoller {
    private final OutboxRepository outboxRepo;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final int batchSize = 100;
    private final int maxRetries = 3;

    @Scheduled(fixedDelay = 500)  // poll every 500ms
    public void poll() {
        List<OutboxEntry> pending = outboxRepo.findPending(batchSize);

        for (OutboxEntry entry : pending) {
            try {
                // Kafka send — idempotent producer (enable.idempotence=true)
                kafkaTemplate.send(entry.getTopic(), entry.getAggregateId(), entry.getPayload())
                    .get(5, TimeUnit.SECONDS);  // sync wait for confirmation

                outboxRepo.markPublished(entry.getMessageId());
                metrics.counter("outbox.published").increment();

            } catch (Exception e) {
                log.error("Failed to publish outbox entry {}", entry.getMessageId(), e);
                outboxRepo.incrementRetryCount(entry.getMessageId());

                if (entry.getRetryCount() + 1 >= maxRetries) {
                    outboxRepo.markFailed(entry.getMessageId(), e.getMessage());
                    alerting.sendAlert("Outbox entry failed after " + maxRetries + " retries: " + entry.getMessageId());
                }
            }
        }
    }
}

// Database schema
/*
CREATE TABLE outbox (
    message_id      UUID PRIMARY KEY,
    aggregate_type  VARCHAR(50) NOT NULL,
    aggregate_id    VARCHAR(100) NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    payload         JSONB NOT NULL,
    topic           VARCHAR(200) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMPTZ,
    retry_count     INT NOT NULL DEFAULT 0,
    failure_reason  TEXT,

    INDEX idx_outbox_status_created (status, created_at)
    WHERE status = 'PENDING'
);
*/

// Alternative: Debezium CDC (Change Data Capture)
// Instead of polling, Debezium reads PostgreSQL WAL and publishes new outbox rows to Kafka automatically
// Advantages: zero polling overhead, sub-second latency
// Setup: Debezium PostgreSQL connector → Kafka topic → consumers
```

### How It Works (walkthrough)

1. `orderService.placeOrder(request, user)` → BEGIN TX
2. `orderRepo.save(order)` → `INSERT INTO orders (...)` 
3. `outboxRepo.save(outboxEntry)` → `INSERT INTO outbox (..., status='PENDING')`
4. COMMIT → both rows atomically committed; Kafka not called
5. OutboxPoller wakes up (500ms later) → `SELECT * FROM outbox WHERE status='PENDING'`
6. For each entry: `kafkaTemplate.send("order-events", orderId, payload)` → success
7. `UPDATE outbox SET status='PUBLISHED', published_at=NOW()`
8. Kafka consumers (inventory, email, analytics) process `OrderPlaced` event

**Failure scenarios handled:**
- Kafka down during step 6: retry up to 3x, entry stays PENDING, retried on next poll
- App crashes between step 4 and step 6: poller picks up PENDING entries on restart
- DB crash during step 2 or 3: TX rolled back, no outbox entry, no order — clean state

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | OrderService writes business data; OutboxPoller handles publishing |
| Open/Closed | ✅ | Add new event types — just write new outbox entries; poller unchanged |
| Liskov Substitution | ✅ | Any Kafka-compatible broker substitutable |
| Interface Segregation | ✅ | `OutboxRepository` has focused read/write methods |
| Dependency Inversion | ✅ | OrderService depends on `OutboxRepository` interface |

---

## When to Use

- A database write and a message publication must be atomic
- At-least-once delivery is acceptable (Kafka consumers must be idempotent)
- You need to guarantee event publication even if the message broker is temporarily unavailable
- Microservices need reliable event-driven integration

## When NOT to Use

- Exactly-once delivery required — consider Kafka transactions (more complex)
- Message volume is very high — polling adds DB load; use CDC/Debezium instead
- The domain object and message broker are the same system (e.g., event store that doubles as a message bus)

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates dual-write — atomicity guaranteed by the DB transaction | Extra table and polling process to maintain |
| Retry on failure — entries stay PENDING until successfully published | At-least-once delivery — consumers must be idempotent |
| DB is the source of truth for unpublished events | Polling adds load to the DB (mitigated by CDC/Debezium) |
| No Kafka dependency in the order placement path | Latency: events published 0–500ms after commit (not inline) |

---

**FAANG interview application**: "The Outbox Pattern solves the dual-write problem: we can't write to PostgreSQL and Kafka atomically because they're different systems. Solution: write the event to an outbox table in the same DB transaction as the domain object, then publish asynchronously from the outbox. The key properties: (1) if the TX commits, the outbox entry exists — guaranteed delivery; (2) if Kafka is down, entries accumulate in outbox and are published when Kafka recovers; (3) consumers must be idempotent — at-least-once delivery means duplicates are possible. For sub-second latency, use Debezium CDC to tail the PostgreSQL WAL instead of polling."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Saga](26-saga.md) | Saga events should be published via the Outbox Pattern for guaranteed delivery |
| [Domain Events](31-domain-events.md) | Domain events should be durably published using the Outbox Pattern |
| [Event Sourcing](27-event-sourcing.md) | Event store events can serve as the outbox — CDC publishes them to Kafka |
