# Milvus — Usage, Query Patterns, Deployment & Scaling
> Milvus 2.4.x / PyMilvus 2.4 SDK reference with production patterns

---

## Part 1: Core Concepts Mapping

Before diving into code, understand how Milvus maps to familiar database concepts:

```
Relational DB        Milvus Equivalent       Notes
─────────────────────────────────────────────────────────────────
Database          ←→ Database                Multi-tenant namespace
Table             ←→ Collection              Fixed schema at creation; can have dynamic fields
Row               ←→ Entity                  One entity = one vector + its metadata fields
Column            ←→ Field                   Typed; one field must be a VectorField
Primary Key       ←→ Primary Key (int64/varchar)  auto_id=True auto-generates PKID
Index             ←→ Index (per vector field) HNSW / IVF_FLAT / IVF_PQ / SCANN / DiskANN
Partition         ←→ Partition               Physical sub-division within a collection
View              ←→ Alias                   Collection alias, swappable atomically
Transaction       ←→ Consistency Level       Bounded / Session / Strong / Eventually
```

---

## Part 2: Collection Schema Design

### Creating a Collection — Full Schema Pattern

```python
from pymilvus import (
    connections, Collection, CollectionSchema, FieldSchema,
    DataType, utility
)

# 1. Connect
connections.connect(
    alias="default",
    host="localhost",
    port="19530",
    # For Zilliz Cloud:
    # uri="https://<cluster>.zillizcloud.com",
    # token="<api_key>",
)

# 2. Define fields
fields = [
    # Primary key — always required
    FieldSchema(
        name="product_id",
        dtype=DataType.VARCHAR,
        max_length=64,
        is_primary=True,
        auto_id=False          # we supply our own IDs (e.g., ASINs)
    ),

    # Scalar metadata fields (for filtering)
    FieldSchema(name="category",      dtype=DataType.VARCHAR,  max_length=128),
    FieldSchema(name="brand",         dtype=DataType.VARCHAR,  max_length=128),
    FieldSchema(name="price",         dtype=DataType.FLOAT),
    FieldSchema(name="avg_rating",    dtype=DataType.FLOAT),
    FieldSchema(name="review_count",  dtype=DataType.INT64),
    FieldSchema(name="in_stock",      dtype=DataType.BOOL),
    FieldSchema(name="launch_ts",     dtype=DataType.INT64),   # epoch seconds
    FieldSchema(name="marketplace",   dtype=DataType.VARCHAR,  max_length=8),

    # JSON field for flexible attributes (Milvus 2.2+)
    FieldSchema(name="attributes",    dtype=DataType.JSON),

    # Dense vector from a text/image embedding model (e.g., 768-dim CLIP)
    FieldSchema(
        name="product_embedding",
        dtype=DataType.FLOAT_VECTOR,
        dim=768
    ),

    # Sparse vector for BM25-style lexical matching (Milvus 2.4+)
    FieldSchema(
        name="sparse_embedding",
        dtype=DataType.SPARSE_FLOAT_VECTOR   # variable-length sparse; no dim needed
    ),
]

# 3. Create schema
schema = CollectionSchema(
    fields=fields,
    description="Amazon product catalogue — dense + sparse hybrid search",
    enable_dynamic_field=True    # allows inserting fields not in schema; stored in $meta JSON
)

# 4. Create collection
collection = Collection(
    name="products",
    schema=schema,
    using="default",
    shards_num=4,               # partition shards for parallel ingest/search
    consistency_level="Bounded" # Bounded | Session | Strong | Eventually
)
print(f"Collection created: {utility.get_collection_stats('products')}")
```

### Consistency Level Trade-offs

| Level | Guarantee | Latency Impact | Best For |
|-------|-----------|---------------|----------|
| `Strong` | Read-your-own-write; latest snapshot always visible | Highest (+20–50ms) | Financial, inventory — correctness > speed |
| `Session` | Reads within the same session see all prior writes from that session | Medium | User-facing search after they update preferences |
| `Bounded` | Reads lag behind writes by at most `max_lag` (default 5s) | Low | Product search — 5s lag acceptable |
| `Eventually` | No freshness guarantee; lowest overhead | Lowest | Analytics, batch export, non-critical reads |

**Production default**: Use `Bounded` for search (invisible lag is fine), `Strong` for inventory checks.

---

## Part 3: Index Creation — All Supported Types

### Index Type Reference

| Index | Algorithm | Memory | Build Time | Query Speed | Recall | Best For |
|-------|-----------|:------:|:----------:|:-----------:|:------:|----------|
| `FLAT` | Exact brute-force scan | High (full FP32) | None | Slowest | 100% (baseline) | Benchmarking, < 100K vectors |
| `IVF_FLAT` | K-means clustering + flat lists | High | Moderate | Fast | High (95–99%) | 1M–50M, high recall required |
| `IVF_SQ8` | IVF + scalar quantization (FP32→INT8) | 4× smaller | Moderate | Fast | Good (92–97%) | Memory-constrained, acceptable recall |
| `IVF_PQ` | IVF + product quantization | 8–64× smaller | Slow | Moderate | Moderate (88–95%) | Billion-scale, memory budget critical |
| `HNSW` | Hierarchical Navigable Small Worlds graph | High (graph overhead) | Slow | Fastest | Highest (97–99.5%) | Latency-critical < 500M vectors |
| `SCANN` | Google's ScaNN (tree-AH) | Medium | Fast | Very fast | High | Billion-scale with speed priority |
| `DiskANN` | Graph-based, index stored on NVMe SSD | Very low (RAM) | Very slow | Moderate (NVMe bound) | High | Trillion-scale, RAM-constrained |
| `GPU_IVF_FLAT` | IVF on GPU VRAM | GPU-dependent | Fast (GPU) | Very fast | High | GPU-accelerated clusters |
| `GPU_CAGRA` | CUDA-native graph index | GPU-dependent | Very fast | Fastest | Very high | GPU-heavy search infra |
| `BIN_FLAT` | Exact Hamming distance scan | Low (binary) | None | Fast (POPCOUNT) | 100% | Binary embeddings |
| `BIN_IVF_FLAT` | IVF + Hamming | Low | Moderate | Fast | High | Scaled binary embeddings |

### Creating HNSW Index (Production Default for < 500M)

```python
# Dense vector index — HNSW
index_params_dense = {
    "metric_type": "IP",              # IP (inner product) = cosine after normalization
    "index_type": "HNSW",
    "params": {
        "M": 32,                       # edges per layer; higher = better recall, more RAM
        "efConstruction": 256          # beam width at build; higher = better quality; irreversible
    }
}
collection.create_index(
    field_name="product_embedding",
    index_params=index_params_dense,
    index_name="hnsw_dense"
)

# Sparse vector index (Milvus 2.4+)
index_params_sparse = {
    "metric_type": "IP",
    "index_type": "SPARSE_INVERTED_INDEX",
    "params": { "drop_ratio_build": 0.2 }  # discard bottom 20% sparse weights at build for speed
}
collection.create_index(
    field_name="sparse_embedding",
    index_params=index_params_sparse,
    index_name="sparse_bm25"
)

# Scalar field indexes for metadata filtering (critical for performance)
collection.create_index(field_name="category",     index_name="idx_category")
collection.create_index(field_name="price",        index_name="idx_price")
collection.create_index(field_name="in_stock",     index_name="idx_in_stock")
collection.create_index(field_name="launch_ts",    index_name="idx_launch_ts")
```

### IVF_PQ for Billion-Scale

```python
index_params_ivfpq = {
    "metric_type": "IP",
    "index_type": "IVF_PQ",
    "params": {
        "nlist": 65536,   # number of Voronoi cells (clusters); rule: sqrt(n_vectors)
        "m": 8,           # number of sub-quantizers; must divide dim evenly; 768/8=96 sub-vectors
        "nbits": 8        # bits per sub-quantizer code; 8 = 256 centroids per sub-space
        # Memory per vector = m × nbits/8 = 8 bytes (vs 3072 bytes FP32 for d=768)
        # 100M vectors × 8 bytes = 800 MB vs 307 GB uncompressed — 384× reduction
    }
}
```

### DiskANN for Trillion-Scale (NVMe Required)

```python
index_params_diskann = {
    "metric_type": "L2",
    "index_type": "DISKANN",
    "params": {
        "search_list": 100,      # candidate list size (recall vs latency)
        # Stores graph index on NVMe SSD; only navigational metadata in RAM
        # ~80 bytes/vector in RAM vs 3200 bytes/vector for HNSW
    }
}
```

---

## Part 4: Inserting Data

### Batch Insert (Production Pattern)

```python
import numpy as np

# Load collection into memory before any operation
collection.load()

# Simulate embedding generation
def generate_mock_data(n: int, dim: int = 768):
    vecs = np.random.rand(n, dim).astype("float32")
    # L2-normalize for cosine via inner product
    norms = np.linalg.norm(vecs, axis=1, keepdims=True)
    return (vecs / norms).tolist()

BATCH_SIZE = 10_000
total_inserted = 0

for batch_start in range(0, 1_000_000, BATCH_SIZE):
    batch_ids = [f"B{str(batch_start + i).zfill(10)}" for i in range(BATCH_SIZE)]

    entities = [
        batch_ids,                                      # product_id
        ["Electronics"] * BATCH_SIZE,                  # category
        ["BrandX"] * BATCH_SIZE,                        # brand
        [float(np.random.uniform(5, 500))] * BATCH_SIZE,  # price
        [float(np.random.uniform(3.5, 5.0))] * BATCH_SIZE, # avg_rating
        [int(np.random.randint(100, 50000))] * BATCH_SIZE,  # review_count
        [True] * BATCH_SIZE,                            # in_stock
        [int(1700000000 + i) for i in range(BATCH_SIZE)],  # launch_ts
        ["US"] * BATCH_SIZE,                            # marketplace
        [{"color": "black", "size": "M"}] * BATCH_SIZE, # attributes (JSON)
        generate_mock_data(BATCH_SIZE, 768),            # product_embedding
        # sparse_embedding omitted here — use BM25 encoder separately
    ]

    mr = collection.insert(entities)
    total_inserted += len(mr.primary_keys)

collection.flush()   # ensure segments sealed and persisted before search
print(f"Inserted {total_inserted:,} entities")
```

### Upsert (Update or Insert)

```python
# Milvus 2.3+: upsert replaces existing entity with same primary key
collection.upsert([
    ["ASIN_B001"],         # product_id
    ["Toys"],              # category
    ["ToyBrand"],          # brand
    [19.99],               # price
    [4.3],                 # avg_rating
    [250],                 # review_count
    [True],                # in_stock
    [1710000000],          # launch_ts
    ["US"],                # marketplace
    [{"color": "red"}],    # attributes
    [generate_mock_data(1, 768)[0]],  # product_embedding
])
```

### Delete by Primary Key or Expression

```python
# Delete by primary key list
collection.delete(expr='product_id in ["ASIN_B001", "ASIN_B002"]')

# Delete by scalar filter (Milvus 2.3+)
collection.delete(expr='in_stock == false AND launch_ts < 1680000000')
```

---

## Part 5: Query Pattern Types — Complete Reference

### Pattern 1: Pure ANN Search (No Filter)

```python
results = collection.search(
    data=[query_vector],              # list of query vectors; batch up to 16384
    anns_field="product_embedding",   # which vector field to search
    param={
        "metric_type": "IP",
        "params": { "ef": 128 }       # HNSW query beam width; higher = better recall
    },
    limit=10,                         # top-K results
    output_fields=["product_id", "category", "price", "avg_rating"]
)

for hit in results[0]:
    print(f"ID={hit.id}  score={hit.score:.4f}  price={hit.entity.get('price')}")
```

**When to use**: Semantic similarity without business constraints. Rare in production — almost always combined with filters.

---

### Pattern 2: Filtered ANN Search (Most Common Production Pattern)

Pre-filtering vs post-filtering vs in-graph filtering:

```
Pre-filtering (Milvus default for scalar fields):
  1. Evaluate scalar filter → get matching entity set as bitmap
  2. Execute ANN search on the filtered subset only
  Advantage: exact — results all satisfy the filter
  Risk: if filter is very selective (< 1% match), ANN graph traversal degrades
        (not enough neighbours in the subgraph)

Post-filtering (fallback strategy):
  1. Execute ANN search → get top-K×factor candidates
  2. Filter candidates by scalar predicate
  3. Return top-K after filtering
  Risk: actual result count < K if filter is very selective

In-graph filtering (HNSW with filtering):
  Navigate graph but skip nodes that don't match filter
  Milvus 2.3+ uses this adaptively when filter ratio > 0.1%
```

```python
# Filtered search — products in Electronics, price $20–$200, in stock
results = collection.search(
    data=[query_vector],
    anns_field="product_embedding",
    param={"metric_type": "IP", "params": {"ef": 200}},
    limit=20,
    expr='category == "Electronics" and price >= 20.0 and price <= 200.0 and in_stock == true',
    output_fields=["product_id", "brand", "price", "avg_rating"],
    consistency_level="Bounded"
)
```

**Filter expression syntax**:

```python
# Comparison operators
'price > 50'
'avg_rating >= 4.0'
'review_count between 100 and 10000'   # inclusive range shorthand

# Logical operators
'category == "Electronics" and brand != "Banned_Brand"'
'price < 20 or (price > 100 and avg_rating > 4.5)'
'not in_stock == false'

# IN / NOT IN
'brand in ["Apple", "Samsung", "Sony"]'
'marketplace not in ["DE", "FR"]'

# String operations
'category like "Elec%"'                # prefix match
'brand like "%Pro"'                    # suffix match (expensive — full scan)

# JSON field access (Milvus 2.2+)
'attributes["color"] == "black"'
'attributes["size"] in ["M", "L", "XL"]'
'JSON_CONTAINS(attributes["tags"], "wireless")'

# ARRAY field operations
'ARRAY_CONTAINS(category_path, "Home & Kitchen")'
'ARRAY_LENGTH(images) > 0'

# Null checks
'description_embedding is not null'
```

---

### Pattern 3: Range Search (Distance-Bounded)

```python
# Return ALL vectors within a distance threshold, up to limit
results = collection.search(
    data=[query_vector],
    anns_field="product_embedding",
    param={
        "metric_type": "IP",
        "params": {
            "ef": 256,
            "radius": 0.7,           # minimum similarity score (IP); include if score >= radius
            "range_filter": 0.99     # maximum similarity score; exclude if score > range_filter
            # For L2: radius = max distance (include if distance <= radius)
            #         range_filter = min distance (exclude if distance < range_filter)
        }
    },
    limit=100,                       # cap on returned results within range
    output_fields=["product_id", "price"]
)
# Use case: "find all products semantically similar enough to this one (score >= 0.7)"
# Not "top-K most similar" — every result in the band
```

---

### Pattern 4: Metadata-Only Query (No Vector)

```python
# Pure scalar query — no vector involved, like a SQL SELECT WHERE
results = collection.query(
    expr='category == "Books" and price < 15.0 and avg_rating > 4.2',
    output_fields=["product_id", "brand", "price", "avg_rating"],
    limit=100,
    offset=0,
    consistency_level="Strong"
)
# Returns list of dicts; no similarity scores
```

---

### Pattern 5: Hybrid Search — Dense + Sparse (BM25 + Semantic)

Milvus 2.4 introduces first-class hybrid search combining dense ANN + sparse inverted index with weighted reranking:

```python
from pymilvus import AnnSearchRequest, RRFRanker, WeightedRanker

# Dense search request
dense_req = AnnSearchRequest(
    data=[dense_query_vector],          # float32 normalized vector (768-dim)
    anns_field="product_embedding",
    param={"metric_type": "IP", "params": {"ef": 128}},
    limit=50,                           # candidates from dense leg
    expr='in_stock == true'
)

# Sparse search request (BM25 lexical matching)
sparse_req = AnnSearchRequest(
    data=[sparse_query_vector],         # sparse float vector from BM25/SPLADE tokenizer
    anns_field="sparse_embedding",
    param={"metric_type": "IP", "params": {"drop_ratio_search": 0.2}},
    limit=50                            # candidates from sparse leg
)

# Reranking strategy 1: Reciprocal Rank Fusion (positional, no score calibration needed)
results = collection.hybrid_search(
    reqs=[dense_req, sparse_req],
    rerank=RRFRanker(k=60),            # RRF formula: score = Σ 1/(k + rank_i)
    limit=10,
    output_fields=["product_id", "brand", "price", "avg_rating"]
)

# Reranking strategy 2: Weighted linear combination (requires calibrated scores)
results = collection.hybrid_search(
    reqs=[dense_req, sparse_req],
    rerank=WeightedRanker(0.6, 0.4),   # 60% dense weight, 40% sparse weight
    limit=10,
    output_fields=["product_id", "price"]
)
```

**Sparse vector generation for BM25** (typical pattern using `milvus_model` library):

```python
from milvus_model.sparse.bm25.tokenizers import build_default_analyzer
from milvus_model.sparse import BM25EmbeddingFunction

# Build BM25 analyzer on your corpus (fit IDF weights)
analyzer = build_default_analyzer(language="en")
bm25_ef = BM25EmbeddingFunction(analyzer)

# Fit on corpus to learn IDF weights
bm25_ef.fit(product_title_corpus)
bm25_ef.save("bm25_params.json")

# At insert time: generate sparse vector
sparse_vecs = bm25_ef.encode_documents(["Wireless Bluetooth Headphones Noise Cancelling"])
# sparse_vecs is a scipy.sparse CSR matrix — Milvus handles natively

# At query time: generate sparse query vector
sparse_query = bm25_ef.encode_queries(["bluetooth headphones"])
```

---

### Pattern 6: Multi-Vector Search

A collection can have multiple vector fields. Search on one; or run separate searches on different fields and merge:

```python
# Collection with both image and text embeddings
# text_embedding (dim=768): from text descriptions
# image_embedding (dim=512): from product images (CLIP)

# Text query
text_results = collection.search(
    data=[text_query_vec],
    anns_field="text_embedding",
    param={"metric_type": "IP", "params": {"ef": 128}},
    limit=20
)

# Image query (reverse image search — user uploads photo)
image_results = collection.search(
    data=[image_query_vec],
    anns_field="image_embedding",
    param={"metric_type": "IP", "params": {"ef": 128}},
    limit=20
)

# Application-layer fusion (RRF or learned model)
```

---

### Pattern 7: Batch/Multi-Query Search

```python
# Search for multiple query vectors in a single RPC — reduces round-trip overhead
query_vectors = [embedding_model.encode(q) for q in [
    "wireless noise cancelling headphones",
    "running shoes waterproof",
    "4K gaming monitor 144hz"
]]

# Single call, returns list of result lists (one per query)
batch_results = collection.search(
    data=query_vectors,               # up to 16,384 queries in one batch
    anns_field="product_embedding",
    param={"metric_type": "IP", "params": {"ef": 128}},
    limit=10,
    expr='in_stock == true',
    output_fields=["product_id", "price"]
)

for q, results in zip(query_vectors, batch_results):
    print(f"Query results: {[hit.id for hit in results]}")
```

---

### Pattern 8: Partitioned Search (Multi-Tenancy / Category Isolation)

```python
# Create partitions at collection creation or dynamically
collection.create_partition("Electronics")
collection.create_partition("Clothing")
collection.create_partition("Books")
collection.create_partition("Home_Kitchen")

# Insert into a specific partition
collection.insert(entities, partition_name="Electronics")

# Search within a partition only — reduces search scope dramatically
results = collection.search(
    data=[query_vector],
    anns_field="product_embedding",
    param={"metric_type": "IP", "params": {"ef": 128}},
    limit=10,
    partition_names=["Electronics"],   # search only Electronics shard
    output_fields=["product_id", "price"]
)

# Search across multiple partitions
results = collection.search(
    data=[query_vector],
    anns_field="product_embedding",
    param={"metric_type": "IP", "params": {"ef": 128}},
    limit=10,
    partition_names=["Electronics", "Clothing"],
    output_fields=["product_id", "price"]
)
```

**Partition key pattern (Milvus 2.2.9+)**: Automatically route entities to partitions based on a field value:

```python
# Define partition_key_field in schema
FieldSchema(name="marketplace", dtype=DataType.VARCHAR, max_length=8, is_partition_key=True)
# Milvus automatically hashes marketplace value to one of N internal partitions (default 16)
# Queries with 'marketplace == "US"' automatically narrow to the right partition
```

---

### Pattern 9: Iterator / Cursor for Large Result Sets

```python
from pymilvus import Collection

# When you need > 16,384 results (e.g., bulk export, re-embedding)
iterator = collection.search_iterator(
    data=[query_vector],
    anns_field="product_embedding",
    param={"metric_type": "IP", "params": {"ef": 256}},
    batch_size=1000,              # results per page
    limit=100_000,                # total results to iterate through
    output_fields=["product_id"],
    expr='category == "Electronics"'
)

all_results = []
while True:
    batch = iterator.next()
    if not batch:
        break
    all_results.extend(batch)
    print(f"Fetched {len(all_results)} so far...")

iterator.close()
```

---

### Pattern 10: Async Search (High-Throughput Applications)

```python
import asyncio
from pymilvus import AsyncMilvusClient

async def search_product(client, query_vec, filters):
    results = await client.search(
        collection_name="products",
        data=[query_vec],
        anns_field="product_embedding",
        search_params={"metric_type": "IP", "params": {"ef": 128}},
        limit=10,
        filter=filters,
        output_fields=["product_id", "price"]
    )
    return results

async def batch_concurrent_search(queries):
    client = AsyncMilvusClient(uri="http://localhost:19530")
    tasks = [
        search_product(client, vec, f'category == "{cat}"')
        for vec, cat in queries
    ]
    results = await asyncio.gather(*tasks)   # all searches run concurrently
    await client.close()
    return results
```

---

## Part 6: Collection Management

### Alias — Zero-Downtime Schema Migration

```python
# Create alias pointing to v1
utility.create_alias(collection_name="products_v1", alias="products")

# Build and populate v2 (new schema, re-embedded vectors)
# ...

# Atomic alias swap — no downtime
utility.alter_alias(collection_name="products_v2", alias="products")
# All subsequent queries using alias "products" now hit products_v2

# Drop old collection after validation
utility.drop_collection("products_v1")
```

### Collection Statistics and Info

```python
# Check collection info
print(utility.get_collection_stats("products"))     # entity count per partition
print(collection.describe())                         # schema, shards, consistency

# Check index build progress
utility.index_building_progress("products", index_name="hnsw_dense")
# Returns: {"total_rows": 1000000, "indexed_rows": 850000, "pending_index_rows": 150000}

# Wait until fully indexed
utility.wait_for_index_building_complete("products", index_name="hnsw_dense")

# Compact (merge small segments, purge deleted vectors)
collection.compact()
utility.wait_for_compaction_completed("products")
```

### Load and Release

```python
# Load into memory with specific replica count (for high-QPS)
collection.load(replica_number=2)    # 2 in-memory replicas across QueryNodes

# Load specific partitions only (save memory)
collection.load(partition_names=["Electronics", "Clothing"])

# Release from memory (frees QueryNode RAM)
collection.release()
```

---

## Part 7: Deployment Modes

### Mode 1: Milvus Standalone (Single Node — Dev / Small Production)

```
Architecture:
  ┌───────────────────────────────────────────────────────┐
  │  Milvus Standalone Container                          │
  │  ┌────────────┐  ┌──────────┐  ┌──────────────────┐  │
  │  │  Proxy     │  │  RootCrd │  │  DataCoord       │  │
  │  │  (API GW)  │  │          │  │  QueryCoord      │  │
  │  └────────────┘  └──────────┘  │  IndexCoord      │  │
  │                                └──────────────────┘  │
  │  ┌────────────────────────────────────────────────┐   │
  │  │  Embedded etcd  │  Embedded MinIO (object)     │   │
  │  └────────────────────────────────────────────────┘   │
  └───────────────────────────────────────────────────────┘

Suitable for: < 10M vectors, development, single-team, PoC
```

```yaml
# docker-compose.yml — Milvus Standalone
version: '3.7'
services:
  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls=http://0.0.0.0:2379
    volumes: ["etcd_data:/etcd"]

  minio:
    image: minio/minio:RELEASE.2023-03-13T19-46-17Z
    command: minio server /minio_data --console-address ":9001"
    environment:
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin
    volumes: ["minio_data:/minio_data"]

  standalone:
    image: milvusdb/milvus:v2.4.0
    command: ["milvus", "run", "standalone"]
    environment:
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
    ports:
      - "19530:19530"   # gRPC
      - "9091:9091"     # metrics (Prometheus)
    depends_on: [etcd, minio]

volumes:
  etcd_data:
  minio_data:
```

### Mode 2: Milvus Distributed (Kubernetes — Production)

```
Architecture (all components independently scalable):

  ┌──────────────────────────────────────────────────────────────────────────┐
  │                          Client Requests                                 │
  └─────────────────────────────┬────────────────────────────────────────────┘
                                │
                  ┌─────────────▼──────────────┐
                  │    Proxy (K8s Service LB)  │   ← stateless; scale freely
                  │    3–5 replicas            │
                  └─────────────┬──────────────┘
                                │
          ┌─────────────────────┼────────────────────────┐
          ▼                     ▼                        ▼
  ┌───────────────┐   ┌──────────────────┐   ┌──────────────────┐
  │  RootCoord   │   │   DataCoord      │   │   QueryCoord     │
  │  (1 active,  │   │   (metadata of   │   │  (search routing │
  │   1 standby) │   │   segments/shards│   │   & load balance)│
  └───────────────┘   └──────────────────┘   └──────────────────┘
          │                     │                        │
          │           ┌─────────▼──────────┐    ┌───────▼───────┐
          │           │  DataNodes (N)     │    │ QueryNodes (N) │
          │           │  [Ingest + flush]  │    │ [In-memory idx]│
          │           └─────────┬──────────┘    └───────┬───────┘
          │                     │                        │
          └─────────────────────▼────────────────────────┘
                         Message Queue (Pulsar / Kafka)
                         Object Storage (MinIO / S3 / GCS)
                         Metadata Store (etcd)
                         Index Storage (MinIO / S3)
```

**Helm deployment**:

```bash
# Add Milvus helm repo
helm repo add milvus https://zilliztech.github.io/milvus-helm/
helm repo update

# Install with production values
helm install milvus milvus/milvus \
  --namespace milvus --create-namespace \
  -f values-production.yaml
```

**`values-production.yaml` (key sections)**:

```yaml
cluster:
  enabled: true       # distributed mode

proxy:
  replicas: 3
  resources:
    requests: { cpu: "2", memory: "4Gi" }
    limits:   { cpu: "4", memory: "8Gi" }

queryNode:
  replicas: 6         # scale for search throughput
  resources:
    requests: { cpu: "8", memory: "64Gi" }   # memory = all loaded index segments
    limits:   { cpu: "16", memory: "128Gi" }

dataNode:
  replicas: 3         # scale for ingest throughput
  resources:
    requests: { cpu: "4", memory: "8Gi" }

indexNode:
  replicas: 2         # scale for index build speed
  resources:
    requests: { cpu: "8", memory: "16Gi" }

# External dependencies (use managed services in production)
etcd:
  enabled: false      # use external etcd cluster (3-node)
externalEtcd:
  enabled: true
  endpoints: ["etcd-0.etcd:2379", "etcd-1.etcd:2379", "etcd-2.etcd:2379"]

minio:
  enabled: false      # use S3 or GCS
externalS3:
  enabled: true
  host: "s3.amazonaws.com"
  port: 443
  useSSL: true
  bucketName: "milvus-prod"
  accessKey: ""       # use IAM role
  secretKey: ""
  useIAM: true

pulsar:
  enabled: true       # or use external Kafka
  broker:
    replicaCount: 3
  bookkeeper:
    replicaCount: 3
  zookeeper:
    replicaCount: 3
```

### Mode 3: Zilliz Cloud (Fully Managed)

```
Zilliz Cloud = Milvus-as-a-Service
  - Zero infrastructure ops
  - Auto-scaling QueryNodes
  - Serverless tier (pay-per-query) or Dedicated tier
  - Enterprise SLA + SOC2/ISO27001 compliance
  - Global regions: US-East, US-West, EU-West, AP-Southeast

Connection:
  from pymilvus import MilvusClient
  client = MilvusClient(
      uri="https://in01-abc123.aws-us-east-2.vectordb.zillizcloud.com",
      token="<user>:<password>"
  )
```

---

## Part 8: Scaling Patterns

### Scaling Reads (Query Throughput)

```
Bottleneck: QueryNode memory and CPU

Solution 1: Add QueryNode replicas
  - Each replica holds a full in-memory copy of the collection
  - QueryCoord load-balances search requests across replicas
  - Rule: QPS ÷ (QPS per QueryNode) = QueryNode count needed
  - Benchmark: single QueryNode serves ~1000–3000 QPS for HNSW at 10ms budget

Solution 2: Multiple in-memory replicas per collection shard
  collection.load(replica_number=3)
  - Creates 3 copies of each shard across available QueryNodes
  - Read QPS scales linearly with replica_number

Solution 3: Partition-based read isolation
  - Load only hot partitions (recent items, premium categories)
  - Release cold partitions; serve from object storage via DiskANN
  - Balance: memory cost vs latency per partition tier
```

### Scaling Writes (Ingest Throughput)

```
Bottleneck: DataNode segment flush + WAL throughput

Solution 1: Add DataNode replicas
  - Each collection shard is owned by one DataNode
  - Add shards (shards_num at creation) + DataNodes to increase parallel ingest
  - Rule: shards_num ≤ DataNode count (one DataNode can own multiple shards)

Solution 2: Bulk insert (offline) via Import API
  - Prepare data as Parquet files → upload to S3/MinIO
  - POST /collections/{name}/import  →  bypass WAL entirely
  - Throughput: 50M–500M vectors/hour (limited by S3 bandwidth + IndexNode capacity)
  - Use for initial load and large re-embedding jobs

Solution 3: Async streaming ingest
  - Client writes to Kafka; a consumer calls collection.insert() in batches
  - Decouples ingest burst from Milvus write capacity
  - Consumer batch size: 10K–100K vectors; flush every 1–5 seconds
```

### Scaling Index (Segment Build Throughput)

```
Bottleneck: IndexNode CPU for HNSW/IVF construction

Solution: Add IndexNode replicas
  - Index builds are embarrassingly parallel across segments
  - Rule: 2–4 IndexNodes typically sufficient; add if indexed_rows lags behind total_rows

Monitor:
  utility.index_building_progress("collection_name")
  # If indexed_rows << total_rows → add IndexNode or reduce segment size threshold
```

### Sharding Strategy

```
When to add shards (shards_num at creation — immutable):

Collection size → shards_num guideline:
  < 10M vectors   → 1–2 shards   (single DataNode)
  10M–100M        → 4 shards     (distribute write load)
  100M–1B         → 8–16 shards
  > 1B            → 16–64 shards (+ partition key for namespace isolation)

Rule: shards_num = max(2, ceil(expected_peak_write_QPS / 50_000))
```

### Memory Sizing Guide

```
Required QueryNode RAM = (vectors_in_collection × bytes_per_vector × replica_count) + overhead

Bytes per vector by index type (d=768):
  HNSW M=32:     ~3,200 bytes raw + 512 bytes graph = 3,712 bytes/vector
  IVF_FLAT:      ~3,072 bytes raw + 64 bytes centroid ref = 3,136 bytes/vector
  IVF_SQ8:       ~768 bytes (INT8 quantized) + centroid table
  IVF_PQ (m=8):  ~8 bytes compressed + ~12 KB centroid tables (shared)
  DiskANN:       ~80 bytes in RAM (navigational metadata only)

Example: 100M products, d=768, HNSW M=32, 2 replicas:
  100M × 3,712 bytes × 2 = 742 GB QueryNode RAM needed
  → 12 QueryNodes × 64 GB each, or fewer nodes with larger RAM
  → With IVF_PQ: 100M × 8B × 2 = 1.6 GB — 460× smaller (plus centroid tables)
```

---

## Part 9: Observability & Best Practices

### Prometheus Metrics (key metrics to alert on)

| Metric | Alert Condition | Meaning |
|--------|----------------|---------|
| `milvus_querynode_search_latency_ms{quantile="0.99"}` | > latency SLO | P99 search latency; tune `ef` or add QueryNode |
| `milvus_querynode_sq_queue_length` | > 100 | Search queue backing up; QueryNodes overloaded |
| `milvus_datanode_flush_seg_latency_ms` | > 30s | Flush slow; storage I/O or CPU bottleneck |
| `milvus_rootcoord_dml_channel_num` | < shards_num | Missing WAL channels; config issue |
| `milvus_indexnode_index_task_num` | continuously > 0 | Index build lagging; add IndexNode |
| `process_resident_memory_bytes` (QueryNode) | > 90% node RAM | OOM risk; reduce replica_number or switch to DiskANN |
| `etcd_server_leader_changes_seen_total` | > 0 | etcd instability; cluster state risk |

### Top 10 Production Best Practices

1. **Always create scalar field indexes** on every field used in `expr` filters — without them, filters cause full segment scans.

2. **Pre-normalize vectors** before inserting when using cosine similarity — use `METRIC_IP` after normalization instead of `COSINE` to avoid per-query normalization overhead.

3. **Set `ef_construction ≥ 200`** for HNSW. This is irreversible — a low-quality index cannot be improved without a full rebuild.

4. **Use `partition_key_field`** for multi-tenant workloads (one field value per tenant/category) — queries with the partition key filter skip irrelevant shards automatically.

5. **Batch inserts at 10K–100K entities per call**. Single-entity inserts create one segment per call → segment proliferation → high compaction overhead.

6. **Call `collection.flush()` after bulk load** before searching — unsealed growing segments are searched with brute force; flushed segments use the ANN index.

7. **Version-stamp embedding models**. Store the model name/version as a metadata field. When you upgrade the embedding model, all existing vectors become incompatible — you must re-embed and either rebuild the collection or use a versioned alias swap.

8. **Use `Bounded` consistency** for search (default `max_lag = 5s`) unless you need read-your-own-write. `Strong` consistency adds a 20–50ms latency penalty per query.

9. **Monitor `indexed_rows` vs `total_rows`**. Unsealed/unindexed rows are searched with brute force → latency spikes during heavy ingest periods.

10. **Size shards_num at collection creation** — it cannot be changed. Default is 1; use `shards_num = 4` for collections expected to grow beyond 10M vectors.
