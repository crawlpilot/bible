# 31. Domain Events
**Category**: Modern / Enterprise  
**GoF**: No (Evans, "Domain-Driven Design", 2003)  
**Complexity**: Medium  
**Frequency in FAANG interviews**: Common

> Explicitly model significant occurrences within the domain as events, enabling other parts of the system to react without tight coupling.

---

## Problem It Solves

When `Order.place()` is called, it must: accrue loyalty points, update the seller dashboard, notify the fulfillment warehouse, fire a marketing pixel, and trigger the search index update. Calling each directly from `OrderService` creates coupling to 5 unrelated domains. Domain Events decouple this: `Order.place()` raises `OrderPlacedEvent` internally, domain event handlers in other bounded contexts react independently.

## Structure (Participants)

```
         Order (aggregate)
    ┌─────────────────────────────┐
    │ + place(cmd)                │──► raises OrderPlacedEvent
    │ + cancel(reason)            │──► raises OrderCancelledEvent
    │ + ship(tracking)            │──► raises OrderShippedEvent
    └─────────────────────────────┘
                 │
    DomainEventPublisher.publish()
                 │
    ┌────────────┼──────────────────────────────────────┐
    │            │              │              │         │
LoyaltyBC  FulfillmentBC  SellerDashBC  MarketingBC  SearchBC
 Handler      Handler         Handler      Handler    Handler
```

Key participants:
- **Domain Event** (`OrderPlacedEvent`): immutable value object; records what happened, when, and with what context
- **Aggregate** (`Order`): the source — raises events as a side effect of state changes
- **Domain Event Publisher** (`DomainEventPublisher`): dispatches events to registered handlers
- **Event Handlers**: live in separate bounded contexts; react to events without knowing the source

---

## Real-World Use Case: Order Domain Events → Multiple Bounded Contexts

An order aggregate publishes events at key lifecycle moments. Each bounded context subscribes to relevant events without the order aggregate knowing about them.

### Implementation

```java
// Base domain event — every event has these fields
public abstract class DomainEvent {
    private final String eventId;
    private final Instant occurredAt;
    private final String aggregateId;
    private final String aggregateType;

    protected DomainEvent(String aggregateId, String aggregateType) {
        this.eventId = UUID.randomUUID().toString();
        this.occurredAt = Instant.now();
        this.aggregateId = aggregateId;
        this.aggregateType = aggregateType;
    }

    public String getEventId()       { return eventId; }
    public Instant getOccurredAt()   { return occurredAt; }
    public String getAggregateId()   { return aggregateId; }
    public String getAggregateType() { return aggregateType; }
}

// Domain Events — named in past tense
public class OrderPlacedEvent extends DomainEvent {
    private final String userId;
    private final List<OrderItem> items;
    private final Money total;
    private final String channel;
    private final Address shippingAddress;

    public OrderPlacedEvent(Order order) {
        super(order.getId(), "Order");
        this.userId = order.getUserId();
        this.items = List.copyOf(order.getItems());
        this.total = order.getTotal();
        this.channel = order.getChannel();
        this.shippingAddress = order.getShippingAddress();
    }

    // Getters...
}

public class OrderCancelledEvent extends DomainEvent {
    private final String userId;
    private final Money refundAmount;
    private final String reason;

    public OrderCancelledEvent(Order order, String reason) {
        super(order.getId(), "Order");
        this.userId = order.getUserId();
        this.refundAmount = order.getTotal();
        this.reason = reason;
    }
}

public class OrderShippedEvent extends DomainEvent {
    private final String userId;
    private final ShipmentTracking tracking;

    public OrderShippedEvent(Order order, ShipmentTracking tracking) {
        super(order.getId(), "Order");
        this.userId = order.getUserId();
        this.tracking = tracking;
    }
}

// Aggregate — registers events internally, not published yet
public class Order {
    private String id;
    private String userId;
    private OrderStatus status;
    private List<OrderItem> items;
    private Money total;
    private String channel;
    private Address shippingAddress;
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    public void place(PlaceOrderCommand cmd) {
        // Business logic
        this.status = OrderStatus.PENDING;
        this.items = List.copyOf(cmd.items());
        this.total = cmd.total();

        // Register event — NOT published yet
        domainEvents.add(new OrderPlacedEvent(this));
    }

    public void cancel(String reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED)
            throw new InvalidTransitionException("Cannot cancel " + status + " order");
        this.status = OrderStatus.CANCELLED;
        domainEvents.add(new OrderCancelledEvent(this, reason));
    }

    public void ship(ShipmentTracking tracking) {
        this.status = OrderStatus.SHIPPED;
        domainEvents.add(new OrderShippedEvent(this, tracking));
    }

    public List<DomainEvent> getDomainEvents() { return Collections.unmodifiableList(domainEvents); }
    public void clearDomainEvents()             { domainEvents.clear(); }
}

// Domain Event Publisher
public class DomainEventPublisher {
    private static final Map<Class<? extends DomainEvent>, List<DomainEventHandler>> handlers = new ConcurrentHashMap<>();

    public static <T extends DomainEvent> void subscribe(Class<T> eventType, DomainEventHandler<T> handler) {
        handlers.computeIfAbsent(eventType, k -> new CopyOnWriteArrayList<>()).add(handler);
    }

    @SuppressWarnings("unchecked")
    public static void publish(DomainEvent event) {
        List<DomainEventHandler> eventHandlers = handlers.getOrDefault(event.getClass(), emptyList());
        for (DomainEventHandler handler : eventHandlers) {
            try {
                handler.handle(event);
            } catch (Exception e) {
                log.error("Handler {} failed for event {}", handler.getClass().getSimpleName(), event.getEventId(), e);
            }
        }
    }
}

// Application service — orchestrates aggregate + publishes events AFTER commit
@Service
@Transactional
public class OrderApplicationService {
    private final OrderRepository orderRepo;
    private final OutboxRepository outboxRepo;  // for reliable publishing
    private final ObjectMapper mapper;

    public Order placeOrder(PlaceOrderCommand cmd, User user) {
        Order order = new Order();
        order.place(cmd);
        orderRepo.save(order);

        // Publish domain events via outbox (reliable delivery)
        for (DomainEvent event : order.getDomainEvents()) {
            outboxRepo.save(OutboxEntry.fromDomainEvent(event));
        }
        order.clearDomainEvents();

        return order;
    }
}

// In-process handlers (same JVM, synchronous)
@DomainEventHandler
public class LoyaltyBoundedContextHandler {
    private final LoyaltyService loyaltyService;

    @HandleEvent(OrderPlacedEvent.class)
    public void on(OrderPlacedEvent event) {
        loyaltyService.accruePoints(event.getUserId(), event.getTotal());
    }

    @HandleEvent(OrderCancelledEvent.class)
    public void on(OrderCancelledEvent event) {
        loyaltyService.reversePoints(event.getUserId(), event.getAggregateId());
    }
}

@DomainEventHandler
public class SellerDashboardHandler {
    private final SellerDashboardService dashboardService;

    @HandleEvent(OrderPlacedEvent.class)
    public void on(OrderPlacedEvent event) {
        dashboardService.updateRevenueMetrics(event);
    }
}

// Cross-service handlers (via Kafka — registered by OutboxPoller publishing to Kafka)
// FulfillmentService, MarketingService subscribe to Kafka topic "order-events"
// and react to OrderPlacedEvent JSON payload
```

### How It Works (walkthrough)

1. `orderAppService.placeOrder(cmd, user)` → `order.place(cmd)` → domain event registered in `order.domainEvents`
2. `orderRepo.save(order)` → persisted
3. For each domain event: `outboxRepo.save(OutboxEntry.fromDomainEvent(event))` → outbox entry persisted (same TX)
4. TX commits → order + outbox entries atomically persisted
5. OutboxPoller publishes `OrderPlacedEvent` to Kafka `order-events` topic
6. In-process: `LoyaltyBoundedContextHandler.on(OrderPlacedEvent)` → accrues points
7. Cross-service: Kafka consumers (fulfillment, seller dashboard, marketing) process the event

---

## SOLID Analysis

| Principle | Satisfied? | How |
|-----------|-----------|-----|
| Single Responsibility | ✅ | Order manages order state; handlers manage reactions in their own bounded contexts |
| Open/Closed | ✅ | Add `SearchIndexHandler` — zero changes to Order or existing handlers |
| Liskov Substitution | ✅ | All events extend `DomainEvent`; all handlers are interchangeable |
| Interface Segregation | ✅ | Each handler subscribes only to events it cares about |
| Dependency Inversion | ✅ | Order depends on `DomainEvent` abstraction; publisher dispatches via handler interfaces |

---

## When to Use

- An aggregate's state change must trigger reactions in multiple other bounded contexts
- Bounded contexts must remain decoupled — the source should not know its subscribers
- Events must be durable and publishable across service boundaries
- Building event-driven architecture or microservices integration

## When NOT to Use

- Event is not meaningful to any other bounded context — don't publish events nobody consumes
- Immediate consistency is required between source and handler — use direct method calls (synchronous)
- Team is small with 1–2 services — event-driven complexity is not worth it

---

## Trade-offs

| Benefit | Cost |
|---------|------|
| Bounded contexts fully decoupled — Order knows nothing about Loyalty | Eventual consistency — Loyalty points may lag behind order placement |
| Add new consumers without touching the source aggregate | Debugging: harder to trace what reacted to an event and in what order |
| Event log provides audit trail of all significant domain occurrences | Event schema evolution is hard — consumers break on new/removed fields |

---

**FAANG interview application**: "Domain Events are the DDD mechanism for decoupling bounded contexts. When `Order.place()` succeeds, it raises `OrderPlacedEvent` — the Loyalty, Fulfillment, and Seller Dashboard bounded contexts react independently. The key implementation detail: the aggregate should not publish directly; it registers events internally, and the application service publishes them via the Outbox Pattern after the DB commit. This ensures that events are only published if the aggregate successfully persisted — no ghost events from rolled-back transactions."

---

## Related Patterns

| Pattern | Relationship |
|---------|-------------|
| [Observer](../behavioral/18-observer.md) | Domain Events is Observer at the DDD level — events cross bounded context boundaries |
| [Outbox Pattern](28-outbox-pattern.md) | Domain events should be durably published using the Outbox Pattern |
| [CQRS](25-cqrs.md) | Domain events bridge the write model and read projections in CQRS |
| [Event Sourcing](27-event-sourcing.md) | In Event Sourcing, domain events are the primary persistence mechanism |
