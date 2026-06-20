# Vector Databases — Read/Write Path Deep Dive

> **Focus**: How data flows from client insert to searchable ANN index (ingestion path), how a search request is executed across distributed segments (search path), the critical problem of metadata filtering in ANN systems, hybrid dense+sparse retrieval, and key performance optimizations. This document assumes familiarity with [01-architecture.md](01-architecture.md).

---

## Part 1: Ingestion Path

### Overview

Vector database ingestion is fundamentally different from OLTP ingestion because vectors cannot be indexed incrementally in the same way as B-tree keys. Index structures like HNSW require batch construction and do not support single-vector insert at sub-millisecond latency into an existing index without degrading the graph structure.

**The key architectural insight**: decouple write acceptance (low latency, high throughput) from index construction (expensive, batched). Accept writes immediately into a growing segment buffer; build the ANN index offline when the segment seals.

---

### Step-by-Step Ingestion Pipeline (Milvus Reference)

```
┌──────────────────────────────────────────────────────────────────────┐
│  Step 1: Client writes                                               │
│                                                                      │
│  client.insert(vectors=[...], metadata={...})                        │
│  → SDK validates schema (field types, vector dimensions match)       │
│  → SDK calls Proxy via gRPC                                          │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Step 2: Proxy processing                                            │
│                                                                      │
│  - Validates auth token, quota, rate limits                          │
│  - Assigns timestamp from RootCoord TSO (Timestamp Oracle)          │
│    → Enables MVCC: reads see snapshot at timestamp T                 │
│  - Routes to DataCoord: "which DataNode owns shard S?"               │
│  - Forwards insert to owning DataNode                                │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Step 3: WAL write (durability before ack)                           │
│                                                                      │
│  DataNode writes insert to WAL (Pulsar / Kafka):                     │
│    Topic: collection-{id}-shard-{n}                                  │
│    Message: {vectors, metadata, timestamp, segment_id}               │
│                                                                      │
│  ACK returned to client ONLY after WAL write confirmed               │
│  → Durability guarantee: data survives DataNode crash                │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Step 4: Growing segment buffer                                      │
│                                                                      │
│  DataNode also writes to in-memory growing segment:                  │
│    - Vector data: float32 array                                      │
│    - Scalar metadata: column stores per field                        │
│    - Delete log: bitmap of deleted primary keys                      │
│                                                                      │
│  Growing segment is searchable immediately (via brute-force scan)    │
│  → Ensures no "search blindspot" during segment seal lifecycle       │
└──────────────────────────────────────────────────────────────────────┘
                              │
              [segment reaches seal threshold]
              default: 1M rows or 512MB
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Step 5: Segment seal + flush to object store                        │
│                                                                      │
│  DataCoord triggers seal:                                            │
│    1. Growing segment → "Sealed" state                               │
│    2. DataNode serializes to binlog format (column-oriented)         │
│    3. Uploads binlogs to S3/MinIO:                                   │
│         s3://bucket/collection-{id}/segment-{id}/                   │
│           insert_log/{field_id}/{timestamp}.binlog                   │
│           delta_log/{timestamp}.binlog  (deletes)                    │
│           stats_log/...                 (field statistics)           │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Step 6: Index build (async, IndexNode)                              │
│                                                                      │
│  IndexCoord detects new sealed segment, schedules index build:       │
│    1. IndexNode downloads binlogs from S3                            │
│    2. Builds HNSW/IVF/PQ index from raw vectors                     │
│       - HNSW (M=32, ef=256): ~10 minutes for 1M 1536-d vectors       │
│       - IVF_PQ (nlist=4096): ~30 minutes for 1M vectors (k-means)   │
│    3. Uploads index files to S3                                      │
│    4. Reports completion to IndexCoord                               │
│                                                                      │
│  Segment state: Sealed → Indexed                                     │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Step 7: Segment load to QueryNode                                   │
│                                                                      │
│  QueryCoord detects new indexed segment:                             │
│    1. Selects QueryNode with sufficient memory                       │
│    2. QueryNode downloads index + raw vectors from S3                │
│       (raw vectors needed for re-scoring after ANN)                  │
│    3. Memory-maps index files for efficient access                   │
│    4. Reports load complete to QueryCoord                            │
│                                                                      │
│  Segment state: Indexed → Loaded → Searchable via ANN               │
└──────────────────────────────────────────────────────────────────────┘
```

**End-to-end latency from insert to ANN-searchable**:
- WAL ack (durability): ~1–5ms
- Brute-force searchable (via growing segment): immediate
- ANN-indexed searchable: 5–60 minutes depending on segment size and index type

---

### Batch vs Streaming Ingestion

| Mode | Mechanism | Throughput | Latency to Indexed | Use Case |
|---|---|---|---|---|
| **Batch Insert (BulkInsert)** | Upload Parquet/CSV to S3, trigger import | 10M–1B vectors/hour | Hours (parallel segment build) | Initial load, nightly batch |
| **Streaming Insert** | SDK insert API, via WAL | 10K–500K vectors/sec | 5–60 min (index build) | Real-time updates, event-driven |
| **Upsert** | Primary key match → delete + insert | Same as streaming | Same | Update existing vectors |

**BulkInsert internals**:
```python
# Milvus BulkInsert: bypass WAL, directly create sealed segments
from pymilvus import BulkInsertState, utility

# 1. Upload Parquet files to MinIO/S3
minio_client.put_object(bucket, "vectors.parquet", parquet_file)

# 2. Trigger import
task_id = utility.do_bulk_insert(
    collection_name="documents",
    files=["s3://bucket/vectors.parquet"]
)

# 3. Monitor import
while True:
    state = utility.get_bulk_insert_state(task_id)
    if state.state == BulkInsertState.ImportCompleted:
        break
    time.sleep(5)
```

**When to use BulkInsert vs streaming**:
- Initial load of existing corpus → BulkInsert (10–100× faster)
- Ongoing document indexing → streaming insert
- Nightly full rebuild (rare documents change scenario) → BulkInsert
- < 1000 documents → SDK insert API is fine

---

### Delete and Update Semantics

**Deletes** are implemented via **tombstones** (not immediate removal):

```
Delete request: primary_key = [1001, 1002, 1003]

1. Delete message written to WAL
2. Delta log: set bits 1001, 1002, 1003 in bloom filter / bitmap
3. At search time: ANN candidates filtered against delete bitmap
4. Physical deletion: happens during compaction
```

**Updates** (upsert):
```
Upsert = logical delete (tombstone) + insert
Note: old vector and new vector may live in different segments
      → search correctly merges results using tombstone filtering
```

**Compaction**: periodic background process that:
- Merges small segments (< 25% of target size) into larger ones
- Physically removes tombstoned records
- Rebuilds index on merged segment
- Reduces segment count → less coordination overhead

---

### Growing Segment Search

During the gap between insert and ANN-indexed searchable, how does Milvus handle searches against the growing segment?

```
Search request arrives:
  1. QueryCoord identifies all segments (loaded + growing)
  2. Loaded segments → HNSW/IVF ANN search (fast)
  3. Growing segments → brute-force scan (slow but correct)
  4. Results merged, top-K returned

Growing segment brute-force is bounded:
  - Seal threshold = 1M rows → worst case 1M-vector brute force
  - At d=768: 1M × 768 × 4 bytes = 3GB scan per growing segment
  - Acceptable for < 1 QPS on growing segments
  - High-write, high-read systems should tune seal threshold lower (e.g., 100K)
```

---

## Part 2: Search Path

### Step-by-Step Search Execution

```
┌────────────────────────────────────────────────────────────┐
│  Step 1: Client search request                             │
│                                                            │
│  collection.search(                                        │
│    data=[query_vector],           # batch of query vectors │
│    anns_field="embedding",        # which field to search  │
│    param={"metric_type": "COSINE", "params": {"ef": 128}}, │
│    limit=10,                      # top-K results          │
│    expr='category == "tech"',     # optional metadata filter│
│    output_fields=["title", "url"] # fields to return       │
│  )                                                         │
└────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────┐
│  Step 2: Proxy routing                                     │
│                                                            │
│  - Validates request parameters                            │
│  - Queries QueryCoord: "which QueryNodes hold collection?" │
│  - Identifies all segments (loaded + growing) in scope     │
│  - Fans out parallel search RPCs to QueryNodes             │
└────────────────────────────────────────────────────────────┘
                         │  │  │
                  ┌──────┘  │  └──────┐
                  ▼         ▼         ▼
           QueryNode-A  QueryNode-B  QueryNode-C
           (Shard 0)    (Shard 1)    (Shard 2)
                │           │           │
           [local ANN    [local ANN   [local ANN
            search on     search on    search on
            segments]     segments]    segments]
                │           │           │
                └─────┬─────┘           │
                      └────────┬────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────┐
│  Step 3: Proxy result merge                                │
│                                                            │
│  - Receives top-K candidates from each QueryNode           │
│  - Merges using min-heap (for distance metrics: lower=better│
│    for similarity metrics: higher=better)                  │
│  - Applies final top-K cutoff                              │
│  - Fetches requested output_fields from metadata store     │
│  - Returns to client                                       │
└────────────────────────────────────────────────────────────┘
```

### QueryNode Internal Search

For each search RPC, a QueryNode executes:

```
For each loaded segment in its assigned partition:
  1. If metadata filter expression provided:
     → Evaluate filter predicate against scalar column stores
     → Build candidate bitset (set bits = valid records)
  
  2. ANN search on vector index:
     → HNSW: ef-guided beam search on graph
     → IVF: probe nprobe clusters, scan member vectors
     → Apply bitset to skip filtered-out records (if pre-filter mode)
  
  3. Re-score top candidates with exact distances
     (important when PQ compression used — PQ distance is approximate)
  
  4. Return local top-K (not just limit — return limit × oversample_factor)
     to allow merge across nodes to produce correct global top-K
```

**Oversample factor**: Each QueryNode returns more than `limit` candidates because the merge at proxy level needs enough candidates to find the global top-K. Default oversample = `limit × num_shards`. For `limit=10, 3 shards`: each node returns top 30 candidates → proxy merges 90 candidates → final top 10.

---

## Part 3: Metadata Filtering — The Critical Trade-Off

Metadata filtering is one of the most complex problems in vector search. Getting it wrong destroys recall or performance.

### The Problem

```
Query: "machine learning research papers about transformers"
Filter: date >= "2022-01-01" AND journal IN ["NeurIPS", "ICML", "ICLR"]

Naive approach:
  1. ANN search full index → top 1000 vectors
  2. Apply filter → only 47 match
  → Return only 47 results when user asked for top 10
  → OR: return results with low semantic similarity that happen to match filter
```

The fundamental tension: **ANN graphs are built without awareness of metadata filters**. The nearest-neighbor graph was optimized for the full distribution of vectors. When you restrict to a filter-matching subset, the graph connectivity into that subset may be poor.

---

### Strategy 1: Post-Filtering (Default in many systems)

```
ANN search → top (K × oversample) candidates → apply metadata filter → return top K

Example: K=10, oversample=100
  1. HNSW search, ef=128 → top 100 candidates
  2. Filter: date >= "2022-01-01" → only 12 candidates survive
  3. Return top 10 (barely enough)

Failure mode:
  If filter selectivity is high (< 1% of vectors match):
  oversample=100 → 0 or 1 survivors
  → Return empty results even though matching vectors exist!
```

**When post-filtering works**:
- Filter selectivity > 10% (at least 1 in 10 vectors match)
- Use dynamic oversample: `oversample = K / expected_selectivity`
- Maximum oversample is bounded by memory and latency

**Milvus implementation**: `consistency_level`, filter expressions in `search` call — post-filter is the default for unindexed scalar fields.

---

### Strategy 2: Pre-Filtering

```
Apply filter first → restricted candidate set → ANN search only within candidates

Example: K=10
  1. Filter: date >= "2022-01-01" → 50,000 matching primary keys (5% selectivity)
  2. ANN search restricted to those 50,000 vectors
  
Naive implementation:
  → Build a sub-index only from filtered vectors → expensive rebuild per query
  → OR: mark unmatched vectors as "deleted" temporarily → impossible without index rebuild

Practical implementation:
  → HNSW graph walk with filter masking: at each graph step, only traverse to nodes
    that pass the filter predicate
```

**Pre-filtering failure mode**: When HNSW traversal is restricted to filter-matching nodes, the graph may have poor connectivity within the filter subset. A path that would normally go through an unfiltered node is blocked → the algorithm explores more candidates but achieves lower recall.

**Recall degradation with pre-filtering**:
```
Full index recall@10 with ef=128: 98%

With filter selectivity = 50%: recall = ~95%  (acceptable)
With filter selectivity = 10%: recall = ~85%  (degraded)
With filter selectivity = 1%:  recall = ~60%  (unacceptable)
```

---

### Strategy 3: Filtered-ANN (Best Approach for Production)

Modern vector databases have developed filter-aware graph traversal algorithms:

#### Weaviate ACORN (2024)

**Paper**: "ACORN: Performant and Predicate-Agnostic Search Over Vector Embeddings and Structured Data" (Peng et al., 2024)

**Key insight**: Instead of restricting traversal to filter-matching nodes, allow traversal through any node but expand the neighborhood search at filter-matching nodes.

```
Standard HNSW traversal:
  Visit node N → expand to M neighbors → filter neighbors → continue with valid ones

ACORN:
  Visit node N → if N matches filter → expand to M neighbors
              → if N doesn't match filter → expand to M² neighbors (deeper lookahead)
  → Maintains graph reachability even for sparse filter matches
```

**Result**: Recall@10 stays above 95% even at 0.1% filter selectivity, with only ~2× latency increase.

#### Qdrant Payload Index + HNSW Integration

Qdrant builds an inverted index (payload index) on scalar fields. During HNSW graph traversal, candidates that fail the filter are skipped with SIMD-accelerated bitset check, minimizing wasted traversal steps. Efficient at filter selectivity > 1%.

#### Milvus Bitset Filtering

Milvus uses a pre-computed bitset per search: 1 bit per vector, 1 = filter-matches, 0 = skip. HNSW traversal applies bitset check at each node visit. Faster than expression evaluation per node; efficient for high-selectivity filters.

---

### Filtering Strategy Selection

```
Filter selectivity (fraction of vectors matching filter):
  > 50%: Post-filtering with 2× oversample — fast, good recall
  10–50%: Post-filtering with dynamic oversample, OR pre-filtering
  1–10%: Filtered-ANN (Qdrant/Weaviate ACORN), or HNSW with bitset
  < 1%: Do NOT use ANN. Build a dedicated index for this filter segment,
        OR use brute-force on the filtered set (if set < 1M vectors)
```

**Architectural recommendation**: For multi-tenant RAG where `tenant_id` is a common filter, use Milvus partition keys — each tenant's vectors are in a separate physical partition, and search is restricted to one partition. This converts a filtering problem into a routing problem.

---

## Part 4: Hybrid Search (Dense + Sparse)

Pure dense vector search has a known failure mode: **vocabulary mismatch / lexical gap**. A query for "Siamese network" may not retrieve documents that say "twin encoder" because the embeddings may not be sufficiently aligned on this technical term.

**Sparse retrieval** (BM25, SPLADE) excels at exact keyword matching but fails at semantic generalization. Hybrid combines both.

---

### BM25 Sparse Retrieval

Elasticsearch/OpenSearch have native BM25 inverted indexes. Milvus 2.4+ adds sparse vector support:

```python
# Milvus 2.4+ sparse vector field
from pymilvus import FieldSchema, DataType

schema = CollectionSchema(fields=[
    FieldSchema("dense_embedding", DataType.FLOAT_VECTOR, dim=1536),
    FieldSchema("sparse_embedding", DataType.SPARSE_FLOAT_VECTOR),  # BM25 / SPLADE
    FieldSchema("text", DataType.VARCHAR, max_length=65535),
])

# Generate sparse representations
from pymilvus.model.sparse import BM25EmbeddingFunction
bm25_ef = BM25EmbeddingFunction()
bm25_ef.fit(corpus)  # build IDF from corpus
sparse_vectors = bm25_ef.encode_documents(documents)
```

---

### SPLADE (Sparse Lexical and Expansion)

SPLADE learns to expand query terms (similar to synonyms) while producing sparse, weighted representations:

```
Input query: "transformer neural network"
SPLADE output: {"transformer": 2.1, "attention": 1.8, "BERT": 1.5, 
                "neural": 2.3, "network": 1.9, "model": 1.4, ...}
(sparse vector with ~200 non-zero terms vs 30K vocab)
```

Compared to BM25:
- Handles synonyms and related terms (semantic expansion)
- More expensive to compute (inference through BERT-like model)
- Higher recall on domain-specific vocabulary

---

### Fusion Strategies

After executing dense ANN search and sparse BM25/SPLADE search independently, combine ranked result lists.

**Reciprocal Rank Fusion (RRF)**:

$$\text{RRF score}(d) = \sum_{r \in R} \frac{1}{k + r(d)}$$

Where $r(d)$ is the rank of document d in ranked list r, and $k = 60$ (constant that moderates high-rank scores).

```python
def reciprocal_rank_fusion(dense_results, sparse_results, k=60, top_k=10):
    scores = {}
    for rank, (doc_id, _) in enumerate(dense_results):
        scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank + 1)
    for rank, (doc_id, _) in enumerate(sparse_results):
        scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank + 1)
    
    return sorted(scores.items(), key=lambda x: -x[1])[:top_k]
```

**Advantages of RRF**: No weight tuning required; rank-based (not score-based, so dense/sparse scores are not on same scale); robust to score distribution differences.

**Linear Score Combination** (alternative):

$$\text{score}(d) = \alpha \cdot \text{dense\_score}(d) + (1 - \alpha) \cdot \text{sparse\_score}(d)$$

Requires normalizing scores to same range and tuning $\alpha$ (typically 0.3–0.7 for dense, with $\alpha=0.7$ common for most RAG).

**RRF vs Linear**:

| Criterion | RRF | Linear Combination |
|---|---|---|
| Requires score normalization | No | Yes |
| Requires weight tuning | No | Yes ($\alpha$) |
| Handles score scale mismatch | Yes | No |
| Optimal when one modality dominates | Equal weighting (may not be optimal) | Tunable |
| Implementation complexity | Low | Medium |
| **Recommendation** | Default starting point | Use after A/B validation |

---

### Multi-Vector Search (ColBERT / Late Interaction)

Standard dense search embeds documents and queries into single vectors (bi-encoder). Late interaction models like **ColBERT** store **all token-level embeddings** and compute similarity via MaxSim operator.

```
Bi-encoder (standard):
  Document D → encode → single 768-d vector
  Query Q    → encode → single 768-d vector
  sim(Q, D) = cos(q_vec, d_vec)

ColBERT (late interaction):
  Document D → encode → N_d × 128-d token vectors (N_d = token count)
  Query Q    → encode → N_q × 128-d token vectors
  
  MaxSim(Q, D) = sum over each query token:
                 max_j cos(q_token_i, d_token_j)

  Idea: every query token finds its most similar document token
        → captures token-level alignment, not just sentence-level
```

**Trade-offs**:

| | Bi-encoder | ColBERT |
|---|---|---|
| Index storage | 1 vector / document | N tokens × 128d per document |
| Storage overhead | 1× | 10–50× |
| ANN compatibility | Yes (standard HNSW) | Requires PLAID index or separate per-token search |
| Recall quality | Good | Excellent (top tier on BEIR benchmark) |
| Retrieval latency | 1–10ms | 50–500ms |
| **Use case** | Default RAG retrieval | Re-ranking pool (apply on top-100 from bi-encoder) |

---

## Part 5: Performance Optimizations

### SIMD (Single Instruction, Multiple Data) Acceleration

Distance computations (dot product, L2) are the inner loop of every ANN operation. Modern CPUs process multiple values simultaneously:

```
Standard scalar dot product (d=1536):
  Loop: multiply + accumulate 1536 times → 1536 FP32 operations

AVX-512 SIMD (available on Intel Skylake+):
  Process 16 FP32 values per instruction → 1536/16 = 96 instructions

For INT8 (SQ8 quantized):
  Process 64 INT8 values per instruction → 1536/64 = 24 instructions
  + SIMD int8 dot product = additional 4× speedup over FP32 SIMD
```

FAISS uses `faiss::FAISS_COMPUTE_ON_GPU=0` with auto-detection of AVX2/AVX-512/ARM NEON. Milvus inherits FAISS SIMD automatically.

**Practical impact**: On AVX-512 hardware (AWS `c5.xlarge` or newer), inner product is ~4–8× faster than naive loop.

### Memory-Mapped Files (mmap)

Milvus 2.x supports memory-mapping index files — the OS manages which pages are in RAM vs disk, enabling index sizes larger than RAM with hot-path caching:

```python
# Milvus mmap configuration
collection.set_properties({
    "mmap.enabled": True  # enables mmap for this collection
})
```

**Hot/cold access pattern**: Frequently accessed segments stay in OS page cache; cold segments are evicted. Good for collections where a subset of segments handles most queries (temporal skew, popular tenants).

### Query Result Caching

For identical query vectors (e.g., popular search queries), cache results at the proxy layer:

```python
import hashlib, json, redis

r = redis.Redis()

def cached_search(collection, query_vector, top_k, expr):
    cache_key = f"search:{hashlib.sha256(json.dumps({
        'vec': query_vector[:10],  # first 10 dims as fingerprint
        'topk': top_k,
        'expr': expr
    }, sort_keys=True).encode()).hexdigest()}"
    
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    results = collection.search(...)
    r.setex(cache_key, 300, json.dumps(results))  # 5-minute TTL
    return results
```

**Applicable when**: Repetitive queries (autocomplete, trending topics). Not applicable for personalized embedding queries (every user has unique query vector).

### Segment Cache Warming

After deploying a new index version or after a QueryNode restart, the first queries against unwarmed segments are slow (S3 download latency). Warm-up strategy:

```python
# Before routing live traffic, run warm-up queries
import random, numpy as np

def warmup_collection(collection, n_warmup=100, dim=1536):
    dummy_queries = np.random.random((n_warmup, dim)).tolist()
    for q in dummy_queries:
        collection.search(data=[q], anns_field="embedding", 
                          param={"ef": 64}, limit=1)
    print(f"Warm-up complete: {n_warmup} queries executed")
```

---

## FAANG Interview Callout

> **What an interviewer is testing**: Can you explain why ANN-indexed searchability is delayed (segment lifecycle)? Can you reason about the recall failure modes of metadata filtering? Do you know the difference between pre-filter, post-filter, and filtered-ANN and when to use each?

**Model answer for "how would you handle filtered vector search when the filter is very selective (< 1%)?**:
*"Standard post-filtering would fail here — if only 1% of vectors match the filter, even with 100× oversampling I might retrieve 100 candidates but only 1 matches. Options: (1) Build a separate sub-collection for this filter value — if it's a high-cardinality but stable filter like `category = 'medical'`, a dedicated collection avoids the problem. (2) Use Weaviate ACORN or Qdrant's filtered HNSW which maintain recall at < 1% selectivity by expanding the graph traversal neighborhood at filter-matching nodes. (3) Fall back to brute-force scan of the filtered subset — if only 1% of 10M vectors match, that's 100K vectors; brute force at d=768 is ~300MB scan, completable in ~50ms with SIMD. The right answer depends on the query frequency and update frequency of the filter-matching set."*

---

## Related Files

- [01-architecture.md](01-architecture.md) — index algorithms (HNSW/IVF/PQ), Milvus architecture, segment concept
- [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) — system comparisons including filtering capabilities
- [04-tuning-guide.md](04-tuning-guide.md) — ef, nprobe, segment size tuning
- [../../AI/llm-applications/vector-retrieval-patterns.md](../../AI/llm-applications/vector-retrieval-patterns.md) — application-level retrieval patterns built on top of this infrastructure
