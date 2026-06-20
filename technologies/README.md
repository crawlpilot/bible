# Technologies — Master Reference

This folder is the **principal engineer's technology decision guide**. Each sub-folder is a complete deep-dive on one technology: how it works internally, when to use it, how to tune it, who uses it in production, and how to talk about it in a FAANG interview.

---

## How to Use This Folder

1. **Interview prep**: Read the technology's `README.md` for a 5-minute overview + decision drivers. Skim `03-trade-offs-and-alternatives.md` to sharpen your comparative reasoning.
2. **System design**: Before choosing a data store or messaging layer, consult the decision matrix below and the relevant `03-trade-offs` file to justify your choice.
3. **Adding a new technology**: Follow the 5-file template (see bottom of this file).

---

## Technology Landscape Map

```
                        CONSISTENCY AXIS
                  Strong ◄──────────────────► Eventual
                  │                                   │
   H              │  PostgreSQL   DynamoDB             │
   I              │  CockroachDB  MongoDB (tunable)    │
   G              │  Spanner                           │
   H              │               HBase                │
   │              │               Cassandra ◄──────────┤
   S              │                                    │
   C              │  Redis (sync)  Redis (async repl)  │
   A              │                                    │
   L              │               Kafka (log)          │
   E              │               Elasticsearch        │
   │              └────────────────────────────────────┘
   L                   SQL / OLTP        NoSQL / Scale-out
   O
   W
```

---

## Decision Matrix

> Legend: ★★★ = excellent fit / ★★ = good fit / ★ = possible / ✗ = not recommended

| Technology | Time-Series / IoT | High-Write Throughput | Flexible Queries | Strong Consistency | Multi-Region A/A | Semantic / ANN Search | Operational Simplicity | Cost (Self-Hosted) |
|-----------|:-----------------:|:---------------------:|:----------------:|:-----------------:|:----------------:|:---------------------:|:----------------------:|:-----------------:|
| **[ZooKeeper](zookeeper/README.md)** | ✗ | ✗ (50K/sec ceiling) | ✗ (path only) | ★★★ (CP, linear writes) | ★ (ZAB, single-DC quorum best) | ✗ | ★ (JVM, ensemble) | Low |
| **[Vector DB (Milvus)](vector-db/README.md)** | ✗ | ★★ (streaming insert) | ★ (ANN + metadata filter) | ★ (eventual AP) | ★★ | ★★★ | ★ | Low–Med |
| **[Cassandra](cassandra/README.md)** | ★★★ | ★★★ | ★ | ★ (tunable) | ★★★ | ✗ | ★★ | Low |
| **[ClickHouse](clickhouse/README.md)** | ★★★ | ★★★ | ★★★ (OLAP) | ★ (eventual repl) | ★★ | ✗ | ★★ | Low |
| DynamoDB *(stub)* | ★★ | ★★★ | ★★ | ★★ | ★★★ | ✗ | ★★★ | High (managed) |
| PostgreSQL *(stub)* | ★ | ★★ | ★★★ | ★★★ | ★ | ★★ (pgvector, < 10M) | ★★★ | Low |
| **[MongoDB](mongodb/README.md)** | ★★ | ★★ | ★★★ | ★★ (w:majority) | ★★ (zone sharding) | ✗ | ★★ | Low–Med |
| HBase *(stub)* | ★★★ | ★★★ | ★ | ★★ | ★ | ✗ | ★ | Med |
| Redis *(stub)* | ★ | ★★★ | ★ | ★★ | ★★ | ★ (VSS, < 100M) | ★★★ | Low |
| Kafka *(stub)* | ★★★ | ★★★ | ✗ (log only) | ★★ | ★★ | ✗ | ★★ | Low |
| **[RabbitMQ](rabbitmq/README.md)** | ✗ | ★★ (< 50K/sec persistent) | ★★ (rich routing) | ★★ (quorum=CP; classic=AP) | ★ (federation only) | ✗ | ★★★ | Low |
| **[Elasticsearch](elasticsearch/README.md)** | ★★ | ★★ | ★★★ (search) | ★ | ★★ | ★★ (hybrid BM25+dense) | ★★ | Med |
| ScyllaDB *(stub)* | ★★★ | ★★★ | ★ | ★ (tunable) | ★★★ | ✗ | ★★ | Low |
| Spanner *(stub)* | ★ | ★★ | ★★★ | ★★★ | ★★★ | ✗ | ★★★ | Very High |

---

## Quick-Decision Flowchart

```
Need to store data?
│
├─ Primarily READ (complex queries, joins, aggregations)?
│   └─ PostgreSQL / CockroachDB / Spanner
│
├─ Primarily WRITE (append-heavy, time-series, event log)?
│   ├─ Need multi-region active-active + horizontal scale?
│   │   └─ Cassandra / ScyllaDB / DynamoDB
│   └─ Single region, manageable scale?
│       └─ PostgreSQL (with partitioning) / MySQL
│
├─ Search / text / faceting?
│   └─ Elasticsearch / OpenSearch
│
├─ Cache / sub-millisecond latency?
│   └─ Redis / Memcached
│
├─ Event streaming / message queue?
│   ├─ Complex routing, task queues, per-message ack, TTL → [RabbitMQ](rabbitmq/README.md)
│   ├─ Event replay, high throughput (> 100K/sec), multiple independent consumers → Kafka
│   └─ Managed, AWS-native, simple queuing → SQS / SNS
│
├─ Large analytical queries (OLAP)?
│   └─ BigQuery / Snowflake / Redshift / ClickHouse
│
├─ Distributed coordination (leader election, distributed locks, config sync, group membership)?
│   ├─ New project / Kubernetes ecosystem → etcd
│   ├─ Already running Kafka / HBase / Hadoop → [ZooKeeper](zookeeper/README.md)
│   └─ Service discovery with health checks / multi-DC → Consul
│
└─ Semantic similarity / vector search / RAG / recommendations?
    ├─ < 1M vectors OR need SQL joins → pgvector (PostgreSQL extension)
    ├─ < 100M vectors, sub-ms latency → Redis VSS
    ├─ Already have Elasticsearch → ES dense_vector + hybrid BM25+dense
    ├─ Zero-ops managed → Pinecone or Zilliz Cloud (managed Milvus)
    └─ Self-hosted, > 10M vectors → [Milvus](vector-db/README.md) or Qdrant
```

---

## Technologies Covered

| Technology | Status | Files | Key Use Case |
|-----------|--------|-------|-------------|
| **[Java / JVM](java/README.md)** | ✅ Complete | 6 | GC selection, thread pools, Virtual Threads, concurrency, JVM tuning |
| **[Apache ZooKeeper](zookeeper/README.md)** | ✅ Complete | 6 | Distributed coordination, leader election, distributed locks, config management |
| **[Vector DB (Milvus)](vector-db/README.md)** | ✅ Complete | 6 | ANN search, RAG systems, semantic similarity, recommendations |
| [Apache Cassandra](cassandra/README.md) | ✅ Complete | 6 | Wide-column, high-write, multi-region |
| [ClickHouse](clickhouse/README.md) | ✅ Complete | 6 | Columnar OLAP, real-time analytics, sub-second queries |
| [Docker / Containers](docker/README.md) | ✅ Complete | 6 | Container runtime, packaging, CI/CD, microservices deployment |
| DynamoDB | 🔲 Stub | — | Managed NoSQL, serverless scale |
| PostgreSQL | 🔲 Stub | — | Relational, ACID, complex queries |
| [Kubernetes](kubernetes/README.md) | ✅ Complete | 6 | Container orchestration, microservices platform, GitOps |
| [Apache Kafka](kafka/README.md) | ✅ Complete | 6 | Distributed event streaming, durable log, CDC |
| [Apache Flink](flink/README.md) | ✅ Complete | 6 | Stateful stream processing, event-time, exactly-once |
| [Kafka Streams](kafka-streams/README.md) | ✅ Complete | 6 | Embedded stream processing library, KTable, microservices |
| **[RabbitMQ](rabbitmq/README.md)** | ✅ Complete | 6 | Message broker, task queues, pub/sub, microservice choreography |
| Redis | 🔲 Stub | — | In-memory cache, pub/sub |
| **[Elasticsearch](elasticsearch/README.md)** | ✅ Complete | 6 | Full-text search, log analytics, hybrid BM25+dense vector |
| ScyllaDB | 🔲 Stub | — | Cassandra-compatible, lower latency |
| Google Spanner | 🔲 Stub | — | Globally distributed SQL |
| [MongoDB](mongodb/README.md) | ✅ Complete | 6 | Document store, flexible schema, cross-DC replication, zone sharding |
| Apache HBase | 🔲 Stub | — | Hadoop-integrated wide-column |

---

## Template: Adding a New Technology

Each technology lives in its own sub-folder with 6 files:

```
technologies/<name>/
├── README.md                       # Overview, decision drivers, quick-reference card
├── 01-architecture.md              # How it works: data model, topology, core design
├── 02-read-write-path.md           # Internals: storage engine, read/write flow, key data structures
├── 03-trade-offs-and-alternatives.md # CAP/PACELC position, comparison table, decision narrative
├── 04-tuning-guide.md              # Key parameters with recommended values, anti-patterns
└── 05-production-and-research.md   # Companies using it, research papers, FAANG interview framing
```

**Quality bar for each file**:
- Concrete numbers (latency, throughput, node counts from real deployments)
- A trade-off table with both sides explicitly stated and a recommendation
- A FAANG interview callout section: what to say, what the interviewer is testing
- Diagram (ASCII or Mermaid) for architecture and data flow files
- Production anti-patterns section in the tuning file

Use the Claude command `/tech [technology name]` to generate a new entry following this template.
