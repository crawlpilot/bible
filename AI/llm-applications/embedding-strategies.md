# Embedding Strategies — From Word2Vec to Multimodal Transformers

> **Scope**: The complete evolution of text embedding techniques (Word2Vec → BERT → modern LLMs), how to select embedding models for production, chunking strategies for RAG, and practical best practices. Written for both the principal engineer who needs to reason about architectural trade-offs, and the practitioner new to the space. RNN/LSTM limitations are explained explicitly as motivation for why transformers won.

---

## Part A: Historical Evolution of Embedding Techniques

Understanding the historical progression matters: every earlier technique's limitation directly motivates the next. An interviewer who asks "why Sentence-BERT?" expects you to trace back to why vanilla BERT fails for sentence similarity.

### The Core Problem: Semantic Representation

Before embeddings, the dominant text representation was **one-hot encoding** + **TF-IDF**:

```
Vocabulary: {"cat": 0, "feline": 1, "dog": 2, ...}  (50,000 dimensions)
"cat" → [1, 0, 0, ..., 0]  (only index 0 is hot)
"feline" → [0, 1, 0, ..., 0]  (orthogonal to "cat")

Problem: cos(cat, feline) = 0 — semantically similar words are maximally dissimilar
```

**Goal of embeddings**: map words / sentences / documents into a dense vector space where semantic similarity = geometric proximity.

---

### 1. TF-IDF and BM25 (Pre-Neural, ~1972–present)

**TF-IDF**: Weight terms by frequency in document (TF) × inverse frequency across corpus (IDF). Produces sparse vectors of vocabulary size.

$$\text{tf-idf}(t, d) = \text{tf}(t,d) \times \log\frac{N}{df(t)}$$

**BM25** (Best Match 25, Robertson & Walker 1994): Improved TF-IDF with document length normalization and saturation:

$$\text{BM25}(q, d) = \sum_{t \in q} \text{IDF}(t) \cdot \frac{f(t,d) \cdot (k_1 + 1)}{f(t,d) + k_1 \cdot (1 - b + b \cdot |d|/\text{avgdl})}$$

Where $k_1 = 1.2$, $b = 0.75$ are typical defaults.

**Strengths**: Interpretable, fast, exact keyword matching, language-agnostic, zero compute cost.
**Weaknesses**: Vocabulary mismatch (synonym problem), no semantic understanding, no multilingual support.
**Still used in production**: Hybrid retrieval systems (BM25 + dense vector fusion), Elasticsearch/Solr as primary search engine, sparse component in SPLADE.

---

### 2. Word2Vec (Mikolov et al., Google, 2013)

**Paper**: "Efficient Estimation of Word Representations in Vector Space"

**Core idea**: Train a shallow neural network to predict context from word (or word from context). The learned internal weights become word embeddings.

**Two architectures**:

| Architecture | Task | Best For |
|---|---|---|
| **CBOW** (Continuous Bag of Words) | Predict center word from context words | Frequent words; faster training |
| **Skip-gram** | Predict context words from center word | Rare words; better for small datasets |

```
Skip-gram training signal:
  Context window: ["The", "quick", [brown], "fox", "jumps"]
  Input: "brown" (one-hot)
  Target: predict "The", "quick", "fox", "jumps"
  
  Loss: maximize log P(context | center)
  Gradient updates move "brown" closer to its typical neighbors
```

**Negative Sampling**: Instead of normalizing over entire vocabulary (50K softmax), sample K "negative" (unlikely) words to contrast against positive context. Reduces training from O(V) to O(K).

**Emergent property — analogy arithmetic**:
```
king - man + woman ≈ queen
Paris - France + Germany ≈ Berlin
```
This demonstrates that the vector space encodes relational semantics geometrically.

**Limitations**:
- **Static embeddings**: "bank" has the same vector regardless of context ("river bank" vs "savings bank")
- **Word-level only**: cannot represent phrases or sentences directly
- **No subword information**: "running" and "run" have unrelated vectors; OOV words fail

---

### 3. GloVe (Pennington et al., Stanford, 2014)

**Paper**: "GloVe: Global Vectors for Word Representation"

**Key difference from Word2Vec**: Word2Vec uses local context windows (sequential, stochastic). GloVe uses the **global co-occurrence matrix** across the entire corpus.

$$J = \sum_{i,j=1}^{V} f(X_{ij})(w_i^T \tilde{w}_j + b_i + \tilde{b}_j - \log X_{ij})^2$$

Where $X_{ij}$ is the co-occurrence count of words i and j, and f is a weighting function that caps common co-occurrences.

**Strength over Word2Vec**: Incorporates corpus-wide statistics, not just local windows. Better on word analogy and similarity benchmarks.
**Same limitation**: Static word-level embeddings; no contextualization.

**Production use**: GloVe pretrained vectors (50d, 100d, 200d, 300d) were widely used as feature initialization for NLP tasks 2014–2018. Largely superseded by BERT-era models for production, but still appear in legacy systems and as baselines.

---

### 4. FastText (Facebook AI Research, 2016)

**Paper**: "Enriching Word Vectors with Subword Information"

**Key innovation**: Represent words as bags of character n-grams. The word vector = sum of n-gram vectors.

```
"apple" (n=3 to 6 character n-grams):
  <ap, app, ppl, ple, le>
  <app, appl, pple, ple>
  <appl, apple, pple>
  <apple, apple>
  + the full word token <apple>

Vector("apple") = sum(vector("app") + vector("ppl") + ... + vector("<apple>"))
```

**Advantages over Word2Vec/GloVe**:
- **OOV handling**: Can embed any word by summing known n-gram vectors. "Instagrammable" → not in vocab, but n-grams are.
- **Morphological languages**: Especially powerful for German, Turkish, Finnish where suffixes carry meaning
- **Rare word handling**: Rare words share subword structure with common words

**Limitation**: Still static (same vector per word regardless of context).

**Production use**: Facebook used FastText for language identification (176 languages) and text classification. Still used in industry for lightweight embedding needs.

---

### 5. ELMo (Peters et al., AI2/UW, 2018)

**Paper**: "Deep Contextualized Word Representations"

**Key breakthrough**: The first broadly used **contextualized embeddings**. The same word gets different vectors based on surrounding context.

**Architecture**: Bidirectional LSTM (biLSTM) — two stacked LSTM layers, one reading left-to-right, one right-to-left, on top of a character-level CNN encoder.

```
"I deposited money at the [bank]." 
  → biLSTM processes full sentence
  → "bank" vector ≈ financial institution

"I fished from the river [bank]."
  → biLSTM processes full sentence  
  → "bank" vector ≈ riverbank
```

**ELMo representation**: Weighted sum of hidden states from all biLSTM layers (not just final layer). Each layer captures different granularity:
- Layer 0 (character CNN): morphological / syntactic features
- Layer 1 (biLSTM layer 1): syntactic structure
- Layer 2 (biLSTM layer 2): semantic content

**Impact**: ELMo improved state of the art on 6 NLP benchmarks simultaneously (NER, QA, SRL, co-reference, NLI, sentiment). Demonstrated that deep contextualized representations transfer effectively.

---

### 6. Why RNNs and LSTMs Failed to Scale — The Attention Motivation

Understanding the limitations of RNN/LSTM architectures is essential context for why transformers became dominant. An interviewer asking "why not use ELMo in production?" expects this answer.

#### RNN / LSTM Fundamental Limitations

**1. Sequential processing — parallelization impossible**

```
RNN: h_t = tanh(W_h × h_{t-1} + W_x × x_t)

Token 5 depends on Token 4 state.
Token 4 depends on Token 3 state.
...
→ No GPU parallelism across time steps within a sequence
→ Training wall-clock time scales linearly with sequence length
```

For a 512-token sequence, you need 512 sequential LSTM steps before backpropagation can begin. A transformer processes all 512 tokens simultaneously.

**2. Vanishing/exploding gradients**

Backpropagation through time (BPTT) requires multiplying gradients across t time steps:
$$\frac{\partial L}{\partial h_0} = \prod_{t=1}^{T} \frac{\partial h_t}{\partial h_{t-1}}$$

If each term < 1, the product → 0 exponentially (vanishing). If > 1, → ∞ (exploding).

LSTM gating partially addresses this but does not eliminate it for sequences > ~100 tokens.

**3. Long-range dependency capture degrades**

Even with LSTM's gating, information from token 1 must pass through hundreds of state updates to influence token 500. Each state update can corrupt, dilute, or overwrite previous signal. Empirically, LSTMs struggle with dependencies > 100 tokens apart.

**4. Fixed-size context bottleneck (pre-LSTM seq2seq)**

Encoder-decoder RNNs compress entire input into a single fixed-size vector. Information from early tokens may be lost.

#### How Attention Solves These Problems

Self-attention computes direct relationships between **all pairs** of tokens simultaneously:

$$\text{Attention}(Q, K, V) = \text{softmax}\left(\frac{QK^T}{\sqrt{d_k}}\right)V$$

- Token 1 can directly attend to Token 500 — O(1) path length regardless of distance
- All tokens processed in parallel (matrix multiplication on GPU)
- No vanishing gradient through recurrent connections
- Scales with model size and data (scaling laws)

**The result**: Transformers replaced RNNs for every NLP embedding task post-BERT (2018). ELMo/biLSTM is not used in new production systems.

---

### 7. BERT (Devlin et al., Google, 2018)

**Paper**: "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding"

**Architecture**: Stacked transformer encoder blocks (12 for BERT-base, 24 for BERT-large). Bidirectional: every token attends to all other tokens simultaneously (unlike GPT's causal/left-to-right attention).

**Pre-training tasks**:
1. **Masked Language Model (MLM)**: Randomly mask 15% of tokens; predict masked tokens. Forces learning bidirectional context.
2. **Next Sentence Prediction (NSP)**: Given two sentences, predict if B follows A in corpus. (Later shown to be less useful; removed in RoBERTa)

**Why bidirectional matters**:
```
GPT (causal):  "The bank by the [MASK]"
               Can only use "The bank by the" — no right-side context

BERT:          "The bank by the [MASK] was flooded"
               Uses both left AND right context → "river" much more likely
```

**Token representations**:
- `[CLS]` token prepended to every input — its final hidden state used as sentence-level representation
- `[SEP]` token separates sentence pairs

**BERT for sentence embeddings (naive approach)**:
```python
# Mean pooling last layer hidden states
embedding = bert_output.last_hidden_state.mean(dim=1)  # [batch, hidden]

# OR: CLS token
embedding = bert_output.last_hidden_state[:, 0, :]  # [batch, hidden]
```

**Critical finding**: Vanilla BERT embeddings are poor for sentence similarity tasks (see Sentence-BERT below). CLS pooling and mean pooling both produce vectors that cluster tightly in a narrow cone of the embedding space — cosine similarity is artificially high between all sentence pairs.

---

### 8. RoBERTa, ALBERT, DistilBERT — BERT Variants

| Model | Key Difference | Trade-off |
|---|---|---|
| **RoBERTa** (Facebook, 2019) | Removed NSP; longer training; dynamic masking; more data | Better downstream tasks; same size as BERT-large |
| **ALBERT** (Google, 2019) | Parameter sharing across layers; factorized embedding | 18× fewer parameters; slower inference per token |
| **DistilBERT** (Hugging Face, 2019) | Knowledge distillation from BERT-base (6 → 12 layers) | 40% smaller, 60% faster, 97% of BERT-base performance |

**Production guidance**: DistilBERT for latency-sensitive, resource-constrained. RoBERTa when quality is paramount and compute is not a concern.

---

### 9. Sentence-BERT (Reimers & Gurevych, UKP-Lab, 2019)

**Paper**: "Sentence-BERT: Sentence Embeddings using Siamese BERT-Networks"

**The problem with vanilla BERT for semantic similarity**:
- Comparing n sentences with BERT requires n(n-1)/2 inference calls (one per pair)
- For 10,000 sentences: 50M inference calls — ~65 hours on a GPU
- BERT's CLS/mean-pool embeddings cluster in a degenerate narrow cone

**Sentence-BERT solution**: Fine-tune BERT with a **siamese network** architecture specifically for sentence similarity.

```
Siamese architecture:
  Input A → BERT → mean pool → u (sentence vector)
  Input B → BERT → mean pool → v (sentence vector)
  
  Objective: minimize |u - v| for similar pairs, maximize for dissimilar
  
  Training signals:
  - Natural Language Inference (NLI) pairs: entailment (+), contradiction (-), neutral
  - Semantic Textual Similarity (STS) datasets: human-rated 0–5 similarity scores
```

**Why this works**: The fine-tuning objective explicitly teaches BERT that similar sentences should have nearby embeddings. Vanilla BERT was only trained to understand language in context, not to produce distance-meaningful sentence vectors.

**Result**: 
- Comparing 10,000 sentences: from 65 hours → 5 seconds (encode all sentences once with bi-encoder)
- STS benchmark: BERT+CLS 58% → SBERT 80%+ Spearman correlation

**Sentence-BERT variants and families** (2020–2024):

| Model Family | Key Innovation | MTEB Score | Dimensions |
|---|---|---|---|
| **SBERT (all-mpnet-base-v2)** | MPNet backbone, pair training | 57.0 | 768 |
| **E5 series** (Microsoft) | Instruction-following embeddings: prefix with "query:" or "passage:" | 66.6 (E5-large) | 1024 |
| **BGE series** (BAAI) | Hard negative mining, academic quality | 64.2 (BGE-large) | 1024 |
| **GTE series** (Alibaba/Thudm) | Multi-task training | 63.1 (GTE-large) | 1024 |
| **Instructor** (HKU) | Task-specific instruction prefix | 59.4 | 768 |

---

### 10. OpenAI Embeddings (2022–2024)

**text-embedding-ada-002** (2022)
- 1536 dimensions
- Replaced 5 earlier OpenAI embedding models
- $0.10 / 1M tokens
- MTEB Avg: ~61

**text-embedding-3-small** (2024)
- Supports **Matryoshka Representation Learning (MRL)**: configurable output dimensions (512, 1024, 1536)
- $0.02 / 1M tokens — 5× cheaper than ada-002
- MTEB Avg: 62.3 at 1536d, 60.0 at 512d (meaningful quality at fraction of memory)

**text-embedding-3-large** (2024)
- Supports MRL: 256 to 3072 dimensions
- $0.13 / 1M tokens
- MTEB Avg: 64.6 at 3072d, 62.0 at 256d

**Matryoshka Representation Learning (MRL) explained**:
```
Traditional embedding: must use full 1536d to preserve quality
  ada-002 truncated to 512d → ~40% quality loss

MRL training: jointly optimize for quality at multiple dimensions
  text-embedding-3-small at 512d → only ~3% quality loss vs full 1536d
  
Why: MRL training forces most important information into first dimensions,
     less important into later dimensions.
     You can truncate and still preserve core semantics.
```

---

### 11. Cohere Embed v3 (2023)

**Key differentiators**:
- Produces **int8 and binary embeddings natively** (not post-hoc quantization)
- 1024 dimensions
- Multilingual support (100+ languages)
- `input_type` parameter: `search_document` vs `search_query` (asymmetric — document and query are embedded differently for better retrieval)
- $0.10 / 1M tokens

**int8 binary output**: Models trained to produce well-distributed int8 representations → can store as int8 without dequantization loss. Binary output further reduces to 128 bytes/vector.

---

### 12. Recent Developments (2024)

**Voyage AI** (2024): 
- voyage-3 and voyage-3-lite models
- 1024d, among best MTEB scores for commercial models
- Specializations: `voyage-code-3` for code, `voyage-law-2` for legal

**E5-mistral-7b-instruct** (2024):
- 4096d embeddings from a 7B parameter LLM
- Instruction-following: "Represent this document for retrieval: {text}"
- MTEB 66.6 — top open-source at the time
- Trade-off: ~20ms per embedding on A100 vs ~2ms for SBERT models

**NomicAI nomic-embed-text-v1.5** (2024):
- 8192 token context length (vs 512 for most BERT-based)
- MRL support: 64 to 768 dimensions
- Open weights, high quality for long documents

---

### 13. Multimodal Embeddings

**CLIP (Radford et al., OpenAI, 2021)**:
- Jointly embeds text and images into a shared 512d or 768d space
- Training: contrastive loss on 400M (image, text) pairs from internet
- At inference: `encode_image(img)` and `encode_text(text)` produce comparable vectors
- Application: reverse image search, image-text retrieval, zero-shot image classification

```
Image: [photo of a cat]  → CLIP image encoder → [0.3, -0.1, 0.8, ...]
Text:  "a cat sitting"   → CLIP text encoder  → [0.28, -0.12, 0.79, ...]
cos(image_vec, text_vec) ≈ 0.94  → highly similar
```

**ImageBind (Gao et al., Meta, 2023)**:
- Extends CLIP to 6 modalities: image, text, audio, depth, thermal, IMU
- All 6 modalities embedded into the same space
- Enables cross-modal retrieval without explicit paired training for all modality pairs

---

### RNN vs Transformer Summary Table

| Dimension | RNN / LSTM | Transformer |
|---|---|---|
| **Parallelism** | Sequential (step t depends on t-1) | Fully parallel (attention is a matrix multiply) |
| **Long-range dependencies** | Degrades at > 100 tokens | O(1) path between any two tokens |
| **Gradient flow** | Vanishing/exploding (mitigated by gates) | Direct residual connections; no vanishing |
| **Context window** | Effective ~100–200 tokens | 512 (BERT) → 8192 (NomicEmbed) → unlimited (ALiBi) |
| **GPU utilization** | Poor (sequential bottleneck) | Excellent (batched matrix multiplications) |
| **Scaling behavior** | Performance plateaus early | Follow scaling laws with data+compute |
| **Production use** | Legacy systems only | Industry standard (2019–present) |
| **Best remaining use** | Streaming token classification, tiny edge devices | Everything else |

---

## Part B: Chunking Strategies

Chunking is the process of splitting source documents into segments before embedding. It is one of the highest-leverage RAG tuning decisions: bad chunking → semantic boundaries broken → poor retrieval → hallucinations.

### Chunking Trade-off

```
Large chunks:                          Small chunks:
+ More context per retrieved chunk     + More precise semantic focus
+ Fewer vector DB queries              + Better recall for specific facts
- Harder to embed precisely            - More storage, more vectors
- LLM context filled with irrelevant   - May miss broader context
  surrounding text                     - More embedding API cost
```

**Rule of thumb**: chunk size should match the typical retrieval unit. If users ask specific factual questions → small chunks (128–256 tokens). If users ask for explanations → medium chunks (512–1024 tokens).

---

### Strategy 1: Fixed-Size Chunking

Split by character or token count; optionally add overlap.

```python
from langchain.text_splitter import CharacterTextSplitter

splitter = CharacterTextSplitter(
    chunk_size=1000,   # characters
    chunk_overlap=200  # 20% overlap
)
chunks = splitter.split_text(document)
```

**Pros**: Simple, deterministic, fast.
**Cons**: Splits mid-sentence, mid-paragraph — breaks semantic units.
**Use when**: Documents are already semi-structured (code, log lines), or as a fallback.

---

### Strategy 2: Sentence-Level Chunking

Split at sentence boundaries (NLTK `sent_tokenize`, spaCy `sentencizer`).

```python
import nltk
sentences = nltk.sent_tokenize(document)
# Optionally group into windows of N sentences
chunks = [" ".join(sentences[i:i+3]) for i in range(0, len(sentences), 3)]
```

**Pros**: Preserves sentence integrity; good for factual QA where answers are single sentences.
**Cons**: Variable chunk sizes; adjacent-sentence context may be lost.
**Use when**: FAQ retrieval, fact-dense documents (legal, scientific).

---

### Strategy 3: Semantic Chunking

Split at topic boundaries detected by cosine similarity drop between consecutive sentence embeddings.

```python
from langchain_experimental.text_splitter import SemanticChunker
from langchain_openai import OpenAIEmbeddings

splitter = SemanticChunker(
    OpenAIEmbeddings(),
    breakpoint_threshold_type="percentile",  # or "standard_deviation"
    breakpoint_threshold_amount=95           # split when similarity drops to 95th %ile
)
chunks = splitter.create_documents([document])
```

**Mechanism**:
1. Embed every sentence
2. Compute cosine similarity between adjacent sentence embeddings
3. Split where similarity drops below threshold (topic shift detected)

**Pros**: Semantically coherent chunks; natural topic boundaries.
**Cons**: Requires embedding every sentence during preprocessing; variable chunk sizes; higher preprocessing cost.
**Use when**: Long-form content (blog posts, reports, books) where topics shift mid-document.

---

### Strategy 4: Recursive Character Text Splitter (LangChain Default)

Split by ordered list of separators: paragraph → sentence → word → character.

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter

splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,
    chunk_overlap=200,
    separators=["\n\n", "\n", ". ", " ", ""]  # tries each in order
)
```

**Mechanism**: Try to split on `\n\n` (paragraph). If still too large, fall back to `\n`, then `. `, etc.

**Pros**: Respects natural document structure; avoids arbitrary word splits; practical default.
**Cons**: Not semantically-aware; still may split related content at paragraph level.
**Best for**: Most text content — the practical starting point before more complex strategies.

---

### Strategy 5: Parent-Child Chunking (Small-to-Big Retrieval)

Store two levels: small chunks (indexed for retrieval precision) + large parent chunks (returned for LLM context).

```
Document:
  Parent chunk 1 (1024 tokens): full section
    ├── Child chunk 1a (256 tokens): first paragraph  ← embedded + stored in vector DB
    ├── Child chunk 1b (256 tokens): second paragraph ← embedded + stored in vector DB
    └── Child chunk 1c (256 tokens): third paragraph  ← embedded + stored in vector DB

Search query:
  1. ANN search on child chunk embeddings → find most similar child
  2. Look up parent_id of matched child
  3. Retrieve parent chunk from document store → feed to LLM
```

**Pros**: Combines precision of small-chunk retrieval with broad context of large chunks; prevents LLM from receiving context-starved fragments.
**Cons**: 2× storage (parent + child); requires parent-child metadata; more complex pipeline.
**Use when**: Technical documentation, legal documents, scientific papers where context surrounding a specific fact matters.

---

### Strategy 6: Proposition Indexing (Atomic Claims)

**Paper**: "Dense X Retrieval: What Retrieval Granularity Should We Use?" (Chen et al., 2023)

Decompose documents into atomic propositions — single self-contained factual claims.

```
Input paragraph:
  "Mount Everest, known in Nepali as Sagarmatha, stands at 8,849 meters. 
   It was first summited by Edmund Hillary and Tenzing Norgay on May 29, 1953."

Atomic propositions:
  1. "Mount Everest is known in Nepali as Sagarmatha."
  2. "Mount Everest stands at 8,849 meters."
  3. "Mount Everest was first summited on May 29, 1953."
  4. "Edmund Hillary and Tenzing Norgay were the first to summit Mount Everest."
```

**How**: Use an LLM (prompt: "Decompose the following text into atomic factual propositions") during document preprocessing.

**Pros**: Maximum precision; each chunk answers one question perfectly; no irrelevant context.
**Cons**: LLM call per document (expensive preprocessing); number of chunks per document increases 3–5×; parent context lost.
**Use when**: Fact-intensive knowledge bases (medical, legal, scientific), when hallucination risk is highest.

---

### Strategy 7: Document-Level Embedding

Generate a summary embedding for the entire document, used as a navigation layer.

```
Two-level retrieval:
  1. Document embedding search → identify most relevant documents
  2. Within top documents, chunk-level search → find precise passages
```

**Use when**: Very large document corpora (millions of documents); want to narrow to 10–50 relevant documents before chunk-level search.

---

### Chunking Strategy Comparison

| Strategy | Precision | Context Quality | Preprocessing Cost | Dynamic Documents | Best For |
|---|---|---|---|---|---|
| Fixed-size | Low | Medium | Minimal | ✅ easy | Baseline, code, logs |
| Sentence | Medium | Medium | Low | ✅ | Factual QA |
| Semantic | High | High | High (embed all sentences) | ⚠️ expensive update | Long-form content |
| Recursive splitter | Medium | Good | Low | ✅ | General default |
| Parent-child | High | Excellent | Medium | ⚠️ complex | Technical/legal docs |
| Proposition | Very high | Low (atomic) | Very high (LLM per doc) | ❌ expensive | Medical/scientific facts |
| Document-level | Navigation only | Very broad | Low | ✅ | Million-doc corpora |

**Overlap recommendation**: 10–20% overlap between adjacent chunks. Prevents clean splits from burying a relevant fact across a boundary. For 1000-char chunks, use 100–200 char overlap.

---

## Part C: Embedding Best Practices

### 1. Normalize Vectors for Cosine Similarity

Always L2-normalize vectors at ingestion time when using cosine or inner-product metrics:

```python
import numpy as np

def normalize(vectors: np.ndarray) -> np.ndarray:
    """L2-normalize a batch of vectors."""
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    return vectors / (norms + 1e-8)  # epsilon prevents division by zero

# With OpenAI: vectors are already normalized for text-embedding-3-*
# With sentence-transformers: normalize_embeddings=True parameter
model.encode(texts, normalize_embeddings=True)
```

**Why**: Cosine similarity = inner product of normalized vectors. Pre-normalizing enables use of the faster `METRIC_IP` in Milvus/FAISS rather than computing norms at query time. Also prevents magnitude bias (longer documents ≠ more relevant).

### 2. Batch API Calls

Never embed one document at a time in a loop:

```python
# BAD: N API calls, N × overhead
for text in texts:
    embedding = openai.embeddings.create(input=text, model="text-embedding-3-small")

# GOOD: 1 API call, 2048 inputs max (OpenAI limit)
BATCH_SIZE = 512  # balance throughput vs retry cost
batches = [texts[i:i+BATCH_SIZE] for i in range(0, len(texts), BATCH_SIZE)]
for batch in batches:
    response = openai.embeddings.create(input=batch, model="text-embedding-3-small")
    embeddings = [item.embedding for item in response.data]
```

**OpenAI limits**: Max 2048 inputs per request; max 8191 tokens per input; max 1M tokens/min (tier 3).

### 3. Cache Embeddings by Content Hash

```python
import hashlib, json, redis

r = redis.Redis(host="localhost", port=6379, db=0)

def get_or_create_embedding(text: str, model: str) -> list[float]:
    cache_key = f"embed:{model}:{hashlib.sha256(text.encode()).hexdigest()}"
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    embedding = openai.embeddings.create(input=text, model=model).data[0].embedding
    r.setex(cache_key, 86400 * 30, json.dumps(embedding))  # 30-day TTL
    return embedding
```

**When to cache**: All document embeddings (content changes rarely). Do NOT cache query embeddings unless exact query repetition is common.

**Cache invalidation**: When you upgrade embedding models, all cached embeddings are invalid. Use model version in cache key (`embed:text-embedding-3-small-v1:...`).

### 4. Domain Fine-Tuning Trigger Points

When should you fine-tune an embedding model on your domain?

| Signal | Interpretation | Action |
|---|---|---|
| MTEB score of chosen model is < 60 on similar benchmarks | Model may not generalize to your domain | Consider domain fine-tuning |
| Retrieval recall@10 < 90% after index tuning | Embedding model is the bottleneck, not index | Fine-tune with in-domain pairs |
| User queries use domain-specific jargon not in BERT vocab | OOV / rare term problem | FastText or fine-tuning with domain corpus |
| Cross-lingual queries not supported | Model is English-only | Switch to multilingual model (Cohere, E5-multilingual) |

**Fine-tuning approach**: Contrastive learning with (query, positive passage, negative passage) triplets. Use sentence-transformers `MultipleNegativesRankingLoss` or `CosineSimilarityLoss`. Requires 1K–100K labeled pairs.

### 5. Embedding Model Versioning Strategy

```
Embedding model lifecycle management:

v1: text-embedding-ada-002 (deployed 2023-Q1)
  - All 10M document embeddings stored with model_version="ada-002"

Model upgrade to v2: text-embedding-3-large
  - DO NOT delete v1 embeddings
  - Create new collection "docs_embeddings_v2"
  - Run backfill job: re-embed all 10M documents
  - Canary test: route 5% traffic to v2, measure recall@10
  - Gradual rollout: 5% → 25% → 100%
  - Delete v1 collection after v2 fully validated
```

**Anti-pattern**: Migrating embeddings in-place without testing recall regression. A new model may have higher average quality but lower recall for your specific domain.

### 6. Dimensionality Reduction for Cost Optimization

Use MRL (Matryoshka) models and truncation to reduce storage and query cost:

```python
# text-embedding-3-small supports MRL dimensions: 512, 1024, 1536
from openai import OpenAI

client = OpenAI()
response = client.embeddings.create(
    input="Your text here",
    model="text-embedding-3-small",
    dimensions=512  # request smaller representation
)
# MTEB quality at 512d: ~96.7% of full 1536d quality
# Memory/storage reduction: 3×
```

**When to use truncation without MRL**: Generally don't. Simple truncation of FP32 embeddings without MRL training causes disproportionate quality loss. Only use with MRL-trained models (text-embedding-3-*, Cohere embed-v3, nomic-embed-text-v1.5).

**PCA reduction alternative**:
```python
from sklearn.decomposition import PCA

# Fit PCA on a representative sample (not all vectors — too slow)
pca = PCA(n_components=256, random_state=42)
pca.fit(sample_embeddings)  # fit on 100K sample

# Apply to all vectors
reduced_embeddings = pca.transform(all_embeddings)

# Measure recall degradation before committing to PCA reduction
# Rule of thumb: if explained_variance_ratio_.sum() > 0.98, safe to reduce
print(f"Explained variance: {pca.explained_variance_ratio_.sum():.3f}")
```

### 7. Rate Limiting and Retry Strategy

```python
import time
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
from openai import RateLimitError, APIConnectionError

@retry(
    retry=retry_if_exception_type((RateLimitError, APIConnectionError)),
    wait=wait_exponential(multiplier=1, min=4, max=60),
    stop=stop_after_attempt(6)
)
def embed_with_retry(texts: list[str]) -> list[list[float]]:
    response = openai.embeddings.create(
        input=texts,
        model="text-embedding-3-small"
    )
    return [item.embedding for item in response.data]
```

**Cost estimation for ingestion at scale**:
```
10M documents × 512 tokens avg × $0.02/1M tokens (text-embedding-3-small)
= 10M × 512 / 1,000,000 × $0.02
= 5,120 tokens × $0.02 / 1M
= $0.10 per 5M tokens... 

Let me recalculate:
10M documents × 512 tokens = 5.12B tokens
5.12B / 1M × $0.02 = $102.40 total one-time ingestion cost

At 1M new documents/day:
512M tokens/day × $0.02/1M = $10.24/day ongoing cost
```

---

## Model Selection Decision Matrix

| Model | Dimensions | MTEB Avg | Cost/1M tokens | Context Window | Strengths | When to Choose |
|---|---|---|---|---|---|---|
| text-embedding-3-small | 512–1536 | 62.3 | $0.02 | 8191 tokens | MRL, cheap, good quality | Default for most RAG applications |
| text-embedding-3-large | 256–3072 | 64.6 | $0.13 | 8191 tokens | Best OpenAI quality, MRL | When recall quality is primary concern |
| text-embedding-ada-002 | 1536 | 61.0 | $0.10 | 8191 tokens | Stable, well-tested | Legacy systems; avoid for new |
| Cohere embed-v3 | 1024 | 64.5 | $0.10 | 512 tokens | Int8/binary native, multilingual | Cost-sensitive at scale; multilingual |
| BGE-large-en-v1.5 | 1024 | 64.2 | Open source | 512 tokens | Self-hosted, high quality | Privacy-sensitive; self-hosted infra |
| E5-large-v2 | 1024 | 62.5 | Open source | 512 tokens | Open source, instruction prefix | Domain-specific with instructions |
| nomic-embed-text-v1.5 | 64–768 | 62.3 | Open source | 8192 tokens | Long docs, MRL, open | Long documents, self-hosted |
| voyage-3 | 1024 | 68.0 | $0.06 | 32K tokens | Best quality overall | When MTEB score is primary criteria |
| E5-mistral-7b | 4096 | 66.6 | ~$0.05 | 4096 tokens | LLM-quality embedding | Maximum quality, tolerate 20ms latency |

---

## FAANG Interview Callout

> **What an interviewer is testing**: Can you reason about why you chose a particular embedding model and chunking strategy? Do you know the trade-offs between RNN and transformer architectures? Can you reason about fine-tuning triggers and operational complexity?

**Model answer for "how would you choose an embedding model for a production RAG system?"**: *"I'd start with text-embedding-3-small — it's cheap at $0.02/1M tokens, supports MRL for dimension flexibility, and scores 62 on MTEB which is competitive for most general-domain tasks. I'd immediately evaluate recall@10 against a held-out test set of real user queries. If recall is below 90%, I'd try text-embedding-3-large or voyage-3 before considering domain fine-tuning. For chunking, I'd start with recursive character splitting at 512 tokens with 10% overlap as a baseline, then test semantic chunking if the corpus has variable-length natural topic sections. If latency becomes a concern as scale grows, I'd look at switching from 1536d to 512d with the MRL option — OpenAI's testing shows only ~3% MTEB degradation."*

---

## Related Files

- [vector-retrieval-patterns.md](vector-retrieval-patterns.md) — retrieval techniques, re-ranking, ingestion pipelines, evaluation
- [../technologies/vector-db/README.md](../technologies/vector-db/README.md) — vector database systems selection and architecture
- [../technologies/vector-db/01-architecture.md](../technologies/vector-db/01-architecture.md) — HNSW/IVF/PQ index algorithms deep-dive
- [../AI/ai-architecture/rag-system-hld.md](../ai-architecture/rag-system-hld.md) — full RESHADED HLD for production RAG systems
