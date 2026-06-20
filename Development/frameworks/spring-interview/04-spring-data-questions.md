# Spring Data — Interview Questions

---

## Fundamentals (L3–L4)

**Q1. What is the repository pattern in Spring Data?**
A repository is an abstraction over data access. Spring Data generates implementations at startup for repository interfaces. `JpaRepository<T, ID>` provides CRUD, pagination, and sorting for free. You write the interface; Spring writes the implementation.

**Q2. What is a derived query method?**
Spring parses method names to generate JPQL. `findByCustomerIdAndStatus(UUID id, OrderStatus s)` becomes `SELECT o FROM Order o WHERE o.customerId = ?1 AND o.status = ?2`. Rules: `findBy`, `deleteBy`, `countBy` + field names connected by `And`/`Or` + conditions (`IsNull`, `Between`, `LessThan`, `Like`, `OrderBy`).

**Q3. What is the difference between `findById()` and `getReferenceById()`?**
- `findById()`: fires a `SELECT` immediately, returns `Optional<T>` with fully loaded entity or empty
- `getReferenceById()`: returns a Hibernate proxy with no SQL; SQL fires only when you access a field. Use for associations where you need the ID only (e.g., setting a foreign key):
  ```java
  order.setCustomer(customerRepository.getReferenceById(customerId));  // no SELECT
  orderRepository.save(order);  // only INSERT with the FK value
  ```

**Q4. What does `@Transactional(readOnly = true)` do?**
Three effects: (1) Disables Hibernate dirty checking — no overhead comparing entities at flush. (2) Signals the DataSource to route to a read replica (if configured). (3) Prevents inadvertent writes. Apply to all service methods that only read; override with `@Transactional` for writes.

**Q5. What is the N+1 problem?**
Querying N entities then accessing their lazy-loaded associations fires N additional SELECT statements. Example: `findAll()` returns 100 orders; accessing `order.getItems()` for each fires 100 more SELECTs = 101 total. Fix: `JOIN FETCH`, `@EntityGraph`, or `hibernate.default_batch_fetch_size`.

---

## Advanced (L5 Senior)

**Q6. Explain `@Transactional` propagation levels.**

| Propagation | Behavior |
|-------------|---------|
| `REQUIRED` (default) | Join existing TX; create new if none |
| `REQUIRES_NEW` | Always create new; suspend outer TX |
| `SUPPORTS` | Use existing if present; run non-TX if none |
| `NOT_SUPPORTED` | Suspend existing; run non-transactionally |
| `MANDATORY` | Must have an existing TX; throw if none |
| `NEVER` | Must NOT have a TX; throw if one exists |
| `NESTED` | Savepoint within existing TX; partial rollback |

Use `REQUIRES_NEW` for audit logs that must persist even if the outer transaction rolls back.

**Q7. When does `@Transactional` NOT work?**
1. Self-invocation (AOP proxy bypassed)
2. Method is `private` or `final` (cannot be proxied)
3. Called from constructor or `@PostConstruct` (no proxy yet)
4. Exception is a checked exception (default rollback only for `RuntimeException`)
5. Transaction already committed before rollback decision

**Q8. What is optimistic locking and how do you implement it?**
Optimistic locking assumes conflicts are rare. Each entity has a `@Version` field (Long or Timestamp). On update, Hibernate includes `WHERE version = ?` in the UPDATE. If another thread updated first, the version changed — update affects 0 rows → Hibernate throws `ObjectOptimisticLockingFailureException`. Handle with retry or surface as HTTP 409.

**Q9. What is a `Specification` and when do you use it?**
`Specification<T>` encapsulates a JPA `CriteriaQuery` predicate. Useful for dynamic queries where filter conditions vary at runtime (search APIs). Composable with `and()`, `or()`, `not()`. Alternative to building query strings manually.

**Q10. What is the difference between `Page` and `Slice` in Spring Data?**
- `Page<T>`: includes total count (fires extra `COUNT` query) — needed for "Page 3 of 10" UIs
- `Slice<T>`: knows only `hasNext()` — no COUNT query — more efficient for infinite scroll or cursor-based pagination
- `List<T>`: no pagination metadata — use with cursor-based queries

---

## Principal Engineer Level

**Q11. How do you design data access for a service with 100M rows and complex query patterns?**

Three-tier strategy:
1. **Primary key access**: `findById()` → Redis cache → DB — sub-ms response
2. **Secondary index queries**: limit to indexed columns; avoid `SELECT *`; return projections
3. **Complex queries**: move to a read replica or separate analytics store; use CQRS — write to PostgreSQL, project read model into Elasticsearch or Cassandra

Schema design decisions at scale:
- Denormalize for read-heavy access patterns (accept write complexity)
- Partial indexes for common filter conditions (`WHERE status = 'ACTIVE'`)
- Partitioning by time/tenant for large tables
- `@BatchSize(50)` on collections to convert N+1 to N/50+1

**Q12. How do you handle database migrations safely in Spring Boot?**
Use Flyway or Liquibase:
- Flyway: versioned SQL scripts (`V1__create_orders.sql`, `V2__add_index.sql`)
- Always use non-destructive migrations in production: add columns (not remove), add indexes concurrently, rename via shadow columns
- `spring.flyway.validate-on-migrate=true` ensures consistency between code and schema
- For zero-downtime deploys: expand-contract pattern (add column → deploy → fill → deploy removing old code → remove column)

**Q13. What is the Spring Data multi-tenancy strategy and trade-offs?**

| Strategy | Isolation | Complexity | Use For |
|----------|-----------|-----------|---------|
| Separate database | Highest | High (1 datasource per tenant) | Enterprise SaaS, regulatory isolation |
| Separate schema | High | Medium (connection switching) | Mid-size SaaS |
| Row-level (discriminator) | Low | Low | Consumer SaaS, trusted tenants |

Hibernate multi-tenancy: configure `MultiTenantConnectionProvider` and `CurrentTenantIdentifierResolver`. Row-level: `@Filter("tenantId = :tenantId")` applied globally per session.

---

## Code Walkthroughs

**Q14. Will this update work correctly? Why or why not?**
```java
@Service
public class OrderService {
    @Transactional
    public void updateStatus(UUID id, OrderStatus status) {
        Order order = orderRepository.findById(id).orElseThrow();
        order.setStatus(status);
        // No save() call
    }
}
```
**Answer**: Yes, it works — Hibernate dirty checking. Within a `@Transactional` method, Hibernate tracks all managed entities. At transaction commit (flush), it compares the current state to the snapshot taken at load time. If `status` changed, Hibernate generates an `UPDATE` automatically. No `save()` needed for modifications to managed entities.

**Q15. What's the problem with this query?**
```java
@Query("SELECT o FROM Order o WHERE o.status = :status")
List<Order> findByStatus(OrderStatus status);
// Called with:
List<Order> orders = orderRepository.findByStatus(PENDING);
orders.forEach(o -> System.out.println(o.getCustomer().getName())); // Customer is @ManyToOne LAZY
```
**Answer**: N+1. `findByStatus` fetches N orders; `o.getCustomer()` fires a new SELECT for each order's customer. Fix: `@Query("SELECT o FROM Order o JOIN FETCH o.customer WHERE o.status = :status")` or add `@EntityGraph(attributePaths = "customer")` to the method.

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `FetchType.EAGER` on relationships | Cartesian product; always loads even when not needed | Always `LAZY`; explicitly load when needed |
| `EnumType.ORDINAL` in `@Enumerated` | Breaks if enum values reordered | Always `EnumType.STRING` |
| `@Transactional` on `private` methods | Ignored silently | Only on `public` or `protected` methods |
| Missing `@Modifying` on update/delete queries | `InvalidDataAccessApiUsageException` | Add `@Modifying` + `@Transactional` |
| Not calling `entityManager.clear()` in test | L1 cache returns stale entity | `TestEntityManager.flush(); entityManager.clear()` |
