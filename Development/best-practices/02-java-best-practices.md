# Java Best Practices — Production-Grade Engineering

## Overview
Java remains the dominant language at FAANG backend engineering (Google, Amazon, LinkedIn, Netflix all run massive Java services). This document covers production-grade Java practices calibrated to principal engineer expectations: not "effective Java tips" but the engineering discipline that makes Java services survive at 100M+ user scale — memory management, concurrency, API design, testing discipline, and operational hygiene.

---

## Core References (The Canon)
- **Effective Java** — Joshua Bloch (3rd edition, 2018): the industry bible. Every item is a principal engineer expectation.
- **Java Concurrency in Practice** — Goetz et al. (2006): still definitive for multi-threaded code.
- **Clean Code** — Robert C. Martin: naming and structure discipline.
- **The Java Memory Model Specification** (JLS §17): authoritative reference for visibility and ordering.

---

## Language Fundamentals at Production Scale

### Immutability First

```java
// WRONG: mutable; race conditions under concurrent access
public class Money {
    private BigDecimal amount;
    private Currency currency;
    
    public void setAmount(BigDecimal amount) { this.amount = amount; }
}

// CORRECT: immutable Value Object
public final class Money {
    private final BigDecimal amount;
    private final Currency currency;
    
    public Money(BigDecimal amount, Currency currency) {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("amount must be non-negative");
        this.amount = amount;
        this.currency = currency;
    }
    
    public Money add(Money other) {
        if (!this.currency.equals(other.currency))
            throw new IllegalArgumentException("Currency mismatch: " + this.currency + " vs " + other.currency);
        return new Money(this.amount.add(other.amount), this.currency);
    }
    
    // equals, hashCode, toString all based on value, not identity
    @Override public boolean equals(Object o) { ... }
    @Override public int hashCode() { ... }
}
```

**Rule**: all domain Value Objects should be immutable (`final` class, `final` fields, no setters, defensive copies in constructors).

---

### Records (Java 16+) for Value Objects

```java
// Modern: use records for pure data carriers
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("amount must be non-negative");
    }
    
    public Money add(Money other) {
        if (!this.currency.equals(other.currency))
            throw new IllegalArgumentException("Currency mismatch");
        return new Money(this.amount.add(other.amount), this.currency);
    }
}
```

Records eliminate boilerplate `equals`, `hashCode`, `toString`, and accessor methods. Use for Value Objects and DTOs.

---

### Effective Use of Optionals

```java
// WRONG: Optional as a field or method parameter
public class Order {
    private Optional<String> trackingNumber; // Don't — fields are never Optional
}

public void process(Optional<OrderId> orderId) { ... } // Don't — parameters are never Optional

// WRONG: Optional.get() without check
Order order = repo.findById(id).get(); // throws NoSuchElementException in production

// CORRECT: Optional as return type only; always handle empty case
public Optional<Order> findById(OrderId id) {
    return Optional.ofNullable(store.get(id));
}

// CORRECT: chain without explicit isPresent()
Order order = repo.findById(id)
    .orElseThrow(() -> new OrderNotFoundException(id));

// CORRECT: transform without unpacking
String status = repo.findById(id)
    .map(Order::status)
    .map(OrderStatus::displayName)
    .orElse("UNKNOWN");
```

**Effective Java Item 55**: `Optional` is for return values from methods that might not return a result. Not for fields, not for parameters.

---

### Generics and Type Safety

```java
// WRONG: raw types lose type safety
List orders = repo.findAll(); // List<Object> — ClassCastException at runtime
Map config = new HashMap();   // Don't

// CORRECT: always parameterise
List<Order> orders = repo.findAll();
Map<String, String> config = new HashMap<>();

// CORRECT: wildcard for producer/consumer patterns (PECS)
public void processOrders(List<? extends Order> orders) { ... }  // producer: extends
public void addTo(List<? super Order> target, Order order) { ... } // consumer: super

// CORRECT: bounded type for constraints
public <T extends Comparable<T>> T max(List<T> list) { ... }
```

---

## Object-Oriented Design Standards

### Builder Pattern for Complex Constructors (Bloch Item 2)

```java
// WRONG: telescoping constructor
public Order(OrderId id, CustomerId customerId, List<OrderLine> lines) { ... }
public Order(OrderId id, CustomerId customerId, List<OrderLine> lines, Instant createdAt) { ... }
// Grows indefinitely; calling code has no idea what position 3 means

// CORRECT: Builder
public final class Order {
    private final OrderId id;
    private final CustomerId customerId;
    private final List<OrderLine> lines;
    private final Instant createdAt;
    
    private Order(Builder builder) {
        this.id = Objects.requireNonNull(builder.id, "id");
        this.customerId = Objects.requireNonNull(builder.customerId, "customerId");
        this.lines = List.copyOf(builder.lines);
        this.createdAt = builder.createdAt != null ? builder.createdAt : Instant.now();
    }
    
    public static Builder builder(OrderId id, CustomerId customerId) {
        return new Builder(id, customerId);
    }
    
    public static class Builder {
        private final OrderId id;
        private final CustomerId customerId;
        private List<OrderLine> lines = new ArrayList<>();
        private Instant createdAt;
        
        private Builder(OrderId id, CustomerId customerId) {
            this.id = id;
            this.customerId = customerId;
        }
        
        public Builder lines(List<OrderLine> lines) {
            this.lines = new ArrayList<>(lines);
            return this;
        }
        
        public Builder createdAt(Instant createdAt) {
            this.createdAt = createdAt;
            return this;
        }
        
        public Order build() { return new Order(this); }
    }
}

// Usage — self-documenting
Order order = Order.builder(orderId, customerId)
    .lines(orderLines)
    .createdAt(Instant.now())
    .build();
```

---

### Interface Design

```java
// CORRECT: program to interfaces, not implementations
public interface OrderRepository {
    void save(Order order);
    Optional<Order> findById(OrderId id);
    List<Order> findByCustomer(CustomerId customerId);
}

// CORRECT: use default methods for backwards-compatible interface evolution
public interface OrderRepository {
    void save(Order order);
    Optional<Order> findById(OrderId id);
    
    // Added in v2 — default prevents breaking existing implementations
    default boolean exists(OrderId id) {
        return findById(id).isPresent();
    }
}

// CORRECT: functional interfaces for single-operation abstractions
@FunctionalInterface
public interface OrderValidator {
    ValidationResult validate(Order order);
}
```

---

## Exception Handling Standards

```java
// WRONG: catching and swallowing exceptions
try {
    processOrder(order);
} catch (Exception e) {
    // Do nothing — this hides failures in production
}

// WRONG: catching Exception or Throwable broadly
try {
    processOrder(order);
} catch (Exception e) {
    log.error("Failed", e); // Still too broad — catches NPE, OOM, everything
}

// CORRECT: catch specific exceptions; preserve context
try {
    processOrder(order);
} catch (OrderNotFoundException e) {
    throw new OrderProcessingException("Order not found: " + order.id(), e);
} catch (PaymentDeclinedException e) {
    // Controlled failure — log and return result, don't throw
    log.warn("Payment declined for order {}: {}", order.id(), e.declineReason());
    return OrderResult.paymentDeclined(e.declineReason());
}

// CORRECT: domain exceptions carry context
public class OrderNotFoundException extends RuntimeException {
    private final OrderId orderId;
    
    public OrderNotFoundException(OrderId orderId) {
        super("Order not found: " + orderId);
        this.orderId = orderId;
    }
    
    public OrderId orderId() { return orderId; }
}
```

**Rule**: checked exceptions for recoverable conditions (Bloch Item 70); unchecked for programming errors; never swallow.

---

## Java Concurrency at Production Scale

### The Concurrency Hierarchy

```
Higher abstraction (prefer these):
  CompletableFuture / reactive streams → async non-blocking
  ExecutorService + Future            → thread pool management
  ConcurrentHashMap / CopyOnWriteArrayList → lock-free data structures
  Atomic* classes (AtomicLong, etc.)  → single-variable atomicity

Lower abstraction (use carefully):
  ReentrantLock / ReadWriteLock       → explicit locking
  synchronized                        → intrinsic lock
  volatile                            → visibility guarantee only (not atomicity)
  
Never use for new code:
  wait() / notify()                   → replaced by higher-level constructs
  Thread directly                     → use ExecutorService
```

### CompletableFuture Patterns

```java
// CORRECT: composing async operations without blocking
CompletableFuture<OrderConfirmation> confirm(Order order) {
    return CompletableFuture
        .supplyAsync(() -> inventory.reserve(order.lines()), ioExecutor)
        .thenComposeAsync(reservation -> 
            payment.authorise(order.total(), order.paymentToken()), ioExecutor)
        .thenApplyAsync(auth -> 
            OrderConfirmation.of(order.id(), auth.reference()), computeExecutor)
        .exceptionally(ex -> {
            log.error("Order confirmation failed for {}: {}", order.id(), ex.getMessage());
            throw new OrderConfirmationException(order.id(), ex);
        });
}

// CORRECT: fan-out and join
CompletableFuture<Void> notifyAll(OrderConfirmation confirmation) {
    CompletableFuture<Void> emailFuture = 
        CompletableFuture.runAsync(() -> email.send(confirmation), notificationExecutor);
    CompletableFuture<Void> pushFuture = 
        CompletableFuture.runAsync(() -> push.send(confirmation), notificationExecutor);
    
    return CompletableFuture.allOf(emailFuture, pushFuture);
}
```

### Thread Pool Configuration

```java
// CORRECT: separate thread pools by concern (bulkhead pattern)
@Configuration
public class ExecutorConfig {
    
    // IO-bound pool: threads = 2–4× CPU count
    @Bean("ioExecutor")
    public ExecutorService ioExecutor() {
        int threads = Runtime.getRuntime().availableProcessors() * 3;
        return new ThreadPoolExecutor(
            threads, threads,
            60L, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(1000),        // bounded queue
            new ThreadFactoryBuilder()
                .setNameFormat("io-worker-%d")
                .setDaemon(true)
                .build(),
            new ThreadPoolExecutor.CallerRunsPolicy() // backpressure: caller blocks
        );
    }
    
    // CPU-bound pool: threads = CPU count
    @Bean("computeExecutor")
    public ExecutorService computeExecutor() {
        int threads = Runtime.getRuntime().availableProcessors();
        return Executors.newFixedThreadPool(threads,
            new ThreadFactoryBuilder().setNameFormat("compute-%d").build());
    }
}
```

**Production rule**: always use bounded queues. Unbounded queues hide backpressure and cause OOM under load.

---

### Lock-Free Data Structures

```java
// CORRECT: ConcurrentHashMap for concurrent access
private final ConcurrentHashMap<OrderId, Order> orderCache = new ConcurrentHashMap<>();

// CORRECT: atomic update without locking
orderCache.computeIfAbsent(orderId, id -> loadFromDatabase(id));

// CORRECT: AtomicLong for counters without synchronization overhead
private final AtomicLong requestCount = new AtomicLong(0);
requestCount.incrementAndGet();

// CORRECT: compare-and-swap for optimistic updates
AtomicReference<State> state = new AtomicReference<>(State.INITIAL);
boolean transitioned = state.compareAndSet(State.INITIAL, State.PROCESSING);
```

---

## Memory Management and GC Tuning

### Avoiding Common Memory Leaks

```java
// WRONG: growing static collection (classic memory leak)
public class MetricsCollector {
    private static final List<Metric> ALL_METRICS = new ArrayList<>(); // Never cleared
    
    public void record(Metric m) { ALL_METRICS.add(m); } // OOM under load
}

// CORRECT: bounded collection or time-windowed
public class MetricsCollector {
    private final Queue<Metric> recentMetrics = new ArrayDeque<>();
    private static final int MAX_SIZE = 10_000;
    
    public void record(Metric m) {
        recentMetrics.offer(m);
        if (recentMetrics.size() > MAX_SIZE) recentMetrics.poll();
    }
}

// WRONG: non-static inner class holds implicit reference to outer
public class OrderProcessor {
    private List<Order> pendingOrders;
    
    class OrderTask implements Runnable { // Holds reference to OrderProcessor
        public void run() { ... }
    }
}

// CORRECT: static inner class or lambda
public class OrderProcessor {
    static class OrderTask implements Runnable { // No outer reference
        private final OrderProcessor processor;
        OrderTask(OrderProcessor p) { this.processor = p; }
        public void run() { ... }
    }
}
```

### JVM Flags for Production Services (G1GC)

```bash
# Standard production JVM flags for a large Java service (16GB heap)
-Xms8g -Xmx8g                           # Fixed heap size (no resizing overhead)
-XX:+UseG1GC                            # G1 for large heaps; ZGC for latency-sensitive
-XX:MaxGCPauseMillis=200                # Target pause goal (not a hard guarantee)
-XX:G1HeapRegionSize=16m               # Tune for large heap
-XX:+HeapDumpOnOutOfMemoryError         # Critical: always enable
-XX:HeapDumpPath=/var/log/app/heapdump.hprof
-XX:+ExitOnOutOfMemoryError             # Kill the JVM on OOM; let supervisor restart it
-XX:+PrintGCDetails -XX:+PrintGCDateStamps  # GC logging
-Xlog:gc*:file=/var/log/app/gc.log:time,uptime:filecount=5,filesize=20m
-XX:+UseStringDeduplication             # Reduce heap for string-heavy services
```

**ZGC (Java 15+) for latency-critical services**:
```bash
-XX:+UseZGC                             # Sub-millisecond GC pauses
-XX:SoftMaxHeapSize=28g                 # Soft limit; allows GC to use more if needed
-Xmx32g                                 # Hard limit
```

---

## API Design Principles

### Method Design

```java
// CORRECT: command-query separation — methods either return a value or have side effects, not both
public interface OrderService {
    void submitOrder(SubmitOrderCommand command);     // command: side effect, no return
    Order getOrder(OrderId id);                       // query: return value, no side effect
    
    // WRONG: returns value AND has side effects — confusing contract
    // Order submitAndReturnOrder(SubmitOrderCommand command);
}

// CORRECT: parameter validation at API boundary
public void submitOrder(SubmitOrderCommand command) {
    Objects.requireNonNull(command, "command must not be null");
    Objects.requireNonNull(command.orderId(), "orderId must not be null");
    if (command.lines().isEmpty())
        throw new IllegalArgumentException("Order must have at least one line");
    
    // Proceed with validated input
}
```

### Defensive Copies

```java
// WRONG: mutable list leaks; caller can modify Order's internal state
public final class Order {
    private final List<OrderLine> lines;
    
    public List<OrderLine> lines() { return lines; } // Leaked mutable reference
}

// CORRECT: defensive copy on read (or use Collections.unmodifiableList)
public final class Order {
    private final List<OrderLine> lines;
    
    public Order(List<OrderLine> lines) {
        this.lines = List.copyOf(lines); // Defensive copy on construction too
    }
    
    public List<OrderLine> lines() {
        return Collections.unmodifiableList(lines); // Or List.copyOf — depends on usage
    }
}
```

---

## Testing Standards

### Test Pyramid

```
           ┌──────────┐
           │    E2E   │  ← 5-10%; slow; test critical user journeys only
           ├──────────┤
           │Integration│ ← 20-30%; test repository, external service adapters
           ├──────────┤
           │   Unit    │ ← 60-70%; fast; test business logic in isolation
           └──────────┘
```

### Unit Test Standards

```java
@Test
void should_reject_order_submission_when_already_submitted() {
    // Arrange: descriptive names; Arrange-Act-Assert pattern
    Order order = OrderTestData.submittedOrder();
    
    // Act + Assert: test one behaviour
    assertThatThrownBy(() -> order.submit())
        .isInstanceOf(InvalidOrderStateException.class)
        .hasMessageContaining("SUBMITTED");
    
    // Verify: no additional state change
    assertThat(order.status()).isEqualTo(OrderStatus.SUBMITTED);
    assertThat(order.domainEvents()).isEmpty(); // No new events raised
}

@ParameterizedTest
@MethodSource("invalidAmounts")
void should_reject_money_with_negative_amount(BigDecimal invalidAmount) {
    assertThatThrownBy(() -> new Money(invalidAmount, Currency.USD))
        .isInstanceOf(IllegalArgumentException.class);
}

private static Stream<BigDecimal> invalidAmounts() {
    return Stream.of(
        BigDecimal.valueOf(-1),
        BigDecimal.valueOf(-0.01),
        BigDecimal.valueOf(-1000)
    );
}
```

**Test naming convention**: `should_[expected result]_when_[condition]` — test name is the specification.

### Test Data Builders

```java
// Test data builder — prevents test fragility when constructors change
public class OrderTestData {
    
    public static Order draftOrder() {
        return Order.builder(
            OrderId.of(UUID.randomUUID()),
            CustomerId.of(UUID.fromString("customer-1"))
        )
        .lines(List.of(OrderLineTestData.standardLine()))
        .build();
    }
    
    public static Order submittedOrder() {
        Order order = draftOrder();
        order.submit();
        return order;
    }
}
```

---

## Dependency Management (Maven/Gradle)

### Security Standards

```xml
<!-- Maven: always pin exact versions; no floating ranges in production -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
    <version>3.2.4</version> <!-- Exact, pinned -->
    <!-- Never: <version>[3.0,)</version> — allows any version → unpredictable builds -->
</dependency>
```

```groovy
// Gradle: dependency constraints for transitive security fixes
dependencies {
    constraints {
        // Override transitive dependency version for CVE fix
        implementation('com.fasterxml.jackson.core:jackson-databind:2.16.1') {
            because 'CVE-2022-42003: critical deserialization vulnerability in 2.13.x'
        }
    }
}
```

---

## Trade-offs

| Approach | Benefit | Cost | When to use |
|---|---|---|---|
| **Virtual Threads (Project Loom, Java 21)** | High concurrency without thread pool tuning; IO-bound code becomes simple blocking code | Pinning risk with synchronized blocks; still maturing | IO-heavy services: REST clients, database calls |
| **Reactive (WebFlux/Project Reactor)** | Non-blocking; excellent for high-concurrency IO | Steep learning curve; stack traces are unreadable; harder to debug | Very high concurrency (10k+ req/s per instance) |
| **Traditional blocking (Spring MVC)** | Simple mental model; readable stack traces; familiar | Thread-per-request limits concurrency at ~200-500 threads | Standard services with manageable concurrency |
| **Records for domain objects** | Less boilerplate; immutability enforced | Cannot extend; no custom serialisation by default | Value Objects, DTOs, configuration data |
| **Lombok** | Reduces boilerplate | Hidden generated code; annotation processor complexity; conflicts with Records | Legacy codebases; use sparingly, remove where Records suffice |

---

## FAANG Interview Points

**"What's the most important Java discipline for services at Google/Amazon scale?"**: Three things. First: immutability — mutable shared state is the root cause of most production concurrency bugs; defaulting to immutable value objects and thread-safe collections eliminates an entire class of race conditions. Second: proper exception handling — catching and swallowing exceptions is the number one cause of silent production failures; every exception should either be handled and logged with context, or propagated to a boundary handler. Third: bounded data structures — unbounded queues, caches, and collections are the root cause of most OOM incidents in production; every collection that grows under load must have a size limit.

**"How do you choose between CompletableFuture and reactive streams?"**: CompletableFuture for straightforward async composition — fan-out, sequential chaining, timeout handling. Reactive streams (Project Reactor / RxJava) for backpressure-aware pipelines where the producer can overwhelm the consumer. At FAANG, I'd first consider Java 21 Virtual Threads — they handle IO-bound concurrency with simple blocking code, eliminate the CompletableFuture callback chain complexity, and produce readable stack traces. Virtual Threads are the answer for most new services on Java 21+.

**"How do you find and fix memory leaks in a Java service?"**: Three-step process. First: identify the symptom — heap grows monotonically, GC frequency increases without memory release, eventually OOM. Second: capture a heap dump on OOM (`-XX:+HeapDumpOnOutOfMemoryError`) and analyse with Eclipse MAT or VisualVM — look for the top retained heap objects and trace the GC roots to find why they can't be collected. Third: the most common root causes I've seen in production: unbounded static collections, listener/callback registrations that are never deregistered, ThreadLocal variables not cleared after request completion, and connection pool leaks where connections are not returned.
