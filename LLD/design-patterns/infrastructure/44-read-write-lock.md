# 44. Read-Write Lock
**Category**: Infrastructure / Concurrency  
**GoF**: No (Concurrency Patterns)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Allow any number of concurrent readers **or** a single exclusive writer — never both simultaneously — maximising throughput for read-heavy workloads while guaranteeing consistency for writes.

---

## Problem It Solves

A product catalog has 10,000 reads/second and 10 writes/second. Using a plain `synchronized` (exclusive lock for all operations): 10,000 readers block each other unnecessarily — throughput collapses to one operation at a time. Using no lock: concurrent readers during a write may observe a torn (partially updated) object — data corruption. Read-Write Lock solves this by distinguishing the access pattern: readers share access freely; a writer gets exclusive access. At 10K reads / 10 writes per second, a RW lock delivers ~1,000× more throughput than a mutex for this workload.

## Structure (Participants)

```
  Thread-1 (reader) ─────────────► acquire read lock ──► read ──► release
  Thread-2 (reader) ─────────────► acquire read lock ──► read ──► release
  Thread-3 (reader) ─────────────► acquire read lock ──► read ──► release

  Thread-4 (writer) ─────────────► acquire WRITE lock (blocks until all readers done)
                                        │
                                   exclusive access ──► write ──► release
                                        │
  Thread-5 (reader) waits ─────────────┘
```

Invariants:
- Multiple readers can hold the lock simultaneously (shared mode)
- A writer must wait for ALL active readers to finish
- No new readers may enter while a writer is waiting (prevents writer starvation)
- Once a writer holds the lock, all readers block

Key participants:
- **ReadLock**: shareable — many threads can hold it concurrently
- **WriteLock**: exclusive — at most one thread holds it at a time
- **Lock State**: tracks active reader count and whether a writer is waiting or active
- **Condition Variables**: readers wait when a writer is active; writer waits for active reader count to reach 0

---

## Real-World Use Case: Product Catalog In-Memory Cache

A JVM in-memory catalog caches 50,000 product records. Cache invalidation happens every 5 minutes (write). Reads happen 10,000/second. Using `java.util.concurrent.locks.ReentrantReadWriteLock` is the standard answer. For custom interview demonstrations, implement from scratch.

### Implementation: Standard JVM Usage

```java
// Using Java's built-in ReentrantReadWriteLock
public class ProductCatalog {
    private final ReentrantReadWriteLock rwLock = new ReentrantReadWriteLock(
        true  // fair=true: writer will not starve behind a stream of readers
    );
    private final Lock readLock  = rwLock.readLock();
    private final Lock writeLock = rwLock.writeLock();

    private final Map<String, Product> catalog = new HashMap<>();

    // Multiple threads can read simultaneously
    public Product findById(String productId) {
        readLock.lock();
        try {
            return catalog.get(productId);
        } finally {
            readLock.unlock();
        }
    }

    public List<Product> findByCategory(String category) {
        readLock.lock();
        try {
            return catalog.values().stream()
                .filter(p -> p.category().equals(category))
                .collect(Collectors.toList());
        } finally {
            readLock.unlock();
        }
    }

    // Only one thread can write at a time; blocks all readers
    public void updateProduct(Product product) {
        writeLock.lock();
        try {
            catalog.put(product.id(), product);
        } finally {
            writeLock.unlock();
        }
    }

    public void bulkRefresh(Map<String, Product> newCatalog) {
        writeLock.lock();
        try {
            catalog.clear();
            catalog.putAll(newCatalog);
        } finally {
            writeLock.unlock();
        }
    }

    // Lock downgrade: write → read (allowed; opposite is not)
    public Product updateAndRead(Product product) {
        writeLock.lock();
        try {
            catalog.put(product.id(), product);
            readLock.lock();   // acquire read lock while holding write lock
        } finally {
            writeLock.unlock();  // release write lock, keeping read lock
        }
        try {
            return catalog.get(product.id());  // now in read mode
        } finally {
            readLock.unlock();
        }
    }
}
```

### Implementation: From Scratch (Interview Version)

```java
// Manual read-write lock — demonstrates the mechanics clearly
public class ReadWriteLock {
    private int  activeReaders  = 0;   // number of threads currently reading
    private int  waitingWriters = 0;   // number of threads waiting to write
    private boolean writerActive = false;

    // ─── Read lock ─────────────────────────────────────────────────────────
    public synchronized void acquireRead() throws InterruptedException {
        // Block if a writer is active OR waiting (prevents writer starvation)
        while (writerActive || waitingWriters > 0) {
            wait();
        }
        activeReaders++;
    }

    public synchronized void releaseRead() {
        activeReaders--;
        if (activeReaders == 0) {
            // Last reader done — wake waiting writers
            notifyAll();
        }
    }

    // ─── Write lock ────────────────────────────────────────────────────────
    public synchronized void acquireWrite() throws InterruptedException {
        waitingWriters++;
        try {
            // Block until no readers and no active writer
            while (activeReaders > 0 || writerActive) {
                wait();
            }
        } finally {
            waitingWriters--;
        }
        writerActive = true;
    }

    public synchronized void releaseWrite() {
        writerActive = false;
        notifyAll();  // wake both waiting readers and waiting writers
    }
}

// Usage with try-finally discipline
public class SafeCatalog {
    private final ReadWriteLock lock    = new ReadWriteLock();
    private final Map<String, Product>  data = new HashMap<>();

    public Product get(String id) throws InterruptedException {
        lock.acquireRead();
        try { return data.get(id); }
        finally { lock.releaseRead(); }
    }

    public void put(Product p) throws InterruptedException {
        lock.acquireWrite();
        try { data.put(p.id(), p); }
        finally { lock.releaseWrite(); }
    }
}
```

### Distributed Read-Write Lock (Redis)

For cross-process locking — e.g., preventing concurrent catalog refreshes across pods while allowing all pods to read freely.

```java
// Redis Lua for distributed write lock (shared write side only — reads are uncontrolled at Redis level)
// For distributed RW semantics, use Redisson's ReadWriteLock

import org.redisson.Redisson;
import org.redisson.api.RReadWriteLock;

public class DistributedProductCatalog {
    private final RReadWriteLock rwLock;

    public DistributedProductCatalog(RedissonClient redisson) {
        // Redisson distributed RW lock — backed by Redis Lua scripts
        this.rwLock = redisson.getReadWriteLock("catalog:lock");
    }

    public Product findById(String productId) {
        rwLock.readLock().lock();
        try {
            return loadFromCache(productId);
        } finally {
            rwLock.readLock().unlock();
        }
    }

    public void refreshCatalog(Map<String, Product> newData) {
        rwLock.writeLock().lock();
        try {
            rebuildCache(newData);
        } finally {
            rwLock.writeLock().unlock();
        }
    }
}
```

### StampedLock: Optimistic Reads (Java 8+)

For extreme read-heavy scenarios where even a shared lock acquisition is a bottleneck:

```java
public class OptimisticCatalog {
    private final StampedLock stampedLock = new StampedLock();
    private Map<String, Product> catalog = new HashMap<>();

    public Product findById(String productId) {
        // 1. Attempt optimistic read — no lock acquisition, just a version stamp
        long stamp = stampedLock.tryOptimisticRead();
        Product result = catalog.get(productId);

        // 2. Validate: if a write happened between tryOptimisticRead and now, stamp is invalid
        if (!stampedLock.validate(stamp)) {
            // Fallback to a full shared read lock
            stamp = stampedLock.readLock();
            try {
                result = catalog.get(productId);
            } finally {
                stampedLock.unlockRead(stamp);
            }
        }
        return result;  // safe even without a lock if stamp was valid
    }

    public void updateProduct(Product product) {
        long stamp = stampedLock.writeLock();
        try {
            catalog.put(product.id(), product);
        } finally {
            stampedLock.unlockWrite(stamp);
        }
    }
}
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `ReadWriteLock` manages only locking state; `ProductCatalog` manages data |
| Open/Closed | ✅ | Swap `ReentrantReadWriteLock` for `StampedLock` or distributed lock without changing catalog logic |
| Liskov Substitution | ✅ | `StampedLock`, `ReentrantReadWriteLock`, and `ReadWriteLock` are interchangeable for RW semantics |
| Interface Segregation | ✅ | `readLock()` and `writeLock()` provide minimally sufficient interfaces for each access mode |
| Dependency Inversion | ✅ | `ProductCatalog` holds a `Lock` interface reference, not a concrete lock type |

---

## When to Use

- Read operations significantly outnumber writes (read-heavy ratio: > 80% reads)
- Read operations are long enough that blocking them is costly (data transformation, large scans)
- Data consistency requires that readers never see a partially written object
- In-memory caches that are refreshed periodically but read continuously

## When NOT to Use

- Write frequency is similar to read frequency — RW lock overhead exceeds benefit
- Lock hold time is very short (< 100µs) — plain `synchronized` or `AtomicReference` is faster
- Operations are naturally compare-and-swap (increment, conditional set) — use `Atomic*` classes
- Strict ordering is needed (no concurrent reads during any write) — use a mutex

---

## Comparison: When to Use Each Lock Type

| Scenario | Use |
|----------|-----|
| 95% reads, 5% writes, complex object | `ReentrantReadWriteLock` |
| 99%+ reads, very low contention | `StampedLock` with optimistic reads |
| Simple atomic increment/flag | `AtomicInteger` / `AtomicReference` |
| Immutable updates (replace whole object) | `AtomicReference.compareAndSet()` |
| Short critical section, all access patterns | `synchronized` |
| Cross-process distributed RW | Redisson `RReadWriteLock` |

## Trade-offs

| Benefit | Cost |
|---------|------|
| Massive throughput improvement for read-heavy workloads | Writer starvation (without fairness flag): a flood of readers can indefinitely block writers |
| Readers don't block each other — true parallelism | Lock downgrade (write → read) is safe; lock upgrade (read → write) is NOT — causes deadlock |
| Fair mode prevents starvation at the cost of some throughput | More complex than mutex: two lock objects, two release paths — easier to leak |
| `StampedLock` optimistic reads: reads without lock acquisition | `StampedLock` is NOT reentrant — calling `readLock()` from a thread already holding `writeLock()` deadlocks |

---

**FAANG interview application**: "Read-Write Lock is the answer whenever you have a heavily-read, occasionally-written shared data structure — in-memory caches, configuration stores, route tables, session maps. Java's `ReentrantReadWriteLock(fair=true)` is the standard implementation — `fair=true` prevents writer starvation by queuing requests in arrival order. For extreme read throughput (near-zero writes), use `StampedLock` with optimistic reads: `tryOptimisticRead()` returns a stamp without any lock acquisition — it's just a version counter check. The main gotcha: never upgrade from read lock to write lock (deadlock). Always acquire write lock before needing exclusive access."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Object Pool](../modern/38-object-pool.md) | Pool's `idle`/`busy` queues use `ReentrantLock` + `Condition` rather than RW lock — pool state is always mutated on acquire/release so a shared read lock doesn't help |
| [Leader Election](43-leader-election.md) | Leader election acquires an exclusive write-like lock across a distributed cluster; RW lock operates within a single process |
| [Proxy](../structural/12-proxy.md) | A read-write cache proxy (read: return cached value; write: invalidate + delegate) is implemented with a RW lock |
| [Flyweight](../structural/11-flyweight.md) | Flyweight's shared intrinsic state is read-only — no locking required; if the shared state can be updated, RW lock protects it |
