# Kafka Streams — Overview & Decision Guide

**Type**: Embedded stream processing library (Java/Scala)  
**Deployment Model**: Runs inside your application — no separate cluster required  
**Processing Model**: True streaming (event-by-event); not micro-batch  
**State Model**: Local RocksDB state store backed by Kafka changelog topic  
**Exactly-Once**: Via Kafka transactions (atomic offset commit + state changelog write + output produce)  
**Origin**: Confluent / Apache Kafka project (2016, Kafka 0.10.0)

---

## What Is Kafka Streams?

Kafka Streams is a **client library** that turns a regular Java or Scala application into a stateful stream processor. Unlike Flink or Spark Streaming, there is no separate cluster to deploy, no cluster manager to configure, and no resource scheduler to learn. You add a dependency, write a topology (a DAG of stream transformations), and deploy it like any other microservice.

The central insight: **Kafka itself is the coordination layer**. Consumer group rebalancing assigns Kafka partitions to instances; state stores use Kafka changelog topics for durability; exactly-once uses Kafka transactions. Kafka Streams borrows all of Kafka's infrastructure and adds stream processing semantics on top.

Key capabilities:
- **Stateful processing**: per-key `KeyValueStore` (backed by RocksDB locally + Kafka changelog for durability)
- **Stream-Table duality**: any stream can be viewed as a table (latest value per key); any table can be viewed as a changelog stream
- **KTable**: a partitioned, materialized view of a stream (compacted changelog)
- **Joins**: KStream-KStream (windowed), KStream-KTable (enrichment), KTable-KTable
- **Windowing**: tumbling, hopping, session windows on event time
- **Interactive queries**: query local state stores from outside the application (via REST)

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| Deployment | JAR dependency + your application; no external cluster |
| Scaling | Add application instances; Kafka rebalances partition assignments |
| State | RocksDB (local, off-heap) + Kafka changelog topic (remote backup) |
| Exactly-once | `processing.guarantee=exactly_once_v2` (Kafka 2.5+) |
| Fault tolerance | Standby replicas + state store restore from changelog |
| Ordering | Per-partition ordering (same as Kafka) |
| Latency | Sub-millisecond per record; end-to-end ~5–50ms |
| Throughput | 100K–5M records/sec per instance |
| Time semantics | Event time (record timestamp), processing time |
| Language | Java, Scala (no Python native library — use Flink or Faust) |

---

## Decision Drivers: When to Choose Kafka Streams

**Choose Kafka Streams when ALL of the following are true:**

1. **Already using Kafka** — your data is in Kafka topics; you want to process it without pulling data out
2. **Per-microservice stream logic** — the processing is owned by a single service team and fits within one deployable unit
3. **Low operational overhead** — you want stream processing without a separate cluster (no Flink cluster, no YARN/K8s resource manager)
4. **Moderate throughput** — millions of records/sec across multiple instances is fine; you don't need petabyte-scale distributed joins
5. **JVM shop** — your team writes Java or Scala; Kafka Streams has no Python native equivalent

**The single most important question**: *Does the stream processing logic belong to a single microservice, or does it span services?* If single service → Kafka Streams. If cross-service, cross-team, or shared infrastructure → Flink.

---

## Use Cases

| Use Case | Why Kafka Streams Fits | Example |
|----------|----------------------|---------|
| **Event enrichment** | Join event stream with a reference KTable (user profile, product catalog) per-key | Order service joins order events with customer KTable |
| **Real-time aggregation** | Count, sum, average per key in a tumbling window | Metrics service: request count per endpoint per minute |
| **CDC to projection** | Debezium CDC stream → KTable as live in-memory view of a DB table | Search service maintains live index of product data |
| **Session tracking** | Session window per userId to detect active sessions | Analytics service: session duration, pages per session |
| **Filtering / routing** | Route events to different output topics based on content | Payment service: route successful vs failed payments to different topics |
| **State machine** | Track per-entity state (order: pending → confirmed → shipped) | Order lifecycle service |
| **Deduplication** | Use a KV store to track seen event IDs (with TTL) | Idempotent event processor |

---

## Anti-Patterns: When NOT to Use Kafka Streams

| Situation | Better Alternative |
|-----------|-------------------|
| **Cross-service pipelines** | Flink (separate cluster, owned by a platform team) |
| **Very large state** (> available disk on app instances) | Flink with RocksDB on dedicated TaskManagers |
| **Complex multi-stream joins** at scale | Flink (richer join semantics, better resource isolation) |
| **Python/non-JVM teams** | Faust (Python), Flink PyFlink, or ksqlDB |
| **Ad-hoc queries on streams** | ksqlDB (interactive SQL), Apache Druid |
| **Non-Kafka source/sink** | Flink (broad connector ecosystem) |
| **Millisecond SLA with massive state** | Flink (dedicated cluster; tuned resource isolation) |

---

## Key Numbers

| Metric | Typical | Notes |
|--------|---------|-------|
| Throughput per instance | 100K–5M records/sec | Depends on processing complexity and state access |
| State size per instance | GB–tens of GB | Bounded by local disk; distribute across instances |
| End-to-end latency | 5–50ms | Kafka poll interval + processing + produce |
| Scaling unit | Add instances (up to partition count) | 6 partitions → max 6 parallel instances |
| Standby replicas | 1–2 recommended | Fast failover; state pre-fetched to standby |

---

## File Map

| File | What's Inside |
|------|--------------|
| [01-architecture.md](01-architecture.md) | Topology, KStream/KTable, state stores, stream-table duality, task assignment |
| [02-read-write-path.md](02-read-write-path.md) | Record flow, joins, windowing, state access, changelog, interactive queries |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Kafka Streams vs Flink vs ksqlDB vs Faust; exactly-once analysis |
| [04-tuning-guide.md](04-tuning-guide.md) | Thread count, RocksDB, cache, commit interval, standby replicas |
| [05-production-and-research.md](05-production-and-research.md) | Confluent origin, companies, war stories, FAANG interview framing |

---

## FAANG Interview Callout (30-second version)

> "I'd choose Kafka Streams when the stream processing logic belongs to a single microservice that already consumes from Kafka — no external cluster to manage, state is RocksDB-local backed by a Kafka changelog topic for durability, and scaling is just adding instances. The stream-table duality is the key mental model: every KStream is a changelog, and every KTable is a materialized latest-value view. Joins between a KStream (event) and a KTable (reference data, like a user profile) give me enrichment without querying a database. The trade-off versus Flink is operational simplicity vs capability: Kafka Streams has no Flink-style CEP, no cross-cluster joins, and is limited to JVM. For anything that spans services or needs petabyte-scale state, I'd move to Flink."
