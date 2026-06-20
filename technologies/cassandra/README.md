# Apache Cassandra — Overview & Decision Guide

**Type**: Wide-column NoSQL  
**CAP Position**: AP (Availability + Partition Tolerance)  
**Consistency Model**: Tunable (ONE → QUORUM → ALL per operation)  
**Data Model**: Wide-column store (keyspace → table → partition → rows)  
**Write Model**: LSM-tree (Log-Structured Merge); write-optimised  
**Origin**: Facebook (2008), open-sourced 2008, Apache top-level 2010

---

## What Is Cassandra?

Apache Cassandra was designed at Facebook in 2008 to power the inbox search feature — a problem that required handling hundreds of millions of writes per day across geographically distributed datacenters with no single point of failure. The design deliberately combines two ideas:

- **Amazon Dynamo** (2007): decentralised ring topology, consistent hashing, tunable consistency, gossip-based peer discovery
- **Google BigTable** (2006): the SSTable/MemTable storage model, column-family data model, bloom filters, compaction

The result is a database that treats writes as first-class — every write hits memory and a sequential commit log (O(1)), making Cassandra capable of sustaining millions of writes per second per cluster while surviving node failures and network partitions without stopping.

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| CAP | AP — never stops accepting writes during a partition |
| Consistency | Tunable per-query: ONE / QUORUM / LOCAL_QUORUM / ALL |
| Data model | Wide-column: partition key + clustering columns + value columns |
| Write path | Commit log → MemTable → SSTable (async flush) |
| Read path | Bloom filter → partition index → SSTables + MemTable merge |
| Replication | Leaderless (peer-to-peer); configurable replication factor |
| Query language | CQL (Cassandra Query Language — SQL-like but restricted) |
| Horizontal scaling | Add nodes; automatic token redistribution via vnodes |
| Multi-DC | NetworkTopologyStrategy — active-active across datacenters |
| Operational overhead | Medium — requires repair scheduling, compaction monitoring |

---

## Decision Drivers: When to Choose Cassandra

**Choose Cassandra when ALL of the following are true:**

1. **Write throughput is the primary bottleneck** — you need to sustain millions of writes/second (IoT sensors, clickstream events, time-series metrics, message history)
2. **Read patterns are known and partition-key-driven** — you can design your schema around a small set of predictable access patterns (no ad-hoc queries, no joins)
3. **Multi-region active-active is required** — you need writes to be accepted in multiple geographic regions simultaneously, with eventual consistency across them
4. **High availability is non-negotiable** — no single point of failure; the cluster must continue operating during node failures or network partitions
5. **Data volume is large** — petabyte-scale, where vertical scaling of a relational DB has hit its ceiling

**The single most important question**: *Can you model your access patterns as partition key lookups?* If yes, Cassandra excels. If no (you need joins, aggregations, or arbitrary filters), choose a relational database or Elasticsearch.

---

## Use Cases

| Use Case | Why Cassandra Fits | Example Company |
|----------|-------------------|----------------|
| **Time-series metrics / IoT** | Write-heavy, partitioned by device + time bucket, TTL for expiry | Netflix (play events), Uber (location history) |
| **Message history / inbox** | Append-heavy, read by user + time range (clustering key) | Discord (message store), Facebook (inbox search origin) |
| **User activity / event log** | High write rate, partitioned by user ID, large row per user | Instagram (activity feeds), Spotify (listening history) |
| **Recommendation features** | Write feature vectors per user, read full partition for inference | Spotify, Netflix |
| **Distributed session store** | Low-latency read/write, TTL-based expiry, no single point of failure | Airbnb, Uber |
| **Product catalogue (read-optimised schema)** | Denormalised wide rows, partition by category | E-commerce platforms |

---

## Anti-Patterns: When NOT to Use Cassandra

| Situation | Better Alternative |
|-----------|-------------------|
| **Ad-hoc queries / complex joins** | PostgreSQL, Spanner, BigQuery |
| **Strong consistency is required** (financial transactions, inventory) | PostgreSQL, CockroachDB, Spanner |
| **Secondary index-heavy access patterns** | Elasticsearch, MongoDB |
| **Small scale** (< 3 nodes, < 100GB) | Operational overhead isn't worth it — use PostgreSQL |
| **OLAP / analytics** | BigQuery, Redshift, ClickHouse |
| **Graph traversals** | Neo4j, JanusGraph |
| **Schema-free / document queries** | MongoDB, DynamoDB |

---

## Key Numbers (Production Scale)

| Metric | Typical Cluster | Large Production |
|--------|----------------|-----------------|
| Nodes | 3–30 | 100–75,000 (Apple) |
| Write throughput per node | ~50K–100K writes/sec | up to 500K with SSD |
| Read latency (p99, single partition) | 1–5 ms | 1–2 ms (ScyllaDB) |
| Data per node | 1–2 TB recommended | up to 4 TB before GC pressure |
| Replication factor | 3 (standard) | 3–5 (multi-DC) |

---

## File Map

| File | What's Inside |
|------|--------------|
| [01-architecture.md](01-architecture.md) | Ring topology, consistent hashing, vnodes, gossip protocol, data model |
| [02-read-write-path.md](02-read-write-path.md) | Write/read path internals, MemTable, SSTable, compaction strategies, tombstones |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | CAP analysis, consistency levels, comparison vs DynamoDB / MongoDB / HBase / ScyllaDB |
| [04-tuning-guide.md](04-tuning-guide.md) | Key parameters with recommended values, JVM tuning, anti-patterns |
| [05-production-and-research.md](05-production-and-research.md) | Research paper, companies using Cassandra, operational lessons, FAANG interview framing |

---

## FAANG Interview Callout (30-second version)

> "I'd reach for Cassandra when I need multi-region active-active with millions of writes per second and the access patterns are predictable partition-key lookups. Cassandra gives me AP — it keeps accepting writes even during a partition. I design my schema around the queries: partition key determines which node holds the data, clustering key determines the sort order within the partition. The trade-offs are no joins, limited secondary indexes, and eventual consistency — so I'd use LOCAL_QUORUM in each DC to get consistency within a region while tolerating cross-DC lag."
