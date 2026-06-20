# Tactical Design: Building Blocks of the Domain Model

## Overview
Tactical Design is the set of implementation patterns DDD provides for modelling the domain in code. These are the tools that translate a Ubiquitous Language and Bounded Context into actual classes, methods, and data structures. Tactical patterns apply primarily to the **Core Domain** — they are too heavyweight for Supporting subdomains and unnecessary for Generic subdomains.

The central discipline: **business invariants must be enforced by the domain model itself, not by the service layer or the database**.

---

## The Building Blocks

### Entity

An **Entity** is a domain object that has a unique, continuous identity across its lifecycle. The identity persists even as the object's attributes change.

**The rule**: two entities are equal if and only if they have the same identity — regardless of their current attribute values.

```python
from dataclasses import dataclass
from uuid import UUID

@dataclass
class OrderId:
    """Typed ID — prevents passing the wrong ID to the wrong method"""
    value: UUID
    
    def __eq__(self, other):
        return isinstance(other, OrderId) and self.value == other.value

class Order:  # Entity
    def __init__(self, order_id: OrderId, customer_id: CustomerId):
        self._id = order_id
        self._customer_id = customer_id
        self._lines: list[OrderLine] = []
        self._status = OrderStatus.DRAFT
    
    @property
    def id(self) -> OrderId:
        return self._id
    
    def __eq__(self, other):
        if not isinstance(other, Order):
            return False
        return self._id == other._id  # identity determines equality
```

**Common mistake**: using raw `int` or `str` as IDs. A typed `OrderId` prevents passing a `CustomerId` where an `OrderId` is expected — a class of bug caught at compile time (type checkers) rather than runtime.

---

### Value Object

A **Value Object** is a domain object that has no identity. Two Value Objects are equal if all their attributes are equal. They are **immutable** — when you need a different value, you create a new object.

```python
from dataclasses import dataclass
from decimal import Decimal

@dataclass(frozen=True)  # frozen=True enforces immutability
class Money:
    """Value Object — equality by value, not identity"""
    amount: Decimal
    currency: str
    
    def __post_init__(self):
        if self.amount < 0:
            raise ValueError("Money amount cannot be negative")
        if len(self.currency) != 3:
            raise ValueError("Currency must be ISO 4217 code")
    
    def add(self, other: 'Money') -> 'Money':
        if self.currency != other.currency:
            raise ValueError(f"Cannot add {self.currency} and {other.currency}")
        return Money(self.amount + other.amount, self.currency)  # returns new object
    
    def apply_discount(self, percentage: Decimal) -> 'Money':
        return Money(self.amount * (1 - percentage / 100), self.currency)

# Usage:
price = Money(Decimal("29.99"), "USD")
discounted = price.apply_discount(Decimal("10"))  # price unchanged; new object returned
```

**Common mistake**: making everything an Entity. Ask: "Does this concept have a meaningful identity, or is it just a value?" Address, Email, Money, DateRange, PhoneNumber — all Value Objects. Customer, Order, Invoice — Entities.

---

### Aggregate and Aggregate Root ⭐ Most Critical

An **Aggregate** is a cluster of domain objects (Entities and Value Objects) that are treated as a single transactional unit. The **Aggregate Root** is the single entry point to the aggregate — the only object external code can hold a reference to.

**The rule**: a database transaction should modify at most one aggregate. If you need to update two aggregates in one transaction, you have either drawn the boundary wrong, or you should use eventual consistency via Domain Events.

```
                    ┌─────────────────────────────────────┐
                    │         Order Aggregate              │
                    │                                      │
                    │  ┌──────────────────────────────┐   │
                    │  │  Order (Aggregate Root)       │   │
                    │  │  - id: OrderId                │   │
                    │  │  - status: OrderStatus        │   │
                    │  │  + addLine(product, qty, price)│  │
                    │  │  + submit()                   │   │
                    │  │  + cancel(reason)             │   │
                    │  └──────────────────────────────┘   │
                    │         owns ▼                       │
                    │  ┌──────────────────────────────┐   │
                    │  │  OrderLine (child Entity)     │   │
                    │  │  - productId: ProductId       │   │
                    │  │  - quantity: int               │   │
                    │  │  - unitPrice: Money            │   │
                    │  └──────────────────────────────┘   │
                    │                                      │
                    └─────────────────────────────────────┘
External code accesses ONLY via Order (the root)
OrderLine is never returned or held directly by external code
```

```python
class Order:  # Aggregate Root
    def __init__(self, order_id: OrderId, customer_id: CustomerId):
        self._id = order_id
        self._customer_id = customer_id
        self._lines: list[OrderLine] = []
        self._status = OrderStatus.DRAFT
        self._version = 0  # optimistic concurrency
        self._events: list[DomainEvent] = []
    
    def add_line(self, product_id: ProductId, quantity: int, unit_price: Money) -> None:
        if self._status != OrderStatus.DRAFT:
            raise InvalidOrderStateError("Can only add lines to DRAFT orders")
        if quantity <= 0:
            raise ValueError("Quantity must be positive")
        
        # Business invariant enforced HERE, not in OrderService
        existing = self._find_line(product_id)
        if existing:
            existing.increase_quantity(quantity)
        else:
            self._lines.append(OrderLine(product_id, quantity, unit_price))
    
    def submit(self) -> None:
        if self._status != OrderStatus.DRAFT:
            raise InvalidOrderStateError("Order already submitted")
        if not self._lines:
            raise InvalidOrderStateError("Cannot submit an empty order")
        
        self._status = OrderStatus.SUBMITTED
        self._events.append(OrderSubmitted(self._id, self._customer_id, self.total()))
    
    def total(self) -> Money:
        if not self._lines:
            return Money(Decimal("0"), "USD")
        return sum((line.subtotal() for line in self._lines), 
                   start=Money(Decimal("0"), "USD"))
    
    def pull_events(self) -> list[DomainEvent]:
        """Application layer calls this to get events for publishing"""
        events = list(self._events)
        self._events.clear()
        return events
```

### Aggregate Design Rules (Evans + Vernon)

| Rule | Why |
|---|---|
| Reference other aggregates by ID only | Prevents loading entire object graphs; enables eventual consistency |
| One transaction = one aggregate | Enforces that the aggregate is the consistency boundary |
| Keep aggregates small | Large aggregates cause contention; break them up unless truly one consistency unit |
| Enforce invariants at the aggregate root | No business logic in services, controllers, or repositories |
| Use eventual consistency between aggregates | Via Domain Events; not distributed transactions |

---

### Domain Service

A **Domain Service** is a stateless service that encapsulates domain logic that doesn't naturally fit on a single Entity or Value Object — typically because it involves multiple aggregates or external domain knowledge.

```python
class PaymentRiskScoringService:  # Domain Service
    """
    Stateless domain service: calculates fraud risk.
    Lives in the domain layer — depends only on domain objects,
    never on HTTP clients or databases directly.
    """
    
    def calculate_risk(self, order: Order, customer: Customer) -> RiskScore:
        if customer.is_new() and order.total() > Money(Decimal("1000"), "USD"):
            return RiskScore.HIGH
        if order.has_multiple_shipping_addresses():
            return RiskScore.MEDIUM
        return RiskScore.LOW
```

**When NOT to use a Domain Service**: if the logic belongs on an Aggregate, put it on the Aggregate. Domain Services are for cross-aggregate logic — not a dumping ground for "I'm not sure where to put this."

**The distinction from Application Service**: a Domain Service contains business logic (the "what should happen" and "whether it's allowed"). An Application Service orchestrates domain objects and infrastructure (the "how it happens in this delivery context"). Application Services live outside the domain layer; Domain Services live inside it.

---

### Repository

A **Repository** is an abstraction that provides a collection-like interface for retrieving and persisting Aggregates. The domain layer defines the Repository interface; the infrastructure layer implements it.

```python
from abc import ABC, abstractmethod

class OrderRepository(ABC):  # Defined in domain layer
    @abstractmethod
    def find_by_id(self, order_id: OrderId) -> Optional[Order]:
        ...
    
    @abstractmethod
    def save(self, order: Order) -> None:
        ...
    
    @abstractmethod
    def find_submitted_orders_before(self, cutoff: datetime) -> list[Order]:
        ...

# In infrastructure layer (not in domain):
class PostgreSQLOrderRepository(OrderRepository):
    def find_by_id(self, order_id: OrderId) -> Optional[Order]:
        row = self._db.query("SELECT * FROM orders WHERE id = %s", [str(order_id.value)])
        if not row:
            return None
        return self._map_row_to_order(row)
    
    def save(self, order: Order) -> None:
        # Optimistic concurrency: fails if version has changed since last read
        self._db.execute(
            "UPDATE orders SET status=%s, version=%s WHERE id=%s AND version=%s",
            [order.status.value, order.version + 1, str(order.id.value), order.version]
        )
```

**Critical rule**: one Repository per Aggregate Root. Never a Repository for `OrderLine` — it is accessed only through `OrderRepository`. This enforces the aggregate boundary at the persistence layer.

---

### Factory

A **Factory** encapsulates the logic for creating complex Aggregates. Used when the construction logic is too complex for a constructor.

```python
class OrderFactory:
    def create_from_cart(self, cart: Cart, customer: Customer) -> Order:
        order_id = OrderId(uuid4())
        order = Order(order_id, customer.id)
        
        for cart_item in cart.items:
            price = self._pricing_policy.resolve(cart_item.product_id, customer.tier)
            order.add_line(cart_item.product_id, cart_item.quantity, price)
        
        return order
```

---

### Specification

A **Specification** encapsulates a business rule as a reusable, composable predicate.

```python
class EligibleForLoyaltyUpgradeSpecification:
    def __init__(self, evaluation_window_days: int = 90):
        self._window = evaluation_window_days
    
    def is_satisfied_by(self, customer: Customer) -> bool:
        qualifying_purchases = customer.purchases_in_window(days=self._window)
        return len(qualifying_purchases) >= 3 and all(
            p.total > Money(Decimal("50"), "USD") for p in qualifying_purchases
        )

# Composable:
loyalty_spec = EligibleForLoyaltyUpgradeSpecification(90)
not_already_upgraded = NotAlreadyInTopTierSpecification()
eligible = CompositeAndSpec(loyalty_spec, not_already_upgraded)

for customer in customers:
    if eligible.is_satisfied_by(customer):
        customer.upgrade_loyalty_tier()
```

---

### Domain Events
Covered in detail in [LLD/design-patterns/modern/31-domain-events.md](../../LLD/design-patterns/modern/31-domain-events.md). In summary:

- Domain Events are raised by Aggregates when something significant happens (`OrderSubmitted`, `PaymentFailed`)
- The Application Service collects events from the Aggregate after each operation and publishes them
- They enable eventual consistency between Aggregates without distributed transactions
- They are the integration mechanism between Bounded Contexts (async, via message broker)

---

## Building Blocks Reference

| Building block | Identity | Mutable | Scope | Enforces |
|---|---|---|---|---|
| **Entity** | Yes (typed ID) | Yes | Within aggregate | Lifecycle invariants |
| **Value Object** | No | No (immutable) | Within aggregate or cross-aggregate (by value) | Value constraints |
| **Aggregate Root** | Yes | Yes | Transactional boundary | Business invariants |
| **Domain Service** | No (stateless) | No state | Cross-aggregate domain logic | Domain operations |
| **Repository** | No | No | Persistence boundary | Aggregate retrieval/storage |
| **Factory** | No | No | Creation boundary | Construction logic |
| **Specification** | No | No | Reusable rule | Business rule predicate |
| **Domain Event** | Yes (event ID) | No (immutable) | Cross-context | State change record |

---

## Optimistic Concurrency

Aggregates use a version number to detect concurrent modifications:

```python
# Load: version = 5
# Two concurrent requests both read version = 5
# Both attempt to save with version = 6
# First save succeeds; second save fails (version mismatch)
# Second request retries from scratch

UPDATE orders SET status='SUBMITTED', version=6 
WHERE id='ord-123' AND version=5;
-- Returns 0 rows → throw ConcurrentModificationError
-- Caller retries the entire use case
```

This avoids database locks while still preventing lost updates.

---

## Best Practices

1. **Aggregates should be small** — if an Aggregate has more than 3–5 child entities, question whether they all truly require strong consistency with each other
2. **Validate at aggregate boundaries** — all invariants checked in the Aggregate Root's methods, not in the service layer
3. **Value Objects for all primitives with rules** — `Money`, `Email`, `PhoneNumber`, `PostalCode` — not raw strings
4. **Typed IDs everywhere** — `OrderId(uuid)` not `str` — prevents ID mix-ups at compile time
5. **Raise events, not side effects** — Aggregates raise Domain Events; Application Services publish them — keeps the domain layer infrastructure-free
6. **Repository interface in domain, implementation in infrastructure** — the domain layer never imports SQLAlchemy, boto3, or any framework
7. **Never expose child entities directly** — all access through the Aggregate Root; never `order.lines[0].price = ...`

---

## FAANG Interview Points

**"How do you model a payment and prevent double-charge?"**: `Payment` Aggregate with a state machine (PENDING → AUTHORISED → CAPTURED → REFUNDED). The Aggregate enforces the invariant: `capture()` can only be called on an AUTHORISED payment. An idempotency key (Value Object on the Aggregate) ensures that if the same charge request arrives twice, the second is rejected. When captured, the Aggregate raises a `PaymentCaptured` domain event that downstream contexts (Accounting, Notifications) consume. Optimistic concurrency (`version` field) prevents two concurrent capture requests from both succeeding.

**"How do you handle an order that affects inventory, payments, and fulfilment?"**: Each concern is a separate Aggregate (Order, PaymentTransaction, InventoryReservation) in separate Bounded Contexts. No distributed transaction. The Order Aggregate raises `OrderSubmitted`; the Payments context handles `InventoryReserved` before attempting authorisation; the Fulfilment context handles `PaymentAuthorised` before creating a shipment. This is a Saga — see [LLD: Saga](../../LLD/design-patterns/modern/26-saga.md).

**"What is the Anemic Domain Model and why is it a problem?"**: An Anemic Domain Model has classes that look like domain objects (Order, Customer, Invoice) but contain only getters/setters. All business logic lives in service classes (`OrderService.processOrder()`). It is a problem because business rules are scattered, duplicated, and disconnected from the concepts they constrain. Two callers of `OrderService` may apply rules in different orders. The fix: move the business rules into the Aggregate (`order.submit()` checks all preconditions internally). The Aggregate's methods are the executable specification of the business rules.
