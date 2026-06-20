# 08 — OOM Debugging and Profiling

**Calibration:** Principal Engineer bar — expected to have solved OOM in production  
**Focus:** Systematic, tool-driven playbook. Not theory — procedure.

---

## OOM Taxonomy — Know Which Type Before Debugging

Java throws six distinct `OutOfMemoryError` subtypes. The message tells you where to look:

| OOM Message | Meaning | Primary Tools |
|-------------|---------|---------------|
| `Java heap space` | Heap exhausted — object allocation failed | Heap dump + MAT |
| `GC overhead limit exceeded` | >98% time in GC, recovering <2% heap | Heap dump + GC log |
| `Metaspace` | Class metadata area full | Class loader analysis |
| `Compressed class space` | Native memory for compressed oops exhausted | `NativeMemoryTracking` |
| `Unable to create new native thread` | OS thread limit hit | `jstack` + ulimit |
| `Direct buffer memory` | Off-heap `ByteBuffer` pool exhausted | `NativeMemoryTracking` |

**Critical insight:** `Java heap space` and `GC overhead limit exceeded` both indicate the heap is full, but their root causes differ:
- `Java heap space`: a single large allocation failed (e.g., `new byte[2GB]` when only 1GB free) OR heap is continuously full.
- `GC overhead limit exceeded`: heap has enough free space to technically fit small objects, but GC keeps running, recovering almost nothing, and eventually gives up. This fires BEFORE the heap is completely full. Often indicates a slow memory leak that has filled 98% of heap.

---

## JVM Flags for Crash Intelligence

**Always run these in all environments — dev, staging, prod:**

```bash
# Heap dump on OOM — the single most important flag
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/log/app/heapdumps/

# Exit cleanly instead of running degraded
-XX:+ExitOnOutOfMemoryError

# Run a script on OOM (e.g., notify PagerDuty, rotate logs)
-XX:OnOutOfMemoryError="kill -9 %p; /opt/scripts/notify-oom.sh"

# GC logging (Java 11+ unified logging)
-Xlog:gc*:file=/var/log/app/gc.log:time,uptime:filecount=5,filesize=20m

# Native memory tracking for off-heap investigation
-XX:NativeMemoryTracking=detail

# Heap sizing (start conservatively, tune from data)
-Xms2g -Xmx8g

# G1GC tuning for latency-sensitive services
-XX:+UseG1GC
-XX:MaxGCPauseMillis=100
-XX:G1HeapRegionSize=16m
```

---

## 8-Step OOM Investigation Playbook

### Step 1: Identify OOM Type From Logs

```bash
grep "OutOfMemoryError" /var/log/app/app.log | tail -20
# Look for the exact message after the colon:
# "Java heap space" → Step 2 (heap dump)
# "Metaspace" → Step 7 (class loader)
# "unable to create new native thread" → Step 5b (thread count)
# "Direct buffer memory" → use jcmd for NMT summary
```

### Step 2: Capture Heap Dump

If `HeapDumpOnOutOfMemoryError` was set, the dump is already written. For a running process:

```bash
# Find the PID
jps -l

# Capture live heap dump (causes a GC pause — do in off-peak or staging)
jmap -dump:format=b,live,file=/tmp/app-$(date +%Y%m%d-%H%M%S).hprof <pid>
# "live" = only include objects reachable from GC roots (excludes garbage)
# Omit "live" to capture everything including garbage (larger file, shows allocation)

# Check dump size
ls -lh /tmp/app-*.hprof
# Typical: 1–5GB for a service with 4GB heap
```

**In containers (Kubernetes):** Mount `/tmp` as an `emptyDir` volume or use a persistent volume. The container's ephemeral filesystem may not have space.

### Step 3: GC Log Pattern Analysis

Before opening MAT, GC logs can confirm whether this is a leak or undersizing in seconds:

```
Pattern 1: Sawtooth — HEALTHY
  |  /\  /\  /\
  | /  \/  \/  \
  |/
  → Heap fills, GC runs, reclaims, fills again. Normal.

Pattern 2: Climbing sawtooth — MEMORY LEAK
  |       /\
  |    /\/  \
  | /\/       \
  |/           \  ← eventually OOM
  → Baseline after each GC is higher. Objects survive that shouldn't.

Pattern 3: Flat high — UNDERSIZED HEAP
  |___________/\   ← one spike causes OOM
  |           OOM
  → GC runs, reclaims, but heap is consistently 95%+ full.
  → Increasing heap size will fix it (temporarily).
```

Parse GC log for heap occupancy after full GC:
```bash
grep "Heap: " /var/log/app/gc.log | awk '{print $3}' | \
  sed 's/M.*//' | sort -n | tail -20
# If the "after full GC" sizes are steadily increasing → leak
```

### Step 4: Eclipse MAT Analysis

MAT is the standard heap dump analyser. Download: `eclipse.org/mat`.

```bash
# Open dump (MAT needs ~50% of dump size as its own heap)
# Set MAT heap size in MemoryAnalyzer.ini:
-Xmx8g  # for a 5GB dump

# Command-line parse for CI/automation:
./ParseHeapDump.sh app.hprof org.eclipse.mat.api:suspects
```

**Workflow:**

1. **Leak Suspects Report** (auto-generated): MAT runs heuristics to identify the most likely leak objects. Review the top 1–3 suspects with their retained heap size and reference chain.

2. **Dominator Tree:** Shows which objects are retaining the most heap. An object A dominates object B if every path from GC roots to B passes through A. Objects at the top of the dominator tree are responsible for the most retained memory.
   - Sort by "Retained Heap" descending.
   - Look for unexpected objects at the top (e.g., a single `HashMap` retaining 4GB).

3. **Path to GC Roots:** Right-click a suspicious object → "Path to GC Roots" → "Exclude weak/soft/phantom references". This shows why an object is not being GC'd — the chain from a GC root (static field, active thread, JNI ref) to the object.

4. **OQL — Object Query Language:**
```sql
-- Find all HashMaps with more than 1000 entries
SELECT * FROM java.util.HashMap WHERE size() > 1000

-- Find all String objects whose content starts with a prefix
SELECT * FROM java.lang.String WHERE toString().startsWith("user:")

-- Find all ThreadLocal values
SELECT * FROM java.lang.ThreadLocal$ThreadLocalMap$Entry

-- Show top 10 classes by instance count
SELECT s.clazz.name, count(*) FROM OBJECTS s GROUP BY s.clazz.name ORDER BY count(*) DESC LIMIT 10
```

5. **Retained vs. Shallow Heap:**
   - **Shallow heap**: memory consumed by the object itself (header + fields).
   - **Retained heap**: shallow heap + heap of all objects exclusively reachable through this object.
   - A `HashMap` with 1M entries: shallow ~48 bytes, retained ~500MB. The dominator tree shows retained heap — that's what you want.

### Step 5: Thread Dump for Stuck Allocations

```bash
jstack <pid> > /tmp/thread-dump-$(date +%s).txt

# Count threads
grep "^\"" /tmp/thread-dump-*.txt | wc -l
# Healthy service: < 500 threads
# Concerning: > 1000 threads

# Find threads blocked in allocation
grep -A 3 "java.lang.OutOfMemoryError" /tmp/thread-dump-*.txt

# Find threads stuck in GC
grep "VM Thread\|GC Thread\|Concurrent Mark" /tmp/thread-dump-*.txt | wc -l
```

### Step 6: async-profiler Allocation Profiling

For identifying allocation hot spots on a RUNNING process (no restart required):

```bash
# Download async-profiler
wget https://github.com/async-profiler/async-profiler/releases/download/v3.0/async-profiler-3.0-macos.zip

# Attach to running JVM and capture 60s allocation profile
./asprof -e alloc -d 60 -f /tmp/alloc-$(date +%s).html <pid>

# For production with minimal overhead (sample every 512KB allocated per thread)
./asprof -e alloc -d 60 --alloc 512k -f /tmp/alloc.html <pid>

# CPU profiling (to find what's consuming CPU during GC pressure)
./asprof -e cpu -d 60 -f /tmp/cpu.html <pid>
```

**Reading the flame graph:**
- The x-axis is allocation volume (not time). Wider = more allocation.
- Read from bottom (entry points) to top (allocation sites).
- Find the **widest frame near the top** — that is the direct allocation call site.
- Compare two profiles: before leak onset vs. during leak. The frame that grew is the culprit.

### Step 7: Correlate With Application Metrics

Check these metrics at the time of OOM:
- Request rate (was there a traffic spike?)
- Cache sizes (Caffeine/Guava cache hit ratio, eviction rate)
- Connection pool sizes (JDBC pool active connections)
- Kafka consumer lag (could indicate backed-up in-memory buffers)
- Session count (HTTP sessions, WebSocket connections)
- Upload/batch job activity (large in-memory processing)

### Step 8: Root Cause Categorization and Fix

See §Root Cause Reference below.

---

## Eclipse MAT — Production Workflow Walkthrough

**Scenario:** Service OOMing after 4 hours. Heap dump shows 4GB used. Dominator tree top entry: `java.util.HashMap` retaining 3.9GB.

```
1. Open dominator tree
2. Expand the HashMap entry → shows Map$Entry[] table
3. Expand the table → shows a sample of the entries
4. Right-click HashMap → "Path to GC Roots" → exclude weak/soft refs
   Result: com.example.CacheManager.userCache (static field)
           ↑ held by Class com.example.CacheManager
           ↑ held by ClassLoader

5. The static field userCache is a HashMap with no eviction policy
   Fix: Replace with Caffeine cache with maximumSize and expireAfterAccess
```

**MAT OQL to confirm:**
```sql
SELECT s.key.toString(), s.value.toString()
FROM OBJECTS s IN dominators(SELECT * FROM java.util.HashMap WHERE size() > 100000)
LIMIT 100
```

---

## async-profiler — Allocation Flame Graph Interpretation

```
Example flame graph for a service leaking memory:

Bottom: HTTP handler threads
  ├── HttpServlet.service()
  │   └── OrderController.getOrders()
  │       └── OrderRepository.findAll()          ← wide frame
  │           └── ResultSet.getObject()
  │               └── String.<init>              ← allocation site
  │
  └── CacheLoader.load()
      └── UserService.loadUser()
          └── new UserSession()                  ← wide frame
              └── Object.<init>

The two wide frames: OrderRepository.findAll() and UserService.loadUser()
Action: findAll() is loading ALL orders without pagination — fix with LIMIT
        UserSession is created but never invalidated — check TTL
```

---

## Root Cause Reference

### 1. Unbounded Cache

**Symptom:** Heap climbs steadily. MAT shows a Map or List retaining large retained heap via a static field.

```java
// WRONG: No eviction policy
private static final Map<String, Report> cache = new HashMap<>();

// FIX: Caffeine with bounded size and TTL
private static final Cache<String, Report> cache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(10))
    .build();
```

### 2. Event Listener / Callback Not Deregistered

**Symptom:** Memory grows proportional to number of lifecycle events (deploys, user logins).

```java
// WRONG: Register listener, never remove it
eventBus.register(new UserActivityListener(userId));
// Each UserActivityListener holds a reference to the userId context
// EventBus holds a reference to the listener → listener is never GC'd

// FIX: Weak references in the event bus, or explicit deregistration
eventBus.register(listener);
// ... later, on user logout:
eventBus.unregister(listener);
```

### 3. ThreadLocal Not Cleared on Tomcat Thread Pool

**Symptom:** Request N's data visible in request N+1 on the same thread. Memory climbs with number of requests served.

```java
// WRONG
private static final ThreadLocal<RequestContext> context = new ThreadLocal<>();

void handleRequest(Request req) {
    context.set(new RequestContext(req));
    // ... handle ...
    // Missing: context.remove()
}
// Tomcat thread pool reuses threads.
// Thread serves 1M requests → 1M RequestContext objects retained by the ThreadLocal

// FIX: Always call remove() in finally
void handleRequest(Request req) {
    try {
        context.set(new RequestContext(req));
        processRequest();
    } finally {
        context.remove();   // MUST be in finally
    }
}
```

### 4. Connection / ResultSet Leak

**Symptom:** Heap climbs slowly. MAT shows many `com.mysql.jdbc.ResultSet` or `org.postgresql.jdbc.PgResultSet` objects.

```java
// WRONG: ResultSet not closed if exception occurs
Connection conn = dataSource.getConnection();
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery(sql);
processRows(rs);  // throws exception → rs, stmt, conn never closed

// FIX: try-with-resources
try (Connection conn = dataSource.getConnection();
     Statement stmt = conn.createStatement();
     ResultSet rs = stmt.executeQuery(sql)) {
    processRows(rs);
}
// All three closed in reverse order automatically
```

### 5. Non-Static Inner Class Holding Outer Reference

**Symptom:** Long-lived objects (thread pool tasks, event handlers) retain large outer class instances.

```java
// WRONG: Anonymous Runnable captures 'this' (the service instance)
class DataService {
    private final byte[] largeBuffer = new byte[50_000_000];  // 50MB

    void startBackgroundJob() {
        executor.submit(new Runnable() {
            public void run() {
                // 'this' refers to the Runnable instance, but
                // the anonymous class holds an implicit reference to DataService.this
                processData();
            }
        });
    }
}
// If the Runnable stays in the executor queue, DataService (with 50MB buffer) is retained

// FIX: Use static inner class or extract to a top-level class
executor.submit(() -> processData(dataRef));  // lambda with explicit capture only
// OR static inner class with only the needed data passed in
```

### 6. ClassLoader / Metaspace Leak

**Symptom:** `OutOfMemoryError: Metaspace`. Grows over time with hot deploys or dynamic class loading.

```java
// Pattern: Dynamic ClassLoader created but never GC'd
// Each ClassLoader retains all classes it loaded
// Classes are retained as long as their ClassLoader is reachable

// Leak source: Static field holding ClassLoader (or object loaded by it)
private static Class<?> cachedClass = myClassLoader.loadClass("com.example.Plugin");
// cachedClass holds a reference to myClassLoader → ClassLoader never GC'd → all classes leaked

// FIX: Use WeakReference for dynamically loaded class references
// OR ensure ClassLoader is not reachable from any GC root when done
WeakReference<Class<?>> classRef = new WeakReference<>(
    myClassLoader.loadClass("com.example.Plugin"));
```

**Detecting Metaspace leak:**
```bash
# Check current Metaspace usage
jcmd <pid> VM.native_memory summary

# Output shows:
# Metaspace (reserved=512MB, committed=256MB)
#   Class (reserved=256MB, committed=64MB)
# If "committed" grows steadily → class loading leak
```

### 7. Off-Heap ByteBuffer Leak (Direct Buffer Memory)

**Symptom:** `OutOfMemoryError: Direct buffer memory`. Heap usage is fine, but native memory grows.

```java
// ByteBuffer.allocateDirect() allocates OUTSIDE the heap
ByteBuffer buf = ByteBuffer.allocateDirect(1024 * 1024);  // 1MB off-heap

// Direct buffers are cleaned up when the ByteBuffer object is GC'd
// AND the Cleaner runs. If the ByteBuffer object is never GC'd (leaked),
// the off-heap memory is never freed.

// Common in Netty: buf.retain() without a matching buf.release()
// Netty uses reference counting. Each retain() increments; each release() decrements.
// When count reaches 0, the direct memory is freed.
// Missing release() → direct memory accumulates.
```

**Detecting:**
```bash
# Check direct memory usage
jcmd <pid> VM.native_memory detail | grep "Direct Buffers"
# OR
-XX:NativeMemoryTracking=detail
jcmd <pid> VM.native_memory baseline
# ... wait 10 minutes ...
jcmd <pid> VM.native_memory summary.diff
```

---

## Metaspace OOM Specifically

**Why Metaspace replaced PermGen (Java 8):**
- PermGen was a fixed-size heap region (default 256MB max).
- Common cause of OOM in Java EE apps with frequent hot deploys.
- Metaspace uses native memory (no fixed upper bound by default) — grows until `MaxMetaspaceSize` or system memory.

**ClassLoader as GC root for loaded classes:**

```
ClassLoader (GC root)
  └── Class A
  └── Class B
  └── Class C
      └── static fields of Class C (these are NOT on the heap — they're in the class object)
```

As long as a `ClassLoader` is reachable from any GC root, all classes it loaded are retained in Metaspace. Classes are never unloaded individually — the entire `ClassLoader` must become unreachable.

**Setting a ceiling:**
```bash
-XX:MaxMetaspaceSize=512m
# Without this, Metaspace grows until OS memory is exhausted
# With it, OOM fires with the Metaspace message when limit is hit
```

---

## GC Tuning for Latency vs. Throughput

| GC | Target Use Case | Max Pause | Throughput |
|----|----------------|-----------|-----------|
| G1GC | Balanced — default for Java 9+ | Configurable (`MaxGCPauseMillis`) | High |
| ZGC | Ultra-low latency | < 1ms (Java 15+ concurrent) | Slightly lower |
| Shenandoah | Low latency | < 10ms | Moderate |
| ParallelGC | Batch jobs, max throughput | Seconds | Highest |

### G1GC Tuning

```bash
# Set pause target (G1 will attempt to stay under this)
-XX:MaxGCPauseMillis=100    # 100ms pause budget

# Heap region size (larger = fewer regions = less bookkeeping)
-XX:G1HeapRegionSize=16m    # default is auto-calculated from heap size

# For humongous allocations (> 50% of region size):
# These bypass G1's normal allocation path — increase region size if many large allocations
```

### Heap Sizing Heuristic

```
Heap size = 3 × live set size (minimum), 4× is comfortable

Measure live set: jstat -gc <pid> | look for OGC (Old Gen Capacity) after major GC
# or: -XX:+PrintGCDetails will show "Heap occupancy after full GC"

Example: Live set = 2GB after full GC → set -Xmx8g for comfortable headroom
```

### When to Use ZGC

```bash
-XX:+UseZGC

# Good for:
# - Services with latency SLAs < 5ms P99
# - Large heaps (> 32GB) where G1 pauses become unpredictable
# - Services that do large heap operations (sort/bulk load)

# Trade-off: ZGC uses more memory (requires ~20% overhead for forwarding pointers)
# and has slightly lower throughput for CPU-bound workloads
```

---

## Interview Q&A

### Q1 `[Principal]` Heap dump shows 4GB retained in `HashMap$Entry` objects. Walk through your MAT investigation step by step.

**Answer:**

```
Step 1: Open MAT, check Leak Suspects report first.
  → Likely already points to the HashMap. Note the class name of the retaining object.

Step 2: Open Dominator Tree.
  → Sort by Retained Heap descending.
  → Find the single HashMap at the top (3.9GB retained from 4GB total → it's the culprit).

Step 3: Right-click the HashMap → "Path to GC Roots" → "Exclude weak/soft/phantom references".
  → This shows the chain from GC root to the HashMap.
  → Typical results:
    (a) A static field: ClassLoader → MyClass → MyClass.cache (static HashMap)
    (b) A thread's stack frame: Thread "http-thread-23" → HttpHandler.handle() → local variable Map
    (c) A ThreadLocal: Thread → ThreadLocalMap.Entry[] → the HashMap

Step 4: For case (a) — static field cache:
  → OQL query: SELECT * FROM java.util.HashMap WHERE size() > 10000
  → Inspect key-value types: e.g., String keys, UserSession values
  → Check if values have TTL: if no expiry → unbounded cache
  → Fix: add Caffeine maximumSize() + expireAfterAccess()

Step 5: Confirm fix by comparing heap dump before and after.
  → New map should show bounded size, regular eviction in GC logs.
```

**Key MAT technique: "Exclude weak/soft refs"** — SoftReference and WeakReference are intentional weak-retention mechanisms. If the HashMap is ONLY held via a SoftReference, it will be GC'd under memory pressure — that's not a leak. We exclude them to find only the strong-reference paths that truly prevent GC.

---

### Q2 `[Principal]` Difference between `GC overhead limit exceeded` and `Java heap space`. Which indicates a leak vs. undersizing?

**Answer:**

**`Java heap space`:** Fires when an allocation request cannot be satisfied — the heap is at maximum capacity. Either:
- The heap is genuinely too small for the working set (undersizing), OR
- A memory leak has filled the heap over time (leak).

Both have the same root cause (full heap) but different trajectories in GC logs.

**`GC overhead limit exceeded`:** Fires when the JVM detects it spent >98% of elapsed time across the last 5 full GCs and recovered <2% of heap. The heap is not necessarily completely full — but GC is spinning without progress. This fires **before** `Java heap space`.

**Which indicates which:**

- `GC overhead limit exceeded` almost always indicates a **slow memory leak** that has filled the heap to 98%+ capacity. The leak is slow enough that small GC cycles recover some memory, but the trend is consistently upward.
- `Java heap space` from a single sudden allocation (e.g., `new byte[2GB]`) indicates **undersizing** or a code bug (allocating more than the heap can hold).
- `Java heap space` after a steady climbing GC log indicates a **leak**.

**Debugging approach:** Both require the same investigation (heap dump + MAT dominator tree). The GC log pattern is the key differentiator:
- Steadily climbing post-GC occupancy → leak → find the retaining root.
- Flat high post-GC occupancy → undersizing → increase heap or reduce working set.

---

### Q3 `[Principal]` Explain the ThreadLocal leak on Tomcat. What is the exact mechanism, and what is the fix?

**Answer:**

**Mechanism:**

Tomcat uses a thread pool (default 200 threads). Threads are never destroyed between requests — they are reused.

`ThreadLocal` storage is held in the `Thread` object itself: `Thread.threadLocals = ThreadLocalMap`. Each `ThreadLocal.set(value)` creates an entry in the current thread's map. The entry is a `WeakReference` to the `ThreadLocal` key but a **strong reference** to the value.

```
Thread "http-thread-42" (lives for the JVM lifetime)
  └── threadLocals: ThreadLocalMap
        └── Entry[k=WeakRef(MY_THREAD_LOCAL), v=RequestContext(requestId="req-001")]
```

If `ThreadLocal.remove()` is never called:
1. Request 1 sets `context.set(new RequestContext("req-001"))` on thread-42.
2. Request 1 completes. Thread-42 returns to pool.
3. Request 2 arrives on thread-42. `context.get()` returns `RequestContext("req-001")` — previous request's data!
4. If the `RequestContext` holds a reference to a large object graph (DB session, user data), that object graph is retained for the lifetime of thread-42 — effectively forever.
5. 200 threads × large RequestContext = significant heap pressure.

**Fix — always in `finally`:**

```java
private static final ThreadLocal<RequestContext> CTX = new ThreadLocal<>();

void doFilter(HttpServletRequest req, ...) {
    try {
        CTX.set(new RequestContext(req));
        chain.doFilter(req, resp);
    } finally {
        CTX.remove();   // Mandatory. Without finally, an exception skips this.
    }
}
```

**Spring's `RequestContextHolder`** does this correctly. If using Spring MVC, prefer `RequestContextHolder.getRequestAttributes()` over custom `ThreadLocal`.

**Secondary risk:** If the `ThreadLocal` variable itself becomes unreachable (but wasn't `remove()`d), the entry's key (WeakReference) is cleared by GC but the value remains in the `ThreadLocalMap` — a "stale entry." The JVM cleans stale entries lazily during subsequent `get()`/`set()` calls, but this cleanup is not guaranteed without continued activity on the thread.

---

### Q4 `[Principal]` How do you use async-profiler allocation mode on a production JVM without restarting it?

**Answer:**

async-profiler uses the Java Attach API and `AsyncGetCallTrace` JVMTI (or perf_events on Linux) — no restart required.

**Command:**
```bash
./asprof -e alloc -d 60 --alloc 512k -f /tmp/alloc-$(date +%s).html <pid>

# Options:
# -e alloc       — allocation profiling mode
# -d 60          — capture for 60 seconds
# --alloc 512k   — sample every 512KB allocated per thread (reduces overhead)
# -f out.html    — output as interactive flame graph HTML
# <pid>          — JVM process ID
```

**What it records:** TLAB (Thread-Local Allocation Buffer) exhaustion events. Each time a thread's TLAB fills up, the profiler captures the stack trace and accumulates allocation size by stack. Samples are `--alloc`-bytes apart.

**Reading the output:**
- Open `alloc.html` in a browser.
- X-axis = proportional allocation volume. Wider = more bytes allocated.
- Y-axis = call stack depth. Top = allocation site. Bottom = entry point.
- Find the **widest frame near the top** — that's where the most bytes are being allocated.
- Hover for exact values.

**Typical finding:**
```
Wide frame: OrderService.findAll() → 2.1GB/min allocated
  ↳ Cause: SELECT * loading all orders without LIMIT
  ↳ Fix: Paginate the query; add LIMIT/OFFSET or keyset pagination
```

**Production safety:** async-profiler has ~1–3% CPU overhead in alloc mode with `--alloc 512k`. Acceptable for short profiling windows (60–120s). Avoid alloc-mode profiling during peak load on extremely latency-sensitive paths.

---

### Q5 `[Principal]` Your service is throwing `Unable to create new native thread`. Heap is at 40%. Walk through the diagnosis.

**Answer:**

This is NOT a heap issue. It's a **thread limit** — either per-process or system-wide.

**Step 1: Confirm thread count**
```bash
# Count threads in JVM
jstack <pid> | grep "^\"" | wc -l

# Or via /proc (Linux)
ls /proc/<pid>/task | wc -l

# Healthy microservice: 100–500 threads
# Problematic: 1000+, critical: approaching kernel thread-max
```

**Step 2: Check OS limits**
```bash
ulimit -u                              # max user processes (= max threads)
cat /proc/sys/kernel/threads-max       # system-wide thread limit
cat /proc/sys/vm/max_map_count         # each thread needs VMAs for its stack
```

**Step 3: Find the thread creation source**
```bash
# Look at thread names in jstack
jstack <pid> | grep "^\"" | sort | uniq -c | sort -rn | head -20
# Common culprits:
#   "pool-X-thread-Y"      → unconfigured ThreadPoolExecutor (unbounded)
#   "http-nio-"            → Tomcat thread pool (check maxThreads)
#   "kafka-consumer-"      → too many consumer groups or partitions
#   "grpc-default-"        → gRPC channel per request
```

**Common root causes:**
1. `Executors.newCachedThreadPool()` with no bound — creates a new thread for every task if existing threads are busy. Under load spike: thousands of threads in seconds.
2. `new Thread(r).start()` in a loop — no pool at all.
3. Each gRPC/HTTP client call creating its own connection pool with dedicated threads.

**Fix:**
```java
// WRONG: unbounded
ExecutorService exec = Executors.newCachedThreadPool();

// RIGHT: bounded thread pool
ExecutorService exec = new ThreadPoolExecutor(
    10,                             // core threads
    100,                            // max threads
    60L, TimeUnit.SECONDS,          // idle thread timeout
    new LinkedBlockingQueue<>(1000), // bounded queue
    new ThreadPoolExecutor.CallerRunsPolicy()  // backpressure
);
```

For I/O-bound services on Java 21+: virtual threads eliminate the OS thread limit concern — thousands of virtual threads run on a handful of carrier threads.

---

*See also:* [03-concurrency-and-loom.md](03-concurrency-and-loom.md) for ThreadLocal vs. ScopedValue with virtual threads | [04-data-structures-internals.md](04-data-structures-internals.md) for ConcurrentHashMap and LongAdder internals
