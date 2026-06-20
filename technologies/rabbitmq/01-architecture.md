# RabbitMQ — Architecture

## Erlang/OTP Foundation

RabbitMQ is written in Erlang and runs on the BEAM virtual machine (OTP platform). This is not an implementation detail — it is the reason RabbitMQ is operationally reliable at scale.

| Erlang/OTP Property | Impact on RabbitMQ |
|---|---|
| **Lightweight processes** (~2KB each) | Each connection and channel is an isolated Erlang process; millions can run concurrently |
| **"Let it crash" + supervision trees** | If a connection handler crashes, its supervisor restarts it; other connections are unaffected |
| **Hot code loading** | Broker can be upgraded without stopping (connection-level granularity) |
| **Message-passing concurrency** | No shared memory between processes; no global locks on the connection handling path |
| **Soft real-time scheduling** | BEAM scheduler pre-empts long-running reductions; no single process can starve others |
| **Built-in distribution** | Erlang nodes communicate natively; RabbitMQ clustering is built on Erlang distribution |

The same runtime powers Ericsson's telecom switches (nine 9s of availability) and WhatsApp (900M users, 50 engineers).

---

## AMQP 0-9-1 Protocol: Core Concepts

AMQP 0-9-1 (Advanced Message Queuing Protocol) is a binary, wire-level protocol. Every interaction between a client and RabbitMQ is a sequence of **frames** over a **channel** over a **connection**.

### Connection vs Channel

```
Client Process
│
TCP Connection (one per client application; ~100KB RAM)
│
├── Channel 1 (one per thread/goroutine; ~2KB RAM)
│     ├── Exchange declare
│     ├── Queue declare / bind
│     ├── Basic.Publish (message in)
│     └── Basic.Consume (message out)
│
├── Channel 2
└── Channel N (max 2,047 per connection)
```

**Rule**: One channel per thread. Never share channels between threads — channels are not thread-safe. Connections are expensive (TCP + TLS handshake); channels are cheap. Use one long-lived connection per process, one channel per concurrent operation.

### Frame Types

| Frame Type | Purpose |
|---|---|
| **Method frame** | AMQP command (declare exchange, publish, ack) |
| **Header frame** | Message properties (content-type, delivery-mode, priority, TTL) |
| **Body frame** | Message payload (can be split across multiple body frames if > frame_max) |
| **Heartbeat frame** | Keep-alive signal to detect stale connections |

---

## Core Components

### The AMQP Topology

```
                                    ┌─────────────────────────────────┐
                                    │           RabbitMQ Broker        │
[Producer]──Basic.Publish──────────►│                                  │
           (exchange + routing key) │  [Exchange]──binding──►[Queue A] │──►[Consumer 1]
                                    │       │                           │
                                    │       └────────►[Queue B]         │──►[Consumer 2]
                                    │                                  │
                                    └─────────────────────────────────┘
```

| Component | Role |
|---|---|
| **Producer** | Publishes messages to an exchange. Never publishes directly to a queue. |
| **Exchange** | Receives messages from producers, routes them to queues based on type and bindings |
| **Binding** | A rule associating an exchange with a queue (plus optional routing key or arguments) |
| **Queue** | Buffer that stores messages until a consumer pulls them |
| **Consumer** | Subscribes to a queue; broker pushes messages via `Basic.Deliver` |
| **Virtual Host (vhost)** | Logical namespace; isolates exchanges, queues, users within one broker |
| **Message** | Payload (bytes) + properties (headers, delivery_mode, priority, TTL, correlation_id) |

### Key Message Properties

| Property | Type | Purpose |
|---|---|---|
| `delivery_mode` | 1 or 2 | 1 = transient (in-memory only); 2 = persistent (written to disk) |
| `content_type` | string | MIME type of payload (e.g., `application/json`) |
| `priority` | 0–255 | Message priority (queue must be declared with `x-max-priority`) |
| `expiration` | ms string | Per-message TTL; broker discards after this many ms |
| `correlation_id` | string | Used in RPC patterns to match reply to request |
| `reply_to` | string | Queue name where the consumer should send the reply |
| `message_id` | string | Application-assigned unique ID (idempotency key) |
| `headers` | table | Arbitrary key-value pairs used by headers exchange routing |

---

## Exchange Types

### 1. Direct Exchange

Routes messages to queues whose binding key **exactly matches** the routing key.

```
                  routing_key = "error"
[Producer] ──────────────────────────────► [Direct Exchange]
                                                    │
                                binding key="error" ├──────► [error-queue] ──► [Error Logger]
                                binding key="info"  └──────► [info-queue]  ──► [Info Logger]
                                                    (no match = message dropped or returned)
```

**Use case**: Task routing by type (e.g., `order.created`, `payment.failed`), log severity levels.

```python
# Publisher
channel.basic_publish(exchange='logs', routing_key='error', body=message)

# Consumer binding
channel.queue_bind(queue='error-queue', exchange='logs', routing_key='error')
```

---

### 2. Fanout Exchange

Routes messages to **all bound queues** regardless of routing key. The routing key is ignored.

```
                  routing_key = (ignored)
[Producer] ──────────────────────────────► [Fanout Exchange]
                                                    │
                                                    ├──────► [email-queue]  ──► [Email Service]
                                                    ├──────► [sms-queue]    ──► [SMS Service]
                                                    └──────► [push-queue]   ──► [Push Service]
```

**Use case**: Broadcast events to all subscribers — notification systems, cache invalidation, distributed config refresh.

**Critical nuance**: Fanout delivers a *copy* of the message to each bound queue. If a queue is not yet bound at publish time, that consumer never sees the historical message (no replay).

---

### 3. Topic Exchange

Routes messages to queues based on **wildcard pattern matching** of the routing key (dot-separated words).

```
Wildcards:
  *  = exactly one word
  #  = zero or more words

Routing key examples:
  "order.created"          → matches "order.*", "order.#", "#"
  "order.payment.failed"   → matches "order.#", "*.payment.*", "#"
  "user.profile.updated"   → matches "user.#", "*.*.updated"

[Producer] ─── routing_key="order.payment.failed" ───► [Topic Exchange]
                                                                │
                            binding="order.#"                  ├──► [order-service-queue]
                            binding="*.payment.*"              ├──► [payment-audit-queue]
                            binding="#"                        └──► [all-events-queue]
```

**Use case**: Microservice event bus — each service subscribes to the event patterns it cares about. Most flexible exchange type.

---

### 4. Headers Exchange

Routes messages based on **message header values** instead of routing key. The binding specifies required header key-value pairs.

```
Message headers: { "format": "pdf", "type": "report" }

Binding A: { "format": "pdf", "x-match": "all" }   → requires ALL headers to match
Binding B: { "format": "pdf", "x-match": "any" }   → requires ANY header to match
Binding C: { "type": "urgent", "x-match": "any" }  → matches if "type"="urgent" OR "format"="pdf"
```

**Use case**: Route by content type, format, or any business attribute not expressible as a routing key. Rare in practice; topic exchange handles most cases more simply.

---

### Default (Nameless) Exchange

Every broker has a built-in default direct exchange (`""`) pre-bound to every queue with the queue's name as routing key. This allows publishing directly to a queue by name without declaring an explicit exchange.

```python
channel.basic_publish(exchange='', routing_key='my-queue', body=message)
# message routes to the queue named "my-queue" via the default exchange
```

---

## Queue Types

### Classic Queues (Legacy)

The original queue type. In a cluster, a classic queue exists on **one primary node**; optional **mirrors** (async replicas) can be configured via policies. Mirrors sync asynchronously, which means:
- If the primary crashes before a mirror is fully synced, **messages can be lost**
- Mirror promotion involves potential gaps

**Status**: Deprecated as of RabbitMQ 3.9 for HA use cases. **Use quorum queues for all new production deployments.**

---

### Quorum Queues (Current Production Standard)

Introduced in RabbitMQ 3.8. Replaces classic mirrored queues.

```
                          ┌─────────────┐
                          │  Leader     │◄── All reads and writes
                          │  (Node 1)   │
                          └──────┬──────┘
                                 │ Raft replication
                    ┌────────────┴────────────┐
                    ▼                         ▼
             ┌─────────────┐          ┌─────────────┐
             │  Follower   │          │  Follower   │
             │  (Node 2)   │          │  (Node 3)   │
             └─────────────┘          └─────────────┘

  Write ACK returned to producer only after majority (≥ 2/3) confirm persistence
```

**How Raft works here**: The leader replicates each message to followers. A write is confirmed only after a quorum (majority) of nodes acknowledge it. This guarantees no data loss as long as a majority of quorum members are available.

| Property | Value |
|---|---|
| Consensus | Raft (leader + followers) |
| Minimum nodes | 3 (quorum of 2) |
| Write path | Leader only |
| Read path | Leader only (no stale reads) |
| Failure tolerance | Can lose `(N-1)/2` nodes (1 of 3; 2 of 5) |
| Durable | Always (cannot be non-durable) |
| Exclusive | Not supported |
| Performance | ~10K–30K msg/sec (Raft overhead vs classic's ~50K) |

**Limitations**: Cannot be non-durable or exclusive; `x-max-priority` not supported; slightly higher latency.

---

### Stream Queues (RabbitMQ 3.9+)

An append-only log (similar to Kafka topics) implemented as a native RabbitMQ queue type.

```
[Producer] ──► [Stream Queue: events] ──► offset 0: {msg A}
                                         offset 1: {msg B}
                                         offset 2: {msg C}
                                                │
                               ┌───────────────┼──────────────────┐
                               ▼               ▼                  ▼
                     [Consumer Group A]  [Consumer Group B]  [Consumer Group C]
                     reads from offset 0 reads from offset 2 reads from offset 0
                     (independent cursors)
```

| Property | Quorum Queue | Stream Queue |
|---|---|---|
| Message deletion | After consumer ack | By retention policy (size or time) |
| Multiple consumers | Competing (one gets each message) | Independent (each reads all messages) |
| Replay | No | Yes (seek to offset or timestamp) |
| Ordering | FIFO | Per-stream FIFO |
| Use case | Task queue, RPC, fan-out to distinct queues | Event log, audit trail, fan-out to same data |

**When to use stream queues**: Fan-out to many consumers that each need all messages (previously required N queues); event sourcing within RabbitMQ; simple replay without migrating to Kafka.

---

## Clustering Architecture

RabbitMQ cluster: multiple nodes sharing exchange/binding/vhost metadata, with queues on specific nodes.

```
                          ┌─────────────────────────────────────────────┐
                          │              RabbitMQ Cluster               │
                          │                                             │
                          │  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
                          │  │  Node 1  │  │  Node 2  │  │  Node 3  │ │
 [Producer]──────────────►│  │          │  │          │  │          │ │
                          │  │ Exchange │  │ Exchange │  │ Exchange │ │
                          │  │ (shared  │  │ (shared  │  │ (shared  │ │
                          │  │ metadata)│  │ metadata)│  │ metadata)│ │
                          │  │          │  │          │  │          │ │
                          │  │ Queue A  │◄─┤ Queue A  │◄─┤ Queue A  │ │ ← Quorum queue
                          │  │ (leader) │  │ (follwr) │  │ (follwr) │ │
                          │  │          │  │          │  │          │ │
                          │  │ Queue B  │  │ Queue B  │  │          │ │ ← Classic queue
                          │  │ (primary)│  │ (mirror) │  │          │ │
                          │  └──────────┘  └──────────┘  └──────────┘ │
 [Consumer A]────────────►│      ▲                                     │
 [Consumer B]────────────►│      │(consumer connects to any node;      │
                          │       broker routes to queue's leader)      │
                          └─────────────────────────────────────────────┘
```

**Key clustering facts**:
- All nodes share exchange/binding/vhost/user metadata (replicated via Mnesia)
- Queue data is on specific node(s) — not shared across all nodes unless quorum/stream
- A consumer can connect to any node; the broker transparently proxies to the queue's leader
- Cluster uses Erlang distribution protocol (port 25672); nodes must resolve each other's hostnames
- `rabbitmq-plugins enable rabbitmq_federation` enables cross-cluster message routing (federation/shovel)

### Node Types

| Node Type | RAM Usage | Disk Usage | Use Case |
|---|---|---|---|
| **Disc node** (default) | Normal | Writes all metadata + messages to disk | Standard — use for all production nodes |
| **RAM node** | Higher (all metadata in RAM) | No metadata on disk | Avoid — only useful for very large clusters with massive exchange churn |

**Rule**: All production nodes should be disc nodes. A RAM-only cluster loses all metadata on full restart.

---

## Message Lifecycle

```
[Producer]
    │
    ├─ Basic.Publish ──► [Exchange]
    │                         │
    │                   (routing logic)
    │                         │
    │                    [Queue]
    │                         │
    │                    ┌────┴────────────────┐
    │                    │  Message States      │
    │                    │  ┌───────────────┐  │
    │                    │  │    Ready      │  │ ← Waiting for consumer
    │                    │  └──────┬────────┘  │
    │                    │         │ Basic.Deliver
    │                    │  ┌──────▼────────┐  │
    │                    │  │   Unacked     │  │ ← Delivered, waiting for ack
    │                    │  └──────┬────────┘  │
    │                    │         │ Basic.Ack / Nack / Reject
    │                    └─────────┼────────────┘
    │                              │
    │              ┌───────────────┼──────────────────┐
    │              ▼               ▼                  ▼
    │           [Acked]       [Requeued]         [Dead-lettered]
    │         (deleted)     (back to Ready)   (→ Dead Letter Exchange)
```

---

## FAANG Interview Callout

> "Know the four exchange types cold — interviewers test them. Direct = exact routing key match; Fanout = broadcast to all bound queues; Topic = wildcard pattern match (`*` = one word, `#` = zero or more); Headers = route by message header key-value pairs. The critical insight: producers never address queues directly — they publish to exchanges. This decouples producers from consumers; you can add new queues/consumers without changing the producer. For HA, the answer today is always quorum queues — they use Raft consensus to guarantee no data loss as long as a majority of replicas are alive. Classic mirrored queues are deprecated and can lose messages during failover."

---

## Related Files

| File | Topic |
|---|---|
| [02-read-write-path.md](02-read-write-path.md) | What happens inside the broker when a message is published and consumed |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Quorum vs classic, RabbitMQ vs Kafka |
| [04-tuning-guide.md](04-tuning-guide.md) | How to tune exchange/queue settings for production |
