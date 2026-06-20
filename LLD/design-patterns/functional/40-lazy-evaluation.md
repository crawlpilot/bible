# 40. Lazy Evaluation
**Category**: Functional Programming  
**GoF**: No (FP / Language theory)  
**Complexity**: Low–Medium  
**Frequency in FAANG interviews**: Common

> Lazy evaluation defers computation until its result is actually needed — values are not computed on creation but on first access, and infinite or expensive sequences can be described without exhausting memory or CPU.

---

## Problem It Solves

A search service has 10 million products. Building `List<Product>` for every query would exhaust memory before a single result is returned. With lazy evaluation, `stream().filter(...).map(...).limit(20)` describes the computation; the actual work is deferred until `collect()`. Only the 20 needed products are ever fetched, filtered, and mapped. Two key benefits:
1. **Short-circuit optimisation** — only process as much as needed
2. **Infinite sequences** — describe an infinite series without computing it all; take only what you need

## Structure

```
Eager (strict):
  source → [build all] → [filter all] → [map all] → result
  Memory peak = N elements at every stage

Lazy (deferred):
  source → describe filter → describe map → describe limit
                                                  ↓
                                           pull one element at a time
                                           until limit reached → result
  Memory peak = O(1) elements in flight
```

---

## Real-World Use Case: Product Search with Large Catalog

A catalog service has 10M products. The search query filters by category, maps to DTOs, and paginates. With lazy streams, only the 20 products on the current page ever materialise.

### Java — Stream API (lazy by design)

```java
// All intermediate operations are LAZY — nothing runs until a terminal op
Stream<ProductDto> searchStream = productRepository.streamAll()   // lazy source
    .filter(p -> p.categoryPath().startsWith(category))          // lazy filter
    .filter(p -> p.price().compareTo(maxPrice) <= 0)             // lazy filter
    .filter(p -> p.stockQuantity() > 0)                          // lazy filter
    .map(ProductMapper::toDto)                                    // lazy map
    .sorted(Comparator.comparing(ProductDto::rating).reversed()); // lazy sort

// Terminal operation triggers ALL lazy steps above
List<ProductDto> page = searchStream
    .skip((long) pageNumber * pageSize)
    .limit(pageSize)              // terminal: pulls only pageSize elements
    .collect(toList());

// Lazy vs eager — the difference
List<Product> eager = productRepository.findAll()   // loads ALL 10M into memory NOW
    .stream()
    .filter(...).collect(toList());

Stream<Product> lazy = productRepository.streamAll() // loads NOTHING until terminal op
    .filter(...);

// Infinite stream — describe without generating
Stream<Integer> naturals = Stream.iterate(0, n -> n + 1);  // infinite: 0,1,2,3,...
Stream<Long> fibonacci = Stream.iterate(
    new long[]{0, 1}, pair -> new long[]{pair[1], pair[0] + pair[1]}
).map(pair -> pair[0]);

// Take only what you need
List<Integer> first100Primes = naturals
    .filter(PrimeChecker::isPrime)
    .limit(100)
    .collect(toList());

// Lazy loading with Supplier
public class LazyConnection<T> {
    private final Supplier<T> factory;
    private T instance;

    public LazyConnection(Supplier<T> factory) {
        this.factory = factory;
    }

    public T get() {
        if (instance == null) {
            instance = factory.get();  // created on first access
        }
        return instance;
    }
}

// Thread-safe lazy initialisation (double-checked locking)
public class LazyService {
    private volatile ExpensiveService service;

    public ExpensiveService getService() {
        if (service == null) {
            synchronized (this) {
                if (service == null) {
                    service = new ExpensiveService();  // lazy, thread-safe
                }
            }
        }
        return service;
    }
}

// Optional.map is lazy — the function only runs if value is present
Optional<String> email = userRepository.findById(userId)
    .map(User::getEmail)       // only runs if user found
    .map(String::toLowerCase); // only runs if email non-null
```

### Kotlin — Sequence vs List and lazy delegation

```kotlin
// Sequence is Kotlin's lazy Stream equivalent
val page: List<ProductDto> = productRepository.all()    // Sequence<Product> (lazy source)
    .filter { it.categoryPath.startsWith(category) }    // lazy
    .filter { it.price <= maxPrice }                    // lazy
    .map { it.toDto() }                                 // lazy
    .drop(pageNumber * pageSize)
    .take(pageSize)                                     // terminal: pulls only pageSize
    .toList()                                           // materialise

// Sequence vs List — when each makes sense
val listResult = listOf(1..1_000_000)
    .filter { it % 2 == 0 }   // eager: builds List<Int> of 500_000 elements
    .map { it * it }           // eager: builds another List<Int>
    .first()                   // only needs one element — wasted 999_999 computations

val seqResult = (1..1_000_000).asSequence()
    .filter { it % 2 == 0 }   // lazy: no computation yet
    .map { it * it }           // lazy: no computation yet
    .first()                   // computes ONLY until first match found (element 2)

// Infinite sequence
val naturals = generateSequence(1) { it + 1 }      // infinite: 1,2,3,...
val first10Primes = naturals.filter(::isPrime).take(10).toList()

val fibonacci: Sequence<Long> = sequence {
    var a = 0L; var b = 1L
    while (true) {
        yield(a)               // suspends here until next element requested
        val next = a + b; a = b; b = next
    }
}
val first20Fib = fibonacci.take(20).toList()

// by lazy — lazy property initialisation
class UserService(private val config: Config) {
    private val db: Database by lazy {
        Database.connect(config.dbUrl)   // created only on first access to `db`
    }

    private val emailClient: EmailClient by lazy {
        EmailClient(config.smtpHost)     // created only if email is ever sent
    }

    fun sendWelcome(userId: String) {
        val user = db.findUser(userId)   // db initialised here on first call
        emailClient.send(user.email, "welcome") // emailClient initialised here
    }
}

// Lazy parameter evaluation via lambda
fun expensiveQuery(): List<User> = db.query("SELECT * FROM users WHERE ...")

// EAGER: always evaluates expensiveQuery() before the function runs
fun logIfDebugEager(message: String, data: List<User>) { ... }
logIfDebugEager("Users: ", expensiveQuery())  // query runs even if debug logging is off

// LAZY: only evaluates if debug is enabled
fun logIfDebugLazy(message: String, data: () -> List<User>) {
    if (isDebugEnabled) println("$message ${data()}")  // query runs only if needed
}
logIfDebugLazy("Users: ") { expensiveQuery() }
```

### Python — generators and itertools

```python
from typing import Iterator, Generator, Iterable
import itertools

# Generator function — lazy sequence via yield
def product_stream(category: str) -> Generator[dict, None, None]:
    offset = 0
    while True:
        batch = db.query(
            "SELECT * FROM products WHERE category = %s LIMIT 1000 OFFSET %s",
            (category, offset)
        )
        if not batch:
            break
        for product in batch:
            yield product          # suspends here; resumes on next()
        offset += 1000

# Lazy pipeline — each step is an iterator, nothing runs until consumed
def search_products(category: str, max_price: float, page: int, size: int):
    source     = product_stream(category)                        # lazy
    filtered   = (p for p in source if p['price'] <= max_price) # lazy generator expr
    mapped     = (to_dto(p) for p in filtered)                   # lazy
    paginated  = itertools.islice(mapped, page * size, (page + 1) * size)  # lazy
    return list(paginated)         # materialises ONLY the current page

# Infinite generator
def naturals(start: int = 1) -> Generator[int, None, None]:
    n = start
    while True:
        yield n
        n += 1

def fibonacci() -> Generator[int, None, None]:
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

first_10_primes = list(itertools.islice(
    filter(is_prime, naturals()),
    10
))

# itertools — lazy combinatorics
pairs = itertools.product([1, 2, 3], ['a', 'b', 'c'])  # lazy cartesian product
first_5 = list(itertools.islice(pairs, 5))              # takes only 5

# Lazy file reading — don't load entire file into memory
def read_large_log(path: str, error_pattern: str) -> Iterator[str]:
    with open(path) as f:
        for line in f:             # file iterator is lazy
            if error_pattern in line:
                yield line.strip() # yield one at a time

# @property as lazy computation
class UserStats:
    def __init__(self, user_id: str):
        self.user_id = user_id
        self._stats = None

    @property
    def stats(self) -> dict:
        if self._stats is None:
            self._stats = stats_service.compute(self.user_id)  # computed once on first access
        return self._stats
```

### JavaScript / TypeScript — generators and lazy iterables

```typescript
// Generator function — lazy sequence
function* productStream(category: string): Generator<Product> {
    let offset = 0;
    while (true) {
        const batch = await db.query(`SELECT * FROM products WHERE category = $1 LIMIT 1000 OFFSET $2`, [category, offset]);
        if (batch.length === 0) return;
        for (const product of batch) {
            yield product;         // pauses here; resumes on next()
        }
        offset += 1000;
    }
}

// Lazy iterator pipeline
function* filter<T>(iterable: Iterable<T>, pred: (x: T) => boolean): Generator<T> {
    for (const x of iterable) if (pred(x)) yield x;
}

function* map<T, U>(iterable: Iterable<T>, f: (x: T) => U): Generator<U> {
    for (const x of iterable) yield f(x);
}

function* take<T>(iterable: Iterable<T>, n: number): Generator<T> {
    let count = 0;
    for (const x of iterable) {
        if (count++ >= n) return;
        yield x;
    }
}

// Compose lazy pipeline — nothing runs until consumed
const pipeline = take(
    map(
        filter(productStream('electronics'), p => p.price <= 500),
        toDto
    ),
    20
);

const page: ProductDto[] = [...pipeline];  // materialise 20 items

// Infinite sequences
function* naturals(): Generator<number> {
    let n = 1;
    while (true) yield n++;
}

function* fibonacci(): Generator<number> {
    let [a, b] = [0, 1];
    while (true) { yield a; [a, b] = [b, a + b]; }
}

const first10Primes = [...take(filter(naturals(), isPrime), 10)];

// RxJS — reactive lazy streams
import { from, interval } from 'rxjs';
import { filter, map, take } from 'rxjs/operators';

const priceAlerts$ = from(productStream('electronics')).pipe(
    filter(p => p.priceChanged),
    map(p => ({ sku: p.sku, newPrice: p.price })),
    take(100)
);

priceAlerts$.subscribe(alert => console.log(alert));  // pulls lazily
```

---

## Eager vs Lazy — Decision Guide

| Scenario | Use | Why |
|----------|-----|-----|
| Process all N elements, always | Eager (List) | Simpler, better cache locality |
| Process first K of N (K << N) | Lazy (Stream/Sequence) | Avoid computing N-K wasted elements |
| Infinite sequence | Lazy required | Eager is infinite memory |
| Pipeline with early exit (findFirst, anyMatch) | Lazy | Short-circuit stops at first match |
| Small collections (< 1000) | Either | Lazy overhead may dominate |
| IO-bound per element (DB, network) | Lazy | Pull-based avoids over-fetching |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each pipeline step has one job; deferral is the container's job |
| Open/Closed | ✅ | Add pipeline steps without modifying existing steps |
| Liskov Substitution | ✅ | Lazy sequence and eager list both satisfy `Iterable` |
| Interface Segregation | ✅ | Consumers use `Iterable`/`Iterator`; they don't care if lazy |
| Dependency Inversion | ✅ | Processing logic depends on `Iterable`, not `ArrayList` |

---

## When to Use

- Processing large or potentially infinite datasets where you only need a subset
- Building pipelines where early termination is common (`findFirst`, `anyMatch`, `limit`)
- Expensive initialisation that may never be needed (`by lazy`, `Supplier`)
- Reading large files or streams without loading everything into memory

## When NOT to Use

- You need the full result anyway — lazy has overhead (iterator state machines)
- Multiple passes over the same data — streams/generators are single-pass; collect to list first
- Debugging — lazy pipelines are harder to step through
- Shared stream — Java Streams are single-use; collecting to a list before sharing is safer

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Memory O(1) per element in pipeline | Single-pass — can't reuse a Stream/Generator |
| Short-circuit saves CPU and IO | Stack traces through lazy iterators are harder to read |
| Infinite sequences are expressible | Lazy bugs can be subtle — side effects in a lazy step may never run |
| Natural backpressure in pull-based pipelines | Sorting a lazy stream forces full materialisation anyway |

---

**FAANG interview application**: "When I see a query that returns 10M rows but the caller only needs the first 20, I reach for lazy evaluation. In Java, `Stream` is lazy by default — all intermediate operations are descriptors, not results. The terminal operation (`collect`, `findFirst`, `limit`) triggers the pull. In Kotlin I use `Sequence` instead of `List` for the same reason — `asSequence()` turns a List pipeline into a lazy one with zero other changes. The canonical interviewer question: 'why use Stream instead of Collection?' Answer: lazy composition, O(1) memory pipeline, and short-circuit operations."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Functor](33-functor.md) | `Stream.map` is a lazy functor operation |
| [Monad](34-monad.md) | `Stream.flatMap` is a lazy monad operation |
| [Memoization](41-memoization.md) | Memoization caches the result of lazy computation after first evaluation |
| [Proxy](../structural/12-proxy.md) | Virtual proxy is lazy instantiation — create the real object on first use |
