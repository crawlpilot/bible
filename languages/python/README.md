# Python Interview Preparation — Principal Engineer Bar

**Target:** Principal / Staff Engineer interviews at FAANG  
**Calibration:** Every Q&A pair is at Principal or Distinguished tier  
**Companions:** [../java/README.md](../java/README.md) | [../kotlin/README.md](../kotlin/README.md)

---

## Why Python at the Principal Level

Python interviews at senior level test syntax and libraries.  
At principal level, interviewers expect:

- **GIL mechanics and concurrency model** — when threading, multiprocessing, and asyncio each apply
- **CPython internals** — reference counting, descriptor protocol, MRO, metaclasses
- **Type system design** — Protocol vs ABC, generic typing, how to design type-safe APIs in a dynamically typed language
- **Production debugging** — memory leaks from `lru_cache`, asyncio event loop blocking, generator lifecycle
- **Pattern application** — which GoF patterns Python renders trivial and which it makes tricky

---

## Python Version Timeline

| Feature | Version | Notes |
|---------|---------|-------|
| f-strings | 3.6 | |
| `dataclasses` | 3.7 | |
| `asyncio` | 3.4 / stabilized 3.7 | |
| `walrus operator :=` | 3.8 | |
| `TypedDict`, `Protocol` | 3.8 | |
| `Annotated`, `Literal`, `Final` | 3.8 | |
| `dict` union `\|` operator | 3.9 | |
| Built-in generics `list[int]` | 3.9 | No more `typing.List` |
| `match`/`case` (pattern matching) | 3.10 | |
| `X \| Y` union types | 3.10 | No more `Optional` |
| `TypeGuard` | 3.10 | |
| `tomllib` | 3.11 | |
| `TaskGroup`, `asyncio.timeout` | 3.11 | Structured concurrency |
| `ExceptionGroup`, `except*` | 3.11 | |
| `TypeVarTuple`, `ParamSpec` finalized | 3.12 | |
| `itertools.batched` | 3.12 | |
| `override` decorator | 3.12 | |
| Free-threaded CPython (no GIL) | 3.13 (opt-in) | `python3.13t` |
| Lazy annotation evaluation (PEP 649) | 3.14 | Replaces PEP 563 |

---

## File Index

| File | Covers | Interview Weight |
|------|--------|----------------|
| [01-language-internals.md](01-language-internals.md) | GIL mechanics, reference counting + cyclic GC, `__dunder__` data model, descriptor protocol, `__slots__`, MRO + C3 linearization, metaclasses, `__init_subclass__` | **Critical** |
| [02-concurrency-and-asyncio.md](02-concurrency-and-asyncio.md) | threading vs. multiprocessing vs. asyncio decision, GIL release points, event loop internals, `async/await` mechanics, `gather` vs `TaskGroup`, `run_in_executor`, production patterns | **Critical** |
| [03-type-system.md](03-type-system.md) | Gradual typing, `Protocol` vs ABC, `TypeVar`/`Generic`/`ParamSpec`, `TypedDict`, `dataclasses` vs alternatives, type narrowing, `overload`, `get_type_hints` | High |
| [04-functional-patterns.md](04-functional-patterns.md) | Generator internals, `yield from`, decorator mechanics (`functools.wraps`, `ParamSpec`), context managers, `functools.lru_cache` memory leak patterns, `itertools` building blocks | High |
| [05-design-patterns-python.md](05-design-patterns-python.md) | GoF in Python (singleton, factory, decorator, proxy, strategy, observer, state), Python-specific patterns (mixin, registry, fluent interface), anti-patterns | High |

---

## Quick Reference — "Which File for Topic X?"

| Topic | File |
|-------|------|
| GIL — what it is, when released, Python 3.13 free-threaded | `01` |
| Reference counting + cyclic GC | `01` |
| `weakref` for caches | `01` |
| Descriptor protocol — how `@property` works | `01` |
| `__slots__` memory savings and failure modes | `01` |
| MRO C3 linearization | `01` |
| Metaclasses vs `__init_subclass__` | `01` |
| threading vs. multiprocessing vs. asyncio | `02` |
| asyncio event loop architecture | `02` |
| `gather` vs `TaskGroup` cancellation behavior | `02` |
| `run_in_executor` for blocking code | `02` |
| Async generators and context managers | `02` |
| Protocol vs ABC — structural vs nominal subtyping | `03` |
| `TypeVar` bounded, `ParamSpec` for decorators | `03` |
| `dataclass` vs `NamedTuple` vs `TypedDict` vs Pydantic | `03` |
| `from __future__ import annotations` → PEP 649 | `03` |
| Generator `send()` and `yield from` delegation | `04` |
| Decorator with `functools.wraps` and `ParamSpec` | `04` |
| `lru_cache` memory leak on instance methods | `04` |
| `contextlib.contextmanager` | `04` |
| `itertools` — batched, accumulate, groupby | `04` |
| Singleton — idiomatic Python approaches | `05` |
| Plugin registry with `Protocol` | `05` |
| `__getattr__` vs `__getattribute__` | `05` |
| `__new__` vs `__init__` — immutable subclasses | `05` |
| Mixin pattern with cooperative `super()` | `05` |

---

## Python vs Java vs Kotlin Quick Comparison

| Feature | Python | Java | Kotlin |
|---------|--------|------|--------|
| Null safety | Optional convention, no type-system enforcement | `@NonNull` annotations | Type system: `T` vs `T?` |
| Generics at runtime | Erased (same as Java) | Erased | Erased; `reified` for inline |
| Concurrency | GIL limits CPU threads; asyncio for I/O | Virtual threads (Java 21) | Coroutines |
| Pattern matching | `match/case` (3.10) | `switch` with pattern matching (21) | `when` + sealed classes |
| Immutable data containers | `@dataclass(frozen=True)`, `NamedTuple` | `record` | `data class` (val properties) |
| Structural subtyping | `Protocol` | None (nominal only) | None (nominal only) |
| Decorators | First-class `@decorator` | Annotations + AOP | Annotations + AOP |
| Metaclasses | Yes | No | No |
| Type hints | Optional/gradual | Mandatory (all types) | Mandatory (most types) |

---

## Q&A Calibration Standard

**Every question targets Principal or Distinguished tier.** The distinction from Senior:

| Topic | Senior Level | Principal Level |
|-------|-------------|----------------|
| GIL | "GIL prevents true parallelism for CPU-bound threads" | "A NumPy operation releases the GIL but still has a race condition. Describe the exact scenario and fix." |
| asyncio | "Don't block the event loop" | "An asyncio service shows 30-second latency spikes on a production pod. Walk through 4 diagnostic steps and 3 likely causes, including one GC-related." |
| `lru_cache` | "It memoizes function calls" | "Describe two production memory leaks caused by `lru_cache`, including the instance method case and the high-cardinality key case, with fixes for each." |
| Descriptors | "Property is a decorator for getters/setters" | "Implement a `PositiveNumber` descriptor that validates on set. Explain the lookup order that makes this work even when `__dict__` has an entry for the same key." |
| `Protocol` | "Protocol enables duck typing with type checking" | "Design a plugin system using `Protocol` and a registry pattern. Explain two classes of bugs that Protocol misses vs ABC, and when each is the right choice." |

---

## FAANG Interview Callout

**Top 5 Python topics at principal engineer level:**

1. **GIL + Concurrency Model.** Every FAANG Python question on distributed systems or high-throughput services eventually asks: "how would you make this scale across cores?" You need to know multiprocessing, asyncio, and when each applies — not just that the GIL exists.

2. **asyncio — event loop mechanics.** Python async services are increasingly common at FAANG (FastAPI, aiohttp). Interviewers probe: what blocks the event loop, how do you run CPU work without blocking, `gather` vs `TaskGroup` semantics.

3. **Descriptor protocol.** ORM internals (SQLAlchemy, Django ORM), Pydantic fields, and `@property` all use descriptors. Knowing the lookup chain separates senior from principal.

4. **Type system design — Protocol vs ABC.** "Design a type-safe, extensible X" is a common principal question. The answer usually involves `Protocol` for structural typing. Knowing when to use ABC vs Protocol vs neither is a design judgment question.

5. **Memory management.** `lru_cache` on methods, circular references, `weakref` for caches. Production Python services frequently have memory growth issues — interviewers at staff level expect you to have debugged these.
