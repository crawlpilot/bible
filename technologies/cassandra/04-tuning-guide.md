# Cassandra — Tuning Guide

## Tuning Philosophy

Cassandra has over 200 configuration parameters. In practice, you need to deeply understand ~20. The tuning categories are:

1. **Replication & consistency** — the most impactful, set at design time
2. **Compaction** — the biggest lever for read performance
3. **Memory** — MemTable, bloom filters, key cache, row cache
4. **JVM** — heap size, GC algorithm
5. **Timeouts & concurrency** — thread pool sizing
6. **Disk layout** — separating data from commit log

---

## 1. Replication Factor (Design Time)

**File**: `cqlsh` (per-keyspace DDL)

| RF | Node failures tolerated | Notes |
|----|------------------------|-------|
| 1 | 0 | Development only. Data loss on any node failure. |
| 2 | 0 with QUORUM, 1 with ONE | Not recommended — QUORUM = all nodes needed |
| **3** | **1 (QUORUM), 2 (ONE)** | **Production standard. Minimum for QUORUM safety.** |
| 5 | 2 (QUORUM) | Multi-DC active-active; high availability headroom |

```sql
-- Production keyspace
CREATE KEYSPACE orders
WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'us-east-1': 3,
    'eu-west-1': 3
};
```

**Rule**: Never change RF without running a full repair afterwards. Adding RF adds replicas but old nodes won't have the data until repair streams it.

---

## 2. Consistency Level (Per-Query — Application Code)

| Scenario | Write CL | Read CL | Rationale |
|----------|---------|---------|-----------|
| Default production | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Consistent within DC; tolerates 1 node failure |
| Maximum availability | `ONE` | `ONE` | May return stale data; accept eventual consistency |
| Cross-DC consistency | `EACH_QUORUM` | `LOCAL_QUORUM` | Writes confirmed in all DCs; reads from local DC |
| Debugging only | `ALL` | `ALL` | Blocks on all replicas; never in production |
| Counters | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Counters require idempotent-safe consistency |

```java
// Java driver — set per statement
SimpleStatement stmt = SimpleStatement.builder(
    "INSERT INTO user_events (user_id, ts, type) VALUES (?, ?, ?)")
    .setConsistencyLevel(ConsistencyLevel.LOCAL_QUORUM)
    .build();
```

---

## 3. Compaction Strategy (Per-Table DDL)

Select at table creation based on the dominant access pattern. Changing strategy on a live table triggers a full rewrite — plan ahead.

```sql
-- Write-heavy: SizeTieredCompactionStrategy (default)
CREATE TABLE sensor_raw (
    sensor_id UUID,
    ts        TIMESTAMP,
    value     DOUBLE,
    PRIMARY KEY (sensor_id, ts)
) WITH compaction = {
    'class': 'SizeTieredCompactionStrategy',
    'min_threshold': 4,       -- compact when 4 SSTables of similar size exist
    'max_threshold': 32,      -- max SSTables to compact in one pass
    'min_sstable_size': 52428800  -- 50MB minimum size to be eligible
};

-- Read-heavy: LeveledCompactionStrategy
CREATE TABLE product_catalog (
    product_id UUID PRIMARY KEY,
    name       TEXT,
    price      DECIMAL
) WITH compaction = {
    'class': 'LeveledCompactionStrategy',
    'sstable_size_in_mb': 160,   -- target SSTable size at each level
    'fanout_size': 10            -- size multiplier between levels
};

-- Time-series with TTL: TimeWindowCompactionStrategy
CREATE TABLE metrics (
    host      TEXT,
    bucket    DATE,
    ts        TIMESTAMP,
    value     DOUBLE,
    PRIMARY KEY ((host, bucket), ts)
) WITH compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': 1      -- one window per day
} AND default_time_to_live = 2592000; -- 30 days TTL
```

---

## 4. Key Parameters in cassandra.yaml

### Memory

| Parameter | Default | Recommendation | Notes |
|-----------|---------|---------------|-------|
| `memtable_heap_space_in_mb` | 1/4 heap | Leave at default | Total heap for all MemTables |
| `memtable_offheap_space_in_mb` | 1/4 heap | 2048–4096 MB | Off-heap MemTable — reduces GC pressure |
| `key_cache_size_in_mb` | 100MB | 200–500MB (SSD), 100MB (HDD) | Caches partition key → byte offset mappings; critical for read performance |
| `row_cache_size_in_mb` | 0 (disabled) | Keep disabled unless read-heavy + small working set | Row cache is very coarse; usually not worth the memory vs key cache |

### Bloom Filters

| Parameter | Default | When to Tune |
|-----------|---------|-------------|
| `bloom_filter_fp_chance` | 0.01 (1%) | Lower to 0.001 for read-heavy tables (3x more memory, 10x fewer false disk reads); raise to 0.1 for write-heavy tables with low read rate |

```sql
-- Per-table bloom filter tuning
ALTER TABLE user_events WITH bloom_filter_fp_chance = 0.001;
```

### Tombstone & GC

| Parameter | Default | Recommendation |
|-----------|---------|---------------|
| `gc_grace_seconds` | 864000 (10 days) | Must exceed your repair interval. If you repair daily: 259200 (3 days). Never set below your repair cadence. |
| `tombstone_warn_threshold` | 1000 | Keep default; treat warnings as alerts |
| `tombstone_failure_threshold` | 100000 | Never raise this — fix the root cause (use TTL; run repair) |

### Timeouts & Concurrency

| Parameter | Default | Recommendation |
|-----------|---------|---------------|
| `read_request_timeout_in_ms` | 5000 (5s) | Reduce to 2000ms to fail fast; set consistent with your SLA |
| `write_request_timeout_in_ms` | 2000 (2s) | Keep default for most workloads |
| `concurrent_reads` | 32 | Formula: `8 × num_data_drives` (e.g., 4 SSD drives → 32) |
| `concurrent_writes` | 32 | Formula: `8 × num_cores` for mostly sequential workloads |
| `concurrent_compactors` | min(2, num_disks) | Raise to 4–8 for SSD with STCS or LCS |
| `num_tokens` | 256 | Reduce to 16–32 for large nodes (> 2TB) to reduce gossip state size |

### Disk Layout

**Critical**: Commit log and data directories should be on **separate physical disks** (or at minimum separate partitions).

```yaml
# cassandra.yaml
data_file_directories:
    - /data/cassandra/data       # SSD or NVMe — random I/O (reads, compaction)

commitlog_directory: /commitlog/cassandra   # SSD — sequential I/O; separate spindle ideal

hints_directory: /data/cassandra/hints
```

Mixing commit log with data on the same disk causes compaction I/O to compete with sequential commit log writes, reducing write throughput.

---

## 5. JVM Tuning

### Heap Size

| Cluster Size | Recommended Heap | Rationale |
|-------------|-----------------|-----------|
| Development | 2–4 GB | Minimal |
| Production (< 1TB/node) | **8 GB** | Standard; beyond 8GB GC pauses increase significantly |
| Production (> 1TB/node) | 8 GB + aggressive off-heap | Use off-heap for MemTable; keep heap at 8GB |

```
# jvm.options (Cassandra 4.x)
-Xms8G
-Xmx8G  ← heap min = max to avoid resize pauses

# GC: G1GC (Cassandra 4.x default; CMS is legacy)
-XX:+UseG1GC
-XX:G1RSetUpdatingPauseTimePercent=5
-XX:MaxGCPauseMillis=500
-XX:InitiatingHeapOccupancyPercent=70  ← trigger G1 concurrent GC at 70% heap used
```

### Why 8GB Heap Limit?

G1GC must scan the entire heap during STW (stop-the-world) phases. At 8GB with `MaxGCPauseMillis=500ms`, pauses are typically < 500ms. At 16GB, pauses can reach 2–4 seconds — long enough for the gossip failure detector to suspect the node (φ rises above threshold), causing unnecessary node flapping in the cluster.

**Alternative**: Use `off_heap_memtables_enabled: true` + ZGC (Cassandra 5.x) for near-zero GC pauses at large heap sizes.

---

## 6. Anti-Patterns (Production Killers)

| Anti-Pattern | Impact | Fix |
|-------------|--------|-----|
| **`ALLOW FILTERING`** | Full partition scan on every read — O(N) not O(1) | Redesign table with correct partition key |
| **Unbounded partition growth** | Partitions > 1GB cause GC pressure, read timeouts, repair failures | Add time bucket to partition key; use TTL |
| **High-cardinality secondary index** | Local secondary indexes cause scatter-gather — every node queried | Use Elasticsearch or Solr (DSE Search) for secondary access patterns |
| **Deleting rows without TTL in write-heavy tables** | Tombstone accumulation → read latency → `TombstoneOverwhelmingException` | Use TTL on inserts instead of explicit deletes |
| **Large blob storage in Cassandra** | Compaction reads entire blobs; row cache is useless | Store blobs in S3/GCS; store only the reference key in Cassandra |
| **Skip repair > gc_grace_seconds** | Deleted data can be resurrected by a rejoining node | Schedule weekly repair with `nodetool repair -pr` |
| **Not separating commit log disk** | Compaction and commit log I/O contend → write throughput drops by 30–50% | Separate physical disks for data and commit log |
| **Counter tables with QUORUM** | Each counter increment is a read + write (Paxos-like); bottleneck at scale | Model counters differently or use Spark for batch aggregation |

---

## 7. Monitoring: Key Metrics to Watch

| Metric | Normal | Alert Threshold |
|--------|--------|----------------|
| `Read Latency (p99)` | < 5ms | > 50ms |
| `Write Latency (p99)` | < 2ms | > 10ms |
| `Pending Compactions` | 0–5 | > 15 (compaction falling behind) |
| `Dropped Mutations` | 0 | > 0 (writes being dropped — cluster overloaded) |
| `Tombstone Warnings` | 0 | > 0 per query (investigate schema) |
| `GC Pause Duration` | < 200ms | > 500ms (GC pressure; reduce heap or switch to ZGC) |
| `Heap Usage` | < 70% | > 80% (approaching GC trigger point) |
| `SSTable Count per Table` | < 20 | > 50 (compaction not keeping up; raise `concurrent_compactors`) |

```bash
# Essential nodetool commands
nodetool status                        # cluster health, node states
nodetool tpstats                       # thread pool stats — check for dropped tasks
nodetool compactionstats               # pending compaction work
nodetool tablehistograms ks.table      # partition size, row size, read/write latency distribution
nodetool cfstats ks.table              # SSTable count, bloom filter stats
nodetool repair -pr                    # repair only primary ranges (run on each node)
nodetool gcstats                       # GC pause summary
```

---

## FAANG Interview Callout

> "The two most impactful tuning decisions for Cassandra are compaction strategy and consistency level. For compaction: TWCS for time-series with TTL — it's the only strategy that actually deletes data efficiently. STCS for append-only workloads. LCS when you need predictable read latency. For consistency: LOCAL_QUORUM is the default — it's the sweet spot between consistency and latency in a multi-DC setup. The JVM is the biggest operational pain point: keep heap at 8GB, use G1GC, and monitor for > 500ms pauses. At Apple and Netflix scale, they run dedicated Cassandra platform teams just for this tuning. The biggest anti-pattern I've seen is tombstone accumulation — teams that use explicit deletes instead of TTL and then wonder why reads are timing out."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | Why compaction matters — read amplification from SSTable accumulation |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Consistency level trade-offs; why ScyllaDB avoids JVM GC entirely |
| [05-production-and-research.md](05-production-and-research.md) | How Netflix and Apple operationalise these tuning decisions |
