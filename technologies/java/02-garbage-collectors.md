# 02 — Garbage Collectors: When to Use Which One

## The Core Trade-off: Throughput vs Latency vs Memory

Every GC algorithm makes a three-way trade-off:

| Axis | Definition | Measured By |
|------|-----------|-------------|
| **Throughput** | Fraction of CPU time not spent on GC | `(1 - GC_CPU_time / total_CPU_time)` |
| **Latency** | Longest pause an application thread experiences | p99/p999 pause duration |
| **Memory Footprint** | Extra memory needed by the GC itself (card tables, remembered sets, marking bitmaps) | Heap overhead %, GC metadata size |

No GC wins on all three. Each algorithm picks a point on this triangle.

---

## GC Evolution Timeline

```
Java 1.0   Serial GC         — single-threaded STW, still default for small heaps
Java 1.4   Parallel GC       — multi-threaded STW Young + Old, throughput-optimized
Java 6     CMS               — concurrent Old Gen marking, deprecated in Java 9
Java 7u4   G1GC              — region-based, default in Java 9+
Java 11    ZGC               — concurrent everywhere, < 1ms pauses
Java 12    Shenandoah        — concurrent compaction, < 1ms pauses
Java 11    Epsilon            — no-op GC, testing only
Java 21    ZGC generational   — generational ZGC, better throughput
```

---

## 1. Serial GC

**Flags**: `-XX:+UseSerialGC`

**How it works**:
- Single GC thread for both Young and Old Gen collections
- All application threads stop (STW) for the duration
- Young: copy collection (Eden + Survivor → Survivor/Old)
- Old: mark-sweep-compact

```
Application threads: ████████░░░░░░░░████████░░░░░░░░████████
GC thread:           ────────████████────────████████────────
                              Minor GC         Major GC
```

**When to use**:
- Single-core machines or containers with < 1 CPU
- Very small heaps (< 100MB) — CLI tools, batch scripts
- Embedded JVMs where memory footprint matters more than latency
- When you want the simplest, most predictable GC behavior

**When NOT to use**:
- Multi-core servers (wastes all cores during GC)
- Any service with latency SLAs
- Heap > 200MB

**Pause characteristics**:
- Minor GC: 1–100ms (depends on live set in Young Gen)
- Major GC: 100ms–10s (depends on Old Gen live set size)

---

## 2. Parallel GC (Throughput Collector)

**Flags**: `-XX:+UseParallelGC` (default in Java 8 and below)

**How it works**:
- Multiple GC threads, but still STW for all phases
- Uses all available CPUs during GC — minimizes elapsed wall-clock pause time
- Adaptive sizing: automatically adjusts Eden/Survivor ratios and heap size to meet throughput goals

```
Application threads: ████████░░░░████████░░░░████████
GC threads (4):      ────────████────────████────────
                         4 GC threads working in parallel
```

**Key flags**:
```
-XX:+UseParallelGC
-XX:ParallelGCThreads=N          # default: min(8, CPU_count) or CPU_count * 5/8
-XX:MaxGCPauseMillis=500         # hint (not guarantee) — GC will try to meet this
-XX:GCTimeRatio=99               # target: < 1% time in GC (99:1 app:GC ratio)
-XX:+UseAdaptiveSizePolicy       # auto-tune Eden/Survivor sizes (default on)
```

**When to use**:
- Batch processing jobs (Hadoop, Spark executors, ETL pipelines)
- Offline analytics, report generation
- Applications where throughput >> latency (nightly jobs, data exports)
- Throughput target: > 99% time in application (< 1% in GC)

**When NOT to use**:
- User-facing services with latency SLAs
- Heaps > 10GB (pause times grow with heap size)

**Pause characteristics**:
- Minor GC: 10–100ms
- Major GC: 100ms–2s (scales with heap size)

---

## 3. CMS (Concurrent Mark-Sweep) — DEPRECATED

**Flags**: `-XX:+UseConcMarkSweepGC` (removed in Java 14)

**Status**: Deprecated in Java 9, removed in Java 14. **Do not use for new projects.** Covered here for legacy system discussions.

**Innovation over Parallel GC**: Old Gen marking done concurrently with application threads — no STW for the bulk of Old Gen work. But: no compaction → fragmentation over time → eventual Concurrent Mode Failure → fallback to Serial Old (Full GC, very long pause).

**Why it was retired**: fragmentation was the fundamental unfixable problem. Replaced by G1GC.

---

## 4. G1GC (Garbage-First Garbage Collector)

**Flags**: `-XX:+UseG1GC` (default in Java 9+)

**Core innovation**: heap divided into equal-sized regions (1–32MB each). Regions can be Eden, Survivor, Old, or Humongous. G1 collects the regions with the most garbage first (hence "Garbage-First") — predictable pause times because you control how many regions are collected per cycle.

```
Heap as G1 sees it:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ E  │ E  │ O  │ S  │ H  │ H  │ O  │ E  │
├────┼────┼────┼────┼────┼────┼────┼────┤
│ O  │ E  │ E  │ O  │ O  │ S  │ E  │ O  │
├────┼────┼────┼────┼────┼────┼────┼────┤
│ E  │ O  │ H  │ H  │ H  │ O  │ E  │ E  │
└────┴────┴────┴────┴────┴────┴────┴────┘
E=Eden  S=Survivor  O=Old  H=Humongous
```

**G1 Collection Cycle**:

```
Phase 1: Young-only GC (STW)
  ├── Evacuate Eden + Survivor → new Survivor regions
  └── Promote objects exceeding tenuring threshold to Old

Phase 2: Concurrent Marking (while app runs)
  ├── Initial Mark (STW, piggybacks on Young GC) — mark GC roots
  ├── Concurrent Mark — trace object graph concurrently
  ├── Remark (STW) — finalize marking after application mutations
  └── Cleanup (STW) — reclaim empty regions; account live data per region

Phase 3: Mixed GC (STW)
  ├── Collect Young regions (always)
  └── Collect a subset of Old regions (most garbage → least live data)
      Repeat until Old Gen occupancy drops below threshold

Full GC: fallback if concurrent marking cannot keep up
  → Serial Full GC (STW, all threads, all heap) — very long pause
  → Cause: allocation rate > concurrent marking rate (called "evacuation failure")
```

**Key flags and tuning**:

```
-XX:+UseG1GC
-Xms4g -Xmx4g                      # Set min=max to avoid resizing pauses
-XX:MaxGCPauseMillis=200            # Pause target (default 200ms) — G1 tunes collection set size to meet this
-XX:G1HeapRegionSize=N              # 1–32MB, power of 2; auto-calculated if unset
                                    # Rule: HeapSize / 2048 (aim for ~2000 regions)
-XX:G1NewSizePercent=5              # Min Young Gen size (% of heap)
-XX:G1MaxNewSizePercent=60          # Max Young Gen size
-XX:G1MixedGCLiveThresholdPercent=85 # Only include Old regions with < 85% live data in Mixed GC
-XX:InitiatingHeapOccupancyPercent=45 # Start concurrent marking when Old Gen hits this %
                                      # Lower this if you get Full GCs: try 35-40
-XX:G1ReservePercent=10             # Reserve 10% of heap as headroom for promotions
-XX:ConcGCThreads=N                 # Concurrent marking threads (default: ParallelGCThreads/4)

# For low-latency:
-XX:MaxGCPauseMillis=100            # Aggressive target
-XX:G1HeapRegionSize=16m            # Larger regions = fewer regions to scan = shorter pauses
-XX:InitiatingHeapOccupancyPercent=35  # Start marking earlier to avoid evacuation failure
```

**Humongous objects — critical gotcha**:

Objects > 50% of a G1 region size go directly to humongous regions (Old Gen), skipping Young Gen entirely. They are only collected during concurrent marking or Full GC — not during Young GC. Frequent large object allocation (e.g., `new byte[5MB]` on every request with `G1HeapRegionSize=8m`) causes Old Gen to fill fast → premature Mixed GC or Full GC.

```
Diagnosis: -XX:+G1PrintRegionLivenessInfo (JDK 11-)
           or JFR G1HeapRegionTypeChange events

Fix 1: Increase G1HeapRegionSize to make objects non-humongous
Fix 2: Pool large objects (see Object Pool pattern)
Fix 3: Switch to ZGC which handles large objects better
```

**When to use G1GC**:
- General purpose: heap 4GB–100GB
- Target pause time: 50–200ms p99 is realistic
- Mixed workloads (some latency sensitivity + some throughput)
- Replacing CMS (G1 was designed as CMS successor)

**When NOT to use G1GC**:
- Heap < 4GB: Parallel GC has less overhead
- Latency requirement < 50ms p99: use ZGC
- Very large heaps (> 100GB) with large live sets: ZGC/Shenandoah scale better

**Pause characteristics**:
- Young GC: 10–200ms
- Mixed GC: 20–200ms
- Full GC (emergency): 1s–minutes (avoid at all cost)

---

## 5. ZGC (Z Garbage Collector)

**Flags**: `-XX:+UseZGC` (production-ready from Java 15)

**Core innovation**: ALL work done concurrently — marking, relocation, reference updating — using **colored pointers** (load barriers). Application threads pay a small overhead on every heap read (the load barrier) instead of pausing for GC. Pause times are bounded by safepoint overhead only, not heap size.

**How colored pointers work**:

ZGC encodes metadata in unused high bits of 64-bit object pointers:
```
Pointer: ┌──────────────────────────────────────────────────────────────┐
         │ metadata (4 bits) │          object address (42 bits)         │
         └──────────────────────────────────────────────────────────────┘
           ▲ Remapped/Marked/Finalizable flags

Load barrier: every time application code reads a reference:
  if (pointer.remapped == 0) {
      pointer = forwardingTable[pointer.address]  // update stale reference
  }
  return pointer
```

This means ZGC can relocate objects while the application runs — the load barrier transparently updates references to relocated objects.

**ZGC Collection Cycle**:
```
Concurrent Mark:        app runs + GC marks live objects concurrently
STW Pause 1:           <1ms — mark roots (stack roots only)
Concurrent Relocate:   app runs + GC copies live objects to new locations
STW Pause 2:           <1ms — relocate roots
Concurrent Remap:      app runs + GC updates all references to relocated objects
STW Pause 3:           <1ms — minor cleanup
```

Total STW pauses: 2–3 pauses per GC cycle, each < 1ms regardless of heap size.

**Key flags**:

```
-XX:+UseZGC
-Xms8g -Xmx16g                    # Allow heap to grow (ZGC needs headroom for concurrent work)
-XX:SoftMaxHeapSize=12g            # Soft limit — ZGC will try to stay below this
                                   # Useful for containers: avoid OOM killer while allowing GC headroom
-XX:ZCollectionInterval=5          # Force GC every 5 seconds (prevents heap from never collecting during idle)
-XX:ZAllocationSpikeTolerance=2    # How much spike headroom to allow (default 2×)
-XX:ConcGCThreads=N               # Concurrent GC threads (auto-tuned by default)

# Generational ZGC (Java 21+) — better throughput, same latency
-XX:+UseZGC -XX:+ZGenerational    # Java 21 default when using ZGC
```

**Memory overhead**: ZGC needs 6× multi-mapping of the heap virtual address space (colored pointers). On a 16GB heap: ~96GB of virtual address space reserved (not physical memory). This can look alarming in `top` — look at RSS, not VIRT.

**When to use ZGC**:
- Latency requirement: p99 < 10ms, p999 < 15ms
- Large heaps (> 32GB) — ZGC pauses don't grow with heap size
- Real-time trading systems, gaming backends, payment APIs
- Any service where tail latency outliers are business-critical
- JDK 15+ (production-ready)

**When NOT to use ZGC**:
- Throughput is the priority (Parallel GC is still 10–20% more throughput)
- Heap < 4GB: load barrier overhead is noticeable
- JDK < 15 (experimental before that)
- Need 32-bit JVMs (ZGC requires 64-bit)

**Pause characteristics**:
- All pauses: < 1ms (p99), < 5ms (p999), independent of heap size
- GC overhead: typically 5–15% CPU for concurrent GC work

---

## 6. Shenandoah GC

**Flags**: `-XX:+UseShenandoahGC` (available from OpenJDK 12, backported to JDK 8/11 by Red Hat)

**Core innovation**: Similar to ZGC but uses **brooks pointers** (forwarding pointer stored in the object header) instead of colored pointers. Achieves concurrent compaction without load barriers on every read.

**How brooks pointers work**:
```
Object header:  [brooks pointer | mark word | klass pointer | fields...]
                      ▲ Points to the object itself normally;
                        updated to new location during relocation
```

Read barrier on object access: check if brooks pointer still points to self. If not, follow it to the new location (happens during relocation window only).

**Key difference from ZGC**:
- Shenandoah: lower memory overhead (no multi-mapping); slightly higher CPU overhead per GC cycle
- ZGC: better for very large heaps (> 100GB); better latency on JDK 21 with Generational ZGC
- Both achieve < 1ms pauses

**Key flags**:
```
-XX:+UseShenandoahGC
-XX:ShenandoahGCHeuristics=adaptive  # Default: adaptive to allocation rate
                                     # compact: more aggressive, lower memory
                                     # static: fixed cycle interval
-XX:ShenandoahUnloadClassesFrequency=5  # Unload unreferenced classes every N GC cycles
```

**When to use Shenandoah vs ZGC**:
- Red Hat environments / OpenJDK backports to JDK 8/11: Shenandoah (ZGC not backported)
- JDK 21 on new services: ZGC Generational (better overall)
- JDK 17 on Quarkus / Spring Boot: either; benchmark for your workload

---

## 7. Epsilon GC (No-Op Collector)

**Flags**: `-XX:+UseEpsilonGC` (JDK 11+, experimental → production)

**How it works**: allocates memory but **never frees it**. When heap is full → OOM.

**When to use**:
- Performance testing: measure allocation rate without GC interference
- Short-lived tools where heap is large enough that GC never needed
- GC research / benchmarking
- Applications that manage their own memory (off-heap with manual lifecycle)

**NEVER use in production services**.

---

## GC Selection Decision Tree

```
What is the primary concern?

THROUGHPUT (batch jobs, offline processing)?
    → Parallel GC
    → Configure: -XX:GCTimeRatio=99

LATENCY (user-facing services)?
    ├── p99 < 10ms required?
    │   ├── JDK 21+ → ZGC Generational (-XX:+UseZGC -XX:+ZGenerational)
    │   ├── JDK 15–20 → ZGC (-XX:+UseZGC)
    │   └── JDK 8–11 with Red Hat OpenJDK → Shenandoah
    │
    └── p99 50–200ms acceptable?
        ├── Heap 4GB–100GB → G1GC (default)
        ├── Heap < 4GB → Parallel GC or G1GC
        └── Heap > 100GB → ZGC

MEMORY FOOTPRINT (containers, small services)?
    ├── < 256MB heap → Serial GC
    └── Need GraalVM native binary → Epsilon GC during testing,
                                      no GC in native image

TESTING ONLY (no real service)?
    → Epsilon GC
```

---

## Comparison Table

| GC | Min JDK | Pause Type | Pause Duration | Throughput | Heap Size | Best For |
|----|---------|-----------|---------------|-----------|-----------|---------|
| Serial | 1.0 | Full STW | 100ms–5s | Low | < 200MB | CLI tools, tiny containers |
| Parallel | 1.4 | Full STW | 50ms–2s | Highest | 1–20GB | Batch, Hadoop, Spark |
| CMS | 1.4 | Mostly concurrent | < 100ms (no compaction) | Medium | 4–32GB | **Deprecated — use G1** |
| G1GC | 7 | Mostly STW | 20–200ms | Medium-High | 4–100GB | General purpose |
| ZGC | 11 (prod: 15) | ~Concurrent | < 1ms | Medium | 8MB–16TB | Low-latency services |
| ZGC Gen | 21 | ~Concurrent | < 1ms | Medium-High | 8MB–16TB | Low-latency + throughput |
| Shenandoah | 12 | ~Concurrent | < 1ms | Medium | 4GB–1TB | Low-latency, OpenJDK backport |
| Epsilon | 11 | None (until OOM) | N/A | Highest | Limited by `-Xmx` | Testing only |

---

## Reading GC Logs

Enable with:
```
-Xlog:gc*:file=/var/log/app/gc.log:time,uptime,level,tags:filecount=5,filesize=20m
```

### G1GC Log Anatomy

```
[2.456s][info][gc] GC(3) Pause Young (Normal) (G1 Evacuation Pause) 512M->256M(2048M) 45.123ms
         ▲                   ▲                 ▲                      ▲       ▲        ▲
         time             GC type          GC reason              heap before  after  pause
```

Key events to watch:
- `Pause Young (Normal)` — normal Young GC, good
- `Pause Young (Concurrent Start)` — Young GC kicked off concurrent marking, good
- `Pause Remark` — concurrent marking STW phase, should be < 100ms
- `Pause Cleanup` — counting live regions, should be < 10ms  
- `Pause Mixed` — collecting Old Gen regions, watch for > 200ms
- `Pause Full` — emergency Full GC — investigate immediately
- `Concurrent Mark Abort` — allocation pressure too high; lower `InitiatingHeapOccupancyPercent`

### ZGC Log

```
[2.345s][info][gc] GC(5) Garbage Collection (Allocation Rate) 8192M(50%)->4096M(25%)
[2.346s][info][gc] GC(5) Pause Mark Start 0.456ms    ← all pauses < 1ms
[2.367s][info][gc] GC(5) Pause Mark End 0.234ms
[2.389s][info][gc] GC(5) Pause Relocate Start 0.123ms
```

---

## GC Tuning Workflow

```
1. Enable GC logging
   -Xlog:gc*:file=gc.log:time,uptime

2. Analyze with GCViewer / GCEasy.io
   - Throughput %
   - Pause histogram (p50/p95/p99/max)
   - Allocation rate MB/s
   - Promotion rate MB/s

3. Identify bottleneck:
   ├── Frequent Full GC → Old Gen too small or IHOP too high
   ├── Long Mixed GC → reduce G1MixedGCCountTarget (more but shorter mixed GCs)
   ├── Long Young GC → Large Survivor or slow card table scanning
   ├── Humongous allocations → increase G1HeapRegionSize
   └── Pause > MaxGCPauseMillis → G1 can't meet target; increase heap or lower IHOP

4. Fix → re-deploy → verify with GC logs
5. Monitor: GC pause p99, GC CPU%, heap usage trending
```

---

## FAANG Interview Callouts

- **"What GC would you choose for a payment service SLA of p99 < 50ms?"** → G1GC with `MaxGCPauseMillis=50` is a starting point; if not achievable due to heap size, migrate to ZGC which gives < 1ms pauses independent of heap.
- **"Your G1GC Full GC takes 30 seconds on a 64GB heap. How do you fix it?"** → The Full GC is the symptom, not the cause. Root cause: allocation rate exceeds concurrent marking throughput. Fix: lower `InitiatingHeapOccupancyPercent` (start marking sooner), increase `ConcGCThreads`, reduce allocation rate, or migrate to ZGC which doesn't have this problem.
- **"How does ZGC achieve < 1ms pauses on a 100GB heap?"** → Colored pointers + load barriers. Marking and relocation happen concurrently with application threads. Pauses are only for safepoint operations (scanning thread stacks) which take microseconds regardless of heap size.
- **"What's the trade-off of switching from G1 to ZGC?"** → Latency win: p99 drops from 200ms to < 1ms. Throughput cost: ~10–15% lower throughput due to load barrier overhead on every heap read. Memory: ZGC needs more headroom (allocate into to-space while from-space is being copied). Generational ZGC (Java 21) largely closes the throughput gap.
- **"Why is a 31GB heap sometimes better than a 33GB heap?"** → Compressed OOPs breaks at 32GB. Below 32GB: 4-byte references (30% memory saving). Above: 8-byte references. A 31GB heap uses less memory total than a 33GB heap.
