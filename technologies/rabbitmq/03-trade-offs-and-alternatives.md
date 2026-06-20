# RabbitMQ — Trade-offs & Alternatives

## CAP Theorem Position

RabbitMQ's CAP position depends on the queue type:

```
         Consistency
              │
     CP       │       CA
  (Quorum     │   (Classic mirrored
   Queues     │    — async, can lose
   via Raft)  │      data under partition)
              │
──────────────┼──────────────────
              │
     AP       │
  (Classic    │
   Queues     │
   without HA)│
              │
        Partition Tolerance
```

### Quorum Queues (CP)

Quorum queues use Raft consensus. During a network partition where a minority of nodes are isolated:
- The **majority partition** (quorum) continues accepting reads and writes
- The **minority partition** stops accepting writes to prevent split-brain
- After partition heals, minority nodes catch up via Raft log replay

This is CP: the minority sacrifices Availability to preserve Consistency (no divergent state).

### Classic Queues (AP, but inconsistent)

Classic queues with mirrors use **asynchronous replication**. During a partition:
- The primary and mirror(s) may diverge
- On primary failure, a mirror promotes — but messages not yet replicated are **lost**
- Both sides continue accepting writes (AP) but with potential inconsistency

This is why classic mirrored queues are deprecated: they claim HA but actually deliver neither strong consistency nor data safety under partition. Use quorum queues.

---

## PACELC Analysis

| Scenario | Choice | RabbitMQ Behavior |
|---|---|---|
| **Partition, quorum queues** | Consistency | Minority nodes stop accepting writes; majority continues with full consistency |
| **No partition, quorum queues** | Latency | Raft adds ~2–5ms per write (follower round-trip); trade latency for consistency |
| **No partition, classic queues** | Latency | Writes to primary only; mirrors async; low latency, potential staleness |

RabbitMQ quorum queues: **PC/EC** — Consistency under partition; Consistency in normal operation (at higher latency than classic queues).

---

## Key Trade-offs Made in RabbitMQ's Design

| Design Decision | What You Get | What You Give Up |
|---|---|---|
| **Smart broker (exchange + binding routing)** | Complex routing without consumer logic; consumers are decoupled from publishers | Broker is a stateful dependency; routing changes require broker reconfiguration |
| **Push-based delivery** | Low consumer latency; broker controls pacing via prefetch | Consumer must handle backpressure; flow control is broker-driven |
| **Message deleted after ack** | Queue stays small; memory bounded; consumers are stateless | No replay; late-joining consumers cannot catch up |
| **Per-message acknowledgment** | Individual message lifecycle; retry/DLQ for failures | Higher protocol overhead than Kafka's offset commit |
| **Quorum queues (Raft)** | No data loss; strong consistency; safe leader failover | ~3–5x lower throughput than classic queues; requires ≥3 nodes |
| **Erlang/OTP process model** | Crash isolation; hot reload; millions of concurrent connections | Less tooling ecosystem than JVM; Erlang expertise required for deep debugging |
| **AMQP over TCP** | Rich protocol semantics; ack, nack, flow control | Higher overhead than Kafka's binary protocol; connections are stateful |
| **Exchange/binding topology** | Flexible routing; topology changes without consumer changes | Topology management is broker-side operational complexity |

---

## RabbitMQ vs Apache Kafka

This is the most important comparison in message system design. They are **complementary, not competing** — they solve different problems.

| Property | RabbitMQ | Apache Kafka |
|---|---|---|
| **Broker model** | Smart broker — routing, filtering, TTL, priority in broker | Dumb broker — sequential log; consumers own offset, filtering, routing |
| **Consumer model** | Push — broker delivers to consumer (within prefetch window) | Pull — consumer polls at its own pace |
| **Message retention** | Until acked (deleted after ack) | By time or size policy (independent of consumption) |
| **Replay** | Not supported (message gone after ack) | Supported — seek to offset or timestamp; reprocess historical events |
| **Multiple independent consumers** | Requires N queues (one per consumer group) | Native — consumer groups read independently at their own offsets |
| **Throughput** | 20K–50K persistent msg/sec per node | 1M+ msg/sec per node (sequential disk I/O optimised) |
| **Ordering** | FIFO within one queue, one consumer | Per-partition FIFO; guaranteed ordering across partitions within consumer group |
| **Message routing** | Exchange types (direct, fanout, topic, headers); complex topologies | Producers write to named topics; consumers subscribe to topics |
| **Message TTL** | Native (per-message or per-queue) | Via retention policy (all messages expire together) |
| **Priority queues** | Native (x-max-priority) | Not supported natively |
| **Dead letter** | Native (DLX configuration) | Via consumer-side logic or separate topic |
| **Request-reply / RPC** | Native (reply_to + correlation_id) | Not designed for this; requires manual implementation |
| **Clustering model** | Raft (quorum queues); classic mirrors (deprecated) | Replicated partitions; KRaft for metadata (Kafka 3.x) |
| **Protocol** | AMQP 0-9-1 (binary TCP) | Custom binary protocol over TCP |
| **Ecosystem** | MQTT, STOMP, AMQP 1.0 plugins | Kafka Connect, Kafka Streams, ksqlDB, Schema Registry |
| **Latency** | < 1ms per message | 5–15ms (batch-optimised; latency traded for throughput) |
| **Operational complexity** | Low–medium | High (ZooKeeper/KRaft, topic partitions, consumer group rebalancing) |

### When to Choose RabbitMQ over Kafka

- Complex routing (topic patterns, header-based filtering) that would be expensive to implement in every consumer
- Individual message retry / dead-lettering is a first-class requirement
- Request-reply / async RPC pattern
- Message TTL / expiry as a correctness requirement
- Moderate throughput (< 50K msg/sec) with rich broker semantics
- Task queues with competing consumers and fair dispatch

### When to Choose Kafka over RabbitMQ

- Event replay is required (audit logs, event sourcing, re-processing after bugs)
- Multiple independent services need to consume the same events
- Throughput > 100K msg/sec sustained
- Event streaming pipeline into Flink/Spark for stateful processing
- Long-term message retention (hours, days, weeks)
- Strict per-partition ordering at high throughput

### The Architectural Decision in One Sentence

> **Use RabbitMQ when the broker should make routing decisions. Use Kafka when consumers should control what they read and when.**

---

## RabbitMQ vs Amazon SQS / SNS

| Property | RabbitMQ | Amazon SQS | Amazon SNS |
|---|---|---|---|
| **Message model** | Exchange + Queue (rich routing) | Simple queue (point-to-point) | Topic (fan-out to subscribers) |
| **Delivery** | At-least-once (with acks) | At-least-once | At-least-once |
| **Ordering** | FIFO within queue | Best-effort (SQS Standard); FIFO queue available | No ordering |
| **Throughput** | 20K–50K msg/sec per node (self-hosted) | Virtually unlimited (managed) | Virtually unlimited |
| **Retention** | Until acked | 4 days (default); max 14 days | None (fire-and-forget) |
| **DLQ** | Native DLX | Native (MaxReceiveCount → DLQ) | Supported |
| **TTL** | Native (per-message or queue-level) | MessageRetentionPeriod (queue level) | Not applicable |
| **Complex routing** | Topic/Header exchanges | Not supported | Filter policies (basic attribute matching) |
| **RPC pattern** | Native (reply_to) | Not native (requires manual impl) | No |
| **Operational burden** | Self-hosted (low–medium) | Zero (fully managed) | Zero (fully managed) |
| **Cost model** | Fixed (EC2/hardware) | Pay-per-request ($0.40 per 1M requests) | Pay-per-notification |
| **Vendor lock-in** | None (open standard AMQP) | AWS-only | AWS-only |
| **Best for** | Self-hosted, complex routing, rich semantics | AWS-native, simple queuing, variable load | AWS-native, simple fan-out |

**When to prefer SQS**: You're AWS-native, need zero operational overhead, load is variable (pay-per-request scales to zero), and routing requirements are simple.

**When to prefer RabbitMQ**: You need self-hosted (on-prem, multi-cloud), complex exchange routing, MQTT support, or AMQP protocol semantics.

---

## RabbitMQ vs ActiveMQ

| Property | RabbitMQ | Apache ActiveMQ (Artemis) |
|---|---|---|
| **Protocol** | AMQP 0-9-1 (primary), MQTT, STOMP | AMQP 1.0, JMS, MQTT, STOMP, OpenWire |
| **Language** | Erlang | Java |
| **JMS support** | Via plugin | Native |
| **Performance** | Higher (Erlang process model) | Lower (JVM; lock contention at scale) |
| **Quorum / HA** | Quorum queues (Raft) | Master-slave with shared journal |
| **Community** | Larger, more active | Older; Artemis replaces classic ActiveMQ |
| **Ecosystem** | VMware/Pivotal backed | Apache foundation |
| **Best for** | Modern microservices, AMQP, Kubernetes | Java enterprise (JMS), legacy JEE apps |

**When to prefer ActiveMQ**: Legacy Java enterprise apps with JMS requirements; Spring JMS integration; JEE application servers.

---

## RabbitMQ vs NATS

| Property | RabbitMQ | NATS |
|---|---|---|
| **Model** | Persistent broker (messages stored until acked) | Default fire-and-forget; JetStream adds persistence |
| **Protocol** | AMQP (complex, binary) | Simple text-based (ultra lightweight) |
| **Durability** | Full persistence (quorum queues) | JetStream only |
| **Message routing** | Rich exchange/binding topology | Subject-based (wildcard subscriptions) |
| **Latency** | < 1ms | ~200µs (extremely low) |
| **Throughput** | 20K–50K persistent/sec | Millions of msg/sec (in-memory) |
| **Clustering** | Full cluster support | Cluster + leaf nodes |
| **Best for** | Enterprise messaging, task queues, microservices | Edge computing, IoT, low-latency pub/sub, service mesh |

**When to prefer NATS**: Sub-millisecond latency is critical, messages are ephemeral (IoT telemetry, real-time metrics), or you need an extremely lightweight footprint.

---

## Decision Flowchart

```
Do you need event replay or multiple independent consumers reading the same stream?
  YES → Apache Kafka (or RabbitMQ Stream queues for simpler cases)
  NO  ↓

Do you need complex broker-side routing (topic wildcards, header filtering, priority)?
  YES → RabbitMQ
  NO  ↓

Is throughput > 100K persistent messages/sec?
  YES → Apache Kafka
  NO  ↓

Is operational overhead unacceptable (no self-hosted)?
  YES → Amazon SQS (simple) or SNS+SQS (fan-out) if on AWS
  NO  ↓

Do you need JMS / Java EE integration?
  YES → ActiveMQ Artemis
  NO  ↓

Do you need sub-millisecond latency with minimal footprint?
  YES → NATS
  NO  → RabbitMQ
```

---

## Quorum Queues vs Classic Mirrored Queues

This is the intra-RabbitMQ trade-off that interviewers test:

| Property | Classic Mirrored (deprecated) | Quorum Queues (current standard) |
|---|---|---|
| **Consensus** | Async mirror sync (no consensus) | Raft (majority-based consensus) |
| **Data safety** | Can lose messages during failover (async lag) | No data loss if majority available |
| **Split-brain** | Possible — both sides accept writes | Impossible — minority stops writing |
| **Throughput** | Higher (~50K msg/sec) | Lower (~10K–30K msg/sec — Raft overhead) |
| **Min nodes** | 1 (plus optional mirrors) | 3 (for quorum of 2) |
| **Non-durable** | Supported | Not supported |
| **Exclusive** | Supported | Not supported |
| **Priority** | Supported | Not supported |
| **x-delivery-limit** | Not supported | Supported (max retry count) |
| **Status** | **Deprecated in 3.9** | **Recommended for all HA use cases** |

**Summary**: Quorum queues give you real HA at the cost of ~3x lower throughput and 3-node minimum. For any system where message loss is unacceptable, quorum queues are the only correct choice.

---

## FAANG Interview Callout

> "The RabbitMQ vs Kafka question is really about where routing intelligence lives. RabbitMQ is a smart broker — exchange topology, TTL, priority, and dead-lettering are broker-side features. Kafka is a dumb broker — it's just a replicated log; routing, filtering, and retry logic live in the consumer. The practical test: if you need event replay or multiple independent consumers reading the same messages, Kafka wins by design. If you need complex message routing, per-message TTL, or request-reply patterns, RabbitMQ wins. For quorum vs classic: always choose quorum queues in production — classic mirrored queues can silently lose messages during node failover due to async replication lag. Quorum queues use Raft, which guarantees no data loss as long as a majority of quorum members are available."

---

## Related Files

| File | Topic |
|---|---|
| [01-architecture.md](01-architecture.md) | How exchange routing and queue types create the properties discussed here |
| [02-read-write-path.md](02-read-write-path.md) | How publisher confirms and acks implement the delivery guarantees |
| [04-tuning-guide.md](04-tuning-guide.md) | How to tune for the trade-offs chosen here |
