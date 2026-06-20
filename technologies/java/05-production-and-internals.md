# 05 — Production Patterns, Real Incidents, and FAANG Interview Framing

## Real-World GC Incidents at Scale

### Netflix: G1GC Full GC from Humongous Allocations

**Context**: Netflix's Hollow data loading library loads reference datasets (product catalogs, movie metadata) as large byte arrays. When loading a 400MB dataset into a JVM with `G1HeapRegionSize=16m`, the 400MB byte array is a humongous object (> 8MB = 50% of region size). This bypasses Eden entirely and lands in Old Gen — consuming 50% of a 1GB Old Gen in one allocation.

**Symptom**: every catalog refresh triggered a Full GC as the humongous allocation pushed Old Gen occupancy over the IHOP threshold immediately.

**Fix**: 
1. Increased `G1HeapRegionSize=32m` to raise the humongous threshold to 16MB
2. For objects that still exceeded this: used off-heap (`DirectByteBuffer`) for the data store — zero GC pressure for the large dataset, only the index lived on heap

**Lesson**: G1 humongous object handling is the most common surprise when migrating from CMS to G1. Always check object sizes vs `G1HeapRegionSize`.

---

### LinkedIn: ZGC Migration for Feed Service

**Context**: LinkedIn's feed service has a strict p99 latency SLA of 50ms. Their 16GB heap on G1GC consistently produced p99 pauses of 150–300ms during Mixed GC phases, violating the SLA on every heavy collection cycle.

**Migration**:
```
G1GC: -Xmx16g -XX:MaxGCPauseMillis=50 → actual p99 pauses 150–300ms
ZGC:  -Xmx20g -XX:+UseZGC             → actual p99 pauses 1–3ms
      (extra heap headroom for concurrent to-space reservation)
```

**Throughput cost**: ~8% lower request throughput due to load barrier overhead (every heap object read pays ~3ns overhead). At feed service scale: acceptable for the latency win.

**Gotcha encountered**: ZGC needs more heap headroom because concurrent relocation requires both from-space and to-space simultaneously. Increasing heap from 16GB to 20GB was necessary to avoid `OutOfMemoryError: Java heap space` from allocation stalls during concurrent GC.

---

### Uber: Thread Starvation from Blocking in Virtual Thread Pool

**Context** (post-JDK 21 migration): Uber's trip dispatch service migrated from a 200-thread `ThreadPoolExecutor` to virtual threads (`newVirtualThreadPerTaskExecutor()`). Immediately saw performance regression: p99 latency doubled.

**Root cause**: the service used several `synchronized` blocks around database access (legacy code, not yet migrated). Every virtual thread blocked on I/O inside a `synchronized` block was **pinned** to its carrier thread — converting virtual thread I/O blocking back to OS thread blocking. With 8 carrier threads and each pinned during 50ms DB calls: max effective concurrency dropped from thousands to ~160 (8 threads × 20 calls/s each).

**Diagnosis**: `-Djdk.tracePinnedThreads=full` logged every pinning event with stack trace.

**Fix**: replaced `synchronized` blocks in the critical path with `ReentrantLock`. After migration: virtual threads unmounted during DB I/O → 8 carrier threads handled thousands of concurrent virtual threads correctly.

**Lesson**: virtual threads are not magic — `synchronized` blocks pin. Audit all `synchronized` usage before migrating to virtual threads.

---

### Amazon: Thread Pool Starvation Deadlock

**Context**: an order processing service used a single shared `ThreadPoolExecutor` for all async work. A refactor added a feature where a submitted task itself submitted another task to the same pool and called `.get()` on it.

```java
// Pool: 50 threads
executor.submit(() -> {
    // Task A — submitted by request handler
    Data raw = fetchFromDb();
    // Task A submits Task B to the same pool and blocks
    Future<Data> enriched = executor.submit(() -> enrich(raw));
    return enriched.get();  // DEADLOCK when all 50 threads are in this wait
});
```

**Deadlock**: 50 requests filled the pool with Task A. All 50 Task A's tried to submit Task B and called `.get()`. No threads available to run Task B. All 50 threads blocked indefinitely. Service appeared hung; all health checks timing out.

**Fix**: Task B ran on a separate `enrichmentPool`. Alternatively, Task A was refactored to use `thenCompose()` instead of `.get()` to avoid blocking a thread.

**Lesson**: thread starvation deadlock is silent and not detected by `jstack` as a Java-level deadlock (all threads WAITING, not BLOCKED — no lock cycle). Diagnose by looking at what all threads are waiting for.

---

## JVM Internals Interviewers Ask About

### How does `synchronized` work internally?

```java
synchronized(obj) { ... }
```

Compiles to `MONITORENTER` / `MONITOREXIT` bytecode instructions. The JVM implements them via the object's **mark word** (part of every object header):

```
Mark word states:
  Unlocked:        identity hashCode (25 bits) | age (4 bits) | 00
  Biased:          thread ID (54 bits) | epoch | age | 01
  Thin lock:       thread stack pointer | 00 (lock record in stack frame)
  Inflated (fat):  pointer to ObjectMonitor | 10
  Marked for GC:   11
```

**Lock escalation** (JVM optimizes light locks to heavier ones only as contention grows):
1. **Biased locking** (JDK < 15, deprecated in 15, removed in 21): first locker writes its thread ID into mark word. Subsequent locks by the same thread: just check thread ID (no CAS) — zero overhead for single-threaded synchronized. Revocation cost when another thread tries to lock is high (safepoint).
2. **Thin lock**: CAS the stack frame pointer into mark word. Works for short uncontended critical sections.
3. **Fat lock** (inflated `ObjectMonitor`): kernel mutex, full blocking queue for waiting threads. Used when threads actually contend.

### How does volatile prevent reordering?

`volatile` inserts **memory barriers**:
- **LoadLoad** barrier before a volatile read: previous reads complete before this read
- **LoadStore** barrier before a volatile read: previous reads complete before subsequent writes  
- **StoreStore** barrier before a volatile write: all prior writes are flushed before this write
- **StoreLoad** barrier after a volatile write: the write is visible before any subsequent reads

On x86/x64, `StoreLoad` is the only expensive barrier (requires `MFENCE` or lock-prefix). On ARM/Power, all four barriers map to explicit instructions.

### How does `HashMap` work? (Always asked)

```
HashMap<K,V>:
  - Backing array of Node<K,V>[] (power of 2 size)
  - Hash index = hash(key) & (capacity - 1)  [fast bitmask instead of modulo]
  - Collision: linked list at bucket
  - JDK 8+: list → red-black tree when bucket depth > 8 (treeify threshold)
             tree → list when depth < 6 (untreeify threshold)
  - Load factor: 0.75 default → resize (double array) when 75% full
  - Resize: rehash all entries into new array (O(n) amortized O(1) per put)

Performance:
  - Average O(1) get/put
  - Worst case O(log n) with treeified buckets
  - Resize is O(n) — avoid by pre-sizing: new HashMap<>(expectedSize / 0.75 + 1)

Thread safety:
  - HashMap: NOT thread-safe (resize corrupts structure under concurrent modification)
  - ConcurrentHashMap: thread-safe; fine-grained locks (Java 8: CAS + synchronized per bucket)
  - Hashtable: legacy; synchronized on entire map (performance poor)
```

### How does `String.intern()` work? Why avoid it?

```
String pool (interning): JVM maintains a global table of String literals.
  String s1 = "hello";             // from pool
  String s2 = new String("hello"); // new heap object
  String s3 = s2.intern();         // returns pooled "hello"

  s1 == s3 → true  (same pool reference)
  s1 == s2 → false (different objects)

Problems at scale:
  - String pool is global (static) — grows unboundedly if you intern user-generated strings
  - Before JDK 7: pool lived in PermGen (limited size)
  - After JDK 7: pool lives on heap but still global — GC pressure from millions of interned strings
  - HashCode collision in pool degrades to O(n) lookup

Best practice: don't intern at all. Use an explicit bounded cache (Guava Cache, Caffeine)
for deduplication if needed.
```

---

## Java Performance Patterns for Principal Engineers

### Pattern 1: Off-Heap Storage for Large Working Sets

Services like Cassandra (MemTable), Kafka (page cache relying on OS), and Elasticsearch (Lucene off-heap) avoid GC pressure for large datasets by using:

```java
// Allocate off-heap — not managed by GC
ByteBuffer buf = ByteBuffer.allocateDirect(100 * 1024 * 1024);  // 100MB off-heap
// Freed when: ByteBuffer GC'd (unreachable) + Cleaner.clean() callback, OR explicit Unsafe.freeMemory()

// Netty PooledByteBufAllocator: pools off-heap buffers (PooledDirectByteBuf)
// - Avoids per-request ByteBuffer allocation (GC pressure)
// - Thread-local arenas minimize synchronization
ByteBufAllocator allocator = PooledByteBufAllocator.DEFAULT;
ByteBuf buf2 = allocator.directBuffer(4096);
// ...
buf2.release();  // return to pool
```

### Pattern 2: String Table vs Encoding

```java
// BAD: string concatenation in hot path (creates intermediate Strings)
String result = "";
for (Item item : items) {
    result += item.name() + "," + item.price();  // N² allocations
}

// GOOD: StringBuilder
StringBuilder sb = new StringBuilder(items.size() * 32);
for (Item item : items) {
    sb.append(item.name()).append(',').append(item.price());
}
String result = sb.toString();

// BETTER for JSON/binary: write directly to OutputStream (no intermediate String)
JsonGenerator gen = factory.createGenerator(outputStream);
gen.writeStartObject();
for (Item item : items) { gen.writeStringField(item.name(), item.price().toString()); }
gen.writeEndObject();
gen.flush();
```

### Pattern 3: Reduce Object Allocation — Value-Based Classes

```java
// Java 14+: Records (immutable, value-based)
public record Point(double x, double y) {}

// Java 21+: Value Objects (Valhalla project — in preview)
// Stored inline in arrays — no object header overhead
// int[] feels but for custom types: value class Point = { double x; double y; }
// Future: Point[] → laid out as [x1,y1,x2,y2,...] not [ptr1,ptr2,...] → no indirection

// Current workaround: struct-of-arrays instead of array-of-structs
// For 1M points:
double[] xs = new double[1_000_000];  // 8MB, cache-friendly
double[] ys = new double[1_000_000];  // 8MB, cache-friendly
// vs
Point[] points = new Point[1_000_000];  // 8MB refs + 1M × 24B objects = 32MB, cache-unfriendly
```

### Pattern 4: ThreadLocal for Per-Thread Reuse

```java
// Reuse expensive-to-create objects without synchronization
private static final ThreadLocal<MessageDigest> SHA256 = ThreadLocal.withInitial(() -> {
    try { return MessageDigest.getInstance("SHA-256"); }
    catch (NoSuchAlgorithmException e) { throw new RuntimeException(e); }
});

public byte[] hash(byte[] input) {
    MessageDigest md = SHA256.get();
    md.reset();
    return md.digest(input);
}

// CRITICAL: always remove() ThreadLocal in thread pools
// Thread pool threads are reused — ThreadLocal state persists across requests
try {
    // process request using SHA256.get()
} finally {
    SHA256.remove();  // prevent request data leaking to next request on same thread
}
```

### Pattern 5: Benchmark Before Optimizing — JMH

```java
@State(Scope.Thread)
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
public class StringBenchmark {

    private String[] words = {"apple", "banana", "cherry", "date"};

    @Benchmark
    public String concatenation() {
        String s = "";
        for (String w : words) s += w;
        return s;
    }

    @Benchmark
    public String stringBuilder() {
        StringBuilder sb = new StringBuilder();
        for (String w : words) sb.append(w);
        return sb.toString();
    }
}
// JMH handles JVM warmup, prevents dead code elimination, measures steady-state performance
// Run: java -jar benchmarks.jar -wi 5 -i 10 -f 2  (5 warmup, 10 measure, 2 forks)
```

---

## FAANG System Design: Java-Specific Design Decisions

### High-Throughput Service Architecture

```
Service: 50K RPS, p99 < 10ms, 16GB container

Component selections:
  Framework:     Netty for I/O (non-blocking, zero-copy)
                 OR Spring WebFlux (reactive)
                 OR Spring Boot 3.2 + Virtual Threads (simpler, same throughput)
  
  Serialization: Jackson with streaming API (JsonParser/JsonGenerator, no intermediate objects)
                 OR Protobuf (binary, ~5× smaller, ~10× faster serialize/deserialize)
                 NOT Jackson ObjectMapper with @JsonProperty everywhere (reflection overhead)
  
  DB client:     R2DBC (reactive, non-blocking) if using reactive stack
                 OR JDBC + virtual threads + HikariCP if using virtual thread stack
  
  GC:            ZGC with -Xmx12g (75% of 16GB), -XX:SoftMaxHeapSize=10g
                 → < 1ms GC pauses; request p99 stays under 10ms
  
  Caching:       Caffeine in-process cache (lock-free, high performance)
                 NOT HashMap (not thread-safe, no eviction)
                 NOT ConcurrentHashMap (no TTL/LRU eviction)
```

### Memory-Efficient Data Pipeline

```
Pipeline: process 100GB of event data in a 16GB JVM

Option A: Load all into heap
  → OOM — doesn't fit

Option B: Streaming processing with lazy evaluation
  Files.lines(path)           // lazy — reads line by line, O(1) memory
      .parallel()              // ForkJoinPool for parallelism
      .filter(this::isValid)
      .map(this::parse)
      .forEach(this::process);
  // Memory: ~10MB for buffers + pipeline state

Option C: Off-heap memory-mapped files
  FileChannel channel = FileChannel.open(path, READ);
  MappedByteBuffer buffer = channel.map(MAP_SHARED, 0, channel.size());
  // OS manages paging — 100GB file, only hot pages in RAM
  // Zero-copy: no data copied from kernel to JVM heap

Best choice: Option B for transformed data; Option C for scan-heavy analytics
```

---

## Interview Preparation: Common Principal-Level Java Questions

| Question | What They're Testing | Key Answer Points |
|----------|---------------------|------------------|
| "GC pauses spiking p99 to 500ms on G1GC. What do you do?" | GC diagnosis methodology | GC logs → identify Full GC or Mixed GC → root cause (IHOP, humongous allocs, allocation rate) → targeted fix |
| "When would you choose ZGC over G1GC?" | GC trade-off reasoning | Latency < 10ms required, heap > 32GB, or can't tune G1 to meet SLA. Cost: ~10% throughput, more heap headroom |
| "How does Java 21 Virtual Threads change your architecture?" | Modern Java knowledge | Removes thread-per-request bottleneck. Keep synchronous code style. Watch for `synchronized` pinning. Not magic — CPU-bound work still needs bounded pools |
| "What's wrong with `Executors.newCachedThreadPool()` in production?" | Thread pool internals | Unbounded thread creation (`MAX_INT` max) → OOM under load. Always use explicit `ThreadPoolExecutor` with bounded queue |
| "How would you implement a high-performance in-memory cache?" | Concurrency + GC awareness | Caffeine (W-TinyLFU algorithm, lock-free reads). Alternative: off-heap (Chronicle Map) for large datasets to avoid GC. Consider TTL, max-size, eviction policy |
| "Your service has 16GB heap but OOMs with 80% heap free. Why?" | JVM memory model | Off-heap OOM: Metaspace (ClassLoader leak), DirectByteBuffer (NIO/Netty), thread stacks, Code Cache. Use `NativeMemoryTracking` to diagnose |
| "How do you prevent a ThreadLocal from causing a memory leak?" | Concurrency gotchas | ThreadLocal.remove() in `finally` block. Thread pool reuses threads — ThreadLocal persists between requests unless explicitly removed |
| "Design a distributed rate limiter in Java." | System design + Java implementation | Redis Lua script (atomic), token bucket algorithm, local cache (Caffeine) to reduce Redis calls. See Rate Limiter pattern |

---

## Quick-Reference: Java Versions Feature Timeline

| Java Version | Key Feature for Principal Engineers |
|-------------|-------------------------------------|
| Java 8 | Lambda, Stream API, CompletableFuture, G1GC improved, Default interface methods |
| Java 9 | G1GC default, Module system (Jigsaw) |
| Java 11 | ZGC (experimental), `var` in lambdas, HTTP Client API, LTS |
| Java 14 | Records (preview), Switch expressions |
| Java 15 | ZGC production-ready, Sealed classes (preview) |
| Java 17 | Sealed classes GA, Pattern matching instanceof, LTS |
| Java 21 | Virtual Threads (Project Loom) GA, Sequenced Collections, ZGC Generational, LTS |
| Java 25 | Project Valhalla (Value Objects — inline types for zero-overhead primitives) |
