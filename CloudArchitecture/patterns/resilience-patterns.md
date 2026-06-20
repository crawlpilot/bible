# Cloud Resilience Patterns

## Overview
Resilience patterns are the set of design techniques that allow distributed systems to tolerate failures, degrade gracefully, and recover quickly. In cloud systems running at scale, failure is not an exception — it is the steady state. The question is never "will something fail?" but "when it fails, how does the system behave?"

This document covers the core resilience patterns every principal engineer must be able to deploy and reason about.

---

## The Core Failure Modes

| Failure mode | Description | Pattern to apply |
|---|---|---|
| **Transient failure** | Temporary error (network blip, timeout) | Retry with backoff |
| **Persistent failure** | Dependency is down | Circuit Breaker |
| **Cascading failure** | One failing service overwhelms its caller | Circuit Breaker + Bulkhead |
| **Overload** | More requests than capacity can handle | Rate Limiting + Load Shedding |
| **Slow response** | Dependency is slow, not down | Timeout + Fallback |
| **Partial failure** | Some nodes/replicas fail | Health check + auto-replace |
| **Poison pill** | Malformed message crashes consumer | DLQ + skip + retry |
| **AZ failure** | Entire availability zone unavailable | Multi-AZ + cross-AZ routing |
| **Region failure** | Entire region unavailable | Multi-Region + failover |

---

## Pattern 1: Retry with Exponential Backoff and Jitter

**The most fundamental resilience pattern.** Transient errors resolve themselves if given time.

### Naive retry (wrong)
```python
for attempt in range(3):
    try:
        result = call_service()
        break
    except TransientError:
        time.sleep(1)  # constant delay — all retriers hammer simultaneously
```

### Exponential backoff with full jitter (correct)
```python
import random, time

def call_with_retry(func, max_attempts=5, base_delay=0.1, max_delay=30):
    for attempt in range(max_attempts):
        try:
            return func()
        except TransientError as e:
            if attempt == max_attempts - 1:
                raise
            # Exponential backoff: 0.1s, 0.2s, 0.4s, 0.8s, 1.6s...
            # Full jitter: random(0, min(cap, base * 2^attempt))
            delay = random.uniform(0, min(max_delay, base_delay * (2 ** attempt)))
            time.sleep(delay)
```

**Full jitter** spreads retry storms. Without jitter, all clients back off for exactly the same duration and slam the server simultaneously at the retry moment. With jitter, they spread their retries across the backoff window.

**AWS SDK**: all AWS SDKs implement exponential backoff with jitter by default. `RetryConfig` controls max attempts and base delay.

**Idempotency requirement**: retries only work correctly if the operation is idempotent. Non-idempotent operations (e.g., payment charge) must use an idempotency key so duplicates are detected and deduplicated.

---

## Pattern 2: Circuit Breaker

Prevents cascading failures by stopping requests to a failing dependency, giving it time to recover.

### State machine
```
CLOSED (normal operation)
  → requests pass through; failures counted
  → if failures exceed threshold: transition to OPEN

OPEN (dependency failing)
  → all requests fail immediately (no attempt made)
  → no load sent to failing dependency
  → after cooldown period: transition to HALF-OPEN

HALF-OPEN (probing recovery)
  → one probe request allowed through
  → if probe succeeds: transition to CLOSED
  → if probe fails: back to OPEN
```

### Implementation (Python example)
```python
from pybreaker import CircuitBreaker

# Opens after 5 failures within 60 seconds; stays open for 30 seconds
payment_breaker = CircuitBreaker(fail_max=5, reset_timeout=30)

@payment_breaker
def charge_payment(order_id, amount):
    return payment_service.charge(order_id, amount)
```

### AWS implementations
- **Application Load Balancer**: automatic deregistration of unhealthy targets — effectively a circuit breaker at the routing level
- **API Gateway**: timeout + retry configuration prevents infinite waits
- **AWS SDK + Resilience4j / Hystrix** (Java): application-level circuit breaker
- **Istio DestinationRule**: service mesh circuit breaking (outlier detection)

```yaml
# Istio circuit breaker (outlier detection)
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
spec:
  trafficPolicy:
    outlierDetection:
      consecutiveErrors: 5           # open after 5 consecutive 5xx
      interval: 30s                  # evaluation window
      baseEjectionTime: 30s          # time to eject (OPEN duration)
      maxEjectionPercent: 50         # eject at most 50% of endpoints
```

---

## Pattern 3: Bulkhead

Isolates failures in one part of the system from affecting the rest. Named after ship bulkheads that prevent a single hull breach from sinking the entire ship.

### Thread Pool Bulkhead
Assign a dedicated thread pool per downstream dependency. If dependency A is slow, its thread pool fills, but dependency B's thread pool is unaffected.

```java
// Resilience4j ThreadPoolBulkhead
ThreadPoolBulkheadConfig config = ThreadPoolBulkheadConfig.custom()
    .maxThreadPoolSize(10)           // max concurrent calls to this dependency
    .coreThreadPoolSize(5)
    .queueCapacity(100)              // queue for waiting calls
    .build();
ThreadPoolBulkhead paymentBulkhead = ThreadPoolBulkhead.of("payments", config);
```

### Semaphore Bulkhead
Limit concurrent calls to a dependency without a separate thread pool. Simpler; less overhead.

### Lambda Concurrency Bulkhead
Set reserved concurrency per Lambda function. A burst of background jobs can't consume all Lambda concurrency and starve the user-facing API.

```
User-facing API Lambda: reserved concurrency = 500
Background job Lambda: reserved concurrency = 100
Remaining: 400 for other functions (including new functions without reserved concurrency)
```

### ECS/EKS Resource Quota Bulkhead
Kubernetes Resource Quotas limit the maximum CPU and memory a namespace can consume — one team's runaway deployment can't starve another team's pods.

---

## Pattern 4: Timeout

Every call to an external dependency must have a timeout. Without timeouts, slow dependencies cause thread/connection pool exhaustion.

**Timeout hierarchy** (each layer must be shorter than the layer above):
```
User's HTTP client: 30s timeout
  → API Gateway: 29s timeout (hard limit)
    → Application service: 5s timeout
      → Database call: 2s timeout
        → Redis call: 100ms timeout
```

**Too long**: threads blocked waiting; connection pools exhausted; cascading slowness
**Too short**: excessive timeouts on transient slowness; retries amplify load

**Timeout budget (deadline propagation)**: pass the remaining time budget down the call chain:
```python
# gRPC deadline propagation
context.set_deadline(time.time() + 5.0)  # 5 second total budget
# All downstream calls use context; if budget exhausted, all cancel
```

AWS API Gateway has a hard 29-second timeout. Lambda has a configurable 15-minute timeout. Set both to match your SLA, not the maximums.

---

## Pattern 5: Fallback

When a dependency fails (circuit open, timeout, error), return a degraded but acceptable response instead of failing completely.

| Fallback type | Description | Example |
|---|---|---|
| **Static default** | Return a pre-defined safe response | Return empty recommendation list if ML service down |
| **Cached response** | Return the last known good response | Return stale product prices from cache |
| **Degraded functionality** | Return partial response | Show checkout without personalised recommendations |
| **Queue for later** | Accept the request and process asynchronously | Accept order even if inventory service down; reconcile later |

```python
@payment_breaker
def get_personalised_recommendations(user_id):
    try:
        return ml_service.get_recommendations(user_id)
    except (CircuitBreakerOpen, ServiceTimeout):
        # Fallback: return top-20 popular items (cached; not personalised)
        return cache.get("popular_items:top20") or []
```

**Never return errors when a fallback is available.** Users tolerate degraded functionality; they don't tolerate crashes.

---

## Pattern 6: Rate Limiting and Load Shedding

Protect your service from being overwhelmed by excessive inbound traffic.

### Token Bucket Algorithm
```
Bucket capacity: 1000 tokens
Refill rate: 100 tokens/second
Each request consumes 1 token
If bucket empty: reject request with 429 Too Many Requests
```

### API Gateway Rate Limiting
```
Account-level: 10,000 RPS + 5,000 burst
Usage plan (per API key): 100 RPS + 200 burst
Method-level: 50 RPS for /checkout, 500 RPS for /search
```

### Load Shedding
When under load, shed lower-priority requests first:
```python
async def handle_request(request, ctx):
    queue_depth = get_queue_depth()
    
    if queue_depth > HIGH_THRESHOLD:
        if request.priority == Priority.LOW:  # batch jobs, analytics
            raise TooManyRequestsError(retry_after=30)
    
    if queue_depth > CRITICAL_THRESHOLD:
        if request.priority != Priority.CRITICAL:  # only payments, auth
            raise TooManyRequestsError(retry_after=60)
    
    return process_request(request)
```

**Fail fast under load**: returning 429 immediately is better than queuing and returning 504 after 30 seconds. The client can retry; a 30-second wait frustrates users and blocks threads.

---

## Pattern 7: Health Checks and Auto-Recovery

Systems must expose health state and automatically remove unhealthy components.

### Health Check Endpoints
```python
@app.get("/health/live")   # Is the process alive? (Kubernetes liveness probe)
async def liveness():
    return {"status": "ok"}  # Always return 200 unless process should restart

@app.get("/health/ready")  # Can this instance serve traffic? (readiness probe)
async def readiness():
    if not database.is_connected():
        raise HTTPException(503, "Database not available")
    if cache_hit_rate() < 0.5:
        raise HTTPException(503, "Cache miss rate too high")
    return {"status": "ready"}

@app.get("/health/startup")  # Has the app finished starting up? (startup probe)
async def startup():
    if not app.is_fully_initialised():
        raise HTTPException(503, "Still starting")
    return {"status": "started"}
```

**Kubernetes probes**: `livenessProbe` (fail = restart pod), `readinessProbe` (fail = remove from Service endpoints, stop receiving traffic), `startupProbe` (fail = don't start other probes yet).

### Auto-Recovery Patterns
- **ASG health check replacement**: EC2 fails health check → ASG terminates and launches replacement
- **ECS task restart**: ECS service restarts failed tasks automatically
- **Kubernetes CrashLoopBackoff**: pod crashes → Kubernetes restarts with exponential delay
- **RDS failover**: primary fails → Aurora automatically promotes read replica (typically <30s)
- **ElastiCache failover**: primary node failure → automatic promotion of replica

---

## Pattern 8: Multi-AZ and Multi-Region

### Multi-AZ (default for all production workloads)
```
Availability Zone A: EC2/ECS, RDS primary, ElastiCache primary
Availability Zone B: EC2/ECS, RDS standby (sync replication), ElastiCache replica
Availability Zone C: EC2/ECS, RDS read replica, ElastiCache replica

ALB spans all three AZs; routes to healthy targets only
```

RDS Multi-AZ failover: 30–120 seconds (DNS update + replica promotion). Minimise by using **Aurora** (sub-30s failover) or **Route 53 health check** aware DNS.

### Multi-Region (for highest availability)
```
Active-Active: both regions serve traffic simultaneously
  Route53 → latency routing → Region A (us-east-1) + Region B (eu-west-1)
  DynamoDB Global Tables: multi-master replication between regions (< 1s lag)

Active-Passive: one region active; other on standby
  Route53 → health check → primary region; failover to secondary on health check failure
  RDS Global Database: read replica in secondary; promote on failover (< 1 min)
```

**RPO and RTO targets** determine architecture:
| Target | Architecture |
|---|---|
| RPO=0, RTO<1min | Active-Active multi-region (DynamoDB Global Tables, Aurora Global) |
| RPO<15min, RTO<15min | Active-Passive with warm standby |
| RPO<1hr, RTO<1hr | Active-Passive with pilot light |
| RPO<24hr, RTO<24hr | Backup and restore |

---

## Chaos Engineering

Proactively inject failures to validate resilience:

| Tool | What it does |
|---|---|
| **AWS Fault Injection Simulator (FIS)** | Terminate EC2 instances, inject CPU stress, delay network, fail RDS |
| **Chaos Monkey** (Netflix) | Randomly terminates instances in production |
| **Gremlin** | Managed chaos engineering platform |
| **Litmus** (Kubernetes) | Kubernetes-native chaos experiments |

**Game Day pattern**: scheduled, coordinated chaos experiments with full team awareness. Document hypothesis ("if we kill the payment service, orders should queue and process when service recovers"), run experiment, measure, improve.

---

## Resilience Trade-offs

| Pattern | Complexity | Benefit | Cost |
|---|---|---|---|
| Retry + backoff | Low | Handles transient failures | Amplifies load on already-struggling service |
| Circuit Breaker | Medium | Prevents cascading failure | False positives; open state needs tuning |
| Bulkhead | Medium | Failure isolation | More resource allocation; overhead |
| Timeout | Low | Prevents thread exhaustion | May cut legitimate slow requests |
| Rate Limiting | Medium | Protects from overload | Legitimate traffic rejected during spikes |
| Multi-AZ | Low | AZ failure tolerance | ~2× cost for stateful resources |
| Multi-Region | High | Region failure tolerance | 2–4× cost; replication lag; global coordination |

---

## Best Practices

1. **Set timeouts everywhere** — every external call; every database query; every message receive
2. **Retry with full jitter** — never constant delay; never retry infinite times
3. **Circuit breakers on all external dependencies** — not just databases; also HTTP calls, message queue connections
4. **Test failure scenarios in staging** — use FIS; don't discover circuit breaker bugs in production
5. **Design graceful degradation** — define which features degrade (recommendations) vs which never degrade (checkout)
6. **Multi-AZ by default** — RDS Multi-AZ, ALB spanning 3 AZs, ECS tasks in 3 AZs; no exceptions
7. **Health checks at every layer** — liveness + readiness probes for all containers; ALB health checks for all targets
8. **Alert on circuit open events** — a circuit breaking is a signal the dependency is struggling; don't wait for users to report issues
9. **Idempotency before retry** — retries are only safe if the operation is idempotent; implement deduplication first
10. **Define RTO/RPO explicitly** — "we need 99.99% availability" translates to specific architecture decisions; without targets, you can't choose the right pattern

---

## FAANG Interview Points

**"How do you prevent a slow database from taking down your entire service?"**: Timeout on every DB query (2s maximum). Circuit Breaker opens after 5 consecutive timeouts — rejects requests immediately. Thread pool bulkhead: DB calls in a dedicated pool of 20 threads; other operations unaffected by DB pool exhaustion. Fallback: read from Redis cache if circuit open. HPA scales compute; circuit breaker protects DB.

**"Design a system that survives AZ failure"**: ALB + Multi-AZ ECS/EKS (tasks spread across 3 AZs using pod topology spread constraints or ECS placement spread). RDS Multi-AZ (Aurora Serverless for sub-30s failover). ElastiCache Multi-AZ. Route53 health-check-aware routing. Test with FIS `aws:ec2:terminate-instances` in one AZ. RTO target: < 60 seconds.

**"What's the difference between circuit breaker and retry?"**: Retry is for transient failures — try again, it might work. Circuit breaker is for persistent failures — stop trying, you're making it worse. Use retry first; if the circuit opens (too many retries failing), the circuit breaker kicks in and stops all requests for a cooldown period, giving the dependency time to recover without being hammered.
