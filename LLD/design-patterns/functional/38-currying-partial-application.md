# 38. Currying & Partial Application
**Category**: Functional Programming  
**GoF**: No (Lambda Calculus / FP)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Occasional

> **Currying** transforms a function of multiple arguments into a chain of single-argument functions: `f(a, b, c)` becomes `f(a)(b)(c)`. **Partial Application** fixes some arguments now to produce a new function that accepts the rest: `f(a, ?, ?)` becomes `g(b, c)`.

---

## Problem It Solves

You have a generic `sendEmail(template, recipient, data)` function. Different parts of the system always use the same template but vary the recipient and data. Without partial application, callers must always repeat `template` or introduce a wrapper class. With partial application, you create `sendWelcomeEmail = sendEmail.bind(null, "welcome")` — a specialised function that only asks for what changes. This is **dependency injection without objects**: bake in the fixed parameters up front, distribute the specialised function.

The second use case: curried functions are **composable** — `f(a)(b)(c)` fits naturally into a pipeline where each step expects a single argument.

## Structure

```
Multi-arg function            Curried form
f(a, b, c): R    →    f(a): (b) → (c) → R
                              │
                              f(a)(b): (c) → R
                                       │
                                       f(a)(b)(c): R

Partial Application
f(a, b, c): R    →    partial(f, a): (b, c) → R
```

---

## Real-World Use Case: Configurable Data Transformer

A data platform has a generic `transform(schema, validator, data)` function. Schemas and validators are known at startup; data arrives at runtime. Partial application bakes in schema + validator at startup, producing a fast, clean per-record function.

### Java — partial application via lambdas and method references

```java
// Java doesn't have native currying, but lambdas + BiFunction achieve it
import java.util.function.*;

// Generic three-arg function via chained functions
@FunctionalInterface
interface TriFunction<A, B, C, R> {
    R apply(A a, B b, C c);
}

// Currying helper
public static <A, B, C, R> Function<A, Function<B, Function<C, R>>> curry(TriFunction<A, B, C, R> f) {
    return a -> b -> c -> f.apply(a, b, c);
}

// Partial application helper
public static <A, B, R> Function<B, R> partial(BiFunction<A, B, R> f, A a) {
    return b -> f.apply(a, b);
}

// Use case: sending notifications
BiFunction<String, User, Boolean> sendNotification =
    (template, user) -> notificationService.send(template, user);

// Specialise at startup — bake in the template
Function<User, Boolean> sendWelcome = partial(sendNotification, "welcome-email");
Function<User, Boolean> sendPasswordReset = partial(sendNotification, "password-reset");

// Distribute specialised functions — callers only provide User
users.stream()
    .filter(User::isNew)
    .forEach(sendWelcome::apply);

// Builder pattern comparison — partial application is leaner
// OOP: new NotificationSender(template)  // object with baked-in config
// FP:  partial(sendNotification, template) // function with baked-in config

// Request authorisation — bake in the permission check context
BiFunction<Permission, Request, Boolean> authorise =
    (permission, request) -> authService.check(request.getUser(), permission);

Function<Request, Boolean> authoriseRead  = partial(authorise, Permission.READ);
Function<Request, Boolean> authoriseWrite = partial(authorise, Permission.WRITE);
Function<Request, Boolean> authoriseAdmin = partial(authorise, Permission.ADMIN);

// Curried price calculation
Function<Double, Function<Double, Double>> applyDiscount =
    discountPct -> price -> price * (1 - discountPct / 100);

Function<Double, Double> apply10PctOff = applyDiscount.apply(10.0);
Function<Double, Double> apply20PctOff = applyDiscount.apply(20.0);

double discountedPrice = apply10PctOff.apply(99.99);  // 89.99
```

### Kotlin — extension functions and function references

```kotlin
// Kotlin closures are partial application
fun sendNotification(template: String, user: User): Boolean =
    notificationService.send(template, user)

// Partial application via lambda capturing
val sendWelcome: (User) -> Boolean = { user -> sendNotification("welcome-email", user) }
val sendPasswordReset: (User) -> Boolean = { user -> sendNotification("password-reset", user) }

// Generic partial application extension
fun <A, B, C> ((A, B) -> C).partial(a: A): (B) -> C = { b -> this(a, b) }

val authorise: (Permission, Request) -> Boolean = { perm, req ->
    authService.check(req.user, perm)
}
val authoriseRead  = authorise.partial(Permission.READ)
val authoriseWrite = authorise.partial(Permission.WRITE)

// Higher-order functions with receiver — elegant DI
fun buildValidator(config: ValidationConfig): (Order) -> ValidationResult = { order ->
    with(config) {
        when {
            order.amount < minAmount -> ValidationResult.Fail("Below minimum: $minAmount")
            order.amount > maxAmount -> ValidationResult.Fail("Above maximum: $maxAmount")
            !allowedCurrencies.contains(order.currency) -> ValidationResult.Fail("Unsupported currency")
            else -> ValidationResult.Pass
        }
    }
}

// At startup: bake in config
val validateOrder: (Order) -> ValidationResult = buildValidator(
    ValidationConfig(minAmount = 1.0, maxAmount = 50_000.0, allowedCurrencies = setOf("USD", "EUR"))
)

// At runtime: just pass the order
orders.map(validateOrder)

// Curried form using Kotlin
fun <A, B, C> curry(f: (A, B) -> C): (A) -> (B) -> C = { a -> { b -> f(a, b) } }

val curriedSend = curry(::sendNotification)    // (String) -> (User) -> Boolean
val sendPromo   = curriedSend("promo-email")   // (User) -> Boolean
users.forEach { sendPromo(it) }
```

### Python — functools.partial and closures

```python
from functools import partial, reduce
from typing import Callable, TypeVar

A = TypeVar('A')
B = TypeVar('B')

# functools.partial — standard library partial application
def send_notification(template: str, user: dict, locale: str = 'en') -> bool:
    return notification_service.send(template, user, locale)

# Bake in the template at startup
send_welcome       = partial(send_notification, 'welcome-email')
send_password_reset = partial(send_notification, 'password-reset')
send_promo_en      = partial(send_notification, 'promo', locale='en')
send_promo_fr      = partial(send_notification, 'promo', locale='fr')

# Distribute — callers only provide user
for user in new_users:
    send_welcome(user)

# Closure as partial application
def make_validator(min_val: float, max_val: float) -> Callable[[float], bool]:
    """Returns a function with min_val and max_val baked in."""
    def validate(value: float) -> bool:
        return min_val <= value <= max_val
    return validate

validate_age    = make_validator(0, 150)
validate_rating = make_validator(0, 5)
validate_price  = make_validator(0.01, 999_999.99)

# Currying — transform f(a, b) into f(a)(b)
def curry(f):
    """Curry a two-argument function."""
    return lambda a: lambda b: f(a, b)

@curry
def add(a: int, b: int) -> int:
    return a + b

add5 = add(5)              # partial: (int) -> int
result = add5(3)           # 8

# Multi-arg currying with inspect
import inspect

def autocurry(f):
    n = len(inspect.signature(f).parameters)
    def curried(*args):
        if len(args) >= n:
            return f(*args)
        return lambda *more: curried(*(args + more))
    return curried

@autocurry
def transform(schema, validator, data):
    validated = validator(data)
    return schema.apply(validated)

# At startup
transform_order = transform(order_schema, order_validator)  # bakes in schema + validator
# At runtime
results = list(map(transform_order, raw_orders))

# Decorators ARE partial application of the decorator function
def rate_limit(max_calls: int, period: float):
    """Partial application: bake in rate limit params."""
    def decorator(fn):
        call_times = []
        def wrapper(*args, **kwargs):
            now = time.time()
            call_times[:] = [t for t in call_times if now - t < period]
            if len(call_times) >= max_calls:
                raise RateLimitExceeded()
            call_times.append(now)
            return fn(*args, **kwargs)
        return wrapper
    return decorator

@rate_limit(max_calls=100, period=60.0)   # partial: bake in limits
def search_products(query: str): ...
```

### JavaScript / TypeScript — native closures and bind

```typescript
// JavaScript closures ARE partial application
function sendNotification(template: string, user: User, locale = 'en'): boolean {
    return notificationService.send(template, user, locale);
}

// Closure-based partial application
const sendWelcome       = (user: User) => sendNotification('welcome-email', user);
const sendPasswordReset = (user: User) => sendNotification('password-reset', user);

// Function.prototype.bind — native partial application
const sendPromoEn = sendNotification.bind(null, 'promo-email', undefined, 'en');

// Generic partial helper
function partial<A extends any[], B extends any[], R>(
    f: (...args: [...A, ...B]) => R,
    ...partialArgs: A
): (...args: B) => R {
    return (...remainingArgs) => f(...partialArgs, ...remainingArgs);
}

// Currying
function curry<A, B, C>(f: (a: A, b: B) => C): (a: A) => (b: B) => C {
    return a => b => f(a, b);
}

const curriedDiscount = curry((pct: number, price: number) => price * (1 - pct / 100));
const apply15PctOff = curriedDiscount(15);  // (price: number) => number
const apply30PctOff = curriedDiscount(30);

const salePrice = apply15PctOff(199.99);   // 169.99

// React: partial application for event handlers — avoid inline lambdas in render
const handleDeleteItem = (itemId: string) => () => dispatch(deleteItem(itemId));
// <button onClick={handleDeleteItem(item.id)}>Delete</button>
// Equivalent: onClick={partial(dispatch, deleteItem(item.id))}

// Higher-order component / hook — config baked in
function createApiClient(baseUrl: string, token: string) {
    const get    = (path: string) => fetch(`${baseUrl}${path}`, { headers: { Authorization: token } });
    const post   = (path: string, body: any) => fetch(`${baseUrl}${path}`, { method: 'POST', body: JSON.stringify(body), headers: { Authorization: token } });
    return { get, post };
}

// baseUrl and token baked in at startup — distributed functions need no config
const apiClient = createApiClient('https://api.example.com', process.env.API_TOKEN!);
apiClient.get('/users');
```

---

## Currying vs Partial Application — Precise Distinction

| | Currying | Partial Application |
|---|---------|---------------------|
| Transformation | `f(a,b,c)` → `f(a)(b)(c)` | `f(a,b,c)` → `g(b,c)` |
| Argument count | Each call takes exactly **one** argument | Fix **some** args; rest taken as a group |
| Output | A chain of unary functions | A single function with fewer params |
| Use case | Function composition pipelines | Specialising a general function |
| Language support | Native in Haskell, Scala; manual in others | `functools.partial`, `.bind()`, closures |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each function has one job; partial application specialises without adding responsibility |
| Open/Closed | ✅ | New specialisations are new partially-applied functions — base function unchanged |
| Liskov Substitution | ✅ | Partially applied `f(a)` substitutable anywhere `(b) → R` is expected |
| Interface Segregation | ✅ | Callers receive only the interface they need (fewer parameters) |
| Dependency Inversion | ✅ | Baked-in dependencies are injected via closure, not via constructor |

---

## When to Use

- You have a general function and multiple callers that always provide the same subset of arguments
- You want to inject dependencies into a function without creating a class (FP-style DI)
- You are building a pipeline where steps must be unary (currying enables this)

## When NOT to Use

- The "fixed" arguments change frequently — partial application buys nothing
- The team is unfamiliar with closures — a simple class with constructor injection is clearer
- More than 3–4 levels of currying — readability drops sharply

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| DI without classes — no boilerplate objects just to carry config | Closures capture by reference — mutation of captured state is a hidden dependency |
| Specialised functions are smaller API surfaces | Deeply curried functions are hard to read in stack traces |
| Composable — unary functions compose directly | Not idiomatic in OOP codebases; team resistance |

---

**FAANG interview application**: "I use partial application when I have a general function and need several specialised versions — `sendWelcomeEmail`, `sendPromoEmail` are all `partial(sendEmail, template)`. This is dependency injection without a class: bake in the fixed dependency (template) at composition root, distribute the specialised function. In Python `functools.partial` handles this natively. In Kotlin closures capture config cleanly. The distinction from currying: partial application fixes multiple args at once; currying transforms to a chain of unary functions, enabling composition in pipelines."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Function Composition](37-function-composition.md) | Curried (unary) functions compose directly in a pipeline |
| [Strategy](../behavioral/20-strategy.md) | Strategy swaps algorithms via objects; partial application swaps via functions |
| [Factory Method](../creational/02-factory-method.md) | Both create specialised versions of a general thing; one uses objects, one uses functions |
