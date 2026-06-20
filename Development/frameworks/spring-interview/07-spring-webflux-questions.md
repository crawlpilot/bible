# Spring WebFlux — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is the difference between `Mono` and `Flux`?**
- `Mono<T>`: 0 or 1 item — equivalent to `Optional<CompletableFuture<T>>`
- `Flux<T>`: 0 to N items — equivalent to `Stream<T>` but asynchronous and lazy
Both are `Publisher` implementations from Project Reactor. Neither executes until `subscribe()` is called.

**Q2. What does "non-blocking" mean in WebFlux?**
The HTTP thread never waits for I/O (DB, HTTP, file). When a DB call starts, the thread is returned to the event loop; when results arrive, a callback schedules the continuation. A single event-loop thread can handle thousands of concurrent connections because it's never blocked waiting — it's always processing something.

**Q3. How do you return JSON from a WebFlux controller?**
```java
@RestController
public class OrderController {
    @GetMapping("/orders/{id}")
    public Mono<Order> getOrder(@PathVariable UUID id) {
        return orderRepository.findById(id);  // Mono — Spring subscribes automatically
    }

    @GetMapping("/orders")
    public Flux<Order> getAllOrders() {
        return orderRepository.findAll();  // Flux — Spring subscribes automatically
    }
}
```
Spring WebFlux subscribes to the returned `Mono`/`Flux` and writes items to the HTTP response.

**Q4. What is `WebClient` and when do you use it over `RestTemplate`?**
`WebClient` is the non-blocking HTTP client. `RestTemplate` is blocking — it holds a thread while waiting for the HTTP response. In a reactive application, use `WebClient` — blocking with `RestTemplate` would hold the event-loop thread and starve other requests. `RestTemplate` is deprecated since Spring 5.

**Q5. What is a "cold" vs "hot" publisher?**
- **Cold**: each subscriber gets its own independent data stream — `Mono.fromCallable(() -> db.query(...))` re-executes for each subscriber
- **Hot**: data stream is shared; late subscribers miss past events — `Flux.interval(Duration.ofSeconds(1))` emits regardless of subscribers

Most Reactor operators create cold publishers. `ConnectableFlux.publish()` converts cold to hot.

---

## Advanced (L5 Senior)

**Q6. What is the difference between `flatMap` and `concatMap`?**

| | `flatMap` | `concatMap` |
|-|-----------|-------------|
| Concurrency | All inner publishers run concurrently | One at a time — waits for each |
| Order | Output interleaved — not guaranteed | Output in exact input order |
| Speed | Fastest | Slower (sequential) |
| Use for | Parallel I/O calls, order doesn't matter | Sequential steps, state machines |

```java
// flatMap — all 100 product fetches run concurrently (fast, unordered)
Flux.fromIterable(productIds).flatMap(id -> productRepo.findById(id), 20)

// concatMap — fetch one by one in order (sequential pipeline)
Flux.fromIterable(steps).concatMap(step -> executeStep(step))
```

**Q7. What is backpressure and how does Reactor handle it?**
Backpressure is the downstream signaling to upstream how many items it can handle. Without it, a fast producer overwhelms a slow consumer (OOM). In Reactor, `Subscriber.request(n)` controls the flow. When the subscriber can't keep up:
```java
flux.onBackpressureBuffer(1000)       // buffer up to 1000; overflow → error
    .onBackpressureDrop(item -> ...)   // drop overflow; log dropped
    .onBackpressureLatest()            // keep only the latest
```

**Q8. How do you call a blocking service from a reactive chain?**
```java
// WRONG: blocks the event-loop thread — starves all other requests
Mono.just(id)
    .map(i -> blockingRepository.findById(i));  // BLOCKS event loop!

// CORRECT: offload to bounded elastic thread pool
Mono.fromCallable(() -> blockingRepository.findById(id))
    .subscribeOn(Schedulers.boundedElastic());
```
`boundedElastic()` is designed for wrapping blocking I/O — it grows on demand but has a cap (10 * CPU cores default). Never use `parallel()` for blocking code.

**Q9. How does error handling work in reactive chains?**
```java
orderMono
    .onErrorReturn(OrderNotFoundException.class, Order.EMPTY)  // substitute default
    .onErrorResume(NetworkException.class, ex -> fallback.findOrder(id))  // alternative Mono
    .onErrorMap(DatabaseException.class, ex -> new ServiceException(ex))  // rethrow as different type
    .doOnError(ex -> log.error("Failed: {}", ex.getMessage()))  // side-effect, doesn't catch
    .retry(3)  // retry entire subscription 3x on any error
    .retryWhen(Retry.backoff(3, Duration.ofMillis(200))
        .filter(ex -> ex instanceof TransientException));  // retry only specific exceptions
```

**Q10. What is `switchMap` and when do you use it?**
`switchMap` cancels the previous inner subscription when a new item arrives. Use for latest-wins scenarios:
```java
// Search autocomplete: only care about the result for the latest keystroke
searchInputFlux
    .debounce(Duration.ofMillis(300))  // wait until user stops typing
    .switchMap(query -> searchService.search(query));  // cancels previous search
```

---

## Principal Engineer Level

**Q11. When would you choose WebFlux over Spring MVC for a new service?**

Choose WebFlux when:
- **High concurrency** (10K+ simultaneous connections) with I/O-bound workloads
- **Streaming** (SSE, WebSocket, reactive streams consumer)
- **Chained async I/O** (call 3 services in parallel, merge results)
- Entire stack is reactive-compatible (R2DBC, reactive Mongo/Redis, WebClient)

Choose MVC when:
- Team is unfamiliar with reactive (learning curve is steep; reactive debugging is hard)
- Heavy use of blocking JDBC/JPA (you'd wrap everything in `boundedElastic` — no real benefit)
- Simple CRUD with moderate concurrency (< 1000 concurrent users — MVC handles it fine)
- Using libraries that don't support reactive (many enterprise libraries don't)

**Q12. How do you handle security context propagation in a WebFlux application?**
```java
// In WebFlux, SecurityContext lives in Reactor Context (not ThreadLocal)
@GetMapping("/orders")
public Mono<List<Order>> getOrders() {
    return ReactiveSecurityContextHolder.getContext()
        .map(SecurityContext::getAuthentication)
        .map(Authentication::getName)
        .flatMap(userId -> orderRepository.findByUserId(userId));
}

// SecurityContext is automatically propagated through Reactor Context
// by Spring Security's reactive filter chain
```

**Q13. How do you implement a reactive rate limiter?**
```java
// Token bucket per API key using Redis INCR with TTL
public Mono<Boolean> isAllowed(String apiKey) {
    String key = "rate:" + apiKey + ":" + Instant.now().getEpochSecond();
    return reactiveRedis.opsForValue()
        .increment(key)
        .flatMap(count -> {
            if (count == 1) {
                return reactiveRedis.expire(key, Duration.ofSeconds(1))
                    .thenReturn(true);
            }
            return Mono.just(count <= MAX_REQUESTS_PER_SECOND);
        });
}

// In Gateway filter (reactive):
@Override
public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
    String apiKey = exchange.getRequest().getHeaders().getFirst("X-API-Key");
    return rateLimiter.isAllowed(apiKey)
        .flatMap(allowed -> {
            if (!allowed) {
                exchange.getResponse().setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                return exchange.getResponse().setComplete();
            }
            return chain.filter(exchange);
        });
}
```

---

## Code Walkthroughs

**Q14. Why does nothing happen when this code runs?**
```java
Mono<Order> orderMono = orderRepository.findById(id)
    .map(order -> {
        order.setStatus(CONFIRMED);
        return order;
    });
// Nothing is saved to DB
```
**Answer**: Reactor sequences are lazy — `orderMono` is just a recipe. Nothing executes until `subscribe()` is called. In a Spring WebFlux controller, returning the `Mono` causes Spring to subscribe. But here, the `Mono` is created and discarded without subscribing. Fix: subscribe explicitly (in tests), or return from a controller method.

**Q15. What is wrong with this reactive chain?**
```java
Flux<Order> orders = orderRepository.findAll();
orders.subscribe(order -> {
    // blocking DB call inside reactive chain!
    String customerName = jdbcTemplate.queryForObject(
        "SELECT name FROM customers WHERE id = ?",
        String.class, order.getCustomerId());
    order.setCustomerName(customerName);
});
```
**Answer**: Blocking JDBC call inside the reactive pipeline on the event-loop thread. This blocks the thread, defeating the purpose of WebFlux and potentially causing thread starvation. Fix: wrap JDBC call with `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())` and compose with `flatMap`.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `block()` in reactive chain | Deadlock if on event-loop thread | Never block; return Mono/Flux all the way |
| Blocking I/O on event-loop | Starvation; P99 latency spikes | `subscribeOn(Schedulers.boundedElastic())` |
| Not handling errors | Unhandled `onError` signals — default behavior depends on subscriber | Always add `onErrorResume` or `onErrorReturn` |
| `flatMap` when order matters | Non-deterministic output order | `concatMap` for ordered sequential |
| Shared mutable state in operators | Thread-safety issues | Use immutable objects; avoid side effects |
| Not subscribing (forgetting return) | Nothing executes | Always return Mono/Flux from controller methods |
