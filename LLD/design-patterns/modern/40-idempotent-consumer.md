# 40. Idempotent Consumer
**Category**: Modern / Enterprise  
**GoF**: No (Enterprise Integration Patterns — Hohpe & Woolf 2003)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Design a message consumer so that processing the same message multiple times produces the same result as processing it once — by recording processed message IDs in a deduplication store before committing side effects.

---

## Problem It Solves

Kafka, SQS, and most message brokers guarantee **at-least-once delivery**: a message may be delivered multiple times due to consumer rebalance, broker failure, or network partition. An `OrderPlaced` event processed twice means: two confirmation emails sent, inventory decremented twice, and potentially two payment charges. Without Idempotent Consumer, at-least-once delivery cannot be used safely. The pattern converts at-least-once into effectively-exactly-once at the consumer side — without requiring a distributed transaction with the broker.

**Root cause**: Offset commits in Kafka (or visibility-timeout deletions in SQS) are a separate operation from business logic. A crash between them causes redelivery.

## Structure (Participants)

```
  Broker (Kafka/SQS)
       │
       │  delivers message (possibly duplicate)
       ▼
  IdempotentConsumer
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │  1. Extract message ID                           │
  │  2. Check deduplication store                    │
  │       ├── SEEN? → ack + discard (return early)   │
  │       └── NEW?  → proceed                        │
  │  3. Execute business logic                       │
  │  4. Record message ID in deduplication store     │
  │  5. Commit offset / delete from queue            │
  │                                                  │
  └──────────────────────────────────────────────────┘
         │                        │
         ▼                        ▼
  Business Logic          Deduplication Store
  (order service)         (Redis / DB table)
```

Key participants:
- **Message ID**: globally unique identifier embedded in every message (Kafka: `topic+partition+offset`; SQS: `MessageId`; custom: `UUID` in headers)
- **Deduplication Store**: fast, durable KV store recording processed message IDs with a TTL
- **Idempotent Handler**: checks store before processing; records ID after successful processing
- **Business Logic**: the actual handler — must be wrapped, not modified

---

## Real-World Use Case: Order Processing Consumer

An `OrderPlaced` event triggers: inventory reservation, payment charge, and email confirmation. Any of these can fail mid-processing, causing redelivery. Without idempotency, each redelivery causes double-charging.

### Implementation

```java
// Message envelope with a stable, globally unique ID
public record Message<T>(
    String  messageId,    // e.g. "order-placed:kafka:orders:3:142857"
    T       payload,
    Instant publishedAt,
    Map<String, String> headers
) {}

// Deduplication store abstraction
public interface DeduplicationStore {
    // Returns true if message was NEW (not seen before)
    // Returns false if DUPLICATE (already processed)
    // Implementation must be atomic: check-and-set in one operation
    boolean markIfAbsent(String messageId, Duration ttl);
}

// Redis implementation — SETNX with TTL
public class RedisDeduplicationStore implements DeduplicationStore {
    private final RedisTemplate<String, String> redis;
    private static final String PREFIX = "msg:dedup:";

    public RedisDeduplicationStore(RedisTemplate<String, String> redis) {
        this.redis = redis;
    }

    @Override
    public boolean markIfAbsent(String messageId, Duration ttl) {
        // SET NX EX is atomic in Redis — no TOCTOU race
        Boolean result = redis.opsForValue().setIfAbsent(
            PREFIX + messageId, "1", ttl);
        return Boolean.TRUE.equals(result);  // true = new; false = duplicate
    }
}

// DB implementation — unique constraint on processed_messages table
public class DbDeduplicationStore implements DeduplicationStore {
    private final JdbcTemplate jdbc;

    @Override
    public boolean markIfAbsent(String messageId, Duration ttl) {
        try {
            jdbc.update(
                "INSERT INTO processed_messages (message_id, processed_at, expires_at) " +
                "VALUES (?, NOW(), NOW() + INTERVAL '? seconds')",
                messageId, ttl.getSeconds());
            return true;  // insert succeeded → new message
        } catch (DuplicateKeyException e) {
            return false; // unique constraint violation → duplicate
        }
    }
}

// Idempotent consumer wrapper
public class IdempotentConsumer<T> {
    private final Consumer<Message<T>> delegate;       // real business logic handler
    private final DeduplicationStore   dedupStore;
    private final Duration             dedupTtl;       // how long to remember processed IDs
    private final MeterRegistry        metrics;

    public IdempotentConsumer(
            Consumer<Message<T>> delegate,
            DeduplicationStore dedupStore,
            Duration dedupTtl,
            MeterRegistry metrics) {
        this.delegate   = delegate;
        this.dedupStore = dedupStore;
        this.dedupTtl   = dedupTtl;
        this.metrics    = metrics;
    }

    public void handle(Message<T> message) {
        boolean isNew = dedupStore.markIfAbsent(message.messageId(), dedupTtl);

        if (!isNew) {
            metrics.counter("consumer.duplicate.discarded",
                "message_type", message.payload().getClass().getSimpleName()).increment();
            log.info("Duplicate message discarded: {}", message.messageId());
            return;  // ack without processing — safe to drop
        }

        // New message — execute business logic
        try {
            delegate.accept(message);
            metrics.counter("consumer.processed").increment();
        } catch (Exception e) {
            // Processing failed after marking as seen.
            // Options:
            //   1. Remove the dedup entry + rethrow → broker will redeliver → retry
            //   2. Send to DLQ + keep dedup entry → no retry, manual intervention
            //   3. Keep dedup entry + swallow → message is lost (almost never right)
            dedupStore.markIfAbsent(message.messageId() + ":failed", Duration.ofMinutes(1));
            // Option 1: allow retry
            throw new MessageProcessingException("Failed to process " + message.messageId(), e);
        }
    }
}

// ─── Kafka integration ────────────────────────────────────────────────────────

@Component
public class OrderPlacedConsumer {
    private final IdempotentConsumer<OrderPlacedEvent> idempotentWrapper;

    @KafkaListener(topics = "order-placed", groupId = "order-processor")
    public void onOrderPlaced(ConsumerRecord<String, OrderPlacedEvent> record,
                              Acknowledgment ack) {
        String messageId = String.format("order-placed:%s:%d:%d",
            record.topic(), record.partition(), record.offset());

        Message<OrderPlacedEvent> message = new Message<>(
            messageId, record.value(), Instant.now(), Map.of());

        idempotentWrapper.handle(message);
        ack.acknowledge();  // manual ack after successful (or deduplicated) processing
    }
}

// The actual business logic — completely unaware of deduplication
@Component
public class OrderProcessor implements Consumer<Message<OrderPlacedEvent>> {
    private final InventoryService inventory;
    private final PaymentService   payment;
    private final EmailService     email;

    @Override
    @Transactional
    public void accept(Message<OrderPlacedEvent> message) {
        OrderPlacedEvent event = message.payload();
        inventory.reserve(event.orderId(), event.items());
        payment.charge(event.orderId(), event.totalAmount(), event.paymentMethodId());
        email.sendConfirmation(event.customerId(), event.orderId());
    }
}
```

### Choosing the Deduplication TTL

```
TTL = max expected redelivery window + safety margin

Kafka default retention: 7 days
  → TTL = 7 days (cover full retention window)

SQS message visibility timeout: up to 12 hours
  → TTL = 24 hours

For financial transactions: TTL = 30 days (regulatory audit window)
```

### When Processing Is NOT Naturally Idempotent

| Business Operation | Problem | Idempotency Strategy |
|-------------------|---------|---------------------|
| Charge payment | Double charge | Payment ID in request → payment provider deduplicates |
| Send email | Duplicate notification | Dedup store tracks `order_id + notification_type` |
| Decrement inventory | Over-decrement | Conditional update: `UPDATE ... WHERE reserved_qty = expected_qty` |
| Increment counter | Double count | Record `(message_id, counter_name)` in processed_messages |
| API call to third party | Provider charges per call | Idempotency key in API header (Stripe, PayPal support this) |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `IdempotentConsumer` handles deduplication only; `OrderProcessor` handles business logic only |
| Open/Closed | ✅ | New dedup strategies (Redis, DB, in-memory) via `DeduplicationStore` interface — no changes to consumer |
| Liskov Substitution | ✅ | `RedisDeduplicationStore` and `DbDeduplicationStore` are interchangeable |
| Interface Segregation | ✅ | `DeduplicationStore` exposes one method; `Consumer<T>` exposes one method |
| Dependency Inversion | ✅ | Business logic depends on `DeduplicationStore` abstraction |

---

## When to Use

- The message broker delivers at-least-once (Kafka, SQS, RabbitMQ, Pub/Sub)
- Business operations are not naturally idempotent (charges, emails, inventory mutations)
- Consumer rebalances or crashes can cause redelivery
- Exactly-once semantics are required at the application level

## When NOT to Use

- Using Kafka exactly-once semantics with transactional producers and consumers (handles duplication at the broker level)
- Operations are already naturally idempotent (SET instead of INCREMENT; upsert instead of insert)
- Messages are small enough that replaying from the start is cheaper than maintaining a dedup store

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Converts at-least-once to effectively-exactly-once without broker coordination | Dedup store is an additional dependency — Redis/DB must be highly available |
| Business logic handler is clean — no dedup concern mixed in | TTL management: too short → missed duplicates; too long → growing storage cost |
| Works across consumer restarts, rebalances, and deployments | Network partition: if dedup store is unreachable, you must choose: fail (miss messages) or process (accept risk of duplicate) |
| Complements Dead Letter Queue: non-idempotent failures → DLQ | Cross-consumer deduplication requires shared store; per-instance stores do not help for rebalances |

---

**FAANG interview application**: "At-least-once delivery is the practical reality with Kafka and SQS — exactly-once at the broker is expensive and rarely used. Idempotent Consumer is the standard answer for making consumers safe under redelivery. The implementation is: Redis SETNX with a TTL keyed on `topic:partition:offset` before processing, ack after. The TTL must cover the full message retention window (7 days for Kafka). For payment operations, always pass the order ID as an idempotency key to the payment provider — Stripe and PayPal both support this natively and deduplicate at their end, giving you belt-and-suspenders protection."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Dead Letter Queue](41-dead-letter-queue.md) | Complementary: DLQ handles poison-pill messages that can never succeed; Idempotent Consumer handles duplicates that should succeed once |
| [Outbox Pattern](28-outbox-pattern.md) | Outbox makes producers idempotent (publish exactly once); Idempotent Consumer makes consumers safe under redelivery — together they solve the dual-write problem end-to-end |
| [Saga](26-saga.md) | Saga steps must be idempotent — a compensating transaction applied twice must produce the same result |
| [Unit of Work](32-unit-of-work.md) | Record the processed message ID in the same DB transaction as the business write — atomically prevents duplicate processing without a separate dedup store |
