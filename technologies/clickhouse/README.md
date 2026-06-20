# ClickHouse — Complete Deep Dive

**Category:** OLAP Columnar Database  
**Version covered:** ClickHouse 23.x / 24.x  
**Primary use:** Real-time analytics over hundreds of billions of rows with sub-second query latency

---

## What ClickHouse Is

ClickHouse is a **column-oriented OLAP database** built for analytical queries over large datasets at interactive speed. It was built by Yandex in 2016 for Yandex.Metrica (a web analytics product processing 20+ billion events/day) and open-sourced the same year.

**The key claim:** Single-node ClickHouse can scan and aggregate **1–10 billion rows per second** on commodity hardware. This is not marketing — it is a direct consequence of:
1. Column-oriented storage (only read columns you query)
2. Vectorized SIMD execution (process 512 bits / cycle with AVX-512)
3. Aggressive compression (columnar data compresses 5–10× better than rows)
4. Asynchronous merge architecture (writes are cheap; background merges absorb cost)

---

## Decision Drivers — When to Choose ClickHouse

### Choose ClickHouse When:

| Signal | Why ClickHouse fits |
|--------|-------------------|
| Analytical queries over 100M–100B+ rows | Column scan + SIMD = 1–10 GB/s effective throughput |
| High write throughput (100K–10M rows/sec) | Append-only parts, background merge |
| Real-time "time to queryable" < 1–2 seconds | Parts visible immediately after insert |
| Queries read few columns from wide tables | Columnar skips unneeded columns entirely |
| Time-series aggregation with rollups | `AggregatingMergeTree` + materialized views |
| Ad-hoc SQL analytics | Full SQL + window functions + subqueries |
| Cost-sensitive analytics at scale | Self-hosted, no per-query billing |

### Do NOT Choose ClickHouse When:

| Anti-pattern | Why |
|-------------|-----|
| Point lookups by primary key | No B-tree; primary key is a sparse index. Use Postgres/MySQL. |
| Frequent UPDATEs / DELETEs | Mutations are expensive rewrites. Use OLTP databases. |
| ACID transactions | Not supported. Use Postgres. |
| Small datasets (< 10M rows) | Overhead not justified. Postgres is faster here. |
| Many tiny writes (< 100 rows/batch) | Too many small parts → merge storm. Must batch writes. |
| JOIN-heavy workloads with many tables | ClickHouse optimizes for star schema + flat tables, not normalized OLTP. |

---

## Architecture Overview

```
                    ┌─────────────────────────────────────────┐
                    │            ClickHouse Cluster            │
                    │                                         │
  Clients ──────►  │  ┌──────────┐    ┌──────────┐           │
  (SQL/HTTP)       │  │  Shard 1  │    │  Shard 2  │  ...     │
                    │  │          │    │          │           │
                    │  │ Replica1 │    │ Replica1 │           │
                    │  │ Replica2 │    │ Replica2 │           │
                    │  └────┬─────┘    └────┬─────┘           │
                    │       │               │                 │
                    │       └───────┬───────┘                 │
                    │               │                         │
                    │        ┌──────▼──────┐                  │
                    │        │  ZooKeeper  │                  │
                    │        │  (or CH     │                  │
                    │        │   Keeper)   │                  │
                    │        └─────────────┘                  │
                    └─────────────────────────────────────────┘
```

**Key components:**
- **Parts:** Immutable directory of column files written on each INSERT batch. The fundamental unit of storage.
- **MergeTree:** The storage engine. Background processes merge parts; this is where deduplication, aggregation pre-computation, and ordering maintenance happen.
- **Sparse Primary Index:** Every 8,192 rows (one granule), a mark is stored. Queries use this to skip granules that can't satisfy the WHERE clause.
- **ZooKeeper / ClickHouse Keeper:** Coordinates replication metadata and DDL. ClickHouse Keeper (built-in, Raft-based) is preferred over ZooKeeper for new deployments.
- **Distributed engine:** A virtual table that fans queries out to shards and merges results.

---

## Quick Reference Card

| Parameter | Value | Notes |
|-----------|-------|-------|
| Default granule size | 8,192 rows | Controls sparse index granularity |
| Default part size trigger | ~150 MB | Above this, a new part is created |
| Recommended insert batch | ≥ 100K rows | Fewer batches → fewer parts → fewer merges |
| Max parts per partition warning | 300 | "Too many parts" error at ~1,000 |
| Default replication factor | 2 | Via `ReplicatedMergeTree` |
| Default compression | LZ4 | Fast decompress; ZSTD for better ratio |
| Default max threads | num CPUs | Per query, configurable |
| Typical compression ratio | 5–10× | Columnar + LZ4 |
| Scan throughput (single node) | 1–10 GB/s | Depends on CPU, NVMe, codec |
| ZooKeeper session timeout | 30s | Increase for large clusters |

---

## File Index

| File | Covers |
|------|--------|
| [01-architecture.md](01-architecture.md) | Column storage, MergeTree family, sparse index, granules, marks, replication, sharding, ClickHouse Keeper |
| [02-read-write-path.md](02-read-write-path.md) | Write path (buffer → part → merge), read path (index → mark → SIMD scan), data skipping indexes, compression codecs |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | vs Druid, BigQuery, Redshift, Snowflake, Pinot, Elasticsearch — when each wins |
| [04-tuning-guide.md](04-tuning-guide.md) | MergeTree settings, insert batching, compression, ZooKeeper tuning, query optimization, anti-patterns |
| [05-production-and-research.md](05-production-and-research.md) | Yandex.Metrica paper, Cloudflare, ByteDance, Uber, Discord, FAANG interview framing |
