# Kotlin Interview Preparation — Principal Engineer Bar

**Target:** Principal / Staff Engineer interviews at FAANG  
**Calibration:** Every Q&A pair is at Principal or Distinguished tier  
**Companion:** See [../java/README.md](../java/README.md) for deep JVM internals

---

## Why Kotlin at the Principal Level

At senior level, Kotlin questions are about idioms and syntax.  
At principal level, interviewers test whether you understand:

- What the compiler generates (CPS transformation for suspend, inline bytecode, erasure)
- When each abstraction adds value vs. introduces surprising behavior
- How Kotlin coroutines compose with JVM threading models
- Architectural decisions: sealed+when vs. Visitor, object vs. DI, data class invariants

---

## File Index

| File | Covers | Interview Weight |
|------|--------|----------------|
| [01-language-features-and-idioms.md](01-language-features-and-idioms.md) | Data classes, sealed classes, `object`, companion objects, extension functions, null safety, named/default params, delegation (`by`), `inline`/`reified`, value classes, smart casts | High |
| [02-coroutines-deep-dive.md](02-coroutines-deep-dive.md) | CPS transformation, builders (`launch`/`async`/`coroutineScope`), structured concurrency, Dispatchers, cancellation, exception handling, Channels, Flow, SharedFlow/StateFlow, VT vs. coroutines | **Critical** |
| [03-functional-and-scope-functions.md](03-functional-and-scope-functions.md) | `let`/`run`/`apply`/`also`/`with` decision matrix, HOF, non-local returns, inline/noinline/crossinline, Sequences vs. eager collections, DSL building with function types with receiver | High |
| [04-design-patterns-kotlin.md](04-design-patterns-kotlin.md) | GoF in Kotlin (singleton, builder, decorator, visitor → sealed, state machine), Kotlin-specific patterns (Result type, actor, lazy init), anti-patterns | High |

---

## Quick Reference — "Which File for Topic X?"

| Topic | File |
|-------|------|
| Data class `copy()` shallow copy bug | `01` |
| Data class vs. Java Record | `01` |
| `object` JVM thread safety guarantee | `01` |
| Companion object implementing interface | `01` |
| Extension function static dispatch | `01` |
| `by lazy` thread safety modes + VT implications | `01` |
| `inline` + `reified` — eliminating TypeReference | `01` |
| Value classes vs. Valhalla | `01` |
| `suspend` CPS transformation + `COROUTINE_SUSPENDED` | `02` |
| `launch` vs. `async` vs. `coroutineScope` | `02` |
| `SupervisorJob` vs. regular `Job` failure propagation | `02` |
| Cancellation cooperative model + `NonCancellable` | `02` |
| Channel capacity modes | `02` |
| `Flow` vs. `SharedFlow` vs. `StateFlow` | `02` |
| Coroutines vs. virtual threads comparison | `02` |
| Scope function decision matrix | `03` |
| `apply` vs. `also` — when each is correct | `03` |
| Non-local returns from lambdas | `03` |
| `Sequence` performance crossover point | `03` |
| DSL building with function-type-with-receiver | `03` |
| `@DslMarker` — why needed | `03` |
| Singleton via `object` vs. DI container | `04` |
| Builder via named/default params | `04` |
| Visitor → sealed+when replacement | `04` |
| Data class as `HashMap` key — mutation bug | `04` |
| Actor pattern with `Channel` | `04` |
| `GlobalScope` anti-pattern | `04` |

---

## Kotlin vs. Java Quick Comparison

| Feature | Java | Kotlin |
|---------|------|--------|
| Null safety | `@NonNull` annotations, runtime NPE | Type system: `T` vs `T?`, compile-time checks |
| Data class | Manual equals/hashCode/toString or Lombok | `data class` — one keyword |
| Sealed class | Java 17+ sealed classes | Available since Kotlin 1.0 |
| Singleton | DCLP with volatile | `object` declaration |
| Builder pattern | Builder class or Lombok @Builder | Named + default parameters + `copy()` |
| Extension methods | Not possible | First-class, statically dispatched |
| Null-safe chaining | `Optional` chaining | `?.` safe call, `?:` Elvis |
| Async/concurrency | CompletableFuture, virtual threads (Java 21) | Coroutines (richer composition) |
| Reified generics | `TypeReference` workaround | `inline` + `reified` |
| Delegation | Manual forwarding methods | `by` keyword — compiler generated |
| Operator overloading | Not supported | Yes (fixed set of operators) |

---

## Q&A Calibration Standard

Every question targets **Principal or Distinguished tier**. The distinction from Senior:

| Topic | Senior Level | Principal Level |
|-------|-------------|----------------|
| Coroutine cancellation | "CancellationException is thrown at suspend points" | "Explain why `withContext(NonCancellable)` is necessary in `finally` blocks and when misusing it causes resource leaks." |
| Extension functions | "They are statically dispatched" | "A library author made a polymorphic method an extension. Production bug: subtype behavior silently ignored. Redesign decision." |
| `data class` | "Generates equals/hashCode" | "A `data class` with a `var` field is used as a HashMap key. Describe the exact failure mode and two architectural fixes." |
| Coroutines vs. VT | "Coroutines use cooperative scheduling" | "Migrate a Hibernate-backed service from VT to coroutines: what breaks (synchronized pinning), what changes (all I/O must be coroutine-aware), and when you'd keep VT instead." |

---

## FAANG Interview Callout

**Top 5 Kotlin topics at principal engineer level:**

1. **Coroutines — structured concurrency contracts.** Know `Job` vs. `SupervisorJob` propagation, `coroutineScope` vs. `supervisorScope`, cancellation, and `CoroutineExceptionHandler`. These map directly to fault isolation and system reliability questions.

2. **Coroutines — suspend function mechanics.** CPS transformation, `COROUTINE_SUSPENDED`, and how `withContext` switches threads. Interviewers use this to test JVM understanding alongside Kotlin.

3. **Flow / SharedFlow / StateFlow.** The distinction between hot and cold streams, backpressure operators, and when to use each. This replaces the Java reactive streams question in Kotlin interviews.

4. **Sealed classes + `when` exhaustiveness.** Modeling domains as sealed hierarchies and replacing Visitor. Interviewers check whether you've internalized "adding a type forces all handlers to update" — and whether you see that as a feature, not a bug.

5. **Null safety at system boundaries.** How to handle Java interop platform types, design non-null domain models, and avoid `!!` in production code. Shows disciplined API design.
