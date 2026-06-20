# Cassandra — Trade-offs & Alternatives

## CAP Theorem Position

Cassandra is an **AP system** — it prioritises Availability and Partition Tolerance over strong Consistency.

```
         Consistency
              │
     CP       │       CA
  (ZooKeeper  │   (traditional
   HBase)     │    RDBMS — not
              │    realistic in
              │    distributed)
──────────────┼──────────────────
              │
     AP       │
  (Cassandra  │
   DynamoDB   │
   CouchDB)   │
              │
        Partition Tolerance
```

### What AP Means in Practice

During a **network partition** (nodes can't communicate):
- Cassandra **continues accepting writes** on both sides of the partition
- The two sides **diverge** — same partition key may have different values on different nodes
- After the partition heals, **last-write-wins (LWW)** reconciliation resolves conflicts using cell-level timestamps
- Data written during the partition is not lost — it converges eventually

**Implication**: Cassandra can return stale reads. If Node A and Node B have a conflicting version of row X, and you read from Node A with consistency ONE, you get Node A's version even if Node B has newer data.

---

## Tunable Consistency: The W + R > N Quorum Rule

Cassandra does not force you to choose AP or CP globally — you choose **per operation** via the consistency level. The rule for strong consistency:

```
W + R > N   (where N = replication factor)

Example: RF=3
  QUORUM writes: W = ceil(3/2)+1 = 2
  QUORUM reads:  R = ceil(3/2)+1 = 2
  W + R = 4 > 3 ✓  →  at least 1 replica in common → consistent
```

### Consistency Levels Reference

| Consistency Level | Write ACKs Required | Read Replicas Queried | Tolerates Node Failures | Latency |
|------------------|--------------------|-----------------------|------------------------|---------|
| **ONE** | 1 replica | 1 replica | 2 of 3 down | Lowest |
| **TWO** | 2 replicas | 2 replicas | 1 of 3 down | Low |
| **QUORUM** | ceil(RF/2)+1 | ceil(RF/2)+1 | RF=3: 1 node down | Medium |
| **LOCAL_QUORUM** | Quorum within local DC | Quorum within local DC | Local DC: 1 node down | Medium (no cross-DC) |
| **EACH_QUORUM** | Quorum in EACH DC | — (write only) | Each DC: 1 node down | Highest |
| **ALL** | All replicas | All replicas | 0 failures tolerated | Highest |
| **LOCAL_ONE** | 1 replica in local DC | 1 replica in local DC | 2 of 3 in DC down | Lowest |

### Production Recommendation

```
Default choice:    LOCAL_QUORUM for both reads and writes
Rationale:        - Consistent within a DC (W+R > N holds)
                  - No cross-DC penalty for every operation
                  - Tolerates 1 node failure per DC
                  - Used by Netflix, Apple, Uber

For casual data:   ONE (user activity events where eventual is fine)
Never in prod:     ALL (blocks on single slow/down node)
```

### PACELC Extension

PACELC extends CAP: "In case of Partition, choose Availability or Consistency; Else (no partition), choose Latency or Consistency."

Cassandra's PACELC classification: **PA/EL** — during a partition it gives Availability; during normal operation it gives lower Latency at the cost of potential Consistency (with ONE/LOCAL_ONE).

---

## Trade-offs Made in Cassandra's Design

| Design Decision | What You Get | What You Give Up |
|----------------|-------------|-----------------|
| Leaderless replication | No leader bottleneck; any node accepts writes | No linearisability; must use QUORUM for consistency |
| LSM-tree (write-optimised) | O(1) writes, no read-before-write | Read amplification (must merge multiple SSTables) |
| Tunable consistency | Flexibility per operation | Developer must understand W+R>N; wrong choice = stale reads |
| Immutable SSTables + compaction | Simple write path; no in-place update overhead | Compaction uses CPU/IO; space amplification during compaction |
| Wide-column model | Efficient column-family queries; flexible schema per row | No joins; schema must be query-driven; data duplication |
| Eventual consistency + LWW | Availability during partitions | Conflicting concurrent writes resolved by timestamp (silent data loss) |
| Gossip-based failure detection | Fully distributed; no external coordinator | Slower failure detection (~10–30s) vs ZooKeeper (~1–3s) |

---

## Comparison: Cassandra vs Alternatives

### vs Amazon DynamoDB

| Property | Cassandra | DynamoDB |
|----------|-----------|----------|
| **Consistency model** | Tunable (AP default; QUORUM for CP) | Eventual default; strongly consistent reads optional |
| **Data model** | Wide-column; CQL | Key-value + document (flexible attribute model) |
| **Multi-region** | Active-active via NTS; self-managed | Global Tables — managed active-active |
| **Operational burden** | High (repair, compaction, GC tuning) | Zero — fully managed |
| **Query flexibility** | Partition-key primary; limited secondary index | GSI/LSI for secondary; PartiQL for SQL-like queries |
| **Cost model** | Fixed cost (hardware/EC2) — high scale is cheap | Pay-per-request or provisioned; expensive at very high scale |
| **Scalability ceiling** | Unlimited (add nodes) | Unlimited (managed) but cost explodes |
| **Schema migrations** | Non-blocking (add columns online) | Schema-less; no migrations |
| **Best for** | Self-hosted at scale, multi-DC, write-heavy | AWS-native, serverless, unpredictable load |

**When to prefer DynamoDB**: You're all-in on AWS, want zero operational overhead, or your scale is unpredictable (spiky). Cost can be prohibitive at millions of writes/sec.

**When to prefer Cassandra**: You need multi-cloud or on-prem, or your scale is predictable and massive (cost savings at >1B writes/day are substantial).

---

### vs MongoDB

| Property | Cassandra | MongoDB |
|----------|-----------|---------|
| **Data model** | Wide-column (rigid schema per table) | Document (flexible schema per document) |
| **Query flexibility** | Very limited — partition key required | Rich — any field queryable; aggregation pipeline |
| **Consistency** | Tunable AP | Tunable; default eventual (replica sets) |
| **Write throughput** | Higher (LSM-tree, masterless) | Lower (WiredTiger B-tree, primary-based) |
| **Read patterns** | Known, narrow access patterns | Ad-hoc, diverse queries |
| **Sharding** | Automatic (consistent hashing) | Manual zone configuration or Atlas auto-sharding |
| **Joins** | None | `$lookup` (limited) |
| **Best for** | High-volume, schema-stable write streams | Flexible document data with varied read patterns |

**When to prefer MongoDB**: Your schema evolves rapidly, you need rich querying, or your data is naturally document-shaped (nested objects with varied structures).

**When to prefer Cassandra**: Write throughput is primary, schema is stable and query-pattern-driven.

---

### vs Apache HBase

| Property | Cassandra | HBase |
|----------|-----------|-------|
| **Architecture** | Masterless (leaderless) | Master-slave (HMaster + RegionServers) |
| **Dependency** | Standalone | Requires HDFS + ZooKeeper + YARN |
| **Strong consistency** | No (tunable AP) | Yes (row-level strong consistency) |
| **Write throughput** | Higher (no master bottleneck) | High, but bounded by RegionServer |
| **Operational complexity** | Medium | Very high (Hadoop ecosystem) |
| **Integration** | Standalone or with Spark | Native Hadoop; MapReduce, Spark, Hive |
| **Best for** | High availability, multi-DC, write-heavy | Hadoop-native analytics, strong consistency needed |

**When to prefer HBase**: You're already in the Hadoop ecosystem, need strong consistency at row level, or have massive HDFS-backed storage requirements.

---

### vs ScyllaDB

| Property | Cassandra | ScyllaDB |
|----------|-----------|---------|
| **Architecture** | JVM-based | C++, shard-per-core (no JVM, no GC) |
| **Latency** | p50: 1–5ms; p99: 10–50ms | p50: < 1ms; p99: 1–5ms |
| **Throughput** | ~100K writes/sec/node (SSD) | ~500K–1M writes/sec/node (SSD) |
| **CQL compatibility** | Full CQL | Full CQL (drop-in replacement) |
| **Operational overhead** | Medium (GC tuning required) | Lower (no GC; auto-tuning compaction) |
| **Cost** | Lower hardware for same throughput | 3–5x better hardware utilisation |
| **Maturity** | Very mature (13+ years) | Newer (2015); growing fast |
| **Best for** | Established Cassandra deployments | New high-performance deployments; replacing Cassandra at scale |

**When to prefer ScyllaDB**: New deployment with strict latency requirements; Discord migrated from Cassandra to ScyllaDB specifically for p99 latency and lower operational complexity.

---

## Decision Flowchart: Cassandra vs Alternatives

```
Is operational overhead acceptable (no managed service required)?
  NO  → DynamoDB (AWS) or Cosmos DB (Azure)
  YES ↓

Is strong consistency required (financial transactions, inventory counts)?
  YES → PostgreSQL / CockroachDB / Spanner
  NO  ↓

Are access patterns predictable and partition-key-driven?
  NO  → MongoDB (flexible queries) or Elasticsearch (search)
  YES ↓

Is write throughput the primary bottleneck (> 50K writes/sec per node)?
  NO  → PostgreSQL with partitioning is simpler
  YES ↓

Is data time-series with TTL?
  YES → Consider InfluxDB or TimescaleDB for simpler operational model
       Cassandra with TWCS if already in Cassandra ecosystem
  NO  ↓

Is p99 latency < 5ms required and you're starting fresh?
  YES → ScyllaDB (Cassandra-compatible, 3–5x better latency)
  NO  → Apache Cassandra
```

---

## When Cassandra Fails (Known Limitations)

1. **Anti-entropy repair must be run regularly** — if you don't run `nodetool repair` within `gc_grace_seconds`, deleted data can be resurrected
2. **JVM GC pauses** — stop-the-world GC pauses (G1GC) cause latency spikes; nodes appear temporarily unresponsive to gossip
3. **Wide partitions** — partitions > 1GB cause read timeouts, GC pressure, repair failures
4. **Concurrent schema changes** — schema disagreement across nodes can cause `InvalidQueryException`
5. **No transactions** — multi-partition operations are not atomic; lightweight transactions (LWT with Paxos) exist but are very slow (10–100x slower than regular writes)
6. **Secondary indexes** — Cassandra's built-in secondary indexes are per-node local indexes; they do NOT scale like partition-key queries and cause full-cluster scans for low-selectivity predicates

---

## FAANG Interview Callout

> "When an interviewer asks 'why Cassandra over DynamoDB?', the answer is usually cost and multi-cloud flexibility at extreme scale. Cassandra at Apple (75K nodes) or Netflix would cost tens of billions per year on DynamoDB. When they ask 'why not Cassandra?', the answer is operational overhead — Cassandra requires a dedicated team to manage repair schedules, compaction, and GC tuning. DynamoDB gives you all of Cassandra's availability guarantees with zero ops. The deeper trade-off: with QUORUM consistency on Cassandra you get the same consistency guarantees as DynamoDB's strongly-consistent reads, but you've now added cross-replica network latency to every read. LOCAL_QUORUM is the compromise — consistent within a DC, eventual across DCs. That's the right answer for multi-region systems that can tolerate some replication lag."

---

## Related Files

| File | Topic |
|------|-------|
| [01-architecture.md](01-architecture.md) | How the ring topology creates the distributed properties discussed here |
| [02-read-write-path.md](02-read-write-path.md) | How LWW and read repair work in practice |
| [04-tuning-guide.md](04-tuning-guide.md) | How to tune consistency level, replication factor, and repair frequency |
