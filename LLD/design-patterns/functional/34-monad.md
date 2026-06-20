# 34. Monad
**Category**: Functional Programming  
**GoF**: No (Category Theory / FP)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> A Monad is a Functor that also supports `flatMap` (also called `bind` or `chain`) — composing operations where each step returns a wrapped value, without ending up with nested wrappers.

---

## Problem It Solves

You have a `findUser(id): Optional<User>` and a `findOrder(user): Optional<Order>`. If you chain with plain `map`, you get `Optional<Optional<Order>>` — a nested wrapper you must manually unwrap. `flatMap` flattens the nesting: it applies the function and unwraps one layer, giving `Optional<Order>`. The same problem appears with:
- **Async**: `fetchUser(): Promise<User>` then `fetchOrders(user): Promise<Order[]>` — chaining with `.then` (flatMap) avoids `Promise<Promise<Order[]>>`
- **Error propagation**: if any step fails, the failure propagates automatically without explicit checks at each step
- **Stream**: `flatMap` expands one element into many, flattening the resulting nested streams

**One sentence**: Monad = Functor + `flatMap` + the guarantee that `flatMap(pure)` is a no-op.

## Structure

```
        «interface / typeclass»
            Monad<A>
    ┌──────────────────────────────────┐
    │ + map(f: A → B): Monad<B>        │  ← inherited from Functor
    │ + flatMap(f: A → Monad<B>): Monad<B> │  ← the key addition
    │ + pure(a: A): Monad<A>           │  ← lift a value into the monad
    └──────────────────────────────────┘
              △
    ┌─────────┼──────────────────────┐
    │         │           │          │
 Optional   Promise    Stream     Either
  (null)   (async)   (multi)   (error)
```

### Monad Laws

| Law | Meaning |
|-----|---------|
| Left identity | `pure(a).flatMap(f)` == `f(a)` |
| Right identity | `m.flatMap(pure)` == `m` |
| Associativity | `m.flatMap(f).flatMap(g)` == `m.flatMap(a → f(a).flatMap(g))` |

---

## Real-World Use Case: Order Fulfilment Chain

Fetching a user, then their address, then validating the address, then creating a shipment — each step can be absent or fail. Monad chains propagate the first absent/failure automatically.

### Java — Optional and Stream flatMap

```java
// map vs flatMap — understanding the difference
Optional<User> optUser = userRepo.findById(userId);  // Optional<User>

// WRONG: map returns Optional<Optional<Address>>
Optional<Optional<Address>> nested = optUser.map(user -> addressRepo.findPrimary(user.getId()));

// RIGHT: flatMap flattens to Optional<Address>
Optional<Address> address = optUser.flatMap(user -> addressRepo.findPrimary(user.getId()));

// Chaining multiple flatMap steps — Railway-oriented
public Optional<Shipment> createShipment(String userId) {
    return userRepo.findById(userId)                          // Optional<User>
        .flatMap(user -> addressRepo.findPrimary(user.getId())) // Optional<Address>
        .flatMap(addr -> validateAddress(addr))               // Optional<ValidAddress>
        .flatMap(valid -> shipmentService.create(valid));     // Optional<Shipment>
    // If ANY step returns empty, the whole chain short-circuits to Optional.empty()
    // Zero explicit null checks
}

// Stream.flatMap — expand one order into its line items
List<LineItem> allLineItems = orders.stream()
    .flatMap(order -> order.getLineItems().stream())  // Order → Stream<LineItem>
    .filter(item -> item.getQuantity() > 0)
    .collect(toList());

// CompletableFuture — async monad
CompletableFuture<Shipment> asyncCreateShipment(String userId) {
    return userService.fetchAsync(userId)                               // CF<User>
        .thenCompose(user -> addressService.fetchPrimaryAsync(user))   // CF<Address>
        .thenCompose(addr -> addressValidator.validateAsync(addr))     // CF<ValidAddress>
        .thenCompose(valid -> shipmentService.createAsync(valid));     // CF<Shipment>
    // thenCompose is flatMap for CompletableFuture
    // thenApply is map for CompletableFuture
}
```

### Kotlin — let, flatMap, and coroutines

```kotlin
// Kotlin nullable type as monad: let is flatMap for T?
fun createShipment(userId: String): Shipment? =
    userRepo.findById(userId)                              // User?
        ?.let { user -> addressRepo.findPrimary(user.id) } // Address?  (flatMap)
        ?.let { addr -> validateAddress(addr) }            // ValidAddress?
        ?.let { valid -> shipmentService.create(valid) }   // Shipment?

// Result<T> as monad (Kotlin stdlib)
fun createShipmentResult(userId: String): Result<Shipment> =
    runCatching { userRepo.findById(userId) ?: error("User not found") }
        .mapCatching { user -> addressRepo.findPrimary(user.id) ?: error("Address missing") }
        .mapCatching { addr -> validateAddress(addr) }
        .mapCatching { valid -> shipmentService.create(valid) }

// Coroutines — sequential async without callback nesting
suspend fun createShipmentAsync(userId: String): Shipment {
    val user    = userService.fetchAsync(userId)     // suspends; no nesting
    val address = addressService.fetchAsync(user)    // suspends
    val valid   = addressValidator.validate(address) // suspends
    return shipmentService.create(valid)             // no flatMap boilerplate needed
}
// Coroutines ARE monadic — suspend functions are syntactic sugar for flatMap chains
```

### Python — chaining with generators and Optional-style

```python
from typing import Optional, TypeVar, Callable, Generic

A = TypeVar('A')
B = TypeVar('B')

class Maybe(Generic[A]):
    """Minimal monad implementation."""
    def __init__(self, value: Optional[A]):
        self._value = value

    @classmethod
    def of(cls, value: Optional[A]) -> 'Maybe[A]':
        return cls(value)

    def map(self, f: Callable[[A], B]) -> 'Maybe[B]':
        if self._value is None:
            return Maybe(None)
        return Maybe(f(self._value))

    def flat_map(self, f: Callable[[A], 'Maybe[B]']) -> 'Maybe[B]':
        if self._value is None:
            return Maybe(None)
        return f(self._value)  # f already returns a Maybe — no double-wrapping

    def get_or(self, default: A) -> A:
        return self._value if self._value is not None else default

# Usage — zero explicit None checks
shipment = (
    Maybe.of(user_repo.find(user_id))
        .flat_map(lambda user: Maybe.of(address_repo.find_primary(user.id)))
        .flat_map(lambda addr: validate_address(addr))   # returns Maybe[ValidAddress]
        .flat_map(lambda valid: shipment_service.create(valid))
        .get_or(None)
)

# Generator pipeline as a monad-like structure
def process_orders(user_ids):
    """Each yield can be thought of as a monadic step."""
    for uid in user_ids:
        user = user_repo.find(uid)
        if user is None:
            continue                        # short-circuit for this element
        for order in order_repo.find_by_user(user.id):   # flatMap behaviour
            yield enrich_order(order)
```

### JavaScript / TypeScript — Promise chain as monad

```typescript
// Promise.then is flatMap when f returns a Promise
// Promise.then is map when f returns a plain value
// (JS auto-flattens, so .then works as both)

async function createShipment(userId: string): Promise<Shipment> {
    // async/await is syntactic sugar over Promise flatMap chains
    const user    = await fetchUser(userId);          // flatMap step
    const address = await fetchPrimaryAddress(user);  // flatMap step
    const valid   = await validateAddress(address);   // flatMap step
    return await shipmentService.create(valid);       // flatMap step
}

// Explicit Promise chain (the desugared monad)
function createShipmentChain(userId: string): Promise<Shipment> {
    return fetchUser(userId)                               // Promise<User>
        .then(user => fetchPrimaryAddress(user))           // Promise<Address>  (flatMap)
        .then(addr => validateAddress(addr))               // Promise<ValidAddress>
        .then(valid => shipmentService.create(valid));     // Promise<Shipment>
}

// Array.flatMap — monad for collections
const allTags: string[] = products
    .flatMap(product => product.tags);   // Product[] → string[] (flattened, not string[][])

// fp-ts Option monad (typed FP in TypeScript)
import { Option, some, none, chain } from 'fp-ts/Option'
import { pipe } from 'fp-ts/function'

const shipment: Option<Shipment> = pipe(
    userRepo.findById(userId),                          // Option<User>
    chain(user => addressRepo.findPrimary(user.id)),    // Option<Address>  (flatMap)
    chain(addr => validateAddress(addr)),               // Option<ValidAddress>
    chain(valid => shipmentService.create(valid))       // Option<Shipment>
)
```

---

## map vs flatMap — The Key Distinction

```
f: A → B          →  use map      →  Functor<B>
f: A → Functor<B> →  use flatMap  →  Functor<B>  (NOT Functor<Functor<B>>)
```

| Operation | Input function | Returns |
|-----------|---------------|---------|
| `map(f)` | `A → B` (plain value) | `Monad<B>` |
| `flatMap(f)` | `A → Monad<B>` (wrapped value) | `Monad<B>` (flattened) |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each `flatMap` step has exactly one job |
| Open/Closed | ✅ | New steps added to the chain without modifying existing steps |
| Liskov Substitution | ✅ | All monads satisfy the same flatMap contract |
| Interface Segregation | ✅ | `map` and `flatMap` are the minimal required operations |
| Dependency Inversion | ✅ | Steps depend on pure functions, not on orchestration logic |

---

## When to Use

- Chaining operations where each step returns a wrapped value (Optional, Promise, Result)
- You want automatic short-circuit on failure/absence without try-catch or null checks at each step
- Building async pipelines where each step is independently testable

## When NOT to Use

- You only need `map` — don't reach for monad complexity if no step returns a wrapped value
- The language already provides syntactic sugar (async/await, `?.`) that is clearer for your team
- Side-effectful code — monads work best with pure functions; mixing IO inside a monad chain loses the benefits

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Zero explicit null checks or try-catch in happy-path chain | Requires understanding of flatMap vs map distinction |
| Failure propagates automatically through the chain | Error context can be lost in Optional (use Either instead) |
| Each step is independently unit-testable as a pure function | Stack traces through flatMap chains are harder to follow |
| Consistent pattern across sync, async, collection contexts | Unfamiliar to developers with purely imperative background |

---

**FAANG interview application**: "When I see a chain of `flatMap` calls I know two things: every step returns a wrapped value (Optional, Future, Stream), and failures short-circuit without try-catch noise. `thenCompose` in CompletableFuture, `flatMap` on Optional, and `flatMap` on Stream are all the same monad operation. I use this when I need a clean pipeline where each step can fail — the alternative is nested null checks or try-catch ladders, which are harder to read and test. The important distinction in the interview: if `map` gives you `Optional<Optional<T>>`, you needed `flatMap`."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Functor](33-functor.md) | Monad extends Functor; `flatMap` is the extra operation |
| [Maybe / Option](35-maybe-option.md) | Maybe is a monad for null safety |
| [Either](36-either.md) | Either is a monad for typed error propagation |
| [Lazy Evaluation](40-lazy-evaluation.md) | `Stream.flatMap` is a lazy monad operation |
