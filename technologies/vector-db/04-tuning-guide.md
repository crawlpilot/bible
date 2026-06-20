# Vector Databases — Tuning Guide

> **Tuning philosophy**: Vector database performance lives at the intersection of three competing constraints — **recall**, **latency**, and **memory**. Every tuning parameter moves you along this triangle. Tune for your SLO (define recall target and latency budget first), not for theoretical maximums. Measure before and after every change using the evaluation set from your RAGAS/retrieval pipeline.

---

## The Recall-Latency-Memory Triangle

```
             Recall (accuracy)
                   ▲
                   │
          Higher M/ef_construction
          Higher ef_search/nprobe
          FP32 (no quantization)
          More replicas
                   │
Memory ────────────┼────────────── Latency
(cost, hardware)   │             (user experience)
                   │
          Lower M, fewer edges
          PQ quantization
          Lower ef_search
          Fewer replicas
```

**SLO-first approach**:
1. Define: Recall@10 ≥ 95%, p99 latency ≤ 10ms, memory budget ≤ 64GB
2. Establish baseline: FLAT index (exact recall = 100%, known latency)
3. Tune index parameters to meet recall target within latency budget
4. Apply quantization if memory budget exceeded
5. Validate: re-run evaluation set; compare to baseline

---

## Part 1: HNSW Parameter Tuning

HNSW has three primary parameters: M (graph connectivity), ef_construction (build quality), and ef (query quality).

### Parameter Reference

| Parameter | Default | Range | Effect on Recall | Effect on Latency | Effect on Memory | Effect on Build Time |
|---|---|---|---|---|---|---|
| `M` | 16 | 8–64 | ↑ | slight ↑ | ↑ (n×M×8 bytes) | ↑ |
| `ef_construction` | 200 | 100–500 | ↑ (index quality) | no effect | no effect | ↑ |
| `ef` / `ef_search` | 64 | 16–500 | ↑ | ↑ | no effect | no effect |

### M — Graph Connectivity

M controls the maximum number of bidirectional edges per node in the HNSW graph.

```
Memory per vector = M × 2 × 4 bytes (edges) + d × sizeof(dtype) (raw vector)

M=16, d=768, FP32:
  edges: 16 × 2 × 4 = 128 bytes
  vector: 768 × 4 = 3072 bytes
  total: 3200 bytes/vector
  10M vectors: 32 GB

M=32, d=768, FP32:
  edges: 32 × 2 × 4 = 256 bytes
  vector: 3072 bytes
  total: 3328 bytes/vector
  10M vectors: 33.3 GB (only 4% more memory than M=16!)

M=64, d=768, FP32:
  edges: 512 bytes
  vector: 3072 bytes
  total: 3584 bytes/vector
  10M vectors: 35.8 GB (11% more memory vs M=16)
```

**M tuning guidance**:

| Use Case | Recommended M | Recall@10 (ef=128) |
|---|---|---|
| Memory-constrained (< 16 bytes/dim overhead) | 8–12 | 92–95% |
| General production | 16–32 | 96–99% |
| High-recall (> 99% target) | 48–64 | 99%+ |
| Billion-scale with quantization | 8–16 (combine with PQ) | 90–95% |

**M tuning rule of thumb**: Start at M=16. If Recall@10 < 95% after increasing ef_search to 256, increase M to 32. Beyond M=32, returns diminish rapidly while build time increases linearly.

### ef_construction — Build Quality

Controls the beam size during index construction. Higher ef_construction = better graph quality = higher achievable recall at any given ef_search. **Once the index is built, ef_construction cannot be changed without rebuilding.**

```
ef_construction = 100: 20–40% faster build; recall ceiling ~96% (never exceeds)
ef_construction = 200: balanced build time / quality
ef_construction = 500: slow build; recall ceiling ~99.5%
```

**Recommendation**: Always use ef_construction ≥ 200 for production. Build happens offline (IndexNode); the time cost is absorbed in the segment seal pipeline, not user-visible.

**Anti-pattern**: Setting ef_construction = 64 to speed up development. This permanently caps achievable recall at ~94%, even with ef_search = 1000.

### ef / ef_search — Query Quality

The most important runtime-tunable parameter. Higher ef = larger beam search = better recall, higher latency. This is the primary latency lever.

**Recall vs latency curve (example: 10M vectors, M=32, d=768, ef_construction=256)**:

| ef | Recall@10 | p50 latency | p99 latency |
|---|---|---|---|
| 16 | 88% | 0.5ms | 1ms |
| 32 | 93% | 0.8ms | 1.5ms |
| 64 | 96% | 1.2ms | 2ms |
| 128 | 98% | 2ms | 4ms |
| 256 | 99.2% | 4ms | 8ms |
| 512 | 99.5% | 8ms | 15ms |

**Tuning procedure**:
1. Run ANN Benchmarks-style evaluation on your data + evaluation set
2. Find the lowest ef that meets your recall SLO (e.g., ≥ 95%)
3. Verify p99 latency meets SLO at that ef
4. If latency is violated, you need to scale horizontally (more QueryNodes) or accept lower recall

**Milvus Python example**:
```python
# HNSW index creation
index_params = {
    "metric_type": "COSINE",
    "index_type": "HNSW",
    "params": {
        "M": 32,
        "efConstruction": 256
    }
}
collection.create_index(field_name="embedding", index_params=index_params)

# Search with ef
search_params = {
    "metric_type": "COSINE",
    "params": {"ef": 128}
}
results = collection.search(data=[query_vec], anns_field="embedding",
                             param=search_params, limit=10)
```

---

## Part 2: IVF Parameter Tuning

IVF is the choice when memory budget forces quantization at large scale (> 100M vectors). The key parameters are nlist and nprobe.

### nlist — Number of Voronoi Cells (Clusters)

```
Rule of thumb: nlist ≈ √n where n = number of vectors

1M vectors  → nlist = 1000   (practical: 1024)
10M vectors → nlist = 3162   (practical: 4096)
100M vectors → nlist = 10000 (practical: 8192–16384)
1B vectors  → nlist = 31623  (practical: 65536)
```

**Effect of nlist**:
- Higher nlist → smaller clusters → better ANN quality per probe → but more centroids to compare at query time
- Lower nlist → larger clusters → more vectors per probe → higher nprobe needed for same recall

**Training data requirement (FAISS rule)**:
- Training set must be ≥ 39 × nlist vectors (k-means convergence requirement)
- For nlist=4096: train on ≥ 160K representative vectors
- Sample from your actual corpus; use random sample if corpus > 1M

### nprobe — Clusters to Search at Query Time

The primary recall/latency trade-off for IVF.

```
nprobe = 1:  search only nearest centroid → ~5–15% recall
nprobe = 4:  ~40–60% recall
nprobe = 16: ~70–85% recall
nprobe = 32: ~80–92% recall
nprobe = 64: ~87–96% recall  ← typical production range
nprobe = 128: ~92–98% recall
nprobe = nlist: exact KNN (= FLAT, no approximation benefit)
```

**Rule of thumb for production**: nprobe = nlist / 64 as starting point, then tune.

**Effect of nlist on nprobe requirements**: Larger nlist with smaller clusters means each probe covers fewer vectors → need more probes for same recall. At nlist=4096, nprobe=64 gives ~90% recall. At nlist=1024, nprobe=16 gives ~90% recall.

```python
# IVF_FLAT index (no quantization)
index_params = {
    "metric_type": "COSINE",
    "index_type": "IVF_FLAT",
    "params": {"nlist": 4096}
}

# IVF_PQ index (with Product Quantization)
index_params = {
    "metric_type": "COSINE",
    "index_type": "IVF_PQ",
    "params": {
        "nlist": 4096,
        "m": 64,       # sub-spaces (must divide d evenly: 1536/64 = 24)
        "nbits": 8     # bits per sub-space (standard: 8 = 256 centroids)
    }
}
collection.create_index(field_name="embedding", index_params=index_params)

# Search
search_params = {
    "metric_type": "COSINE",
    "params": {"nprobe": 64}  # runtime-tunable per query
}
```

---

## Part 3: Product Quantization (PQ) Tuning

PQ is layered on top of IVF (IVF_PQ) or HNSW (HNSW_PQ in newer Milvus). Choosing the right m value is the key decision.

### Selecting m (Number of Sub-spaces)

**Hard constraint**: m must divide d evenly. For d=1536: valid m values are 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1536.

**Rule**: Each sub-space should have ≥ 4 dimensions. Maximum m = d/4.
For d=1536: max effective m = 384.

**Memory calculation**:
```
PQ storage per vector = m × nbits / 8 bytes

m=8,   nbits=8, d=768:  1 byte  × 8  = 8 bytes  (96× compression vs FP32)
m=32,  nbits=8, d=768:  1 byte  × 32 = 32 bytes (24× compression)
m=64,  nbits=8, d=1536: 1 byte  × 64 = 64 bytes (24× compression)
m=192, nbits=8, d=1536: 1 byte  × 192 = 192 bytes (8× compression)
```

**Recall vs compression table**:

| d | m | Compression | Recall@10 vs IVF_FLAT |
|---|---|---|---|
| 768 | 8 | 96× | ~82% |
| 768 | 32 | 24× | ~90% |
| 768 | 64 | 12× | ~94% |
| 1536 | 64 | 24× | ~88% |
| 1536 | 96 | 16× | ~92% |
| 1536 | 192 | 8× | ~96% |

**Starting recommendation**: m = d/8 as starting point. Measure recall. If < recall SLO, increase m (higher quality, less compression). If memory budget exceeded, decrease m.

### PQ centroid table memory

```
Centroid table size = m × 2^nbits × (d/m) × sizeof(float32)
                    = m × 256 × (d/m) × 4
                    = d × 256 × 4
                    = d × 1024 bytes

For d=768:  768 KB (trivial)
For d=1536: 1.5 MB (trivial)

→ Centroid tables are not significant; focus on per-vector storage
```

---

## Part 4: Dimension Reduction

When embedding dimensions are too high for memory/latency budget, reduce via PCA or use MRL models.

### PCA (Principal Component Analysis)

```python
from sklearn.decomposition import PCA
import numpy as np

def fit_and_reduce_pca(embeddings: np.ndarray, n_components: int) -> tuple:
    """
    Fit PCA on a representative sample. Returns (pca_model, reduced_embeddings).
    """
    sample_size = min(100_000, len(embeddings))
    sample_idx = np.random.choice(len(embeddings), sample_size, replace=False)
    
    pca = PCA(n_components=n_components, random_state=42)
    pca.fit(embeddings[sample_idx])
    
    explained = pca.explained_variance_ratio_.sum()
    print(f"Explained variance at {n_components}d: {explained:.4f}")
    
    # Apply to full corpus
    reduced = pca.transform(embeddings)
    return pca, reduced

# Decision: if explained variance > 0.98, PCA reduction is safe
pca, reduced = fit_and_reduce_pca(embeddings, n_components=256)
# explained variance: 0.983 → safe to use 256d instead of 1536d
```

**PCA reduction guidelines**:

| Explained variance | Action |
|---|---|
| ≥ 0.99 | Safe reduction; < 1% recall impact |
| 0.97–0.99 | Generally acceptable; validate recall@10 |
| 0.95–0.97 | May have 3–5% recall loss; validate carefully |
| < 0.95 | Too much information loss; don't reduce this far |

**Important**: PCA must be fit on your specific embedding distribution. Refit whenever you change embedding models.

---

## Part 5: Hardware Sizing

### Memory Sizing Formula

```
Total QueryNode memory required = 
  (n_vectors × bytes_per_vector)     # raw vectors for re-scoring
  + (n_vectors × M × 2 × 4)          # HNSW graph edges (if HNSW)
  + overhead (OS, Milvus process)     # ~2–4 GB

Example: 10M vectors, d=1536, HNSW M=32, FP32

  raw vectors:    10M × 1536 × 4 = 61.44 GB
  HNSW graph:     10M × 32 × 2 × 4 = 2.56 GB
  overhead:       4 GB
  ──────────────────────────────────
  Total:          68 GB

→ Need at least 2 × m5.4xlarge (64GB RAM each), with segments distributed
  OR 1 × r5.4xlarge (128GB RAM) for single-node
```

**With SQ8 quantization** (same example):
```
  raw vectors:    10M × 1536 × 1 = 15.36 GB (INT8, 4× reduction)
  HNSW graph:     2.56 GB (unchanged — graph stores int32 node IDs)
  overhead:       4 GB
  ──────────────────────────────────
  Total:          22 GB → 1 × r5.2xlarge (64GB) with headroom
```

### CPU Sizing

| Workload | Guidance |
|---|---|
| Low QPS (< 100 QPS) | 4–8 cores per QueryNode; I/O-bound more than CPU |
| Medium QPS (100–1000 QPS) | 16–32 cores; AVX-512 vectorization pays off |
| High QPS (> 1000 QPS) | Scale QueryNodes horizontally; each QueryNode can serve ~500 QPS for HNSW at ef=128 |
| Index build (IndexNode) | 32+ cores for HNSW build; GPU accelerates IVF k-means by 10–50× |

### GPU for Index Build

GPU acceleration applies to:
- IVF k-means training: 10–50× speedup (GPU k-means vs CPU)
- HNSW build: limited benefit (graph traversal is pointer-heavy, poor for GPU)
- FLAT search: 10× speedup on GPU vs CPU

```python
# FAISS GPU-accelerated IVF training
import faiss, numpy as np

res = faiss.StandardGpuResources()
index_flat = faiss.IndexFlatL2(d)
index_ivf = faiss.IndexIVFFlat(index_flat, d, nlist)
gpu_index = faiss.index_cpu_to_gpu(res, 0, index_ivf)  # move to GPU 0
gpu_index.train(training_vectors)    # k-means on GPU
gpu_index.add(all_vectors)
cpu_index = faiss.index_gpu_to_cpu(gpu_index)  # move back to CPU for serving
faiss.write_index(cpu_index, "index.faiss")
```

---

## Part 6: Batch Ingestion Sizing

### Optimal Batch Size

```
Embedding API (OpenAI):
  Max per request: 2048 inputs
  Max tokens per input: 8191
  Optimal batch: 512 (balance throughput vs retry cost on error)

Milvus insert:
  Recommended: 1K–10K vectors per insert call
  Max effective: ~100K (above this, single insert holds lock too long)
  
  # Good: batch of 5K vectors
  collection.insert(list_of_5000_entities)
  
  # Bad: single-row insert in a loop
  for entity in entities:
      collection.insert([entity])  # 1000× slower due to WAL overhead
```

### Segment Size Threshold Tuning

```
# Milvus default: seal segment at 512MB or 1M rows (whichever first)
# Tune based on your index build time vs search latency trade-off:

# Small segments (100K rows):
#   + Faster index build
#   + ANN-searchable sooner after insert
#   - More segments → higher QueryCoord coordination overhead
#   - More S3 objects → higher metadata overhead

# Large segments (5M rows):
#   + Fewer segments → less coordination
#   + Better ANN graph quality (larger training set for IVF)
#   - Longer index build time
#   - ANN-searchable later after insert

# For latency-sensitive workloads (fast insert → search pipeline):
milvus_client.alter_collection_properties(
    collection_name="docs",
    properties={"collection.insertBufferSize": "134217728"}  # 128MB seal threshold
)
```

---

## Part 7: Monitoring Metrics

Every production vector DB deployment needs these metrics:

| Metric | Target | Alert Threshold | Meaning |
|---|---|---|---|
| `search_latency_p99` | < 10ms (HNSW) | > 50ms | ANN search performance |
| `search_latency_p50` | < 3ms | > 15ms | Typical user experience |
| `search_qps` | (baseline) | > 90% of capacity | Near saturation |
| `recall@10` (evaluated) | ≥ 95% | < 90% | Retrieval quality degradation |
| `querynode_memory_used` | < 80% | > 90% | Risk of OOM → segment eviction |
| `segment_count` | (baseline) | > 10,000 | Too many small segments; compaction needed |
| `index_build_queue_depth` | < 5 | > 50 | IndexNode can't keep up with segment seal rate |
| `growing_segment_row_count` | < seal threshold | N/A | Monitor insert backlog |
| `compaction_pending_segments` | < 10 | > 100 | Compaction not running fast enough |
| `deleted_ratio_per_segment` | < 20% | > 50% | High delete rate; compaction needed |
| `embedding_api_error_rate` | < 0.1% | > 1% | Embedding pipeline health |
| `embedding_api_p99_latency` | < 500ms | > 2000ms | Ingestion pipeline throughput |

### Prometheus Queries (Milvus)

```promql
# p99 search latency
histogram_quantile(0.99, sum(rate(milvus_proxy_search_latency_bucket[5m])) by (le))

# QueryNode memory utilization
milvus_querynode_collection_loaded_size / milvus_querynode_max_collection_loaded_size

# Index build queue depth
milvus_indexcoord_index_task_count{task_type="InProgress"}

# Segment count by state
milvus_datacoord_segment_count{segment_state="Flushed"}
```

---

## Part 8: Anti-Patterns

| Anti-Pattern | Consequence | Fix |
|---|---|---|
| **Not normalizing vectors for cosine** | Cosine on unnormalized vectors = wrong distances; recall degrades unpredictably | L2-normalize all vectors at ingestion: `v / np.linalg.norm(v)` |
| **ef_construction too low (< 100)** | Graph quality permanently capped; cannot be fixed without index rebuild | Always use ef_construction ≥ 200 |
| **nprobe = 1 (IVF default)** | ~5–15% recall — most results are wrong | nprobe ≥ nlist / 64 for production recall |
| **FLAT index at > 1M vectors** | O(n×d) per query; latency grows linearly | Switch to HNSW or IVF |
| **High d without quantization** | Memory explodes: 10M × 3072d × 4B = 117 GB | Apply SQ8 first, then PQ if needed |
| **Single growing segment for all inserts** | Large brute-force scan range; hot segment bottleneck | Use multiple shards; lower seal threshold |
| **No index warmup after deploy** | First queries hit S3 cold start (~10s load time) | Send warm-up queries before routing traffic |
| **One collection per user (10K users)** | 10K collections × overhead = massive coordination load | Use partition keys for user isolation in single collection |
| **Not monitoring recall@10** | Recall silently degrades as corpus grows or model changes | Weekly automated recall evaluation on held-out set |
| **Wrong metric type** | Using L2 for text embeddings (should be cosine/IP); wrong results | Use COSINE or IP for text; L2 for spatial |
| **Reindexing in place during peak** | Index rebuild blocks searches on affected segments | Use blue-green collection switch: build new → validate → atomic swap |

---

## Part 9: Blue-Green Index Rebuild

When you need to rebuild the entire index (new index type, parameter change, new embedding model):

```python
# Blue-Green Collection Switch (Milvus)

# Step 1: Create new collection (v2) alongside live collection (v1)
create_collection("docs_v2", schema, index_params=new_index_params)

# Step 2: Backfill all vectors into v2 (background)
backfill_job = BulkInsert("docs_v2", source="docs_v1_backup.parquet")
await_job_completion(backfill_job)

# Step 3: Validate recall on evaluation set against v2
recall_v2 = run_recall_evaluation("docs_v2", eval_set)
assert recall_v2 >= 0.95, f"v2 recall {recall_v2} below SLO"

# Step 4: Atomic alias switch
drop_alias("docs_latest")
create_alias("docs_v2", "docs_latest")  # all queries route to v2 immediately

# Step 5: Keep v1 for 24 hours (rollback window)
# Step 6: Drop v1 after validation
drop_collection("docs_v1")
```

**Rollback**: Simply point alias back to v1 (< 1 second).

---

## FAANG Interview Callout

> **What an interviewer tests**: Can you describe the recall-latency-memory triangle? Do you know the memory formula for HNSW? Can you reason about when to apply PQ and what quality you're trading? Do you know operational concerns like monitoring recall drift?

**Model answer for "you're asked to serve 100M 1536-d vectors with < 10ms p99 and ≥ 95% recall@10. What are your index choices and hardware requirements?"**:

*"Let me work through the options. HNSW at 100M × 1536d × FP32 = 614GB + graph overhead = ~650GB — that's a very large memory footprint. I'd first apply SQ8 to bring it to ~154GB, then add HNSW graph overhead to ~160GB total. With 3 QueryNodes at r5.4xlarge (128GB each), I can distribute 160GB across nodes with replicas for read scaling. Parameters: M=32, ef_construction=256, ef=128 for production. I'd verify Recall@10 ≥ 95% on a held-out evaluation set — if short, bump ef to 256. If 160GB is still too expensive (r5.4xlarge is ~$1/hour each = $2K/month for 3 nodes), I'd consider IVF_PQ: nlist=65536, m=192, nbits=8 → ~192 bytes/vector → 19.2GB for all vectors. With nprobe=128, Recall@10 ≈ 92–95% — marginal, but may meet SLO with higher nprobe. The HNSW+SQ8 path gives better and more predictable recall; IVF_PQ is the memory-constrained fallback."*

---

## Related Files

- [01-architecture.md](01-architecture.md) — index algorithms explained with full theory
- [02-read-write-path.md](02-read-write-path.md) — segment lifecycle, how seal threshold affects ingestion
- [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) — system selection, CAP analysis
- [05-production-and-research.md](05-production-and-research.md) — company-scale deployments and operational lessons
