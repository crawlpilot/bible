# 05 — Production Usage and Research

---

## 1. Founding Research Context

ClickHouse does not have a single founding paper in the style of Dynamo or Bigtable. It emerged from engineering work at Yandex. The closest authoritative sources:

**"ClickHouse — The Lightning-Fast OLAP DBMS" (VLDB 2022)**  
Alexey Milovidov (creator), et al.  
*Proceedings of the VLDB Endowment, Vol. 15*

**Key findings from the paper:**
- ClickHouse processes 1.7 billion rows/second on a single server with SIMD AVX-512 for INT32 aggregation.
- The MergeTree storage engine with columnar layout achieves 5–20× compression ratios for typical analytics data.
- Vectorized execution (block-at-a-time processing) is 2–10× faster than volcano model (row-at-a-time) for analytics workloads.
- Adaptive granularity (variable granule size to maintain ~10MB compressed blocks) improves skip efficiency over fixed 8192-row granules for variable-length data.

**Original Yandex.Metrica context (2016):**
- 12+ billion events per day at Yandex.Metrica when ClickHouse was deployed.
- Previous solution: MySQL + in-memory pre-aggregation → could not handle the query patterns at scale.
- ClickHouse replaced it: raw data + columnar aggregation → no pre-aggregation required for most queries.

---

## 2. Cloudflare — 36+ Trillion Rows

**Use case:** Cloudflare uses ClickHouse for their HTTP traffic analytics — every DNS query, HTTP request, and firewall event passing through Cloudflare's network is logged and made queryable.

**Scale (as of 2023):**
- 36+ trillion rows stored
- ~6 million rows/second write throughput
- ~1,000 queries/second from customer dashboards
- 1 PB+ of data

**Architecture decisions:**
- All events stream via Kafka → dedicated ingestor service → ClickHouse batch INSERT (100K rows/batch)
- Dedicated ClickHouse clusters per product line (DNS, HTTP, firewall) — isolation prevents noisy-neighbor
- `ReplicatedMergeTree` with 2 replicas per shard for HA
- Materialized views for pre-aggregated customer-facing dashboards (P99 <200ms)
- Cold data (>90 days) moved to S3 via ClickHouse Tiered Storage — 70% cost reduction

**Key lesson from Cloudflare:** At this scale, the ingestor layer (Kafka → batch buffer → ClickHouse) is as critical as the database itself. They built a custom Rust-based ingestor that handles backpressure, deduplication, and exactly-once semantics before hitting ClickHouse.

---

## 3. ByteDance — Internal OLAP Platform

**Use case:** ByteDance (TikTok parent) runs one of the largest known ClickHouse deployments for internal business analytics — ad performance, content recommendation evaluation, A/B test analysis.

**Scale:**
- Thousands of ClickHouse nodes
- Petabyte-scale storage
- Millions of queries/day from internal analysts

**Architecture decisions:**
- Custom scheduler on top of ClickHouse for resource governance (prevent one analyst from saturating nodes)
- Tiered storage: NVMe SSD for hot data (last 30 days), HDDs for warm, S3 for cold
- `AggregatingMergeTree` + materialized views for all business KPI dashboards
- A/B test analysis: ClickHouse's `quantilesTDigest` for metric distribution analysis without materializing full sample data

**Key lesson:** ByteDance invested heavily in multi-tenant query governance. Without it, a single expensive analytical query can saturate a shared ClickHouse node and impact all other users. Production ClickHouse needs a query queue and per-user resource limits (`SET max_memory_usage`, user-level quotas).

---

## 4. Uber — Real-Time Trip Analytics

**Use case:** Uber uses ClickHouse for real-time trip analytics — surge pricing models, driver positioning dashboards, city-level aggregate metrics.

**Architecture:**
```
Trip events → Kafka → Flink (enrichment + sessionization) → ClickHouse
                                                           → Druid (subset)
```

**Why both ClickHouse and Druid:** Uber uses Druid for their high-volume, simple dimension-filter-aggregate dashboard queries (where Druid's star-tree index excels) and ClickHouse for complex ad-hoc SQL that requires JOINs and subqueries. Two tools for different access patterns on overlapping data.

**Key lesson:** A polyglot storage approach is valid at FAANG scale. Don't force one tool to do everything; accept operational complexity in exchange for optimal performance per use case.

---

## 5. Discord — Messages and Events

**Context:** Discord discussed ClickHouse as part of their analytics infrastructure for message metrics and server activity analytics.

**Use case:** Aggregating message counts, active user counts, and engagement metrics per server (Discord has millions of servers).

**Key architectural choice:** Discord uses `ReplacingMergeTree` for metrics where events can arrive out of order. Since ClickHouse's deduplication is eventual (only fully consistent after merge), Discord's dashboards use the `argMax` pattern rather than `SELECT ... FINAL`:

```sql
SELECT
    server_id,
    argMax(message_count, updated_at) AS latest_count
FROM server_metrics
WHERE date >= today() - 7
GROUP BY server_id
ORDER BY latest_count DESC
LIMIT 100;
```

---

## 6. eBay — Search Analytics

**Use case:** eBay uses ClickHouse for their search analytics platform — query volume, click-through rates, conversion funnels, A/B test evaluation for search ranking changes.

**Scale:** Billions of search events per day; analysts run 10K+ queries/day.

**Architecture decisions:**
- Separated ingestion cluster (heavy writes) from query cluster (heavy reads) using ClickHouse replication + S3 as the bridge
- Partition strategy: `toDate(event_time)` (daily) — enables instant partition drop for GDPR data deletion by day
- `LowCardinality(String)` for all dimension columns (category, country, device) — significant storage savings at their scale

**Key lesson:** For GDPR compliance, `PARTITION BY toDate(event_time)` + `ALTER TABLE DROP PARTITION 'YYYY-MM-DD'` is dramatically simpler than row-level deletion. Design your partition scheme with compliance requirements in mind from the start.

---

## 7. Operational Lessons Across Deployments

### The Batching Problem Is Universal

Every large ClickHouse deployment builds an ingestor layer. Whether it's Cloudflare's Rust service, ByteDance's custom scheduler, or a Kafka consumer, the pattern is always:

```
High-frequency events → Buffer (Kafka / application memory) → Batch INSERT to ClickHouse
```

No production deployment writes directly to ClickHouse at high frequency without buffering.

### Tiered Storage Is Standard at Scale

ClickHouse Tiered Storage (S3 integration) is not optional for petabyte-scale deployments:

```sql
-- Define storage volumes in storage_configuration
-- Hot: NVMe SSD (last 30 days)
-- Cold: S3 (older data)

CREATE TABLE events (...) ENGINE = MergeTree()
ORDER BY ...
TTL date + INTERVAL 30 DAY TO VOLUME 'cold'  -- move to S3 after 30 days
SETTINGS storage_policy = 'hot_cold';
```

Cost comparison: $1–3/GB for NVMe SSD vs $0.02–0.05/GB for S3. Tiered storage enables 95% cost reduction for the cold portion.

### ClickHouse Keeper Adoption

As of ClickHouse 23.x, most new deployments use ClickHouse Keeper instead of ZooKeeper. The operational burden reduction (no separate Java stack) is significant. The Keeper Raft protocol is more transparent and easier to debug than ZAB.

---

## 8. FAANG Interview Framing

### "Why did you choose ClickHouse over BigQuery?"

**Strong answer:** "BigQuery's on-demand pricing at our scale was $X/month (calculate: TB/month × $5/TB). ClickHouse on [3 nodes × instance cost] was $Y/month with sub-second latency that BigQuery's job scheduling overhead couldn't match. The engineering cost of operating ClickHouse was justified by the cost savings and latency improvement."

### "How does ClickHouse handle data that arrives out of order?"

**Strong answer:** "ClickHouse has no global ordered buffer — each INSERT creates a part, and parts are sorted within themselves but not globally ordered. For time-series data arriving slightly out of order, this is fine — queries with ORDER BY return correct results. For deduplication (ReplacingMergeTree), out-of-order arrivals are handled during merge — the row with the highest `version` value is kept. For exactly-once semantics, we use a three-layer idempotency: (1) client-side UUID per event, (2) Redis Bloom filter for fast dedup before insert, (3) ReplacingMergeTree for eventual storage-level dedup."

### "What would you change about ClickHouse for a FAANG-scale deployment?"

**Strong answer demonstrates knowing the limitations:**
1. **No strong consistency for reads** — `select_sequential_consistency = 1` adds ZooKeeper RTT to every read. For financial reporting requiring read-your-own-writes, you need application-level coordination or accept eventual consistency.
2. **Manual sharding is operational overhead** — unlike Snowflake or BigQuery, you choose the sharding key and live with the consequences. Skewed keys = uneven load. Consider consistent hash sharding with enough virtual buckets to allow rebalancing.
3. **Mutations are expensive** — any `ALTER TABLE UPDATE` is a blocking part rewrite. Design schemas around append-only patterns; use `ReplacingMergeTree` for upsert semantics rather than mutations.
4. **Multi-tenant resource governance is DIY** — ByteDance solved this with a custom layer. ClickHouse's built-in quotas (user-level `max_memory_usage`, query queues) are functional but not as sophisticated as BigQuery's slot-based fair scheduling.

### "Design an ad click aggregation system at Google scale using ClickHouse."

Reference: [../../HLD/designs/ad-click-aggregator.md](../../HLD/designs/ad-click-aggregator.md)

Key ClickHouse-specific points to hit:
1. `AggregatingMergeTree` with `sumState`/`uniqExactState` for pre-aggregated rollups.
2. Tiered query routing: minute rollup for last hour, hourly rollup for last 7 days, daily rollup for older.
3. Three-layer deduplication: UUID in Kafka message → Redis Bloom filter → ClickHouse `ReplacingMergeTree`.
4. `toStartOfMinute(event_time)` as the first sorting key element for rollup queries.
5. `PARTITION BY toDate(event_time)` for instant TTL and partition-level operations.

---

## FAANG Interview Callout — The Top 5 ClickHouse Questions

1. **"What is a granule and why does ClickHouse use sparse indexes instead of B-trees?"**  
   Core architecture question. Answer: granule = 8,192 rows; sparse index = one entry per granule; analytics queries scan ranges not point-lookup rows; sequential I/O + SIMD = 10–100× better scan throughput than random B-tree traversal.

2. **"Why does inserting one row at a time break ClickHouse?"**  
   Tests understanding of MergeTree write path. Answer: each INSERT = one part; parts accumulate; merges can't keep up; "too many parts" exception. Fix: batch inserts ≥ 1K rows, use Kafka or Buffer table.

3. **"What is ReplacingMergeTree and when is the deduplication NOT guaranteed to be visible?"**  
   Tests understanding of eventual consistency. Answer: dedup happens at merge time, not at insert time. Until the merge runs, duplicate rows are visible. Use `FINAL` (expensive) or `argMax` pattern for correct reads before merge.

4. **"How does ClickHouse's query execution use SIMD?"**  
   Tests depth. Answer: vectorized block-at-a-time processing; load 512 bits (8 doubles) in one AVX-512 instruction; compare all 8 values in one instruction; mask-based selection; sequential column layout = perfect cache prefetch.

5. **"Compare ClickHouse and Druid for a real-time analytics use case."**  
   Principal-level trade-off question. Answer: ClickHouse wins on SQL flexibility, lower operational complexity, faster time-to-queryable (seconds vs minutes). Druid wins on star-tree index for multi-dimensional rollups and automatic data tiering. For ad analytics: ClickHouse preferred unless you have >50 dimension combinations that need pre-aggregated response in <100ms.
