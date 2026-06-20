# 19. State
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Allow an object to alter its behavior when its internal state changes. The object will appear to change its class.

---

## Problem It Solves

An order has 7 states: Pending, Confirmed, Processing, Shipped, Delivered, Returned, Cancelled. Each state allows only certain transitions and operations (you can't ship a cancelled order; you can only return a delivered order). Without State, you write a `switch (order.status)` in every method (`cancel()`, `ship()`, `return()`), and each switch block grows with every new state. With State, each state is a class that defines which transitions are valid and what to do.

## Structure (Participants)

```
              «interface»
              OrderState
        ┌──────────────────────────────┐
        │ + confirm(order)             │
        │ + processPayment(order)      │
        │ + ship(order)                │
        │ + deliver(order)             │
        │ + cancel(order, reason)      │
        │ + returnOrder(order)         │
        │ + getName(): String          │
        └──────────────────────────────┘
                    △
  ┌─────────┬───────┼────────┬─────────┐
  │         │       │        │         │
Pending Confirmed Shipped Delivered Cancelled
State    State    State     State     State
                         ReturnedState
```

Key participants:
- **State** (`OrderState`): interface with all possible operations
- **Concrete States** (`PendingState`, `ConfirmedState`, etc.): each implements valid operations and throws `InvalidTransitionException` for invalid ones
- **Context** (`Order`): holds the current state; delegates all operations to `currentState`; has `setState()` for transitions

---

## Real-World Use Case: Order State Machine

An e-commerce order lifecycle has 7 states and strict valid transitions. Each state knows what it can and cannot do. The `Order` class is clean — no switch statements, no if-else chains.

```
Pending → Confirmed → Processing → Shipped → Delivered → Returned
   ↓          ↓            ↓           ↓         ↓
Cancelled  Cancelled    Cancelled  (no cancel) (no cancel)
```

### Implementation

```java
// State interface
public interface OrderState {
    void confirm(Order order);
    void processPayment(Order order, PaymentResult payment);
    void ship(Order order, ShipmentTracking tracking);
    void deliver(Order order, Instant deliveredAt);
    void cancel(Order order, String reason);
    void requestReturn(Order order, ReturnReason reason);
    String getName();
}

// Base class for default "invalid" behavior
public abstract class AbstractOrderState implements OrderState {
    @Override public void confirm(Order o)              { invalid("confirm"); }
    @Override public void processPayment(Order o, PaymentResult p) { invalid("processPayment"); }
    @Override public void ship(Order o, ShipmentTracking t)        { invalid("ship"); }
    @Override public void deliver(Order o, Instant at)             { invalid("deliver"); }
    @Override public void cancel(Order o, String r)    { invalid("cancel"); }
    @Override public void requestReturn(Order o, ReturnReason r)   { invalid("requestReturn"); }

    protected void invalid(String op) {
        throw new InvalidTransitionException(
            "Cannot " + op + " an order in state: " + getName());
    }
}

// Concrete States
public class PendingState extends AbstractOrderState {
    @Override
    public void confirm(Order order) {
        order.setConfirmedAt(Instant.now());
        order.setState(new ConfirmedState());
        order.publishEvent(new OrderConfirmedEvent(order));
    }

    @Override
    public void cancel(Order order, String reason) {
        order.setCancellationReason(reason);
        order.setState(new CancelledState());
        order.publishEvent(new OrderCancelledEvent(order, reason));
    }

    @Override public String getName() { return "PENDING"; }
}

public class ConfirmedState extends AbstractOrderState {
    @Override
    public void processPayment(Order order, PaymentResult payment) {
        order.setPaymentTransactionId(payment.transactionId());
        order.setState(new ProcessingState());
        order.publishEvent(new OrderPaymentCapturedEvent(order, payment));
    }

    @Override
    public void cancel(Order order, String reason) {
        // Confirmed can be cancelled — trigger inventory release
        order.setCancellationReason(reason);
        order.setState(new CancelledState());
        order.publishEvent(new OrderCancelledEvent(order, reason));
    }

    @Override public String getName() { return "CONFIRMED"; }
}

public class ProcessingState extends AbstractOrderState {
    @Override
    public void ship(Order order, ShipmentTracking tracking) {
        order.setTracking(tracking);
        order.setShippedAt(Instant.now());
        order.setState(new ShippedState());
        order.publishEvent(new OrderShippedEvent(order, tracking));
    }

    @Override
    public void cancel(Order order, String reason) {
        // Processing: cancel triggers payment refund
        order.setCancellationReason(reason);
        order.setState(new CancelledState());
        order.publishEvent(new OrderCancelledEvent(order, reason));
    }

    @Override public String getName() { return "PROCESSING"; }
}

public class ShippedState extends AbstractOrderState {
    @Override
    public void deliver(Order order, Instant deliveredAt) {
        order.setDeliveredAt(deliveredAt);
        order.setState(new DeliveredState());
        order.publishEvent(new OrderDeliveredEvent(order, deliveredAt));
    }

    // Cannot cancel or return while shipped
    @Override public String getName() { return "SHIPPED"; }
}

public class DeliveredState extends AbstractOrderState {
    private static final Duration RETURN_WINDOW = Duration.ofDays(30);

    @Override
    public void requestReturn(Order order, ReturnReason reason) {
        if (Instant.now().isAfter(order.getDeliveredAt().plus(RETURN_WINDOW))) {
            throw new ReturnWindowExpiredException("Return window of 30 days has closed");
        }
        order.setReturnReason(reason);
        order.setState(new ReturnRequestedState());
        order.publishEvent(new ReturnRequestedEvent(order, reason));
    }

    // Cannot cancel a delivered order
    @Override public String getName() { return "DELIVERED"; }
}

public class CancelledState extends AbstractOrderState {
    // All operations throw InvalidTransitionException — terminal state
    @Override public String getName() { return "CANCELLED"; }
}

public class ReturnRequestedState extends AbstractOrderState {
    @Override public String getName() { return "RETURN_REQUESTED"; }
    // Further transitions: RETURN_APPROVED, RETURN_REJECTED, REFUNDED
}

// Context — the Order class
public class Order {
    private OrderState currentState;
    private String id;
    private Instant confirmedAt;
    private String paymentTransactionId;
    private ShipmentTracking tracking;
    private Instant shippedAt;
    private Instant deliveredAt;
    private String cancellationReason;
    private ReturnReason returnReason;
    private final OrderEventPublisher eventPublisher;

    public Order(String id, OrderEventPublisher publisher) {
        this.id = id;
        this.eventPublisher = publisher;
        this.currentState = new PendingState();  // always starts Pending
    }

    // Delegate all operations to current state
    public void confirm()                          { currentState.confirm(this); }
    public void processPayment(PaymentResult p)    { currentState.processPayment(this, p); }
    public void ship(ShipmentTracking tracking)    { currentState.ship(this, tracking); }
    public void deliver(Instant deliveredAt)       { currentState.deliver(this, deliveredAt); }
    public void cancel(String reason)              { currentState.cancel(this, reason); }
    public void requestReturn(ReturnReason reason) { currentState.requestReturn(this, reason); }

    public String getStatus() { return currentState.getName(); }

    // Package-private: only states can call these
    void setState(OrderState newState)   { this.currentState = newState; }
    void publishEvent(OrderEvent event)  { eventPublisher.publish(event); }
    void setConfirmedAt(Instant t)       { this.confirmedAt = t; }
    void setPaymentTransactionId(String t) { this.paymentTransactionId = t; }
    void setTracking(ShipmentTracking t) { this.tracking = t; }
    void setShippedAt(Instant t)         { this.shippedAt = t; }
    void setDeliveredAt(Instant t)       { this.deliveredAt = t; }
    void setCancellationReason(String r) { this.cancellationReason = r; }
    void setReturnReason(ReturnReason r) { this.returnReason = r; }
    Instant getDeliveredAt()             { return deliveredAt; }
}

// Usage
Order order = new Order("ORD-123", eventPublisher);
order.confirm();                              // PendingState → ConfirmedState
order.processPayment(paymentResult);          // ConfirmedState → ProcessingState
order.ship(ShipmentTracking.of("FX123456")); // ProcessingState → ShippedState
order.deliver(Instant.now());                 // ShippedState → DeliveredState

order.cancel("Customer request");             // throws InvalidTransitionException — DELIVERED can't be cancelled
```

### How It Works (walkthrough)

1. `order.cancel("reason")` on a `ShippedState` order
2. `ShippedState.cancel()` is not overridden → `AbstractOrderState.cancel()` → throws `InvalidTransitionException("Cannot cancel an order in state: SHIPPED")`
3. `order.cancel("reason")` on a `ConfirmedState` order
4. `ConfirmedState.cancel()` → sets cancellation reason → `order.setState(new CancelledState())` → publishes `OrderCancelledEvent`
5. Next operation on cancelled order → `CancelledState.confirm()` → throws `InvalidTransitionException`

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each state class handles one lifecycle stage; `Order` handles business data |
| Open/Closed | ✅ | Add `DisputeState` — new class; existing states and `Order` unchanged |
| Liskov Substitution | ✅ | All states substitutable through `OrderState` |
| Interface Segregation | ⚠️ | `OrderState` has many methods; most states throw for most methods |
| Dependency Inversion | ✅ | `Order` depends on `OrderState` interface |

---

## When to Use

- An object's behavior depends on its state and must change at runtime
- State-specific code appears in many methods as `if/switch` branching on state
- States have explicit valid transitions (state machine)
- Transition logic is complex — invalid transition detection, side effects, event publishing

## When NOT to Use

- Few states with simple transitions — use an enum + switch; it's more readable
- State machine is defined in external config/DSL — use a framework (Spring State Machine) instead
- State transitions have no side effects — a simple state field with validation is enough

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Invalid transitions caught at compile-time-analogous level (pattern guarantees) | Class proliferation: one class per state |
| Each state independently testable | State objects may need access to Order internals (package-private pattern) |
| Adding new state = new class; no changes to existing states | Finding which state an order is in requires inspecting the type |

---

**FAANG interview application**: "State is the right pattern for an order lifecycle with 7 states and strict valid transitions. The key insight: each state defines which operations are valid, not the Order class. This means `order.cancel()` on a SHIPPED order automatically throws — the state machine enforces the business rule. Adding a new DISPUTE state means one new class and updating DELIVERED's `requestReturn()` to also handle disputes — no changes to PendingState, ShippedState, or the Order class."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Strategy](20-strategy.md) | Both delegate to an interchangeable object. Strategy changes the algorithm; State changes the behavior based on lifecycle position. Strategy objects are usually stateless; State objects know about transitions. |
| [Command](14-command.md) | Commands often trigger state transitions — `ShipCommand` calls `order.ship()` |
| [Observer](18-observer.md) | State transitions publish events — state classes call `order.publishEvent()` |
