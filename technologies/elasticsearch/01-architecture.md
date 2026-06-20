# Elasticsearch — Architecture

## Origins: Lucene as the Engine

Elasticsearch is a **distributed coordination layer** on top of Apache Lucene. Every shard is a self-contained Lucene instance. Elasticsearch's job is to:

1. Route documents to the right shard
2. Scatter queries across all shards and merge results
3. Handle node failures, shard rebalancing, and replication
4. Expose a REST/JSON API hiding Lucene's Java API complexity

Understanding this decomposition is critical: when you tune Elasticsearch, you are tuning either the **Lucene layer** (heap, segment merge, refresh) or the **coordination layer** (shard count, routing, replication factor).

---

## Cluster Topology

### Node Roles

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Elasticsearch Cluster                         │
│                                                                      │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐   │
│  │  Master-eligible│   │  Master-eligible│   │  Master-eligible│   │
│  │  node (m1)      │◄─►│  node (m2)      │◄─►│  node (m3)      │   │
│  │  [cluster state]│   │  [cluster state]│   │  [cluster state]│   │
│  └────────┬────────┘   └────────┬────────┘   └────────┬────────┘   │
│           │  elected master      │                     │            │
│           ▼                      │                     │            │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐   │
│  │  Data node (d1) │   │  Data node (d2) │   │  Data node (d3) │   │
│  │  [shard 0 pri]  │   │  [shard 1 pri]  │   │  [shard 2 pri]  │   │
│  │  [shard 2 rep]  │   │  [shard 0 rep]  │   │  [shard 1 rep]  │   │
│  └─────────────────┘   └─────────────────┘   └─────────────────┘   │
│                                                                      │
│  ┌─────────────────┐   ┌─────────────────┐                         │
│  │  Coordinating   │   │  Ingest node    │                         │
│  │  node (c1)      │   │  [pipelines]    │                         │
│  │  [scatter/gather│   │  [enrich,       │                         │
│  │   + merge]      │   │   geoip, etc.]  │                         │
│  └─────────────────┘   └─────────────────┘                         │
└──────────────────────────────────────────────────────────────────────┘
```

| Node Role | Responsibility | Sizing Guidance |
|-----------|---------------|----------------|
| **Master-eligible** | Cluster state management (index creation, shard allocation decisions, node join/leave). Elected by majority. | 3 dedicated master nodes (never co-locate with data). 8–16 GB RAM, low heap (2–4 GB), fast disk for cluster state. |
| **Data** | Stores shards; handles indexing and query execution. Most nodes in a cluster are data nodes. | Size to 50–64 GB heap max; 32–64 GB RAM; high-throughput SSD. |
| **Coordinating** | Receives client requests, fans out to relevant shards, merges results. Stateless. | Useful when query merging is CPU-heavy (large aggregations). Can be a load balancer substitute. |
| **Ingest** | Runs ingest pipelines (geoip enrichment, field extraction, date parsing) before indexing. | Dedicate when pipeline processing is CPU-heavy; otherwise run on data nodes. |
| **ML** | Hosts trained models for anomaly detection, NLP inference (ELSER, dense_vector). | Dedicated GPU-equipped nodes in modern deployments. |

**Split-brain prevention**: Elasticsearch uses Raft-based cluster coordination (since 7.0, replacing Zen Discovery). Requires a quorum of master-eligible nodes: always deploy an **odd number** (3 or 5). `discovery.zen.minimum_master_nodes` is deprecated; `cluster.initial_master_nodes` replaces it.

---

## Sharding Model

### Primary and Replica Shards

```
Index "products" — 3 primary shards, 1 replica each
                    (total 6 shards across 3 data nodes)

  Data Node 1            Data Node 2            Data Node 3
  ┌───────────┐          ┌───────────┐          ┌───────────┐
  │ Shard 0 P │          │ Shard 1 P │          │ Shard 2 P │  (Primaries)
  │ Shard 2 R │          │ Shard 0 R │          │ Shard 1 R │  (Replicas)
  └───────────┘          └───────────┘          └───────────┘

  Fault tolerance: any single node can fail — all 3 primaries survive (on the remaining 2 nodes)
  Read throughput: 6 shards can serve queries in parallel
```

### Document Routing

Every document is routed to a shard deterministically:

```
shard_id = hash(document_id) % number_of_primary_shards
```

This is why **primary shard count is fixed at index creation** — changing it changes every document's target shard (requires full re-indexing). Replica count can be changed live.

**Custom routing**: `_routing` field overrides the formula. Used to co-locate related documents on the same shard (e.g., all documents for a `tenant_id` on one shard) to avoid scatter-gather for tenant-scoped queries.

### Shard Sizing Rules of Thumb

| Metric | Target | Why |
|--------|--------|-----|
| Shard size | 10–50 GB | < 10 GB: too many small shards → overhead; > 50 GB: slow recovery, large GC pressure |
| Shards per GB heap | ≤ 20 | ES holds shard metadata in heap; 1 shard ≈ a few MB heap overhead |
| Max docs per shard | ~2 billion | Lucene's `Integer.MAX_VALUE` document limit per index |
| Primary shard count for new index | `ceil(total_data_GB / 30)` | Starting heuristic; tune after profiling |

---

## The Inverted Index — Lucene Internals

This is the core data structure. For each field indexed as `text`, Lucene builds:

```
Document corpus:
  doc1: "elasticsearch is fast"
  doc2: "elasticsearch scales horizontally"
  doc3: "fast horizontal scaling"

Inverted index (term → posting list):
  "elasticsearch" → [doc1, doc2]
  "fast"          → [doc1, doc3]
  "horizontal"    → [doc2, doc3]
  "horizontally"  → [doc2]          ← before analysis/stemming
  "is"            → [doc1]
  "scale"         → [doc3]          ← after stemming "scales" → "scale"
  "scaling"       → [doc3]
  "scales"        → [doc2]

After analysis pipeline (standard analyzer: lowercase + stop-words + stemming):
  "is" → removed (stop word)
  "horizontally" + "scaling" + "scales" → "horizontal" + "scale" (stemmed)
```

Each entry in the posting list stores: **document ID + term frequency + positions** (for phrase queries) + **offsets** (for highlighting).

---

## Lucene Segments

Shards are made of **immutable Lucene segments**. Each segment is its own mini-inverted-index on disk.

```
Shard (= Lucene index)
├── Segment_1   (created from first bulk index batch, now immutable)
│   ├── _1.fnm  (field names metadata)
│   ├── _1.fdt  (stored field values — original _source JSON)
│   ├── _1.tim  (term dictionary)
│   ├── _1.doc  (posting lists: docId + freq)
│   ├── _1.pos  (term positions)
│   └── _1.dvd  (doc values — columnar data for aggregations + sorting)
├── Segment_2   (immutable)
├── Segment_3   (immutable)
└── [in-memory buffer]  → becomes new segment on refresh
```

**Why immutable?** Immutability enables:
- Lock-free concurrent reads
- OS page cache efficiency (files never change → cache stays valid)
- Simple merging (merge = read N segments, write 1 new segment)

**Deletion handling**: Deletes are recorded in a `.del` bitset file (tombstone), not by removing from the segment. Deleted docs are filtered during queries. They are physically removed only when segments merge.

---

## Segment Merging

As segments accumulate, Elasticsearch's background **merge scheduler** (based on Lucene's `TieredMergePolicy`) continuously merges small segments into larger ones.

```
State 1 (many small segments after heavy indexing):
  [seg1: 1MB] [seg2: 2MB] [seg3: 1MB] [seg4: 3MB] [seg5: 2MB] ...

After merge (TieredMergePolicy selects similar-sized groups):
  [merged_A: 4MB]   [merged_B: 5MB]   [seg4: 3MB] ...

Eventually:
  [large_seg: 50GB]   ← single segment is optimal for read performance
```

**Why merges matter for FAANG interviews**:
- Merges are I/O and CPU intensive — can cause indexing slowdowns and GC pressure
- `indices.store.throttle.max_bytes_per_sec` controls merge I/O (deprecated in 7.x; now managed by OS throttling + `index.merge.scheduler.max_thread_count`)
- Force merge (`_forcemerge?max_num_segments=1`) before making an index read-only (e.g., time-based log indices after rollover) — eliminates deleted doc overhead and maximises read performance

---

## Analysis Chain (Text Processing Pipeline)

When a text field is indexed, it passes through an **analyzer**:

```
Raw text: "Elasticsearch is FAST, isn't it?"
              │
              ▼
    ┌─────────────────┐
    │  Character Filter│  → strip HTML tags, map Unicode variants
    └────────┬────────┘
             ▼
    ┌─────────────────┐
    │    Tokenizer    │  → "Elasticsearch" "is" "FAST" "isn't" "it"
    │ (standard: split│
    │  on whitespace  │
    │  + punctuation) │
    └────────┬────────┘
             ▼
    ┌─────────────────┐
    │  Token Filters  │  → lowercase → "elasticsearch" "is" "fast" "isn't" "it"
    │  (lowercase,    │     stop-words → "elasticsearch" "fast" "isn't"
    │   stop-words,   │     stemmer → "elasticsearch" "fast" "isn't"
    │   stemmer, ...)  │
    └────────┬────────┘
             ▼
   Terms stored in inverted index:
   ["elasticsearch", "fast", "isn't"]
```

**The same analyzer runs at query time** — this is why `match` query (uses analyzer) and `term` query (exact match, no analysis) give different results on analyzed fields. A common bug: using `term` query on a `text` field (analyzed), expecting exact match — it fails because the stored term is lowercased.

---

## Mapping: Field Types and Their Impact

Elasticsearch mapping defines how each field is stored and indexed:

| Field Type | Use Case | Inverted Index? | Doc Values? | Notes |
|-----------|---------|:--------------:|:-----------:|-------|
| `text` | Full-text search | ✅ (analyzed) | ❌ | Cannot aggregate/sort directly |
| `keyword` | Exact match, facets, sorting, aggregation | ✅ (not analyzed) | ✅ | For enum-like values, IDs, tags |
| `date` | Date range queries, date histogram | ✅ (as epoch ms) | ✅ | |
| `integer` / `long` | Numeric range, sorting | ✅ (BKD tree) | ✅ | Stored as BKD tree for range efficiency |
| `geo_point` | Geo-distance, geo-bounding-box | ✅ (BKD tree) | ✅ | |
| `dense_vector` | ANN similarity (kNN search) | ❌ | HNSW graph | Since 8.0; `dims` must match at creation |
| `object` | Nested JSON object | flattened | ✅ | Loses inner doc boundaries — use `nested` for array of objects |
| `nested` | Array of objects with per-object queries | Per inner doc | ✅ | Stores as hidden inner docs; slower than `object` |

**Dynamic mapping pitfall**: ES creates fields dynamically when new keys appear in documents. A `string` field defaults to `text` + `keyword` sub-field. In production, always use **explicit mappings** and `"dynamic": "strict"` to prevent mapping explosions (too many fields = OOM on master).

---

## FAANG Interview Callout: Architecture

**What interviewers test**: Can you explain *why* ES is near-real-time (not real-time)?

**What to say**: "Elasticsearch writes go to an in-memory buffer and translog. The buffer is refreshed to a new Lucene segment every second by default — that refresh is what makes documents searchable. Until the refresh happens, the document is durable (translog survives crash) but not searchable. This is the NRT gap. You can reduce it by calling `?refresh=true` on individual writes, but that creates a segment per document — a classic throughput vs. visibility trade-off."

**Follow-up they often ask**: "What happens when a data node fails mid-write?" → Primary shard on the failed node becomes unavailable → master promotes the replica on another node to primary → cluster goes yellow during replica copy → green once replica count is restored. The translog on the failed node, if recovered, handles partial writes via sequence numbers (since 6.0).
