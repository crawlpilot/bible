# 33. Functor
**Category**: Functional Programming  
**GoF**: No (Category Theory / FP)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> A Functor is any type that wraps a value and supports a `map` operation — apply a function to the wrapped value and return the same wrapper type with the transformed value, without unwrapping it.

---

## Problem It Solves

You have a list of user IDs, and you want to fetch each user's email. Without Functor thinking, you write a loop, manually unwrap each element, transform it, and re-wrap into a new list. With Functor, you call `map` — the wrapping, iteration, and re-wrapping are handled by the container. The same principle applies to `Optional` (map only runs if the value is present), `Promise`/`Future` (map runs when the async value resolves), and `Stream` (map is applied lazily to each element). The key invariant: **the wrapper structure is preserved, only the inner value changes type**.

## Structure

```
        «interface / typeclass»
            Functor<A>
    ┌───────────────────────────┐
    │ + map(f: A → B): Functor<B>│
    └───────────────────────────┘
              △
    ┌─────────┼──────────────┐
    │         │              │
 List<A>  Optional<A>   Future<A>
```

### Functor Laws

| Law | Meaning |
|-----|---------|
| Identity | `map(x → x)` == original functor |
| Composition | `map(g ∘ f)` == `map(f).map(g)` |

These laws ensure `map` never changes structure — only value.

---

## Real-World Use Case: Order Processing Pipeline

An e-commerce platform receives orders, enriches each order with user data, applies discounts, then formats for the invoice service. Each step is a pure function. The `List` functor chains transformations without intermediate variables.

### Java — Stream as Functor

```java
// Each transformation is a pure function; Stream.map is the functor operation
List<Invoice> invoices = orderRepository.findAll()                    // List<Order>
    .stream()
    .map(order -> enrichWithUser(order, userService))                 // Order → EnrichedOrder
    .map(enriched -> applyDiscounts(enriched, promotionService))      // EnrichedOrder → DiscountedOrder
    .map(discounted -> toInvoiceDto(discounted))                      // DiscountedOrder → Invoice
    .collect(toList());

// Optional.map — functor over nullable values
public Optional<String> getUserEmail(String userId) {
    return userRepository.findById(userId)          // Optional<User>
        .map(User::getEmail)                        // Optional<String>  — runs only if present
        .map(String::toLowerCase);                  // Optional<String>  — chains safely
}

// Without Optional.map (imperative — brittle)
public String getUserEmailImperative(String userId) {
    User user = userRepository.findById(userId);
    if (user == null) return null;
    String email = user.getEmail();
    if (email == null) return null;
    return email.toLowerCase();                     // null-check explosion
}
```

### Kotlin — map on nullable and collections

```kotlin
// Kotlin nullable is a functor: ?.let is map
fun getUserEmail(userId: String): String? =
    userRepository.findById(userId)   // User?
        ?.email                       // String?  — map(User::email)
        ?.lowercase()                 // String?  — map(String::lowercase)

// Extension function as functor operation
data class Money(val amount: BigDecimal, val currency: String)

fun List<Order>.totalRevenue(): Money =
    map { it.total }                  // List<Money>
        .reduce { acc, m -> acc + m }
```

### Python — map and list comprehension

```python
from typing import Optional, List
from dataclasses import dataclass

@dataclass
class Order:
    id: str
    user_id: str
    amount: float

# map() is the functor operation on iterables
def enrich_orders(orders: List[Order]) -> List[dict]:
    return list(
        map(lambda o: {**vars(o), "email": fetch_email(o.user_id)}, orders)
    )

# List comprehension — idiomatic Python functor
invoices = [
    format_invoice(apply_discount(enrich(order)))
    for order in orders
]

# Optional as functor using walrus operator and chaining
def get_user_email(user_id: str) -> Optional[str]:
    user = user_repository.find(user_id)          # Optional[User]
    return user.email.lower() if user and user.email else None

# Cleaner with a small Maybe helper (or use returns/option libraries)
class Maybe:
    def __init__(self, value):
        self._value = value

    def map(self, f):
        if self._value is None:
            return Maybe(None)
        return Maybe(f(self._value))

    def get_or(self, default):
        return self._value if self._value is not None else default

# Usage
email = Maybe(user_repository.find(user_id)) \
    .map(lambda u: u.email) \
    .map(str.lower) \
    .get_or("unknown@example.com")
```

### JavaScript / TypeScript — Array and Promise as functors

```typescript
// Array.map — canonical functor
const invoices: Invoice[] = orders
    .map(order => enrichWithUser(order, userService))       // Order → EnrichedOrder
    .map(enriched => applyDiscounts(enriched))              // EnrichedOrder → DiscountedOrder
    .map(discounted => toInvoiceDto(discounted));           // DiscountedOrder → Invoice

// Promise.then is map for async values
const userEmail: Promise<string> = fetchUser(userId)       // Promise<User>
    .then(user => user.email)                              // Promise<string>
    .then(email => email.toLowerCase());                   // Promise<string>

// Optional chaining — JS native functor for nullable
const email = user?.profile?.email?.toLowerCase() ?? "unknown";

// Generic Functor interface in TypeScript
interface Functor<A> {
    map<B>(f: (a: A) => B): Functor<B>;
}

class Box<A> implements Functor<A> {
    constructor(private readonly value: A) {}

    map<B>(f: (a: A) => B): Box<B> {
        return new Box(f(this.value));
    }

    getValue(): A { return this.value; }
}

// Usage
const discountedPrice = new Box(100)
    .map(price => price * 0.9)
    .map(price => Math.round(price))
    .getValue();  // 90
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each `map` step does one transformation; container handles wrapping |
| Open/Closed | ✅ | New transformations via new functions — no modification to the functor |
| Liskov Substitution | ✅ | All functors satisfy the same map contract |
| Interface Segregation | ✅ | `map` is the only required operation |
| Dependency Inversion | ✅ | Transformations depend on pure functions, not concrete containers |

---

## When to Use

- You want to transform values inside a container (list, optional, future) without manual unwrapping
- You are building a transformation pipeline where each step is a pure function
- You want to propagate absence (`None`/`null`) or pending state (`Promise`) without explicit checks at each step

## When NOT to Use

- The transformation itself returns a wrapped value — use `flatMap` (Monad) instead, or you get double-wrapping (`Optional<Optional<T>>`)
- Side effects are needed inside the map — use `forEach` or `peek`, not `map`
- The container doesn't satisfy functor laws (e.g., a custom container that mutates structure during map)

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Eliminates explicit loops and null checks | Mental model shift for imperative developers |
| Transformation pipeline reads like a specification | Stack traces through map chains can be harder to read |
| Functor laws guarantee predictable composition | Not all languages enforce these laws at the type level |

---

**FAANG interview application**: "Every collection transformation, Optional chain, and Promise `.then` in your codebase is a Functor in action. The value of naming it: `map` communicates that structure is preserved and no side effects occur. When I see a chain of `.map()` calls I know the type of the container doesn't change and each step is independently testable. The interviewer signal: can you explain why `Optional.map` and `Stream.map` and `Promise.then` are the same concept? Answer: all three are functors — apply a function inside a wrapper, return the same wrapper."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Monad](34-monad.md) | Monad extends Functor with `flatMap` to handle nested wrappers |
| [Maybe / Option](35-maybe-option.md) | Maybe is a specific Functor for null safety |
| [Lazy Evaluation](40-lazy-evaluation.md) | `Stream.map` is a lazy functor — transformation deferred until terminal op |
| [Function Composition](37-function-composition.md) | Functions composed with `andThen`/`pipe` are often applied inside a functor |
