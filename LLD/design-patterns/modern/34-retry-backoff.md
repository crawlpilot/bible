# 34. Retry with Exponential Backoff + Jitter
**Category**: Modern / Enterprise  
**GoF**: No (AWS best practice, "Designing Cloud-Native Applications")  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Retry failed transient operations using exponentially increasing delays with random jitter — recovering from temporary failures without creating a retry storm that further overwhelms a struggling dependency.

---

## Problem It Solves

A microservice calls DynamoDB. A transient throttle (`ProvisionedThroughputExceededException`) hits 3 out of 1,000 concurrent requests. Without retry, those 3 requests fail permanently. With naive retry (retry immediately), all 3 clients fire again within milliseconds — along with all other throttled clients — creating a thundering herd that makes the throttle worse. Exponential backoff with jitter spreads retries randomly across a time window, reducing burst retry load by ~70% while still recovering from transient errors within seconds.

## Structure (Participants)

```
  Client
    │
    ▼
  RetryPolicy
  ┌────────────────────────────────────────────────────────┐
  │  attempt 1 → fail → wait (base * 2^0) + jitter(rand)  │
  │  attempt 2 → fail → wait (base * 2^1) + jitter(rand)  │
  │  attempt 3 → fail → wait (base * 2^2) + jitter(rand)  │
  │  attempt 4 → success                                   │
  │                                                        │
  │  if maxAttempts exceeded → throw RetryExhaustedException│
  └────────────────────────────────────────────────────────┘
    │
    ▼
  Downstream Service (DynamoDB / external API / message broker)
```

**Jitter variants (AWS recommendation)**:
- **Full jitter**: `sleep = random(0, base * 2^attempt)` — lowest contention, best for high-concurrency
- **Equal jitter**: `sleep = (cap/2) + random(0, cap/2)` — balanced
- **Decorrelated jitter**: `sleep = min(cap, random(base, prev_sleep * 3))` — avoids correlated waves

Key participants:
- **RetryPolicy**: encapsulates max attempts, backoff formula, jitter strategy, retryable exception set
- **RetryExecutor**: executes the operation and applies the retry loop
- **Client**: the calling code — unaware of retry internals
- **Operation**: the callable being retried (a network call, DB write, API call)

---

## Real-World Use Case: DynamoDB Write with Retry

### Implementation

```java
// Configurable retry policy
public record RetryConfig(
    int maxAttempts,
    Duration baseDelay,
    Duration maxDelay,
    double multiplier,
    JitterStrategy jitter,
    Set<Class<? extends Throwable>> retryableExceptions
) {
    public static RetryConfig dynamoDefault() {
        return new RetryConfig(
            4,
            Duration.ofMillis(100),
            Duration.ofSeconds(20),
            2.0,
            JitterStrategy.FULL,
            Set.of(
                ProvisionedThroughputExceededException.class,
                RequestLimitExceededException.class,
                ServiceUnavailableException.class
            )
        );
    }
}

public enum JitterStrategy { NONE, FULL, EQUAL, DECORRELATED }

public class RetryExecutor {
    private final RetryConfig config;
    private final MeterRegistry metrics;
    private final Random random = new Random();

    public RetryExecutor(RetryConfig config, MeterRegistry metrics) {
        this.config = config;
        this.metrics = metrics;
    }

    public <T> T execute(String operationName, Callable<T> operation) throws Exception {
        int attempt = 0;
        long prevSleepMs = config.baseDelay().toMillis();
        Exception lastException = null;

        while (attempt < config.maxAttempts()) {
            try {
                T result = operation.call();
                if (attempt > 0) {
                    metrics.counter("retry.success",
                        "operation", operationName, "attempts", String.valueOf(attempt + 1)).increment();
                }
                return result;
            } catch (Exception e) {
                if (!isRetryable(e)) {
                    throw e;  // non-retryable: fail immediately
                }

                lastException = e;
                attempt++;

                if (attempt >= config.maxAttempts()) break;

                long sleepMs = computeDelay(attempt, prevSleepMs);
                prevSleepMs = sleepMs;

                metrics.counter("retry.attempt",
                    "operation", operationName,
                    "attempt", String.valueOf(attempt),
                    "exception", e.getClass().getSimpleName()).increment();

                log.warn("Retry {}/{} for '{}' after {}ms — {}: {}",
                    attempt, config.maxAttempts(), operationName, sleepMs,
                    e.getClass().getSimpleName(), e.getMessage());

                Thread.sleep(sleepMs);
            }
        }

        metrics.counter("retry.exhausted", "operation", operationName).increment();
        throw new RetryExhaustedException(
            operationName + " failed after " + config.maxAttempts() + " attempts", lastException
        );
    }

    private long computeDelay(int attempt, long prevSleepMs) {
        long base = config.baseDelay().toMillis();
        long cap = config.maxDelay().toMillis();
        long exponential = (long) Math.min(cap, base * Math.pow(config.multiplier(), attempt - 1));

        return switch (config.jitter()) {
            case NONE -> exponential;
            case FULL -> (long) (random.nextDouble() * exponential);        // [0, exp)
            case EQUAL -> (exponential / 2) + (long) (random.nextDouble() * (exponential / 2));
            case DECORRELATED -> Math.min(cap, base + (long) (random.nextDouble() * (prevSleepMs * 3 - base)));
        };
    }

    private boolean isRetryable(Exception e) {
        return config.retryableExceptions().stream().anyMatch(cls -> cls.isInstance(e));
    }
}

// Repository using retry
@Repository
public class OrderRepository {
    private final DynamoDB dynamoDB;
    private final RetryExecutor retry;

    public OrderRepository(DynamoDB dynamoDB, RetryExecutor retry) {
        this.dynamoDB = dynamoDB;
        this.retry = retry;
    }

    public void save(Order order) {
        try {
            retry.execute("order.save", () -> {
                dynamoDB.putItem(new PutItemRequest()
                    .withTableName("orders")
                    .withItem(orderToItem(order))
                    .withConditionExpression("attribute_not_exists(pk)"));  // idempotency guard
                return null;
            });
        } catch (RetryExhaustedException e) {
            throw new OrderPersistenceException("Failed to save order " + order.id(), e);
        } catch (ConditionalCheckFailedException e) {
            throw new DuplicateOrderException(order.id());  // non-retryable — already exists
        }
    }
}

// Spring integration via @Retryable (declarative alternative)
@Service
public class PaymentService {
    @Retryable(
        retryFor = { HttpServerErrorException.class, ResourceAccessException.class },
        maxAttempts = 3,
        backoff = @Backoff(delay = 200, multiplier = 2, random = true, maxDelay = 5000)
    )
    public PaymentResult charge(ChargeRequest request) {
        return httpClient.post("/charge", request, PaymentResult.class);
    }

    @Recover
    public PaymentResult chargeRecovery(Exception e, ChargeRequest request) {
        // called after all retries exhausted
        auditLog.record("payment_retry_exhausted", request.orderId(), e.getMessage());
        throw new PaymentFailedException("Payment unavailable after retries", e);
    }
}
```

### How It Works (walkthrough)

1. `order.save()` → DynamoDB throttles → `ProvisionedThroughputExceededException` thrown
2. Attempt 1 failed. `isRetryable()` → true. Compute delay: `full_jitter(100ms * 2^0)` → random(0, 100) → e.g. 47ms
3. Sleep 47ms. Attempt 2 → throttled again. Delay: `full_jitter(100ms * 2^1)` → random(0, 200) → e.g. 183ms
4. Sleep 183ms. Attempt 3 → throttled. Delay: `full_jitter(100ms * 2^2)` → random(0, 400) → e.g. 271ms
5. Sleep 271ms. Attempt 4 → DynamoDB recovered → write succeeds
6. `retry.success` counter incremented with `attempts=4`
7. Total elapsed: ~500ms — transparent to caller

**Idempotency is mandatory**: since the operation may be retried, it must be safe to execute multiple times. Use condition expressions (DynamoDB), idempotency keys (Stripe), or upsert semantics.

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `RetryExecutor` handles retry logic; repositories handle data access |
| Open/Closed | ✅ | New jitter strategies added to `JitterStrategy` enum without changing executor |
| Liskov Substitution | ✅ | `RetryExecutor` wraps any `Callable<T>` |
| Interface Segregation | ✅ | `execute(name, Callable<T>)` — minimal interface |
| Dependency Inversion | ✅ | `RetryConfig` is injected; `RetryExecutor` doesn't know about DynamoDB |

---

## When to Use

- Calling external APIs or services that can experience transient failures (throttling, 503, network blips)
- Cloud SDK calls (DynamoDB, S3, SQS, GCS) that have built-in throttling under bursty load
- Message publishing to brokers with backpressure (Kafka producer retries)
- Any idempotent operation — retry is safe only when the operation can be applied more than once

## When NOT to Use

- Non-idempotent operations without explicit deduplication (charging a credit card without idempotency key will double-charge)
- Non-retryable errors (4xx client errors like 400 Bad Request, 404 Not Found, 409 Conflict — retrying won't help)
- When the timeout budget is already tight — retrying inside a synchronous request can push end-to-end latency past the SLA
- Downstream is consistently failing (not transiently) — use Circuit Breaker to fail fast instead

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Recovers from transient failures automatically without user-visible errors | Increases tail latency — p99 latency for a retried call is higher than without retry |
| Full jitter distributes retry load, preventing thundering herd | Requires idempotency — non-idempotent operations risk duplicate side effects |
| Configurable per-operation — DynamoDB vs payment API can have different policies | Error swallowing risk — if retry succeeds, the initial failure may not be investigated |

---

**FAANG interview application**: "Exponential backoff with full jitter is the AWS-recommended retry strategy for any distributed call. The key insight is that naive backoff without jitter causes retry waves — all throttled clients wake up at the same time and hammer the service again. Full jitter randomizes the sleep window to [0, cap], spreading load. The two things you must always combine with retry: (1) idempotency keys so duplicate retries don't create duplicate records; (2) a circuit breaker so you don't retry forever when the service is down. At Google scale, even a 1% retry rate on 1M QPS is 10K extra RPS — jitter is not optional."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Circuit Breaker](29-circuit-breaker.md) | Pair with Retry: CB detects sustained failure and stops retrying; Retry handles transient failures |
| [Bulkhead](33-bulkhead.md) | Retries consume concurrency permits — size Bulkhead to account for retry amplification |
| [Outbox Pattern](28-outbox-pattern.md) | Outbox uses retry internally to guarantee event delivery |
| [Idempotent Receiver](https://www.enterpriseintegrationpatterns.com/) | Prerequisite for safe retry — receiver must handle duplicate messages gracefully |
