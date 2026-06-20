# 39. Immutable Data
**Category**: Functional Programming  
**GoF**: No (FP fundamentals, adopted in mainstream OOP)  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Immutable data is data that cannot be changed after creation — any "modification" produces a new value, leaving the original intact. This eliminates an entire class of concurrency bugs, simplifies reasoning, and enables structural sharing for efficiency.

---

## Problem It Solves

Two threads both hold a reference to the same `User` object. Thread A calls `user.setEmail(...)`. Thread B reads `user.getEmail()`. Without synchronisation, the result is undefined. With immutable data, mutation is impossible: `user.withEmail(newEmail)` returns a **new** `User` object; the original is unchanged. Both threads always see a consistent snapshot. Immutability also enables:
- **Safe caching** — a cached immutable value never goes stale
- **Free thread safety** — no locks needed if data can't be mutated
- **Undo/redo** — old version always available (see also Event Sourcing)
- **Structural sharing** — two versions of a list that differ in one element share all unchanged elements

## Structure

```
    Mutable (dangerous)          Immutable (safe)
┌──────────────────────┐     ┌──────────────────────────┐
│ User                 │     │ User (record / data class)│
│ - String email       │     │ + String email()  (final) │
│ + setEmail(String)   │     │ + User withEmail(String)  │
│ + getEmail(): String │     │   returns NEW User        │
└──────────────────────┘     └──────────────────────────┘

Persistent data structure (structural sharing):
List[1,2,3,4,5]
       │
 withAppended(6) → List[1,2,3,4,5,6]  (shares 1–5 with original)
```

---

## Real-World Use Case: Order State Machine

An order moves through states (PENDING → CONFIRMED → SHIPPED → DELIVERED). Each transition creates a new order snapshot. Previous states are preserved for audit, undo, and event sourcing.

### Java — Records (Java 16+) and value objects

```java
// Java record — immutable by default; all fields final
public record Order(
    String id,
    OrderStatus status,
    Money total,
    List<LineItem> items,          // defensive copy in compact constructor
    Instant createdAt,
    Instant updatedAt
) {
    // Compact constructor — validate and defensively copy
    public Order {
        Objects.requireNonNull(id, "id required");
        items = List.copyOf(items); // unmodifiable copy — no mutation via the list reference
    }

    // Wither methods — return new instance with one field changed
    public Order withStatus(OrderStatus newStatus) {
        return new Order(id, newStatus, total, items, createdAt, Instant.now());
    }

    public Order withTotal(Money newTotal) {
        return new Order(id, status, newTotal, items, createdAt, Instant.now());
    }

    public Order addItem(LineItem item) {
        var newItems = new ArrayList<>(items);
        newItems.add(item);
        return new Order(id, status, total, List.copyOf(newItems), createdAt, Instant.now());
    }
}

// Order state machine — each transition returns new Order
public class OrderStateMachine {
    public Order confirm(Order order) {
        if (order.status() != PENDING)
            throw new IllegalStateTransitionException(order.status(), CONFIRMED);
        return order.withStatus(CONFIRMED);
    }

    public Order ship(Order order, TrackingNumber tracking) {
        if (order.status() != CONFIRMED)
            throw new IllegalStateTransitionException(order.status(), SHIPPED);
        return order
            .withStatus(SHIPPED)
            .withTracking(tracking);    // returns new instance each time
    }
}

// Thread-safe order processing — no locks needed
public class OrderProcessor {
    // AtomicReference allows thread-safe swap of the immutable order
    private final AtomicReference<Order> orderRef;

    public boolean tryShip(TrackingNumber tracking) {
        return orderRef.getAndUpdate(current -> {
            if (current.status() != CONFIRMED) return current;     // no-op
            return stateMachine.ship(current, tracking);           // new immutable value
        }).status() == CONFIRMED;
    }
}

// Collections — defensive copies and unmodifiable views
public class ProductCatalog {
    private final List<Product> products;

    public ProductCatalog(List<Product> products) {
        this.products = List.copyOf(products);  // immutable copy
    }

    public List<Product> getProducts() {
        return products;                         // safe to return — unmodifiable
    }

    public ProductCatalog withProduct(Product p) {
        var newList = new ArrayList<>(products);
        newList.add(p);
        return new ProductCatalog(newList);      // new catalog
    }
}
```

### Kotlin — data classes with copy()

```kotlin
// Kotlin data class — copy() is the wither method
data class Order(
    val id: String,
    val status: OrderStatus,
    val total: Money,
    val items: List<LineItem>,     // use List (read-only) not MutableList
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now()
) {
    init {
        require(id.isNotBlank()) { "Order id must not be blank" }
    }

    // Named wither for domain clarity (more expressive than copy())
    fun confirm() = copy(status = CONFIRMED, updatedAt = Instant.now())
    fun ship(tracking: TrackingNumber) = copy(
        status = SHIPPED,
        trackingNumber = tracking,
        updatedAt = Instant.now()
    )
    fun addItem(item: LineItem) = copy(items = items + item, updatedAt = Instant.now())
}

// Deeply nested immutable update — copy at each level
data class UserProfile(val address: Address, val preferences: Preferences)
data class Address(val city: String, val country: String)

// Updating a nested field
fun updateCity(profile: UserProfile, newCity: String): UserProfile =
    profile.copy(
        address = profile.address.copy(city = newCity)
    )

// Kotlin sealed classes as immutable algebraic types
sealed class PaymentState {
    object Pending : PaymentState()
    data class Processing(val transactionId: String) : PaymentState()
    data class Completed(val receipt: Receipt, val at: Instant) : PaymentState()
    data class Failed(val reason: String, val at: Instant) : PaymentState()
}

// State transitions return new states — the original is never mutated
fun authorise(state: PaymentState, txId: String): PaymentState = when (state) {
    is PaymentState.Pending -> PaymentState.Processing(txId)
    else -> throw IllegalStateException("Cannot authorise in state $state")
}
```

### Python — frozen dataclasses and named tuples

```python
from dataclasses import dataclass, replace, field
from typing import Tuple
from datetime import datetime

# frozen=True makes all fields immutable (raises FrozenInstanceError on mutation)
@dataclass(frozen=True)
class Order:
    id: str
    status: str
    total: float
    items: Tuple[dict, ...]   # tuple is immutable; not list
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    def with_status(self, new_status: str) -> 'Order':
        return replace(self, status=new_status, updated_at=datetime.utcnow())

    def add_item(self, item: dict) -> 'Order':
        return replace(self, items=self.items + (item,), updated_at=datetime.utcnow())

# Usage
order = Order(id="O001", status="PENDING", total=99.99, items=())
confirmed = order.with_status("CONFIRMED")  # new object; order unchanged

# NamedTuple — lighter-weight immutable value object
from typing import NamedTuple

class Money(NamedTuple):
    amount: float
    currency: str

    def add(self, other: 'Money') -> 'Money':
        if self.currency != other.currency:
            raise ValueError(f"Currency mismatch: {self.currency} vs {other.currency}")
        return Money(self.amount + other.amount, self.currency)

price = Money(99.99, "USD")
tax   = Money(8.00, "USD")
total = price.add(tax)   # Money(107.99, 'USD'); price unchanged

# Persistent data structures via pyrsistent
from pyrsistent import pvector, pmap, freeze

immutable_list = pvector([1, 2, 3])
new_list = immutable_list.append(4)      # new pvector; immutable_list unchanged
shared   = immutable_list               # structural sharing — no deep copy

immutable_map = pmap({'a': 1, 'b': 2})
updated_map   = immutable_map.set('c', 3)  # new pmap; immutable_map unchanged

# freeze converts mutable structures to immutable recursively
config = freeze({
    'database': {'host': 'localhost', 'port': 5432},
    'cache': {'ttl': 300}
})
# config['database']['port'] = 9999  ← raises: cannot mutate frozen map
```

### JavaScript / TypeScript — Object.freeze, spread, and Immer

```typescript
// Object.freeze — shallow immutability
const order = Object.freeze({
    id: 'O001',
    status: 'PENDING',
    total: 99.99,
    items: Object.freeze([])   // freeze nested structures too
});

// order.status = 'CONFIRMED';  // silently ignored in non-strict mode, TypeError in strict

// Spread operator — immutable update
const confirm = (order: Order): Order => ({
    ...order,
    status: 'CONFIRMED',
    updatedAt: new Date()
});

const ship = (order: Order, tracking: string): Order => ({
    ...order,
    status: 'SHIPPED',
    trackingNumber: tracking,
    updatedAt: new Date()
});

// TypeScript readonly — compiler-enforced immutability
interface Order {
    readonly id: string;
    readonly status: OrderStatus;
    readonly total: number;
    readonly items: ReadonlyArray<LineItem>;
}

// Recursive readonly for deep immutability
type DeepReadonly<T> = {
    readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
};

// Immer — write mutable code that produces immutable updates
import produce from 'immer';

const addItem = (order: Order, item: LineItem): Order =>
    produce(order, draft => {
        draft.items.push(item);          // looks mutable, produces new immutable order
        draft.total += item.price;
        draft.updatedAt = new Date();
    });

// Redux uses this pattern — all state transitions via produce()
const reducer = (state: AppState, action: Action): AppState =>
    produce(state, draft => {
        switch (action.type) {
            case 'CONFIRM_ORDER':
                draft.orders[action.orderId].status = 'CONFIRMED';
                break;
        }
    });
```

---

## Structural Sharing — Why Immutability Is Not Always O(n) Copy

```
Original list:  [A → B → C → D → E]
Append F:       [A → B → C → D → E → F]
                 ↑_________________________↑  (shared — no copy of A-E)

Persistent vector (Clojure/Scala/Immutable.js) uses tree structure:
- Modification: O(log n) — only the path to the changed node is copied
- All other nodes shared between old and new version
```

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Data objects only carry values — no mutation logic |
| Open/Closed | ✅ | New transformations are new wither functions — data class unchanged |
| Liskov Substitution | ✅ | Immutable subtypes cannot violate contracts by mutating shared state |
| Interface Segregation | ✅ | Consumers receive read-only views |
| Dependency Inversion | ✅ | Components receive immutable value objects — no unexpected side effects |

---

## When to Use

- Shared state accessed by multiple threads — immutability eliminates race conditions
- Value objects in domain model (Money, Address, DateRange) — they have no identity, only value
- Cache keys or cache values — immutable values are safe to cache indefinitely
- Event sourcing — events are immutable facts; past cannot change

## When NOT to Use

- High-frequency mutation of large objects (e.g., game state at 60fps) — copy cost is real
- Large collections modified in a tight loop — use a mutable builder, then freeze at end
- Legacy codebase with deep ORM integration — many ORMs require mutable JavaBeans

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Thread safety for free — no locks needed | Wither methods create new objects — GC pressure |
| Eliminates defensive copying at API boundaries | Deeply nested updates require copying every level (Kotlin `copy` verbosity) |
| Time-travel / undo built-in — old versions are just references | Mutable algorithms (in-place sort, graph traversal) must be restructured |
| Predictable equality — two equal immutable values are interchangeable | Frameworks (JPA, Jackson) often expect mutable JavaBeans |

---

**FAANG interview application**: "At FAANG scale, mutable shared state is the root cause of a huge class of production incidents — two threads updating the same object without synchronisation. My default is immutable value objects: Java records, Kotlin data classes, Python frozen dataclasses. The wither pattern (`withStatus`, `copy(status=...)`) creates a new object for each transition. The cost is minor GC pressure; the benefit is zero synchronisation overhead and inherently testable code. For collections I return `List.copyOf` or `ReadonlyArray` — the caller can't mutate my internal state. The one exception: high-throughput accumulation where I use a mutable builder (StringBuilder, ArrayList) then freeze at the end."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Memento](../behavioral/17-memento.md) | Memento stores snapshots — immutable data makes snapshots trivially safe |
| [Event Sourcing](../modern/27-event-sourcing.md) | Events are immutable facts; immutable data is foundational |
| [Prototype](../creational/05-prototype.md) | Prototype clones objects; immutable data can share structure instead of cloning |
| [Builder](../creational/04-builder.md) | Builder is the mutable construction phase before producing an immutable object |
