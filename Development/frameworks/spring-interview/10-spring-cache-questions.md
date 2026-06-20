# Spring Cache — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What does `@Cacheable` do?**
Before invoking the method, Spring checks the cache for the key. On hit: returns the cached value without calling the method. On miss: invokes the method, stores the result in the cache, returns the result. The cache key defaults to the method parameters; customized with `key` SpEL.

**Q2. What is the difference between `@Cacheable` and `@CachePut`?**
- `@Cacheable`: skip method on cache hit (read-through on miss only) — for reads
- `@CachePut`: always invoke the method AND update the cache — for writes (write-through)

Both update the cache, but `@Cacheable` skips the method body when data is cached; `@CachePut` always executes it.

**Q3. What does `@CacheEvict` do?**
Removes an entry (or all entries) from a cache after the method runs:
```java
@CacheEvict(value = "products", key = "#id")           // remove specific entry
@CacheEvict(value = "products", allEntries = true)     // clear entire cache
@CacheEvict(value = "products", beforeInvocation = true) // remove BEFORE method (prevents stale on exception)
```

**Q4. What is the default cache key?**
By default, Spring generates the key from all method parameters. Rules:
- No params: `SimpleKey.EMPTY`
- One param: the param itself
- Multiple params: `SimpleKey` of all params
Override with SpEL: `key = "#userId + ':' + #region"`.

**Q5. What do you need to enable caching in Spring Boot?**
Add `@EnableCaching` to a `@Configuration` class (auto-applied with `spring-boot-starter-cache`). Define a `CacheManager` bean (or use the auto-configured one for the detected provider). Add cache annotations to methods.

---

## Advanced (L5 Senior)

**Q6. How does Spring Cache work internally?**
`@EnableCaching` registers a `CacheInterceptor` (AOP advice). Every `@Cacheable` method gets a proxy. On invocation, the interceptor calls `CacheManager.getCache(name)` to get the `Cache` object, then calls `cache.get(key)`. On miss: invokes the real method, stores result with `cache.put(key, result)`. This is the same AOP proxy mechanism as `@Transactional` — same self-invocation trap applies.

**Q7. How do you configure per-cache TTL with Redis?**
```java
@Bean
public RedisCacheManager cacheManager(RedisConnectionFactory cf) {
    RedisCacheConfiguration defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
        .entryTtl(Duration.ofMinutes(30));

    return RedisCacheManager.builder(cf)
        .cacheDefaults(defaultConfig)
        .withInitialCacheConfigurations(Map.of(
            "hot-products", defaultConfig.entryTtl(Duration.ofSeconds(30)),
            "user-prefs",   defaultConfig.entryTtl(Duration.ofHours(24))
        ))
        .build();
}
```

**Q8. What is the cache stampede problem and how do you prevent it?**
When a popular cached key expires, many concurrent requests all miss the cache simultaneously and all hit the database at once — a thundering herd. Prevention:
1. **Probabilistic early expiration** (Caffeine `refreshAfterWrite`): refresh the cache slightly before expiry while still serving stale value
2. **Distributed lock on miss**: only one thread loads from DB; others wait or return stale
3. **Jitter in TTL**: randomize expiry (e.g., 30 min ± 5 min) so not all keys expire simultaneously

**Q9. How do you handle cache invalidation across multiple service instances?**
With Redis as a shared cache, `@CacheEvict` calls `Redis DEL` — all instances see the eviction on their next request (they all read from the same Redis). For a two-level cache (L1 Caffeine + L2 Redis): L1 Caffeine is per-instance; invalidation requires broadcasting to all instances. Use Redis Pub/Sub: on evict, publish to a channel; each instance's subscriber clears its L1 cache for that key.

**Q10. When should you NOT cache something?**
- Write-heavy data (cache invalidated constantly — overhead with no benefit)
- Data that must be strongly consistent (cache introduces staleness)
- Small datasets (the overhead of caching exceeds the benefit)
- Data that changes per-user or per-request (cache hit rate near 0%)
- Sensitive data without encryption (cache may expose PII in logs or memory dumps)

---

## Principal Engineer Level

**Q11. How do you design caching for a multi-tenant SaaS application?**
Tenant isolation is critical — tenant A must never see tenant B's data:
```java
@Cacheable(value = "products", key = "@tenantContext.tenantId + ':' + #productId")
public Product getProduct(UUID productId) { ... }

@CacheEvict(value = "products",
            key = "@tenantContext.tenantId + ':' + #productId")
public void updateProduct(UUID productId, Product product) { ... }
```
Key design: always prefix with `tenantId`. For full tenant cache eviction: use pattern-based eviction `Redis DEL <tenantId>:*` (requires `SCAN` pattern — not atomic, use Lua script) or a per-tenant cache namespace.

**Q12. How do you measure cache effectiveness and what metrics matter?**

Key metrics:
- **Hit rate**: `cache.hits / (cache.hits + cache.misses)` → target > 80% for a healthy cache
- **Miss penalty**: latency of a cache miss (DB call time) — the cost of a miss
- **Eviction rate**: high eviction = cache too small or TTL too short
- **Memory usage**: Redis memory per cache region
- **Stale read rate**: how often clients see expired data (only measurable with version tracking)

Monitoring with Spring Boot Actuator + Micrometer:
```yaml
management:
  metrics:
    tags:
      application: ${spring.application.name}
```
`/actuator/metrics/cache.gets?tag=cache:products&tag=result:hit` — hit count
`/actuator/metrics/cache.gets?tag=cache:products&tag=result:miss` — miss count

**Q13. How do you handle cache versioning when schema changes?**
Problem: cached JSON of version 1 is deserialized into version 2 class → `JsonMappingException` or corrupted data on deploy.

Solutions:
1. **Version in cache name**: `products-v2` — deploy with new name, old entries naturally expire, rollback safe
2. **TTL-based**: if TTL is short (< 1h), just wait for expiry after deploy; brief inconsistency acceptable
3. **Cache flush on deploy**: `@CacheEvict(allEntries = true)` in `ApplicationRunner` on startup — causes cold start
4. **Version suffix in key**: `key = "#id + ':v2'"` — forces new key, old entries irrelevant

---

## Code Walkthroughs

**Q14. Why is this method always called even when the result should be cached?**
```java
@Service
public class ProductService {
    @Autowired
    private ProductService self;  // self-injection to fix AOP

    public Product getProduct(String id) {
        return self.getCached(id);  // calls through proxy — correct
    }

    @Cacheable("products")
    public Product getCached(String id) {
        return productRepository.findById(id).orElseThrow();
    }
}
```
The code shown is actually the CORRECT fix. Without `self.getCached(id)` (i.e., using `this.getCached(id)`), the self-invocation would bypass the proxy and `@Cacheable` would be ignored.

**Q15. What happens when this cache configuration runs in production?**
```java
@Bean
public CacheManager cacheManager() {
    return new ConcurrentMapCacheManager("products", "users");
    // No TTL, no eviction policy, no max size
}
```
**Answer**: Memory leak. `ConcurrentMapCacheManager` uses `ConcurrentHashMap` with no eviction and no TTL — entries are never removed. Under normal production load, the JVM heap fills up and causes `OutOfMemoryError`. Fix: use Caffeine with `maximumSize` and `expireAfterWrite`, or Redis for distributed caching.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Caching JPA entities | Hibernate entity state managed separately; stale/corrupt | Cache DTOs or value objects |
| `ConcurrentMapCacheManager` in prod | No TTL → memory leak | Caffeine or Redis with TTL and max size |
| Java serialization for Redis | Class version mismatch on deploy | Use `GenericJackson2JsonRedisSerializer` |
| Self-invocation with `@Cacheable` | Cache bypassed | Self-inject bean or refactor to another bean |
| No `unless = "#result == null"` | Caches null → every miss returns null forever | Add `unless` to avoid caching nulls |
| Not monitoring hit rate | Cache degradation goes unnoticed | Alert when hit rate drops below 70% |
