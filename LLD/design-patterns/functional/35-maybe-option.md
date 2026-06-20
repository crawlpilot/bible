# 35. Maybe / Option
**Category**: Functional Programming  
**GoF**: No (Haskell / ML origins, mainstream in Java 8+, Kotlin, Scala)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Maybe (also called Option) is a container that explicitly models the presence or absence of a value — replacing null with a type-safe wrapper that forces callers to handle the absent case.

---

## Problem It Solves

`NullPointerException` is the billion-dollar mistake (Tony Hoare's words). Every method that returns `null` is a lie: the return type says `User` but sometimes it hands you a timebomb. Callers forget to check. Null propagates silently up the call stack. Maybe makes absence **explicit in the type**: `Optional<User>` communicates "this might not exist" at the API boundary, and the compiler refuses to let you use the value without handling the empty case.

```
Before:  User getUser(String id)     — lying type, hidden null
After:   Optional<User> findUser(String id) — honest type, forced handling
```

## Structure

```
            Maybe<A>
    ┌─────────────────────┐
    │ + map(f): Maybe<B>  │
    │ + flatMap(f): Maybe<B>│
    │ + getOrElse(default)│
    │ + isPresent(): bool │
    │ + ifPresent(action) │
    └─────────────────────┘
              △
    ┌─────────────────────┐
    │                     │
 Just<A> / Some<A>    Nothing / None / Empty
 (value present)      (value absent)
```

---

## Real-World Use Case: User Profile Lookup

A recommendation engine looks up user preferences, falls back to category defaults, and renders personalised content. Any step can legitimately return nothing (new user, deleted preferences, unknown category).

### Java — Optional<T>

```java
// Repository returns Optional — honest API
public interface UserRepository {
    Optional<User> findById(String userId);
    Optional<User> findByEmail(String email);
}

// Service — chains transformations safely
public class RecommendationService {

    public List<Product> getRecommendations(String userId) {
        return userRepo.findById(userId)                        // Optional<User>
            .map(User::getPreferences)                          // Optional<Preferences>
            .map(Preferences::getFavoriteCategories)           // Optional<List<Category>>
            .map(categories -> productRepo.findByCategories(categories)) // Optional<List<Product>>
            .orElseGet(() -> productRepo.findTopSellers());    // fallback if any step empty
    }

    // ifPresent for side effects
    public void sendWelcomeEmail(String userId) {
        userRepo.findById(userId)
            .filter(user -> !user.hasReceivedWelcomeEmail())
            .ifPresent(user -> emailService.sendWelcome(user.getEmail()));
    }

    // orElseThrow — fail fast at domain boundary with meaningful error
    public User getOrThrow(String userId) {
        return userRepo.findById(userId)
            .orElseThrow(() -> new UserNotFoundException("User not found: " + userId));
    }
}

// Anti-patterns to avoid with Optional
public class OptionalAntiPatterns {

    // WRONG: checking isPresent() then get() is just null-check in disguise
    Optional<User> opt = userRepo.findById(id);
    if (opt.isPresent()) {
        User user = opt.get();   // defeats the purpose
    }

    // WRONG: Optional as a field (serialisation issues, memory overhead)
    class UserProfile {
        private Optional<String> nickname;  // use @Nullable String instead
    }

    // WRONG: returning Optional.empty() to signal errors — use Either for that
    Optional<Order> placeOrder(Cart cart) {
        if (!paymentValid) return Optional.empty(); // WHY is it empty? Use Either<Error, Order>
    }
}
```

### Kotlin — nullable types as built-in Maybe

```kotlin
// Kotlin's nullable type T? IS the Option monad — no wrapper class needed
interface UserRepository {
    fun findById(userId: String): User?   // ? suffix = Maybe<User>
}

class RecommendationService(
    private val userRepo: UserRepository,
    private val productRepo: ProductRepository
) {
    fun getRecommendations(userId: String): List<Product> {
        return userRepo.findById(userId)               // User?
            ?.preferences                              // Preferences?   (map)
            ?.favoriteCategories                       // List<Category>?
            ?.let { cats -> productRepo.findByCategories(cats) }  // List<Product>?
            ?: productRepo.findTopSellers()            // Elvis: fallback if any step null
    }

    // Safe cast + null propagation
    fun getDisplayName(userId: String): String =
        userRepo.findById(userId)
            ?.displayName
            ?.takeIf { it.isNotBlank() }
            ?: "Anonymous"
}

// Extension function to make patterns more readable
fun <T, R> T?.mapNotNull(transform: (T) -> R?): R? = this?.let(transform)

// Scope functions as map/flatMap
val email: String? = user?.let { u ->
    if (u.isEmailVerified) u.email else null   // flatMap-style with condition
}
```

### Python — Optional type hints + explicit None handling

```python
from typing import Optional, TypeVar, Callable, Generic
from dataclasses import dataclass

# Type hints make absence explicit — Optional[X] == Union[X, None]
def find_user(user_id: str) -> Optional['User']:
    return db.query(User).filter_by(id=user_id).first()

# Chain with walrus + conditional
def get_recommendations(user_id: str) -> list:
    if (user := find_user(user_id)) is None:
        return get_top_sellers()
    if (prefs := user.preferences) is None:
        return get_top_sellers()
    return find_by_categories(prefs.favorite_categories)

# Maybe class for clean FP chaining
T = TypeVar('T')
U = TypeVar('U')

class Maybe(Generic[T]):
    def __init__(self, value: Optional[T]):
        self._value = value

    @classmethod
    def of(cls, value: Optional[T]) -> 'Maybe[T]':
        return cls(value)

    @classmethod
    def empty(cls) -> 'Maybe[T]':
        return cls(None)

    def is_present(self) -> bool:
        return self._value is not None

    def map(self, f: Callable[[T], U]) -> 'Maybe[U]':
        if self._value is None:
            return Maybe.empty()
        return Maybe.of(f(self._value))

    def flat_map(self, f: Callable[[T], 'Maybe[U]']) -> 'Maybe[U]':
        if self._value is None:
            return Maybe.empty()
        return f(self._value)

    def or_else(self, default: T) -> T:
        return self._value if self._value is not None else default

    def or_else_get(self, supplier: Callable[[], T]) -> T:
        return self._value if self._value is not None else supplier()

    def if_present(self, consumer: Callable[[T], None]) -> None:
        if self._value is not None:
            consumer(self._value)

    def filter(self, predicate: Callable[[T], bool]) -> 'Maybe[T]':
        if self._value is None or not predicate(self._value):
            return Maybe.empty()
        return self

# Usage
result = (
    Maybe.of(find_user(user_id))
        .map(lambda u: u.preferences)
        .flat_map(lambda p: Maybe.of(p.favorite_categories))
        .map(lambda cats: find_by_categories(cats))
        .or_else_get(get_top_sellers)
)
```

### JavaScript / TypeScript — Optional chaining + explicit types

```typescript
// TypeScript: nullable union types
function findUser(userId: string): User | null { ... }
function findUser(userId: string): User | undefined { ... }

// Optional chaining (?.) is native Maybe.map for property access
function getDisplayName(userId: string): string {
    const user = findUser(userId);
    return user?.profile?.displayName?.trim() ?? 'Anonymous';
}

// Nullish coalescing (??) as orElse
const email = user?.email ?? 'noreply@example.com';

// Option class for explicit pipeline (fp-ts style)
class Option<A> {
    private constructor(private readonly value: A | null) {}

    static some<A>(value: A): Option<A> { return new Option(value); }
    static none<A>(): Option<A> { return new Option<A>(null); }
    static of<A>(value: A | null | undefined): Option<A> {
        return value != null ? Option.some(value) : Option.none();
    }

    map<B>(f: (a: A) => B): Option<B> {
        return this.value != null ? Option.some(f(this.value)) : Option.none();
    }

    flatMap<B>(f: (a: A) => Option<B>): Option<B> {
        return this.value != null ? f(this.value) : Option.none();
    }

    getOrElse(defaultValue: A): A {
        return this.value != null ? this.value : defaultValue;
    }

    filter(predicate: (a: A) => boolean): Option<A> {
        return this.value != null && predicate(this.value) ? this : Option.none();
    }
}

// Usage
const recommendations = Option.of(findUser(userId))
    .flatMap(user => Option.of(user.preferences))
    .map(prefs => prefs.favoriteCategories)
    .map(cats => findByCategories(cats))
    .getOrElse(getTopSellers());
```

---

## Decision: null / undefined vs Optional vs Maybe class

| Approach | Language | Pros | Cons |
|----------|---------|------|------|
| Nullable type `T?` | Kotlin, TypeScript | Zero overhead, compiler-enforced | No chainable map/flatMap without `?.` |
| `Optional<T>` | Java 8+ | Chainable, explicit | Not serialisable, field use discouraged |
| Maybe class | Python, JS | Full monadic API | Runtime overhead, manual implementation |
| `@NonNull`/`@Nullable` annotations | Java (legacy) | Backward-compatible | IDE/static analysis only, not enforced |

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Container handles presence/absence; domain logic lives in map functions |
| Open/Closed | ✅ | New transformations added via new map steps — no modification |
| Liskov Substitution | ✅ | `Just` and `Nothing` are substitutable through `Maybe` interface |
| Interface Segregation | ✅ | Consumers only call the operations they need |
| Dependency Inversion | ✅ | Business logic depends on `Optional<User>`, not `User` + null |

---

## When to Use

- A method can legitimately return nothing (lookup by ID that may not exist)
- You want to chain transformations over a value that might be absent
- Replacing null returns at domain/service boundaries

## When NOT to Use

- The absence carries an error reason — use `Either<Error, T>` instead
- Performance-critical inner loops — `Optional` allocates on the heap
- Collection return types — return an empty list, not `Optional<List<T>>`
- Fields in entities / DTOs — use `@Nullable` annotations; `Optional` is not serialisation-friendly

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Absence is visible in the type — no hidden nulls | Method chaining with `map`/`flatMap` is unfamiliar to OOP developers |
| Compiler forces handling of empty case | Optional wrapper allocates memory (minor, but present) |
| orElse/orElseGet provides clear fallback semantics | Cannot be used as a method parameter or entity field cleanly |

---

**FAANG interview application**: "I return `Optional<T>` at repository boundaries — it communicates that the absence is a normal outcome, not an error. If absence means something went wrong, I use Either. The key discipline: never use `Optional.get()` directly — always use `map`, `flatMap`, `orElse`, or `orElseThrow`. In Kotlin I lean on the nullable type system (`?.` and `?:`) which is the same concept built into the language. In Python I use `Optional[T]` type hints and a thin Maybe wrapper when I need chainable transforms."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Functor](33-functor.md) | Maybe is a Functor — map applies a function if value is present |
| [Monad](34-monad.md) | Maybe is a Monad — flatMap chains operations that return Maybe |
| [Either](36-either.md) | Either extends Maybe with an error value in the empty case |
