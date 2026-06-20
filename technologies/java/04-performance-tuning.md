# 04 — JVM Performance Tuning Guide

## Tuning Workflow

```
1. Define the target: p99 latency < Xms, GC overhead < Y%, throughput > Z req/s
2. Establish a baseline: deploy with GC logging + JFR enabled from day one
3. Identify the bottleneck: GC? CPU? Memory? Thread contention? I/O?
4. Change ONE variable at a time
5. Validate with load test, not just unit tests
6. Monitor in production — synthetic load ≠ real traffic pattern
```

---

## Essential JVM Flags — Production Baseline

```bash
# ── Memory ─────────────────────────────────────────────────────────────
-Xms4g -Xmx4g               # Set initial = max to avoid heap resize pauses
                              # and prevent JVM from releasing memory back to OS
-XX:MetaspaceSize=256m        # Initial Metaspace (avoids repeated expansions at startup)
-XX:MaxMetaspaceSize=512m     # Cap Metaspace (catch ClassLoader leaks early)

# ── GC ────────────────────────────────────────────────────────────────
-XX:+UseG1GC                 # Default in JDK 9+; explicit for documentation
-XX:MaxGCPauseMillis=200      # Pause target (hint, not hard guarantee)
-XX:InitiatingHeapOccupancyPercent=45  # Start concurrent marking at 45% Old Gen occupancy
-XX:G1HeapRegionSize=16m      # Larger regions → fewer regions → faster GC for large heaps
-XX:G1ReservePercent=10       # Keep 10% headroom for promotions
-XX:+ExplicitGCInvokesConcurrent  # System.gc() triggers concurrent GC, not Full GC

# ── GC Logging ──────────────────────────────────────────────────────────
-Xlog:gc*:file=/var/log/app/gc.log:time,uptime,level,tags:filecount=5,filesize=20m
# filecount=5, filesize=20m → rolling 100MB of GC logs

# ── JIT ────────────────────────────────────────────────────────────────
-XX:+TieredCompilation        # Default on; JDK uses both C1 and C2
-XX:ReservedCodeCacheSize=512m  # Default 240MB; increase for large codebases
-XX:+UseStringDeduplication   # Deduplicate String objects in Old Gen (G1 only)
                              # Saves 10-25% heap on string-heavy workloads

# ── Crash/OOM diagnostics ───────────────────────────────────────────────
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/log/app/heapdump.hprof
-XX:+ExitOnOutOfMemoryError   # Kill JVM on OOM (let k8s restart fresh vs limping)
-XX:ErrorFile=/var/log/app/hs_err_%p.log

# ── JFR (Java Flight Recorder) ──────────────────────────────────────────
-XX:StartFlightRecording=name=startup,delay=30s,duration=60s,filename=/tmp/startup.jfr
# or start from jcmd:
# jcmd <pid> JFR.start name=prod duration=60s filename=/tmp/prod.jfr settings=profile

# ── Compressed OOPs (automatic, but document) ──────────────────────────
# Enabled automatically for heaps < 32GB — DO NOT disable unless you know why
# -XX:+UseCompressedOops   (default)
# -XX:+UseCompressedClassPointers  (default)

# ── Container awareness (Java 10+) ──────────────────────────────────────
-XX:+UseContainerSupport     # JVM reads cgroup limits, not host CPU/memory (default J10+)
-XX:MaxRAMPercentage=75      # Heap = 75% of container memory limit
                              # Leave 25% for: Metaspace, JIT code cache, off-heap, OS
```

---

## Heap Sizing Strategy

```
Container Memory Limit: 8GB

Recommended allocation:
  Heap (-Xmx):        6GB     (75% of RAM — MaxRAMPercentage=75)
  Metaspace:          256MB
  Code Cache:         256MB
  Thread stacks:      ~200 × 512KB = 100MB
  OS / JVM overhead:  ~500MB
  DirectByteBuffer:   depends on Netty/NIO usage (check with NativeMemoryTracking)
  ─────────────────────────────────
  Total:              ~7.1GB  (leaves 900MB headroom — avoids OOM killer)

Heap sizing rules:
  Live set × 2.5 = minimum heap  (less → constant Full GC)
  Live set × 4   = comfortable heap (enough for GC headroom + promotion)
  > 32GB         → loses Compressed OOPs (use 31GB if possible, or accept the cost)
```

---

## Profiling Tools

### async-profiler — CPU and allocation profiling

The gold standard for JVM profiling. Uses async-signal-safe code; does not require safepoints (unlike JVM's built-in sampling, which only samples at safepoints and misses CPU-bound code in long loops).

```bash
# Download: https://github.com/async-profiler/async-profiler

# CPU flamegraph
./asprof -d 60 -f /tmp/cpu.html <pid>

# Allocation flamegraph (find what allocates the most objects)
./asprof -e alloc -d 60 -f /tmp/alloc.html <pid>

# Lock/contention profiling
./asprof -e lock -d 60 -f /tmp/lock.html <pid>

# Wall-clock profiling (includes I/O wait — shows where threads spend time regardless of CPU)
./asprof -e wall -t -d 60 -f /tmp/wall.html <pid>
```

Reading a CPU flamegraph:
```
Width = CPU time spent in that method (or its callees)
Hover over a frame to see exact %

Look for:
  → Wide bars at the bottom: expensive hot paths
  → Unexpected frames (GC, lock contention, serialization)
  → Framework overhead (Spring proxy calls, reflection)
```

### Java Flight Recorder (JFR)

Low-overhead (< 2%) continuous profiling. Production-safe. Captures: GC events, thread state, I/O, JIT, class loading, method profiling.

```bash
# Start recording (production: always-on)
jcmd <pid> JFR.start name=prod settings=default maxage=1h maxsize=500m

# Dump when needed (without stopping)
jcmd <pid> JFR.dump name=prod filename=/tmp/dump.jfr

# Stop recording
jcmd <pid> JFR.stop name=prod

# Analyze with JDK Mission Control (JMC):
# - Method profiling (hot methods)
# - GC analysis (pause histogram, allocation rates)
# - Thread analysis (blocked threads, deadlocks)
# - System events (CPU, memory, I/O)
```

### GCViewer / GCEasy.io — GC log analysis

```bash
# Download GCViewer jar
java -jar gcviewer.jar gc.log

# Or upload to https://gceasy.io (cloud analysis)

# Key metrics to extract:
# - Throughput %: time NOT in GC
# - Max/p99 pause
# - Allocation rate (MB/s)
# - Promotion rate (MB/s → Old Gen)
# - Full GC count and frequency
```

### jcmd — live JVM diagnostics

```bash
# List all Java processes
jcmd

# Force GC (use sparingly — for testing only)
jcmd <pid> GC.run

# Heap histogram (live objects by class, sorted by count/size)
jcmd <pid> GC.class_histogram | head -30

# Heap dump
jcmd <pid> GC.heap_dump /tmp/heap.hprof

# JVM flags in effect
jcmd <pid> VM.flags

# Thread dump
jcmd <pid> Thread.print

# System info
jcmd <pid> VM.system_properties
jcmd <pid> VM.native_memory summary  # off-heap memory breakdown (needs -XX:NativeMemoryTracking=summary)
```

### jstack / jmap — quick diagnostics

```bash
# Thread dump — find deadlocks, blocked threads
jstack <pid> > /tmp/threads.txt
grep -E "BLOCKED|WAITING|deadlock" /tmp/threads.txt

# Heap histogram without full heap dump (fast)
jmap -histo:live <pid> | head -30
```

---

## Common Performance Problems and Fixes

### 1. High GC Overhead (GC CPU > 5%)

```
Symptom: CPU spike every N seconds; GC log shows Minor GCs every 100ms
Cause: High allocation rate — creating too many short-lived objects

Diagnosis:
  async-profiler -e alloc → shows what code allocates most

Common culprits:
  - String concatenation in loops (+ operator creates intermediate Strings)
  - Autoboxing (int → Integer in collections)
  - Logging with string formatting in disabled log levels
  - new ArrayList<>() in every request path instead of reusing

Fix:
  - StringBuilder for string building
  - Primitive collections (Eclipse Collections, Trove)
  - Log guards: if (log.isDebugEnabled()) { ... }
  - Object Pool for expensive objects
  - Increase Eden size: -XX:NewRatio=2 (Old:Young = 2:1 → larger Young Gen)
```

### 2. Full GC Causing Long Pauses

```
Symptom: occasional pauses 5–30s; GC log shows "Pause Full"
Cause (G1): allocation rate > concurrent marking rate → evacuation failure

Diagnosis:
  grep "Pause Full" gc.log | wc -l         # count Full GCs
  grep "Concurrent Mark Abort" gc.log      # marking couldn't keep up

Fix:
  1. Lower IHOP: -XX:InitiatingHeapOccupancyPercent=35 (start marking sooner)
  2. Increase heap: more headroom between marking and full
  3. Increase ConcGCThreads: more threads for concurrent marking
  4. Reduce allocation rate (see above)
  5. Switch to ZGC (no Full GC under normal conditions)
```

### 3. Humongous Object GC Pressure (G1)

```
Symptom: GC log shows "Humongous allocation" or frequent Mixed GC
Cause: Objects > 50% of G1HeapRegionSize go directly to Old Gen

Diagnosis:
  JFR: filter G1HeapSummary events; look for humongous region count

Fix:
  1. Increase -XX:G1HeapRegionSize to make objects non-humongous
  2. Use Object Pool for large byte arrays (request/response buffers)
  3. Use off-heap (DirectByteBuffer) for I/O buffers
```

### 4. Thread Pool Saturation

```
Symptom: request latency spikes; thread pool queue depth climbing; rejection exceptions

Diagnosis:
  - Check pool metrics: active threads, queue size, rejection rate
  - Thread dump (jstack): many threads in WAITING or BLOCKED on same lock?
  
Cause types:
  A. I/O-bound: all threads waiting for slow DB/network → increase pool size
  B. CPU-bound: all threads doing CPU work → adding threads makes it worse
  C. Deadlock: threads waiting on each other → thread dump, look for "found one Java-level deadlock"

Fix A: increase maxPoolSize (using Little's Law calculation)
Fix B: optimize the CPU work, or scale out
Fix C: fix locking order; use timeouts; switch to lock-free structures
```

### 5. Memory Leak (Heap grows indefinitely)

```
Symptom: heap slowly grows; GC after GC doesn't reclaim → eventual OOM

Diagnosis:
  1. Take heap dump: jcmd <pid> GC.heap_dump /tmp/leak.hprof
  2. Analyze with Eclipse MAT (Memory Analyzer Tool)
  3. Look for "dominator tree" — objects retaining the most heap
  4. Find GC roots holding references to large object graphs

Common causes:
  - Cache without eviction (HashMap never cleared)
  - ThreadLocal not removed (thread pool reuses threads — ThreadLocal survives)
  - Event listeners not de-registered (Observer pattern leak)
  - ClassLoader leak (new ClassLoader on each request, old ClassLoaders not GC'd)
  - Static collections accumulating objects

Fix: heap dump → MAT analysis → trace the retention path → remove unintended reference
```

### 6. Metaspace OOM

```
Symptom: java.lang.OutOfMemoryError: Metaspace
Cause: ClassLoader leak — new ClassLoaders created but not GC'd

Diagnosis:
  jcmd <pid> VM.classloader_stats
  # Look for ClassLoaders with count growing over time

Common causes:
  - Hot reload (JRebel, Spring DevTools) accumulating class versions
  - Dynamic proxies (CGLIB, JDK proxy) per-request class generation
  - Groovy/Clojure dynamic class compilation
  - OSGi bundles not properly uninstalled

Fix: find where ClassLoaders are created; ensure they can be GC'd;
     add -XX:MaxMetaspaceSize=512m to catch it early with OOM instead of quiet memory growth
```

### 7. Code Cache Full

```
Symptom: sudden latency spike after hours of steady performance; CPU drops but latency rises
Cause: Code Cache full → JIT stops compiling → execution falls back to interpreter

Diagnosis:
  -XX:+PrintCodeCache (JDK 11-)
  JFR: filter Compilation events, look for CodeCacheFull

Fix:
  Increase: -XX:ReservedCodeCacheSize=512m (default 240MB)
```

---

## Container-Specific Tuning

```bash
# ── Kubernetes / Docker ──────────────────────────────────────────────────

# Always set in containerized JVMs (JDK 10+ reads cgroup limits)
-XX:+UseContainerSupport     # default on JDK 10+
-XX:MaxRAMPercentage=75      # heap = 75% of container memory limit

# WRONG: setting -Xmx to host memory ignores container limit
# -Xmx32g on a container with 8GB limit → OOM killer

# CPU throttling: JVM defaults to host CPU count for parallelism
# Override if container CPU limit < host:
-XX:ActiveProcessorCount=4   # or let JDK auto-detect from cgroup cpu.cfs_quota_us

# ── Startup time (especially Kubernetes pods) ────────────────────────────

# JDK 12+: Class Data Sharing (AppCDS)
# Pre-compute class loading for faster startup
java -Xshare:dump -XX:SharedClassListFile=classes.lst -XX:SharedArchiveFile=app.jsa ...
java -Xshare:on -XX:SharedArchiveFile=app.jsa -jar app.jar
# Startup improvement: 20-50% faster

# Project CRaC (Coordinated Restore at Checkpoint) — JDK 21+
# Snapshot JVM state after warmup → restore in milliseconds
# Used by: Spring Boot 3.2+ checkpoint/restore feature
```

---

## Monitoring — Key Metrics

```yaml
# Prometheus / Micrometer metrics to expose and alert on:

jvm_gc_pause_seconds:
  alert: p99 > 200ms (G1) or > 10ms (ZGC)
  
jvm_gc_overhead_percent:  # % of time in GC
  alert: > 5% sustained
  
jvm_memory_used_bytes{area="heap"}:
  alert: > 80% of max (headroom exhaustion)
  
jvm_memory_used_bytes{area="nonheap"}:  # Metaspace
  alert: > 80% of MaxMetaspaceSize

jvm_threads_states{state="blocked"}:
  alert: > 10 (lock contention issue)
  
jvm_threads_states{state="waiting"}:  
  alert: rapid growth (thread pool starvation)
  
executor_pool_size:
  executor_active_threads:
  executor_queue_size:
  alert on queue depth > 80% of capacity
  
jvm_compilation_time_seconds_total:  # JIT overhead
  # Alert if growing faster than expected (deoptimization loop)
```

---

## FAANG Interview Callouts

- **"Walk me through how you'd diagnose a p99 latency regression deployed 2 hours ago."** → Check GC logs first (pause spikes?). Thread dump for blocked threads. async-profiler flamegraph for new hot paths. Compare allocation rate before/after. Check JFR for lock contention.
- **"What's the first thing you'd change for a service with 10GB heap and 2-second Full GCs?"** → Lower `InitiatingHeapOccupancyPercent` from 45 to 35 (start concurrent marking sooner). If that doesn't fix it, the allocation rate is too high — need async-profiler to find what's allocating. Last resort: switch to ZGC (no Full GC under normal conditions).
- **"Why would a container JVM use more memory than its -Xmx?"** → Off-heap usage: Metaspace, JIT Code Cache, thread stacks (N × 512KB), DirectByteBuffer (Netty). Total JVM memory = heap + off-heap. Use `-XX:NativeMemoryTracking=summary` and `jcmd <pid> VM.native_memory summary` to see the breakdown.
- **"How do you find a memory leak in a running JVM?"** → Take two heap dumps 30 minutes apart. Diff in Eclipse MAT (Compare Objects). The growing class/object graph between dumps points to the leak. Dominator tree shows which GC roots are retaining the leaked objects.
