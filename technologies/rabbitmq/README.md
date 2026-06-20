# RabbitMQ — Overview & Decision Guide

**Type**: General-purpose Message Broker (AMQP)
**Protocol**: AMQP 0-9-1 (default), AMQP 1.0, MQTT 3.1.1, STOMP
**CAP Position**: Quorum queues — **CP** (Raft majority); Classic queues — **AP** (async mirror)
**Delivery Guarantee**: At-least-once (publisher confirms + consumer acks); at-most-once (autoAck)
**Message Model**: Smart Broker — routing, filtering, priority, and TTL live inside the broker
**Origin**: Rabbit Technologies Ltd (2007); acquired by SpringSource → Pivotal → VMware; open-source (MPL 2.0)

---

## What Is RabbitMQ?

RabbitMQ is a **general-purpose message broker** built on Erlang/OTP. It implements the AMQP 0-9-1 specification and extends it with publisher confirms, dead-letter exchanges, priority queues, quorum queues, and stream queues.

The core model: producers publish messages to **exchanges**, exchanges route messages to **queues** via **bindings**, consumers receive messages pushed by the broker. Producers never address queues directly — they publish to an exchange and the exchange decides which queues receive the message.

The defining architectural principle is the **smart broker**: routing decisions, message filtering, priority, TTL, dead-lettering, and flow control all live in the broker. This contrasts with Kafka's **dumb broker / smart consumer** model, where the broker is a replicated log and consumers control their own offsets and replay. The choice between them hinges on where routing complexity should live.

**Erlang/OTP foundation**: RabbitMQ inherits Erlang's "let it crash" supervision model — if a connection handler process crashes, its supervisor restarts it in isolation without affecting other connections. This is the same runtime WhatsApp used to serve 900M users with 50 engineers.

---

## Quick-Reference Card

| Property | Value |
|---|---|
| Protocol | AMQP 0-9-1 (default), AMQP 1.0, MQTT 3.1.1, STOMP |
| CAP position | Quorum queues: **CP** (Raft); Classic queues: **AP** (async mirror) |
| Delivery guarantee | At-least-once (confirms + acks); at-most-once (autoAck) |
| Message ordering | FIFO within queue (single consumer); not guaranteed with multiple consumers |
| Throughput (persistent) | 20K–50K msg/sec per node (single node) |
| Throughput (quorum) | 10K–30K msg/sec (Raft consensus overhead) |
| Throughput (transient) | 100K–200K msg/sec per node |
| Latency (p50) | < 1ms single node; < 5ms quorum cluster |
| Latency (p99) | 1–5ms single node; 5–20ms quorum cluster |
| Optimal message size | < 128KB; store large payloads externally |
| Memory alarm threshold | 40% of system RAM (triggers flow control) |
| Disk alarm threshold | 50MB free (default; raise to 1–2GB in production) |
| Default AMQP port | 5672; TLS: 5671 |
| Management UI port | 15672 |
| Erlang distribution port | 25672 (cluster inter-node) |
| Max channels per connection | 2,047 |

---

## Decision Drivers: When to Choose RabbitMQ

**Choose RabbitMQ when ALL of the following apply:**

1. **Complex routing is required** — messages must be routed to different queues based on routing keys, topic patterns, or message headers; this logic belongs in the broker, not in every consumer
2. **Individual message acknowledgment matters** — each message has its own lifecycle (delivered, acked, nacked, dead-lettered); you cannot afford silent message loss
3. **Task queues / worker pools** — distribute work across competing consumers; failed tasks should retry or land in a dead-letter queue
4. **Diverse message types with different subscribers** — a single event triggers different actions in different services; topic exchanges route by `order.#` or `payment.completed`
5. **Moderate throughput with rich semantics** — you need broker-side TTL, priority, retry, or RPC patterns, and peak throughput is < 50K persistent msg/sec per node

**The single most important question:** *Does routing complexity belong in the broker?* If yes — RabbitMQ. If your consumers should control what they read and when they replay — Kafka.

---

## Use Cases

| Use Case | Why RabbitMQ Fits | Pattern |
|---|---|---|
| **Background job / task queue** | Competing consumers, at-least-once delivery, DLQ for failed jobs | Direct exchange → work queue → N workers |
| **Microservice event bus** | Route domain events to interested services by topic pattern | Topic exchange (`order.#`, `payment.completed`) |
| **Notification fan-out** | One event → email queue + SMS queue + push queue simultaneously | Fanout exchange → 3 queues |
| **Async RPC / request-reply** | Service sends request, waits on reply queue; broker routes reply by `correlation_id` | `reply_to` + `correlation_id` pattern |
| **Priority job scheduling** | High-priority tasks preempt low-priority in the same queue | `x-max-priority` queue (1–255) |
| **Retry with exponential backoff** | Failed messages route to TTL delay queue, re-enqueue after delay | DLX → wait queue (TTL) → original queue |
| **IoT device commands** | Lightweight MQTT clients; broker routes to service queues | MQTT plugin + topic exchange |
| **Saga choreography** | Services publish domain events; each service subscribes to events it cares about | Topic exchanges per domain bounded context |

---

## Anti-Patterns: When NOT to Use RabbitMQ

| Situation | Better Alternative |
|---|---|
| **Sustained throughput > 100K persistent msg/sec** | Apache Kafka — purpose-built for this |
| **Event replay / audit log** | Kafka — consumer offset enables replay; RabbitMQ deletes messages after ack |
| **Multiple independent consumers reading the same messages** | Kafka consumer groups; in RabbitMQ each consumer group needs its own queue |
| **Long-term message retention (hours → days → weeks)** | Kafka with retention policy; deep RabbitMQ queues cause memory pressure and flow control |
| **Stateful stream processing** | Kafka + Flink or Kafka Streams |
| **Messages > 1MB** | Store payload in S3/blob; put reference URL in the queue message |
| **Strictly ordered delivery across multiple consumers** | Kafka partitions guarantee per-partition order per consumer group |

---

## Key Numbers (Production Scale)

| Metric | Single Node | 3-Node Quorum Cluster |
|---|---|---|
| Persistent msg throughput | 20K–50K msg/sec | 10K–30K msg/sec |
| Transient msg throughput | 100K–200K msg/sec | ~60K–100K msg/sec |
| p50 latency | < 1ms | < 5ms |
| p99 latency | 1–5ms | 5–20ms |
| Memory threshold (flow control) | 40% of RAM | same |
| Disk threshold (alarm) | 50MB free (raise to 1GB) | same |
| Max recommended queue depth | < 1M messages | < 1M per queue |
| Channel overhead | ~2KB RAM per channel | same |
| Connection overhead | ~100KB RAM per connection | same |

---

## File Map

| File | What's Inside |
|---|---|
| [01-architecture.md](01-architecture.md) | Erlang/OTP, AMQP components, exchange types, queue types (Classic/Quorum/Stream), clustering |
| [02-read-write-path.md](02-read-write-path.md) | Publish path, publisher confirms, consumer delivery, ack/nack/reject, prefetch, flow control, DLX |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | CAP analysis, quorum vs classic, RabbitMQ vs Kafka / ActiveMQ / SQS, decision flowchart |
| [04-tuning-guide.md](04-tuning-guide.md) | Key parameters, prefetch tuning, memory/disk, monitoring metrics, anti-patterns |
| [05-production-and-research.md](05-production-and-research.md) | AMQP history, Erlang/OTP foundations, companies using RabbitMQ, operational lessons, FAANG framing |

---

## FAANG Interview Callout (30-second version)

> "I'd reach for RabbitMQ when routing logic belongs in the broker — complex fan-out, topic pattern routing, header-based filtering — and when individual message acknowledgment is critical. The model is Exchange → Binding → Queue: producers publish to exchanges and never address queues directly. The key trade-off versus Kafka is that RabbitMQ deletes messages after consumption — no replay. If you need multiple independent consumers reading the same stream, or event sourcing, Kafka is the answer. RabbitMQ's strength is task queues and microservice choreography where the broker carries routing complexity, TTL, and at-least-once delivery semantics."
