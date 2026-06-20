# 10. Facade
**Category**: Structural  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Provide a unified interface to a set of interfaces in a subsystem. Facade defines a higher-level interface that makes the subsystem easier to use.

---

## Problem It Solves

Placing an order requires coordinating: inventory reservation, fraud check, payment capture, order persistence, notification dispatch, shipping scheduling, loyalty points accrual, and analytics event emission. Without Facade, the API controller calls all 8 services directly — it's coupled to each service's API, initialization order, error handling, and rollback logic. Facade encapsulates all of that into `OrderPlacementFacade.placeOrder()` — the controller calls one method.

## Structure (Participants)

```
   «Client»
  OrderController
       │
       │  placeOrder(request)
       ▼
  OrderPlacementFacade
  ┌─────────────────────────────────────────┐
  │ + placeOrder(request): OrderConfirmation│
  │                                         │
  │  internally coordinates:                │
  │  ┌─────────────┐  ┌──────────────────┐  │
  │  │InventorySvc │  │  FraudCheckSvc   │  │
  │  └─────────────┘  └──────────────────┘  │
  │  ┌─────────────┐  ┌──────────────────┐  │
  │  │ PaymentSvc  │  │  OrderRepository │  │
  │  └─────────────┘  └──────────────────┘  │
  │  ┌─────────────┐  ┌──────────────────┐  │
  │  │NotificationS│  │  ShippingSvc     │  │
  │  └─────────────┘  └──────────────────┘  │
  │  ┌─────────────┐  ┌──────────────────┐  │
  │  │ LoyaltySvc  │  │  AnalyticsSvc    │  │
  │  └─────────────┘  └──────────────────┘  │
  └─────────────────────────────────────────┘
```

Key participants:
- **Facade** (`OrderPlacementFacade`): the single entry point; knows which subsystem classes to invoke and in what order
- **Subsystems**: `InventoryService`, `FraudCheckService`, `PaymentService`, etc. — each is unaware of the Facade
- **Client** (`OrderController`): calls the Facade; does not interact with subsystems directly

---

## Real-World Use Case: Order Placement Orchestration

A marketplace's order placement involves 8 steps with specific ordering, error handling, and compensation logic. The REST controller should be dumb — validate the request, call the facade, return the response. All the business orchestration lives in the facade.

### Implementation

```java
// Subsystem services (each independently developed and tested)
public interface InventoryService {
    ReservationId reserve(String sku, int quantity, String orderId);
    void release(ReservationId reservationId);
}

public interface FraudCheckService {
    FraudCheckResult evaluate(OrderRequest request, User user);
}

public interface PaymentService {
    PaymentResult charge(Money amount, PaymentMethod method, String orderId);
    void refund(String transactionId);
}

public interface OrderRepository {
    Order save(Order order);
    void updateStatus(String orderId, OrderStatus status);
}

public interface NotificationService {
    void sendOrderConfirmation(Order order, User user);
    void sendPaymentFailedNotification(Order order, User user, String reason);
}

public interface ShippingService {
    ShipmentId scheduleShipment(Order order, Address destination);
}

public interface LoyaltyService {
    void accruePoints(String userId, Money orderValue);
}

public interface AnalyticsService {
    void trackOrderPlaced(Order order, User user, String channel);
}

// Facade — encapsulates all orchestration
public class OrderPlacementFacade {
    private final InventoryService inventoryService;
    private final FraudCheckService fraudCheckService;
    private final PaymentService paymentService;
    private final OrderRepository orderRepository;
    private final NotificationService notificationService;
    private final ShippingService shippingService;
    private final LoyaltyService loyaltyService;
    private final AnalyticsService analyticsService;

    // All dependencies injected — Facade testable with mocks
    public OrderPlacementFacade(/* all services */) { /* ... */ }

    public OrderConfirmation placeOrder(OrderRequest request, User user) {
        // Step 1: Fraud check — fail fast before reserving inventory
        FraudCheckResult fraud = fraudCheckService.evaluate(request, user);
        if (fraud.isSuspicious()) {
            throw new FraudSuspectedException(fraud.reason());
        }

        // Step 2: Reserve inventory for all items
        List<ReservationId> reservations = new ArrayList<>();
        try {
            for (OrderItem item : request.items()) {
                ReservationId res = inventoryService.reserve(item.sku(), item.quantity(), request.orderId());
                reservations.add(res);
            }
        } catch (OutOfStockException e) {
            // Compensate: release already-reserved items
            reservations.forEach(inventoryService::release);
            throw e;
        }

        // Step 3: Persist order in PENDING state
        Order order = new Order(request, OrderStatus.PENDING);
        order = orderRepository.save(order);

        // Step 4: Charge payment
        PaymentResult payment;
        try {
            payment = paymentService.charge(order.total(), request.paymentMethod(), order.id());
        } catch (PaymentFailedException e) {
            // Compensate: release inventory, update order to PAYMENT_FAILED
            reservations.forEach(inventoryService::release);
            orderRepository.updateStatus(order.id(), OrderStatus.PAYMENT_FAILED);
            notificationService.sendPaymentFailedNotification(order, user, e.getMessage());
            throw e;
        }

        // Step 5: Confirm order
        order = order.withStatus(OrderStatus.CONFIRMED).withTransactionId(payment.transactionId());
        orderRepository.save(order);

        // Steps 6–8: Fire-and-forget side effects (async, non-blocking)
        scheduleShipment(order);
        accruePoints(user, order);
        trackAnalytics(order, user, request.channel());

        // Step 9: Notify user
        notificationService.sendOrderConfirmation(order, user);

        return new OrderConfirmation(order.id(), order.total(), payment.transactionId());
    }

    private void scheduleShipment(Order order) {
        try { shippingService.scheduleShipment(order, order.shippingAddress()); }
        catch (Exception e) { log.error("Shipping scheduling failed for {}", order.id(), e); }
    }

    private void accruePoints(User user, Order order) {
        try { loyaltyService.accruePoints(user.id(), order.total()); }
        catch (Exception e) { log.warn("Loyalty accrual failed for user {}", user.id(), e); }
    }

    private void trackAnalytics(Order order, User user, String channel) {
        try { analyticsService.trackOrderPlaced(order, user, channel); }
        catch (Exception e) { log.warn("Analytics tracking failed for order {}", order.id(), e); }
    }
}

// Client — REST controller
@RestController
public class OrderController {
    private final OrderPlacementFacade orderFacade;
    private final UserService userService;

    @PostMapping("/orders")
    public ResponseEntity<OrderConfirmation> placeOrder(
            @RequestBody OrderRequest request,
            @AuthenticationPrincipal String userId) {
        User user = userService.findById(userId);
        OrderConfirmation confirmation = orderFacade.placeOrder(request, user);
        return ResponseEntity.status(201).body(confirmation);
    }
    // Controller is 10 lines — all orchestration in Facade
}
```

### How It Works (walkthrough)

1. Controller receives POST `/orders`, validates JWT → extracts userId
2. Calls `orderFacade.placeOrder(request, user)` — 1 method call
3. Facade orchestrates: fraud → inventory reserve → persist → charge → confirm → ship → points → analytics → notify
4. On payment failure: facade compensates (release inventory, update status, notify user), controller receives the exception and returns 402
5. Controller never imports `InventoryService`, `PaymentService`, etc. — zero coupling to subsystems

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Facade's job: orchestrate order placement. Each subsystem has its own SRP. |
| Open/Closed | ✅ | Add `GiftWrappingService` — add it to Facade, controller unchanged |
| Liskov Substitution | ✅ | Each subsystem implements its own interface — test with mocks |
| Interface Segregation | ✅ | Each subsystem has a focused interface — Facade depends on all of them |
| Dependency Inversion | ✅ | Facade depends on service interfaces, not concrete implementations |

---

## When to Use

- A complex subsystem needs a simple entry point for common use cases
- Tightly coupled client → subsystem code — Facade re-introduces a seam
- Building a layered architecture — each layer's public API is a Facade over the layer below
- Reducing coupling: controller/API layer should not know about service orchestration internals

## When NOT to Use

- The subsystem is simple — a Facade over 2 services adds indirection for no benefit
- Clients need fine-grained control over subsystem steps — Facade hides too much
- The Facade becomes a God class that grows without bound — split it by domain when this happens

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Simple client code — 1 call replaces 8 | Facade can become a God object if not bounded |
| All orchestration in one place — easy to understand the full flow | Clients who need step-by-step control can't use the Facade |
| Facade is the natural boundary for integration tests | Compensating transaction logic is complex — facade must get this right |

---

**FAANG interview application**: "Facade is the right pattern for order placement orchestration. The controller should be 10 lines — validate, call facade, return response. All the 'what happens when payment fails' logic (release inventory, update status, send failure notification) belongs in the facade. This makes the orchestration independently testable: mock all 8 subsystem services, verify the facade calls them in the right order and compensates correctly on failure."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Adapter](06-adapter.md) | Adapter makes incompatible interfaces work; Facade simplifies a complex but compatible subsystem |
| [Mediator](../behavioral/16-mediator.md) | Mediator coordinates objects that know about each other; Facade acts as a one-way entry point where subsystems don't know about the Facade |
| [Singleton](../creational/01-singleton.md) | Facade is often a Singleton — one entry point to the subsystem |
| [Saga](../modern/26-saga.md) | For distributed systems, the Saga pattern handles the same orchestration concerns as Facade but with compensating transactions across service boundaries |
