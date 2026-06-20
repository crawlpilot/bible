# Spring Data — Repositories, JPA, Transactions, and Data Access Patterns

Spring Data abstracts the data access layer. Its repository pattern eliminates boilerplate DAO code — a 50-line JdbcTemplate DAO becomes a 5-line interface. Understanding when this abstraction helps vs hurts is critical for principal engineer discussions.

---

## Spring Data Module Landscape

```
Spring Data Commons (core abstractions)
    ├── Spring Data JPA          ← Hibernate, relational DBs
    ├── Spring Data MongoDB      ← Document store
    ├── Spring Data Redis        ← Cache, key-value
    ├── Spring Data Cassandra    ← Wide-column, FAANG-scale
    ├── Spring Data Elasticsearch← Full-text search
    ├── Spring Data R2DBC        ← Reactive relational DB access
    └── Spring Data JDBC         ← Simpler than JPA, no ORM magic
```

---

## Repository Hierarchy

```
Repository (marker interface)
    └── CrudRepository<T, ID>
            ├── save(), findById(), findAll(), deleteById()
            └── PagingAndSortingRepository<T, ID>
                    ├── findAll(Pageable), findAll(Sort)
                    └── JpaRepository<T, ID>  ← JPA-specific
                            ├── saveAll(), saveAndFlush()
                            ├── findAll(Example<T>)  ← QBE
                            └── getReferenceById()   ← lazy proxy, no SQL until accessed
```

```java
// Spring generates implementation at startup — no code needed
public interface OrderRepository extends JpaRepository<Order, UUID> {

    // Derived query — Spring parses method name into JPQL
    List<Order> findByCustomerIdAndStatusOrderByCreatedAtDesc(UUID customerId, OrderStatus status);

    // Custom JPQL — use when derived query is unreadable
    @Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.id = :id")
    Optional<Order> findByIdWithItems(@Param("id") UUID id);

    // Native SQL — last resort, database-specific
    @Query(value = "SELECT * FROM orders WHERE EXTRACT(YEAR FROM created_at) = :year",
           nativeQuery = true)
    List<Order> findByYear(@Param("year") int year);

    // Modifying query — always pair with @Transactional
    @Modifying
    @Query("UPDATE Order o SET o.status = :status WHERE o.id IN :ids")
    int bulkUpdateStatus(@Param("status") OrderStatus status, @Param("ids") List<UUID> ids);

    // Projections — only fetch what you need
    List<OrderSummary> findByCustomerId(UUID customerId);

    // Paging
    Page<Order> findByStatus(OrderStatus status, Pageable pageable);

    // Specifications — dynamic queries
    List<Order> findAll(Specification<Order> spec);
}

// Projection interface — Spring generates a proxy, no extra class needed
public interface OrderSummary {
    UUID getId();
    OrderStatus getStatus();
    BigDecimal getTotal();
}
```

---

## Entity Design

```java
@Entity
@Table(name = "orders",
       indexes = @Index(name = "idx_orders_customer_status", columnList = "customer_id, status"))
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false)
    private UUID customerId;

    @Enumerated(EnumType.STRING)  // never EnumType.ORDINAL — breaks on enum reorder
    private OrderStatus status;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true,
               fetch = FetchType.LAZY)  // always LAZY — EAGER is almost always wrong
    private List<OrderItem> items = new ArrayList<>();

    @Version  // optimistic locking — increment on every update
    private Long version;

    @CreationTimestamp
    private Instant createdAt;

    @UpdateTimestamp
    private Instant updatedAt;
}
```

---

## N+1 Problem — The Most Common JPA Trap

```java
// DANGER: N+1 — 1 query for orders + N queries for items (one per order)
List<Order> orders = orderRepository.findAll();
orders.forEach(o -> o.getItems().size()); // triggers N lazy loads

// FIX 1: JOIN FETCH in JPQL
@Query("SELECT DISTINCT o FROM Order o JOIN FETCH o.items WHERE o.status = :status")
List<Order> findWithItemsByStatus(OrderStatus status);

// FIX 2: EntityGraph
@EntityGraph(attributePaths = {"items", "items.product"})
List<Order> findByCustomerId(UUID customerId);

// FIX 3: Batch fetching (Hibernate property)
spring.jpa.properties.hibernate.default_batch_fetch_size=32
# Converts N+1 → N/32 + 1 queries
```

---

## @Transactional — Complete Reference

```java
@Service
@Transactional(readOnly = true)  // default for all methods — enables read optimizations
public class OrderService {

    // Inherits readOnly=true — SELECT with no dirty checking
    public Optional<Order> findById(UUID id) {
        return orderRepository.findById(id);
    }

    @Transactional  // overrides to readOnly=false for writes
    public Order createOrder(CreateOrderRequest req) {
        Order order = new Order(req.customerId(), OrderStatus.PENDING);
        return orderRepository.save(order);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)  // suspends outer transaction
    public void auditLog(String message) {
        auditRepository.save(new AuditEntry(message));
        // Committed independently even if outer transaction rolls back
    }

    @Transactional(rollbackFor = BusinessException.class)  // checked exception
    public void processPayment(UUID orderId) throws BusinessException { ... }

    @Transactional(noRollbackFor = StockWarningException.class)
    public void fulfillOrder(UUID orderId) throws StockWarningException { ... }

    @Transactional(timeout = 30)  // fails with TransactionTimedOutException after 30s
    public Report generateLargeReport() { ... }
}
```

### Transaction Propagation Cheat Sheet

| Propagation | Behavior |
|-------------|---------|
| `REQUIRED` (default) | Join existing; create new if none |
| `REQUIRES_NEW` | Always create new; suspend existing |
| `SUPPORTS` | Join if exists; no transaction if none |
| `NOT_SUPPORTED` | Suspend existing; run non-transactionally |
| `MANDATORY` | Must exist; throw if none |
| `NEVER` | Must not exist; throw if one exists |
| `NESTED` | Savepoint within existing transaction |

---

## Specifications — Dynamic Queries

```java
public class OrderSpecifications {

    public static Specification<Order> hasStatus(OrderStatus status) {
        return (root, query, cb) ->
            status == null ? null : cb.equal(root.get("status"), status);
    }

    public static Specification<Order> createdAfter(Instant date) {
        return (root, query, cb) ->
            date == null ? null : cb.greaterThan(root.get("createdAt"), date);
    }

    public static Specification<Order> forCustomer(UUID customerId) {
        return (root, query, cb) ->
            customerId == null ? null : cb.equal(root.get("customerId"), customerId);
    }
}

// Usage — composable, type-safe
Specification<Order> spec = where(hasStatus(PENDING))
    .and(createdAfter(Instant.now().minus(7, DAYS)))
    .and(forCustomer(userId));
List<Order> orders = orderRepository.findAll(spec);
```

---

## Pagination — Cursor vs Offset

```java
// Offset pagination — simple but scales poorly (LIMIT 20 OFFSET 10000 scans 10020 rows)
Page<Order> page = orderRepository.findAll(PageRequest.of(pageNum, 20,
    Sort.by(DESC, "createdAt")));

// Cursor pagination — stable, scalable (no offset scan)
// Use a unique, indexed cursor field (createdAt + id for tie-breaking)
@Query("SELECT o FROM Order o WHERE o.createdAt < :cursor OR " +
       "(o.createdAt = :cursor AND o.id < :lastId) ORDER BY o.createdAt DESC, o.id DESC")
List<Order> findNextPage(@Param("cursor") Instant cursor,
                          @Param("lastId") UUID lastId,
                          Pageable pageable);
```

---

## Spring Data JDBC vs JPA

| Aspect | Spring Data JDBC | Spring Data JPA |
|--------|----------------|----------------|
| Abstraction | Thin — close to SQL | Thick — ORM maps objects to SQL |
| Magic | Minimal | High (proxies, dirty checking, L1 cache) |
| N+1 risk | Low (no lazy loading) | High (must manage explicitly) |
| Aggregate control | Explicit — you control everything | Implicit — Hibernate decides |
| Joins | Manual @Query | JOIN FETCH, @EntityGraph |
| Use for | New greenfield, simple aggregates | Complex domain models, legacy schemas |

---

## Design Patterns Used

| Pattern | Where in Spring Data |
|---------|---------------------|
| **Repository** | `CrudRepository`, `JpaRepository` — abstraction over data store |
| **Proxy** | Repository interfaces get a proxy at startup; projections are proxies too |
| **Specification** | `Specification<T>` — composable predicate objects |
| **Query Object** | `@Query`, derived query methods — encapsulate query intent |
| **Unit of Work** | JPA `EntityManager` / Hibernate Session — tracks changes, flushes on commit |
| **Identity Map** | JPA first-level cache — same entity object returned for same ID within session |
| **Template Method** | `SimpleJpaRepository` implements the boilerplate; subclass customizes |

---

## Trade-offs

| Aspect | Benefit | Cost |
|--------|---------|------|
| Repository pattern | Zero DAO boilerplate | Complex queries require @Query — abstraction leaks |
| JPA / Hibernate | Object-graph navigation | N+1, LazyInitializationException, Cartesian product |
| `@Transactional(readOnly=true)` | DB routing to replicas, no dirty checking | Must explicitly mark writes |
| JPQL | Database-agnostic | Can't use DB-specific features |
| Derived queries | Readable, no SQL | Verbose for complex filters; Specifications needed |

---

## FAANG Interview Callout

1. **"Explain the N+1 problem and how you fix it."**
   - 1 query fetches N entities → accessing a lazy collection fires N more queries
   - Fix: `JOIN FETCH`, `@EntityGraph`, or `@BatchSize`; detect with Hibernate statistics

2. **"What does `@Transactional(readOnly=true)` actually do?"**
   - Tells Hibernate to skip dirty checking (performance); tells driver to route to read replica if configured; disables flush

3. **"What's the difference between `save()` and `saveAndFlush()`?"**
   - `save()`: marks entity as managed; flushed to DB at transaction commit or when Hibernate decides
   - `saveAndFlush()`: immediately flushes to DB — needed when next query must see the change within same transaction

4. **"How do you handle optimistic locking in Spring Data?"**
   - Add `@Version Long version` to entity; Spring Data increments on each update
   - On conflict: `ObjectOptimisticLockingFailureException` — catch and retry or surface as 409

5. **"When would you choose Spring Data JDBC over JPA?"**
   - Simple domain model, no complex relationships
   - Need predictable SQL without ORM magic
   - Aggregate-based design (DDD) where you don't want implicit lazy loading
