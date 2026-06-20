# Spring Cache — Caching Abstraction, Redis Integration, and Eviction Strategies

Spring Cache provides a declarative caching abstraction that decouples cache logic from business code. It works with any cache provider — Caffeine (in-process), Redis (distributed), Hazelcast, EhCache — through a uniform annotation model.

---

## Core Architecture

```
  @Cacheable("products")
  public Product getProduct(String id) { ... }
            │
            ▼
  CacheInterceptor (AOP proxy around the method)
            │
            ├── CacheManager
            │       └── Cache ("products")
            │              ├── Hit → return cached value
            │              └── Miss → invoke method → store result → return
            │
  CacheManager Implementations:
    ├── RedisCacheManager      ← distributed, persistent
    ├── CaffeineCacheManager   ← in-process, high-performance
    ├── SimpleCacheManager     ← ConcurrentHashMap (testing only)
    └── CompositeCacheManager  ← L1 (Caffeine) + L2 (Redis)
```

---

## Core Annotations

```java
@Service
public class ProductService {

    // @Cacheable — cache the return value; skip method if cache hit
    @Cacheable(
        value = "products",           // cache name
        key = "#id",                  // SpEL for cache key
        condition = "#id != null",    // only cache if condition true
        unless = "#result == null"    // don't cache null results
    )
    public Product getProduct(String id) {
        return productRepository.findById(id)
            .orElseThrow(() -> new ProductNotFoundException(id));
    }

    // Compound key
    @Cacheable(value = "products", key = "#region + ':' + #category + ':' + #page")
    public Page<Product> getProducts(String region, String category, int page) { ... }

    // @CachePut — always invoke method AND update the cache (write-through)
    @CachePut(value = "products", key = "#product.id")
    public Product updateProduct(Product product) {
        return productRepository.save(product);
    }

    // @CacheEvict — remove from cache
    @CacheEvict(value = "products", key = "#id")
    public void deleteProduct(String id) {
        productRepository.deleteById(id);
    }

    // Evict all entries in the cache
    @CacheEvict(value = "products", allEntries = true)
    public void clearProductCache() { }

    // Evict before method runs (not after — prevents stale reads during execution)
    @CacheEvict(value = "products", key = "#id", beforeInvocation = true)
    public void replaceProduct(String id, Product newProduct) { ... }

    // @Caching — multiple cache operations on one method
    @Caching(
        evict = {
            @CacheEvict(value = "products", key = "#product.id"),
            @CacheEvict(value = "productsByCategory", key = "#product.category")
        },
        put = @CachePut(value = "products", key = "#product.id")
    )
    public Product saveProduct(Product product) {
        return productRepository.save(product);
    }
}
```

---

## Redis Cache Configuration

```java
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory connectionFactory) {
        RedisCacheConfiguration defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeKeysWith(
                RedisSerializationContext.SerializationPair.fromSerializer(new StringRedisSerializer()))
            .serializeValuesWith(
                RedisSerializationContext.SerializationPair.fromSerializer(
                    new GenericJackson2JsonRedisSerializer()))  // JSON, not Java serialization
            .disableCachingNullValues();

        // Per-cache TTL overrides
        Map<String, RedisCacheConfiguration> cacheConfigs = Map.of(
            "products",          defaultConfig.entryTtl(Duration.ofHours(1)),
            "user-sessions",     defaultConfig.entryTtl(Duration.ofMinutes(15)),
            "exchange-rates",    defaultConfig.entryTtl(Duration.ofSeconds(60)),
            "static-content",    defaultConfig.entryTtl(Duration.ofDays(1))
        );

        return RedisCacheManager.builder(connectionFactory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(cacheConfigs)
            .build();
    }
}
```

---

## Two-Level Cache (L1 + L2)

```java
@Bean
public CacheManager cacheManager(RedisConnectionFactory redisFactory) {
    // L1: Caffeine — in-process, sub-millisecond
    CaffeineCacheManager caffeineManager = new CaffeineCacheManager();
    caffeineManager.setCaffeine(Caffeine.newBuilder()
        .maximumSize(1000)
        .expireAfterWrite(5, TimeUnit.MINUTES)
        .recordStats());

    // L2: Redis — distributed, shared across instances
    RedisCacheManager redisManager = RedisCacheManager.builder(redisFactory)
        .cacheDefaults(RedisCacheConfiguration.defaultCacheConfig().entryTtl(Duration.ofHours(1)))
        .build();

    // Composite: try L1 first, fall back to L2
    CompositeCacheManager composite = new CompositeCacheManager(caffeineManager, redisManager);
    composite.setFallbackToNoOpCache(false);
    return composite;
}
```

---

## Custom Key Generator

```java
// Default key: method name + all args (may collide)
// Custom: full control over key structure

@Bean
public KeyGenerator versionedKeyGenerator() {
    return (target, method, params) -> {
        StringBuilder sb = new StringBuilder();
        sb.append(method.getName()).append(":");
        Arrays.stream(params).forEach(p -> sb.append(p).append(":"));
        sb.append("v2");  // version suffix for cache invalidation on schema change
        return sb.toString();
    };
}

@Cacheable(value = "reports", keyGenerator = "versionedKeyGenerator")
public Report generateReport(String type, String period) { ... }
```

---

## Cache Patterns at Scale

### Cache-Aside (Lazy Loading)
```java
// Spring @Cacheable implements cache-aside automatically
// miss → load from DB → store in cache → return
@Cacheable("products")
public Product getProduct(String id) {
    return productRepository.findById(id).orElseThrow();
}
```

### Write-Through
```java
// @CachePut ensures cache always reflects the DB after write
@CachePut(value = "products", key = "#product.id")
public Product updateProduct(Product product) {
    return productRepository.save(product);  // DB first, then cache updated
}
```

### Write-Behind (Write-Back) — Manual
```java
// Spring Cache doesn't natively support write-behind
// Implement with a queue: write to cache immediately, async flush to DB
@Cacheable("products")
public Product getProduct(String id) { ... }

// In a background job or event-driven async:
@Scheduled(fixedDelay = 5000)
public void flushDirtyCache() {
    dirtySet.forEach(id -> {
        Product cached = cacheManager.getCache("products").get(id, Product.class);
        if (cached != null) productRepository.save(cached);
    });
}
```

### Cache Stampede Prevention

When a hot key expires, thousands of requests hit the DB simultaneously:

```java
// Solution 1: Probabilistic early refresh (Caffeine built-in)
Caffeine.newBuilder()
    .refreshAfterWrite(5, TimeUnit.MINUTES)  // async refresh before expiry
    .expireAfterWrite(10, TimeUnit.MINUTES)

// Solution 2: Distributed lock on cache miss
public Product getProductWithLock(String id) {
    Product cached = cache.get(id, Product.class);
    if (cached != null) return cached;

    String lockKey = "lock:product:" + id;
    if (redisLock.acquire(lockKey, 5, TimeUnit.SECONDS)) {
        try {
            // Double-check after acquiring lock
            cached = cache.get(id, Product.class);
            if (cached != null) return cached;

            Product fresh = productRepository.findById(id).orElseThrow();
            cache.put(id, fresh);
            return fresh;
        } finally {
            redisLock.release(lockKey);
        }
    } else {
        // Another instance is loading — wait briefly and retry
        return Mono.delay(Duration.ofMillis(100))
            .flatMap(x -> Mono.just(getProductWithLock(id)))
            .block();
    }
}
```

---

## Common Caching Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| **No TTL** | Stale data forever; cache fills memory | Always set TTL per cache |
| **Caching mutable objects** | Cache returns modified object shared across calls | Cache immutable DTOs, not entities |
| **Java serialization** | Version mismatch on deploy → ClassCastException | Use JSON serialization for Redis |
| **Self-invocation** | `@Cacheable` bypassed when calling from same class | Same AOP proxy trap as `@Transactional` |
| **Cache stampede** | All instances miss simultaneously → DB overwhelmed | Probabilistic refresh or distributed lock |
| **Too large keys** | Redis memory exhausted by key overhead | Keep keys short, use prefixes |
| **Caching everything** | Eviction thrashing, no memory benefit | Cache only expensive, frequently-read, infrequently-changing data |
| **Not monitoring** | Cache ratio drops and nobody notices | Track hit/miss ratio; alert < 80% hit rate |

---

## Design Patterns Used

| Pattern | Where in Spring Cache |
|---------|----------------------|
| **Proxy** | `CacheInterceptor` wraps the target method (AOP proxy) |
| **Decorator** | Cache layer decorates the repository with caching behavior |
| **Template Method** | `AbstractCacheManager` defines lifecycle; subclasses implement storage |
| **Strategy** | `KeyGenerator`, `CacheResolver` — pluggable algorithms |
| **Cache-Aside** | `@Cacheable` — check cache first, load on miss |
| **Write-Through** | `@CachePut` — update cache on every write |

---

## Monitoring Cache Performance

```java
// Caffeine statistics
CaffeineCacheManager manager = (CaffeineCacheManager) cacheManager;
CaffeineCache cache = (CaffeineCache) manager.getCache("products");
CacheStats stats = cache.getNativeCache().stats();
log.info("Hit rate: {}%, evictions: {}",
    stats.hitRate() * 100, stats.evictionCount());

// Micrometer integration (automatic with Spring Boot Actuator)
// /actuator/metrics/cache.gets?tag=cache:products&tag=result:hit
// /actuator/metrics/cache.gets?tag=cache:products&tag=result:miss
```

---

## FAANG Interview Callout

1. **"How does `@Cacheable` work internally?"**
   - AOP proxy wraps the method; on call, checks `CacheManager` for the key; on hit returns cached value; on miss invokes method, stores result, returns it

2. **"What is the cache stampede problem and how do you solve it?"**
   - When a popular key expires, all concurrent misses hit the DB simultaneously
   - Fix: probabilistic early expiry (`refreshAfterWrite`), or distributed lock on miss

3. **"Why shouldn't you cache JPA entities?"**
   - Entities are mutable; shared cached reference can be modified; Hibernate manages their state — caching them outside Hibernate's control leads to stale/corrupt state
   - Cache DTOs or value objects instead

4. **"What's the difference between `@CachePut` and `@Cacheable`?"**
   - `@Cacheable`: skip method if cache hit (read-through on miss only)
   - `@CachePut`: always invoke method AND update cache (write-through on every call)

5. **"How do you handle cache invalidation across multiple service instances?"**
   - Redis as shared cache — all instances write to / invalidate the same Redis key
   - `@CacheEvict` calls Redis `DEL` command — all instances see the eviction
   - For L1+L2: need a pub/sub mechanism (Redis Pub/Sub) to invalidate L1 on all instances
