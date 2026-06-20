# 01. Singleton
**Category**: Creational  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Ensure a class has only one instance and provide a global access point to it.

---

## Problem It Solves

Some resources must be shared across the entire application — a database connection pool, a configuration service, a metrics registry, or a feature-flag client. Creating multiple instances wastes resources, causes inconsistent state, and introduces subtle race conditions. Singleton ensures a single, shared, thread-safe instance.

## Structure (Participants)

```
┌──────────────────────────────────────────────┐
│                  Singleton                   │
│──────────────────────────────────────────────│
│ - instance: Singleton  (static, volatile)    │
│ - connectionPool: List<Connection>           │
│──────────────────────────────────────────────│
│ - Singleton()          (private constructor) │
│ + getInstance(): Singleton  (static)         │
│ + getConnection(): Connection                │
│ + releaseConnection(c: Connection): void     │
└──────────────────────────────────────────────┘
```

Key participants:
- **Singleton**: holds the static `instance` and private constructor; exposes `getInstance()`
- **Client**: calls `Singleton.getInstance()` — never calls `new Singleton()`

---

## Real-World Use Case: Database Connection Pool

A microservice handles 10K requests/second. Each request needs a database connection. Creating a new `Connection` per request costs 50–200ms (TCP handshake + auth). A connection pool pre-creates N connections and leases them — but there must be **exactly one pool** per service instance, shared across all threads.

### The Design

`DatabaseConnectionPool` is a Singleton. The pool is initialized once at startup with `minConnections=10, maxConnections=100`. All service threads call `DatabaseConnectionPool.getInstance().getConnection()`.

A second real-world Singleton in the same codebase: `FeatureFlagClient` — wraps LaunchDarkly SDK, initialized once with API key, and queried by every feature gate in the application.

### Implementation

```java
public class DatabaseConnectionPool {

    // volatile: ensures visibility across threads after write
    private static volatile DatabaseConnectionPool instance;

    private final List<Connection> availableConnections;
    private final List<Connection> usedConnections;
    private final int maxSize;

    // Private constructor — prevents external instantiation
    private DatabaseConnectionPool(String jdbcUrl, int minSize, int maxSize) {
        this.maxSize = maxSize;
        this.availableConnections = new ArrayList<>();
        this.usedConnections = new ArrayList<>();
        for (int i = 0; i < minSize; i++) {
            availableConnections.add(createConnection(jdbcUrl));
        }
    }

    // Double-checked locking — thread-safe, lazy initialization
    public static DatabaseConnectionPool getInstance() {
        if (instance == null) {                         // First check (no lock)
            synchronized (DatabaseConnectionPool.class) {
                if (instance == null) {                 // Second check (with lock)
                    String url = Config.get("db.url");
                    instance = new DatabaseConnectionPool(url, 10, 100);
                }
            }
        }
        return instance;
    }

    public synchronized Connection getConnection() {
        if (availableConnections.isEmpty()) {
            if (usedConnections.size() < maxSize) {
                availableConnections.add(createConnection(Config.get("db.url")));
            } else {
                throw new RuntimeException("Connection pool exhausted");
            }
        }
        Connection conn = availableConnections.remove(availableConnections.size() - 1);
        usedConnections.add(conn);
        return conn;
    }

    public synchronized void releaseConnection(Connection conn) {
        usedConnections.remove(conn);
        availableConnections.add(conn);
    }

    private Connection createConnection(String url) {
        return DriverManager.getConnection(url); // actual JDBC call
    }
}

// Client usage
public class OrderRepository {
    public Order findById(String orderId) {
        Connection conn = DatabaseConnectionPool.getInstance().getConnection();
        try {
            // execute query
        } finally {
            DatabaseConnectionPool.getInstance().releaseConnection(conn);
        }
    }
}
```

### How It Works (walkthrough)

1. Thread A calls `getInstance()` — `instance == null`, acquires lock, creates pool, releases lock
2. Thread B calls `getInstance()` — `instance != null` (first check passes), returns existing pool
3. Thread C calls `getInstance()` during Thread A's initialization — blocked at `synchronized`, then sees non-null instance on second check, returns it
4. All threads share the same pool; `getConnection()` / `releaseConnection()` are `synchronized` for thread safety

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ⚠️ | Singleton manages both its own lifecycle AND pool logic — often better to separate |
| Open/Closed | ❌ | Hard to extend; subclassing a Singleton is problematic |
| Liskov Substitution | ❌ | Cannot substitute a different implementation without changing `getInstance()` |
| Interface Segregation | ✅ | Pool interface can be kept narrow |
| Dependency Inversion | ⚠️ | Callers depend on the concrete Singleton, not an interface — makes testing hard |

**Mitigation**: Expose the Singleton via an interface (`ConnectionPool`); inject it via DI framework (Spring `@Bean(scope=singleton)`). This recovers DIP and LSP.

---

## When to Use

- Exactly one instance is needed: shared connection pool, metrics registry, config service, logger, thread pool executor
- The instance is expensive to create and must be reused
- Global state is genuinely required (not just convenient)

## When NOT to Use

- When "global access" is just laziness — prefer dependency injection
- When you need multiple configurations (e.g., two different DB pools) — Singleton becomes a liability
- In unit tests — Singleton state leaks between tests; use DI + mock instead
- When the class has mutable shared state beyond a pool — prefer stateless services

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Single shared resource — no duplicate pools | Hard to unit test without DI framework |
| Lazy initialization — created only when first needed | Global state — hidden dependency in call sites |
| Thread-safe with double-checked locking | Violates DIP — callers depend on concrete class |
| Widely understood pattern | Considered an anti-pattern in DI-heavy codebases |

---

**FAANG interview application**: "I'd implement the connection pool as a Singleton using double-checked locking with a `volatile` field to ensure visibility. In a Spring application I'd just annotate the `@Bean` as `@Scope("singleton")` — the framework handles the thread safety. The key tradeoff is testability: if callers take the pool by interface via constructor injection, I can swap a mock pool in tests without touching the Singleton itself."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Factory Method](02-factory-method.md) | Factory is often a Singleton — one factory, many products |
| [Abstract Factory](03-abstract-factory.md) | Abstract Factory is usually implemented as a Singleton |
| [Flyweight](../structural/11-flyweight.md) | Flyweight factory is a Singleton that manages the shared flyweight pool |
| [Facade](../structural/10-facade.md) | Facade objects are often Singletons — one entry point to a subsystem |
