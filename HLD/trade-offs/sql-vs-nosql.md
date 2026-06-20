# Trade-off: SQL vs NoSQL

**Category**: HLD · Data Storage · Architecture Decision  
**FAANG interview trigger**: "What database would you use for X?" — the correct answer always starts with trade-offs, never with a tool name.

---

## Context

Every system design interview that involves persistent storage will test whether you can choose the right data model and consistency model for the use case. The SQL vs NoSQL question is rarely binary — production systems at FAANG typically use both, with each handling the workloads it's optimized for.

The real question is: **what properties does your use case actually require?**

---

## Definitions

**SQL (Relational)**: PostgreSQL, MySQL, Aurora, CockroachDB, Google Spanner  
Properties: schema-on-write, ACID transactions, normalized data, joins, strong consistency by default, vertical + limited horizontal scaling.

**NoSQL** is a family, not a single thing:
| Type | Examples | Optimized For |
|------|----------|---------------|
| Key-Value | Redis, DynamoDB, Riak | Point lookups, caching, sessions |
| Document | MongoDB, Firestore, CouchDB | Semi-structured data, flexible schema |
| Wide-Column | Cassandra, HBase, Bigtable | Time-series, write-heavy, massive scale |
| Graph | Neo4j, Amazon Neptune | Relationship traversal, social graphs |
| Search | Elasticsearch, OpenSearch | Full-text search, faceted queries |

Conflating "NoSQL = MongoDB" or "NoSQL = scales better" is a red flag in interviews. Name the type and explain why.

---

## Comparison

| Dimension | SQL | NoSQL |
|-----------|-----|-------|
| **Schema** | Rigid — enforced at write time | Flexible — enforced at application layer (or not at all) |
| **Transactions** | ACID — multi-row, multi-table | Varies: DynamoDB has single-item ACID; Cassandra has lightweight transactions; most lack multi-document ACID |
| **Consistency** | Strong by default | Eventual by default (tunable in some: Cassandra, DynamoDB) |
| **Query power** | Rich: JOINs, aggregations, window functions, arbitrary predicates | Limited: DynamoDB requires access pattern defined upfront; Cassandra queries must match partition key |
| **Scaling** | Vertical primarily; horizontal via read replicas; sharding is painful | Horizontal natively (Cassandra, DynamoDB auto-shard) |
| **Write throughput** | 10K–100K writes/sec per node (tunable) | Cassandra: 1M+ writes/sec per cluster; DynamoDB: unlimited (provisioned or on-demand) |
| **Latency** | P99 1–10ms (local), 50–100ms (cross-AZ) | DynamoDB: <1ms P99; Cassandra: 2–5ms P99 at scale |
| **Operational complexity** | Complex for sharding; simpler for single-node | DynamoDB: fully managed; Cassandra: operationally demanding |
| **Cost model** | License/instance-based; cheaper at moderate scale | DynamoDB: expensive at high read volume; Cassandra: cheaper at extreme write scale |

---

## When to Choose SQL

**Choose SQL when:**

1. **Data has complex relationships requiring JOINs**: financial systems (accounts, transactions, ledgers), ERP, CRM — these have multi-entity queries that would require denormalization in NoSQL.

2. **You need ACID across multiple entities**: bank transfers (`debit account A, credit account B` — must be atomic), e-commerce order placement (`reserve inventory, create order, charge payment` — must be consistent).

3. **Query patterns are unknown or evolving**: ad-hoc analytics, reporting, dashboards. SQL's query flexibility means you can answer new questions without schema changes. NoSQL requires you to know your access patterns upfront.

4. **Data integrity is critical**: foreign key constraints, unique constraints, check constraints enforced at the DB layer. NoSQL systems enforce none of this — integrity is the application's responsibility.

5. **Team is small or operational complexity must be minimized**: PostgreSQL with good indexing handles 10K QPS for most startups. Prematurely moving to Cassandra introduces operational complexity that a small team can't absorb.

**Real examples**: Stripe's core transaction ledger runs on PostgreSQL. GitHub's core data store is MySQL. Shopify runs most workloads on MySQL with carefully managed sharding.

---

## When to Choose NoSQL

**Choose NoSQL when:**

1. **Write throughput exceeds what a single SQL primary can handle**: >100K writes/sec with low latency requirements → Cassandra, DynamoDB. A SQL primary with synchronous replication saturates at approximately 50K–100K writes/sec on high-end hardware.

2. **Access patterns are simple and known**: user profile lookup by user_id, session data by session_token, product catalog by product_id. If every query is a key lookup, you're paying for SQL's join capability without using it.

3. **You need geographic distribution**: DynamoDB Global Tables, Cassandra multi-datacenter — designed for multi-region active-active. SQL multi-master is possible (CockroachDB, Spanner) but adds latency cost for synchronous replication.

4. **Schema changes frequently (document store)**: Mobile app configs, A/B test parameters, feature flags — where different users might have different schema versions simultaneously. MongoDB handles this without migrations.

5. **Massive time-series data**: IoT telemetry, metrics, log data — Cassandra's append-only write path and time-based compaction strategies outperform SQL for pure append workloads.

**Real examples**: Discord migrated messages from Cassandra to ScyllaDB (not SQL) when they hit billions of messages. Netflix uses Cassandra for viewing history. Uber uses Cassandra for their location data. Twitter's timeline is DynamoDB.

---

## The CAP Theorem Lens

SQL databases traditionally occupy CP space (Consistent + Partition Tolerant, sacrificing Availability — a single primary fails over, causing downtime). NoSQL systems were designed for AP (Available + Partition Tolerant, sacrificing strong consistency).

Modern nuance:
- **Google Spanner and CockroachDB**: CP with global external consistency via TrueTime / hybrid logical clocks — they're "globally consistent SQL" at the cost of higher latency.
- **DynamoDB**: AP by default but offers "strong consistency" reads (at 2× cost) — you choose per-read.
- **Cassandra**: tunable — `QUORUM` reads and writes give strong consistency at the cost of availability; `ONE` gives high availability at the cost of consistency.

In interviews, stating "NoSQL is AP, SQL is CP" is too simplistic. State which specific consistency level you need and which system provides it.

---

## Recommendation Framework (Decision Flowchart)

```
What are the primary access patterns?
├── Point lookups (get by ID) with no relationships → Key-Value NoSQL (DynamoDB, Redis)
├── Complex queries, JOINs, unknown patterns → SQL (PostgreSQL, Aurora)
├── Relationship traversal (friends-of-friends, graph) → Graph DB (Neptune, Neo4j)
├── Full-text search, faceted filtering → Search (Elasticsearch)
├── High-volume time-series, append-only → Wide-column (Cassandra, Bigtable)
└── Semi-structured, evolving schema → Document (MongoDB, Firestore)

What is the write volume?
├── <100K writes/sec → SQL handles it
└── >100K writes/sec → Wide-column NoSQL

What are the consistency requirements?
├── Multi-entity ACID transactions → SQL (or CockroachDB/Spanner for scale)
├── Single-entity strong consistency → DynamoDB (strong reads) or Cassandra (QUORUM)
└── Eventual consistency acceptable → Any NoSQL

What is the operational context?
├── Managed preferred, cost less critical → DynamoDB
├── High write scale, operational team available → Cassandra
├── Standard web app, small team → PostgreSQL
└── Global distribution required → Spanner or DynamoDB Global Tables
```

---

## Trade-off Table Summary

| Choose SQL When | Choose NoSQL When |
|----------------|------------------|
| Multi-entity ACID is required | Single-entity lookups dominate |
| Query patterns are unknown or complex | Access patterns are simple and fixed |
| Data integrity at DB layer needed | Application can enforce integrity |
| <100K writes/sec | >100K writes/sec needed |
| Team prefers operational simplicity | Horizontal scalability is non-negotiable |
| Strong consistency always required | Eventual consistency is acceptable |

---

## FAANG Interview Callouts

**What interviewers want to hear:**
- "For the core user profile data, I'd use DynamoDB because our access pattern is almost entirely `getUserById` and we need <1ms latency at 500K RPS — SQL's join capability would go unused."
- "The financial ledger needs SQL with ACID because a failed charge that still reserves inventory would be a consistency violation we can't handle at the application layer."
- "I'd use both: PostgreSQL for the transactional data (orders, payments) and Cassandra for the activity feed (high write volume, time-series, eventual consistency is fine for feeds)."

**Red flags:**
- "NoSQL scales better" — without specifying what kind of NoSQL or what the bottleneck is
- Choosing SQL for a time-series IoT use case expecting 10M inserts/min
- Choosing MongoDB for a banking ledger without mentioning the lack of multi-document ACID
- Not mentioning the CAP implications of your choice

**Good follow-up questions to ask the interviewer:**
- "What's the expected write volume and access pattern distribution?"
- "Do we have requirements for cross-entity transactional consistency?"
- "Is there a preference for managed services vs. self-managed?"

---

## Hybrid Pattern: Polyglot Persistence

Most FAANG systems use multiple databases, each for the use case it's optimized for:

**Example — E-commerce platform:**
- PostgreSQL: orders, payments, user accounts (ACID required)
- DynamoDB: shopping cart, sessions (key-value, <1ms latency)
- Elasticsearch: product search (full-text, faceted filtering)
- Redis: inventory counts (atomic increment, cache), rate limiting
- Cassandra: product view history, click events (time-series, high write volume)

The challenge with polyglot persistence: **consistency across systems**. If a checkout flow writes to PostgreSQL (order) and DynamoDB (cart cleared) and Cassandra (activity logged), a failure between writes leaves the systems inconsistent. The resolution is usually eventual consistency + idempotent event-driven reconciliation (Saga pattern), not 2PC across systems.
