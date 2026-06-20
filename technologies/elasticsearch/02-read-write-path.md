# Elasticsearch — Read & Write Path

## Write Path: From HTTP to Disk

### Overview

```
Client HTTP PUT /products/_doc/123
         │
         ▼
┌─────────────────┐
│ Coordinating    │  1. Receives request
│ Node            │  2. Determines target shard: hash("123") % 3 = shard 1
│                 │  3. Routes to data node holding shard 1 primary
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Data Node — Primary Shard 1                                     │
│                                                                 │
│  4. Validate mapping; run ingest pipeline (if configured)       │
│  5. Write to in-memory Indexing Buffer (lucene memory buffer)   │
│  6. Write to Translog (append-only, fsync'd — durable)         │
│  7. Replicate to all replica shards (parallel, sync by default) │
│  8. Return ACK to coordinating node after replicas confirm      │
│                                                                 │
│  [Background, every 1 second]                                   │
│  9. REFRESH: flush in-memory buffer → new Lucene segment        │
│     (segment now searchable; translog still needed for recovery)│
│                                                                 │
│  [Background, every 30 minutes or on translog size threshold]   │
│  10. FLUSH: fsync all segments to disk, commit Lucene           │
│      checkpoint, truncate translog                              │
└─────────────────────────────────────────────────────────────────┘
```

### The Three Durability Layers

| Layer | When Committed | What It Does | Survivor on Crash |
|-------|---------------|-------------|:-----------------:|
| **Translog** | Every write (fsync configurable) | Append-only log for crash recovery; replayed on node restart if Lucene checkpoint is behind | ✅ Yes |
| **Lucene memory buffer** | Cleared on refresh (1s) | In-RAM inverted index; searchable after refresh | ❌ Lost (recovered from translog) |
| **Lucene segment on disk** | On flush / Lucene commit | Immutable segment file; no translog needed after checkpoint | ✅ Yes |

**Key insight**: Documents are durable immediately (translog) but not searchable until the next refresh. This is the NRT (near-real-time) gap that distinguishes ES from a database with synchronous read-your-write semantics.

### Translog Configuration

```yaml
# Async fsync (higher throughput, ~5s data loss window on crash)
index.translog.durability: async
index.translog.sync_interval: 5s

# Synchronous fsync (default — safer, ~10% write throughput penalty)
index.translog.durability: request
```

**FAANG design choice**: For log aggregation pipelines (ELK), async translog is acceptable — losing 5s of logs in a crash is acceptable. For search on e-commerce products, use the default `request` durability.

---

## Refresh: Making Documents Searchable

```
Timeline:
t=0:    Document written to memory buffer + translog
t=0.1s: Document visible in memory buffer — NOT YET searchable
t=1s:   REFRESH — memory buffer flushed to new Lucene segment
         → document is now searchable
t=30min: FLUSH — Lucene commit + segment files fsync'd to disk
          → translog can be truncated
```

### Controlling Refresh Behaviour

```json
// Per-index: default (1s)
PUT /products/_settings
{ "index.refresh_interval": "1s" }

// Disable for bulk indexing (massive throughput gain)
PUT /products/_settings
{ "index.refresh_interval": "-1" }
// Re-enable after bulk load:
PUT /products/_settings
{ "index.refresh_interval": "1s" }
POST /products/_refresh   // force refresh

// Per-request: make document immediately searchable
PUT /products/_doc/123?refresh=true     // force refresh of shard → expensive
PUT /products/_doc/123?refresh=wait_for // wait for next scheduled refresh
PUT /products/_doc/123?refresh=false    // default — no guarantee
```

**Trade-off**: `refresh=true` creates one Lucene segment per document → rapid segment proliferation → expensive merges → write throughput collapse. Only use in testing or for very low-volume critical writes.

---

## Bulk Indexing Pattern (Production Standard)

Single-document writes are expensive. Always use the `_bulk` API:

```
POST /_bulk
{ "index": { "_index": "products", "_id": "1" } }
{ "name": "Widget A", "price": 9.99, "category": "tools" }
{ "index": { "_index": "products", "_id": "2" } }
{ "name": "Widget B", "price": 14.99, "category": "tools" }
...
```

**Optimal bulk request size**: 5–15 MB per request (not document count — measure bytes). Start at 1000 docs/request and tune up until latency or throughput degrades.

**Maximum sustainable throughput formula**:
```
indexing_throughput = (bulk_size_MB × parallel_bulk_threads) / avg_indexing_latency_ms × 1000
```
A well-tuned 10-node cluster can sustain 500K–1M docs/min on typical log documents (avg 500 bytes).

---

## Read Path: From HTTP to Results

### Two-Phase Search: Query Phase + Fetch Phase

```
Client GET /products/_search  { "query": { "match": { "name": "widget" } } }
         │
         ▼
┌─────────────────┐
│ Coordinating    │  QUERY PHASE:
│ Node            │  1. Identify all shards for the index (primary OR replica — round-robin)
│                 │  2. Broadcast query to one shard copy per shard
│                 │  3. Each shard returns: top-N doc IDs + _scores (NO _source yet)
│                 │  4. Coordinating node merges N×shards results → global top-N
│                 │
│                 │  FETCH PHASE:
│                 │  5. Request full _source for global top-N doc IDs
│                 │  6. Shards return _source JSON
│                 │  7. Coordinating node assembles final response
└─────────────────┘
```

**Why two phases?** Returning full `_source` for every candidate across all shards would be wasteful. Scores are cheap to compute; `_source` retrieval is I/O-bound. The query phase is cheap; fetch phase touches only the final top-K documents.

**Deep pagination problem**: `from: 9900, size: 100` forces every shard to return 10,000 doc IDs → coordinating node merges 10,000 × N_shards results → keeps only 100. Memory and CPU blow up as `from` increases. Max recommended: `from + size ≤ 10,000` (enforced by `index.max_result_window`).

---

## Pagination Strategies

| Strategy | How It Works | Pros | Cons | When to Use |
|----------|-------------|------|------|-------------|
| **from/size** | Offset + limit | Simple | O(from×shards) memory; max 10K | First few pages of results |
| **search_after** | Cursor using last doc's sort values | Stateless, O(page_size) | Must sort by unique field; no random page access | Deep pagination, infinite scroll |
| **scroll API** | Snapshot search context held in memory | Consistent snapshot; deep pages | Server-side state; deprecated for real-time | Bulk export, re-indexing |
| **Point In Time (PIT)** | Lightweight snapshot ID + search_after | Stateless cursor + consistent view | Requires PIT open/close lifecycle | Preferred for deep pagination since ES 7.10 |

### search_after Example

```json
GET /products/_search
{
  "size": 10,
  "query": { "match": { "category": "tools" } },
  "sort": [
    { "price": "asc" },
    { "_id": "asc" }          ← tie-breaker: must be unique
  ],
  "search_after": [9.99, "42"]  ← values from last doc of previous page
}
```

---

## Relevance Scoring: BM25

Elasticsearch uses **BM25** (Best Match 25) as the default similarity algorithm (replaced TF-IDF in ES 5.0):

```
BM25 score(term t in document D) =
  IDF(t) × (TF(t,D) × (k1 + 1)) / (TF(t,D) + k1 × (1 - b + b × |D|/avgDL))

Where:
  IDF(t) = log((N - df(t) + 0.5) / (df(t) + 0.5) + 1)   ← penalises common terms
  TF(t,D) = count of t in D                                ← rewards local frequency
  |D| = length of document D                               ← length normalisation
  avgDL = average doc length in index
  k1 = term frequency saturation (default 1.2)             ← diminishing returns for high TF
  b = length normalisation factor (default 0.75)           ← 0 = no normalisation, 1 = full
```

**Interview insight**: BM25 fixes TF-IDF's over-weighting of high-frequency terms (a word appearing 100× is not 100× more relevant than appearing 10×). The `k1` parameter caps term frequency saturation.

---

## Doc Values: Columnar Storage for Aggregations

Doc values are the **column-store** layer alongside the inverted index row-store:

```
Inverted index (row-oriented, for search):
  "elasticsearch" → [doc1, doc2, doc47, doc831, ...]
  "fast"          → [doc1, doc3, doc5, ...]

Doc values (column-oriented, for sorting + aggregation):
  doc1 → price: 9.99,  category: "tools",  date: 2024-01-01
  doc2 → price: 14.99, category: "tools",  date: 2024-01-02
  doc3 → price: 4.99,  category: "home",   date: 2024-01-01
  ...
```

Doc values are stored on disk in a compressed columnar format (DPACK), memory-mapped. A `terms` aggregation on `category` reads only the `category` column — no need to load `_source` JSON.

**Fielddata vs. doc values**: `text` fields cannot have doc values (analyzed, multi-term). If you must aggregate on a `text` field, enable `fielddata: true` — this loads the inverted index into **heap** as an uninverted structure. This is expensive and can cause GC pressure. The correct solution: add a `keyword` sub-field and aggregate on that.

---

## Fielddata Circuit Breaker

Elasticsearch protects the JVM from OOM errors via circuit breakers:

```
indices.breaker.fielddata.limit: 40%  (of heap)  → fielddata circuit breaker
indices.breaker.request.limit: 60%    (of heap)  → request-level aggregation
indices.breaker.total.limit: 70%      (of heap)  → total in-flight requests
```

When a request would push heap usage past the limit, ES throws `CircuitBreakerException` rather than crashing. The correct response is to reduce field data usage (use `keyword` for aggregations, avoid `fielddata: true` on `text`).

---

## FAANG Interview Callout: Read/Write Path

**What interviewers test**: Deep understanding of the two-phase search and why deep pagination is expensive.

**What to say on deep pagination**: "The from/size pagination in Elasticsearch has O(from × shard_count) memory cost because the coordinating node must receive and merge `from + size` results from every shard to determine the global top-K. At from=9900, that's 10,000 results per shard × N shards. The solution is search_after with a Point-in-Time — the coordinating node only needs to hold `size` results per shard per page, and the PIT snapshot ensures consistent results even as the index changes during pagination."

**Common follow-up**: "How would you design a real-time search feature where new products appear in search results within 100ms?" → Reduce `refresh_interval` to `100ms` on the products index. Trade-off: 10× more segment creation, 10× more merge pressure. Mitigate with larger bulk batches and sufficient merge threads. Alternatively, use the `?refresh=wait_for` parameter on the indexing path — the HTTP call blocks until the next scheduled refresh, giving you predictable visibility without per-write refresh overhead.
