# Functional Programming Patterns

These patterns emerge from functional programming theory and practice — adopted heavily in JavaScript, Python, Kotlin, and modern Java (8+). They are not in the GoF catalogue but are essential vocabulary for principal engineer interviews, especially in discussions around null safety, error handling, data pipelines, and reactive systems.

## Why Functional Patterns Matter at Principal Engineer Level

- **Immutability by default** eliminates an entire class of concurrency bugs
- **Pure functions** make reasoning, testing, and parallelisation trivial
- **Composable abstractions** (Functor, Monad) reduce boilerplate without sacrificing type safety
- Modern JVM languages (Kotlin, Scala) and frameworks (Spring WebFlux, Project Reactor) are built on these primitives
- JavaScript's async/await, Python's generators, and Java's Stream API are all monadic patterns

## When to Reach for a Functional Pattern

- You are wrapping a nullable value and want propagation without null checks (Maybe/Option)
- An operation can fail and you want typed error handling without exceptions (Either)
- You need to chain transformations over wrapped values (Functor, Monad)
- You are building a data pipeline from composable steps (Function Composition)
- You need to configure or inject behaviour without objects (Currying / Partial Application)
- State mutation is causing concurrency or testability problems (Immutable Data)
- You are processing a potentially infinite or expensive sequence (Lazy Evaluation)
- A pure function is called repeatedly with the same inputs (Memoization)

## Patterns in This Category

| # | Pattern | Intent | JS | Python | Java/Kotlin | Interview Frequency |
|---|---------|--------|-----|--------|-------------|---------------------|
| 33 | [Functor](33-functor.md) | Map a function over a wrapped value | `Array.map`, `Promise.then` | `map()`, pandas `.apply` | `Stream.map`, `Optional.map` | Common |
| 34 | [Monad](34-monad.md) | Chain computations that carry context | `Promise` chain, `flatMap` | Generator pipeline | `Optional.flatMap`, `Stream.flatMap` | Common |
| 35 | [Maybe / Option](35-maybe-option.md) | Null-safe value container | Optional chaining `?.` | `None` + type hints | `Optional<T>`, Kotlin `?` | Common |
| 36 | [Either](36-either.md) | Typed error as a value, no exceptions | fp-ts `Either` | `Result` types | `Either<L,R>`, Kotlin `Result<T>` | Occasional |
| 37 | [Function Composition](37-function-composition.md) | Build pipelines from small pure functions | `pipe`, `compose` | `functools`, operator chaining | `Function.andThen`, Kotlin extensions | Common |
| 38 | [Currying & Partial Application](38-currying-partial-application.md) | Fix arguments to produce specialised functions | Closure DI | `functools.partial` | Kotlin lambdas, method refs | Occasional |
| 39 | [Immutable Data](39-immutable-data.md) | Prevent mutation; share structure safely | `Object.freeze`, spread | `frozen dataclass` | Java records, Kotlin `data class` | Common |
| 40 | [Lazy Evaluation](40-lazy-evaluation.md) | Defer computation until value is needed | Generator functions | `yield`, `itertools` | `Stream`, Kotlin `Sequence` | Common |
| 41 | [Memoization](41-memoization.md) | Cache pure function results by input | Manual cache / decorator | `@lru_cache` | `ConcurrentHashMap.computeIfAbsent` | Common |

## Key Distinctions

### Functor vs Monad
- **Functor**: `map(f)` — applies `f` inside the wrapper, returns the same wrapper type (`List<B>` from `List<A>`)
- **Monad**: `flatMap(f)` — `f` itself returns a wrapper; Monad prevents double-wrapping (`Optional<Optional<B>>` → `Optional<B>`)

### Maybe vs Either
- **Maybe/Option**: models presence/absence — `Some(value)` or `None`; no reason for absence
- **Either**: models success/failure — `Right(value)` or `Left(error)`; the error carries information

### Currying vs Partial Application
- **Currying**: transforms `f(a, b, c)` into `f(a)(b)(c)` — every function takes exactly one argument
- **Partial Application**: fixes some arguments now, receives the rest later — `f(a, ?)` returns `g(b, c)`

## Language Quick-Reference

| Concept | JavaScript | Python | Java | Kotlin |
|---------|-----------|--------|------|--------|
| map | `Array.map`, `Promise.then` | `map()`, list comprehension | `Stream.map`, `Optional.map` | `.map {}` |
| flatMap | `Array.flatMap`, `Promise.then` | `itertools.chain.from_iterable` | `Stream.flatMap`, `Optional.flatMap` | `.flatMap {}` |
| null safety | `?.`, `??` | `or`, `if x is not None` | `Optional<T>` | `?.`, `?:` Elvis |
| immutability | `Object.freeze`, spread | `@dataclass(frozen=True)` | `record`, `Collections.unmodifiable*` | `data class` + `val` |
| lazy | Generator `function*` | `yield`, `itertools` | `Stream` (lazy by default) | `Sequence` |
| memoize | Manual / Lodash `_.memoize` | `@functools.lru_cache` | `ConcurrentHashMap.computeIfAbsent` | `by lazy`, custom |
