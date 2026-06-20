# Azure Cloud Design Patterns — Complete Catalog

> **Source**: [Microsoft Azure Architecture Center — Cloud Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/patterns/)  
> **AWS Equivalents**: Side-by-side implementations for all 44 patterns  
> **WAF Alignment**: Each pattern maps to Azure Well-Architected Framework pillars

---

## Pattern Catalog (All 44)

| Pattern | Problem It Solves | WAF Pillars | Azure Implementation | AWS Equivalent |
|---------|-------------------|-------------|---------------------|----------------|
| **Ambassador** | Proxy helper services for cross-cutting concerns (retry, circuit break, logging) | Reliability, Security | Envoy sidecar in AKS; APIM policy | AWS App Mesh (Envoy); API Gateway |
| **Anti-Corruption Layer** | Translate between modern app and legacy system without polluting domain model | Operational Excellence | Azure API Management + Logic Apps adapter | API Gateway + Lambda adapter |
| **Asynchronous Request-Reply** | Back-end is async but front-end needs a response URL to poll | Performance Efficiency | Azure Functions + Service Bus + Blob (status store) | Lambda + SQS + DynamoDB (status) |
| **Backends for Frontends (BFF)** | Different front-ends (mobile, web) need tailored APIs | Reliability, Security, Performance | Azure APIM with per-product APIs; AKS microservices | API Gateway (separate stages); ALB routing |
| **Bulkhead** | Isolate failure in one subsystem from others | Reliability, Security, Performance | AKS node pools per workload; Container Apps environments | EKS node groups per service; Fargate task isolation |
| **Cache-Aside** | Load data on demand into cache to reduce DB load | Reliability, Performance | Azure Cache for Redis + Cosmos DB | ElastiCache + DynamoDB |
| **Choreography** | Services react to events independently — no central orchestrator | Operational Excellence, Performance | Azure Event Grid + Service Bus Topics | EventBridge + SNS |
| **Circuit Breaker** | Stop calling a failing dependency; fail fast and recover | Reliability, Performance | Azure APIM circuit breaker policy; Polly SDK | API Gateway throttling; AWS SDK retry with jitter |
| **Claim Check** | Split large message into reference + payload to avoid bus overload | Reliability, Security, Cost, Performance | Azure Blob Storage (payload) + Service Bus (claim key) | S3 (payload) + SQS Extended Client Library |
| **Compensating Transaction** | Undo steps in a partially-completed distributed operation | Reliability | Azure Durable Functions Saga orchestration | AWS Step Functions with compensate states |
| **Competing Consumers** | Scale message processing horizontally with multiple consumers | Reliability, Cost, Performance | Service Bus Queue + Azure Functions (KEDA scaling) | SQS + Lambda (event source mapping) |
| **Compute Resource Consolidation** | Co-locate multiple lightweight tasks in one compute unit | Cost, Operational Excellence, Performance | Azure Functions with multiple triggers in one app | Lambda layers sharing common code; single Lambda for multi-function |
| **CQRS** | Separate read and write models for different scaling characteristics | Performance | Cosmos DB change feed → read replica; Event Hubs → materialized views | DynamoDB Streams → read replica in ElastiCache/OpenSearch |
| **Deployment Stamps** | Deploy identical copies of app stack per region/tenant | Operational Excellence, Performance | Azure Deployment Stacks + Bicep; Front Door routing | CloudFormation StackSets; CloudFront origin groups |
| **Event Sourcing** | Persist state as append-only event log; derive current state from events | Reliability, Performance | Azure Event Hubs (event store) + Blob Storage (snapshots) | Amazon Kinesis Data Streams + S3 snapshots |
| **External Configuration Store** | Centralize config outside the app deployment | Operational Excellence | Azure App Configuration + Key Vault references | AWS Systems Manager Parameter Store + Secrets Manager |
| **Federated Identity** | Delegate authentication to external IdP | Reliability, Security, Performance | Microsoft Entra ID (OIDC/SAML) + APIM JWT validation | Amazon Cognito + API Gateway authorizer |
| **Gatekeeper** | Dedicated security host validates/sanitizes requests before private back-ends | Security, Performance | Azure APIM + Application Gateway WAF | AWS WAF + API Gateway + Lambda authorizer |
| **Gateway Aggregation** | Single gateway call fans out to multiple services; aggregates responses | Reliability, Security, Operational, Performance | Azure APIM with aggregate policy; Azure Functions orchestrator | API Gateway + Lambda aggregator; App Mesh |
| **Gateway Offloading** | Move cross-cutting concerns (auth, SSL, rate limiting) to gateway | Reliability, Security, Cost, Operational, Performance | Azure APIM (JWT validation, rate limiting, caching, transformation) | API Gateway (authorizers, usage plans, caching) |
| **Gateway Routing** | Single entry point routes to multiple backend services | Reliability, Operational, Performance | Azure Front Door (URL routing, health probes) + APIM | CloudFront + API Gateway; ALB path-based routing |
| **Geode** | Deploy back-end nodes globally; any node serves any client | Reliability, Performance | Azure Cosmos DB multi-region writes + Front Door anycast | DynamoDB Global Tables + CloudFront |
| **Health Endpoint Monitoring** | Expose `/health` endpoints for external monitoring | Reliability, Operational, Performance | Azure Monitor + Application Insights availability tests | CloudWatch Synthetics + Route 53 health checks |
| **Index Table** | Create secondary index over fields not in primary key | Reliability, Performance | Cosmos DB composite indexes + partial indexes | DynamoDB GSI; ElasticSearch index |
| **Leader Election** | Elect one instance as coordinator in distributed app | Reliability | Azure Blob Storage leases (distributed lock) + Azure Functions | DynamoDB conditional writes (optimistic lock); ElastiCache SETNX |
| **Materialized View** | Precomputed views over raw data for query-optimized reads | Performance | Cosmos DB change feed → Azure Functions → read store | DynamoDB Streams → Lambda → ElastiCache/OpenSearch read model |
| **Messaging Bridge** | Intermediary between incompatible messaging systems | Cost, Operational Excellence | Azure Logic Apps connectors; Service Bus bridge | EventBridge Pipes; custom Lambda bridge |
| **Pipes and Filters** | Break complex processing into composable, reusable pipeline stages | Reliability | Azure Functions Durable orchestration chains; Event Hubs → Functions → Blob | AWS Step Functions; Kinesis → Lambda → S3 |
| **Priority Queue** | High-priority messages processed before low-priority ones | Reliability, Performance | Service Bus Premium with message sessions by priority | SQS FIFO with message group IDs; separate queues per priority |
| **Publisher-Subscriber** | Async fan-out to multiple consumers without coupling | Reliability, Security, Cost, Operational, Performance | Azure Event Grid (push) or Service Bus Topics (pull) | Amazon SNS (push); EventBridge (rule-based) |
| **Quarantine** | Validate external assets before workload consumption | Security, Operational Excellence | Azure Blob Storage lifecycle + Defender for Storage malware scan | S3 + Amazon Macie + Lambda scan before promotion |
| **Queue-Based Load Leveling** | Buffer between producer and consumer to absorb traffic spikes | Reliability, Cost, Performance | Service Bus Queue absorbs spikes; Functions scale to drain | SQS absorbs spikes; Lambda scales to drain |
| **Rate Limiting** | Control resource consumption to avoid throttling | Reliability | Azure APIM rate-limit policy; Azure Functions with Durable Functions rate limiter | API Gateway usage plans; Lambda with SQS throttle |
| **Retry** | Retry transient failures with backoff | Reliability | Azure SDK built-in retry policies; Polly (exponential + jitter) | AWS SDK built-in retry; custom exponential backoff |
| **Saga** | Manage data consistency across microservices in distributed transactions | Reliability | Azure Durable Functions (orchestration Saga) | AWS Step Functions Standard Workflow |
| **Scheduler Agent Supervisor** | Coordinate long-running distributed tasks with fault recovery | Reliability, Performance | Azure Durable Functions (Monitor pattern) | AWS Step Functions + Lambda + DynamoDB state |
| **Sequential Convoy** | Process related messages in order without blocking other groups | Reliability | Service Bus sessions (FIFO within session, parallel across sessions) | SQS FIFO message group IDs |
| **Sharding** | Horizontally partition data across multiple stores | Reliability, Cost | Cosmos DB logical partitions (automatic); Azure SQL elastic pools | DynamoDB partitions (automatic); RDS shard-per-tenant |
| **Sidecar** | Deploy auxiliary process alongside main service for isolation | Security, Operational Excellence | AKS sidecar containers; Dapr sidecar for state/pub-sub/secrets | EKS sidecar containers; AWS App Mesh Envoy proxy |
| **Static Content Hosting** | Serve static assets from storage, not compute | Cost | Azure Blob Storage + Azure CDN; Azure Static Web Apps | S3 + CloudFront |
| **Strangler Fig** | Incrementally replace legacy system piece-by-piece | Reliability, Cost, Operational | Azure APIM routing rules to old vs new; Front Door weighted routing | API Gateway canary deployments; ALB weighted target groups |
| **Throttling** | Control consumption of shared resources per tenant or service | Reliability, Security, Cost, Performance | Azure APIM throttling policies; Cosmos DB RU/s per container | API Gateway usage plans; DynamoDB provisioned capacity |
| **Valet Key** | Give clients time-limited, scoped direct access to storage | Security, Cost, Performance | Azure Storage SAS (Shared Access Signature) tokens | AWS S3 Pre-Signed URLs; STS temporary credentials |

---

## Deep-Dives: 12 Most Interview-Relevant Patterns

---

### 1. Circuit Breaker

**Problem**: A remote dependency is failing slowly (timeouts, errors). Each request blocks a thread and cascades.

**States**:
```
Closed → (failure threshold exceeded) → Open → (reset timeout) → Half-Open
  ↑                                                                    │
  └──────────── (success in Half-Open) ──────────────────────────────┘
```

**Azure implementation**:
- **Azure APIM**: Built-in circuit breaker policy (GA 2024). Configure `tripDuration`, `failureCondition`, `acceptRetryAfter`.
- **Polly (.NET)**: `services.AddHttpClient().AddPolicies(circuitBreaker)` — most common app-level implementation.
- **Azure Front Door**: Health probes auto-remove unhealthy origins (origin-level circuit breaker).

**AWS implementation**:
- **AWS App Mesh + Envoy**: Outlier detection (passive circuit breaker) — `consecutiveGatewayErrors: 5`.
- **API Gateway**: No native circuit breaker; use Lambda power tools or custom logic.
- **AWS SDK**: Built-in retry with jitter, but no automatic open/close circuit state.

**Trade-off**:

| Aspect | Azure (APIM) | AWS (App Mesh) |
|--------|-------------|----------------|
| Config location | Gateway policy (infra) | Service mesh sidecar |
| App code changes | None required | None required (sidecar) |
| Granularity | Per API operation | Per route/service |
| Cost | APIM pricing | App Mesh + EC2/Fargate overhead |

**FAANG callout**: "I use Circuit Breaker at two levels: at the gateway (APIM policy / API Gateway) for external services, and in application code (Polly / AWS SDK retry) for internal calls. The key parameter is the reset timeout — too short and you re-open before the dependency recovers; too long and you degrade unnecessarily. I set it to 2× the p99 recovery time from the last post-mortem."

---

### 2. Saga Pattern

**Problem**: A distributed transaction spans multiple microservices. 2PC (two-phase commit) is unavailable or too slow. Need rollback on partial failure.

**Two flavors**:

| Flavor | Coordination | Azure | AWS |
|--------|-------------|-------|-----|
| **Orchestration** | Central coordinator tells each service what to do | Azure Durable Functions (Orchestrator function) | AWS Step Functions Standard Workflow |
| **Choreography** | Services react to events; no central coordinator | Azure Event Grid / Service Bus Topic chain | Amazon EventBridge / SNS chain |

**Azure Durable Functions Saga** (orchestration):
```
OrderOrchestrator
  ├── Call PaymentService.Reserve()    → success
  ├── Call InventoryService.Reserve()  → failure!
  └── Compensate:
      └── Call PaymentService.Release()  ← compensating transaction
```

**AWS Step Functions Saga**:
```json
{
  "States": {
    "ReservePayment": { "Catch": [{ "Next": "ReleasePayment" }] },
    "ReserveInventory": { "Catch": [{ "Next": "ReleasePayment" }] },
    "ReleasePayment": { "Type": "Task", "End": true }
  }
}
```

**When to use choreography over orchestration**:
- Choreography: Loosely coupled services, simple flows, teams own their own events
- Orchestration: Complex flows with many compensation steps, need visibility, auditability required

**Trade-off**:

| Aspect | Orchestration | Choreography |
|--------|--------------|-------------|
| Coupling | Central orchestrator is a dependency | Services are decoupled |
| Visibility | Full execution history in Durable Functions / Step Functions | Must aggregate events from all services |
| Failure handling | Explicit compensation in orchestrator | Each service owns its own retry/compensate |
| Testing | Easier to unit test orchestrator | Harder to trace full flow in tests |

---

### 3. CQRS (Command Query Responsibility Segregation)

**Problem**: Read and write workloads have different scaling, latency, and model requirements.

**Azure implementation**:
```
Write side:                          Read side:
Client → API → Cosmos DB (write)     Cosmos DB Change Feed
                    │                        │
                    └── Change Feed ──► Azure Functions
                                              │
                                    ┌─────────┴─────────┐
                                    ▼                   ▼
                               Azure Cache           Azure AI Search
                               for Redis             (full-text read)
                               (hot reads)
```

**AWS implementation**:
```
Write side:                          Read side:
Client → API → DynamoDB (write)      DynamoDB Streams
                    │                      │
                    └── Streams ──► Lambda
                                       │
                             ┌─────────┴─────────┐
                             ▼                   ▼
                        ElastiCache          Amazon OpenSearch
                        (hot reads)          (search reads)
```

**Key insight**: Cosmos DB Change Feed and DynamoDB Streams are both ordered, at-least-once delivery mechanisms — the backbone of CQRS on cloud.

**When NOT to use CQRS**: When reads and writes have similar volume. The operational overhead of two models isn't justified for simple CRUD apps.

---

### 4. Event Sourcing

**Problem**: Current state loses history. Need audit trail, temporal queries ("what was the state at T?"), or event replay for new projections.

**Azure architecture**:
```
Events → Azure Event Hubs (immutable log, 7–90 day retention)
              │
              ├── Azure Functions (real-time projection to Cosmos DB)
              ├── Azure Stream Analytics (aggregations)
              └── Azure Blob Storage (cold archival, snapshots)
```

**AWS architecture**:
```
Events → Amazon Kinesis Data Streams (7-day default, 365-day extended)
              │
              ├── Lambda (real-time projection to DynamoDB)
              ├── Kinesis Data Analytics (aggregations)
              └── S3 (cold archival via Kinesis Firehose)
```

**Trade-off table**:

| Aspect | Event Hubs | Kinesis |
|--------|-----------|---------|
| Kafka compatibility | Yes (Kafka protocol surface) | No (custom SDK) |
| Max retention | 90 days (Standard), unlimited with Capture to ADLS | 365 days (extended) |
| Max message size | 1 MB | 1 MB |
| Throughput unit | 1 MB/s in, 2 MB/s out per TU | 1 MB/s in, 2 MB/s out per shard |
| Ordering guarantee | Within partition | Within shard |

**Pair with**: CQRS — Event Sourcing is the write side; CQRS defines the read projections.

---

### 5. Claim Check

**Problem**: Message bus has a size limit (Service Bus: 256 KB standard, 100 MB premium; SQS: 256 KB). Large payloads (images, documents, large JSON) exceed the limit.

**Azure implementation**:
```
Publisher:
  1. Upload payload → Azure Blob Storage
  2. Get blob URL + SAS token
  3. Publish claim message to Service Bus → { "claim_url": "https://…", "correlation_id": "abc" }

Consumer:
  1. Receive claim from Service Bus
  2. Download payload from Blob using URL
  3. Process payload
  4. Delete blob (cleanup)
```

**AWS implementation**:
```
Publisher:
  1. Upload payload → S3
  2. Get pre-signed URL or S3 key
  3. Publish claim to SQS → { "s3_key": "payloads/abc.json" }

Consumer:
  1. Receive SQS message
  2. Download from S3 using s3_key
  3. Process
  4. Delete S3 object + SQS message
```

**AWS alternative**: Amazon SQS Extended Client Library (Java) automates this pattern transparently.

**Azure alternative**: Service Bus Premium tier supports 100 MB messages — Claim Check may not be needed.

---

### 6. Strangler Fig

**Problem**: Rewrite a monolith incrementally. Can't do a big-bang rewrite. Need zero-downtime migration.

**Azure implementation using APIM**:
```
Phase 1: All traffic → Legacy system (APIM routes to monolith)
Phase 2: /orders/* → New Orders Service | rest → Legacy
Phase 3: /products/* → New Products Service | /orders/* → New | rest → Legacy
Phase N: All traffic → New system (APIM routes fully to microservices)
```

APIM policy for routing:
```xml
<choose>
  <when condition="@(context.Request.Url.Path.StartsWith("/orders"))">
    <set-backend-service base-url="https://orders-service.azurewebsites.net" />
  </when>
  <otherwise>
    <set-backend-service base-url="https://legacy-monolith.azurewebsites.net" />
  </otherwise>
</choose>
```

**AWS implementation**:
- **API Gateway + Lambda**: Lambda checks request path, proxies to old or new service
- **ALB weighted target groups**: Gradually shift % traffic from monolith target group to microservice target group
- **CloudFront behaviors**: Different cache behaviors with different origins

**Key metric**: Track error rate per path segment — only migrate when new service error rate ≤ old system error rate for 72 hours.

---

### 7. Competing Consumers

**Problem**: Processing queue messages is slow. Need to scale horizontally. But each message should be processed exactly once.

**Azure with Service Bus + Azure Functions**:
```
Service Bus Queue (with lock duration 5 min)
       │
       ├── Function Instance 1 ──► Lock message → Process → Complete/Abandon
       ├── Function Instance 2 ──► Lock message → Process → Complete/Abandon
       └── Function Instance N ──► Lock message → Process → Complete/Abandon
                                              ↑
                            KEDA scales based on queue depth (messages per instance)
```

**AWS with SQS + Lambda**:
```
SQS Queue (visibility timeout 5 min)
       │
       └── Lambda (event source mapping, batch size 10, concurrency 100)
               │
               ├── Process batch → deleteMessageBatch() on success
               └── Partial failures → SQS moves failed to DLQ after maxReceiveCount
```

**Difference**: Service Bus `Complete()`/`Abandon()` is explicit per message; SQS Lambda integration handles batch completion automatically (with `reportBatchItemFailures`).

---

### 8. Valet Key

**Problem**: Clients need direct access to storage (upload/download) without routing through app server. App server is a bottleneck and unnecessary intermediary.

**Azure SAS Token**:
```python
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from datetime import datetime, timedelta

sas_token = generate_blob_sas(
    account_name=account_name,
    container_name="uploads",
    blob_name=f"user/{user_id}/avatar.jpg",
    account_key=account_key,
    permission=BlobSasPermissions(write=True, read=False),  # write-only!
    expiry=datetime.utcnow() + timedelta(minutes=15)
)
upload_url = f"https://{account_name}.blob.core.windows.net/uploads/user/{user_id}/avatar.jpg?{sas_token}"
```

**AWS Pre-Signed URL**:
```python
import boto3
s3 = boto3.client('s3')
presigned_url = s3.generate_presigned_url(
    'put_object',
    Params={'Bucket': 'uploads', 'Key': f'user/{user_id}/avatar.jpg'},
    ExpiresIn=900  # 15 minutes
)
```

**Security controls**:

| Control | Azure SAS | AWS Pre-Signed URL |
|---------|----------|-------------------|
| Scope | Account, container, or blob level | Bucket + object key |
| Permissions | Read, Write, Delete, List (granular) | Single HTTP method |
| IP restriction | `signedIP` in SAS | Bucket policy condition |
| HTTPS only | `signedProtocol=https` | Bucket policy `aws:SecureTransport` |
| Revocation | Rotate account key or use stored access policy | No revocation (wait for expiry) |

**Azure advantage**: Stored Access Policies allow revocation by deleting the policy — SAS tokens referencing it immediately expire. AWS pre-signed URLs cannot be revoked before expiry.

---

### 9. Bulkhead

**Problem**: One slow or failing service consumes all shared resources (threads, connections), starving others.

**Azure AKS implementation**:
```yaml
# Separate node pools per workload class
nodePool: payment-pool
  taints: [dedicated=payments:NoSchedule]
  vmSize: Standard_D4s_v5

nodePool: reporting-pool
  taints: [dedicated=reporting:NoSchedule]
  vmSize: Standard_D2s_v5
```

Reporting slowness → only `reporting-pool` saturates. Payment processing unaffected.

**Azure Container Apps** (alternative):
- Separate Container Apps Environments = separate virtual networks + compute pools

**AWS EKS implementation**:
```yaml
# Separate managed node groups
nodeGroup: payment-nodes
  instanceType: m5.xlarge
  labels: { workload: payments }
  taints: [{ key: dedicated, value: payments, effect: NoSchedule }]

nodeGroup: reporting-nodes
  instanceType: m5.large
  labels: { workload: reporting }
```

**Bulkhead at the connection pool level** (app code — same on both clouds):
```python
# Polly (.NET) / Resilience4j (Java)
bulkhead_policy = Policy.BulkheadAsync(
    maxParallelization=10,    # max concurrent calls to payments
    maxQueuingActions=5       # max queued; beyond this → IsolationException
)
```

---

### 10. Retry + Circuit Breaker (Combo)

**The canonical pairing**: Retry handles transient faults (blip). Circuit Breaker stops retrying when faults are persistent.

```
Request
  │
  ▼
[Retry Policy: 3 attempts, exponential backoff]
  │
  ▼ if all retries fail
[Circuit Breaker: open for 30s]
  │
  ▼ while open
[Fail Fast: return cached response or error]
```

**Azure (.NET Polly / Microsoft.Extensions.Resilience)**:
```csharp
services.AddHttpClient<IPaymentClient, PaymentClient>()
    .AddStandardResilienceHandler()  // retry + circuit breaker + timeout in one call
    .Configure(options => {
        options.Retry.MaxRetryAttempts = 3;
        options.CircuitBreaker.SamplingDuration = TimeSpan.FromSeconds(30);
        options.CircuitBreaker.FailureRatio = 0.5;
    });
```

**AWS (Python boto3)**:
```python
# boto3 has built-in retry; combine with circuit breaker library
from aws_lambda_powertools.utilities.batch import batch_processor
from circuitbreaker import circuit

@circuit(failure_threshold=5, recovery_timeout=30)
def call_payment_service(payload):
    return requests.post(PAYMENT_URL, json=payload, timeout=2)
```

**Jitter is mandatory**: Without jitter, all retrying clients synchronize and create a retry storm. Use `ExponentialBackoff + FullJitter` (AWS recommendation) or Polly's `DecorrelatedJitter`.

---

### 11. Throttling

**Problem**: Shared service cannot handle unlimited load from all tenants. Need per-tenant limits.

**Azure APIM throttling**:
```xml
<!-- Rate limit per subscription key (tenant) -->
<rate-limit-by-key calls="100" renewal-period="60"
    counter-key="@(context.Subscription.Id)" />

<!-- Quota per month per subscription -->
<quota-by-key calls="10000" bandwidth="40000" renewal-period="2629800"
    counter-key="@(context.Subscription.Id)" />
```

**AWS API Gateway**:
- **Usage Plans**: Assign throttle (requests/sec) and quota (requests/month) per API key
- **Stage throttling**: Account-level default 10,000 RPS, burst 5,000

**Cosmos DB RU/s throttling** (storage-level):
- Each container has provisioned RU/s
- Exceeding → `429 Too Many Requests` with `x-ms-retry-after-ms` header
- **Autoscale mode**: Max RU/s set; scales 10%–100% automatically

**FAANG callout**: "For multi-tenant SaaS, I implement throttling at three levels: API gateway (request rate), application logic (tenant-specific quota in Redis/Cosmos), and data layer (Cosmos RU/s per tenant container or DynamoDB table-level capacity). Defense in depth means a misbehaving tenant can't DoS the shared infrastructure."

---

### 12. Publisher-Subscriber

**Problem**: Producer should not know about consumers. Consumers should onboard independently without producer changes.

**Azure Event Grid** (push-based, ideal for lightweight events):
```
Event Source (Blob Storage, Cosmos DB, custom) → Event Grid Topic
                                                         │
                                              ┌──────────┼──────────┐
                                              ▼          ▼          ▼
                                         WebHook    Azure Fn   Service Bus
                                        (HTTP push) (trigger)  (durable delivery)
```

**Azure Service Bus Topics** (pull-based, ideal for guaranteed delivery):
```
Publisher → Service Bus Topic
                  │
         ┌────────┼────────┐
         ▼        ▼        ▼
   Subscription  Sub2     Sub3
   (SQL filter)  (all)    (all)
         │
   Consumer polls → receives matching messages
```

**AWS EventBridge** (rule-based, best for internal AWS events):
```
Event Source → EventBridge Bus
                    │
              Rules matching
                    │
         ┌──────────┼──────────┐
         ▼          ▼          ▼
       Lambda      SQS       SNS → Email/SMS
```

**Decision: Event Grid vs Service Bus Topics vs EventBridge**:

| Criteria | Azure Event Grid | Azure Service Bus Topics | AWS EventBridge |
|----------|-----------------|------------------------|-----------------|
| Delivery | Push (HTTP webhook) | Pull (AMQP/HTTPS) | Push (Lambda, SQS, etc.) |
| Ordering | Not guaranteed | Session-based FIFO | Not guaranteed |
| Retry | Built-in with backoff | Dead-letter after maxDeliveryCount | 24-hour retry with backoff |
| Max message size | 1 MB | 256 KB (Standard), 100 MB (Premium) | 256 KB |
| SQL filtering | No | Yes (rich SQL-like filters) | Pattern matching on JSON fields |
| Best for | Lightweight domain events | Business transactions | AWS service integration |

---

## Pattern Composition Examples

### E-commerce Order Flow
```
Queue-Based Load Leveling (SQS/Service Bus)
    + Competing Consumers (Lambda/Azure Functions scaling)
    + Saga (Step Functions/Durable Functions for order → payment → inventory)
    + Compensating Transaction (refund on inventory failure)
    + Event Sourcing (audit trail of all order state changes)
    + CQRS (fast read model for order status page)
```

### API at Scale
```
Gateway Routing (Front Door / CloudFront)
    + Gateway Aggregation (APIM / API Gateway)
    + Gateway Offloading (JWT validation, rate limiting, caching)
    + Throttling (per-tenant RU/s or usage plans)
    + Circuit Breaker (APIM policy / App Mesh)
    + Retry (SDK-level with jitter)
```

### Multi-Tenant SaaS
```
Deployment Stamps (one stack per tenant tier)
    + Sharding (per-tenant Cosmos DB container or DynamoDB table)
    + Valet Key (direct storage access without app proxy)
    + Bulkhead (separate AKS node pools per tenant class)
    + Throttling (APIM rate limits per subscription key)
    + Federated Identity (Entra ID / Cognito per tenant IdP)
```

### Data Pipeline
```
Event Sourcing (Event Hubs / Kinesis as immutable log)
    + Pipes and Filters (Azure Functions chain / Lambda → Lambda)
    + Claim Check (large payloads in Blob/S3; reference in message)
    + Competing Consumers (parallel processing instances)
    + Materialized View (read-optimized projections built from events)
```

---

## Anti-Patterns to Avoid

> See full catalog: [Azure Cloud Anti-Patterns](https://learn.microsoft.com/en-us/azure/architecture/antipatterns/)

| Anti-Pattern | What Goes Wrong | Correct Pattern |
|-------------|-----------------|-----------------|
| **Chatty I/O** | Too many small network calls; latency multiplies | Gateway Aggregation; batch calls |
| **Busy Database** | App logic in stored procedures; DB becomes bottleneck | Move logic to service layer; CQRS |
| **Monolithic Persistence** | Single DB for all services; tight coupling | Shard per service; polyglot persistence |
| **No Caching** | Every request hits the DB; latency spikes under load | Cache-Aside with TTL |
| **Synchronous calls across services** | Request fan-out causes cascading latency | Choreography or async messaging |
| **Retry storm** | All clients retry simultaneously on failure | Exponential backoff + full jitter |
| **Missing Circuit Breaker** | Slow dependency cascades to all consumers | Circuit Breaker at every external call |
| **Fat message bus** | Sending full objects in events; schema coupling | Claim Check or event notification only (ID + event type) |

---

> **FAANG Interview Framing**: "Cloud design patterns are technology-agnostic — Circuit Breaker, Saga, CQRS exist independently of Azure or AWS. What changes is the implementation: on Azure you use APIM policies and Durable Functions; on AWS you use API Gateway and Step Functions. In an interview I first identify the pattern that solves the problem, then map it to the cloud stack in scope. The pattern decision is more important than the service choice."
