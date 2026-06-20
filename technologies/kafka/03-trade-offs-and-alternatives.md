# Kafka — Trade-offs and Alternatives

## PACELC Analysis

Kafka is an **AP** system under the CAP theorem, but PACELC gives more nuance:

```
PACELC: If Partition → choose Availability or Consistency
                       During normal operation → choose Latency or Consistency

Kafka:
  P → A: During a partition, Kafka continues accepting writes to the available leader.
          If `unclean.leader.election.enable=false` (default), Kafka will wait for an ISR member
          to be available rather than elect a lagging replica — this can mean unavailability
          rather than data loss.

  E → L: In normal operation, Kafka optimises for latency. With acks=1, acknowledgement is
          immediate from the leader. With acks=all, there's a replication latency (~1–5ms).

Consistency guarantee: within a partition, records are totally ordered. Consumers with
committed offsets will never see a record disappear (no rollback). But there is no
cross-partition ordering guarantee.
```

---

## Exactly-Once Semantics: Comparison

| Guarantee | Mechanism | Trade-off |
|-----------|-----------|-----------|
| **At-most-once** | `acks=0` or no retry | Fastest; data loss possible on broker failure |
| **At-least-once** | `acks=all` + retries | Default; duplicates on retry without idempotence |
| **Exactly-once (producer-broker)** | `enable.idempotence=true` | Deduplicates retries within a session; PID resets on restart |
| **Exactly-once (end-to-end)** | Idempotent producer + transactions + `isolation.level=read_committed` | Full EOS; ~20% throughput overhead; required for financial, billing, counting |

---

## Kafka vs Alternatives

### Kafka vs RabbitMQ

| Dimension | Kafka | RabbitMQ |
|-----------|-------|----------|
| **Model** | Durable log; consumer pulls by offset | Message queue; broker pushes to consumer; message deleted after ack |
| **Retention** | Configurable (days/weeks/forever) | Until consumed (or DLX/TTL) |
| **Replayability** | Yes — any consumer can re-read from offset 0 | No — consumed messages are gone |
| **Multiple consumers** | Same topic readable by unlimited independent consumer groups | Each queue has one consumer (fan-out requires exchange → multiple queues) |
| **Throughput** | Millions of msg/sec; GB/s via sequential I/O | Hundreds of thousands msg/sec; lower throughput at scale |
| **Ordering** | Strict within partition; choose partition key for per-entity ordering | Per-queue FIFO; not guaranteed across multiple consumers |
| **Routing** | Partition key hash; no content-based routing | Rich exchange types: direct, topic, fanout, headers |
| **Dead-letter / retry** | Manual (produce to DLT topic); limited native DLQ support | Native DLX/DLQ with TTL, routing, backoff |
| **Operations** | Complex (ZK/KRaft, partition management, lag monitoring) | Simpler (single binary, management UI out of the box) |
| **Best for** | Event streaming, CDC, data pipeline, high-throughput fanout | Task queues, work distribution, RPC-over-MQ, complex routing |

**Decision rule**: If you need replay, multi-consumer fanout, or > 100K msg/sec → Kafka. If you need simple task queuing, dead-letter routing, or RPC patterns → RabbitMQ.

---

### Kafka vs Apache Pulsar

| Dimension | Kafka | Pulsar |
|-----------|-------|--------|
| **Storage architecture** | Broker stores segment files on local disk | Separated: brokers are stateless; Apache BookKeeper stores data |
| **Scaling** | Scale = add brokers (storage + compute coupled) | Scale brokers (compute) and BookKeeper (storage) independently |
| **Multi-tenancy** | Topics; namespace-level ACLs | Native: tenants → namespaces → topics with quotas per tenant |
| **Geo-replication** | MirrorMaker 2 (separate tool, complex) | Built-in async geo-replication |
| **Consumer model** | Pull (offset-based) | Flexible: exclusive, shared, failover, key_shared subscription types |
| **Exactly-once** | Supported (transactions) | Supported (similar mechanism) |
| **Maturity** | Very mature; massive ecosystem (Kafka Streams, Kafka Connect, ksqlDB) | Younger; growing but smaller ecosystem |
| **Operational overhead** | High (Kafka + ZK/KRaft) | Higher (Kafka + BookKeeper + ZooKeeper) |
| **Tiered storage** | Available (Confluent, MSK Tiered Storage, Kafka 3.6+) | Built-in |
| **Best for** | Most use cases; large ecosystem | Multi-tenant SaaS; independent storage/compute scaling; complex subscription models |

**Decision rule**: Kafka for most production deployments due to maturity and ecosystem. Pulsar for greenfield multi-tenant platforms or when independent storage/compute scaling is critical.

---

### Kafka vs Amazon Kinesis

| Dimension | Kafka | Kinesis |
|-----------|-------|---------|
| **Hosting** | Self-managed or Confluent/MSK (managed) | Fully managed AWS service |
| **Shard / Partition** | Partition count configurable (up to millions with KRaft) | Shard (up to 500 shards/stream, 10K records/sec/shard by default) |
| **Retention** | Up to indefinite (tiered storage) | 1–365 days (Enhanced Fan-out: 7 days default) |
| **Throughput per shard/partition** | ~10–50 MB/s per partition | 1 MB/s in, 2 MB/s out per shard |
| **Latency** | Sub-10ms | ~70ms (standard), ~70ms (enhanced fan-out) |
| **Consumer model** | Pull (offset) | Pull (GetRecords) or Enhanced Fan-Out (push, lower latency) |
| **Exactly-once** | Supported | Not natively; at-least-once |
| **Ecosystem** | Kafka Connect (1000+ connectors), Kafka Streams, ksqlDB, Flink, Spark | AWS Lambda, Kinesis Data Analytics (Flink), Firehose |
| **Cost** | Infrastructure cost (self) or MSK cost | Per-shard-hour + data transfer; can be expensive at high scale |
| **Best for** | On-prem or multi-cloud; cost-sensitive high volume; rich ecosystem | AWS-native, low ops overhead, moderate throughput |

---

### Kafka vs Redis Pub/Sub / Redis Streams

| Dimension | Kafka | Redis Pub/Sub | Redis Streams |
|-----------|-------|---------------|---------------|
| **Durability** | Durable (configurable) | Not durable — fire and forget | Durable (AOF/RDB) |
| **Retention** | Days to forever | No retention — missed if not connected | Configurable (MAXLEN) |
| **Consumer groups** | Yes (full group semantics) | No — all subscribers get all messages | Yes (consumer groups since Redis 5.0) |
| **Throughput** | GB/s | Very high (in-memory) | Very high (in-memory) |
| **Scale** | Petabytes | Limited by RAM | Limited by RAM |
| **Best for** | Durable event streaming | Ephemeral notifications (cache invalidation, live chat) | Lightweight event streaming for moderate scale |

---

## When to Choose What: Decision Tree

```
Need to persist events and replay them later?
  ├─ YES → Need high throughput (> 100K msg/sec) or multi-consumer fanout?
  │         ├─ YES → Kafka (or Pulsar for multi-tenant SaaS)
  │         └─ NO  → Redis Streams (simpler ops, lower volume)
  │
  └─ NO (task queue / work distribution)?
      ├─ Need complex routing (DLX, priority, header matching)?
      │   └─ RabbitMQ
      ├─ AWS-native, low ops?
      │   └─ SQS (simple queue) or Kinesis (streaming)
      └─ Need pub/sub with ephemeral delivery?
          └─ Redis Pub/Sub or SNS
```

---

## Common Trade-offs in System Design Interviews

### Trade-off 1: Kafka as Event Store vs Dedicated Event Store

| Approach | Pros | Cons |
|----------|------|------|
| **Kafka as event store** (EventSourcing via Kafka) | No additional infra; producers already writing to Kafka | Retention is time-based not count-based; no efficient random offset access by event ID; compaction loses intermediate states |
| **EventStoreDB / custom event store** | Purpose-built: event ID indexing, projection support, stream-level versioning | Additional service to manage; replication complexity |

**Recommendation**: Use Kafka for high-volume event streaming where time-window retention is acceptable. Use EventStoreDB or a custom event store where you need event ID lookups, projections, or strong stream versioning (aggregate-level).

### Trade-off 2: Partition Count — Too Few vs Too Many

| Too Few Partitions | Too Many Partitions |
|--------------------|---------------------|
| Limits consumer parallelism | Slower leader election (more partitions to reassign) |
| Single partition bottleneck | Higher memory per broker (open file handles) |
| Can't scale reads beyond partition count | Rebalance takes longer (more partitions to redistribute) |
| **Fix**: increase partitions (but can't decrease) | **Fix**: Don't over-partition; start with 10–50, scale up |

**Rule of thumb**: `numPartitions = max(desiredThroughputMBps / 10, maxConcurrentConsumers)`

### Trade-off 3: `acks=all` + `min.insync.replicas=2` vs `acks=1`

| `acks=all`, `min.insync.replicas=2` | `acks=1` |
|-------------------------------------|----------|
| No data loss: acknowledged writes survive 1 broker failure | ~5–20% higher throughput |
| Latency: leader waits for 1 follower (~1–5ms extra) | Risk: leader failure before replication = data loss |
| Write blocked if only 1 ISR member alive | Continues writing even with degraded ISR |
| **Use for**: financial events, orders, billing | **Use for**: metrics, logs, analytics (tolerable loss) |

---

## FAANG Interview Callout

> "The core trade-off in Kafka is that ordering is per-partition, not global. This is by design — you trade global ordering for horizontal scale. In practice, I choose a partition key that gives me the ordering semantics I need: for an order event stream, I partition by orderId so all events for a given order are ordered. The biggest architectural decision is `acks=all` vs `acks=1` — for any data that matters financially or operationally, I always use `acks=all` with `min.insync.replicas=2`. The ~5ms extra latency is irrelevant compared to the operational risk of data loss. Compared to RabbitMQ, the key difference is replayability: Kafka's log survives consumption, so a new analytics service can read the full history. In RabbitMQ, consumed messages are gone."
