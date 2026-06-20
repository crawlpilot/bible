# Partitioning Strategies

## The Core Problem (Start Here)

Imagine you're running a database for a social network with 1 billion users. A single machine can store maybe 10 million user records comfortably. You need 100 machines. But **which records go on which machine?**

That's partitioning (also called *sharding*). The goal: distribute data across nodes so that:
1. Each node holds a manageable slice
2. You can find the right node quickly for any query
3. No single node becomes a bottleneck (a "hot partition")

Getting this wrong means 95% of traffic hits 5% of your machines while the rest sit idle — the system looks scaled-out but behaves like a single machine.

```
BAD (uneven load):            GOOD (even load):
Node 1: ██████████ 80% load   Node 1: ████ 33% load
Node 2: █ 5% load             Node 2: ████ 33% load
Node 3: █ 5% load             Node 3: ████ 33% load
Node 4: █ 5% load             → each node does equal work
Node 5: █ 5% load
```

---

## Strategy 1: Range Partitioning

### How It Works

Divide the key space into contiguous ranges. Each range is assigned to a node.

```
User IDs: 1–1,000,000      → Node A
          1,000,001–2,000,000 → Node B
          2,000,001–3,000,000 → Node C

OR by name:
  A–F → Node A
  G–M → Node B
  N–Z → Node C
```

### Efficient Range Scans

Range partitioning excels at range queries: "find all orders placed in January 2024" — if partitioned by timestamp, all January records are on adjacent nodes (or a single node).

```sql
-- Routed to a single partition (great!)
SELECT * FROM orders WHERE created_at BETWEEN '2024-01-01' AND '2024-01-31'
```

### The Hot Partition Problem

**Monotonic keys are the enemy of range partitioning.** If you partition by `order_id` and IDs are sequential (1, 2, 3, 4...), **all new writes always go to the last partition**:

```
Time → writes pile into last partition:
Partition A (IDs 1-1M):     ░░░░░░░░ (cold, old data)
Partition B (IDs 1M-2M):    ░░░░░░░░ (cold, old data)
Partition C (IDs 2M-3M):    ████████ (HOT — all new writes here)
```

**Mitigation:** Use UUIDs or reverse-byte-order of sequential IDs as the partition key. CockroachDB uses a 32-bit hash prefix on primary keys by default.

### Production: HBase, CockroachDB, Bigtable

CockroachDB splits ranges at 64MB–512MB; uses Raft per range; auto-rebalances by moving ranges between nodes. Bigtable row keys are sorted; careful key design prevents hotspots.

---

## Strategy 2: Hash Partitioning

### How It Works

Apply a hash function to the key; use the result to pick a node.

```
node = hash(key) % num_nodes

user:alice → hash = 9823742 → 9823742 % 4 = 2 → Node 2
user:bob   → hash = 4729103 → 4729103 % 4 = 3 → Node 3
user:carol → hash = 6294801 → 6294801 % 4 = 1 → Node 1
```

**Uniform distribution:** A good hash function spreads keys uniformly — no hot partition from access patterns (though one key being extremely popular still causes hotspots, covered below).

### The Modulo Problem

`hash(key) % num_nodes` has a catastrophic flaw: **adding or removing a node invalidates almost all partition assignments.**

```
4 nodes:  hash("alice") % 4 = 2 → Node 2
5 nodes:  hash("alice") % 5 = 4 → Node 4  ← different!

When you go from 4 → 5 nodes, ~80% of all keys must move.
```

This is why consistent hashing was invented.

---

## Strategy 3: Consistent Hashing

### The Idea

Place nodes and keys on a **ring** of hash values (0 → 2^32). A key is assigned to the first node encountered going clockwise.

```
          0
        /   \
Key X →  Node A ← hash(A)
    |              |
  Node D         Node B
        \   /
         Node C
          (2^32)

Key X lands between Node D and Node A → assigned to Node A
```

**Adding a node:** Only keys between the new node and its predecessor move. On average, `K/N` keys move (K = total keys, N = nodes). Adding Node E between D and A: only keys in [D, E) move from A to E.

**Removing a node:** Only its keys move (to its successor). No other data moves.

### Virtual Nodes (vnodes)

A single physical node appears at **many points on the ring** (typically 100–200 virtual nodes). This:
- Smooths out load imbalance (without vnodes, ring placement is uneven)
- Allows gradual data migration when a node joins/leaves

```
Without vnodes:        With vnodes (100 per node):
Node A: 0%–25%         Node A: spread across ring at 100 points
Node B: 25%–45%        Node B: spread across ring at 100 points
Node C: 45%–90%  ← Node C holds 45% of data — 3× overloaded
Node D: 90%–100%
```

**Production:** Cassandra (150 vnodes default, configurable), Amazon DynamoDB, Apache Riak.

**Cross-reference:** See [DSA/system-design-ds/](../../DSA/system-design-ds/) for consistent hashing implementation details and the jump hash algorithm.

---

## Strategy 4: Directory-Based Partitioning

### How It Works

A separate **lookup service** maintains the mapping from key → partition → node. Clients query the directory first.

```
Client: "Where is user:alice?"
Directory: "Partition 7, Node C"
Client → Node C: GET user:alice
```

### Trade-offs

| Pros | Cons |
|---|---|
| Maximum flexibility — partition can be moved without changing key | Directory is a single point of failure |
| Support complex resharding policies | Extra network hop per request |
| Easy to implement non-uniform partition sizes | Must cache directory client-side for performance |

**Production use:** Memcached with a consistent-hashing router (mcrouter), ZooKeeper as a shard directory for HBase.

---

## Strategy 5: Geo-Based Partitioning

### How It Works

Partition by geographic region — EU users go to EU nodes, US users to US nodes. Often layered on top of hash or range partitioning within each region.

```
URL: user_id=123, region=EU  → EU cluster
URL: user_id=456, region=US  → US cluster
```

**Geospatial keys:** Use S2 cells (Google's spherical geometry library) or H3 (Uber's hexagonal grid) to convert lat/lon to a sortable cell ID, then range-partition by cell ID. Enables efficient proximity queries.

```
Find all restaurants within 1km of (lat, lon):
  → convert to S2 cell ID
  → range scan S2 cells covering 1km radius
  → much more efficient than full table scan
```

**Data sovereignty:** GDPR requires EU user PII stays in EU. Geo-partitioning is often mandated by compliance, not just performance.

---

## Rebalancing Algorithms

### Why Rebalancing Is Needed

Nodes join (scale out), leave (hardware failure), or become unequal (new data skews to certain partitions). Rebalancing moves partitions between nodes to restore balance.

### CockroachDB Range Rebalancing

1. **Split:** When a range exceeds ~512MB, split it at its median key into two ranges
2. **Rebalance:** Background rebalancer moves ranges to nodes with below-average load
3. **Constraint satisfaction:** Rack awareness, zone constraints (e.g., one replica per AZ)

### Vitess Resharding (MySQL)

1. Define new shard map (e.g., 4 shards → 8 shards)
2. Copy data to new shards (reads from old, writes to both)
3. Cut over: switch routing to new shards
4. Clean up old shards
5. Downtime window: minutes (if careful), or zero-downtime with online schema change

---

## Hot Partition Detection and Mitigation

### Detection

```
Metric: requests_per_second per partition
Alert:  any partition > (avg × 3) for > 60 seconds
```

**Write sharding (random suffix):** For a key like `product:99` that everyone writes to, add a random suffix:

```
key = f"product:99:{random.randint(0, 9)}"  # 10 virtual keys
```

Reads must scatter-gather across all 10 keys and merge. Writes distribute across 10 partitions.

**Use case:** Real-time counters (view counts, like counts), hot product pages during flash sales.

**Adaptive splitting (DynamoDB):** DynamoDB automatically detects hot partitions and splits them, rerouting traffic to new sub-partitions transparently.

---

## Cross-Shard Operations

### Scatter-Gather

```
Query: "Get orders for users A, B, C" (on different shards)

1. Coordinator fans out:  Shard 1 ← user A query
                           Shard 2 ← user B query
                           Shard 3 ← user C query

2. Coordinator collects all results
3. Merge and sort in coordinator memory
4. Return to client

Latency:  max(shard1_latency, shard2_latency, shard3_latency) + merge time
Cost:     fanout = O(N shards), not O(1)
```

### Distributed Joins

Cross-shard joins are expensive. Two strategies:

1. **Broadcast join (for small tables):** Broadcast the small table to all shards; each shard does a local join
2. **Repartition join:** Repartition both tables on the join key so matching rows land on the same shard

Production: Vitess (MySQL sharding) routes queries; BigQuery/Snowflake use MPP (Massively Parallel Processing) with broadcast joins.

---

## Partition Strategy Decision Guide

| Requirement | Best Strategy | Why |
|---|---|---|
| Need efficient range queries (time-series, sorted IDs) | Range partitioning | Contiguous data on same/nearby nodes |
| Uniform write distribution, no range queries | Hash partitioning + consistent hash | Even spread, no hotspots |
| Need to add/remove nodes without mass data movement | Consistent hashing with vnodes | Only K/N keys move |
| Complex resharding policies, metadata-heavy | Directory-based | Full flexibility |
| GDPR / data sovereignty / proximity queries | Geo-based + S2/H3 cells | Compliance + locality |
| Hot key problem (flash sale, trending topic) | Write sharding (random suffix) | Split one logical key across many physical partitions |

---

## Production Examples

| System | Strategy | Notes |
|---|---|---|
| **Amazon DynamoDB** | Consistent hashing + adaptive splits | Auto-detects hot partitions, transparent re-partitioning |
| **Apache Cassandra** | Consistent hashing (Murmur3) + vnodes | 150 vnodes default; partition key in CQL determines placement |
| **Google Bigtable** | Range (sorted row key) | Key design critical; reverse-byte timestamp avoids hotspot |
| **CockroachDB** | Range (sorted keys) + hash prefix option | Ranges split at 512MB; Raft per range |
| **Vitess (MySQL sharding)** | Hash or range, configurable | Explicit resharding workflow; used by YouTube, Slack |
| **Elasticsearch** | Hash by `_id` → fixed shards | Shards fixed at index creation; reindex to change count |
| **MongoDB** | Hash or range, configurable | Chunk-based; balancer moves chunks between shards |

---

## FAANG Interview Application

**Likely questions:**
- "How would you partition a social graph for 1 billion users?"
- "Design a URL shortener that handles 100K writes/sec. How do you shard the database?"
- "You're seeing hot partition issues in Cassandra. How do you diagnose and fix it?"
- "How does consistent hashing help when you add/remove nodes from a cluster?"

**What interviewers evaluate:**
- Do you know the difference between hash and range partitioning and when to use each?
- Can you explain the resharding problem (modulo fails) and why consistent hashing solves it?
- Do you know how to handle hot keys (write sharding, random suffix)?
- Can you reason about scatter-gather cost for cross-shard queries?

**Principal-level signal:**
> "Partition key selection is an early, hard-to-reverse decision. For a time-series system, range partitioning by time enables efficient range queries but needs hot-partition protection (write sharding or pre-splitting). For a user store, hash + consistent hashing gives uniform write distribution at the cost of range queries. At FAANG scale, the real challenge is often hot keys — a celebrity's post generates millions of writes per second to one logical key. The solution is not a better partitioning strategy; it's application-level fan-out: write to N random shards, read-merge at the application layer."
