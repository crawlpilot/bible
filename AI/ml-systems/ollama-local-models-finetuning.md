# Ollama & Local LLM Deployment — Finetuning Trade-offs

> **Scope**: Principal engineer treatment of running LLMs locally with Ollama, covering architecture internals, quantization strategies, finetuning approaches (LoRA / QLoRA / full), and the system-design decisions that govern when each approach is correct.

---

## 1. Why This Matters at FAANG Scale

Local model deployment is no longer just a developer convenience — it appears in principal engineer interviews as a **system design forcing function** when:

- **Data residency / compliance**: HIPAA, GDPR, FedRAMP — customer data cannot leave your datacenter
- **Latency SLAs below 50ms**: Round-trip to OpenAI averages 200–800ms; local inference on A100 is 15–40ms
- **Cost at scale**: GPT-4o at $5/M tokens → 1B tokens/month = $5,000/month; a 4× A100 node amortizes in ~6 months at that volume
- **Model customization**: Task-specific behavior (code style, domain vocabulary, output format) that prompt engineering cannot reliably achieve

The decision tree — **prompt engineer vs RAG vs finetune vs pretrain** — is a first-class interview question at Google DeepMind, Meta AI, and AWS AI roles.

---

## 2. Ollama Architecture

Ollama is a local LLM runtime that wraps **llama.cpp** with a model registry, REST API server, and hardware abstraction layer.

```
┌─────────────────────────────────────────────────────┐
│                    Ollama Daemon                     │
│                                                     │
│  ┌──────────────┐   ┌────────────────────────────┐  │
│  │  REST API    │   │       Model Runner          │  │
│  │  (OpenAI-    │──▶│  (llama.cpp via CGo/FFI)   │  │
│  │  compatible) │   │                            │  │
│  └──────────────┘   │  ┌──────────┐ ┌─────────┐  │  │
│                     │  │  Metal   │ │  CUDA   │  │  │
│  ┌──────────────┐   │  │ (Apple   │ │(NVIDIA) │  │  │
│  │  Model       │   │  │ Silicon) │ │         │  │  │
│  │  Registry /  │   │  └──────────┘ └─────────┘  │  │
│  │  Modelfile   │   │  ┌──────────┐              │  │
│  │  (OCI-like)  │   │  │  CPU     │              │  │
│  └──────────────┘   │  │ (AVX512) │              │  │
│                     │  └──────────┘              │  │
│                     └────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Key Components

| Component | Role | Detail |
|-----------|------|--------|
| **llama.cpp** | Core inference engine | C++ impl of transformer forward pass; GGUF model format |
| **GGUF format** | Model serialization | Successor to GGML; stores weights + metadata + tokenizer in one file |
| **Metal / CUDA / ROCm** | GPU acceleration | Offloads matrix multiplications to GPU; CPU fallback always available |
| **Modelfile** | Model configuration | Dockerfile-style DSL: base model, system prompt, parameters, adapter layers |
| **OpenAI-compatible API** | Integration layer | `/api/generate`, `/api/chat`, `/api/embeddings` — drop-in for OpenAI SDK |

### Startup and Memory Layout

When Ollama loads a model, it:
1. Memory-maps the GGUF file (avoids reading entire file into RAM)
2. Allocates **KV cache** in VRAM (key-value cache for attention layers; size = `2 × n_layers × n_heads × head_dim × context_len × dtype_bytes`)
3. Keeps model weights in VRAM if sufficient; spills to RAM/disk with `--gpu-layers` control

**KV cache is the dominant memory cost at runtime**, not the model weights. A 7B model with 4-bit weights is ~4GB, but a 32K context window adds another 4–8GB of KV cache.

---

## 3. Quantization — The Core Trade-off Table

Quantization reduces float32 weights to lower-bit representations. This is the primary lever for fitting large models on consumer hardware.

### Quantization Levels (GGUF naming)

| Format | Bits/weight | 7B VRAM | 13B VRAM | 70B VRAM | Perplexity delta | Use case |
|--------|-------------|---------|----------|----------|-----------------|----------|
| `F32`  | 32 | 28 GB | 52 GB | 280 GB | Baseline | Research only |
| `F16`  | 16 | 14 GB | 26 GB | 140 GB | ~0% | Fine-tune base |
| `Q8_0` | 8  | 7.7 GB | 14 GB | 77 GB | < 0.1% | Production quality bar |
| `Q6_K` | 6  | 6.1 GB | 11 GB | 61 GB | ~0.2% | Best quality/size ratio |
| `Q5_K_M`| 5 | 5.2 GB | 9.5 GB | 52 GB | ~0.4% | Recommended default |
| `Q4_K_M`| 4 | 4.1 GB | 7.7 GB | 41 GB | ~0.7% | Consumer GPU sweet spot |
| `Q3_K_M`| 3 | 3.3 GB | 6.1 GB | 33 GB | ~2.5% | Severe capacity constraint |
| `Q2_K` | 2  | 2.7 GB | 4.7 GB | 27 GB | ~7%+ | Avoid for production |

**`K` suffix** = K-quants (mixed precision: sensitive layers kept at higher bits). Always prefer K-quants over legacy Q4_0.

### Quantization Decision Framework

```
Is model accuracy critical (legal, medical, finance)?
  YES → Q8_0 or Q6_K minimum
  NO  → continue

What VRAM do you have?
  > 24 GB → Q6_K for 7B/13B; consider Q5_K_M for 70B
  8–24 GB → Q4_K_M (sweet spot for most workloads)
  < 8 GB  → Q4_K_M for 7B; larger models need CPU offloading (3–5× slower)

CPU-only deployment?
  YES → Q4_K_M or Q5_K_M; threads = physical cores (not HT)
```

### Perplexity vs. Task Performance Note

Perplexity delta (measured on WikiText-103) understates task degradation on **structured output** problems. A model at Q4_K_M with ~0.7% perplexity delta may fail JSON schema compliance 15–25% more often than Q8_0 on the same prompts. Always benchmark on your actual task, not perplexity alone.

---

## 4. The Adaptation Ladder — When to Use Each Approach

This is the most common interview question in this space. Ordered by cost and data requirement:

```
Prompt Engineering → RAG → Few-shot → Finetuning (LoRA/QLoRA) → Full Finetune → Pretraining
     (cheapest)                                                                   (most expensive)
```

### Decision Matrix

| Situation | Recommended Approach | Reasoning |
|-----------|---------------------|-----------|
| Need the model to know your company's FAQ | RAG | External knowledge, changes frequently |
| Need consistent output format (JSON schema) | Prompt engineering + output parser | System prompt + grammar-constrained decoding |
| Need domain tone/style (legal, medical) | LoRA finetune | Style is captured in weights, not documents |
| Need the model to learn new vocabulary/concepts | QLoRA finetune | Embedding space needs updating |
| Need task-specific reasoning (custom code style) | LoRA/QLoRA | 100–1000 examples sufficient |
| Need to distill a large model into a smaller one | Full finetune or QLoRA + distillation loss | KL divergence from teacher model |
| Need to change safety behavior or refusals | Full RLHF/DPO pipeline | Alignment changes require preference data |
| Base model doesn't exist for your domain | Continued pretraining | Domain-adaptive pretraining (DAP) |

---

## 5. Finetuning Approaches — Deep Dive

### 5.1 Full Fine-tuning

Updates **all model parameters** using gradient descent on your task data.

```
Memory footprint during training:
  Model weights (FP16):  14 GB for 7B
  Optimizer states (Adam = 2× weights in FP32): 56 GB
  Gradients (FP16):      14 GB
  Activations:           8–16 GB
  ─────────────────────────────
  Total:                 ~92 GB for a 7B model
```

**Requires**: 4× A100 (80GB) minimum for 7B models with ZeRO-3 sharding.

**When to use**: You have 10K+ high-quality examples, the task is far from base model behavior, and you have the infra budget.

**Risk**: **Catastrophic forgetting** — the model loses general capabilities as it overfits the target distribution. Mitigate with:
- Replay buffers (mix in general pretraining data)
- EWC (Elastic Weight Consolidation) — penalizes changes to weights important for prior tasks
- Lower learning rate (1e-5 to 5e-5)

---

### 5.2 LoRA (Low-Rank Adaptation)

Decomposes weight updates into two low-rank matrices. Instead of updating W (d×d), trains A (d×r) and B (r×d) where r << d.

```
Original:  W_new = W_orig + ΔW           (full matrix update)
LoRA:      W_new = W_orig + (A × B) × α  (rank-r update, α = scaling factor)
```

```python
# LoRA configuration with PEFT library
from peft import LoraConfig, get_peft_model

config = LoraConfig(
    r=16,                    # rank — higher = more capacity, more params
    lora_alpha=32,           # scaling factor; effective lr = alpha/r
    target_modules=[         # which weight matrices to adapt
        "q_proj", "v_proj",  # attention: query and value projections
        # add "k_proj", "o_proj", "gate_proj" for more capacity
    ],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM"
)

model = get_peft_model(base_model, config)
model.print_trainable_parameters()
# trainable params: 4,194,304 || all params: 6,738,415,616 || trainable%: 0.062%
```

**Memory savings**: Only A and B matrices are stored in optimizer states. Training memory drops from ~92GB to ~18–20GB for a 7B model.

**LoRA rank selection**:
| r | Trainable params (7B) | Use case |
|---|----------------------|----------|
| 4 | ~2M | Style transfer, format compliance |
| 8 | ~4M | Domain adaptation, moderate task shift |
| 16 | ~8M | Significant behavioral change |
| 32 | ~16M | Approaching full finetune quality |
| 64+ | ~32M+ | Diminishing returns; consider full finetune |

---

### 5.3 QLoRA (Quantized LoRA)

Combines **4-bit quantization of the frozen base model** with full-precision LoRA adapters. This is the breakthrough that enabled finetuning 65B models on a single A100.

```
┌────────────────────────────────────────────────────┐
│  Base model weights (NF4 / 4-bit)  — FROZEN        │
│  ┌──────────────────────────────────────────────┐  │
│  │  LoRA adapters (BF16) — TRAINABLE            │  │
│  │  A: [d × r]   B: [r × d]                    │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  Double Quantization: quantize the quantization    │
│  constants themselves (saves ~0.37 bits/param)     │
│                                                    │
│  Paged Optimizers: spill optimizer states to       │
│  CPU RAM when VRAM is exhausted                    │
└────────────────────────────────────────────────────┘
```

```python
from transformers import BitsAndBytesConfig
import torch

bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",       # NormalFloat4 > Int4 for LLM weights
    bnb_4bit_compute_dtype=torch.bfloat16,  # upcast to BF16 for compute
    bnb_4bit_use_double_quant=True,  # double quantization
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Meta-Llama-3-8B",
    quantization_config=bnb_config,
    device_map="auto"
)
```

**Hardware requirement comparison**:
| Model | Full FT | LoRA FT | QLoRA FT |
|-------|---------|---------|---------|
| 7B    | 4× A100 | 1× A100 | 1× RTX 3090 (24GB) |
| 13B   | 8× A100 | 2× A100 | 1× A100 (40GB) |
| 70B   | 16× A100 | 4× A100 | 2× A100 (80GB) |

**QLoRA quality gap**: ~1–3% degradation vs full LoRA on most benchmarks. For instruction following and style tasks, often undetectable.

---

### 5.4 DPO (Direct Preference Optimization)

Replaces the RLHF reward model + PPO pipeline with a simpler offline loss over preference pairs. Critical for aligning model behavior post-finetuning.

```
Input: pairs of (prompt, chosen_response, rejected_response)
Loss: maximize P(chosen) / P(rejected) relative to reference model

Combines well with QLoRA — finetune on SFT data first, then DPO pass
```

---

## 6. Data Requirements for Finetuning

| Task type | Minimum examples | Target examples | Format |
|-----------|-----------------|-----------------|--------|
| Style / tone shift | 50–200 | 500–1K | (prompt, completion) pairs |
| Domain adaptation | 500–1K | 5K–10K | Domain-specific text corpus |
| Instruction following | 1K–2K | 10K–50K | (instruction, response) pairs |
| Function calling / tool use | 500–2K | 5K–20K | JSON schema + examples |
| RLHF / DPO alignment | 5K–10K | 50K–100K | (prompt, chosen, rejected) |

**Data quality > data quantity**. A 500-example curated dataset consistently outperforms a 10K noisy dataset. Deduplication, quality filtering, and format consistency are the dominant factors.

---

## 7. Ollama Modelfile — Custom Model Deployment

After finetuning, merge LoRA adapters and convert to GGUF for Ollama deployment:

```bash
# Step 1: Merge LoRA into base model weights
python merge_adapters.py \
  --base_model meta-llama/Meta-Llama-3-8B \
  --adapter_path ./output/checkpoint-final \
  --output_dir ./merged_model

# Step 2: Convert to GGUF
python llama.cpp/convert_hf_to_gguf.py ./merged_model \
  --outtype q4_k_m \
  --outfile ./models/llama3-finetuned-q4km.gguf

# Step 3: Create Modelfile
cat > Modelfile <<'EOF'
FROM ./models/llama3-finetuned-q4km.gguf

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER num_ctx 4096
PARAMETER repeat_penalty 1.1

SYSTEM """
You are a specialized assistant for [domain]. Always respond in [format].
[domain-specific instructions]
"""
EOF

# Step 4: Build and run
ollama create my-finetuned-model -f Modelfile
ollama run my-finetuned-model
```

---

## 8. Constrained Decoding — The Underrated Alternative to Finetuning

Before reaching for finetuning for **structured output problems**, evaluate grammar-constrained decoding:

```python
# llama.cpp grammar (GBNF) for JSON schema enforcement
grammar = r"""
root   ::= object
value  ::= object | array | string | number | boolean | null
object ::= "{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws
array  ::= "[" ws (value ("," ws value)*)? "]" ws
string ::= "\"" ([^\\"\n] | "\\" ([\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]))* "\""
"""
```

Ollama supports grammar via the `format` parameter: `{"format": "json"}` enforces valid JSON output at the token sampling level — no finetuning required for format compliance.

**When grammar-constrained decoding beats finetuning for structured output**: ~80% of cases where the problem is format compliance, not knowledge/reasoning.

---

## 9. Local vs Cloud — System Design Decision

### Cost Analysis (at scale)

| Workload | Cloud (GPT-4o) | Cloud (GPT-4o-mini) | Local 4× A100 | Local 4× RTX 4090 |
|---------|---------------|--------------------|--------------|--------------------|
| 1M tokens/day | $5,000/month | $600/month | $800/month amortized | $300/month amortized |
| 10M tokens/day | $50,000/month | $6,000/month | $800/month amortized | $300/month amortized |
| 100M tokens/day | $500,000/month | $60,000/month | $1,600/month (scale-out) | $600/month |

Local becomes cost-positive at **~2M tokens/day** for mid-tier models.

### Latency Comparison

| Setup | TTFT (time to first token) | Throughput |
|-------|--------------------------|------------|
| OpenAI GPT-4o | 200–800ms (network + cold start) | 60–80 tok/s |
| Ollama + A100 local | 30–80ms | 80–120 tok/s |
| Ollama + RTX 4090 | 50–150ms | 50–80 tok/s |
| Ollama + M2 Ultra (CPU) | 200–400ms | 20–35 tok/s |
| Ollama + CPU (16-core) | 1–3s | 8–15 tok/s |

### Decision Framework

```
Does data leave the building? (compliance/IP)
  YES → Must be local. No choice.

Is p99 latency < 100ms required?
  YES → Local GPU required; cloud inconsistency unacceptable.

Volume > 10M tokens/day?
  YES → Local is likely cheaper; do TCO analysis.

Is the model a commodity (GPT-4 level reasoning needed)?
  YES → Cloud; local 7B/13B models won't match GPT-4 on complex reasoning.
  NO  → Local finetuned model can match GPT-4 on narrow tasks.

Team has ML infra expertise?
  NO → Cloud; local model ops is non-trivial (GPU drivers, CUDA OOM, batching).
```

---

## 10. Production Architecture for Local LLM Serving

Ollama alone is not production-grade for multi-tenant, high-availability deployments. A production pattern:

```
                    ┌─────────────────────────────┐
                    │      Load Balancer           │
                    └──────────────┬──────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
    ┌─────────▼──────┐   ┌─────────▼──────┐   ┌─────────▼──────┐
    │  Ollama Node 1  │   │  Ollama Node 2  │   │  Ollama Node 3  │
    │  (A100 × 2)     │   │  (A100 × 2)     │   │  (A100 × 2)     │
    └────────────────┘   └────────────────┘   └────────────────┘

Alternatives to Ollama for production:
  - vLLM: PagedAttention, continuous batching, 3–5× throughput vs Ollama
  - TensorRT-LLM (NVIDIA): Best throughput on A100/H100; harder to deploy
  - Text Generation Inference (HuggingFace TGI): Good tooling, OpenAI-compatible
  - llama-cpp-python: Direct Python binding for llama.cpp
```

**vLLM vs Ollama decision point**: For >10 concurrent users, vLLM's PagedAttention and continuous batching deliver 3–5× higher throughput. Ollama is optimized for simplicity and single-user scenarios.

---

## 11. Evaluation Pipeline

Finetuning without evaluation is not engineering. Required components:

```
┌──────────────────────────────────────────────────────┐
│                Evaluation Pipeline                    │
│                                                      │
│  1. Task-Specific Metrics                            │
│     - ROUGE/BLEU for summarization                   │
│     - Exact match / F1 for extraction                │
│     - Pass@k for code generation                     │
│     - Human eval on 10% sample                       │
│                                                      │
│  2. Regression Suite                                 │
│     - Held-out test set from before finetuning       │
│     - Ensures no catastrophic forgetting             │
│                                                      │
│  3. LLM-as-Judge                                     │
│     - GPT-4 or Claude grades (prompt, response) pairs│
│     - MT-Bench / AlpacaEval style scoring            │
│                                                      │
│  4. Adversarial / Edge Cases                         │
│     - Out-of-distribution inputs                     │
│     - Jailbreak / safety probes (if applicable)      │
└──────────────────────────────────────────────────────┘
```

---

## 12. Key Anti-Patterns

| Anti-pattern | Consequence | Fix |
|-------------|-------------|-----|
| Finetuning before trying prompt engineering | Wasted compute; often PE is sufficient | Exhaustively test PE first |
| Using Q2/Q3 quantization in production | Output quality collapse on structured tasks | Q4_K_M minimum; Q5_K_M preferred |
| Training on noisy, unfiltered data | Model learns noise as signal; worse than base | Invest 80% of effort in data quality |
| Ignoring KV cache sizing | OOM on long contexts; silent quality degradation | Pre-calculate: `2 × layers × heads × head_dim × ctx_len × 2 bytes` |
| One giant LoRA rank (r=256) | Overfitting; not better than smaller r with more data | r=16–32 with good data beats r=256 with bad data |
| Ollama in production without batching | 1 request at a time; throughput collapse under load | Use vLLM or TGI for multi-user serving |
| Deploying merged adapter without benchmark | Silent regression from quantization + merge | Always benchmark merged model before deployment |

---

## 13. FAANG Interview Framing

### Canonical question: "Design a system that allows engineers to use a private LLM for internal code review"

**Key decisions the interviewer wants to hear**:
1. **Local deployment** (data never leaves infra; IP protection) — immediately justify with compliance
2. **Model selection**: CodeLlama-34B-Instruct Q5_K_M or Deepseek-Coder-33B — justify on code benchmarks (HumanEval, MBPP)
3. **Finetuning**: LoRA on internal codebase (style, patterns, proprietary APIs) — justify with 500–1K curated PR review examples
4. **Serving**: vLLM with PagedAttention for 100+ concurrent engineers; autoscaling on GPU nodes
5. **Evaluation**: Pass@1 on internal test suite, LLM-judge for review quality, A/B vs human reviewers
6. **Failure modes**: Model OOM → fallback to smaller model; GPU node failure → reroute to cloud with prompt sanitization

### Signal that separates principal engineers
- Knows that **finetuning for code style is worth it** because it reduces prompt token overhead by 60% (compressed context vs. shot examples)
- Mentions **grammar-constrained decoding** for structured diff output instead of finetuning for format
- Proactively discusses **model drift** — finetuned on 6-month-old codebase, needs retraining pipeline
- Quantifies the trade-off: "At 1,000 engineers × 50 reviews/day × 2K tokens/review = 100M tokens/day → local is $50/day vs $1,500/day cloud"

---

## 14. Quick Reference Card

```
Ollama commands:
  ollama pull llama3.2:3b-instruct-q5_K_M   # pull quantized model
  ollama run llama3.2                         # interactive chat
  ollama serve                                # start API server (port 11434)
  ollama create my-model -f Modelfile         # build custom model
  ollama ps                                   # show loaded models + VRAM usage
  ollama show llama3.2 --modelinfo            # show quantization + parameters

vLLM for production:
  vllm serve meta-llama/Meta-Llama-3-8B \
    --quantization awq \
    --max-model-len 8192 \
    --tensor-parallel-size 2 \  # number of GPUs
    --port 8000

PEFT LoRA training (minimal):
  pip install transformers peft trl bitsandbytes
  # use SFTTrainer from trl for supervised finetuning
  # use DPOTrainer from trl for preference alignment

Model size rules of thumb:
  7B  → good for: classification, extraction, style, format
  13B → good for: reasoning, summarization, translation
  34B → good for: code generation, complex instruction following
  70B → approaches GPT-4 on many benchmarks; diminishing returns above
```

---

*See also*: [ml-observability-monitoring.md](ml-observability-monitoring.md) for model monitoring in production, [RAG system HLD](../ai-architecture/rag-system-hld.md) for when RAG beats finetuning.
