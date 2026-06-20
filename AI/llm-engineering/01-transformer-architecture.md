# Transformer Architecture — Internals

Understanding what actually happens inside a transformer is prerequisite knowledge for every training and inference decision you'll make. This file goes one level below the surface: not just "attention is all you need" but *why*, and *what breaks when you scale*.

---

## The Core Problem Transformers Solve

RNNs/LSTMs processed sequences token-by-token, which created two hard problems:
1. **Sequential bottleneck**: can't parallelize training over sequence length.
2. **Vanishing gradients**: long-range dependencies degrade over hundreds of tokens.

Transformers solve both by processing the entire sequence simultaneously using **attention**, where every token can directly attend to every other token.

---

## Tokenization: Before Any Math Happens

```
Raw text: "Parse <div class='product'>$29.99</div>"
     │
     ▼  tokenizer (BPE, WordPiece, SentencePiece)
     │
Tokens: ["Parse", " <div", " class", "='", "product", "'>", "$", "29", ".", "99", "</div", ">"]
Token IDs: [12843, 523, 770, 11626, 3017, 1404, 3, 1895, 13, 2079, 1701, 29]
```

| Tokenizer | Algorithm | Used By | HTML/Code Handling |
|-----------|-----------|---------|-------------------|
| BPE (Byte-Pair Encoding) | Merge most frequent pairs iteratively | GPT-2, GPT-3, LLaMA | Good — byte-level variant handles any Unicode |
| WordPiece | Maximize likelihood of training data | BERT, DistilBERT | Mediocre — splits on characters not bytes |
| SentencePiece | Language-agnostic BPE/unigram | T5, LLaMA, Mistral | Good — treats whitespace as token |
| tiktoken | Fast BPE with regex pre-tokenization | GPT-4, Claude | Excellent — handles code, HTML well |

**Vocab size trade-off**: Larger vocab (100K+) = fewer tokens per document = faster training + inference, but larger embedding table. Smaller vocab (32K) = cheaper memory but more tokens per sequence, hurting context-length efficiency for code/HTML.

---

## Embedding Layer

Each token ID maps to a learned vector in R^d (d = model dimension: 512 to 8192 depending on model size).

```
Token ID 523 ──► Embedding lookup ──► [0.21, -0.87, 0.04, ...] (d-dimensional vector)
```

These embeddings are initialized randomly and *learned* during training — they encode semantic similarity in geometric space.

---

## Positional Encoding: Teaching the Model About Order

Attention has no inherent notion of position. You need to inject position information.

```
Input to attention = token_embedding + positional_encoding
```

| Method | Formula | Used By | Key Property |
|--------|---------|---------|--------------|
| **Sinusoidal (absolute)** | sin/cos at different frequencies | Original Transformer, BERT | Fixed, doesn't generalize beyond training length |
| **Learned absolute** | Trainable position embeddings | GPT-2, early LLaMA | Simple but hard length-limit |
| **RoPE** (Rotary Position Embedding) | Rotate Q/K vectors by angle θ·pos | LLaMA 2/3, Mistral, Gemma | Relative positions naturally encoded; extrapolates |
| **ALiBi** (Attention with Linear Biases) | Subtract linear bias from attention scores | BLOOM, MPT | Strong length generalization, no positional params |

**RoPE is the current FAANG default** for new decoder models — it supports context extension (e.g., LLaMA 3's 128K context uses RoPE scaling) and naturally captures relative positions.

---

## The Transformer Block

Every transformer is a stack of N identical blocks. Each block:

```
Input x
  │
  ├── LayerNorm ──► Multi-Head Attention ──► Dropout ──► x + residual
  │                                                          │
  └──────────────────────────────────────── x_1 ◄───────────┘
       │
  ├── LayerNorm ──► Feed-Forward Network ──► Dropout ──► x_1 + residual
  │
Output
```

**Pre-LayerNorm** (shown above, used by LLaMA/GPT) is more stable for training than the original post-LayerNorm. This is why modern models don't suffer from the initialization sensitivity of the 2017 paper.

---

## Attention Mechanism — The Core

### Scaled Dot-Product Attention

```
         Q · K^T
Attn = softmax(────────) · V
               √d_k

where:
  Q = query  = X · W_Q   (what am I looking for?)
  K = key    = X · W_K   (what do I contain?)
  V = value  = X · W_V   (what do I return if matched?)
  d_k = dimension of Q and K
```

The √d_k scaling prevents the dot products from growing too large for large d_k, which would push softmax into regions of near-zero gradient.

```
Attention pattern for "Parse <div class='product'>$29.99</div>":

Query: "$29.99" token
Attends strongly to: "<div", "class", "product"  (context: this price is inside product div)
Attends weakly to:  "Parse", ">"                  (less relevant tokens)
```

### Multi-Head Attention

Instead of one attention operation, run H heads in parallel with separate projections:

```
MultiHead(Q,K,V) = Concat(head_1, ..., head_H) · W_O

head_i = Attention(Q·W_Q_i, K·W_K_i, V·W_V_i)
```

Each head can specialize: one head might track syntax, another semantics, another coreference. This is empirically important — pruning individual heads degrades performance on different sub-tasks.

**Memory cost of attention**: O(seq_len²) — the quadratic bottleneck that limits context length. A 128K context window requires 128K² = 16B attention operations per layer.

---

## Feed-Forward Network (FFN)

Each attention output passes through a two-layer MLP:

```
FFN(x) = activation(x · W_1 + b_1) · W_2 + b_2

Typical dimensions (7B model):
  x: d=4096, W_1: 4096×11008, W_2: 11008×4096
  (the 4× expansion is a design choice; SwiGLU uses ≈2.7×)
```

Modern models use **SwiGLU** instead of ReLU: `FFN(x) = (xW_1 ⊙ σ(xV)) · W_2`. It consistently outperforms ReLU/GELU at equal parameter count.

The FFN is where most of the "knowledge" lives — attention routes information, FFN processes it.

---

## Modern Decoder-Only Architecture (LLaMA-style)

```
                    ┌─────────────────────────────┐
Input tokens        │  Embedding (vocab_size × d)  │
                    └──────────────┬──────────────┘
                                   │ × N layers
                    ┌──────────────▼──────────────┐
                    │  RMSNorm                      │
                    │  Multi-Head Attention (RoPE)  │
                    │  + Residual                   │
                    │  RMSNorm                      │
                    │  SwiGLU FFN                   │
                    │  + Residual                   │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  RMSNorm                      │
                    │  Linear (d → vocab_size)      │
                    │  Softmax → next token probs   │
                    └─────────────────────────────┘
```

RMSNorm (vs LayerNorm): drops the mean-centering step. 7–15% faster at large scale, empirically equivalent quality.

---

## Model Variants: Choosing the Right Architecture

| Architecture | Training Objective | Use Case | Example Models |
|-------------|-------------------|----------|----------------|
| **Decoder-only** | Causal LM (predict next token) | Generation, instruction following | GPT, LLaMA, Mistral, Gemma |
| **Encoder-only** | Masked LM (predict masked tokens) | Classification, embeddings, retrieval | BERT, RoBERTa, DeBERTa |
| **Encoder-decoder** | Seq2Seq (encode input, decode output) | Translation, summarization, structured extraction | T5, BART, mT5 |

**For the HTML parsing use case**: encoder-decoder (T5-style) is a natural fit for extraction tasks (structured input → structured output), but decoder-only (LLaMA/Mistral) dominates in practice because you can instruction-tune it more flexibly and leverage a stronger base model.

---

## Scaling Laws

From Chinchilla (Hoffmann et al., 2022): given a compute budget C, the optimal allocation is:

```
N_opt ∝ C^0.5    (model parameters)
D_opt ∝ C^0.5    (training tokens)

Optimal tokens-per-parameter ≈ 20
```

GPT-3 (175B params, 300B tokens) was compute-*suboptimal* — it should have been trained on ~3.5T tokens. LLaMA 3 (8B params, 15T tokens) corrects this: deliberately overtrain smaller models for better inference economics.

**Implication for fine-tuning**: the base model's capability ceiling is determined by pre-training scale, not fine-tuning. Fine-tuning adjusts *behavior*, not *knowledge ceiling*.

---

## FAANG Interview Callout

> **"Walk me through a transformer forward pass for HTML input."**
>
> "The raw HTML string is tokenized using BPE — HTML tags often get split into meaningful sub-tokens like `<div`, `class`, `=`, so the model sees structure implicitly. Each token becomes a d-dimensional embedding, plus a RoPE positional signal injected into the attention computation rather than added to the embedding. Every transformer block then runs attention — each token computes queries, keys, and values; the query of, say, a price token attends to the surrounding product div tokens with high weight. That produces a context-aware representation, which passes through a SwiGLU FFN that applies learned transformations. After N such blocks, the final representation is projected to the vocabulary and softmaxed. For training on extraction tasks, we compute cross-entropy loss only on the output tokens (the extracted fields), not the HTML input — that's the standard instruction-following setup."

---

## Related Files

- [02-fine-tuning-base-models.md](02-fine-tuning-base-models.md) — Using this architecture as a base for HTML parsing
- [03-pretraining-and-llm-from-scratch.md](03-pretraining-and-llm-from-scratch.md) — Architecture choices during pre-training
- [04-inference-patterns.md](04-inference-patterns.md) — How KV cache exploits the attention computation
