# 37. Function Composition
**Category**: Functional Programming  
**GoF**: No (Mathematics / FP)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Function composition is the practice of building complex transformations from small, single-purpose pure functions by chaining their outputs as inputs — creating a data pipeline that reads as a specification of what happens, not how.

---

## Problem It Solves

A data enrichment pipeline needs to: normalise a raw event, parse the timestamp, enrich with user data, apply business rules, and format for downstream. The imperative version creates a deeply nested call: `format(applyRules(enrich(parseTimestamp(normalise(event)))))` — reading inside-out, hard to test individual steps, and painful to reorder. Function composition lets you declare the pipeline as a sequence:

```
normalise → parseTimestamp → enrich → applyRules → format
```

Each step is a pure function (`A → B`). The pipeline itself is a new pure function (`RawEvent → FormattedEvent`). Add a step? Insert it in the chain. Change order? Reorder the chain.

## Structure

```
   f: A → B         g: B → C
        │                │
        └─── compose ────┘
              A → C

  pipe(f, g, h) = x → h(g(f(x)))   (left-to-right, readable order)
  compose(h, g, f) = x → h(g(f(x))) (right-to-left, math notation)
```

---

## Real-World Use Case: Event Processing Pipeline

A streaming platform processes raw clickstream events: normalise → deduplicate → enrich → classify → route.

### Java — Function.andThen and compose

```java
import java.util.function.Function;
import java.util.function.Predicate;

// Each step is a pure Function<Input, Output>
Function<RawEvent, NormalisedEvent>  normalise    = RawEvent::normalise;
Function<NormalisedEvent, NormalisedEvent> deduplicate = DeduplicationService::deduplicate;
Function<NormalisedEvent, EnrichedEvent>  enrich      = EnrichmentService::enrich;
Function<EnrichedEvent, ClassifiedEvent> classify    = ClassificationService::classify;
Function<ClassifiedEvent, RoutedEvent>   route       = RoutingService::route;

// andThen: left-to-right composition (f.andThen(g) = g(f(x)))
Function<RawEvent, RoutedEvent> pipeline =
    normalise
        .andThen(deduplicate)
        .andThen(enrich)
        .andThen(classify)
        .andThen(route);

// Process all events
List<RoutedEvent> results = events.stream()
    .map(pipeline)
    .collect(toList());

// compose: right-to-left (g.compose(f) = g(f(x)))
Function<RawEvent, RoutedEvent> pipelineAlt =
    route.compose(classify).compose(enrich).compose(deduplicate).compose(normalise);

// Building a configurable validation pipeline
public class ValidationPipelineBuilder<T> {
    private Function<T, T> pipeline = Function.identity();

    public ValidationPipelineBuilder<T> addStep(Function<T, T> step) {
        pipeline = pipeline.andThen(step);
        return this;
    }

    public Function<T, T> build() { return pipeline; }
}

Function<PaymentRequest, PaymentRequest> validator = new ValidationPipelineBuilder<PaymentRequest>()
    .addStep(req -> req.withNormalisedCurrency())
    .addStep(req -> req.withClampedAmount(MIN_AMOUNT, MAX_AMOUNT))
    .addStep(req -> req.withSanitisedCardNumber())
    .build();

// Predicate composition — boolean logic
Predicate<User> isActive   = user -> user.status() == ACTIVE;
Predicate<User> isPremium  = user -> user.tier() == PREMIUM;
Predicate<User> isVerified = user -> user.isEmailVerified();

Predicate<User> eligibleForPromo = isActive.and(isPremium).and(isVerified);
Predicate<User> needsOnboarding  = isActive.and(isPremium.negate().or(isVerified.negate()));

List<User> promoUsers = users.stream().filter(eligibleForPromo).collect(toList());
```

### Kotlin — extension functions and function references

```kotlin
// Kotlin infix operator for composition
infix fun <A, B, C> ((A) -> B).then(g: (B) -> C): (A) -> C = { a -> g(this(a)) }
infix fun <A, B, C> ((B) -> C).after(f: (A) -> B): (A) -> C = { a -> this(f(a)) }

// Pure step functions
val normalise:   (RawEvent) -> NormalisedEvent     = RawEvent::normalise
val enrich:      (NormalisedEvent) -> EnrichedEvent = ::enrichEvent
val classify:    (EnrichedEvent) -> ClassifiedEvent = ::classifyEvent
val route:       (ClassifiedEvent) -> RoutedEvent   = ::routeEvent

// Pipeline via infix composition
val pipeline: (RawEvent) -> RoutedEvent =
    normalise then enrich then classify then route

// Using it
val results: List<RoutedEvent> = events.map(pipeline)

// also/let/run as mini-pipelines on a single value
val enrichedEvent = rawEvent
    .let { normalise(it) }
    .let { enrich(it) }
    .let { classify(it) }

// Function references as configuration
data class TransformConfig(
    val steps: List<(Event) -> Event>
)

fun applyPipeline(event: Event, config: TransformConfig): Event =
    config.steps.fold(event) { acc, step -> step(acc) }
```

### Python — functools, operator, and custom pipe

```python
from functools import reduce
from typing import Callable, TypeVar

A = TypeVar('A')
B = TypeVar('B')
C = TypeVar('C')

# compose: right-to-left (mathematical convention)
def compose(*fns):
    """compose(h, g, f)(x) == h(g(f(x)))"""
    return reduce(lambda f, g: lambda *args: f(g(*args)), fns)

# pipe: left-to-right (readable pipeline order)
def pipe(*fns):
    """pipe(f, g, h)(x) == h(g(f(x)))"""
    return reduce(lambda f, g: lambda *args: g(f(*args)), fns)

# Step functions
def normalise(event: dict) -> dict:
    return {**event, 'timestamp': event['ts'].isoformat()}

def enrich(event: dict) -> dict:
    user = user_repo.find(event['user_id'])
    return {**event, 'user_email': user.email if user else None}

def classify(event: dict) -> dict:
    return {**event, 'category': classifier.predict(event)}

def route(event: dict) -> dict:
    return {**event, 'destination': router.select(event['category'])}

# Build and apply pipeline
process_event = pipe(normalise, enrich, classify, route)

routed_events = list(map(process_event, raw_events))

# Class-based pipeline for configuration
class Pipeline:
    def __init__(self):
        self._steps: list[Callable] = []

    def add(self, fn: Callable) -> 'Pipeline':
        self._steps.append(fn)
        return self

    def __call__(self, value):
        return reduce(lambda v, fn: fn(v), self._steps, value)

pipeline = (
    Pipeline()
        .add(normalise)
        .add(enrich)
        .add(classify)
        .add(route)
)

# Python decorators are function composition
import functools

def retry(times):
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            for attempt in range(times):
                try:
                    return fn(*args, **kwargs)
                except Exception as e:
                    if attempt == times - 1:
                        raise
        return wrapper
    return decorator

def log_call(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        print(f"Calling {fn.__name__}")
        result = fn(*args, **kwargs)
        print(f"{fn.__name__} returned {result}")
        return result
    return wrapper

# Two decorators = two composed functions
@log_call
@retry(3)
def fetch_user(user_id: str):
    return http_client.get(f"/users/{user_id}")
# equivalent to: fetch_user = log_call(retry(3)(fetch_user))
```

### JavaScript / TypeScript — pipe and compose

```typescript
// pipe: left-to-right (most readable)
const pipe = <T>(...fns: Array<(arg: T) => T>) =>
    (value: T): T => fns.reduce((acc, fn) => fn(acc), value);

// compose: right-to-left
const compose = <T>(...fns: Array<(arg: T) => T>) =>
    (value: T): T => fns.reduceRight((acc, fn) => fn(acc), value);

// Type-safe pipe with overloads (handles type transitions)
function typedPipe<A, B>(f: (a: A) => B): (a: A) => B;
function typedPipe<A, B, C>(f: (a: A) => B, g: (b: B) => C): (a: A) => C;
function typedPipe<A, B, C, D>(f: (a: A) => B, g: (b: B) => C, h: (c: C) => D): (a: A) => D;
function typedPipe(...fns: any[]) {
    return (value: any) => fns.reduce((acc, fn) => fn(acc), value);
}

// Pipeline
const processEvent = typedPipe(
    normalise,     // RawEvent → NormalisedEvent
    enrich,        // NormalisedEvent → EnrichedEvent
    classify,      // EnrichedEvent → ClassifiedEvent
    route          // ClassifiedEvent → RoutedEvent
);

const results: RoutedEvent[] = rawEvents.map(processEvent);

// RxJS — reactive function composition
import { pipe as rxPipe, map, filter, mergeMap } from 'rxjs/operators';

const processStream = rxPipe(
    filter((e: RawEvent) => e.type !== 'HEARTBEAT'),
    map(normalise),
    mergeMap(async e => enrich(e)),     // async enrichment
    map(classify),
    map(route)
);

eventStream$.pipe(processStream).subscribe(routedEvents$);
```

---

## Point-Free Style

```typescript
// Point-free: don't name intermediate arguments
// Instead of:
const processedEmails = users.map(user => user.email.toLowerCase().trim());

// Point-free (compose operations, not values):
const getEmail    = (user: User) => user.email;
const toLower     = (s: string) => s.toLowerCase();
const trim        = (s: string) => s.trim();
const normaliseEmail = typedPipe(getEmail, toLower, trim);

const processedEmails = users.map(normaliseEmail);
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each function in the pipeline does exactly one thing |
| Open/Closed | ✅ | Insert or remove pipeline steps without modifying others |
| Liskov Substitution | ✅ | Any step with matching type signature is interchangeable |
| Interface Segregation | ✅ | Steps are just `A → B` functions — minimal contract |
| Dependency Inversion | ✅ | Pipeline depends on function types, not concrete implementations |

---

## When to Use

- You have a sequence of transformations where the output of one is the input of the next
- Individual steps are independently useful and testable
- You need to configure or vary the pipeline at runtime (add/remove steps from config)

## When NOT to Use

- Steps have side effects — composition hides when effects run
- The pipeline has branching logic — use a state machine or Strategy instead
- Team is unfamiliar with FP — an explicit for-loop or class-based pipeline is clearer

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Pipeline reads like a specification — intent is clear | Type inference across many steps can become complex |
| Each step independently unit-testable | Debugging: hard to set breakpoints inside a composed pipeline |
| Adding/removing steps doesn't touch other steps | Point-free style can be cryptic without good names |
| Same pattern across sync, async (Promise), reactive (RxJS) | |

---

**FAANG interview application**: "Function composition is the right design when I have a sequence of transformations where each step is independently valuable. In a data pipeline — normalise, enrich, classify, route — each step is a pure function, the pipeline is their composition. The benefit over a monolithic method: I can test each step in isolation, insert a new step without touching others, and configure the pipeline from feature flags. In Java I use `Function.andThen`, in Kotlin I build an infix `then` operator, in Python `functools.reduce`, in JS `pipe` from fp-ts or a trivial implementation."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Functor](33-functor.md) | `map` applies a composed function inside a wrapper |
| [Currying & Partial Application](38-currying-partial-application.md) | Currying produces functions suitable for composition |
| [Strategy](../behavioral/20-strategy.md) | Strategy is OOP's equivalent — swap a step; composition swaps a function |
| [Chain of Responsibility](../behavioral/13-chain-of-responsibility.md) | OOP pipeline with handler objects vs FP pipeline with pure functions |
| [Decorator](../structural/09-decorator.md) | Runtime behaviour stacking; composition stacks transforms statically |
