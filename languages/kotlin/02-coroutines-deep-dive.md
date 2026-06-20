# 02 — Kotlin Coroutines Deep Dive

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** Coroutine runtime mechanics, structured concurrency guarantees, Channels, and reactive-style cold/hot flows. Interviewers probe whether you understand what the compiler generates, not just the API.

---

## The Mental Model: Cooperative Multitasking at Compile Time

Kotlin coroutines are **not threads**. They are continuations — the compiler transforms `suspend` functions into state machines. Each `suspend` point becomes a state transition; the coroutine framework decides when to resume.

This is fundamentally different from Java virtual threads, which are OS-managed context switches. Coroutines are **cooperative** (the coroutine decides when to yield) and **compiler-generated** (the state machine is produced by the Kotlin compiler).

---

## 1. `suspend` Functions — What the Compiler Does

```kotlin
suspend fun fetchUser(id: Long): User {
    val user = database.getUser(id)  // suspend point — database call
    return user
}
```

**What the compiler generates (CPS transformation):**

```kotlin
// Conceptual — the actual generated code uses a state machine
fun fetchUser(id: Long, continuation: Continuation<User>): Any {
    // State 0: initial call
    // State 1: after database.getUser() resumes
    return when (state) {
        0 -> {
            state = 1
            database.getUser(id, continuation)  // pass continuation down
        }
        1 -> {
            continuation.resumeWith(result)
        }
    }
}
```

**`Continuation<T>`:** The interface that represents "the rest of the computation after this suspend point." It has one method: `resumeWith(result: Result<T>)`.

**Return type `Any`:** Suspend functions can return either the actual value (if the coroutine doesn't actually need to suspend — e.g., the result was already cached) or `COROUTINE_SUSPENDED` sentinel (if it must wait). The compiler handles this transparently.

### `suspend` Functions Cannot Be Called from Non-Suspend Context

```kotlin
suspend fun loadData(): String = "data"

fun main() {
    loadData()  // COMPILE ERROR — suspend function called from non-suspend context
    
    // Correct: use a coroutine builder
    runBlocking {
        val data = loadData()
    }
}
```

---

## 2. Coroutine Builders

| Builder | Behavior | Returns | Use Case |
|---------|----------|---------|----------|
| `launch` | Fire-and-forget | `Job` | Side effects, parallel work without result |
| `async` | Deferred result | `Deferred<T>` | Parallel computations that return values |
| `runBlocking` | Blocks calling thread | `T` | Main/test bridging — not for production coroutines |
| `coroutineScope` | Creates child scope, suspends until all children complete | `T` | Structured fan-out within a suspend function |
| `supervisorScope` | Like `coroutineScope` but one child failure doesn't cancel siblings | `T` | Independent parallel tasks |

```kotlin
// launch — fire-and-forget
val job: Job = scope.launch {
    performBackgroundWork()
}
job.cancel()   // cancellation propagates

// async — parallel with result
val deferred: Deferred<User> = scope.async {
    fetchUser(id)
}
val user: User = deferred.await()  // suspends until result ready

// Parallel fan-out:
suspend fun loadDashboard(): Dashboard = coroutineScope {
    val user = async { fetchUser(userId) }
    val orders = async { fetchOrders(userId) }
    val notifications = async { fetchNotifications(userId) }
    // All three run concurrently; Dashboard created when all complete
    Dashboard(user.await(), orders.await(), notifications.await())
}
```

---

## 3. CoroutineScope and Structured Concurrency

Every coroutine must be launched within a scope. The scope defines the lifetime of its children.

```kotlin
class OrderService {
    // Scope tied to a lifecycle — coroutines are cancelled when the service is closed
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun processOrder(order: Order) {
        scope.launch {
            // This coroutine's lifetime is bounded by scope
            orderRepository.save(order)
            notificationService.send(order)
        }
    }

    fun close() {
        scope.cancel()  // Cancels all coroutines launched in this scope
    }
}
```

### The Structured Concurrency Contract

1. **A parent coroutine waits for all children to complete before completing itself.**
2. **Cancelling a parent cancels all children transitively.**
3. **If a child fails with an exception, the parent is cancelled** (unless `supervisorScope`/`SupervisorJob`).

```kotlin
// This demonstrates the contract:
suspend fun example() = coroutineScope {  // parent scope
    launch {                               // child 1
        delay(100)
        println("child 1 done")
    }
    launch {                               // child 2
        delay(200)
        println("child 2 done")
    }
    // coroutineScope suspends until BOTH children complete
    println("both children done")          // prints last
}
```

---

## 4. Dispatchers

| Dispatcher | Thread Pool | Use Case |
|-----------|-------------|----------|
| `Dispatchers.Default` | CPU cores count | CPU-bound: sorting, parsing, computation |
| `Dispatchers.IO` | 64 threads (or more, elastic) | I/O-bound: database, network, file |
| `Dispatchers.Main` | Main/UI thread | Android UI updates; no-op in server code |
| `Dispatchers.Unconfined` | No specific thread | Testing; rarely production |
| Custom | `newFixedThreadPoolContext` | Dedicated pool for specific tasks |

```kotlin
// Switch dispatcher within a coroutine
suspend fun processImage(image: ByteArray): ProcessedImage {
    return withContext(Dispatchers.Default) {  // CPU-bound work on Default
        imageProcessor.compress(image)
    }
}

suspend fun saveResult(result: ProcessedImage) {
    withContext(Dispatchers.IO) {  // I/O-bound on IO
        database.save(result)
    }
}
```

**`withContext` vs `async/await`:**

```kotlin
// withContext — sequential, switches context
val result = withContext(Dispatchers.IO) { fetchData() }
processResult(result)

// async/await — concurrent
val deferred = async(Dispatchers.IO) { fetchData() }
val result = deferred.await()
```

Use `withContext` when you just need to run on a different dispatcher. Use `async` when you want to run concurrently while doing other work.

---

## 5. Cancellation

Cancellation is **cooperative**. A coroutine must check for cancellation at `suspend` points or explicitly.

```kotlin
suspend fun longComputation() {
    for (i in 0..1_000_000) {
        // yield() is a suspend point that checks for cancellation
        yield()
        doWork(i)
    }
}

// Or: ensureActive() is a lightweight cancellation check (no actual suspension)
suspend fun longComputation2() {
    for (i in 0..1_000_000) {
        ensureActive()  // throws CancellationException if cancelled
        doWork(i)
    }
}
```

### What Happens When a Coroutine is Cancelled

1. The coroutine is marked as cancelling.
2. On the next `suspend` point, `CancellationException` is thrown.
3. `finally` blocks execute normally — use them for cleanup.
4. `CancellationException` is NOT an error — it's the normal cancellation signal. Don't catch it (or re-throw it).

```kotlin
scope.launch {
    try {
        delay(Long.MAX_VALUE)  // suspends; will throw CancellationException when cancelled
    } finally {
        // Runs on cancellation — clean up resources here
        connection.close()
    }
}

scope.cancel()  // triggers CancellationException in the above coroutine
```

**The `NonCancellable` escape hatch:**

```kotlin
scope.launch {
    try {
        doWork()
    } finally {
        // Problem: if cancelled, delay() inside finally would immediately throw
        withContext(NonCancellable) {
            delay(100)              // OK — NonCancellable ignores cancellation
            database.rollback()     // cleanup that must complete even if cancelled
        }
    }
}
```

---

## 6. Exception Handling

```kotlin
// Exception in a launch {} propagates to the parent scope — crashes all siblings
scope.launch {
    throw RuntimeException("boom")  // cancels scope's other coroutines
}

// Catch at launch level — CoroutineExceptionHandler
val handler = CoroutineExceptionHandler { _, exception ->
    logger.error("Coroutine failed", exception)
}
val scope = CoroutineScope(SupervisorJob() + handler)

// Exception in async {} is deferred until .await() is called
val deferred = scope.async {
    throw RuntimeException("boom")
}
try {
    deferred.await()  // exception thrown here, not where async{} was called
} catch (e: RuntimeException) {
    handleError(e)
}
```

### `SupervisorJob` vs Regular `Job`

```kotlin
// Regular Job: one child fails → all siblings cancelled
val regularScope = CoroutineScope(Job())

// SupervisorJob: one child fails → siblings continue independently
val supervisorScope = CoroutineScope(SupervisorJob())
```

Use `SupervisorJob` when you have multiple independent tasks (like loading multiple dashboard widgets) — one failure should not cancel the others.

---

## 7. Channels — Coroutine Communication Primitives

`Channel<T>` is a coroutine-safe queue. Think of it as a `BlockingQueue` but for coroutines (non-blocking, suspends instead).

```kotlin
val channel = Channel<Int>(capacity = 10)  // buffered channel

// Producer coroutine
scope.launch {
    for (i in 1..100) {
        channel.send(i)    // suspends if channel full
    }
    channel.close()        // signals no more elements
}

// Consumer coroutine
scope.launch {
    for (item in channel) {  // suspends waiting for next element; completes when channel closed
        process(item)
    }
}
```

### Channel Capacity Modes

| Capacity | Name | Behavior |
|----------|------|----------|
| `0` | Rendezvous | Producer suspends until consumer receives |
| `1..N` | Buffered | Producer suspends only when buffer full |
| `UNLIMITED` | Unlimited | Never suspends on send (backpressure lost) |
| `CONFLATED` | Conflated | Only latest value kept; producer never suspends |

### `produce` and `consume` Builders

```kotlin
// produce builds a ReceiveChannel from a coroutine
fun CoroutineScope.generateNumbers(): ReceiveChannel<Int> = produce {
    for (i in 1..Int.MAX_VALUE) {
        send(i)
    }
}

val numbers = generateNumbers()
repeat(10) {
    println(numbers.receive())
}
numbers.cancel()
```

### Fan-Out and Fan-In Patterns

```kotlin
// Fan-out: multiple consumers from one channel
val workChannel = Channel<WorkItem>(100)
repeat(4) {  // 4 worker coroutines
    scope.launch {
        for (item in workChannel) {
            process(item)
        }
    }
}

// Fan-in: merge multiple channels into one
fun CoroutineScope.merge(vararg channels: ReceiveChannel<Int>): ReceiveChannel<Int> =
    produce {
        channels.forEach { channel ->
            launch {
                for (item in channel) send(item)
            }
        }
    }
```

---

## 8. Flow — Cold Reactive Streams

`Flow<T>` is Kotlin's cold stream — values are computed on demand by each collector independently.

```kotlin
// Define a flow — code doesn't execute until collected
fun fetchPages(): Flow<Page> = flow {
    var page = 1
    while (true) {
        val result = api.getPage(page++)   // suspend call inside flow builder
        if (result.isEmpty()) break
        emit(result)                        // emit each page to collector
    }
}

// Collect — triggers execution
fetchPages()
    .filter { it.isPublished }
    .map { it.toDto() }
    .take(10)
    .collect { page ->
        println(page)
    }
```

**Cold = each `collect` starts a fresh execution.** Unlike a hot stream, calling `collect` twice runs the producer twice.

### Flow Operators

```kotlin
flow
    .filter { it > 0 }          // stateless intermediate
    .map { it * 2 }             // stateless intermediate
    .take(10)                    // stateful intermediate (short-circuits)
    .buffer(50)                  // run producer and consumer concurrently
    .conflate()                  // skip values if consumer is slow
    .flowOn(Dispatchers.IO)     // upstream runs on IO, downstream on caller's context
    .catch { e -> emit(defaultValue) }  // handle exceptions in upstream
    .onCompletion { cause -> cleanup() }
    .collect { value -> consume(value) }
```

**`flowOn` vs `withContext` inside flow:**

```kotlin
// WRONG: withContext inside flow body changes context inconsistently
val badFlow = flow {
    withContext(Dispatchers.IO) {   // emit from wrong context
        emit(fetchFromDb())
    }
}

// CORRECT: flowOn moves the entire upstream to IO
val goodFlow = flow {
    emit(fetchFromDb())   // runs on IO because of flowOn below
}.flowOn(Dispatchers.IO)
```

---

## 9. SharedFlow and StateFlow — Hot Streams

### `SharedFlow` — Event Bus

```kotlin
// MutableSharedFlow = broadcast channel to multiple collectors
private val _events = MutableSharedFlow<UserEvent>(
    replay = 0,         // new collectors don't get past events
    extraBufferCapacity = 64,
    onBufferOverflow = BufferOverflow.DROP_OLDEST
)
val events: SharedFlow<UserEvent> = _events.asSharedFlow()

// Emit from anywhere
suspend fun sendEvent(event: UserEvent) {
    _events.emit(event)  // suspends if buffer full
}
// Or non-suspending:
fun sendEventNonSuspending(event: UserEvent) {
    _events.tryEmit(event)  // returns false if buffer full
}

// Multiple independent collectors receive each emission
scope.launch { events.collect { handleAudit(it) } }
scope.launch { events.collect { handleMetrics(it) } }
```

### `StateFlow` — State Holder

```kotlin
// StateFlow holds a current value — always has a value, replays to new collectors
private val _uiState = MutableStateFlow(UiState.Loading)
val uiState: StateFlow<UiState> = _uiState.asStateFlow()

// Update state
_uiState.value = UiState.Success(data)
// or from a coroutine:
_uiState.emit(UiState.Success(data))  // same as setting value but suspend-friendly

// Collector always gets the current value immediately on subscription
scope.launch {
    uiState.collect { state ->
        renderUI(state)
    }
}
```

**`StateFlow` vs `SharedFlow` comparison:**

| Aspect | `StateFlow` | `SharedFlow` |
|--------|------------|-------------|
| Initial value | Required | Not required |
| Replay | Always 1 (current value) | Configurable (0 to N) |
| Equality | Skips equal values | Emits all values |
| Use case | UI state, config | Events, one-shot actions |
| Collector joining late | Gets current value | Gets only new values (unless replay > 0) |

---

## 10. Coroutines vs. Virtual Threads

This comparison appears in every senior/principal Kotlin interview:

| Aspect | Kotlin Coroutines | Java Virtual Threads (JDK 21) |
|--------|-------------------|-------------------------------|
| Scheduling | Cooperative (yield at suspend points) | Preemptive (JVM scheduler) |
| Blocking I/O | Must use coroutine-aware I/O | Any blocking I/O works transparently |
| Memory per unit | ~100 bytes (continuation stack) | ~1–8 KB (initial stack) |
| Composition | Rich: Flow, Channel, structured concurrency | Limited: join, CompletableFuture, StructuredTaskScope |
| Cancellation | Cooperative, structured | Interrupt-based (Thread.interrupt) |
| Backpressure | Flow with `buffer()`, `conflate()` | Manual or reactive wrappers |
| Migration cost | Requires rewriting to suspend functions | Often zero — change `Thread.ofVirtual().start()` |
| Debugging | Suspend points opaque in stack traces | Normal stack traces |
| `synchronized` behavior | Works, but blocks the thread | Pins carrier (JEP 491 fixes in Java 24) |

**The key trade-off:** Virtual threads require less code change but don't give you structured concurrency or reactive operators. Coroutines require adopting the model but give you richer composition (Flow, structured cancellation, Channel). For new Kotlin code: coroutines. For Java codebases that mostly do blocking I/O: virtual threads.

---

## Interview Q&A

### Q1 `[Principal]` Describe what the Kotlin compiler generates for a `suspend` function. What is `COROUTINE_SUSPENDED` and when is it returned?

**Answer:**

The compiler transforms a `suspend` function into a **continuation-passing style (CPS)** state machine. Each `suspend` call site becomes a state number. The function signature gains an implicit `Continuation<T>` parameter.

The return type becomes `Any?`. The function returns either:
- The **actual result value** if computation completed synchronously without suspending (e.g., cache hit — no actual I/O needed).
- `COROUTINE_SUSPENDED` sentinel if the coroutine truly needs to wait (e.g., waiting for network response).

When `COROUTINE_SUSPENDED` is returned, the coroutine framework knows to stop executing this coroutine and schedule other work. When the awaited operation completes, it calls `continuation.resumeWith(result)`, which re-enters the state machine at the correct state number.

This is why suspend functions have zero overhead when they don't actually suspend — the fast path returns the value directly without any coroutine context switching.

---

### Q2 `[Principal]` `CoroutineScope(Job())` vs. `CoroutineScope(SupervisorJob())` — explain the failure propagation rules and give the production scenario where the wrong choice caused an incident.

**Answer:**

**Regular `Job`:** Exception in any child → parent is cancelled → all sibling coroutines are cancelled.

**`SupervisorJob`:** Exception in any child → only that child fails → siblings continue unaffected.

**Propagation rule for regular Job:**
```
Parent (Job)
├── Child A (succeeds)
└── Child B (throws RuntimeException)
    → B's exception propagates to Parent
    → Parent cancels A
    → Parent fails
```

**Production incident pattern:** A service uses `CoroutineScope(Job())` and launches both a background cache-refresh coroutine and a request-serving coroutine in the same scope. The cache-refresh hits a network partition and throws. Because of `Job()` propagation, the request-serving coroutine is cancelled — the service appears to stop responding entirely. The fix is `SupervisorJob()` or separate scopes.

**Counter-pattern where `Job()` is correct:** A saga/transaction scope where all steps are interdependent — if one fails, you want everything to roll back (cancel). Here `Job()` propagation is the desired behavior.

---

### Q3 `[Principal]` Explain `Channel` vs. `Flow` and when you'd use each. What is the backpressure behavior difference?

**Answer:**

**Channel:** A **hot** communication primitive. Values are sent independently of whether anyone is receiving. Multiple coroutines can send to and receive from the same channel. Channel is stateful — it holds a buffer.

**Flow:** A **cold** stream. Values are produced only when collected. Each collector gets an independent execution — no sharing. Flow has no state between collector calls.

**Backpressure:**
- `Channel`: `send()` suspends when buffer is full. Producer naturally applies backpressure.
- `Flow`: operators like `buffer()` decouple producer and consumer coroutines; `conflate()` drops intermediate values; `collectLatest` cancels previous collector on new emission.

**Decision matrix:**

| Scenario | Use |
|----------|-----|
| Worker queue: many producers, multiple consumers | `Channel` |
| Pipeline: transform a stream of data | `Flow` |
| Event broadcast to multiple subscribers | `SharedFlow` |
| UI state — current value always needed | `StateFlow` |
| Server-sent events to one consumer | `Flow` |
| Actor model: one coroutine processes messages | `Channel` (via `actor{}`) |

---

### Q4 `[Principal]` A `Flow` collector throws an exception in `collect`. Where does it propagate and how do you distinguish producer exceptions from consumer exceptions?

**Answer:**

If the **consumer** (inside `collect {}`) throws, the exception propagates to the coroutine that called `collect`. The flow is cancelled.

If the **producer** (inside `flow {}`) throws, the exception propagates to the consumer as if `collect` threw.

**The `catch` operator only catches upstream (producer) exceptions:**

```kotlin
flow {
    emit(fetchData())     // producer — exception here is caught by catch below
}
.catch { e ->
    emit(defaultValue)    // recover from producer exception
}
.collect { value ->
    throw RuntimeException("consumer exception")  // NOT caught by .catch above
}
```

`.catch` is positioned between producer and consumer in the operator chain. It only intercepts exceptions flowing downward from upstream operators. Consumer exceptions flow upward (to the coroutine launching `collect`) and are not visible to `catch`.

**To handle both:**
```kotlin
try {
    flow
        .catch { e -> emit(fallback) }  // handles producer errors
        .collect { processItem(it) }    // consumer errors handled by outer try-catch
} catch (e: Exception) {
    handleConsumerError(e)
}
```

---

### Q5 `[Principal]` You have a service that makes 3 parallel HTTP calls and aggregates the result. One call is non-critical (analytics). How do you implement this with structured concurrency so a failure in the analytics call doesn't cancel the critical calls?

**Answer:**

```kotlin
suspend fun loadPage(userId: Long): PageData = supervisorScope {
    // Critical calls — failure in these should cancel everything
    val userDeferred = async { userService.getUser(userId) }
    val ordersDeferred = async { orderService.getOrders(userId) }

    // Non-critical — use separate error handling
    val analyticsDeferred = async {
        try {
            analyticsService.getRecommendations(userId)
        } catch (e: Exception) {
            logger.warn("Analytics failed, using empty recommendations", e)
            emptyList<Recommendation>()  // graceful fallback
        }
    }

    PageData(
        user = userDeferred.await(),            // throws if user call failed
        orders = ordersDeferred.await(),         // throws if orders call failed
        recommendations = analyticsDeferred.await()  // always returns (caught internally)
    )
}
```

**Why `supervisorScope`:** Without it, if the analytics `async` threw before the inner `try-catch` could handle it (e.g., if the inner try-catch missed a case), the exception would cancel the other async blocks. `supervisorScope` ensures each `async` is independent at the scope level.

**Alternative — structured failure with timeout on non-critical:**

```kotlin
val analytics = async {
    withTimeoutOrNull(500) {
        analyticsService.getRecommendations(userId)
    } ?: emptyList()  // returns empty list if times out
}
```

---

*See also:* [01-language-features-and-idioms.md](01-language-features-and-idioms.md) for `by lazy` thread safety modes | [../java/03-concurrency-and-loom.md](../java/03-concurrency-and-loom.md) for Java virtual threads comparison
