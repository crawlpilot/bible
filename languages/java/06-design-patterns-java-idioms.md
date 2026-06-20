# 06 — Design Patterns and Java Idioms

**Calibration:** Principal Engineer bar  
**Boundary:** Full GoF catalog → [LLD/design-patterns/](../../LLD/design-patterns/). This file covers: modern Java idioms that replace classic patterns, SOLID non-obvious applications, DDD building blocks in Java.

---

## 1. Classic Patterns Replaced or Simplified by Modern Java

### Singleton → Enum Singleton

```java
// Classic: DCLP with volatile (fragile, verbose)
// See 03-concurrency-and-loom.md §2 for why DCLP is hard to get right

// Modern: Enum singleton — best practice since Java 5
public enum AppConfig {
    INSTANCE;

    private final String dbUrl = System.getenv("DB_URL");

    public String getDbUrl() { return dbUrl; }
}
// JLS guarantees: class loading is synchronized, enum constants initialized once
// Serialization-safe: enum deserialization returns the existing constant (no duplicate)
// Reflection-safe: cannot call constructor via reflection
```

### Visitor → Sealed Interface + Pattern Matching Switch

```java
// Classic Visitor: requires accept() on every type, separate visitor class
interface Shape { void accept(ShapeVisitor v); }
interface ShapeVisitor { void visit(Circle c); void visit(Rectangle r); }
class Circle implements Shape { public void accept(ShapeVisitor v) { v.visit(this); } }
// Adding a new Shape requires updating ALL visitors. Adding a new Visitor is easy.

// Modern: Sealed + switch expression
sealed interface Shape permits Circle, Rectangle, Triangle {}
record Circle(double radius) implements Shape {}
record Rectangle(double w, double h) implements Shape {}
record Triangle(double base, double height) implements Shape {}

// Adding a new operation: just write a new method
static double area(Shape s) {
    return switch (s) {
        case Circle(double r)           -> Math.PI * r * r;
        case Rectangle(double w, double h) -> w * h;
        case Triangle(double b, double h) -> 0.5 * b * h;
    };
}

static String describe(Shape s) {
    return switch (s) {
        case Circle c    -> "circle with radius " + c.radius();
        case Rectangle r -> "rectangle " + r.w() + "x" + r.h();
        case Triangle t  -> "triangle";
    };
}
```

**Trade-off table:**

| Criterion | Visitor Pattern | Sealed + Switch |
|-----------|----------------|----------------|
| Add new operation | Easy (new Visitor) | Easy (new method with switch) |
| Add new type | Hard (update all Visitors) | Hard (update all switches — but compiler catches it!) |
| Exhaustiveness check | No — runtime `IllegalArgumentException` | Yes — compile error |
| Readability | Low (indirection through accept) | High (co-located logic) |
| Null safety | No (null.accept() → NPE) | Yes (explicit `case null` or compile warning) |

**When Visitor is still better:** When the type hierarchy is in a library you don't control (can't add `permits`), or when you need to accumulate state across visits (visitor objects carry state easily; switch methods need external accumulators).

### Strategy → Functional Interface

```java
// Classic: separate class for each strategy
interface SortStrategy { void sort(int[] arr); }
class QuickSort implements SortStrategy { ... }
class MergeSort implements SortStrategy { ... }

// Modern: functional interface
@FunctionalInterface interface SortStrategy { void sort(int[] arr); }

// Usage: pass any lambda or method reference
process(arr, Arrays::sort);
process(arr, a -> bubbleSortImpl(a));
process(arr, myCustomSorter::sort);
```

### Null Object → `Optional` Chain

```java
// Classic: NullObject class that implements interface with no-op methods
interface Logger { void log(String msg); }
class NoOpLogger implements Logger { public void log(String msg) {} }

// Modern: Optional eliminates null objects for optional return values
Optional<Logger> logger = config.getLogger();  // empty if not configured
logger.ifPresent(l -> l.log("event happened"));
logger.orElse(NOOP).log("always logs");
```

---

## 2. SOLID — The Non-Obvious Applications

SOLID principles are well-known but often applied superficially. Principal engineers know the non-obvious cases.

### Single Responsibility — Domain Events

The naive application: "one method per class." The non-obvious application: separate **raising events** from **dispatching events**.

```java
// Anti-pattern: OrderService raises AND dispatches
class OrderService {
    private EmailService emailService;
    private InventoryService inventoryService;

    void placeOrder(Order order) {
        orderRepo.save(order);
        emailService.sendConfirmation(order);       // direct call — tight coupling
        inventoryService.reserveItems(order);       // direct call — tight coupling
    }
}
// Single change to email format requires touching OrderService
```

```java
// SRP with domain events: OrderService raises, infrastructure dispatches
class OrderService {
    private EventPublisher events;

    void placeOrder(Order order) {
        orderRepo.save(order);
        events.publish(new OrderPlacedEvent(order.id(), order.customerId()));
        // OrderService has no knowledge of email or inventory
    }
}
// EmailNotificationHandler listens for OrderPlacedEvent — independently changeable
// InventoryReservationHandler listens for OrderPlacedEvent — independently changeable
```

### Open/Closed — Sealed Classes

The classic OCP uses abstract classes and inheritance (open for extension, closed for modification). With sealed classes, the constraint flips:

```java
sealed interface PaymentMethod permits CreditCard, BankTransfer, Crypto {}

// Adding a new payment method (Crypto):
// 1. Add: record Crypto(String walletAddress) implements PaymentMethod {}
// 2. The compiler forces you to handle it in every switch
// → Closed for modification (don't edit existing switch)
// → Open for extension (add new sealed subtype)

// The compiler IS the closed-for-modification enforcement:
static void processPayment(PaymentMethod pm) {
    switch (pm) {
        case CreditCard cc -> chargeCreditCard(cc);
        case BankTransfer bt -> initiateBankTransfer(bt);
        // Adding Crypto without handling it: COMPILE ERROR ← the OCP enforcement mechanism
    }
}
```

### Liskov Substitution — Covariant Return Types

LSP: a subtype must be substitutable for its supertype without breaking the program.

**The non-obvious violation:** Strengthening preconditions or weakening postconditions.

```java
class AnimalFeeder {
    void feed(Animal animal, Food food) {}
}

class CatFeeder extends AnimalFeeder {
    @Override
    void feed(Animal animal, Food food) {
        if (!(animal instanceof Cat)) throw new IllegalArgumentException();  // LSP VIOLATION
        // Strengthened precondition: original accepts any Animal, override requires Cat
        // Code that works with AnimalFeeder may break with CatFeeder
    }
}

// LSP-compliant: covariant return type (weaker postcondition is fine)
class AnimalRepo {
    Animal findById(long id) { ... }
}
class CatRepo extends AnimalRepo {
    @Override
    Cat findById(long id) { ... }  // Cat IS-A Animal — valid covariant return
    // Callers expecting Animal still work; they just get a more specific type
}
```

### Interface Segregation — `@FunctionalInterface` + Default Methods

Don't force implementors to implement methods they don't use.

```java
// FAT interface — ISP violation
interface Processor {
    void process(Event e);
    void flush();            // many processors don't need explicit flushing
    void setMaxBatchSize(int n);  // not relevant for streaming processors
    int getProcessedCount();
}

// ISP: split into focused interfaces, use default methods for optional behavior
@FunctionalInterface
interface EventProcessor {
    void process(Event e);         // single required method
    default void flush() {}        // no-op default — override only if needed
    default int processedCount() { return -1; }  // optional metric
}

// Lambda-compatible: any lambda can implement EventProcessor
EventProcessor logger = e -> System.out.println(e);
// No need to implement flush() or processedCount() — defaults handle it
```

### Dependency Inversion — Field Injection vs. Constructor Injection

The most concrete DIP question in Java: why is `@Autowired` on fields wrong?

```java
// WRONG: Field injection
@Service
class OrderService {
    @Autowired private EmailService emailService;  // injected via reflection
    @Autowired private InventoryService inventory;

    // Problems:
    // 1. Cannot instantiate without Spring container — unit test requires @SpringBootTest or MockitoAnnotations
    // 2. Cannot do null checks at construction time (invariant validation impossible)
    // 3. Circular dependencies detected only at runtime (context startup)
    // 4. The dependency is implicit — reading the constructor doesn't reveal dependencies
}

// RIGHT: Constructor injection
@Service
class OrderService {
    private final EmailService emailService;
    private final InventoryService inventory;

    OrderService(EmailService emailService, InventoryService inventory) {
        this.emailService = Objects.requireNonNull(emailService);  // invariant validation
        this.inventory = Objects.requireNonNull(inventory);
    }
    // Unit test: new OrderService(mockEmail, mockInventory) — no container needed
    // Circular dependency: compile-time (can't construct the cycle)
    // Dependencies are explicit in the constructor signature
}
```

---

## 3. DDD Building Blocks in Java

### Entity vs. Value Object

```java
// Entity: mutable, identity-based equality (same ID = same entity)
@Entity
class Order {
    @Id
    private final OrderId id;          // strong identity type, not raw Long
    private OrderStatus status;        // mutable state
    private List<LineItem> items;

    @Override
    public boolean equals(Object o) {
        if (!(o instanceof Order other)) return false;
        return id.equals(other.id);    // identity-based: only id matters
    }
    @Override public int hashCode() { return id.hashCode(); }
}

// Value Object: immutable, structural equality (same values = same object)
// Modern Java: records ARE value objects
record Money(BigDecimal amount, Currency currency) {
    // Compact constructor for validation
    Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("negative money");
    }

    Money add(Money other) {
        if (!currency.equals(other.currency))
            throw new IllegalArgumentException("currency mismatch");
        return new Money(amount.add(other.amount), currency);
    }
}
// Money.equals() is structural by default (record auto-generates equals based on all components)
```

### Aggregate Invariant Enforcement via Package-Private Access

The aggregate root controls access to inner entities. Java's package-private visibility enforces this at the language level:

```java
// Package: com.example.order
// OrderAggregate.java — root (public)
public class Order {
    private final OrderId id;
    private final List<LineItem> items = new ArrayList<>();
    private Money total;

    public void addItem(Product product, int qty) {
        LineItem item = new LineItem(this, product, qty);  // can construct LineItem
        items.add(item);
        recalculateTotal();   // invariant: total is always consistent
    }

    public Money getTotal() { return total; }
    public List<LineItem> getItems() { return Collections.unmodifiableList(items); }
}

// LineItem.java — inner entity (package-private constructor)
class LineItem {
    private final Order order;        // reference to root (not public)
    private final Product product;
    private final int quantity;

    LineItem(Order order, Product product, int qty) {  // package-private constructor!
        this.order = order;
        this.product = product;
        this.quantity = qty;
    }
    // External code CANNOT create LineItem directly — must go through Order.addItem()
    // This enforces the invariant that total is always recalculated on addition
}
```

**Cross-aggregate references:** Aggregates should reference other aggregates by ID, not by object reference. This prevents cross-aggregate transactions:

```java
// WRONG: direct object reference across aggregates
class Order {
    private Customer customer;  // direct reference — pulls Customer into Order's transaction scope
}

// RIGHT: reference by ID
class Order {
    private CustomerId customerId;  // lightweight — no cascade loading
    // Load Customer separately when needed, in a separate transaction
}
```

### Domain Events with Sealed Interfaces

```java
// Sealed hierarchy for type-safe domain events
sealed interface OrderEvent permits
    OrderPlacedEvent, OrderCancelledEvent, OrderShippedEvent, OrderDeliveredEvent {}

record OrderPlacedEvent(OrderId orderId, CustomerId customerId, Money total,
                        Instant occurredAt) implements OrderEvent {}
record OrderCancelledEvent(OrderId orderId, String reason, Instant occurredAt) implements OrderEvent {}
record OrderShippedEvent(OrderId orderId, TrackingNumber tracking, Instant occurredAt) implements OrderEvent {}

// Handler with exhaustive switch — compiler catches missing cases
class OrderEventProjection {
    void project(OrderEvent event) {
        switch (event) {
            case OrderPlacedEvent e    -> incrementOrderCount(e.customerId());
            case OrderCancelledEvent e -> decrementOrderCount(e.orderId());
            case OrderShippedEvent e   -> updateShipmentStatus(e.tracking());
            case OrderDeliveredEvent e -> markDelivered(e.orderId());
            // Adding OrderRefundedEvent to the sealed hierarchy → compile error here
            // Forces the developer to handle the new event type
        }
    }
}
```

### Repository Interface in Domain Layer

The Repository interface belongs in the domain layer (high-level policy). The implementation belongs in the infrastructure layer. This is the DIP applied to persistence:

```java
// domain layer: no imports from Spring, Hibernate, or any framework
package com.example.order.domain;

interface OrderRepository {
    Optional<Order> findById(OrderId id);
    void save(Order order);
    List<Order> findByCustomerId(CustomerId customerId);
}

// infrastructure layer: implementation with Spring Data
package com.example.order.infrastructure;

@Repository
class JpaOrderRepository implements OrderRepository {
    private final SpringDataOrderRepo springRepo;

    @Override
    public Optional<Order> findById(OrderId id) {
        return springRepo.findById(id.value()).map(OrderMapper::toDomain);
    }
}

// The domain layer (OrderService) depends on the interface, never on JPA
// Swapping JPA for MongoDB: only change the infrastructure package
```

---

## 4. Template Method vs. Functional Composition

### Classic Template Method (Inheritance-Based)

```java
abstract class DataExporter {
    // Template method — defines the algorithm skeleton
    final void export(DataSet data) {
        validate(data);
        List<Row> rows = transform(data);    // hook 1 — subclass provides
        String formatted = format(rows);     // hook 2 — subclass provides
        write(formatted);
    }

    abstract List<Row> transform(DataSet data);
    abstract String format(List<Row> rows);

    private void validate(DataSet data) { ... }  // fixed step
    private void write(String content) { ... }   // fixed step
}

class CsvExporter extends DataExporter {
    @Override List<Row> transform(DataSet data) { ... }
    @Override String format(List<Row> rows) { ... }
}
```

### Functional Replacement

```java
class DataExporter {
    private final Function<DataSet, List<Row>> transformer;
    private final Function<List<Row>, String> formatter;

    DataExporter(Function<DataSet, List<Row>> transformer,
                 Function<List<Row>, String> formatter) {
        this.transformer = transformer;
        this.formatter = formatter;
    }

    void export(DataSet data) {
        validate(data);
        List<Row> rows = transformer.apply(data);
        String formatted = formatter.apply(rows);
        write(formatted);
    }
}

// Usage: compose from lambdas or method references
DataExporter csvExporter = new DataExporter(
    CsvTransformer::transform,
    CsvFormatter::format
);
DataExporter jsonExporter = new DataExporter(
    data -> JsonTransformer.toRows(data),
    rows -> JsonFormatter.format(rows)
);
```

**When inheritance-based Template Method is still correct:**
- Framework extension points (e.g., Spring's `AbstractMessageConverterMethodArgumentResolver`) where subclasses implement a protocol defined by the framework.
- When the algorithm skeleton has many interrelated steps that share protected state — passing all state via lambda captures becomes unwieldy.
- When the subclass must call `super.method()` for partial extension (functional composition can't do this cleanly).

---

## 5. Decorator Pattern — AOP Limitation

**The `this.method()` bypass:**

Spring AOP creates a proxy (JDK dynamic proxy or CGLIB subclass). Method calls on the proxy go through the `InvocationHandler` or the CGLIB interceptor — that's where AOP advice runs. But when a method calls another method via `this`, it bypasses the proxy:

```java
@Service
class OrderService {
    @Transactional
    void placeOrder(Order order) {
        saveOrder(order);
        notifyCustomer(order);
    }

    @Transactional(propagation = REQUIRES_NEW)
    void notifyCustomer(Order order) {  // ← transaction does NOT start
        // Called via this.notifyCustomer() inside placeOrder()
        // The call goes directly to the target object, not through the proxy
        // @Transactional on notifyCustomer is IGNORED
    }
}

// Fix: inject self-reference (ugly but works)
@Autowired private OrderService self;  // Spring injects the proxy
void placeOrder(Order order) {
    saveOrder(order);
    self.notifyCustomer(order);  // ← now goes through the proxy → @Transactional respected
}
// Better fix: extract notifyCustomer to a separate Spring bean
```

---

## Interview Q&A

### Q1 `[Principal]` Replace the Visitor pattern with sealed classes and pattern matching switch. What do you gain and what do you lose?

**Answer:**

**What you gain:**

1. **Compile-time exhaustiveness:** Adding a new sealed subtype causes a compile error at every switch that doesn't handle it. With Visitor, adding a new `Shape` requires updating all Visitor implementations — but the compiler gives no warning for forgetting.

2. **Readability:** The logic for each operation is co-located in one method with a switch. Visitor scatters logic across multiple classes (one per visitor).

3. **No boilerplate:** No `accept(Visitor v)` method on every type. Records are POJOs — no visitor plumbing.

4. **Record pattern decomposition:** `case Circle(double r) -> ...` destructures the record inline — impossible with Visitor.

**What you lose:**

1. **Open for new operations without modifying types:** With Visitor, you can add a new `CalculateShadowVisitor` without touching any `Shape` class. With sealed+switch, every new operation is a new switch — fine for internal code, problematic if the operations are user-defined plugins.

2. **Stateful traversal:** Visitor instances carry state between visits (running totals, depth tracking). A switch method needs external accumulators.

**Decision rule:**
- **Stable types, evolving operations → Visitor** (adding new operations is easy; compile errors guide adding new types to all visitors).
- **Evolving types, stable operations → Sealed+Switch** (adding new types forces compile-time update of all switches).
- **Internal code with known types and operations → Sealed+Switch** (readability wins).

---

### Q2 `[Principal]` Why does `@Autowired` field injection violate DIP, and what production problems does it cause?

**Answer:**

**DIP violation:** DIP says high-level modules should not depend on the details of the injection mechanism. Field injection uses Spring's `AutowiredAnnotationBeanPostProcessor` to reflectively set private fields via `Field.setAccessible(true)`. The class now implicitly depends on Spring's internal reflection mechanism — not just the interface it declares as a dependency.

**Production problems:**

1. **Unit test complexity:** `new OrderService()` has `null` fields. Every unit test requires either `@SpringBootTest` (loads full context: 10–30 seconds) or `MockitoAnnotations.openMocks(this)` (fragile, uses reflection). Constructor injection: `new OrderService(mockEmail, mockInventory)` — pure Java, instantaneous.

2. **Invariant validation impossible:** The constructor runs before fields are injected. `Objects.requireNonNull(emailService)` in a constructor would throw before Spring can inject. With constructor injection, you can validate and throw `NullPointerException` immediately if a required dependency is missing — at startup, not at first use.

3. **Circular dependency detection:** Field injection allows circular dependencies (`A → B → A`) — they're detected at context startup (runtime). Constructor injection makes the cycle impossible to construct — the Java compiler detects it (you'd need `A` to construct `B` and `B` to construct `A` — impossible).

4. **Immutability:** Field injection forces fields to be non-final (`final` fields set by constructor, not by later reflection). Constructor injection enables `private final` fields — immutable, thread-safe, clearly owned by the constructor.

---

### Q3 `[Principal]` How do Aggregate boundaries in DDD map to Java's accessibility model, and what is the "reference by ID" rule?

**Answer:**

**Accessibility as boundary enforcement:**

An Aggregate root is `public`. Inner entities are `package-private` (default access). This is not a convention — it is Java's access control system enforcing the Aggregate invariant:

```
package com.example.order:
  Order.java         — public class (Aggregate root)
  LineItem.java      — package-private class (inner entity)
  OrderItem.java     — package-private class (inner entity)

package com.example.catalog:
  CatalogService.java — CANNOT instantiate LineItem or OrderItem
                         (package-private: not visible outside com.example.order)
```

Any code outside the `com.example.order` package must go through `Order`'s public methods to create or modify `LineItem`. This guarantees the invariant that `Order.total` is always recalculated when items change.

**The reference by ID rule:**

Aggregate roots must not hold direct object references to other Aggregate roots. Only IDs:

```java
// WRONG: Order holds direct reference to Customer aggregate
class Order {
    private Customer customer;
    // Hibernate: loading Order loads Customer (and Customer.addresses, Customer.orders...)
    // JPA transaction: saving Order may cascade to Customer
    // Boundary violation: Order's invariants now span Customer's data
}

// RIGHT: reference by ID
class Order {
    private CustomerId customerId;
    // Loading Order: no Customer loaded
    // Saving Order: no Customer touched
    // Separate use case: load Customer separately, in a separate transaction
}
```

**Why this matters at scale:** At FAANG scale, each Aggregate maps to a potential microservice boundary. If `Order` holds a direct reference to `Customer`, separating them into different services becomes refactoring hell. The "reference by ID" rule is the distributed systems boundary drawn at the domain model level.

---

*See also:* [LLD/design-patterns/](../../LLD/design-patterns/) for full GoF implementations | [01-modern-language-features.md](01-modern-language-features.md) for sealed classes and records | [03-concurrency-and-loom.md](03-concurrency-and-loom.md) for DCLP Singleton
