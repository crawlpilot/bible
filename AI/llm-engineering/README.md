# LLM Engineering — Training, Inference & Deployment

**Type**: ML Systems / Applied Deep Learning  
**Scope**: Model training (fine-tune + pre-train) → inference optimization → production serving  
**Complexity Model**: Training cost = O(params × tokens); Inference cost = O(params × seq_len) per request

---

## What Is LLM Engineering?

LLM Engineering is the discipline of taking a transformer-based language model from research artifact to production system: choosing the right base model, adapting it to a task, optimizing it for inference, and running it reliably at scale.

It sits at the intersection of ML research, systems engineering, and infrastructure. At FAANG scale, a single LLM inference cluster can serve billions of tokens per day — every percentage point of throughput improvement translates directly to cost and latency.

```
Base Model ──► Fine-Tune / Pre-Train ──► Quantize ──► Serve ──► Monitor
  (weights)       (task adaptation)     (compress)   (vLLM etc)  (cost + quality)
```

---

## Decision Matrix: How to Adapt a Model

| Approach | When to Use | Cost | Risk | Latency |
|----------|-------------|------|------|---------|
| **Prompt engineering only** | General tasks, fast iteration, no labeled data | $ | Low | API latency |
| **RAG** | Knowledge-heavy tasks, data changes frequently | $$ | Medium | +50–200ms retrieval |
| **Fine-tuning (LoRA/QLoRA)** | Task-specific behavior, consistent output format, labeled data available | $$$ | Medium | Same as base |
| **Full fine-tuning** | Domain shift, base model too generic, large dataset | $$$$ | High (forgetting) | Same as base |
| **Pre-training from scratch** | Proprietary data, novel domain, custom tokenizer | $$$$$ | Very high | Depends on size |

**Rule of thumb**: Try prompt engineering first. If accuracy plateaus, try RAG. If format/behavior needs to change, fine-tune. Only pre-train if you have >100B domain tokens and a specific reason the base model is wrong.

---

## Quick-Reference Card

| Item | Typical Value | Notes |
|------|--------------|-------|
| LoRA rank | 8–64 | Higher = more capacity, more VRAM |
| QLoRA base precision | 4-bit NF4 | Use bfloat16 for adapter weights |
| SFT learning rate | 1e-4 to 3e-4 | Cosine decay, warm-up 3% of steps |
| Batch size (effective) | 128–512 | Use gradient accumulation to hit this |
| vLLM throughput (A100) | 1,500–4,000 tokens/s | Continuous batching, bf16, LLaMA-7B |
| INT4 quantization speedup | 2–3× vs FP16 | ~1–3% quality degradation |
| KV cache memory (7B, 4K ctx) | ~0.5 GB per concurrent request | PagedAttention manages this dynamically |
| TTFT target | < 500ms | Time to first token for interactive use |

---

## Anti-Patterns

1. **Fine-tuning before establishing a baseline**: always measure prompt-only first — often good enough.
2. **Training on unfiltered data**: one bad example can override thousands of good ones; quality >> quantity.
3. **Serving FP16 when INT4/INT8 suffices**: 2–4× more VRAM for marginal quality gain on many tasks.
4. **Using vLLM for single-request batch size 1**: overkill; llama.cpp or Ollama is faster to set up for dev.
5. **Ignoring KV cache memory in capacity planning**: it grows linearly with context length and concurrent users.
6. **Evaluating only on loss**: loss goes down while downstream task accuracy stagnates — always eval task metrics.

---

## File Map

| File | What you'll learn |
|------|-------------------|
| [01-transformer-architecture.md](01-transformer-architecture.md) | Attention, positional encoding, tokenization, scaling laws, modern variants |
| [02-fine-tuning-base-models.md](02-fine-tuning-base-models.md) | LoRA/QLoRA, SFT pipeline, HTML-parser running example, evaluation |
| [03-pretraining-and-llm-from-scratch.md](03-pretraining-and-llm-from-scratch.md) | Tokenizer training, architecture choices, distributed training, data pipeline |
| [04-inference-patterns.md](04-inference-patterns.md) | vLLM, PagedAttention, quantization (GPTQ/AWQ/GGUF), batching, speculative decoding |
| [05-deployment-and-production.md](05-deployment-and-production.md) | Serving architecture, hardware sizing, autoscaling, monitoring, cost optimization |

---

## FAANG Interview Callout

> **30-second pitch on when to train vs. when to prompt**:
>
> "I start from the cheapest intervention that achieves the quality bar. Prompt engineering costs nothing to iterate. RAG solves freshness and hallucination on knowledge tasks without touching weights. Fine-tuning is the right call when the task requires a specific output format or behavior that prompting can't reliably produce — structured extraction, domain-specific code generation, or format compliance at scale. Pre-training from scratch is almost never the answer unless you have a proprietary corpus that the base model was explicitly not trained on. The reason to be conservative is forgetting: every fine-tuning run risks degrading capabilities you're not measuring."

---

## Related Files in This Repo

- [AI/prompt-engineering/04-production-prompt-engineering.md](../prompt-engineering/04-production-prompt-engineering.md) — Production prompting vs. fine-tuning decision
- [AI/ml-systems/ollama-local-models-finetuning.md](../ml-systems/ollama-local-models-finetuning.md) — Local dev workflow with Ollama + QLoRA
- [AI/agent-workflows/README.md](../agent-workflows/README.md) — Deploying fine-tuned models inside agent loops
- [technologies/vector-db/README.md](../../technologies/vector-db/README.md) — RAG as an alternative to fine-tuning for knowledge tasks
