# Spring WebFlux — Reactive Programming, Project Reactor, and Non-Blocking I/O

Spring WebFlux is Spring's reactive web framework. It runs on Netty (non-blocking) instead of Tomcat (blocking), enabling a single thread to handle thousands of concurrent connections. Understanding when reactive actually helps — and when it hurts — is a principal engineer-level judgment call.

---

## Why Reactive? The Problem with Blocking I/O

```
Blocking Model (Spring MVC + Tomcat):
  Thread 1: ▓▓▓▓▓ request ▒▒▒▒▒▒▒▒▒ waiting for DB ▒▒▒▒▒▒▒▒▒ response ▓▓▓▓▓
  Thread 2: ▓▓▓▓▓ request ▒▒▒▒▒▒▒▒▒ waiting for API ▒▒▒▒▒▒▒▒▒ response ▓▓▓▓▓
  ...
  Thread 200: (max Tomcat threads — 201st request QUEUED)

Reactive Model (Spring WebFlux + Netty):
  Event loop: ▓ start ► dispatch DB call ► handle next request ► DB callback ► response
              ▓ start ► dispatch API call ► handle next request ► API callback ► response
  2 threads (event loops) handle 10,000 concurrent connections
```

**Key insight**: Reactive shines under **I/O-bound, high-concurrency** loads. For CPU-bound workloads or simple CRUD with low concurrency, it adds complexity with no benefit.

---

## Project Reactor — Core Types

```java
// Mono<T>: 0 or 1 item (like Optional + CompletableFuture)
Mono<Order> order = orderRepository.findById(id);

// Flux<T>: 0 to N items (like Stream, but async and lazy)
Flux<Order> orders = orderRepository.findByCustomerId(customerId);
```

### Publisher, Subscriber, Subscription

```
Publisher (Mono/Flux) ──subscribe()──► Subscriber
         │                               │
         │◄──────────request(n)──────────┤  ← backpressure
         │──────────onNext(item)────────►│
         │──────────onNext(item)────────►│
         │──────────onComplete()────────►│
         │──────────onError(ex)─────────►│  (or this, instead of onComplete)
```

Nothing happens until `subscribe()` is called — Reactor sequences are **lazy**.

---

## Core Operators

```java
// Transformation
Mono.just("hello")
    .map(String::toUpperCase)              // sync transform — 1:1
    .flatMap(s -> callExternalService(s))  // async transform — 1:Mono
    .flatMapMany(s -> streamResults(s));   // async transform — 1:Flux

// Combining
Mono.zip(getUser(id), getOrders(id), getPreferences(id))
    .map(tuple -> new UserProfile(tuple.getT1(), tuple.getT2(), tuple.getT3()));

// Error handling
orderMono
    .onErrorReturn(OrderNotFoundException.class, Order.EMPTY)
    .onErrorMap(DatabaseException.class, ex -> new ServiceException("DB error", ex))
    .onErrorResume(TimeoutException.class, ex -> fallbackRepository.findById(id))
    .retry(3)                              // retry on any error, 3 times
    .retryWhen(Retry.backoff(3, Duration.ofMillis(500)).maxBackoff(Duration.ofSeconds(5)));

// Filtering
Flux.fromIterable(orders)
    .filter(o -> o.getStatus() == PENDING)
    .take(10)
    .skip(5)
    .distinct(Order::getCustomerId);

// Scheduling
Mono.fromCallable(this::blockingDbCall)
    .subscribeOn(Schedulers.boundedElastic())  // offload blocking to bounded thread pool
    .publishOn(Schedulers.parallel());          // downstream on parallel scheduler
```

---

## flatMap vs concatMap vs mergeMap

| Operator | Concurrency | Order Preserved | Use Case |
|----------|-------------|----------------|----------|
| `flatMap` | Concurrent (all at once) | No | Parallel I/O calls — fastest |
| `concatMap` | Sequential (one at a time) | Yes | Ordered processing, state machines |
| `mergeMap` | Concurrent (bound by concurrency param) | No | `flatMap(f, 4)` — cap parallelism |
| `switchMap` | Latest only (cancels previous) | No | Search autocomplete, latest-wins |

```java
// RIGHT: parallel DB lookups
Flux.fromIterable(productIds)
    .flatMap(id -> productRepository.findById(id), 10)  // 10 concurrent
    .collectList();

// WRONG for ordered: flatMap doesn't guarantee order
// Use concatMap if order matters:
Flux.fromIterable(steps)
    .concatMap(step -> executeStep(step));  // step 2 waits for step 1
```

---

## Backpressure

```java
Flux<Order> orderStream = orderProducer.streamOrders();

orderStream
    .onBackpressureBuffer(1000, BufferOverflowStrategy.DROP_OLDEST)
    // OR:
    .onBackpressureDrop(dropped -> log.warn("Dropped: {}", dropped.getId()))
    // OR:
    .onBackpressureLatest()  // keep only the latest, discard older
    .subscribe(this::processOrder);
```

**Backpressure in HTTP (SSE)**:
```java
@GetMapping(value = "/stream/orders", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<Order> streamOrders() {
    return orderRepository.streamByStatus(OrderStatus.ACTIVE)
        .delayElements(Duration.ofMillis(100));  // rate limit the stream
}
```

---

## R2DBC — Reactive Relational Database

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-r2dbc</artifactId>
</dependency>
<dependency>
    <groupId>io.r2dbc</groupId>
    <artifactId>r2dbc-postgresql</artifactId>
</dependency>
```

```java
// R2DBC Repository — all methods return Mono/Flux
public interface OrderRepository extends R2dbcRepository<Order, UUID> {
    Flux<Order> findByCustomerIdOrderByCreatedAtDesc(UUID customerId);
    Mono<Order> findByIdAndStatus(UUID id, OrderStatus status);
}

// Service — fully non-blocking
@Service
public class OrderService {
    public Mono<Order> createOrder(CreateOrderRequest req) {
        return orderRepository.save(new Order(req))
            .flatMap(order -> inventoryClient.reserve(order.getProductId(), order.getQuantity())
                .thenReturn(order))
            .flatMap(order -> eventPublisher.publish(new OrderCreated(order))
                .thenReturn(order));
    }
}
```

**R2DBC limitations vs JPA**:
- No lazy loading (no entity graph)
- No first-level cache
- No JPQL — must use `@Query` with native SQL or Spring Data R2DBC `DatabaseClient`
- `@Transactional` works but uses reactive transaction manager

---

## WebClient — Non-Blocking HTTP Client

```java
@Bean
public WebClient inventoryWebClient(WebClient.Builder builder) {
    return builder
        .baseUrl("http://inventory-service")
        .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
        .filter(ExchangeFilterFunction.ofRequestProcessor(request -> {
            log.debug("Request: {} {}", request.method(), request.url());
            return Mono.just(request);
        }))
        .codecs(c -> c.defaultCodecs().maxInMemorySize(5 * 1024 * 1024))  // 5MB
        .build();
}

// Usage
public Mono<InventoryResponse> checkInventory(String productId) {
    return webClient.get()
        .uri("/api/v1/inventory/{id}", productId)
        .retrieve()
        .onStatus(HttpStatus::is4xxClientError, response ->
            response.bodyToMono(ErrorResponse.class)
                .flatMap(err -> Mono.error(new InventoryException(err.getMessage()))))
        .bodyToMono(InventoryResponse.class)
        .timeout(Duration.ofSeconds(5))
        .retryWhen(Retry.backoff(3, Duration.ofMillis(200)));
}
```

---

## Schedulers

| Scheduler | Thread Pool | Use For |
|-----------|------------|---------|
| `Schedulers.parallel()` | CPU core count | CPU-bound work |
| `Schedulers.boundedElastic()` | Dynamic, bounded | Blocking I/O calls (JDBC, files) |
| `Schedulers.single()` | 1 thread | Serial operations |
| `Schedulers.immediate()` | Current thread | No scheduling overhead |

```java
// Wrapping blocking calls — ESSENTIAL pattern in reactive apps
Mono.fromCallable(() -> legacyBlockingService.call())
    .subscribeOn(Schedulers.boundedElastic());
// Never block on the event loop — it starves all other requests
```

---

## Common Reactive Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Blocking inside reactive chain | Starves event loop | `subscribeOn(boundedElastic())` |
| Not subscribing | Nothing happens | Ensure subscriber exists; return Mono/Flux from controllers |
| `block()` in reactive context | Deadlock | Never call `block()` in reactive code |
| Ignoring backpressure | OOM | Add `onBackpressureBuffer` with bounded buffer |
| `flatMap` when order matters | Wrong sequence | Use `concatMap` |
| Shared mutable state | Thread safety issues | Use immutable objects; avoid side effects in operators |
| No timeout | Hung requests | Always set `.timeout(Duration)` on external calls |

---

## Design Patterns Used

| Pattern | Where in Spring WebFlux |
|---------|------------------------|
| **Observer** | Publisher/Subscriber — reactive streams core |
| **Iterator** | Backpressure-aware iteration over Flux |
| **Decorator** | `ExchangeFilterFunction` — wraps WebClient requests |
| **Pipeline** | Operator chains — data flows through transformation stages |
| **Scheduler** | `Schedulers` — select execution context per stage |
| **Bulkhead** | `flatMap(f, N)` — limit concurrency to protect downstream |

---

## MVC vs WebFlux — Decision Table

| Factor | Spring MVC | Spring WebFlux |
|--------|-----------|----------------|
| Team familiarity | High (standard Java) | Low (reactive mindset shift) |
| Concurrency | Thread-per-request | Event loop |
| Blocking libraries (JDBC, JPA) | Full support | Must wrap in `boundedElastic` |
| Streaming / SSE | Limited | Native |
| Debugging | Simple stack traces | Reactor operator traces |
| Database | JPA/JDBC | R2DBC (reactive) |
| Performance (low concurrency) | Equal | Equal |
| Performance (10K+ concurrent) | Thread pool saturates | Handles gracefully |
| Choose when | Standard CRUD, team is Java-traditional | High throughput streaming, microservices with reactive-compatible libs |

---

## FAANG Interview Callout

1. **"What's the difference between `Mono` and `Flux`?"**
   - `Mono<T>`: 0 or 1 item; `Flux<T>`: 0 to N items. Both are lazy publishers — nothing executes until subscribed.

2. **"When would you NOT use WebFlux?"**
   - Team unfamiliar with reactive (training cost high)
   - Application is predominantly blocking JDBC calls (use `boundedElastic` — same threads, no benefit)
   - Simple CRUD with < 1000 concurrent users (MVC is simpler)

3. **"What is backpressure and how does Reactor handle it?"**
   - Downstream signals how many items it can handle (`request(n)`); upstream produces at most that rate
   - Reactor operators: `onBackpressureBuffer`, `onBackpressureDrop`, `onBackpressureLatest`

4. **"What is the difference between `flatMap` and `concatMap`?"**
   - `flatMap`: concurrent, interleaved, no order guarantee — fastest
   - `concatMap`: sequential, preserves order — use when downstream order matters

5. **"How do you call a blocking service from a reactive chain?"**
   - `Mono.fromCallable(() -> blockingCall()).subscribeOn(Schedulers.boundedElastic())`
   - Never block directly — it will starve the event loop thread
