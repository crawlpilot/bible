# 39. Scatter-Gather
**Category**: Modern / Enterprise  
**GoF**: No (Enterprise Integration Patterns — Hohpe & Woolf 2003)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Broadcast a single logical request to multiple services or partitions in parallel (scatter), then aggregate all responses into a single result (gather) — hiding the fan-out complexity from the caller.

---

## Problem It Solves

A product search page must fetch: prices from 5 regional seller services, inventory from 3 warehouse services, and ratings from a reviews service. Serial calls: 9 × 50ms = 450ms — unacceptable for a user-facing page. Naive parallel calls with no aggregation: caller must know about all 9 services, handle partial failures, and merge responses. Scatter-Gather encapsulates the fan-out, concurrency, timeout enforcement, and partial-result merging behind a single interface — caller gets one result in max(50ms per leg) + ~5ms aggregation = ~55ms.

## Structure (Participants)

```
        ─────────────── scatter ───────────────
       │                                        │
  Client ──► Orchestrator ──► SellerService-1 ──┐
                   │       ──► SellerService-2 ──┤
                   │       ──► SellerService-3 ──┼──► Aggregator ──► Result
                   │       ──► Warehouse-US  ────┤
                   │       ──► Warehouse-EU  ────┤
                   │       ──► ReviewService  ───┘
                   │
                    ──── timeout fence (SLA) ─────
```

Key participants:
- **Orchestrator**: fans out requests concurrently; enforces overall deadline
- **Worker / Target Service**: independent downstream — each receives its own request slice
- **Aggregator**: merges partial results; applies partial-result policy (all-or-fail vs best-effort)
- **ResultCollector**: accumulates responses from workers as futures/promises resolve

---

## Real-World Use Case: Product Search Page Aggregation

Search for "laptop" returns 200 product IDs. For each displayed product: fetch live price from regional price service, inventory from warehouse service, and rating summary from reviews service. Deadline: 200ms total.

### Implementation

```java
// Per-target request slice
public record ScatterRequest<T>(String targetId, T payload) {}

// Partial result from one target
public record PartialResult<T>(String targetId, T data, Throwable error, long latencyMs) {
    public boolean isSuccess() { return error == null; }
}

// Aggregation policy
public interface Aggregator<T, R> {
    R aggregate(List<PartialResult<T>> results);
}

// Core Scatter-Gather orchestrator
public class ScatterGather<REQ, RESP, RESULT> {
    private final Function<ScatterRequest<REQ>, RESP> workerFn;
    private final Aggregator<RESP, RESULT> aggregator;
    private final ExecutorService executor;
    private final Duration timeout;
    private final int minSuccessfulResults;  // partial-success policy

    public ScatterGather(
            Function<ScatterRequest<REQ>, RESP> workerFn,
            Aggregator<RESP, RESULT> aggregator,
            ExecutorService executor,
            Duration timeout,
            int minSuccessfulResults) {
        this.workerFn             = workerFn;
        this.aggregator           = aggregator;
        this.executor             = executor;
        this.timeout              = timeout;
        this.minSuccessfulResults = minSuccessfulResults;
    }

    public RESULT execute(List<ScatterRequest<REQ>> requests) {
        if (requests.isEmpty()) return aggregator.aggregate(List.of());

        long deadlineMs = System.currentTimeMillis() + timeout.toMillis();

        // SCATTER: submit all requests concurrently
        Map<String, CompletableFuture<PartialResult<RESP>>> futures = new LinkedHashMap<>();
        for (ScatterRequest<REQ> req : requests) {
            CompletableFuture<PartialResult<RESP>> future = CompletableFuture
                .supplyAsync(() -> {
                    long start = System.currentTimeMillis();
                    try {
                        RESP resp = workerFn.apply(req);
                        return new PartialResult<>(req.targetId(), resp, null,
                            System.currentTimeMillis() - start);
                    } catch (Exception e) {
                        return new PartialResult<>(req.targetId(), null, e,
                            System.currentTimeMillis() - start);
                    }
                }, executor)
                .orTimeout(deadlineMs - System.currentTimeMillis(), TimeUnit.MILLISECONDS)
                .exceptionally(e -> new PartialResult<>(req.targetId(), null, e, timeout.toMillis()));

            futures.put(req.targetId(), future);
        }

        // GATHER: wait for all futures up to the deadline
        CompletableFuture<Void> allOf = CompletableFuture.allOf(
            futures.values().toArray(new CompletableFuture[0]));

        try {
            long remaining = deadlineMs - System.currentTimeMillis();
            allOf.get(Math.max(remaining, 0), TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            // Deadline hit — cancel outstanding futures; use whatever completed
            futures.values().forEach(f -> f.cancel(true));
        } catch (ExecutionException | InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Collect completed results (some may be timeouts/errors)
        List<PartialResult<RESP>> results = futures.values().stream()
            .map(f -> f.isDone() && !f.isCompletedExceptionally()
                ? f.join()
                : new PartialResult<>("unknown", null,
                    new TimeoutException("Scatter-gather deadline exceeded"), timeout.toMillis()))
            .collect(Collectors.toList());

        long successCount = results.stream().filter(PartialResult::isSuccess).count();
        if (successCount < minSuccessfulResults) {
            throw new InsufficientResultsException(String.format(
                "Scatter-gather: need %d successes, got %d/%d",
                minSuccessfulResults, successCount, requests.size()));
        }

        // AGGREGATE: merge partial results
        return aggregator.aggregate(results);
    }
}

// ─── Product search application ───────────────────────────────────────────────

// Price aggregator: merge prices from multiple regional services
public class PriceAggregator implements Aggregator<PriceResponse, Map<String, Money>> {
    @Override
    public Map<String, Money> aggregate(List<PartialResult<PriceResponse>> results) {
        return results.stream()
            .filter(PartialResult::isSuccess)
            .collect(Collectors.toMap(
                r -> r.data().productId(),
                r -> r.data().price(),
                (a, b) -> a.compareTo(b) <= 0 ? a : b  // take lowest price on collision
            ));
    }
}

// Product page aggregator: merge prices, inventory, and ratings
public class ProductPageAggregator implements Aggregator<ServiceResponse, ProductPage> {
    @Override
    public ProductPage aggregate(List<PartialResult<ServiceResponse>> results) {
        Map<String, Money>   prices    = new HashMap<>();
        Map<String, Integer> inventory = new HashMap<>();
        Map<String, Double>  ratings   = new HashMap<>();

        for (PartialResult<ServiceResponse> r : results) {
            if (!r.isSuccess()) {
                log.warn("Partial failure from {}: {}", r.targetId(), r.error().getMessage());
                continue;
            }
            switch (r.data().type()) {
                case PRICE     -> prices.put(r.data().productId(),    r.data().price());
                case INVENTORY -> inventory.put(r.data().productId(), r.data().stock());
                case RATING    -> ratings.put(r.data().productId(),   r.data().rating());
            }
        }
        return new ProductPage(prices, inventory, ratings);  // partial data beats no data
    }
}

// Wiring
ScatterGather<ProductRequest, ServiceResponse, ProductPage> sg = new ScatterGather<>(
    request -> serviceRouter.dispatch(request),  // fan-out to price/inventory/rating services
    new ProductPageAggregator(),
    ForkJoinPool.commonPool(),
    Duration.ofMillis(150),
    1  // at least 1 success (best-effort partial rendering)
);

// Invoke
List<ScatterRequest<ProductRequest>> requests = buildRequests(productIds);
ProductPage page = sg.execute(requests);
```

### Partial-Result Policy

| Policy | When to Use | Example |
|--------|------------|---------|
| All-or-fail | Correctness is paramount; partial data would mislead | Financial calculation across all accounts |
| Best-effort (threshold N) | UX degradation beats blank page | Product page: show items even if ratings service is down |
| Quorum (majority) | Consistency across replicas | Read repair in distributed storage |
| First-wins | Redundant requests to multiple replicas | Hedged requests for tail latency reduction |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `ScatterGather` orchestrates concurrency; `Aggregator` handles merging — separate concerns |
| Open/Closed | ✅ | New aggregation strategies via new `Aggregator` implementations — no changes to orchestrator |
| Liskov Substitution | ✅ | Any `Aggregator<T, R>` substitutable — price, rating, or composite aggregators all work |
| Interface Segregation | ✅ | `Aggregator` has a single method; `ScatterGather` exposes only `execute()` |
| Dependency Inversion | ✅ | Orchestrator depends on `Aggregator` interface; caller injects strategy at construction time |

---

## When to Use

- A single logical operation requires data from multiple independent services or shards
- Serial calls to those services would breach latency SLAs
- Partial results are acceptable (best-effort rendering) or a quorum is sufficient
- Fan-out logic is complex enough to hide behind an abstraction (partial failures, retries, timeouts)

## When NOT to Use

- Services have dependencies on each other's results — use Pipeline or Chain-of-Responsibility instead
- There is only one target service — no scatter needed; add unnecessary overhead
- All results are required with zero tolerance for partial failure — a synchronous orchestration with explicit error handling is clearer

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Dramatic latency reduction: serial 9 × 50ms → parallel ~55ms | Amplifies load: 1 incoming request generates N outgoing requests; downstream must handle fan-out burst |
| Hides fan-out complexity from the caller | Deadline enforcement is tricky: which leg's timeout starts the clock? |
| Partial-result policy makes degraded-mode behavior explicit | Aggregation logic can become complex: deduplication, conflict resolution, partial sort |
| Each scatter leg can be independently retried | Resource usage: N concurrent goroutines/threads per request under high load |

---

**FAANG interview application**: "Scatter-Gather is the latency pattern for product pages, search results, and dashboards that aggregate multiple data sources. The implementation is CompletableFuture.allOf() with a per-overall-deadline timeout, not per-leg timeouts. Critical design choice: partial-result policy — for a product search page, showing prices without ratings is better than showing nothing. Hedged requests are a degenerate case of Scatter-Gather where you scatter to N replicas of the same service and take the first response, which is how Google/Bigtable cuts tail latency at p99."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Competing Consumers](37-competing-consumers.md) | Scatter fans out to specific targets; Competing Consumers pulls from a shared queue — opposite fan-out directions |
| [Aggregator (EIP)](https://www.enterpriseintegrationpatterns.com/patterns/messaging/Aggregator.html) | Gather phase IS the EIP Aggregator pattern |
| [Bulkhead](33-bulkhead.md) | Use Bulkhead to isolate the thread pool used for scatter fan-out from the main request pool |
| [Circuit Breaker](29-circuit-breaker.md) | Wrap each scatter leg in a Circuit Breaker — a failing downstream should return a fast empty result, not block the gather phase |
| [CQRS](25-cqrs.md) | Scatter-Gather is often the read path in CQRS — scatter to multiple read projections, gather into a view model |
