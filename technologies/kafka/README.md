# Apache Kafka — Overview & Decision Guide

**Type**: Distributed event streaming platform / persistent log  
**CAP Position**: AP (Availability + Partition Tolerance)  
**Consistency Model**: At-least-once by default; exactly-once via idempotent producers + transactions  
**Data Model**: Ordered, immutable, partitioned log of byte records  
**Storage Model**: Sequential disk writes; retention by time or size (not consumption)  
**Origin**: LinkedIn (2011), open-sourced 2011, Apache top-level 2012

---

## What Is Kafka?

Apache Kafka was built at LinkedIn in 2011 to solve a specific problem: dozens of internal systems were generating activity events (page views, searches, ad clicks, likes) and dozens of downstream systems needed those events — but the point-to-point pipeline had become an O(N²) integration mess. Kafka introduced the **commit log** as the universal integration bus.

The core insight is deceptively simple: treat all data as an **ordered, append-only, durable log**. Producers append records; consumers read at their own pace using an offset cursor. The log is retained regardless of consumption — any consumer can re-read from the beginning at any time. This single primitive enables:

- **Decoupling**: producers and consumers are fully independent
- **Replayability**: new consumers can process all historical data
- **Multiple consumers**: same topic can be consumed by many systems simultaneously (analytics, search indexing, ML feature pipelines, alerting)
- **Backpressure absorption**: consumers process at their own rate; the log buffers any burst

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| CAP | AP — partition-tolerant; prioritises availability over strong consistency |
| Ordering | Strict ordering **within a partition**; no global ordering across partitions |
| Durability | Configurable: `acks=all` + `min.insync.replicas=2` for strong durability |
| Delivery | At-least-once (default); exactly-once via idempotent producers + transactions |
| Retention | Time-based (default 7 days) or size-based; independent of consumption |
| Consumer model | Pull-based; consumer tracks its own offset |
| Replication | Leader-follower per partition; ISR (In-Sync Replica) list |
| Horizontal scaling | Add partitions (write scale) or add consumers (read scale) |
| Coordination | ZooKeeper (legacy) or KRaft (Kafka 3.3+ default, no ZooKeeper) |
| Throughput | Millions of messages/sec per cluster; GB/s sequential I/O |

---

## Decision Drivers: When to Choose Kafka

**Choose Kafka when ALL of the following are true:**

1. **High-throughput, durable event streaming** — you produce millions of events/sec and need them stored reliably for downstream consumption (not just queued and discarded)
2. **Multiple independent consumers** — more than one system needs the same event stream (fanout); a queue-per-consumer model would duplicate data
3. **Replayability matters** — consumers need to re-process historical events (new downstream system onboarding, bug replay, backfill ML features)
4. **Decoupling producer from consumer** — producers should not know or care about downstream systems; consumers should be able to fall behind and catch up
5. **Event-driven architecture at scale** — you are building a data pipeline, CDC feed, stream processing system, or microservices integration bus

**The single most important question**: *Do you need the data retained after consumption, accessible to multiple independent consumers?* If yes, Kafka. If you just need task queuing with one consumer per message and no need for replay, RabbitMQ or SQS is simpler.

---

## Use Cases

| Use Case | Why Kafka Fits | Example Company |
|----------|---------------|----------------|
| **Activity event pipeline** | High write volume; many consumers (analytics, ML, monitoring, GDPR audit) | LinkedIn (origin), Twitter, Airbnb |
| **Change Data Capture (CDC)** | Debezium captures DB changes → Kafka → downstream consumers (search index, cache, data warehouse) | Stripe, Shopify, Uber |
| **Microservices integration bus** | Services emit domain events; consumers react without direct coupling | Netflix, Lyft, DoorDash |
| **Stream processing** | Kafka Streams or Flink reads Kafka topics; outputs to another Kafka topic or data store | Uber (surge pricing), LinkedIn (fraud detection) |
| **Log aggregation** | Services emit structured logs to Kafka; log consumers write to Elasticsearch / S3 | Most FAANG companies |
| **Metrics pipeline** | High-rate numeric time series (counters, gauges) → Kafka → Flink → TimescaleDB / Prometheus remote write | Netflix (Atlas), Uber (M3) |
| **Event sourcing store** | Domain events appended to Kafka topics; state rebuilt from replay | EventStoreDB alternative for very high volume |

---

## Anti-Patterns: When NOT to Use Kafka

| Situation | Better Alternative |
|-----------|-------------------|
| **Simple task queue** (one consumer, discard after ack) | RabbitMQ, Amazon SQS, Celery |
| **Request/reply RPC** | gRPC, HTTP/REST, GraphQL |
| **Low-volume, low-latency messaging** (< 1K msg/sec) | RabbitMQ (simpler ops), Redis Pub/Sub |
| **Large messages** (> 1MB each) | Store blobs in S3/GCS; put a reference key in Kafka |
| **Complex routing / dead-letter + retry logic** | RabbitMQ (mature exchange/queue/DLX model) |
| **Strict global ordering across partitions** | Design limitation — use single partition (limits throughput) or use an external sequencer |
| **Real-time OLAP / querying event data** | ClickHouse, Apache Druid, BigQuery — Kafka is write-only from the consumer's perspective |

---

## Key Numbers (Production Scale)

| Metric | Typical | Large Production |
|--------|---------|-----------------|
| Brokers per cluster | 3–10 | 100+ (LinkedIn: 1,100+ brokers) |
| Topics per cluster | Tens to hundreds | Thousands (LinkedIn: 110K+ topics) |
| Partitions per topic | 10–100 | 1,000+ (for highest-throughput topics) |
| Write throughput per broker | 500 MB/s | 1–2 GB/s (dedicated NVMe) |
| Message throughput per cluster | 1M msg/sec | 7M+ msg/sec (LinkedIn) |
| End-to-end latency (p99) | 5–20ms | Sub-10ms with tuning |
| Retention | 7 days default | 30 days for compliance; indefinite with Tiered Storage |
| Consumer lag (healthy) | Near-zero | < 1 minute for real-time consumers |

---

## File Map

| File | What's Inside |
|------|--------------|
| [01-architecture.md](01-architecture.md) | Brokers, topics, partitions, consumer groups, ISR, ZooKeeper vs KRaft |
| [02-read-write-path.md](02-read-write-path.md) | Producer path, acknowledgement levels, consumer pull loop, log segments, compaction |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Kafka vs RabbitMQ vs Pulsar vs Kinesis; exactly-once semantics; PACELC analysis |
| [04-tuning-guide.md](04-tuning-guide.md) | Key producer/consumer/broker parameters, anti-patterns, partition sizing |
| [05-production-and-research.md](05-production-and-research.md) | LinkedIn origin paper, companies, war stories, FAANG interview framing |

---

## FAANG Interview Callout (30-second version)

> "I'd choose Kafka when I need a durable, replayable event log that multiple independent consumers can read at their own pace. Kafka's key insight is that the log retains data regardless of consumption — so a new consumer can onboard and replay all history, a slow consumer can fall behind without affecting others, and producers never need to know who's consuming. The trade-off is that ordering is only guaranteed within a partition, not across partitions, so I choose my partition key carefully — usually the entity ID (user ID, order ID) to ensure all events for a given entity are ordered. For strong durability I set `acks=all` and `min.insync.replicas=2`. For exactly-once I use idempotent producers plus Kafka transactions."
