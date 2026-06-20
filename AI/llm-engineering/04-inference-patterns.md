# Inference Patterns

Inference is where training costs are recovered — or squandered. A 7B model served inefficiently can cost more per request than a 70B model served well. This file covers the bottlenecks, the tools, and the trade-offs.

---

## The Inference Bottleneck: Memory, Not Compute

During training, compute dominates — each parameter is updated via gradients. During inference, the model weights are static and the bottleneck is **memory bandwidth**:

```
GPU memory bandwidth = how fast weights can be moved from VRAM to compute units

A100 80GB:   ~2 TB/s memory bandwidth, 312 TFLOPS bf16
LLaMA-3-7B FP16: ~14 GB weights → ~7ms/token at batch_size=1 (memory-bound)
LLaMA-3-7B at batch=32: same 14 GB read, 32× the output → amortized to ~0.2ms/token
```

**Key insight**: At batch size 1, you pay to read 14GB of weights for a single output token. At batch size 32, you still read 14GB but produce 32 tokens — 32× better throughput. **Batching is the primary lever for inference efficiency.**

---

## KV Cache: The Memory Complexity Problem

During autoregressive decoding, each new token attends to all previous tokens. Without caching:
- Token 1: compute attention over [t1] 
- Token 2: recompute [t1] + compute [t2] — wasteful
- Token N: recompute all N-1 previous tokens

**KV cache**: Store the K and V matrices for all previous tokens. On each new token, only compute K, V for the new token and append.

```
KV cache memory per request:
  = 2 × num_layers × num_kv_heads × head_dim × seq_len × bytes_per_element

LLaMA-3-8B (32 layers, 8 KV heads, 128 head_dim, fp16):
  = 2 × 32 × 8 × 128 × seq_len × 2 bytes
  = 131,072 × seq_len bytes
  = ~131 MB at 1K tokens, ~524 MB at 4K tokens, ~2 GB at 16K tokens

With 80GB A100 and 14GB model weights: ~66 GB left for KV cache
  → ~32 concurrent requests at 2K context
  → ~8 concurrent requests at 8K context
```

This is why KV cache management is the central problem in LLM serving systems.

---

## Batching Strategies

| Strategy | How It Works | Throughput | Latency |
|----------|-------------|-----------|---------|
| **Static batching** | Fill batch, wait for all to finish | Low | Worst — shortest waits for longest |
| **Dynamic batching** | Batch requests in a time window | Medium | Better — bounded wait window |
| **Continuous batching** (iteration-level) | New requests join as others finish | Highest | Best — no idle compute |

### Continuous Batching (PagedAttention)

vLLM's core insight: requests don't need to finish together. At each generation step, any request that generated an EOS token leaves the batch and a new request immediately joins.

```
Step 1: [Req A (5 tokens left), Req B (12 left), Req C (3 left)]
Step 4: [Req A (1 left), Req B (8 left), Req C (EOS - done!)]
Step 5: [Req A (EOS - done!), Req B (7 left), Req D (new, 15 left)]
```

This keeps GPU compute near 100% utilization regardless of output length variance — which is extreme for real workloads (some requests generate 10 tokens, some 2000).

---

## vLLM Deep-Dive

vLLM is the de facto standard for high-throughput LLM serving. Its two innovations:

### 1. PagedAttention

Manages KV cache like an OS manages virtual memory — in fixed-size "pages" (blocks of KV vectors, typically 16 tokens per block):

```
Physical KV cache memory divided into N pages of 16 tokens each

Request A: [page 3] → [page 7] → [page 12]    (non-contiguous in memory)
Request B: [page 1] → [page 9]                 (can use same physical pages)

No pre-allocation: pages assigned on demand, freed immediately at EOS
```

This eliminates three types of memory waste from naive KV cache management:
- **Reservation waste**: pre-allocating max_seq_len for every request
- **Internal fragmentation**: wasted space within allocated blocks
- **External fragmentation**: memory holes between allocations

Result: 2–4× more concurrent requests in the same GPU memory.

### 2. Continuous Batching

Already described above — PagedAttention makes it practical by enabling non-contiguous KV cache across requests.

**vLLM usage**:
```python
from vllm import LLM, SamplingParams

llm = LLM(
    model="mistralai/Mistral-7B-Instruct-v0.2",
    tensor_parallel_size=1,    # GPUs to use
    gpu_memory_utilization=0.9,
    max_model_len=4096,
)

sampling_params = SamplingParams(
    temperature=0.0,           # deterministic for extraction
    max_tokens=512,
    stop=["</s>", "[INST]"],   # stop sequences
)

outputs = llm.generate(prompts, sampling_params)
for output in outputs:
    print(output.outputs[0].text)
```

**With LoRA adapter** (our HTML parser fine-tune):
```python
from vllm import LLM
from vllm.lora.request import LoRARequest

llm = LLM(model="mistralai/Mistral-7B-Instruct-v0.2", enable_lora=True)

output = llm.generate(
    "Extract JSON from HTML...",
    lora_request=LoRARequest("html-extractor", 1, "./html-extractor-adapter")
)
```

vLLM supports serving multiple LoRA adapters simultaneously on one base model — critical for multi-tenant deployments.

---

## Inference Servers: Tool Comparison

| Tool | Best For | Throughput | Ease of Setup | Quantization | Notes |
|------|----------|-----------|--------------|-------------|-------|
| **vLLM** | Production, high throughput | ★★★★★ | Medium | AWQ, GPTQ, fp8 | OpenAI-compatible API |
| **TGI** (Hugging Face) | Hugging Face ecosystem | ★★★★ | Easy | GPTQ, bits-and-bytes | Flash Attention, token streaming |
| **TensorRT-LLM** | NVIDIA GPU max performance | ★★★★★ | Hard | INT8, INT4, FP8 | Fastest on NVIDIA; complex build |
| **llama.cpp** | CPU inference, edge, dev | ★★ (CPU) | Very easy | GGUF (all variants) | Runs on MacBook; great for prototyping |
| **Ollama** | Local dev, CLI, single user | ★★ | Trivial | GGUF | Wraps llama.cpp; best DX for local |
| **DeepSpeed-Inference** | Tensor parallel on A100s | ★★★★ | Hard | INT8 ZeroQuant | Strong for 13B+ on multi-GPU |

**Decision tree**:
```
Single developer / laptop ──► Ollama
Prototyping on single GPU ──► vLLM (simplest production-grade option)
High throughput production ──► vLLM (default) or TRT-LLM (max NVIDIA perf)
Edge / on-device deployment ──► llama.cpp + GGUF
Hugging Face-native team ──► TGI
```

---

## Quantization

Quantization reduces weight precision to save VRAM and increase throughput, at the cost of quality.

### Quantization Methods Compared

| Method | Precision | VRAM (7B) | Throughput vs FP16 | Quality Loss |
|--------|-----------|-----------|-------------------|-------------|
| FP16 | 16-bit float | ~14 GB | 1× (baseline) | None |
| INT8 | 8-bit int | ~7 GB | 1.5–2× | < 1% on most benchmarks |
| GPTQ | 4-bit int, calibrated | ~4 GB | 2–3× | 1–3% |
| AWQ | 4-bit int, activation-aware | ~4 GB | 2–3× | 0.5–2% (better than GPTQ) |
| GGUF Q4_K_M | 4-bit, mixed precision | ~4.5 GB | CPU-optimized | 1–2% |
| GGUF Q8_0 | 8-bit | ~7.5 GB | CPU-optimized | < 1% |

**AWQ vs GPTQ**: AWQ scales important weights before quantization (activation-aware). This preserves quality better than GPTQ's pure post-training quantization, especially for 4-bit. Use AWQ when quality matters; GPTQ has wider tooling support.

**When to use INT4**: When you need to fit a 7B model on a 6GB GPU (RTX 3060) or run a 13B model on a single A100 for max concurrency. Not for tasks where small errors compound (long-form reasoning, math).

```python
# Load AWQ-quantized model with vLLM
llm = LLM(
    model="TheBloke/Mistral-7B-Instruct-v0.2-AWQ",
    quantization="awq",
    dtype="float16",
)
```

---

## Speculative Decoding

**Problem**: Autoregressive decoding is sequential — you can't generate token N+1 until you have token N.

**Speculative decoding** breaks this with a draft-then-verify pattern:

```
1. Draft model (small, fast — e.g., 68M params) generates k candidate tokens quickly
2. Target model (large — e.g., 7B) verifies all k candidates in parallel (single forward pass)
3. Accept all correct candidates, reject from first mismatch
4. Net result: up to k tokens generated per target model forward pass

Speedup: 2–3× for greedy decoding on text that the draft model predicts well
         (code, structured output, continuation tasks — not open-ended chat)
```

```python
# vLLM speculative decoding
llm = LLM(
    model="mistralai/Mistral-7B-v0.1",
    speculative_model="TinyLlama/TinyLlama-1.1B-Chat-v1.0",
    num_speculative_tokens=5,    # draft 5 tokens per verification step
)
```

**When it helps**: tasks where output is predictable (code generation, HTML extraction, templated responses). Doesn't help for open-ended generation where draft model frequently mispredicts.

---

## Streaming Inference

For interactive applications, send tokens as they're generated rather than waiting for completion:

```python
# vLLM async streaming
from vllm.engine.arg_utils import AsyncEngineArgs
from vllm.engine.async_llm_engine import AsyncLLMEngine

engine = AsyncLLMEngine.from_engine_args(AsyncEngineArgs(model="..."))

async def generate_stream(prompt: str):
    request_id = str(uuid.uuid4())
    async for output in engine.generate(prompt, sampling_params, request_id):
        if output.outputs:
            yield output.outputs[0].text  # stream partial text
```

**SSE (Server-Sent Events)** is the standard transport for streaming LLM responses to browsers — simpler than WebSockets for unidirectional server→client streams.

---

## Throughput Benchmarks (Reference Numbers)

| Model | Hardware | Method | Throughput | Notes |
|-------|----------|--------|-----------|-------|
| LLaMA-3-8B | 1× A100 80GB | vLLM FP16 | ~3,500 tokens/s | Continuous batching |
| Mistral-7B | 1× A100 80GB | vLLM AWQ INT4 | ~5,500 tokens/s | 1.6× vs FP16 |
| LLaMA-3-70B | 4× A100 80GB | vLLM TP=4 | ~1,800 tokens/s | Tensor parallel |
| LLaMA-3-8B | MacBook M3 Max | Ollama Q4 | ~50 tokens/s | CPU+MPS, local dev |

Numbers vary significantly with batch size, prompt/output length ratio, and hardware generation.

---

## FAANG Interview Callout

> **"How would you serve an LLM at 10,000 requests per minute?"**
>
> "10K RPM is ~167 RPS. At an average output of 200 tokens per request, that's 33K tokens/second — roughly 10 A100s running vLLM at peak throughput. The core design is: an API gateway with request queuing → a fleet of vLLM instances with continuous batching → a KV cache proxy layer for common prompt prefixes (prompt caching). The failure mode to plan for is KV cache eviction under burst load — when memory pressure is high, vLLM will evict in-flight KV states and the latency spike is visible to users. I'd set a queue depth limit and return HTTP 429 before eviction rather than degrading silently. For the HTML extraction use case specifically, output length is predictable (~100 tokens), which means the continuous batching gains are highest — you can pack many requests per batch. I'd also evaluate speculative decoding here because JSON output from a structured extraction model is predictable enough that a small draft model should hit > 80% acceptance rate."

---

## Related Files

- [01-transformer-architecture.md](01-transformer-architecture.md) — KV cache mechanics tie directly to the attention computation
- [02-fine-tuning-base-models.md](02-fine-tuning-base-models.md) — Serving LoRA adapters with vLLM
- [05-deployment-and-production.md](05-deployment-and-production.md) — Infrastructure around the inference server
