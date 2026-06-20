# Serverless Architecture Pattern

## Overview
Serverless is an execution model where the cloud provider manages all infrastructure — servers, scaling, availability, and patching — and you pay only for actual compute time consumed. The unit of deployment is a function or a container task, not a server.

**The core promise**: eliminate undifferentiated heavy lifting (OS patching, capacity planning, cluster management) so engineers focus on business logic.

Serverless is not a single service — it is a *design philosophy* applied consistently across the stack:

| Layer | Serverless equivalent |
|---|---|
| Compute | Lambda, Fargate |
| API | API Gateway (HTTP), AppSync (GraphQL) |
| Database | DynamoDB, Aurora Serverless v2, Firestore |
| Queue/messaging | SQS, SNS, EventBridge |
| Storage | S3 |
| Orchestration | Step Functions |
| Search | OpenSearch Serverless |
| Analytics | Athena, Redshift Serverless |
| Stream processing | Kinesis Data Streams (on-demand), MSK Serverless |
| CDN/edge | CloudFront, Lambda@Edge, CloudFront Functions |

---

## Architecture Patterns

### Pattern 1: Serverless REST API
```
Client → CloudFront → API Gateway (HTTP API) → Lambda → DynamoDB
                                              → SQS (async work)
         Route53       JWT Authoriser (Cognito)
```

**Cost model**: $0 when idle. Pay per request: API Gateway ($1/million) + Lambda ($0.20/million invocations + duration). DynamoDB on-demand ($1.25/million WCUs). At 1M requests/day = ~$50/month all-in.

**Cold starts**: the Lambda execution environment is recycled after ~15 minutes idle. First invocation after recycling incurs a cold start: 100ms (Python/Node.js) to 2,000ms (JVM without SnapStart).

### Pattern 2: Event-Driven Pipeline
```
S3 PUT → S3 Event → SQS → Lambda (process) → DynamoDB
                    ↓ DLQ (failed records)
```

### Pattern 3: Orchestrated Workflow
```
API Gateway → Lambda (submit job) → SQS → Step Functions
  ↓ 202 Accepted                            ↓ Steps: validate → enrich → persist → notify
  GET /status/{jobId}                       ↓ DynamoDB (state)
```

### Pattern 4: Scheduled Batch
```
EventBridge Scheduler (cron) → Lambda → RDS/S3/external API
```

### Pattern 5: Real-Time Data Processing
```
Kinesis Data Streams → Lambda (event source mapping) → DynamoDB / OpenSearch / S3
                     → Kinesis Firehose (parallel) → S3 archive
```

---

## Lambda: The Core Compute Unit

### Execution Model
Each Lambda invocation runs in an isolated execution environment (Firecracker microVM on Nitro hypervisor). Environments are reused for warm invocations. Each environment handles one request at a time — concurrency = number of simultaneous execution environments.

**Concurrency model**:
```
Reserved concurrency: hard cap on a specific function (starve or protect downstream)
Provisioned concurrency: pre-warm environments for zero cold start
Account limit: 1,000 concurrent invocations (soft; increase via support)
```

### Invocation Types

| Type | Response | Retry | Use case |
|---|---|---|---|
| **Synchronous** | Immediate response | Caller retries | API Gateway, CLI, direct SDK call |
| **Asynchronous** | 202 Accepted | Lambda retries 2x; then DLQ | SNS, EventBridge, S3 notifications |
| **Event Source Mapping** | Processed in batch | Configurable retries; DLQ | SQS, Kinesis, DynamoDB Streams, MSK |

### Cold Start Optimisation

| Strategy | Impact | Trade-off |
|---|---|---|
| **Provisioned Concurrency** | Eliminates cold starts | Cost ($0.015/hour per provisioned env) |
| **Lambda SnapStart (Java)** | Reduces JVM cold start from 2s → 200ms | Snapshot restore overhead; extra deploy time |
| **Smaller deployment package** | Faster environment init | Less code means less flexibility |
| **Runtime choice** | Node.js/Python: ~100ms; Java: 1–2s; Go: ~50ms | Language preference |
| **Arm64 (Graviton2)** | 20% better price-performance | Arm ABI compatibility |
| **Keep-warm ping** | Reduces recycling | Adds cost; hack, not solution |
| **Application-level optimisation** | Move heavy init outside handler | Code discipline required |

**Move heavy initialisation outside the handler**:
```python
# Runs once per execution environment (warm reuse)
import boto3
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('orders')

def handler(event, context):
    # Uses pre-initialised table client — no SDK init per request
    return table.get_item(Key={'id': event['id']})
```

### Memory and Performance
Lambda allocates CPU proportionally to memory. Memory doubles → CPU doubles → execution time halves (for CPU-bound work) → cost same.

```
Lambda pricing: $0.0000166667 per GB-second
128 MB, 1s → $0.00000213
512 MB, 0.3s → $0.00000256  (slightly more expensive, but 3x faster for users)
1024 MB, 0.15s → $0.00000256 (same cost, 6x faster)
```

Use AWS Lambda Power Tuning (open-source Step Functions state machine) to find the optimal memory setting for cost and latency.

### Lambda Networking
- **Outside VPC** (default): internet access, fast cold start; no VPC resource access
- **Inside VPC**: access to RDS, ElastiCache, private services; +100–200ms cold start; requires NAT Gateway for internet

**Rule**: only put Lambda in a VPC when it needs VPC resources (RDS, ElastiCache, private endpoints). Use Secrets Manager, DynamoDB, S3, SQS via public endpoints (or VPC endpoints) from outside-VPC Lambdas.

---

## Serverless Database: DynamoDB

The natural serverless database — no connections to manage, no connection pool exhaustion, on-demand pricing.

**Why DynamoDB fits serverless**:
- Connection-less (HTTP API) — Lambda functions don't hold idle TCP connections
- On-demand mode scales to 0 (no minimum cost)
- Sub-millisecond reads; single-digit ms writes
- DynamoDB Accelerator (DAX) for microsecond read caching

**Aurora Serverless v2**: scales RDS Aurora down to 0.5 ACUs (~1GB RAM), up to 128 ACUs, in seconds. For workloads that need SQL but can tolerate variable latency during scale events. Minimum cost: ~$43/month at 0.5 ACU minimum.

---

## Serverless Patterns and Anti-Patterns

### Pattern: Fan-Out with SNS + Lambda
One event triggers N parallel Lambda functions:
```
OrderPlaced event → SNS → Lambda A (inventory reserve)
                       → Lambda B (fraud check)
                       → Lambda C (analytics)
All complete independently; no orchestration overhead
```

### Pattern: Async Long-Running Job
```
Client POSTs request → API Gateway → Lambda (submit) → SQS + Step Functions
                        ← 202 + jobId
Client GETs /jobs/{id} → Lambda (read from DynamoDB) → {status: processing}
                        → Lambda → {status: complete, result: ...}
```

### Pattern: Dead-Letter Queue for All Async Lambdas
Every Lambda with async invocation (SNS, EventBridge, S3) must have a DLQ:
```json
"FunctionConfiguration": {
  "DeadLetterConfig": {"TargetArn": "arn:aws:sqs:...:function-name-dlq"}
}
```

### Anti-Pattern: Lambda Calling Lambda Synchronously
```
# WRONG: tight coupling, latency stacking, concurrent Lambda exhaustion
Lambda A → invoke(Lambda B) → invoke(Lambda C)
```
Latency = A + B + C. If B times out (15 min), A also blocks. Concurrency consumed by the chain.

**Fix**: use SQS or Step Functions between Lambdas. Never synchronous chaining except for trivially fast utility calls.

### Anti-Pattern: Lambda with Relational Database (Direct)
Lambda scales to 1,000 concurrent; each opens a DB connection; MySQL/Postgres max connections = 100–500. Lambda will exhaust the connection pool during burst.

**Fix**: Use RDS Proxy (connection pooler between Lambda and RDS) or use DynamoDB instead. RDS Proxy holds the pool; Lambda shares connections from the proxy.

### Anti-Pattern: Monolithic Lambda
One Lambda handling every endpoint of an API:
- Cold start cost rises with package size
- Deployment affects all endpoints
- IAM permissions become over-broad

**Fix**: one Lambda per API endpoint (or per logical boundary). Or use a web framework (FastAPI, Express) inside a Lambda for simpler ops, but be aware of trade-offs.

---

## Cost Model: Serverless vs Always-On

### Serverless wins when:
- **Variable/bursty traffic** — pay only during peaks
- **Idle periods** — a serverless API at midnight costs $0
- **Infrequent tasks** — a nightly report at 2 AM costs microseconds

### Always-on (EC2/ECS/EKS) wins when:
- **Sustained, predictable high throughput** — at 100M req/day, Lambda cost > ECS cost
- **Long-running processes** — Lambda max 15 min; ECS tasks run indefinitely
- **CPU-intensive work** — Lambda's CPU is time-shared; EC2 gives dedicated CPU
- **WebSockets / persistent connections** — Lambda is stateless and request-scoped
- **Latency-sensitive + cold start intolerant** — trading cold start for always-warm

**Break-even rule of thumb**: if your compute is consistently > 50% utilised, reserved EC2/ECS is cheaper than Lambda. If utilisation varies significantly (overnight drops to <10%), serverless likely wins.

---

## Observability for Serverless

Serverless removes servers but adds distributed complexity. Observability must be built into the architecture.

| Tool | What it provides |
|---|---|
| **Lambda Insights** (Container Insights for Lambda) | Per-invocation memory, duration, cold start, init time |
| **X-Ray** | Distributed traces across Lambda + DynamoDB + SQS calls |
| **CloudWatch EMF** | Custom business metrics from Lambda stdout — zero API call overhead |
| **Powertools for Lambda** | Structured logging, tracing, metrics library (Python/TypeScript/Java) |
| **CloudWatch Logs Insights** | Query logs across all Lambda functions simultaneously |

**Lambda Powertools** is the standard observability library for serverless:
```python
from aws_lambda_powertools import Logger, Tracer, Metrics
logger = Logger()
tracer = Tracer()
metrics = Metrics(namespace="PaymentsApp")

@tracer.capture_lambda_handler
@metrics.log_metrics
@logger.inject_lambda_context
def handler(event, context):
    logger.info("Processing payment", payment_id=event['id'])
    metrics.add_metric(name="PaymentProcessed", unit=MetricUnit.Count, value=1)
```

---

## Trade-offs Summary

| Dimension | Serverless | Containerised (ECS/EKS) |
|---|---|---|
| **Operational overhead** | Very low — no cluster management | Medium to high |
| **Cold start** | Present (mitigable) | None (always warm) |
| **Max execution time** | 15 minutes | Unlimited |
| **Concurrency model** | Per-invocation isolation | Shared process |
| **Cost at low load** | Near zero | Fixed (idle containers) |
| **Cost at high sustained load** | Can exceed containers | Lower per-request |
| **Persistent connections** | Not possible per invocation | Full support |
| **Debugging** | Harder (distributed, ephemeral) | Easier (exec into container) |
| **Custom runtimes** | Limited (Lambda custom runtime) | Any Docker image |
| **Vendor lock-in** | High (Lambda API surface) | Low (Docker portable) |

---

## Best Practices

1. **Separate Lambda per responsibility** — don't build monolithic Lambdas
2. **Keep handler thin** — move initialisation code outside the handler for warm reuse
3. **Set memory based on profiling** — use Lambda Power Tuning; more memory = more CPU
4. **Use Provisioned Concurrency only for user-facing latency-sensitive APIs** — not for batch
5. **Always configure DLQ for async invocations** — failures must be captured
6. **Use SQS between Lambdas, not synchronous chaining**
7. **Use RDS Proxy for relational databases** — prevents connection pool exhaustion
8. **Use DynamoDB on-demand mode** for serverless backends — scales to zero with the Lambda
9. **Instrument with Lambda Powertools** — structured logging + X-Ray + EMF metrics from day one
10. **Set concurrency limits on non-critical Lambdas** — protect downstream systems from Lambda burst

---

## FAANG Interview Points

**"When would you not use serverless?"**: Long-running processes (>15 min), WebSocket servers needing persistent state, CPU-intensive sustained workloads (ML training, video encoding at scale), workloads where cold start latency is unacceptable and Provisioned Concurrency cost is too high, or when vendor lock-in is a hard constraint.

**"Design a serverless payment API"**: API Gateway (HTTP API, JWT auth) → Lambda (validate + submit) → SQS FIFO → Step Functions (saga: fraud check → inventory → charge → notify). DynamoDB for state. All Lambda functions have DLQs. RDS Proxy if relational DB needed. X-Ray tracing end-to-end.

**"How do you handle Lambda cold starts?"**: For user-facing APIs: Provisioned Concurrency (eliminates cold start at cost). For JVM: Lambda SnapStart (snapshots initialised environment). For all: move initialisation outside handler, use smaller packages, choose interpreted runtimes (Python/Node) over JVM for latency-critical.
