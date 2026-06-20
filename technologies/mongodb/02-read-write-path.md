# MongoDB Read & Write Path

## Write Path

Every write in MongoDB follows this path — whether it's an insert, update, or delete.

```
Application
    │
    ▼
MongoDB Driver (connection pool, retry logic, write concern negotiation)
    │
    ▼  [if sharded cluster]
mongos Router  ──── Config Server ───► chunk map lookup → target shard(s)
    │
    ▼  [always]
Primary (mongod)
    │
    ├──► 1. Acquire document-level lock (WiredTiger MVCC — no collection lock for most ops)
    │
    ├──► 2. Write to WiredTiger journal (WAL) — fsync controlled by journalCommitInterval
    │         └── Sequential write; survives crash before checkpoint
    │
    ├──► 3. Apply to in-memory WiredTiger cache (B-tree page update)
    │         └── Dirty pages written to data files at checkpoint (default every 60s)
    │
    ├──► 4. Append to oplog (local.oplog.rs)
    │         └── Capped collection; idempotent operations; timestamped with BSON Timestamp
    │
    └──► 5. Return ACK to client (timing depends on write concern — see below)
              │
              ▼  [async, after ACK]
    Secondaries pull oplog entries → apply to their own storage engines
```

### Key Insight: Sequential I/O

The journal write (step 2) and oplog append (step 4) are both **sequential, append-only** operations. This means even on spinning HDDs, write throughput is predictable. WiredTiger's B-tree updates (step 3) are random I/O but happen in memory first, then flushed via checkpoint — reads of hot data hit RAM, not disk.

---

## WiredTiger Journal (WAL)

The **journal** is MongoDB's write-ahead log. It ensures durability between checkpoints:

| Property | Value | Notes |
|----------|-------|-------|
| Location | `dbPath/journal/` | Separate from data files; put on fast SSD |
| Sync mode | Every `journalCommitInterval` ms (default 100ms) | Controls max data loss window on crash |
| Size | Up to 100 MB per journal file | Rotated automatically |
| Encryption | Available (MongoDB Enterprise) | Required for compliance workloads |
| Fsync behavior | `j: true` in write concern forces immediate fsync | See write concern section |

**Without journaling** (deprecated; not recommended): MongoDB relied on checkpoints only, meaning a crash could lose up to 60 seconds of data. Always run with journaling enabled (the default).

---

## Oplog: The Replication Log

The **oplog** (`local.oplog.rs`) is the mechanism by which all replication, change streams, and point-in-time recovery work.

### Oplog Properties

| Property | Details |
|----------|---------|
| **Type** | Capped collection in the `local` database |
| **Format** | Each entry is an idempotent operation (insert, update expressed as full document replacement or delta, delete) |
| **Retention** | Size-based (default: 5% of free disk, min 990 MB, max 50 GB) OR time-based (v4.4+: `oplogMinRetentionHours`) |
| **Idempotency** | Updates rewritten as `$set` with full field values, not relative deltas — safe to re-apply |
| **Timestamp** | BSON Timestamp: 32-bit seconds + 32-bit ordinal within second |
| **Access** | `db.getReplicationInfo()` to see oplog window; secondaries use it to sync |

### Oplog Sizing Rules

```
Oplog window (hours) = oplog size (GB) / (write rate GB/hour)

Minimum recommended: 24 hours
Production recommendation: 72–168 hours

Why: A secondary that falls off the oplog tail (replication lag > oplog window)
     must do a full initial sync — expensive and causes replication lag to worsen.
```

```javascript
// Set oplog size at startup (mongod.conf):
replication:
  oplogSizeMB: 51200   # 50 GB

// Or set minimum retention (v4.4+):
replication:
  oplogMinRetentionHours: 72
```

### Oplog Entry Example

```javascript
// A findOneAndUpdate operation appears in oplog as:
{
  "op": "u",                          // u=update, i=insert, d=delete, c=command
  "ns": "ecommerce.orders",           // namespace
  "o": {                              // operation document (idempotent delta)
    "$v": 2,
    "diff": { "u": { "status": "shipped", "updatedAt": ISODate("...") } }
  },
  "o2": { "_id": ObjectId("...") },  // filter (which document)
  "ts": Timestamp(1718000000, 1),     // oplog timestamp
  "t": NumberLong(5),                 // term (election term)
  "v": NumberLong(2),                 // protocol version
  "wall": ISODate("2024-06-10T..."),  // wall clock time
  "lsid": { ... },                    // session ID (for transactions)
  "txnNumber": NumberLong(42)         // transaction number (for transactions)
}
```

---

## Read Path

```
Application
    │
    ▼
MongoDB Driver (read preference selection → pick target node)
    │
    ├── readPreference=primary  → Primary
    ├── readPreference=secondary → Any Secondary
    └── readPreference=nearest  → Node with lowest RTT
              │
              ▼
Target mongod
    │
    ├──► 1. Parse query → create query plan candidates
    │
    ├──► 2. Query planner: evaluate candidate plans
    │         └── Uses index statistics, collection cardinality estimates
    │         └── Runs competing plans in parallel ("plan cache tournament")
    │         └── Winning plan cached in plan cache
    │
    ├──► 3. Execute winning plan:
    │         ├── IXSCAN (index scan) → follow B-tree → get matching RecordIds
    │         │     └── Covered query: return index data directly (no doc fetch)
    │         └── COLLSCAN (collection scan) → sequential scan of all documents
    │
    ├──► 4. Fetch documents from WiredTiger (if not covered query)
    │         └── WiredTiger B-tree lookup by RecordId → in-memory cache or disk
    │
    ├──► 5. Apply projection (keep only requested fields)
    │
    └──► 6. Return cursor / batch to driver
```

### Reading `explain()` Output

```javascript
db.orders.find({ status: "shipped", userId: ObjectId("...") })
         .explain("executionStats")
```

Key fields to inspect:

| Field | What It Tells You |
|-------|------------------|
| `stage: "IXSCAN"` | Index scan used — good |
| `stage: "COLLSCAN"` | No index — potentially full table scan |
| `stage: "FETCH"` | Document fetch after index scan — okay if selectivity is high |
| `nReturned` | Documents returned to client |
| `totalDocsExamined` | Documents read from storage |
| `totalKeysExamined` | Index keys scanned |
| `executionTimeMillis` | Wall time |

**Efficiency signal**: `nReturned / totalDocsExamined` should be close to 1.0. A ratio of 0.01 means you're scanning 100 docs to return 1 — add or improve the index.

---

## Write Concern

Write concern controls **when MongoDB considers a write "done"** and acknowledges it to the client. It is the primary durability lever.

| Level | `w` value | Journal (`j`) | What It Means | Durability | Latency Impact |
|-------|-----------|--------------|--------------|------------|---------------|
| Unacknowledged | `w: 0` | — | Fire-and-forget; no error detection | None — data loss possible | Lowest |
| Acknowledged | `w: 1` | `j: false` | Primary received write; not yet flushed to journal | Lost on primary crash before checkpoint | Low |
| Journaled | `w: 1` | `j: true` | Primary wrote to journal; survives crash | Survives primary crash | +1–5 ms (journal fsync) |
| Majority | `w: "majority"` | `j: true` (default v5+) | Write replicated to majority of voting members | Survives primary failover with no data loss | +cross-DC RTT (if multi-DC) |
| Custom tag | `w: "tag_name"` | configurable | Write confirmed on members matching tag | Zone-specific durability | Depends on tag members |
| All members | `w: N` (total count) | configurable | All N members confirmed | Maximum durability | Highest |

### Production Recommendation

```javascript
// Default write concern for most operations:
{ w: "majority", j: true, wtimeout: 5000 }

// For non-critical, high-throughput bulk writes (analytics events, logs):
{ w: 1, j: false }

// Never use w:0 in production — you won't know if writes failed
```

**`w: "majority"` with multi-DC**: The write must reach nodes in enough DCs to satisfy the majority. In a 3-2 DC split, `w:majority` = 3 nodes. If DC2 is unreachable, the primary in DC1 and its 2 DC1 secondaries can still satisfy majority — the write succeeds. This is the key advantage of the 3-2 split.

---

## Read Preference

Read preference controls **which replica set member** handles a read operation.

| Mode | Reads From | Stale Risk | Latency | When to Use |
|------|-----------|-----------|---------|------------|
| `primary` | Primary only | None (always current) | Highest (may be cross-DC) | Financial reads, inventory checks, anything requiring strong consistency |
| `primaryPreferred` | Primary if available; else secondary | Low (brief lag) | Medium | High availability reads; acceptable to be slightly stale |
| `secondary` | Any secondary | Yes (replication lag) | Lower (local DC replica) | Analytics, reporting, bulk exports that can tolerate stale data |
| `secondaryPreferred` | Secondary if available; else primary | Yes | Lowest | Offload read traffic; reporting dashboards |
| `nearest` | Member with lowest RTT | Yes (for secondaries) | Lowest | Latency-sensitive reads in multi-DC; geo-local reads |

### Tag Sets for Zone-Aware Reads

```javascript
// Tag replicas in each DC:
rs.conf().members[2].tags = { "dc": "us-east", "use": "analytics" };

// Read from us-east DC only:
db.orders.find({}).readPref("secondary", [{ dc: "us-east" }]);

// Read from analytics-tagged replicas only:
db.orders.find({}).readPref("secondary", [{ use: "analytics" }]);
```

---

## Cross-DC Replication: Internals

### How Secondaries Replicate

1. Secondary maintains a **replication thread** that tails the primary's oplog (or another secondary's oplog in chained replication).
2. Each secondary tracks its **last applied oplog timestamp** — the `lastApplied` timestamp in `rs.status()`.
3. Secondaries apply oplog entries using **multiple parallel applier threads** (default: 16 threads, controlled by `replWriterThreadCount`).
4. Writes within a single session are applied in order (causal consistency); cross-session writes are applied in parallel.

### Replication Lag

**Replication lag** = timestamp of primary's last oplog entry − secondary's `lastApplied` timestamp.

```javascript
// Check replication lag:
rs.printReplicationInfo();      // oplog window on primary
rs.printSecondaryReplicationInfo();  // lag per secondary

// In rs.status() output:
db.adminCommand({ replSetGetStatus: 1 }).members.forEach(m => {
  if (m.stateStr === "SECONDARY") {
    print(m.name, "lag:", m.optimeDate, "optime lag:", m.lastApplied);
  }
});
```

### Replication Lag Causes

| Cause | Symptom | Fix |
|-------|---------|-----|
| High write throughput exceeding secondary apply rate | Lag grows monotonically | Increase `replWriterThreadCount`; add more shards |
| Large index builds | Lag spikes during build | Use rolling index builds; schedule during low traffic |
| Secondary under heavy read load | CPU/IO saturation on secondary | Separate analytics replicas; use `readPreference: secondary` sparingly |
| Network partition or congestion | Lag spikes then recovers | Improve cross-DC bandwidth; monitor `replicationLagSeconds` |
| Secondary falls off oplog tail | Secondary enters initial sync | Increase oplog size; catch issue before it happens |

**Alert threshold**: Lag > 10 seconds = warning; Lag > 60 seconds = critical.

---

## Active-Passive Replication: Failover Deep-Dive

### Normal Operation (Steady State)

```
Client writes → Primary (DC1) → journal ACK → oplog append → ACK to client
                                                    │
                                               async replication
                                                    ▼
                                         Secondary 1 (DC1) ←── lag: < 100ms
                                         Secondary 2 (DC2) ←── lag: 50-500ms (cross-DC)
```

### Primary Failure Scenario

```
t=0:    Primary (DC1) crashes
t=0–10s: Secondaries miss heartbeats → wait electionTimeoutMillis (10s default)
t=10s:  Secondary 1 (DC1) starts election — sends RequestVotes RPC
t=10s:  Secondary 2 (DC2) also starts election — candidates compete
t=11s:  Winner: Secondary with highest oplog timestamp AND sufficient votes
        → New primary elected (likely DC1 Secondary 1 if priority higher)
t=11s:  New primary begins accepting writes
t=11–30s: Old primary recovers → detects new term → steps down → becomes secondary
```

**RTO**: 10–30 seconds (election timeout + replication catch-up)
**RPO**: Up to `replication lag` at time of failure (typically < 1s with `w:majority`)

### Planned Failover (Zero-Downtime Maintenance)

```javascript
// Step 1: On current primary, step down gracefully
// MongoDB will elect a new primary before stepping down
db.adminCommand({ replSetStepDown: 60, secondaryCatchUpPeriodSecs: 30 });

// Step 2: Verify new primary
rs.status();

// Step 3: Perform maintenance on old primary (now a secondary)
// Step 4: Return to desired topology (adjust priorities if needed)
```

**RTO for planned failover**: < 5 seconds (secondaries are already caught up; election is fast when all nodes are healthy).

---

## Active-Active: What MongoDB Actually Supports

MongoDB does **not** natively support multi-primary writes the way Cassandra or DynamoDB do. There is exactly one primary per replica set (and one primary per shard in a sharded cluster).

### What "Active-Active" Means in MongoDB Context

| Approach | What It Is | Trade-off |
|----------|-----------|-----------|
| **Zone sharding** | Shard key ranges pinned to specific DC zones; each DC is "primary" for its range | Writes for your data stay local; cross-zone reads scatter-gather; requires zone-aware shard key design |
| **Multi-region reads** | All DCs serve reads via `readPreference: nearest`; one DC gets writes | Read latency is local; write latency is remote for non-primary DCs |
| **MongoDB Atlas Global Clusters** | Atlas-managed zone sharding + cross-cluster sync + local read routing | Fully managed; write latency to local shard; cross-zone data requires scatter-gather |
| **True multi-primary** | Not supported | Use Cassandra / DynamoDB / CockroachDB if required |

### Zone Sharding for Geo-Partitioned Active-Active

```javascript
// Tag shards with zones:
sh.addShardTag("shard0001", "US");
sh.addShardTag("shard0002", "EU");

// Assign key ranges to zones:
sh.addTagRange("users.profiles",
  { region: "US", _id: MinKey },
  { region: "US", _id: MaxKey },
  "US"
);
sh.addTagRange("users.profiles",
  { region: "EU", _id: MinKey },
  { region: "EU", _id: MaxKey },
  "EU"
);
```

**Result**: US users' data stays on US shards (local writes for US clients); EU users' data stays on EU shards. Cross-region queries (e.g., join a US user with EU order) still scatter-gather. Shard key must include `region` as the prefix.

---

## Aggregation Pipeline

The aggregation pipeline processes documents through a sequence of stages, similar to Unix pipes.

### Stage Execution Order (Performance-Critical)

```javascript
db.orders.aggregate([
  { $match: { status: "shipped", createdAt: { $gte: ISODate("2024-01-01") } } }, // FIRST: filter early
  { $sort: { createdAt: -1 } },          // SECOND: sort before $group if possible (index sort)
  { $group: { _id: "$customerId", total: { $sum: "$amount" } } },
  { $lookup: {                            // LAST: $lookup is expensive — apply after reducing docs
      from: "customers",
      localField: "_id",
      foreignField: "_id",
      as: "customer"
  }},
  { $project: { customer: 1, total: 1, _id: 0 } }
]);
```

### Aggregation Pipeline: Key Stages

| Stage | Purpose | Performance Note |
|-------|---------|-----------------|
| `$match` | Filter documents (like `WHERE`) | Put first; uses indexes |
| `$project` | Include/exclude fields | Reduce document size early |
| `$sort` | Order results | Hits index if sort key matches index prefix |
| `$group` | Aggregate (sum, count, avg) | Requires full scan of input |
| `$lookup` | Left outer join to another collection | Expensive; use indexes on `foreignField`; avoid on large collections |
| `$unwind` | Expand array into multiple documents | Can multiply document count — filter before unwinding |
| `$limit` / `$skip` | Pagination | Deep pagination (large skip) is O(n) — use range queries instead |
| `$facet` | Multiple parallel pipelines | Useful for faceted search results |
| `$out` / `$merge` | Write results to a collection | Used for materialized views |

---

## Change Streams

Change streams expose the oplog as a real-time event stream to application code. Built on the aggregation framework.

```javascript
// Watch all changes to orders collection:
const changeStream = db.orders.watch([
  { $match: { "operationType": { $in: ["insert", "update"] } } }
], { fullDocument: "updateLookup" });

changeStream.on("change", (change) => {
  console.log("Order changed:", change.fullDocument);
  // Resume token allows restart from exact position:
  lastResumeToken = change._id;
});

// Restart after crash using resume token:
db.orders.watch([], { resumeAfter: lastResumeToken });
```

**Use cases**: Event-driven microservices (CDC); real-time notifications; cache invalidation; audit logging.
**Cross-shard**: `db.watch()` at database or cluster level works across shards — mongos aggregates oplog streams.

---

## Write Path vs. Read Path: Complexity Asymmetry

| Dimension | Write Path | Read Path |
|-----------|-----------|----------|
| I/O type | Sequential (journal + oplog) | Random (B-tree index + document fetch) |
| Latency (p50) | 1–5 ms (w:1); 10–50 ms (w:majority cross-DC) | 1–3 ms (indexed, cache hit) |
| Primary bottleneck | Network RTT for `w:majority`; journal fsync | Index selectivity; WiredTiger cache size; COLLSCAN |
| Horizontal scale | Sharding (one primary per shard) | Read preference + secondary offload + sharding |
| Consistency | Controlled by write concern | Controlled by read concern + read preference |

---

## FAANG Interview Callout

> "MongoDB's write path is optimized for crash safety: every write hits the WAL journal first (sequential I/O), then updates the in-memory B-tree, then appends to the oplog. The oplog is the single source of truth for replication — secondaries tail it, change streams watch it, and point-in-time recovery replays it. The critical design decision is write concern: `w:majority` means the write is committed to a majority quorum before ACK, which guarantees no data loss on primary failover. The cost is +RTT for the cross-DC network round trip when majority members are in another datacenter.
>
> Active-active in MongoDB means zone sharding, not multi-primary. Each zone has one primary, so US-region writes go to the US shard's primary and EU-region writes go to the EU shard's primary — both DCs are 'active' for their own data. If you need true multi-primary (any node in any DC accepts any write), you need Cassandra or DynamoDB — MongoDB cannot do that without sacrificing its CP consistency guarantee."

---

## Related Files

| File | Topic |
|------|-------|
| [01-architecture.md](01-architecture.md) | Replica sets, sharding, multi-DC topology configurations, document model |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Active-passive vs active-active trade-offs; vs Cassandra (true multi-primary) |
| [04-tuning-guide.md](04-tuning-guide.md) | Oplog sizing, write concern configuration, replication lag monitoring, cross-DC parameters |
| [05-production-and-research.md](05-production-and-research.md) | Real-world replication lag incidents; Shopify shard key lessons; Coinbase write concern strategy |
