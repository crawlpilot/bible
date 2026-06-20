# Case Study: Vector Search for Amazon.com Product Discovery
> A principal engineer-level system design showing how to layer semantic vector search
> on top of Amazon's existing search infrastructure at 350M+ product scale

---

## Problem Statement

Amazon.com has ~350 million product listings across 40+ categories, indexed via a large-scale inverted-index system (comparable to Elasticsearch at massive scale). BM25 lexical search works well for exact queries ("Sony WH-1000XM5") but fails for:

| Query Type | BM25 Failure Mode | Example |
|-----------|-------------------|---------|
| Semantic / intent queries | "something to block out office noise" → no lexical match to headphones | Returns nothing useful |
| Paraphrase queries | "earbuds for jogging" vs "running earphones" → miss due to vocabulary mismatch | Low recall |
| Visual search ("shop by photo") | User uploads a photo; BM25 has no image signal | Not possible |
| Cross-lingual search | Spanish query → English product titles → no overlap | Zero results |
| "More like this" recommendations | "show me similar items to what I just bought" | No similarity signal in BM25 |
| Long-tail / typo tolerance | Creative misspellings, new brand names | Requires fuzzy; poor ranking |

**Goal**: Add semantic vector search capability that boosts discovery without replacing the existing lexical index — hybrid retrieval that improves both recall and precision.

---

## Scale and SLOs

```
Scale:
  Products indexed:     350 million ASINs
  New products/day:     ~500K (continuous ingestion)
  Products updated/day: ~5M   (price, stock, ratings refreshes)
  Product images/ASIN:  avg 8 images × 350M = 2.8B image embeddings

Search traffic:
  Peak QPS:             500,000 queries/second (Black Friday)
  Steady-state QPS:     80,000 queries/second
  Query types:          60% text, 25% browse/navigation, 10% image, 5% voice

Latency SLOs:
  Text search p50:      < 30ms end-to-end (user-facing)
  Text search p99:      < 100ms
  Image search p99:     < 500ms (acceptable — feature is "experimental feel")
  Vector retrieval leg: < 15ms p99 (to leave budget for reranking and hydration)

Availability:
  Search uptime:        99.99% (< 53 minutes downtime/year)
```

---

## Architecture Overview

```
                        ┌─────────────────────────────┐
                        │        User Query            │
                        │  (text / image upload / voice│
                        └──────────────┬──────────────┘
                                       │
                        ┌──────────────▼──────────────┐
                        │       Query Gateway          │
                        │  (rate limit, auth, A/B gate)│
                        └──────┬───────────────┬───────┘
                               │               │
              ┌────────────────▼───┐    ┌──────▼──────────────────┐
              │  Query Processor   │    │   Embedding Service      │
              │  - intent classify │    │   (GPU inference fleet)  │
              │  - query expansion │    │   Text → 768-dim vec     │
              │  - spell correct   │    │   Image → 512-dim vec    │
              └──────┬─────────────┘    └──────┬───────────────────┘
                     │                         │
           ┌─────────▼───────────┐   ┌─────────▼────────────────────┐
           │  Lexical Retrieval  │   │   Vector Retrieval (Milvus)  │
           │  (Inverted Index /  │   │   - Dense ANN (text emb)     │
           │   BM25 + ES)        │   │   - Dense ANN (image emb)    │
           │  Top-1000 candidates│   │   - Sparse BM25 vector       │
           └─────────┬───────────┘   │   Hybrid RRF merge           │
                     │               │   Top-500 candidates          │
                     └──────────┬────┘
                                │
                  ┌─────────────▼──────────────────┐
                  │        Candidate Merger         │
                  │  Deduplicate, union, normalise  │
                  │  scores across retrieval legs   │
                  └─────────────┬──────────────────┘
                                │
                  ┌─────────────▼──────────────────┐
                  │       Reranking Service         │
                  │  - LambdaRank / GBDT model      │
                  │  - Features: BM25 score,        │
                  │    vector score, CTR, conversion,│
                  │    price, reviews, personalization│
                  │  Top-50 products                │
                  └─────────────┬──────────────────┘
                                │
                  ┌─────────────▼──────────────────┐
                  │      Business Logic Layer        │
                  │  - Ads injection                 │
                  │  - Compliance filters            │
                  │  - Diversity & dedup             │
                  │  - A/B experiment assignment     │
                  └─────────────┬──────────────────┘
                                │
                  ┌─────────────▼──────────────────┐
                  │        Product Hydration        │
                  │  Fetch title, images, price,    │
                  │  availability from product store│
                  └─────────────┬──────────────────┘
                                │
                        Final 20 results returned to user
```

---

## Component 1: Embedding Service

### Dual-Tower Model Architecture

Amazon's product embedding uses a **dual-tower (bi-encoder)** model — the standard industry pattern for scalable semantic retrieval:

```
Query Tower                    Product Tower
─────────────────────────────────────────────────────
Input: raw query text          Input: title + bullets + category + brand
  ↓                              ↓
BERT-based encoder             BERT-based encoder
(fine-tuned on Amazon          (fine-tuned on same
click/conversion data)         click/conversion data)
  ↓                              ↓
768-dim dense vector           768-dim dense vector
  ↓                              ↓
L2-normalize                   L2-normalize
  ↓                              ↓
Query embedding q              Product embedding p

Similarity: cosine(q, p) = q · p  (after normalization = inner product)

Training signal: positive pairs = (query, purchased product)
                 negative pairs = (query, random non-purchased products)
                                + hard negatives = top BM25 matches not purchased
Training loss: in-batch softmax (SimCSE / multi-negative ranking)
```

**Why dual-tower over cross-encoder?**
- Cross-encoder (query ++ product → single score) is more accurate but requires O(n) inference per query — infeasible at 350M products
- Dual-tower: product embeddings pre-computed offline; only the query tower runs at query time
- Trade-off: ~5–10% recall loss vs cross-encoder, 1000× faster

### GPU Inference Fleet

```
Traffic: 80K QPS × avg 15ms GPU inference = 1,200 concurrent GPU requests
GPU fleet sizing (per AWS p3.8xlarge: 4×V100, ~2,000 QPS text encoding):
  Steady state: 40 instances
  Black Friday: auto-scale to 250 instances (spot + on-demand mix)

Optimization stack:
  1. TensorRT: convert PyTorch BERT to TensorRT for 3-5× GPU speedup
  2. Dynamic batching: batch queries arriving in 5ms window (batch size 1-64)
  3. Sequence padding: pad to next power of 2 (32, 64, 128) to enable CUDA kernel fusion
  4. FP16 inference: 2× throughput, minimal recall degradation
  5. KV-cache for static prefix tokens (product category names, boilerplate)

Latency breakdown for text query:
  Tokenization:       0.5ms
  GPU inference:      8ms   (FP16, batch 32, max_len 64)
  L2 normalization:   0.1ms
  Total:             ~9ms
```

---

## Component 2: Offline Product Embedding Pipeline

### Ingestion Architecture

```
Product Catalog Events
  (new listing, price update, title change, image change)
         │
         ▼
   Amazon EventBridge / Kafka
   Topic: product-catalog-changes
         │
   ┌─────▼──────────────────────────────────────────────────────┐
   │  Embedding Pipeline (AWS Batch / Apache Spark on EMR)      │
   │                                                             │
   │  1. Consume from Kafka (batch window: 5 minutes)           │
   │  2. Fetch product attributes from product store            │
   │  3. Build text input: f"{title}. {brand}. {category}. {bullets[:200]}"│
   │  4. GPU-batch encode: 10K products/batch → 768-dim vectors │
   │  5. L2-normalize                                           │
   │  6. Write to Milvus (upsert by ASIN)                       │
   │  7. Write raw vectors + model version to S3 (archive)      │
   └─────────────────────────────────────────────────────────────┘
         │
         ▼
   Milvus Cluster (product_text_embeddings collection)
   + Milvus Cluster (product_image_embeddings collection)

Full re-embedding schedule:
  - Triggered by: embedding model upgrade, schema change
  - Frequency: every 3–6 months (model refresh cycle)
  - Method: build new collection → populate → alias swap → delete old
  - Duration: 350M products × 15ms/batch-10 = ~145 GPU-hours
              with 50 GPU nodes: ~3 hours wall clock
```

### Text Input Construction

```python
def build_product_text(product: dict) -> str:
    """
    Concatenate fields in order of relevance signal strength.
    Title carries the most semantic weight; cap total tokens at 128.
    """
    parts = [
        product.get("title", ""),
        product.get("brand", ""),
        product.get("category_path", "").replace(">", " "),
        " ".join(product.get("bullet_points", [])[:3]),  # first 3 bullets
        product.get("color", ""),
        product.get("size", ""),
    ]
    text = " ".join(p for p in parts if p).strip()
    # Truncate at ~500 characters (roughly 128 tokens for BERT)
    return text[:500]

# Example output:
# "Sony WH-1000XM5 Wireless Noise Canceling Overhead Headphones Sony Electronics
#  Headphones > Over-Ear Industry Leading Noise Canceling with Auto Noise Canceling
#  Optimizer Up to 30-Hour Battery Life Lightweight folding design Multipoint connection
#  Black One Size"
```

---

## Component 3: Milvus Collection Design

### Collection Schema

```python
from pymilvus import Collection, CollectionSchema, FieldSchema, DataType

# Collection 1: Text embeddings (primary search collection)
text_collection_schema = CollectionSchema(fields=[
    FieldSchema("asin",              DataType.VARCHAR,      max_length=16, is_primary=True),
    FieldSchema("marketplace",       DataType.VARCHAR,      max_length=4,  is_partition_key=True),
    FieldSchema("category_l1",       DataType.VARCHAR,      max_length=64),
    FieldSchema("category_l2",       DataType.VARCHAR,      max_length=64),
    FieldSchema("brand",             DataType.VARCHAR,      max_length=128),
    FieldSchema("price_usd_cents",   DataType.INT64),
    FieldSchema("avg_star_rating",   DataType.FLOAT),
    FieldSchema("review_count",      DataType.INT64),
    FieldSchema("is_prime",          DataType.BOOL),
    FieldSchema("is_in_stock",       DataType.BOOL),
    FieldSchema("launch_epoch",      DataType.INT64),
    FieldSchema("embedding_model_v", DataType.INT16),        # model version for staleness detection
    FieldSchema("text_embedding",    DataType.FLOAT_VECTOR, dim=768),
    FieldSchema("sparse_embedding",  DataType.SPARSE_FLOAT_VECTOR),
], enable_dynamic_field=True)

text_collection = Collection(
    name="product_text_embeddings_v3",
    schema=text_collection_schema,
    shards_num=16,              # 16 shards → 16 parallel write channels
    consistency_level="Bounded"
)

# Collection 2: Image embeddings (separate collection — different dim, update cadence)
image_collection_schema = CollectionSchema(fields=[
    FieldSchema("image_id",          DataType.VARCHAR,      max_length=32, is_primary=True),
    # image_id = f"{asin}_{image_sequence_number}"
    FieldSchema("asin",              DataType.VARCHAR,      max_length=16),
    FieldSchema("marketplace",       DataType.VARCHAR,      max_length=4,  is_partition_key=True),
    FieldSchema("is_primary_image",  DataType.BOOL),
    FieldSchema("category_l1",       DataType.VARCHAR,      max_length=64),
    FieldSchema("image_embedding",   DataType.FLOAT_VECTOR, dim=512),  # CLIP ViT-B/32
], enable_dynamic_field=False)

# Index configuration
text_collection.create_index("text_embedding", {
    "metric_type": "IP",
    "index_type": "HNSW",
    "params": {"M": 32, "efConstruction": 256}
}, index_name="hnsw_text")

text_collection.create_index("sparse_embedding", {
    "metric_type": "IP",
    "index_type": "SPARSE_INVERTED_INDEX",
    "params": {"drop_ratio_build": 0.1}
}, index_name="sparse_text")

# Scalar indexes for filtered search
for field in ["category_l1", "category_l2", "brand", "price_usd_cents",
              "avg_star_rating", "is_prime", "is_in_stock", "launch_epoch"]:
    text_collection.create_index(field, index_name=f"idx_{field}")
```

### Capacity Calculation

```
Text embedding collection:
  Entities:        350M ASINs × 1.2 (growth buffer) = 420M
  Vector storage:  420M × 768 × 4 bytes = 1.29 TB raw
  HNSW overhead:   420M × 512 bytes (M=32 edges) = 215 GB
  Scalar metadata: 420M × ~200 bytes avg = 84 GB
  Sparse vectors:  420M × avg 500 non-zero × 8 bytes = 1.68 TB
  Total on disk:   ~3.3 TB per replica
  QueryNode RAM for dense HNSW (1 replica):
    420M × (768×4 + 32×2×4) bytes = 420M × 3,328 bytes ≈ 1.4 TB
  → Too large for pure HNSW — use IVF_PQ or partition-per-marketplace

Optimized approach: IVF_PQ(nlist=131072, m=16, nbits=8)
  Compressed:      420M × 16 bytes = 6.7 GB  ← fits in 16 GB QueryNode!
  + centroid table: 131072 × 768 × 4 = 402 MB
  Total RAM needed: ~7.2 GB per replica (vs 1.4 TB with HNSW)
  Recall tradeoff:  ~92% vs 99% — acceptable for top-of-funnel retrieval
                    (reranker compensates for missed items)

Image embedding collection:
  Entities:        2.8B image embeddings (8 per ASIN)
  Vector dim:      512 (CLIP ViT-B/32)
  Storage:         2.8B × 512 × 4 = 5.7 TB raw
  → Use DiskANN: ~80 bytes/vec in RAM = 224 GB RAM total
                  (stored on NVMe SSD)
```

---

## Component 4: Query Execution Flow (Step by Step)

### Text Query: "wireless noise cancelling headphones under $100"

```
Step 1: Query Gateway (0.5ms)
  - Rate limit check (token bucket per user, 100 QPS)
  - A/B experiment assignment: user in "vector_search_treatment" group?
  - Route to Query Processor

Step 2: Query Processor (2ms)
  - Intent classification: "product search" (not browse, not reorder)
  - Price filter extraction: price_usd_cents <= 10000  (NER/regex)
  - Query expansion: "wireless noise cancelling headphones"
      + synonyms: "bluetooth ANC headphones"
      + category hint: "Electronics > Headphones"
  - Spell check: OK

Step 3: Parallel Retrieval (15ms — runs in parallel)

  Leg A: Lexical (BM25/inverted index)
    Query: "wireless noise cancelling headphones"
    Filter: price <= $100, in_stock=true, marketplace=US
    Returns: top-1000 ASINs with BM25 scores

  Leg B: Dense Vector ANN (Milvus — text embedding)
    Query vector: encode("wireless noise cancelling headphones") → 768-dim
    Search params: {
        "anns_field": "text_embedding",
        "metric_type": "IP",
        "params": {"nprobe": 256}      # IVF_PQ: probe 256 of 131072 clusters
    }
    Filter: 'is_in_stock == true and price_usd_cents <= 10000
              and marketplace == "US" and category_l1 == "Electronics"'
    limit: 500
    Returns: 500 (ASIN, similarity_score) pairs

  Leg C: Sparse Vector BM25 (Milvus — learned sparse)
    Query sparse vector: BM25EF.encode("wireless noise cancelling headphones")
    Returns: 500 (ASIN, sparse_score) pairs
    # Captures exact term matches that dense embedding may miss

  Leg D: Image Vector (if user attached photo — skip here)

Step 4: Candidate Merger (1ms)
  - Union of Leg A (1000), Leg B (500), Leg C (500) = up to 1500 unique ASINs
  - Deduplicate by ASIN
  - Normalize scores to [0, 1] per leg
  - Produce: { asin: {bm25_score, dense_score, sparse_score} } for ~1200 candidates

Step 5: Reranking Service (5ms)
  Model: LightGBM or Neural reranker
  Features per candidate:
    - bm25_score (lexical relevance)
    - dense_vector_score (semantic relevance)
    - sparse_vector_score (BM25 vector relevance)
    - user_affinity_score (collaborative filter — user's purchase/click history)
    - item_quality_score (weighted: avg_rating × log(review_count+1))
    - price_competitiveness (% below category median)
    - conversion_rate_30d (historical for this query category)
    - is_prime (strong positive feature)
    - listing_freshness (days since launch, negated — prefer newer)
    - exact_title_match_score (does query appear verbatim in title?)

  Output: top-50 ASINs with final_score

Step 6: Business Logic (1ms)
  - Sponsored products injection (slot 1, 5, 10, 16)
  - Compliance: remove adult, recalled, restricted items from market
  - Diversity: no more than 3 ASINs from same brand in top 10
  - Dedup: remove duplicate variations (color/size variants → show 1 representative)

Step 7: Hydration (3ms — async fan-out)
  - Fetch from product store: title, primary image URL, price, Prime badge, rating
  - Redis cache for hot products (> 1000 views/day): 1ms
  - Product store for cold products: 3ms

Total end-to-end: ~28ms p50  (within 30ms SLO)
                  ~85ms p99  (within 100ms SLO)
```

---

## Component 5: Image Search ("Shop by Photo")

### Flow

```
User uploads photo of a pair of shoes
           │
           ▼
  Image Preprocessing Service
  - Resize to 224×224
  - Center crop, normalize
           │
           ▼
  CLIP ViT-B/32 Image Encoder (GPU, ~50ms)
  - Output: 512-dim image embedding
  - L2-normalize
           │
           ▼
  Milvus: product_image_embeddings collection
  - Index: DiskANN (2.8B vectors, NVMe SSD)
  - Search: top-100 similar images
  - Filter: 'is_primary_image == true and marketplace == "US"'
  - Dedup: group by ASIN, keep highest similarity per ASIN
  - Result: 50 unique ASINs
           │
           ▼
  Retrieve ASIN text embeddings for these 50 candidates
  (join in application layer: asin → text metadata)
           │
           ▼
  Rerank: combine image_similarity + item_quality_score
           │
           ▼
  Return 20 visually similar products

Total: ~350ms p99 (acceptable for visual search — async UX)
```

### CLIP Dual Modality — Cross-Modal Search

Because CLIP embeds text and images into the **same vector space**, you can search image vectors with a text query and vice versa:

```python
# User types "red leather sneakers" → encode as CLIP text vector → search image collection
clip_text_vec = clip_model.encode_text("red leather sneakers")  # 512-dim

results = image_collection.search(
    data=[clip_text_vec],
    anns_field="image_embedding",
    param={"metric_type": "IP", "params": {"search_list": 200}},  # DiskANN
    limit=50,
    expr='is_primary_image == true and marketplace == "US"',
    output_fields=["asin", "category_l1"]
)
# Returns images of red leather sneakers even if product titles say "crimson"
# CLIP captures visual semantics, not text overlap
```

---

## Component 6: Personalized Vector Search

### User Preference Embedding

Amazon can build a per-user preference vector by aggregating past purchase/click embeddings:

```python
def compute_user_preference_vector(user_id: str, lookback_days: int = 90) -> np.ndarray:
    """
    Aggregate product embeddings of user's recent interactions.
    Use exponential time decay: recent interactions weighted more.
    """
    interactions = fetch_user_interactions(user_id, lookback_days)
    # interactions = list of (asin, interaction_type, timestamp, weight)
    # interaction_type: purchase=1.0, add_to_cart=0.6, click=0.2, view=0.1

    if not interactions:
        return None  # cold-start: fall back to non-personalized search

    # Fetch precomputed product embeddings from cache
    asins = [i["asin"] for i in interactions]
    product_vecs = fetch_embeddings_from_cache(asins)  # Redis / DynamoDB

    # Weighted average with time decay
    weights = []
    for interaction in interactions:
        age_days = (now - interaction["timestamp"]).days
        time_decay = np.exp(-age_days / 30)           # half-life ~30 days
        type_weight = interaction["weight"]
        weights.append(time_decay * type_weight)

    vecs = np.array([product_vecs[a] for a in asins])
    weights = np.array(weights)
    user_vec = np.average(vecs, weights=weights, axis=0)
    return user_vec / np.linalg.norm(user_vec)         # L2-normalize

# At search time: linear interpolation of query vector + user preference vector
def personalized_query_vector(query_vec, user_vec, alpha=0.3):
    """alpha=0: pure query semantics; alpha=1: pure user preference"""
    if user_vec is None:
        return query_vec
    combined = (1 - alpha) * query_vec + alpha * user_vec
    return combined / np.linalg.norm(combined)
```

---

## Component 7: Real-Time Embedding Updates

### The Staleness Problem

```
Products change constantly:
  - Price changes: 5M/day → update price metadata (cheap: Milvus upsert metadata only)
  - Title changes: 200K/day → re-embed + upsert (expensive: GPU inference required)
  - New listings: 500K/day → embed + insert
  - Delistings: 100K/day → delete from collection

Staleness tiers:
  CRITICAL (re-embed within 1 hour):
    - Title change > 10 edit-distance from original
    - Category change (primary taxonomy)
    - Brand change

  HIGH (re-embed within 6 hours):
    - Significant bullet-point change
    - New primary image

  LOW (update metadata only, no re-embed within 24 hours):
    - Price change
    - Stock status change
    - Rating/review count update

  IGNORE (never re-embed):
    - Seller name change
    - Internal operational fields
```

```python
# Kafka consumer for product change events
async def process_product_change(event: ProductChangeEvent):
    staleness_tier = classify_staleness(event)

    if staleness_tier == "LOW":
        # Fast path: update scalar fields only (no re-embedding)
        collection.upsert([
            [event.asin],
            [event.new_price_cents],
            [event.is_in_stock],
            [event.avg_star_rating],
            # ... other metadata fields
            # NOTE: do NOT include text_embedding — it stays unchanged
        ])
    else:
        # Expensive path: re-embed and upsert
        text = build_product_text(event.new_attributes)
        new_vec = await embedding_service.encode(text)  # GPU inference ~9ms
        collection.upsert([
            [event.asin],
            [event.new_price_cents],
            [event.is_in_stock],
            # ... all metadata
            [new_vec.tolist()]          # overwrite embedding
        ])
```

---

## Component 8: A/B Testing and Evaluation

### Offline Evaluation Pipeline

```
Ground truth:
  - 10M (query, purchased_ASIN) pairs from Amazon's historical click/purchase logs
  - Split: 8M train / 1M validation / 1M test

Metrics:
  Recall@10:   fraction of purchased items in top-10 results
               Baseline (BM25): 0.41
               BM25 + dense ANN: 0.61  (+49% relative improvement)
               BM25 + dense + sparse hybrid: 0.67 (+63% relative improvement)

  MRR@10:      mean reciprocal rank of first relevant result
               Baseline: 0.38
               Hybrid: 0.54

  NDCG@10:     normalized discounted cumulative gain (position-weighted)
               Baseline: 0.42
               Hybrid: 0.58

  Coverage:    fraction of queries with ≥1 relevant result
               Baseline: 0.78 (22% of queries get zero relevant results in BM25)
               Hybrid: 0.91 (9% zero-result rate — near-zero recall on long-tail)
```

### Online A/B Experiment Design

```
Experiment: "Vector Search Treatment"
  Control:    100% BM25 lexical retrieval
  Treatment:  70% BM25 + 30% vector ANN (hybrid RRF)

Allocation: 10% of US traffic (50M users/day sample)
Duration: 2 weeks (sufficient power for 1% GMV lift detection)

Primary metric:    GMV (gross merchandise value) per search session
Secondary metrics: CTR@1, CTR@3, Add-to-cart rate, zero-result rate
Guardrail metrics: Page latency p99 (must not increase > 5ms), error rate

Results after 2 weeks:
  GMV/session:       +3.2% (p<0.001) — statistically significant
  CTR@1:             +1.8%
  Zero-result rate:  -41% (from 4.2% → 2.5%)
  p99 latency:       +7ms (exceeded guardrail → optimize before full ramp)

Action: fix latency before full ramp (reduce nprobe from 512 to 256; add 2 QueryNodes)
```

---

## Infrastructure Sizing Summary

```
Milvus cluster for Amazon product search:

Component             Nodes   Spec                    Purpose
────────────────────────────────────────────────────────────────────────
Proxy                 6       8 vCPU / 16 GB          API gateway, load balance
RootCoord             2       4 vCPU / 8 GB           Leader + standby
QueryCoord            2       4 vCPU / 8 GB           Query routing
DataCoord             2       4 vCPU / 8 GB           Segment management
IndexCoord            2       4 vCPU / 8 GB           Index task scheduling
QueryNode             24      32 vCPU / 256 GB        In-memory IVF_PQ search
                              NVMe 2TB                (DiskANN for image coll)
DataNode              8       16 vCPU / 64 GB         Write + flush
IndexNode             6       32 vCPU / 128 GB        HNSW/IVF build
                              GPU optional (CAGRA)
────────────────────────────────────────────────────────────────────────
External dependencies:
  etcd:               3-node cluster (high availability cluster metadata)
  Kafka/Pulsar:       6-broker cluster (WAL for all write operations)
  S3 (MinIO-compat):  3.3 TB text embeddings + 5.7 TB image embeddings
  Redis:              100 GB (hot product embedding cache, query result cache)

Total RAM (QueryNodes): 24 × 256 GB = 6.1 TB
  420M products × 16 bytes IVF_PQ = 6.7 GB per replica (text)
  420M products × replica_count 3 = 20 GB text collection in RAM
  2.8B images × DiskANN RAM = 224 GB in RAM (NVMe spill for rest)

Peak throughput:
  Write: 500K products/day = ~6 ASINs/second → trivial for 8 DataNodes
  Search: 80K QPS / 24 QueryNodes = 3,333 QPS per node
          Benchmark: IVF_PQ nprobe=256 at d=768 = ~3,500 QPS/node ✓
```

---

## Key Engineering Lessons

### 1. Retrieval is a Recall Problem; Reranking is a Precision Problem

> "Don't optimize your vector retrieval for precision — optimize for recall. Get 500 good candidates, not 20 perfect ones. The reranker is orders of magnitude cheaper per-candidate than retrieval is per-query. A 92% recall retriever that returns 500 candidates feeds a reranker that achieves 99% NDCG in the final 20. A 99% recall retriever returning 20 directly is a false economy — the first missed relevant item at position 11 is a lost sale."

### 2. The Embedding Model IS the Schema

> "When you upgrade the embedding model (e.g., ada-002 → text-embedding-3-large), every stored vector becomes incompatible with new query vectors. Plan for this from day 1: store `embedding_model_version` as a field; use collection aliases for zero-downtime swaps; maintain a re-embedding pipeline. We got burned once by mixing query vectors from model v2 with stored vectors from model v1 — search quality silently degraded 30% before we caught it in metrics."

### 3. Filtered ANN Degrades at High Selectivity

> "When a filter selects < 0.1% of the collection (e.g., search within one specific brand that has 5000 products out of 350M), the ANN graph has too few neighbours to navigate. Milvus falls back to brute force within the filtered set. Design for this: if a use case always searches within a narrow namespace, use a separate collection or a partition — not a filter on a global collection."

### 4. Separate Collections for Separate Update Cadences

> "Text embeddings and image embeddings have completely different update patterns. Text embeddings change when product titles/bullets change (~200K/day). Image embeddings change when product images change (~50K/day). Mixing them in one collection means every text update forces a write to the image embedding too, or you maintain complex partial-update logic. Keep them separate. The alias join at query time costs < 1ms."

### 5. Cold Start: BM25 is Your Safety Net

> "On day 1, your embedding model has zero production fine-tuning. BM25 has years of query logs baked into its relevance tuning. Launch with hybrid search at 30% vector weight, 70% BM25. Increase vector weight as you validate recall improvement in A/B tests. Never remove BM25 entirely — it handles exact product ID lookups ('ASIN B07XJ8C8F5') and product title verbatim queries perfectly, where vector search adds noise."

---

## FAANG Interview Callout

**Question**: "How would you add semantic search to Amazon.com without breaking existing search?"

**Structured answer**:

> "I'd layer vector retrieval on top of the existing BM25 index as a second retrieval leg, not a replacement. The key insight is that retrieval and ranking are separate concerns. BM25 already works well for navigational and exact queries. Vector search adds value for semantic and discovery queries. So the architecture is: parallel retrieval from both systems → candidate merger → unified reranker. This is the two-tower retrieve-then-rerank pattern used at every FAANG at scale.
>
> For Milvus at 350M products: I'd use IVF_PQ with nlist=131072 and m=16 quantization — this compresses 1.4 TB of HNSW memory to ~7 GB per replica, making the collection feasible on standard 256 GB QueryNodes. We accept 7% recall loss (92% vs 99%), which is compensated by the reranker downstream.
>
> The hardest operational problem is embedding freshness: 5M product updates/day need to be reflected in search. I'd categorise updates into re-embed-required vs metadata-only-update tiers, and process via a Kafka-fed streaming pipeline, using Milvus upsert for metadata changes and full vector upsert when the product text changes significantly.
>
> The A/B test measures GMV/session as the primary metric, with p99 latency as a guardrail. I'd start with 10% traffic, 30% vector weight in the hybrid blend, and increase after validating no latency regression."
