# Kafka Streams — Trade-offs and Alternatives

## Kafka Streams vs Apache Flink

The most critical comparison. See also [Flink's 03-trade-offs](../flink/03-trade-offs-and-alternatives.md) for the same comparison from Flink's perspective.

| Dimension | Kafka Streams | Apache Flink |
|-----------|--------------|-------------|
| **Deployment** | Library in your app — deploy like a microservice | Separate cluster (standalone, YARN, K8s) |
| **Operational overhead** | Low — no cluster to manage | High — JM HA, TaskManager config, checkpoint storage |
| **Scaling unit** | Add instances (bounded by partition count) | Add TaskManagers; tune slots |
| **State size** | Bounded by local disk per instance | Bounded by cluster disk (distributed across TMs) |
| **Exactly-once** | Kafka transactions (within Kafka ecosystem only) | Chandy-Lamport + 2PC sinks (end-to-end, broader) |
| **Event-time / watermarks** | Basic (Kafka record timestamps); no watermark model | Full Dataflow model: watermarks, triggers, allowed lateness |
| **CEP** | Not supported natively | Flink CEP library |
| **Stream-stream joins** | Windowed KStream-KStream (good for moderate scale) | Temporal joins, interval joins, richer semantics |
| **SQL** | Not native (ksqlDB is a separate product) | Flink SQL (streaming-aware, unified batch/stream) |
| **Language** | Java, Scala | Java, Scala, Python (PyFlink) |
| **Throughput** | Moderate (single app instance is the unit) | Massive (parallelism independent of partition count via sub-tasks) |
| **Best for** | Single-service, Kafka-native, moderate-scale stream processing | Cross-service, platform-level, large-scale, low-latency |

**Decision framework**:
```
Is the processing owned by a single microservice team?
  YES → Does it need CEP, Flink SQL, or cross-cluster joins?
          NO  → Kafka Streams (simpler ops)
          YES → Flink
  NO  → Flink (platform-owned, cross-service)

Does the state exceed what fits on one instance's disk?
  YES → Flink
  NO  → Kafka Streams acceptable
```

---

## Kafka Streams vs ksqlDB

ksqlDB is Confluent's SQL layer built on top of Kafka Streams. It IS Kafka Streams under the hood.

| Dimension | Kafka Streams | ksqlDB |
|-----------|--------------|--------|
| **Interface** | Java/Scala DSL + Processor API | SQL (`CREATE STREAM AS SELECT ...`) |
| **Deployment** | Embedded in your app | Separate ksqlDB server cluster |
| **Custom logic** | Full Java flexibility | Limited to SQL functions; UDFs possible but complex |
| **Exactly-once** | Supported | Supported (via Kafka Streams underneath) |
| **Interactive queries** | Via custom REST endpoint | Built-in (pull queries: `SELECT * FROM table WHERE key='x'`) |
| **Joins** | All Kafka Streams joins | SQL joins (KStream-KTable, KStream-KStream) |
| **Schema management** | Manual Serde | Integrates with Confluent Schema Registry (Avro/Protobuf) |
| **Learning curve** | Moderate (Java/DSL) | Low (SQL) |
| **Best for** | Engineers writing Java services | Data analysts, SQL-fluent teams, rapid prototyping |

**Rule**: If your team is data-engineering-oriented and comfortable with SQL → ksqlDB. If you need custom Java business logic, UDFs, or the full flexibility of the Processor API → Kafka Streams.

---

## Kafka Streams vs Faust (Python)

| Dimension | Kafka Streams | Faust |
|-----------|--------------|-------|
| **Language** | Java, Scala | Python |
| **Ecosystem** | JVM; integrates with Spring Boot, Micronaut | Python; integrates with aiohttp, FastAPI |
| **State stores** | RocksDB (production-grade) | RocksDB (via rocksdict), in-memory |
| **Exactly-once** | Supported | At-least-once (Faust does not support Kafka transactions) |
| **Maturity** | Mature, well-documented | Less mature; smaller community |
| **Best for** | JVM shops | Python ML/data teams that need lightweight stream processing |

---

## Exactly-Once: Deep Dive

Kafka Streams exactly-once relies entirely on **Kafka transactions**. The guarantee is:

```
Guarantee: Each input record is processed exactly once.
           Each output record is produced exactly once.
           State store updates are atomic with output and offset commit.

Scope: input Kafka topic → Kafka Streams processing → output Kafka topic
       (Does NOT cover: external DB writes, HTTP calls, filesystem writes)
```

### Exactly-Once v2 vs v1

| | EOS v1 (`exactly_once`) | EOS v2 (`exactly_once_v2`) |
|--|--------------------------|---------------------------|
| **Introduced** | Kafka 0.11 | Kafka 2.5 |
| **Producer per** | Task (N tasks = N transactional producers) | Stream thread (T threads = T producers) |
| **Broker load** | High (many producers) | Low (fewer producers) |
| **Throughput** | ~10–30% overhead vs at-least-once | ~10–20% overhead |
| **Recommendation** | Deprecated | Use this in all new applications |

### What's NOT Covered by Exactly-Once

```java
// This is at-MOST-once for the HTTP call, even with exactly_once_v2:
stream.foreach((key, value) -> {
    httpClient.post("/notify", value);   // called once per record but HTTP call can fail
    // No rollback mechanism for external calls
});
```

For external side effects (HTTP calls, DB writes), you must design the external system to be **idempotent**: handle duplicate calls safely (same request ID → same result).

---

## Key Trade-offs

### Trade-off 1: Embedded vs Cluster

| Embedded (Kafka Streams) | Cluster (Flink) |
|--------------------------|-----------------|
| Deploy = standard service deployment | Deploy = cluster management |
| State = local disk (bounded per instance) | State = distributed across cluster |
| Failures isolated per service | Failures managed by cluster failover |
| Scaling = more instances | Scaling = add TaskManagers or increase parallelism |
| **Use when**: single-team ownership, moderate scale | **Use when**: platform-level, cross-team, large scale |

### Trade-off 2: Co-partitioning Constraint

KStream-KTable joins require both topics to have **the same number of partitions**. This constraint is not negotiable in Kafka Streams.

| Scenario | Implication |
|----------|------------|
| Order topic has 12 partitions, user-profile topic has 6 | Cannot join directly; must repartition one of them |
| Adding partitions to one topic | May break existing joins if the other topic is not also repartitioned |
| GlobalKTable | Bypasses co-partitioning (replicated to all instances) — use for small tables |

### Trade-off 3: State Recovery Time vs Standby Replicas

| Config | Recovery Time | Memory/Disk Cost |
|--------|--------------|-----------------|
| `num.standby.replicas=0` | Full changelog replay (can be minutes for large state) | No extra cost |
| `num.standby.replicas=1` | Near-instant (standby pre-warmed) | 2× state storage |
| `num.standby.replicas=2` | Near-instant, survive 2 failures | 3× state storage |

---

## When Kafka Streams Loses to Alternatives

| Scenario | Better Choice | Reason |
|----------|--------------|--------|
| Python team | Faust | No native Python Kafka Streams |
| Very large stateful joins | Flink | Flink distributes state across cluster; Kafka Streams bounded by per-instance disk |
| Complex CEP patterns | Flink CEP | No CEP support in Kafka Streams |
| Ad-hoc stream queries | ksqlDB | SQL interface; interactive pull queries built-in |
| Non-Kafka sources/sinks | Flink | Kafka Streams is Kafka-only |
| Sub-10ms end-to-end latency | Flink | Kafka Streams poll interval adds inherent latency |

---

## FAANG Interview Callout

> "The key trade-off between Kafka Streams and Flink is operational simplicity versus capability. Kafka Streams gives you stream processing as a library — your service IS the stream processor, no cluster to manage, scaling is just adding instances. The price you pay is that everything must go through Kafka, state is bounded by your instance disk, and there's no CEP or Flink SQL. Flink gives you a dedicated cluster, unlimited scalability, event-time watermarks, CEP, and SQL — at the cost of running and operating a cluster. In an interview, I'd choose Kafka Streams for 'enrich order events with the latest user profile' (single-team, Kafka-native, moderate scale) and Flink for 'compute real-time fraud scores across all users with 50ms SLA' (platform-level, low-latency, large state)."
