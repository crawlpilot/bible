# 24. Repository
**Category**: Modern / Enterprise  
**GoF**: No (DDD pattern, Evans 2003)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Mediate between the domain and data mapping layers using a collection-like interface for accessing domain objects.

---

## Problem It Solves

`ProductService` directly calls `jdbcTemplate.query("SELECT...")`, `redisTemplate.get(...)`, and `elasticsearchClient.search(...)` scattered throughout business logic. Adding a cache means changing every service that fetches products. Testing requires a real database. Repository provides a domain-facing collection interface — the service only knows `productRepository.findById()`, not which storage tier served it.

## Structure (Participants)

```
      «interface»
   ProductRepository
┌──────────────────────────────┐
│ + findById(id): Product      │
│ + findByCategory(cat): List  │
│ + search(query): List        │
│ + save(product): Product     │
│ + delete(id)                 │
└──────────────────────────────┘
              △
  ┌───────────┴─────────────────────────────┐
  │                                         │
MultiSourceProductRepo         InMemoryProductRepo
(production: Redis→PG→ES)      (testing)
```

Key participants:
- **Repository Interface** (`ProductRepository`): domain-facing contract; uses domain types, not SQL/Redis
- **Concrete Repository** (`MultiSourceProductRepository`): orchestrates cache, DB, and search layers
- **In-Memory Repository**: test double — no external dependencies needed for unit tests

---

## Real-World Use Case: Product Catalog Repository (Redis → PostgreSQL → Elasticsearch)

A product service serves catalog pages, category pages, and search. For direct product lookups (`/products/{id}`): try Redis first (10ms), fall back to PostgreSQL (50ms), populate cache on miss. For search: always Elasticsearch. For saves: write to PostgreSQL, invalidate Redis cache.

### Implementation

```java
// Repository interface — domain-facing, no storage details
public interface ProductRepository {
    Optional<Product> findById(String productId);
    List<Product> findByCategory(String categoryPath, PageRequest pageRequest);
    Page<Product> search(ProductSearchQuery query);
    List<Product> findByIds(Collection<String> productIds);  // bulk fetch
    Product save(Product product);
    void delete(String productId);
}

// Multi-source concrete repository
public class MultiSourceProductRepository implements ProductRepository {
    private final RedisTemplate<String, Product> redis;
    private final ProductJpaRepository jpa;
    private final ElasticsearchProductRepository es;
    private final Duration cacheTtl;
    private final MeterRegistry metrics;

    @Override
    public Optional<Product> findById(String productId) {
        // L1: Redis cache
        String cacheKey = "product:" + productId;
        Product cached = redis.opsForValue().get(cacheKey);
        if (cached != null) {
            metrics.counter("product.cache.hit").increment();
            return Optional.of(cached);
        }

        // L2: PostgreSQL (source of truth)
        metrics.counter("product.cache.miss").increment();
        Optional<Product> fromDb = jpa.findById(productId)
            .map(ProductMapper::toDomain);

        // Populate cache on miss
        fromDb.ifPresent(p -> redis.opsForValue().set(cacheKey, p, cacheTtl));

        return fromDb;
    }

    @Override
    public List<Product> findByIds(Collection<String> productIds) {
        if (productIds.isEmpty()) return emptyList();

        // Bulk cache read
        List<String> keys = productIds.stream().map(id -> "product:" + id).collect(toList());
        List<Product> cached = redis.opsForValue().multiGet(keys).stream()
            .filter(Objects::nonNull).collect(toList());

        Set<String> cachedIds = cached.stream().map(Product::id).collect(toSet());
        Set<String> missedIds = productIds.stream()
            .filter(id -> !cachedIds.contains(id)).collect(toSet());

        // DB fetch for misses only
        List<Product> fromDb = jpa.findAllById(missedIds).stream()
            .map(ProductMapper::toDomain).collect(toList());

        // Populate cache for misses
        fromDb.forEach(p -> redis.opsForValue().set("product:" + p.id(), p, cacheTtl));

        List<Product> result = new ArrayList<>(cached);
        result.addAll(fromDb);
        return result;
    }

    @Override
    public List<Product> findByCategory(String categoryPath, PageRequest pageRequest) {
        // Category pages: PostgreSQL (indexed on category_path)
        return jpa.findByCategoryPath(categoryPath, pageRequest)
            .map(ProductMapper::toDomain).getContent();
    }

    @Override
    public Page<Product> search(ProductSearchQuery query) {
        // Full-text search: always Elasticsearch
        return es.search(query);
    }

    @Override
    public Product save(Product product) {
        // Write to PostgreSQL
        ProductEntity saved = jpa.save(ProductMapper.toEntity(product));

        // Invalidate Redis cache (write-invalidate pattern)
        redis.delete("product:" + product.id());

        // Update Elasticsearch async (via event or immediate)
        es.index(product);

        return ProductMapper.toDomain(saved);
    }

    @Override
    public void delete(String productId) {
        jpa.deleteById(productId);
        redis.delete("product:" + productId);
        es.delete(productId);
    }
}

// In-memory test double
public class InMemoryProductRepository implements ProductRepository {
    private final Map<String, Product> store = new HashMap<>();

    @Override
    public Optional<Product> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }

    @Override
    public Product save(Product product) {
        store.put(product.id(), product);
        return product;
    }

    @Override
    public void delete(String id) { store.remove(id); }

    @Override
    public List<Product> findByIds(Collection<String> ids) {
        return ids.stream().map(store::get).filter(Objects::nonNull).collect(toList());
    }

    @Override public List<Product> findByCategory(String cat, PageRequest page) {
        return store.values().stream()
            .filter(p -> p.categoryPath().startsWith(cat)).collect(toList());
    }

    @Override public Page<Product> search(ProductSearchQuery q) {
        return Page.of(new ArrayList<>(store.values()), 0, store.size());
    }
}

// Domain service — depends only on the interface
public class ProductService {
    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public ProductDetail getProductDetail(String productId) {
        Product product = productRepository.findById(productId)
            .orElseThrow(() -> new ProductNotFoundException(productId));
        return ProductDetail.from(product);
    }
}

// Test — uses InMemoryProductRepository, no DB required
class ProductServiceTest {
    @Test
    void shouldReturnProductDetail() {
        InMemoryProductRepository repo = new InMemoryProductRepository();
        repo.save(new Product("P1", "Laptop", "electronics", Money.of(999)));
        ProductService service = new ProductService(repo);
        ProductDetail detail = service.getProductDetail("P1");
        assertThat(detail.name()).isEqualTo("Laptop");
    }
}
```

### How It Works (walkthrough)

1. `GET /products/SKU-123` → `productService.getProductDetail("SKU-123")`
2. `repository.findById("SKU-123")` → `MultiSourceProductRepository`
3. Redis check → cache miss → PostgreSQL query → product found
4. Cache populated: `redis.set("product:SKU-123", product, 5min)`
5. Return domain `Product` → service builds `ProductDetail` → controller serializes to JSON
6. Next request for same SKU → Redis hit → returned in ~10ms vs ~50ms

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Repository handles data access; service handles business logic |
| Open/Closed | ✅ | Add L3 caching (CDN) by extending the repository, not modifying the service |
| Liskov Substitution | ✅ | `InMemoryProductRepository` fully substitutable for production repository |
| Interface Segregation | ⚠️ | Large interface — consider splitting into `ProductReadRepository` and `ProductWriteRepository` (CQRS) |
| Dependency Inversion | ✅ | `ProductService` depends on `ProductRepository` interface |

---

## When to Use

- Business logic should be decoupled from data access mechanisms (cache, DB, search)
- Unit testing should not require a database
- Multiple storage tiers need to be orchestrated behind a unified API
- Data access code is scattered across service methods

## When NOT to Use

- Simple CRUD with no business logic — a plain JPA repository is sufficient
- Single storage tier with no abstraction benefit — the interface adds indirection without value

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Testable domain logic — swap InMemory for production at test time | Interface abstraction can be over-engineered for simple CRUDs |
| Storage tier changes transparent to domain services | N+1 queries still possible if `findByCategory()` is implemented naively |
| Clean seam for adding caching, sharding, replication | Cache invalidation logic lives in the repo — must be correct and tested |

---

**FAANG interview application**: "Repository is the seam between domain logic and storage. The interface is domain-typed (`Product`, not `ProductEntity`), and the implementation decides whether to hit Redis, PostgreSQL, or Elasticsearch. At FAANG scale, the repository often hides a multi-tier read path: L1 Redis (10ms), L2 regional cache (30ms), L3 database (50ms). Cache invalidation on write is write-through with key delete — safer than write-through update which has race conditions on concurrent writes."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [CQRS](25-cqrs.md) | Repository can be split into read repo (optimized for queries) and write repo (strong consistency) |
| [Unit of Work](32-unit-of-work.md) | Unit of Work coordinates multiple repositories in a single transaction |
| [Proxy](../structural/12-proxy.md) | The caching logic in a multi-source repository is a Proxy pattern internally |
