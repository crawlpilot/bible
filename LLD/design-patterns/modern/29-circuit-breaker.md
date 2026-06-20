# 29. Circuit Breaker
**Category**: Modern / Enterprise  
**GoF**: No (Nygard 2007, "Release It!")  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Wrap calls to a remote service in a circuit breaker object that monitors for failures. When failures exceed a threshold, the circuit "opens" and fails fast without calling the service — allowing it to recover.

---

## Problem It Solves

The checkout service calls the payment service. When the payment service degrades (high latency, 50% errors), every checkout request blocks for 30 seconds waiting for a timeout — threads are exhausted, the checkout service cascades into failure. Without Circuit Breaker, one failing downstream kills the entire upstream. Circuit Breaker detects the failure, opens the circuit, and fails fast (in ~1ms vs 30s) — shedding load from the failing service and freeing upstream threads.

## Structure (Participants)

```
   CheckoutService
        │
        │  paymentService.charge(...)
        ▼
  PaymentCircuitBreaker
  ┌──────────────────────────────────────────────┐
  │                                              │
  │  CLOSED ──(5 failures/10s)──► OPEN           │
  │     └── pass through, count failures         │
  │                                              │
  │  OPEN ──(30s timeout)──► HALF_OPEN           │
  │     └── fail fast (throw immediately)         │
  │                                              │
  │  HALF_OPEN ──(1 probe success)──► CLOSED     │
  │          └──(probe failure)──► OPEN           │
  │     └── allow 1 probe request                 │
  └──────────────────────────────────────────────┘
        │
        ▼
  PaymentService (real)
```

Key participants:
- **Circuit Breaker** (`PaymentCircuitBreaker`): wraps the downstream call; tracks failure rate; transitions between states
- **States**: CLOSED (normal), OPEN (fail fast), HALF_OPEN (probing)
- **Client** (`CheckoutService`): calls through the circuit breaker; gets either a response or a fast `CircuitOpenException`
- **Real Service** (`PaymentService`): the downstream dependency being protected

---

## Real-World Use Case: Payment Service Circuit Breaker

The checkout service calls the payment service. Payment service SLA: <500ms p99. Circuit breaker config: open if 5 failures in a 10-second window; cool-down 30 seconds; probe 1 request in half-open state.

### Implementation

```java
// Circuit breaker states
public enum CircuitState { CLOSED, OPEN, HALF_OPEN }

// Configuration
public record CircuitBreakerConfig(
    int failureThreshold,       // open after this many failures
    int successThreshold,       // close after this many successes in HALF_OPEN
    Duration openTimeout,       // how long to stay OPEN before probing
    Duration callTimeout,       // max time to wait for a call
    int windowSize              // sliding window for failure counting
) {}

// Thread-safe circuit breaker implementation
public class CircuitBreaker {
    private final String name;
    private final CircuitBreakerConfig config;
    private volatile CircuitState state = CircuitState.CLOSED;
    private final AtomicInteger failureCount = new AtomicInteger(0);
    private final AtomicInteger successCount = new AtomicInteger(0);
    private volatile Instant openedAt;
    private final Deque<Boolean> callWindow = new ConcurrentLinkedDeque<>();  // sliding window
    private final Object stateLock = new Object();
    private final MeterRegistry metrics;

    public CircuitBreaker(String name, CircuitBreakerConfig config, MeterRegistry metrics) {
        this.name = name;
        this.config = config;
        this.metrics = metrics;
    }

    public <T> T execute(Callable<T> operation) throws Exception {
        switch (state) {
            case CLOSED -> {
                return executeWithTracking(operation);
            }
            case OPEN -> {
                if (shouldProbe()) {
                    transitionTo(CircuitState.HALF_OPEN);
                    return executeProbe(operation);
                }
                metrics.counter("circuit.breaker.rejected", "name", name).increment();
                throw new CircuitOpenException(name + " circuit is OPEN — failing fast");
            }
            case HALF_OPEN -> {
                return executeProbe(operation);
            }
        }
        throw new IllegalStateException("Unknown state: " + state);
    }

    private <T> T executeWithTracking(Callable<T> operation) throws Exception {
        try {
            T result = callWithTimeout(operation);
            onSuccess();
            return result;
        } catch (Exception e) {
            onFailure();
            throw e;
        }
    }

    private <T> T executeProbe(Callable<T> operation) throws Exception {
        try {
            T result = callWithTimeout(operation);
            onProbeSuccess();
            return result;
        } catch (Exception e) {
            onProbeFailure();
            throw e;
        }
    }

    private <T> T callWithTimeout(Callable<T> operation) throws Exception {
        // Execute with configured timeout
        Future<T> future = executorService.submit(operation);
        try {
            return future.get(config.callTimeout().toMillis(), TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            future.cancel(true);
            throw new CallTimeoutException(name + " call timed out after " + config.callTimeout());
        }
    }

    private void onSuccess() {
        recordCall(true);
        failureCount.set(0);
    }

    private void onFailure() {
        recordCall(false);
        int failures = failureCount.incrementAndGet();
        if (failures >= config.failureThreshold() && state == CircuitState.CLOSED) {
            transitionTo(CircuitState.OPEN);
        }
    }

    private void onProbeSuccess() {
        int successes = successCount.incrementAndGet();
        if (successes >= config.successThreshold()) {
            transitionTo(CircuitState.CLOSED);
        }
    }

    private void onProbeFailure() {
        successCount.set(0);
        transitionTo(CircuitState.OPEN);
    }

    private boolean shouldProbe() {
        return openedAt != null && Instant.now().isAfter(openedAt.plus(config.openTimeout()));
    }

    private void transitionTo(CircuitState newState) {
        synchronized (stateLock) {
            CircuitState previous = this.state;
            this.state = newState;

            if (newState == CircuitState.OPEN) {
                openedAt = Instant.now();
                failureCount.set(0);
            } else if (newState == CircuitState.CLOSED) {
                failureCount.set(0);
                successCount.set(0);
            } else if (newState == CircuitState.HALF_OPEN) {
                successCount.set(0);
            }

            metrics.counter("circuit.breaker.transition",
                "name", name, "from", previous.name(), "to", newState.name()).increment();
            log.warn("Circuit '{}' transitioned {} → {}", name, previous, newState);
        }
    }

    private void recordCall(boolean success) {
        callWindow.addLast(success);
        if (callWindow.size() > config.windowSize()) callWindow.pollFirst();
    }

    public CircuitState getState() { return state; }
}

// Service client with circuit breaker
public class PaymentServiceClient {
    private final PaymentServiceStub stub;
    private final CircuitBreaker circuitBreaker;
    private final FallbackPaymentService fallback;  // optional fallback

    public PaymentServiceClient(PaymentServiceStub stub, CircuitBreaker cb, FallbackPaymentService fallback) {
        this.stub = stub;
        this.circuitBreaker = cb;
        this.fallback = fallback;
    }

    public PaymentResult charge(Money amount, PaymentMethod method, String orderId) {
        try {
            return circuitBreaker.execute(() -> stub.charge(amount, method, orderId));
        } catch (CircuitOpenException e) {
            // Optional: use fallback (e.g., queue the charge for async processing)
            if (fallback != null) {
                return fallback.queueCharge(amount, method, orderId);
            }
            throw new ServiceUnavailableException("Payment service unavailable, please try again", e);
        } catch (CallTimeoutException e) {
            throw new ServiceUnavailableException("Payment service timed out", e);
        } catch (Exception e) {
            throw new PaymentFailedException("Payment charge failed", e);
        }
    }
}

// Wiring
CircuitBreakerConfig config = new CircuitBreakerConfig(
    failureThreshold: 5,
    successThreshold: 2,
    openTimeout: Duration.ofSeconds(30),
    callTimeout: Duration.ofMillis(500),
    windowSize: 20
);
CircuitBreaker paymentCB = new CircuitBreaker("payment-service", config, meterRegistry);
PaymentServiceClient paymentClient = new PaymentServiceClient(stub, paymentCB, fallback);
```

### How It Works (walkthrough)

1. Payment service starts degrading: calls timeout → `failureCount` reaches 5
2. `transitionTo(OPEN)` → `openedAt = now()`; logged + alerted; metrics emitted
3. Next 30 calls to `paymentClient.charge()` → circuit OPEN → `CircuitOpenException` thrown in <1ms
4. After 30s: `shouldProbe()` returns true → transition to HALF_OPEN
5. One probe request sent: payment service recovered → success → `successCount = 1`
6. After 2 successes: `transitionTo(CLOSED)` → normal operation resumes
7. If probe fails: `transitionTo(OPEN)` again → 30s more wait

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | CircuitBreaker manages failure detection; PaymentServiceClient makes calls |
| Open/Closed | ✅ | Add new state (HALF_OPEN_SLOW) by extending the state machine |
| Liskov Substitution | ✅ | Fallback service substitutable for real service |
| Interface Segregation | ✅ | `execute(Callable<T>)` — simple, generic interface |
| Dependency Inversion | ✅ | Client depends on `CircuitBreaker` abstraction |

---

## When to Use

- A downstream service is unreliable or can fail under load
- Timeouts from one failing service can cascade to exhaust threads in the caller
- You want automatic recovery testing (HALF_OPEN probe) without manual intervention
- Operating under SLAs where a slow downstream is worse than failing fast

## When NOT to Use

- The dependency is highly reliable and always fast (internal in-process call)
- Fallbacks are not available — fast failure without fallback can confuse users
- Request volume is very low — circuit breaker overhead is not justified

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Prevents cascading failures — isolates a failing dependency | False positives: temporarily high failure rate from a transient spike may open the circuit |
| Fail fast — frees threads, reduces latency for users | State management: circuit state must be shared across instances (use Redis for distributed CB) |
| Automatic recovery testing via HALF_OPEN probe | Adds complexity — tuning thresholds (failure count, window, timeout) requires load testing |

---

**FAANG interview application**: "Circuit Breaker is the pattern for resilience against downstream failures. When payment service hits 5 failures in 10s, the circuit opens — subsequent checkout calls fail in <1ms instead of waiting 30s for timeout. This protects checkout service threads from exhaustion and sheds load from the struggling payment service so it can recover. The key tuning challenge is threshold calibration: too sensitive → false positives on traffic spikes; too loose → doesn't protect against slow degradation. In production (multiple instances), use a distributed circuit breaker backed by Redis so all instances share state."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Proxy](../structural/12-proxy.md) | Circuit Breaker is often implemented as a Proxy around a service client |
| [Saga](26-saga.md) | Saga steps should be guarded by circuit breakers — fail the saga early rather than timing out |
| [State](../behavioral/19-state.md) | Circuit Breaker is a State pattern implementation — CLOSED/OPEN/HALF_OPEN are states with defined transitions |
