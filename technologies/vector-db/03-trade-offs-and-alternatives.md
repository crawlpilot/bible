# Vector Databases — Trade-offs and Alternatives

> **Focus**: Systematic comparison of the eight major vector database/search systems across 10 dimensions, six deep 1-on-1 comparisons, an 8-node decision flowchart, a 19-row trade-offs-made table, and CAP/PACELC analysis. Use this to answer "which vector DB should I choose?" in an interview or architecture review.

---

## Part 1: The Decision Framework

### Dedicated Vector DB vs Vector Extension vs Library

Before comparing systems, establish what category of tool you actually need:

```
Do you need:
  A) ANN search embedded in an existing OLTP/OLAP system?
     → Vector Extension (pgvector, Elasticsearch dense_vector, Redis VSS)
     → Advantage: no new infra; consistent transactions with other data
     → Disadvantage: not purpose-built; limited ANN index options; recall/latency at scale
  
  B) Standalone, production-grade ANN search at > 10M vectors?
     → Dedicated Vector DB (Milvus, Weaviate, Qdrant, Pinecone)
     → Advantage: purpose-built indexes; better recall/latency curve
     → Disadvantage: new infra to operate; data duplication (vectors + source)
  
  C) Offline/research batch ANN search (no HTTP server needed)?
     → Library (FAISS, ScaNN, Annoy)
     → Advantage: zero operational overhead; maximum control
     → Disadvantage: no persistence, no replication, no multi-tenancy
```

---

## Part 2: Master Comparison Table — 8 Systems × 10 Dimensions

| Dimension | **Milvus** | **Pinecone** | **Weaviate** | **Qdrant** | **pgvector** | **Redis VSS** | **Elasticsearch** | **FAISS** |
|---|---|---|---|---|---|---|---|---|
| **Open source** | ✅ Apache 2.0 | ❌ Proprietary | ✅ BSD-3 | ✅ Apache 2.0 | ✅ PostgreSQL | ⚠️ (Redis CE + Redis Stack) | ⚠️ (SSPL / Elastic) | ✅ MIT |
| **Managed cloud** | ✅ Zilliz Cloud | ✅ Native (AWS/GCP/Azure) | ✅ Weaviate Cloud | ✅ Qdrant Cloud | ✅ (via Neon, Supabase, AlloyDB) | ✅ Redis Cloud | ✅ Elastic Cloud | ❌ N/A |
| **Index types** | HNSW, IVF, IVF_PQ, IVF_SQ8, DiskANN, SCANN, BinIVF | HNSW (serverless) | HNSW | HNSW | HNSW, IVF_FLAT | HNSW, FLAT | HNSW | FLAT, IVF, HNSW, PQ, ScaNN |
| **Metadata filtering** | Bitset + inverted index; post/pre/filtered | Tag-based + metadata filters | ACORN filtered-ANN (best-in-class) | Payload index + HNSW (excellent) | PostgreSQL WHERE clause (full SQL) | Tag filtering | ES query DSL + score boosting | External post-filter only |
| **Hybrid search** | ✅ (2.4+) dense + sparse, RRF/weighted | ⚠️ Limited (planned) | ✅ BM25 + dense built-in | ✅ dense + sparse fusion | ⚠️ No native BM25 (pg_bm25 needed) | ❌ | ✅ Excellent (native BM25 + dense) | ❌ |
| **Max scale tested** | 10B+ (Zilliz) | 1B+ (serverless) | ~1B | ~1B | ~100M (with partitioning) | ~100M (memory-bound) | 1B+ (sharded cluster) | Unlimited (offline, single-machine) |
| **p99 search latency** | 1–10ms (HNSW, 10M) | 10–50ms (serverless) | 5–20ms | 1–5ms (Rust advantage) | 10–100ms (10M) | 1–5ms (in-memory) | 10–50ms | N/A (library) |
| **Ecosystem / SDKs** | Python, Java, Go, Node.js, REST | Python, Node.js, Java, REST | Python, JS/TS, Java, REST, GraphQL | Python, Rust, Go, REST | Any PostgreSQL driver | Python, Node.js, Java (Redis clients) | Python, Java, REST | Python, C++ |
| **Cost model** | Open source (free) + Zilliz Cloud (usage) | Pay per write + read unit | Open source + Weaviate Cloud | Open source + Qdrant Cloud | PostgreSQL cost (free or managed) | Open source / Redis Cloud | Open source / Elastic Cloud | Free |
| **Operational complexity** | High (multi-component: RootCoord, DataCoord, etc.) | Minimal (fully managed) | Medium (modular, Docker-compose) | Low (single binary) | Low (PostgreSQL extension) | Low (Redis module) | Medium (ES cluster) | None (embedded library) |

---

## Part 3: Deep 1-on-1 Comparisons

### Comparison 1: Pinecone vs Milvus

The "managed vs self-hosted" decision for teams building their first production vector search.

| Dimension | Pinecone | Milvus |
|---|---|---|
| **Setup time** | 5 minutes (API key + index name) | 2–8 hours (Kubernetes/Helm chart) |
| **Operational burden** | Zero — fully managed, auto-scaling | High — 6+ microservices, etcd, Pulsar/MinIO |
| **Cost at scale** | High at large scale ($0.08/1M vectors/month + read/write units) | Low (compute only; no per-vector pricing) |
| **Cost at small scale** | Low to medium (serverless pays per use) | High operational overhead amortized over small dataset |
| **Customization** | Limited (index params hidden in serverless) | Full control over all index parameters |
| **Data residency** | Pinecone's cloud; regional options limited | Your cloud/on-prem; full control |
| **Index rebuild** | Handled by Pinecone | Manual coordination required |
| **Max dimension** | 20,000 (serverless) | Unlimited |
| **Hybrid search** | Limited (sparse vector support in beta) | Full (HNSW + sparse, RRF fusion) |

**When to choose Pinecone**: Time-to-production matters more than cost or control. Teams without dedicated ML infrastructure. Startups, prototyping, PoCs.

**When to choose Milvus**: > 100M vectors where Pinecone per-vector cost becomes significant. Data residency requirements. Need full index parameter control. Have dedicated ML infrastructure team.

**Cost crossover**: At ~10M vectors, Pinecone serverless (~$0.80/month storage) vs Milvus on 2 × m5.2xlarge (~$500/month compute). Milvus becomes cheaper at larger scale despite higher operational cost.

---

### Comparison 2: Weaviate vs Qdrant

Both are open-source dedicated vector DBs with modern architectures. Most often compared for "which open-source vector DB for production?"

| Dimension | Weaviate | Qdrant |
|---|---|---|
| **Implementation language** | Go | Rust |
| **Search latency** | 5–20ms p99 | 1–5ms p99 (Rust memory safety advantage) |
| **Metadata filtering** | ACORN filtered-ANN — best recall at any selectivity | Payload index + HNSW — excellent, near-ACORN quality |
| **Schema** | Schema-first: define object types with properties | Schema-optional: flexible JSON payloads |
| **Built-in ML modules** | ✅ text2vec, image2vec, CLIP, re-rankers built-in | ❌ External embedding only |
| **Hybrid search** | ✅ BM25 + dense, weighted RRF | ✅ dense + sparse, IDF-based sparse |
| **Replication** | ✅ Multi-node (Weaviate Cluster) | ✅ (distributed mode) |
| **Multitenancy** | ✅ (multi-tenancy API: data isolation per tenant) | ✅ (collections + payload-based namespacing) |
| **GraphQL API** | ✅ Native | ❌ |
| **Operational complexity** | Medium | Low (single binary, horizontal scaling) |
| **Community** | Large (GraphQL API popular in Node ecosystem) | Growing fast (Rust reliability) |

**When to choose Weaviate**: Already using GraphQL; want built-in embedding modules (no external embedding service); schema-defined data model (knowledge management, structured ontologies); multi-tenancy at SaaS level (each customer gets isolated tenant).

**When to choose Qdrant**: Latency-critical (< 5ms p99 required); simpler ops (single binary deployment); flexible payload without schema definition; Rust ecosystem preference; aggressive filtering selectivity.

---

### Comparison 3: pgvector vs Milvus

The most common "do we really need a dedicated vector DB?" question.

| Dimension | pgvector (PostgreSQL) | Milvus |
|---|---|---|
| **New infra required** | No (extend existing PG) | Yes (new cluster) |
| **ACID transactions** | ✅ Full ACID | ❌ Eventual consistency on distributed |
| **SQL joins** | ✅ Join vectors with any relational table | ❌ No SQL; metadata filter only |
| **Query expressiveness** | Full SQL (GROUP BY, aggregations, subqueries) | ANN + basic metadata filter only |
| **Index types** | HNSW (pgvector 0.5+), IVF_FLAT | HNSW, IVF, IVF_PQ, DiskANN, SCANN |
| **Max practical scale** | ~100M vectors on dedicated Postgres instance | 10B+ (distributed) |
| **Search latency (1M vectors)** | 10–30ms (HNSW, ef=64) | 1–5ms (HNSW, ef=64) |
| **Search latency (100M vectors)** | 100–500ms | 5–20ms |
| **Hybrid search** | ❌ No native BM25 (pg_bm25 extension can add) | ✅ Native (2.4+) |
| **Operational overhead** | DBAs already familiar with PostgreSQL | New tooling required |

**Decision rule**:
- < 5M vectors + need SQL joins/transactions → **pgvector**
- > 10M vectors + latency SLO < 50ms → **Milvus**
- 5M–10M vectors → **pgvector first, migrate to Milvus when needed**

**The pgvector migration path**: Start with pgvector. When latency or scale requires it, introduce Milvus alongside Postgres — Milvus holds vectors + IDs, Postgres holds relational metadata. Join in application layer: vector search returns IDs → fetch metadata from Postgres by ID.

---

### Comparison 4: Elasticsearch vs Qdrant

When teams already have Elasticsearch for text search and are adding semantic vector capabilities.

| Dimension | Elasticsearch | Qdrant |
|---|---|---|
| **Existing infra leverage** | ✅ Add `dense_vector` field to existing indices | ❌ New system |
| **Hybrid BM25 + dense** | ✅ Excellent — native RRF, combined scoring | ✅ Good — but separate vector+sparse stores |
| **Vector search latency** | 10–50ms (HNSW) | 1–5ms (HNSW, Rust) |
| **Memory overhead** | High (ES JVM heap + Lucene segment overhead) | Low (Rust, minimal overhead) |
| **Max vector dimensions** | 4096 | 65536 |
| **Filtering quality** | ES query DSL (excellent for complex filters) | Payload index (excellent for common cases) |
| **Operational familiarity** | High (teams with ES already) | Low (new ops) |
| **Cost** | High (ES licensing at scale) | Low (open source) |

**Decision rule**:
- Have Elasticsearch for text search already → add `dense_vector` field, use hybrid BM25 + dense; avoid new system
- No existing infra → Qdrant for vector-first new system
- Compliance/security requirements already solved in ES → stay in ES

---

### Comparison 5: Redis VSS vs Milvus

When sub-millisecond latency is non-negotiable.

| Dimension | Redis VSS (Vector Similarity Search) | Milvus |
|---|---|---|
| **Architecture** | In-memory; all vectors must fit in RAM | Tiered: hot in QueryNode RAM, cold on S3 |
| **Search latency** | < 1ms p99 (in-memory) | 1–10ms p99 |
| **Max scale** | Memory-bound: ~100M vectors @ 768d = 300GB RAM | 10B+ (tiered storage) |
| **Persistence** | RDB/AOF snapshots; not primary store | S3-backed; durable |
| **ACID** | ❌ | ❌ |
| **Index types** | HNSW, FLAT | HNSW, IVF, IVF_PQ, DiskANN |
| **Cost at scale** | Very high (all RAM) | Lower (tiered; RAM only for hot data) |
| **Hybrid search** | ❌ | ✅ |
| **Consistency** | Eventual (Redis cluster) | Eventual (distributed) |

**Decision rule**:
- < 50M vectors + sub-ms latency required → Redis VSS
- > 50M vectors OR hybrid search required → Milvus

**Common pattern**: Redis VSS as cache for hot embedding queries, Milvus as the durable full-index backend. Warm-up cache on startup; on Redis miss, fall back to Milvus.

---

### Comparison 6: FAISS (Library) vs Milvus (System)

FAISS is an embedding within your application, not a separate service.

| Dimension | FAISS | Milvus |
|---|---|---|
| **Type** | Python/C++ library (no HTTP server) | Distributed database with client-server protocol |
| **Deployment** | Embedded in your application process | Separate service/cluster |
| **Replication** | Manual (copy index files) | Built-in (WAL + replica) |
| **Multi-tenancy** | Manual (separate index files) | Built-in (collections, partitions) |
| **Dynamic inserts** | Yes (but rebuilds needed for quality) | Yes (streaming inserts + growing segments) |
| **Persistence** | Save/load index to disk (manual) | Automatic (S3-backed) |
| **Scale** | Single machine (GPU optional) | Distributed (10B+ vectors) |
| **Monitoring** | None (add your own) | Built-in metrics (Prometheus) |
| **Production-grade** | ❌ (needs wrapping) | ✅ |

**Decision rule**:
- Research, ML training pipeline, offline batch processing → FAISS
- Production serving, multi-tenant, needs SLA guarantees → Milvus or other dedicated DB

---

## Part 4: Decision Flowchart

```
START: Do you need vector search?
│
├── < 100K vectors?
│   └── YES → pgvector on existing PostgreSQL. Stop here.
│
├── Need ACID transactions + SQL joins?
│   └── YES → pgvector (up to ~10M vectors). Stop here.
│
├── Already have Elasticsearch for text search?
│   └── YES → Add dense_vector field. Use BM25+dense hybrid. Stop here.
│
├── Need sub-millisecond p99?
│   └── YES → Redis VSS (if < 100M vectors). Stop here.
│
├── Is this research/offline batch? (No serving required)
│   └── YES → FAISS library. Stop here.
│
├── Want zero-ops managed solution?
│   └── YES → Pinecone (fast start) OR Zilliz Cloud (Milvus managed)
│
├── Need maximum filtering flexibility?
│   └── YES → Qdrant (best payload index) OR Weaviate (ACORN filtered-ANN)
│
├── Scale > 1B vectors OR need hybrid dense+sparse?
│   └── YES → Milvus (full-featured, 10B+ scale)
│
├── Schema-first, GraphQL API, built-in ML modules?
│   └── YES → Weaviate
│
└── Default open-source production choice?
    └── → Qdrant (simpler ops) or Milvus (full-featured)
```

---

## Part 5: Trade-offs Made in Vector Database Design

This table enumerates the core design decisions every vector database makes and what is gained/sacrificed.

| # | Trade-off | What's Gained | What's Sacrificed |
|---|---|---|---|
| 1 | **Approximate search instead of exact** | 100–10,000× query speedup | Up to 5% recall loss (tunable) |
| 2 | **HNSW graph structure** | O(log n) query time, high recall | Memory: n×M×8 bytes graph overhead |
| 3 | **Product Quantization (PQ)** | 8–32× memory reduction | 5–15% recall loss; ADC approximation |
| 4 | **Separation of write path and index build** | High write throughput (streaming ingest) | Delay between insert and ANN-searchable (minutes) |
| 5 | **Growing segment brute-force search** | No search blindspot during seal | O(n×d) scan on newest data |
| 6 | **Segment-based architecture** | Parallel index builds; horizontal scaling | Segment compaction overhead; segment count monitoring |
| 7 | **WAL (message queue) for durability** | Durability before flush to S3; replay on crash | Additional infrastructure (Pulsar/Kafka) |
| 8 | **Eventual consistency (AP)** | High write availability; no quorum writes | Stale reads possible; search may miss recent inserts |
| 9 | **Tombstone-based deletes** | Low delete latency; no index rebuild | Physical space not reclaimed until compaction |
| 10 | **Columnar metadata storage** | Fast metadata filter evaluation | Additional memory for column stores per field |
| 11 | **Post-filtering default** | Simple implementation; correct K results when selectivity is high | Recall degrades sharply at < 10% selectivity |
| 12 | **MVCC via timestamp oracle** | Consistent point-in-time reads | Clock coordination overhead; TSO as potential bottleneck |
| 13 | **Coordination layer separation (RootCoord/DataCoord/QueryCoord)** | Independent scaling of each component | Higher complexity; additional failure points |
| 14 | **Object store (S3) as primary persistence** | Cheap, durable, serverless-friendly | Cold-start load time (seconds to minutes for large segments) |
| 15 | **Memory-mapped files for segment access** | Index sizes larger than QueryNode RAM | OS page cache competition; unpredictable GC-like eviction |
| 16 | **Fixed-dimension vectors** | SIMD optimization possible; compact storage | Cannot mix embedding models in same collection |
| 17 | **Per-collection index type** | Optimal index per workload | Cannot change index type without full rebuild |
| 18 | **Single similarity metric per index** | Optimized graph construction | Cannot change metric without rebuild; wrong metric = wrong results |
| 19 | **Shared-nothing distributed architecture** | Linear horizontal scaling | No cross-shard transactions; joins impossible |

---

## Part 6: CAP Theorem and Consistency Analysis

### CAP Position

Most vector databases are **AP** (Availability + Partition Tolerance):

```
         Consistency
              │
    CA ───────┼──────── (impossible under partition)
              │
              │   CP ← Spanner/CockroachDB territory
              │
   ───────────┼───────── Partition Tolerance
              │
    AP ←── Vector DBs (Milvus, Qdrant, Weaviate, Pinecone)
    (availability favored over strict consistency)
```

**What AP means in practice**:
- Writes acknowledged after WAL durability, not after ANN index is built
- A newly inserted vector may not appear in search results for several minutes (until segment is indexed and loaded to QueryNode)
- Replica reads may return slightly stale results during replication lag

**pgvector exception**: Inherits PostgreSQL's CP guarantees. Writes are synchronous; reads are immediately consistent. This is why pgvector is preferred for compliance or audit scenarios.

### Consistency Levels Available

| System | Consistency Options |
|---|---|
| Milvus | `Strong` (read-after-write, higher latency), `Session` (user-level RYW), `Bounded Staleness` (configurable), `Eventually` (default) |
| Qdrant | No explicit levels; eventual consistency on replicas |
| Weaviate | Eventual (no strong consistency option) |
| pgvector | PostgreSQL transaction isolation levels (READ COMMITTED, REPEATABLE READ, SERIALIZABLE) |
| Pinecone | Eventual; vectors become searchable within seconds |

### PACELC Analysis

When there is no partition, the trade-off is **latency vs consistency** (PACELC):

| System | Partition behavior | Normal (no partition) |
|---|---|---|
| Milvus | AP (continue writes, eventual consistency) | Lower latency with eventual; higher latency with strong |
| Weaviate | AP | Lower latency (async index propagation) |
| Qdrant | AP | Low latency (Rust, in-memory operations) |
| pgvector | CP (PostgreSQL 2PC) | Higher latency (synchronous write with index update) |
| Pinecone | AP (Pinecone decides) | Managed latency (~10–50ms) |

**Interview insight**: *"For a RAG knowledge base where slightly stale results are acceptable (documents don't need to appear in search within seconds), AP is fine. For a compliance system where 'what did the system know at time T' must be answerable, pgvector with CP guarantees is required."*

---

## FAANG Interview Callout

> **What the interviewer is testing**: Can you reason about the full system trade-off landscape? Do you know that pgvector is often the right answer for small scale? Can you articulate the price/performance/ops triangle between Pinecone/Milvus/Qdrant?

**Model answer for "which vector DB would you choose for a multi-tenant SaaS product with 100 customers, growing to 10,000?"**:

*"I'd start with pgvector on Postgres — 100 customers × average 100K vectors each = 10M total vectors, well within pgvector's comfortable range. I get SQL joins with user/tenant metadata, full ACID, and zero new infrastructure. I'd use pgvector's HNSW index for sub-100ms search. As we scale to 10,000 customers × 100K vectors = 1B total, I'd migrate to Milvus with partition keys for tenant isolation — each tenant's vectors route to a dedicated partition within a shared collection. The migration path is clean: Milvus IDs match Postgres primary keys; application layer joins on ID. I'd use Zilliz Cloud to avoid managing the Milvus cluster ourselves until the team grows."*

---

## Related Files

- [README.md](README.md) — overview, use cases, anti-patterns, key numbers
- [01-architecture.md](01-architecture.md) — index algorithms, Milvus internals
- [02-read-write-path.md](02-read-write-path.md) — ingestion path, filtering strategies
- [04-tuning-guide.md](04-tuning-guide.md) — parameter tuning for chosen system
- [05-production-and-research.md](05-production-and-research.md) — production deployments, research papers
