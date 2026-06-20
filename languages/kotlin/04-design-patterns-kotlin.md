# 04 — Design Patterns in Kotlin

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** Which GoF patterns are reduced to one-liners in Kotlin, which require new Kotlin-specific idioms, and where Kotlin's type system enables patterns that are impossible in Java.

---

## 1. Creational Patterns

### Singleton — `object` Declaration

```kotlin
// Java: DCLP, synchronized, volatile
// Kotlin: one keyword, JVM class-loading guarantees thread safety
object DatabasePool {
    val dataSource: HikariDataSource by lazy {
        HikariDataSource(config())
    }
    fun connection() = dataSource.connection
}

// Usage — no getInstance() call needed
DatabasePool.connection()
```

**When not to use object Singleton:** Object declarations are loaded when the class is first referenced and live for the JVM lifetime. In test environments, you cannot easily replace them with mocks. For anything that needs DI or replacement in tests, use a class with a companion factory or just inject an instance.

### Factory Method — Companion Object + Named Factories

```kotlin
class PaymentProcessor private constructor(
    private val gateway: PaymentGateway,
    private val timeout: Duration
) {
    companion object {
        fun stripe(apiKey: String): PaymentProcessor =
            PaymentProcessor(StripeGateway(apiKey), Duration.ofSeconds(30))

        fun paypal(clientId: String, secret: String): PaymentProcessor =
            PaymentProcessor(PayPalGateway(clientId, secret), Duration.ofSeconds(45))

        fun mock(): PaymentProcessor =
            PaymentProcessor(MockGateway(), Duration.ofSeconds(1))
    }
}

// Usage:
val processor = PaymentProcessor.stripe(apiKey)
val testProcessor = PaymentProcessor.mock()
```

### Builder Pattern — Named and Default Parameters

```kotlin
// Java Builder: ~40 lines; Kotlin equivalent:
data class QueryConfig(
    val table: String,
    val limit: Int = 100,
    val offset: Int = 0,
    val orderBy: String = "id",
    val ascending: Boolean = true,
    val filters: List<Filter> = emptyList()
)

// Callers specify only what they need:
val config = QueryConfig(table = "orders", limit = 50, filters = listOf(activeFilter))
```

When you genuinely need a builder (e.g., Java interop, validation logic that crosses multiple fields), use `apply`:

```kotlin
class Query private constructor(val sql: String, val params: List<Any>) {

    class Builder {
        private var table: String = ""
        private val conditions = mutableListOf<String>()
        private val params = mutableListOf<Any>()

        fun from(table: String) = apply { this.table = table }
        fun where(condition: String, vararg args: Any) = apply {
            conditions.add(condition)
            params.addAll(args)
        }
        fun build(): Query {
            require(table.isNotBlank()) { "Table must be specified" }
            val sql = buildString {
                append("SELECT * FROM $table")
                if (conditions.isNotEmpty()) append(" WHERE ${conditions.joinToString(" AND ")}")
            }
            return Query(sql, params)
        }
    }
}

val query = Query.Builder().from("orders").where("status = ?", "active").build()
```

---

## 2. Structural Patterns

### Decorator — Extension Functions and Delegation

**Extension function as lightweight decoration:**

```kotlin
// Add retry behavior to any suspend function without wrapping
suspend fun <T> withRetry(
    maxAttempts: Int = 3,
    delayMs: Long = 1000,
    block: suspend () -> T
): T {
    var lastException: Exception? = null
    repeat(maxAttempts) { attempt ->
        try {
            return block()
        } catch (e: Exception) {
            lastException = e
            if (attempt < maxAttempts - 1) delay(delayMs)
        }
    }
    throw lastException!!
}

// Usage:
val user = withRetry(maxAttempts = 3) { userService.getUser(id) }
```

**`by` delegation as zero-boilerplate Decorator:**

```kotlin
interface Cache<K, V> {
    fun get(key: K): V?
    fun put(key: K, value: V)
    fun invalidate(key: K)
}

// MetricsCache decorates any Cache implementation — delegates everything + adds metrics
class MetricsCache<K, V>(
    private val delegate: Cache<K, V>,
    private val metrics: MetricsService
) : Cache<K, V> by delegate {

    override fun get(key: K): V? {
        val start = System.nanoTime()
        return delegate.get(key).also {
            val hit = it != null
            metrics.record("cache.${if (hit) "hit" else "miss"}", System.nanoTime() - start)
        }
    }
    // put() and invalidate() are auto-delegated — no override needed
}
```

### Adapter — Extension Functions

```kotlin
// Adapt a third-party type to your domain interface
// Without wrapper class:
fun ThirdPartyUser.toDomain(): User = User(
    id = this.userId.toLong(),
    email = this.emailAddress,
    name = "${this.firstName} ${this.lastName}"
)

// No adapter class needed — the extension IS the adapter
val user: User = thirdPartyClient.getUser(id).toDomain()
```

### Composite — Sealed Classes + Recursion

```kotlin
sealed interface Expr {
    data class Number(val value: Double) : Expr
    data class Add(val left: Expr, val right: Expr) : Expr
    data class Multiply(val left: Expr, val right: Expr) : Expr
    data class Negate(val expr: Expr) : Expr
}

fun evaluate(expr: Expr): Double = when (expr) {
    is Expr.Number   -> expr.value
    is Expr.Add      -> evaluate(expr.left) + evaluate(expr.right)
    is Expr.Multiply -> evaluate(expr.left) * evaluate(expr.right)
    is Expr.Negate   -> -evaluate(expr.expr)
}

// The sealed hierarchy + recursive when = Composite pattern with exhaustiveness guarantee
val expression = Expr.Add(
    Expr.Multiply(Expr.Number(3.0), Expr.Number(4.0)),
    Expr.Negate(Expr.Number(2.0))
)
println(evaluate(expression))  // (3 * 4) + (-2) = 10.0
```

---

## 3. Behavioral Patterns

### Strategy — `@FunctionalInterface` / Lambda Parameter

```kotlin
// Java: create an interface + multiple implementing classes
// Kotlin: just use a function type
class Sorter<T>(private val comparator: Comparator<T>) {
    fun sort(items: MutableList<T>) = items.sortWith(comparator)
}

// Or even simpler — the strategy IS the lambda
fun <T> List<T>.sortedWith(strategy: (T, T) -> Int): List<T> =
    sortedWith(Comparator(strategy))

// Strategies as named properties (readable)
val byName: (User, User) -> Int = compareBy { it.name }
val byAge: (User, User) -> Int = compareByDescending { it.age }
val byNameThenAge: Comparator<User> = compareBy<User> { it.name }.thenByDescending { it.age }
```

### Observer — `SharedFlow` / `StateFlow`

```kotlin
// EventBus using SharedFlow — all subscribers receive every emission
object EventBus {
    private val _events = MutableSharedFlow<AppEvent>(extraBufferCapacity = 64)
    val events: SharedFlow<AppEvent> = _events.asSharedFlow()

    suspend fun publish(event: AppEvent) = _events.emit(event)
}

// Subscribers:
scope.launch {
    EventBus.events
        .filterIsInstance<AppEvent.UserCreated>()
        .collect { event -> sendWelcomeEmail(event.user) }
}

scope.launch {
    EventBus.events
        .filterIsInstance<AppEvent.OrderPlaced>()
        .collect { event -> updateInventory(event.order) }
}
```

### Command Pattern — Data Classes + Sealed Interfaces

```kotlin
sealed interface UserCommand
data class CreateUser(val name: String, val email: String) : UserCommand
data class UpdateEmail(val userId: Long, val newEmail: String) : UserCommand
data class DeleteUser(val userId: Long) : UserCommand

class UserCommandHandler {
    suspend fun handle(command: UserCommand) = when (command) {
        is CreateUser    -> createUser(command.name, command.email)
        is UpdateEmail   -> updateEmail(command.userId, command.newEmail)
        is DeleteUser    -> deleteUser(command.userId)
    }  // exhaustive — compiler error if new command type added without handling
}
```

**Bonus:** Commands as `data class` gives you free `equals`/`hashCode` for deduplication and `toString` for logging/audit trails.

### Visitor Pattern — Sealed Classes + `when` (Modern Replacement)

```kotlin
// Java: Visitor interface with visitX() for each type — adding new types requires
// changing every Visitor implementation. Kotlin sealed + when eliminates this:

sealed interface Document
data class PdfDocument(val path: String, val pages: Int) : Document
data class WordDocument(val path: String, val content: String) : Document
data class SpreadsheetDocument(val path: String, val sheets: Int) : Document

// "Visitor" is now just a function with exhaustive when:
fun previewDocument(doc: Document): String = when (doc) {
    is PdfDocument         -> "PDF: ${doc.pages} pages from ${doc.path}"
    is WordDocument        -> "Word: ${doc.content.take(100)}"
    is SpreadsheetDocument -> "Spreadsheet: ${doc.sheets} sheets"
}

fun sizeEstimate(doc: Document): Long = when (doc) {
    is PdfDocument         -> doc.pages * 50_000L
    is WordDocument        -> doc.content.length * 2L
    is SpreadsheetDocument -> doc.sheets * 200_000L
}
```

**Trade-off:** Adding a new `Document` type forces you to update every `when` block (compiler enforces this — missing arm = compile error). This is the inverse of the classic Visitor trade-off (easy to add types, hard to add operations). For Kotlin principal interviews: sealed+when is better when **types are fixed** and **operations are added frequently**.

### State Machine — Sealed Classes

```kotlin
sealed interface OrderState {
    object Pending : OrderState
    data class Confirmed(val confirmationId: String) : OrderState
    data class Shipped(val trackingNumber: String, val carrier: String) : OrderState
    data class Delivered(val deliveredAt: Instant) : OrderState
    data class Cancelled(val reason: String) : OrderState
}

class Order(initialState: OrderState = OrderState.Pending) {
    var state: OrderState = initialState
        private set

    fun confirm(confirmationId: String) {
        state = when (val current = state) {
            is OrderState.Pending -> OrderState.Confirmed(confirmationId)
            else -> throw IllegalStateException("Cannot confirm from $current")
        }
    }

    fun ship(trackingNumber: String, carrier: String) {
        state = when (val current = state) {
            is OrderState.Confirmed -> OrderState.Shipped(trackingNumber, carrier)
            else -> throw IllegalStateException("Cannot ship from $current")
        }
    }
}
```

---

## 4. Kotlin-Specific Patterns

### The Result Type Pattern

```kotlin
// Kotlin's built-in Result<T> for error handling without exceptions
fun divide(a: Int, b: Int): Result<Int> = runCatching {
    if (b == 0) throw ArithmeticException("division by zero")
    a / b
}

val result = divide(10, 0)
result.fold(
    onSuccess = { value -> println("Result: $value") },
    onFailure = { error -> println("Error: ${error.message}") }
)

// Chain results:
divide(10, 2)
    .map { it * 3 }
    .mapCatching { it.toString() }
    .getOrDefault("error")
```

For domain-driven error handling, model errors explicitly:

```kotlin
sealed interface UserResult<out T> {
    data class Success<T>(val value: T) : UserResult<T>
    data class NotFound(val userId: Long) : UserResult<Nothing>
    data class Unauthorized(val reason: String) : UserResult<Nothing>
    data class ValidationError(val errors: List<String>) : UserResult<Nothing>
}

suspend fun getUser(id: Long, requesterId: Long): UserResult<User> {
    val user = userRepository.findById(id) ?: return UserResult.NotFound(id)
    if (!authorizer.canAccess(requesterId, user)) return UserResult.Unauthorized("insufficient permissions")
    return UserResult.Success(user)
}

// Call site — exhaustive when
when (val result = getUser(id, requesterId)) {
    is UserResult.Success -> renderUser(result.value)
    is UserResult.NotFound -> return404()
    is UserResult.Unauthorized -> return403()
    is UserResult.ValidationError -> renderErrors(result.errors)
}
```

### Lazy Initialization of Expensive Resources

```kotlin
class ReportGenerator(private val config: ReportConfig) {
    // Initialized once on first access; thread-safe by default
    private val templateEngine by lazy { TemplateEngine.build(config.templateDir) }
    private val pdfRenderer by lazy { PdfRenderer.create(config.fontDir) }

    // These are only initialized if the corresponding generate method is called
    fun generateHtml(data: ReportData): String = templateEngine.render(data)
    fun generatePdf(data: ReportData): ByteArray = pdfRenderer.render(data)
}
```

### Scope Functions as Transaction Pattern

```kotlin
suspend fun transferFunds(fromId: Long, toId: Long, amount: BigDecimal) {
    db.transaction {  // 'this' = TransactionScope inside
        val from = findAccount(fromId).also {
            require(it.balance >= amount) { "Insufficient funds" }
        }
        val to = findAccount(toId)

        from.debit(amount)
        to.credit(amount)

        save(from)
        save(to)
        auditLog.record(Transfer(fromId, toId, amount, Instant.now()))
    }  // transaction committed if no exception, rolled back otherwise
}
```

### Coroutine-Based Actor Pattern

```kotlin
// Actor: single coroutine processes all messages serially — eliminates shared mutable state
sealed interface CounterMessage
data class Increment(val by: Int = 1) : CounterMessage
data class GetCount(val response: CompletableDeferred<Int>) : CounterMessage

fun CoroutineScope.counterActor(): SendChannel<CounterMessage> = actor {
    var count = 0
    for (message in channel) {  // processes messages sequentially — no locking needed
        when (message) {
            is Increment -> count += message.by
            is GetCount  -> message.response.complete(count)
        }
    }
}

// Usage:
val counter = scope.counterActor()
counter.send(Increment(5))
counter.send(Increment(3))
val response = CompletableDeferred<Int>()
counter.send(GetCount(response))
println(response.await())  // 8 — no race condition, no locks
```

---

## 5. Anti-Patterns to Recognize in Code Review

### Overusing `!!`

```kotlin
// Bad: !! everywhere = Java null pointer safety thrown away
val name = user!!.profile!!.displayName!!

// Better: model nullable path explicitly
val name = user?.profile?.displayName ?: "Anonymous"

// Or: design the API to not have nulls at this layer
data class UserProfile(val displayName: String)  // non-nullable
data class User(val profile: UserProfile)          // non-nullable
```

### Misusing `apply` When You Need the Result

```kotlin
// Bad: using apply when you want to compute a value
val message = user.apply {
    lastLogin = Instant.now()
}.let { "Welcome ${it.name}" }  // extra let needed

// Better: apply for configuration, let for transformation
val message = user.also { it.lastLogin = Instant.now() }
    .run { "Welcome $name" }
// Or even simpler:
user.lastLogin = Instant.now()
val message = "Welcome ${user.name}"
```

### Companion Object Holding Application State

```kotlin
// Bad: companion object as a global state bag
class UserRepository {
    companion object {
        var connection: DatabaseConnection? = null  // global mutable state
        val cache = HashMap<Long, User>()           // uncontrolled cache
    }
}

// Better: inject dependencies, use proper DI container
class UserRepository(
    private val connection: DatabaseConnection,
    private val cache: Cache<Long, User>
)
```

### Creating Coroutines Without a Scope (GlobalScope)

```kotlin
// Bad: GlobalScope is unstructured — coroutines leak, can't be cancelled
GlobalScope.launch {
    loadData()
}

// Better: use an injected scope tied to a lifecycle
class DataLoader(private val scope: CoroutineScope) {
    fun load() = scope.launch { loadData() }
}
```

---

## Interview Q&A

### Q1 `[Principal]` Kotlin sealed classes replace the Visitor pattern. When would you still choose the Visitor pattern (or its equivalent) in Kotlin?

**Answer:**

The sealed+when approach is better when you know all types upfront and add operations frequently. Visitor is better when the type hierarchy is open or grows independently of the operations.

**Kotlin scenario where Visitor-like dispatch still makes sense:**

1. **Open hierarchies across module boundaries.** If `Document` types are defined in separate modules (third-party types, plugin-defined types), you can't use `sealed`. You need double-dispatch.

2. **AST processing in compilers.** Compiler phases (type-checking, optimization, code generation) are operations on a large, fixed AST node hierarchy. But the operations accumulate and are defined across packages. A visitor interface with `acceptVisitor(v)` keeps each phase's logic cohesive.

3. **Performance-critical hot paths where virtual dispatch is explicitly faster than `when`.** Sealed+when compiles to a `tableswitch` or `lookupswitch` JVM bytecode; Visitor is two virtual calls. For very tight loops over heterogeneous types, measure.

**The Kotlin idiom for extensible dispatch (open hierarchy):** Extension functions on an interface + type-safe casts — not pretty, but it's the Kotlin way when you don't control the sealed hierarchy:

```kotlin
// Interface from library you can't modify
interface Shape

// Dispatch extension with contract-like documentation
fun Shape.renderTo(canvas: Canvas) = when (this) {
    is Circle    -> canvas.drawCircle(this.cx, this.cy, this.radius)
    is Rectangle -> canvas.drawRect(this.x, this.y, this.width, this.height)
    else         -> logger.warn("Unknown shape type: ${this::class.simpleName}")
}
```

---

### Q2 `[Principal]` Explain the `object` singleton vs. a class with a companion object factory. In a dependency-injection environment (Hilt, Koin, Spring), which do you use and why?

**Answer:**

**`object` singleton problems in DI:**
- It's instantiated by the JVM class loader, not the DI container — the container can't inject dependencies into it.
- It cannot be replaced in tests without reflection or test-specific wiring.
- Its lifecycle is the JVM lifetime — no scope management (request-scope, session-scope, etc.).

**In a DI environment:** Use a regular class with a companion factory (or just let the DI container manage construction):

```kotlin
// Koin definition:
val networkModule = module {
    single { HttpClient { install(JsonPlugin) } }
    factory { UserRepository(get()) }
    scoped { UserService(get(), get()) }
}

// The class is not an object — it has constructor injection, is mockable in tests
class UserService(
    private val repository: UserRepository,
    private val cache: Cache<Long, User>
) {
    // ...
}
```

**When `object` is fine:** Utility objects with no external dependencies and no need for test replacement:

```kotlin
object JsonSerializer {
    private val mapper = ObjectMapper().apply { configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false) }
    fun <T> toJson(value: T): String = mapper.writeValueAsString(value)
    inline fun <reified T> fromJson(json: String): T = mapper.readValue(json, T::class.java)
}
```

---

### Q3 `[Principal]` A data class is used as a `HashMap` key. A developer changes one field from `val` to `var` for "convenience." What breaks and how do you enforce immutability at the API level?

**Answer:**

`data class` generates `hashCode()` based on constructor properties. If a property is `var` and mutates after the object is placed in a `HashMap`, the key's `hashCode` changes — the key is now in the wrong bucket and the map **cannot find it**:

```kotlin
data class CacheKey(var service: String, val endpoint: String)

val cache = HashMap<CacheKey, Response>()
val key = CacheKey("user-service", "/api/user")
cache[key] = fetchUser()

key.service = "order-service"  // mutate the key!
println(cache[key])            // null — key is in the wrong hash bucket
println(cache.size)            // 1 — the entry is still there, but unfindable
```

This is an invisible memory leak: entries accumulate but are never retrievable or evictable.

**Enforcing immutability at the API level:**

1. **All `val` in data classes used as map keys.** Code review rule. Enforce with a lint check (Detekt rule: `DataClassContainsFunctions` covers some of this; custom rules can enforce all-val for data classes implementing `hashCode`).

2. **Sealed interface with a `@Immutable` annotation** processed by an annotation processor.

3. **Value class as a key wrapper:**

```kotlin
@JvmInline
value class CacheKey private constructor(val raw: String) {
    companion object {
        fun of(service: String, endpoint: String) = CacheKey("$service:$endpoint")
    }
}
// A value class wrapping a String is always immutable and has correct equals/hashCode
```

4. **Defensive API design:** Don't expose mutable data classes in public APIs. Return immutable snapshots. Use Kotlin's `copy()` for "mutation" — creates a new object, doesn't invalidate existing map entries.

---

*See also:* [01-language-features-and-idioms.md](01-language-features-and-idioms.md) for sealed classes and object declarations | [02-coroutines-deep-dive.md](02-coroutines-deep-dive.md) for the actor pattern with Channels | [../java/06-design-patterns-java-idioms.md](../java/06-design-patterns-java-idioms.md) for the Java perspective on these patterns
