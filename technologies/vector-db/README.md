# Vector Databases — Overview & Decision Guide

> **Principal Engineer Quick Reference**: Vector databases are purpose-built for approximate nearest-neighbor (ANN) search over high-dimensional embedding vectors. They are the storage and retrieval layer that makes semantic search, RAG systems, and real-time recommendation feasible at production scale. Understanding when to choose a vector DB — and which one — is a core system design competency for AI-adjacent roles.

---

## What Is a Vector Database?

A vector database stores numerical embeddings (dense float arrays) and answers the question: *"given this query vector, return the K most semantically similar stored vectors."*

**Why not a regular database?**

Traditional databases use B-trees and inverted indexes optimized for exact-match or range queries. Finding the nearest neighbor in a 1536-dimensional space with exact arithmetic costs **O(n × d)** per query — scanning billions of floats for every request. At 100M vectors with d=1536:

```
100,000,000 × 1536 × 4 bytes = 614 GB of computation per query
At 10,000 QPS = 6.14 PB/s of memory bandwidth required
```

This is physically impossible without approximation. Vector databases solve this via **Approximate Nearest Neighbor (ANN) indexes** that trade a bounded recall loss (typically 1–5%) for 100–10,000× speedup.

**The core trade-off every system has to make:**

```
Recall ←────────────────────────────→ Latency / Throughput
  ↑                                           ↑
Higher M, ef, nprobe            Lower M, ef, nprobe
More accurate                   Faster queries
More memory                     Less memory
```

---

## Quick-Reference Card

| Dimension | Value |
|---|---|
| **Primary data model** | Fixed-dimension float vectors (FP32/FP16/INT8/Binary) + metadata fields |
| **Query type** | K-nearest neighbor (KNN) / approximate nearest neighbor (ANN) |
| **Similarity metrics** | Cosine, L2 (Euclidean), Inner Product (dot product), Hamming |
| **Consistency model** | Eventual (most systems); Strong on single-segment reads |
| **CAP position** | AP — availability + partition tolerance; tunable in some systems |
| **Typical write throughput** | 10K–500K vectors/second (batch insert, indexed offline) |
| **Typical search latency** | 1–10ms p99 at 10M vectors with HNSW; 50–200ms with IVF+PQ |
| **Memory overhead** | ~100–500 bytes/vector for HNSW; ~8–16 bytes/vector for IVF+PQ |
| **Horizontal scaling** | Sharding by collection partition; replicas for read throughput |
| **Primary bottleneck** | Memory bandwidth (HNSW); CPU (IVF distance computation); I/O (DiskANN) |
| **Reference system** | **Milvus 2.x** (open-source, production-grade, FAANG-adopted) |

---

## Decision Drivers: When to Choose a Vector Database

### Choose a vector DB when ALL of the following are true:

| # | Criterion | Threshold |
|---|---|---|
| 1 | **Semantic similarity is the query** | You're asking "find similar items," not "find exact items by ID" |
| 2 | **Scale exceeds brute-force feasibility** | > 1M vectors OR < 100ms latency requirement |
| 3 | **Embeddings are first-class data** | The embedding IS the query, not an auxiliary feature |
| 4 | **Recall is an SLO** | You need ≥ 95% recall@10 measurable and monitorable |
| 5 | **Metadata filtering is required** | You need to filter by attributes at query time (e.g., `category = 'tech' AND date > '2024-01-01'`) |

### Don't choose a vector DB when:

| Scenario | Better Choice | Reason |
|---|---|---|
| < 100K vectors, any scale | **pgvector on PostgreSQL** | ACID transactions, SQL joins, zero operational overhead |
| Full-text search is primary | **Elasticsearch / OpenSearch** | BM25 + inverted index; add vector via `dense_vector` as secondary |
| Sub-millisecond latency | **Redis VSS** (small scale) | In-memory, no ANN graph traversal overhead |
| Strong consistency required | **PostgreSQL + pgvector** | Most vector DBs are AP; pgvector inherits Postgres CP guarantees |
| ML offline batch (no serving) | **FAISS** (library, no server) | No operational overhead; fast batch processing in Python |
| You already have Elasticsearch | **ES `dense_vector` field** | Avoid new infra; hybrid sparse+dense search built in |
| < 10 QPS semantic search | **Any LLM API with cosine in app layer** | Not worth vector DB overhead |

---

## Use Cases

| Use Case | Description | Scale | Latency Req | Recommended Index |
|---|---|---|---|---|
| **RAG / Semantic Search** | Retrieve relevant document chunks for LLM context | 1M–500M chunks | < 200ms p99 | HNSW |
| **Recommendation** | Collaborative / content-based item similarity | 100M–10B items | < 50ms p99 | IVF+PQ or HNSW |
| **Duplicate / Deduplication** | Detect near-identical content (spam, plagiarism) | 10M–1B docs | Batch acceptable | IVF+Binary |
| **Image / Video Similarity** | Visual search, reverse image search | 100M–5B images | < 100ms p99 | HNSW or DiskANN |
| **Anomaly Detection** | Flag embeddings far from cluster centroids | 1M–100M events | Batch or < 500ms | IVF |
| **Multimodal Search** | Cross-modal retrieval (image↔text via CLIP) | 10M–1B items | < 200ms p99 | HNSW |
| **Fraud Detection** | Entity embedding similarity to known fraud patterns | 10M–100M entities | < 50ms p99 | HNSW |
| **Code Search** | Semantic code snippet retrieval | 1M–100M snippets | < 500ms | HNSW |
| **Drug Discovery** | Molecular fingerprint similarity | 100M–10B molecules | Batch or interactive | IVF+PQ |
| **Face Recognition** | Face embedding nearest-neighbor matching | 1M–100M faces | < 100ms p99 | HNSW or Flat (small) |

---

## Anti-Patterns

| Anti-Pattern | Why It's Wrong | What to Do Instead |
|---|---|---|
| Using FLAT index at > 1M vectors | O(n×d) scan — latency blows up linearly | Switch to HNSW or IVF; build FLAT only for benchmarking recall |
| Filtering metadata in application layer after full vector scan | Returns more results than needed; wastes bandwidth | Use in-DB metadata filtering with payload indexes |
| Single massive collection with no partitioning | Hot shards, index build failures, slow recall | Partition by tenant or date range; use collection-level sharding |
| Not normalizing vectors before cosine similarity | Cosine on non-normalized = wrong distances | L2-normalize all vectors at ingestion time; or use inner product after normalization |
| Ignoring dimension count in model selection | ada-002 at 1536d uses 2.5× the RAM of 3-small at 512d | Choose minimum dimension that meets MTEB recall bar |
| Over-engineering with dedicated vector DB at < 100K vectors | Operational overhead not justified | Use pgvector; migrate later |
| Re-embedding on every LLM model upgrade | Breaks existing search relevance silently | Version-stamp embeddings; maintain model registry; backfill before cutover |
| Setting ef_construction too low | Poor index quality, low recall at build time — irreversible without rebuilding | ef_construction ≥ 200 for production (see tuning guide) |
| Querying with nprobe = 1 (IVF default) | 1 cluster probe = ~5% recall | nprobe ≥ nlist/10 for > 90% recall |

---

## Key Numbers at a Glance

| Metric | Value |
|---|---|
| HNSW search latency (10M vectors, d=768, M=32, ef=64) | 1–5ms p99 |
| HNSW search latency (100M vectors, d=1536, M=32, ef=128) | 5–20ms p99 |
| IVF_PQ search latency (1B vectors, nlist=65536, nprobe=128) | 50–200ms p99 |
| DiskANN search latency (1B vectors, beam_width=64) | 20–100ms p99 |
| HNSW memory: per vector (d=768, M=16) | ~100 bytes overhead + 3KB raw |
| HNSW memory: per vector (d=1536, M=32) | ~200 bytes overhead + 6KB raw |
| IVF_PQ memory: per vector (d=1536, m=8, nbits=8) | ~8 bytes compressed + centroid table |
| OpenAI ada-002 embedding cost | $0.10 / 1M tokens |
| OpenAI text-embedding-3-large cost | $0.13 / 1M tokens |
| Milvus throughput: batch insert | 500K vectors/sec (8-core node) |
| Recall@10 achievable with HNSW, ef=200 | 98–99.5% |
| Recall@10 achievable with IVF_PQ, nprobe=64 | 90–95% |

---

## System Comparison Snapshot

> Full deep-dive in [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md)

| System | Type | Open Source | Max Tested Scale | Best For |
|---|---|---|---|---|
| **Milvus** | Dedicated vector DB | ✅ Apache 2.0 | 10B+ vectors | Production, self-hosted, full-featured |
| **Pinecone** | Managed vector DB | ❌ Proprietary | 1B+ vectors | Zero-ops, fast time-to-production |
| **Weaviate** | Dedicated vector DB | ✅ BSD | 1B vectors | Schema-first, built-in ML modules |
| **Qdrant** | Dedicated vector DB | ✅ Apache 2.0 | 1B vectors | Rust performance, best filtering |
| **pgvector** | PostgreSQL extension | ✅ Open source | 100M vectors | Existing Postgres, consistency + SQL |
| **Redis VSS** | In-memory vector | ✅ / ❌ (both) | 100M vectors | Sub-ms, small-medium scale |
| **Elasticsearch** | Search + vector | ✅ / ❌ (both) | 1B+ vectors | Existing ES infra, hybrid sparse+dense |
| **FAISS** | Library (no server) | ✅ MIT | Unlimited (offline) | Research, offline batch, embedding |

---

## FAANG Interview Callout

> **What an interviewer is testing**: Can you recognize that semantic similarity at scale is a distinct engineering problem from relational queries? Do you know the ANN recall/latency trade-off? Can you select the right vector DB given constraints (managed vs self-hosted, scale, filtering complexity, existing infra)?

**30-second pitch**: *"Vector databases solve the k-nearest-neighbor search problem in high-dimensional embedding spaces using approximate index structures like HNSW or IVF. The core trade-off is recall vs latency vs memory. For a RAG system at 10M document chunks, I'd use HNSW with M=32 and ef=128 — that gets p99 < 10ms at 99% recall@10. For billion-scale recommendations, I'd move to IVF-PQ with quantization, accepting 90-95% recall for 8× memory reduction. I'd choose Milvus for a self-hosted production system and Pinecone for fast time-to-production with managed ops."*

---

## File Map

| File | Contents |
|---|---|
| **README.md** ← *you are here* | Overview, decision guide, use cases, anti-patterns, key numbers |
| [01-architecture.md](01-architecture.md) | Similarity metrics, index algorithms (HNSW/IVF/LSH/DiskANN), quantization, Milvus internals, sharding/replication |
| [02-read-write-path.md](02-read-write-path.md) | Ingestion pipeline, search path, metadata filtering strategies, hybrid search, performance optimizations |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | 8-system comparison, 6 deep 1-on-1 pairs, decision flowchart, CAP analysis |
| [04-tuning-guide.md](04-tuning-guide.md) | HNSW/IVF/PQ parameters, hardware sizing, anti-patterns, monitoring metrics |
| [05-production-and-research.md](05-production-and-research.md) | Research papers (HNSW/FAISS/DiskANN/ScaNN), Spotify/LinkedIn/Airbnb/Pinterest production deployments, operational lessons |

### Related Files Across Repository

| File | Relationship |
|---|---|
| [AI/llm-applications/embedding-strategies.md](../../AI/llm-applications/embedding-strategies.md) | Embedding model selection, chunking strategies, RNN→Transformer evolution |
| [AI/llm-applications/vector-retrieval-patterns.md](../../AI/llm-applications/vector-retrieval-patterns.md) | Retrieval patterns (HyDE, hybrid, re-ranking), ingestion pipelines, evaluation |
| [AI/ai-architecture/rag-system-hld.md](../../AI/ai-architecture/rag-system-hld.md) | Full RESHADED HLD for production RAG at 10M docs / 10K QPS |
| [technologies/elasticsearch/](../elasticsearch/) | Elasticsearch dense_vector for hybrid search use case |
| [technologies/redis/](../redis/) | Redis VSS for sub-ms in-memory vector search |
