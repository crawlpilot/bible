# Deployment and Production

Running an LLM in production is a distributed systems problem with an ML model attached. The infra patterns are more deterministic than the model — and more likely to be your production bottleneck.

---

## Serving Architecture

```
                    ┌─────────────────┐
   Clients          │   API Gateway   │  Rate limiting, auth, routing
(web, mobile, API)  │   (Kong/Envoy)  │  Cost attribution, request logging
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │        Load Balancer         │  Route by model version, tenant
              │  (Nginx / AWS ALB / k8s SVC) │  Sticky sessions for KV cache reuse
              └──┬────────────┬─────────────┘
                 │            │
        ┌────────▼──┐  ┌──────▼────────┐
        │ vLLM Pod  │  │  vLLM Pod     │  Horizontal replicas
        │ (GPU: A100)│  │  (GPU: A100)  │  Each pod: 1 GPU = 1 model replica
        └─────┬─────┘  └──────┬────────┘
              │               │
        ┌─────▼───────────────▼─────┐
        │     Prompt Cache Layer    │  Redis / custom KV store
        │  (cache common prefixes)  │  Hit rate: 30–70% for templated prompts
        └───────────────────────────┘
              │
        ┌─────▼──────────┐
        │  Observability  │  Token throughput, TTFT, error rate, cost/request
        │  (Prometheus +  │
        │   Grafana)      │
        └─────────────────┘
```

---

## Hardware Sizing

Choosing the right GPU is a cost × latency × availability decision.

| GPU | VRAM | BF16 Throughput | Memory BW | Best For | $/hr (cloud) |
|-----|------|----------------|-----------|----------|-------------|
| **A100 80GB** | 80 GB | 312 TFLOPS | 2 TB/s | Production default, 7B–70B | $3–4 |
| **H100 80GB** | 80 GB | 989 TFLOPS | 3.35 TB/s | Max throughput, 70B+ | $8–10 |
| **A100 40GB** | 40 GB | 312 TFLOPS | 1.6 TB/s | 7B models, cost-sensitive | $2–3 |
| **RTX 4090** | 24 GB | 165 TFLOPS | 1 TB/s | Dev/test, 7B INT4 | $0.5–1 |
| **L40S** | 48 GB | 362 TFLOPS | 864 GB/s | Mid-tier production | $2–3 |
| **CPU (c5.18xl)** | — | ~5 tokens/s | — | Emergency fallback only | $3 |

**Cost per token** (rough guide, LLaMA-3-8B, A100 80GB at $3.50/hr):
- Throughput: 3,500 tokens/s at peak batching
- Cost: $3.50 / 3600s = $0.00097/s = $0.00028 per 1,000 tokens output
- Compare to OpenAI GPT-4o: $0.60 per 1M tokens output (≈2,000× cheaper to self-host at scale)

Self-hosting breaks even vs. API at roughly 50M–100M tokens/day depending on utilization rate.

---

## Multi-GPU Serving: Tensor Parallelism

For models larger than one GPU's VRAM, split the model across GPUs. Tensor Parallelism (TP) divides individual weight matrices:

```
7B model on 1× A100 80GB: fits in VRAM, no TP needed
13B model on 1× A100 80GB: fits (26 GB FP16)
70B model on 1× A100 80GB: does NOT fit (140 GB FP16)
70B model on 4× A100 80GB: 35 GB/GPU with TP=4 ✓

vLLM tensor parallel:
llm = LLM(model="meta-llama/Meta-Llama-3-70B", tensor_parallel_size=4)
```

**TP requirement**: GPUs must be connected via NVLink for low-latency all-reduce communication. PCIe-connected GPUs can do TP but the bandwidth bottleneck reduces throughput 2–3×.

**Rule**: Use the smallest model that hits your quality bar. A 8B model at TP=1 is cheaper and faster than a 70B model at TP=4 for the same total GPU count.

---

## Autoscaling

### The Cold Start Problem

Starting a new LLM pod takes 3–8 minutes:
- Pull Docker image: 30–60s
- Load model weights from S3/EFS: 60–180s (70B FP16 = 140 GB)
- Warm up compute graphs: 30–60s

**Mitigation strategies**:
1. **Pre-warming**: keep N idle replicas in standby (expensive but simplest)
2. **Fast model loading**: store model in instance-local NVMe SSD, not S3
3. **Checkpoint sharding**: use safetensors format and parallel loading across GPU lanes
4. **PVC-based warm cache**: pre-load model into a PersistentVolumeClaim on k8s node

### Scaling Signal

Don't scale on CPU/GPU utilization — LLM GPUs run at high utilization even when serving a light load due to continuous batching. Scale on:

```
Metrics to autoscale on:
  - Request queue depth > N for > 30 seconds → scale out
  - TTFT p95 > target (e.g., 500ms) for > 60 seconds → scale out
  - KV cache utilization > 85% → scale out (or reject new requests)
  - GPU replicas idle for > 10 minutes → scale in
```

Kubernetes HPA (Horizontal Pod Autoscaler) with custom metrics via Prometheus adapter works well for this.

---

## Prompt Caching: Free Latency Wins

For templated prompts where the system prompt + context is repeated across requests, prefix caching eliminates redundant KV computation:

```
Request 1: [System: "Extract product JSON..."] + [HTML: "<div>A</div>"]
Request 2: [System: "Extract product JSON..."] + [HTML: "<div>B</div>"]

Without caching: compute full KV for both
With prefix caching: compute KV for system prompt once, reuse for all requests
                     only compute KV for the unique HTML portion

Cache hit saves: (system_prompt_tokens / total_tokens) × latency
For 200-token system prompt + 800-token HTML: 20% TTFT reduction
For 1000-token system prompt + 200-token HTML: 83% TTFT reduction
```

vLLM's `enable_prefix_caching=True` handles this automatically. For high-traffic applications with consistent system prompts, this can halve your inference cost.

---

## Monitoring: The Right Metrics

| Metric | What It Measures | Alert Threshold |
|--------|-----------------|-----------------|
| **TTFT** (time to first token) | User-perceived responsiveness | p95 > 500ms for interactive |
| **TBT** (time between tokens) | Streaming smoothness | p95 > 100ms per token |
| **Total latency** | End-to-end request time | Depends on use case |
| **Token throughput** | Server efficiency | Drop > 20% from baseline |
| **KV cache utilization** | Memory pressure | > 85% → scaling trigger |
| **Request queue depth** | Backpressure | > 50 requests → scale out |
| **Parse error rate** | Model output quality | > 1% for JSON output tasks |
| **GPU memory utilization** | VRAM headroom | > 95% → risk of OOM |
| **Model error rate** | Hard failures | > 0.1% → investigate |

```python
# Prometheus metrics in your wrapper
from prometheus_client import Histogram, Counter, Gauge

ttft_histogram = Histogram('llm_ttft_seconds', 'Time to first token',
                           buckets=[0.1, 0.25, 0.5, 1.0, 2.5, 5.0])
token_throughput = Counter('llm_tokens_total', 'Total tokens generated',
                           ['model', 'tenant'])
kv_cache_util = Gauge('llm_kv_cache_utilization', 'KV cache utilization ratio')
```

---

## Cost Optimization

**1. Right-size the model**: Use the smallest model that meets the quality bar. 3B models are 3× cheaper to serve than 7B, often with acceptable quality on narrow tasks.

**2. Quantize aggressively**: INT4 AWQ halves VRAM with < 2% quality loss on most extraction tasks — doubles your concurrent capacity on the same hardware.

**3. Optimize for batch size**: Maximizing tokens/second means maximizing batch size. Use async request queuing to hold requests for up to 50–100ms to build larger batches.

**4. Cache aggressively**: System prompt prefix caching, response caching for identical inputs (with content hash), and semantic caching (vector similarity) in layers of increasing cost.

**5. Spot/preemptible instances**: LLM inference is stateless at the request level. Spot instances on AWS/GCP work well with a queue-based architecture — if a pod is preempted mid-request, re-queue the request.

**6. Route to smaller models first**: Deploy a 3B model and a 7B model. Route simple requests (short context, predictable format) to 3B. Escalate to 7B on failure or confidence threshold.

---

## Safety and Guardrails

Production LLMs need input and output filtering layers:

```
Request → Input Filter → LLM → Output Filter → Response

Input filters:
  - PII detection (redact SSNs, credit cards before sending to model)
  - Prompt injection detection (flag attempts to override system prompt)
  - Token budget enforcement (truncate inputs beyond context limit)
  - Content policy (block malicious requests at gateway)

Output filters:
  - JSON schema validation (for structured extraction tasks)
  - PII in output (model sometimes regenerates PII from context)
  - Hallucination detection for critical paths (secondary verification)
  - Token limit enforcement (prevent runaway generation)
```

For the HTML extraction use case: validate every response against the JSON schema before returning to the caller. A parse error rate > 1% means the model needs retraining or the temperature needs adjustment.

---

## Production Case Studies

**Mistral AI (La Plateforme)**: Runs vLLM with continuous batching on H100 clusters. Key insight: separate pools for short-context (< 2K tokens) and long-context requests to maximize batching within each pool.

**Together AI**: Uses FP8 quantization on H100s (H100 has native FP8 tensor cores). 2× throughput vs. BF16 with ~0.5% quality loss on most tasks. First movers on H100 FP8 serving.

**Replicate**: Serves many models on same hardware using a model-loading daemon that keeps the last N accessed models "warm" in VRAM. Cold start is the main product problem; they've invested heavily in < 30s first-request latency.

**Anyscale**: Routes requests across model replicas using Ray Serve. Key pattern: separate the request queue from the model worker so queue depth drives autoscaling independently of GPU utilization.

---

## Deployment Checklist

```
Before go-live:
  ✓ Load test to find max throughput + degradation point
  ✓ KV cache eviction tested under memory pressure (no crashes, graceful 429)
  ✓ Circuit breaker wired to queue depth (reject early, not slowly)
  ✓ Prometheus metrics + Grafana dashboard configured
  ✓ Log sampling enabled (not every token — 1% is enough for debugging)
  ✓ Model output validation / schema enforcement live
  ✓ Rollback plan: old model version still deployed and routable
  ✓ Spot instance re-queue logic tested
  ✓ PII scrubbing verified on input and output samples
```

---

## FAANG Interview Callout

> **"Design a scalable LLM inference platform for 10 million requests per day."**
>
> "10M RPD is ~116 RPS average, with a peak factor of 3–5× for 300–580 RPS. At 200 tokens average output, that's ~60K tokens/second at peak. With A100s running vLLM at ~3,500 tokens/s sustained, I need ~17 A100s. I'd provision 20 for 15% headroom and use spot instances for 40% of capacity with a SQS queue for retry on preemption. The architecture is: API gateway → request queue → vLLM fleet → output validator. The most important operational investment is prompt prefix caching — if the system prompt is consistent, this cuts TTFT by 50–80% and saves ~30% on compute. The scaling trigger is KV cache utilization, not GPU utilization, because a heavily loaded vLLM instance at 90% KV cache is a latency cliff — I'd scale out before hitting that wall. For 10M RPD, I'd also add a semantic cache in front of the model for repeated queries; at that volume, 10–20% of requests are likely near-duplicates."

---

## Related Files

- [04-inference-patterns.md](04-inference-patterns.md) — The inference server layer this file wraps
- [03-pretraining-and-llm-from-scratch.md](03-pretraining-and-llm-from-scratch.md) — Training → deployment handoff
- [AI/agent-workflows/README.md](../agent-workflows/README.md) — LLM serving inside agent loops
- [HLD/designs/](../../HLD/designs/) — Full HLD with capacity estimation for LLM serving platforms
