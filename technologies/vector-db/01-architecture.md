# Vector Databases — Architecture Deep Dive

> **Focus**: How vector databases represent similarity, how ANN index structures work internally, how Milvus is architected for production, and how systems scale horizontally. This is the "why does it work this way" document.

---

## Part 1: Similarity Metrics

Before indexing, you must choose a distance function. This choice locks in how the index is built and cannot be changed without rebuilding.

### The Four Production Metrics

**Cosine Similarity** — angle between vectors, ignoring magnitude

$$\text{cos}(A, B) = \frac{A \cdot B}{\|A\| \cdot \|B\|}$$

- Range: [-1, 1]; higher = more similar
- **Use when**: Embeddings from language models (BERT, OpenAI) — text meaning lives in direction, not magnitude
- **Tip**: If you L2-normalize all vectors at insert time, cosine similarity = inner product, which is faster to compute (no normalization at query time)
- FAISS / Milvus optimization: store pre-normalized vectors and use `METRIC_IP` — eliminates per-query normalization

**L2 / Euclidean Distance** — straight-line geometric distance

$$d(A, B) = \sqrt{\sum_{i=1}^{d}(A_i - B_i)^2}$$

- Range: [0, ∞); lower = more similar
- **Use when**: Image embeddings, coordinate-based embeddings, when absolute magnitude carries meaning (e.g., topic intensity)
- **Caution**: Suffers from the curse of dimensionality — at d > 100, distances concentrate; all points become "equidistant"

**Inner Product / Dot Product** — projection of one vector onto another

$$\text{IP}(A, B) = A \cdot B = \sum_{i=1}^{d} A_i \cdot B_i$$

- Range: (-∞, ∞); higher = more similar
- **Use when**: Recommendation models trained with softmax loss (YouTube DNN, DSSM), where magnitude carries relevance signal
- **Caution**: Not a proper metric (violates triangle inequality); can produce non-intuitive results with unnormalized vectors

**Hamming Distance** — number of bit positions that differ

$$d_H(A, B) = \sum_{i=1}^{d} A_i \oplus B_i$$

- Range: [0, d]; lower = more similar
- **Use when**: Binary quantized embeddings, DNA sequences, perceptual hashing, fingerprinting
- **Advantage**: POPCOUNT instruction on x86 — extremely fast; 64 bits in one CPU cycle

### Metric Selection Decision

```
Is magnitude meaningful in your embedding space?
├── Yes → Inner Product (IP)
└── No  → Are vectors normalized or will you normalize?
         ├── Normalized → either Cosine or IP (equivalent; use IP for speed)
         └── Not normalized, magnitude irrelevant → Cosine
         
Do you have binary-quantized embeddings?
└── Yes → Hamming

Are you doing image geometry / spatial coordinates?
└── Yes → L2 / Euclidean
```

---

## Part 2: ANN Index Algorithms

### The Fundamental Problem

Given a database of n vectors in ℝᵈ, find the k vectors closest to a query vector q.

**Exact KNN** complexity:
- Build: O(n × d) to load data
- Query: O(n × d) per query — linear scan
- This is FAISS's `IndexFlatL2` — correct by definition, used as recall baseline

**Why ANN instead of exact KNN?** At n=100M, d=1536:
- Exact scan: 100M × 1536 × 4 bytes = 614 GB of memory reads per query
- At 1000 QPS: 614 TB/s memory bandwidth — impossible
- HNSW query: ~1000 distance computations per query (~3KB) — 200,000× fewer

---

### Index Algorithm 1: FLAT (Brute Force)

```
Build: O(n × d)   Query: O(n × d)   Memory: n × d × sizeof(float)
Recall: 100%      Suitable scale: < 500K vectors
```

**Mechanism**: Store all vectors raw; scan all at query time using SIMD.

**FAISS implementation**: `IndexFlatL2`, `IndexFlatIP`

**When to use**:
- Recall benchmarking baseline — define your recall target by comparing other indices to FLAT
- < 100K vectors where HNSW overhead (memory, build time) exceeds benefit
- GPU-accelerated batch search where GPU memory holds entire index

**Production anti-pattern**: FLAT at 10M+ vectors in a latency-sensitive path.

---

### Index Algorithm 2: IVF (Inverted File Index)

```
Build: O(n × k-means iterations)  Query: O(nprobe × n/nlist × d)
Recall: 85–98%   Suitable scale: 1M–1B vectors (with PQ)
Memory: ~same as raw vectors (without PQ)
```

**Mechanism**: Partition the vector space into `nlist` Voronoi cells using k-means clustering. Each vector is assigned to its nearest centroid. At query time, search only the `nprobe` closest centroids and their member vectors.

```
Training phase (offline):
  vectors → k-means(k=nlist) → nlist centroids

Insert phase:
  vector v → find nearest centroid c → add v to inverted list[c]

Query phase:
  query q → find nprobe nearest centroids
          → search all vectors in those nprobe inverted lists
          → return top-K overall
```

**Parameters**:

| Parameter | Effect | Recommendation |
|---|---|---|
| `nlist` | Number of clusters (Voronoi cells) | `√n` as starting point; 4096 for 10M vectors, 65536 for 1B |
| `nprobe` | Clusters to search at query time | 16–128 for production; higher = better recall, higher latency |
| Training data | Vectors used for k-means | Must be ≥ 39 × nlist (Faiss requirement); use representative sample |

**Memory**: O(nlist × d × 4 bytes) for centroids + O(n × d × 4 bytes) for vectors. No compression.

**Critical insight**: IVF quality degrades when clusters are unbalanced. Hot categories create oversized inverted lists → higher nprobe needed for those queries. Monitor list size distribution.

**IVF_FLAT vs IVF_PQ vs IVF_SQ**:

| Variant | Storage | Recall vs IVF_FLAT | Build Time | Use Case |
|---|---|---|---|---|
| IVF_FLAT | 100% (raw) | 100% (baseline) | Fast | Medium scale, good recall |
| IVF_SQ8 | 25% (INT8) | 99%+ | Fast | 4× compression, near-lossless |
| IVF_PQ | 4–8% (PQ codes) | 90–95% | Slow (PQ training) | Billion-scale, memory-constrained |

---

### Index Algorithm 3: HNSW (Hierarchical Navigable Small World)

```
Build: O(n × M × log n)    Query: O(log n)
Recall: 95–99.5%            Suitable scale: 1M–100M vectors
Memory: n × M × 2 × 4 bytes (graph edges) + n × d × 4 bytes (vectors)
```

This is the **production default** for recall-critical, latency-sensitive workloads.

**Origins**: Malkov & Yashunin (2018). Extended Navigable Small World graphs with a hierarchical multi-layer structure inspired by skip lists.

**Mechanism**:

```
Layer structure (skip-list analogy):
  Layer 2 (sparse):  ●─────────────●─────────────●
  Layer 1 (medium):  ●──●──────●───●──●─────●────●
  Layer 0 (dense):   ●●●●●●●●●●●●●●●●●●●●●●●●●●●●

Insert vector v:
  1. Randomly assign entry layer l (exponential decay probability)
  2. Starting from layer max_layer, greedily navigate to nearest neighbor
  3. At each layer, connect v to M nearest neighbors found by beam search
  4. Store bidirectional edges (M per layer, 2M at layer 0)

Search query q:
  1. Enter at top layer (usually 1 vector)
  2. Greedy descent: at each layer, move to nearest neighbor, repeat
  3. At layer 0: expand beam search using priority queue of size ef
  4. Return top-K from the ef explored candidates
```

**Parameters**:

| Parameter | Meaning | Recommended Range | Effect |
|---|---|---|---|
| `M` | Max edges per node per layer | 16–64 | Higher M → better recall, more memory, slower build |
| `ef_construction` | Beam size during index build | 100–500 | Higher → better index quality, slower build |
| `ef` / `ef_search` | Beam size during query | 50–500 | Higher → better recall, higher query latency |

**Memory formula**:
```
HNSW memory = n × (M × 2 × sizeof(int32)) + n × d × sizeof(float)
            = n × (M × 8) + n × d × 4  bytes

Example: n=10M, d=768, M=32
  = 10M × (32 × 8) + 10M × 768 × 4
  = 2.56 GB (graph) + 30.72 GB (vectors) = 33.28 GB
```

**Why HNSW beats IVF at medium scale** (10M–100M):
- IVF: recall depends on nprobe; more nprobe = more vectors scanned = linear latency
- HNSW: O(log n) navigation — doubling n adds ~1ms, not 2× latency
- HNSW is cache-friendlier: follows a small path through graph vs scanning inverted list blocks

**HNSW weaknesses**:
- High memory: no compression in vanilla HNSW (addressed by HNSW+PQ in Milvus)
- Build time: slow for very large datasets (DiskANN faster at 1B+)
- Non-deterministic recall: graph quality varies with ef_construction; low ef_construction is irreversible

**FAANG callout**: *"HNSW is the industry default for latency-sensitive, moderate-scale (up to ~100M vector) use cases. The M and ef parameters are the main tuning levers. In production, I'd set M=32, ef_construction=256, ef=128 and measure recall@10 against FLAT baseline. If recall < 98%, increase ef. If latency > SLO, decrease ef or use IVF_PQ."*

---

### Index Algorithm 4: LSH (Locality Sensitive Hashing)

```
Build: O(n × L × k)    Query: O(L × k + bucket_size × d)
Recall: 70–90%          Suitable scale: 1M–1B vectors
Memory: O(n × L) hash tables
```

**Mechanism**: Project vectors through L random hyperplanes; vectors in the same bucket are likely similar. Hash collision probability is a monotone function of cosine similarity.

```
For each of L hash tables:
  - Generate k random hyperplanes h1..hk
  - For vector v: hash = [sign(v·h1), sign(v·h2), ..., sign(v·hk)]
  - Bucket by this k-bit hash string

Query: compute hash for q, look up bucket in each table, merge candidates
```

**Why LSH has fallen out of favour in production**:
- Lower recall than HNSW at same QPS
- Difficult to tune (L and k interact non-linearly with recall)
- Superseded by HNSW for RAM-resident indexes
- Still used in: deduplication pipelines (MinHash LSH), document fingerprinting, streaming systems where approximate recall is sufficient

---

### Index Algorithm 5: Annoy (Approximate Nearest Neighbors Oh Yeah)

```
Build: O(n × n_trees × log n)   Query: O(n_trees × log n)
Recall: 90–97%                   Suitable scale: 1M–100M
Memory: ~2× raw vector size
```

**Created by**: Spotify (Erik Bernhardsson, 2013). Still used in production for music and podcast recommendations.

**Mechanism**: Build a forest of `n_trees` binary space-partitioning trees. Each tree is built by randomly picking two points, splitting by the hyperplane equidistant between them, recursively partitioning.

```
Build:
  For each tree:
    pick random points p1, p2
    split plane: vectors closer to p1 go left, p2 go right
    recurse to depth log2(n/leaf_size)

Query:
  Traverse all n_trees, collecting candidates from all matching leaves
  Compute exact distances for candidates, return top-K
```

**Annoy vs HNSW**:

| Dimension | Annoy | HNSW |
|---|---|---|
| Build time | Faster | Slower |
| Memory | Lower (on-disk support) | Higher (graph edges) |
| Query recall | 90–97% | 95–99.5% |
| Incremental insert | Not supported (rebuild tree) | Supported |
| Best use case | Static datasets, read-heavy, memory-constrained | Dynamic inserts, low latency |

**Spotify's case**: 100M+ songs and podcasts; nightly batch rebuild of Annoy index; no incremental inserts needed.

---

### Index Algorithm 6: DiskANN / ScaNN (Billion-Scale)

#### DiskANN (Microsoft Research, 2019)

```
Suitable scale: 1B–10B vectors
Memory: 64–128 GB RAM for 1B d=128 vectors (vs 600+ GB for HNSW)
Latency: 20–100ms p99 at 1B vectors (beam_width=64)
```

**Key insight**: Store graph on SSD, cache only hot nodes in RAM. The Vamana graph construction algorithm builds a navigable small world graph on disk rather than RAM.

- **Vamana algorithm**: Similar to HNSW but optimized for disk layout; uses a greedy construction with long-range edges to reduce SSD I/O per query
- **Beam search with prefetch**: Speculative SSD reads allow next-hop nodes to be prefetched while current distance is computed
- **Used by**: Bing (web-scale image search), large e-commerce product search

#### ScaNN (Google Research, 2020)

**Key innovation**: Anisotropic quantization — instead of minimizing L2 error across all dimensions equally, weight dimensions proportional to their contribution to inner product. This preserves the recall-critical signal in the compressed representation.

- Also introduces SOAR (second-pass re-ranking) to recover recall after quantization
- Powers Google Search, Google Photos, YouTube recommendations
- Open-sourced in 2020; supports up to 1B vectors on a single machine

---

### Index Algorithm Comparison Table

| Algorithm | Build Complexity | Query Complexity | Recall | Memory | Scale Sweet Spot | Dynamic Inserts | Best Use |
|---|---|---|---|---|---|---|---|
| FLAT | O(n×d) | O(n×d) | 100% | n×d×4B | < 500K | ✅ trivial | Recall baseline |
| IVF_FLAT | O(n×k-means) | O(nprobe×n/nlist×d) | 85–98% | n×d×4B | 1M–100M | ⚠️ re-cluster | Medium scale |
| IVF_PQ | O(n×k-means+PQ) | O(nprobe×n/nlist×m) | 85–95% | n×(m×log₂nbits)B | 100M–10B | ⚠️ re-cluster | Billion-scale, memory constrained |
| HNSW | O(n×M×log n) | O(log n) | 95–99.5% | n×(M×8+d×4)B | 1M–100M | ✅ supported | Production default |
| LSH | O(n×L×k) | O(L×k+bucket×d) | 70–90% | O(n×L) | 1M–1B | ✅ | Deduplication, streaming |
| Annoy | O(n×trees×log n) | O(trees×log n) | 90–97% | 2×n×d×4B | 1M–100M | ❌ rebuild | Static read-heavy |
| DiskANN | O(n×log n) on disk | O(beam×SSD latency) | 95–99% | ~64GB/1B vecs | 1B–10B | ⚠️ complex | Billion-scale, disk-resident |
| ScaNN | O(n×PQ+graph) | O(log n+SOAR pass) | 97–99% | moderate | 100M–1B | ⚠️ | Google-scale, IP metric |

---

## Part 3: Quantization Techniques

Quantization compresses floating-point vectors to reduce memory footprint and speed up distance computations. The fundamental trade-off: **compression ratio vs recall loss**.

### Floating-Point Precision Reduction

```
FP32 → FP16:  2× size reduction, negligible recall loss (< 0.5%)
FP32 → INT8:  4× size reduction, ~1–2% recall loss (depends on distribution)
FP32 → Binary: 32× size reduction, significant recall loss (15–30%)
```

### Scalar Quantization (SQ)

Map each float dimension linearly to an integer range.

```python
# SQ8 example: map each dimension to [0, 255]
min_val, max_val = vector.min(), vector.max()
quantized = ((vector - min_val) / (max_val - min_val) * 255).astype(uint8)

# At query time: approximate distance using uint8 arithmetic
```

- **Memory**: 4× reduction (FP32 → INT8)
- **Recall loss**: < 1% for well-distributed embeddings
- **Speed**: AVX-512 processes 64 INT8 values per instruction vs 16 FP32
- **Milvus**: `IVF_SQ8`, `HNSW_SQ8` — recommended as first compression step

### Product Quantization (PQ)

Split the d-dimensional vector into m sub-vectors of d/m dimensions each. Cluster each sub-space into 2^nbits centroids independently. Store only the centroid index (nbits bits) per sub-space.

```
Original vector (d=1536, FP32): 6144 bytes

PQ encoding (m=192 sub-spaces, nbits=8, i.e., 256 centroids per sub-space):
  1536/192 = 8 dims per sub-space
  192 × 8 bits = 192 bytes per vector (32× compression!)

Distance approximation (ADC - Asymmetric Distance Computation):
  For query q, precompute distances to all 256 centroids in each sub-space
  → 192 lookup tables of 256 entries = 49,152 lookups total
  Per vector: 192 table lookups + 192 additions (vs 1536 multiplications)
```

**PQ Parameters**:

| Parameter | Typical Values | Effect |
|---|---|---|
| `m` (sub-spaces) | 8, 16, 32, 64, 96, 192 | More sub-spaces → better recall, more memory for centroid tables |
| `nbits` | 8 (standard), 4 (aggressive) | 8-bit PQ is standard; 4-bit further 2× compression, more recall loss |

**PQ recall guidance**:
- d/m ≥ 4 (minimum 4 dims per sub-space for enough information per codebook)
- SQ8 first, PQ only if memory budget still requires it
- Always evaluate recall@10 vs FLAT after adding PQ

### Binary Quantization (BQ)

Map each float to a single bit based on sign (or threshold).

```
BQ: vector[i] > 0 → 1, else → 0
Hamming distance replaces float distance
32× compression (1536 FP32 → 48 bytes)
```

- **Use case**: Pre-filtering candidate set → then re-score with original floats
- **Not suitable as sole index** unless embedding model was trained with binary quantization in mind (e.g., Cohere embed-v3 with int8/binary output)

### Compression Comparison

| Technique | Memory Factor | Typical Recall Loss | Build Overhead | Production Use |
|---|---|---|---|---|
| None (FP32) | 1× | 0% | None | < 100M, memory available |
| FP16 | 0.5× | < 0.5% | Minimal | Moderate scale |
| SQ8 (INT8) | 0.25× | 0.5–2% | Low | Good first step |
| PQ (m=32, nbits=8) | 0.083× | 3–8% | High (training) | Billion-scale |
| PQ (m=64, nbits=8) | 0.167× | 2–5% | High | Better recall vs m=32 |
| Binary | 0.03× | 15–30% | Low | Pre-filter only |

---

## Part 4: Milvus Architecture (Reference Implementation)

Milvus 2.x is the reference production system — a distributed, cloud-native vector database with complete separation of storage, compute, and coordination.

### System Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                          CLIENT LAYER                              │
│   SDK (Python/Java/Go/Node) → gRPC → Load Balancer → Proxy        │
└────────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────▼──────────────────────────────────┐
│                       COORDINATION LAYER                           │
│  RootCoord   DataCoord    QueryCoord    IndexCoord                 │
│  (schema,    (segment     (query        (index build               │
│   DDL,        lifecycle,   routing,      scheduling,               │
│   TSO)        data flow)   load balance) priority)                 │
└─────────────┬──────────────────────────────────────┬───────────────┘
              │                                       │
┌─────────────▼───────────┐          ┌────────────────▼──────────────┐
│       DATA LAYER        │          │       QUERY LAYER             │
│  DataNode               │          │  QueryNode                    │
│  - Receives inserts      │          │  - Holds segments in memory  │
│  - Writes to WAL         │          │  - Executes ANN search        │
│  - Flushes to growing    │          │  - Vector + scalar filter     │
│    segments              │          │  - Returns results to proxy   │
│  - Triggers seal at      │          │                               │
│    threshold             │          │  IndexNode                   │
│  - Compaction            │          │  - Builds HNSW/IVF indexes    │
│                         │          │  - CPU/GPU accelerated        │
└─────────────────────────┘          └───────────────────────────────┘
              │                                       │
┌─────────────▼───────────────────────────────────────▼──────────────┐
│                       STORAGE LAYER                                 │
│  Message Queue (Pulsar / Kafka):  WAL, streaming replication       │
│  Object Store (S3 / MinIO):       Sealed segments, index files     │
│  Metadata Store (etcd):           Schema, collection metadata      │
│  KV Store (RocksDB/etcd):         Small metadata, stats            │
└─────────────────────────────────────────────────────────────────────┘
```

### Segment Lifecycle

Segments are the fundamental storage unit. Understanding the segment lifecycle is key to understanding Milvus data flow.

```
INSERT → Growing Segment → [seal threshold] → Sealed Segment
                                                      │
                                               [index trigger]
                                                      ▼
                                              Indexed Segment ──→ Loaded to QueryNode
```

| Segment State | Description | Search Behavior |
|---|---|---|
| **Growing** | Actively receiving inserts; in-memory buffer (DataNode) | Searched by brute force; no index yet |
| **Sealed** | Full (≥ configured threshold, default 1M rows); flushed to S3 | Waiting for index build |
| **Indexed** | Index built by IndexNode; stored in S3 | Loaded to QueryNode on demand |
| **Flushed** | Persisted to object store; index ready | Not yet loaded |
| **Loaded** | Index + raw vectors in QueryNode memory | Fully searchable via ANN |
| **Released** | Unloaded from QueryNode | Not searchable (must reload) |

### Coordination Layer Components

**RootCoord** — Global metadata manager
- Maintains schema (collection definitions, field types, indexes)
- Issues Timestamps (TSO — Time Stamped Oracle) for MVCC
- Handles DDL (CREATE/DROP/ALTER collection)
- Single master; uses etcd for persistent state

**DataCoord** — Segment lifecycle manager
- Tracks which DataNode owns which growing segment
- Triggers seal when segment reaches capacity threshold
- Assigns segment IDs; coordinates compaction
- Maintains segment stats (row count, size)

**QueryCoord** — Query routing and load balancing
- Maintains which QueryNode holds which indexed segment
- Routes search requests to appropriate QueryNodes
- Handles segment handoff (DataNode → QueryNode)
- Load balancing: distributes segments across QueryNodes based on memory

**IndexCoord** — Index build scheduling
- Watches for newly sealed segments
- Schedules index build jobs on IndexNodes
- Maintains index build status
- Persists index metadata to etcd

### Write Path Summary

```
1. Client calls collection.insert(vectors, metadata)
2. Proxy receives request, validates schema, routes to DataNode
3. DataNode writes to WAL (Pulsar/Kafka message queue)
4. DataNode buffers in growing segment (memory)
5. When growing segment reaches threshold (default: 1M rows or 512MB):
   - DataCoord marks segment as "sealed"
   - DataNode flushes raw data to S3 (binlog format)
6. IndexCoord detects new sealed segment:
   - Dispatches index build to available IndexNode
7. IndexNode reads binlogs from S3, builds HNSW/IVF index
8. IndexNode writes index files back to S3
9. IndexCoord notifies QueryCoord: new index ready
10. QueryCoord loads index from S3 to a QueryNode
11. Segment is now fully searchable via ANN
```

### Read Path Summary

```
1. Client calls collection.search(query_vectors, top_k, params)
2. Proxy fetches routing info from QueryCoord
3. Proxy fans out search to all QueryNodes holding relevant segments
4. Each QueryNode searches its loaded segments (ANN + metadata filter)
5. QueryNodes return local top-K results to Proxy
6. Proxy merges all results, returns global top-K to client
```

---

## Part 5: Sharding, Replication, and Multi-Tenancy

### Sharding

Milvus uses **collection sharding** to distribute vectors across multiple DataNodes and QueryNodes.

```
Collection: products (10B vectors)
  ├── Shard 0 → DataNode-1, DataNode-2 (primary, replica)
  ├── Shard 1 → DataNode-3, DataNode-4
  ├── Shard 2 → DataNode-5, DataNode-6
  └── Shard 3 → DataNode-7, DataNode-8

Routing: hash(primary_key) % num_shards → shard assignment
```

- Default shards per collection: 2
- Max recommended shards: 16 (coordination overhead grows with shard count)
- Each shard's segments are independently indexed and loaded

### Replication

Milvus 2.x uses **segment-level replication** for QueryNodes:

```
Indexed Segment:
  QueryNode-A (primary search replica)
  QueryNode-B (secondary search replica)
  QueryNode-C (tertiary, optional)

QueryCoord routes:
  - All search requests distributed across A, B, C (read load balancing)
  - Any replica can answer; no consensus needed for reads
```

**WAL-based durability**: Pulsar/Kafka provides durable WAL replication. Even if DataNode fails before flushing, the WAL allows recovery.

### Multi-Tenancy Patterns

| Pattern | Implementation | Isolation | Cost | Scale |
|---|---|---|---|---|
| **Per-tenant collection** | One collection per tenant | Full (index, memory, shards) | High (fixed overhead per collection) | Up to ~1000 tenants |
| **Partition key** | Single collection, `partition_key` field | Logical (shared index, isolated partitions) | Low | Millions of tenants |
| **Namespace** | Milvus 2.4+: database-level isolation | Full (schema, collections) | Medium | Hundreds of databases |

**Partition key recommendation** (Milvus 2.3+):
```python
# Define partition_key field at collection creation
schema = CollectionSchema(fields=[
    FieldSchema("id", DataType.INT64, is_primary=True),
    FieldSchema("tenant_id", DataType.VARCHAR, is_partition_key=True),
    FieldSchema("embedding", DataType.FLOAT_VECTOR, dim=1536),
])

# Search is automatically routed to correct partition
results = collection.search(
    data=[query_vector],
    expr='tenant_id == "acme_corp"',  # filtered to partition
    ...
)
```

### Hot/Warm/Cold Tiered Storage

```
HOT tier (QueryNode memory):
  - Recently accessed indexed segments
  - Full vector + index in RAM
  - Sub-10ms search latency

WARM tier (SSD-resident):
  - Less frequently accessed indexed segments
  - DiskANN-style disk graph OR S3-cached segments
  - 20–100ms search latency

COLD tier (Object store — S3/GCS):
  - All sealed + indexed segments persisted
  - Raw binlogs
  - Loaded on-demand to QueryNode (1–30s load time)
```

**Memory management**: QueryCoord monitors QueryNode memory utilization; auto-evicts cold segments when memory pressure exceeds threshold (configurable, default 85%).

---

## FAANG Interview Callout

> **What an interviewer tests with architecture questions**: Can you trace data from an insert all the way to a searchable state? Do you understand why HNSW beats IVF at medium scale? Can you reason about trade-offs when asked "how would you serve 1B vectors with < 50ms latency"?

**Model answer for "how does HNSW work?"**: *"HNSW builds a multi-layer navigable small world graph. At the top layer, connections are sparse and long-range — these enable fast navigation. At the bottom layer (layer 0), every vector has M bidirectional edges to its M nearest neighbors, giving fine-grained search resolution. A query starts at the entry point of the top layer, greedily follows edges to get closer to the query vector, then 'descends' to layer 0 where a beam search with ef candidates explores the neighborhood. The key insight is that the hierarchical structure achieves O(log n) expected query time — adding 10× more vectors adds only ~3ms latency rather than 10× more latency."*

**Model answer for "what index for 1B vectors?"**: *"At 1B vectors, HNSW is too memory-intensive — M=32, d=768 would require ~600 GB RAM. I'd use IVF-PQ for a fully in-memory approach: nlist=65536, m=64, nbits=8 gives 96% compression versus raw FP32. That brings 1B × 768d from 3TB to ~100GB, achievable with a multi-node cluster. For billion-scale on a single machine, DiskANN (or Milvus DiskANN index) is compelling — it serves 1B d=128 vectors from 64GB RAM with SSD-backed graph traversal at ~50ms p99."*

---

## Related Files

- [README.md](README.md) — overview, decision guide, use cases, anti-patterns
- [02-read-write-path.md](02-read-write-path.md) — ingestion pipeline, search path, filtering, hybrid search
- [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) — 8-system comparison, decision flowchart
- [04-tuning-guide.md](04-tuning-guide.md) — HNSW/IVF/PQ parameter tuning reference
- [05-production-and-research.md](05-production-and-research.md) — research papers, companies, operational lessons
