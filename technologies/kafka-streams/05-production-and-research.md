# Kafka Streams — Production Use Cases & Research

## Origin

Kafka Streams was introduced in **Apache Kafka 0.10.0 (2016)** by Confluent and the Kafka community. The primary author is **Guozhang Wang** (then at Confluent, now at Amazon).

**Motivation**: Kafka already stored all the data; teams were building complex consumer applications that essentially reimplemented stream processing (windowing, state management, joins) from scratch on top of the Kafka consumer API. Kafka Streams standardised these patterns as a first-class, embeddable library — no separate cluster, no new operational paradigm.

### Design Philosophy Paper

**"Kafka Streams: Processing Data Infinitely"**  
Guozhang Wang, Joel Koshy, Sriram Subramanian, Kartik Paramasivam, Mammad Zadeh, Junrao Wang, Dmitry Madan  
*ACM SIGMOD 2017 (System Demonstrations)*

Key design decisions from the paper:
1. **Embed in the application** — co-locate processing with business logic; avoid operational overhead of a separate cluster
2. **Leverage Kafka for everything** — use Kafka for state durability (changelog), coordination (consumer groups), and fault tolerance (replication)
3. **Stream-table duality** — treat KStream and KTable as two views of the same underlying log; enable joins between them
4. **Elastic scaling** — Kafka consumer group rebalancing handles instance addition/removal automatically

---

## Production at Scale: Companies and Use Cases

### Confluent (Creator)

- **Use case**: Confluent Cloud's own metadata and billing pipelines; customer analytics; schema validation pipelines
- **Architecture**: Kafka Streams as the execution engine beneath ksqlDB — every ksqlDB query runs as a Kafka Streams application
- **Key insight**: ksqlDB's persistence, scaling, and fault tolerance are entirely inherited from Kafka Streams + Kafka; the SQL layer is purely syntactic sugar

### LinkedIn

- **Use case**: Feed ranking signal computation; member activity aggregation; Kafka Cruise Control (Kafka cluster auto-balancing tool is built on Kafka Streams)
- **Key insight**: Kafka Cruise Control uses Kafka Streams to compute partition-level metrics (byte rates, leader/follower load) in real-time and drive rebalancing decisions — a non-obvious application of Kafka Streams for infrastructure tooling

### Trivago (European Travel Platform)

- **Use case**: Real-time hotel price aggregation (prices from 400+ partners → latest price per hotel/room/date via KTable) serving 100M+ hotel-date pairs
- **Architecture**: Debezium CDC → Kafka → Kafka Streams KTable → REST API (interactive queries)
- **Scale**: 10M+ price updates/day; p99 query latency < 5ms (local RocksDB lookup)
- **Key insight**: Replaced a cache invalidation system (Redis + DB) with a Kafka Streams KTable — the KTable IS the cache, self-updating from the changelog, with no separate invalidation mechanism

### Zalando (European Fashion E-commerce)

- **Use case**: Order event processing (status transitions: placed → confirmed → shipped → delivered); real-time inventory updates; recommendation signal computation
- **Architecture**: Microservice per domain event type; each microservice owns a Kafka Streams topology for its domain
- **Key insight**: Kafka Streams enabled Zalando to adopt event-driven microservices where each service is self-contained: it consumes its input Kafka topics, maintains its own state, produces output topics — no shared database

### New Relic (Observability Platform)

- **Use case**: Real-time metric aggregation (compute count/sum/min/max per metric per minute window for 100B+ data points/day)
- **Architecture**: Kafka → Kafka Streams (per-metric windowed aggregation) → query serving layer
- **Key insight**: Kafka Streams' windowed aggregation with RocksDB state allowed New Relic to move metric aggregation from a batch pipeline (1-minute latency) to real-time (< 5-second latency) without operational overhead of a Flink cluster

---

## Real-World War Stories

### Trivago: Co-partitioning Incident

> "We had a price topic with 12 partitions and a hotel metadata topic with 6 partitions. When we tried to join the price KStream with the hotel KTable, Kafka Streams threw a TopologyException at startup. We had to create a new hotel metadata topic with 12 partitions, backfill it, and redeploy. The lesson: plan partition counts for ALL related topics together before going to production — changing partition count later requires topic recreation."

**Lesson**: Co-partitioning is a hard constraint. Audit all topics that will be joined before creating them. Use `replication-factor` and `partitions` from a shared configuration to ensure alignment.

### Zalando: Standby Replica Omission

> "A Kafka Streams application managing order status state had `num.standby.replicas=0` (default). During a deployment, rolling restart caused task rebalancing. Each reassigned task had to replay 45 minutes of changelog before becoming active. During this window, the application was processing stale state. Order status updates were delayed by 45+ minutes."

**Lesson**: `num.standby.replicas=1` is mandatory for any production application with non-trivial state. The disk cost of a second RocksDB copy is far cheaper than extended recovery windows.

### New Relic: Record Cache Caused Metric Loss

> "We relied on Kafka Streams' windowed aggregation with a large record cache. Because the cache batched updates before flushing, during a host failure we lost up to `commit.interval.ms` (30 seconds) of metric aggregations that were in the cache but not yet flushed to RocksDB. This manifested as gaps in metric charts during host restarts."

**Lesson**: Understand that the record cache holds un-flushed state. Reducing `commit.interval.ms` and `statestore.cache.max.bytes` reduces the loss window on failure. For metrics pipelines that must not lose aggregations, consider disabling the cache and committing frequently.

---

## Kafka Streams Ecosystem

| Tool | Purpose | Notes |
|------|---------|-------|
| **ksqlDB** | SQL interface over Kafka Streams | For SQL-fluent teams; runs KS topologies under the hood |
| **Kafka Streams Topology Visualizer** | Visual topology graph | Useful for debugging complex topologies |
| **Confluent Schema Registry** | Avro/Protobuf schema management | Integrates with KS SerDes; enables schema evolution |
| **Kafka Cruise Control** | Cluster auto-balancing tool | Built on Kafka Streams for metric computation |
| **Spring Cloud Stream** | Spring integration | Higher-level abstraction; Kafka Streams binder available |
| **Micronaut Kafka** | Micronaut integration | Lightweight; good for serverless deployments |

---

## FAANG Interview Framing

### What Interviewers Are Testing

| Question Type | What They're Probing |
|---------------|---------------------|
| "Design an order enrichment service" | KStream-KTable join; co-partitioning; interactive queries |
| "How do you maintain a real-time view of a database table in a service?" | CDC + KTable; stream-table duality |
| "What happens to Kafka Streams state when an instance crashes?" | Changelog restore; standby replicas; recovery time trade-off |
| "How would you scale a Kafka Streams application?" | Partition count = max parallelism; `num.stream.threads` tuning |
| "How does Kafka Streams achieve exactly-once?" | Kafka transactions; atomic offset commit + produce |

### The 3-Part Kafka Streams Answer Framework

1. **Why Kafka Streams here?** — Kafka-native, single-service ownership, operational simplicity vs Flink; the data is already in Kafka; no separate cluster.

2. **Key design decisions** — Input topic partition count (sets max parallelism), KStream vs KTable choice, co-partitioning of joined topics, state store naming (for interactive queries), `num.standby.replicas`.

3. **Failure and exactly-once** — Changelog topic restores state on crash; standby replicas reduce recovery to seconds; `exactly_once_v2` wraps each commit in a Kafka transaction.

### 30-Second Answer: "When would you use Kafka Streams over Flink?"

> "I'd choose Kafka Streams when the stream processing logic belongs to a single microservice team that's already on Kafka, and the operational simplicity of an embedded library outweighs Flink's additional capabilities. Concretely: enriching order events with the latest customer profile (KStream-KTable join), computing per-user request counts in 1-minute windows, or building a queryable projection of a Kafka topic — all of these are textbook Kafka Streams use cases. The moment the processing spans services, needs CEP patterns, requires sub-10ms latency with large state, or the team wants Flink SQL, I move to Flink. The operational calculus is simple: Kafka Streams = one more JAR in your service; Flink = a cluster to operate."
