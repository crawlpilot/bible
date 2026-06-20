# 18. Observer
**Category**: Behavioral  
**GoF**: Yes  
**Complexity**: Low  
**Frequency in FAANG interviews**: Common

> Define a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.

---

## Problem It Solves

When an order is placed, the platform must: send an order confirmation email, send a push notification, decrement inventory, accrue loyalty points, track the analytics event, and update the search index. If `OrderService` directly calls each handler, it's coupled to all of them — adding a new handler (webhook to merchant's ERP) requires modifying `OrderService`. Observer decouples publishers from subscribers.

## Structure (Participants)

```
    «interface»                    «interface»
   OrderEventPublisher           OrderEventListener
┌─────────────────────────┐   ┌─────────────────────────┐
│ + subscribe(listener)   │   │ + onEvent(event)         │
│ + unsubscribe(listener) │   └─────────────────────────┘
│ + publish(event)        │              △
└─────────────────────────┘   ┌──────────┼──────────────┐
                              │          │               │
                         EmailNotifier PushNotifier InventoryUpdater
                         LoyaltyAccruer AnalyticsTracker SearchIndexer
```

Key participants:
- **Subject** (`OrderEventPublisher`): maintains subscriber list; publishes events
- **Observer** (`OrderEventListener`): interface for receiving events
- **Concrete Observers**: each implements its own reaction to the event
- **Event** (`OrderPlacedEvent`): carries the state change data

---

## Real-World Use Case: OrderPlaced Event Fan-Out

An e-commerce platform fans out `OrderPlaced`, `OrderShipped`, `OrderCancelled`, and `OrderReturned` events to multiple independent handlers. Each handler is independently deployable and testable. Adding a new integration (merchant ERP webhook) means adding one new listener — `OrderService` is untouched.

### Implementation

```java
// Event types
public sealed interface OrderEvent permits
    OrderPlacedEvent, OrderShippedEvent, OrderCancelledEvent, OrderReturnedEvent {}

public record OrderPlacedEvent(Order order, User user, String channel, Instant occurredAt) implements OrderEvent {}
public record OrderShippedEvent(Order order, ShipmentTracking tracking, Instant occurredAt) implements OrderEvent {}
public record OrderCancelledEvent(Order order, String reason, Instant occurredAt) implements OrderEvent {}

// Observer interface
public interface OrderEventListener {
    void onEvent(OrderEvent event);
    boolean supports(Class<? extends OrderEvent> eventType);  // for typed dispatch
}

// Subject — synchronous in-process publisher
public class OrderEventPublisher {
    private final List<OrderEventListener> listeners = new CopyOnWriteArrayList<>();

    public void subscribe(OrderEventListener listener) { listeners.add(listener); }
    public void unsubscribe(OrderEventListener listener) { listeners.remove(listener); }

    public void publish(OrderEvent event) {
        for (OrderEventListener listener : listeners) {
            if (listener.supports(event.getClass())) {
                try {
                    listener.onEvent(event);
                } catch (Exception e) {
                    // One listener failure should not block others
                    log.error("Listener {} failed for event {}", listener.getClass().getSimpleName(), event, e);
                }
            }
        }
    }
}

// Concrete Observers
public class EmailNotificationListener implements OrderEventListener {
    private final EmailService emailService;

    @Override
    public void onEvent(OrderEvent event) {
        if (event instanceof OrderPlacedEvent e) {
            emailService.sendOrderConfirmation(e.order(), e.user());
        } else if (event instanceof OrderShippedEvent e) {
            emailService.sendShippingConfirmation(e.order(), e.tracking());
        }
    }

    @Override
    public boolean supports(Class<? extends OrderEvent> type) {
        return type == OrderPlacedEvent.class || type == OrderShippedEvent.class;
    }
}

public class InventoryUpdaterListener implements OrderEventListener {
    private final InventoryService inventoryService;

    @Override
    public void onEvent(OrderEvent event) {
        if (event instanceof OrderPlacedEvent e) {
            e.order().items().forEach(item ->
                inventoryService.decrementReserved(item.sku(), item.quantity())
            );
        } else if (event instanceof OrderCancelledEvent e) {
            e.order().items().forEach(item ->
                inventoryService.releaseReservation(item.sku(), item.quantity())
            );
        }
    }

    @Override
    public boolean supports(Class<? extends OrderEvent> type) {
        return type == OrderPlacedEvent.class || type == OrderCancelledEvent.class;
    }
}

public class LoyaltyPointsListener implements OrderEventListener {
    private final LoyaltyService loyaltyService;

    @Override
    public void onEvent(OrderEvent event) {
        if (event instanceof OrderPlacedEvent e) {
            loyaltyService.accruePoints(e.user().id(), e.order().total());
        } else if (event instanceof OrderCancelledEvent e) {
            loyaltyService.reversePoints(e.user().id(), e.order().id());
        }
    }

    @Override
    public boolean supports(Class<? extends OrderEvent> type) {
        return type == OrderPlacedEvent.class || type == OrderCancelledEvent.class;
    }
}

public class AnalyticsTrackingListener implements OrderEventListener {
    private final AnalyticsClient analyticsClient;

    @Override
    public void onEvent(OrderEvent event) {
        if (event instanceof OrderPlacedEvent e) {
            analyticsClient.trackEvent("order_placed", Map.of(
                "orderId", e.order().id(),
                "userId", e.user().id(),
                "total", e.order().total().toDouble(),
                "channel", e.channel(),
                "itemCount", e.order().items().size()
            ));
        }
    }

    @Override public boolean supports(Class<? extends OrderEvent> type) {
        return type == OrderPlacedEvent.class;
    }
}

// OrderService — publisher is injected
public class OrderService {
    private final OrderRepository orderRepo;
    private final OrderEventPublisher publisher;

    public Order placeOrder(OrderRequest request, User user) {
        Order order = createAndSave(request, user);
        publisher.publish(new OrderPlacedEvent(order, user, request.channel(), Instant.now()));
        return order;
    }

    // No knowledge of email, inventory, loyalty, analytics — decoupled
}

// Wiring (in DI configuration)
OrderEventPublisher publisher = new OrderEventPublisher();
publisher.subscribe(new EmailNotificationListener(emailService));
publisher.subscribe(new InventoryUpdaterListener(inventoryService));
publisher.subscribe(new LoyaltyPointsListener(loyaltyService));
publisher.subscribe(new AnalyticsTrackingListener(analyticsClient));

// Adding merchant webhook — zero changes to OrderService or existing listeners
publisher.subscribe(new MerchantWebhookListener(webhookService));
```

### How It Works (walkthrough)

1. `orderService.placeOrder(request, user)` → saves order → publishes `OrderPlacedEvent`
2. Publisher iterates 5 listeners; each checks `supports(OrderPlacedEvent.class)`
3. EmailNotifier → sends confirmation email
4. InventoryUpdater → decrements reserved inventory
5. LoyaltyPoints → accrues 1% of order total in points
6. AnalyticsTracker → posts event to analytics pipeline
7. If LoyaltyPoints throws: logged, other listeners continue — no cascade failure

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Each listener does one thing; publisher just notifies |
| Open/Closed | ✅ | Add new listener without touching publisher or `OrderService` |
| Liskov Substitution | ✅ | All listeners substitutable through `OrderEventListener` |
| Interface Segregation | ✅ | `onEvent()` + `supports()` — focused interface |
| Dependency Inversion | ✅ | `OrderService` depends on `OrderEventPublisher` abstraction |

---

## When to Use

- One event must trigger multiple independent reactions (fan-out)
- The set of subscribers is not known at compile time (plugins, integrations)
- Publishers and subscribers should evolve independently (different teams, different services)

## When NOT to Use

- Observers are synchronous and one failure must abort all subsequent observers — use a saga instead
- Observer order matters and must be guaranteed — CoR is more appropriate
- Event payload is large — consider passing a reference or event ID instead of the full object

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Publisher decoupled from all subscribers — adding integrations is zero-touch | Debugging: hard to trace which observer handled what, and in what order |
| Each observer independently unit-testable | Accidental dependency on observer execution order |
| Subscriber failures isolated | Memory leaks if subscribers aren't unsubscribed (especially in long-running objects) |

---

**FAANG interview application**: "Observer is the pattern for event fan-out — OrderPlaced triggers email, inventory, loyalty, analytics, and search index. In production at scale, I'd push the `OrderPlacedEvent` to Kafka instead of in-process observers — each consumer group is an independent 'observer' that processes at its own pace. This gives persistence, replay-ability, and backpressure. The in-process Observer is good for synchronous needs; Kafka-based is better for cross-service fan-out at 100K+ events/sec."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Mediator](16-mediator.md) | Observer decouples via broadcast; Mediator centralizes coordination. Mediator can be implemented using Observer internally. |
| [Domain Events](../modern/31-domain-events.md) | Domain Events is Observer at the DDD layer — events cross bounded context boundaries |
| [Outbox Pattern](../modern/28-outbox-pattern.md) | For reliable cross-service observer notification, publish events via DB outbox to Kafka |
