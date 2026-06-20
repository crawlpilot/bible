# Cassandra — Architecture

## Origins: Dynamo + BigTable

Cassandra's architecture is a deliberate synthesis of two landmark papers:

| Source | Contribution to Cassandra |
|--------|--------------------------|
| **Amazon Dynamo (2007)** | Decentralised ring topology, consistent hashing, virtual nodes, tunable consistency, gossip protocol, hinted handoff, leaderless replication |
| **Google BigTable (2006)** | SSTable storage format, MemTable in-memory buffer, column-family data model, bloom filters, compaction |

The combination yields a system that is **masterless** (no single point of failure), **linearly scalable** (add nodes without downtime), and **write-optimised** (every write is O(1) — append to commit log + insert into MemTable).

---

## Ring Topology

Cassandra organises nodes in a **logical ring**. Each node owns a range of the token space (by default: −2⁶³ to +2⁶³ − 1). A row's partition key is hashed to a token; the node owning that token range is the **coordinator** for that request.

```
                Token space: -2^63 ──────────────── +2^63
                
                            Node A
                         (token 0)
                        /           \
                       /             \
              Node D                 Node B
          (token -6917)          (token 3074)
                       \             /
                        \           /
                            Node C
                         (token -3458)

  Partition key "user:123" → Murmur3 hash → token 1842 → lands in Node B's range
  With RF=3: replicated to Node B, Node C, Node D (next 2 clockwise)
```

### Partitioner

The partitioner determines how keys map to tokens:

| Partitioner | Hash Function | Distribution | When to Use |
|------------|--------------|-------------|------------|
| **Murmur3Partitioner** (default) | MurmurHash3 | Uniform random | Almost always |
| **RandomPartitioner** (legacy) | MD5 | Uniform random | Legacy only |
| **ByteOrderedPartitioner** | Raw bytes | Sequential (ordered) | Avoid — causes hotspots; range scans don't work across nodes |

**Critical rule**: Never use `ByteOrderedPartitioner` in production — sequential keys create write hotspots on a single node, defeating horizontal scaling.

---

## Virtual Nodes (vnodes)

Before vnodes, each node owned a single contiguous token range. Adding a node required manual token reassignment. **Vnodes** split each node's ownership into 256 small, non-contiguous token ranges distributed around the ring.

```
Without vnodes (4 nodes):                With vnodes (4 nodes, 256 vnodes each):
  Node A: [0, 25%)                         Node A owns: ranges 3, 17, 41, 89, 132 ... (256 ranges)
  Node B: [25%, 50%)                       Node B owns: ranges 1, 12, 38, 91, 140 ... (256 ranges)
  Node C: [50%, 75%)                       Node C owns: ranges 5, 19, 44, 95, 138 ... (256 ranges)
  Node D: [75%, 100%)                      Node D owns: ranges 2, 18, 43, 92, 145 ... (256 ranges)
```

**Benefits of vnodes**:
1. **Automatic load balancing**: each node gets ~equal share of token space
2. **Faster bootstrapping**: a new node takes small chunks from many existing nodes (parallel streaming)
3. **Faster repair**: repair operates per-token range, so smaller ranges complete faster
4. **Heterogeneous hardware**: assign more vnodes to larger nodes via `num_tokens`

**Tuning**: `num_tokens: 256` (default). Reduce to 16–32 if nodes are large (> 3TB) to reduce gossip overhead.

---

## Replication

Cassandra replicates every row to **N** nodes where N = the **replication factor (RF)** defined per keyspace.

### Replica Placement Strategies

| Strategy | How Replicas Are Placed | When to Use |
|----------|------------------------|------------|
| **SimpleStrategy** | Next N nodes clockwise on the ring | Development / single datacenter only |
| **NetworkTopologyStrategy** | N replicas per datacenter, spread across distinct racks | **Always in production** |

```sql
-- Production keyspace definition
CREATE KEYSPACE user_activity
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,   -- 3 replicas in US East
    'eu-west-1': 3    -- 3 replicas in EU West
};
```

### Replica Selection

With NetworkTopologyStrategy and RF=3 per DC, Cassandra places replicas on nodes in **different racks** within each DC. If there are only 2 racks, one rack gets 2 replicas — this is acceptable but documented.

**Rule**: RF ≥ 3 in every production datacenter. RF=1 means data loss on any single node failure.

---

## Gossip Protocol

Cassandra uses the **Gossip protocol** for peer discovery, failure detection, and cluster state propagation. It is the backbone of Cassandra's masterless architecture.

### How Gossip Works

Every second, each node initiates a gossip exchange with 1–3 randomly selected peers. Each exchange carries the node's **endpoint state**: load, schema version, status (NORMAL, LEAVING, JOINING, MOVING), token ranges, and datacenter/rack identity.

```
Gossip round (every 1 second):

  Node A wakes up →
    picks Node B, Node C, Node D randomly →
    sends: { nodeA_state, nodeB_state_as_A_knows_it, ... }
    Node B responds with its own view →
    both update their state if they receive newer information

  After a few rounds, all nodes converge on the same cluster view.
```

### Failure Detection: Phi Accrual

Cassandra does not use a simple timeout for failure detection. It uses the **Phi Accrual Failure Detector** (from a 2004 paper by Hayashibara et al.) which outputs a continuous suspicion score φ rather than a binary alive/dead:

- φ = 1 → 10% chance the node is dead
- φ = 8 → 99.996% chance the node is dead (default threshold)
- φ = 12 → 99.9999% chance

**Tuning**: `phi_convict_threshold: 8` (default). Lower = faster failure detection but more false positives. Raise to 12 in unstable network environments.

### Gossip States

| State | Meaning |
|-------|---------|
| NORMAL | Fully operational, owning its token ranges |
| JOINING | Bootstrapping — streaming data from peers |
| LEAVING | Decommissioning — streaming data out |
| LEFT | Decommissioned, token ranges redistributed |
| MOVING | Token range being reassigned |

---

## Data Model

Cassandra's data model is a **wide-column store**. Understanding it is critical to schema design.

### Hierarchy

```
Cluster
  └── Keyspace (≈ database schema; defines replication)
        └── Table (≈ SQL table, but with mandatory primary key design)
              └── Partition (rows sharing the same partition key — stored together on disk)
                    └── Row (partition key + clustering columns + value columns)
```

### Primary Key Anatomy

```sql
CREATE TABLE user_events (
    user_id    UUID,           -- partition key: determines which node
    event_time TIMESTAMP,      -- clustering key: determines sort order within partition
    event_type TEXT,
    payload    TEXT,
    PRIMARY KEY (user_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```

```
Partition: user_id = "abc-123"
  ┌─────────────────────────────────────────────┐
  │ event_time=2024-01-15T10:00  type=PURCHASE  │  ← row 1 (newest first)
  │ event_time=2024-01-15T09:30  type=VIEW      │  ← row 2
  │ event_time=2024-01-15T09:00  type=SEARCH    │  ← row 3
  └─────────────────────────────────────────────┘
  All rows for user "abc-123" stored contiguously on disk
```

### Composite Partition Keys

```sql
-- Bucket time-series data to avoid unbounded partitions
CREATE TABLE sensor_readings (
    sensor_id TEXT,
    bucket    DATE,            -- time bucket (e.g., one day per partition)
    ts        TIMESTAMP,
    value     DOUBLE,
    PRIMARY KEY ((sensor_id, bucket), ts)
) WITH CLUSTERING ORDER BY (ts DESC);
```

**Why bucket?** A single partition should not exceed ~100MB. Unbounded time-series data for a single key would grow the partition forever — bucketing caps partition size.

### Column Types

| Feature | CQL Syntax | Notes |
|---------|-----------|-------|
| **TTL (Time To Live)** | `INSERT INTO ... USING TTL 86400` | Row auto-expires after N seconds |
| **Counter columns** | `UPDATE t SET count = count + 1` | Atomic increment; separate table required |
| **Collections** | `list<text>`, `map<uuid, int>`, `set<text>` | Stored inline; avoid large unbounded sets |
| **Frozen collections** | `frozen<map<uuid, int>>` | Immutable; entire value replaced on write |
| **User-defined types (UDT)** | `CREATE TYPE address (...)` | Nested structured type; use sparingly |

### Partition Size Guidelines

| Partition Size | Status |
|---------------|--------|
| < 1MB | Ideal |
| 1–100MB | Acceptable |
| > 100MB | Warning — causes GC pressure, read latency spikes |
| > 1GB | Critical — must redesign schema |

Monitor with: `nodetool tablehistograms keyspace.table` — shows partition size distribution.

---

## Schema Design Rules (Principal Engineer Level)

1. **Design schema for your queries, not for normalisation** — Cassandra has no joins; denormalise
2. **The partition key is your distribution unit** — all rows with the same partition key land on the same node; choose it to spread load evenly
3. **The clustering key determines query shape** — you can only range-scan on clustering columns in the declared order
4. **One table per query pattern** — it is correct and expected to duplicate data across multiple tables optimised for different access patterns
5. **Avoid `ALLOW FILTERING`** — it triggers a full partition scan; never in production code
6. **Avoid `SELECT *` on large partitions** — page queries with `LIMIT` and `token()` pagination

---

## FAANG Interview Callout

> "Cassandra's architecture is masterless — every node is equal, there's no primary/replica distinction. Consistent hashing on a token ring determines which node owns which rows. Replication is controlled by the replication factor: with RF=3 and NetworkTopologyStrategy, every row has 3 copies in each datacenter, placed on different racks. The gossip protocol propagates cluster state — alive/dead node status, token ranges — to all nodes in O(log N) rounds. The key schema constraint is that Cassandra can only efficiently answer queries that are partition-key-first; everything else is a full scan. When I design a Cassandra schema I start with 'what are my exact query patterns?' and work backwards to partition and clustering key selection."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | What happens after the coordinator receives a request |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | CAP analysis, how this architecture differs from DynamoDB |
| [04-tuning-guide.md](04-tuning-guide.md) | num_tokens, phi_convict_threshold, replication factor tuning |
