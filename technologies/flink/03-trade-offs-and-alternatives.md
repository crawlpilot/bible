# Flink — Trade-offs and Alternatives

## Flink vs Spark Structured Streaming

The most common comparison in FAANG interviews.

| Dimension | Apache Flink | Spark Structured Streaming |
|-----------|-------------|--------------------------|
| **Processing model** | True streaming: per-event, continuous | Micro-batch: chops stream into small batches (default 100ms–1s) |
| **Latency** | Sub-millisecond to tens of milliseconds | 100ms–1s (micro-batch interval) |
| **Event-time support** | Native: full Dataflow model (watermarks, triggers, allowed lateness) | Yes, but less flexible (fixed trigger model) |
| **State management** | First-class: keyed state, state backends, incremental checkpoints | DStream state (RDD-based); Structured Streaming: stateful ops limited |
| **Exactly-once** | End-to-end via Chandy-Lamport + 2PC sinks | End-to-end via idempotent writes + WAL |
| **Fault tolerance** | Checkpoint + replay (fine-grained; only replays since last checkpoint) | Replay entire micro-batch |
| **Backpressure** | Native credit-based flow control | Dynamic rate limiting per micro-batch |
| **SQL / Table API** | Flink SQL: strong (unified batch+stream; CDC with changelog semantics) | Spark SQL: mature, wider function coverage |
| **Batch processing** | Supported (bounded DataStream / Table API) | Spark's core strength |
| **Ecosystem maturity** | Excellent for streaming; batch smaller than Spark | Mature; dominant for batch; streaming improving |
| **Operational complexity** | High: JM/TM configuration, state backend, checkpoint tuning | High: Spark config is also complex; more familiar to data engineers |
| **Community / adoption** | Strong in EU, Alibaba; growing in US | Dominant in US data platforms (Databricks ecosystem) |
| **Best for** | Low-latency stateful streaming, event-time correctness, CEP | Batch ETL with streaming capabilities; teams already on Spark |

**Decision**: If your team owns a Spark cluster and latency > 1s is acceptable → Spark Structured Streaming. If you need sub-100ms latency, complex event time processing, or very large stateful pipelines → Flink.

---

## Flink vs Kafka Streams

| Dimension | Apache Flink | Kafka Streams |
|-----------|-------------|--------------|
| **Deployment** | Separate cluster (standalone, YARN, K8s) | Embedded library in your application; no separate cluster |
| **Operational overhead** | High: cluster management, JM HA, checkpoint storage | Low: deploy like any microservice |
| **Scalability** | Massively parallel: thousands of TaskManagers | Scale = number of application instances (limited by partition count) |
| **State management** | Managed externally (RocksDB on TM disk + S3) | Managed locally (RocksDB) with Kafka changelog topic as backup |
| **Exactly-once** | End-to-end via 2PC | End-to-end via Kafka transactions |
| **Stream joins** | Rich: temporal joins, interval joins, stream-stream joins | KTable-KStream join, KTable-KTable join |
| **Event-time** | Full Dataflow model (watermarks, allowed lateness) | Basic; relies on Kafka timestamps |
| **SQL** | Flink SQL: production-grade, streaming-aware | ksqlDB (separate product, not embedded) |
| **Language** | Java, Scala, Python (PyFlink) | Java, Scala |
| **Throughput** | Millions/sec per cluster | Hundreds of thousands/sec per instance; horizontally scalable |
| **Best for** | Cross-service, large-scale, low-latency pipelines | Per-microservice stream processing; Kafka-native teams |

---

## Flink vs Apache Storm

Storm is Flink's predecessor in true streaming. Largely superseded.

| Dimension | Flink | Storm |
|-----------|-------|-------|
| **Exactly-once** | Yes (checkpoints) | At-least-once (Trident extension for EOS, complex) |
| **State management** | Built-in keyed state | No native state; must use external store (Redis, Cassandra) |
| **Event time** | Full watermark support | No native event-time; processing time only |
| **Throughput** | High (batched network transfer) | Lower (per-tuple acking overhead) |
| **Adoption** | Growing rapidly | Declining; Twitter (origin) moved away |

---

## Exactly-Once: Semantics Comparison

| System | Mechanism | Limitation |
|--------|-----------|-----------|
| **Flink** | Chandy-Lamport checkpoint + 2PC sinks | Requires replayable source (Kafka) + transactional sink |
| **Spark Structured Streaming** | WAL + idempotent writes | Sink must be idempotent (harder to guarantee) |
| **Kafka Streams** | Kafka transactions (atomic offset commit + produce) | Only within the Kafka ecosystem |
| **Storm Trident** | Micro-batch with state isolation | High latency; complex implementation |

---

## When Flink Loses to Alternatives

| Scenario | Better Choice | Reason |
|----------|--------------|--------|
| Simple Kafka → S3 ETL | Kafka Connect S3 Sink | Zero code, zero cluster overhead |
| Per-microservice stream logic | Kafka Streams | No cluster to manage; scales with the app |
| Heavy batch workloads | Spark | Flink batch is functional but Spark ecosystem is larger |
| Millisecond latency with simple transforms | Kafka Streams | Flink cluster adds operational complexity not justified |
| ML model training on streaming data | Spark ML + Structured Streaming | Spark's ML library is far more mature |
| BI / ad-hoc queries on streams | ksqlDB, Apache Druid | Interactive query support; Flink SQL lacks good UI |

---

## Key Trade-offs Summary

| Trade-off | Flink Chooses | Because |
|-----------|--------------|---------|
| Correctness vs latency | Correctness (event-time, exactly-once) | Late data and duplicates silently corrupt aggregations |
| In-memory vs disk state | Both (HashMapState / RocksDB) | Different jobs have different state-to-throughput profiles |
| Checkpoint frequency | Lower frequency → higher throughput; higher → faster recovery | `checkpoint.interval` is a tuneable lever |
| Aligned vs unaligned checkpoints | Aligned (default); unaligned for skewed workloads | Aligned: simpler recovery; unaligned: avoids latency spikes on checkpoint |
| Full vs incremental snapshots | Incremental (RocksDB) | Full snapshots of TB-scale state are impractical |

---

## FAANG Interview Callout

> "The fundamental difference between Flink and Spark Streaming is the processing model: Flink processes each record as it arrives; Spark Structured Streaming accumulates records into micro-batches and processes each batch as a mini job. For most batch-heavy teams, Spark's model is fine — latency of a few hundred milliseconds is acceptable. But when I need sub-100ms latency, correct event-time semantics over out-of-order data, or complex stateful patterns like session windows and CEP, Flink is the right choice. Compared to Kafka Streams, Flink is the right answer when the processing logic is cross-service (not embedded in a single microservice), when state exceeds what a single application instance can hold, or when I need the full Dataflow model with watermarks and allowed lateness."
