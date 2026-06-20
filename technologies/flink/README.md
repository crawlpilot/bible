# Apache Flink — Overview & Decision Guide

**Type**: Distributed stateful stream processing engine  
**CAP Position**: CP during checkpointing; AP during normal processing  
**Processing Model**: True streaming (event-by-event); not micro-batch  
**State Model**: Managed keyed state with exactly-once guarantees via distributed snapshots  
**Time Models**: Event time, processing time, ingestion time  
**Origin**: TU Berlin (2010 as "Stratosphere"), Apache top-level 2014; Alibaba acquisition of Ververica 2019

---

## What Is Flink?

Apache Flink is a distributed computation engine built around the concept of **infinite data streams**. Unlike Spark Streaming (which chops the stream into micro-batches and processes each as a batch job), Flink processes each event individually as it arrives — a fundamentally different architecture that enables lower latency, correct event-time semantics, and fine-grained stateful operations.

The core design decisions that distinguish Flink:

- **True streaming**: records flow through a pipeline of operators continuously; no artificial batch boundaries
- **Managed state**: Flink owns the state lifecycle — it checkpoints, restores, and rebalances state transparently
- **Event time**: Flink reasons about *when events happened*, not *when they arrived* — critical for out-of-order data from distributed producers
- **Exactly-once**: Flink's Chandy-Lamport distributed snapshot algorithm guarantees that state is consistent even after failures, with no duplicates or data loss
- **Unified batch and stream**: the same API and same engine handles both bounded (batch) and unbounded (stream) datasets

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| Processing model | True streaming (per-event); no micro-batching |
| State backend | In-memory (HashMap), RocksDB (large state, spills to disk) |
| Exactly-once | Via distributed snapshots (Chandy-Lamport); requires exactly-once source/sink |
| Time semantics | Event time (preferred), processing time, ingestion time |
| Watermarks | Heuristic bounds on event-time completeness; trigger window computation |
| Fault tolerance | Checkpoint + restore; configurable interval (default: disabled; recommend 1–5min) |
| Scalability | Horizontal: add TaskManagers; vertical: increase task slots per TM |
| Latency | Sub-millisecond per record (no checkpoint overhead in critical path) |
| Throughput | Millions of records/sec per cluster; GB/s with RocksDB and SSDs |
| APIs | DataStream API (low-level), Table API / SQL (high-level, unified batch/stream) |

---

## Decision Drivers: When to Choose Flink

**Choose Flink when ALL of the following are true:**

1. **Low-latency stateful stream processing** — you need to transform, aggregate, or join streams with per-record latency in milliseconds, not seconds
2. **Event-time correctness matters** — your producers generate events out of order (mobile clients, IoT sensors, distributed microservices) and you need correct windowed aggregations
3. **State is large or complex** — you maintain state per user/entity (session windows, running aggregations, ML model serving) that exceeds memory and must be managed reliably
4. **Exactly-once end-to-end** — financial calculations, billing, fraud scores that cannot afford duplicates or lost events
5. **Long-running, continuously evolving pipelines** — not a one-off ETL; the job runs 24/7 and must recover automatically from failures

**The single most important question**: *Do you need correct results over out-of-order event streams with sub-second latency?* If yes, Flink. If micro-batch latency (1–5s) is acceptable and your team already knows Spark, use Spark Structured Streaming.

---

## Use Cases

| Use Case | Why Flink Fits | Example Company |
|----------|---------------|----------------|
| **Fraud / anomaly detection** | Sub-second windowed patterns over event streams; stateful per-user rules | PayPal, ING Bank, Lyft |
| **Real-time analytics / dashboards** | Continuous aggregations (counts, sums, P99) over event-time windows | Alibaba (Double 11), Netflix, Uber |
| **Stream-to-stream join** | Enrich clickstream with user profile stream; event-time join with temporal table | LinkedIn, Airbnb |
| **CEP (Complex Event Processing)** | Detect patterns across events: login → failed → suspicious alert | Yelp, Booking.com |
| **ETL / data pipeline** | Kafka → transform/enrich → Cassandra/Elasticsearch/S3 | Most data platform teams |
| **ML feature computation** | Compute real-time features (avg spend, session length) fed to online serving | Netflix, Uber |
| **CDC processing** | Debezium CDC events from DB → Flink → data warehouse | Shopify, DoorDash |

---

## Anti-Patterns: When NOT to Use Flink

| Situation | Better Alternative |
|-----------|-------------------|
| **Simple Kafka → DB ETL** (no stateful logic) | Kafka Connect (zero-code, 1000+ connectors) |
| **Ad-hoc SQL queries over historical data** | Spark, Trino, BigQuery |
| **Micro-batch acceptable** (seconds latency) and Spark already in use | Spark Structured Streaming |
| **Lightweight event processing in a microservice** | Kafka Streams (embedded library, no cluster) |
| **Simple message routing / transformation** | Kafka Streams or KSQL |
| **Very small scale** (< 1K msg/sec) | Single-machine processing; Flink cluster overhead not justified |

---

## Key Numbers (Production Scale)

| Metric | Typical | Large Production |
|--------|---------|-----------------|
| TaskManagers per cluster | 5–20 | 1,000+ (Alibaba) |
| Records per second | 100K–10M | 1B+ (Alibaba Double 11) |
| State size | MB–GB per key group | TB total (RocksDB spills to disk) |
| Checkpoint interval | 1–5 minutes | 30s for low-RTO jobs |
| Recovery time (from checkpoint) | Seconds–minutes | Depends on state size and parallelism |
| End-to-end latency | 5–50ms | Sub-1ms (no windowing; passthrough) |

---

## File Map

| File | What's Inside |
|------|--------------|
| [01-architecture.md](01-architecture.md) | JobManager, TaskManager, slots, DAG, checkpointing, state backends |
| [02-read-write-path.md](02-read-write-path.md) | Event flow, watermarks, windows, state access, checkpoint barriers |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Flink vs Spark Streaming vs Kafka Streams vs Storm; exactly-once analysis |
| [04-tuning-guide.md](04-tuning-guide.md) | Parallelism, RocksDB, checkpoint config, backpressure, memory model |
| [05-production-and-research.md](05-production-and-research.md) | Research papers, Alibaba/Netflix/Uber/LinkedIn deployments, war stories |

---

## FAANG Interview Callout (30-second version)

> "I'd reach for Flink when I need low-latency, stateful stream processing with event-time correctness. Flink's key advantage over Spark Streaming is that it's true streaming — no micro-batch latency penalty — and it handles out-of-order events correctly via watermarks. For fault tolerance, Flink uses distributed snapshots: it periodically injects checkpoint barriers into the stream; when all operators have processed the barrier, their state is snapshotted to durable storage. On recovery, Flink restores all operator state from the last consistent snapshot and replays records since that checkpoint — achieving exactly-once even across failures. The main operational complexity is state management: I'd use RocksDB as the state backend for any job with more than a few GB of state, and tune checkpoint intervals to balance recovery time vs throughput overhead."
