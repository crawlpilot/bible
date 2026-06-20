# 26. Saga Pattern
**Category**: Modern / Enterprise  
**GoF**: No (Garcia-Molina & Salem, 1987; microservices context: Richardson 2018)  
**Complexity**: High  
**Frequency in FAANG interviews**: Common

---

## The One-Line Summary

> **When a business action spans multiple services and one step fails, automatically undo the completed steps.** A Saga is a sequence of steps with a built-in undo plan for each step.

---

## Part 1 — The Problem (Read This First)

### The Bank Transfer Analogy

You want to transfer $500 from Bank A to Bank B. Two operations:
1. Debit $500 from Bank A
2. Credit $500 to Bank B

What if step 1 succeeds but step 2 fails (Bank B's server is down)?

```
Without a Saga:
  Step 1: $500 debited from Bank A  ✅
  Step 2: Credit to Bank B  ❌ (server down)
  Result: $500 disappears from the world. Customer is furious.

With a Saga:
  Step 1: $500 debited from Bank A  ✅
  Step 2: Credit to Bank B  ❌ (server down)
  Compensating action: Reverse the debit → put $500 back in Bank A
  Result: Nothing changed. Retry later.
```

The "compensating action" is the undo step. A Saga defines both the forward steps AND the undo steps upfront.

---

### Why Not Use a Database Transaction?

In a monolith with one database, you use a single ACID transaction:

```java
// Single database — this is fine
@Transactional  // one atomic unit: all or nothing
public void placeOrder(Order order) {
    inventoryRepo.reserve(order.items());  // same DB
    paymentRepo.charge(order.payment());   // same DB
    shippingRepo.schedule(order);          // same DB
    // If anything throws, the transaction rolls back automatically
}
```

In a microservices world, **each service owns its own database**. There is no shared transaction across services:

```
OrderService    → PostgreSQL (orders DB)
InventoryService → MySQL (inventory DB)
PaymentService  → Oracle (payments DB)
ShippingService → MongoDB (shipping DB)

You CANNOT do @Transactional across these four databases.
There is no rollback button that works across service boundaries.
```

**Distributed transactions (2PC)** do exist but they are:
- ❌ A single point of failure (the transaction coordinator)
- ❌ Block resources across services during the transaction window
- ❌ Not supported by most cloud services (DynamoDB, SQS, S3 don't participate in 2PC)
- ❌ Catastrophically slow at scale

**Saga is the solution**: instead of one atomic transaction, use a sequence of local transactions. Each step does its own commit. If a later step fails, run compensating transactions to undo the earlier ones.

---

### The Order Placement Scenario

```
Customer places an order. Four services must participate:

Step 1: Reserve inventory    (InventoryService)
Step 2: Charge payment       (PaymentService)
Step 3: Schedule shipment    (ShippingService)
Step 4: Send confirmation    (NotificationService)

What if Step 3 (shipping) fails?
  → Step 2 must be undone: refund the payment
  → Step 1 must be undone: release the inventory reservation
  → Step 4: not reached yet, nothing to undo

The Saga defines:
  Forward:      reserve → charge → ship → notify
  Compensation: undo-ship → refund → release
```

---

## Part 2 — Two Flavours of Saga

### Flavour 1: Orchestration (Central Conductor)

One "conductor" service tells each participant what to do and handles failures.

```
  OrderSagaOrchestrator (the conductor)
  ┌─────────────────────────────────────────────────────────┐
  │                                                          │
  │  1. → InventoryService: "reserve items X,Y,Z"           │
  │  2. → PaymentService:   "charge $99.99"                 │
  │  3. → ShippingService:  "schedule delivery"             │
  │  4. → NotificationService: "send confirmation email"    │
  │                                                          │
  │  If step 3 fails:                                       │
  │  C2. → PaymentService:   "refund $99.99"               │
  │  C1. → InventoryService: "release reservation"          │
  └─────────────────────────────────────────────────────────┘
```

**Pros**: Easy to read, central audit trail, clear saga flow  
**Cons**: Orchestrator can become a bottleneck, a single point of failure

---

### Flavour 2: Choreography (Reactive Events)

No conductor. Each service reacts to events and publishes the next one.

```
OrderService          InventoryService         PaymentService           ShippingService
    │                       │                       │                        │
    │── OrderPlaced ────────►│                       │                        │
    │                        │── StockReserved ──────►│                       │
    │                        │                       │── PaymentCharged ─────►│
    │                        │                       │                        │── ShipmentScheduled
    │                        │                       │                        │
    │          If payment fails:                      │                        │
    │                        │◄── CompensateStock ────│                        │
    │                        │                       │                        │
    │◄── OrderFailed ─────────────────────────────────┘                        │
```

**Pros**: Services are loosely coupled — each only knows about events, not other services  
**Cons**: Hard to see the overall flow ("where is this saga right now?"); harder to debug

---

## Part 3 — Full Java Implementation

### Orchestration Saga (recommended for most systems)

```java
// ════════════════════════════════════════════════════════════
// STEP 1 — Saga State (persisted to DB for durability)
//
// This is critical: if the service crashes mid-saga, we must
// be able to resume or compensate from where we left off.
// Without persisted state, a crash loses the saga forever.
// ════════════════════════════════════════════════════════════

public enum SagaStatus {
    STARTED,            // just started
    INVENTORY_RESERVED, // step 1 done
    PAYMENT_CHARGED,    // step 2 done
    SHIPMENT_SCHEDULED, // step 3 done
    COMPLETED,          // all steps done, happy path
    COMPENSATING,       // something failed, rolling back
    FAILED              // compensation complete, saga failed
}

@Entity
@Table(name = "order_saga_state")
public class OrderSagaState {

    @Id
    private String sagaId;           // unique ID for this saga instance

    private String orderId;
    private SagaStatus status;

    // These IDs are persisted so compensation can reference them
    private String reservationId;       // needed to release inventory
    private String paymentTransactionId; // needed to refund
    private String shipmentId;

    private Instant startedAt;
    private String failureReason;

    @Version                          // optimistic locking: prevents two threads
    private int version;              // from running the same saga simultaneously

    // Getters, setters, constructor...
}

// ════════════════════════════════════════════════════════════
// STEP 2 — The Orchestrator
//
// This is the "state machine": it advances through steps
// and triggers compensation on failure.
// ════════════════════════════════════════════════════════════

@Service
public class OrderPlacementSaga {

    private final InventoryServiceClient inventoryClient;
    private final PaymentServiceClient paymentClient;
    private final ShippingServiceClient shippingClient;
    private final NotificationServiceClient notificationClient;
    private final OrderSagaStateRepository sagaRepo;

    @Transactional
    public void execute(Order order) {

        // Always persist saga state first — this is your crash recovery point
        OrderSagaState state = new OrderSagaState(
            UUID.randomUUID().toString(),
            order.id(),
            SagaStatus.STARTED
        );
        sagaRepo.save(state);

        try {
            // ── Step 1: Reserve inventory ──────────────────────────────────
            // orderId is the idempotency key: if this call is retried,
            // the inventory service will return the same reservationId
            String reservationId = inventoryClient.reserve(order.items(), order.id());
            state.setReservationId(reservationId);
            state.setStatus(SagaStatus.INVENTORY_RESERVED);
            sagaRepo.save(state); // save after EACH step — crash recovery checkpoint

            // ── Step 2: Charge payment ─────────────────────────────────────
            String transactionId = paymentClient.charge(
                order.total(), order.paymentMethod(), order.id() // idempotency key
            );
            state.setPaymentTransactionId(transactionId);
            state.setStatus(SagaStatus.PAYMENT_CHARGED);
            sagaRepo.save(state);

            // ── Step 3: Schedule shipment ──────────────────────────────────
            String shipmentId = shippingClient.schedule(order, order.shippingAddress());
            state.setShipmentId(shipmentId);
            state.setStatus(SagaStatus.SHIPMENT_SCHEDULED);
            sagaRepo.save(state);

            // ── Step 4: Send confirmation (best-effort) ────────────────────
            // Notification is NOT compensatable — you can't "unsend" an email.
            // So we do it last, and if it fails, we accept that (the order is placed).
            notificationClient.sendConfirmation(order);
            state.setStatus(SagaStatus.COMPLETED);
            sagaRepo.save(state);

        } catch (InventoryOutOfStockException e) {
            // Step 1 failed — nothing was reserved, nothing to undo
            state.setStatus(SagaStatus.FAILED);
            state.setFailureReason("Out of stock: " + e.getMessage());
            sagaRepo.save(state);
            throw new OrderFailedException("Item out of stock", e);

        } catch (PaymentDeclinedException | PaymentServiceException e) {
            // Step 2 failed — inventory was reserved, must release it
            state.setStatus(SagaStatus.COMPENSATING);
            sagaRepo.save(state);

            compensateStep1_releaseInventory(state);

            state.setStatus(SagaStatus.FAILED);
            state.setFailureReason("Payment failed: " + e.getMessage());
            sagaRepo.save(state);
            throw new OrderFailedException("Payment failed", e);

        } catch (ShippingUnavailableException e) {
            // Step 3 failed — inventory reserved AND payment charged, must undo both
            state.setStatus(SagaStatus.COMPENSATING);
            sagaRepo.save(state);

            compensateStep2_refundPayment(state);  // refund first (reverse order)
            compensateStep1_releaseInventory(state); // then release inventory

            state.setStatus(SagaStatus.FAILED);
            state.setFailureReason("Shipping unavailable: " + e.getMessage());
            sagaRepo.save(state);
            throw new OrderFailedException("Shipping unavailable", e);
        }
    }

    // ── Compensating Transactions ──────────────────────────────────────────

    private void compensateStep1_releaseInventory(OrderSagaState state) {
        if (state.getReservationId() == null) return; // nothing was reserved

        try {
            inventoryClient.releaseReservation(state.getReservationId());
        } catch (Exception e) {
            // Compensation itself failed! This requires human intervention.
            // Log loudly, send to dead-letter queue, alert on-call engineer.
            log.error("⚠️ SAGA COMPENSATION FAILED: could not release inventory. " +
                      "sagaId={}, reservationId={}", state.getSagaId(), state.getReservationId(), e);
            alertingService.sendCriticalAlert("Manual inventory release needed: " + state.getReservationId());
            // Don't re-throw — mark saga as FAILED and continue
        }
    }

    private void compensateStep2_refundPayment(OrderSagaState state) {
        if (state.getPaymentTransactionId() == null) return;

        try {
            paymentClient.refund(state.getPaymentTransactionId());
        } catch (Exception e) {
            log.error("⚠️ SAGA COMPENSATION FAILED: could not refund payment. " +
                      "sagaId={}, txId={}", state.getSagaId(), state.getPaymentTransactionId(), e);
            alertingService.sendCriticalAlert("Manual refund needed: " + state.getPaymentTransactionId());
        }
    }
}

// ════════════════════════════════════════════════════════════
// STEP 3 — Idempotency (THE most important concept for Sagas)
//
// Every saga step MUST be safe to call multiple times.
// Why? Network failures cause retries. If "charge payment" is
// retried after a partial success, the customer could be
// charged twice. Idempotency keys prevent this.
// ════════════════════════════════════════════════════════════

@Service
public class PaymentServiceImpl {

    private final PaymentTransactionRepository txRepo;
    private final PaymentGateway gateway;

    public String charge(Money amount, PaymentMethod method, String idempotencyKey) {
        // The idempotency key is the orderId — globally unique per order

        // Check: was this payment already processed? (e.g., this is a retry)
        Optional<PaymentTransaction> existing = txRepo.findByIdempotencyKey(idempotencyKey);
        if (existing.isPresent()) {
            // Don't charge again — return the result from the first attempt
            return existing.get().transactionId();
        }

        // First time: actually charge
        PaymentTransaction tx = gateway.charge(amount, method);
        tx.setIdempotencyKey(idempotencyKey); // store the key to detect future retries
        txRepo.save(tx);
        return tx.transactionId();
    }
}

// ════════════════════════════════════════════════════════════
// STEP 4 — Choreography Saga (alternative approach)
//
// No central orchestrator. Each service:
//   1. Listens for the previous step's "success" event
//   2. Does its work
//   3. Publishes either a "success" event (forward) or
//      a "failure" event (triggers compensation upstream)
// ════════════════════════════════════════════════════════════

// InventoryService listens for OrderPlaced and StockReservationFailed events
@Component
public class InventoryChoreographyHandler {

    private final InventoryService inventoryService;
    private final EventBus eventBus;

    // Forward step: order placed → reserve stock
    @KafkaListener(topics = "order.placed")
    public void on(OrderPlacedEvent event) {
        try {
            String reservationId = inventoryService.reserve(event.items(), event.orderId());
            // Success: signal next step (payment)
            eventBus.publish(new StockReservedEvent(event.orderId(), reservationId));
        } catch (OutOfStockException e) {
            // Failure: signal that the whole saga should fail
            eventBus.publish(new StockReservationFailedEvent(event.orderId(), e.getMessage()));
        }
    }

    // Compensating step: payment failed → release the reservation we made
    @KafkaListener(topics = "payment.failed")
    public void on(PaymentFailedEvent event) {
        String reservationId = reservationRepo.findByOrderId(event.orderId());
        if (reservationId != null) {
            inventoryService.release(reservationId);
            eventBus.publish(new StockReleasedEvent(event.orderId()));
        }
    }
}

// PaymentService listens for StockReserved event
@Component
public class PaymentChoreographyHandler {

    private final PaymentService paymentService;
    private final OrderRepository orderRepo;
    private final EventBus eventBus;

    @KafkaListener(topics = "stock.reserved")
    public void on(StockReservedEvent event) {
        Order order = orderRepo.findById(event.orderId());
        try {
            String txId = paymentService.charge(order.total(), order.paymentMethod(), order.id());
            eventBus.publish(new PaymentChargedEvent(event.orderId(), txId));
        } catch (PaymentDeclinedException e) {
            // Tell the world payment failed — inventory service will compensate
            eventBus.publish(new PaymentFailedEvent(event.orderId(), e.getMessage()));
        }
    }
}
```

---

## Part 4 — Crash Recovery: Why Persisted State Matters

```
What happens if the saga service crashes mid-execution?

Without persisted state:
  Step 1 done ✅ (inventory reserved)
  Step 2 done ✅ (payment charged)
  Service CRASHES during step 3
  → Nobody knows steps 1 and 2 happened
  → Customer was charged, inventory is still reserved
  → Order never completes
  → Manual cleanup needed by engineers

With persisted saga state:
  Step 1 done ✅ → state saved: {status=INVENTORY_RESERVED, reservationId=R1}
  Step 2 done ✅ → state saved: {status=PAYMENT_CHARGED, txId=TX1}
  Service CRASHES
  Service restarts → finds all sagas in INVENTORY_RESERVED or PAYMENT_CHARGED state
  → Resumes step 3, or if too many retries, triggers compensation automatically
```

A startup recovery job handles stuck sagas:

```java
@Component
public class SagaRecoveryJob {

    private final OrderSagaStateRepository sagaRepo;
    private final OrderPlacementSaga saga;

    @Scheduled(fixedDelay = 60_000) // run every minute
    public void recoverStuckSagas() {
        // Find sagas that started but didn't complete (might be crashed)
        Instant stuckThreshold = Instant.now().minus(Duration.ofMinutes(5));
        List<OrderSagaState> stuckSagas = sagaRepo.findByStatusInAndStartedAtBefore(
            List.of(SagaStatus.STARTED, SagaStatus.INVENTORY_RESERVED, SagaStatus.PAYMENT_CHARGED),
            stuckThreshold
        );

        for (OrderSagaState state : stuckSagas) {
            if (state.getRetryCount() >= 3) {
                // Give up — trigger compensation
                saga.compensateFromState(state);
            } else {
                // Try to resume
                saga.resumeFromState(state);
                state.incrementRetryCount();
                sagaRepo.save(state);
            }
        }
    }
}
```

---

## Part 5 — Orchestration vs Choreography Decision Guide

```
                     Should I use Orchestration or Choreography?

                  Do you need to see the full flow in one place?
                                   │
               YES ────────────────┴──────────────── NO
                │                                     │
        Orchestration                         Choreography
        (use this if...)                      (use this if...)
        
        - Steps > 3                           - Steps ≤ 3
        - Complex compensation logic          - Services are truly independent
        - Need audit trail in one table       - Teams own separate services
        - New engineers need to understand    - You have good distributed tracing
          the flow easily                     - Low coupling is more important
                                               than visibility
```

---

## Part 6 — What Can Go Wrong (and How to Handle It)

```
Scenario 1: Compensation itself fails
  Saga: payment charged ✅ → shipping failed ❌ → refund fails ❌
  Solution: send to dead-letter queue, alert on-call, manual refund by support team

Scenario 2: Event delivered twice (Kafka at-least-once delivery)
  StockReservedEvent fired twice → inventory service tries to reserve twice
  Solution: idempotency key! Second reserve call returns first reservation's ID

Scenario 3: Service is slow, saga thinks it failed
  Shipping takes 10s, saga timeout is 5s → marks as failed, triggers compensation
  But shipping actually succeeded → inventory released AND shipment scheduled
  Solution: timeouts should be generous; use a reconciliation job to detect phantom compensations

Scenario 4: Partial step (DB write succeeds but Kafka publish fails)
  PaymentService: payment charged to bank ✅, but PaymentChargedEvent not published ❌
  Saga doesn't know payment succeeded → might retry → double charge
  Solution: Outbox Pattern (see 28-outbox-pattern.md) — write event to DB in same transaction,
            then a separate poller publishes it to Kafka
```

---

## SOLID Analysis

| Principle | Satisfied? | Why |
|---|---|---|
| Single Responsibility | ✅ | Orchestrator manages only saga flow; each service handles only its own business logic |
| Open/Closed | ✅ | Add a "loyalty points" step without modifying existing steps |
| Interface Segregation | ✅ | Each service client has a focused interface (charge, refund, reserve, release) |
| Dependency Inversion | ✅ | Orchestrator depends on service client interfaces, not concrete HTTP clients |

---

## When to Use vs When NOT to Use

| ✅ Use Saga when... | ❌ Do NOT use when... |
|---|---|
| A business action spans ≥ 2 microservices | Everything is in one service with one DB |
| Each service owns its own database | 2PC is available and performance allows it |
| Steps can be made idempotent | Compensation is impossible for most steps |
| You can tolerate temporary intermediate states | Strict isolation (ACID) is required for all reads |

---

## Trade-offs Table

| What You Gain | What You Pay |
|---|---|
| No distributed transaction — each service is independent | Compensating transactions are complex; must handle partial failures in compensation |
| Horizontally scalable — each service scales independently | Temporary inconsistency visible (stock reserved but order not confirmed) |
| Orchestration: clear, auditable flow in one place | Choreography: very hard to trace flow across services |
| Choreography: services don't know about each other | Orchestration: coordinator is a bottleneck and potential single point of failure |

---

## The Key FAANG Interview Answer

> "For order placement across inventory, payment, and shipping services, I'd use an **orchestration saga** with a durable saga state table.
>
> Three critical design decisions:
> 1. **Persist saga state before each step** — if the service crashes, a recovery job can resume or compensate from the last checkpoint.
> 2. **Every step must be idempotent** — use orderId as the idempotency key so retries are safe and don't double-charge.
> 3. **Compensation must be best-effort with escalation** — if a refund fails, we can't retry infinitely; send to a dead-letter queue and alert support.
>
> The key trade-off is that saga intermediate states are **visible** — there's a window where inventory is reserved but the order isn't confirmed. This is ACI (Atomicity+Consistency+Isolation... no Isolation) — other services can see the partial state. For order placement this is acceptable; for financial reconciliation it may not be."

---

## Related Patterns

| Pattern | Relationship |
|---|---|
| [Outbox Pattern](28-outbox-pattern.md) | Saga event publication should use the Outbox — guarantees events reach Kafka even on crash |
| [CQRS](25-cqrs.md) | CQRS command handlers often trigger Sagas; Saga state changes publish events that update CQRS read models |
| [Event Sourcing](27-event-sourcing.md) | Saga state can be stored as an event stream instead of status fields |
| [Circuit Breaker](29-circuit-breaker.md) | Each saga step's external call should be wrapped in a circuit breaker to fail fast |
| [Retry + Backoff](34-retry-backoff.md) | Transient failures in saga steps should trigger retry with exponential backoff |
