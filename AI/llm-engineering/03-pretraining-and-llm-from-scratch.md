# Pre-Training and Building an LLM from Scratch

Pre-training is expensive, slow, and risky — and sometimes the only correct answer. This file covers when to do it, how to do it, and the engineering decisions that compound across billions of tokens.

---

## When to Pre-Train vs. Fine-Tune

```
Does a capable base model (LLaMA, Mistral, Gemma) exist for your domain?
  │
  ├── YES ──► Can fine-tuning + prompting hit the quality bar?
  │               │
  │               ├── YES ──► Fine-tune. Stop here.
  │               │
  │               └── NO ──► Is this because of knowledge gaps (not behavior)?
  │                               │
  │                               ├── YES + data available ──► Continue pre-train
  │                               │                            on domain corpus
  │                               └── YES + data unavailable ──► RAG
  │
  └── NO ──► Do you have 100B+ domain-specific tokens?
                  │
                  ├── YES ──► Pre-train from scratch or from existing base
                  └── NO ──► Use existing base + fine-tune (no benefit)
```

**Real threshold**: Google trained Med-PaLM on general PaLM + medical fine-tuning, not from scratch. BloombergGPT pre-trained from scratch on 363B financial tokens because financial text is structurally different enough that the general base model's tokenizer and embeddings were a disadvantage. Most teams never hit this threshold.

---

## Tokenizer Training

The tokenizer is trained before the model. It's a data-preprocessing artifact, not a neural network.

```python
from sentencepiece import SentencePieceTrainer

SentencePieceTrainer.train(
    input="domain_corpus.txt",   # raw text file
    model_prefix="my_tokenizer",
    vocab_size=32000,            # LLaMA-style; 100K+ for multilingual
    character_coverage=0.9995,   # capture rare chars; 1.0 for code
    model_type="bpe",            # bpe | unigram | char | word
    pad_id=0,
    unk_id=1,
    bos_id=2,
    eos_id=3,
)
```

**Vocab size decision**:
| Vocab Size | Best For | Trade-off |
|-----------|----------|-----------|
| 32K | English-only, small model | Efficient; longer sequences for code/HTML |
| 64K | Multilingual or code-heavy | Balanced |
| 100K+ | Strong multilingual, code + HTML | Larger embedding table; better token efficiency |

For an HTML-heavy domain: a larger vocab that treats `<div>`, `</div>`, `class=` as single tokens dramatically reduces sequence length and improves training efficiency.

---

## Architecture Decisions Before Training

Every choice is a trade-off you're locked into for the duration of pre-training.

| Parameter | Formula | LLaMA-3-8B | Notes |
|-----------|---------|------------|-------|
| `d_model` (hidden dim) | — | 4096 | Width of every layer |
| `n_layers` | depth | 32 | Depth multiplies compute linearly |
| `n_heads` | d_model / head_dim | 32 | head_dim=128 is standard |
| `n_kv_heads` | n_heads / GQA factor | 8 | GQA reduces KV cache size 4× |
| `d_ffn` | ~2.7 × d_model (SwiGLU) | 14336 | Adjusted for SwiGLU gate |
| `context_length` | — | 8192 | Max sequence length at training |
| `vocab_size` | — | 128256 | Large for multilingual |

**GQA (Grouped Query Attention)**: Instead of 1 KV pair per Q head, share 1 KV pair across a group of Q heads. LLaMA 3 8B uses 8 KV heads for 32 Q heads. Effect: 4× smaller KV cache → 4× more concurrent requests at inference. Minimal quality loss.

---

## Data Pipeline

Pre-training is 80% a data engineering problem. Model architecture matters less than data quality at this scale.

```
Raw internet data (Common Crawl, GitHub, ArXiv, Books)
           │
           ▼
1. Language filtering (fastText classifier)
           │
           ▼
2. Quality filtering
   - Remove pages with < N words
   - Perplexity filter (discard garbled text)
   - Heuristic rules: remove nav bars, cookie notices, SEO spam
           │
           ▼
3. Deduplication
   - Exact dedup: MinHash LSH at document level
   - Fuzzy dedup: SimHash for near-duplicates
   - CRITICAL: train/test contamination check
           │
           ▼
4. PII scrubbing (emails, phone numbers, SSNs)
           │
           ▼
5. Domain mix weighting
   - Web: 75-80%
   - Code: 10-15%
   - Books/papers: 5-10%
           │
           ▼
6. Tokenize + pack into fixed-length sequences
   - Concatenate documents, insert EOS tokens between them
   - Fill sequences to max context length (no padding waste)
```

**WebDataset format** for streaming at scale:

```python
import webdataset as wds

dataset = (
    wds.WebDataset("data/shard-{000000..009999}.tar")  # 10K shards
       .shuffle(10000)                                   # buffer shuffle
       .decode("utf-8")
       .map(tokenize_and_pack)
       .batched(batch_size)
)
```

Streaming avoids loading 10TB into RAM — each worker reads shards independently, enabling arbitrary dataset sizes.

---

## Training Loop: The Essentials

### Mixed Precision (bf16)

```python
# Always use bf16 for LLM training, not fp16
# bf16: same exponent range as fp32, lower precision mantissa
# fp16: smaller exponent range → overflow/underflow with large gradients

model = model.to(torch.bfloat16)  # or use --bf16 in TrainingArguments
```

fp16 requires loss scaling to avoid underflow. bf16 does not — it's a strict upgrade for modern GPUs (A100/H100 have native bf16 tensor cores).

### Gradient Accumulation and Effective Batch Size

Large batch sizes stabilize training. With limited VRAM:

```python
# If you can fit batch_size=4 per GPU, but want effective=512:
# gradient_accumulation_steps = 512 / (4 × num_gpus)

# With 8 GPUs: 512 / 32 = 16 accumulation steps
optimizer.zero_grad()
for i, batch in enumerate(loader):
    loss = model(batch) / accumulation_steps
    loss.backward()
    if (i + 1) % accumulation_steps == 0:
        optimizer.step()
        optimizer.zero_grad()
```

Effective batch of 256–2048 tokens is typical for LLM pre-training. Too small → noisy gradients, slow convergence. Too large → poor generalization.

### Gradient Checkpointing

Trade compute for memory: don't store all activations during forward pass; recompute them during backward pass.

```python
model.gradient_checkpointing_enable()
# Cost: ~30% slower backward pass
# Benefit: ~5× memory reduction on activations
```

Essential for training models > 7B on < A100 80GB.

---

## Distributed Training: DDP vs FSDP vs Tensor Parallelism

| Strategy | What it shards | Best For | Overhead |
|----------|---------------|----------|----------|
| **DDP** (DistributedDataParallel) | Nothing — full replica on each GPU | < 7B models that fit in GPU VRAM | Low |
| **FSDP** (Fully Sharded Data Parallel) | Params + gradients + optimizer state | 7B–70B models | Medium (all-gather ops) |
| **Tensor Parallelism** | Individual weight matrices (column/row split) | 70B+, requires NVLink | High — tight GPU coupling needed |
| **Pipeline Parallelism** | Layers across GPUs | 70B+ without NVLink | High — bubble overhead |
| **3D Parallelism** | DP + TP + PP combined | 100B+ (GPT-4, Llama 3 405B) | Very high engineering complexity |

**For most teams**: FSDP with 8–16 A100s can handle 7B–13B model pre-training. This is the sweet spot for domain-specific models.

```python
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
from torch.distributed.fsdp.wrap import transformer_auto_wrap_policy

model = FSDP(
    model,
    auto_wrap_policy=transformer_auto_wrap_policy,
    mixed_precision=MixedPrecision(param_dtype=torch.bfloat16),
    sharding_strategy=ShardingStrategy.FULL_SHARD,
)
```

---

## Checkpointing and Recovery

Pre-training jobs fail. Plan for it.

```
Checkpoint every N steps (N = 500–2000 depending on training speed)
Store:
  - model weights (optimizer-free "best model" checkpoint)
  - optimizer state (needed to resume training — 3× the model size)
  - scheduler state
  - RNG state (for reproducible data ordering)
  - step number

Keep last 3–5 checkpoints; delete older ones.
Store to S3/GCS with versioning enabled.
```

**Training monitoring** (watch these metrics):
- `train/loss`: should decrease smoothly; spikes indicate learning rate too high or bad batch
- `grad_norm`: typically 0.5–3.0; explosion (> 10) = instability, clip at 1.0
- `lr`: cosine decay should be visible
- `tokens_per_second`: detect hardware failures (one GPU dying drops throughput by 1/N)
- `mfu` (model FLOP utilization): should be 40–60% on A100; below 30% = bottleneck

---

## The nanoGPT Reference: Building Intuition

Andrej Karpathy's nanoGPT (github.com/karpathy/nanoGPT) is ~300 lines of PyTorch that implements a full GPT-2-style pre-training loop. Reading it once is worth more than most papers because it makes the training loop concrete:

```python
# Core loop from nanoGPT — stripped to essentials
for iter_num in range(max_iters):
    X, Y = get_batch('train')           # token IDs
    logits, loss = model(X, Y)          # forward pass
    loss.backward()                      # backward pass
    clip_grad_norm_(model.parameters(), 1.0)  # gradient clipping
    optimizer.step()                     # Adam update
    optimizer.zero_grad(set_to_none=True)
```

That's it. The complexity is in the data pipeline, distributed setup, and hyperparameter search — not the core loop.

---

## Scaling Laws in Practice

**Chinchilla optimal** for a training budget C (FLOPs):
- Model size N ≈ C^0.5 / 2.1
- Token count D ≈ 20 × N

**LLaMA 3 strategy**: Deliberately over-train small models beyond compute-optimal. A 8B model trained on 15T tokens (far beyond Chinchilla optimal) is better than a 13B model trained on 6T tokens *for inference* — you get the same quality at half the serving cost.

**Implication**: If you're building a domain model to deploy at scale, train a 3B–7B model for 3–5× Chinchilla-optimal tokens on your domain corpus. You get a model that's fast and cheap to serve with strong domain quality.

---

## FAANG Interview Callout

> **"How would you train a domain-specific LLM from scratch for Amazon's product catalog?"**
>
> "I'd start by challenging whether we need to train from scratch — if the goal is structured extraction or product Q&A, continued pre-training on LLaMA-3-8B with product catalog data followed by SFT would almost certainly be faster, cheaper, and lower risk. If we genuinely need a custom tokenizer (product IDs, SKUs, ASIN formats are important tokens) or the domain is orthogonal to general web text, then pre-training makes sense. The data pipeline would be the largest investment: product titles, descriptions, reviews, catalog metadata, and structured attributes need dedup, quality filtering, and domain mixing. For compute, 8B params × 200B domain tokens ≈ 3.2×10^21 FLOPs, roughly 400 A100-hours at 40% MFU. The failure mode I worry most about is data contamination between train and eval — especially if the eval set uses current catalog data that existed at train time."

---

## Related Files

- [01-transformer-architecture.md](01-transformer-architecture.md) — Architecture choices referenced here
- [02-fine-tuning-base-models.md](02-fine-tuning-base-models.md) — Fine-tuning as the cheaper alternative
- [04-inference-patterns.md](04-inference-patterns.md) — Serving the model after pre-training
