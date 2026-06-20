# MongoDB Tuning Guide

## Tuning Philosophy

MongoDB tuning has three layers. Address them in order — a bad decision at a higher layer cannot be fixed by tuning at a lower layer:

```
Layer 1: Schema Design          ← Highest leverage. Bad schema = no tuning can save you.
          └── shard key choice, embedding vs referencing, index strategy

Layer 2: Replication & Durability ← Controls consistency/availability/performance trade-off.
          └── write concern, read preference, replica set topology

Layer 3: Operational Parameters  ← Fine-tuning for known workloads.
          └── WiredTiger cache, connection pool, oplog size, compaction
```

---

## Layer 1: Shard Key Selection

The shard key is the most consequential decision in a MongoDB deployment. It is effectively **permanent** — changing it requires a full collection rebuild (v5.x allows limited resharding, but it's operationally expensive).

### Shard Key Requirements

| Requirement | Why It Matters |
|-------------|---------------|
| **High cardinality** | Low cardinality (e.g., boolean, enum with 5 values) means few chunks — limits parallelism |
| **Non-monotonic** | Monotonically increasing keys (ObjectId, timestamp) always insert to the "max" chunk → hotspot on last shard |
| **Query coverage** | Most queries should include the shard key (or its prefix) — avoids scatter-gather to all shards |
| **Uniform distribution** | Even spread of documents across shards → balanced chunk map → no hotspot shards |

### Shard Key Patterns

| Pattern | Example | Pros | Cons | When to Use |
|---------|---------|------|------|------------|
| **Hashed single field** | `{ userId: "hashed" }` | Perfectly uniform distribution; avoids hotspot | No range queries; scatter-gather for range scans | High-write collections with point lookups |
| **Ranged single field** | `{ region: 1 }` | Range queries are shard-local | Low cardinality → hotspot | Zone sharding only |
| **Compound ranged** | `{ tenantId: 1, createdAt: 1 }` | Tenant isolation; time-range queries per tenant | Must include tenantId in all queries | Multi-tenant SaaS |
| **Compound hashed** | `{ category: 1, productId: "hashed" }` | Category locality + uniform distribution within category | Slightly complex; category must be in queries | Catalog with category-level access |
| **Compound geo+user** | `{ region: 1, userId: "hashed" }` | Zone sharding per region; uniform within region | Region must be in all queries | Geo-partitioned active-active |

### ObjectId as Shard Key: The Classic Anti-Pattern

```
ObjectId = [4B timestamp][5B random][3B counter]
                ↑
          Monotonically increasing → all inserts go to LAST shard

Result:
  Shard 1: ████████░░░░░░░░  (old data, mostly reads)
  Shard 2: ████░░░░░░░░░░░░  (older data, mostly reads)
  Shard 3: ████████████████  (all new writes — HOTSPOT)

Fix: Use hashed _id as shard key:
  sh.shardCollection("db.orders", { _id: "hashed" })
```

### Resharding (MongoDB 5.0+)

MongoDB 5.0 introduced online resharding — change the shard key without stopping the cluster:

```javascript
db.adminCommand({
  reshardCollection: "ecommerce.orders",
  key: { customerId: "hashed" }  // new shard key
});
// Runs in background; ~30 min to hours depending on collection size
// Zero downtime; application continues writing
```

**Warning**: Resharding is I/O intensive and impacts performance. Schedule during low-traffic windows.

---

## Layer 2: Write Concern Tuning

### Write Concern by Scenario

| Scenario | Write Concern | Journal | Rationale |
|---------|--------------|---------|-----------|
| Financial transactions, inventory | `w: "majority"` | `j: true` | No data loss on failover; journal ensures crash safety |
| User profile updates, orders | `w: "majority"` | `j: true` | Standard production default |
| High-throughput event logging | `w: 1` | `j: false` | Throughput matters; individual event loss acceptable |
| Analytics / metrics ingestion | `w: 1` | `j: false` | Best-effort; pipeline can tolerate gaps |
| Bulk import (initial load) | `w: 0` | `j: false` | Fastest load; validate after completion |
| Audit trail | `w: "majority"` | `j: true` | Every record must be durable |

### Driver Configuration (Node.js example)

```javascript
const { MongoClient } = require("mongodb");

const client = new MongoClient(uri, {
  // Default write concern for all operations on this client:
  writeConcern: {
    w: "majority",
    j: true,
    wtimeout: 5000  // fail if quorum not ack'd within 5s (prevents infinite wait)
  },
  // Read preference:
  readPreference: "primaryPreferred",
  // Retry writes (idempotent retries on transient network errors):
  retryWrites: true,
  // Retry reads:
  retryReads: true
});

// Override write concern per-operation for high-throughput inserts:
await db.collection("events").insertMany(events, {
  writeConcern: { w: 1, j: false }
});
```

### Write Concern Timeout

Always set `wtimeout` in production. Without it, a write waiting for `w:majority` can hang indefinitely if a secondary is unreachable:

```javascript
// WRONG — can hang forever if secondary is down:
{ w: "majority" }

// CORRECT — fail fast with clear error if quorum unavailable:
{ w: "majority", wtimeout: 5000 }
```

---

## Layer 2: Read Preference Tuning

### Read Preference by Scenario

| Scenario | Read Preference | Stale Tolerance | Why |
|---------|----------------|----------------|-----|
| Financial reads (balance, inventory) | `primary` | None | Must be current; secondary lag is unacceptable |
| User-facing reads (product details, profiles) | `primaryPreferred` | < 1s | High availability; brief staleness acceptable |
| Analytics dashboards | `secondary` | Minutes | Offload primary; dashboards don't need real-time |
| Reporting / bulk exports | `secondary` | Minutes | Never hit primary with long-running scans |
| Multi-DC latency-sensitive reads | `nearest` | Seconds | Serve from closest replica; accept some stale data |
| Read-heavy A/B test bucketing | `secondaryPreferred` | Seconds | Distribute read load; bucket assignments stable |

### Tag-Based Read Routing (Cross-DC)

```yaml
# mongod.conf — tag each member with its DC:
replication:
  replSetName: "rs0"

# Applied via rs.reconfig():
{
  _id: 2,
  host: "dc2-node1:27017",
  priority: 1,
  tags: { "dc": "us-west", "use": "reporting" }
}
```

```javascript
// Route reads to us-west DC only:
db.collection("orders").find({}).readPref("nearest", [{ dc: "us-west" }]);

// Route analytics reads to reporting-tagged replicas:
db.collection("events").aggregate([...]).readPref("secondary", [{ use: "reporting" }]);
```

---

## Layer 3: WiredTiger Cache

WiredTiger is MongoDB's default storage engine (since v3.2). Its in-memory cache is the primary performance lever for read-heavy workloads.

### Cache Sizing Formula

```
Default: max(50% of RAM − 1GB, 256MB)

Examples:
  16 GB RAM → cache = max(7 GB, 256 MB) = 7 GB
  32 GB RAM → cache = max(15 GB, 256 MB) = 15 GB
  64 GB RAM → cache = max(31 GB, 256 MB) = 31 GB

Recommended for dedicated MongoDB nodes:
  wiredTigerCacheSizeGB = 0.6 × total_RAM
  (leave 30–40% for OS, index key memory, connection overhead, oplog)
```

```yaml
# mongod.conf:
storage:
  dbPath: /data/db
  wiredTiger:
    engineConfig:
      cacheSizeGB: 20        # Explicit override
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy  # snappy: fast; zlib/zstd: smaller
    indexConfig:
      prefixCompression: true
```

### Cache Eviction Thresholds

WiredTiger manages cache via eviction. Tune these if you see cache pressure:

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `eviction_target` | 80% | Start background eviction when cache reaches 80% full |
| `eviction_trigger` | 95% | Foreground eviction (blocks reads/writes) at 95% — avoid this |
| `eviction_dirty_target` | 5% | Target dirty page % in cache |
| `eviction_dirty_trigger` | 20% | Foreground eviction if dirty % reaches 20% |

```yaml
storage:
  wiredTiger:
    engineConfig:
      configString: "eviction=(threads_min=4,threads_max=8)"  # More eviction threads
```

**Symptom of cache pressure**: `wiredTiger.cache.pages read into cache` metric rising; `wiredTiger.cache.tracked dirty bytes in the cache` persistently high.

---

## Layer 3: Index Tuning

### The ESR Rule

For compound indexes, field order determines efficiency:

```
E → S → R
Equality first → Sort second → Range last

Example query:
  find({ status: "active", createdAt: { $gte: yesterday } }).sort({ priority: -1 })

BAD index:  { createdAt: 1, status: 1, priority: -1 }
             └── Range first → can't use sort direction effectively

GOOD index: { status: 1, priority: -1, createdAt: 1 }
             └── Equality (status) → Sort (priority) → Range (createdAt)
```

### Index Patterns

```javascript
// Partial index — only index active orders (saves space, faster writes):
db.orders.createIndex(
  { customerId: 1, createdAt: -1 },
  { partialFilterExpression: { status: { $in: ["pending", "processing"] } } }
);

// TTL index — auto-expire session documents after 1 hour:
db.sessions.createIndex(
  { lastActivity: 1 },
  { expireAfterSeconds: 3600 }
);

// Sparse index — don't index documents without the field:
db.users.createIndex(
  { promoCode: 1 },
  { sparse: true }  // Only documents with promoCode field are indexed
);

// Wildcard index — for dynamic schemas:
db.products.createIndex({ "attributes.$**": 1 });
// Allows: db.products.find({ "attributes.color": "red" })
//     and: db.products.find({ "attributes.voltage": "220V" })
```

### Rolling Index Build (Zero Downtime)

Never build an index on a live primary of a large collection — it degrades throughput and increases replication lag.

```
Step 1: For each SECONDARY:
  a. Remove secondary from load balancer / read pool
  b. Build index on secondary:
     db.collection.createIndex({ field: 1 }, { background: true })  # pre-v4.2
     // or just createIndex() in v4.4+ (always foreground on the node, but non-blocking for replica)
  c. Verify index is built: db.collection.getIndexes()
  d. Return secondary to load balancer

Step 2: Step down PRIMARY (triggers election):
  rs.stepDown(30)

Step 3: Build index on the old primary (now a secondary):
  Same as Step 1

Step 4: Index is now on all members — primary included.
```

### Hidden Index Pattern (Safe Rollout)

Test whether an index is actually needed before building it permanently:

```javascript
// Create index as hidden — exists but query planner won't use it:
db.orders.createIndex({ status: 1, createdAt: -1 }, { hidden: true });

// Verify it won't be used:
db.orders.find({ status: "shipped" }).explain();  // should show COLLSCAN or different index

// Unhide to activate:
db.runCommand({
  collMod: "orders",
  index: { name: "status_1_createdAt_-1", hidden: false }
});

// Drop if not needed:
db.orders.dropIndex("status_1_createdAt_-1");
```

### `explain("executionStats")` Quick Reference

```javascript
const result = db.orders.find({ customerId: uid }).sort({ createdAt: -1 }).explain("executionStats");

// Key checks:
result.executionStats.executionTimeMillis  // total ms
result.executionStats.totalDocsExamined    // should be close to nReturned
result.executionStats.totalKeysExamined    // index keys scanned
result.executionStats.nReturned            // docs returned

// Winning plan stage check:
result.queryPlanner.winningPlan.stage      // IXSCAN = good; COLLSCAN = needs index
result.queryPlanner.winningPlan.inputStage // FETCH = post-index doc fetch
```

---

## Layer 3: Connection Pool Tuning

### `maxPoolSize` Formula

```
maxPoolSize per driver instance = (num_CPUs_on_DB_node × 2) / num_app_instances

Example:
  MongoDB primary: 32 CPUs
  App servers: 10 instances
  maxPoolSize per app server = (32 × 2) / 10 = ~6 (round up to 10 for burst headroom)

MongoDB default maxPoolSize: 100 connections (per driver pool)
Danger zone: > 1000 total connections to a single mongod
```

```javascript
const client = new MongoClient(uri, {
  maxPoolSize: 10,          // Max connections this driver instance holds
  minPoolSize: 2,           // Keep warm
  maxIdleTimeMS: 30000,     // Close idle connections after 30s
  connectTimeoutMS: 5000,   // Give up connecting after 5s
  socketTimeoutMS: 45000    // Give up waiting for response after 45s
});
```

### Connection Storm Anti-Pattern

On app deploy or restart, all app instances try to establish their full pool simultaneously:

```
App restart: 50 app servers × 100 maxPoolSize = 5000 simultaneous connections
→ MongoDB accept queue fills → connection refused errors → cascading failures

Fix: Stagger app restarts; reduce maxPoolSize; use connection pre-warming
```

---

## Cross-DC Tuning Parameters

### Replica Set `mongod.conf` Parameters

```yaml
replication:
  replSetName: "rs0"
  oplogSizeMB: 51200        # 50 GB oplog — ensure 72+ hour retention window

# Per-member settings applied via rs.reconfig():
# members[].priority         — higher = more likely to become primary
# members[].votes            — 1 (default) or 0 (hidden/delayed replicas)
# members[].secondaryDelaySecs — lag behind primary (for delayed DR replica)
# members[].hidden           — invisible to driver discovery
# members[].buildIndexes     — false for dedicated reporting replica (no indexes)
```

### Delayed Replica for Point-in-Time Recovery

```javascript
// Configure a delayed replica (e.g., 6 hours behind primary):
rs.reconfig({
  ...rs.conf(),
  members: [
    ...otherMembers,
    {
      _id: 5,
      host: "dc2-delayed:27017",
      priority: 0,         // Never becomes primary
      votes: 0,            // Doesn't count toward majority (doesn't delay elections)
      hidden: true,        // Invisible to drivers
      secondaryDelaySecs: 21600  // 6 hours behind primary
    }
  ]
});
```

**Use case**: Human error recovery. If someone drops a collection or runs a destructive update, the delayed replica has the pre-error state available for up to 6 hours.

### Election Timeout Tuning

```yaml
# Default election timeout: 10 seconds
# This means writes are unavailable for up to ~30s on primary failure
# (10s timeout + election time + new primary ramp-up)

# For lower RTO (at cost of false elections under network jitter):
# Reduce to 5s only in stable, low-jitter networks:
replication:
  settings:
    electionTimeoutMillis: 5000   # Lower = faster failover, more false elections
    heartbeatIntervalMillis: 2000  # Default 2s; don't go lower
```

---

## Anti-Patterns

| Anti-Pattern | Impact | Fix |
|-------------|--------|-----|
| **ObjectId as shard key** | All writes go to last shard (hotspot) | Use `{ _id: "hashed" }` or compound key with high-cardinality first field |
| **Unbounded arrays in documents** | Document grows without limit → 16MB error; multikey index explosion | Cap arrays; use references for unbounded one-to-many |
| **No index on queried fields** | COLLSCAN on every query → linear scan of collection | Add compound index following ESR rule; use `explain()` to verify |
| **`$where` JavaScript operator** | Runs JS interpreter per document → full collection scan → security risk | Use native MQL operators (`$expr`, `$cond`, aggregation pipeline) |
| **`skip()` for deep pagination** | `skip(N)` scans and discards N documents — O(n) | Use range-based pagination: `find({ _id: { $gt: lastId } }).limit(20)` |
| **Cross-shard transactions** | 2PC coordination overhead; 50–200ms latency per transaction | Redesign schema so related data is on same shard; avoid transactions across shard boundaries |
| **Large documents (> 1MB)** | Network bandwidth; slower cache eviction; higher read latency | Extract large fields to GridFS or S3; reference from document |
| **Secondary indexes on every field** | Every write must update all indexes → 2–3× write amplification; high memory | Index only queried fields; use partial/sparse indexes to reduce index size |
| **`w:1` without `j:true` on primary** | Data loss on crash between checkpoint intervals (up to 60s) | Use `{ w: 1, j: true }` minimum for anything you care about |
| **`$lookup` on unindexed foreign collection** | Full collection scan of `from` collection per input document | Ensure `foreignField` is indexed; consider denormalization |
| **Storing secrets in documents** | Compliance risk; appears in log output, `explain()` | Use field-level encryption (MongoDB CSFLE) or store references to a secrets manager |

---

## Monitoring: Key Metrics

```javascript
// Check server status:
db.adminCommand({ serverStatus: 1 });

// Check replication info:
rs.status();
rs.printReplicationInfo();
rs.printSecondaryReplicationInfo();

// Check current operations (find slow queries):
db.adminCommand({ currentOp: true, secs_running: { $gt: 1 } });

// Check slow query log (operations > slowMS):
db.adminCommand({ getLog: "global" });
db.setProfilingLevel(1, { slowms: 100 });  // Log queries > 100ms
```

### Metrics to Watch

| Metric | Normal | Alert Threshold | Source |
|--------|--------|----------------|--------|
| Replication lag | < 5s | > 30s | `rs.printSecondaryReplicationInfo()` |
| Connections current | < 500 | > 800 (per node) | `serverStatus.connections.current` |
| Opcounters (ops/sec) | Baseline | 2× baseline | `serverStatus.opcounters` |
| WiredTiger cache usage | 60–80% | > 95% (triggers foreground eviction) | `serverStatus.wiredTiger.cache` |
| WiredTiger pages read into cache | Low | Sustained high = working set > cache | `serverStatus.wiredTiger.cache` |
| Queue length (readers/writers) | 0 | > 10 | `serverStatus.globalLock.currentQueue` |
| Index miss ratio | < 1% | > 5% | Computed from `totalDocsExamined / nReturned` |
| Chunk migrations/hour | Low | > 5/hour sustained | `sh.status()` |
| Oplog window | > 72 hours | < 24 hours | `rs.printReplicationInfo()` |
| Disk I/O utilization | < 60% | > 80% | OS iostat / CloudWatch |

---

## FAANG Interview Callout

> "The most impactful tuning decisions in MongoDB are, in order: shard key choice, write concern, and WiredTiger cache size. The shard key is permanent and determines whether you have hotspots — never use an ObjectId or timestamp as a ranged shard key. Use hashed shard keys for uniform write distribution, or compound keys for zone sharding. Write concern `w:majority` with `j:true` is the production default — it's the only setting that guarantees no data loss on primary failover. The cost is one cross-DC round trip for each write in a multi-DC deployment, typically 20–80ms depending on geography. WiredTiger cache should be set to ~60% of RAM on a dedicated node; if your working set exceeds the cache, reads go to disk and latency climbs from 1ms to 10–50ms.
>
> The anti-pattern I see most often in interviews is candidates proposing `skip()` for pagination — that's O(n) on large collections. Always use keyset pagination: store the last `_id` or sort key you returned and use `find({ _id: { $gt: lastId } }).limit(N)`. Same complexity, zero wasted scans."

---

## Related Files

| File | Topic |
|------|-------|
| [01-architecture.md](01-architecture.md) | Multi-DC topology configuration, replica set priority/votes setup |
| [02-read-write-path.md](02-read-write-path.md) | Write concern levels, read preference, oplog internals |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | When to accept write concern latency cost vs switch to Cassandra |
| [05-production-and-research.md](05-production-and-research.md) | Shopify shard key disaster; Uber's oplog sizing incident; Coinbase write concern strategy |
