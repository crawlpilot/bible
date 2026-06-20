# MongoDB Trade-offs & Alternatives

## CAP Theorem Position

```
        C (Consistency)
            /\
           /  \
          /    \
         / CP   \
        / MongoDB \
       /────────────\
      /  ✓  │       \
     /       │        \
    /─────────────────── \
   CA         │          AP
PostgreSQL     │     Cassandra
CockroachDB    │     DynamoDB
               │     CouchDB
        P (Partition Tolerance)
```

MongoDB is **CP**: under a network partition, MongoDB preserves consistency (only the majority partition can elect a primary and accept writes) at the cost of availability (the minority partition loses write availability).

### What CP Means in Practice

```
Timeline: Network partition between DC1 and DC2

t=0:   Partition occurs — DC1 and DC2 can no longer communicate
t=0:   DC1 has 3/5 nodes (majority) → Primary stays in DC1
       DC2 has 2/5 nodes (minority) → DC2 secondaries go read-only

During partition:
  - DC1 clients: full read/write availability ✓
  - DC2 clients (if they hit DC2 secondaries directly): reads OK but stale;
    writes fail or route to DC1 via driver
  - DC2 clients (if routed to DC1): normal operation, higher latency

t=X:   Partition heals → DC2 secondaries re-sync from oplog
```

**The key difference from Cassandra/DynamoDB**: MongoDB cannot accept conflicting writes from both DCs simultaneously. You never need a conflict resolution strategy (last-write-wins, vector clocks) because there is always exactly one writer (primary).

---

## PACELC Position

**PACELC**: When Partitioned → Availability vs Consistency. Else (no partition) → Latency vs Consistency.

| Scenario | MongoDB choice | Alternative |
|----------|--------------|-------------|
| **P**: Under partition | **C** — minority DC loses writes | AP systems accept writes in both partitions |
| **EL**: No partition | **C** with `w:majority` (higher latency) OR **L** with `w:1` (eventual) | Configurable per-operation |

MongoDB's PACELC classification: **PC/EC** with tunable EC (Else-Consistency vs Else-Latency trade-off controlled by write concern).

---

## Tunable Consistency Matrix

Write concern + read concern combinations determine the actual consistency level:

| Write Concern | Read Concern | Consistency Level | Use Case |
|--------------|-------------|-------------------|---------|
| `w:1` | `local` | Eventual — may read stale or rolled-back data | Logging, analytics events |
| `w:1` | `majority` | Monotonic reads — won't read rolled-back data | Safe reads but low write durability |
| `w:majority` | `local` | Read-your-writes within session | Default for most apps |
| `w:majority` | `majority` | Strong consistency — reads only committed-majority data | Financial operations, inventory |
| `w:majority` | `snapshot` | Snapshot isolation — consistent point-in-time view | Multi-document transactions |
| `w:majority` | `linearizable` | Linearizable — strictest guarantee; confirms majority ack before return | Leader election, distributed locks |

**Production default**: `w:majority` + `readConcern:majority` for critical collections; `w:1` + `readConcern:local` for high-throughput event collections.

**Linearizable read cost**: Must confirm with majority on every read (not just writes) — 2–5× higher read latency. Use only when absolutely required.

---

## Topology Trade-offs

Detailed analysis of each deployment topology and when to choose it.

| Topology | HA? | Geo Redundancy? | RTO | RPO | Write Availability Under DC Loss | Operational Cost |
|---------|-----|----------------|-----|-----|----------------------------------|-----------------|
| **Single node** | No | No | Infinite (manual) | Full data loss possible | No | Lowest |
| **3-node, same DC** | Yes | No | 10–30s | ~0s (w:majority) | N/A — single DC | Low |
| **3-node, 2-DC (2-1 split)** | Yes | Partial | 10–30s if DC2 fails; manual if DC1 fails | ~0s (w:majority) | DC1 fails: manual failover | Low |
| **5-node, 2-DC (3-2 split)** | Yes | Yes | 10–30s (DC2 fails); manual (DC1 fails) | ~0s | DC1 fails: manual; DC2 fails: automatic | Medium |
| **5-node, 3-DC (2-2-1 split)** | Yes | Yes | 10–30s (any single DC fails) | ~0s | Any DC fails: automatic | Medium |
| **Sharded cluster** | Yes (per shard) | Yes (per shard) | Per-shard: 10–30s | ~0s | Per-shard: automatic | High |
| **Global Clusters (Atlas)** | Yes | Yes (multi-region) | < 30s | ~0s | Zone-based: local shard stays available | Very High (managed) |

### 3-2 Split Deep-Dive (Most Common Production Pattern)

```
                 DC1 (Primary DC)                DC2 (DR DC)
                 ─────────────────                ──────────
Nodes:           P (pri=3), S1(pri=2), S2(pri=1)  S3(pri=1), S4(pri=1)
Votes:           3                                 2
Majority:        3 out of 5 → DC1 alone has it

Scenario A — DC2 goes down:
  → DC1 still has 3/5 votes ✓
  → Automatic operation, zero interruption
  → Writes: normal (w:majority = 3 nodes, all in DC1)
  → Reads: DC1 only until DC2 recovers

Scenario B — DC1 goes down:
  → DC2 has only 2/5 votes ✗ (cannot reach majority)
  → NO automatic failover
  → Manual intervention required:
      rs.reconfig({..., force: true})  // reduce voting members
      or: bring DC1 back up

Scenario C — DC1–DC2 network partition (both DCs up, can't talk):
  → DC1 (3 votes): retains primary, continues accepting writes
  → DC2 (2 votes): secondaries go read-only
  → On partition heal: DC2 secondaries re-sync from oplog
```

**Why 3-2 and not 2-2-1 (with arbiter)?**: An arbiter in DC3 makes DC1 failure trigger a cross-DC election that could elect a DC2 secondary. The 3-2 split guarantees DC1 is always the majority DC without an arbiter dependency.

### 2-DC Split Options Comparison

| Split | DC1 votes | DC2 votes | DC1 failure | DC2 failure | Verdict |
|-------|-----------|-----------|-------------|-------------|---------|
| 2-1 (3 nodes) | 2 | 1 | Manual failover | Automatic | Good for low-cost setups |
| 3-2 (5 nodes) | 3 | 2 | Manual failover | Automatic | **Recommended production** |
| 2-2 + arbiter (5 nodes) | 3 (w/arbiter in DC1) | 2 | Manual failover | Automatic | OK but arbiter in DC1 is a single point |
| 2-2 + arbiter (tie-break DC3) | 2+1 | 2 | Depends on DC3 | Depends on DC3 | Fragile — DC3 becomes critical |

### Active-Active Trade-off Analysis

| Approach | True Multi-Primary? | Write Latency | Consistency | Conflict Resolution | When to Use |
|---------|-------------------|--------------|-------------|--------------------|----|
| **MongoDB zone sharding** | No (one primary per zone) | Local to zone (< 5ms) | Strong within zone | Not needed (no conflicts) | Geo-partitioned data with clear ownership |
| **Cassandra** | Yes | < 5ms any DC | Eventual (LWW) | Last-Write-Wins (timestamp) | High write throughput, global scale, AP acceptable |
| **DynamoDB Global Tables** | Yes | Local DDB endpoint | Eventual (LWW) | Last-Write-Wins | Fully managed; DynamoDB ecosystem |
| **CockroachDB** | Yes | ~20–50ms (consensus) | Serializable | Not needed (serializable) | Strong consistency + global active-active (expensive) |
| **MongoDB single-primary** | No | Remote DC RTT if cross-DC | Strong | Not needed | Strong consistency is paramount; global scale not needed |

**The honest answer for FAANG interviews**: MongoDB does not support true active-active writes. If an interviewer asks "how do you handle writes from both US and EU simultaneously with no coordination latency?" — the correct answer is zone sharding (data ownership-based) or switching to Cassandra/DynamoDB for that workload.

---

## Design Trade-offs Made in MongoDB

| Design Decision | What You Gain | What You Give Up |
|----------------|--------------|-----------------|
| **Single primary per replica set** | Strong consistency; no conflict resolution; predictable reads | Write bottleneck at shard level; no leaderless multi-DC writes |
| **Document model (BSON)** | Schema flexibility; nested data in one read; no JOIN overhead | 16MB doc limit; data duplication in embedded model; no referential integrity |
| **Oplog replication (async)** | High write throughput; secondaries don't slow primary | Replication lag; possible stale reads on secondaries |
| **B-tree indexes** | Efficient range queries; sorted results; compound index coverage | Write amplification (every write updates all relevant indexes); index memory usage |
| **WiredTiger MVCC** | Snapshot isolation; non-blocking reads with concurrent writes | Memory overhead for multiple versions; checkpoint cost |
| **`w:majority` write concern** | Durability: write survives primary failure | Higher write latency (+RTT for quorum ACK) |
| **Flexible schema** | No migration scripts; polymorphic documents | No database-enforced constraints; schema drift risk; need app-level validation |
| **Distributed transactions** | Multi-document atomicity | 3–10× write latency overhead; throughput reduction; 60s timeout |
| **Sharding on static key** | Horizontal scale; data locality via zones | Shard key is permanent; bad key choice causes hotspot; cross-shard queries scatter-gather |

---

## MongoDB vs Cassandra

| Dimension | MongoDB | Cassandra | Notes |
|-----------|---------|-----------|-------|
| **Architecture** | Single primary replica set | Leaderless (any node accepts writes) | Fundamental difference — determines multi-DC behavior |
| **CAP** | CP | AP (tunable toward CP) | MongoDB: consistency > availability; Cassandra: availability > consistency |
| **Multi-region writes** | One primary per shard (geo-partitioned via zones) | Any node in any DC accepts writes | Cassandra wins for global active-active write scale |
| **Write throughput** | 20K–50K/sec per shard (scales with shards) | 100K–500K/sec per node (scales linearly) | Cassandra wins for pure write throughput |
| **Query flexibility** | Rich MQL; aggregation pipeline; ad-hoc indexes; $lookup | CQL only; queries must match partition key; no ad-hoc | MongoDB wins for complex queries |
| **Consistency** | Strong by default (w:majority); no conflict resolution | Eventual by default; LWW conflict resolution | MongoDB wins for data integrity |
| **Schema** | Flexible (BSON); schema-on-read | Schema-required; denormalized per query pattern | MongoDB wins for evolving schemas |
| **Data model** | Document (nested objects, arrays) | Wide-column (rows + sorted columns) | MongoDB: general purpose; Cassandra: time-series/append |
| **Transactions** | Multi-document ACID (v4.0+) | LWT (lightweight transactions) only; no multi-row ACID | MongoDB wins for transactional workloads |
| **Operational complexity** | Medium (sharding adds complexity) | Medium (repair, compaction, schema design) | Roughly equivalent at scale |

**Choose MongoDB over Cassandra when**: You have complex, ad-hoc query patterns; schema evolves frequently; you need ACID transactions; strong consistency is required; write throughput fits within shard capacity.

**Choose Cassandra over MongoDB when**: You need true multi-primary global writes; write throughput exceeds 50K/sec; time-series or append-only workload; AP is acceptable; you can define access patterns upfront.

---

## MongoDB vs PostgreSQL (JSONB)

| Dimension | MongoDB | PostgreSQL + JSONB | Notes |
|-----------|---------|-------------------|-------|
| **Data model** | Native document; BSON | Relational + JSONB column as escape hatch | PostgreSQL: relational is first-class; JSONB is an add-on |
| **Joins** | `$lookup` (expensive, no optimizer) | Native JOINs with query planner optimization | PostgreSQL wins for join-heavy workloads |
| **Schema enforcement** | Optional (`$jsonSchema`) | Strong (DDL) or relaxed (JSONB column) | PostgreSQL wins for data integrity |
| **Horizontal scale** | Native sharding | Citus (extension) or Postgres-XL | MongoDB wins for built-in horizontal scale |
| **Full-text search** | Text indexes (limited) | `tsvector`; full FTS capabilities | Both limited vs Elasticsearch |
| **ACID** | Multi-document transactions | Native ACID; full serializable isolation | PostgreSQL wins for complex transactional workloads |
| **Write throughput** | Higher (no WAL sync by default; sharding) | Lower (WAL, lock contention) | MongoDB wins at scale |
| **Indexing on nested fields** | Native (dot notation) | JSON path indexes | MongoDB more ergonomic |

**Choose MongoDB over PostgreSQL when**: Documents are truly heterogeneous; horizontal write scale is needed; schema evolution is frequent; deep nesting is natural to the domain.

**Choose PostgreSQL over MongoDB when**: Data is highly relational; ACID at the row level is critical; you need full JOIN optimization; team is more comfortable with SQL.

---

## MongoDB vs DynamoDB

| Dimension | MongoDB | DynamoDB | Notes |
|-----------|---------|----------|-------|
| **Operations model** | Self-hosted or Atlas (managed) | Fully managed (AWS-only) | DynamoDB: zero ops; MongoDB: ops required (self-hosted) |
| **Query model** | Rich MQL; aggregation pipeline | Key-value + GSI; limited queries; scan expensive | MongoDB wins for query flexibility |
| **Pricing** | License + infra (self-hosted) or Atlas pricing | Per-RCU/WCU; can be expensive at scale | DynamoDB expensive at high throughput; MongoDB predictable |
| **Multi-region active-active** | Zone sharding (limited) | Global Tables (full multi-primary) | DynamoDB wins for managed global active-active |
| **Consistency** | Tunable (CP) | Tunable (eventual default; strong optional) | Similar |
| **Scaling model** | Manual shard management (Atlas: automated) | Automatic (serverless mode) | DynamoDB wins for truly hands-free scaling |
| **Secondary indexes** | Rich (compound, geospatial, text, partial) | GSI (limited; max 20; additional cost) | MongoDB wins for indexing flexibility |
| **Transactions** | Multi-document ACID | Multi-item transactions (limited) | MongoDB more capable |
| **Ecosystem lock-in** | Open source; portable | AWS-only | MongoDB wins for portability |

**Choose MongoDB over DynamoDB when**: You need query flexibility; vendor lock-in is a concern; budget is predictable; team values open-source.

**Choose DynamoDB over MongoDB when**: Pure AWS shop; operational simplicity is paramount; truly serverless scale-to-zero; global active-active required without custom sharding.

---

## MongoDB vs Couchbase

| Dimension | MongoDB | Couchbase | Notes |
|-----------|---------|-----------|-------|
| **Query language** | MQL + aggregation pipeline | N1QL (SQL-like) | Couchbase wins for SQL familiarity |
| **Caching layer** | WiredTiger cache (passive) | Built-in managed caching (Couchbase is also a cache) | Couchbase wins for cache-DB combo |
| **Multi-DC** | Zone sharding; single primary | XDCR (cross-datacenter replication); bi-directional | Couchbase has more mature multi-DC replication |
| **Ecosystem / adoption** | Much larger; better tooling; richer ecosystem | Smaller ecosystem; strong in mobile (Lite) | MongoDB wins on ecosystem |
| **Full-text search** | Text indexes (limited) | Native FTS (Bleve-based) | Couchbase slightly more capable |
| **Mobile sync** | N/A | Couchbase Lite + Sync Gateway | Couchbase wins for mobile-edge-cloud sync |

---

## Decision Flowchart

```
Need a NoSQL data store?
│
├─ Data is naturally relational (foreign keys, joins, complex transactions)?
│   └─ PostgreSQL / CockroachDB / Spanner
│
├─ Need true multi-primary global writes (any DC writes to any record)?
│   ├─ Managed / AWS-only acceptable? → DynamoDB Global Tables
│   ├─ Need SQL + global scale → CockroachDB / Spanner
│   └─ Write-heavy, AP acceptable → Cassandra / ScyllaDB
│
├─ Write throughput > 50K/sec sustained (per collection)?
│   └─ Cassandra / DynamoDB / ScyllaDB
│
├─ Data is document-shaped AND queries are diverse/ad-hoc?
│   ├─ Need strong consistency? → MongoDB (w:majority)
│   ├─ Need managed + global? → MongoDB Atlas / DynamoDB
│   └─ Need geospatial? → MongoDB (2dsphere indexes)
│
├─ Pure key-value at very high QPS (> 100K/sec)?
│   └─ DynamoDB / Redis / Cassandra
│
├─ Time-series at massive scale?
│   └─ Cassandra / InfluxDB / MongoDB Time Series Collections (< 100K events/sec)
│
└─ Need full-text search + document store?
    └─ MongoDB + Elasticsearch side-by-side
       (MongoDB as source of truth; ES for search)
```

---

## Known Limitations of MongoDB

1. **Single primary per shard**: Every shard has exactly one writer. Horizontal write scale requires adding shards, each with its own primary. True multi-primary is not supported.

2. **16 MB document limit**: No document can exceed 16 MB. Large binary data (images, videos) must be stored in GridFS or external object storage (S3).

3. **Shard key immutability (pre-v4.4)**: You cannot change a document's shard key value without deleting and reinserting. In v4.4+, shard key updates are allowed but still constrained.

4. **Cross-shard transactions are expensive**: Distributed 2PC across shards adds significant latency (50–200 ms) and reduces throughput. Design schemas to avoid them.

5. **$lookup does not scale**: Join-like operations (`$lookup`) perform no query optimizer magic — the pipeline does a nested loop join. At millions of documents, this is a full table scan on the `from` collection unless indexed.

6. **WiredTiger cache is not a distributed cache**: Cache is per-node. A sharded cluster's total working set must fit across all shards' caches. If working set exceeds cache, reads go to disk.

7. **Oplog is a single point of replication truth**: All secondaries must stay within the oplog window. A secondary that falls behind (due to read load, network issues, or maintenance) must resync from scratch — expensive for large datasets.

8. **Election timeout is 10 seconds**: Under primary failure, writes are unavailable for up to 30 seconds (election timeout + election + new-primary-accepts-writes). This is acceptable for most workloads but not for sub-second RTO requirements.

---

## FAANG Interview Callout

> "MongoDB's biggest trade-off is the single-primary model. It gives you strong consistency — no conflict resolution, no eventual consistency surprises — but it means that under a DC partition, the minority DC loses write availability. This is a deliberate CP choice. If your interviewer asks 'what happens if DC2 goes down in your MongoDB setup?', the answer is: if DC2 has minority votes (3-2 split), nothing happens — DC1 continues normally. If DC1 goes down, DC2 cannot self-elect and you need manual failover. The way to handle that depends on your RTO requirements: if RTO < 30s and you can tolerate manual ops, 3-2 split is fine. If you need automatic failover even for DC1 loss, you need a 3-DC setup (1 node per DC) so any single DC failure still leaves 2/3 nodes.
>
> The fundamental comparison: Cassandra trades consistency for write availability (any DC accepts writes, eventual consistency, LWW conflict resolution). MongoDB trades availability for consistency (one primary, no conflicts, strong reads possible). Choose based on whether your application can tolerate stale reads and conflict resolution logic — if not, MongoDB is the right call."

---

## Related Files

| File | Topic |
|------|-------|
| [01-architecture.md](01-architecture.md) | Multi-DC topology configurations, election protocol, zone sharding setup |
| [02-read-write-path.md](02-read-write-path.md) | Write concern internals, active-active zone sharding implementation |
| [04-tuning-guide.md](04-tuning-guide.md) | Write concern tuning, read preference tuning, cross-DC parameters |
| [05-production-and-research.md](05-production-and-research.md) | Real-world MongoDB vs Cassandra decisions at Uber, LinkedIn, Shopify |
