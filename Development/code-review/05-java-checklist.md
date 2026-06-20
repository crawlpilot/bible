# Java — Code Review Checklist

> Java-specific items to check on every Java PR. Applies to Java 11+. Items that differ for Java 17+ or Java 21 are called out explicitly.

---

## Quick Checklist

```
Null Safety
  ☐ No NullPointerException risk — Optional used where a value may be absent
  ☐ Optional not used as a method parameter or field type
  ☐ @NonNull / @Nullable annotations on public API boundaries

Exceptions
  ☐ Checked exceptions not used for recoverable business cases
  ☐ Exception cause always chained (new RuntimeException(message, cause))
  ☐ Custom exceptions extend the right base class
  ☐ No catch (Exception e) or catch (Throwable e) without strong justification

Collections and Streams
  ☐ Stream operations are stateless and not sharing mutable state
  ☐ No parallel streams on small collections or I/O-bound operations
  ☐ Collectors.toList() vs List.copyOf() — mutability intent is clear
  ☐ No modification of a collection while iterating it (ConcurrentModificationException)

Concurrency
  ☐ Shared mutable state protected by synchronisation or atomic classes
  ☐ Locks acquired in consistent order (deadlock prevention)
  ☐ No busy-wait (while(flag) {} without sleep/yield)
  ☐ CompletableFuture chains handle exceptions (exceptionally / handle)
  ☐ No ExecutorService.shutdown() missing

Immutability
  ☐ Value objects are immutable (final fields, no setters, defensive copy in constructor)
  ☐ Collections returned from getters are unmodifiable
  ☐ record used for pure data carriers (Java 16+)

equals / hashCode / Comparable
  ☐ If equals() is overridden, hashCode() is also overridden
  ☐ equals() and hashCode() use the same fields
  ☐ Comparable.compareTo() is consistent with equals()

Resources
  ☐ All AutoCloseable resources in try-with-resources
  ☐ No manual close() in finally without try-with-resources
```

---

## Null Safety

```java
// [BLOCK] NPE risk — method may return null; caller doesn't check
String name = user.getName().toUpperCase();   // NPE if getName() returns null

// [BLOCK] Optional used as parameter — forces callers to wrap
public Order findOrder(Optional<String> orderId) { ... }
// CORRECT: Optional is for return types only
public Optional<Order> findOrder(String orderId) { ... }

// [BLOCK] Optional.get() without isPresent() check
Optional<Order> order = orderRepository.findById(id);
return order.get();   // throws NoSuchElementException if empty
// CORRECT:
return order.orElseThrow(() -> new OrderNotFoundException(id));

// [WARN] Optional used as a field type (serialisation issues)
public class Order {
    private Optional<String> couponCode;   // don't do this
}
// CORRECT: use @Nullable String couponCode; handle null in methods

// [WARN] Optional.ifPresent when orElse is cleaner
Optional<String> name = getName();
if (name.isPresent()) {
    return name.get();
} else {
    return "Unknown";
}
// CORRECT:
return getName().orElse("Unknown");

// [NIT] Chained Optional operations are readable (Java 9+)
Optional<String> city = getUser()
    .flatMap(User::getAddress)
    .map(Address::getCity);
```

---

## Exceptions

```java
// [BLOCK] Swallowing the cause — root cause lost
try {
    riskyOperation();
} catch (IOException e) {
    throw new ServiceException("Operation failed");  // cause not chained
}
// CORRECT:
throw new ServiceException("Operation failed", e);  // cause preserved

// [BLOCK] Catching Error (OutOfMemoryError, StackOverflowError)
try {
    doWork();
} catch (Error e) {
    log.error("Error occurred", e);
    // Cannot safely recover from OOM or SOE
}

// [WARN] Checked exception used for domain logic
// Checked exceptions force callers to handle; appropriate for I/O, not domain
public Order submitOrder(String orderId) throws OrderAlreadySubmittedException { ... }
// CORRECT: use unchecked (RuntimeException subclass) for domain errors
public Order submitOrder(String orderId) throws OrderAlreadySubmittedException { ... }
// Actually checked is OK here — it forces callers to think about this case
// But: don't use checked exceptions for things callers can't reasonably handle

// [WARN] Exception message not useful
throw new IllegalStateException("Error");  // which error? what state?
// CORRECT:
throw new IllegalStateException(
    String.format("Cannot submit order %s: current status is %s, expected DRAFT", orderId, status));

// [NIT] Custom exception class missing standard constructors
public class OrderNotFoundException extends RuntimeException {
    // CORRECT: provide all four standard constructors
    public OrderNotFoundException(String message) { super(message); }
    public OrderNotFoundException(String message, Throwable cause) { super(message, cause); }
    public OrderNotFoundException(Throwable cause) { super(cause); }
    protected OrderNotFoundException(String message, Throwable cause,
                                     boolean enableSuppression, boolean writableStackTrace) {
        super(message, cause, enableSuppression, writableStackTrace);
    }
}
```

---

## Collections and Streams

```java
// [BLOCK] ConcurrentModificationException — modifying while iterating
for (Order order : orders) {
    if (order.isCancelled()) {
        orders.remove(order);   // throws ConcurrentModificationException
    }
}
// CORRECT:
orders.removeIf(Order::isCancelled);

// [WARN] Mutable list returned from getter (exposes internal state)
public class Order {
    private List<OrderLine> lines = new ArrayList<>();
    public List<OrderLine> getLines() { return lines; }   // caller can mutate internal state
}
// CORRECT:
public List<OrderLine> getLines() { return Collections.unmodifiableList(lines); }
// Or in Java 10+:
public List<OrderLine> getLines() { return List.copyOf(lines); }

// [WARN] parallel() on I/O-bound or small collection
List<Order> results = orders.parallelStream()
    .map(o -> orderRepository.enrich(o))   // DB call per item — all use common ForkJoinPool
    .collect(toList());
// CORRECT: parallel streams are only for CPU-bound operations with large collections;
// for I/O, use CompletableFuture with a dedicated executor

// [WARN] collect(toList()) when immutable list is fine
List<Order> submitted = orders.stream()
    .filter(Order::isSubmitted)
    .collect(Collectors.toList());  // mutable list
// If caller won't mutate result:
List<Order> submitted = orders.stream()
    .filter(Order::isSubmitted)
    .toList();  // Java 16+ — unmodifiable

// [NIT] Stream re-use (streams are not reusable)
Stream<Order> stream = orders.stream();
stream.filter(Order::isActive).count();
stream.filter(Order::isCancelled).count();  // throws IllegalStateException
```

---

## Concurrency

```java
// [BLOCK] Unsynchronised access to shared mutable state
private int requestCount = 0;

@GetMapping("/orders")
public List<Order> getOrders() {
    requestCount++;   // not thread-safe — lost updates under concurrency
    ...
}
// CORRECT:
private final AtomicInteger requestCount = new AtomicInteger(0);
requestCount.incrementAndGet();

// [BLOCK] Deadlock risk — inconsistent lock ordering
void transfer(Account from, Account to, int amount) {
    synchronized(from) {
        synchronized(to) {
            from.debit(amount);
            to.credit(amount);
        }
    }
    // Thread A: lock(accountA) then lock(accountB)
    // Thread B: lock(accountB) then lock(accountA) → deadlock
}
// CORRECT: always acquire locks in a consistent global order (e.g., by account ID)
Account first = from.getId().compareTo(to.getId()) < 0 ? from : to;
Account second = first == from ? to : from;
synchronized(first) { synchronized(second) { ... } }

// [BLOCK] CompletableFuture exception not handled
CompletableFuture<Order> future = CompletableFuture
    .supplyAsync(() -> orderService.create(request));
// If supplyAsync throws, the exception is silently captured in the future
// CORRECT:
CompletableFuture<Order> future = CompletableFuture
    .supplyAsync(() -> orderService.create(request))
    .exceptionally(ex -> {
        log.error("order.creation.failed", ex);
        throw new CompletionException(ex);
    });

// [WARN] volatile misunderstood — volatile guarantees visibility, not atomicity
private volatile int counter = 0;
counter++;   // not atomic — read-modify-write is still a race condition
// CORRECT:
private final AtomicInteger counter = new AtomicInteger(0);
counter.incrementAndGet();

// [WARN] Executor not shut down on application stop
ExecutorService executor = Executors.newFixedThreadPool(10);
// MISSING: executor.shutdown() on application shutdown
// CORRECT: register shutdown hook or use Spring @PreDestroy
@PreDestroy
public void shutdown() {
    executor.shutdown();
    try { executor.awaitTermination(30, SECONDS); }
    catch (InterruptedException e) { Thread.currentThread().interrupt(); }
}
```

---

## Immutability

```java
// [WARN] Value object with setters — opens mutation after construction
public class Money {
    private String amount;
    private String currency;
    public void setAmount(String amount) { this.amount = amount; }  // allows mutation
}
// CORRECT: final fields, no setters
public final class Money {
    private final String amount;
    private final String currency;
    public Money(String amount, String currency) {
        this.amount = Objects.requireNonNull(amount);
        this.currency = Objects.requireNonNull(currency);
    }
    // Only getters, no setters
}

// Java 16+ — use record for pure data carriers (auto: final fields, equals, hashCode, toString)
public record Money(String amount, String currency) {
    // Compact constructor for validation
    public Money {
        Objects.requireNonNull(amount, "amount must not be null");
        Objects.requireNonNull(currency, "currency must not be null");
    }
}

// [WARN] Defensive copy missing in constructor
public class Order {
    private final List<OrderLine> lines;
    public Order(List<OrderLine> lines) {
        this.lines = lines;   // caller retains reference; can mutate the list
    }
}
// CORRECT:
public Order(List<OrderLine> lines) {
    this.lines = List.copyOf(lines);  // defensive copy; immutable
}
```

---

## equals / hashCode

```java
// [BLOCK] equals() overridden without hashCode() — breaks HashMap/HashSet
public class OrderId {
    private final String value;

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof OrderId)) return false;
        return Objects.equals(value, ((OrderId) o).value);
    }
    // MISSING: hashCode() — if equals() returns true, hashCode() must be equal
}
// CORRECT: always override both. Use Objects.hash():
@Override
public int hashCode() { return Objects.hash(value); }

// [WARN] equals() inconsistent with compareTo()
// If a.equals(b) is true, a.compareTo(b) must return 0
// If violated, behavior in TreeMap/TreeSet is undefined

// [NIT] instanceof pattern matching (Java 16+) in equals
@Override
public boolean equals(Object o) {
    if (!(o instanceof OrderId other)) return false;  // pattern matching
    return Objects.equals(value, other.value);
}
```

---

## String and Formatting

```java
// [WARN] String concatenation in a loop
String result = "";
for (String item : items) { result += item; }   // O(n²) — creates n intermediate strings
// CORRECT:
String result = String.join("", items);
// Or:
String result = items.stream().collect(Collectors.joining());

// [NIT] Use text blocks for multi-line strings (Java 15+)
String sql = "SELECT o.id, o.status, c.name\n" +
             "FROM orders o\n" +
             "JOIN customers c ON o.customer_id = c.id\n" +
             "WHERE o.status = 'SUBMITTED'";
// CORRECT (Java 15+):
String sql = """
    SELECT o.id, o.status, c.name
    FROM orders o
    JOIN customers c ON o.customer_id = c.id
    WHERE o.status = 'SUBMITTED'
    """;
```

---

## Modern Java (17 / 21)

```java
// [SUGGESTION] Sealed classes for sum types (Java 17+)
// Instead of an open hierarchy with instanceof chains:
if (event instanceof OrderSubmittedEvent) { ... }
else if (event instanceof OrderCancelledEvent) { ... }
// Use sealed + pattern matching switch (Java 21):
sealed interface OrderEvent permits OrderSubmittedEvent, OrderCancelledEvent, OrderShippedEvent {}

String describe(OrderEvent event) {
    return switch (event) {
        case OrderSubmittedEvent e -> "Submitted: " + e.orderId();
        case OrderCancelledEvent e -> "Cancelled: " + e.reason();
        case OrderShippedEvent e   -> "Shipped to: " + e.address();
    };  // compiler enforces exhaustiveness
}

// [SUGGESTION] Virtual threads (Java 21) for high-concurrency I/O
// Replace:
ExecutorService executor = Executors.newFixedThreadPool(200);
// With:
ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();
// Virtual threads are cheap — one per request is now feasible
```

---

## Reviewer Severity Summary

| Issue | Severity |
|---|---|
| NPE risk — Optional.get() without check | `[BLOCK]` |
| Exception cause not chained | `[BLOCK]` |
| Unsynchronised shared mutable state | `[BLOCK]` |
| Deadlock risk (inconsistent lock order) | `[BLOCK]` |
| ConcurrentModificationException (modify while iterating) | `[BLOCK]` |
| equals() without hashCode() | `[BLOCK]` |
| Resource not closed (no try-with-resources) | `[BLOCK]` |
| CompletableFuture exception not handled | `[WARN]` |
| parallel() on I/O-bound operations | `[WARN]` |
| Mutable collection returned from getter | `[WARN]` |
| Optional as method parameter | `[WARN]` |
| Executor not shut down | `[WARN]` |
| String concat in loop | `[WARN]` |
| Missing defensive copy in constructor | `[WARN]` |
| Missing text block for multi-line strings | `[NIT]` |
