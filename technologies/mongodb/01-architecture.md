# MongoDB Architecture

## Design Philosophy

MongoDB was designed around three convictions:

1. **Data is naturally hierarchical** — embedding related data in one document eliminates the joins that dominate OLTP query latency.
2. **Schemas evolve** — application code, not DDL migrations, should own schema validation. `$jsonSchema` validators are opt-in.
3. **Consistency matters** — unlike Cassandra's eventual-by-default model, MongoDB chose a single-primary design to provide strong consistency guarantees that developers can reason about.

These choices produce a system that is operationally approachable for application teams but trades away the leaderless, multi-primary write path that powers Cassandra/DynamoDB at global write scale.

---

## Replica Set: The Fundamental Unit

Every MongoDB deployment is a **replica set** — a group of `mongod` processes that maintain identical data via oplog replication. A standalone node is just a 1-member replica set.

```
┌─────────────────────────────────────────────────────────────┐
│                      REPLICA SET (rs0)                      │
│                                                             │
│  ┌─────────────┐     oplog     ┌─────────────┐             │
│  │   PRIMARY   │──────────────►│ SECONDARY 1 │             │
│  │  (writes +  │               │ (reads opt) │             │
│  │   reads)    │               └─────────────┘             │
│  └──────┬──────┘                                           │
│         │              oplog   ┌─────────────┐             │
│         └─────────────────────►│ SECONDARY 2 │             │
│                                │ (reads opt) │             │
│  ┌─────────────┐               └─────────────┘             │
│  │   ARBITER   │  (votes only, no data — avoids even nodes) │
│  │  (optional) │                                           │
│  └─────────────┘                                           │
│                                                             │
│  Heartbeat: every 2 seconds between all members            │
│  Election timeout: 10 seconds (default electionTimeoutMS)  │
└─────────────────────────────────────────────────────────────┘
```

### Replica Set Roles

| Role | Votes | Holds Data | Eligible as Primary | Notes |
|------|-------|-----------|--------------------|----|
| Primary | Yes | Yes | Yes | Accepts all writes; at most 1 at a time |
| Secondary | Yes | Yes | Yes (if priority > 0) | Can serve reads with `readPreference` ≠ `primary` |
| Arbiter | Yes | No | No | Tie-breaking vote only; use sparingly — adds no redundancy |
| Hidden | Yes | Yes | No (priority = 0) | Invisible to drivers; used for backups / delayed replicas |
| Delayed | Yes | Yes | No (priority = 0) | Lags behind primary by `secondaryDelaySecs`; disaster recovery |

### Election Protocol (Raft-Inspired)

MongoDB uses a **Raft-like** consensus algorithm (not pure Raft) for elections:

1. A member suspects the primary is down after missing heartbeats for `electionTimeoutMillis` (default 10s).
2. It increments its term, sets itself to CANDIDATE, and requests votes from peers.
3. A candidate wins if it receives votes from a **majority of all voting members** (not just reachable members).
4. The member with the **highest oplog timestamp** among candidates wins ties.
5. New primary begins accepting writes; old primary (if it comes back) steps down automatically.

**Key constraint**: Majority of *all* voting members — not just reachable ones — must agree. A 3-node set loses write availability if 2 nodes are down, even if 1 is reachable. This is the CP tradeoff.

---

## Sharding Architecture

Sharding horizontally partitions a collection across multiple replica sets (shards). It adds three new components:

```
┌──────────────────────────────────────────────────────────────────┐
│                     SHARDED CLUSTER                              │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                   │
│  │ mongos 1 │    │ mongos 2 │    │ mongos 3 │  ← Routers        │
│  │ (router) │    │ (router) │    │ (router) │    (stateless)    │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘                   │
│       └───────────────┴───────────────┘                         │
│                           │ chunk routing table                  │
│                    ┌──────▼──────┐                               │
│                    │  Config     │  ← Config Server Replica Set  │
│                    │  Servers    │    (CSRS, 3 nodes)            │
│                    │  (CSRS)     │    Stores chunk map           │
│                    └─────────────┘                               │
│                           │                                      │
│          ┌────────────────┼────────────────┐                     │
│          ▼                ▼                ▼                     │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│   │  Shard 1    │  │  Shard 2    │  │  Shard 3    │ ← Each      │
│   │ (Replica    │  │ (Replica    │  │ (Replica    │   shard is  │
│   │  Set rs1)   │  │  Set rs2)   │  │  Set rs3)   │   a replica │
│   └─────────────┘  └─────────────┘  └─────────────┘   set      │
└──────────────────────────────────────────────────────────────────┘
```

### Shard Key Types

| Type | How It Works | Pros | Cons | When to Use |
|------|-------------|------|------|------------|
| **Hashed** | MD5 hash of field → uniform distribution | Even writes; avoids hotspots | Cannot do range queries on shard key; scatter-gather reads | High-cardinality monotonic keys (ObjectId, timestamps) |
| **Ranged** | Documents sorted by key value; adjacent ranges on same shard | Range queries stay on one shard; efficient sequential reads | Monotonic keys create write hotspot on last shard | Non-monotonic high-cardinality fields; geographic zone sharding |
| **Compound** | Combination of two fields (e.g., `{country, userId}`) | Balance distribution + locality | Must include all prefix fields in queries | Multi-tenant, geo-partitioned workloads |
| **Zone sharding** | Tag shards with zones; assign key ranges to zones | Data locality for geo; compliance (data residency) | Manual zone management; operational overhead | GDPR-scoped data; active-active geo patterns |

### Chunk Mechanics

- A **chunk** is a contiguous range of the shard key space, default 128 MB.
- The **balancer** (runs on CSRS) migrates chunks between shards to equalize data distribution.
- Chunk migrations consume I/O and network; tune `_secondaryThrottle` to limit replication impact during migration.
- Watch for **chunk imbalance** after bulk inserts or when a bad shard key creates a hotspot.

---

## Multi-DC Topologies

This is the most operationally critical section. The topology determines your RTO, RPO, and write availability under DC failure.

### Topology 1 — Single-DC Replica Set (Dev / Low-Stakes)

```
DC1: Primary + Secondary1 + Secondary2
```
- **Write HA**: Survives 1 node failure.
- **DC failure**: Total outage.
- **Use when**: Single-region product, no DR requirement.

### Topology 2 — 2-DC Active-Passive (Majority in Primary DC)

```
DC1 (primary DC):  Primary (priority=3) + Secondary1 (priority=2)
DC2 (DR DC):       Secondary2 (priority=1)
```

```
┌──────────────────────┐         ┌──────────────────────┐
│         DC1          │         │         DC2          │
│  ┌──────────────┐    │  oplog  │   ┌──────────────┐   │
│  │   PRIMARY    │    │────────►│   │  SECONDARY   │   │
│  │ (priority=3) │    │         │   │  (priority=1)│   │
│  └──────────────┘    │         │   └──────────────┘   │
│  ┌──────────────┐    │         │                      │
│  │  SECONDARY   │    │         │                      │
│  │ (priority=2) │    │         │                      │
│  └──────────────┘    │         │                      │
└──────────────────────┘         └──────────────────────┘
     Majority (2/3 votes)           Minority (1/3 votes)
```

- **Write quorum**: `w:majority` = 2 nodes. DC1 can commit without DC2.
- **DC1 failure**: DC2 Secondary cannot elect itself (only 1/3 votes). **No automatic failover** — manual intervention required.
- **DC2 failure**: No impact. Cluster continues normally.
- **RPO** on DC1 failure: Data in DC2 is behind by replication lag (typically < 1s, but async means gap exists).
- **RTO** on DC2 failure: ~0 seconds (DC2 is passive, no election needed).
- **When to use**: Disaster recovery / warm standby. DC2 provides a readable replica for reporting.

### Topology 3 — 2-DC Even Split (Anti-Pattern: Avoid)

```
DC1: Primary (priority=2) + Secondary1 (priority=1)
DC2: Secondary2 (priority=1) + Secondary3 (priority=1)
```

**Problem**: 4-node set with 2 nodes per DC. Under DC split:
- Neither DC has majority (2/4). **Both DCs lose write availability**.
- Fix: Add an arbiter in a 3rd location (tie-breaker), or go to 3-2 split.

### Topology 4 — 2-DC 3-2 Split (Recommended Production Pattern)

```
DC1 (primary DC):  Primary (priority=3) + Secondary1 (priority=2) + Secondary2 (priority=1)
DC2 (DR DC):       Secondary3 (priority=1) + Secondary4 (priority=1)
```

```
┌────────────────────────────────┐      ┌─────────────────────────┐
│              DC1               │      │           DC2           │
│  ┌──────────┐  ┌──────────┐    │oplog │  ┌────────┐ ┌────────┐  │
│  │ PRIMARY  │  │  SEC 1   │    │─────►│  │ SEC 3  │ │ SEC 4  │  │
│  │ (pri=3)  │  │ (pri=2)  │    │      │  │(pri=1) │ │(pri=1) │  │
│  └──────────┘  └──────────┘    │      │  └────────┘ └────────┘  │
│       ┌──────────┐             │      │                         │
│       │  SEC 2   │             │      │                         │
│       │ (pri=1)  │             │      │                         │
│       └──────────┘             │      │                         │
└────────────────────────────────┘      └─────────────────────────┘
   3 votes — can form majority             2 votes — cannot form majority alone
```

- **DC1 failure**: DC2 has 2/5 votes — **cannot elect primary**. Requires manual `rs.stepDown()` + `rs.reconfig()`.
- **DC2 failure**: DC1 has 3/5 votes — automatic re-election in DC1. Service continues.
- **DC1 is the "majority" DC** — this is truly active-passive.
- **`w:majority`** = 3 nodes. A write that reaches 3 nodes survives DC2 loss AND 1 node failure in DC1.
- **When to use**: Standard production DR setup. Primary DC is authoritative; DR DC is for failover and read offload.

### Topology 5 — 3-DC Active-Active-Active (1-1-1 Split, Lowest RPO)

```
DC1: Primary (priority=3) + Secondary (priority=1)
DC2: Secondary (priority=2) + Secondary (priority=1)
DC3: Secondary (priority=1) + Arbiter (optional)
```

Or simpler 3-member version:
```
DC1: Primary (priority=3)
DC2: Secondary (priority=2)
DC3: Secondary (priority=1)
```

- **Any single DC failure**: Remaining 2 DCs have 2/3 votes — automatic election.
- **RPO**: Near-zero if `w:majority` used (write confirmed on 2 of 3 DCs before ack).
- **Write latency**: Increased by cross-DC RTT for `w:majority` (e.g., 40–80 ms for US multi-region).
- **"Active-active"**: All 3 DCs serve reads (`readPreference: nearest`). Only one DC holds primary for writes.
- **When to use**: Mission-critical, RPO~0, RTO < 30s. Accept higher write latency.

### Topology Configuration Example (3-2 Split)

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "dc1-node1:27017", priority: 3 },
    { _id: 1, host: "dc1-node2:27017", priority: 2 },
    { _id: 2, host: "dc1-node3:27017", priority: 1 },
    { _id: 3, host: "dc2-node1:27017", priority: 1 },
    { _id: 4, host: "dc2-node2:27017", priority: 1 }
  ]
});
```

### Points to Keep in Mind for Multi-DC Design

| Decision | Recommendation | Rationale |
|---------|----------------|-----------|
| Majority DC placement | Put majority of voting members in primary DC | Ensures automatic failover stays in primary DC; DR DC cannot accidentally become primary |
| Write concern | `w:majority` always in production | Survives primary failure with no data loss; `w:1` risks data loss on failover |
| Read preference | `readPreference: nearest` for read-heavy paths | Reduces cross-DC read latency; accept stale secondaries |
| Oplog size | 72–168 hours retention | Long enough for secondary to catch up after network partition or maintenance |
| Priority settings | Primary DC nodes: priority 2–3; DR DC nodes: priority 1 | Ensures primary always re-elects in primary DC after transient DC2 failure |
| Arbiter usage | Avoid in production (especially cross-DC) | Arbiter adds a vote without adding data redundancy; in cross-DC it can swing election to DR DC unexpectedly |
| Tag sets | Use tags for zone-aware read routing | Allows `readPreference` to target specific DC replicas |

---

## Document Model

### BSON Data Types

MongoDB stores data as **BSON** (Binary JSON) — a superset of JSON that adds types not present in JSON:

| BSON Type | Use Case | Notes |
|-----------|----------|-------|
| ObjectId | Default `_id` | 12-byte: 4B timestamp + 5B random + 3B counter. Monotonically increasing — **avoid as shard key** |
| String (UTF-8) | Text fields | — |
| Int32 / Int64 | Counters, quantities | Use Int64 for values > 2B |
| Double | Floating point | Imprecise; use Decimal128 for money |
| Decimal128 | Financial values | Exact decimal arithmetic |
| Date | Timestamps | Stored as UTC milliseconds since epoch |
| Boolean | Flags | — |
| Array | One-to-many embedded | Indexed with multikey index |
| Embedded Document | Nested objects | Queried with dot notation |
| BinData | Binary, UUIDs | — |
| Null | Missing values | Distinct from field absence |

### Embedding vs. Referencing

The central schema design decision in MongoDB:

| Pattern | When to Embed | When to Reference |
|---------|--------------|------------------|
| **Embed** | "Has-a" relationship; child rarely queried without parent; bounded size | Orders with line items; blog posts with comments (< 100) |
| **Reference** | "Belongs-to" many parents; unbounded growth; child queried independently | Products in many orders; users in many groups |
| **Hybrid** | Frequently accessed fields embedded; full detail referenced | Embed `{userId, name, avatar}` in post; reference full user profile |

**Rule**: Embed when data is accessed together and bounded in size. Reference when unbounded growth would exceed the 16 MB document limit or when the referenced document is updated frequently by many writers.

---

## Indexing Internals

MongoDB indexes use a **B-tree** structure (WiredTiger's implementation uses a B+-tree variant).

### Index Types

| Index Type | Syntax | Use Case |
|-----------|--------|---------|
| Single field | `{field: 1}` or `{field: -1}` | Simple equality or range on one field |
| Compound | `{a: 1, b: 1, c: -1}` | Multi-field queries; follow ESR rule |
| Multikey | `{tags: 1}` on array field | Queries on array elements; one key per array element |
| Geospatial (2dsphere) | `{location: "2dsphere"}` | `$near`, `$geoWithin`, `$geoIntersects` |
| Text | `{body: "text"}` | Full-text search; tokenization; stemming |
| Hashed | `{_id: "hashed"}` | Shard key for uniform distribution |
| Partial | `{status: 1}, {partialFilterExpression: {status: "active"}}` | Index only documents matching a filter; smaller index |
| Sparse | `{optionalField: 1}, {sparse: true}` | Exclude documents without the field |
| TTL | `{createdAt: 1}, {expireAfterSeconds: 3600}` | Auto-delete documents after duration |
| Wildcard | `{"$**": 1}` | Dynamic schemas with arbitrary field names |

### Covered Queries

A **covered query** is one where the index contains all projected fields — MongoDB never reads the document itself:

```javascript
// Index: {status: 1, createdAt: -1, _id: 1}
// Query (covered): returns only status + createdAt — no doc fetch
db.orders.find(
  { status: "shipped" },
  { status: 1, createdAt: 1, _id: 0 }
).sort({ createdAt: -1 })
```

**Performance**: Covered queries can be 10–100× faster than document-fetching queries at scale.

---

## Transactions

MongoDB supports **multi-document ACID transactions** (v4.0+) and **distributed transactions across shards** (v4.2+).

### Transaction Lifecycle

```javascript
const session = client.startSession();
session.startTransaction({
  readConcern: { level: "snapshot" },
  writeConcern: { w: "majority" }
});
try {
  await orders.insertOne({ ... }, { session });
  await inventory.updateOne({ sku: "X" }, { $inc: { qty: -1 } }, { session });
  await session.commitTransaction();
} catch (err) {
  await session.abortTransaction();
} finally {
  session.endSession();
}
```

### Transaction Trade-offs

| Property | Single-Document Operation | Multi-Document Transaction |
|---------|--------------------------|--------------------------|
| Latency overhead | Baseline | +3–10× (lock acquisition, 2PC for sharded) |
| Throughput impact | None | Reduces overall throughput by holding locks |
| Max duration | N/A | 60 seconds default (`transactionLifetimeLimitSeconds`) |
| Cross-shard | N/A | Supported (v4.2+); uses 2-phase commit via coordinator |
| WiredTiger snapshot | Per-operation | Entire transaction sees consistent snapshot |

**Principal engineer note**: Design schemas to make single-document operations sufficient for the hot path. Reserve transactions for cases with true atomicity requirements (e.g., financial transfers, inventory decrement + order creation). Transactions at high QPS will become a throughput bottleneck.

---

## FAANG Interview Callout

> "MongoDB's architecture is built around three layers: the document model, the replica set, and optional sharding. The replica set is the key unit — a Raft-inspired single-primary consensus group where all writes go to the primary, get written to a WAL journal and then the oplog, and asynchronously replicate to secondaries. The oplog is an idempotent, capped, append-only log — this is what change streams, replica sync, and point-in-time recovery all depend on.
>
> For multi-DC, the critical insight is: MongoDB is CP, meaning a partition that takes away the majority DC causes the minority DC to lose write availability. A 3-2 cross-DC split with majority in the primary DC is the standard pattern — DC2 failure causes no interruption; DC1 failure requires manual failover. For RPO~0 requirements, use `w:majority` — writes that are ack'd survived even if the primary crashes immediately after.
>
> The shard key is the most consequential schema decision. You cannot change it without a collection rebuild. A monotonic key (ObjectId, timestamp) creates a write hotspot on the last shard — always use a hashed shard key or compound key that distributes writes uniformly."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | Oplog mechanics, write concern, read preference, replication lag, active-passive failover |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | CAP analysis, topology trade-offs, vs Cassandra / PostgreSQL / DynamoDB |
| [04-tuning-guide.md](04-tuning-guide.md) | Shard key selection, WiredTiger cache, index tuning, cross-DC parameters |
| [05-production-and-research.md](05-production-and-research.md) | Production case studies, operational lessons, FAANG system design framing |
