# 03 — Trade-offs and Alternatives

---

## 1. ClickHouse CAP / PACELC Position

ClickHouse is a **PA/EL system** in the PACELC model:

- **Partition tolerance:** Yes — the cluster continues operating when a replica is unreachable.
- **Availability over Consistency (during partition):** A write succeeds as soon as `insert_quorum` replicas acknowledge it (default: 1 = just the receiving replica). Reads can be served from any replica even if it's slightly behind.
- **Latency over Consistency (normal operation):** Replication is asynchronous. A reader querying Replica 2 may see data 100–500ms after it was written to Replica 1.

**Configuring stronger consistency:**

```sql
-- Wait for 2 replicas to confirm before INSERT returns
SET insert_quorum = 2;
SET insert_quorum_parallel = 0;  -- wait sequentially

-- Read from the most up-to-date replica
SET select_sequential_consistency = 1;  -- expensive: checks ZooKeeper before each read
```

**The trade-off:** `select_sequential_consistency = 1` adds ZooKeeper RTT to every read (~1–5ms). Use only when stale reads are unacceptable (e.g., read-your-own-writes requirement).

---

## 2. ClickHouse vs. Apache Druid

| Dimension | ClickHouse | Apache Druid |
|-----------|-----------|-------------|
| **Architecture** | Shared-nothing, column store + MergeTree | Tiered (real-time nodes, historical nodes, broker, coordinator) |
| **Data model** | Flexible SQL tables, any schema | Optimized for time-series + dimensions + metrics (fixed schema role) |
| **Ingestion** | Pull (Kafka engine) or push (INSERT) | Pull only via Kafka/HTTP |
| **Latency to queryable** | ~1–2 seconds (part visible immediately) | ~30–60 seconds (segment handoff) |
| **Query language** | Full SQL (window functions, subqueries, JOINs) | Druid SQL (limited JOINs, no window functions historically) |
| **Approximate aggregation** | `uniqCombined`, `quantileTDigest` | Built-in HLL, theta sketch (first-class) |
| **Data mutability** | Mutations are expensive (rewrite parts) | Segment reingestion for updates |
| **Operational complexity** | Moderate (ZooKeeper/Keeper + CH nodes) | High (6 service types + Deep Storage + ZooKeeper) |
| **Storage cost** | Column files on local NVMe or S3 | Historical nodes on local + deep storage (S3/HDFS) |
| **Horizontal scaling** | Manual sharding | Automatic segment distribution |
| **FAANG usage** | Cloudflare, ByteDance, Uber, eBay | Yahoo, Netflix, Lyft, Airbnb |

**Choose Druid over ClickHouse when:**
- You need automatic time-based segment management (TTL, retention).
- You need first-class approximate queries (HLL/theta sketches) with formal error bounds.
- Your query patterns are exclusively time-series + dimension filters (no complex SQL).
- You need automatic data tiering (real-time → historical → deep storage).

**Choose ClickHouse over Druid when:**
- You need full SQL (subqueries, complex JOINs, window functions).
- You want lower operational complexity (Druid has 6 service types).
- You need data visible within 1–2 seconds (vs Druid's ~30–60s segment handoff).
- Your team is more comfortable with SQL than a JSON-based query API.

---

## 3. ClickHouse vs. Google BigQuery

| Dimension | ClickHouse | BigQuery |
|-----------|-----------|---------|
| **Deployment** | Self-hosted or ClickHouse Cloud | Fully managed (Google) |
| **Pricing model** | Infrastructure cost (fixed) | On-demand ($5/TB scanned) or flat-rate |
| **Latency** | Sub-second for well-tuned queries | 1–5 seconds (job scheduling overhead) |
| **Scale limit** | Petabyte-scale with cluster growth | Petabyte-scale managed |
| **SQL completeness** | Full SQL + ClickHouse extensions | Full SQL + scripting |
| **Streaming ingestion** | Via Kafka engine or INSERT | BigQuery Storage Write API (~seconds latency) |
| **ML integration** | External (Python/Spark) | BigQuery ML (native SQL-based ML) |
| **Materialized views** | Yes, with AggregatingMergeTree | Yes (automatic refresh) |
| **Federated queries** | Limited | Yes (query GCS, Drive, etc.) |
| **Data sharing** | Manual | BigQuery Datasets sharing |
| **Operational burden** | Moderate | Zero |

**Cost crossover:** At ~50–200TB/month scanned, BigQuery's per-TB cost ($5/TB) becomes more expensive than self-hosted ClickHouse. Below that, BigQuery's zero-ops cost justifies the price premium.

**Choose BigQuery when:**
- Small team, no infra expertise — zero-ops is worth the premium.
- Already in GCP ecosystem.
- Need ML integration (BQML).
- Data < 50TB/month scanned.

**Choose ClickHouse when:**
- >100TB/month scanned — cost savings justify operations.
- Need sub-second latency (BigQuery's job scheduling adds 1–5s floor).
- Need real-time ingestion (<5s latency to queryable).
- On-premises or multi-cloud requirement.

---

## 4. ClickHouse vs. Amazon Redshift

| Dimension | ClickHouse | Redshift |
|-----------|-----------|---------|
| **Architecture** | Columnar, MergeTree, shared-nothing | Columnar, MPP, shared-nothing |
| **Storage** | Local NVMe or S3 (Tiered Storage) | Redshift Managed Storage (S3-backed) |
| **Compression** | LZ4/ZSTD + Delta/Gorilla | Encodings (AZ64, Zstandard, LZO) |
| **Primary index** | Sparse (granule-based) | Zone maps (min/max per block) |
| **Write latency** | Seconds (INSERT batches) | Minutes (COPY from S3) |
| **Real-time ingestion** | Yes (Kafka engine, INSERT) | No (bulk load oriented) |
| **Concurrency** | High (no WLM queuing by default) | WLM queuing limits concurrent queries |
| **JOIN performance** | Good (hash joins, distributed) | Very good (co-located joins with distkey) |
| **Pricing** | Infrastructure | RA3 nodes by the hour |
| **AWS integration** | External | Native (S3, Glue, Kinesis) |

**Choose Redshift when:**
- Deep AWS integration is a requirement.
- Workload is primarily batch ETL → query (not real-time).
- Large complex JOINs between multiple large tables (Redshift's distribution keys optimize these).
- Team already has Redshift expertise.

**Choose ClickHouse when:**
- Need real-time or near-real-time ingestion + queries.
- Cost optimization matters (Redshift RA3 nodes are expensive).
- Sub-second latency required.
- On-premises or non-AWS cloud.

---

## 5. ClickHouse vs. Snowflake

| Dimension | ClickHouse | Snowflake |
|-----------|-----------|---------|
| **Architecture** | Shared-nothing (storage + compute co-located) | Shared storage (S3) + separate compute (virtual warehouses) |
| **Scaling** | Scale by adding nodes | Scale compute independently of storage |
| **Multi-tenancy** | Manual | Multiple virtual warehouses on same data |
| **Query isolation** | None (queries share resources) | Virtual warehouses provide isolation |
| **Write throughput** | Very high (INSERT batches) | Moderate (micro-partition compaction) |
| **Data freshness** | Sub-second | Seconds to minutes |
| **Semi-structured data** | JSON path extraction | VARIANT type (native JSON/Parquet) |
| **Concurrency scaling** | High | Excellent (add virtual warehouses) |
| **Zero-copy cloning** | No | Yes (instant clone of database/table) |
| **Time travel** | Mutations (no undo log) | 90-day time travel |
| **Operational burden** | Moderate | Zero |

**The fundamental Snowflake advantage: storage-compute separation.** Multiple teams can query the same data simultaneously with isolated virtual warehouses (no resource contention). ClickHouse does not have this — all queries compete for the same node resources.

**The fundamental ClickHouse advantage: raw query speed.** ClickHouse's SIMD vectorized execution on co-located NVMe is significantly faster than Snowflake's S3-backed remote storage for the same query. For sub-second SLA on large scans, ClickHouse wins.

---

## 6. ClickHouse vs. Apache Pinot

| Dimension | ClickHouse | Apache Pinot |
|-----------|-----------|-------------|
| **Query latency** | Sub-second (SIMD columnar) | Sub-second (inverted index optimized) |
| **Index types** | Sparse primary + data skipping | Inverted, sorted, range, bloom, star-tree |
| **Star-tree index** | No | Yes — pre-aggregated multi-dimensional rollups |
| **Real-time ingestion** | Via Kafka engine | Native real-time tables |
| **Upserts** | ReplacingMergeTree (eventual) | Primary key upserts (near-real-time) |
| **SQL** | Full SQL | SQL (with some limitations) |
| **Multi-stage query** | Distributed query engine | Multi-stage query engine (v2) |
| **FAANG usage** | Cloudflare, ByteDance | LinkedIn (creator), Uber, Stripe |

**Pinot's star-tree index** is a key differentiator for dashboards with many dimension combinations. It pre-aggregates all combinations of dimensions at write time, enabling `GROUP BY country, device, version` to return in milliseconds regardless of data volume. ClickHouse's `AggregatingMergeTree` requires explicit materialized views per rollup combination.

**Choose Pinot when:**
- Dashboard queries with many dimension GROUP BY combinations.
- Need near-real-time upserts (Pinot handles updates better than ClickHouse's eventual deduplication).
- LinkedIn-style user-facing real-time analytics.

**Choose ClickHouse when:**
- Ad-hoc SQL flexibility matters.
- Queries don't follow a fixed dimension pattern.
- Lower operational complexity (Pinot has controller, broker, server, minion roles).

---

## 7. ClickHouse vs. Elasticsearch

| Dimension | ClickHouse | Elasticsearch |
|-----------|-----------|--------------|
| **Primary use** | Analytics (aggregations, GROUP BY) | Full-text search + analytics |
| **Storage** | Columnar, compressed | Row-oriented inverted index (Lucene) |
| **Aggregation speed** | 10–100× faster than ES for numeric aggregations | Slow for high-cardinality aggregations |
| **Full-text search** | Limited (tokenbf index, LIKE) | Excellent (BM25, field boosting, relevance) |
| **Schema flexibility** | Strict schema (ALTER TABLE) | Dynamic mapping |
| **Storage efficiency** | 5–10× better (columnar compression) | 2–3× compression |
| **Write cost** | Low (append parts) | High (inverted index maintenance) |
| **JOINs** | Yes | No |

**The guidance:** If you have a search AND analytics use case, run both. Elasticsearch/OpenSearch for document search; ClickHouse for the aggregation/dashboard layer. Ingest events to both via Kafka.

---

## 8. Decision Flowchart

```
Start: Need analytics storage
        │
        ▼
Is it full-text search? ──YES──► Elasticsearch / OpenSearch
        │NO
        ▼
Is it OLTP (many updates, transactions)? ──YES──► Postgres / MySQL
        │NO
        ▼
Need zero-ops fully managed? ──YES──► Need sub-second latency?
        │NO                            │YES → ClickHouse Cloud
        │                              │NO  → BigQuery or Snowflake
        ▼
Is it <10M rows OR mostly point lookups? ──YES──► Postgres with columnar extension
        │NO
        ▼
Need multi-dimensional star-tree rollups for dashboards? ──YES──► Pinot
        │NO
        ▼
Primary use: real-time event analytics, ad-click aggregation,
log analytics, time-series metrics? ──YES──► ClickHouse
        │NO
        ▼
Large complex JOINs + batch workloads + AWS? ──YES──► Redshift
        │NO
        ▼
Unstructured/semi-structured data + multiple isolated teams? ──YES──► Snowflake
```

---

## FAANG Interview Callout

**Q: You are designing an ad click aggregation system for 10M active ads, 10K clicks/second peak. ClickHouse vs Druid vs Pinot — which do you choose and why?**

**Recommended answer: ClickHouse**

1. **Latency to queryable:** 1–2 seconds (ClickHouse INSERT → part visible) vs 30–60 seconds (Druid segment handoff). For an ad serving system where advertisers want real-time spend visibility, 30 seconds is too long.

2. **SQL flexibility:** Advertisers want ad-hoc queries — top 10 ads by CTR this hour, spending anomalies, cohort breakdowns. Full SQL in ClickHouse handles this. Druid's query API is more restrictive.

3. **`AggregatingMergeTree` + materialized views:** Pre-aggregate minute/hourly/daily rollups automatically. Query the rollup table for dashboards (sub-second), query raw data for ad-hoc analysis (seconds).

4. **Operational simplicity:** Druid requires 6 service types. Pinot requires 4. ClickHouse requires 1 binary + ZooKeeper/Keeper. Simpler to operate at the scale of 10M ads.

**Counterarguments to address:**
- Pinot's upsert capability is better if you need to correct click counts after fraud detection. ClickHouse's `ReplacingMergeTree` is eventual — a read might return stale deduplicated data until the merge happens. Mitigation: use `FINAL` modifier on reads (forces immediate deduplication, slower) or accept ~seconds of staleness.
- Druid's automatic segment tiering is better if you have 3-year data retention requirements and want old data automatically moved to cheaper storage. Mitigate in ClickHouse with Tiered Storage to S3.
