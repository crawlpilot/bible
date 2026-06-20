# Cassandra — Read & Write Path (Internal Workings)

## Write Path

Cassandra is **write-optimised by design**. Every write is O(1) regardless of data volume — it never reads before writing (no read-before-write), never performs in-place updates, and never seeks on disk for the write itself.

### Step-by-Step Write Flow

```
Client
  │
  ▼
Coordinator Node  (any node; determined by token of partition key)
  │
  ├─ Murmur3(partition_key) → token → replica nodes (e.g., N1, N2, N3 for RF=3)
  │
  ▼
Each Replica Node (in parallel):
  │
  ├─ 1. Write to COMMIT LOG (sequential append, fsync)  ← durability guarantee
  │         /var/lib/cassandra/commitlog/CommitLog-7-*.log
  │
  ├─ 2. Write to MEMTABLE (in-memory sorted structure)  ← live data
  │
  └─ 3. Return ACK to coordinator
            │
            ▼
  Coordinator waits for W ACKs (W = consistency level, e.g., QUORUM = ceil(RF/2)+1)
            │
            ▼
  Client receives success
```

**Key insight**: The commit log write is sequential (append-only) — this is why Cassandra sustains high write throughput even on spinning disks. MemTable writes are in-memory. Neither operation seeks.

### Commit Log

- Sequential, append-only file per node
- Written **before** MemTable for durability
- On crash recovery: replay uncommitted segments to rebuild MemTables
- Segmented: new segment created when current exceeds `commitlog_segment_size` (default 32MB)
- Synced to disk based on `commitlog_sync`:
  - `periodic` (default): fsync every `commitlog_sync_period_in_ms` (10ms) — can lose up to 10ms of writes on hard crash
  - `batch`: fsync on every write — durable but 10–20x lower write throughput

### MemTable

- Per-table, in-memory sorted data structure
- Accepts all writes; holds the most recent version of each cell
- **Flush trigger**: when MemTable reaches `memtable_heap_space_in_mb` / `memtable_offheap_space_in_mb`, or `memtable_flush_period_in_ms` elapses
- After flush: MemTable becomes an immutable SSTable on disk; commit log segment is freed

### SSTable (Sorted String Table)

- Immutable, sorted, on-disk representation of a MemTable flush
- Never modified after written — updates and deletes create new SSTables
- Each SSTable consists of multiple component files:

```
users-1-Data.db         ← actual row data
users-1-Index.db        ← partition index (maps partition key → byte offset in Data.db)
users-1-Filter.db       ← bloom filter (is partition key present in this SSTable?)
users-1-Summary.db      ← sparse partition key sample (fits in memory)
users-1-Statistics.db   ← metadata: min/max token, timestamps, tombstone count
users-1-TOC.txt         ← table of contents: lists component files
```

---

## Read Path

Reads are more expensive than writes because they may need to merge data from multiple SSTables + the MemTable.

### Step-by-Step Read Flow

```
Client
  │
  ▼
Coordinator Node
  │
  ├─ Hash partition key → token → replica nodes
  ├─ Send read request to closest replica (typically)
  │   or to all replicas (for QUORUM with digest requests)
  │
  ▼
Replica Node — per SSTable + MemTable:
  │
  ├─ 1. CHECK ROW CACHE (if enabled) ──► cache hit? return immediately
  │
  ├─ 2. CHECK BLOOM FILTER (per SSTable)
  │         "Is this partition key possibly in this SSTable?"
  │         NO  → skip this SSTable entirely (saves disk I/O)
  │         YES → proceed (may be false positive, ~1% default)
  │
  ├─ 3. CHECK KEY CACHE (partition key → byte offset in Data.db)
  │         Cache hit → seek directly to offset in Data.db
  │         Cache miss → consult Partition Index
  │
  ├─ 4. READ PARTITION INDEX (Index.db → Summary.db)
  │         Binary search Summary.db (fits in memory) → range in Index.db
  │         Linear scan Index.db → byte offset in Data.db
  │
  ├─ 5. READ DATA (Data.db) at the byte offset
  │
  └─ 6. MERGE: MemTable + all SSTables (by timestamp — latest cell wins)
            │
            ▼
  Return merged result to coordinator
            │
            ▼
  Coordinator: if multiple replicas responded, compare digests
  Read repair (async or blocking) if replicas disagree
```

### Read Amplification Problem

Each additional SSTable on disk adds one more merge step. If a node has 50 SSTables for a table, a single read may touch all 50 files. This is why **compaction** is critical — it merges SSTables to reduce read amplification.

---

## Bloom Filters

A **Bloom filter** is a probabilistic data structure that answers: *"Is element X definitely NOT in this set, or possibly yes?"*

| Answer | Meaning |
|--------|---------|
| NO | Partition is definitely NOT in this SSTable — skip it (zero false negatives) |
| YES | Partition is POSSIBLY in this SSTable — read it (may be a false positive) |

Cassandra keeps one Bloom filter per SSTable in memory. For a 1% false positive rate (`bloom_filter_fp_chance = 0.01`), ~10 bits per entry.

**Trade-off**: Lower FP chance → larger Bloom filter in memory → fewer wasted disk reads.  
`bloom_filter_fp_chance = 0.01` (default, suitable for balanced workloads)  
`bloom_filter_fp_chance = 0.001` (read-heavy — 3x larger filter, 10x fewer false positives)  
`bloom_filter_fp_chance = 0.1` (write-heavy / small memory — accept more disk reads)

---

## Compaction

Without compaction, SSTables accumulate indefinitely. Compaction merges multiple SSTables into fewer (or one) larger SSTable, removing obsolete data (old versions of cells, expired TTLs, tombstones) and improving read performance.

### Why Compaction Is Necessary

```
Time →

T1: SSTable-1: { user:A → {name: "Alice", age: 30} }
T2: SSTable-2: { user:A → {age: 31} }            ← update: only age changed
T3: SSTable-3: { user:A → TOMBSTONE }             ← delete
T4: SSTable-4: { user:B → {name: "Bob"} }

Without compaction: reading user:A requires checking 4 SSTables
After compaction:   SSTable-1234: { user:B → {name: "Bob"} }
                    user:A is gone (tombstone + older data removed)
```

### Compaction Strategies

#### 1. SizeTieredCompactionStrategy (STCS) — default

**How it works**: Groups SSTables of similar size; compacts when a group reaches `min_threshold` (default 4).

```
4 × ~100MB SSTables → compact → 1 × ~400MB SSTable
4 × ~400MB SSTables → compact → 1 × ~1.6GB SSTable
```

| Property | Value |
|----------|-------|
| Write amplification | Low (1x per tier) |
| Read amplification | Medium (SSTables grow; more to merge) |
| Space amplification | High (needs ~50% free space for compaction) |
| Best for | **Write-heavy workloads** with infrequent reads; time-series append |

#### 2. LeveledCompactionStrategy (LCS)

**How it works**: SSTables organised into levels (L0, L1, L2…). Each level is 10x larger than the previous. SSTables within a level have non-overlapping key ranges. Compaction always produces non-overlapping SSTables.

```
L0: several SSTables (can overlap)
L1: 10 × 160MB = 1.6GB  (non-overlapping key ranges)
L2: 10 × 1.6GB = 16GB   (non-overlapping key ranges)
```

| Property | Value |
|----------|-------|
| Write amplification | High (data compacted multiple times across levels) |
| Read amplification | Low (at most 1 SSTable per level for a given key) |
| Space amplification | Low (~10% overhead) |
| Best for | **Read-heavy workloads**; when storage efficiency matters |

#### 3. TimeWindowCompactionStrategy (TWCS)

**How it works**: Groups SSTables by time window (e.g., one window per day). Never compacts across windows. Expired windows drop entirely when all data has TTL-expired.

```
Window: 2024-01-15: SSTables for data written that day → compact together
Window: 2024-01-14: SSTables from yesterday → compact and eventually expire
```

| Property | Value |
|----------|-------|
| Write amplification | Low |
| Read amplification | Low within a time window |
| Space amplification | Low (windows drop cleanly) |
| Best for | **Time-series data with TTL** — IoT, metrics, log data |
| Critical requirement | Writes must be nearly monotonically increasing (write to past windows causes cross-window compaction) |

### Compaction Selection Guide

```
Write-heavy, no TTL?   → STCS
Read-heavy, mixed?     → LCS
Time-series with TTL?  → TWCS (by far the best for IoT/metrics)
```

---

## Tombstones

Cassandra is **immutable** — deletes do not remove data immediately. Instead, a **tombstone** marker is written. The actual data is removed during compaction after `gc_grace_seconds` has elapsed.

### Why gc_grace_seconds?

Imagine a node goes down during a delete. The tombstone is written on the other replicas. When the node comes back up, hinted handoff replays the tombstone to it. If compaction had already run and removed the tombstone, the node would "resurrect" the deleted data. `gc_grace_seconds` (default: 864,000 = 10 days) must be longer than the maximum time a node can be down before being replaced.

```
t=0:    DELETE user_id='abc' FROM users          ← tombstone written to all live replicas
t=1d:   Node D comes back online                 ← hinted handoff delivers tombstone to D
t=10d:  gc_grace_seconds elapses                 ← safe to physically remove tombstone + data
t=10d+: Compaction removes the data from disk    ← actual disk space reclaimed
```

### Tombstone Accumulation Anti-Pattern

If a table generates many tombstones faster than compaction removes them:
1. Reads must scan tombstones to verify data is deleted → read latency increases
2. Cassandra throws `TombstoneOverwhelmingException` at 100,000 tombstones in a partition scan

**Symptoms**: Read timeouts increasing, GC pressure, `WARN` logs about tombstone count.

**Solutions**:
- Use TTL instead of explicit deletes for time-bounded data
- Choose TWCS so expired data drops entirely with the time window
- Reduce `gc_grace_seconds` if your repair schedule is faster (e.g., 3 days instead of 10)
- Run anti-entropy repair more frequently

---

## Hinted Handoff & Read Repair

### Hinted Handoff

When a replica node is down during a write, the coordinator stores a **hint** — a copy of the mutation + target node address. When the target node comes back, the coordinator replays the hint.

**Scope**: Hints stored for `max_hint_window_in_ms` (default 3 hours). If a node is down longer than 3 hours, it won't receive hints — it must be repaired manually (`nodetool repair`).

### Read Repair

During a read at consistency level QUORUM, the coordinator sends digest requests to multiple replicas. If digests disagree (replicas are out of sync), the coordinator:
1. Fetches the full row from all replicas
2. Determines the winner by timestamp (latest write wins)
3. Sends the correct version to the stale replica(s)

**Speculative execution**: At `read_request_timeout_in_ms × speculative_retry` threshold, Cassandra sends a speculative retry to another replica to reduce tail latency (P99 improvement).

---

## Write Path vs Read Path: Complexity Asymmetry

| | Write | Read |
|-|-------|------|
| Disk I/O | Sequential append (commit log) | Random reads (multiple SSTables) |
| Complexity | O(1) always | O(SSTables) before compaction; O(1) after |
| Latency (p50) | < 1ms | 1–5ms |
| Latency (p99) | 1–5ms | 10–50ms (without tuning) |
| Bottleneck | Flush throughput, commit log sync | Bloom filter + compaction state |

This asymmetry is why Cassandra is described as write-optimised. If your workload is read-heavy, LCS compaction and aggressive Bloom filter sizing are the primary levers.

---

## FAANG Interview Callout

> "The write path is why Cassandra is write-optimised: a write is two sequential appends — commit log for durability, MemTable for in-memory serving — and never a disk seek. Reads are more complex because they merge across multiple SSTables. The Bloom filter is the critical optimisation: it eliminates the need to even look at most SSTables for a given read. Compaction is how you trade write amplification for read performance. I always default to TWCS for time-series tables with TTL because it gives the cleanest deletion semantics — entire time windows expire atomically. The tombstone anti-pattern is a common production gotcha: if you're doing high-volume deletes instead of using TTL, tombstones accumulate and reads slow down — I've seen this crash production clusters."

---

## Related Files

| File | Topic |
|------|-------|
| [01-architecture.md](01-architecture.md) | Ring topology, replication, gossip — how writes are routed |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | How this internal model compares to DynamoDB, HBase |
| [04-tuning-guide.md](04-tuning-guide.md) | Compaction strategy selection, bloom_filter_fp_chance, gc_grace_seconds values |
