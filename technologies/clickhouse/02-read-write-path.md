# 02 — Read and Write Path

---

## 1. Write Path

### Step-by-Step INSERT Flow

```
Client: INSERT INTO events (date, user_id, value) VALUES (...)
          ↓
1. Parse SQL and validate schema
          ↓
2. Sort rows by sorting key (ORDER BY) in memory
          ↓
3. Write new Part to disk:
   - date.bin       (compressed column data)
   - user_id.bin
   - value.bin
   - primary.idx    (sparse index: one entry per 8192 rows)
   - *.mrk2         (mark files: byte offsets per granule per column)
   - checksums.txt
          ↓
4. Register part in ZooKeeper (if ReplicatedMergeTree)
          ↓
5. Return OK to client  ← INSERT completes here (~5–50ms for large batch)
          ↓
6. Background: merge small parts into larger parts
              (asynchronous, independent of client)
```

**The INSERT is synchronous only for step 1–5.** The data is immediately queryable after step 5 — background merges are not blocking.

### Part Naming Convention

```
20240101_1_3_2
│       │ │ └── merge level (0=fresh, 1=first merge, 2=second merge...)
│       │ └──── max block number in this part
│       └────── min block number in this part
└────────────── partition ID (from PARTITION BY expression)
```

A part `20240101_1_1_0` was created directly from an INSERT (merge level 0). After merging parts 1 and 2, you get `20240101_1_2_1` (merge level 1). ClickHouse uses this naming to track the merge history and avoid redundant work.

### Background Merge Process

ClickHouse runs multiple background merge threads. The merge scheduler selects parts to merge based on:
1. **Size similarity:** Merge parts of similar size (avoids a 10GB part being merged with a 1KB part).
2. **Count threshold:** If a partition has too many small parts, force-merge regardless of size.
3. **Merge tree settings:** `max_bytes_to_merge_at_max_space_in_pool`, `merge_tree_max_rows_to_use_cache`, etc.

```
Background merge example:
  Parts before: [1KB] [1KB] [1KB] [1KB] [1KB] [1KB] [1KB] [1KB]
  Merge round 1: [8KB] [8KB] [8KB] [8KB]
  Merge round 2: [32KB] [32KB]
  Merge round 3: [128KB]

During merge:
  - Read source parts (sorted)
  - Merge-sort by sorting key
  - For ReplacingMergeTree: keep max(version) per key
  - For AggregatingMergeTree: combine aggregate states
  - Write new merged part
  - Atomically swap (rename new part, delete old parts)
```

**Mutation (UPDATE/DELETE) as special merge:** ClickHouse `ALTER TABLE UPDATE` and `ALTER TABLE DELETE` are implemented as a forced merge that rewrites affected parts. This is expensive — avoid in high-write scenarios. Use `ReplacingMergeTree` for upserts instead.

---

## 2. Part Storage Layout in Detail

### Column Files (`.bin`)

Each column is stored as a sequence of compressed **blocks**:

```
age.bin:
┌────────────────────────────────────────┐
│ Compressed block 1 (granule 0–8191)    │ ← LZ4 or ZSTD compressed
│ [30, 25, 42, 19, 55, ...]             │
├────────────────────────────────────────┤
│ Compressed block 2 (granule 8192–16383)│
│ [22, 31, 40, ...]                      │
├────────────────────────────────────────┤
│ ...                                    │
└────────────────────────────────────────┘
```

Each compressed block is independently decompressible. The decompressed size is always the granule size × column width.

### Mark Files (`.mrk2`)

Mark files are the **index into the column files**. Each mark entry contains:
- Byte offset in `.bin` file to the start of the compressed block
- Row offset within the decompressed block (for variable-length types)

```
age.mrk2:
Granule 0: {compressed_offset: 0, uncompressed_offset: 0}
Granule 1: {compressed_offset: 4128, uncompressed_offset: 0}
Granule 2: {compressed_offset: 9032, uncompressed_offset: 0}
...
```

**Read process:** Given granule numbers to read (from primary index lookup), fetch the mark entries → seek to exact byte positions in the `.bin` files → decompress those blocks only.

### Primary Index (`primary.idx`)

The primary index stores the first row of each granule for each column in the `PRIMARY KEY`:

```
primary.idx (for ORDER BY (date, user_id)):
Granule 0: (2024-01-01, 1000)
Granule 1: (2024-01-01, 8500)
Granule 2: (2024-01-02, 200)
Granule 3: (2024-01-03, 14200)
...
```

The primary index is loaded entirely into memory (it's small — 1 entry per 8,192 rows × 2 columns × 8 bytes = ~2KB per million rows). Binary search on the in-memory index → identify candidate granule range → use mark files to seek to exact disk positions.

---

## 3. Read Path

### Full Read Path for a Query

```sql
SELECT sum(value) FROM events
WHERE date = '2024-01-01' AND user_id BETWEEN 1000 AND 2000
```

```
1. Query planning:
   - Determine which partitions match (PARTITION BY filter)
   - For each relevant partition, load primary.idx into memory

2. Granule selection via primary index:
   - Binary search: find first granule where (date, user_id) >= (2024-01-01, 1000)
   - Find last granule where (date, user_id) <= (2024-01-01, 2000)
   - Mark granules in range as "candidate"

3. Data skipping index evaluation (if any exist):
   - Check bloom filter / minmax index for each candidate granule
   - Eliminate granules where filter guarantees no matching rows

4. Column reading:
   - For each candidate granule, fetch mark entries for 'date', 'user_id', 'value' columns
   - Issue pread() calls to .bin files at marked byte offsets
   - Decompress LZ4 blocks

5. Vectorized execution:
   - Apply WHERE date = '2024-01-01' filter using SIMD (AVX2/AVX-512)
   - Apply WHERE user_id BETWEEN 1000 AND 2000 using SIMD
   - Accumulate sum(value) using SIMD

6. Return result
```

**Parallelism:** ClickHouse reads multiple granules in parallel, multiple parts in parallel, and multiple shards in parallel (for Distributed queries). The degree of parallelism is controlled by `max_threads` (default: num CPUs).

### Vectorized Execution — SIMD Details

ClickHouse processes data in **vectors** (blocks of ~8,192 values), not row by row.

For `WHERE value > 100.0` on a Float64 column with AVX-512:
- Load 8 doubles (512 bits) in one instruction (`_mm512_loadu_pd`)
- Compare all 8 with 100.0 in one instruction (`_mm512_cmplt_pd_mask`)
- Get a bitmask of which lanes pass the filter
- Accumulate only passing values

This achieves ~8 comparisons/instruction rather than 1. Combined with branch-free code and sequential memory access (perfect cache prefetch), ClickHouse achieves 1–10 billion rows/second effective filter throughput.

**Column-oriented execution also benefits cache:** Scanning `age.bin` = sequential read of integers. The CPU prefetcher predicts the access pattern and loads cache lines ahead. A row-store scan = jumping through memory with stride = row width, defeating the prefetcher.

---

## 4. Data Skipping Indexes (Secondary Indexes)

ClickHouse's primary index handles prefix-of-sorting-key predicates. Data skipping indexes handle other columns.

```sql
-- Define a minmax index on value column
ALTER TABLE events ADD INDEX idx_value value TYPE minmax GRANULARITY 4;

-- Define a bloom filter index for equality lookups on event_type
ALTER TABLE events ADD INDEX idx_event_type event_type TYPE bloom_filter(0.01) GRANULARITY 1;

-- Define a set index (exact values) for low-cardinality columns
ALTER TABLE events ADD INDEX idx_country country TYPE set(100) GRANULARITY 1;

-- Define a token bloom filter for substring search
ALTER TABLE events ADD INDEX idx_message message TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1;
```

### Index Types

| Index Type | Stores | Good For | False Positive Rate |
|-----------|--------|----------|-------------------|
| `minmax` | Min and max value per granule group | Range predicates (`WHERE value BETWEEN 0 AND 100`) | 0% (exact) |
| `bloom_filter` | Probabilistic set membership | Equality predicates (`WHERE event_type = 'click'`) | User-defined (default 1%) |
| `set(N)` | Exact set of up to N distinct values | Low-cardinality equality | 0% if N not exceeded |
| `tokenbf_v1` | Bloom filter of tokens | Substring search (`LIKE '%error%'`) | ~1% |
| `ngrambf_v1` | Bloom filter of N-grams | Fuzzy string search | ~1% |

**GRANULARITY parameter:** How many primary index granules make up one data skipping index granule. `GRANULARITY 4` means the skipping index stores one entry per 4×8,192 = 32,768 rows. Larger = smaller index but less precise skipping.

**How skipping indexes interact with the read path:**
1. Primary index identifies candidate granule range.
2. Skipping index eliminates granules within that range where no rows can match.
3. Only remaining granules are read from disk.

A query on `event_type = 'payment'` with a bloom filter index:
- Primary index: can't help (event_type is not in the sorting key).
- Without skipping index: scan ALL granules.
- With bloom filter: skip granules where the bloom filter says `'payment'` is definitely absent. Typically skips 80–95% of granules for low-frequency values.

---

## 5. Compression Codecs

ClickHouse applies two compression layers:
1. **General compression codec** (LZ4, ZSTD): block-level compression of column data.
2. **Delta/specialized codec**: pre-transforms data before general compression (improves ratio).

```sql
CREATE TABLE metrics (
    timestamp DateTime CODEC(DoubleDelta, LZ4),    -- DoubleDelta for monotonic timestamps
    value     Float64  CODEC(Gorilla, ZSTD(3)),     -- Gorilla for slowly-changing floats
    user_id   UInt64   CODEC(Delta(4), LZ4),        -- Delta for incrementing IDs
    country   LowCardinality(String)                 -- LowCardinality is its own optimization
)
```

### Codec Decision Matrix

| Column Type | Pattern | Recommended Codec | Typical Ratio |
|------------|---------|-------------------|--------------|
| Timestamps, monotonic IDs | Monotonically increasing | `DoubleDelta` + `LZ4` | 20–50× |
| Sensor values, metrics | Slowly changing floats | `Gorilla` + `ZSTD` | 10–30× |
| Incrementing integers | Regular increments | `Delta` + `LZ4` | 5–15× |
| Enum-like strings | Low cardinality (< 10K distinct) | `LowCardinality(String)` | 5–20× |
| Arbitrary strings | High cardinality | `ZSTD(3)` | 2–5× |
| Already compressed | Binary, encrypted | `NONE` | 1× |

### `LowCardinality` — Dictionary Encoding

`LowCardinality(String)` stores the string values as integers (dictionary-encoded). For a column with 100 distinct values across 1 billion rows:
- Normal `String`: 1B × avg_string_len bytes
- `LowCardinality(String)`: 100 × avg_string_len (dictionary) + 1B × 1–2 bytes (indices)

Queries on `LowCardinality` columns also use integer comparison (dictionary lookup) rather than string comparison — faster filter evaluation.

**When not to use `LowCardinality`:** Columns with >10,000 distinct values (URL, user agent, email). The dictionary becomes large and the benefit disappears. Use `String` + `ZSTD`.

---

## 6. Materialized Views

Materialized views in ClickHouse are **triggers on INSERT** — they are not maintained lazily like PostgreSQL materialized views. When rows are inserted into the source table, the materialized view's SELECT is evaluated on those rows and the result is inserted into the target table.

```sql
-- Source: raw click events
CREATE TABLE ad_clicks (
    event_time DateTime,
    ad_id      UInt64,
    user_id    UInt64,
    clicks     UInt32
) ENGINE = MergeTree() ORDER BY (ad_id, event_time);

-- Target: pre-aggregated hourly rollup
CREATE TABLE ad_clicks_hourly (
    hour       DateTime,
    ad_id      UInt64,
    total_clicks  AggregateFunction(sum, UInt64),
    unique_users  AggregateFunction(uniqExact, UInt64)
) ENGINE = AggregatingMergeTree() ORDER BY (ad_id, hour);

-- The trigger: runs on each INSERT to ad_clicks
CREATE MATERIALIZED VIEW ad_clicks_mv TO ad_clicks_hourly AS
SELECT
    toStartOfHour(event_time) AS hour,
    ad_id,
    sumState(clicks)           AS total_clicks,
    uniqExactState(user_id)    AS unique_users
FROM ad_clicks
GROUP BY ad_id, hour;
```

**Important limitation:** Materialized views only process NEW rows (at INSERT time). They do not backfill historical data. To backfill:

```sql
INSERT INTO ad_clicks_hourly
SELECT
    toStartOfHour(event_time) AS hour,
    ad_id,
    sumState(clicks),
    uniqExactState(user_id)
FROM ad_clicks
GROUP BY ad_id, hour;
```

---

## 7. Query Execution Pipeline

```
SQL Text
   ↓ Parser (ANTLR grammar → AST)
   ↓ Analyzer (name resolution, type checking)
   ↓ Optimizer
     - Predicate pushdown (move WHERE into storage layer)
     - Column pruning (only read needed columns)
     - Partition pruning (skip partitions based on PARTITION BY filter)
     - Subquery inlining
     - JOIN reordering (for distributed joins)
   ↓ Query pipeline (DAG of processors)
     - Source processors (read from parts)
     - Transform processors (filter, project, aggregate)
     - Merge processors (combine from parallel streams)
   ↓ Execution (thread pool, SIMD)
   ↓ Result
```

**Pipeline parallelism:** The query DAG is executed by a thread pool. Multiple source processors read parts in parallel. Aggregation is done per-thread, then merged. For Distributed queries, the pipeline spans multiple nodes — each node executes the local portion and sends partial results to the initiator.

---

## FAANG Interview Callout

**Q: Walk through what happens when ClickHouse executes `SELECT count(*) FROM events WHERE user_id = 12345`.**

**Step 1 — Partition pruning:** If `PARTITION BY toYYYYMM(date)`, and no date filter is given, ALL partitions must be checked. (Lesson: always include the partition key in high-frequency queries.)

**Step 2 — Primary index:** `user_id` is not the leading column in `ORDER BY (date, user_id)`. The sparse primary index cannot skip based on `user_id` alone. ALL granules are candidates. (Lesson: sorting key order matters; this is a full scan of the `user_id` column.)

**Step 3 — Data skipping index:** If a bloom filter index on `user_id` exists, ClickHouse checks which granules' bloom filters contain `12345`. Granules that don't are skipped.

**Step 4 — Column read:** Read only the `user_id` column (columnar benefit — `date`, `value`, etc. not touched).

**Step 5 — SIMD filter:** Apply `user_id = 12345` on read granules, count matching rows.

**The teaching point:** This query is O(N) in the number of rows (no index for `user_id` as non-leading key). If this is a frequent query pattern, you'd either: (a) add a bloom filter skip index on `user_id`, (b) add `user_id` as the first element of the sorting key (changes data organization for all queries), or (c) use a separate table ordered by `user_id`.

**Q: What is a "merge storm" and how do you prevent it?**

A merge storm occurs when too many small parts accumulate faster than background merges can consolidate them. Symptoms: query latency degrades as the query layer must read and merge hundreds of tiny parts; eventually the "Too many parts" exception fires.

Prevention:
1. **Batch inserts:** minimum 1,000 rows, ideally 100K–1M rows per INSERT.
2. Use an ingestion buffer (Kafka → ClickHouse Kafka table engine or a batch-writing service).
3. Tune `max_insert_block_size` and `min_insert_block_size_rows`.
4. Monitor `system.parts` — alert when `active_parts` per partition exceeds 100.
