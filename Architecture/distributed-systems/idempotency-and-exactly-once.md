# Idempotency and Exactly-Once Delivery

## The Core Problem (Start Here)

Your payment service sends a charge request to Stripe. The network drops the response. Did Stripe charge the customer or not? You don't know. If you retry and Stripe *did* receive it, the customer gets charged twice. If you don't retry and Stripe *didn't* receive it, the payment is lost.

This is the **Two Generals' Problem** at its core: in an unreliable network, you can never be 100% certain the other side received your message. Every distributed system must answer: "what happens when we retry?"

```
Your service              Stripe
     │                      │
     │── POST /charges ────►│
     │                      │ (charges customer: success!)
     │ ← response DROPPED   │
     │                      │
     │ Did it work? Unknown. │
     │                      │
Option A: retry → DOUBLE CHARGE
Option B: no retry → LOST PAYMENT
Option C: idempotent retry with same key → exactly-once charge ✓
```

---

## Delivery Semantics: Three Levels

| Semantic | Description | Problem | Fix |
|---|---|---|---|
| **At-most-once** | Send and forget; never retry | Messages can be lost | Add retries |
| **At-least-once** | Retry until acknowledged | Duplicate processing | Add idempotency |
| **Exactly-once** | No loss, no duplicates | Requires coordination | Idempotent producer + idempotent consumer |

**Important:** "Exactly-once" at the *broker* layer (e.g., Kafka EOS) does not give you exactly-once end-to-end unless your consumer's processing is also idempotent. Each layer must independently provide its guarantee.

---

## Why Exactly-Once Is Hard

### The Two Generals' Problem

Two generals must coordinate an attack. They communicate via messengers through enemy territory (unreliable). How does General A know General B received the "attack at dawn" message?

- A sends message → no response → did B get it?
- A sends again → response → did first message arrive too?

**Formally proven:** In an asynchronous network with message loss, there is no protocol that guarantees both sides commit simultaneously with certainty. You cannot achieve "true" exactly-once delivery between two nodes connected by an unreliable network — you can only achieve exactly-once *processing* through idempotency.

### Process Pauses and Retries

Even without network loss, exactly-once is hard because:
- Your service crashes after sending but before persisting "sent" state → retries cause duplicates
- The downstream service crashes after processing but before acknowledging → retries cause duplicates

---

## Idempotency Keys: The Canonical Pattern

### Definition

An **idempotency key** is a unique identifier for a logical operation. Retrying with the same key produces the same result with no side effect.

```
First request:
  POST /payments
  Idempotency-Key: "order-789-payment-attempt-1"
  { amount: 9900, currency: "usd" }
  → Response: 200 { payment_id: "ch_123", status: "succeeded" }

Retry (same key):
  POST /payments
  Idempotency-Key: "order-789-payment-attempt-1"
  { amount: 9900, currency: "usd" }
  → Response: 200 { payment_id: "ch_123", status: "succeeded" }  ← same response, no new charge
```

### Storage Design

```sql
CREATE TABLE idempotency_keys (
    key VARCHAR(255) PRIMARY KEY,      -- client-provided unique key
    request_hash VARCHAR(64),          -- SHA-256 of request body (detect misuse)
    response_status INT,               -- HTTP status code
    response_body TEXT,                -- cached response
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ,            -- TTL: typically 24h or 7 days

    INDEX idx_expires (expires_at)     -- for TTL cleanup
);

-- Request handling:
BEGIN;
  result = SELECT * FROM idempotency_keys WHERE key = $1 FOR UPDATE;
  IF result EXISTS AND result.request_hash == hash(request_body):
    RETURN result.response_body;       -- cache hit: return cached response
  ELSE IF result EXISTS:
    RETURN 422 "Idempotency key reuse with different request body";
  ELSE:
    -- Process request
    response = process(request_body);
    INSERT INTO idempotency_keys VALUES ($1, hash(body), response.status, response.body, now() + 7d);
    RETURN response;
COMMIT;
```

**TTL design:**
- Too short: client's retry window expires before all retries happen → can double-charge
- Too long: storage grows unbounded
- Stripe uses 24 hours; most payment processors use 7 days
- Use a background job to delete expired keys

### Idempotency Key Generation (Client Side)

```python
import uuid, hashlib

# Option 1: Pure random UUID (simplest)
key = str(uuid.uuid4())

# Option 2: Deterministic from business context (safer — idempotent even on client restart)
def make_idempotency_key(order_id: str, attempt: int) -> str:
    return hashlib.sha256(f"order:{order_id}:attempt:{attempt}".encode()).hexdigest()[:32]
```

**Deterministic keys** are superior: if your client restarts between generating and sending the key, a random UUID key is lost and you can't correlate retries. A deterministic key derived from stable business data (`order_id + attempt_number`) survives restarts.

---

## The Outbox Pattern

### The Dual-Write Problem

Imagine: a service processes an order and must (a) save the order to PostgreSQL and (b) publish an `OrderPlaced` event to Kafka. Two separate writes — and there is no atomic transaction spanning both:

```
DANGEROUS:
  1. Write order to PostgreSQL  ← succeeds
  2. Publish to Kafka           ← crashes here
  Result: order saved, event never published → downstream services never informed
```

### The Outbox Solution

Write the event to an **outbox table** in the *same database transaction* as the business data. A relay process then reads the outbox and publishes to Kafka.

```sql
BEGIN;
  -- Business write
  INSERT INTO orders VALUES ($order_id, $user_id, $amount, 'created');

  -- Outbox write (SAME transaction)
  INSERT INTO outbox (event_type, payload, status)
  VALUES ('OrderPlaced', '{"order_id": 123, ...}', 'pending');
COMMIT;
-- If this transaction commits, both the order AND the outbox entry exist.
-- If it fails, neither exists. Atomic!
```

**Relay process:**
```python
while True:
    events = db.query("SELECT * FROM outbox WHERE status = 'pending' ORDER BY id LIMIT 100")
    for event in events:
        kafka.publish(event.payload)             # at-least-once delivery to Kafka
        db.execute("UPDATE outbox SET status = 'sent' WHERE id = $1", event.id)
    sleep(0.1)
```

The relay delivers at-least-once to Kafka — if it crashes mid-batch, some events may be delivered twice. Make downstream consumers idempotent (below).

---

## Transactional Outbox + CDC

Instead of a polling relay, use **Change Data Capture (CDC)** to read the outbox:

```
PostgreSQL outbox table
    → Debezium (CDC connector reads WAL/replication slot)
    → Kafka Connect
    → Kafka topic

Benefits:
  - No polling overhead
  - Low latency (WAL is tailed continuously)
  - Transactional: Debezium only reads committed transactions
```

**Production:** Debezium + Kafka is the standard FAANG-scale implementation. Used by LinkedIn, Shopify, Airbnb for transactional event publishing.

---

## Kafka Exactly-Once Semantics (EOS)

### Producer Idempotence

```
producer.enable.idempotence = true

Kafka assigns each producer a PID (Producer ID).
Each message gets a sequence number per partition.
Broker deduplicates messages with same (PID, partition, sequence_number).
```

This handles the case where the producer retries after a network error — the broker sees the duplicate sequence number and drops it.

### Transactional API

For atomic writes across multiple topics/partitions:

```python
producer = KafkaProducer(
    transactional_id="payment-processor-1",  # stable ID across restarts
    enable_idempotence=True
)
producer.init_transactions()

try:
    producer.begin_transaction()
    producer.send("payments", key=b"order-789", value=payment_data)
    producer.send("notifications", key=b"user-123", value=notification_data)
    producer.commit_transaction()         # atomic: both topics get the message or neither
except Exception:
    producer.abort_transaction()          # atomic rollback
```

### Consumer-Side: Read Committed

Consumers should use `isolation.level = read_committed` — they only see messages from committed transactions (not aborted ones).

```
Without read_committed:
  Produce transaction begins, writes message M1 to topic A
  Transaction aborts
  Consumer reads M1 ← reads a message from an aborted transaction!

With read_committed:
  Consumer waits until transaction is committed/aborted before seeing M1
```

### The Limits of Kafka EOS

Kafka EOS guarantees exactly-once **within Kafka** — messages are not duplicated in the log. But:
- If your consumer writes to an external database and crashes mid-write, you may process twice → need idempotent consumer logic
- "Exactly-once" end-to-end requires the full stack to be idempotent

---

## Consumer-Side Idempotency

Three strategies for making consumers handle duplicate messages:

### 1. Naturally Idempotent Operations

```python
# Idempotent: setting a value is always safe to repeat
db.execute("UPDATE users SET email_verified = true WHERE id = $1", user_id)
# Running this twice → same result as running once ✓

# NOT idempotent: incrementing
db.execute("UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, account_id)
# Running twice → double-charges ✗
```

### 2. Deduplication Table

```sql
CREATE TABLE processed_messages (
    message_id VARCHAR(255) PRIMARY KEY,
    processed_at TIMESTAMPTZ DEFAULT now()
);

-- Consumer processing:
BEGIN;
  IF NOT EXISTS (SELECT 1 FROM processed_messages WHERE message_id = $1):
    -- process the message (business logic)
    INSERT INTO processed_messages VALUES ($1);
COMMIT;
```

### 3. Kafka Consumer Group Offsets

Kafka tracks which offset the consumer group has committed. On restart, consumer re-reads from the last committed offset. If processing is idempotent, replaying a few messages is harmless.

```python
# Manual offset commit (after successful processing)
consumer.poll(...)
process(message)
consumer.commitSync()   # only commit after successful processing
```

---

## End-to-End Exactly-Once: Full Stack

For a payment system processing charges exactly once:

```
Client → API Gateway → Payment Service → Stripe → DB

Layer 1: Client
  - Generate deterministic idempotency key: SHA256(user_id + order_id)
  - Retry with same key on network error

Layer 2: API Gateway
  - Check idempotency key in Redis/DB
  - Return cached response on duplicate

Layer 3: Payment Service
  - Idempotency key stored in DB before calling Stripe
  - If crash before Stripe call: retry detects no Stripe call made → call Stripe
  - If crash after Stripe call: retry detects Stripe already charged → return cached response

Layer 4: Stripe
  - Stripe's own idempotency key (our key passed through) → Stripe deduplicates

Layer 5: Outbox → Kafka
  - Outbox pattern ensures event only published if DB write committed
  - Kafka EOS ensures event not duplicated in Kafka log

Layer 6: Downstream consumers
  - Idempotent processing (dedup table or naturally idempotent operation)
```

---

## Production Examples

| System | Mechanism | Exactly-Once? |
|---|---|---|
| **Stripe API** | Idempotency-Key header, 24h TTL | Yes (per API call) |
| **Kafka EOS** | Producer idempotence + transactional API | Within Kafka only |
| **Google Pub/Sub** | Exactly-once delivery option (beta) | Best-effort dedupe |
| **AWS SQS FIFO** | Message deduplication ID, 5-minute window | Yes (within 5 min) |
| **Debezium + Outbox** | WAL-based CDC, Kafka EOS | Yes (if consumer idempotent) |
| **Temporal.io workflows** | Workflow state persisted; activities retried with same ID | Yes (workflow level) |

---

## Cross-References

- [distributed-transactions.md](./distributed-transactions.md) — Outbox pattern, SAGA compensating transactions
- [write-ahead-log-and-storage-internals.md](./write-ahead-log-and-storage-internals.md) — WAL + CDC foundation
- [replication-patterns.md](./replication-patterns.md) — Kafka ISR (in-sync replicas) and durability

---

## FAANG Interview Application

**Likely questions:**
- "Your payment service needs to charge a card exactly once. Walk me through the design."
- "What's the outbox pattern? Why do you need it instead of writing to DB and Kafka directly?"
- "What does Kafka exactly-once semantics guarantee? What doesn't it guarantee?"
- "A client retries a payment request because the network timed out. How do you prevent double-charging?"

**What interviewers evaluate:**
- Do you know the difference between at-least-once, at-most-once, and exactly-once?
- Can you explain why the outbox pattern is necessary (the dual-write problem)?
- Do you know that Kafka EOS is only "exactly-once within Kafka" — not end-to-end?
- Can you design an idempotency key schema with correct TTL reasoning?

**Principal-level signal:**
> "Exactly-once is a stack property, not a single component property. Kafka EOS gives you exactly-once in the log, but if your consumer writes to Postgres without a deduplication check, you still process twice on consumer restart. The correct approach is: idempotency keys at the API layer (with deterministic key generation), outbox pattern for the DB→Kafka boundary, Kafka EOS for the log, and deduplication tables or naturally idempotent operations at the consumer. Each layer handles its own failure mode. The Two Generals' Problem means you can never have absolute certainty at the network layer — you can only make retries safe through idempotency."
