# RabbitMQ — Read/Write Path & Delivery Internals

## Message Publish Path

```
[Producer]
    │
    1. Basic.Publish (exchange, routing_key, body, properties)
    │
    ▼
[Broker: Connection Process]
    │
    2. Validate message (frame parsing, size check)
    │
    ▼
[Exchange Process]
    │
    3. Route: match routing_key against bindings
    │
    ▼
[Queue Process(es)]
    │
    4a. If delivery_mode=2 (persistent): write to on-disk journal (Mnesia/WAL)
    4b. If delivery_mode=1 (transient): hold in memory only
    │
    ▼
    5. If publisher confirms enabled: send Basic.Ack back to producer
    │
    ▼
[Consumer Process]
    │
    6. Basic.Deliver (when consumer has prefetch capacity available)
    │
    ▼
    7. Consumer processes → Basic.Ack / Basic.Nack
    │
    ▼
    8. Message deleted from queue (on ack) or re-queued (on nack with requeue=true)
```

---

## Publisher Confirms

Publisher confirms are the mechanism that gives producers **at-least-once delivery guarantees**. Without confirms, publishing is fire-and-forget — a broker crash between steps 1–4 silently loses the message.

### How Confirms Work

```
Producer                          Broker
   │                                │
   ├─── Basic.Publish(msg, seq=1) ──►│
   ├─── Basic.Publish(msg, seq=2) ──►│  ← async — do not wait per message
   ├─── Basic.Publish(msg, seq=3) ──►│
   │                                 │
   │                       (broker persists batch)
   │                                 │
   │◄── Basic.Ack(deliveryTag=3, multiple=true)  ── confirms seq 1, 2, 3 in one ack
```

### Three Confirm Modes

| Mode | How | Throughput | Reliability |
|---|---|---|---|
| **No confirms** | Fire and forget | Highest | None — silent loss on crash |
| **Individual confirms** | `waitForConfirmsOrDie()` after each publish | Low (~5–10K/sec) | Highest — exactly when each message is safe |
| **Batch confirms** | Publish N messages, then `waitForConfirmsOrDie()` | Medium-high | High — lose at most N messages on crash (tune batch size) |
| **Async confirms** (preferred) | Register confirm listener; publish freely; handle ack/nack callbacks | Highest with safety | High — non-blocking; track pending in a correlation map |

### Async Confirm Implementation (Java)

```java
Channel channel = connection.createChannel();
channel.confirmSelect();                // enable confirm mode

// Track unconfirmed messages
ConcurrentNavigableMap<Long, Message> pendingConfirms = new ConcurrentSkipListMap<>();

channel.addConfirmListener(
    (deliveryTag, multiple) -> {        // ack handler
        if (multiple) {
            pendingConfirms.headMap(deliveryTag + 1).clear();
        } else {
            pendingConfirms.remove(deliveryTag);
        }
    },
    (deliveryTag, multiple) -> {        // nack handler — broker rejected
        if (multiple) {
            pendingConfirms.headMap(deliveryTag + 1).forEach((k, v) -> handleFailure(v));
        } else {
            handleFailure(pendingConfirms.remove(deliveryTag));
        }
    }
);

long seqNo = channel.getNextPublishSeqNo();
pendingConfirms.put(seqNo, message);
channel.basicPublish(exchange, routingKey, props, body);
```

**Rule**: Always use publisher confirms in production. Async confirms give you both safety and throughput.

---

## Message Persistence

| Scenario | In-Memory | On Disk |
|---|---|---|
| `delivery_mode=1` (transient) | ✅ | ❌ (lost on broker restart) |
| `delivery_mode=2` (persistent) | ✅ (cache) | ✅ (journal + index) |
| Queue declared `durable=false` | ✅ | ❌ (queue itself deleted on restart) |
| Queue declared `durable=true` | ✅ | ✅ (queue survives restart) |

**Rule**: For reliable messaging, both the queue (`durable=true`) AND the message (`delivery_mode=2`) must be persistent. Either one missing → data loss on broker restart.

### Persistence Internals

RabbitMQ uses two on-disk stores for persistent messages:

| Store | What it Contains | Purpose |
|---|---|---|
| **Message journal** (WAL) | Raw message bodies | Durability — survives crash; written sequentially (fast) |
| **Message index** | Delivery state, sequence numbers, ack status | Tracks which messages are in which queues |
| **Queue index** | Per-queue sequence of message positions | Maps queue position to message store location |

Messages are written to the journal first (sequential append = fast), then indexed. On startup after a crash, the journal is replayed to rebuild queue state.

**Memory-to-disk paging**: When a queue's RAM usage grows beyond a threshold, RabbitMQ pages messages to disk (lazy queues force this immediately). Paged-out messages are read back on demand for delivery.

---

## Consumer Delivery Path

```
[Queue Process]
    │
    ├─ Consumer registers with Basic.Consume
    │
    └─ Queue checks: does consumer have prefetch capacity?
         │
         YES ──► Basic.Deliver(deliveryTag, exchange, routingKey, body, props)
         │              │
         │      [Consumer Process]
         │              │
         │       Process message
         │              │
         │       Basic.Ack(deliveryTag)  ──►  Queue removes message
         │              OR
         │       Basic.Nack(deliveryTag, requeue=true)  ──►  Queue re-enqueues
         │              OR
         │       Basic.Nack(deliveryTag, requeue=false) ──►  Dead-letter or discard
         │
         NO ──► Wait (backpressure — consumer is busy)
```

### Acknowledgment Modes

| Mode | Command | Behavior | Risk |
|---|---|---|---|
| **Auto-ack** | `autoAck=true` in `basicConsume` | Message removed from queue as soon as delivered | Data loss if consumer crashes before processing |
| **Manual ack** | `channel.basicAck(deliveryTag, false)` | Message removed after explicit ack | None — correct default for reliable processing |
| **Nack + requeue** | `channel.basicNack(deliveryTag, false, true)` | Message returned to front of queue | Risk: infinite retry loop if message is poison |
| **Nack + discard** | `channel.basicNack(deliveryTag, false, false)` | Dead-lettered (if DLX configured) or discarded | Requires DLX to avoid silent loss |
| **Reject** | `channel.basicReject(deliveryTag, false)` | Same as nack for single message | Single-message nack |

**Rule**: Never use `autoAck=true` in production unless messages are genuinely idempotent and loss is acceptable (e.g., real-time metric samples where missing one is fine).

---

## Consumer Prefetch (QoS)

Prefetch controls how many **unacknowledged messages** can be outstanding per consumer. This is the single most important tuning knob for consumer performance and fairness.

```
prefetch_count = 1  (fair dispatch):

Queue: [A][B][C][D][E][F]
Consumer 1: processes slowly → gets [A] → acks [A] → gets [C] → ...
Consumer 2: processes fast   → gets [B] → acks [B] → gets [D] → ...
Result: work is fairly distributed; slow consumer doesn't block fast one

prefetch_count = unlimited (default, BAD):

Queue: [A][B][C][D][E][F]
Consumer 1: receives ALL 6 messages at once (all buffered locally)
Consumer 2: receives nothing (queue appears empty)
Result: Consumer 1 is a bottleneck; Consumer 2 is idle
```

### Prefetch Recommendations

| Scenario | Recommended Prefetch | Reason |
|---|---|---|
| **Task queue (slow, variable processing time)** | 1 | Fair dispatch; slow task doesn't block queue for other consumers |
| **Fast consumer (predictable, sub-ms)** | 10–100 | Reduces round-trip overhead; batch delivery amortises network cost |
| **RPC server (fast processing)** | 10–50 | Throughput improvement without starvation risk |
| **Stream-like high-throughput consumer** | 100–500 | Maximise throughput; acks in batches |

```java
// Set prefetch before consuming
channel.basicQos(1);  // prefetch = 1 (fair dispatch for task queues)
channel.basicConsume(queueName, false, deliverCallback, cancelCallback);
```

---

## Flow Control (Credit-Based)

RabbitMQ uses a **credit-based flow control** mechanism at two levels:

### Level 1: Per-Queue Backpressure

Each queue grants credits to its connections. When a queue grows (messages accumulate faster than consumed), it reduces credits. When credits run out, the producer's channel pauses — publishers block without an error.

```
Queue depth: 0–10K     → full credits to publisher  → normal publish rate
Queue depth: 10K–50K   → reduced credits             → publish rate slows
Queue depth: 50K+      → zero credits                → publisher blocks
```

### Level 2: Global Memory and Disk Alarms

When **broker-wide** thresholds are crossed, all publishers block globally:

| Alarm | Default Threshold | Effect |
|---|---|---|
| **Memory alarm** | 40% of total system RAM | All publishers block; consumers continue |
| **Disk alarm** | 50MB free disk | All publishers block; consumers continue |

```
# rabbitmq.conf
vm_memory_high_watermark.relative = 0.4   # 40% of RAM
disk_free_limit.relative = 1.0            # 1x RAM free (safer than 50MB default)
```

**How producers observe blocking**: The AMQP `Connection.Blocked` / `Connection.Unblocked` notifications. Java client:

```java
connection.addBlockedListener(
    reason -> System.out.println("Publisher blocked: " + reason),
    ()     -> System.out.println("Publisher unblocked")
);
```

---

## Dead Letter Exchange (DLX)

A Dead Letter Exchange (DLX) is a regular exchange to which the broker routes messages that are "dead":

| Death Reason | Trigger |
|---|---|
| `rejected` | Consumer calls `basicNack(requeue=false)` or `basicReject(requeue=false)` |
| `expired` | Message TTL exceeded (per-message `expiration` or queue `x-message-ttl`) |
| `maxlen` | Queue exceeded `x-max-length`; oldest message dropped |
| `delivery_limit` | Quorum queue `x-delivery-limit` exceeded (max retries) |

### DLX Configuration

```java
// Declare the work queue with DLX routing
Map<String, Object> args = new HashMap<>();
args.put("x-dead-letter-exchange", "dlx-exchange");     // where dead messages go
args.put("x-dead-letter-routing-key", "dlq.orders");    // routing key for dead messages
args.put("x-message-ttl", 30000);                        // messages expire after 30 sec
args.put("x-max-length", 10000);                         // max 10K messages; oldest dead-lettered

channel.queueDeclare("orders-work-queue", true, false, false, args);

// Declare the DLX exchange and dead letter queue
channel.exchangeDeclare("dlx-exchange", "direct", true);
channel.queueDeclare("dead-letter-queue", true, false, false, null);
channel.queueBind("dead-letter-queue", "dlx-exchange", "dlq.orders");
```

### Dead Letter Headers

The broker appends `x-death` headers to dead-lettered messages:

```json
"x-death": [
  {
    "queue":         "orders-work-queue",
    "exchange":      "orders-exchange",
    "routing-keys":  ["order.created"],
    "reason":        "rejected",
    "count":         3,
    "time":          "2024-01-15T10:00:00Z"
  }
]
```

Use `count` to implement max-retry logic: inspect `x-death[0].count` in the DLQ consumer; if count > threshold, send to a human-review queue.

### Retry with Exponential Backoff via DLX

```
                          RETRY TOPOLOGY

[Work Queue] ──(nack, requeue=false)──► [DLX Exchange]
                                              │
                                    ┌─────────▼──────────┐
                                    │  Delay Queue (TTL)  │
                                    │  x-message-ttl=5000 │  ← 5 second delay
                                    │  x-dead-letter-exchange=work-exchange │
                                    └────────────────────┘
                                              │
                                    (TTL expires → message dead-lettered back)
                                              │
                                    [Work Exchange] ──► [Work Queue]  ← retried
```

For multiple backoff tiers: declare multiple delay queues (5s, 30s, 5min, 30min) and route each retry to the appropriate tier based on `x-death[0].count`.

---

## Lazy Queues

Lazy queues store messages on disk as soon as possible rather than keeping them in RAM. Useful when:
- Queue depth is expected to be very large (millions of messages)
- Consumers are slow or offline for extended periods
- Memory pressure is a concern

```java
Map<String, Object> args = new HashMap<>();
args.put("x-queue-mode", "lazy");
channel.queueDeclare("lazy-queue", true, false, false, args);
```

**Trade-off**: Lazy queues have higher per-message disk I/O. For fast consumers with small queue depths, normal queues (RAM) are faster. For slow consumers with large backlogs, lazy queues prevent OOM.

In RabbitMQ 3.12+, quorum queues are inherently lazy (they always page to disk beyond a configurable in-memory limit).

---

## FAANG Interview Callout

> "Publisher confirms and consumer acks are the two sides of at-least-once delivery. Without confirms, a broker crash between publish and persistence silently loses the message. Without acks, a consumer crash after delivery but before processing silently loses the message. Together they guarantee delivery but require idempotent consumers — the same message may be delivered twice on consumer restart. The standard production pattern is async publisher confirms (batch-confirm listener, not wait-per-message) and manual acks with a low prefetch (1 for task queues, 10–100 for fast consumers). The DLX is the safety net: nack without requeue routes to a dead-letter queue for inspection rather than silent discard."

---

## Related Files

| File | Topic |
|---|---|
| [01-architecture.md](01-architecture.md) | Exchange types and queue types that determine the publish/consume topology |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | How delivery guarantees compare to Kafka |
| [04-tuning-guide.md](04-tuning-guide.md) | Prefetch, confirm batch size, memory/disk alarm thresholds |
