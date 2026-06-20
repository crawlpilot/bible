# 36. Either (Railway-Oriented Programming)
**Category**: Functional Programming  
**GoF**: No (Haskell origins, widely adopted in Kotlin, Scala, TypeScript)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Occasional

> Either is a container with exactly two states — `Right` (success, the conventional "right" answer) and `Left` (failure, carrying the error) — enabling typed error handling as a value instead of thrown exceptions.

---

## Problem It Solves

Exceptions break the flow of function composition. A method that throws can't be safely passed to `map` — the caller must wrap it in try-catch, destroying the pipeline. `Optional` handles absence but loses the *reason* for absence. `Either<Error, Value>` carries both cases in one type:
- `Right<Value>` — computation succeeded; value is here
- `Left<Error>` — computation failed; reason is here

Operations chain through `Right` and short-circuit on the first `Left`. This is called **Railway-Oriented Programming** — the happy path is one rail, errors are a parallel rail, and any switch onto the error rail stays there.

```
Input → [step 1] → [step 2] → [step 3] → Right(result)
           ↓                              
        Left(error) ──────────────────→  Left(error)  (skips all subsequent steps)
```

## Structure

```
            Either<L, R>
    ┌──────────────────────────┐
    │ + map(f: R → R2): Either │   maps over Right; Left passes through
    │ + flatMap(f: R → Either) │   chains operations that return Either
    │ + mapLeft(f: L → L2)     │   maps over Left; Right passes through
    │ + fold(left, right)      │   extract value from either side
    │ + isRight(): bool        │
    └──────────────────────────┘
              △
    ┌───────────────────────┐
    │                       │
  Left<L>              Right<R>
 (failure/error)       (success/value)
```

---

## Real-World Use Case: Payment Processing Pipeline

Validating a payment request: parse the request, validate card details, check fraud rules, authorise with the payment gateway. Any step can fail with a distinct, typed error.

### Kotlin — Result<T> and custom Either

```kotlin
// Sealed class Either — idiomatic Kotlin
sealed class Either<out L, out R> {
    data class Left<L>(val value: L) : Either<L, Nothing>()
    data class Right<R>(val value: R) : Either<Nothing, R>()

    fun <R2> map(f: (R) -> R2): Either<L, R2> = when (this) {
        is Right -> Right(f(value))
        is Left  -> this
    }

    fun <R2> flatMap(f: (R) -> Either<L, R2>): Either<L, R2> = when (this) {
        is Right -> f(value)
        is Left  -> this
    }

    fun <T> fold(ifLeft: (L) -> T, ifRight: (R) -> T): T = when (this) {
        is Left  -> ifLeft(value)
        is Right -> ifRight(value)
    }
}

fun <R> right(value: R) = Either.Right(value)
fun <L> left(value: L)  = Either.Left(value)

// Domain errors — a sealed hierarchy, not strings
sealed class PaymentError {
    data class InvalidCard(val reason: String) : PaymentError()
    data class FraudDetected(val riskScore: Double) : PaymentError()
    data class GatewayError(val code: Int, val message: String) : PaymentError()
    object InsufficientFunds : PaymentError()
}

// Each step returns Either<PaymentError, T>
fun parsePaymentRequest(raw: RawRequest): Either<PaymentError, PaymentRequest> {
    if (raw.cardNumber.isBlank())
        return left(PaymentError.InvalidCard("Card number required"))
    if (!luhnCheck(raw.cardNumber))
        return left(PaymentError.InvalidCard("Invalid card number"))
    return right(PaymentRequest(raw.cardNumber, raw.amount, raw.currency))
}

fun validateCard(request: PaymentRequest): Either<PaymentError, ValidatedCard> {
    val card = cardService.lookup(request.cardNumber)
        ?: return left(PaymentError.InvalidCard("Card not found"))
    if (card.isExpired) return left(PaymentError.InvalidCard("Card expired"))
    return right(ValidatedCard(card, request.amount))
}

fun checkFraud(validated: ValidatedCard): Either<PaymentError, ValidatedCard> {
    val riskScore = fraudService.score(validated)
    return if (riskScore > 0.8)
        left(PaymentError.FraudDetected(riskScore))
    else
        right(validated)
}

fun authorise(validated: ValidatedCard): Either<PaymentError, AuthorisedPayment> {
    val response = gatewayClient.authorise(validated)
    return when (response.status) {
        "APPROVED"            -> right(AuthorisedPayment(response.transactionId, validated.amount))
        "INSUFFICIENT_FUNDS"  -> left(PaymentError.InsufficientFunds)
        else                  -> left(PaymentError.GatewayError(response.code, response.message))
    }
}

// The pipeline — clean, no try-catch, no null checks
class PaymentService {
    fun process(raw: RawRequest): Either<PaymentError, AuthorisedPayment> =
        parsePaymentRequest(raw)
            .flatMap { validated -> validateCard(validated) }
            .flatMap { card -> checkFraud(card) }
            .flatMap { checked -> authorise(checked) }

    fun processAndRespond(raw: RawRequest): ApiResponse =
        process(raw).fold(
            ifLeft = { error -> when (error) {
                is PaymentError.InvalidCard       -> ApiResponse.badRequest(error.reason)
                is PaymentError.FraudDetected     -> ApiResponse.forbidden("Transaction blocked")
                is PaymentError.GatewayError      -> ApiResponse.serviceUnavailable(error.message)
                PaymentError.InsufficientFunds    -> ApiResponse.paymentRequired("Insufficient funds")
            }},
            ifRight = { payment -> ApiResponse.ok(payment.transactionId) }
        )
}
```

### Java — implementing Either manually

```java
// Sealed interface (Java 17+)
public sealed interface Either<L, R> permits Either.Left, Either.Right {

    record Left<L, R>(L value) implements Either<L, R> {}
    record Right<L, R>(R value) implements Either<L, R> {}

    static <L, R> Either<L, R> left(L value)  { return new Left<>(value); }
    static <L, R> Either<L, R> right(R value) { return new Right<>(value); }

    default <R2> Either<L, R2> map(Function<R, R2> f) {
        return switch (this) {
            case Right<L, R> r -> Either.right(f.apply(r.value()));
            case Left<L, R>  l -> Either.left(l.value());
        };
    }

    default <R2> Either<L, R2> flatMap(Function<R, Either<L, R2>> f) {
        return switch (this) {
            case Right<L, R> r -> f.apply(r.value());
            case Left<L, R>  l -> Either.left(l.value());
        };
    }

    default <T> T fold(Function<L, T> ifLeft, Function<R, T> ifRight) {
        return switch (this) {
            case Left<L, R>  l -> ifLeft.apply(l.value());
            case Right<L, R> r -> ifRight.apply(r.value());
        };
    }
}

// Usage in payment processing
public Either<PaymentError, AuthorisedPayment> processPayment(RawRequest raw) {
    return parsePaymentRequest(raw)
        .flatMap(this::validateCard)
        .flatMap(this::checkFraud)
        .flatMap(this::authorise);
}
```

### Python — Result type pattern

```python
from typing import Generic, TypeVar, Callable, Union
from dataclasses import dataclass

L = TypeVar('L')
R = TypeVar('R')
R2 = TypeVar('R2')

class Either(Generic[L, R]):
    pass

@dataclass(frozen=True)
class Right(Either[L, R]):
    value: R

    def map(self, f: Callable[[R], R2]) -> 'Either[L, R2]':
        return Right(f(self.value))

    def flat_map(self, f: Callable[[R], 'Either[L, R2]']) -> 'Either[L, R2]':
        return f(self.value)

    def fold(self, if_left, if_right):
        return if_right(self.value)

    def is_right(self) -> bool:
        return True

@dataclass(frozen=True)
class Left(Either[L, R]):
    value: L

    def map(self, f) -> 'Either[L, R2]':
        return self  # pass through unchanged

    def flat_map(self, f) -> 'Either[L, R2]':
        return self  # pass through unchanged

    def fold(self, if_left, if_right):
        return if_left(self.value)

    def is_right(self) -> bool:
        return False

# Domain errors as typed classes
@dataclass(frozen=True)
class InvalidCardError:
    reason: str

@dataclass(frozen=True)
class FraudDetectedError:
    risk_score: float

PaymentError = Union[InvalidCardError, FraudDetectedError]

# Pipeline
def process_payment(raw: dict) -> Either:
    return (
        parse_request(raw)
            .flat_map(validate_card)
            .flat_map(check_fraud)
            .flat_map(authorise)
    )

def parse_request(raw: dict) -> Either:
    if not raw.get('card_number'):
        return Left(InvalidCardError("Card number required"))
    return Right(PaymentRequest(**raw))

# Using Python's built-in exception handling (pragmatic alternative)
# For teams not adopting Either, contextlib.suppress or try/except is fine
# Either shines when you need typed errors that flow through a pipeline
```

### JavaScript / TypeScript — fp-ts and custom Either

```typescript
// Custom Either implementation
type Either<L, R> = Left<L> | Right<R>

class Left<L> {
    readonly _tag = 'Left' as const
    constructor(readonly value: L) {}

    map<R2>(f: (r: never) => R2): Either<L, R2> { return this as any; }
    flatMap<R2>(f: (r: never) => Either<L, R2>): Either<L, R2> { return this as any; }
    fold<T>(ifLeft: (l: L) => T, _ifRight: (r: never) => T): T { return ifLeft(this.value); }
    isRight(): this is Right<never> { return false; }
}

class Right<R> {
    readonly _tag = 'Right' as const
    constructor(readonly value: R) {}

    map<R2>(f: (r: R) => R2): Either<never, R2> { return new Right(f(this.value)); }
    flatMap<L, R2>(f: (r: R) => Either<L, R2>): Either<L, R2> { return f(this.value); }
    fold<T>(_ifLeft: (l: never) => T, ifRight: (r: R) => T): T { return ifRight(this.value); }
    isRight(): this is Right<R> { return true; }
}

const left  = <L>(value: L): Either<L, never>  => new Left(value);
const right = <R>(value: R): Either<never, R>  => new Right(value);

// Payment pipeline
type PaymentError =
    | { type: 'INVALID_CARD'; reason: string }
    | { type: 'FRAUD_DETECTED'; riskScore: number }
    | { type: 'INSUFFICIENT_FUNDS' }
    | { type: 'GATEWAY_ERROR'; code: number; message: string }

function processPayment(raw: RawRequest): Either<PaymentError, AuthorisedPayment> {
    return parseRequest(raw)
        .flatMap(validateCard)
        .flatMap(checkFraud)
        .flatMap(authorise);
}

// Exhaustive error handling with fold
const response = processPayment(raw).fold(
    error => {
        switch (error.type) {
            case 'INVALID_CARD':       return { status: 400, body: error.reason };
            case 'FRAUD_DETECTED':     return { status: 403, body: 'Blocked' };
            case 'INSUFFICIENT_FUNDS': return { status: 402, body: 'Insufficient funds' };
            case 'GATEWAY_ERROR':      return { status: 503, body: error.message };
        }
    },
    payment => ({ status: 200, body: { transactionId: payment.transactionId } })
);
```

---

## Either vs Exceptions vs Maybe

| Approach | Error info | Composable? | Forced handling? | Performance |
|----------|-----------|-------------|-----------------|-------------|
| Exceptions (`throw`) | Rich message + stack | No — breaks pipelines | No (unless checked) | JVM stack capture is expensive |
| `Optional` / Maybe | None (absence only) | Yes | Partially | Fast |
| `Either<Error, Value>` | Rich typed error | Yes | Yes (compiler) | Fast |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each step returns Either; fold at the edge handles presentation |
| Open/Closed | ✅ | New error types added to the sealed hierarchy — no existing code changes |
| Liskov Substitution | ✅ | `Left` and `Right` substitutable through `Either` |
| Interface Segregation | ✅ | `map`, `flatMap`, `fold` are the only operations |
| Dependency Inversion | ✅ | Business logic returns `Either`, not HTTP status codes |

---

## When to Use

- Operations that can fail with distinct, typed error reasons (payment, validation, parsing)
- You want errors to propagate through a pipeline without try-catch at every step
- The error type carries structured data that callers need to react to differently

## When NOT to Use

- Simple absence with no error context — use Maybe/Optional
- Truly exceptional conditions (out of memory, programming bugs) — use exceptions
- Teams unfamiliar with FP — the cognitive overhead may not be worth it; pragmatic try/catch can be fine
- JVM checked exceptions already enforce handling at each call site

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Errors are values — pipeline never throws, always returns | Requires `fold` or pattern matching at the edge — no implicit handling |
| Typed errors force exhaustive handling in `fold` | Sealed error hierarchy must be maintained as requirements grow |
| Each step is independently unit-testable (returns Either, not throws) | Unfamiliar to OOP developers; onboarding cost |
| Error path is as clean as the happy path | Interop with throw-based libraries requires wrapping |

---

**FAANG interview application**: "I use Either when an operation can fail with a reason that the caller needs to act on differently — payment declined vs fraud vs gateway error. The pipeline `parse.flatMap(validate).flatMap(fraud).flatMap(authorise)` short-circuits on the first Left, and the final `fold` maps each error to the right HTTP response. The key benefit over exceptions: the type system enforces that every caller handles every error case. In Kotlin I use a sealed class for the Left type, which combined with a `when` expression gives exhaustive coverage checked at compile time."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Maybe / Option](35-maybe-option.md) | Maybe is Either with an untyped Left (no error info) |
| [Monad](34-monad.md) | Either is a Monad — flatMap chains operations that may fail |
| [Functor](33-functor.md) | Either is a Functor — map transforms Right, passes Left through |
| [Chain of Responsibility](../behavioral/13-chain-of-responsibility.md) | Similar step-by-step pipeline, but uses OOP handler chain vs typed return values |
