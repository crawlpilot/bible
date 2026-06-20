# 05 — Functional Programming and Reactive Java

**Calibration:** Principal Engineer bar  
**Focus:** Lambda/stream internals, reactive streams specification, backpressure semantics, Virtual threads vs. Reactive trade-off.

---

## 1. Lambda and Method Reference Mechanics

### Lambdas Are NOT Anonymous Inner Classes

Pre-Java 8, the idiom was anonymous classes:

```java
// Anonymous inner class (Java 7)
Runnable r = new Runnable() {
    @Override public void run() { System.out.println("hello"); }
};
// Compiled to a separate .class file: MyClass$1.class
// Creates a new object on every execution
```

Java 8 lambdas use `invokedynamic` + `LambdaMetafactory`:

```java
// Lambda (Java 8)
Runnable r = () -> System.out.println("hello");
// No separate .class file
// First call: LambdaMetafactory generates a class at runtime (once, cached)
// Subsequent calls: may return the same instance (if no captured variables)
```

**LambdaMetafactory** is a bootstrap method for `invokedynamic`. On first invocation:
1. Generates a class implementing the target functional interface.
2. Caches it in a `MutableCallSite`.

For non-capturing lambdas (no captured variables), the same instance is reused — zero allocation after warmup. For capturing lambdas (captures variables), a new instance is created per invocation (the captured values are stored in the instance).

### Method Reference Kinds

```java
// 1. Static method reference
Function<String, Integer> f = Integer::parseInt;
// Equivalent to: s -> Integer.parseInt(s)

// 2. Bound instance method reference (instance is fixed)
String prefix = "Hello, ";
Function<String, String> f = prefix::concat;
// Equivalent to: s -> prefix.concat(s)  — prefix is captured

// 3. Unbound instance method reference (instance is the argument)
Function<String, Integer> f = String::length;
// Equivalent to: s -> s.length()  — s is the first argument

// 4. Constructor reference
Supplier<ArrayList<String>> f = ArrayList::new;
// Equivalent to: () -> new ArrayList<String>()
```

### Effective Finality and Variable Capture

```java
String name = "Alice";
Runnable r = () -> System.out.println(name);  // captures name
// name must be effectively final — not reassigned after initialization
// name = "Bob";  ← would cause compile error

// Why: lambdas capture values, not references (for local variables)
// Mutable capture would create race conditions with concurrent execution
```

**`this` capture:** Non-static lambdas implicitly capture `this` if they reference instance fields. This prevents the lambda from being a static method reference and increases allocation cost.

---

## 2. Stream API Internals

### Pipeline Architecture

```
Source → Intermediate ops → Terminal op

Stream.of(list)
  .filter(x -> x > 0)   ← StatelessOp (ReferencePipeline.StatelessOp)
  .map(x -> x * 2)      ← StatelessOp
  .sorted()             ← StatefulOp (must see all elements before continuing)
  .collect(toList())    ← TerminalOp (triggers execution)
```

Internally, each intermediate operation wraps the previous stage in a `ReferencePipeline.StatelessOp` or `StatefulOp` — a linked list of `AbstractPipeline` objects. **No data flows until the terminal operation is called.**

### Lazy Evaluation

```java
Stream.of(1, 2, 3, 4, 5)
      .filter(x -> { System.out.println("filter " + x); return x > 2; })
      .map(x -> { System.out.println("map " + x); return x * 10; })
      .findFirst();

// Output:
// filter 1
// filter 2
// filter 3    ← first element that passes filter
// map 3       ← only map is called for this element
// (done — findFirst() short-circuits, elements 4,5 never processed)
```

`findFirst()` short-circuits. No unnecessary work. This is only possible because the pipeline is lazy.

### `Spliterator` — The Source Abstraction

Every stream source implements `Spliterator<T>`, which provides:

```java
interface Spliterator<T> {
    boolean tryAdvance(Consumer<? super T> action);  // process next element
    void forEachRemaining(Consumer<? super T> action); // process all remaining
    Spliterator<T> trySplit();   // split for parallel processing (returns null if can't split)
    long estimateSize();         // estimated remaining elements
    int characteristics();       // bitmask of SIZED, ORDERED, SORTED, DISTINCT, etc.
}
```

**Characteristics affect optimization:**
- `SIZED`: `estimateSize()` returns exact count → enables better parallel splits.
- `ORDERED`: elements have encounter order → `findFirst()` is meaningful, parallel sorted streams must maintain order.
- `SORTED`: elements are pre-sorted → `sorted()` in the pipeline is a no-op.
- `DISTINCT`: no duplicates → `distinct()` is a no-op.

```java
// ArrayList's Spliterator: SIZED | SUBSIZED | ORDERED
// → parallel stream splits into equal halves based on exact size
// HashSet's Spliterator: SIZED | DISTINCT
// → no ordering guarantee, but size is known
```

---

## 3. Collectors Deep-Dive

### The `Collector` Contract

```java
interface Collector<T, A, R> {
    Supplier<A>          supplier();      // creates mutable accumulator: () -> new ArrayList<>()
    BiConsumer<A, T>     accumulator();   // adds element to accumulator: (list, e) -> list.add(e)
    BinaryOperator<A>    combiner();      // merges two accumulators (parallel): (l1, l2) -> { l1.addAll(l2); return l1; }
    Function<A, R>       finisher();      // transforms accumulator to result: list -> Collections.unmodifiableList(list)
    Set<Characteristics> characteristics(); // CONCURRENT, IDENTITY_FINISH, UNORDERED
}
```

`IDENTITY_FINISH`: finisher is identity function — skipped for performance.  
`CONCURRENT`: accumulator is thread-safe, no combiner needed in parallel.  
`UNORDERED`: result order doesn't matter — enables better parallel optimization.

### Custom Batch Collector

```java
// Collect into List<List<T>> where each inner list has at most batchSize elements
static <T> Collector<T, List<List<T>>, List<List<T>>> batching(int batchSize) {
    return Collector.of(
        () -> { List<List<T>> result = new ArrayList<>(); result.add(new ArrayList<>()); return result; },
        (batches, element) -> {
            List<T> last = batches.get(batches.size() - 1);
            if (last.size() >= batchSize) {
                batches.add(new ArrayList<>());
                last = batches.get(batches.size() - 1);
            }
            last.add(element);
        },
        (b1, b2) -> { b1.addAll(b2); return b1; }  // simple merge for parallel
    );
}

// Usage:
List<List<Order>> batches = orders.stream().collect(batching(100));
```

### `Collectors.teeing` (Java 12)

Apply two collectors simultaneously and combine their results:

```java
record Stats(long count, double sum) {}

Stats stats = numbers.stream().collect(
    Collectors.teeing(
        Collectors.counting(),
        Collectors.summingDouble(Double::doubleValue),
        Stats::new
    )
);
// Single pass over the stream — both collectors run simultaneously
```

---

## 4. Parallel Streams — When They Hurt

### When Parallel Streams Are Counterproductive

| Scenario | Why It Hurts |
|----------|-------------|
| Small collection (< 10K elements) | Fork/Join overhead > speedup |
| I/O-bound operations | Blocks `commonPool` threads — starves other parallel operations |
| Operations that acquire locks | Contention eliminates parallel benefit |
| Ordered operations on unordered source | Maintaining order in parallel requires synchronization |
| Server application using `commonPool` | All parallel streams on the JVM share the same pool |

```java
// DANGEROUS in a Spring/Tomcat server:
List<Result> results = requests.parallelStream()
    .map(r -> callExternalService(r))  // 50ms I/O call per request
    .collect(toList());
// Each call blocks a ForkJoinPool.commonPool() thread for 50ms
// 8-thread commonPool saturated → other parallelStream() calls elsewhere stall
```

### Custom Pool for Parallel Streams

```java
ForkJoinPool pool = new ForkJoinPool(20);  // dedicated pool
List<Result> results = pool.submit(() ->
    requests.parallelStream()
             .map(r -> callExternalService(r))
             .collect(toList())
).get();
```

The `parallelStream()` picks up the calling thread's `ForkJoinPool` context — submitting from a `ForkJoinPool.submit()` call makes it use that pool.

---

## 5. Optional as a Monad

### Monad Pattern

A monad wraps a value and provides:
- `unit` / `return`: wrap a value → `Optional.of(value)`
- `bind` / `flatMap`: unwrap, apply function that returns a monad, rewrap → `Optional.flatMap(f)`
- `fmap` / `map`: unwrap, apply ordinary function, rewrap → `Optional.map(f)`

```java
// Monad laws:
// 1. Left identity: unit(a).flatMap(f) == f(a)
Optional.of(5).flatMap(x -> Optional.of(x * 2))  ==  Optional.of(10)

// 2. Right identity: m.flatMap(unit) == m
Optional.of(5).flatMap(Optional::of)  ==  Optional.of(5)

// 3. Associativity: m.flatMap(f).flatMap(g) == m.flatMap(x -> f(x).flatMap(g))
```

### Optional Chain (Null Object Pattern)

```java
// Pre-Optional: nested null checks
String city = null;
if (user != null && user.getAddress() != null && user.getAddress().getCity() != null) {
    city = user.getAddress().getCity().toUpperCase();
}

// Post-Optional: chained flatMap
String city = Optional.ofNullable(user)
    .flatMap(User::getAddress)           // User.getAddress() returns Optional<Address>
    .map(Address::getCity)               // Address.getCity() returns String
    .map(String::toUpperCase)
    .orElse("UNKNOWN");
```

**When Optional hurts:**
- As a method parameter — callers must check presence before calling, creating double Optional nesting.
- In collections — `List<Optional<T>>` is almost always a design mistake; use filtering instead.
- In hot paths — each `Optional` is a heap allocation (though JIT can scalar-replace them in simple cases).

---

## 6. Reactive Streams Specification

### The Four Interfaces

```java
// Reactive Streams specification (Java 9 java.util.concurrent.Flow)
interface Publisher<T> {
    void subscribe(Subscriber<? super T> s);
}

interface Subscriber<T> {
    void onSubscribe(Subscription s);   // called first, always
    void onNext(T t);                   // called for each element
    void onError(Throwable t);          // called once on error, then no more signals
    void onComplete();                  // called once when done, then no more signals
}

interface Subscription {
    void request(long n);   // demand signal: "send me n more items"
    void cancel();          // I don't want more items
}

interface Processor<T, R> extends Subscriber<T>, Publisher<R> {}
```

### The Demand Protocol — Core of Backpressure

```
Subscriber                   Publisher
    |                            |
    |---onSubscribe(sub)-------->|
    |<--onSubscribe(sub)---------|
    |                            |
    |---sub.request(3)---------->|  "I can handle 3 items"
    |<--onNext(item1)------------|
    |<--onNext(item2)------------|
    |<--onNext(item3)------------|
    |                            |  (publisher MUST NOT send item4 until more request)
    |---sub.request(2)---------->|  "I'm ready for 2 more"
    |<--onNext(item4)------------|
    |<--onNext(item5)------------|
    |<--onComplete()-------------|
```

**The invariant:** `onNext` call count ≤ sum of all `request(n)` calls.

Calling `request(Long.MAX_VALUE)` = unbounded demand = disables backpressure. Project Reactor's `Flux.subscribe(consumer)` uses unbounded demand internally — for push-based reactive pipelines without backpressure.

---

## 7. Project Reactor (Mono/Flux)

### Cold vs. Hot Publishers

```java
// Cold publisher: each subscription gets its own independent stream
Flux<Integer> cold = Flux.just(1, 2, 3);
cold.subscribe(System.out::println);  // 1, 2, 3
cold.subscribe(System.out::println);  // 1, 2, 3 again — independent sequences

// Hot publisher: all subscribers share the same stream
Sinks.Many<Integer> sink = Sinks.many().multicast().onBackpressureBuffer();
Flux<Integer> hot = sink.asFlux();
hot.subscribe(s -> System.out.println("A: " + s));
hot.subscribe(s -> System.out.println("B: " + s));
sink.tryEmitNext(1);  // A: 1, B: 1 — both receive the same element
```

Cold: HTTP response body, file read — each consumer starts from the beginning.  
Hot: WebSocket stream, stock price feed — subscribers see only items emitted after they subscribed.

### `publishOn` vs. `subscribeOn`

This is the most misunderstood Reactor API:

```java
Flux.just(1, 2, 3)
    .map(x -> x * 2)              // runs on thread where subscription starts
    .publishOn(Schedulers.parallel())  // from here downward: parallel scheduler
    .map(x -> expensiveOp(x))     // runs on parallel scheduler
    .subscribeOn(Schedulers.boundedElastic()) // affects the SOURCE and upstream
    .subscribe(System.out::println);

// Execution:
// Flux.just() and first map: boundedElastic (subscribeOn affects source)
// expensiveOp: parallel (publishOn affects downstream)
// subscribe callback: parallel (last publishOn wins for the terminal)
```

**`publishOn`:** Shifts execution of operators AFTER it to the specified scheduler. Think of it as "switch thread pool at this point in the pipeline."

**`subscribeOn`:** Shifts execution of the SOURCE and everything before the first `publishOn`. Only the first `subscribeOn` in a chain has effect on the source.

**Rule of thumb:**
- `subscribeOn(Schedulers.boundedElastic())` for blocking I/O sources (DB calls, file reads).
- `publishOn(Schedulers.parallel())` for CPU-intensive operators after a source.

### Operator Fusion

Reactor performs **micro-fusion** and **macro-fusion** to eliminate intermediate queues between operators:

**Macro-fusion:** If adjacent operators are fuseable (e.g., `map` followed by `map`), they are merged into a single operator — one pass over the data, no intermediate collection.

**Micro-fusion:** When a source is `SYNC` (synchronously pulls elements), the downstream operator can call `tryOnNext` directly on the source without a queue between them.

This is an internal optimization — you don't control it, but it explains why operator ordering can affect performance. Placing `filter` before `map` is not just logically better — it enables fusion that reduces the number of elements that flow through the map.

---

## 8. Backpressure Strategies

```java
// The fast producer, slow consumer problem
Flux<Event> fastProducer = Flux.interval(Duration.ofMillis(1));  // 1000/s
fastProducer
    .onBackpressureBuffer(1000)    // buffer up to 1000 items
    .onBackpressureDrop(dropped -> metrics.counter("dropped").increment())
    // alternatives:
    // .onBackpressureLatest()     // keep only the most recent item
    // .onBackpressureError()      // OverflowException when buffer full
    .delayElements(Duration.ofMillis(100))  // 10/s processing
    .subscribe(event -> process(event));
```

| Strategy | Behavior | Use Case |
|----------|---------|---------|
| `BUFFER` | Store in queue, error when full | Short bursts OK; sustained overflow = bad |
| `DROP` | Silently discard excess | Sensor data where latest is sufficient |
| `LATEST` | Keep most recent undelivered | UI updates, stock ticks |
| `ERROR` | `OverflowException` on overflow | Strict contract: no data loss allowed |

**Architecturally correct:** Make the source pull-based using `Flux.create`:

```java
Flux<Event> pullBased = Flux.create(sink -> {
    sink.onRequest(n -> {
        // Only fetch n events from the source
        List<Event> events = eventQueue.poll(n);
        events.forEach(sink::next);
    });
    sink.onDispose(() -> eventQueue.close());
});
// The source generates events only when downstream has demand
// Zero dropped events, zero buffering overhead
```

---

## 9. Virtual Threads vs. Reactive

The comparison every principal engineer interview reaches:

| Aspect | Virtual Threads | Reactive (Project Reactor) |
|--------|----------------|--------------------------|
| Programming model | Imperative (synchronous-looking) | Functional pipeline |
| Backpressure | **None** — no demand signaling | Built-in via `request(n)` |
| Complexity | Low — familiar try/catch, loops | High — operator knowledge required |
| Debugging | Stack traces are readable | Stack traces are callback soup |
| I/O handling | Blocking calls auto-unmount | Non-blocking required throughout |
| Context propagation | `ScopedValue` (Java 21) | `contextWrite` / `Hooks` |
| Error handling | try/catch | `onError`, `retry`, `retryWhen` |
| Library support | Any library (blocking is fine) | Must use reactive-compatible drivers |

**The decisive trade-off:**

Virtual threads give you imperative simplicity for I/O-bound workloads. But they cannot apply backpressure to producers — if a Kafka consumer reads faster than it processes, the in-memory queue grows unboundedly.

Reactive streams give you declarative backpressure — the consumer controls the production rate. But you pay with complexity, non-obvious threading, and a library ecosystem dependency.

**Hybrid recommendation:**

```java
// Use virtual threads for: service-to-service calls, DB queries, request handling
// Use Reactor for: streaming pipelines with backpressure (Kafka consumer → DB batch write)

// Spring WebFlux on virtual threads (Spring Boot 3.2+):
// @Bean RouterFunction<ServerResponse> routes() {
//     return route(GET("/api"), req -> {
//         String result = blockingDbCall();  // OK on virtual thread
//         return ServerResponse.ok().bodyValue(result);
//     });
// }
// spring.threads.virtual.enabled=true
```

---

## Interview Q&A

### Q1 `[Principal]` How does `Stream.parallel()` work? What determines thread count, and give 3 scenarios where it hurts?

**Answer:**

**Mechanics:** `parallel()` sets a flag on the pipeline. The terminal operation delegates to `ForkJoinPool.commonPool()` by default. The `Spliterator.trySplit()` method is called recursively to divide the source into chunks; each chunk is processed by a pool thread. Results are combined using the collector's `combiner()`.

**Thread count:** `ForkJoinPool.commonPool()` size = `Runtime.getRuntime().availableProcessors() - 1`. On a 16-core machine: 15 threads. Can be overridden with `-Djava.util.concurrent.ForkJoinPool.common.parallelism=N`.

**3 scenarios where it hurts:**

1. **Small collections:** A 100-element list takes ~2μs sequentially. Fork/Join overhead (deque operations, work stealing setup) takes ~10–50μs. Net result: 5–25× SLOWER in parallel.

2. **I/O-bound operations:** `parallelStream().map(url -> fetch(url))` blocks `commonPool` threads on network I/O. With 8 threads and 50ms fetch time, only 160 requests/second. Sequential with a proper thread pool or virtual threads is both simpler and faster.

3. **Server application with `commonPool`:** Two simultaneous HTTP requests both call `parallelStream()`. They share the 15-thread `commonPool`. Request A's parallel work steals threads from Request B's. Latency becomes unpredictable and requests can cascade-starve each other. Use `CompletableFuture` with a dedicated executor or virtual threads instead.

---

### Q2 `[Principal]` Explain the reactive streams `request(n)` protocol. What happens if you never call it?

**Answer:**

`request(n)` is the **demand signal** — it tells the publisher "I am ready to receive n more items." The publisher MUST NOT emit more `onNext` calls than the total requested so far.

**Lifecycle:**
```
1. Subscriber.onSubscribe(sub) is called — publisher passes the Subscription
2. Subscriber calls sub.request(n) — MUST happen before any onNext
3. Publisher emits at most n onNext calls
4. Subscriber calls request(m) for more — publisher emits at most m more
5. Eventually: onComplete() or onError() (counted outside demand)
```

**If you never call `request`:** The publisher stalls indefinitely. `onNext` is never called. The subscription is "live" (not cancelled) but delivering zero elements. This is correct behavior — the publisher respects zero demand.

**`request(Long.MAX_VALUE)` = unbounded demand:** This is what `Flux.subscribe(consumer)` does internally — it signals infinite demand. The publisher emits as fast as it can. This is fine for cold, bounded publishers (a list of 100 elements). It's dangerous for infinite hot publishers (a socket stream) — the subscriber can be overwhelmed.

---

### Q3 `[Principal]` `publishOn` vs. `subscribeOn` — which affects the source, which affects downstream, and give a production use case for each.

**Answer:**

```
Flux<T> source
  .subscribeOn(Schedulers.A)    ← affects: source + everything above this
  .map(...)
  .publishOn(Schedulers.B)      ← affects: everything BELOW this
  .map(...)
  .subscribe(...)
```

**`subscribeOn(A)`:** When `subscribe()` is called, the subscription propagates up through the pipeline and reaches the source — the source's `subscribe()` method runs on Scheduler A. All operators BEFORE the first `publishOn` also run on A.

**`publishOn(B)`:** At this point in the pipeline, the thread switches to Scheduler B. All operators after this point (including the subscriber's `onNext`) run on B.

**Production use cases:**

`subscribeOn(Schedulers.boundedElastic())`:
```java
// Source is a blocking JDBC call — must run on a thread that can block
Flux<Order> orders = Flux.defer(() -> Flux.fromIterable(jdbcRepo.findAll()))
    .subscribeOn(Schedulers.boundedElastic());  // runs JDBC call on elastic thread pool
// Without this: JDBC runs on the event loop thread → blocks the reactor event loop
```

`publishOn(Schedulers.parallel())`:
```java
// Source emits fast, downstream does CPU-intensive work
kafkaFlux
    .publishOn(Schedulers.parallel())  // CPU-heavy map runs on parallel scheduler
    .map(msg -> expensiveJsonParsing(msg))
    .subscribe(parsed -> storeToDb(parsed));
// Kafka source uses its own thread; parsing parallelized on CPU pool
```

---

### Q4 `[Principal]` Fast producer (100k/s), slow consumer (10k/s). Walk through all 4 options and identify the architecturally correct one.

**Answer:**

**Option 1: `onBackpressureBuffer(10000)`**
```java
fastFlux.onBackpressureBuffer(10000).subscribe(this::process);
```
Buffer up to 10k items. Handles burst traffic. Problem: if the rate mismatch is sustained, the buffer fills → `OverflowException`. Appropriate for short bursts, not sustained overload.

**Option 2: `onBackpressureDrop()`**
```java
fastFlux.onBackpressureDrop(e -> metrics.dropCounter.increment()).subscribe(this::process);
```
Discard items when consumer can't keep up. Appropriate when items are disposable (sensor readings, UI updates). Not appropriate when all items must be processed (financial transactions, audit events).

**Option 3: `onBackpressureLatest()`**
```java
fastFlux.onBackpressureLatest().subscribe(this::process);
```
Keep only the most recent undelivered item. One delivery per consumer poll. Appropriate for "show the current state" scenarios (dashboard values, stock prices). Delivers stale data if consumer is very slow.

**Option 4 (Architecturally Correct): Pull-based source**
```java
Flux<Event> pullBased = Flux.create(sink -> {
    sink.onRequest(n -> {
        // Produce exactly n events — no more
        for (long i = 0; i < n; i++) {
            Event e = eventSource.poll();
            if (e == null) { sink.complete(); return; }
            sink.next(e);
        }
    });
});
pullBased.subscribe(this::process);  // request(Long.MAX_VALUE) internally
// The subscriber drives the rate: subscriber requests 1 → processes → requests 1 more
```

Why this is architecturally correct: **the consumer controls production rate**. There are no dropped events, no unbounded buffers, no overflow exceptions. The event source is only polled when the consumer is ready. This is the true spirit of reactive backpressure — demand-driven production.

---

*See also:* [03-concurrency-and-loom.md](03-concurrency-and-loom.md) for virtual thread model and why reactive complexity is avoidable for I/O-bound work | [04-data-structures-internals.md](04-data-structures-internals.md) for ArrayList's Spliterator characteristics
