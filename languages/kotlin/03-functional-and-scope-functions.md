# 03 — Functional Programming and Scope Functions

**Calibration:** Principal Engineer bar — Google / Meta / Amazon  
**Focus:** Kotlin's functional idioms, when each scope function is correct, Sequences vs. eager collections, DSL building blocks.

---

## 1. Scope Functions — The `let / run / apply / also / with` Decision Matrix

Five scope functions that look similar but differ on two axes:

| Function | Receiver in block | Return value | Usage |
|----------|------------------|--------------|-------|
| `let` | `it` (lambda arg) | Lambda result | Null-safe block, transform a value |
| `run` | `this` (extension) | Lambda result | Execute code on object, return computed value |
| `apply` | `this` (extension) | The receiver | Configure an object (builder-style) |
| `also` | `it` (lambda arg) | The receiver | Side effects without changing the object |
| `with` | `this` (non-extension) | Lambda result | Group operations on an object you already have |

### `let` — Transform or Null-Safe Block

```kotlin
// Primary use case 1: null-safe block
val user: User? = findUser(id)
user?.let { u ->
    sendEmail(u.email)
    audit.log("email sent to ${u.id}")
}

// Primary use case 2: transform a value
val name: String = rawInput
    .trim()
    .let { it.ifBlank { "anonymous" } }
    .also { logger.debug("Processed name: $it") }

// Primary use case 3: limit scope of a variable
val result = heavyCalculation().let { intermediate ->
    // intermediate only exists within this block
    transform(intermediate)
}
```

### `apply` — Builder Pattern Replacement

```kotlin
// Old Java pattern: builder object
val config = ConnectionConfig.Builder()
    .host("localhost")
    .port(5432)
    .timeout(Duration.ofSeconds(30))
    .build()

// Kotlin apply: configure any object, get the object back
val config = ConnectionConfig().apply {
    host = "localhost"
    port = 5432
    timeout = Duration.ofSeconds(30)
}

// Fluent initialization of a data structure
val headers = HashMap<String, String>().apply {
    put("Content-Type", "application/json")
    put("Authorization", "Bearer $token")
    put("X-Request-Id", UUID.randomUUID().toString())
}
```

### `also` — Side Effects Without Interrupting the Chain

```kotlin
// also returns the receiver — chain continues uninterrupted
val user = createUser(name, email)
    .also { logger.info("Created user ${it.id}") }
    .also { metricsService.increment("user.created") }
    .also { auditTrail.record(AuditEvent.UserCreated(it)) }
// user is still the User object — also didn't transform it
```

### `run` — Compute a Value From an Object's Context

```kotlin
// run as an extension: gives you this = the object
val message: String = user.run {
    if (isAdmin) "Welcome, admin ${name}" else "Welcome, ${name}"
}

// run without receiver: create a scope for a block of code
val config = run {
    val env = System.getenv("ENV") ?: "dev"
    val baseUrl = if (env == "prod") "https://api.example.com" else "http://localhost:8080"
    Config(env, baseUrl)
}
```

### `with` — Multiple Operations on the Same Object

```kotlin
// Use when you already have the object and just want to call multiple methods
with(htmlDocument) {
    appendTitle("Report")
    appendBody(generateContent())
    appendFooter(date)
}

// Equivalent to:
htmlDocument.appendTitle("Report")
htmlDocument.appendBody(generateContent())
htmlDocument.appendFooter(date)
```

**`with` vs `run`:** Identical semantics, different call style. `with(obj) { ... }` vs `obj.run { ... }`. Prefer `run` for nullable receivers (`obj?.run { ... }` works; `with(null) { ... }` doesn't).

---

## 2. Higher-Order Functions and Function Types

```kotlin
// Function type: (InputType) -> ReturnType
val transform: (String) -> Int = { it.length }

// Function type with receiver: InputType.() -> ReturnType
val appendSuffix: String.(String) -> String = { suffix -> this + suffix }
"hello".appendSuffix("!")  // "hello!"

// Nullable function type
val optionalCallback: (() -> Unit)? = null
optionalCallback?.invoke()  // safe call on nullable function
```

### Passing Lambdas — Trailing Lambda Syntax

```kotlin
// Last parameter lambda can be moved outside parentheses
fun repeat(n: Int, action: (Int) -> Unit) {
    for (i in 0 until n) action(i)
}

repeat(3) { i -> println(i) }  // trailing lambda
repeat(3, { i -> println(i) }) // equivalent, less idiomatic
```

### `inline` Functions and Non-Local Returns

```kotlin
inline fun runSafely(action: () -> Unit) {
    try {
        action()
    } catch (e: Exception) {
        logger.error("Error", e)
    }
}

fun processItems(items: List<Item>) {
    items.forEach { item ->
        runSafely {
            if (item.isInvalid) return  // NON-LOCAL RETURN: returns from processItems
            process(item)
        }
    }
}
```

Non-local returns are only possible when the lambda is passed to an `inline` function. The lambda body is inlined into the calling function, so `return` exits the enclosing function. If you don't want this, use `return@label`:

```kotlin
items.forEach { item ->
    if (item.isInvalid) return@forEach  // local return — continues to next item
    process(item)
}
```

---

## 3. Sequences — Lazy Evaluation for Collections

`Sequence<T>` is to Kotlin collections what `Stream<T>` is to Java — lazy, pull-based evaluation.

```kotlin
// Eager (List operations): creates intermediate lists at each step
val result = (1..1_000_000)
    .filter { it % 2 == 0 }   // creates a list of 500,000 elements
    .map { it * it }            // creates another list of 500,000 elements
    .take(10)                   // creates a list of 10 elements
    .toList()

// Lazy (Sequence): elements pass through the pipeline one at a time
val result = (1..1_000_000)
    .asSequence()
    .filter { it % 2 == 0 }   // no allocation — sets up a filter step
    .map { it * it }            // no allocation — sets up a map step
    .take(10)                   // no allocation — sets up a take step
    .toList()                   // terminal: processes only until 10 elements pass all steps
```

For `take(10)`, the sequence version processes approximately 20 elements (finds 10 even numbers), while the eager version processes all 1,000,000. Same output, 50,000× less work.

### When to Use Sequences

```kotlin
// USE sequences when:
// 1. Pipeline with early termination (take, first, find, any, all)
val firstLongLine = fileLines.asSequence()
    .filter { it.length > 80 }
    .first()  // stops after finding the first match

// 2. Large collections with expensive intermediate steps
// 3. Infinite sequences:
val fibonacci: Sequence<Long> = sequence {
    var a = 0L
    var b = 1L
    while (true) {
        yield(a)
        val next = a + b
        a = b
        b = next
    }
}
fibonacci.take(20).toList()

// DON'T use sequences for:
// - Small collections (overhead of sequence wrapper exceeds benefit)
// - Operations without early termination on small-medium collections
// - Parallel operations (use streams or coroutines instead)
```

---

## 4. Kotlin Collections vs. Java Streams

```kotlin
// Kotlin collections are eager by default
val processed = items
    .filter { it.isActive }
    .map { it.toDto() }
    .sortedBy { it.name }

// Kotlin also has fold (left fold):
val sum = numbers.fold(0) { acc, n -> acc + n }
val product = numbers.fold(1L) { acc, n -> acc * n }

// groupBy — similar to Collectors.groupingBy
val byDepartment: Map<String, List<Employee>> = employees.groupBy { it.department }

// groupingBy + eachCount — like Collectors.groupingBy(counting())
val countByDepartment: Map<String, Int> = employees.groupingBy { it.department }.eachCount()

// flatMap — equivalent to Stream.flatMap
val allTags: List<String> = articles.flatMap { it.tags }

// partition — split into (matching, non-matching) — no Java equivalent
val (active, inactive) = users.partition { it.isActive }

// zip — pairwise combine two lists
val pairs: List<Pair<String, Int>> = names.zip(scores)

// windowed / chunked — sliding/tumbling windows
val batches: List<List<Item>> = items.chunked(100)  // batches of 100
val windows: List<List<Int>> = numbers.windowed(3)   // [1,2,3], [2,3,4], [3,4,5]...
```

---

## 5. DSL Building — Function Type with Receiver

Kotlin's function types with receivers (`T.() -> Unit`) enable type-safe builders — the basis of DSLs like Gradle's Kotlin DSL, Ktor, etc.

```kotlin
// Define a DSL for building an HTTP request
class HttpRequestBuilder {
    var method: String = "GET"
    var url: String = ""
    private val headers = mutableMapOf<String, String>()
    private var body: String? = null

    fun header(name: String, value: String) {
        headers[name] = value
    }

    fun body(content: String) {
        this.body = content
    }

    fun build(): HttpRequest = HttpRequest(method, url, headers, body)
}

// Builder function with receiver lambda
fun httpRequest(block: HttpRequestBuilder.() -> Unit): HttpRequest {
    return HttpRequestBuilder().apply(block).build()
}

// Usage — looks like a DSL, type-safe
val request = httpRequest {
    method = "POST"
    url = "https://api.example.com/users"
    header("Content-Type", "application/json")
    header("Authorization", "Bearer $token")
    body("""{"name": "Alice"}""")
}
```

### Nested DSL with `@DslMarker`

`@DslMarker` prevents calling outer scope functions from inside inner scope lambdas — prevents confusing DSL usage:

```kotlin
@DslMarker
annotation class HtmlDsl

@HtmlDsl
class HtmlBuilder {
    private val content = StringBuilder()

    fun div(block: DivBuilder.() -> Unit) {
        val div = DivBuilder()
        div.block()
        content.append(div.build())
    }

    fun build(): String = "<html>${content}</html>"
}

@HtmlDsl
class DivBuilder {
    private val content = StringBuilder()

    fun p(text: String) {
        content.append("<p>$text</p>")
    }

    fun build(): String = "<div>${content}</div>"
}

fun html(block: HtmlBuilder.() -> Unit): String = HtmlBuilder().apply(block).build()

// Usage
val page = html {
    div {
        p("Hello")
        div {   // ERROR if @DslMarker present: outer html's div can't be called here
            p("nested")
        }
    }
}
```

---

## 6. Operator Overloading

```kotlin
data class Vector2D(val x: Double, val y: Double) {
    operator fun plus(other: Vector2D) = Vector2D(x + other.x, y + other.y)
    operator fun minus(other: Vector2D) = Vector2D(x - other.x, y - other.y)
    operator fun times(scalar: Double) = Vector2D(x * scalar, y * scalar)
    operator fun unaryMinus() = Vector2D(-x, -y)

    // Component functions for destructuring
    operator fun component1() = x
    operator fun component2() = y
}

val v1 = Vector2D(1.0, 2.0)
val v2 = Vector2D(3.0, 4.0)
val v3 = v1 + v2          // calls plus()
val (x, y) = v3           // calls component1(), component2()

// invoke operator: makes an object callable like a function
class Multiplier(private val factor: Int) {
    operator fun invoke(n: Int): Int = n * factor
}
val triple = Multiplier(3)
triple(10)   // calls triple.invoke(10) = 30
```

---

## 7. `typealias` — Naming Complex Types

```kotlin
typealias UserId = Long
typealias Handler<T> = suspend (T) -> Unit
typealias EventMap = Map<String, List<Handler<UserEvent>>>

// Reduces noise:
fun registerHandler(eventType: String, handler: Handler<UserEvent>) { ... }
// vs:
fun registerHandler(eventType: String, handler: suspend (UserEvent) -> Unit) { ... }
```

**`typealias` vs `value class`:**
- `typealias` is a compile-time alias only — `UserId` and `Long` are the same type. No type safety.
- `value class UserId(val value: Long)` is a distinct type at compile time — you can't accidentally pass a `Long` where `UserId` is expected. Zero runtime overhead in non-generic contexts.

---

## Interview Q&A

### Q1 `[Principal]` `apply` and `also` both return the receiver. When do you use each and what is the bug introduced by using `apply` when you need `also`?

**Answer:**

`apply` gives you `this` = the receiver inside the block.  
`also` gives you `it` = the receiver inside the block.

The **`apply` bug:** If you accidentally shadow `this` in `apply`, or if you're inside a class method where `this` already means something, `apply` creates an ambiguous scope:

```kotlin
class UserService {
    private val users = mutableListOf<User>()

    fun addAndLog(user: User) {
        users.apply {
            add(user)          // this = users (MutableList) — correct
            logger.info(...)   // ERROR: logger is not a MutableList method
            // this inside apply = MutableList, not UserService
            // logger is resolved from UserService's scope (outer this) which is fine
            // but if you tried: this.logger.info — this = MutableList, no logger property
        }
    }
}
```

More concretely:

```kotlin
class Connection {
    private val pool = ConnectionPool().apply {
        maxSize = 10          // pool.maxSize — correct
        timeout = 30          // pool.timeout — correct
        // But if you write: logger.info("pool created") — 'this' is the pool,
        // which has no logger. You must use outer reference explicitly.
    }
}
```

`also` solves this by using `it` — unambiguous:

```kotlin
val pool = ConnectionPool().also { pool ->
    pool.maxSize = 10
    logger.info("pool created")  // 'this' still = the outer class, no ambiguity
}
```

**Rule:** Use `apply` for pure configuration of the object (all operations are on the object). Use `also` when you need to both configure AND reference the outer scope.

---

### Q2 `[Principal]` Explain non-local returns from lambdas. When are they allowed and what does this imply architecturally for higher-order function design?

**Answer:**

Non-local returns are allowed only in lambdas passed to `inline` functions. The lambda body is inlined at the call site, so `return` exits the enclosing function — not just the lambda.

```kotlin
inline fun findFirst(items: List<Item>, predicate: (Item) -> Boolean): Item? {
    for (item in items) {
        if (predicate(item)) return item  // local return — just exits the lambda
    }
    return null
}

fun processItems(items: List<Item>) {
    items.forEach { item ->
        if (item.isExpired) return  // non-local: exits processItems, not just forEach
        process(item)
    }
}
```

**Architectural implication:** When you design a library with `inline` higher-order functions, you're giving callers the ability to exit the **caller's** function from inside the lambda. This is powerful but surprising. Use `crossinline` to forbid non-local returns when you need to capture the lambda in another object:

```kotlin
inline fun launchAsync(crossinline action: () -> Unit) {
    thread {
        action()  // action is captured in Thread — non-local return would be invalid here
    }
}

// With crossinline, action cannot contain return — compile error at the call site
launchAsync {
    return  // COMPILE ERROR
}
```

Use `noinline` to pass a lambda parameter as a non-inlined object:

```kotlin
inline fun runWithCallbacks(
    noinline onSuccess: (String) -> Unit,  // stored as object
    action: () -> String                    // inlined
) {
    val result = action()                   // inlined — non-local return allowed
    successCallbacks.add(onSuccess)         // onSuccess is a real object
    onSuccess(result)
}
```

---

### Q3 `[Principal]` When does using a `Sequence` perform worse than a `List`, and how would you benchmark the crossover point?

**Answer:**

Sequences perform worse when:

1. **No early termination, small collections:** The overhead of the `Sequence` wrapper (object allocations for each step, virtual dispatch per element) exceeds the cost of allocating intermediate lists for a small N.

```kotlin
// For a list of 10 elements with no take/first:
// Sequence: 10 wrapper objects + virtual dispatch + no early termination benefit
// List: 10 elements in an array — likely faster due to CPU cache
```

2. **Stateful operations that must process all elements anyway:** `sorted()`, `distinct()`, `groupBy()` — these terminal operations cannot benefit from laziness because they need the full dataset.

3. **Parallel processing:** Sequences are single-threaded. Parallel streams or coroutines with `Flow` and `buffer()` are better.

**Benchmarking crossover:**

```kotlin
// Use JMH (Java Microbenchmark Harness) with Kotlin:
@Benchmark
fun eagerly(state: BenchmarkState): List<Int> {
    return state.list.filter { it % 2 == 0 }.map { it * it }.take(100).toList()
}

@Benchmark
fun lazily(state: BenchmarkState): List<Int> {
    return state.list.asSequence().filter { it % 2 == 0 }.map { it * it }.take(100).toList()
}
```

Empirically: the crossover is typically around **100–1,000 elements** depending on the operation cost. Below ~100 elements with no early termination, eager collections often win. Above ~10,000 with early termination, sequences win decisively.

---

*See also:* [01-language-features-and-idioms.md](01-language-features-and-idioms.md) for `inline` + `reified` | [02-coroutines-deep-dive.md](02-coroutines-deep-dive.md) for Flow vs. Sequence in async contexts
