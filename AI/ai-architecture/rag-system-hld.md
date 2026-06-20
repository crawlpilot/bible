# Production RAG System — High-Level Design (RESHADED)

> **Problem statement**: Design a production Retrieval-Augmented Generation (RAG) system for a company with 10 million documents, 1 million daily active users, and a requirement to answer natural-language questions with citations from the corpus. The system must support semantic search, multi-document synthesis, streaming responses, and continuous document ingestion.

> **Format**: RESHADED framework — Requirements → Estimation → Storage → High-level design → APIs → Detail deep dive → Evaluate → Distinctive features

---

## R — Requirements

### Functional Requirements

| Priority | Requirement |
|---|---|
| P0 | **Semantic search**: users can search the corpus with natural language; results are semantically relevant, not just keyword-matched |
| P0 | **RAG question answering**: users can ask questions; system retrieves relevant context and generates grounded answers with citations |
| P0 | **Streaming responses**: LLM output streams token-by-token; users see partial responses progressively |
| P0 | **Document ingestion**: new documents ingested continuously (< 5 minutes from upload to searchable) |
| P1 | **Multi-document synthesis**: answers synthesize information across multiple retrieved documents |
| P1 | **Conversation memory**: multi-turn conversations remember context from earlier turns |
| P1 | **Feedback collection**: users can rate answers (thumbs up/down) for quality improvement |
| P2 | **Access control**: documents can be tagged as private (tenant-scoped) or public |
| P2 | **Multi-modal support**: PDFs with embedded images; images captioned and embedded separately |

### Non-Functional Requirements

| Dimension | Target |
|---|---|
| **Search latency** | p99 < 200ms for semantic search (retrieval only) |
| **RAG answer latency** | p99 < 3s time-to-first-token (TTFT); full response < 10s |
| **Ingestion latency** | < 5 minutes from document upload to ANN-indexed |
| **Availability** | 99.9% uptime (< 9 hours/year downtime) |
| **Throughput** | 10,000 QPS peak retrieval; 1,000 QPS peak RAG queries |
| **Recall target** | Recall@10 ≥ 95% on held-out evaluation set |
| **Scale** | 10M documents, growing to 100M; 1M DAU |
| **Multi-tenancy** | 10,000+ tenants; tenant A cannot access tenant B's private documents |

### Assumptions and Constraints

- Documents are English text (PDFs, HTML, Markdown, plain text); ~2,000 words average length
- Users are enterprise employees or API consumers; authenticated via OAuth 2.0
- LLM inference is external API (OpenAI GPT-4o) — we own the retrieval layer
- Embedding model: OpenAI text-embedding-3-small (1536d, MRL) — managed, no GPU needed for embedding
- Budget: $50K/month infrastructure ceiling (guides technology choices)

---

## E — Estimation

### Document and Chunk Volume

```
10M documents × 2,000 words avg × 1.3 tokens/word = 26B tokens total

Chunking strategy: 512-token chunks with 10% overlap
→ 26B tokens / 512 tokens/chunk × 1.1 (overlap factor) ≈ 56M chunks

Round up: 60M vector chunks in vector DB (including metadata)
```

### Embedding Cost (One-time Ingestion)

```
text-embedding-3-small: $0.02 / 1M tokens

One-time ingestion:
  26B tokens × ($0.02 / 1M) = $520 total one-time cost

Ongoing (2M new documents/month × 2,000 words × 1.3 tokens/word / 1M × $0.02):
  = 52M tokens/month × $0.02/1M = $1.04/month embedding cost
```

### Vector Storage (Milvus)

```
60M vectors × 1536 dimensions × 4 bytes (FP32) = 368 GB raw vectors

With SQ8 quantization (4× compression): 92 GB
HNSW graph (M=32): 60M × 32 × 2 × 4 = 15 GB
Metadata (text, doc_id, tenant_id, chunk_index, created_at): ~500 bytes/chunk × 60M = 30 GB

Total QueryNode memory: ~137 GB
→ 3 × r5.4xlarge (128GB RAM each) = 384 GB total; 137 GB data + headroom for replication
→ Cost: 3 × $0.99/hr = $2,138/month
```

### Query Throughput

```
Retrieval QPS: 10,000 QPS peak
  - Each HNSW query (SQ8, ef=128): ~3ms on QueryNode
  - 3 QueryNodes × 500 QPS capacity each = 1,500 QPS single-replica
  - Need 10,000 / 1,500 ≈ 7 replica sets
  - But: 10,000 QPS peak is bursty; average is ~1,000 QPS
  - 2 replica sets (6 QueryNodes) handles average + 3× burst headroom

RAG QPS: 1,000 QPS
  - Each RAG query: 1 retrieval + 1–2 LLM calls (streaming, ~1–3s)
  - LLM is the bottleneck: 1,000 parallel streams × 1,000 tokens/response = 1M tokens/min to GPT-4o
  - OpenAI tier-5 rate limit: 800,000 TPM → may require multiple API keys or Azure OpenAI
```

### Ingestion Throughput

```
2M new documents/month = 2,000,000 / (30 × 24 × 3600) ≈ 0.77 documents/second average
Peak: assume 10× = 7.7 documents/second

7.7 docs/sec × 4 chunks/doc avg = 31 chunks/sec
31 chunks/sec → small Kafka partition, single embedding worker sufficient

One-time ingestion of 10M documents:
  At 7.7 docs/sec: 10M / 7.7 ≈ 15 days → use BulkInsert for initial load
  At 10,000 docs/sec with BulkInsert (Spark): 10M / 10,000 = 1,000 seconds ≈ 17 minutes
```

### Monthly Infrastructure Cost Estimate

| Component | Instance | Count | Monthly Cost |
|---|---|---|---|
| Milvus QueryNodes | r5.4xlarge (128GB) | 6 | $5,140 |
| Milvus DataNodes | m5.2xlarge (32GB) | 2 | $554 |
| Milvus IndexNodes | c5.4xlarge (16 cores) | 2 | $549 |
| Milvus Coordination | m5.large | 4 | $277 |
| Kafka (streaming) | m5.xlarge | 3 | $462 |
| etcd (metadata) | m5.large | 3 | $208 |
| MinIO / S3 | S3 (200GB) | — | $5 |
| PostgreSQL (metadata) | db.r5.xlarge | 2 (primary + replica) | $1,490 |
| Redis (cache) | r6g.xlarge | 2 (primary + replica) | $390 |
| API servers | c5.2xlarge | 4 | $554 |
| LLM (OpenAI API) | — | — | ~$10,000 (1,000 QPS × $0.03/1K tokens avg) |
| **Total** | | | **~$19,629/month** |

Well within $50K/month budget.

---

## S — Storage Design

### Data Stores and Their Roles

```
┌────────────────────────────────────────────────────────────────────────┐
│  STORAGE TIER                                                          │
│                                                                        │
│  S3 / Object Store                                                     │
│    - Raw documents (PDF, HTML, Markdown)                               │
│    - Milvus sealed segment binlogs (persistent WAL)                    │
│    - HNSW index files                                                  │
│    - Embedding model checkpoints (if self-hosted)                      │
│    Cost: ~$0.023/GB/month                                              │
│                                                                        │
│  Milvus (Vector Database)                                              │
│    Collections:                                                         │
│      chunks (primary):                                                 │
│        - id (INT64, primary key)                                       │
│        - tenant_id (VARCHAR, partition key)                            │
│        - doc_id (VARCHAR, FK to PostgreSQL documents table)            │
│        - chunk_index (INT32, position in parent document)              │
│        - embedding (FLOAT_VECTOR, dim=1536 or 512 with MRL)           │
│        - text_preview (VARCHAR, first 500 chars for display)           │
│        - embedding_model_version (VARCHAR, e.g., "3-small-v1")        │
│        - created_at (INT64, unix timestamp)                            │
│        Index: HNSW(M=32, ef=256) on embedding                         │
│               BITMAP on tenant_id                                      │
│               SCALAR on embedding_model_version                        │
│                                                                        │
│  PostgreSQL (Relational Metadata)                                      │
│    documents:                                                           │
│      id (UUID), tenant_id, title, source_url, file_hash,              │
│      status (ENUM: pending/processing/indexed/failed),                 │
│      chunk_count, created_at, updated_at                               │
│    chunk_metadata:                                                     │
│      id (UUID), doc_id, chunk_index, page_number, char_start,         │
│      char_end, parent_chunk_id (for parent-child), full_text          │
│    tenants: id, name, plan, rate_limits                                │
│    eval_set: query_id, query_text, relevant_chunk_ids, created_at     │
│    feedback: query_id, user_id, answer_id, rating, created_at         │
│                                                                        │
│  Redis (Cache + Session)                                               │
│    - Embedding cache: SHA256(text) → JSON(embedding) [30-day TTL]     │
│    - Query result cache: SHA256(query_vec + filters + k) → results    │
│      [5-minute TTL for popular queries]                                │
│    - Conversation history: session_id → last N turns [24h TTL]        │
│    - Rate limiting: tenant_id → request_count [sliding window]        │
│    - Warm-up embeddings: pre-computed embeddings for frequent queries  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## H — High-Level Design

### System Architecture Diagram

```
                        ┌─────────────────────────────────────┐
                        │           CLIENT LAYER              │
                        │  Web App   Mobile   API (SDK)       │
                        └─────────────┬───────────────────────┘
                                      │ HTTPS
                        ┌─────────────▼───────────────────────┐
                        │           API GATEWAY               │
                        │  Auth (OAuth2) · Rate Limiting      │
                        │  TLS termination · Request routing  │
                        └─────────────┬───────────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          │                           │                           │
          ▼                           ▼                           ▼
   ┌─────────────┐            ┌──────────────┐           ┌──────────────┐
   │  INGEST API │            │  SEARCH API  │           │   RAG API    │
   │             │            │              │           │              │
   │ POST /ingest│            │ GET /search  │           │ POST /query  │
   │             │            │              │           │              │
   └──────┬──────┘            └──────┬───────┘           └──────┬───────┘
          │                          │                           │
          ▼                          │                           │
   ┌─────────────────┐               │                           │
   │  INGESTION      │               │                           │
   │  PIPELINE       │               │                           │
   │                 │    ┌──────────▼──────────────────────────▼──────────┐
   │  Doc Parser     │    │          QUERY PIPELINE                        │
   │  ├─ PDF extract │    │                                                 │
   │  ├─ HTML clean  │    │  ┌──────────────────┐                          │
   │  └─ OCR (imgs)  │    │  │ Query Transformer │ (optional: HyDE,         │
   │                 │    │  │                  │  multi-query, step-back)  │
   │  Chunker        │    │  └────────┬─────────┘                          │
   │  (recursive,    │    │           │                                     │
   │   512 tokens,   │    │  ┌────────▼──────────┐   ┌───────────────────┐ │
   │   10% overlap)  │    │  │ Query Embedder    │   │ Conversation      │ │
   │                 │    │  │ (text-embed-3-sm) │   │ Memory (Redis)    │ │
   │  Embedder       │    │  └────────┬──────────┘   └─────────┬─────────┘ │
   │  (batch, 512/   │    │           │                        │            │
   │   req)          │    │  ┌────────▼──────────────────────▼─────────┐   │
   │                 │    │  │           RETRIEVER                     │   │
   │  Kafka → Milvus │    │  │  Dense ANN (Milvus HNSW, ef=128)        │   │
   │  BulkInsert     │    │  │  Sparse BM25 (Elasticsearch optional)   │   │
   └─────────────────┘    │  │  RRF fusion → top-100 candidates        │   │
                          │  └──────────────┬──────────────────────────┘   │
                          │                 │                               │
                          │  ┌──────────────▼────────────────┐             │
                          │  │          RE-RANKER             │             │
                          │  │  BGE-reranker-v2 or Cohere     │             │
                          │  │  100 candidates → top-10       │             │
                          │  └──────────────┬────────────────┘             │
                          │                 │                               │
                          │                 ├──────────────── [search only] │
                          │                 │                               │
                          │  ┌──────────────▼────────────────┐             │
                          │  │       CONTEXT BUILDER          │ [RAG only]  │
                          │  │  Parent chunk fetch (PostgreSQL)│             │
                          │  │  Context window packing        │             │
                          │  │  Citation metadata attachment  │             │
                          │  └──────────────┬────────────────┘             │
                          │                 │                               │
                          │  ┌──────────────▼────────────────┐             │
                          │  │      LLM (OpenAI GPT-4o)      │ [RAG only]  │
                          │  │  System + context + question  │             │
                          │  │  Streaming token output        │             │
                          │  └──────────────┬────────────────┘             │
                          │                 │                               │
                          │  SSE Stream ────┘                               │
                          └──────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Technology |
|---|---|---|
| API Gateway | Auth, rate limiting, TLS, routing | Kong / AWS API Gateway |
| Ingest API | Accept uploads, queue for processing | FastAPI |
| Ingestion Pipeline | Parse, chunk, embed, index | Python workers + Kafka |
| Search API | Semantic search endpoint | FastAPI |
| RAG API | Question answering endpoint | FastAPI |
| Query Embedder | Embed user queries | OpenAI SDK (cached in Redis) |
| Retriever | Dense + optional sparse retrieval | Milvus SDK + ES |
| Re-ranker | Cross-encoder precision pass | BGE-reranker-v2 (GPU pod) |
| Context Builder | Fetch full text, pack context window | PostgreSQL queries |
| LLM | Generate streaming answers | OpenAI GPT-4o API |
| Conversation Memory | Multi-turn context | Redis + Postgres |
| Vector DB | ANN index, metadata filtering | Milvus 2.x |
| Metadata DB | Document registry, chunk text | PostgreSQL |
| Cache | Embeddings, query results, sessions | Redis 7 |
| Object Store | Raw documents, Milvus segments | S3 |
| Message Queue | Async ingestion pipeline | Kafka 3.x |

---

## A — APIs

### POST /ingest — Document Ingestion

```
POST /v1/ingest
Authorization: Bearer {token}
Content-Type: multipart/form-data

Request:
  file: <binary, max 50MB>
  tenant_id: string (required)
  title: string
  source_url: string (optional)
  access_level: "private" | "public" (default: "private")
  metadata: { key: value, ... }  (optional custom fields)

Response 202 Accepted:
  {
    "doc_id": "uuid-abc-123",
    "status": "pending",
    "estimated_ready_at": "2024-06-08T10:05:00Z"
  }

Async processing:
  → Document stored in S3
  → doc_id queued to Kafka topic: doc.ingest.{tenant_id}
  → Status updates: pending → processing → indexed | failed
```

### GET /search — Semantic Search

```
GET /v1/search
Authorization: Bearer {token}

Query params:
  q: string (required, natural language query)
  top_k: integer (default: 10, max: 50)
  tenant_id: string (required)
  filter: JSON string (optional metadata filter)
    e.g., '{"access_level": "public", "created_after": "2024-01-01"}'
  hybrid: boolean (default: false, enables BM25+dense fusion)
  rerank: boolean (default: true, enables cross-encoder)

Response 200:
  {
    "query": "machine learning transformers",
    "results": [
      {
        "chunk_id": "chunk-abc-123",
        "doc_id": "doc-xyz-456",
        "title": "Attention Is All You Need",
        "text_preview": "Transformer models use self-attention...",
        "score": 0.942,
        "rerank_score": 8.7,
        "page_number": 3,
        "source_url": "https://example.com/paper.pdf"
      },
      ...
    ],
    "search_latency_ms": 87,
    "retrieved_count": 100,
    "reranked_count": 10
  }
```

### POST /query — RAG Question Answering (Streaming)

```
POST /v1/query
Authorization: Bearer {token}
Content-Type: application/json
Accept: text/event-stream  # SSE streaming

Request:
  {
    "question": "What are the main benefits of transformer architectures?",
    "tenant_id": "acme-corp",
    "session_id": "session-abc-123",  # for multi-turn
    "top_k": 10,
    "filter": { "access_level": "public" },
    "hybrid": true,
    "stream": true,
    "hyde": false,   # enable Hypothetical Document Embedding
    "options": {
      "model": "gpt-4o",
      "max_tokens": 1024,
      "temperature": 0.1
    }
  }

Response: SSE stream
  event: metadata
  data: {"session_id": "session-abc-123", "query_id": "q-def-789"}
  
  event: source
  data: {"chunk_id": "chunk-abc-123", "title": "Attention Is All You Need", 
         "score": 0.94, "page": 3}
  
  event: token
  data: {"token": "Transformer"}
  
  event: token
  data: {"token": " architectures"}
  
  ... (streaming tokens)
  
  event: done
  data: {"query_id": "q-def-789", "total_tokens": 312, 
         "retrieval_ms": 87, "ttft_ms": 423, "total_ms": 2841}

Error events:
  event: error
  data: {"code": "RETRIEVAL_EMPTY", "message": "No relevant documents found"}
```

### POST /feedback — Answer Rating

```
POST /v1/feedback
Authorization: Bearer {token}
Content-Type: application/json

Request:
  {
    "query_id": "q-def-789",
    "rating": "positive" | "negative",
    "comment": "Answer was well-cited",
    "correction": "The actual answer is..."  # optional
  }

Response 201 Created:
  { "feedback_id": "fb-ghi-012", "status": "received" }
```

---

## D — Detail Deep Dive

### Deep Dive 1: Chunking Algorithm Selection

Starting point: recursive character text splitter (512 tokens, 10% overlap).

**Adaptive chunking policy** (based on document type):

```python
def select_chunker(doc_type: str, doc_length: int):
    if doc_type in ("legal", "medical", "scientific"):
        if doc_length > 10_000:
            return PropositionChunker(llm=gpt4o_mini)  # atomic claims
        else:
            return SentenceChunker(max_tokens=256)
    
    elif doc_type in ("technical_doc", "api_reference"):
        return ParentChildChunker(
            child_size=256, parent_size=1024
        )
    
    else:  # general content: blog posts, reports, emails
        return RecursiveCharacterTextSplitter(
            chunk_size=512, chunk_overlap=50
        )
```

**Why parent-child for technical docs**: API reference has small precise facts ("Parameter `temperature` must be between 0 and 2") that should be indexed as small chunks for precision, but the surrounding context (function description, parameter list) helps the LLM generate a complete answer.

### Deep Dive 2: Embedding Model Trade-offs at Scale

At 60M chunks, the choice between text-embedding-3-small (1536d) and text-embedding-3-small with MRL truncation to 512d has significant cost impact:

```
Full 1536d:
  Storage: 60M × 1536 × 4 = 368 GB raw vectors
  HNSW memory: 60M × 32 × 8 = 15 GB graph
  Total: 383 GB QueryNode memory

MRL 512d (3× smaller):
  Storage: 60M × 512 × 4 = 123 GB raw vectors
  HNSW memory: 60M × 32 × 8 = 15 GB graph (unchanged)
  Total: 138 GB QueryNode memory
  
Quality trade-off: text-embedding-3-small at 512d achieves 96.7% of full 1536d quality per OpenAI
Recall@10 impact: expect ~1-2% recall degradation at 512d vs 1536d
Cost savings: ~63% memory reduction → fewer/smaller QueryNodes

Decision: use 512d MRL truncation. Monitor recall@10 on evaluation set; if drops below 93%, switch back to 1536d.
```

### Deep Dive 3: Vector DB Sharding for 10K Tenants

With 10,000 tenants and 60M chunks:
- Average: 6,000 chunks per tenant
- Large tenants: top 1% = 600,000 chunks each

Using Milvus partition keys:
```python
# Schema with partition key
schema = CollectionSchema(fields=[
    FieldSchema("id", DataType.INT64, is_primary=True, auto_id=True),
    FieldSchema("tenant_id", DataType.VARCHAR, max_length=128, is_partition_key=True),
    FieldSchema("embedding", DataType.FLOAT_VECTOR, dim=512),
    FieldSchema("text_preview", DataType.VARCHAR, max_length=500),
    FieldSchema("doc_id", DataType.VARCHAR, max_length=128),
    FieldSchema("embedding_model_version", DataType.VARCHAR, max_length=64),
], num_partitions=1024)  # 1024 partition buckets for 10K tenants

# Search scoped to one tenant (routed to one partition bucket)
results = collection.search(
    data=[query_embedding],
    anns_field="embedding",
    param={"metric_type": "COSINE", "params": {"ef": 128}},
    limit=100,
    expr='tenant_id == "acme-corp"',  # partition key filter
    output_fields=["doc_id", "text_preview"]
)
```

**For large tenants** (top 100 tenants with > 100K chunks): dedicated collection per tenant. Routing layer directs their queries to tenant-specific collection.

### Deep Dive 4: Re-ranking Latency Budget

```
Target: retrieval + re-ranking < 500ms total (to stay within 3s TTFT budget)

Stage breakdown:
  Query embedding (cached hit):        1ms
  Query embedding (cache miss):        50ms (OpenAI API)
  Milvus ANN search (ef=128, 60M):    30ms
  Result fetch (text from PostgreSQL): 20ms
  Cross-encoder re-ranking (100 docs): 150ms (BGE-reranker on T4 GPU)
  Context assembly:                    10ms
  ────────────────────────────────────
  Total (cache hit):                   211ms ✅
  Total (cache miss):                  261ms ✅

LLM streaming:
  Time to first token (TTFT):  300–500ms (GPT-4o API)
  Full response (512 tokens):  ~2000ms

End-to-end (cache hit):  211ms + 350ms (avg TTFT) = 561ms to first token  ✅
End-to-end (cache miss): 261ms + 350ms = 611ms ← well within 3s target
```

**Re-ranker deployment**: BGE-reranker-v2-m3 on dedicated GPU pod (k8s, 1× T4 per pod). Scale with HPA based on queue depth. At 1,000 RAG QPS, need ~7 T4 pods (each processes ~150 docs/s → 150 re-ranking requests/s per pod).

### Deep Dive 5: Prompt Construction for Grounded Answers

```python
SYSTEM_PROMPT = """You are a helpful assistant that answers questions based on provided documents.
Always cite your sources using [1], [2], etc. referencing the numbered documents.
If the documents don't contain enough information, say so clearly.
Do not fabricate information not present in the documents."""

def build_prompt(question: str, retrieved_chunks: list[dict], 
                 conversation_history: list[dict]) -> list[dict]:
    # Build context from top-10 reranked chunks
    context_parts = []
    for i, chunk in enumerate(retrieved_chunks[:10], 1):
        context_parts.append(
            f"[{i}] Source: {chunk['title']} (page {chunk['page_number']})\n"
            f"{chunk['full_text']}"
        )
    
    context = "\n\n".join(context_parts)
    
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    
    # Add last N turns of conversation history
    messages.extend(conversation_history[-6:])  # last 3 user/assistant turns
    
    # Add current context + question
    messages.append({
        "role": "user",
        "content": f"Documents:\n{context}\n\nQuestion: {question}"
    })
    
    return messages
```

**Context window management**: GPT-4o has 128K context window. At 512 tokens/chunk × 10 chunks = 5,120 tokens for context. Plus system prompt (~300 tokens), conversation history (~1,500 tokens), question (~50 tokens) = ~7,000 tokens total. Well within limits; safe to expand to 20 chunks if needed.

---

## E — Evaluate (Observability and SLO Tracking)

### SLO Dashboard Metrics

```
Retrieval Layer:
  - p50/p95/p99 ANN search latency per collection
  - Recall@10 (weekly automated evaluation)
  - Cache hit rate (embedding cache, query result cache)
  - Milvus QueryNode memory utilization

RAG Layer:
  - TTFT (time to first token) p50/p95/p99
  - RAG total response latency p95/p99
  - LLM API error rate, rate limit hits
  - Answer faithfulness (RAGAS, sampled 1% of queries)
  - Answer relevancy (RAGAS)

Ingestion Layer:
  - Document ingestion lag (upload → indexed p95)
  - Embedding API error rate, latency
  - Kafka consumer lag
  - Index build queue depth

Business Layer:
  - Daily Active Users
  - Thumbs-up rate (positive feedback ratio)
  - Session length (proxy for answer quality)
  - Search-to-answer conversion (users who search and then ask a RAG question)
```

### Alerting Rules

```yaml
# PagerDuty-style alert definitions

- name: RAG TTFT p99 > 3s
  condition: histogram_quantile(0.99, rag_ttft_bucket) > 3
  severity: critical
  action: escalate to on-call + check LLM API status

- name: Recall@10 drop > 5%
  condition: weekly_recall_10 < (baseline_recall_10 * 0.95)
  severity: warning
  action: ticket to ML team; investigate corpus change or index issue

- name: Ingestion lag > 15 minutes
  condition: doc_ingest_p95_latency_minutes > 15
  severity: warning
  action: check Kafka consumer lag, Milvus IndexNode queue

- name: QueryNode memory > 90%
  condition: milvus_querynode_mem_used / milvus_querynode_mem_total > 0.9
  severity: critical
  action: scale out QueryNodes immediately (risk of segment eviction)
```

---

## D — Distinctive Features

### Feature 1: Multi-Modal Support (PDF Images)

```
PDF with embedded figures → extraction pipeline:
  1. pdfplumber extracts text per page
  2. pdf2image + PyMuPDF extracts embedded images
  3. BLIP-2 generates caption for each image:
     "A bar chart showing quarterly revenue growth from Q1 2022 to Q4 2023"
  4. Caption embedded with same text embedding model
  5. Stored with modality="image_caption" + s3_path to original image
  
Search result rendering:
  - Text chunks: display text excerpt
  - Image caption chunks: display image from S3 + caption
```

### Feature 2: Conversation-Aware Retrieval

Naive RAG treats each query independently. For multi-turn conversations, earlier context should influence retrieval.

```python
def contextual_query_expansion(
    current_question: str,
    conversation_history: list[dict]
) -> str:
    """Expand current question with context from conversation."""
    if not conversation_history:
        return current_question
    
    # Use LLM to resolve coreferences and expand the question
    expansion_prompt = f"""
Given this conversation:
{format_history(conversation_history[-4:])}

The user now asks: "{current_question}"

Rewrite the question to be fully self-contained and explicit 
(resolve pronouns, include context from conversation).
Return only the rewritten question."""
    
    expanded = gpt4o_mini.invoke(expansion_prompt)
    return expanded

# Example:
# History: "Tell me about the transformer architecture"
#          "It was introduced in 2017 by Vaswani et al."
# Current: "What are its main components?"
# Expanded: "What are the main components of the transformer architecture 
#            introduced by Vaswani et al. in 2017?"
```

### Feature 3: Feedback Loop for Fine-Tuning

Negative feedback (thumbs down) + corrections feed into embedding model fine-tuning:

```
Collection pipeline:
  User thumbs-down → feedback.correction (optional) logged to PostgreSQL
  
Weekly processing job:
  SELECT query_text, retrieved_chunk_ids, rating, correction
  FROM feedback
  WHERE created_at > NOW() - INTERVAL '7 days'
  
  Positive pairs: (query, retrieved_chunk) where rating = "positive"
  Hard negatives: (query, retrieved_chunk) where rating = "negative"
  
  → Train sentence-transformers model with MultipleNegativesRankingLoss
  → Evaluate on hold-out eval set: recall@10 must improve by > 2%
  → If passes: deploy new embedding model version + trigger re-indexing
```

### Feature 4: Multi-Tenant Data Isolation

```
Tenant isolation guarantees:
  1. Query-time: Milvus partition key ensures tenant_id filter is enforced
     even if client sends no filter → server-side injection
  
  2. Storage-level: tenant data co-mingled in shared Milvus collection,
     but partition key creates physical separation within collection
  
  3. For premium tenants (enterprise tier): dedicated collection + dedicated
     QueryNode set. Complete physical isolation.

Security validation:
  - All API endpoints extract tenant_id from JWT (not from request body)
  - QueryNode search requests include server-injected tenant_id predicate
  - Integration tests validate cross-tenant data leakage (part of CI/CD)
```

---

## Failure Modes and Mitigations

| Failure | Detection | Mitigation |
|---|---|---|
| Milvus QueryNode OOM | Memory alert > 90% | Auto-scale QueryNodes (k8s HPA); reduce ef temporarily |
| OpenAI API rate limit | LLM error rate spike | Multiple API keys; Azure OpenAI as fallback; queue + retry |
| Embedding model upgrade (stale vectors) | Recall@10 drop | Recall monitoring + model_version metadata check |
| Kafka consumer lag (ingestion backlog) | Kafka lag metric > 10K | Scale ingestion workers; alert if lag > 15 min |
| ANN recall drift (corpus distribution shift) | Weekly recall evaluation | Re-tune index parameters; consider model fine-tuning |
| Cold start after deployment | Latency spike at deploy | Warm-up queries in readiness probe before traffic |
| LLM hallucination | RAGAS faithfulness < 0.9 | Stricter system prompt; add citation validation pass |
| Cross-tenant data leak | Security audit, pentest | JWT-injected tenant_id; integration tests; dedicated collections for enterprise |

---

## FAANG Interview Callout

> **Principal engineer scope**: This design handles 3 cross-cutting concerns that distinguish principal from senior work: (1) cost-capacity trade-off (MRL 512d vs 1536d, $19K vs $40K/month), (2) multi-tenancy security (server-side tenant_id injection, dedicated collections for enterprise), (3) quality feedback loop (thumbs-down → fine-tuning pipeline → recall@10 gates deployment).

**What makes this answer stand out**:
- Concrete capacity numbers: 60M chunks, 137GB QueryNode memory, $19.6K/month
- TTFT budget breakdown: every millisecond accounted for
- Three distinctive features that show operational and product thinking
- Failure modes with specific detection + mitigation

---

## Related Files

- [../../technologies/vector-db/README.md](../../technologies/vector-db/README.md) — vector database selection
- [../../technologies/vector-db/01-architecture.md](../../technologies/vector-db/01-architecture.md) — Milvus architecture, HNSW index
- [../../technologies/vector-db/04-tuning-guide.md](../../technologies/vector-db/04-tuning-guide.md) — tuning parameters used in this design
- [../llm-applications/embedding-strategies.md](../llm-applications/embedding-strategies.md) — embedding model selection, chunking strategies
- [../llm-applications/vector-retrieval-patterns.md](../llm-applications/vector-retrieval-patterns.md) — retrieval patterns, re-ranking, evaluation
