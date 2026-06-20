# Vector Databases — Production Deployments & Research Foundations

> **Focus**: The foundational research papers that created modern ANN search, how FAANG-scale companies deploy vector search in production, operational lessons learned at scale, and the FAANG interview framing for vector database questions.

---

## Part 1: Foundational Research Papers

### Paper 1: HNSW — Hierarchical Navigable Small World Graphs

**Citation**: Malkov, Y. A., & Yashunin, D. A. (2018). "Efficient and Robust Approximate Nearest Neighbor Search Using Hierarchical Navigable Small World Graphs." *IEEE Transactions on Pattern Analysis and Machine Intelligence (TPAMI)*, 42(4), 824–836.

**arXiv**: https://arxiv.org/abs/1603.09320 (first version 2016, final TPAMI 2018)

**Problem Statement**: Prior Navigable Small World (NSW) graphs achieved good ANN recall but had O(log n × log n) search complexity with a logarithmic "polylog" factor that degraded at large n. The search also exhibited poor cache locality — graph traversal accessed distant memory locations in random order.

**Key Contributions**:
1. **Hierarchical layer structure**: The single NSW graph is decomposed into L layers of increasing sparsity, inspired by skip lists. Layer 0 (dense) contains all vectors. Layer 1 contains a random subset (~1/e of Layer 0). Layer 2 contains ~1/e² of vectors, etc.
2. **O(log n) search complexity**: The sparse upper layers act as a "fast highway" — few well-connected nodes provide long-range navigation. Descent to Layer 0 is the fine-grained exhaustive phase. This reduces the polylog factor to a single log factor.
3. **Separate M per layer**: Layer 0 nodes have 2M edges (denser for recall); upper layer nodes have M edges.
4. **Greedy descent with entry point caching**: The search maintains the best candidate as it descends through layers. Entry point selection from prior queries improves cache efficiency.

**Why it matters for interviews**: HNSW is now the default ANN index in virtually every vector database (Milvus, Weaviate, Qdrant, Elasticsearch, pgvector). Understanding its structure (skip-list hierarchy, why O(log n)) lets you reason correctly about M, ef_construction, ef tuning.

**Recall on benchmarks (2018)**: At 0.9 recall@10 on SIFT-1M (1M 128-d vectors), HNSW achieved 490K QPS on 1 CPU core. Nearest competitor (IVFADC) achieved 60K QPS at same recall — 8× slower.

---

### Paper 2: FAISS — Billion-Scale Similarity Search with GPUs

**Citation**: Johnson, J., Douze, M., & Jégou, H. (2021). "Billion-Scale Similarity Search with GPUs." *IEEE Transactions on Big Data*, 7(3), 535–547.

**Original arXiv**: 2017 (updated 2019).

**Problem Statement**: Existing ANN libraries couldn't efficiently utilize GPU SIMD parallelism. Facebook needed to index billions of image vectors for reverse image search across 2.5B images. CPU-only IVF approaches were too slow for online serving.

**Key Contributions**:
1. **GPU-accelerated k-means**: Implemented k-means on GPU with tile-based matrix multiplication. 5–10× speedup over CPU for IVF centroid training.
2. **Product Quantization (PQ) with GPU ADC**: Asymmetric Distance Computation on GPU — precompute distances to all PQ centroids, then use fast GPU lookup. Enables 1B-scale index in ~64GB GPU RAM.
3. **Hierarchical coarse/fine quantization**: Combine IVF (coarse partitioning) with PQ (fine compression). The IVF+PQ combination (now standard in FAISS as `IndexIVFPQ`) was validated at 1B vectors.
4. **Unified C++/Python API**: Made billion-scale ANN accessible to ML practitioners.

**Production context**: Facebook ran image deduplication, photo organization, and reverse image search across 2.5B photos using FAISS. The FAISS library became the de-facto standard embedded ANN library and powers the index builds in Milvus, Weaviate, and others.

**Interview angle**: *"FAISS isn't just a library — it established the IVF+PQ pattern that underpins most production billion-scale vector databases. When Milvus says it uses `IVF_PQ` index type, it's running FAISS's `IndexIVFPQ` under the hood."*

---

### Paper 3: DiskANN — Serving Billion-Scale ANN from Disk

**Citation**: Jayaram Subramanya, S., Devvrit, F., Simhadri, H. V., Krishnawamy, R., & Kadekodi, R. (2019). "DiskANN: Fast Accurate Billion-point Nearest Neighbor Search on a Single Node." *NeurIPS 2019*.

**Problem Statement**: HNSW requires the entire graph to be in RAM — impossible for 1B vectors at d=128 (requires ~400GB RAM). IVF_PQ can fit in RAM but has lower recall. Is there a way to serve billion-scale ANN from SSD without sacrificing recall?

**Key Contributions**:
1. **Vamana graph**: A new graph construction algorithm optimized for disk layout. Unlike HNSW's random memory access pattern, Vamana builds a graph with local + long-range edges designed for sequential SSD reads.
2. **SSD-resident index with selective RAM caching**: Only hot nodes (frequently accessed during beam search) are cached in RAM. At 1B vectors (d=128): 64GB RAM + 200GB SSD serves queries at ~35ms p99 with 95% recall@10.
3. **Beam search with prefetch**: When visiting a graph node, the algorithm speculatively prefetches the next K likely nodes from SSD before finishing current node's distance computation. Hides SSD latency.
4. **Filtered DiskANN (2023)**: Extended to support metadata filters at query time without recall degradation (similar problem as filtered HNSW).

**Benchmark results**: 1B SIFT vectors (128-d): 95% recall@10 at 35ms p99 on a single server with 64GB RAM + NVMe SSD. HNSW at same recall would require ~400GB RAM.

**Production use**: Microsoft uses DiskANN in Azure AI Search (previously Azure Cognitive Search). Milvus added DiskANN as an index type in Milvus 2.1 for billion-scale disk-resident queries.

---

### Paper 4: ScaNN — Scalable Nearest Neighbor Search

**Citation**: Guo, R., Sun, P., Lindgren, E., Geng, Q., Simcha, D., Chern, F., & Kumar, S. (2020). "Accelerating Large-Scale Inference with Anisotropic Vector Quantization." *ICML 2020*.

**Problem Statement**: Standard PQ minimizes L2 reconstruction error uniformly across all directions. But for inner product (dot product) similarity, the directions that matter most for preserving the ranking (high-inner-product directions) are not uniform. Standard PQ wastes bits representing directions that don't affect the final ranking.

**Key Contribution — Anisotropic Quantization**:
Instead of minimizing `||x - quantize(x)||²` uniformly, weight the error by the contribution to inner product preservation:

```
Loss = Σ_i w(x_i, q) × ||x_i - quantize(x_i)||²

where w(x_i, q) is higher for directions parallel to the query distribution
→ Preserves inner product ranking better than isotropic PQ
→ SOAR improvement: second-pass re-scoring of quantized candidates
```

**Results on BigANN benchmark** (1B 96-d vectors): ScaNN achieves 10× higher QPS than HNSW at 90% recall@10.

**Production at Google**: ScaNN powers:
- Google Search embedding-based retrieval
- Google Photos visual similarity
- YouTube recommendations (two-tower model retrieval)
- Google Assistant entity matching

ScaNN is open-sourced (Apache 2.0) but primarily optimized for Google's hardware (x86 + custom accelerators). Milvus includes a `SCANN` index type.

---

### Paper 5: ANN Benchmarks — The Community Standard

**Citation**: Bernhardsson, E. et al. "ANN Benchmarks: A benchmarking tool for approximate nearest neighbor algorithms." *Information Systems* (2019). http://ann-benchmarks.com

**What it is**: A standardized benchmarking framework comparing ANN algorithms on the same hardware, same datasets (SIFT-1M, GIST-1M, GloVe-100, etc.), measuring the recall vs QPS Pareto frontier.

**Why it matters for interviews**: ANN Benchmarks is the common reference when discussing "which algorithm is fastest at X% recall." Numbers like "HNSW achieves 100K QPS at 95% recall" come from this benchmark.

**Key insight from benchmarks**: No single algorithm dominates all scenarios. HNSW wins at medium scale (< 100M vectors) and moderate recall (90–99%). At billion scale, DiskANN or IVF_PQ (quantized) dominate.

---

## Part 2: Companies Using Vector Databases at Scale

### Spotify — Annoy for Music and Podcast Recommendations

**Scale**: 100M+ songs, 5M+ podcasts (2023)

**System**: Annoy (Approximate Nearest Neighbors Oh Yeah), the library Spotify built and open-sourced.

**Why Annoy and not HNSW**:
- Song catalog is largely static (nightly batch updates, no real-time inserts)
- Annoy supports on-disk indexes — the Spotify playlist recommendation index was too large for RAM
- Random projection trees suit the static rebuild pattern: rebuild overnight, swap in fresh index at midnight
- Read path is heavily parallelized (multiple Annoy trees in parallel), suitable for Spotify's batch serving pattern

**Architecture** (simplified):
```
Nightly batch:
  User interaction data → collaborative filtering → item embeddings
  Item embeddings (100M vectors) → Annoy index build (4 hours)
  
Serving:
  User profile embedding → Annoy query → top-K candidates
  Candidates → re-scoring (feature store + audio features)
  → Recommendations served
```

**Operational lesson**: Annoy's lack of incremental insert support meant that new songs weren't in recommendations until the next nightly rebuild. This was acceptable for Spotify's latency budget but would not work for a real-time use case (e.g., user's own uploaded content).

**What Spotify would use today**: HNSW in Qdrant or Weaviate, with incremental insert support for new tracks.

---

### LinkedIn — FAISS Two-Tower for People and Job Recommendations

**Scale**: 900M+ members, 15M+ job listings (2023)

**System**: Custom FAISS deployment

**Use case**: Two-tower recommendation — train a neural network where one tower embeds users, another embeds jobs/people. At serving time, find the top-K most relevant jobs/people for a given user embedding via ANN.

**Architecture**:
```
Offline:
  Two-tower model training (user tower, item tower)
  → Item embeddings for all 15M+ jobs
  → FAISS IVF_PQ index built (batch, ~1 hour)

Serving:
  User request → user tower inference → user embedding
  → FAISS IVF_PQ query → top-500 candidates
  → Ranking model (point-wise scoring) → top-20 shown to user
```

**Scale specifics**: LinkedIn reported (2020 blog) serving 100M+ FAISS queries per day. At 15M items, IVF_PQ fits comfortably in memory of a modern server.

**Key design decision**: Two-stage retrieval. FAISS for first-stage recall (fast, approximate), gradient-boosted tree ranking model for second-stage precision (slower, exact features). This mirrors the standard recommendation system architecture at all FAANG companies.

---

### Airbnb — Listing Similarity and Neighborhood Embeddings

**Scale**: 8M+ active listings (2023)

**System**: Custom FAISS embedding layer, later migrated to dedicated vector DB

**Use cases**:
1. **Listing similarity** ("Similar homes you might like"): listing embedding based on location, amenities, guest reviews. FAISS cosine similarity retrieval.
2. **Neighborhood vectors**: embed neighborhoods (not just individual listings) to enable "homes in similar neighborhoods" recommendations.
3. **Real-time upsert**: New listings must appear in search within minutes. (This was a key limitation of FAISS batch approach.)

**Listing embedding generation**:
- Listing2Vec: trained on click-stream data (which listings users click in sequence → word2vec-style training)
- Features: location (lat/lon bucketed), amenity features, host features
- Final embedding: multi-modal fusion of text + structured features + location

**Real-time challenge**: Unlike Spotify (static catalog), Airbnb has active hosts adding/removing listings in real time. This drove migration from FAISS batch to a vector DB with streaming insert support.

---

### DoorDash — Store and Item Embeddings for Discovery

**Scale**: 700K+ merchant partners, 100M+ menu items (2023)

**System**: Pinecone (managed), migrated from custom FAISS

**Use cases**:
1. **Restaurant discovery**: embed each store's cuisine profile, location context, menu diversity
2. **Item recommendation**: cold-start items (new stores) handled via metadata similarity to similar items
3. **Search ranking**: vector similarity as one signal in multi-feature ranking model

**Why Pinecone over self-hosted Milvus**:
- Small ML infra team (5–10 engineers) — no capacity to operate Milvus cluster
- 700K stores × ~100-d embedding = 70M vectors × 4B = 28 GB — easily managed in Pinecone
- Time-to-production was measured in days, not months

**Operational lesson**: For teams < 20 ML engineers, managed vector DB is usually the right call. The operational overhead of self-hosted Milvus (etcd, Pulsar, MinIO, coordination layer) typically requires a dedicated platform team.

---

### Pinterest — PinSage GNN at 3 Billion Pins

**Scale**: 3B+ pins (2023)

**System**: Custom HNSW via FAISS, now partially on Milvus

**Use case**: Visual and content similarity for "More Like This" and homefeed recommendations.

**Key innovation — PinSage**: 
- Graph Neural Network applied to the Pinterest graph (users, boards, pins as nodes; interactions as edges)
- At 3B nodes, standard GNN is infeasible. PinSage uses importance-based neighbor sampling: for each pin, sample the K most influential graph neighbors (not all neighbors)
- Produces rich 256-d embeddings that encode visual + textual + social graph context

**Paper**: Hamilton, W., Ying, R., & Leskovec, J. (2017). "Inductive Representation Learning on Large Graphs." *NeurIPS 2017*. (PinSage extends this for Pinterest scale.)

**Architecture**:
```
Offline embedding pipeline (weekly batch):
  3B pins → PinSage GNN training → 256-d embeddings
  → HNSW index build (distributed FAISS, ~12 hours)
  
Serving:
  Current pin → embedding lookup → ANN query → top-K candidates
  → Reranking (engagement prediction model) → served recommendations
```

**Scale challenge**: Building an HNSW index over 3B vectors is a distributed engineering problem. Pinterest ran distributed FAISS: partition corpus into 30 shards × 100M vectors each, build HNSW per shard in parallel, shard-route queries by approximate nearest centroid.

---

### OpenAI — Azure AI Search as Vector Layer for GPT Applications

**Scale**: Millions of developers; billions of documents indexed across API users

**System**: Azure AI Search (Microsoft's managed vector search, backed by DiskANN internally)

**Use cases**:
- GPT plugins and Assistants: when users connect data sources (uploaded PDFs, SharePoint, etc.), OpenAI Assistants use vector search to retrieve relevant context
- API file retrieval: OpenAI's file-based retrieval feature embeds and indexes user-uploaded files

**Why Azure AI Search over Pinecone/Milvus**: Deep Azure/Microsoft integration; DiskANN enables billion-scale disk-resident index without RAM explosion; enterprise compliance features (RBAC, audit logs, data residency).

**Operational note**: OpenAI does not rely on a single vector DB vendor internally. Their production retrieval infrastructure uses multiple systems depending on context, including FAISS-based internal services for ChatGPT web browsing retrieval.

---

### Uber — Semantic Search over Internal Services

**Scale**: Tens of millions of internal documents, service registry entries, code snippets

**System**: Weaviate (as of 2023 internal blog)

**Use cases**:
1. **Service discovery**: semantic search over Uber's 10K+ internal microservices — "find the service that handles driver payments"
2. **Incident management**: semantic search over past incident reports to find similar incidents
3. **Code search**: embedding Uber's internal codebase (Go/Python/Java) for developer tooling

**Why Weaviate**: GraphQL API aligned with Uber's developer tooling conventions; built-in text2vec modules simplified embedding pipeline; multi-tenancy support for different Uber internal teams.

---

## Part 3: Operational Lessons at Scale

### Lesson 1: Recall Monitoring is Non-Negotiable

Recall degrades silently in production. Sources of drift:
- **Document distribution shift**: your corpus expands into new topics that are underrepresented in the original index
- **Embedding model upgrade**: new model version changes vector space; old index now maps to wrong embedding space
- **Index build failure**: silently corrupted index due to OOM during build — queries return results, but recall is degraded
- **Quantization regression**: PQ codebooks trained on early data don't represent later data distribution

**Solution**: Weekly automated recall@10 evaluation on a held-out set of 200–500 real queries with labeled relevance. Alert on > 5% recall drop from baseline.

### Lesson 2: Embedding Model Upgrades Require Full Re-Indexing

There is no incremental migration path for embedding model changes. When you upgrade:
1. All existing vectors are in the old embedding space
2. New queries use the new embedding space
3. New query vectors have cosine similarity ≈ 0 with old document vectors (different spaces)

**The "stale embedding" failure mode**: A new embedding model is deployed for query encoding, but the indexed document embeddings haven't been re-ingested. Users report that search is returning irrelevant results. This can take weeks to diagnose if there's no embedding model version metadata stored with each vector.

**Fix**: Store `model_version` as metadata on every vector. At query time, reject or re-route queries where `model_version` doesn't match the active embedding model.

### Lesson 3: Cold-Start Performance After Deployment

After a new deployment or QueryNode restart, the first queries against any collection are dramatically slower (~10–30 seconds) due to S3 segment load time. This causes latency spikes that look like regressions in monitoring.

**Standard mitigation**:
1. Warm-up script runs immediately post-deploy: 100–500 random queries against all loaded collections
2. Kubernetes readiness probe: pod is only marked Ready after warm-up completes
3. Progressive traffic shift: 0% → 5% → 25% → 100% over 15 minutes (allows warm-up under low load)

### Lesson 4: Segment Count Sprawl

Systems with high insert rates and frequent small batches accumulate thousands of tiny segments. At 100K segments:
- QueryCoord metadata queries become slow
- Compaction runs constantly (high CPU/IO)
- Search routes to too many segments in parallel (fan-out overhead)

**Fix**: Set `segment.smallSegmentThreshold` in Milvus (segments below this size are merged). Set seal threshold high enough that segments are at least 500K rows before sealing. Monitor segment count metric.

### Lesson 5: The Re-Ranking Latency Budget

A common mistake: adding a cross-encoder re-ranker without budgeting the latency impact.

```
Example latency budget:
  ANN retrieval:    10ms p99
  Cross-encoder:    150ms p99 (100 candidates × BGE-reranker-large)
  LLM generation:  1000ms p99
  ─────────────────────────
  Total:            1160ms p99

With re-ranker: 1160ms (acceptable if SLO = 2s)
Without:         1010ms

Trade-off: +150ms for significantly better retrieval precision
→ Always measure re-ranking latency before deploying; batch cross-encoder calls
```

---

## Part 4: FAANG Interview Framing

### Angle 1: System Design — "Design a semantic search system for 10M documents"

Key components the interviewer expects:
1. **Embedding pipeline**: document → chunking → embedding model → batch insert
2. **Vector DB selection**: HNSW index, why (recall/latency trade-off), Milvus vs Pinecone
3. **Search pipeline**: query → query embedding → ANN search → metadata filter → re-rank → LLM
4. **Capacity estimation**: 10M chunks × 1536d × 4B = 61GB; HNSW overhead adds 4GB; 2 QueryNodes at 64GB sufficient
5. **Recall/latency**: M=32, ef=128 → 98% recall@10 at < 10ms p99
6. **Failure modes**: embedding model upgrade (full re-index), recall drift, cold start, delete lag

### Angle 2: Index Selection — "How would you handle 1B vectors?"

**Expected answer trace**:
- HNSW: 1B × 1536d × 4B + graph overhead ≈ 7TB RAM → impossible on single machine
- IVF_PQ: nlist=65536, m=192, nbits=8 → 192 bytes/vector → 192GB for raw + 512MB centroids → feasible on 3-node cluster (64GB each with PQ)
- DiskANN: 1B vectors, disk-resident Vamana graph → 64GB RAM + 400GB NVMe SSD → single machine feasible at 35ms p99
- Sharded HNSW: 10 shards × 100M vectors each → HNSW per shard → 700GB total RAM across 10 nodes → expensive but best recall

### Angle 3: Filtering — "How do you handle searches with metadata filters?"

**Expected answer** (see [02-read-write-path.md](02-read-write-path.md) Part 3):
- Post-filtering (simple, recall degrades at < 10% selectivity)
- Pre-filtering with bitset (Milvus) — good at > 5% selectivity
- ACORN filtered-ANN (Weaviate) — maintains recall at < 1% selectivity
- Partition-based routing (Milvus partition keys) — converts filter to routing for tenant_id

### Angle 4: Embedding Model Selection

**Expected answer trace** (see [AI/llm-applications/embedding-strategies.md](../../AI/llm-applications/embedding-strategies.md)):
- Start with text-embedding-3-small (cheap, MRL flexible dimensions, 62 MTEB)
- Evaluate recall@10 on held-out test set
- If recall insufficient → try text-embedding-3-large or voyage-3
- If domain mismatch → fine-tune with sentence-transformers + in-domain pairs

### Angle 5: Recall Monitoring

**Expected answer**: Maintained held-out eval set (200–1000 real queries with labeled relevant docs). Weekly automated recall@10 computation. Alert on > 5% drop. Store model_version metadata on vectors to detect stale embedding regressions.

---

## FAANG Interview Callout

> **The 3-minute vector DB answer that covers all bases**:

*"Vector databases solve approximate nearest-neighbor search in high-dimensional embedding space. The dominant production algorithm is HNSW — a hierarchical navigable small world graph that achieves O(log n) query complexity. For 10M vectors at 1536d, I'd use Milvus with HNSW (M=32, ef=128) on 2 QueryNodes (64GB RAM each with SQ8 quantization). This gives 98% Recall@10 at < 10ms p99.*

*At billion scale, HNSW's RAM requirements (~7TB for 1B 1536-d vectors) force a different approach: DiskANN (disk-resident, 35ms p99, 64GB RAM) or IVF_PQ (192GB RAM, 95% recall with nlist=65536, nprobe=128).*

*The hardest production problem is metadata filtering at low selectivity (< 1%). Post-filtering fails because few ANN candidates survive the filter. The solution is ACORN filtered-ANN (Weaviate) or Milvus partition keys for tenant-scoped search. I'd also monitor Recall@10 weekly — it drifts silently as corpus grows or when embedding models are upgraded.*

*For the application layer: two-stage retrieval — bi-encoder ANN (fast, high recall) → cross-encoder re-ranker (slow, high precision) → top-10 for LLM context. HyDE (hypothetical document embedding) improves recall for complex questions where query→document vocabulary mismatch is high."*

---

## Related Files

- [README.md](README.md) — overview, decision guide, use cases, anti-patterns
- [01-architecture.md](01-architecture.md) — HNSW/IVF/PQ internals, Milvus architecture
- [02-read-write-path.md](02-read-write-path.md) — ingestion pipeline, search path, filtering
- [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) — 8-system comparison, decision flowchart
- [04-tuning-guide.md](04-tuning-guide.md) — HNSW/IVF/PQ parameter tuning, hardware sizing
- [../../AI/llm-applications/embedding-strategies.md](../../AI/llm-applications/embedding-strategies.md) — embedding model selection and chunking strategies
- [../../AI/llm-applications/vector-retrieval-patterns.md](../../AI/llm-applications/vector-retrieval-patterns.md) — retrieval patterns, re-ranking, ingestion pipelines
- [../../AI/ai-architecture/rag-system-hld.md](../../AI/ai-architecture/rag-system-hld.md) — full production RAG HLD
