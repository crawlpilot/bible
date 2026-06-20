# Elasticsearch — Trade-offs & Alternatives

## CAP / PACELC Position

Elasticsearch is an **AP system** with near-real-time (NRT) visibility:

```
         Consistency
              │
     CP       │       CA
  (ZooKeeper  │   (traditional
   HBase,     │    RDBMS —
   Spanner)   │    unrealistic
              │    across DCs)
──────────────┼──────────────────
              │
     AP       │
  (Cassandra  │
   Elasticsearch│
   DynamoDB)  │
              │
        Partition Tolerance
```

### What AP Means for Elasticsearch

During a **network partition**:
- **Primary shard** remains available and accepts writes
- **Replica shards** on the isolated side are **promoted** if their primary is lost (master election)
- A shard may be temporarily **unassigned** if quorum cannot be achieved, causing the index to go **red** (data loss risk)
- ES does NOT have a "write to both sides of partition" model like Cassandra — if the primary is partitioned away and no quorum exists, that shard goes unavailable

**Near-real-time consistency**: Even without a partition, reads are not linearisable — the 1s refresh window means a document written at T=0 is invisible to searches until T≈1s. Unlike Cassandra's "read-your-own-write with consistency=ONE", ES has no mechanism to guarantee freshness without forcing a refresh.

### PACELC Analysis

```
PACELC: If Partition → Availability (not Consistency)
        Else → Low Latency (not full Consistency)

ES chooses:
  P → A  (availability over consistency during partition)
  E → L  (latency over consistency during normal operation — NRT by design)
```

---

## Primary Trade-offs

### Trade-off 1: Inverted Index vs. Row Store — Query Flexibility vs. Write Amplification

| Dimension | Elasticsearch | Cassandra | PostgreSQL |
|-----------|:-------------|:---------|:----------|
| Query model | Ad-hoc full-text + filter + aggregation | Partition-key primary; no ad-hoc | Full SQL; any query |
| Write path | Inverted index rebuild per field per doc | Append-only LSM tree | B-tree random update |
| Write amplification | High (N fields → N posting list updates + merge) | Low (sequential append only) | Medium |
| Update semantics | Delete + re-index (segment tombstone) | Upsert (newer timestamp wins) | In-place update (MVCC) |
| **Verdict** | Read-optimised; design for low update rate | Write-optimised; schema drives access | Balanced; suits OLTP |

**Recommendation**: If your workload is 80% reads and 20% writes with low update rate → ES wins. If write rate exceeds ~30% of corpus/day with frequent updates to existing documents → Cassandra or PostgreSQL.

### Trade-off 2: NRT vs. Strong Consistency

| Requirement | Elasticsearch (NRT) | Recommendation |
|------------|-------------------|---------------|
| Show me the cart I just saved | ❌ 1s lag | PostgreSQL / Redis |
| Search the product catalog I just updated | ✅ acceptable | Elasticsearch |
| Financial audit log — must read my write | ❌ never | PostgreSQL (SERIALIZABLE) |
| Log search 5s after ingestion | ✅ fine | Elasticsearch |
| Autocomplete as user types | ✅ fine (suggest API) | Elasticsearch |

### Trade-off 3: Shard Count — Parallelism vs. Overhead

| Shard Count | Effect | Anti-Pattern |
|------------|--------|-------------|
| Too few (1–2 for large index) | Limited query parallelism; single shard becomes hot | 1 TB index on 1 shard |
| Too many (1 per document or thousands) | Heap overhead per shard (~1–2 MB); cluster state bloat; slow recovery; scatter-gather overhead | Time-series index with 1 shard/hour |
| Optimal (10–50 GB per shard) | Balanced parallelism, fast recovery, manageable overhead | Use ILM with rollover |

**Goldilocks rule**: A cluster with 50 GB heap across nodes should have no more than ~1,000 shards (≤20 shards/GB heap).

---

## Elasticsearch vs. Alternatives

### vs. Apache Solr

| Dimension | Elasticsearch | Apache Solr |
|-----------|:-------------|:-----------|
| Architecture | Masterless cluster (Raft) | Leader-based (SolrCloud + ZooKeeper) |
| Ease of use | REST + JSON out of the box | XML config, schema.xml, complex setup |
| Ecosystem | Kibana, Logstash, Beats (ELK/Elastic Stack) | Limited; Banana dashboard |
| Community / velocity | Dominant; Elastic drives Lucene | Slower; legacy-heavy |
| Analytics | Rich aggregations, ML features | Basic faceting |
| Cloud | Elastic Cloud (managed) | No official managed offering |
| **Verdict** | Choose ES for all new projects | Choose Solr only if migrating existing Solr deployment |

### vs. OpenSearch (AWS Fork)

| Dimension | Elasticsearch | OpenSearch |
|-----------|:-------------|:----------|
| License | SSPL (non-OSS since 7.11) / Elastic License 2.0 | Apache 2.0 |
| API compatibility | Source; features added ahead | Compatible with ES 7.10; some ES 8.x gaps |
| Managed cloud | Elastic Cloud | AWS OpenSearch Service |
| Feature parity | More advanced ML (ELSER, ESRE) | Comparable core; some unique AI features |
| **Verdict** | Choose ES on Elastic Cloud or when Elastic's ML stack is needed. Choose OpenSearch when Apache 2.0 license is required (enterprise compliance, AWS native). |

### vs. Algolia

| Dimension | Elasticsearch | Algolia |
|-----------|:-------------|:-------|
| Deployment | Self-hosted or Elastic Cloud | SaaS only |
| Latency | 20–100ms (self-tuned) | <10ms (globally distributed CDN-backed) |
| Customisation | Full: custom analyzers, scoring scripts | Limited; opinionated API |
| Scale | Petabyte-scale self-hosted | Limited dataset size (pricing per record) |
| Cost | Infrastructure cost | High per-record SaaS cost at scale |
| Analytics depth | Deep (Kibana, ML) | Basic search analytics |
| **Verdict** | ES for large datasets, custom scoring, analytics platform. Algolia for consumer-facing instant search with SLA requirements and small-to-medium catalogue. |

### vs. Typesense

| Dimension | Elasticsearch | Typesense |
|-----------|:-------------|:---------|
| Focus | General search + analytics + logs | Instant search, typo tolerance |
| Ease of ops | Complex (JVM, shard tuning) | Simple (single binary, minimal config) |
| Features | Full aggregations, geo, ML | Basic faceting; excellent typo/fuzzy |
| Scale | Petabytes | < 100 GB practical |
| **Verdict** | ES for enterprise-scale. Typesense for a small-team product needing fast, easy-to-operate instant search. |

### vs. PostgreSQL Full-Text Search

| Dimension | Elasticsearch | PostgreSQL (tsvector + GIN) |
|-----------|:-------------|:---------------------------|
| Integration | Separate service | Same DB; transactional FTS |
| Relevance | BM25 + scripted scoring + ML | Limited; no BM25 built-in |
| Freshness | NRT (1s lag) | Real-time (read-your-own-write) |
| Aggregations | Rich | Limited (GROUP BY only) |
| Scale | Billions of docs | < 50M docs practical |
| Operational overhead | High | None (already running Postgres) |
| **Verdict** | PostgreSQL FTS first (zero added ops) when corpus < 10M docs and basic keyword search suffices. Move to ES when you need relevance tuning, faceting, or scale beyond 50M docs. |

### vs. Meilisearch

| Dimension | Elasticsearch | Meilisearch |
|-----------|:-------------|:----------- |
| Target | Enterprise, analytics, logs | Developer-friendly, small SaaS |
| Typo tolerance | Configurable (fuzziness) | Built-in, excellent |
| Performance | High throughput with tuning | Extremely fast out of box |
| Analytics | Deep (Kibana) | Minimal |
| **Verdict** | ES for production scale; Meilisearch for small projects prioritising developer experience. |

---

## Hybrid Search: BM25 + Dense Vector (Elasticsearch 8.x)

Modern Elasticsearch supports **hybrid search** — combining lexical BM25 with semantic dense vector search. This is the preferred architecture for RAG pipelines:

```
Query: "fast NoSQL database for write-heavy workloads"
         │
         ├─ BM25 search (lexical)         → matches "NoSQL", "write-heavy", "database"
         │   → documents with exact terms ranked high
         │
         └─ kNN search (dense vector)     → matches semantic meaning of "fast write"
             using HNSW ELSER embeddings  → documents about Cassandra, DynamoDB without those exact words
                │
                ▼
         Reciprocal Rank Fusion (RRF) or linear combination merge
                │
                ▼
         Final ranked result list
```

**Elasticsearch ELSER**: Elastic's own sparse neural model for semantic retrieval — produces sparse vectors (like BM25 but learned) rather than dense 768-dim embeddings, trading some accuracy for 3–5× faster inference.

---

## Decision Flowchart

```
Need search or analytics?
│
├─ Full-text relevance ranking required?
│   ├─ Yes + large scale (> 10M docs) + analytics → Elasticsearch
│   ├─ Yes + small scale (< 10M docs) + ops simplicity → PostgreSQL FTS or Typesense
│   └─ Yes + consumer SaaS, SLA, no ops → Algolia
│
├─ Log aggregation + dashboards?
│   ├─ Existing AWS infra → OpenSearch Service
│   └─ Self-hosted or Elastic Cloud → Elasticsearch (ELK stack)
│
├─ Semantic / vector search (RAG)?
│   ├─ Already have ES cluster → dense_vector + ELSER hybrid search
│   ├─ Pure vector search, > 100M vectors → Milvus / Qdrant
│   └─ Managed, simple → Pinecone
│
└─ Geo-search?
    └─ Elasticsearch (geo_point + geo_distance queries)
```

---

## FAANG Interview Callout: Trade-offs

**What interviewers test**: Can you compare ES to alternatives on concrete dimensions, not just recite "ES is good for search"?

**What to say**: "Elasticsearch vs. PostgreSQL full-text search: for < 10M docs, PostgreSQL's tsvector + GIN index gives you full-text search with zero additional operational overhead, real-time consistency, and ACID transactions for free. I'd default to that. Once the corpus exceeds 50M docs, query latency on Postgres degrades, and you lose BM25 relevance, faceted navigation, and aggregation depth. That's the inflection point where Elasticsearch earns its operational cost."

**Hot follow-up**: "You've chosen ES for search but your source of truth is Postgres. How do you keep them in sync?" → **Dual-write** (application writes to both — risks inconsistency on partial failure) vs. **CDC via Debezium** (reads Postgres WAL, emits to Kafka, a consumer indexes into ES — decoupled, at-least-once, eventual). CDC is the production-grade approach. Handle re-indexing needs with a backfill job that reads from Postgres and bulk-loads into a new ES index, then atomically aliases the old index to the new one.
