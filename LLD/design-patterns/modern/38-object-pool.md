# 38. Object Pool
**Category**: Modern / Enterprise  
**GoF**: No (Resource management pattern)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Pre-allocate a pool of reusable, expensive-to-create objects. Clients borrow an object from the pool, use it, and return it — avoiding the creation/teardown cost on every request.

---

## Problem It Solves

Creating a database connection takes 20–100ms (TCP handshake, TLS, auth, protocol negotiation). An e-commerce service handling 10,000 requests/second cannot afford to open a new DB connection per request. Without pooling: 10K connections opened per second, exhausting DB `max_connections` (~500–2000 on Postgres); TCP FIN/RST storms; 100ms per-request overhead. With connection pooling: 20–100 persistent connections shared across 10K requests; connections borrowed in <0.5ms; DB load manageable.

Object Pool applies the same principle to any expensive-to-create resource: DB connections, thread pools, HTTP client connections, cryptographic cipher instances, PDF renderers, GPU handles.

## Structure (Participants)

```
  Client
    │ acquire()                    release()
    ▼                                  │
 ObjectPool ◄──────────────────────────┘
 ┌─────────────────────────────────────┐
 │  idle: [conn1, conn2, conn3]        │
 │  busy: [conn4, conn5]               │
 │  min=5  max=20                      │
 │  waitQueue (blocked acquires)       │
 └─────────────────────────────────────┘
         │
         │ creates / validates / destroys
         ▼
  PooledObjectFactory
```

Key participants:
- **ObjectPool**: manages idle/busy partitions; enforces min/max size; evicts stale objects
- **PooledObjectFactory**: creates, validates, and destroys pooled objects
- **PooledObject**: wrapper tracking borrow time, last-use timestamp, health state
- **Client**: acquires from pool; uses object; releases back (ideally via try-with-resources)

---

## Real-World Use Case: Database Connection Pool

PostgreSQL `max_connections = 500`. Microservice with 200 instances. Without pooling each instance could attempt 50 connections = 10,000 → impossible. With HikariCP (`maxPoolSize=10`): 200 × 10 = 2,000 app-side connections → still high. Production answer: add PgBouncer at transaction-mode pooling with 100 server-side connections shared across all app instances.

### Implementation

```java
// Wrapper tracking pool lifecycle metadata
public class PooledConnection {
    private final Connection connection;
    private volatile long borrowedAt;
    private volatile long lastUsedAt;
    private volatile boolean inUse;

    public PooledConnection(Connection connection) {
        this.connection = connection;
        this.lastUsedAt = System.currentTimeMillis();
    }

    public Connection get()          { return connection; }
    public boolean isInUse()         { return inUse; }
    public long idleTimeMs()         { return System.currentTimeMillis() - lastUsedAt; }

    public void markBorrowed() {
        inUse = true;
        borrowedAt = System.currentTimeMillis();
    }

    public void markReturned() {
        inUse = false;
        lastUsedAt = System.currentTimeMillis();
    }

    public boolean isHealthy() {
        try { return !connection.isClosed() && connection.isValid(1); }
        catch (SQLException e) { return false; }
    }
}

// Pool configuration
public record PoolConfig(
    String jdbcUrl,
    String username,
    String password,
    int    minIdle,               // maintain at least this many idle connections
    int    maxSize,               // hard cap on total connections
    long   connectionTimeoutMs,   // max wait when pool is exhausted
    long   idleTimeoutMs,         // evict connections idle longer than this
    long   maxLifetimeMs,         // rotate connections older than this
    long   keepaliveIntervalMs    // heartbeat interval for idle connections
) {}

// Thread-safe connection pool
public class ConnectionPool implements AutoCloseable {
    private final PoolConfig config;
    private final LinkedBlockingDeque<PooledConnection> idle  = new LinkedBlockingDeque<>();
    private final Set<PooledConnection>                  busy = ConcurrentHashMap.newKeySet();
    private final AtomicInteger totalConnections = new AtomicInteger(0);
    private final ReentrantLock  lock     = new ReentrantLock();
    private final Condition      notEmpty = lock.newCondition();
    private final ScheduledExecutorService maintenance;
    private volatile boolean closed = false;

    public ConnectionPool(PoolConfig config) throws SQLException {
        this.config = config;
        this.maintenance = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "pool-maintenance");
            t.setDaemon(true);
            return t;
        });
        // Pre-warm minimum idle connections
        for (int i = 0; i < config.minIdle(); i++) {
            idle.add(createConnection());
        }
        maintenance.scheduleAtFixedRate(this::runMaintenance,
            config.keepaliveIntervalMs(), config.keepaliveIntervalMs(), TimeUnit.MILLISECONDS);
    }

    // Borrow a connection — blocks until available or timeout
    public PooledConnection acquire() throws SQLException, InterruptedException {
        if (closed) throw new IllegalStateException("Pool is closed");
        long deadline = System.currentTimeMillis() + config.connectionTimeoutMs();

        while (true) {
            // 1. Try idle queue first (non-blocking)
            PooledConnection conn = idle.poll();
            if (conn != null) {
                if (conn.isHealthy()) {
                    conn.markBorrowed();
                    busy.add(conn);
                    return conn;
                }
                // Discard unhealthy; replace it
                destroyConnection(conn);
                conn = createConnection();
                conn.markBorrowed();
                busy.add(conn);
                return conn;
            }

            // 2. Create new connection if under maxSize
            lock.lock();
            try {
                if (totalConnections.get() < config.maxSize()) {
                    conn = createConnection();
                    conn.markBorrowed();
                    busy.add(conn);
                    return conn;
                }
                // 3. Pool exhausted — wait for a release signal
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) {
                    throw new SQLException(String.format(
                        "Connection pool exhausted after %dms (total=%d, busy=%d)",
                        config.connectionTimeoutMs(), totalConnections.get(), busy.size()));
                }
                notEmpty.await(remaining, TimeUnit.MILLISECONDS);
            } finally {
                lock.unlock();
            }
        }
    }

    // Return a connection to the pool
    public void release(PooledConnection conn) {
        if (conn == null) return;
        busy.remove(conn);
        conn.markReturned();

        if (!conn.isHealthy() || conn.idleTimeMs() > config.maxLifetimeMs()) {
            destroyConnection(conn);
            tryReplenish();
        } else {
            idle.addFirst(conn);   // MRU ordering — recently-used connections stay warm
            lock.lock();
            try { notEmpty.signal(); } finally { lock.unlock(); }
        }
    }

    // Auto-closeable handle for try-with-resources
    public PooledConnectionHandle acquireHandle() throws SQLException, InterruptedException {
        return new PooledConnectionHandle(this, acquire());
    }

    private PooledConnection createConnection() throws SQLException {
        Connection raw = DriverManager.getConnection(
            config.jdbcUrl(), config.username(), config.password());
        totalConnections.incrementAndGet();
        return new PooledConnection(raw);
    }

    private void destroyConnection(PooledConnection conn) {
        try { conn.get().close(); } catch (SQLException ignored) {}
        totalConnections.decrementAndGet();
    }

    private void tryReplenish() {
        int deficit = config.minIdle() - idle.size();
        for (int i = 0; i < deficit && totalConnections.get() < config.maxSize(); i++) {
            try { idle.addLast(createConnection()); }
            catch (SQLException e) { log.error("Failed to replenish connection", e); }
        }
    }

    private void runMaintenance() {
        // Evict connections idle beyond idleTimeoutMs (keeping at least minIdle)
        idle.removeIf(conn -> {
            if (conn.idleTimeMs() > config.idleTimeoutMs() && idle.size() > config.minIdle()) {
                destroyConnection(conn);
                return true;
            }
            return false;
        });
        // Validate remaining idle connections (keepalive — sends SELECT 1)
        idle.forEach(conn -> {
            if (!conn.isHealthy()) { idle.remove(conn); destroyConnection(conn); }
        });
        tryReplenish();
    }

    @Override
    public void close() {
        closed = true;
        maintenance.shutdown();
        idle.forEach(this::destroyConnection);
        busy.forEach(c -> log.warn("Connection leaked during pool shutdown: {}", c));
        idle.clear();
    }
}

// Auto-closeable wrapper — guarantees release even on exception
public class PooledConnectionHandle implements AutoCloseable {
    private final ConnectionPool     pool;
    private final PooledConnection   conn;

    public PooledConnectionHandle(ConnectionPool pool, PooledConnection conn) {
        this.pool = pool;
        this.conn = conn;
    }

    public Connection get() { return conn.get(); }

    @Override public void close() { pool.release(conn); }
}

// Caller — zero manual release needed
public class UserRepository {
    private final ConnectionPool pool;

    public User findById(long userId) throws Exception {
        try (PooledConnectionHandle h = pool.acquireHandle()) {
            try (PreparedStatement ps = h.get().prepareStatement(
                    "SELECT * FROM users WHERE id = ?")) {
                ps.setLong(1, userId);
                return mapUser(ps.executeQuery());
            }
        }
    }
}
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Idle queue structure | `LinkedBlockingDeque` with front-insert on return | MRU ordering — recently returned connections are warm (TCP state, prepared statement cache) |
| Wait strategy | Timed condition variable | Threads sleep until notified; no CPU spin; deadline enforced precisely |
| Validation timing | Lazy — on borrow and on maintenance cycle | Avoids blocking the hot path with network round-trips; failures caught at first reuse |
| Return handling | Auto-closeable `PooledConnectionHandle` | Eliminates connection leaks — connection always returned even on exception |
| Maintenance | Daemon background thread | Amortizes eviction and keepalive cost; does not penalize request latency |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `ConnectionPool` manages lifecycle; `PooledConnection` tracks state; handle manages auto-return |
| Open/Closed | ✅ | Extract `PooledObjectFactory<T>` to pool threads, HTTP clients, or GPU handles without changing pool logic |
| Liskov Substitution | ✅ | `PooledConnectionHandle.get()` returns a real `Connection` — transparent to callers |
| Interface Segregation | ✅ | Pool exposes `acquire/release`; handle exposes only `get/close` |
| Dependency Inversion | ✅ | `UserRepository` depends on `ConnectionPool` abstraction, not `DriverManager` directly |

---

## When to Use

- Object creation is expensive: 10ms+ (DB connection, TLS handshake, socket, GPU context)
- Objects are stateless between uses, or state can be fully reset on return
- Concurrency is high and creating one object per request would exhaust the underlying resource
- The resource is finite and shared: DB `max_connections`, thread count, GPU handles

## When NOT to Use

- Object creation is cheap (< 1ms): pool overhead exceeds the benefit
- Objects carry irrecoverable per-request state that cannot be reset
- The resource is unlimited or has no per-connection overhead (in-memory value objects)

---

## Production Tuning

| Parameter | Rule of Thumb | Reasoning |
|-----------|--------------|-----------|
| `maxSize` | `(core_count × 2) + effective_spindle_count` | HikariCP formula — avoids context-switch overhead from threads competing for DB |
| `minIdle` | 25–50% of `maxSize` | Keep warm connections ready; avoid cold-start penalty under moderate load |
| `connectionTimeout` | 30s default; 1–5s for user-facing paths | SLA-driven; 30s is acceptable for background batch jobs |
| `idleTimeout` | 600s (10 min) | DB firewalls and NAT gateways kill idle TCP after ~15 min; evict before they silently break |
| `maxLifetime` | 1800s (30 min) | Rotate before DB `wait_timeout`; also rotates around memory leaks in JDBC drivers |
| `keepaliveInterval` | 60s | Lightweight `SELECT 1` prevents firewall timeout on idle connections |

## Trade-offs

| Benefit | Cost |
|---------|------|
| 100–300× reduction in connection acquisition latency | Pool exhaustion: misconfigured `maxSize` causes request queuing and cascading timeout |
| Caps total DB connections — prevents DB overload | Connection leaks: borrowed objects never returned starve the pool over time |
| Warm TCP connections — avoids TCP slow start on every query | Stale connections: DB restarts or firewall resets silently invalidate pooled connections |
| Stable `pg_stat_activity` connection count | Maintenance complexity: keepalive tuning, health-check timeouts, eviction thresholds |

---

**FAANG interview application**: "For any DB-backed service, connection pooling is non-negotiable. At 10K RPS across 200 pods with `maxPoolSize=10`, you have 2,000 app-side connections — already pushing Postgres `max_connections`. Production answer: add PgBouncer in transaction mode, where 10,000 app connections multiplex through 100–200 server-side connections. Critical tuning knobs: `maxLifetime=1800s` (rotate before firewall kills idle connections), `connectionTimeout=5s` for user-facing paths (fail fast rather than queue), and `keepaliveIntervalMs=60s` (prevent NAT gateway stale-connection drops). Leaked connections (not returned to pool) are the most common production failure — always use try-with-resources or equivalent RAII."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Singleton](../creational/01-singleton.md) | Pool is typically a singleton — one shared pool per data source per process |
| [Flyweight](../structural/11-flyweight.md) | Both share expensive objects; Flyweight is read-only immutable shared state; Pool manages mutable, reusable objects with exclusive access |
| [Proxy](../structural/12-proxy.md) | `PooledConnectionHandle` is a proxy — intercepts `close()` to return to pool instead of destroying |
| [Factory Method](../creational/02-factory-method.md) | `createConnection()` is a factory method — pool is decoupled from how objects are created |
| [Bulkhead](33-bulkhead.md) | Pool IS the bulkhead mechanism — limits concurrent resource use per dependency |
