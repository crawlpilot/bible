# Elasticsearch — Production & Research

## Founding Papers and Technology Lineage

### Apache Lucene (2001) — Doug Cutting
Elasticsearch is built on Lucene. The key papers and references:
- **Lucene Design** (Doug Cutting, 2001): Inverted index, posting lists, segment-based architecture
- **"IR: A Self-Survey" (Manning et al.)** — Foundational IR theory behind BM25, TF-IDF
- **"Probabilistic Relevance Framework: BM25 and Beyond" (Robertson & Zaragoza, 2009)** — The BM25 model Elasticsearch uses as default similarity

### "Elasticsearch: The Definitive Guide" (Clinton Gormley, Zachary Tong, 2015)
Not a research paper, but the canonical reference for ES architecture. Chapters 10–12 cover shard allocation, routing, and the two-phase search — essential reading before a FAANG interview where ES is part of the system design.

### Shay Banon's Original Design Goals (2010)
Banon designed Elasticsearch around three principles:
1. **REST API over HTTP** — no Lucene Java API complexity
2. **Schema-free JSON** — documents auto-mapped without schema declaration
3. **Distributed by default** — every cluster feature (replication, failover, recovery) built in from day one

These principles are why ES won over Solr: Solr had better search features in 2010, but ES had dramatically lower time-to-production.

---

## How FAANG Companies Use Elasticsearch

### Netflix — Multi-Cluster Log Analytics at Scale

**Problem**: 1+ billion log events per day from microservices running on thousands of EC2 instances; on-call engineers need < 5s query response on last 24 hours of logs.

**Architecture**:
```
Microservices → Filebeat agents → Kafka topics → Logstash consumers → ES clusters (regional)
                                                                              │
                                                                         Kibana dashboards
                                                                         (on-call queries)
```

**Scale**: ~50-node clusters per region; 400+ TB total log storage; separate hot clusters (7-day retention, SSD) and warm clusters (90-day retention, HDD) with ILM.

**Netflix lesson**: "The most important thing we did was enforce schema governance on log fields. Dynamic mapping led to a mapping explosion that crashed a cluster in 2014. We now pre-register every log schema and use `dynamic: strict` everywhere." — Netflix Tech Blog, 2016.

### Uber — Real-Time Rider/Driver Search

**Problem**: Match riders to the nearest available drivers across 10,000+ cities; < 100ms query latency; 50K+ requests/second at peak.

**Architecture**:
```
Driver location updates (GPS) → Kafka → ES indexing pipeline
Rider search request → ES geo_distance query → top 10 nearest drivers
                   → result sent to rider app
```

**Key design choice**: Uber uses **routing by city_id** (`_routing` parameter) — all drivers in a city land on the same set of shards. A rider search only fans out to 2 shards (primary + replica), not all 100 shards. This reduces scatter-gather overhead from 100 nodes to 2 for the common case.

**Uber scale**: 1M+ active drivers indexed; real-time geo_point updates at ~100K writes/sec during peak surge; < 10ms p50 query latency.

### GitHub — Code Search

**Problem**: Search 200M+ code repositories; exact substring match + regex + language filter; < 1s results for most queries.

**Architecture** (prior to their Rust-based rewrite in 2023):
- Separate ES clusters per language family
- Custom analyzers for code tokenization (split on operators, camelCase, snake_case)
- `n-gram` tokenizer on identifiers for substring search (e.g., searching "indexOf" finds "lastIndexOf")
- Trigram-based regular expression support via custom Lucene extension

**GitHub lesson**: Standard text analyzers built for natural language perform poorly on code. Code has different tokenisation needs — operators, brackets, and camelCase are meaningful boundaries. They built a custom `code` analyzer.

### Cloudflare — DNS Security Analytics (1.1.1.1 Resolver)

**Problem**: Analyze 1 trillion DNS queries per day for security patterns (DGA detection, malware domains); alert within 60 seconds of new threat signatures matching.

**Architecture**:
```
DNS resolver → Kafka stream (1 trillion events/day) → Flink enrichment → ES ingestion
                                                                    │
                                                             Kibana threat hunting
                                                             Real-time alerting (Watcher)
```

**Scale**: 200+ node ES cluster; ~12 PB storage; custom ILM with 3 tiers (hot SSD → warm HDD → cold S3-backed searchable snapshots).

**Cloudflare lesson**: ES's snapshot-restore + searchable snapshots (ES 7.12+) was a game-changer. They mount cold data directly from S3 without restoring it to disk. Query latency on cold data is ~3–10× worse than warm, but storage cost drops 90%. For threat hunting on historical data, that trade-off is worth it.

### LinkedIn — People and Job Search

**Problem**: "People you may know", job recommendations, profile search across 900M+ members.

**Architecture**:
- **Galene** (LinkedIn's search platform, built on Lucene with custom extensions)
- Hybrid BM25 + learning-to-rank (LTR) — Elasticsearch's LTR plugin (OpenSource by Wikimedia) or native `rank_feature` queries
- Separate indices for people, jobs, companies; joined at query-time by the application layer

**LinkedIn insight**: For professional search, personalised ranking (who you know, your industry, your seniority) matters more than pure BM25 relevance. They introduced **learning-to-rank** models trained on click data on top of ES BM25 baseline.

### Airbnb — Listing Search with Multi-Criteria Ranking

**Problem**: Search 7M+ listings by location, dates, price, amenities, reviews; personalised ranking; < 200ms p99 latency.

**Architecture**:
```
User query → Coordinating layer → ES geo_shape + bool query (hard filters)
                                 + function_score (soft ranking: price, reviews, proximity)
                                 → candidate set (top 500)
                                 → ML re-ranking layer (personalised model)
                                 → final 20 results
```

**Key pattern**: Two-stage retrieval — ES does the hard work of filtering billions of documents to a candidate set; a lightweight ML model re-ranks the candidates with personalisation signals. This is the **ANN + re-rank** pattern seen in modern search and RAG systems.

---

## Searchable Snapshots (ES 7.12+) — The Cold Storage Revolution

Before searchable snapshots, cold data in ES meant a choice: keep it in the cluster (expensive) or delete it (losing searchability). Searchable snapshots changed this:

```
Traditional cold tier:
  Index → forcemerge → copy segments to S3 (backup) → delete from cluster
  To search: restore from S3 → wait hours → search → delete again

Searchable snapshots (Frozen tier):
  Index → forcemerge → take snapshot to S3 → mount as searchable snapshot
  Search: ES streams only needed segment bytes from S3 on demand
  Cost: 90% cheaper than keeping on local disk; 3-10× slower queries
```

**When it matters at FAANG scale**: A 1 PB 90-day log cluster can be reduced to 100 TB hot/warm + 900 TB frozen (on S3 object storage). Cost savings at 1 PB scale: $800K+/year depending on cloud pricing.

---

## FAANG Interview Framing

### System Design: When to Introduce Elasticsearch

The classic FAANG interview scenario: design a system that needs search.

**Correct framing**:
> "I'll use Elasticsearch for the search layer, but it won't be the source of truth. The canonical data lives in [PostgreSQL/Cassandra/DynamoDB]. We'll sync to ES asynchronously — either through CDC via Debezium reading the write-ahead log, or through application-level dual-write with a reconciliation job for consistency. ES gives us full-text ranking, faceted navigation, and aggregations that [primary DB] cannot provide at this scale, but we accept 1–2 second indexing lag and the operational cost of maintaining the sync pipeline."

**What this answer demonstrates**:
1. You understand ES is a secondary store, not a primary store
2. You know how to keep it in sync (CDC is the production-grade answer)
3. You acknowledge the trade-off explicitly (NRT lag, sync complexity)
4. You know why ES is the right choice for this specific use case

### Common FAANG Questions About Elasticsearch

| Question | What They're Testing | Key Answer |
|----------|---------------------|-----------|
| "Why is ES near-real-time, not real-time?" | Lucene internals | Refresh = in-memory buffer → new segment; default 1s interval; `?refresh=true` forces immediate but expensive |
| "How would you scale ES to 10B documents?" | Cluster sizing, sharding | Shard count = ceil(total_GB/30); tiered storage (hot/warm/cold/frozen); ILM; multiple clusters for isolation |
| "How do you keep ES in sync with your primary DB?" | Data architecture | CDC (Debezium → Kafka → ES consumer) preferred over dual-write; handle failures with dead-letter queue; reconciliation job |
| "What happens to ES during a network partition?" | CAP theorem | Primary shard available; replica may serve stale data; isolated shard goes unassigned if no quorum; master re-elects |
| "Why did you choose ES over Solr / Algolia / PostgreSQL FTS?" | Comparative reasoning | See 03-trade-offs |
| "How would you design autocomplete?" | Search features | `completion` suggester (FST-based, < 5ms) or `edge_ngram` tokenizer on `keyword` field; prefix queries on `keyword` |
| "What is the split-brain problem in ES?" | Distributed systems | Two partitioned groups both elect a master → inconsistent cluster state; solved by quorum-based Raft (min master nodes = N/2+1) |

### The Autocomplete Deep Dive (Often Asked)

```json
// Option 1: completion suggester (FST — Finite State Transducer)
// Best for: simple prefix autocomplete, < 5ms latency, fixed list of suggestions
{
  "mappings": {
    "properties": {
      "suggest": {
        "type": "completion",
        "analyzer": "simple"
      }
    }
  }
}
GET /products/_search
{ "suggest": { "product-suggest": { "prefix": "elast", "completion": { "field": "suggest" } } } }

// Option 2: edge_ngram tokenizer
// Best for: autocomplete with BM25 relevance ranking, typo tolerance
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "edge_ngram_tokenizer": { "type": "edge_ngram", "min_gram": 2, "max_gram": 10 }
      }
    }
  }
}
// Index: "elasticsearch" → ["el", "ela", "elas", "elast", "elasto", ..., "elasticsearch"]
// Query: match query on edge_ngram field with "elast" → fast prefix match with ranking
```

**Trade-off**: `completion` suggester is faster (FST lookup) but less flexible (no facets, no ranking by field values). `edge_ngram` is slower but supports full query DSL including filters, function_score, and facets.

---

## Operational Runbook: Production Incident Patterns

| Incident | Symptoms | Root Cause | Resolution |
|---------|----------|------------|----------|
| **Red cluster (unassigned shards)** | `GET /_cluster/health` → red; queries fail | Node failure; disk full; allocation filters | `GET /_cluster/allocation/explain` → fix root cause → `POST /_cluster/reroute?retry_failed=true` |
| **OOM / JVM crash** | ES process dies; heap dump | Heap too small; fielddata bloat; large aggregations | Increase heap (up to 31 GB); eliminate fielddata on text; use keyword sub-fields |
| **Slow queries (p99 > 1s)** | High search latency | Too many shards; missing doc values; deep pagination; cold page cache | Profile with `?profile=true`; reduce shard count with shrink; add keyword sub-field for aggregations; use search_after |
| **Indexing throughput drop** | Write rate falls 50%+ | Merge storm; refresh too frequent; replica bottleneck | Disable refresh during load; reduce merge threads; increase bulk size |
| **Master node overloaded** | Pending tasks > 100; node join delays | Dynamic mapping; too many indices; frequent ILM transitions | Enforce strict mapping; consolidate indices; separate master nodes from data |
