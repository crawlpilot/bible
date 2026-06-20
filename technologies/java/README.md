# Java / JVM — Principal Engineer Deep-Dive

## Why This Matters for FAANG Interviews

Java (and Kotlin/Scala on the JVM) powers backend services at Google, Meta, Amazon, Netflix, Uber, and Airbnb. Principal engineers are expected to understand performance characteristics, not just syntax — specifically: why a service has 500ms GC pauses, why a thread pool's queue length grows unboundedly, and how to tune a JVM for a latency-sensitive vs throughput-oriented workload.

---

## Contents

| File | Topics |
|------|--------|
| [01-jvm-architecture.md](01-jvm-architecture.md) | JVM memory regions, class loading, JIT (C1/C2/GraalVM), TLAB, safepoints |
| [02-garbage-collectors.md](02-garbage-collectors.md) | Serial, Parallel, CMS, G1, ZGC, Shenandoah — mechanics, trade-offs, selection guide |
| [03-thread-pools-and-concurrency.md](03-thread-pools-and-concurrency.md) | ThreadPoolExecutor, ForkJoinPool, Virtual Threads, CompletableFuture, Java Memory Model |
| [04-performance-tuning.md](04-performance-tuning.md) | JVM flags, profiling (async-profiler, JFR), heap sizing, GC log analysis |
| [05-production-and-internals.md](05-production-and-internals.md) | GC incidents at FAANG, production tuning patterns, interview framing |

---

## GC Selection — Quick-Reference Card

| Workload | GC | Key Flags | Pause Target |
|----------|----|-----------|--------------|
| Batch / throughput | Parallel (ParallelGC) | `-XX:+UseParallelGC` | 100ms–1s acceptable |
| General purpose, large heap | G1GC | `-XX:+UseG1GC -XX:MaxGCPauseMillis=200` | 200ms p99 |
| Low-latency services (< 10ms pauses) | ZGC | `-XX:+UseZGC -XX:SoftMaxHeapSize=...` | < 10ms at any heap size |
| Ultra-low-latency, JDK 11+ | Shenandoah | `-XX:+UseShenandoahGC` | < 10ms |
| GC-free testing / off-heap | Epsilon | `-XX:+UseEpsilonGC` | N/A — no GC |

---

## Thread Pool Selection — Quick-Reference Card

| Use Case | Pool Type | Key Config |
|----------|-----------|------------|
| HTTP request handling, I/O-bound | `ThreadPoolExecutor` | `maxPoolSize = 200`, `LinkedBlockingQueue(1000)` |
| CPU-bound parallel tasks (parallelStream) | `ForkJoinPool.commonPool()` | `parallelism = core_count - 1` |
| Async task orchestration | `CompletableFuture` + custom pool | Separate pool per concern (I/O vs CPU) |
| High concurrency I/O (JDK 21+) | Virtual Threads | `Executors.newVirtualThreadPerTaskExecutor()` |
| Scheduled / cron | `ScheduledThreadPoolExecutor` | `corePoolSize = job_count` |

---

## Decision Drivers: When Java JVM Tuning Becomes a Principal Engineer Topic

1. **GC pause spikes** affecting tail latency (p99/p999 latency outliers)
2. **OOM errors** — heap sizing, memory leak investigation, off-heap usage
3. **Thread pool exhaustion** — queue buildup, rejection policies, thread starvation
4. **CPU saturation** from GC overhead — `GcCpuPercentage > 5%` is a red flag
5. **Virtual Threads migration** — removing thread-per-request bottleneck
6. **JIT deoptimization** — sudden latency spikes from code deoptimization events
7. **Metaspace leaks** from class loader proliferation (OSGi, dynamic languages)

---

## Key Numbers to Know

| Metric | Value | Context |
|--------|-------|---------|
| Minor GC frequency | Every 500ms–5s | Depends on allocation rate and Eden size |
| G1GC target pause | 200ms default | Tunable; achievable at 50–100ms with careful sizing |
| ZGC pause | < 1ms (concurrent) | Pause = only safepoint overhead, not heap traversal |
| TLAB size | ~1% of Eden (~512KB) | Per-thread allocation buffer — avoids synchronization |
| Thread stack size | 512KB–1MB | `-Xss`; VirtualThread stacks start at ~1KB |
| JIT compilation threshold | 10,000 invocations (C2) | After threshold, method compiled to native |
| GC overhead limit | 98% time in GC → OOM | JVM kills itself before thrashing infinitely |

---

## Anti-Patterns

| Anti-Pattern | Symptom | Fix |
|-------------|---------|-----|
| Unbounded thread pool | Queue depth grows → OOM | Set `maxPoolSize` and use bounded `LinkedBlockingQueue` |
| Heap too large without ZGC | Full GC pause > 30s on 100GB heap | Switch to ZGC/Shenandoah, or shard the JVM |
| `System.gc()` in application code | Stop-the-world pauses on demand | Remove; use GC logs to diagnose instead |
| Finalizers on pooled objects | GC deferral until finalizer runs | Use `Cleaner` API or explicit `close()` |
| Allocating large objects in hot path | Promoted directly to Old Gen → frequent Full GC | Object Pool or off-heap allocation |
| `ThreadLocal` without `remove()` in thread pools | Memory leak over days | Always `threadLocal.remove()` in `finally` |
| Using `parallelStream()` for I/O | Common pool threads blocked → global starvation | Dedicated `ForkJoinPool` or async pipeline |

---

## FAANG Interview Callouts

- **"Why is your p99 latency 2x your p95?"** → GC pause. Check GC logs first. If G1 pauses > 200ms, tune `MaxGCPauseMillis` or switch to ZGC.
- **"How do you size a thread pool?"** → Little's Law: `threads = latency × throughput`. For 100ms avg latency and 1000 RPS: 100 threads.
- **"What's the difference between heap and off-heap?"** → Heap: GC-managed, easy programming model. Off-heap: no GC pressure, used by Cassandra (memtables), Kafka (page cache), Netty (direct buffers).
- **"Why did your service OOM with 80% heap free?"** → Metaspace OOM (class loader leak) or off-heap OOM (DirectByteBuffer). Heap % is misleading.
