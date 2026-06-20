# 05 — Payment Failure & Rollback

---

## Why Not 2PC (Two-Phase Commit)?

The booking confirmation spans multiple services: Booking Service (DB update), Payment Service (gateway call), Seat Lock Service (Redis + DB update), Notification Service.

**Two-Phase Commit fails here because**:
- The payment gateway (Razorpay/Stripe) is an external system that does not participate in a distributed transaction coordinator
- 2PC locks resources during the prepare phase — holding seat locks while waiting for payment gateway can extend lock duration from seconds to minutes (gateway can be slow)
- If the coordinator crashes during 2PC, all participants block indefinitely

**Decision: Saga Pattern with Compensating Transactions**

Each step has a forward action and a compensating action. If any step fails, all previously-completed steps are undone via compensating actions in reverse order.

---

## Saga for Booking Confirmation

### Forward Steps (Happy Path)

```
Step 1: Lock seats (Seat Lock Service)
  Forward:     Acquire Redis lock + DB UPDATE to LOCKED
  Compensate:  Release locks → status = AVAILABLE

Step 2: Transition to IN_PAYMENT (Seat Lock Service)
  Forward:     DB UPDATE status = IN_PAYMENT
  Compensate:  DB UPDATE status = LOCKED (or AVAILABLE if timeout)

Step 3: Create payment record (Payment Service)
  Forward:     INSERT payments (status=PENDING)
  Compensate:  UPDATE payments SET status='ABANDONED'

Step 4: Charge payment gateway (Payment Service)
  Forward:     POST /charges to gateway
  Compensate:  POST /refunds to gateway (if charge succeeded)

Step 5: Confirm booking (Booking Service)
  Forward:     UPDATE bookings SET status=CONFIRMED
               UPDATE show_seat_inventory SET status=BOOKED
               INSERT booking_outbox (BOOKING_CONFIRMED)
  Compensate:  UPDATE bookings SET status=FAILED
               UPDATE show_seat_inventory SET status=AVAILABLE
               INSERT booking_outbox (BOOKING_FAILED)

Step 6: Send notification (Notification Service)
  Forward:     Send email + SMS
  Compensate:  Send failure email (informational, not rollback)
```

### Saga Execution Engine

The Booking Service acts as the Saga orchestrator. It maintains saga state in the `bookings` table and drives each step via events:

```
Saga state stored in bookings.saga_state JSONB:
{
  "current_step": 4,
  "steps_completed": [1, 2, 3],
  "compensation_needed": false,
  "idempotency_keys": {
    "payment": "uuid-abc",
    "lock": "uuid-def"
  }
}
```

---

## Payment Failure Scenarios

### Scenario 1: Card Declined (Synchronous Failure)

```
Payment gateway responds with 402/422 immediately.

Timeline:
  T+0:   POST /charges → 402 {"reason": "insufficient_funds"}
  T+0:   Booking Service receives synchronous failure
  T+0:   Compensating step triggered: release seat locks
  T+0:   UPDATE show_seat_inventory SET status='AVAILABLE'
  T+0:   DEL seat_lock:{show_id}:* from Redis
  T+0:   HSET show:{show_id}:seat_layout (seats back to 'A')
  T+0:   PUBLISH seat-updates (seats available again)
  T+1s:  402 returned to user with error + can_retry=true
  T+1s:  User can re-select seats and try again (timer reset)

Idempotency: New booking_id required for retry (previous booking_id marked FAILED)
```

### Scenario 2: Payment Timeout (Gateway Unresponsive)

```
Gateway does not respond within 30 seconds.

Problem: Did the charge go through or not? We don't know.

Resolution strategy:
  T+30s: Timeout exception in Payment Service
  T+30s: GET /charges/{idempotency_key} — poll gateway for status
  T+35s: If gateway responds with captured: → proceed with confirmation (Step 5)
  T+35s: If gateway responds with not_found: → compensate (release locks)
  T+35s: If gateway still timeout: → enqueue for webhook reconciliation

Webhook reconciliation:
  - Payment gateway sends webhook on charge completion (async)
  - Payment Service has endpoint: POST /webhooks/payment-gateway
  - Webhook verified by HMAC signature (prevent spoofing)
  - On webhook: look up booking by gateway's order_id → continue saga
  - SLA: webhook delivery within 2 minutes
  - Fallback: batch reconciliation job every 5 minutes queries gateway API

Seat lock extension during uncertainty:
  - While saga is in "uncertain" state, extend lock TTL: EXPIRE seat_lock:...  +300 (5 more min)
  - Maximum extension: 20 minutes (then force release and notify user)
```

### Scenario 3: DB Failure After Payment Captured

```
Most dangerous: gateway charged the user but our DB write failed.

Timeline:
  T+0:  POST /charges → 200 {"payment_id": "pay_xyz", "status": "captured"}
  T+0:  Payment Service attempts DB transaction:
          UPDATE payments SET status='SUCCESS'
          UPDATE bookings SET status='CONFIRMED'
          UPDATE show_seat_inventory SET status='BOOKED'
          INSERT booking_outbox (BOOKING_CONFIRMED)
  T+0:  DB write fails (network partition, primary failover in progress)

Resolution (Outbox pattern):
  - Payment Service writes to outbox WITHIN the same DB transaction
  - If DB transaction fails: outbox was not written → no false event
  - On DB recovery (seconds later): payment status is still PENDING
  - Reconciliation job: query gateway for all PENDING payments older than 60s
  - Gateway confirms payment → DB write retried → saga continues

What if DB never recovers?
  - PENDING payments with confirmed gateway status → manual reconciliation
  - Alert fires: "Payment captured but booking not confirmed" → P1 incident
  - User is charged but has no ticket → priority manual refund + apology

Prevention:
  - RDS Multi-AZ: automatic failover in ~30 seconds
  - Application retries DB write with exponential backoff (3 attempts)
  - During RDS failover window: new writes queue in application memory (bounded, 60s)
```

### Scenario 4: Partial Seat Booking (Some Seats Fail)

```
User selects A1, A2, A3.
Lock service acquires Redis lock for all 3.
DB UPDATE: only A1 and A2 update successfully (A3 had a stale version).

This should NOT happen if the conditional UPDATE is atomic, but defensive handling:

If rows_updated < len(seat_ids):
  → Release ALL locks for this booking (A1 and A2 as well)
  → Return 409 Conflict to user
  → Never create a partial booking
  → User must re-select seats (A3 may now be available with fresh version)

Invariant: Booking is all-or-nothing at the seat level.
```

### Scenario 5: Duplicate Payment Request

```
Network timeout causes client to retry POST /bookings/{id}/pay.

If same booking_id + same idempotency_key:
  → Payment Service checks: SELECT * FROM payments WHERE idempotency_key = ?
  → If PENDING: return 202 (in progress, poll for status)
  → If SUCCESS: return 200 (already confirmed, idempotent)
  → If FAILED: return 402 (already failed, must create new booking)

Idempotency key format: booking_id + "-pay-" + attempt_number
  - Client must increment attempt_number on retry
  - This prevents re-using a failed payment's idempotency key accidentally
```

---

## Outbox Pattern

Ensures event publishing is atomic with DB state change. Without this, a service can update the DB and then crash before publishing the Kafka event — leaving other services unaware.

```sql
-- All in one DB transaction (Payment Service, Step 5):
BEGIN;

UPDATE payments SET status = 'SUCCESS', gateway_payment_id = 'pay_xyz'
WHERE id = ? AND idempotency_key = ?;

UPDATE bookings SET status = 'CONFIRMED', confirmed_at = now()
WHERE id = ? AND status = 'PENDING';

UPDATE show_seat_inventory
SET status = 'BOOKED', version = version + 1
WHERE seat_id IN (?) AND status = 'IN_PAYMENT' AND version = :current_version;

INSERT INTO booking_outbox (
  id, booking_id, event_type, payload, status, created_at
) VALUES (
  gen_random_uuid(),
  'booking_abc123',
  'BOOKING_CONFIRMED',
  '{"booking_id": "...", "seats": [...], "user_id": "..."}',
  'PENDING',
  now()
);

COMMIT;
```

**Outbox relay process** (runs continuously):
```
1. SELECT * FROM booking_outbox WHERE status = 'PENDING' ORDER BY created_at LIMIT 100 FOR UPDATE SKIP LOCKED
2. For each row: publish to Kafka topic 'booking-events'
3. On Kafka ACK: UPDATE booking_outbox SET status = 'PUBLISHED', published_at = now()
4. Retry failed publishes with exponential backoff
5. Dead-letter: after 5 retries, move to 'DEAD' status + alert
```

`SKIP LOCKED` allows multiple relay worker instances to run in parallel without competing.

---

## Rollback Decision Matrix

| Scenario | Charge Occurred? | Action |
|----------|-----------------|--------|
| Card declined | No | Release seats, return 402 |
| Insufficient funds | No | Release seats, return 402 |
| Gateway timeout, not charged | No | Release seats, return 504 |
| Gateway timeout, charged | Yes | Confirm booking, then reconcile |
| DB failure after charge | Yes | Retry DB write; manual refund if exhausted |
| DB failure before charge | No | Release seats (nothing to refund) |
| Duplicate payment | Depends | Idempotency check; return existing result |
| User cancels during payment | Depends | Void/refund if charged; release seats |
| Lock TTL expired mid-payment | Pending | Extend TTL if payment in-flight; else release |
