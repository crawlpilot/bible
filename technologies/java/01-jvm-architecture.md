# 01 — JVM Architecture

## JVM Memory Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              JVM Process                                 │
│                                                                          │
│  ┌──────────────────────────────────────────────┐                       │
│  │                  Heap                         │                       │
│  │  ┌──────────────────────┐  ┌───────────────┐ │                       │
│  │  │    Young Generation   │  │ Old Generation│ │                       │
│  │  │  ┌──────┬──────────┐  │  │  (Tenured)   │ │                       │
│  │  │  │ Eden │ Survivor │  │  │              │ │                       │
│  │  │  │      │  S0 │ S1 │  │  │              │ │                       │
│  │  │  └──────┴──────────┘  │  │              │ │                       │
│  │  └──────────────────────┘  └───────────────┘ │                       │
│  └──────────────────────────────────────────────┘                       │
│                                                                          │
│  ┌──────────────┐  ┌───────────────────┐  ┌───────────────────────────┐ │
│  │  Metaspace   │  │  Code Cache       │  │  Off-Heap / Direct Memory │ │
│  │ (class defs) │  │ (JIT-compiled     │  │ (NIO DirectByteBuffer,    │ │
│  │              │  │  native code)     │  │  Netty, Kafka page cache) │ │
│  └──────────────┘  └───────────────────┘  └───────────────────────────┘ │
│                                                                          │
│  Per-Thread:  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│               │  Stack       │ │  Stack       │ │  Stack       │       │
│               │  (frames,    │ │              │ │              │       │
│               │  local vars) │ │              │ │              │       │
│               └──────────────┘ └──────────────┘ └──────────────┘       │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Heap Regions in Detail

### Young Generation

New objects are allocated here. It is small (10–30% of total heap) and collected frequently (Minor GC / Young GC).

```
Eden (80%) → where new objects are born
Survivor S0 / S1 (10% each) → objects that survived at least one GC
```

**TLAB (Thread-Local Allocation Buffer)**:
Each thread has a private section of Eden (~512KB). Thread allocates into its TLAB without synchronization — `new Object()` is just a pointer bump, ~1–5ns. When TLAB is full, the thread requests a new one from Eden (synchronized). This is why Java allocation is very fast despite being on a GC-managed heap.

```java
// This is essentially what new does internally:
// ptr = tlab.top
// tlab.top += objectSize
// return ptr
// → No lock, no malloc overhead, just a pointer increment
```

**Minor GC mechanics**:
1. Eden fills up → Minor GC triggered
2. Live objects in Eden + S0 copied to S1 (copying collection — no fragmentation)
3. Objects exceeding age threshold (default 15) promoted to Old Gen
4. Eden + S0 wiped — no per-object free, just reset pointer (instantaneous)

**Promotion**: Young GC is fast (milliseconds) but promotion pressure — too many objects surviving long enough to reach Old Gen — is the root cause of most Full GC problems.

### Old Generation (Tenured)

Long-lived objects. Much larger (70–90% of heap). Collected infrequently (Major/Full GC). Full GC is stop-the-world in most collectors and takes 100ms to minutes depending on heap size and live data.

**Humongous objects** (G1): objects > 50% of a G1 region size go directly to Old Gen, bypassing Eden entirely. This is a common source of unexpected Full GC.

### Metaspace (Java 8+, replaced PermGen)

Stores:
- Class definitions (bytecode, methods, field descriptors)
- ClassLoader metadata
- JIT-compiled class data

**Not on the heap** — lives in native memory (off-heap). No explicit size limit by default (`-XX:MaxMetaspaceSize` to cap). Common leak cause: dynamic class loading (reflection-heavy frameworks, OSGi, Hibernate validators) that creates new ClassLoaders but never unloads them.

```
Diagnosis: jcmd <pid> VM.classloader_stats
Symptom: java.lang.OutOfMemoryError: Metaspace
```

### Code Cache

JIT-compiled native code lives here. Default size: 240MB (`-XX:ReservedCodeCacheSize`). When full, JVM stops compiling (falls back to interpreted mode) → sudden latency spike. Monitor with `-XX:+PrintCodeCache`.

---

## Class Loading

```
Bootstrap ClassLoader (JVM native, loads rt.jar / JDK modules)
    └── Extension / Platform ClassLoader (javax.*, jdk.*)
          └── Application ClassLoader (classpath)
                └── Custom ClassLoaders (web apps, OSGi, plugins)
```

**Parent-delegation model**: before loading a class, a ClassLoader asks its parent first. This prevents user code from shadowing `java.lang.String`. Breaking parent delegation (e.g., OSGi, JNDI, JDBC) is the source of most `ClassCastException` and `ClassNotFoundException` across classloader boundaries.

**Class unloading**: a class is only unloaded when its ClassLoader is garbage collected AND there are no live references to any class it loaded. In long-lived servers, custom ClassLoaders (one per web app in Tomcat, one per plugin reload) accumulate in Metaspace if not properly dereferenced.

---

## JIT Compilation — Two-Tier

The JVM starts interpreted (fast startup, no profiling overhead) and progressively compiles hot code to native:

```
Interpreted mode (Tier 0)
    │ 1,000 invocations
    ▼
C1 compiler — Tier 1–3 (client compiler)
  Fast compilation, moderate optimization
  Produces profiling instrumentation
    │ 10,000 invocations (default -XX:CompileThreshold)
    ▼
C2 compiler — Tier 4 (server compiler)
  Aggressive optimization: inlining, loop unrolling,
  escape analysis, scalar replacement, vectorization
  Compilation takes longer but produces optimal native code
```

### Key C2 Optimizations

**Inlining**: the most important optimization. A call to `list.size()` is replaced by the inline `return this.size` at the call site — eliminates method dispatch overhead and enables further optimizations.

```java
// Source
for (int i = 0; i < list.size(); i++) { ... }

// After inlining + hoisting:
int $temp = list.size;  // hoisted out of loop
for (int i = 0; i < $temp; i++) { ... }
```

**Escape Analysis**: determines if an object escapes the current method/thread. Non-escaping objects can be allocated on the stack (no GC pressure) or have their fields scalar-replaced (no object at all).

```java
// This Point object may never be heap-allocated:
void compute() {
    Point p = new Point(x, y);  // escape analysis: p doesn't escape
    return p.x + p.y;           // → JIT: just use x, y directly on stack
}
```

**Deoptimization**: C2 makes speculative optimizations (e.g., assume a virtual call always goes to subclass A). If assumption becomes invalid (class B loaded), JIT **deoptimizes** — reverts to interpreted mode, recompiles without the speculative assumption. Visible as: `DeoptimizationEvent` in JFR; sudden latency spike; `Uncommon Trap` in `-XX:+PrintCompilation` output.

### GraalVM Native Image

AOT (Ahead-of-Time) compilation — entire application compiled to native binary at build time. No JVM, no JIT warmup. Used by: Quarkus, Micronaut. Trade-off: fast startup (<100ms) and low memory vs no JIT optimization after warmup, limited reflection, longer build times.

---

## Safepoints

The JVM cannot perform GC while arbitrary bytecode is running — it needs all threads to be at a **safepoint**: a position in the bytecode where all object references are known and the thread's state is consistent.

**How safepoints work**:
1. JVM sets a "safepoint requested" flag
2. JVM threads check this flag at: method return, back-edge of loop (every N iterations), certain JNI transitions
3. Thread reaches a safepoint → suspends itself (parks)
4. JVM waits for ALL threads to reach a safepoint → "Time To Safepoint" (TTSP)
5. JVM performs the STW operation (GC, deoptimization, class redefinition)
6. All threads resume

**TTSP problems**: a thread in a tight counted loop (`for (int i = 0; i < 1_000_000; i++)`) only reaches a safepoint at the back-edge — which the JIT may optimize away. This can delay a safepoint for 100ms+ while other threads wait. Use `-XX:+PrintSafepointStatistics` (JDK < 17) or JFR `SafepointBegin` events to diagnose.

```java
// This can delay safepoints — JIT may eliminate back-edge safepoint poll
for (int i = 0; i < Integer.MAX_VALUE; i++) {
    // no method calls, no allocations — pure computation
}

// Fix: add a method call or use a while loop with explicit yield
for (int i = 0; i < Integer.MAX_VALUE; i++) {
    if (i % 1_000_000 == 0) Thread.yield();  // safepoint opportunity
}
```

---

## Object Memory Layout

Every Java object on the heap:

```
┌─────────────────────────────┐
│  Mark Word (8 bytes)         │  GC age, identity hashCode, lock state, GC mark bits
│  Klass Pointer (4/8 bytes)   │  pointer to class metadata (4 bytes with CompressedOops)
│  [Array length (4 bytes)]    │  only for arrays
│  Fields...                   │  instance fields, aligned to 8 bytes
└─────────────────────────────┘
```

**Object overhead**: minimum 16 bytes per object. An `Integer` wrapping an `int` costs 16 bytes instead of 4. For a `List<Integer>` of 1M elements: 1M × 16 bytes (Integer objects) + 1M × 4 bytes (array references) = ~20MB vs 4MB for `int[]`. This is why primitive arrays beat boxed collections for memory-sensitive code.

**Compressed OOPs** (`-XX:+UseCompressedOops`, default on ≤ 32GB heap): object references encoded in 32 bits instead of 64 bits → ~30% memory saving. Lost when heap > 32GB — this is why heap size 31GB is often better than 33GB.

---

## FAANG Interview Callouts

- **"Why does your latency spike every 60 seconds?"** → Full GC. Check `-Xmx` vs live set size ratio; if Old Gen fills regularly, increase heap or tune GC. Common cause: large batch allocation promoting objects to Old Gen.
- **"How does Java allocate objects so fast?"** → TLAB: each thread has a private buffer in Eden; allocation is pointer bump (no lock). GC overhead is amortized across many allocations.
- **"What happens when you call new in a tight loop?"** → TLAB fills → new TLAB allocated from Eden → Eden fills → Minor GC. If objects are short-lived, this is fine; if they survive GC, promotion pressure → Full GC.
- **"Why does increasing heap sometimes make latency worse?"** → Larger heap = longer Full GC pauses (more data to scan). Solution: tune GC algorithm (G1/ZGC) rather than heap size.
- **"What is the difference between Metaspace OOM and Heap OOM?"** → Heap OOM: live objects > `-Xmx`. Metaspace OOM: ClassLoader leak — class metadata accumulating. Fix is different: heap → tune GC/increase size; metaspace → fix ClassLoader leak.
