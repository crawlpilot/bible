# MongoDB — Document Store Deep-Dive

**Type**: Document Store (NoSQL)
**CAP Position**: CP (tunable toward AP)
**Consistency Model**: Tunable — from eventual to linearizable via write concern + read concern
**Origin**: 10gen (now MongoDB Inc.), 2009; open-sourced under AGPL
**Primary Language**: C++

---

## What Is MongoDB?

MongoDB was born out of 10gen's frustration with the impedance mismatch between relational schemas and the flexible, nested data structures modern web applications actually produce. Rather than forcing developers to flatten hierarchical data into rows and joins, MongoDB stores data as **BSON documents** — binary-encoded JSON that preserves nesting, arrays, and dynamic typing. The schema is enforced by the application, not the database, which eliminates migration scripts for schema evolution.

MongoDB's architecture is built around **replica sets**: a group of nodes that maintain identical copies of data via an asynchronous oplog. One node is elected primary and accepts all writes; secondaries replicate changes and can serve reads. Replica sets underpin every deployment — even a standalone developer node is implicitly a single-member replica set. For horizontal scale, MongoDB layers **sharding** on top: a `mongos` router distributes documents across multiple replica sets (shards) based on a user-defined shard key.

This combination — document model + replica set HA + optional sharding — makes MongoDB the most operationally accessible NoSQL database. The trade-off is that it sacrifices the leaderless, multi-primary write path that Cassandra and DynamoDB provide, capping horizontal write throughput at the shard level.

---

## Quick-Reference Card

| Property | MongoDB |
|----------|---------|
| **CAP** | CP (partition-tolerant + consistent; availability sacrificed under partition) |
| **Consistency** | Tunable: `w:1` (eventual) → `w:majority` (strong) → `linearizable` |
| **Data Model** | BSON documents; nested objects, arrays, dynamic schema |
| **Write Path** | App → primary → journal (WAL) → oplog → async replication → secondaries |
| **Read Path** | Query planner → B-tree index scan or collection scan → projection → return |
| **Replication** | Oplog-based async; Raft-inspired election; write concern controls durability |
| **Query Language** | MQL (MongoDB Query Language); aggregation pipeline; full CRUD + ad-hoc queries |
| **Horizontal Scaling** | Range or hash sharding; shard key chosen at creation; mongos router |
| **Multi-DC** | Replica set priority/votes control primary placement; Zone sharding for geo-local reads/writes |
| **Transactions** | Multi-document ACID (v4.0+); distributed transactions across shards (v4.2+); ~3–10× write latency overhead |
| **Operational Overhead** | Medium — replica set is easy; sharding adds config servers, mongos, chunk balancing |
| **Indexing** | B-tree; compound, multikey (array), geospatial, text, partial, sparse, TTL, hashed |

---

## Decision Drivers

Choose MongoDB when **all** of the following are true:

- Data is naturally document-shaped (nested objects, variable fields, polymorphic structures)
- Query patterns are **diverse and ad-hoc** — you cannot enumerate access patterns upfront
- You need **strong consistency** within a shard (CP guarantees matter)
- Write throughput fits within a single shard's capacity (~20K–50K writes/sec per shard)
- Schema evolves frequently across application versions
- You need **rich secondary indexes** (compound, geospatial, text, multikey) without pre-declaring access patterns
- Operational team prefers SQL-like expressiveness over a narrow API (DynamoDB) or column-family model (Cassandra)

---

## Use Cases

| Use Case | Why MongoDB Fits | Example Companies |
|----------|-----------------|-------------------|
| Product catalog | Variable attributes per product type; rich filters; frequent schema evolution | eBay, Shopify |
| User profiles & personalization | Nested preferences, activity history, A/B flags in one document | LinkedIn (early), Uber |
| Content management | Articles with embedded metadata, tags, versions | Forbes, The Weather Channel |
| Real-time IoT telemetry | Time-series collections (v5.0+); flexible sensor schemas | Cisco, Bosch |
| E-commerce orders | Embedded line items + shipping + payment in one document; ACID transactions for inventory | Shopify, Carousell |
| Geospatial applications | 2dsphere indexes; `$near`, `$geoWithin` operators | Foursquare, Uber (early ride matching) |
| Gaming player state | Sparse, rapidly changing document per player; low-latency point reads | EA, Ubisoft |

---

## Anti-Patterns

| Situation | Better Alternative | Why |
|-----------|-------------------|-----|
| Write-heavy time-series at millions of events/sec | Cassandra / InfluxDB / TimescaleDB | MongoDB's single-primary bottlenecks; Cassandra's leaderless model handles this natively |
| Pure key-value lookups at very high throughput | DynamoDB / Redis | Shard key overhead and MQL planner add latency unnecessary for simple gets |
| Heavy OLAP / multi-table join analytics | PostgreSQL / ClickHouse / BigQuery | Aggregation pipeline is powerful but not a columnar engine |
| Global active-active writes (multi-primary) | Cassandra / DynamoDB / CockroachDB | MongoDB has one primary per shard; true multi-primary requires a leaderless system |
| Highly relational data (many foreign-key traversals) | PostgreSQL / CockroachDB | $lookup is expensive; joins do not scale the way relational planners do |
| Extreme operational simplicity (no DBA) | DynamoDB / MongoDB Atlas | Self-hosted sharding requires expertise; Atlas abstracts this but at cost |

---

## Key Numbers

| Metric | Typical Cluster | Large Production |
|--------|----------------|-----------------|
| Writes/sec (single shard, primary) | 5K–20K | 50K (with journaling async) |
| Read latency p50 (indexed) | 1–3 ms | < 1 ms (WiredTiger cache hit) |
| Read latency p99 (indexed) | 5–15 ms | 10–30 ms |
| Max document size | 16 MB | 16 MB (hard limit) |
| Replica set members | 3 (recommended) | 5–7 (cross-DC) |
| Max shards (practical) | 1–10 | 100+ (Atlas) |
| Oplog retention | 24–72 hours | 72–168 hours (size-dependent) |
| WiredTiger cache default | 50% RAM − 1 GB | Tuned to 60–70% RAM |
| Index B-tree fan-out | ~500 keys/page | — |
| Change stream lag | < 100 ms (same DC) | 100–500 ms (cross-DC) |

---

## File Map

| File | What's Inside |
|------|--------------|
| [README.md](README.md) | This file — overview, decision drivers, quick-reference |
| [01-architecture.md](01-architecture.md) | Replica sets, sharding, multi-DC topologies, document model, indexing, transactions |
| [02-read-write-path.md](02-read-write-path.md) | Write path, oplog, WiredTiger journal, read path, query planner, write concern, read preference, cross-DC replication, active-passive vs active-active |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | CAP/PACELC, topology trade-offs, vs Cassandra/PostgreSQL/DynamoDB/Couchbase, decision flowchart |
| [04-tuning-guide.md](04-tuning-guide.md) | Shard key selection, WiredTiger cache, index ESR rule, write concern, anti-patterns, monitoring |
| [05-production-and-research.md](05-production-and-research.md) | Companies (Uber, eBay, Shopify, Coinbase, LinkedIn, Cisco), operational lessons, FAANG interview framing |

---

## FAANG Interview Callout (30-Second Pitch)

> "For a product catalog with 100 million SKUs and highly variable attributes per category — electronics have voltage ratings, clothing has size/color variants, food has expiry dates — MongoDB is the right call. The document model lets each SKU carry its own schema without ALTER TABLE migrations. We get rich secondary indexes for faceted search, strong consistency within a shard via `w:majority`, and horizontal scale-out by sharding on a compound key of `{category, _id}` for even distribution. The trade-off versus Cassandra is that we have a single primary per shard — we can't do leaderless multi-region writes — but for a catalog workload that's read-heavy with occasional writes, that's acceptable. I'd run a 5-node replica set across two DCs with priority 3 in primary DC and priority 1 in DR DC, using `w:majority` for writes and `readPreference: nearest` for catalog reads."
