# 25. CQRS (Command Query Responsibility Segregation)
**Category**: Modern / Enterprise  
**GoF**: No (Fowler/Young, 2010)  
**Complexity**: High  
**Frequency in FAANG interviews**: Common

---

## The One-Line Summary

> **Use one model for writing data, a completely different model for reading data.** Never mix them.

---

## Part 1 — The Problem (Read This First)

### A Restaurant Analogy

Imagine a restaurant where the *same person* is the chef AND the waiter.

When a customer orders (a **write** — "I want spaghetti"), the chef must:
- Check ingredient stock
- Cook with precise heat/timing
- Enforce food safety rules

When a customer asks "what's today's special?" (a **read**), they just need a quick verbal answer.

If the chef/waiter is one person, every "what's the special?" question interrupts cooking. The chef's mental model — holding ingredient counts, temperatures, timing — is **not the right model** for answering casual questions.

CQRS says: **hire a separate waiter for questions.** The chef focuses only on cooking. The waiter knows the pre-printed specials board (a read-optimised view) and answers instantly.

---

### The Real Scenario: Order Service

You're building an order service at Amazon-scale:

```
Write operations (things that CHANGE data):
  - Place order         → validate payment, check stock, persist to DB
  - Cancel order        → enforce rules (can't cancel shipped orders)
  - Return item         → calculate refund, update inventory

Read operations (things that DISPLAY data):
  - Check order status  → called 500× per order placed (customer polls "where's my package?")
  - Order history       → shows last 50 orders with thumbnail and price
  - Business dashboard  → "total revenue today by region" — aggregation over millions of rows
```

**The problem with ONE model for both:**

```
// ❌ BEFORE CQRS — single Order table, same model for reads and writes
public class OrderService {

    public Order placeOrder(PlaceOrderRequest req) {
        // Complex write logic: validate, check inventory, process payment
        Order order = new Order(req);
        orderRepo.save(order);
        return order;
    }

    // This read query hits the SAME normalized write database
    // "Get order history" joins 6 tables:
    // orders JOIN order_items JOIN products JOIN shipping JOIN payments JOIN users
    public List<Order> getOrderHistory(String userId) {
        return orderRepo.findByUserId(userId); // ← slow 6-table join on every customer request
    }

    // "Order dashboard" runs a GROUP BY aggregation on the orders table
    // ← blocks writes while it scans millions of rows
    public DashboardData getDashboard(DateRange range) {
        return orderRepo.aggregateDashboard(range); // ← kills write performance
    }
}
```

**Why this breaks at scale:**

```
Problem 1 — Read/write contention:
  Dashboard query scans 10M rows (takes 5s) → holds table-level stats locks
  → concurrent order placements slow down
  → customers experience latency spikes at midnight when reports run

Problem 2 — Read models are wrong for the query:
  Order status check needs: orderId, status, trackingNumber → 3 fields
  But the query returns the full normalized Order object → 50 fields, 6 joins
  → 10ms query becomes 200ms because we're reading data we don't need

Problem 3 — Can't optimize reads without compromising write integrity:
  "Add a Redis cache for order status" → cache invalidation is a nightmare
  "Denormalize order_items into orders table" → breaks write normalization rules
  You can't serve both masters with one table design
```

---

## Part 2 — The Solution

### The Core Idea

Split the application into two halves:

```
┌──────────────────────────────────────────────────────────────────┐
│                         CQRS SPLIT                                │
│                                                                    │
│  WRITE SIDE (Commands)            READ SIDE (Queries)              │
│  ─────────────────────            ──────────────────               │
│  "Change the world"               "Describe the world"             │
│                                                                    │
│  PlaceOrder                       getOrderStatus(id)               │
│  CancelOrder         ──events──►  getOrderHistory(userId)          │
│  ReturnItem                       getDashboard(dateRange)          │
│                                                                    │
│  Database: PostgreSQL             Database: Redis, DynamoDB, ES    │
│  Schema: Normalized (ACID)        Schema: Denormalized per query   │
│  Optimized for: Integrity         Optimized for: Speed             │
└──────────────────────────────────────────────────────────────────┘
```

**The bridge:** When the write side changes data, it publishes an **event** ("OrderPlaced", "OrderCancelled"). The read side listens to these events and updates its own pre-built views.

---

### How It Works Step by Step

```
Step 1: Customer places an order
  POST /orders → CommandService → saves to PostgreSQL → publishes OrderPlacedEvent to Kafka

Step 2: Read side updates itself (asynchronously, ~100ms later)
  OrderPlacedEvent consumed by:
    → StatusProjectionHandler → writes OrderStatusView to Redis ("PENDING")
    → HistoryProjectionHandler → writes OrderHistoryView to DynamoDB
    → DashboardProjectionHandler → writes to Elasticsearch

Step 3: Customer checks order status (500× per order)
  GET /orders/123/status → QueryService → Redis lookup → <5ms response

Step 4: Customer asks "when will it arrive?" → still reads from Redis, not PostgreSQL
Step 5: Business runs nightly report → queries Elasticsearch, never touches orders DB
```

The write database (PostgreSQL) is never touched by read traffic. It can handle writes without contention from dashboard queries.

---

## Part 3 — Full Java Implementation

```java
// ════════════════════════════════════════════════════════════
// STEP 1 — Commands (what a user WANTS to do)
//          Commands are intentions: "I want to place this order"
// ════════════════════════════════════════════════════════════

// A "sealed interface" means only these specific types can be commands.
// The compiler will warn you if you forget to handle one.
public sealed interface OrderCommand permits
    PlaceOrderCommand, CancelOrderCommand, ReturnOrderCommand {}

public record PlaceOrderCommand(
    String orderId,
    String userId,
    List<OrderItem> items,
    Money total,
    PaymentMethod paymentMethod,
    Address shippingAddress
) implements OrderCommand {}

public record CancelOrderCommand(
    String orderId,
    String reason
) implements OrderCommand {}

// ════════════════════════════════════════════════════════════
// STEP 2 — Write Model (the domain aggregate)
//          This is the "chef's model" — complex business rules enforced here
//          It does NOT care about how data is displayed or queried
// ════════════════════════════════════════════════════════════

public class OrderAggregate {

    private String orderId;
    private String userId;
    private OrderStatus status;
    private List<OrderItem> items;
    private Money total;
    private int version; // used to detect concurrent modifications (optimistic locking)

    // Business rule: you can only place an order once
    public OrderPlacedEvent place(PlaceOrderCommand cmd) {
        if (this.status != null)
            throw new OrderAlreadyExistsException(cmd.orderId());

        this.status = OrderStatus.PENDING;
        this.version = 1;

        // Return an event — don't call other services, don't write to DB here
        // Just describe what happened: "an order was placed"
        return new OrderPlacedEvent(
            cmd.orderId(), cmd.userId(), cmd.items(), cmd.total(), Instant.now()
        );
    }

    // Business rule: can't cancel after shipping
    public OrderCancelledEvent cancel(CancelOrderCommand cmd) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED)
            throw new InvalidTransitionException("Cannot cancel after shipping");

        this.status = OrderStatus.CANCELLED;
        return new OrderCancelledEvent(orderId, cmd.reason(), Instant.now());
    }
}

// ════════════════════════════════════════════════════════════
// STEP 3 — Command Handler (the orchestrator for writes)
//          1. Load write model from DB
//          2. Apply business logic → get event
//          3. Save write model to DB
//          4. Publish event to Kafka (so read side can update)
// ════════════════════════════════════════════════════════════

@Service
public class OrderCommandService {

    private final OrderAggregateRepository writeRepo; // writes only to PostgreSQL
    private final EventBus eventBus;                  // publishes to Kafka

    public void handle(PlaceOrderCommand cmd) {
        OrderAggregate order = new OrderAggregate();
        OrderPlacedEvent event = order.place(cmd); // business logic runs here

        writeRepo.save(order);      // persist to the WRITE database (PostgreSQL)
        eventBus.publish(event);    // broadcast: "hey, an order was just placed"
        // Read projections will pick this event up and update themselves
    }

    public void handle(CancelOrderCommand cmd) {
        // Load the WRITE model (not a read projection)
        OrderAggregate order = writeRepo.findById(cmd.orderId())
            .orElseThrow(() -> new OrderNotFoundException(cmd.orderId()));

        OrderCancelledEvent event = order.cancel(cmd);
        writeRepo.save(order);
        eventBus.publish(event);
    }
}

// ════════════════════════════════════════════════════════════
// STEP 4 — Read Models (three completely different views)
//          Each view is shaped for exactly ONE query's needs.
//          No joins needed at query time — the view is pre-built.
// ════════════════════════════════════════════════════════════

// Read model 1: Order Status (stored in Redis)
// Used by: customer polling "where is my package?"
// Query pattern: single key lookup by orderId, needs <5ms
// Contains only what that query needs — not the full order
public record OrderStatusView(
    String orderId,
    String status,          // "PENDING", "SHIPPED", "DELIVERED"
    String trackingNumber,  // null until shipped
    Instant estimatedDelivery,
    Instant lastUpdated
) {}

// Read model 2: Order History (stored in DynamoDB)
// Used by: customer viewing their order list
// Query pattern: list by userId, sorted by date, paginated
public record OrderHistoryView(
    String orderId,
    String userId,        // DynamoDB partition key for fast user-scoped queries
    String status,
    Money total,
    int itemCount,        // pre-computed — no join needed
    Instant placedAt,
    String thumbnailUrl   // first item's image, pre-fetched at write time
) {}

// Read model 3: Dashboard View (stored in Elasticsearch)
// Used by: business analytics, "revenue by region today"
// Query pattern: aggregations, filters, date ranges
public record OrderDashboardView(
    String orderId,
    String status,
    Money revenue,
    String merchantId,
    String category,
    Instant placedAt,
    String region,
    String channel        // "mobile", "web", "api"
) {}

// ════════════════════════════════════════════════════════════
// STEP 5 — Projection Handlers (the read side listeners)
//          These listen to events and update the read views.
//          Think of them as "bookkeepers" — every time something
//          happens on the write side, they update their ledger.
// ════════════════════════════════════════════════════════════

@Component
public class OrderStatusProjectionHandler {

    private final RedisTemplate<String, OrderStatusView> redis;

    // Called when an order is placed → create the initial status entry
    @KafkaListener(topics = "order.placed")
    public void on(OrderPlacedEvent event) {
        OrderStatusView view = new OrderStatusView(
            event.orderId(),
            "PENDING",
            null,           // no tracking number yet
            null,           // no delivery estimate yet
            event.occurredAt()
        );
        // Store in Redis with 30-day TTL
        redis.opsForValue().set(
            "order:status:" + event.orderId(),
            view,
            Duration.ofDays(30)
        );
    }

    // Called when order ships → update tracking info
    @KafkaListener(topics = "order.shipped")
    public void on(OrderShippedEvent event) {
        String key = "order:status:" + event.orderId();
        OrderStatusView existing = redis.opsForValue().get(key);
        // Immutable record update pattern — create new with updated fields
        OrderStatusView updated = new OrderStatusView(
            existing.orderId(),
            "SHIPPED",
            event.trackingNumber(),
            event.estimatedDelivery(),
            event.occurredAt()
        );
        redis.opsForValue().set(key, updated, Duration.ofDays(30));
    }

    @KafkaListener(topics = "order.cancelled")
    public void on(OrderCancelledEvent event) {
        String key = "order:status:" + event.orderId();
        OrderStatusView existing = redis.opsForValue().get(key);
        OrderStatusView updated = new OrderStatusView(
            existing.orderId(), "CANCELLED", null, null, event.occurredAt()
        );
        // Shorter TTL — cancelled orders matter less
        redis.opsForValue().set(key, updated, Duration.ofDays(7));
    }
}

@Component
public class OrderHistoryProjectionHandler {

    private final DynamoDbEnhancedClient dynamoDb;

    @KafkaListener(topics = "order.placed")
    public void on(OrderPlacedEvent event) {
        OrderHistoryView view = new OrderHistoryView(
            event.orderId(),
            event.userId(),       // partition key for DynamoDB
            "PENDING",
            event.total(),
            event.items().size(), // pre-compute so query doesn't need to count
            event.occurredAt(),
            event.items().get(0).thumbnailUrl() // first item image
        );
        dynamoDb.table("order-history", OrderHistoryView.class).putItem(view);
    }

    @KafkaListener(topics = "order.cancelled")
    public void on(OrderCancelledEvent event) {
        // DynamoDB update expression: update status field only
        // PK = userId (lookup from saga state), SK = orderId
        dynamoDb.table("order-history", OrderHistoryView.class)
            .updateItem(
                UpdateItemEnhancedRequest.builder(OrderHistoryView.class)
                    .item(new OrderHistoryView(event.orderId(), /* ... */ "CANCELLED", /* ... */))
                    .conditionExpression(Expression.builder().expression("attribute_exists(orderId)").build())
                    .build()
            );
    }
}

// ════════════════════════════════════════════════════════════
// STEP 6 — Query Service (reads ONLY from read models)
//          This never touches the write database.
//          It just serves pre-built views.
// ════════════════════════════════════════════════════════════

@Service
public class OrderQueryService {

    private final RedisTemplate<String, OrderStatusView> redis;
    private final DynamoDbOrderHistoryRepo dynamoRepo;
    private final ElasticsearchOrderRepo esRepo;

    // Fast path: Redis lookup, <5ms
    public OrderStatusView getOrderStatus(String orderId) {
        OrderStatusView view = redis.opsForValue().get("order:status:" + orderId);
        if (view == null) throw new OrderNotFoundException(orderId);
        return view; // no DB join, no table scan — just a cache key lookup
    }

    // DynamoDB query by userId partition key, paginated
    public List<OrderHistoryView> getOrderHistory(String userId, PageRequest page) {
        return dynamoRepo.findByUserId(userId, page);
    }

    // Elasticsearch aggregation — never hits the write DB
    public OrderDashboardData getDashboard(DashboardQuery query) {
        return esRepo.aggregateDashboard(query);
    }
}
```

---

## Part 4 — The Full Flow, Visualised

```
Customer: "Place my order"
    │
    ▼
POST /orders  (HTTP)
    │
    ▼
OrderCommandService.handle(PlaceOrderCommand)
    │
    ├──► 1. Validate business rules (OrderAggregate)
    │
    ├──► 2. Save to PostgreSQL (write model — normalized, ACID)
    │
    └──► 3. Publish OrderPlacedEvent to Kafka
                    │
                    ├──► StatusProjectionHandler  → Redis ["order:status:123" = PENDING]
                    │
                    ├──► HistoryProjectionHandler → DynamoDB [user123 history row]
                    │
                    └──► DashboardProjectionHandler → Elasticsearch [dashboard doc]


Customer: "Where's my order?"  (called 500× per order placed)
    │
    ▼
GET /orders/123/status
    │
    ▼
OrderQueryService.getOrderStatus("123")
    │
    ▼
Redis.get("order:status:123")  →  {status: "PENDING", ...}   ← <5ms, zero DB load
```

---

## Part 5 — What "Eventual Consistency" Means for a Newbie

This is the biggest gotcha of CQRS. Understand it before your interview.

```
Timeline:
  T=0ms   Customer cancels order  → CancelOrderCommand handled
  T=1ms   Write DB updated (status = CANCELLED)
  T=2ms   OrderCancelledEvent published to Kafka
  T=100ms  StatusProjectionHandler receives event → Redis updated
  T=150ms  DashboardProjectionHandler receives event → ES updated

  At T=50ms, if the customer asks "what's my order status?"
  → Redis still says "PENDING"  ← this is the eventual consistency window!
  → 100ms later, it will correctly say "CANCELLED"
```

**Is this acceptable?**
- ✅ Yes for: displaying order status to customer, showing order history, running reports
- ❌ No for: payment processing (can't charge a cancelled order), inventory decisions

**Rule of thumb**: operations that *display* data can tolerate eventual consistency; operations that *act* on data must read from the write model.

---

## SOLID Analysis

| Principle | Satisfied? | Why |
|---|---|---|
| Single Responsibility | ✅ | Command service = writes only; Query service = reads only; each projection = one view |
| Open/Closed | ✅ | Add a new read view (e.g., ShippingDashboard) without touching the command side at all |
| Interface Segregation | ✅ | A mobile client only imports `OrderQueryService`; a checkout service only imports `OrderCommandService` |
| Dependency Inversion | ✅ | Both services depend on interfaces (`EventBus`, `OrderRepo`), not concrete implementations |

---

## When to Use vs When NOT to Use

| ✅ Use CQRS when... | ❌ Do NOT use when... |
|---|---|
| Read traffic is 100× write traffic | Simple CRUD app (todo list, blog) |
| Reads need different shapes per consumer | Your team is < 5 engineers |
| Write model has complex business rules | You need strong read consistency always |
| Analytics must not slow down transactional DB | You can't tolerate eventual consistency anywhere |
| You're already using event-driven architecture | You have one database and it's fine |

---

## Trade-offs Table

| What You Gain | What You Pay |
|---|---|
| Read queries are blazing fast (pre-built views) | Eventual consistency — reads may lag 100–500ms behind writes |
| Write DB is never hit by read traffic | Two codepaths, two databases, projection handlers to maintain |
| Scale reads and writes independently | Debugging is harder: event → handler → projection chain to trace |
| Add a new read view without touching write code | Rebuilding projections (replay) when you change a read model is slow and risky |

---

## Common Interview Questions

**Q: "What's the difference between CQRS and just having a read replica?"**
> A read replica gives you the same data model, just on a different server — you still do joins and queries on a normalized schema. CQRS gives you *completely different data shapes* per query: Redis for status (key-value), DynamoDB for history (document), Elasticsearch for analytics (inverted index). Each shape is optimal for one specific query pattern.

**Q: "How do you handle the case where a user cancels an order and immediately checks status?"**
> Accept the eventual consistency window (~100ms). Either show a loading state, or on the cancel API response return the new status directly from the write model (one-time strong read), then all subsequent reads can use the eventually consistent read model.

**Q: "How do you rebuild a projection if the read model schema changes?"**
> Replay all events from Kafka (or the event store if using Event Sourcing) into the new projection schema. This is called a "projection rebuild". It can take hours for large datasets — mitigate with blue/green projection strategy: build the new projection alongside the old one, then cut over.

---

## Related Patterns

| Pattern | Relationship |
|---|---|
| [Event Sourcing](27-event-sourcing.md) | The natural partner — events are the bridge between write and read; ES stores every event, CQRS uses them to build projections |
| [Repository](24-repository.md) | Write side uses a repository for its aggregate; read side uses separate read-only repositories |
| [Saga](26-saga.md) | Command handlers often trigger Sagas for multi-step workflows across services |
| [Domain Events](31-domain-events.md) | CQRS's event bus publishes Domain Events — the same events that trigger read model updates |
| [Outbox Pattern](28-outbox-pattern.md) | Guarantees events reach Kafka even if the service crashes between DB write and Kafka publish |
