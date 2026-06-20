# Java Interview Preparation — Principal Engineer Bar

**Target:** Principal / Staff Engineer interviews at FAANG  
**Calibration:** Every Q&A pair is at Principal or Distinguished tier

---

## Scope and Boundaries

This folder covers Java language internals, JVM mechanics, and language paradigms at the depth expected of a principal engineer. It does NOT duplicate:

- **Coding standards and best practices** → [02-java-best-practices.md](../../Development/best-practices/02-java-best-practices.md)
- **GoF pattern catalog** → [LLD/design-patterns/](../../LLD/design-patterns/)
- **Builder/Optional discipline** → [02-java-best-practices.md](../../Development/best-practices/02-java-best-practices.md)

---

## Java Version Timeline

| Feature | Introduced | Finalized | Production-Safe Since |
|---------|-----------|-----------|----------------------|
| Lambda + Streams + Optional | Java 8 | Java 8 | Java 8 |
| `var` (LVTI) | Java 10 | Java 10 | Java 11 (LTS) |
| Text Blocks | Java 13 preview | Java 15 | Java 17 (LTS) |
| Records | Java 14 preview | Java 16 | Java 17 (LTS) |
| Sealed Classes | Java 15 preview | Java 17 | Java 17 (LTS) |
| Pattern Matching `instanceof` | Java 14 preview | Java 16 | Java 17 (LTS) |
| Switch Expressions | Java 12 preview | Java 14 | Java 17 (LTS) |
| Sequenced Collections | — | Java 21 | Java 21 (LTS) |
| Virtual Threads (Project Loom) | Java 19 preview | Java 21 | Java 21 (LTS) |
| Pattern Matching Switch | Java 17 preview | Java 21 | Java 21 (LTS) |
| Structured Concurrency | Java 21 preview | Java 23 preview | Not yet final |
| Scoped Values | Java 21 preview | Java 23 preview | Not yet final |
| String Templates | Java 21 preview | Java 23 preview | Not yet final |
| Value Types (Valhalla) | Java 23 preview | TBD | Not yet final |
| `synchronized` pinning fix | — | Java 24 (JEP 491) | Java 24 |

---

## File Index

| File | Covers | Interview Weight |
|------|--------|----------------|
| [01-modern-language-features.md](01-modern-language-features.md) | Text blocks, records, sealed classes, switch expressions, pattern matching, var, string templates, Valhalla, Sequenced Collections | High |
| [02-type-system-and-generics.md](02-type-system-and-generics.md) | Erasure, heap pollution, PECS, wildcard capture, F-bounds, reifiable types | High |
| [03-concurrency-and-loom.md](03-concurrency-and-loom.md) | JMM happens-before, volatile/synchronized/atomic, lock internals, Fork/Join, CompletableFuture, virtual threads, structured concurrency, scoped values | **Critical** |
| [04-data-structures-internals.md](04-data-structures-internals.md) | HashMap, ConcurrentHashMap, ArrayList, LinkedList, TreeMap, PriorityQueue, EnumMap/EnumSet, ArrayDeque — implementation mechanics | High |
| [05-functional-and-reactive.md](05-functional-and-reactive.md) | Lambda internals, Stream pipeline, Spliterator, Collectors, reactive streams spec, Project Reactor, backpressure, VT vs. Reactive | High |
| [06-design-patterns-java-idioms.md](06-design-patterns-java-idioms.md) | Modern Java idioms replacing classic patterns, SOLID non-obvious, DDD building blocks | Medium-High |
| [07-metaprogramming.md](07-metaprogramming.md) | Annotations, APT, reflection, MethodHandles, VarHandle, dynamic proxies, bytecode, JPMS | Medium |
| [08-oom-debugging-and-profiling.md](08-oom-debugging-and-profiling.md) | OOM taxonomy, 8-step investigation playbook, Eclipse MAT, async-profiler, root cause reference | **Critical** |

---

## Quick Reference — "Which File for Topic X?"

| Topic | File |
|-------|------|
| Records, sealed classes, pattern matching | `01` |
| Virtual threads, Project Loom | `03` |
| `synchronized` pinning explanation | `03` |
| Structured concurrency / `StructuredTaskScope` | `03` |
| HashMap treeification internals | `04` |
| ConcurrentHashMap lock-free reads | `04` |
| `LinkedList` vs `ArrayDeque` | `04` |
| Generics erasure | `02` |
| PECS / wildcard variance | `02` |
| `new T[10]` illegal — why | `02` |
| Stream lazy evaluation / Spliterator | `05` |
| Reactive `request(n)` backpressure | `05` |
| `publishOn` vs `subscribeOn` | `05` |
| Virtual threads vs. Reactive trade-off | `05` |
| Visitor → sealed+switch migration | `06` |
| `@Autowired` field injection DIP violation | `06` |
| DDD Aggregate Java implementation | `06` |
| Spring AOP self-invocation bypass | `06`, `07` |
| Annotation processors (Lombok, MapStruct) | `07` |
| `VarHandle` replacing `sun.misc.Unsafe` | `07` |
| OOM heap dump investigation with MAT | `08` |
| ThreadLocal leak on Tomcat | `08` |
| async-profiler allocation profiling | `08` |
| GC tuning (G1, ZGC) | `08` |
| JVM flags for crash intelligence | `08` |

---

## Q&A Calibration Standard

**Every question in these files is Principal or Distinguished tier.** The distinction from Senior:

| Topic | Senior Level | Principal Level |
|-------|-------------|----------------|
| ConcurrentHashMap | "How does it achieve thread safety?" | "Describe the `computeIfAbsent` reentrancy bug in Java 8, the Java 9 behavior change, and how to detect it in code review." |
| Virtual threads | "Explain carrier thread model" | "Given Hibernate uses `synchronized` in its connection pool, what exactly happens to carrier thread utilization, what JEP fixes this, and what is your migration strategy?" |
| HashMap | "How does resize work?" | "What are the two distinct failure modes under concurrent access — one in Java 7 and one in Java 8 — and why did the Java 8 fix eliminate one while preserving the other?" |
| Generics | "What is erasure?" | "How does `TypeReference<List<Order>>` preserve type information at runtime despite erasure, and which JLS rule makes this work?" |
| GC OOM | "What is a memory leak?" | "Walk through step-by-step investigation of a 4GB `HashMap$Entry` retention using Eclipse MAT, including the specific OQL query and why you exclude soft/weak references." |

---

## FAANG Interview Callout

**Top 5 Java topics that appear most frequently at principal engineer level:**

1. **Concurrency + Virtual Threads** — JMM happens-before, `synchronized` pinning, `StampedLock` optimistic reads, `StructuredTaskScope`. Java 21 changed the concurrency landscape — interviewers want to know if you've migrated production code.

2. **Data Structure Internals** — HashMap secondary hash function, ConcurrentHashMap lock-free reads, `LongAdder` vs `AtomicLong`. These are system design building blocks — "how would you implement a high-throughput counter?" requires knowing `LongAdder`.

3. **OOM Debugging** — Any principal engineer who claims production experience will be asked about OOM investigation. Know the 6 OOM types, the 8-step playbook, and how to use async-profiler.

4. **Modern Language Features** — Records + sealed + pattern matching switch. Interviewers evaluate whether you can model a problem domain idiomatically in modern Java (not Java 8 style).

5. **Generics Depth** — PECS, wildcard capture, TypeReference pattern. These appear in API design questions: "design a type-safe event system" or "implement a generic repository pattern."
