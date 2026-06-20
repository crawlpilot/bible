# 41. Memoization
**Category**: Functional Programming  
**GoF**: No (FP / Dynamic Programming)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Memoization caches the return value of a pure function keyed by its input arguments — so repeated calls with the same arguments return the cached result instantly instead of recomputing.

---

## Problem It Solves

A recommendation engine calls `computeUserSimilarity(userA, userB)` thousands of times per request for a matrix of 500 users. The function is pure (deterministic, no side effects) and expensive (cosine similarity over 300-dimension embeddings). Without memoization: 500×499/2 = 124,750 computations per request. With memoization: each unique pair computed once, result reused for all subsequent lookups. This is dynamic programming's "table" as a general-purpose pattern: trade memory for time.

**Critical prerequisite**: memoization is **only correct for pure functions**. A function with side effects or that reads external state should not be memoized — the cached result may be stale.

## Structure

```
    ┌─────────────────────────────────────┐
    │         MemoizedFunction             │
    │                                     │
    │  cache: Map<Args, Result>           │
    │                                     │
    │  apply(args):                       │
    │    if cache.contains(args):         │
    │        return cache.get(args)       │  ← O(1)
    │    result = originalFn(args)        │  ← O(f) — computed once
    │    cache.put(args, result)          │
    │    return result                    │
    └─────────────────────────────────────┘
```

---

## Real-World Use Case: Recommendation Scoring and Price Computation

### Java — ConcurrentHashMap.computeIfAbsent

```java
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.function.BiFunction;

// Generic memoize wrapper for unary functions
public class Memoize {
    public static <K, V> Function<K, V> of(Function<K, V> fn) {
        Map<K, V> cache = new ConcurrentHashMap<>();
        return key -> cache.computeIfAbsent(key, fn);
        // computeIfAbsent: atomic check-and-compute — thread-safe for ConcurrentHashMap
    }

    // Memoize with bounded cache (LRU eviction)
    public static <K, V> Function<K, V> bounded(Function<K, V> fn, int maxSize) {
        Map<K, V> cache = Collections.synchronizedMap(
            new LinkedHashMap<>(maxSize, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
                    return size() > maxSize;
                }
            }
        );
        return key -> cache.computeIfAbsent(key, fn);
    }
}

// Similarity service — expensive pure computation
public class SimilarityService {
    private final Function<UserPair, Double> memoizedSimilarity =
        Memoize.of(this::computeRawSimilarity);

    public double similarity(String userA, String userB) {
        // Canonical key: sort IDs so (A,B) == (B,A)
        String lower = userA.compareTo(userB) < 0 ? userA : userB;
        String upper = userA.compareTo(userB) < 0 ? userB : userA;
        return memoizedSimilarity.apply(new UserPair(lower, upper));
    }

    private double computeRawSimilarity(UserPair pair) {
        double[] vecA = embeddingStore.get(pair.userA());
        double[] vecB = embeddingStore.get(pair.userB());
        return cosineSimilarity(vecA, vecB);    // expensive: O(d) where d=300 dimensions
    }
}

// Price calculation — tax rates are stable; memoize them
public class PricingService {
    private final Map<String, TaxRate> taxRateCache = new ConcurrentHashMap<>();

    public Money calculatePrice(Product product, String countryCode) {
        TaxRate rate = taxRateCache.computeIfAbsent(
            countryCode,
            code -> taxService.fetchRate(code)   // HTTP call — expensive; memoize
        );
        return product.basePrice().multiply(BigDecimal.ONE.add(rate.value()));
    }
}

// Fibonacci — classic memoization example in interviews
public class Fibonacci {
    private final Map<Long, Long> memo = new HashMap<>();

    public long fib(long n) {
        if (n <= 1) return n;
        return memo.computeIfAbsent(n, k -> fib(k - 1) + fib(k - 2));
        // Without memoization: O(2^n); with: O(n) time, O(n) space
    }
}

// Caffeine — production-grade cache with TTL and max size
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;

public class ProductService {
    private final Cache<String, Product> cache = Caffeine.newBuilder()
        .maximumSize(10_000)
        .expireAfterWrite(5, TimeUnit.MINUTES)    // TTL for mutable data
        .recordStats()                             // monitoring
        .build();

    public Product getProduct(String sku) {
        return cache.get(sku, this::fetchFromDb);  // memoize with TTL
    }
}
```

### Kotlin — by lazy and manual memoize

```kotlin
// by lazy — built-in memoization for property initialisation
class RecommendationEngine(private val userId: String) {
    // Computed once on first access; same value forever
    val userEmbedding: FloatArray by lazy {
        embeddingService.compute(userId)   // expensive; only if recommendations are requested
    }

    val topCategories: List<String> by lazy {
        categoryService.topFor(userId)
    }
}

// Generic memoize extension
fun <K, V> ((K) -> V).memoize(): (K) -> V {
    val cache = ConcurrentHashMap<K, V>()
    return { key -> cache.getOrPut(key) { this(key) } }
}

// Usage
val memoizedSimilarity: (UserPair) -> Double = ::computeSimilarity.memoize()

// Recursive memoization
fun memoFib(): (Long) -> Long {
    val cache = mutableMapOf<Long, Long>()
    fun fib(n: Long): Long = cache.getOrPut(n) {
        if (n <= 1L) n else fib(n - 1) + fib(n - 2)
    }
    return ::fib
}

val fib = memoFib()
println(fib(50))   // instant; without memoization: O(2^50)

// Scoped memoization — within a request context only
class RequestScopedCache {
    private val cache = HashMap<Any, Any>()

    @Suppress("UNCHECKED_CAST")
    fun <K, V> memoize(key: K, compute: () -> V): V =
        cache.getOrPut(key as Any) { compute() as Any } as V
}

// Usage in service layer
fun resolvePermissions(userId: String, cache: RequestScopedCache): Set<Permission> =
    cache.memoize("permissions:$userId") {
        permissionService.resolve(userId)   // called once per request, not per check
    }
```

### Python — @lru_cache and @cache

```python
from functools import lru_cache, cache
import time

# @cache — unlimited memoization (Python 3.9+)
@cache
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

# @lru_cache(maxsize) — LRU eviction when cache fills
@lru_cache(maxsize=1024)
def compute_similarity(user_a: str, user_b: str) -> float:
    """Pure function: same inputs always produce same output."""
    vec_a = embedding_store.get(user_a)
    vec_b = embedding_store.get(user_b)
    return cosine_similarity(vec_a, vec_b)

# Cache stats for monitoring
print(compute_similarity.cache_info())   # CacheInfo(hits=..., misses=..., maxsize=1024, currsize=...)
compute_similarity.cache_clear()         # invalidate all entries

# Memoize only works on hashable arguments
# For unhashable args (list, dict), use a custom key
def memoize(fn):
    cache = {}
    def wrapper(*args, **kwargs):
        key = (args, frozenset(kwargs.items()))  # make key hashable
        if key not in cache:
            cache[key] = fn(*args, **kwargs)
        return cache[key]
    return wrapper

# TTL-aware memoization — for data that changes over time
def memoize_with_ttl(ttl_seconds: float):
    def decorator(fn):
        cache = {}
        def wrapper(*args):
            now = time.monotonic()
            if args in cache:
                result, timestamp = cache[args]
                if now - timestamp < ttl_seconds:
                    return result    # cache hit; not expired
            result = fn(*args)
            cache[args] = (result, now)
            return result
        wrapper.cache_clear = lambda: cache.clear()
        return wrapper
    return decorator

@memoize_with_ttl(ttl_seconds=300)   # 5-minute TTL
def get_tax_rate(country_code: str) -> float:
    return tax_service.fetch(country_code)  # HTTP call; stable for 5 minutes

# Class-level memoization with invalidation
class ProductCatalog:
    def __init__(self):
        self._price_cache: dict[str, float] = {}

    def get_price(self, sku: str) -> float:
        if sku not in self._price_cache:
            self._price_cache[sku] = db.fetch_price(sku)
        return self._price_cache[sku]

    def invalidate(self, sku: str) -> None:
        self._price_cache.pop(sku, None)  # called when price changes

    def invalidate_all(self) -> None:
        self._price_cache.clear()
```

### JavaScript / TypeScript — manual memoize and libraries

```typescript
// Generic memoize function
function memoize<Args extends any[], Return>(
    fn: (...args: Args) => Return
): (...args: Args) => Return {
    const cache = new Map<string, Return>();
    return (...args: Args): Return => {
        const key = JSON.stringify(args);
        if (cache.has(key)) return cache.get(key)!;
        const result = fn(...args);
        cache.set(key, result);
        return result;
    };
}

// Usage
const memoizedSimilarity = memoize((userA: string, userB: string): number => {
    const vecA = embeddingStore.get(userA);
    const vecB = embeddingStore.get(userB);
    return cosineSimilarity(vecA, vecB);
});

// React.useMemo — memoize expensive computation inside a component render
const recommendations = React.useMemo(
    () => computeRecommendations(userId, products),   // runs only when userId or products change
    [userId, products]                                // dependency array
);

// React.useCallback — memoize a callback function reference
const handleDeleteItem = React.useCallback(
    (itemId: string) => dispatch(deleteItem(itemId)),
    [dispatch]   // stable reference — no re-render of children
);

// Memoize with TTL (for semi-stable data)
function memoizeWithTTL<K, V>(fn: (key: K) => V, ttlMs: number): (key: K) => V {
    const cache = new Map<K, { value: V; expiresAt: number }>();
    return (key: K): V => {
        const entry = cache.get(key);
        if (entry && entry.expiresAt > Date.now()) return entry.value;
        const value = fn(key);
        cache.set(key, { value, expiresAt: Date.now() + ttlMs });
        return value;
    };
}

const getTaxRate = memoizeWithTTL(
    (countryCode: string) => taxService.fetch(countryCode),
    5 * 60 * 1000   // 5 minutes
);

// Bounded LRU cache (Map preserves insertion order in JS)
function lruMemoize<K, V>(fn: (key: K) => V, maxSize: number): (key: K) => V {
    const cache = new Map<K, V>();
    return (key: K): V => {
        if (cache.has(key)) {
            const value = cache.get(key)!;
            cache.delete(key); cache.set(key, value);  // move to end (most recently used)
            return value;
        }
        if (cache.size >= maxSize) {
            cache.delete(cache.keys().next().value);   // evict LRU (first key)
        }
        const value = fn(key);
        cache.set(key, value);
        return value;
    };
}
```

---

## Memoization vs Caching — Precise Distinction

| | Memoization | Caching (Redis, Caffeine) |
|---|-------------|--------------------------|
| Scope | In-process, per function | External or distributed |
| Invalidation | Typically manual or TTL | TTL, eviction policies, explicit |
| Use case | Pure functions, CPU-bound | Shared across services, IO-bound |
| Key | Function arguments | Explicit cache key |
| Prerequisite | Function must be pure | Not required |
| Size control | Bounded or unbounded | Always bounded |

---

## When Memoization Is Unsafe

```java
// UNSAFE: function reads mutable external state
@Cache   // WRONG — result changes as catalog changes
public List<Product> getFeaturedProducts() {
    return db.query("SELECT * FROM products WHERE featured = true");
    // The cached result becomes stale when the DB changes
}

// SAFE: function depends only on arguments
@Cache   // CORRECT — same input always produces same output
public double convertCurrency(Money amount, String targetCurrency) {
    ExchangeRate rate = exchangeRateService.getRate(amount.currency(), targetCurrency);
    return amount.value() * rate.value();
}
// (assuming exchange rates are themselves cached with TTL)
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Memoize wrapper handles caching; original function handles computation |
| Open/Closed | ✅ | Wrap any function with memoize without modifying it |
| Liskov Substitution | ✅ | Memoized function is substitutable for original — same signature, same result |
| Interface Segregation | ✅ | Cache is invisible to callers — same API |
| Dependency Inversion | ✅ | Memoize wrapper depends on function signature abstraction |

---

## When to Use

- A pure function is called repeatedly with the same arguments in a request
- CPU-intensive computation: similarity scoring, matrix operations, complex transformations
- Recursive algorithms with overlapping subproblems (Fibonacci, edit distance, knapsack)
- Stable reference data fetched from IO: tax rates, config, feature flags

## When NOT to Use

- The function has side effects or reads mutable external state
- Arguments are rarely repeated — cache overhead exceeds savings
- Memory is constrained — unbounded caches grow without limit
- Result freshness matters — stale cache is worse than no cache

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates redundant computation — O(1) for repeated calls | Memory grows with unique inputs — bounded cache required for production |
| Trivial to add with a decorator/wrapper — zero refactoring | Incorrect use on non-pure functions causes subtle bugs (stale results) |
| Works equally well for CPU-bound and IO-bound calls | Cache keys must be hashable; complex objects need custom key functions |
| Composable with other FP patterns | Concurrency: `computeIfAbsent` is safe in Java; JS/Python single-threaded so simpler |

---

**FAANG interview application**: "Memoization is the right answer when a pure function is called multiple times with the same arguments. In a recommendation engine, `similarity(A, B)` is called O(n²) times per batch — memoizing it drops that to O(n²) unique calls but O(1) repeated ones. In Python I use `@lru_cache(maxsize=...)` — one annotation, zero code changes. In Java I use `ConcurrentHashMap.computeIfAbsent` for thread safety. The three questions I always ask before memoizing: (1) Is the function pure? (2) Do arguments repeat? (3) What is the cardinality — do I need LRU eviction? If the answer to (1) is no, memoization is a bug waiting to happen."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Lazy Evaluation](40-lazy-evaluation.md) | `by lazy` is memoization for zero-arg computations — compute once, reuse |
| [Proxy](../structural/12-proxy.md) | Caching proxy wraps a service; memoization wraps a function — same idea |
| [Flyweight](../structural/11-flyweight.md) | Flyweight shares object instances; memoization shares computation results |
