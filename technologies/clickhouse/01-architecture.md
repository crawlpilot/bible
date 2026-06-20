# 01 — ClickHouse Architecture

---

## 1. Column-Oriented Storage — The Foundational Decision

In a **row-oriented** database (Postgres, MySQL), a row `(id=1, name="Alice", age=30, country="US")` is stored contiguously on disk. Scanning a column means reading the entire row, then discarding unwanted fields.

In a **column-oriented** database, each column is stored as a separate file:
```
age.bin:     [30, 25, 42, 19, 55, ...]   ← only this file is read for "SELECT avg(age)"
country.bin: [US, UK, US, DE, US, ...]
name.bin:    [Alice, Bob, Carol, ...]
```

**The analytic query benefit:**

For a query `SELECT avg(age), country FROM events WHERE date > '2024-01-01'`:
- Row store: reads ALL columns for every matching row, discards `name`, `id`, `email`, etc.
- Column store: reads ONLY `age`, `country`, `date` columns — the rest don't touch disk.

For a typical analytics table with 50 columns and a query touching 3–5 columns: **column store reads 6–10% of the data** a row store would read.

**Compression benefit:** A column of integers all in the range `[0, 100]` compresses dramatically better than a mixed row. Delta encoding + LZ4 on a timestamp column can achieve 20–50× compression.

---

## 2. The MergeTree Storage Engine

`MergeTree` is ClickHouse's primary storage engine. All production tables use it or one of its variants.

### Core Mechanics

**Data Parts:** Every INSERT creates one or more **parts** — immutable directories on disk. A part contains:
```
part_dir/
├── primary.idx        ← sparse primary index (every 8192 rows, one entry)
├── age.bin            ← compressed column data
├── age.mrk2           ← mark file: byte offsets into age.bin per granule
├── country.bin
├── country.mrk2
├── date.bin
├── date.mrk2
├── checksums.txt      ← per-column checksums
├── columns.txt        ← column names and types
└── count.txt          ← total row count in this part
```

**Granule:** The atomic unit of I/O — 8,192 rows by default (`index_granularity = 8192`). A mark file entry points to the byte offset in the column `.bin` file where a granule starts. The primary index stores the first row of each granule.

**Background Merges:** ClickHouse continuously merges small parts into larger parts in the background. This is like LSM-tree compaction — small parts (from many inserts) are merged into medium parts, then large parts. During a merge:
- Parts are sorted by the sorting key.
- For `ReplacingMergeTree`, duplicate keys are deduplicated.
- For `AggregatingMergeTree`, aggregate states are combined.
- The merged part replaces the source parts atomically.

```
Initial state:       [part_1: 1K rows] [part_2: 1K rows] [part_3: 1K rows]
After merge:         [part_merged: 3K rows]
```

**Why this is "merge" in the name:** The engine is named after the merge operation, not B-tree. There are no B-trees in ClickHouse.

---

## 3. The Sparse Primary Index

ClickHouse's primary index is **sparse** — it does not index every row. Instead, it indexes every `index_granularity`-th row (every 8,192 rows by default).

```
Primary index (primary.idx):
Row 0:       date=2024-01-01, user_id=1000    ← entry 0
Row 8192:    date=2024-01-03, user_id=1052    ← entry 1
Row 16384:   date=2024-01-07, user_id=1103    ← entry 2
...
```

**Query execution with the sparse index:**

```sql
SELECT count(*) FROM events WHERE date = '2024-01-05'
```

1. Binary search on `primary.idx` → find granules where `date` could be `2024-01-05`.
2. Read the mark file entries for those granules → get byte offsets in `date.bin`.
3. Read only those byte ranges from `date.bin` (via `pread`, may be parallel).
4. Evaluate `date = '2024-01-05'` on those rows.
5. Sum the count.

**Granules skipped = I/O skipped.** For a table with 1 billion rows and a query matching 1% of dates: ~990 granules (of 1,000 total 8,192-row granules) are skipped. Only ~10 are read.

### Primary Key vs Sorting Key

```sql
CREATE TABLE events (
    date        Date,
    user_id     UInt64,
    event_type  LowCardinality(String),
    value       Float64
)
ENGINE = MergeTree()
ORDER BY (date, user_id)           -- sorting key: data is ordered by this
PRIMARY KEY (date, user_id)        -- primary key: indexed in primary.idx (default = ORDER BY)
PARTITION BY toYYYYMM(date)        -- partition key: separate directory per month
```

**Key insight:** The `ORDER BY` clause is the sorting key — the physical sort order of rows. The `PRIMARY KEY` is what's stored in `primary.idx`. By default they're the same. You can have a primary key that is a **prefix** of the sorting key:

```sql
ORDER BY (date, user_id, event_type)
PRIMARY KEY (date, user_id)   -- index only on date + user_id, not event_type
```

This saves index memory while still allowing efficient range lookups on `(date, user_id)`.

**Why column order in the sorting key matters:**

| Query | `ORDER BY (date, user_id)` | `ORDER BY (user_id, date)` |
|-------|--------------------------|--------------------------|
| `WHERE date = '2024-01-01'` | Efficient — date is first | Full scan — date is second |
| `WHERE user_id = 12345` | Full scan — user_id is second | Efficient |
| `WHERE date = '2024-01-01' AND user_id = 12345` | Efficient | Partly efficient |

**Rule:** Put the column with the highest cardinality reduction first, then the next. Queries must match the prefix of the sorting key.

---

## 4. The MergeTree Family

| Engine | Additional Behavior | Use Case |
|--------|--------------------|---------| 
| `MergeTree` | None — base engine | Append-only logs, event data |
| `ReplacingMergeTree(version)` | Deduplicates rows with same sorting key; keeps highest `version` | Upsert semantics (CDC from OLTP) |
| `AggregatingMergeTree` | Merges aggregate states (not values) | Pre-aggregated rollup tables |
| `SummingMergeTree(col)` | Sums numeric columns for same sorting key | Counters, metrics rollups |
| `CollapsingMergeTree(sign)` | Cancels rows with `sign=-1` against `sign=1` rows | Event sourcing, corrections |
| `VersionedCollapsingMergeTree(sign, version)` | Like Collapsing but order-independent | Out-of-order corrections |
| `GraphiteMergeTree` | Rollup/retention rules for Graphite metrics | Time-series rollup |

### `AggregatingMergeTree` — Deep Dive

This engine is why ClickHouse is so effective for pre-aggregated rollups (e.g., the ad click aggregator HLD):

```sql
-- Raw events table (MergeTree)
CREATE TABLE ad_clicks_raw (
    ad_id    UInt64,
    minute   DateTime,
    clicks   UInt32
) ENGINE = MergeTree()
ORDER BY (ad_id, minute);

-- Aggregated rollup (AggregatingMergeTree)
CREATE TABLE ad_clicks_1min (
    ad_id      UInt64,
    minute     DateTime,
    clicks_agg AggregateFunction(sum, UInt64),  -- aggregate state, not a simple integer
    uniq_agg   AggregateFunction(uniqExact, UInt64)
) ENGINE = AggregatingMergeTree()
ORDER BY (ad_id, minute);

-- Materialized view that populates the rollup
CREATE MATERIALIZED VIEW ad_clicks_mv TO ad_clicks_1min AS
SELECT
    ad_id,
    toStartOfMinute(event_time) AS minute,
    sumState(clicks)       AS clicks_agg,
    uniqExactState(user_id) AS uniq_agg
FROM ad_clicks_raw
GROUP BY ad_id, minute;

-- Query the rollup
SELECT
    ad_id,
    minute,
    sumMerge(clicks_agg)    AS total_clicks,
    uniqExactMerge(uniq_agg) AS unique_users
FROM ad_clicks_1min
WHERE ad_id = 12345 AND minute >= now() - INTERVAL 1 HOUR
GROUP BY ad_id, minute
ORDER BY minute;
```

**`sumState` vs `sum`:** `sumState` stores a serialized aggregate state (partial result). During merge, `sumMerge` combines states. This enables distributed pre-aggregation without losing precision — multiple partial aggregations can be combined correctly.

---

## 5. Partitioning

Partitioning physically separates data on disk into subdirectories. Queries with a partition key filter skip entire partitions without reading primary.idx.

```sql
PARTITION BY toYYYYMM(date)   -- one partition per month
```

```
data/
├── 202401/  ← all data for January 2024
│   ├── 20240101_1_1_0/    ← part
│   ├── 20240101_2_2_0/
│   └── 20240101_1_2_1/    ← merged part
├── 202402/
│   └── ...
└── 202403/
```

**Partition operations are instant:** `ALTER TABLE events DROP PARTITION '202401'` deletes the entire directory — no row-level deletion.

**Partitioning anti-patterns:**

```sql
-- BAD: partition by high-cardinality column (user_id, event_id)
PARTITION BY user_id   -- creates millions of tiny partitions = "too many parts" error

-- BAD: partition too coarsely for a high-volume table
PARTITION BY toYear(date)  -- 1 partition = huge parts = slow DROP PARTITION

-- GOOD: month for most analytics tables
PARTITION BY toYYYYMM(date)

-- GOOD: day for very high volume (>10B rows/day)
PARTITION BY toDate(date)
```

**Max recommended partitions per table:** ~1,000. Beyond this, background merge metadata overhead becomes significant.

---

## 6. Replication — `ReplicatedMergeTree`

Any `MergeTree` variant can be replicated by prepending `Replicated`:

```sql
CREATE TABLE events ON CLUSTER my_cluster (
    ...
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
ORDER BY (date, user_id)
PARTITION BY toYYYYMM(date);
```

**ZooKeeper / ClickHouse Keeper role:**
- Stores replication log: every INSERT creates an entry; replicas fetch and apply it.
- Coordinates part metadata: which parts exist, which are being merged.
- Leader election for replicas (one replica leads merge scheduling per table).

**Replication is asynchronous:**
- INSERT goes to one replica → stored in ZooKeeper → other replicas fetch the data.
- There is no synchronous quorum write by default. `insert_quorum = 2` forces waiting for N replicas to confirm.
- Reads are served from any replica — eventual consistency within the replica set.

```
INSERT → Replica 1 (leader):
  1. Write part to local disk
  2. Register part in ZooKeeper replication log
  3. Return success to client (insert_quorum = 1, default)

Replica 2 (follower):
  1. Poll ZooKeeper log
  2. Download part from Replica 1 (or fetch directly from S3 if using shared storage)
  3. Apply part locally
  (typically < 1 second behind)
```

---

## 7. Sharding — Distributed Engine

ClickHouse sharding is **manual** — you define shards and the routing logic.

```sql
-- On each node, a local table:
CREATE TABLE events_local ON CLUSTER my_cluster (...)
ENGINE = ReplicatedMergeTree(...)
ORDER BY ...;

-- A distributed view that spans all shards:
CREATE TABLE events ON CLUSTER my_cluster (...)
ENGINE = Distributed(
    my_cluster,    -- cluster name (defined in config.xml)
    default,       -- database
    events_local,  -- local table name
    rand()         -- sharding key: rand() = random round-robin
    -- Or: cityHash64(user_id) for consistent routing
);
```

**Distributed query execution:**

```
Client → Distributed table on node 1
  → fan-out: send query to all shards (or relevant shards if sharding key is in WHERE)
  → each shard executes locally, returns partial results
  → node 1 merges partial results, returns to client
```

**Sharding key strategy:**

| Key | Good For | Problem |
|-----|----------|---------|
| `rand()` | Even data distribution | No shard pruning — all shards always queried |
| `cityHash64(user_id)` | User-centric queries | Shard pruning works when user_id in WHERE |
| `toYYYYMM(date)` | Time-partitioned queries | Skewed distribution if recent data >> historical |
| `intHash32(ad_id)` | Ad-centric analytics | Good for ad click aggregator |

---

## 8. ClickHouse Keeper — Replacing ZooKeeper

ZooKeeper is a scaling bottleneck in large ClickHouse clusters. ClickHouse Keeper is a ZooKeeper-compatible implementation built into ClickHouse itself, using the **Raft consensus protocol**.

**Advantages over ZooKeeper:**

| Aspect | ZooKeeper | ClickHouse Keeper |
|--------|-----------|------------------|
| Consistency protocol | ZAB (ZooKeeper Atomic Broadcast) | Raft |
| Data format | Java serialization | Native ClickHouse format |
| Disk I/O | JVM GC pauses affect latency | No GC — lower tail latency |
| Deployment | Separate cluster (3–5 nodes) | Can co-locate on ClickHouse nodes |
| Multi-region | Hard | Raft makes it feasible |
| Operational complexity | High (separate Java stack) | Low (same binary) |

**Recommended deployment (production):** 3 dedicated ClickHouse Keeper nodes for clusters with >10 nodes, or co-located for smaller deployments.

---

## FAANG Interview Callout

**Q: Why does ClickHouse use a sparse primary index instead of a B-tree?**

A sparse index with 8,192-row granules is a deliberate trade-off for analytics:
- A B-tree indexes every row → massive index size for 100B rows → random I/O on lookup.
- A sparse index indexes every 8,192 rows → small index (fits in RAM for most tables) → sequential I/O on scan.
- Analytics queries scan ranges, not point-lookup individual rows. Scanning 8,192 rows to find 1 is cheap when those 8,192 rows are laid out sequentially (one `pread` → CPU cache → SIMD process).
- For point lookups of individual rows, ClickHouse is the wrong tool. The sparse index is not a bug — it's the right trade-off for OLAP.

**Q: What happens if you insert 1 row at a time into ClickHouse?**

Each insert creates at least one part. Parts have a fixed overhead (directory, index file, mark files). Inserting 1,000 rows one-at-a-time creates 1,000 parts. Background merges can't keep up. You hit the "too many parts" error (default: ~1,000 parts per partition triggers a "too many parts" exception). **Minimum recommended batch: 1,000 rows. Production sweet spot: 100K–1M rows per insert.**
