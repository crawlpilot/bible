# 33. Bulkhead
**Category**: Modern / Enterprise  
**GoF**: No (Nygard 2007, "Release It!")  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Isolate components into separate thread pools (or semaphore slots) so that a slow or failing dependency can only exhaust its own allocated resources — not shared resources used by other features.

---

## Problem It Solves

The checkout service shares a single thread pool of 100 threads across all downstream calls: payment, inventory, shipping, and loyalty. When the payment service degrades to 30-second timeouts, 90 threads pile up waiting for payment responses — leaving only 10 threads for all other operations. Inventory lookups and shipping estimates start timing out too, even though those services are healthy. One slow dependency brings down the entire application.

Bulkhead allocates a dedicated thread pool (or semaphore) to each downstream dependency. The payment pool has 20 threads; if all 20 are blocked, only payment calls fail fast — inventory and shipping continue operating normally.

## Structure (Participants)

```
  CheckoutService (inbound thread pool: 200 threads)
        │
        ├─── PaymentBulkhead        (pool: 20 threads, queue: 10)
        │         └──► PaymentService
        │
        ├─── InventoryBulkhead      (pool: 30 threads, queue: 20)
        │         └──► InventoryService
        │
        ├─── ShippingBulkhead       (pool: 15 threads, queue: 5)
        │         └──► ShippingService
        │
        └─── LoyaltyBulkhead        (pool: 10 threads, queue: 5)  ← optional/non-critical
                  └──► LoyaltyService
```

**Payment degrades → 20 threads exhausted → PaymentBulkhead rejects with BulkheadFullException**  
Inventory / Shipping threads unaffected — they still operate normally.

Key participants:
- **Bulkhead** (`PaymentBulkhead`): thread pool or semaphore with fixed capacity per dependency
- **Client** (`CheckoutService`): delegates calls through the bulkhead
- **Real Service**: the downstream dependency
- **Fallback**: optional degraded response when the bulkhead is full

Two implementation styles:
- **Thread-pool isolation**: each dependency gets its own thread pool (Hystrix/Resilience4j `THREADPOOL` mode) — full isolation, higher overhead
- **Semaphore isolation**: limits concurrent calls using a `Semaphore` — lower overhead, but caller thread is still blocked

---

## Real-World Use Case: Checkout Service Isolation

### Implementation (Semaphore-based Bulkhead)

```java
// Bulkhead configuration per downstream dependency
public record BulkheadConfig(
    int maxConcurrentCalls,   // semaphore permits
    int maxWaitDuration,      // ms to wait for a permit before rejecting
    String name
) {}

public class Bulkhead {
    private final String name;
    private final Semaphore semaphore;
    private final long maxWaitMs;
    private final MeterRegistry metrics;

    public Bulkhead(BulkheadConfig config, MeterRegistry metrics) {
        this.name = config.name();
        this.semaphore = new Semaphore(config.maxConcurrentCalls(), true);
        this.maxWaitMs = config.maxWaitDuration();
        this.metrics = metrics;
    }

    public <T> T execute(Callable<T> operation) throws Exception {
        boolean acquired = semaphore.tryAcquire(maxWaitMs, TimeUnit.MILLISECONDS);
        if (!acquired) {
            metrics.counter("bulkhead.rejected", "name", name).increment();
            throw new BulkheadFullException(
                name + " bulkhead full (" + semaphore.availablePermits() + " permits used)"
            );
        }
        metrics.gauge("bulkhead.available_permits", semaphore.availablePermits());
        try {
            return operation.call();
        } finally {
            semaphore.release();
        }
    }

    public int availablePermits() { return semaphore.availablePermits(); }
}

// Service client with bulkhead + circuit breaker
public class PaymentServiceClient {
    private final PaymentServiceStub stub;
    private final Bulkhead bulkhead;
    private final CircuitBreaker circuitBreaker;

    public PaymentResult charge(Money amount, PaymentMethod method, String orderId) {
        try {
            return bulkhead.execute(
                () -> circuitBreaker.execute(
                    () -> stub.charge(amount, method, orderId)
                )
            );
        } catch (BulkheadFullException e) {
            // payment service overloaded — fail fast, do not block checkout
            throw new ServiceUnavailableException("Payment service at capacity", e);
        } catch (CircuitOpenException e) {
            throw new ServiceUnavailableException("Payment service unavailable", e);
        }
    }
}

// Thread-pool bulkhead (stronger isolation, Hystrix-style)
public class ThreadPoolBulkhead {
    private final String name;
    private final ExecutorService pool;
    private final int queueSize;

    public ThreadPoolBulkhead(String name, int corePoolSize, int queueSize) {
        this.name = name;
        this.queueSize = queueSize;
        BlockingQueue<Runnable> queue = new ArrayBlockingQueue<>(queueSize);
        this.pool = new ThreadPoolExecutor(
            corePoolSize, corePoolSize, 0L, TimeUnit.MILLISECONDS,
            queue,
            new ThreadFactory() {
                private final AtomicInteger count = new AtomicInteger();
                public Thread newThread(Runnable r) {
                    return new Thread(r, name + "-" + count.incrementAndGet());
                }
            },
            new ThreadPoolExecutor.AbortPolicy()  // reject when queue full
        );
    }

    public <T> Future<T> submit(Callable<T> operation) {
        try {
            return pool.submit(operation);
        } catch (RejectedExecutionException e) {
            throw new BulkheadFullException(name + " thread pool exhausted");
        }
    }
}

// Wiring in Spring Boot application context
@Configuration
public class BulkheadConfig {
    @Bean
    public Bulkhead paymentBulkhead(MeterRegistry registry) {
        return new Bulkhead(
            new BulkheadConfig(20, 50, "payment-service"),  // 20 permits, wait 50ms
            registry
        );
    }

    @Bean
    public Bulkhead inventoryBulkhead(MeterRegistry registry) {
        return new Bulkhead(
            new BulkheadConfig(30, 100, "inventory-service"),
            registry
        );
    }
}
```

### How It Works (walkthrough)

1. Payment service starts degrading — calls take 30s instead of 200ms
2. Checkout threads calling payment acquire bulkhead permits; 20 permits consumed in 20 concurrent calls
3. 21st call arrives: `tryAcquire(50ms)` waits 50ms — no permit released — throws `BulkheadFullException`
4. Checkout handles: returns "payment unavailable, try again" — no thread blocked
5. Inventory and shipping bulkheads are unaffected — their permits never consumed by payment failures
6. Monitoring: `bulkhead.rejected` counter spikes → alert fires → on-call investigates payment

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Bulkhead manages concurrency limits; service client handles business logic |
| Open/Closed | ✅ | New downstream dependency gets its own `Bulkhead` instance — no existing code changes |
| Liskov Substitution | ✅ | `Bulkhead` wraps any `Callable<T>` — transparent to callers |
| Interface Segregation | ✅ | `execute(Callable<T>)` — minimal interface |
| Dependency Inversion | ✅ | Service clients depend on `Bulkhead` abstraction injected at construction |

---

## When to Use

- A service calls multiple downstream dependencies with different reliability profiles
- A degraded non-critical dependency (loyalty points, recommendations) must not affect critical paths (payment, inventory)
- Thread exhaustion from one service is causing cascading failures to unrelated services
- Services with strict SLA tiers (premium vs standard) needing resource isolation

## When NOT to Use

- Only one downstream dependency — bulkhead adds complexity without isolation benefit
- All dependencies are equally critical with the same SLA tier
- Very low throughput — overhead of semaphore/pool management is not justified
- Prefer rate limiting at the API gateway level for external traffic

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Fault isolation — a slow dependency can only consume its own resource allocation | Capacity planning complexity — must size each bulkhead pool correctly (under-provisioned = unnecessary rejections; over-provisioned = wastes threads) |
| Non-critical features degrade gracefully without affecting critical paths | Thread-pool isolation (vs semaphore) doubles thread count — higher memory overhead |
| Visible failure — `BulkheadFullException` is explicit; easy to alert on | Per-dependency configuration — more parameters to tune per service |

---

**FAANG interview application**: "Bulkhead is the pattern that prevents a slow payment service from killing your entire checkout. Netflix Hystrix and Resilience4j both implement it — thread-pool isolation for strong fault containment, semaphore isolation for lower overhead. The key sizing question: how many concurrent calls does this dependency normally see at p99 load? Start there and add 20% headroom. In a microservices architecture, always pair Bulkhead with Circuit Breaker — Bulkhead limits concurrent load, Circuit Breaker stops retrying when the service is clearly down."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Circuit Breaker](29-circuit-breaker.md) | Complementary — pair Bulkhead (resource isolation) with Circuit Breaker (failure detection); Resilience4j uses both together |
| [Retry with Backoff](34-retry-backoff.md) | Retries consume bulkhead permits — ensure retry count × concurrency doesn't exceed the pool |
| [Proxy](../structural/12-proxy.md) | Bulkhead is typically implemented as a Proxy around the service client |
