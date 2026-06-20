# Kotlin — Code Review Checklist

> Kotlin-specific items to check on every Kotlin PR. Kotlin eliminates many Java pitfalls at the language level, but introduces its own set of review concerns — primarily around null safety, coroutines, and idiomatic usage.

---

## Quick Checklist

```
Null Safety
  ☐ !! (not-null assertion) is not used without a documented reason
  ☐ ?: (Elvis) has a safe fallback, not a force-unwrap
  ☐ lateinit var is used only for DI-injected properties, not to avoid null handling
  ☐ Nullable types at public API boundaries are intentional

Coroutines
  ☐ No GlobalScope.launch (use structured concurrency — CoroutineScope or viewModelScope)
  ☐ Coroutine exceptions handled — launch{} does not swallow exceptions silently
  ☐ suspend functions do not block (no Thread.sleep, no blocking I/O without withContext(IO))
  ☐ Coroutine context (Dispatchers) is appropriate for the operation type
  ☐ Flow is cold and not shared unintentionally (use SharedFlow/StateFlow for hot)

Idiomatic Kotlin
  ☐ data class used for value objects (auto: equals, hashCode, toString, copy)
  ☐ sealed class/interface used for sum types (exhaustive when expressions)
  ☐ object used for singletons (not companion object with @JvmStatic everywhere)
  ☐ Extension functions don't add state or break encapsulation
  ☐ Scope functions (let, run, apply, also, with) used correctly and not nested
  ☐ Prefer val over var; var only where mutation is necessary

Collections
  ☐ Immutable collections (listOf, mapOf) vs mutable (mutableListOf) — intent is clear
  ☐ Sequence used for large collections with multiple chained operations
  ☐ No toList() after asSequence() unless terminal operation is appropriate

Interop with Java
  ☐ @JvmField, @JvmStatic, @JvmOverloads used where Java consumers need them
  ☐ Nullable platform types from Java are handled safely
  ☐ @Throws annotates exceptions for Java callers who need checked exception semantics
```

---

## Null Safety

```kotlin
// [BLOCK] Force-unwrap without justification
val name = user.getName()!!   // throws KotlinNullPointerException if null

// Accepted patterns for !!:
//   Only when a null here is a programming bug (invariant violation),
//   not when null is a valid runtime state.
//   Always add a comment explaining why null cannot occur.
val config = configService.get("key")
    ?: error("Config key 'key' must be set — check application.yml")  // better than !!

// [WARN] Elvis with unsafe right-hand side
val order = orderRepository.find(id) ?: throw RuntimeException("not found")
// CORRECT: use a typed, documented exception
val order = orderRepository.find(id)
    ?: throw OrderNotFoundException(id)

// [WARN] lateinit var for non-injected values
lateinit var currentOrder: Order   // set manually in a method — use nullable instead
// CORRECT: lateinit is only appropriate for dependency injection frameworks
//          (Spring @Autowired, field injection) where the DI container guarantees non-null
@Autowired
private lateinit var orderService: OrderService  // OK

// [NIT] Safe call chain — null-check once, not per access
val city = user?.address?.city?.uppercase()  // clean null propagation
// vs:
if (user != null && user.address != null && user.address.city != null) {
    val city = user.address.city.uppercase()  // verbose and Java-style
}
```

---

## Coroutines

```kotlin
// [BLOCK] GlobalScope — no structured concurrency; leaks on cancellation
GlobalScope.launch {
    orderService.processAll()   // runs even after the caller scope is cancelled
}

// CORRECT: inject or use a scoped coroutine scope
class OrderProcessor(private val scope: CoroutineScope) {
    fun processAll() {
        scope.launch {
            orderService.processAll()
        }
    }
}
// In Spring: use CoroutineScope tied to application lifecycle
// In Android: use viewModelScope, lifecycleScope

// [BLOCK] launch{} silently discards exceptions
scope.launch {
    riskyOperation()   // exception is sent to CoroutineExceptionHandler or lost
}
// CORRECT: use async/await for expected exceptions
val result = scope.async {
    riskyOperation()
}.await()   // exception rethrown here and can be caught

// Or add a CoroutineExceptionHandler:
val handler = CoroutineExceptionHandler { _, throwable ->
    log.error("order.async.failed", throwable)
}
scope.launch(handler) {
    riskyOperation()
}

// [BLOCK] Blocking call inside a coroutine
suspend fun getOrder(id: String): Order {
    Thread.sleep(1000)   // blocks the thread — defeats coroutine purpose
    return orderRepository.findById(id)
}
// CORRECT: use delay for coroutine-aware delay
suspend fun getOrder(id: String): Order {
    delay(1000)          // suspends without blocking thread
    return orderRepository.findById(id)
}

// [BLOCK] JDBC/blocking I/O on Default dispatcher
suspend fun getOrders(): List<Order> = withContext(Dispatchers.Default) {
    orderRepository.findAll()   // blocking JDBC call on a CPU-thread — wrong dispatcher
}
// CORRECT:
suspend fun getOrders(): List<Order> = withContext(Dispatchers.IO) {
    orderRepository.findAll()   // IO dispatcher has more threads for blocking calls
}

// [WARN] Cold Flow shared and collected multiple times triggers re-execution
val ordersFlow: Flow<Order> = flow {
    emit(orderRepository.findAll())   // runs once per collector
}
// If multiple collectors need the same data:
val sharedFlow: SharedFlow<Order> = ordersFlow.shareIn(
    scope = scope,
    started = SharingStarted.WhileSubscribed(),
    replay = 1
)

// [WARN] StateFlow not initialised safely
val orderState: StateFlow<Order?> = MutableStateFlow(null)
// Collecting code must handle null initial state

// [NIT] Use supervisorScope for independent child coroutines
// With launch in a regular scope: one child failure cancels siblings
// With supervisorScope: children are independent
supervisorScope {
    launch { processOrderA() }
    launch { processOrderB() }   // processOrderA failure doesn't cancel this
}
```

---

## Data Classes and Value Objects

```kotlin
// [WARN] data class with mutable properties — loses copy-safety
data class Order(
    var status: OrderStatus,   // mutable field in data class — changes after copy
    var lines: MutableList<OrderLine>
)
// CORRECT: val for all fields; use copy() for modification
data class Order(
    val id: String,
    val status: OrderStatus,
    val lines: List<OrderLine>   // immutable list
)
// Mutation:
val updatedOrder = order.copy(status = OrderStatus.CONFIRMED)

// [WARN] data class used for entities with identity (JPA)
@Entity
data class OrderEntity(
    @Id val id: String,
    var status: OrderStatus
)
// data class equality is field-based; JPA entity equality should be ID-based
// CORRECT: use plain class with custom equals/hashCode for JPA entities

// [SUGGESTION] Inline/value classes for type-safe IDs (Kotlin 1.5+)
@JvmInline
value class OrderId(val value: String)
@JvmInline
value class CustomerId(val value: String)

// No confusion between IDs:
fun getOrder(orderId: OrderId, customerId: CustomerId): Order { ... }
// vs. the unsafe:
fun getOrder(orderId: String, customerId: String): Order { ... }  // args easily swapped
```

---

## Sealed Classes and when Expressions

```kotlin
// [WARN] Non-exhaustive when on sealed type — future subtypes silently ignored
sealed class OrderEvent
data class OrderSubmitted(val orderId: String) : OrderEvent()
data class OrderCancelled(val reason: String) : OrderEvent()

fun handleEvent(event: OrderEvent) {
    when (event) {
        is OrderSubmitted -> processSubmit(event)
        // OrderCancelled not handled — silent no-op
    }
}
// CORRECT: use when as expression (forces exhaustiveness) or add else + assertion
fun handleEvent(event: OrderEvent): Unit = when (event) {
    is OrderSubmitted  -> processSubmit(event)
    is OrderCancelled  -> processCancel(event)
    // Compiler error if a new subtype is added without updating this
}

// [NIT] else in exhaustive when — masks missing cases
fun handleEvent(event: OrderEvent) = when (event) {
    is OrderSubmitted -> processSubmit(event)
    else -> Unit   // masks any new OrderEvent subtypes
}
// Remove 'else' from sealed type when expressions — let the compiler catch missing cases
```

---

## Scope Functions (let, run, apply, also, with)

```kotlin
// [WARN] Deeply nested scope functions — hard to read, hard to debug
val result = user?.let { u ->
    u.address?.let { a ->
        a.city?.also { c ->
            log.info("city", c)
        }?.run {
            geocode(this)
        }
    }
}
// CORRECT: extract to named functions; scope functions should be 1 level deep max

// [WARN] Wrong scope function for the use case
// apply: for configuring an object; returns the receiver
val order = Order().apply {
    status = SUBMITTED
    customerId = "cust_abc"
}
// also: for side effects (logging, analytics); returns the receiver
val order = createOrder().also {
    log.info("order.created", kv("order_id", it.id))
}
// let: transform a nullable value; returns the lambda result
val city = user?.address?.let { it.city.uppercase() }
// run: transform the receiver; returns the lambda result
val summary = order.run { "$id: $status ($total)" }

// [NIT] it vs explicit name — use explicit name in longer lambdas
orders.filter { it.status == SUBMITTED }  // OK for short lambda
orders.map { order ->
    // 10-line transform — 'order' is clearer than 'it'
    OrderSummary(order.id, order.status, order.total)
}
```

---

## Extension Functions

```kotlin
// [WARN] Extension function that accesses private state (workaround for encapsulation)
fun Order.calculateInternalFee(): BigDecimal {
    return this.internalCostBasis * FEE_RATE  // accessing internal field via extension
    // This is a sign the logic belongs inside Order, not outside
}
// CORRECT: put business logic in the class; use extensions for utility operations

// [WARN] Extension function on Any or very broad type
fun Any.toJson(): String = objectMapper.writeValueAsString(this)
// Pollutes autocomplete for all types; makes code harder to trace
// CORRECT: limit extension receivers to specific types
fun Order.toJson(): String = objectMapper.writeValueAsString(this)

// [NIT] Extension used to add domain logic to third-party types (valid use case)
fun LocalDateTime.toUtcMillis(): Long = this.toInstant(ZoneOffset.UTC).toEpochMilli()
// This is the correct use case for extension functions
```

---

## Collections and Sequences

```kotlin
// [WARN] Eager chain on large collection — creates intermediate lists
val result = orders           // 100k elements
    .filter { it.isActive() } // creates new list of ~50k
    .map { it.total }         // creates new list of ~50k
    .sum()

// CORRECT: use Sequence for large collections with multiple operations
val result = orders.asSequence()
    .filter { it.isActive() }  // lazy — no intermediate list
    .map { it.total }          // lazy
    .sum()                     // terminal — processes one element at a time

// [NIT] toList() after collect is redundant
val list = items.asSequence().filter { ... }.toList()  // correct; toList() terminates
// But:
val list = items.filter { ... }.toList()  // toList() on List is a copy — usually unnecessary
val list = items.filter { ... }            // filter returns a List already
```

---

## Interop with Java

```kotlin
// [WARN] Platform type not handled — Kotlin trusts Java but Java may return null
// Java: public String getName() { return null; }
val name = javaObject.getName()   // String! — platform type; not null-safe
val upper = name.toUpperCase()    // NPE if getName() returns null

// CORRECT: handle platform type explicitly
val name: String = javaObject.getName() ?: ""

// [WARN] Kotlin function throws exception without @Throws — Java callers can't see it
// Kotlin doesn't have checked exceptions; Java callers see no throws declaration
fun riskyOperation() {
    throw IOException("Failed")   // Java caller doesn't know this can throw
}
// CORRECT: annotate for Java interop
@Throws(IOException::class)
fun riskyOperation() { ... }

// [NIT] @JvmOverloads for default-parameter functions called from Java
// Without @JvmOverloads, Java callers must supply all parameters
fun createOrder(customerId: String, currency: String = "USD", urgent: Boolean = false): Order
// CORRECT for Java consumers:
@JvmOverloads
fun createOrder(customerId: String, currency: String = "USD", urgent: Boolean = false): Order
```

---

## Reviewer Severity Summary

| Issue | Severity |
|---|---|
| `!!` used without documented justification | `[BLOCK]` |
| GlobalScope.launch (no structured concurrency) | `[BLOCK]` |
| launch{} without exception handling | `[BLOCK]` |
| Blocking call (Thread.sleep, JDBC) inside suspend fun without withContext(IO) | `[BLOCK]` |
| Non-exhaustive when on sealed type (missed case, not caught by compiler) | `[WARN]` |
| data class with mutable (var) fields | `[WARN]` |
| Deeply nested scope functions | `[WARN]` |
| Sequence not used for large multi-step collection transforms | `[WARN]` |
| Platform types from Java not handled safely | `[WARN]` |
| lateinit var for non-DI values | `[WARN]` |
| Extension function encapsulation violation | `[WARN]` |
| else in exhaustive when on sealed type | `[NIT]` |
| Missing @JvmOverloads / @Throws for Java interop | `[NIT]` |
