# AWS Lambda — Deep Dive

## Overview

Lambda is AWS's event-driven, serverless compute service. You upload code; AWS manages provisioning, scaling, patching, and high availability. Billing is per-invocation + GB-second of memory consumed, with a 1M free-tier invocations/month.

**Mental model:** Lambda is a container that starts on demand, runs your function, and idles (or dies). The platform manages the container fleet behind the scenes.

---

## Architecture Internals

### Execution Environment Lifecycle

```
Cold Start:
  Download code → Init runtime → Init extensions → Init function (INIT) → Invoke handler

Warm invocation (reuse):
  Invoke handler  ← same container, no INIT phase
```

- **Init phase** (cold start) = download + runtime bootstrap + your `init()` code outside the handler
- After invocation, container is kept "warm" for ~5–15 min (AWS managed, not guaranteed)
- **SnapStart** (Java/Corretto 21+): snapshot the initialized container at deploy time, restore from snapshot on cold start — reduces Java cold start from ~3s to ~200ms

### Concurrency Model

```
Account concurrency limit: 1,000 (default, raisable to 100k+)
Per-function limits:
  Reserved concurrency: hard cap, starves other functions if set too low
  Provisioned concurrency: pre-warmed containers, eliminates cold starts
```

**Concurrency math:**
```
Concurrent executions = (invocations/sec) × (avg duration in sec)
Example: 500 req/s × 0.2s avg = 100 concurrent
```

**Burst scaling:** Lambda can add 500–3,000 concurrent executions per minute (region-dependent). For sudden traffic spikes beyond this, requests are throttled (429).

### Memory, CPU, and Networking

| Memory | vCPU | Network bandwidth |
|--------|------|-------------------|
| 128 MB | 0.063 vCPU | Low |
| 1,769 MB | 1 vCPU | Moderate |
| 3,008 MB | 2 vCPU | High |
| 10,240 MB | 6 vCPU | ~4 Gbps |

- CPU scales **linearly** with memory — the only way to get more CPU is to allocate more memory
- Memory right-sizing: use Lambda Power Tuning (step function workflow) to find the optimal memory configuration

---

## Key Limits

| Parameter | Limit |
|-----------|-------|
| Max timeout | 15 minutes |
| Sync payload (request + response) | 6 MB |
| Async payload | 256 KB |
| Deployment package (zip, unzipped) | 50 MB / 250 MB |
| Container image | 10 GB |
| `/tmp` ephemeral storage | 512 MB – 10 GB |
| Concurrent executions (account default) | 1,000 |
| Environment variables | 4 KB total |
| Layers | 5 per function, 250 MB unzipped total |

---

## Invocation Types

| Type | Behavior | Retry |
|------|----------|-------|
| **Synchronous** (API GW, ALB, SDK) | Caller waits; function returns response | Caller retries |
| **Asynchronous** (S3, SNS, EventBridge) | Event queued internally, caller gets 202 immediately | 2 retries (built-in), then DLQ |
| **Event source mapping** (SQS, Kinesis, DynamoDB Streams, MSK) | Lambda polls the source | Depends on source |

### Async Destinations
```
Success → Lambda / SQS / SNS / EventBridge
Failure → Lambda / SQS / SNS / EventBridge (replaces DLQ, has richer metadata)
```

---

## Event Source Mappings (ESM)

### SQS ESM
- Lambda polls the queue, batches up to 10,000 messages (configurable)
- **Partial batch failure**: if any message fails, entire batch retries → use `ReportBatchItemFailures` to only retry failed items
- With SQS FIFO: 1 concurrent Lambda per message group ID

### Kinesis/DynamoDB Streams ESM
- Lambda reads from shard in order
- **Bisect on error**: split failing batch to isolate poison messages
- **Tumbling window**: aggregate over time (e.g., rolling sum over 5 minutes) before invoking
- One concurrent Lambda per shard (Enhanced Fan-out: one Lambda per consumer per shard)

### Key ESM parameters
| Parameter | Default | Use case |
|-----------|---------|----------|
| `BatchSize` | 10 (SQS), 100 (Kinesis) | Throughput vs latency |
| `BisectBatchOnFunctionError` | false | Isolate poison messages |
| `MaximumRetryAttempts` | -1 (infinite) | Prevent infinite loops |
| `DestinationConfig` | None | Route failures to SQS/SNS |
| `FilterCriteria` | None | Pre-filter events in ESM, reduces invocations |

---

## VPC Lambda

By default, Lambda runs in an AWS-managed VPC with internet access. Placing Lambda in your VPC:
- Enables access to RDS, ElastiCache, internal services
- Removes public internet access by default (add NAT GW or VPC Endpoint for AWS services)
- **Cold start impact**: formerly severe (ENI creation); since 2019 AWS pre-creates ENIs per subnet/SG combo — cold start impact is now ~100ms extra

**Best practice:** Place VPC Lambdas in **private subnets**, add VPC endpoints for S3/DynamoDB/SQS to avoid NAT costs, and reserve NAT gateway for external traffic only.

---

## Lambda@Edge vs CloudFront Functions

| Feature | Lambda@Edge | CloudFront Functions |
|---------|-------------|----------------------|
| Runtime | Node.js, Python | JavaScript (ES5.1) |
| Max execution time | 5–30s (viewer vs origin) | 1ms |
| Max memory | 128–10,240 MB | 2 MB |
| Pricing | Higher (per GB-second) | Fraction of Lambda@Edge |
| Network access | Yes | No |
| Use case | Auth, A/B, origin routing, body manipulation | Header rewrites, URL rewrites, redirects |
| Execution point | Viewer request/response, Origin request/response | Viewer request/response only |

**Rule of thumb:** CloudFront Functions for simple transforms <1ms; Lambda@Edge for anything needing network I/O or complex logic.

---

## SnapStart (Java)

```
Deploy:    Lambda initializes container → snapshots memory state
Invoke:    Restore from snapshot → invoke handler (~200ms cold start vs ~3s)
```

- Only available for Java (Corretto 11, 17, 21) managed runtime
- State in the snapshot (open sockets, random seeds) must be refreshed in `@SnapStartRestore` hook
- Provisioned Concurrency + SnapStart can achieve <100ms P99 cold starts

---

## Lambda Powertools (Observability Library)

Provides structured logging, tracing (X-Ray), metrics (EMF), and utility patterns:

```python
from aws_lambda_powertools import Logger, Tracer, Metrics
from aws_lambda_powertools.metrics import MetricUnit

logger = Logger()
tracer = Tracer()
metrics = Metrics(namespace="MyService")

@logger.inject_lambda_context
@tracer.capture_lambda_handler
@metrics.log_metrics
def handler(event, context):
    metrics.add_metric(name="Orders", unit=MetricUnit.Count, value=1)
    logger.info("Processing order", order_id=event["orderId"])
```

Key utilities: idempotency (uses DynamoDB), event source data classes, batch processing, feature flags (AppConfig).

---

## Lambda Extensions

- **Internal extensions**: run in same process, used for telemetry (flush logs before shutdown)
- **External extensions**: separate process, used for security agents (Datadog, Dynatrace, Secrets Manager caching)
- Extensions add to init time and billed duration — evaluate overhead carefully

---

## Function URLs

Direct HTTPS endpoint for a Lambda function without API Gateway:
- Supports IAM auth or `NONE` (public)
- Supports streaming responses (for LLM token streaming, chunked transfers)
- Not a replacement for API Gateway — no WAF integration, no throttling per-route, no usage plans

---

## Layers

- Shared dependencies across functions (e.g., common libraries, Powertools)
- Up to 5 layers per function, 250 MB unzipped total
- Layer ARN is version-pinned — updating a layer doesn't auto-update consuming functions
- AWS publishes managed layers for Powertools, X-Ray SDK, etc.

---

## Cost Optimization

| Technique | Impact |
|-----------|--------|
| Right-size memory (use Power Tuning) | 20-40% reduction typical |
| Use Graviton2 (`arm64`) runtime | 20% cheaper, 19% faster per GB-second |
| Avoid VPC if not needed | No NAT GW cost |
| Use ESM filter criteria | Fewer invocations |
| Async + SQS batching | Fewer invocations |
| Reduce cold starts with Provisioned Concurrency | Cost increases but P99 improves |

---

## Trade-off: Lambda vs Fargate vs ECS EC2

| Dimension | Lambda | Fargate | ECS/EC2 |
|-----------|--------|---------|---------|
| Max duration | 15 min | Unlimited | Unlimited |
| Cold start | Yes (100ms–3s) | Yes (10–30s) | No |
| Concurrency burst | 500–3,000/min | Slower (task launch) | Fastest (pre-warmed) |
| State | Stateless only | Stateless or stateful | Either |
| Cost (bursty) | Cheapest | Mid | Expensive (idle) |
| Cost (sustained high QPS) | Expensive | Cheaper | Cheapest |
| Ops overhead | None | Low | High |
| Best for | Event-driven, <15 min | Web services, batch | Long-running, GPU |

**Decision rule:** Lambda for event-driven or spiky workloads. Fargate when you need containers >15 min or predictable throughput. EC2 for GPU, high-memory, or cost-critical sustained workloads.

---

## Failure Modes & Mitigations

| Failure | Symptom | Mitigation |
|---------|---------|------------|
| Throttling (429) | Requests dropped | Raise concurrency limit; add SQS buffer in front |
| Timeout | Silent failure | Set alarm on `Duration` P99; use DLQ/destination |
| Cold start spike | Latency spike on deploy | Provisioned concurrency; SnapStart (Java) |
| Runaway recursion | Cost explosion | Set `RecursiveInvocationDetection` (2023 feature) |
| Poison message (ESM) | Infinite retry loop | `BisectBatchOnFunctionError` + `MaximumRetryAttempts` |
| Memory OOM | Function error | Increase memory; profile heap |

---

## FAANG Interview Callouts

**"Design a serverless image processing pipeline"**
→ S3 event → Lambda (thumbnail generation, <15 min) → result back to S3. Discuss: concurrency limits if traffic spikes to 50k req/s, use SQS as a buffer to smooth burst, Graviton2 for cost.

**"How do you eliminate cold starts for a payment API?"**
→ Provisioned Concurrency on the alias + SnapStart if Java. Quantify: 500 provisioned concurrency × $0.000004646/GB-second = ~$X/month — show you know the cost trade-off.

**"Lambda vs Fargate for a 30-minute video encoding job"**
→ Lambda cannot — max 15 min. Fargate task triggered by SQS or Step Functions. If job can be chunked, Lambda is fine.

**"How do you handle idempotency in Lambda with SQS?"**
→ SQS delivers at-least-once. Use DynamoDB conditional write on a deduplication key (Powertools idempotency decorator handles this). SQS FIFO gives deduplication window of 5 minutes.

**"What happens when your Lambda DLQ is full?"**
→ Messages are dropped. Monitor `DeadLetterErrors` CloudWatch metric. Use EventBridge Pipes to process DLQ systematically instead of treating it as a fire-and-forget dump.
