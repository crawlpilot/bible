# 04. Builder
**Category**: Creational  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Separate the construction of a complex object from its representation so the same construction process can create different representations.

---

## Problem It Solves

An `Order` object has dozens of fields: line items, shipping address, billing address, applied promo codes, gift message, delivery window, loyalty points redemption, split payment methods, invoice settings. Not all are required. Telescoping constructors (`Order(items, address, promo, gift, ...)`) become unreadable at 10+ parameters. Setters allow inconsistent partial state. Builder provides a fluent, step-by-step construction process that produces a valid, immutable object only at `build()`.

## Structure (Participants)

```
                OrderBuilder
  ┌──────────────────────────────────────────┐
  │ - items: List<LineItem>                  │
  │ - shippingAddress: Address               │
  │ - promoCode: String                      │
  │ - giftMessage: String                    │
  │ - deliveryWindow: TimeWindow             │
  │ - loyaltyPointsToRedeem: int             │
  │──────────────────────────────────────────│
  │ + withItem(sku, qty): OrderBuilder       │
  │ + shippingTo(address): OrderBuilder      │
  │ + applyPromo(code): OrderBuilder         │
  │ + withGiftMessage(msg): OrderBuilder     │
  │ + deliverBetween(window): OrderBuilder   │
  │ + redeemLoyaltyPoints(pts): OrderBuilder │
  │ + build(): Order                         │  ← validates + constructs
  └──────────────────────────────────────────┘
                     │ creates
                     ▼
              «immutable»
                Order
  ┌──────────────────────────────────────────┐
  │ - items: List<LineItem>                  │
  │ - shippingAddress: Address               │
  │ - promoCode: Optional<String>            │
  │ - giftMessage: Optional<String>          │
  │ - ...                                    │
  │──────────────────────────────────────────│
  │ (all fields final, getters only)         │
  └──────────────────────────────────────────┘
```

Key participants:
- **Builder** (`OrderBuilder`): holds mutable state, provides fluent methods, validates and produces the **Product**
- **Product** (`Order`): the immutable result; constructor is package-private, only accessible via builder
- **Director** (optional): an `OrderFactory` that orchestrates builder calls for common order types (e.g., `createSubscriptionOrder()`)

---

## Real-World Use Case: E-Commerce Order Construction

A checkout API receives an order request with up to 12 optional fields. The `Order` domain object must be immutable (thread-safe, no accidental mutation after creation) and valid (items required, shipping address required if not digital, promo code validated). Builder enforces these rules at `build()` time.

### The Design

`OrderBuilder` accumulates optional and required fields via fluent methods. `build()` validates required fields, applies business rules (e.g., loyalty points ≤ 50% of order value), and constructs an immutable `Order`. A `Director` (`CommonOrderFactory`) provides preset configurations for digital vs physical orders.

### Implementation

```java
// Product — immutable, package-private constructor
public final class Order {
    private final String orderId;
    private final List<LineItem> items;
    private final Address shippingAddress;       // null for digital orders
    private final String promoCode;              // nullable
    private final String giftMessage;            // nullable
    private final TimeWindow deliveryWindow;     // nullable
    private final int loyaltyPointsRedeemed;
    private final Money totalBeforeDiscount;
    private final Money finalTotal;

    // Package-private — only OrderBuilder can call this
    Order(OrderBuilder builder) {
        this.orderId = UUID.randomUUID().toString();
        this.items = List.copyOf(builder.items);
        this.shippingAddress = builder.shippingAddress;
        this.promoCode = builder.promoCode;
        this.giftMessage = builder.giftMessage;
        this.deliveryWindow = builder.deliveryWindow;
        this.loyaltyPointsRedeemed = builder.loyaltyPointsRedeemed;
        this.totalBeforeDiscount = calculateSubtotal(this.items);
        this.finalTotal = applyDiscounts(this.totalBeforeDiscount, promoCode, loyaltyPointsRedeemed);
    }

    // getters only — no setters
    public List<LineItem> getItems() { return items; }
    public Money getFinalTotal() { return finalTotal; }
    // ...
}

// Builder
public class OrderBuilder {
    // Required
    final List<LineItem> items = new ArrayList<>();

    // Optional
    Address shippingAddress;
    String promoCode;
    String giftMessage;
    TimeWindow deliveryWindow;
    int loyaltyPointsRedeemed = 0;
    boolean isDigitalOnly = false;

    public OrderBuilder withItem(String sku, int quantity, Money unitPrice) {
        items.add(new LineItem(sku, quantity, unitPrice));
        return this;
    }

    public OrderBuilder shippingTo(Address address) {
        this.shippingAddress = address;
        return this;
    }

    public OrderBuilder applyPromo(String promoCode) {
        this.promoCode = promoCode;
        return this;
    }

    public OrderBuilder withGiftMessage(String message) {
        this.giftMessage = message;
        return this;
    }

    public OrderBuilder deliverBetween(LocalDateTime from, LocalDateTime to) {
        this.deliveryWindow = new TimeWindow(from, to);
        return this;
    }

    public OrderBuilder redeemLoyaltyPoints(int points) {
        this.loyaltyPointsRedeemed = points;
        return this;
    }

    public OrderBuilder digitalOnly() {
        this.isDigitalOnly = true;
        return this;
    }

    public Order build() {
        // Validation — enforces business invariants
        if (items.isEmpty()) {
            throw new IllegalStateException("Order must have at least one item");
        }
        if (!isDigitalOnly && shippingAddress == null) {
            throw new IllegalStateException("Physical orders require a shipping address");
        }
        if (loyaltyPointsRedeemed < 0) {
            throw new IllegalStateException("Cannot redeem negative loyalty points");
        }
        // Construct the immutable product
        return new Order(this);
    }
}

// Director — optional; orchestrates builders for common scenarios
public class CommonOrderFactory {

    public static Order createPhysicalOrder(List<LineItem> items, Address address) {
        OrderBuilder builder = new OrderBuilder();
        items.forEach(item -> builder.withItem(item.sku(), item.quantity(), item.price()));
        return builder.shippingTo(address).build();
    }

    public static Order createGiftOrder(List<LineItem> items, Address address, String message) {
        return new OrderBuilder()
            .withItem(/* ... */)
            .shippingTo(address)
            .withGiftMessage(message)
            .deliverBetween(LocalDateTime.now(), LocalDateTime.now().plusDays(5))
            .build();
    }

    public static Order createDigitalOrder(List<LineItem> digitalItems) {
        OrderBuilder builder = new OrderBuilder().digitalOnly();
        digitalItems.forEach(item -> builder.withItem(item.sku(), item.quantity(), item.price()));
        return builder.build();
    }
}

// Client — checkout service
Order order = new OrderBuilder()
    .withItem("SKU-001", 2, Money.of(29.99))
    .withItem("SKU-047", 1, Money.of(14.99))
    .shippingTo(new Address("123 Main St", "San Francisco", "CA", "94105"))
    .applyPromo("SAVE20")
    .redeemLoyaltyPoints(500)
    .withGiftMessage("Happy Birthday!")
    .build();
```

### How It Works (walkthrough)

1. Client chains builder methods — each returns `this` (fluent interface)
2. `build()` runs all validation — fail-fast with clear error messages before object is created
3. `new Order(this)` passes the builder to the private constructor — Order copies all state immutably
4. Order is now fully constructed, valid, and immutable — safe to pass across threads

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | `OrderBuilder` handles construction logic; `Order` handles domain behavior |
| Open/Closed | ✅ | Add new optional fields to builder without changing `Order`'s public API |
| Liskov Substitution | ✅ | N/A — no inheritance hierarchy in this implementation |
| Interface Segregation | ✅ | Builder exposes only construction methods; Order exposes only domain methods |
| Dependency Inversion | ✅ | Client depends on `OrderBuilder` interface, not Order's internal structure |

---

## When to Use

- Objects with 4+ optional parameters — eliminates telescoping constructors and setter-based partial construction
- Construction must be validated before the object is usable — `build()` is the validation gate
- The same step-by-step process creates different representations (physical vs digital order)
- Immutability is important — builder holds mutable state; product is immutable

## When NOT to Use

- Simple objects with 1–3 fields — a constructor is cleaner
- When fields are all required — builder adds boilerplate with no benefit
- When the object is mutable by design — no need for a construction phase

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Readable fluent API — self-documenting construction | Extra builder class per product — doubles the class count |
| Validates at `build()` — no partially invalid objects | Builder state is mutable internally — not thread-safe during construction (by design) |
| Immutable product — thread-safe, no accidental mutation | Director pattern adds another layer of abstraction |
| Easy to add optional fields — no constructor changes | Optional without builder: Java record + static factory may suffice |

---

**FAANG interview application**: "For the Order domain object, I'd use Builder to handle the 12 optional fields cleanly. `build()` enforces invariants — physical orders must have a shipping address, items list can't be empty. The resulting `Order` is immutable — a `final` class with `final` fields and no setters. This makes it safe to pass across threads without defensive copying. In Java I'd consider Lombok's `@Builder` to remove the boilerplate while keeping the semantic benefits."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Abstract Factory](03-abstract-factory.md) | Builder focuses on constructing one complex object step-by-step; Abstract Factory creates a family of objects |
| [Composite](../structural/08-composite.md) | Builders are often used to build Composite trees (e.g., building a cart item tree step-by-step) |
| [Factory Method](02-factory-method.md) | Builder's `build()` acts as a factory — the Director can call different builder chains |
| [Prototype](05-prototype.md) | A builder could clone a prototype as the base and then modify fields |
