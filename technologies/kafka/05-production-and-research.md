# Kafka — Production Use Cases & Research

## Origin Paper

**"Kafka: a Distributed Messaging System for Log Processing"**  
Jay Kreps, Neha Narkhede, Jun Rao — LinkedIn, 2011  
*NetDB Workshop at SOSP 2011*

### Key Claims from the Paper

| Claim | Number |
|-------|--------|
| Write throughput vs ActiveMQ | ~9x faster |
| Write throughput vs RabbitMQ | ~3.5x faster |
| Sequential disk read throughput | ~6x faster than random reads |
| LinkedIn production (2011) | 1+ billion messages/day |

### Core Design Decisions (from the paper)

1. **Simple storage** — No per-message index; just a sequential log file. Consumers track their own offsets. This eliminates the most expensive operation in traditional MQs: marking messages as delivered.

2. **Explicit offset management** — Moving offset tracking to the consumer removes broker state. "The broker does not need to maintain the state of what has and has not been delivered."

3. **Batching by design** — Small API surface; producer and consumer are both batch-oriented. The paper reports that batching 200 messages achieves the same throughput as 1 message due to amortised overhead.

4. **Stateless broker** — Because consumers track offsets, brokers can delete old data purely by time/size, not by consumption state. This simplifies the broker dramatically.

---

## Notable Subsequent Papers

| Paper | Year | Contribution |
|-------|------|--------------|
| "The Log: What every software engineer should know about real-time data's unifying abstraction" — Jay Kreps | 2013 | Foundational blog/paper on the commit log as universal integration primitive; required reading |
| "Kafka Streams: Processing Data Infinitely" — Guozhang Wang et al., Confluent | 2017 | Kafka Streams design: stream-table duality, windowing, state stores backed by changelog topics |
| "Designing Data-Intensive Applications" — Kleppmann | 2017 | Chapter 11 uses Kafka as the canonical example for event stream processing |

---

## Production at Scale: Companies and Use Cases

### LinkedIn (Origin)
- **Scale (2022)**: 7 trillion+ messages/day; 1,100+ brokers; 110,000+ topics; 7 million+ msg/sec peak
- **Use cases**: Activity stream (page views, searches, likes), metrics pipeline, Espresso (NoSQL) CDC, Samza stream processing
- **Key insight**: Replaced 35+ internal MQ systems with a single Kafka cluster, reducing O(N²) pipelines to O(N)

### Uber
- **Use case**: Real-time trip events (location pings every few seconds), surge pricing signals, driver/rider matching, fraud detection
- **Scale**: Petabytes of data/day; used for both operational (sub-second) and analytical (batch) workloads
- **Architecture**: uReplicator — custom Kafka MirrorMaker replacement for cross-cluster replication at Uber scale
- **Key insight**: Kafka as the "nervous system" — everything from GPS location updates to payment events flows through Kafka before being routed to appropriate storage (Cassandra for time-series, Pinot for analytics)

### Netflix
- **Use cases**: Play start/stop events → recommendation model features, error rates → alerting, A/B test event logging, Keystone data pipeline (Kafka → S3 → Iceberg → Spark)
- **Scale**: Trillions of events/day
- **Architecture**: Kafka Connect + custom Kafka source connectors ingest from all microservices; Flink on top for real-time stream processing
- **Key insight**: Every microservice publishes domain events to Kafka; downstream services consume without coupling

### Stripe
- **Use cases**: Payment event streaming, fraud detection pipeline, webhook delivery (internal), CDC from PostgreSQL → Kafka
- **Key insight**: Kafka as the backbone for exactly-once payment event processing across services; Debezium for PostgreSQL CDC

### Airbnb
- **Use cases**: Search indexing pipeline (listing updates → Kafka → Elasticsearch), ML feature pipeline, real-time analytics
- **Architecture**: Kafka → Flink → feature store (for ML) + data warehouse (for analytics)

### Cloudflare
- **Scale**: ~5 million messages/sec, processing DNS queries and HTTP events in real-time
- **Use case**: Security event processing — DDoS detection, bot traffic analysis
- **Key insight**: Kafka as the buffer between edge event generation and security analysis — producers write at edge speed; consumers process at analysis speed

---

## Real-World War Stories (Operational Lessons)

### LinkedIn: Partition Count Cannot Be Reduced

> "When we needed to reduce partitions for a topic (due to hotspot issues), we discovered Kafka provides no mechanism to decrease partition count. We had to create a new topic with the desired partition count, write a migration consumer that reads from the old topic and republishes to the new topic (maintaining key routing), and cut over producers." — LinkedIn Engineering Blog

**Lesson**: Plan partition count carefully. Always start with more than you think you need. Use throughput-per-partition math.

### Uber: Consumer Rebalance Storm

> "During a deployment of a consumer group with 500+ instances, all instances would join the group simultaneously on startup, triggering repeated rebalances (each new join disrupts the in-progress rebalance). The group would thrash for minutes before stabilising." — Uber Engineering Blog

**Lesson**: Use **incremental cooperative rebalancing** (`partition.assignment.strategy=CooperativeStickyAssignor`, Kafka 2.4+). This allows consumers to keep their existing partition assignments during rebalance, only reassigning partitions that need to move.

### Netflix: Large Message Anti-Pattern

> "A service started producing 50MB Avro serialised messages containing full user profile snapshots. Broker heap usage spiked; consumer OOM errors appeared. The fix was to store the snapshot in S3 and produce only the S3 reference key to Kafka." — Netflix Tech Blog

**Lesson**: Kafka is not object storage. Keep messages small (< 100KB typically, < 1MB max). For large payloads, use the **claim-check pattern**: store payload externally, put the reference in Kafka.

### Stripe: Offset Reset Incident

> "A newly deployed consumer group had `auto.offset.reset=latest`. It missed 4 hours of payment events during a deployment because it started from the latest offset rather than processing historical events." — Stripe Engineering

**Lesson**: Always set `auto.offset.reset=earliest` for consumer groups that need to process historical data on first startup. Only use `latest` for truly ephemeral real-time consumers (e.g., live monitoring dashboards).

---

## Kafka Ecosystem: Key Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Kafka Connect** | Source/sink connector framework | 1000+ open-source connectors (Debezium for CDC, S3 Sink, JDBC Sink) |
| **Kafka Streams** | Embedded stream processing library | Java/Scala library; no separate cluster; stateful (RocksDB state stores) |
| **ksqlDB** | SQL interface over Kafka topics | Pull and push queries; persistent queries run as Kafka Streams apps |
| **Schema Registry** | Central Avro/Protobuf/JSON Schema registry | Confluent OSS; producers/consumers auto-validate schema compatibility |
| **Debezium** | Change Data Capture (CDC) | Reads DB transaction logs (PostgreSQL WAL, MySQL binlog) → Kafka |
| **MirrorMaker 2** | Cross-cluster replication | Active-active and active-passive geo-replication |
| **Kafka UI / AKHQ** | Web management UI | Topic browser, consumer group monitoring, schema registry |
| **Burrow** | Consumer lag monitoring | LinkedIn's open-source lag monitor; tracks lag trends, not just absolute values |

---

## FAANG Interview Framing

### What Interviewers Are Testing

| Question Type | What They're Probing |
|---------------|---------------------|
| "How would you design a notification system?" | Can you use Kafka for fanout vs a queue for task distribution? |
| "Design a real-time analytics pipeline" | Do you know Kafka → stream processing (Flink) → serving layer pattern? |
| "How does exactly-once work in Kafka?" | Depth on idempotent producers, transactions, consumer isolation levels |
| "What happens when a Kafka broker dies?" | ISR, leader election, `unclean.leader.election`, impact on producers |
| "How would you scale a Kafka consumer that's falling behind?" | Partition count, consumer parallelism, consumer group mechanics |

### The 3-Part Kafka Answer Framework

For any system design question involving Kafka:

1. **Why Kafka here?** — State the decision driver (high throughput, fanout, replayability, decoupling) and the alternative you ruled out (RabbitMQ, SQS, Redis) and why.

2. **Key design decisions** — Partition key choice (ordering semantics), durability settings (`acks=all`, `min.insync.replicas=2`), retention policy, consumer group structure.

3. **Failure modes** — What happens if the Kafka cluster is degraded? Can producers tolerate backpressure? Is the consumer idempotent so re-processing is safe? How do you monitor consumer lag?

### 30-Second Answer: "When would you use Kafka over a message queue?"

> "I'd use Kafka when I need more than one downstream system to consume the same events, or when consumers need to re-process historical events. Kafka's log persists after consumption — a new analytics service can read 30 days of history on first startup. A queue like RabbitMQ or SQS destroys the message after consumption, so you can't replay. The other differentiator is throughput: Kafka can sustain millions of messages per second per cluster via sequential disk I/O and zero-copy reads. I'd use RabbitMQ when I need complex routing (dead-letter exchanges, priority queues, header-based routing) or when the volume is low enough that Kafka's operational overhead isn't justified."
