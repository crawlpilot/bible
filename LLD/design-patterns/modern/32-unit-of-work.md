# 32. Unit of Work
**Category**: Modern / Enterprise  
**GoF**: No (Fowler, "Patterns of Enterprise Application Architecture", 2002)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Occasional

> Maintain a list of objects affected by a business transaction and coordinates the writing out of changes and the resolution of concurrency problems.

---

## Problem It Solves

Placing an order requires: creating an `Order`, decrementing `InventoryReservation`, creating a `PaymentRecord`, and accruing `LoyaltyPoints`. Each has its own repository. Without Unit of Work, the application service calls each repository separately — 4 separate transactions. If `PaymentRecord.save()` succeeds but `LoyaltyPoints.save()` fails, there's no rollback. Unit of Work tracks all changes and commits them in a single transaction.

## Structure (Participants)

```
            UnitOfWork
  ┌───────────────────────────────────────────┐
  │ - orderRepo: OrderRepository              │
  │ - inventoryRepo: InventoryRepository      │
  │ - paymentRepo: PaymentRepository          │
  │ - loyaltyRepo: LoyaltyRepository          │
  │                                           │
  │ + commit(): void                          │
  │ + rollback(): void                        │
  │                                           │
  │ Internally tracks:                        │
  │   newObjects, dirtyObjects, removedObjects│
  └───────────────────────────────────────────┘
             │
    ApplicationService
  ┌──────────────────────────────────────────┐
  │ uow = unitOfWorkFactory.begin()          │
  │ uow.orders.save(order)                   │
  │ uow.inventory.decrement(sku, qty)        │
  │ uow.payments.save(payment)               │
  │ uow.commit()  ← single ACID transaction  │
  └──────────────────────────────────────────┘
```

Key participants:
- **Unit of Work** (`OrderUnitOfWork`): manages a set of repositories; calls all saves in one transaction
- **Repositories** (within UoW): track objects registered by the application service
- **Application Service**: opens a UoW, uses its repositories, calls `commit()` or `rollback()`
- **Change Tracker**: optional — tracks modified objects automatically (ORM-style)

---

## Real-World Use Case: Order Placement Transaction

Placing an order touches 4 data stores. Unit of Work ensures all 4 changes commit atomically, or none do. The application service works with clean repository interfaces; the UoW handles the transaction boundary.

### Implementation

```java
// Unit of Work interface
public interface UnitOfWork {
    OrderRepository orders();
    InventoryRepository inventory();
    PaymentRepository payments();
    LoyaltyRepository loyalty();
    void commit();
    void rollback();
}

// Spring/JDBC implementation — single DataSource connection, one transaction
@Component
@Scope("prototype")  // new instance per use
public class OrderUnitOfWork implements UnitOfWork {
    private final Connection connection;
    private final List<Runnable> commitCallbacks = new ArrayList<>();
    private final List<Runnable> rollbackCallbacks = new ArrayList<>();

    // Repositories share the same connection — same transaction
    private final OrderRepository orderRepo;
    private final InventoryRepository inventoryRepo;
    private final PaymentRepository paymentRepo;
    private final LoyaltyRepository loyaltyRepo;

    public OrderUnitOfWork(DataSource dataSource) throws SQLException {
        this.connection = dataSource.getConnection();
        this.connection.setAutoCommit(false);

        // All repos share the same connection
        this.orderRepo     = new JdbcOrderRepository(connection);
        this.inventoryRepo = new JdbcInventoryRepository(connection);
        this.paymentRepo   = new JdbcPaymentRepository(connection);
        this.loyaltyRepo   = new JdbcLoyaltyRepository(connection);
    }

    @Override public OrderRepository orders()       { return orderRepo; }
    @Override public InventoryRepository inventory() { return inventoryRepo; }
    @Override public PaymentRepository payments()    { return paymentRepo; }
    @Override public LoyaltyRepository loyalty()     { return loyaltyRepo; }

    @Override
    public void commit() {
        try {
            connection.commit();
            commitCallbacks.forEach(Runnable::run);
        } catch (SQLException e) {
            rollback();
            throw new UnitOfWorkCommitException("Commit failed", e);
        } finally {
            closeConnection();
        }
    }

    @Override
    public void rollback() {
        try {
            connection.rollback();
            rollbackCallbacks.forEach(Runnable::run);
        } catch (SQLException e) {
            log.error("Rollback failed", e);
        } finally {
            closeConnection();
        }
    }

    private void closeConnection() {
        try { connection.close(); } catch (SQLException ignored) {}
    }

    // Register callbacks for post-commit actions (e.g., publish events)
    public void onCommit(Runnable callback)   { commitCallbacks.add(callback); }
    public void onRollback(Runnable callback) { rollbackCallbacks.add(callback); }
}

// Factory
@Component
public class UnitOfWorkFactory {
    private final DataSource dataSource;

    public OrderUnitOfWork begin() {
        try {
            return new OrderUnitOfWork(dataSource);
        } catch (SQLException e) {
            throw new UnitOfWorkException("Could not begin unit of work", e);
        }
    }
}

// Application service — clean transaction boundary
@Service
public class OrderApplicationService {
    private final UnitOfWorkFactory uowFactory;
    private final OutboxService outboxService;

    public Order placeOrder(PlaceOrderCommand cmd, User user) {
        OrderUnitOfWork uow = uowFactory.begin();

        try {
            // All operations share the same DB connection/transaction
            Order order = Order.create(cmd, user);
            uow.orders().save(order);

            for (OrderItem item : order.getItems()) {
                uow.inventory().decrementReservation(item.sku(), item.quantity(), order.id());
            }

            PaymentRecord payment = new PaymentRecord(order.id(), order.total(), cmd.transactionId());
            uow.payments().save(payment);

            int pointsToAccrue = order.total().toCents() / 100;  // 1 point per dollar
            uow.loyalty().accruePoints(user.id(), pointsToAccrue, order.id());

            // Register post-commit callback to publish events
            uow.onCommit(() -> outboxService.publish(new OrderPlacedEvent(order)));
            uow.onRollback(() -> log.warn("Order placement rolled back: {}", order.id()));

            uow.commit();  // single ACID commit for all 4 operations
            return order;

        } catch (OutOfStockException | PaymentFailedException e) {
            uow.rollback();
            throw e;
        } catch (Exception e) {
            uow.rollback();
            throw new OrderPlacementException("Unexpected error", e);
        }
    }
}

// With JPA / Spring @Transactional (simplified UoW)
// Spring's EntityManager IS a Unit of Work — tracks dirty objects and flushes in @Transactional
@Service
@Transactional
public class JpaOrderApplicationService {
    private final OrderJpaRepository orderRepo;
    private final InventoryJpaRepository inventoryRepo;
    private final PaymentJpaRepository paymentRepo;
    private final LoyaltyJpaRepository loyaltyRepo;

    public Order placeOrder(PlaceOrderCommand cmd, User user) {
        Order order = Order.create(cmd, user);
        orderRepo.save(order);  // JPA tracks this entity

        for (OrderItem item : order.getItems()) {
            InventoryReservation res = inventoryRepo.findBySkuForUpdate(item.sku())
                .orElseThrow(() -> new OutOfStockException(item.sku()));
            res.decrement(item.quantity());
            inventoryRepo.save(res);
        }

        PaymentRecord payment = new PaymentRecord(order.id(), order.total(), cmd.transactionId());
        paymentRepo.save(payment);

        LoyaltyAccount account = loyaltyRepo.findByUserId(user.id());
        account.accruePoints(order.total().toCents() / 100);
        loyaltyRepo.save(account);

        // @Transactional commits all of the above at method exit
        // EntityManager = UoW: it tracked all dirty entities and flushes them in one TX
        return order;
    }
}
```

### How It Works (walkthrough)

1. `uowFactory.begin()` → new `Connection` from pool, `autoCommit=false`
2. `uow.orders().save(order)` → `INSERT INTO orders` on the shared connection
3. `uow.inventory().decrementReservation(sku, qty, orderId)` → `UPDATE inventory_reservations` (same connection)
4. `uow.payments().save(payment)` → `INSERT INTO payments` (same connection)
5. `uow.loyalty().accruePoints(userId, points, orderId)` → `INSERT INTO loyalty_transactions` (same connection)
6. `uow.commit()` → `connection.commit()` → single ACID commit for all 4 operations
7. Post-commit callback fires → `outboxService.publish(OrderPlacedEvent)` → event published reliably
8. On any exception: `uow.rollback()` → `connection.rollback()` → all 4 operations rolled back

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | UoW manages the transaction; service manages business logic; repos manage data access |
| Open/Closed | ✅ | Add `NotificationRepository` to the UoW without changing service code |
| Liskov Substitution | ✅ | Any `UnitOfWork` implementation substitutable |
| Interface Segregation | ✅ | `commit()`, `rollback()`, and per-domain repo accessors |
| Dependency Inversion | ✅ | Service depends on `UnitOfWork` interface, not JDBC/JPA directly |

---

## When to Use

- A business operation must write to multiple tables or repositories atomically
- You need an explicit transaction boundary that spans multiple repository calls
- Post-commit callbacks are needed (e.g., publish events only if TX committed)
- Testing: inject an in-memory UoW to test service logic without a DB

## When NOT to Use

- Only one repository is used — @Transactional on a single service method is sufficient
- Spring @Transactional already provides UoW semantics via JPA EntityManager
- Distributed transactions across multiple databases — use Saga instead

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Atomic multi-repo commit — all or nothing | DB connection held for the entire business operation duration |
| Explicit transaction boundary — easy to see what commits together | `prototype` scoped beans in Spring require careful lifecycle management |
| Post-commit/rollback callbacks — reliable event publishing | More complex than @Transactional — only justified when @Transactional is insufficient |

---

**FAANG interview application**: "Unit of Work is most valuable when you need explicit control over what happens after commit — publish events only if the DB commit succeeded. Spring's @Transactional with JPA EntityManager is a built-in UoW, but it doesn't give you post-commit callbacks easily. The explicit UoW pattern does: `uow.onCommit(() -> publishEvent(order))` — the event is only published if all 4 DB writes committed. This is the application-layer implementation of the Outbox pattern's guarantee."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Repository](24-repository.md) | Unit of Work coordinates multiple repositories in a single transaction |
| [Outbox Pattern](28-outbox-pattern.md) | UoW's `onCommit` callback is where the Outbox entry is written or the event is published |
| [Saga](26-saga.md) | Saga is the distributed alternative when UoW's single-DB transaction boundary is not enough |
