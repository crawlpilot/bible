# 03 — Concurrency and Project Loom

**Calibration:** Principal Engineer bar — most interview-critical Java file  
**Cross-reference:** Thread pool sizing and CompletableFuture usage patterns → [02-java-best-practices.md](../../Development/best-practices/02-java-best-practices.md). This file covers internals, JMM, and Loom mechanics.

---

## 1. Java Memory Model — Happens-Before Rules

The JMM defines when a write to a variable by one thread is **visible** to a read by another thread. Without a happens-before relationship, the JVM is free to reorder instructions and cache values in CPU registers.

### The Six Happens-Before Rules

1. **Program Order Rule:** Each action in a thread happens-before every subsequent action in that thread.
2. **Monitor Lock Rule:** An unlock of a monitor happens-before every subsequent lock of the same monitor.
3. **Volatile Variable Rule:** A write to a `volatile` field happens-before every subsequent read of that same field.
4. **Thread Start Rule:** A call to `Thread.start()` happens-before any action in the started thread.
5. **Thread Join Rule:** All actions in a thread happen-before any thread that detects termination via `Thread.join()`.
6. **Transitivity:** If A hb B and B hb C, then A hb C.

### The Two Problems JMM Solves

1. **Visibility:** Without happens-before, a write by Thread A may remain in a CPU register or L1 cache, invisible to Thread B. `volatile` writes flush to main memory; `volatile` reads load from main memory.

2. **Reordering:** The CPU and JIT compiler reorder instructions for performance. They must not reorder across happens-before boundaries. A `volatile` write cannot be reordered before prior writes; a `volatile` read cannot be reordered after subsequent reads.

---

## 2. `volatile` vs. `synchronized` vs. `AtomicX`

### What `volatile` Guarantees

```java
volatile boolean stopped = false;

// Thread A (writes):
stopped = true;           // Write is immediately visible to all threads
                          // No reordering of prior writes past this point

// Thread B (reads):
while (!stopped) { ... }  // Every read sees the latest write
                          // No caching of stopped in a register
```

**What `volatile` does NOT guarantee:** Atomicity of compound operations.

```java
volatile int counter = 0;

// Thread A and Thread B simultaneously:
counter++;   // Read-modify-write — NOT atomic even with volatile
// Expands to: temp = counter; temp++; counter = temp;
// Both threads can read 0, both write 1 → lost update
```

### The Double-Checked Locking Problem (DCLP)

Classic lazy initialization — a rite of passage for every Java concurrency interview:

```java
// WRONG (Java 4 and earlier): not safe without volatile
class Singleton {
    private static Singleton instance;

    static Singleton getInstance() {
        if (instance == null) {              // check 1: unsynchronized read
            synchronized (Singleton.class) {
                if (instance == null) {      // check 2: inside lock
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
// Problem: "instance = new Singleton()" is THREE operations:
//   1. Allocate memory
//   2. Initialize fields
//   3. Assign reference to instance
// The JIT can reorder 3 before 2. Thread B sees non-null instance (step 3 done)
// but reads from an uninitialized object (step 2 not yet done).
```

```java
// CORRECT: volatile prevents reordering around the write
class Singleton {
    private static volatile Singleton instance;

    static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) {
                    instance = new Singleton();  // volatile write: steps 1,2 must complete before 3
                }
            }
        }
        return instance;
    }
}
```

```java
// BEST: Use enum — initialization guaranteed by class loading, not locks
enum Singleton {
    INSTANCE;
    // Initialization is thread-safe by JLS class loading guarantee (clinit is synchronized)
}
```

---

## 3. Lock Internals

### Object Header and Mark Word

Every Java object has a 12–16 byte header:
- **Mark word** (8 bytes): stores identity hash code, GC age, lock state.
- **Class pointer** (4 bytes with compressed oops).

The mark word encodes lock state:

```
Unlocked:         [hash:25 | age:4 | 0 | 01]
Biased:           [thread:54 | epoch:2 | age:4 | 1 | 01]  (removed JDK 15+)
Thin lock:        [lock-record-ptr:62 | 00]
Fat lock:         [monitor-ptr:62 | 10]
GC marked:        [forwarding-ptr:62 | 11]
```

### Lock Escalation

1. **Unlocked:** Initial state.
2. **Thin lock (stack-allocated monitor):** First `synchronized` — record lock in current thread's stack frame via CAS on mark word. No OS involvement. Very fast.
3. **Fat lock (inflated monitor):** When contended — a `ObjectMonitor` heap object is allocated. Waiting threads are queued. OS mutex involved for blocking.

**Biased locking** (removed in JDK 15, JEP 374): Single-threaded objects — mark word encodes the owning thread ID; `synchronized` by the same thread needs no CAS. Removed because the revocation overhead (stopping the world to transfer bias) outweighed benefits for modern concurrent workloads.

### `ReentrantLock` vs. `synchronized`

| Feature | `synchronized` | `ReentrantLock` |
|---------|--------------|----------------|
| Fairness | No (OS-dependent) | Optional (`new ReentrantLock(true)`) |
| Interruptible wait | No | Yes — `lockInterruptibly()` |
| Try-lock with timeout | No | Yes — `tryLock(timeout, unit)` |
| Condition variables | One per object | Multiple per lock |
| Virtual thread pinning | **Yes** (pins carrier) | **No** (does not pin) |
| Code complexity | Low | Medium |

```java
ReentrantLock lock = new ReentrantLock();

// Try-lock with timeout — useful for deadlock prevention
boolean acquired = lock.tryLock(100, TimeUnit.MILLISECONDS);
if (!acquired) {
    // Return error, retry, or take alternative action
    return Optional.empty();
}
try {
    return Optional.of(doWork());
} finally {
    lock.unlock();   // MUST be in finally
}
```

### `StampedLock` — Optimistic Read Protocol

For read-heavy data with occasional writes:

```java
StampedLock lock = new StampedLock();
double x, y;  // coordinates updated rarely, read frequently

// Write path
long stamp = lock.writeLock();
try { x = newX; y = newY; }
finally { lock.unlockWrite(stamp); }

// Read path — optimistic (no lock acquisition for happy path)
double readX, readY;
long stamp = lock.tryOptimisticRead();  // gets a stamp if no writer active
readX = x; readY = y;                  // read values (may be inconsistent if writer ran)
if (!lock.validate(stamp)) {           // validate: no write occurred since stamp
    // Optimistic read failed — fall back to read lock
    stamp = lock.readLock();
    try { readX = x; readY = y; }
    finally { lock.unlockRead(stamp); }
}
// Use readX, readY
```

**When optimistic read wins:** High read-to-write ratios (e.g., 1000:1). The `validate` call is a single volatile read — near-zero cost if no writer ran.

**StampedLock is NOT reentrant.** A thread holding a write lock that tries to acquire a read lock → deadlock. This is the most common `StampedLock` bug.

---

## 4. Atomic Operations and CAS

### Compare-And-Swap (CAS)

CAS is a single hardware instruction: `CMPXCHG` on x86. It atomically:
1. Compares memory location with `expected`.
2. If equal: writes `update` and returns true.
3. If not equal: does nothing and returns false.

```java
AtomicInteger counter = new AtomicInteger(0);

// CAS loop: increment without synchronized
int prev, next;
do {
    prev = counter.get();
    next = prev + 1;
} while (!counter.compareAndSet(prev, next));
// If another thread changed counter between get() and compareAndSet(),
// the CAS fails, we retry with the new value
```

### ABA Problem

CAS checks **value**, not **version**. Thread T1 reads A. T2 changes A → B → A. T1's CAS(A, newValue) succeeds — but the value A after T2's operations may be semantically different from the original A.

```java
// Lock-free stack (Treiber stack)
AtomicReference<Node> top = new AtomicReference<>();

void push(int val) {
    Node newNode = new Node(val);
    Node oldTop;
    do {
        oldTop = top.get();
        newNode.next = oldTop;
    } while (!top.compareAndSet(oldTop, newNode));
}

Node pop() {
    Node oldTop, newTop;
    do {
        oldTop = top.get();
        if (oldTop == null) return null;
        newTop = oldTop.next;
    } while (!top.compareAndSet(oldTop, newTop));
    return oldTop;
}

// ABA scenario:
// T1 reads top = A, A.next = B
// T2 pops A, pops B, pushes A back (node A reused)
// T1's CAS(A, B) succeeds — but A.next may now point to somewhere unexpected
// Result: lost update or corrupted list
```

**Fix:** `AtomicStampedReference<T>` — CAS on (reference, stamp) pair. The stamp (version number) is incremented on every update, making A-after-change distinguishable from A-before-change.

### `LongAdder` vs. `AtomicLong`

`AtomicLong` uses a single CAS. Under high contention (many threads incrementing simultaneously), threads spin-retry the CAS — wasted CPU cycles.

`LongAdder` (Java 8) uses **Striped64**: an array of `Cell` objects. Each thread is hashed to a cell. Increments go to the thread's cell with low contention. `sum()` adds all cells.

```java
// Under 16 concurrent threads incrementing at 10M/s:
// AtomicLong: ~30-40% CAS retry rate
// LongAdder: < 2% CAS retry rate, 3-5x throughput

// Use AtomicLong when: you need compareAndSet (conditional update)
AtomicLong seq = new AtomicLong();
long next = seq.incrementAndGet();  // sequence generation

// Use LongAdder when: you only need add/sum (metrics, counters)
LongAdder hits = new LongAdder();
hits.increment();      // fast
long total = hits.sum();  // slightly slower but reads are rare
```

### `VarHandle` (Java 9)

`VarHandle` replaced `sun.misc.Unsafe` for library-level atomic operations:

```java
// Treiber stack with VarHandle (production-quality lock-free stack)
class TreiberStack<T> {
    private static final VarHandle TOP;
    static {
        try {
            TOP = MethodHandles.lookup()
                .findVarHandle(TreiberStack.class, "top", Node.class);
        } catch (Exception e) { throw new ExceptionInInitializerError(e); }
    }

    private volatile Node<T> top;

    static class Node<T> {
        final T value;
        volatile Node<T> next;
        Node(T v) { this.value = v; }
    }

    void push(T value) {
        Node<T> newNode = new Node<>(value);
        Node<T> oldTop;
        do {
            oldTop = (Node<T>) TOP.getVolatile(this);
            newNode.next = oldTop;
        } while (!TOP.compareAndSet(this, oldTop, newNode));
    }
}
```

`VarHandle` advantages over `Unsafe`:
- Type-checked (can't accidentally pass wrong type).
- Access-controlled (respects module system).
- JIT-optimizable (compiles to same machine code as `Unsafe` after warmup).
- Stable public API (won't break across JDK versions).

---

## 5. Fork/Join Framework

### Work-Stealing Algorithm

Each `ForkJoinWorkerThread` maintains a **double-ended deque (deque)**:
- Worker pushes new tasks to the **front** (LIFO) — exploits temporal locality.
- Worker pops its own tasks from the **front** (LIFO).
- Idle workers **steal** from the **back** of other workers' deques (FIFO) — avoids contention between thief and owner.

```
Worker A deque (owns front):  [task8, task7, task6 | task5, task4, task3, task2, task1]
                                ← A pushes/pops here    thieves steal from here →
```

Why LIFO push + FIFO steal is optimal:
- The worker's most recent fork (front) has the warmest data — local execution is fast.
- Stealing large, old tasks from the back maximizes steal value (stealing a parent task gets all its subtasks).

### `ForkJoinPool.commonPool()` — The Trap

The common pool is shared across the JVM. Its size = `Runtime.availableProcessors() - 1`.

**Danger in server applications:** If your web handler calls `parallelStream()` or submits to `commonPool`, and another request also does so, they share the same pool. A slow parallel job can starve all parallel operations on the same JVM.

```java
// WRONG: blocking in commonPool
List<Order> results = orders.parallelStream()
    .map(order -> repository.findById(order.id()))  // DB call — blocks!
    .collect(toList());
// The blocked DB calls hold commonPool threads, starving other parallel operations

// RIGHT: use a dedicated pool for blocking work
ForkJoinPool customPool = new ForkJoinPool(20);
customPool.submit(() ->
    orders.parallelStream()
        .map(order -> repository.findById(order.id()))
        .collect(toList())
).get();
```

---

## 6. CompletableFuture Internals

### Internal Structure: Treiber Stack of Completions

```
CompletableFuture<T>:
  result: Object        ← null (pending), or AltResult(exception), or actual value
  stack: Completion     ← head of a Treiber stack of dependent actions
```

When the future is completed (`.complete(value)`):
1. Set `result` with CAS.
2. Pop and run all completions from the stack (the dependent `.thenApply`, `.thenAccept`, etc. callbacks).

### Executor Binding: `thenApply` vs. `thenApplyAsync`

```java
CompletableFuture<String> f = CompletableFuture.supplyAsync(() -> fetchData());

// thenApply: runs on whichever thread completed the future
// If fetchData() completed on thread "http-1", processData runs on "http-1"
f.thenApply(data -> processData(data));

// thenApplyAsync: runs on ForkJoinPool.commonPool() (default)
f.thenApplyAsync(data -> processData(data));

// thenApplyAsync with custom executor:
f.thenApplyAsync(data -> processData(data), myExecutorService);
```

**Critical implication:** `thenApply` can run on the completing thread or the calling thread (if the future is already done when `thenApply` is called). This non-determinism is a common source of subtle threading bugs. Use `thenApplyAsync` for predictable thread assignment.

### Exception Propagation

```java
CompletableFuture<String> f = CompletableFuture.supplyAsync(() -> {
    if (Math.random() < 0.5) throw new RuntimeException("failed");
    return "success";
});

// handle: called for BOTH success and failure — replaces value or exception
f.handle((result, ex) -> {
    if (ex != null) return "default";
    return result;
});

// exceptionally: called only on failure — maps exception to a value
f.exceptionally(ex -> "default");

// whenComplete: called for both — does not transform the result
f.whenComplete((result, ex) -> {
    if (ex != null) log.error("failed", ex);
});
// whenComplete propagates the ORIGINAL exception downstream, unlike handle
```

---

## 7. Virtual Threads — Project Loom (Java 21 Final)

### Carrier Thread Model

```
JVM:
  Platform (OS) threads: 8  (= CPU cores, the "carrier pool")
    Carrier thread 1  ← currently running virtual thread V23
    Carrier thread 2  ← currently running virtual thread V7
    ...
  Virtual threads: up to millions
    V1  (blocked on socket read — unmounted, parked in heap)
    V2  (blocked on DB query — unmounted, parked in heap)
    ...
    V23 (running — mounted on carrier 1)
    V7  (running — mounted on carrier 2)
```

**Mount/Unmount:** When a virtual thread calls a blocking operation (socket I/O, `Thread.sleep`, `LockSupport.park`), the JVM:
1. Saves the virtual thread's stack to the heap (a `Continuation` object).
2. Unmounts it from the carrier thread.
3. The carrier is now free to run another virtual thread.
4. When the blocking operation completes, the virtual thread is rescheduled — mounted on any available carrier.

**Cost:** A virtual thread's stack is heap-allocated and grows/shrinks as needed. Initial stack: ~few hundred bytes (vs. 512KB–2MB for platform threads). A million virtual threads = hundreds of MB heap, not hundreds of GB OS virtual memory.

### `synchronized` Block Pinning — The Critical Problem

```java
// This pins the carrier thread — the blocking operation holds the carrier
synchronized (this) {
    Thread.sleep(100);   // virtual thread sleeps, but carrier is PINNED
                         // carrier cannot run other virtual threads during sleep
}
```

**Why:** `synchronized` uses the JVM object monitor. The monitor's owner is recorded in the object header as the **OS thread ID** (the carrier). When the virtual thread parks, the JVM cannot unmount it without releasing the monitor (which would change the semantics). So the carrier is blocked, defeating the purpose of virtual threads.

**`ReentrantLock` does NOT pin:**
```java
ReentrantLock lock = new ReentrantLock();
lock.lock();
try {
    Thread.sleep(100);  // carrier is freed to run other virtual threads
} finally {
    lock.unlock();
}
// ReentrantLock's owner is the virtual thread, not the carrier
// Parking is safe — the lock is transferred when the VT resumes
```

**JEP 491 (Java 24):** Targeted fix — changes the JVM to store the virtual thread as the monitor owner, not the carrier. After JEP 491, `synchronized` blocks no longer pin. In Java 21–23: replace `synchronized` with `ReentrantLock` in code used by virtual threads.

**Detecting pinning:**
```bash
-Djdk.tracePinnedThreads=full   # JVM flag: prints stack trace when pinning occurs
```

### Creating Virtual Threads

```java
// Option 1: Thread builder
Thread vt = Thread.ofVirtual().name("vt-1").start(() -> handleRequest(req));

// Option 2: Virtual thread executor (best for server code)
try (ExecutorService exec = Executors.newVirtualThreadPerTaskExecutor()) {
    for (Request req : requests) {
        exec.submit(() -> handleRequest(req));
    }
}   // try-with-resources: shuts down and waits for all tasks

// Option 3: Virtual thread factory for frameworks
ThreadFactory factory = Thread.ofVirtual().name("handler-", 0).factory();
ExecutorService exec = Executors.newThreadPerTaskExecutor(factory);
```

---

## 8. Structured Concurrency (Java 21 Preview / Java 23 Second Preview)

### The Problem with Flat CompletableFuture Fan-Outs

```java
// Flat fan-out: hard to cancel on partial failure
CompletableFuture<User> userF = fetchUser(userId);
CompletableFuture<Inventory> invF = fetchInventory(productId);
CompletableFuture<Price> priceF = fetchPrice(productId);

// If fetchUser fails: invF and priceF continue running — resource waste
// Cancellation must be managed manually
CompletableFuture<Result> result = CompletableFuture.allOf(userF, invF, priceF)
    .thenApply(_ -> new Result(userF.join(), invF.join(), priceF.join()));
```

### `StructuredTaskScope`

```java
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    Subtask<User>      userTask  = scope.fork(() -> fetchUser(userId));
    Subtask<Inventory> invTask   = scope.fork(() -> fetchInventory(productId));
    Subtask<Price>     priceTask = scope.fork(() -> fetchPrice(productId));

    scope.join();           // wait for all forks to complete
    scope.throwIfFailed();  // if any fork threw, re-throw here

    return new Result(userTask.get(), invTask.get(), priceTask.get());
}
// On scope close: any still-running forks are cancelled automatically
// ShutdownOnFailure: if ANY fork fails → immediately cancel all others
```

`ShutdownOnSuccess`: for "first one wins" scenarios (race two implementations):

```java
try (var scope = new StructuredTaskScope.ShutdownOnSuccess<Result>()) {
    scope.fork(() -> callServiceA());
    scope.fork(() -> callServiceB());
    scope.join();
    return scope.result();  // whichever finished first
}
// The slower one is cancelled
```

**Relationship to Kotlin Coroutines:** Structured concurrency is the same concept as Kotlin's coroutine scopes. A scope defines the lifetime of all work spawned within it. When the scope exits, all spawned work is either complete or cancelled. This is a significant safety improvement over `CompletableFuture` chains where cancellation is opt-in.

---

## 9. Scoped Values (Java 21 Preview / Java 23 Second Preview)

### The Problem with `ThreadLocal` at Scale

```java
// ThreadLocal: stored in Thread.threadLocals map
// At 1M virtual threads: 1M maps, each potentially holding large values
private static final ThreadLocal<RequestContext> CTX = new ThreadLocal<>();

// Per-thread map entry: ~32 bytes + value
// 1M virtual threads × 32 bytes = 32MB minimum, potentially GBs with large values
```

Additionally, `ThreadLocal` doesn't compose with virtual threads well:
- Child virtual threads don't inherit parent's `ThreadLocal` by default.
- `InheritableThreadLocal` copies the map on thread creation — expensive for millions of virtual threads.

### `ScopedValue` — Immutable, Lexically Scoped

```java
private static final ScopedValue<RequestContext> REQUEST_CTX = ScopedValue.newInstance();

// Bind value for the duration of a scope
ScopedValue.where(REQUEST_CTX, new RequestContext(req))
           .run(() -> {
               processRequest();       // can read REQUEST_CTX.get()
               callDownstreamService(); // and so can any called method
           });
// After run() returns: REQUEST_CTX.get() throws NoSuchElementException (unbound)

// Reading:
void processRequest() {
    RequestContext ctx = REQUEST_CTX.get();  // always valid within the scope
}
```

**Key differences from `ThreadLocal`:**

| | `ThreadLocal` | `ScopedValue` |
|--|--------------|--------------|
| Mutability | Mutable (set/remove at any point) | Immutable within binding scope |
| Inheritance | InheritableThreadLocal (copy on fork) | Automatic, zero-copy inheritance by child virtual threads |
| Cleanup | Manual `remove()` required | Automatic when scope exits |
| Memory | Per-thread map (persistent) | Stack-like scope binding (freed on scope exit) |
| Thread safety | Not thread-safe across threads | Read-only within scope — inherently safe |

**Inheritance with virtual threads:**
```java
ScopedValue.where(CTX, requestCtx).call(() -> {
    // Fork 3 virtual threads — they all inherit CTX without copying
    try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
        scope.fork(() -> { CTX.get(); /* sees requestCtx */ });
        scope.fork(() -> { CTX.get(); /* same requestCtx */ });
        scope.join();
    }
    return result;
});
```

---

## 10. Concurrency Patterns Reference

### Producer-Consumer with `BlockingQueue`

```java
BlockingQueue<Task> queue = new LinkedBlockingQueue<>(1000);  // bounded!

// Producer (blocks when full)
executor.submit(() -> {
    while (running) {
        Task t = generateTask();
        queue.put(t);       // blocks if queue is full — backpressure!
    }
});

// Consumer (blocks when empty)
executor.submit(() -> {
    while (running || !queue.isEmpty()) {
        Task t = queue.poll(100, TimeUnit.MILLISECONDS);  // timeout to check running
        if (t != null) process(t);
    }
});
```

### Phaser vs. CountDownLatch vs. CyclicBarrier

| | `CountDownLatch` | `CyclicBarrier` | `Phaser` |
|--|-----------------|----------------|--------|
| Reusable | No | Yes (resets) | Yes (phases) |
| Dynamic parties | No | No | Yes (register/deregister) |
| Use case | Wait for N events | N threads meet at barrier | Multi-phase computation |

```java
// Phaser for multi-phase parallel computation
Phaser phaser = new Phaser(workerCount);

for (int i = 0; i < workerCount; i++) {
    executor.submit(() -> {
        // Phase 1
        doPhase1Work();
        phaser.arriveAndAwaitAdvance();  // wait for all workers to finish phase 1

        // Phase 2
        doPhase2Work();
        phaser.arriveAndDeregister();    // done — deregister from phaser
    });
}
```

---

## Interview Q&A

### Q1 `[Principal]` What exactly does `volatile` guarantee and not guarantee? Production example where necessary but not sufficient.

**Answer:**

**Guarantees:**
1. Visibility: every read of a `volatile` variable sees the most recent write from any thread.
2. No reordering: writes before a `volatile` write are not reordered after it; reads after a `volatile` read are not reordered before it. This creates a "memory fence" at the volatile access.

**Does NOT guarantee:** Atomicity of compound read-modify-write operations.

**Production example:**

```java
// Rate limiter — wrong implementation
volatile long requestCount = 0;
volatile long windowStart = System.currentTimeMillis();

boolean tryAcquire() {
    long now = System.currentTimeMillis();
    if (now - windowStart > WINDOW_MS) {
        windowStart = now;      // volatile write
        requestCount = 1;       // volatile write
        return true;
    }
    if (requestCount < LIMIT) {
        requestCount++;         // NOT atomic — three operations
        return true;
    }
    return false;
}
// Two threads can both read requestCount = 99, both write 100.
// requestCount should be 101 but is 100 → 1 request lost.
```

**Fix:** `AtomicLong.incrementAndGet()` for `requestCount`, `AtomicLong.compareAndSet()` for window reset. Or use a `synchronized` block around the compound check-and-increment.

---

### Q2 `[Principal]` Why does `synchronized` pin a virtual thread to its carrier thread? What is the exact JVM mechanism, and when does JEP 491 fix this?

**Answer:**

**Exact mechanism:**

The JVM object monitor tracks its owner as the **OS thread ID** stored in the object's mark word:

```
Locked mark word: [monitor-ptr:62 | 10]
ObjectMonitor:
  _owner: Thread*  ← pointer to OS (platform) thread struct
  _recursions: int
  _EntryList: ...  ← waiting threads
```

When a virtual thread enters a `synchronized` block:
1. Its carrier OS thread is stored as `_owner` in the monitor.
2. If the virtual thread then hits a blocking point (e.g., `Thread.sleep`), the JVM tries to unmount it from the carrier.
3. But the carrier is the monitor owner. Transferring ownership to the virtual thread would require updating `_owner` — but `_owner` is a pointer to an OS thread, not a virtual thread concept.
4. The JVM cannot unmount without violating the monitor contract → it leaves the virtual thread mounted (pinned) and parks the carrier OS thread.

**Result:** The carrier OS thread blocks, defeating the purpose. With 8 carrier threads and 8 simultaneous `synchronized` + blocking operations, ALL 8 carriers are pinned. No other virtual threads can run.

**JEP 491 (targeted Java 24):** Changes `_owner` to store a Java object reference (the `Thread` object, which can be a virtual `Thread`). The monitor owner becomes the virtual thread itself. Now the carrier can unmount the virtual thread even while it holds a monitor — the monitor remembers the virtual thread, not the carrier.

**Interim fix (Java 21–23):** Replace `synchronized` blocks in I/O-bound paths with `ReentrantLock`, which does not use the object monitor system.

---

### Q3 `[Principal]` Explain work-stealing in Fork/Join and why it outperforms a shared thread pool for recursive algorithms.

**Answer:**

**Shared thread pool behavior:** All N threads read from ONE shared `BlockingQueue`. For a task that forks into 2^20 subtasks (a binary tree of depth 20), all 1M subtasks go into the shared queue. All threads contend on the queue head. Queue lock contention alone can saturate a 16-core system.

**Work-stealing behavior:** Each worker has its own deque. No global contention.

| Aspect | Shared Queue | Work-Stealing Deque |
|--------|-------------|---------------------|
| Task submission | Lock-contended enqueue | Lock-free front-push on own deque |
| Task consumption | Lock-contended dequeue | Lock-free front-pop on own deque |
| Stealing | N/A | Occasional CAS on back of other deque |
| Cache behavior | Global queue pointer | Own deque → cache-warm |

**The LIFO/FIFO insight:**

- Worker pushes to front (LIFO) and pops from front (LIFO): the most recently forked subtask is the hottest — its parent just wrote all its inputs. Running it immediately exploits L1 cache warmth.
- Thieves steal from back (FIFO): old, large tasks at the back represent more work. Stealing a large task (parent of many subtasks) gives the thief a full subtree of work — better than stealing tiny leaf tasks.

For a balanced binary tree of n leaf tasks:
- Each worker submits and processes tasks with near-zero contention.
- When a worker's subtree is exhausted, it steals a fresh subtree.
- Theoretical speedup: near-linear with processor count for balanced recursive algorithms.

---

### Q4 `[Principal]` Describe the ABA problem and a production lock-free stack scenario where it causes corruption.

**Answer:**

**ABA problem:**

CAS checks whether a memory location still contains `expected_value`. It cannot detect that the value was changed from A → B → A since the last read.

**Production lock-free stack (Treiber stack) scenario:**

```
Initial state: top → A → B → null

Thread T1: reads top = A, A.next = B
           [context switch before CAS]

Thread T2: pops A (top = B → null)
           pops B (top = null)
           pushes A (reusing same node object, A.next = null now)
           top → A → null

T1 resumes: CAS(top, A, B) → succeeds! (top still has the node A)
           But now top = B, and B.next is undefined/freed/corrupted
           (B was already popped and potentially garbage)

Result: top = B → null, but B has already been popped.
        Any subsequent pop sees a "ghost" element.
```

**Fix:** `AtomicStampedReference<Node>`:

```java
AtomicStampedReference<Node> top = new AtomicStampedReference<>(null, 0);

Node pop() {
    int[] stampHolder = new int[1];
    Node oldTop, newTop;
    do {
        oldTop = top.get(stampHolder);
        int stamp = stampHolder[0];
        if (oldTop == null) return null;
        newTop = oldTop.next;
    } while (!top.compareAndSet(oldTop, newTop, stamp, stamp + 1));
    return oldTop;
}
// Now CAS checks: reference == oldTop AND stamp == stamp
// T2's A-pop-A sequence increments stamp twice.
// T1's CAS(A, stamp=0) fails because stamp is now 2.
```

---

### Q5 `[Principal]` `ThreadLocal` vs. `ScopedValue` with a million virtual threads — explain the memory and safety implications.

**Answer:**

**`ThreadLocal` with 1M virtual threads:**

`ThreadLocal` storage lives in `Thread.threadLocals` — a hash table inside each `Thread` object. 

Memory: 1M virtual threads × ThreadLocal map entry (~32 bytes + value size).  
If each value is a 1KB `RequestContext`: 1M × 1KB = 1GB additional heap.

Safety issues:
1. **Mutable:** any code path can call `ThreadLocal.set()`, overwriting the value mid-request.
2. **Cleanup required:** `remove()` must be called in `finally` — easy to forget.
3. **Inheritance complexity:** `InheritableThreadLocal` copies the entire map when spawning child threads — expensive for virtual threads.

**`ScopedValue` with 1M virtual threads:**

`ScopedValue` bindings form a linked list of scope frames in the current thread's execution context. When the scope exits, the frame is popped — no explicit cleanup.

Memory: the binding is one frame in a thread-local stack. No per-thread map maintenance. Inherited by child virtual threads as a shallow pointer copy (no value copying).

Safety:
1. **Immutable within scope:** `ScopedValue.get()` always returns the same value. No mutation possible — thread safety is trivially guaranteed.
2. **Automatic cleanup:** when `ScopedValue.where(...).run(...)` returns, the binding is gone — no `finally` needed.
3. **Structured inheritance:** virtual threads forked within a `StructuredTaskScope` inherit the parent's `ScopedValue` bindings automatically with zero-copy semantics.

**When to still use `ThreadLocal`:** Library code that needs mutable per-thread state and cannot use structured scopes (e.g., JDBC connection binding, Spring security context). Even then, ensure `remove()` is always called.

---

### Q6 `[Principal]` Design a `StampedLock`-based rate limiter with an optimistic fast path.

**Answer:**

```java
class OptimisticRateLimiter {
    private final StampedLock lock = new StampedLock();
    private long windowStart = System.currentTimeMillis();
    private long requestCount = 0;
    private final long limit;
    private final long windowMs;

    OptimisticRateLimiter(long limit, long windowMs) {
        this.limit = limit;
        this.windowMs = windowMs;
    }

    boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // Fast path: optimistic read (no lock, no CAS)
        long stamp = lock.tryOptimisticRead();
        long localCount = requestCount;
        long localStart = windowStart;
        if (lock.validate(stamp)) {
            // No writer ran since stamp — values are consistent
            if (now - localStart < windowMs && localCount < limit) {
                // Looks good — but need write lock to actually increment
                stamp = lock.writeLock();
                try {
                    // Re-check under write lock (state may have changed)
                    if (System.currentTimeMillis() - windowStart >= windowMs) {
                        windowStart = System.currentTimeMillis();
                        requestCount = 1;
                        return true;
                    }
                    if (requestCount < limit) {
                        requestCount++;
                        return true;
                    }
                    return false;
                } finally {
                    lock.unlockWrite(stamp);
                }
            }
        }

        // Optimistic read failed or definitely over limit — use write lock directly
        stamp = lock.writeLock();
        try {
            now = System.currentTimeMillis();
            if (now - windowStart >= windowMs) {
                windowStart = now;
                requestCount = 1;
                return true;
            }
            if (requestCount < limit) {
                requestCount++;
                return true;
            }
            return false;
        } finally {
            lock.unlockWrite(stamp);
        }
    }
}
```

**Key insight:** The optimistic read can quickly determine "probably not rate-limited" with no lock overhead. The actual state mutation always requires the write lock. The double-check under write lock handles the TOCTOU gap between optimistic read and write lock acquisition.

**When this outperforms `ReentrantReadWriteLock`:** When most requests are NOT rate-limited (the happy path). The optimistic read returns with zero lock acquisitions. Under heavy contention (many near-limit requests), the fallback to write lock is necessary anyway.

---

*See also:* [04-data-structures-internals.md](04-data-structures-internals.md) for `ConcurrentHashMap` and `LongAdder` internals | [08-oom-debugging-and-profiling.md](08-oom-debugging-and-profiling.md) for `ThreadLocal` leak debugging
