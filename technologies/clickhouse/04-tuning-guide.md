# 04 — Tuning Guide

---

## 1. The Single Most Important Rule: Batch Your Inserts

**Before anything else:** ClickHouse performance lives or dies on insert batch size.

| Batch size | Parts created/sec | Merge overhead | Risk |
|-----------|-------------------|----------------|------|
| 1 row | 1,000/sec | Extreme | "Too many parts" error in seconds |
| 100 rows | 10/sec | High | Parts accumulate faster than merges |
| 1,000 rows | 1/sec | Moderate | Acceptable for low-frequency data |
| 100,000 rows | 0.01/sec | Low | Good production default |
| 1,000,000 rows | 0.001/sec | Minimal | Ideal for bulk loading |

**Why:** Each INSERT creates at least one part. ClickHouse background merges process ~5–10 parts/sec per merge thread. If you insert faster than merges can consolidate, parts accumulate. At ~1,000 active parts per partition, ClickHouse throws `DB::Exception: Too many parts (1002)`.

**Implementation pattern for high-frequency writes:**

```sql
-- Option 1: Buffer table (built-in, but has limitations)
CREATE TABLE events_buffer AS events
ENGINE = Buffer(
    default,           -- database
    events,            -- target table
    16,                -- number of buffer layers
    10,                -- min seconds before flush
    100,               -- max seconds before flush
    10000,             -- min rows before flush
    1000000,           -- max rows before flush
    10000000,          -- min bytes before flush
    100000000          -- max bytes before flush
);

-- Insert into buffer — flushes to events when thresholds are met
INSERT INTO events_buffer VALUES (...);

-- Option 2: Application-side batching (preferred)
-- Collect events in application memory for 1–5 seconds or until 100K rows
-- Insert as one batch via HTTP interface
```

**Option 2 is preferred for production:** The Buffer engine can lose data on crash and has limited monitoring. Application-side batching via a queue (Kafka → batch consumer → ClickHouse INSERT) is more reliable.

---

## 2. Key MergeTree Settings

```xml
<!-- config.xml or table DDL -->
<merge_tree>
    <!-- Max parts per partition before "too many parts" error -->
    <!-- Default: 1000. Increase only if you understand the risk -->
    <max_parts_in_total>3000</max_parts_in_total>

    <!-- Background merge threads (default: num CPUs / 2) -->
    <background_pool_size>16</background_pool_size>

    <!-- Max size of a single part after which it won't be merged further -->
    <!-- Default: 150GB. Increase for large tables to reduce merge frequency -->
    <max_bytes_to_merge_at_max_space_in_pool>161061273600</max_bytes_to_merge_at_max_space_in_pool>
</merge_tree>
```

**Per-table tuning in DDL:**

```sql
CREATE TABLE events (
    ...
) ENGINE = MergeTree()
ORDER BY (date, user_id)
PARTITION BY toYYYYMM(date)
SETTINGS
    -- How many rows between primary index entries (default: 8192)
    -- Lower = more precise granule skipping, larger primary.idx
    -- Higher = smaller primary.idx, less precise
    index_granularity = 8192,

    -- Compress primary index with LZ4 (saves RAM, slight CPU cost on lookup)
    index_granularity_bytes = 10485760,  -- 10MB target granule size (adaptive granularity)

    -- Merge parts in background when count > this per partition
    parts_to_throw_insert = 300,

    -- Minimum age of a part before it can be merged
    min_age_to_force_merge_seconds = 3600,

    -- TTL cleanup frequency
    merge_with_ttl_timeout = 86400;
```

---

## 3. Table Design Checklist

### Sorting Key (ORDER BY)

```sql
-- Rule: most frequently filtered column first, then next most frequent
-- Bad: high-cardinality column first when queries also filter on low-cardinality
ORDER BY (user_id, event_type)
-- Problem: query "WHERE event_type = 'click'" can't skip user_id blocks

-- Good: filter-frequency ordered
ORDER BY (date, event_type, user_id)
-- Works for: WHERE date = ..., WHERE date=... AND event_type=..., WHERE date=... AND event_type=... AND user_id=...
-- Doesn't help: WHERE user_id = ... alone (no prefix match)
```

### Partition Key (PARTITION BY)

```sql
-- For time-series data:
PARTITION BY toYYYYMM(date)          -- ~30 days per partition, good default

-- For very high volume (>100M rows/day):
PARTITION BY toDate(date)            -- 1 day per partition

-- Never partition by high-cardinality columns:
-- PARTITION BY user_id              -- creates millions of tiny partitions
-- PARTITION BY cityHash64(user_id) % 100  -- OK if you have exactly 100 shards
```

### Column Types

```sql
-- Use smallest type that fits the data
user_id    UInt32    -- not UInt64 if values < 4 billion (saves 50% storage)
clicks     UInt16    -- not Int32 if values < 65535
status     Enum8('active'=1, 'inactive'=2, 'deleted'=3)  -- 1 byte, not String

-- Use LowCardinality for string columns with < 10K distinct values
country    LowCardinality(String)    -- not String
platform   LowCardinality(String)

-- Nullable adds 1 bit per row + null bitmap overhead — avoid unless semantically required
value      Float64   -- not Nullable(Float64) if 0 is a valid substitute for null

-- Use Decimal for currency/financial data — never Float for money
amount     Decimal64(2)  -- not Float64 (precision loss)
```

---

## 4. Query Optimization

### Always Include Partition Key in WHERE

```sql
-- BAD: full scan across all partitions
SELECT count(*) FROM events WHERE user_id = 12345;

-- GOOD: partition pruning limits scan to one month
SELECT count(*) FROM events WHERE date >= '2024-01-01' AND user_id = 12345;
```

### Prefer Sorting Key Prefix in WHERE

```sql
-- Table: ORDER BY (date, event_type, user_id)

-- FAST: uses primary index (full prefix match)
SELECT * FROM events WHERE date = '2024-01-01' AND event_type = 'click';

-- MODERATE: uses primary index for date filter, scans event_type within
SELECT * FROM events WHERE date = '2024-01-01';

-- SLOW: no primary index help (user_id is not a prefix)
SELECT * FROM events WHERE user_id = 12345;
-- Add a bloom_filter skip index on user_id to improve this
```

### Use `FINAL` Sparingly (ReplacingMergeTree)

```sql
-- FINAL forces immediate deduplication at query time — very expensive
SELECT * FROM events FINAL WHERE date = '2024-01-01';
-- Every query reads all parts and deduplicates = can be 10× slower

-- Better: rely on background merges for eventual deduplication
-- Or: query with dedup handled by GROUP BY + max(version):
SELECT user_id, argMax(data, version) AS data
FROM events
WHERE date = '2024-01-01'
GROUP BY user_id;
```

### Pre-Aggregation with Materialized Views

```sql
-- Instead of:
SELECT toStartOfHour(event_time), sum(clicks)
FROM ad_clicks
WHERE ad_id = 12345 AND event_time >= now() - INTERVAL 24 HOUR
GROUP BY 1;
-- This scans raw events (potentially billions of rows)

-- Use a materialized view:
SELECT hour, sumMerge(clicks_agg) AS total_clicks
FROM ad_clicks_hourly
WHERE ad_id = 12345 AND hour >= now() - INTERVAL 24 HOUR
GROUP BY hour ORDER BY hour;
-- Scans pre-aggregated hourly buckets (24 rows for 24 hours) — microseconds
```

### Avoid `SELECT *` on Wide Tables

```sql
-- BAD: reads all columns (columnar benefit lost)
SELECT * FROM events WHERE date = '2024-01-01';

-- GOOD: read only needed columns
SELECT user_id, event_type, value FROM events WHERE date = '2024-01-01';
```

### Join Order and Strategy

```sql
-- ClickHouse hash joins: smaller table goes on the RIGHT
-- The right table is fully loaded into memory; the left is streamed

-- GOOD: events (large) LEFT JOIN ads (small)
SELECT e.user_id, a.campaign_name
FROM events e LEFT JOIN ads a ON e.ad_id = a.ad_id
WHERE e.date = '2024-01-01';

-- BAD: ads (small) LEFT JOIN events (large)
-- This tries to load events into memory hash table — OOM risk
```

---

## 5. ClickHouse Keeper / ZooKeeper Tuning

```xml
<!-- ZooKeeper or ClickHouse Keeper config -->
<zookeeper>
    <!-- Session timeout — increase for large clusters with many tables -->
    <session_timeout_ms>30000</session_timeout_ms>

    <!-- Operation timeout — per-request timeout -->
    <operation_timeout_ms>10000</operation_timeout_ms>
</zookeeper>

<!-- Reduce ZooKeeper writes for high-insert-rate tables -->
<!-- By default, every part creation writes to ZooKeeper -->
<!-- With Async replication, writes are batched -->
<merge_tree>
    <replicated_deduplication_window>100</replicated_deduplication_window>
    <replicated_deduplication_window_seconds>604800</replicated_deduplication_seconds>
</merge_tree>
```

**ClickHouse Keeper sizing:**
- 3 nodes for HA (Raft requires 2f+1 nodes for f failures)
- 8–16 GB RAM per Keeper node for large clusters (1000+ tables)
- Fast NVMe SSD — Keeper does sequential log writes, latency-sensitive
- Dedicated nodes (don't co-locate Keeper with heavy ClickHouse nodes in large clusters)

---

## 6. Memory Tuning

```xml
<clickhouse>
    <!-- Max memory per query (default: 10GB) -->
    <max_memory_usage>10737418240</max_memory_usage>

    <!-- Max memory for all queries total (default: 90% of RAM) -->
    <max_memory_usage_for_all_queries>85899345920</max_memory_usage_for_all_queries>

    <!-- Mark cache: stores decompressed mark files in RAM -->
    <!-- Should fit frequently accessed mark files -->
    <mark_cache_size>5368709120</mark_cache_size>  <!-- 5GB -->

    <!-- Uncompressed cache: stores decompressed column blocks -->
    <!-- Only useful when same data is read repeatedly (dashboards) -->
    <uncompressed_cache_size>8589934592</uncompressed_cache_size>  <!-- 8GB, often disabled -->
</clickhouse>
```

**Memory sizing rules:**
- Allocate 60–70% of node RAM to ClickHouse
- Mark cache: 5–20GB on nodes serving interactive dashboards
- Uncompressed cache: disable for ad-hoc analytics (cache thrashing); enable for fixed dashboards
- Leave 20–30% for OS page cache — OS caching of `.bin` files is effective

---

## 7. Compression Tuning

```sql
-- Profile current compression:
SELECT
    table,
    column,
    compression_codec,
    data_compressed_bytes / data_uncompressed_bytes AS ratio
FROM system.columns
WHERE table = 'events'
ORDER BY data_compressed_bytes DESC;

-- Check if DoubleDelta would improve timestamp columns:
SELECT
    sum(data_uncompressed_bytes) AS uncompressed,
    sum(data_compressed_bytes) AS compressed,
    compressed / uncompressed AS ratio
FROM system.columns
WHERE table = 'events' AND name = 'event_time';
```

**Recommended codec changes:**

```sql
-- Monotonic timestamp: DoubleDelta is much better than default LZ4
ALTER TABLE events MODIFY COLUMN event_time DateTime CODEC(DoubleDelta, LZ4);

-- After modifying, force recompression via:
OPTIMIZE TABLE events FINAL;  -- triggers full rewrite (expensive, run off-peak)
```

---

## 8. Monitoring Key Metrics

```sql
-- Active parts per partition (alert if > 100 per partition)
SELECT
    table,
    partition,
    count() AS parts
FROM system.parts
WHERE active AND database = 'default'
GROUP BY table, partition
ORDER BY parts DESC
LIMIT 20;

-- Merge queue depth (alert if > 50)
SELECT count() FROM system.merges;

-- Replication lag (alert if > 60 seconds)
SELECT
    table,
    replica_name,
    absolute_delay
FROM system.replicas
WHERE absolute_delay > 0
ORDER BY absolute_delay DESC;

-- Slow queries (> 1 second)
SELECT
    query_start_time,
    query_duration_ms,
    read_rows,
    read_bytes,
    query
FROM system.query_log
WHERE query_duration_ms > 1000
  AND type = 'QueryFinish'
  AND event_date = today()
ORDER BY query_duration_ms DESC
LIMIT 20;

-- Mutation progress (mutations = ALTER TABLE UPDATE/DELETE)
SELECT
    table,
    mutation_id,
    parts_to_do,
    is_done,
    latest_fail_reason
FROM system.mutations
WHERE NOT is_done;
```

---

## 9. Common Anti-Patterns

| Anti-pattern | Symptom | Fix |
|-------------|---------|-----|
| Inserting rows one at a time | "Too many parts" error; high merge overhead | Batch: minimum 1K rows, ideally 100K |
| `PARTITION BY` on high-cardinality column | Millions of tiny partitions; slow metadata operations | Use `toYYYYMM(date)` or similar low-cardinality partition |
| Using `FINAL` in dashboards | 10–50× slower queries | Rely on eventual dedup; use `argMax` pattern instead |
| `Nullable` columns everywhere | 1 extra byte per row + null bitmap overhead | Use only when null has distinct semantic meaning |
| `Float32/Float64` for money | Rounding errors in financial reporting | `Decimal64(2)` or `Decimal128(6)` |
| `SELECT *` in high-frequency queries | Reads all columns; negates columnar benefit | Specify exact columns |
| Mutations for regular updates | Full part rewrite; blocks merges | Use `ReplacingMergeTree` for upserts |
| Querying without partition key in WHERE | Full partition scan | Always include partition key filter |
| ZooKeeper co-located on ClickHouse nodes | ZK sessions disrupted by CH memory pressure | Dedicated Keeper nodes for >10-node clusters |
| Adaptive granularity disabled on large-row tables | Oversized granules; poor skip efficiency | Use `index_granularity_bytes = 10485760` (default in 23.x+) |

---

## FAANG Interview Callout

**Q: You notice ClickHouse query latency spiked from P99 = 200ms to P99 = 5s over 24 hours. Walk through your investigation.**

**Step 1 — Check active parts per partition:**
```sql
SELECT partition, count() as parts FROM system.parts WHERE active GROUP BY partition ORDER BY parts DESC LIMIT 10;
```
If any partition has > 100 parts, you have a merge storm caused by too-frequent small inserts.

**Step 2 — Check merge queue:**
```sql
SELECT count(), sum(rows_read), sum(bytes_read_uncompressed) FROM system.merges;
```
If >50 merges queued, background threads are overwhelmed.

**Step 3 — Check replication lag:**
```sql
SELECT table, absolute_delay FROM system.replicas WHERE absolute_delay > 10;
```
High lag = followers are behind; reads may hit stale or overloaded replicas.

**Step 4 — Check slow queries:**
```sql
SELECT query_duration_ms, read_rows, read_bytes, query FROM system.query_log WHERE query_duration_ms > 1000 AND type = 'QueryFinish' AND event_date = today() ORDER BY query_duration_ms DESC LIMIT 10;
```
If queries scan billions of rows for what should be small results → missing partition key in WHERE or poor sorting key alignment.

**Step 5 — Check mutations:**
```sql
SELECT table, mutation_id, parts_to_do FROM system.mutations WHERE NOT is_done;
```
An in-progress `ALTER TABLE UPDATE` rewrites parts and competes with merges — can cause significant slowdown.

**Typical root cause for "latency grew over 24 hours":** An upstream service started sending more frequent smaller inserts (e.g., a deployment that changed batch size from 100K to 100 rows). Immediately causes merge storms. Fix: restore batching; optionally increase `background_pool_size` temporarily to help merges catch up.
