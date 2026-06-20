# Vector Retrieval Patterns — Retrieval, Re-ranking, Ingestion, and Evaluation

> **Scope**: Application-layer patterns built on top of vector databases. Covers all major retrieval strategies (dense, sparse, hybrid, HyDE, RAG variants, agentic), re-ranking techniques, ingestion pipeline patterns, and evaluation frameworks. Written for both principal engineers designing retrieval systems and practitioners implementing their first RAG pipeline.

---

## Part A: Retrieval Techniques

### The Retrieval Quality Problem

Even with a perfect vector database and excellent embedding model, retrieval quality is often the primary bottleneck in RAG systems. The gap between what users ask and what documents contain has multiple dimensions:

1. **Vocabulary mismatch**: User says "neural network", document says "deep learning model"
2. **Query-document asymmetry**: Short queries vs long document passages live in different regions of the embedding space
3. **Bi-encoder recall ceiling**: Single-vector representation compresses context; cross-encoder (which sees both query+doc together) is more accurate but too slow for full-corpus retrieval
4. **Multi-hop dependencies**: The answer requires reasoning across multiple documents, not a single retrieval

Each retrieval strategy below addresses one or more of these failure modes.

---

### Strategy 1: Dense Retrieval (Bi-Encoder, Baseline)

The foundation of modern semantic search. Embed query and all documents independently; search by ANN.

```
Architecture:
  Offline: embed_document(d_i) → vector_i → store in vector DB
  Online:  embed_query(q)     → q_vec   → ANN search → top-K doc IDs

Properties:
  - O(1) retrieval (ANN sub-linear)
  - Query and document embeddings are independent (parallelizable)
  - Recall limited by single-vector representation quality
  - "Recall ceiling" problem: BEIR benchmark shows ~65% nDCG@10 for best bi-encoders
```

**When dense retrieval alone is enough**:
- Domain-general queries where vocabulary aligns with training data
- When recall@10 ≥ 90% on held-out test set
- When re-ranking latency budget doesn't allow two-stage pipeline

---

### Strategy 2: Sparse Retrieval (BM25)

Traditional TF-IDF-based ranking with length normalization. Still a powerful signal for exact keyword matching.

```python
# Elasticsearch BM25 retrieval
from elasticsearch import Elasticsearch

es = Elasticsearch(["http://localhost:9200"])

def bm25_search(query: str, index: str, top_k: int = 100) -> list[dict]:
    resp = es.search(
        index=index,
        query={"match": {"content": {"query": query, "operator": "or"}}},
        size=top_k
    )
    return [{"id": h["_id"], "score": h["_score"]} for h in resp["hits"]["hits"]]
```

**When sparse retrieval excels**:
- Named entity queries: "Microsoft Q2 2024 earnings" — exact match is critical
- Technical identifiers: function names, error codes, model numbers
- Low-resource domains where embedding models haven't been fine-tuned

---

### Strategy 3: SPLADE (Learned Sparse Embeddings)

**Paper**: "SPLADE: Sparse Lexical and Expansion Model for First Stage Retrieval" (Formal et al., 2021)

SPLADE uses a BERT-based encoder to produce sparse, weighted term vectors with semantic expansion.

```
SPLADE encoding:
  Input: "car engine repair"
  Output sparse vector:
    {"car": 2.1, "vehicle": 1.8, "automobile": 1.3,  ← expansion
     "engine": 2.4, "motor": 1.7,                     ← expansion
     "repair": 2.1, "fix": 1.4, "maintenance": 1.2}   ← expansion

Stores in inverted index (same as BM25) but with learned weights
Query at runtime: same inverted index lookup as BM25
```

**BM25 vs SPLADE**:

| | BM25 | SPLADE |
|---|---|---|
| Vocabulary expansion | No | Yes (semantic) |
| Encoding latency | None (term count) | ~50ms (BERT inference) |
| Index size | 1× | 3–5× (more terms per doc) |
| Recall on BEIR | ~43 nDCG@10 | ~68 nDCG@10 |
| Storage backend | Any inverted index | Any inverted index |
| Production infra | Elasticsearch, Solr | Elasticsearch + custom vectorizer |

---

### Strategy 4: Hybrid Retrieval (Dense + Sparse)

Run dense ANN search and sparse retrieval in parallel; merge results.

```python
from pymilvus import WeightedRanker, AnnSearchRequest

# Milvus 2.4+ hybrid search
dense_req = AnnSearchRequest(
    data=[query_dense_vector],
    anns_field="dense_embedding",
    param={"metric_type": "COSINE", "params": {"ef": 128}},
    limit=50
)

sparse_req = AnnSearchRequest(
    data=[query_sparse_vector],
    anns_field="sparse_embedding",
    param={"metric_type": "IP"},  # inner product for sparse
    limit=50
)

results = collection.hybrid_search(
    reqs=[dense_req, sparse_req],
    rerank=WeightedRanker(0.7, 0.3),  # or RRFRanker()
    limit=10,
    output_fields=["text", "title"]
)
```

**Hybrid search MTEB/BEIR results** (typical):

| Method | BEIR nDCG@10 | Notes |
|---|---|---|
| BM25 alone | 43.0 | Strong baseline for keyword queries |
| Dense bi-encoder alone | 48.5 | Better on semantic queries |
| Dense + BM25 (RRF) | 52.0 | +3.5 over best single method |
| Dense + SPLADE (RRF) | 55.0 | +6.5 over best single method |
| Dense + SPLADE + cross-encoder rerank | 60.0+ | Best quality, highest latency |

**Rule of thumb**: Hybrid retrieval almost always outperforms either component alone. Add it as a default when infrastructure supports it.

---

### Strategy 5: HyDE (Hypothetical Document Embeddings)

**Paper**: "Precise Zero-Shot Dense Retrieval without Relevance Labels" (Gao et al., 2022)

**Problem**: Query vectors and document vectors occupy different regions of embedding space. A user query "what causes inflation?" is semantically distant from a document that answers it ("Inflation is caused by an increase in money supply relative to goods...").

**HyDE solution**: 
1. Use LLM to generate a hypothetical answer to the query (no external knowledge needed)
2. Embed the hypothetical answer (not the query)
3. Use the answer embedding to retrieve documents

```python
def hyde_retrieve(query: str, collection, llm, embed_model, top_k: int = 10):
    # Step 1: Generate hypothetical answer
    hypothetical_answer = llm.invoke(
        f"Write a brief paragraph that would directly answer this question: {query}"
    )
    
    # Step 2: Embed the hypothetical answer
    hyp_embedding = embed_model.embed_query(hypothetical_answer)
    
    # Step 3: Search with hypothetical embedding
    return collection.search(data=[hyp_embedding], limit=top_k, ...)
```

**Why HyDE works**: The hypothetical answer "looks like" a relevant document more than the raw query does. The embedding model better captures the similarity between two answer-shaped texts than query→answer similarity.

**HyDE trade-offs**:

| | Standard Dense | HyDE |
|---|---|---|
| LLM call per query | No | Yes (~100ms) |
| Works on zero-shot domains | Moderate | Better |
| Risks | None | LLM may generate incorrect hypothetical → retrieval miss |
| Recall improvement | Baseline | +5–15% on factual questions |
| **Recommended when** | General RAG | Domain mismatch; when recall is insufficient with standard dense |

---

### Strategy 6: Query Transformation (Expansion + Decomposition)

Rather than a single query vector, generate multiple queries and merge results.

#### Multi-Query Expansion

```python
from langchain.retrievers.multi_query import MultiQueryRetriever

# LLM generates N reformulations of original query
# Each reformulation is embedded and searched independently
# Results are union-merged

retriever = MultiQueryRetriever.from_llm(
    retriever=vector_store.as_retriever(search_kwargs={"k": 10}),
    llm=ChatOpenAI(temperature=0),
    prompt=PromptTemplate.from_template("""
You are an AI assistant. Generate 3 different versions of the following 
question to retrieve relevant documents. Vary the vocabulary and framing.

Original question: {question}
Output 3 alternative questions, one per line:""")
)
```

**When to use**: Ambiguous queries; domain where synonyms are common; when single-query recall is < 80%.

#### Sub-Question Decomposition

For complex multi-part questions, decompose into atomic sub-questions:

```
Original: "Compare the revenue growth of Apple and Microsoft in 2023"
Decomposed:
  Q1: "What was Apple's revenue in 2023?"
  Q2: "What was Apple's revenue in 2022?"
  Q3: "What was Microsoft's revenue in 2023?"
  Q4: "What was Microsoft's revenue in 2022?"

Retrieve answers to each sub-question independently
LLM synthesizes final answer from sub-answers
```

**Useful for**: Multi-hop reasoning, comparative questions, questions requiring aggregation across documents.

#### Step-Back Prompting

Instead of searching for the specific instance, search for the general principle:

```
Original query: "What caused the 2008 financial crisis?"
Step-back query: "What are the common causes of financial crises?"

Retrieve: general economic principles about financial crisis mechanisms
Then: apply to 2008 specifically
```

---

### Strategy 7: RAG Variants — Naive to Agentic

#### Naive RAG
```
Query → Retrieve top-K → Concatenate as context → LLM → Answer

Failure modes:
  - Context overload: top-K chunks may be too much for context window
  - Retrieval quality bottleneck: bad retrieval = bad answer
  - No iterative refinement
```

#### Advanced RAG
```
Query → [Pre-retrieval: query transform/expansion]
      → Retrieve
      → [Post-retrieval: re-ranking, compression, dedup]
      → LLM → Answer
```

Pre-retrieval improvements: HyDE, query expansion, step-back prompting
Post-retrieval improvements: cross-encoder re-ranking, contextual compression (LLM extracts only relevant sentences), MMR (Maximum Marginal Relevance) for diversity

#### Modular RAG

Decouple retrieval components into pluggable modules:

```
Pipeline (configurable):
  [QueryAnalyzer]      → classify query type (factual/comparative/summarization)
  [Router]             → direct to appropriate retriever (dense/sparse/SQL/API)
  [DenseRetriever]     → ANN search
  [SparseRetriever]    → BM25 search
  [Reranker]           → cross-encoder
  [Compressor]         → extract relevant sentences
  [Generator]          → LLM answer generation
  [Validator]          → fact-checking against retrieved sources
```

**Framework implementations**: LlamaIndex query pipeline, LangChain LCEL chains, Haystack pipelines.

#### Self-RAG

**Paper**: "Self-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection" (Asai et al., 2023)

```
Fine-tuned LLM that:
  1. Decides WHEN to retrieve (Retrieve token: [Retrieve] / [No Retrieve])
  2. Retrieves relevant passages
  3. Evaluates retrieved passage relevance (IsRel: [Relevant] / [Irrelevant])
  4. Generates with retrieved context
  5. Critiques its own output (IsSup: is generation supported by evidence?)
  6. Selects best generation via reflection tokens
```

**Advantage**: Retrieval is on-demand (not every query needs it); self-criticism reduces hallucination.
**Disadvantage**: Requires fine-tuned model; more complex inference pipeline.

#### Agentic RAG

```
LLM Agent with tools:
  - vector_search(query, top_k) → semantic retrieval
  - keyword_search(query)       → BM25 retrieval
  - get_document(doc_id)        → full document fetch
  - web_search(query)           → external knowledge
  - calculator(expression)      → computation
  - sql_query(query)            → structured data

Agent loop:
  Think → choose tool → observe result → think → choose next tool → ...
  Continue until agent decides answer is complete
```

**When to use agentic RAG**:
- Multi-step reasoning (research assistant, competitive analysis)
- Mixed structured + unstructured data sources
- When user query requires planning, not just retrieval + generate

**Latency**: Agentic loops add 5–30 LLM calls per query; expect 10–60 second total latency.

#### Graph RAG (Microsoft, 2024)

**Paper**: "From Local to Global: A Graph RAG Approach to Query-Focused Summarization"

```
Preprocessing (offline):
  1. Extract entities and relationships from documents → knowledge graph
  2. Cluster graph communities (Leiden algorithm)
  3. Generate community summaries with LLM

Query-time retrieval:
  For local queries (specific facts): standard vector retrieval
  For global queries ("what are the main themes?"): 
    - Retrieve relevant community summaries
    - LLM synthesizes global answer
```

**Advantage over standard RAG**: Handles holistic, supra-document questions (e.g., "summarize the key trends in all research papers") that require global understanding, not just local document retrieval.

**Cost**: Preprocessing is expensive (many LLM calls for entity extraction + community summarization). Best for static knowledge bases.

---

### Retrieval Strategy Decision Tree

```
Is the query factual with specific keywords/entities?
├── Yes → Hybrid (dense + BM25). If BM25 infra available, always use hybrid
└── No (semantic, conceptual question) → Dense retrieval baseline

Is recall@10 < 90% on test queries?
├── Yes → Is vocabulary mismatch suspected?
│   ├── Yes → HyDE or multi-query expansion
│   └── No → Try larger/better embedding model, then fine-tuning
└── No → Dense retrieval is sufficient

Does the query require information from multiple documents?
├── Yes → Sub-question decomposition + multi-hop retrieval
└── No → Single-stage retrieval

Is the question about global patterns across many documents?
└── Yes → Graph RAG for global synthesis

Are users asking unpredictable, tool-requiring questions?
└── Yes → Agentic RAG (with appropriate latency SLO)
```

---

## Part B: Re-Ranking

Re-ranking is the second stage of a two-stage retrieval pipeline: retrieve a broad candidate set with a fast bi-encoder, then re-rank with a slower but more accurate model.

### The Precision-Recall Pipeline

```
Stage 1: Recall-focused retrieval
  ├── Dense ANN search: top-100 candidates
  ├── Sparse BM25: top-100 candidates  
  └── Union/RRF: top-100 unique candidates
  
Stage 2: Precision-focused re-ranking
  ├── Cross-encoder scores each (query, document) pair
  └── Returns top-10 highest scored
  
Why two stages:
  - Cross-encoder: processes (query, document) together → high quality, O(n) per candidate
  - At 1M docs: cross-encoder on all = 1M inference calls per query → impossible
  - At 100 candidates: 100 inference calls → ~200ms on GPU → acceptable
```

---

### Re-Ranker 1: Cross-Encoder

Takes (query, document) concatenated as input; outputs a relevance score.

```python
from sentence_transformers import CrossEncoder

model = CrossEncoder("cross-encoder/ms-marco-MiniLM-L-6-v2")  # fast
# OR: "BAAI/bge-reranker-v2-m3"  # higher quality, multilingual

def rerank(query: str, documents: list[str], top_k: int = 10) -> list[tuple]:
    pairs = [(query, doc) for doc in documents]
    scores = model.predict(pairs)  # batch inference
    ranked = sorted(zip(scores, documents), reverse=True)
    return ranked[:top_k]
```

**Popular cross-encoder models**:

| Model | BEIR nDCG@10 | Latency (100 docs, GPU) | Context Window |
|---|---|---|---|
| ms-marco-MiniLM-L-6-v2 | 39.4 | ~30ms | 512 tokens |
| ms-marco-MiniLM-L-12-v2 | 40.2 | ~50ms | 512 tokens |
| BGE-reranker-large | 60.0+ | ~150ms | 512 tokens |
| BGE-reranker-v2-m3 | 62.0+ | ~200ms | 8192 tokens |
| Cohere rerank-english-v3.0 | 60.0+ | ~200ms (API) | 4096 tokens |

**Context window limitation**: Most cross-encoders have 512 token limit. For long retrieved passages, you must truncate or use chunking before re-ranking. BGE-v2-m3 and Cohere v3 support longer contexts.

---

### Re-Ranker 2: Cohere Rerank API (Managed)

```python
import cohere

co = cohere.Client(api_key="...")

def cohere_rerank(query: str, documents: list[str], top_n: int = 10):
    results = co.rerank(
        model="rerank-english-v3.0",
        query=query,
        documents=documents,
        top_n=top_n,
        return_documents=True
    )
    return [(r.relevance_score, r.document["text"]) for r in results.results]
```

**Pricing**: ~$2 per 1000 re-ranking calls.
**Latency**: ~200ms for 100 documents.
**When to use**: Teams without GPU inference infra; when managed API cost is acceptable.

---

### Re-Ranker 3: ColBERT Late Interaction (MaxSim)

**Paper**: "ColBERT: Efficient and Effective Passage Search via Contextualized Late Interaction over BERT" (Khattab & Zaharia, 2020)

```
Standard bi-encoder:
  embed_query(Q) → q_vec (single vector)
  embed_doc(D)   → d_vec (single vector)
  score = cos(q_vec, d_vec)

ColBERT:
  encode_query(Q) → {qt_i}  (token-level embeddings, N_q × 128d)
  encode_doc(D)   → {dt_j}  (token-level embeddings, N_d × 128d)
  
  MaxSim score = sum_i max_j cos(qt_i, dt_j)
  
  Each query token finds its most relevant document token
  Score sums token-level alignments
```

**Why MaxSim is better than single-vector similarity**:
```
Query: "Apple revenue growth Q3 2023"

Document: "Apple reported revenue of $81.8B in Q3 2023, representing 
           2% year-over-year growth..."

Token alignment:
  "Apple" → "Apple" (0.99)
  "revenue" → "revenue" (0.98)
  "growth" → "growth" (0.97)
  "Q3" → "Q3" (0.99)
  "2023" → "2023" (0.98)

MaxSim captures all individual token alignments that a single vector might miss
```

**ColBERT vs cross-encoder**:

| | Cross-Encoder | ColBERT |
|---|---|---|
| Offline precomputation | None | Pre-compute token embeddings per doc |
| Storage | 1 vector / doc | N_tokens × 128d per doc (10–50× larger) |
| Retrieval feasibility | Requires candidate set | PLAID index enables direct retrieval |
| Latency (re-ranking 100 docs) | ~150ms | ~50ms (precomputed embeddings) |
| Quality | Excellent | Excellent (comparable, often better) |
| **Best use** | Re-ranking candidate set | High-quality retrieval, offline index acceptable |

**Production implementation**: Ragatouille library (wraps ColBERT for easy deployment):
```python
from ragatouille import RAGPretrainedModel

rag = RAGPretrainedModel.from_pretrained("colbert-ir/colbertv2.0")
rag.index(collection=documents, index_name="my_index")
results = rag.search(query="machine learning transformers", k=10)
```

---

### Re-Ranker 4: LLM-as-Reranker

Use an LLM to score or rank candidate documents. Two approaches:

**Pointwise**: Score each document independently.
```
Prompt: "On a scale of 1-10, how relevant is the following document 
         to the query '{query}'? Document: {document}. Score only:"
→ Parse integer score
→ Sort by score
```

**Listwise**: Present all candidates and ask LLM to rank them.
```
Prompt: "Rank the following documents by relevance to query '{query}'.
         Return a comma-separated list of document IDs from most to least relevant.
         Documents: [1] {doc1} [2] {doc2} ... [20] {doc20}"
→ Parse ranking order
→ Return top-K
```

**LLM re-ranker trade-offs**:

| | Cross-Encoder | LLM Pointwise | LLM Listwise |
|---|---|---|---|
| Latency | ~150ms/100 docs | ~500ms/100 docs | ~1000ms (1 call for all) |
| Cost | Self-hosted (low) | High (100 LLM calls) | Medium (1 LLM call) |
| Quality | High | Very high | Very high |
| Context window | 512 tokens | 4K–128K | 4K–128K (all docs at once) |
| **Use case** | Default re-ranker | When quality > cost | When quality > cost + short candidate list |

---

### Re-Ranking Pipeline Architecture

```python
from sentence_transformers import CrossEncoder
import numpy as np

class TwoStageRetriever:
    def __init__(self, vector_store, reranker_model: str, 
                 initial_k: int = 100, final_k: int = 10):
        self.vector_store = vector_store
        self.reranker = CrossEncoder(reranker_model)
        self.initial_k = initial_k
        self.final_k = final_k
    
    def retrieve(self, query: str) -> list[dict]:
        # Stage 1: broad recall retrieval
        candidates = self.vector_store.similarity_search(query, k=self.initial_k)
        
        # Stage 2: precision re-ranking
        pairs = [(query, doc.page_content) for doc in candidates]
        scores = self.reranker.predict(pairs)
        
        # Sort and return top-K
        ranked_idx = np.argsort(scores)[::-1][:self.final_k]
        return [{"doc": candidates[i], "score": float(scores[i])} 
                for i in ranked_idx]
```

**Initial K recommendation**:
- Re-ranking is O(initial_k) inference calls
- Diminishing returns above initial_k=100 (documents beyond rank 100 are unlikely to be relevant)
- GPU can batch 100 cross-encoder calls in ~150ms (acceptable for most SLOs)
- CPU: ~1500ms for 100 cross-encoder calls (may be too slow for interactive use)

---

## Part C: Ingestion Pipeline Patterns

### Pattern 1: Batch Ingestion (Nightly ETL)

```
Source DB / S3
    │  (1) Extract changed documents (full or incremental)
    ▼
Spark / Flink Job
    │  (2) Parse & clean text (HTML strip, OCR if PDF)
    │  (3) Chunk documents (recursive splitter)
    │  (4) Batch embed (OpenAI API or self-hosted model)
    │  (5) Generate metadata fields
    ▼
Staging Store (PostgreSQL / DynamoDB)
    │  (6) Deduplication check (hash-based)
    ▼
Vector DB (Milvus BulkInsert)
    │  (7) Upsert vectors + metadata
    ▼
Search Index Updated

Checkpoint: track processed_timestamp for each document
On failure: resume from last checkpoint (idempotent by document ID)
```

**Spark UDF for embedding**:
```python
import openai
from pyspark.sql.functions import pandas_udf
from pyspark.sql.types import ArrayType, FloatType
import pandas as pd

@pandas_udf(ArrayType(FloatType()))
def embed_texts(texts: pd.Series) -> pd.Series:
    client = openai.OpenAI()
    result = []
    # Batch in groups of 512
    batch = texts.tolist()
    for i in range(0, len(batch), 512):
        response = client.embeddings.create(
            input=batch[i:i+512],
            model="text-embedding-3-small"
        )
        result.extend([item.embedding for item in response.data])
    return pd.Series(result)

df_with_embeddings = df.withColumn("embedding", embed_texts(df["chunk_text"]))
```

---

### Pattern 2: Streaming Ingestion (Real-Time Updates)

```
Source Events (Kafka Topic: document.updates)
    │
    ▼
Consumer (Python / Flink)
    │  (1) Parse document update event
    │  (2) Fetch full document from source (if event is change notification)
    │  (3) Chunk document
    │  (4) Embed chunks (batch within consumer, flush every 500ms or 100 chunks)
    │  (5) Upsert to vector DB
    ▼
Vector DB

Dead Letter Queue: failed embed/upsert → retry queue → manual review after N retries
```

**Consumer implementation**:
```python
from kafka import KafkaConsumer
import json, time

class VectorIngestionConsumer:
    def __init__(self, embed_client, vector_store, batch_size=100, flush_interval=0.5):
        self.consumer = KafkaConsumer("document.updates", bootstrap_servers=["kafka:9092"])
        self.embed_client = embed_client
        self.vector_store = vector_store
        self.batch: list[dict] = []
        self.last_flush = time.time()
        self.BATCH_SIZE = batch_size
        self.FLUSH_INTERVAL = flush_interval  # seconds
    
    def run(self):
        for message in self.consumer:
            event = json.loads(message.value)
            chunks = self._chunk_document(event["content"])
            self.batch.extend(chunks)
            
            if len(self.batch) >= self.BATCH_SIZE or \
               (time.time() - self.last_flush) > self.FLUSH_INTERVAL:
                self._flush()
    
    def _flush(self):
        if not self.batch:
            return
        texts = [c["text"] for c in self.batch]
        embeddings = self.embed_client.embed_batch(texts)
        self.vector_store.upsert(self.batch, embeddings)
        self.batch.clear()
        self.last_flush = time.time()
```

---

### Pattern 3: Change Data Capture (CDC-Based Selective Re-Embedding)

For databases with high update frequency, re-embed only changed documents:

```
PostgreSQL CDC (via Debezium)
    │  (change event: {op: "UPDATE", after: {id: 123, content: "..."}})
    │
    ▼
Debezium → Kafka Topic: db.documents
    │
    ▼
CDC Consumer:
    │  Check: is embedding stale?
    │  content_hash = SHA256(event.after.content)
    │  if content_hash == stored_hash: skip (no re-embedding needed)
    │  else: embed + upsert
    ▼
Vector DB
```

**When CDC is essential**:
- Source document updates are frequent but not all documents change
- Full daily re-ingestion would be prohibitively expensive
- Example: product catalog (millions of products, thousands change per day)

---

### Pattern 4: Deduplication

Prevent semantically identical or near-identical content from inflating the vector index.

#### Exact Deduplication (Hash-Based)

```python
import hashlib

def get_content_hash(text: str) -> str:
    return hashlib.sha256(text.strip().lower().encode()).hexdigest()

# Store hash in vector DB as metadata field or separate hash table
# Before insert: check if hash already exists
existing = collection.query(
    expr=f'content_hash == "{content_hash}"',
    output_fields=["id"]
)
if not existing:
    collection.insert([{...}])
```

#### Semantic Deduplication (Near-Duplicate Removal)

```python
import numpy as np

def semantic_dedup(embeddings: np.ndarray, threshold: float = 0.97) -> list[int]:
    """Returns indices of non-duplicate vectors."""
    keep = [0]
    for i in range(1, len(embeddings)):
        # Compare against all kept vectors
        kept_embeds = embeddings[keep]
        similarities = np.dot(kept_embeds, embeddings[i])
        if similarities.max() < threshold:
            keep.append(i)
    return keep

# Threshold guidance:
# 0.99: exact duplicates only (same sentence, minor whitespace difference)
# 0.97: near-duplicates (same content, minor paraphrase)
# 0.95: redundant content (highly similar, may want to keep for coverage)
```

**Scale consideration**: O(n²) exact semantic dedup — feasible for < 100K vectors. For larger scale, use MinHash LSH for approximate deduplication: hash-based bucketing finds candidates, then exact cosine verification.

---

### Pattern 5: Multi-Modal Ingestion

```
Source: PDF document

Pipeline:
  PDF → pdfplumber/PyMuPDF → extract text pages + embedded images
  
  Text pages:
    → chunk (recursive splitter)
    → embed (text embedding model)
    → store with metadata: {doc_id, page_num, modality="text"}
  
  Images:
    → image captioning (BLIP-2 / LLaVA) → text caption
    → embed caption (same text embedding model)
    → store with metadata: {doc_id, page_num, modality="image_caption", img_s3_path}
    
    OR alternatively:
    → CLIP image encoder → embed as image vector
    → store in separate image_embeddings field
    → multimodal search: CLIP text encoder for queries

Retrieval: unified search across text + image_caption fields
           use output metadata to decide whether to show text or image
```

---

### Pattern 6: Pipeline Orchestration Frameworks

#### LangChain Indexing API

```python
from langchain.indexes import SQLRecordManager, index
from langchain_openai import OpenAIEmbeddings
from langchain_community.vectorstores import Milvus

record_manager = SQLRecordManager("milvus/my_collection", db_url="sqlite:///index.db")
record_manager.create_schema()

vector_store = Milvus(embedding_function=OpenAIEmbeddings(), collection_name="docs")

# Handles: deduplication, change tracking, deletion of removed docs
result = index(
    docs_with_chunks,         # your chunked documents
    record_manager,
    vector_store,
    cleanup="incremental",    # "incremental": delete docs no longer in source
    source_id_key="source"    # field that identifies source document
)
print(f"Added: {result['num_added']}, Deleted: {result['num_deleted']}")
```

#### Apache Airflow DAG

```python
from airflow.decorators import dag, task
from datetime import datetime

@dag(schedule_interval="0 2 * * *", start_date=datetime(2024, 1, 1))
def vector_ingestion_pipeline():
    
    @task
    def extract_new_documents(execution_date=None):
        return query_db_for_changes(since=execution_date)
    
    @task
    def chunk_documents(documents: list) -> list:
        return [chunk for doc in documents for chunk in chunk_document(doc)]
    
    @task
    def embed_chunks(chunks: list) -> list:
        return embed_in_batches(chunks)
    
    @task
    def upsert_to_vector_db(chunks_with_embeddings: list):
        vector_db.upsert(chunks_with_embeddings)
    
    docs = extract_new_documents()
    chunks = chunk_documents(docs)
    embedded = embed_chunks(chunks)
    upsert_to_vector_db(embedded)
```

---

## Part D: Evaluation Metrics

### Retrieval Evaluation Metrics

**Recall@K**: What fraction of relevant documents are in the top-K results?

$$\text{Recall@K} = \frac{|\text{relevant} \cap \text{retrieved}_K|}{|\text{relevant}|}$$

**Most important metric for RAG**: If Recall@10 = 0.95, the relevant passage is in the top-10 retrieved chunks 95% of the time. The LLM can only answer correctly if the relevant passage is retrieved.

**Precision@K**: What fraction of top-K results are relevant?

$$\text{Precision@K} = \frac{|\text{relevant} \cap \text{retrieved}_K|}{K}$$

**MRR (Mean Reciprocal Rank)**: How high does the first relevant document rank?

$$\text{MRR} = \frac{1}{|Q|} \sum_{i=1}^{|Q|} \frac{1}{\text{rank}_i}$$

Good for single-answer questions (finding the ONE correct document).

**NDCG@K (Normalized Discounted Cumulative Gain)**: Graded relevance; penalizes relevant docs at lower ranks.

$$\text{DCG@K} = \sum_{i=1}^{K} \frac{2^{rel_i} - 1}{\log_2(i+1)}$$

Best for multi-graded relevance (highly relevant / somewhat relevant / not relevant).

**Metric selection guide**:

| Use Case | Primary Metric | Secondary |
|---|---|---|
| Single-answer factual RAG | MRR | Recall@K |
| Multi-document synthesis | Recall@K | NDCG@K |
| Re-ranking quality | NDCG@K | MRR |
| General retrieval system | NDCG@10 | Recall@10 |

---

### End-to-End RAG Evaluation: RAGAS Framework

RAGAS evaluates the full RAG pipeline (not just retrieval) using LLM-as-judge:

```python
from ragas import evaluate
from ragas.metrics import (
    faithfulness,        # Is the answer supported by retrieved context?
    answer_relevancy,   # Does the answer address the question?
    context_precision,  # Are retrieved contexts relevant to the question?
    context_recall,     # Does retrieved context contain the ground truth?
)

dataset = Dataset.from_dict({
    "question": questions,
    "answer": generated_answers,
    "contexts": retrieved_contexts,    # list of lists
    "ground_truth": reference_answers  # needed for context_recall
})

result = evaluate(dataset, metrics=[
    faithfulness, answer_relevancy, context_precision, context_recall
])
print(result)  # scores 0–1 for each metric
```

**RAGAS Metric Definitions**:

| Metric | Measures | Detects |
|---|---|---|
| **Faithfulness** | Is each claim in answer entailed by retrieved context? | Hallucination |
| **Answer Relevancy** | Does answer address the question? | Off-topic answers |
| **Context Precision** | Fraction of retrieved chunks that are actually relevant | Noisy retrieval |
| **Context Recall** | Fraction of ground-truth facts covered by retrieved context | Under-retrieval |
| **Answer Correctness** | Factual accuracy vs ground truth | Combined quality |

---

### Recall Drift Monitoring

As your document corpus grows or changes, retrieval quality can silently degrade:

```python
# Track Recall@10 over time on a fixed evaluation set
import datetime
from prometheus_client import Gauge

recall_gauge = Gauge("retrieval_recall_at_10", 
                     "Recall@10 on held-out evaluation set",
                     ["collection_version"])

def run_recall_evaluation(collection, eval_set: list[dict]) -> float:
    hits = 0
    for sample in eval_set:
        results = collection.search(data=[sample["query_embedding"]], limit=10)
        retrieved_ids = {r.id for r in results[0]}
        if sample["relevant_doc_id"] in retrieved_ids:
            hits += 1
    recall = hits / len(eval_set)
    recall_gauge.labels(collection_version=collection.version).set(recall)
    return recall

# Alert: if recall@10 drops > 5% from baseline → investigate
# Common causes: index build issue, new document distribution shift, model version mismatch
```

**Evaluation set management**:
- Maintain a held-out set of 200–1000 (query, relevant_doc) pairs
- Sample from real user queries (not synthetic)
- Update evaluation set quarterly as query distribution evolves
- Never use evaluation set documents as training data for embedding fine-tuning

---

### A/B Testing Retrieval Configurations

```
Hypothesis: "Parent-child chunking improves Recall@10 vs fixed-size chunking"

Experiment setup:
  Control:   fixed-size chunks (512 tokens, 10% overlap)
  Treatment: parent-child chunks (256-token child, 1024-token parent)

Traffic split:
  - Hash user_id → [control, treatment] (50/50)
  - Log: {user_id, query_hash, variant, retrieved_doc_ids, user_feedback}

Primary metric: Recall@10 (requires relevance labels)
  - Get labels via: explicit feedback (thumbs up/down), click-through rate proxy, LLM-as-judge

Sample size calculation:
  - Baseline recall = 0.88
  - MDE (minimum detectable effect) = 3% improvement (to 0.91)
  - Power = 0.8, α = 0.05
  - Required queries per variant ≈ 1500

Statistical test: two-proportion z-test on recall@10 pass/fail per query
```

---

## FAANG Interview Callout

> **What an interviewer is testing**: Can you design a complete retrieval pipeline? Do you understand the latency budget of a two-stage retrieval+re-ranking system? Can you reason about when to use HyDE vs multi-query vs hybrid vs standard dense? Can you define and measure the success of a retrieval system?

**Model answer for "design a retrieval pipeline for a 10M document RAG system with < 2s total latency"**:

*"I'd use a two-stage pipeline. Stage 1 (< 200ms): hybrid retrieval — dense ANN search (HNSW, ef=128, top-50 candidates) fused with BM25 sparse retrieval (top-50 candidates) via RRF fusion to top-100 candidates. Stage 2 (< 300ms): cross-encoder re-ranking — BGE-reranker-v2 on the top-100 candidates to produce final top-5. The remaining ~1.5s budget goes to the LLM generation step. I'd measure success with RAGAS: faithfulness (no hallucinations) and Recall@10 (answer is in retrieved context). I'd set up a held-out evaluation set of 500 real queries with relevance labels, run recall evaluation nightly, and alert if Recall@10 drops below 90%. If recall is insufficient, I'd add HyDE for complex questions and query decomposition for multi-hop questions."*

---

## Related Files

- [embedding-strategies.md](embedding-strategies.md) — embedding model selection, chunking strategies, RNN vs Transformer
- [../technologies/vector-db/README.md](../technologies/vector-db/README.md) — vector database system selection
- [../technologies/vector-db/02-read-write-path.md](../technologies/vector-db/02-read-write-path.md) — hybrid search internals, filtering, ingestion path
- [../ai-architecture/rag-system-hld.md](../ai-architecture/rag-system-hld.md) — production RAG system HLD with capacity estimation
