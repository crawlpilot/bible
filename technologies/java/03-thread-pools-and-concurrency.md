# 03 — Thread Pools, Concurrency, and Virtual Threads

## Why Thread Pools Matter for Principal Engineers

Thread pools are the execution backbone of every Java service. Misconfigured pools are responsible for: request queue buildups, thread starvation deadlocks, cascading service failures from a single slow dependency, and OOM from unbounded queues. Understanding `ThreadPoolExecutor` internals is essential for diagnosing and designing concurrent systems.

---

## ThreadPoolExecutor — The Foundation

All high-level executors (`Executors.newFixedThreadPool`, `newCachedThreadPool`, Spring's `ThreadPoolTaskExecutor`) are wrappers around `ThreadPoolExecutor`. Understanding the raw constructor is essential.

```java
new ThreadPoolExecutor(
    int corePoolSize,           // threads kept alive even when idle
    int maximumPoolSize,        // max threads allowed
    long keepAliveTime,         // how long idle threads above corePoolSize live
    TimeUnit unit,
    BlockingQueue<Runnable> workQueue,   // queue for tasks when all core threads busy
    ThreadFactory threadFactory,         // customize thread name, daemon status
    RejectedExecutionHandler handler     // what to do when queue full + maxPoolSize reached
);
```

### Thread lifecycle — the non-obvious rules

```
When a task arrives:
  1. If active threads < corePoolSize → create new thread immediately (even if idle threads exist)
  2. If active threads >= corePoolSize AND queue not full → enqueue task
  3. If queue full AND active threads < maximumPoolSize → create new thread
  4. If queue full AND active threads == maximumPoolSize → REJECTED

Key insight: new threads above corePoolSize are ONLY created when the queue is full.
A SynchronousQueue (no buffer) forces thread creation on every task if all threads busy.
```

### Queue types and their trade-offs

```java
// 1. LinkedBlockingQueue — unbounded (default for Executors.newFixedThreadPool)
new LinkedBlockingQueue<>()
// ✅ Never rejects tasks
// ❌ Queue grows unboundedly → OOM under sustained overload
// ❌ maximumPoolSize is never reached (queue never "full")
// Use: batch processors, acceptable to queue indefinitely

// 2. LinkedBlockingQueue — bounded (PRODUCTION RECOMMENDATION)
new LinkedBlockingQueue<>(1000)
// ✅ Bounded memory usage
// ✅ Allows maximumPoolSize to be used (threads created when queue full)
// ❌ Rejects tasks when full + maxPoolSize reached
// Use: HTTP handlers, service workers — hard upper bound on queued work

// 3. SynchronousQueue — no buffer (default for Executors.newCachedThreadPool)
new SynchronousQueue<>()
// ✅ Creates threads immediately without queuing
// ❌ maximumPoolSize=Integer.MAX_VALUE → unlimited threads → OOM
// Use: short-lived async tasks, caching layer. Set explicit maximumPoolSize.

// 4. ArrayBlockingQueue — bounded with fairness option
new ArrayBlockingQueue<>(500, true)  // fair=true: FIFO ordering under contention
// ✅ Predictable ordering under overload
// ❌ Fair mode reduces throughput (requires lock on every enqueue/dequeue)

// 5. PriorityBlockingQueue — ordered by priority
new PriorityBlockingQueue<>()
// ✅ High-priority tasks processed first
// ❌ Unbounded (same OOM risk as LinkedBlockingQueue())
// Use: task prioritization (premium vs free tier requests)
```

### Rejection policies

```java
// 1. AbortPolicy (default) — throws RejectedExecutionException
// Use: caller handles rejection (circuit break, return 429)

// 2. CallerRunsPolicy — task runs in the calling thread
// Use: natural backpressure — slows down producer when pool saturated
// ⚠️ Danger: if calling thread is a Netty/Tomcat I/O thread, you block the I/O layer

// 3. DiscardPolicy — silently drops the task
// Use: fire-and-forget metrics, analytics where some loss is acceptable

// 4. DiscardOldestPolicy — drops the oldest queued task
// Use: real-time data where fresh data is more valuable than old data

// 5. Custom — submit to a secondary pool, write to DLQ, log + alert
executor.setRejectedExecutionHandler((runnable, pool) -> {
    metrics.counter("pool.rejected").increment();
    dlqWriter.send(runnable);  // preserve for replay
    throw new ServiceOverloadException("Request pool saturated");
});
```

### Production-grade ThreadPoolExecutor

```java
public class ServiceThreadPool {
    private final ThreadPoolExecutor executor;

    public ServiceThreadPool(String name, int coreSize, int maxSize, int queueCapacity) {
        this.executor = new ThreadPoolExecutor(
            coreSize,
            maxSize,
            60L, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(queueCapacity),
            new ThreadFactory() {
                private final AtomicInteger count = new AtomicInteger(0);
                public Thread newThread(Runnable r) {
                    Thread t = new Thread(r, name + "-worker-" + count.incrementAndGet());
                    t.setDaemon(true);  // don't prevent JVM shutdown
                    return t;
                }
            },
            (r, pool) -> {
                metrics.counter("threadpool.rejected", "pool", name).increment();
                throw new RejectedExecutionException(name + " pool saturated");
            }
        );
        // Allow core threads to time out too (prevents idle core threads in low-traffic windows)
        executor.allowCoreThreadTimeOut(true);
    }

    // Expose metrics for monitoring
    public void recordMetrics() {
        metrics.gauge("threadpool.active",    executor.getActiveCount());
        metrics.gauge("threadpool.queue",     executor.getQueue().size());
        metrics.gauge("threadpool.completed", executor.getCompletedTaskCount());
        metrics.gauge("threadpool.pool.size", executor.getPoolSize());
    }
}
```

---

## Sizing Thread Pools — Little's Law

**Little's Law**: `N = λ × W`  
Where: N = average items in system, λ = arrival rate, W = average time in system

For thread pool sizing:
```
threads_needed = requests_per_second × avg_request_latency_seconds

Example: 500 req/s, 100ms avg latency
  threads = 500 × 0.1 = 50 threads (steady state)
  + headroom for spikes: 50 × 2 = 100 threads

For I/O-bound work (waiting on DB, network):
  CPU utilization during wait = 0 → threads can be 10-50× CPU count
  Rule: threads = core_count × (1 + wait_time / compute_time)
  Example: 16 cores, 90ms DB wait, 10ms compute → 16 × (1 + 9) = 160 threads

For CPU-bound work:
  threads = core_count (+ 1 for Amdahl's law margin)
  More threads → context switch overhead > parallel benefit
```

---

## ForkJoinPool

Designed for **recursive divide-and-conquer tasks** (parallelStream, parallel arrays, recursive computation). Uses **work-stealing**: idle threads steal tasks from the tail of other threads' deques.

```java
// ForkJoinPool.commonPool() — shared JVM-wide pool
// ⚠️ parallelStream() uses this; blocking in parallelStream blocks the common pool for everyone

// Custom ForkJoinPool to isolate parallelism
ForkJoinPool customPool = new ForkJoinPool(8);  // 8 worker threads
customPool.submit(() -> {
    largeList.parallelStream().map(this::processItem).collect(Collectors.toList());
}).get();

// RecursiveTask example: parallel merge sort
class MergeSort extends RecursiveTask<int[]> {
    private final int[] array;
    private final int from, to;

    @Override
    protected int[] compute() {
        if (to - from <= 1024) {
            return Arrays.sort(array, from, to);  // base case
        }
        int mid = (from + to) / 2;
        MergeSort left  = new MergeSort(array, from, mid);
        MergeSort right = new MergeSort(array, mid, to);
        left.fork();                         // submit left to pool asynchronously
        int[] rightResult = right.compute(); // process right in current thread
        int[] leftResult  = left.join();     // wait for left
        return merge(leftResult, rightResult);
    }
}
```

**Work-stealing**: a thread with an empty deque steals from the **tail** of another thread's deque. The owner pushes/pops from its own **head** (LIFO, better cache locality). Stealer takes from tail (FIFO). This minimizes contention between owner and stealer.

**When NOT to use ForkJoinPool for I/O**:
```java
// WRONG: blocks a ForkJoinPool worker thread waiting for I/O
largeList.parallelStream()
    .map(id -> httpClient.get("/product/" + id))  // blocks thread!
    .collect(Collectors.toList());

// RIGHT: use CompletableFuture with a dedicated I/O thread pool
CompletableFuture.supplyAsync(() -> httpClient.get(url), ioThreadPool);
```

---

## CompletableFuture — Async Pipeline

`CompletableFuture` chains async operations without blocking threads. The critical rule: **always specify the executor** for any stage that does I/O; never rely on the common ForkJoinPool for blocking work.

```java
// ✅ Correct: separate pools for I/O and CPU
CompletableFuture<ProductPage> buildProductPage(String productId) {
    CompletableFuture<Price> priceF = CompletableFuture
        .supplyAsync(() -> priceService.getPrice(productId), ioPool);

    CompletableFuture<Inventory> inventoryF = CompletableFuture
        .supplyAsync(() -> inventoryService.get(productId), ioPool);

    CompletableFuture<Rating> ratingF = CompletableFuture
        .supplyAsync(() -> ratingService.get(productId), ioPool);

    return CompletableFuture
        .allOf(priceF, inventoryF, ratingF)
        .thenApplyAsync(v ->
            new ProductPage(priceF.join(), inventoryF.join(), ratingF.join()),
            cpuPool  // aggregation on CPU pool
        )
        .orTimeout(150, TimeUnit.MILLISECONDS)
        .exceptionally(ex -> ProductPage.partial(productId));  // graceful degradation
}

// ❌ Wrong: no executor specified — runs on ForkJoinPool.commonPool()
// If ioPool is blocked, this starves other parallelStream users in the same JVM
CompletableFuture.supplyAsync(() -> httpClient.call());  // missing executor!
```

**Common CompletableFuture pitfalls**:

```java
// DEADLOCK: calling .get() from within a CompletableFuture stage running on the same pool
// ───────── If the pool is exhausted, .get() blocks forever (thread holding its slot waits for a task
//           that needs a thread — but all threads are waiting)
executor.submit(() -> {
    CompletableFuture<String> f = CompletableFuture.supplyAsync(heavyTask, executor);
    return f.get();  // DEADLOCK if executor is full
});

// FIX: use different pool for the inner task, or use .thenCompose()
executor.submit(() -> {
    return CompletableFuture.supplyAsync(heavyTask, otherExecutor).join();
});
```

---

## Java Memory Model (JMM)

The JMM defines when writes by one thread are visible to other threads. The key concept is **happens-before (HB)**:

> If action A happens-before action B, then all memory writes by A are visible to B.

### Happens-Before Rules

```
1. Program order:      Within a single thread, each action HB next action
2. Monitor unlock:     Thread A unlock → Thread B lock on same monitor: A's writes visible to B
3. volatile write:     Thread A writes volatile x → Thread B reads volatile x: A HB B
4. Thread start:       Thread A calls t.start() HB any action in thread t
5. Thread join:        Any action in thread t HB Thread A returns from t.join()
6. Transitivity:       If A HB B and B HB C, then A HB C
```

### volatile — visibility without atomicity

```java
// volatile guarantees: writes are immediately visible to all threads (no CPU cache)
// volatile does NOT guarantee: atomicity of compound operations (check-then-act)

private volatile boolean running = true;

// Thread 1
void run() { while (running) { process(); } }

// Thread 2
void stop() { running = false; }  // visible to Thread 1 immediately
```

**volatile is sufficient for**:
- Boolean flags (stop flags, initialized flags)
- Single-writer, multiple-reader references (`volatile SomeConfig config`)
- DCL (double-checked locking) for Singleton (see below)

**volatile is NOT sufficient for**:
```java
// Race condition! i++ is read-modify-write — not atomic even with volatile
volatile int counter = 0;
counter++;  // ← NOT atomic: read(counter) + add(1) + write(counter) are 3 operations

// Fix: use AtomicInteger
AtomicInteger counter = new AtomicInteger(0);
counter.incrementAndGet();
```

### Double-Checked Locking — correct implementation

```java
// Correct DCL requires volatile on the instance field
public class Singleton {
    private static volatile Singleton instance;  // volatile is REQUIRED

    public static Singleton getInstance() {
        if (instance == null) {                  // check 1: no lock (fast path)
            synchronized (Singleton.class) {
                if (instance == null) {          // check 2: under lock
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
// Without volatile: partial construction visible to other threads
// (constructor writes may be reordered before instance = ptr assignment)
```

### Atomic Classes — lock-free concurrency

```java
AtomicInteger  counter = new AtomicInteger(0);
AtomicLong     timestamp = new AtomicLong();
AtomicBoolean  flag = new AtomicBoolean(false);
AtomicReference<Config> config = new AtomicReference<>();

// Compare-and-swap — the foundation of lock-free algorithms
int current;
do {
    current = counter.get();
} while (!counter.compareAndSet(current, current + 1));
// This is what .incrementAndGet() does internally

// LongAdder — better than AtomicLong under high contention
// Stripes the counter across cells; reduces CAS contention
LongAdder requestCount = new LongAdder();
requestCount.increment();  // ~10× faster than AtomicLong under high thread contention
long total = requestCount.sum();
```

### Concurrent Collections

```java
// ConcurrentHashMap — finer-grained locking than synchronized HashMap
// Java 8+: lock-free reads; writes lock individual buckets (not the whole map)
ConcurrentHashMap<String, Product> cache = new ConcurrentHashMap<>();

// Atomic operations on ConcurrentHashMap
cache.computeIfAbsent(key, k -> expensiveLoad(k));   // atomic check+create
cache.merge(key, 1L, Long::sum);                     // atomic read-modify-write

// CopyOnWriteArrayList — reads are lock-free; writes copy the entire array
// Use: small lists that are read very frequently, written rarely (event listener lists)
CopyOnWriteArrayList<EventListener> listeners = new CopyOnWriteArrayList<>();

// BlockingQueue implementations
LinkedBlockingQueue<Task>   lbq = new LinkedBlockingQueue<>(1000);  // two locks: head/tail
ArrayBlockingQueue<Task>    abq = new ArrayBlockingQueue<>(1000);   // one lock
ConcurrentLinkedQueue<Task> clq = new ConcurrentLinkedQueue<>();    // lock-free (Michael-Scott)
```

---

## Virtual Threads (Project Loom — Java 21)

Traditional OS threads are expensive: 1–2MB stack, ~1µs context switch. A thread pool of 200 threads handles 200 concurrent requests. Virtual threads are JVM-managed, cheap (~1KB initial stack, <1µs switch), and block without tying up an OS thread.

```
Platform thread: JVM thread ←1:1→ OS thread  (heavy, expensive, ~200 max practical)
Virtual thread:  JVM thread ←M:N→ OS thread  (light, cheap, millions possible)
```

**How virtual threads work**:
```
Virtual threads run on carrier threads (a ForkJoinPool of platform threads).
When a virtual thread blocks (I/O, lock, sleep):
  → JVM unmounts it from the carrier thread (saves only the continuation/stack)
  → Carrier thread picks up another runnable virtual thread
  → When the I/O completes, the virtual thread is re-mounted on a carrier thread
  → No OS context switch — just bookkeeping in JVM

Carrier thread count = CPU core count (default)
Virtual threads = millions (each is a ~1KB heap object when parked)
```

```java
// Virtual thread per task — replaces thread pool for I/O-bound work
try (ExecutorService vte = Executors.newVirtualThreadPerTaskExecutor()) {
    for (ProductId id : productIds) {
        vte.submit(() -> {
            // This blocks while waiting for DB/HTTP — carrier thread unblocked immediately
            Product p = db.findProduct(id);
            cache.put(id, p);
        });
    }
}  // auto-shutdown waits for all tasks

// HTTP server: Spring Boot 3.2+ enables virtual threads with one line
@Bean
public TomcatProtocolHandlerCustomizer<?> virtualThreads() {
    return handler -> handler.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
}

// Or via application.properties:
// spring.threads.virtual.enabled=true
```

**When virtual threads shine**:
- I/O-bound workloads: HTTP servers, database clients, file I/O
- High-concurrency scenarios where threads would block waiting (10K+ concurrent requests)
- Migrating from thread-per-request model without rewriting async code

**Virtual thread limitations — pinning**:

A virtual thread is **pinned** (cannot unmount) while:
1. Inside a `synchronized` block/method — carrier thread blocked until synchronized exits
2. Holding a native lock (JNI)

```java
// ❌ Causes pinning — blocks carrier thread during I/O inside synchronized
synchronized (this) {
    result = db.query(sql);  // blocks carrier thread, not just virtual thread
}

// ✅ Use ReentrantLock instead
ReentrantLock lock = new ReentrantLock();
lock.lock();
try {
    result = db.query(sql);  // virtual thread unmounts during I/O, carrier thread free
} finally {
    lock.unlock();
}
```

Diagnose pinning: `-Djdk.tracePinnedThreads=full` logs all pinning events.

**Virtual threads vs reactive (Webflux/RxJava)**:

| Aspect | Virtual Threads | Reactive (Webflux) |
|--------|----------------|-------------------|
| Programming model | Synchronous (imperative) | Asynchronous (functional) |
| Learning curve | Low — looks like blocking code | High — operators, schedulers, backpressure |
| Debugging | Easy — stack traces are normal | Hard — async stack traces are fragmented |
| Performance | Similar I/O throughput | Similar I/O throughput |
| CPU-bound work | Need ForkJoinPool for parallelism | Same |
| Pinning gotcha | synchronized blocks pin carrier | N/A |
| Recommendation | **New services on JDK 21+** | Existing reactive codebases |

---

## Concurrency Patterns — Quick Reference

### Thread-Safe Singleton (enum idiom — best approach)

```java
public enum DatabasePool {
    INSTANCE;
    private final ConnectionPool pool = new ConnectionPool(config);
    public ConnectionPool get() { return pool; }
}
// Enum initialization is guaranteed thread-safe by JLS
// No volatile, no synchronized, no DCL needed
```

### Immutable + volatile for config hot-swap

```java
// Pattern: immutable snapshot + volatile reference
// Reads are lock-free; config swap is a single volatile write
public final class AppConfig {  // immutable
    public final int maxConnections;
    public final Duration timeout;
    public AppConfig(int maxConnections, Duration timeout) {
        this.maxConnections = maxConnections;
        this.timeout = timeout;
    }
}

public class ConfigManager {
    private volatile AppConfig current = AppConfig.defaults();

    public AppConfig get() { return current; }  // lock-free read

    public void reload(AppConfig newConfig) {
        current = newConfig;  // single volatile write — instantly visible to all readers
    }
}
```

### Semaphore — bounded concurrency

```java
// Limit concurrent DB writes to 10 regardless of thread count
Semaphore writeSemaphore = new Semaphore(10);

void writeToDb(Data data) {
    writeSemaphore.acquire();
    try {
        db.write(data);
    } finally {
        writeSemaphore.release();
    }
}
```

### CountDownLatch — one-time synchronization barrier

```java
CountDownLatch ready = new CountDownLatch(services.size());

for (Service s : services) {
    executor.submit(() -> {
        s.init();
        ready.countDown();  // each service signals ready
    });
}

ready.await(30, TimeUnit.SECONDS);  // wait for all services to initialize
startAcceptingTraffic();
```

### CyclicBarrier — reusable synchronization point

```java
// All threads must reach the barrier before any proceeds — for parallel batch phases
CyclicBarrier barrier = new CyclicBarrier(workerCount, () -> {
    log.info("All workers completed phase 1, starting phase 2");
});

workers.forEach(w -> executor.submit(() -> {
    w.executePhase1();
    barrier.await();  // wait for all workers
    w.executePhase2();
}));
```

---

## FAANG Interview Callouts

- **"How do you size a thread pool for a service that calls a database?"** → Little's Law: `threads = latency × throughput`. If DB calls average 50ms and you need 1,000 RPS: 50 threads minimum + 50% headroom = 75 threads. Bound the queue to prevent OOM.
- **"What's wrong with Executors.newCachedThreadPool()?"** → It uses `SynchronousQueue` and `maximumPoolSize=MAX_INT`. Under load, creates unlimited threads → OOM. Use `ThreadPoolExecutor` with bounded `LinkedBlockingQueue` and explicit `maxPoolSize`.
- **"Your service has 100-thread pool and it's blocking at 80% CPU. What do you check?"** → Check queue depth first (pool may be saturated, tasks queuing). Check active thread count. Check rejection rate. If all threads active and queue full, increase `maxPoolSize` (if I/O-bound) or accept that you're hitting CPU ceiling.
- **"How does Virtual Threads solve the thread-per-request problem?"** → Each request gets a virtual thread that appears to block synchronously but physically unmounts from the carrier thread during I/O. A 4-core JVM with 4 carrier threads can serve 100K concurrent virtual threads, each blocking on DB/network, with no more than 4 OS threads.
- **"What is thread starvation deadlock?"** → Thread A submits task B to a thread pool and blocks waiting for B. Thread pool is full. Task B never runs because all threads are blocked waiting. Fix: don't have a task block on another task from the same pool. Use a second pool or async completion.
