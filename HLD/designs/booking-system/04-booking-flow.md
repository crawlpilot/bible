# 04 — Booking Flow

---

## End-to-End Booking Sequence

```mermaid
sequenceDiagram
    participant U as User (Browser/App)
    participant WS as WebSocket Service
    participant AG as API Gateway
    participant SS as Seat Layout Service
    participant BS as Booking Service
    participant LS as Seat Lock Service
    participant PS as Payment Service
    participant Redis as Redis Cluster
    participant DB as PostgreSQL
    participant PGW as Payment Gateway (Razorpay)
    participant Kafka as Kafka
    participant NS as Notification Service

    Note over U,NS: Phase 1 — Browse & View Seats

    U->>AG: GET /shows/{show_id}/seats
    AG->>SS: GetSeatLayout(show_id)
    SS->>Redis: HGETALL show:{show_id}:seat_layout
    alt Cache hit
        Redis-->>SS: {seat_id → status} map (300 seats)
        SS-->>AG: SeatLayout{seats[], show_metadata}
    else Cache miss (first request or cold start)
        SS->>DB: SELECT * FROM show_seat_inventory WHERE show_id=?
        DB-->>SS: Seat rows with status
        SS->>Redis: HSET show:{show_id}:seat_layout ...
        SS-->>AG: SeatLayout{seats[], show_metadata}
    end
    AG-->>U: 200 {seat_layout, show_metadata}

    U->>WS: WS Connect /ws/shows/{show_id}/seats
    WS->>Redis: SUBSCRIBE seat-updates:{show_id}
    Note over WS,U: Connection open — real-time deltas pushed as seats are locked/booked

    Note over U,NS: Phase 2 — Seat Selection & Lock

    U->>AG: POST /bookings/initiate\n{show_id, seat_ids: [A1, A2], idempotency_key}
    AG->>BS: InitiateBooking(user_id, show_id, seat_ids)
    BS->>LS: AcquireSeatsLock(show_id, seat_ids, user_id, booking_id)

    loop For each seat_id in seat_ids
        LS->>Redis: SETNX seat_lock:{show_id}:{seat_id}\n{user_id, booking_id, expires: now+600}\nEX 600
        Redis-->>LS: 1 (acquired) or 0 (conflict)
    end

    alt All Redis locks acquired
        LS->>DB: UPDATE show_seat_inventory\nSET status='LOCKED', locked_by_user=?, lock_expires_at=now+10min, version=version+1\nWHERE show_id=? AND seat_id IN (?) AND status='AVAILABLE'
        DB-->>LS: rows_updated = 2 (matches seat_ids count)
        LS->>Redis: PUBLISH seat-updates:{show_id}\n{seats:[{A1,L},{A2,L}]}
        Redis-->>WS: Event received
        WS-->>U: Push seat status delta {A1: LOCKED, A2: LOCKED}
        LS-->>BS: LockAcquired{booking_id, expires_at}
        BS->>DB: INSERT bookings(id=booking_id, status='PENDING', ...)
        BS-->>AG: BookingCreated{booking_id, expires_at, total_amount}
        AG-->>U: 200 {booking_id, expires_in: 600, seats: [A1,A2], total: ₹500}
    else Conflict on any seat
        LS->>Redis: DEL seat_lock:{show_id}:{seat already acquired}
        LS-->>BS: SeatConflictError{conflicting_seats: [A1]}
        BS-->>AG: 409 Conflict
        AG-->>U: 409 {message: "Seats no longer available", conflict_seats: [A1]}
    else DB update count mismatch (race: Redis won but DB seat was taken)
        LS->>Redis: DEL all acquired seat_lock keys
        LS-->>BS: SeatConflictError
        BS-->>AG: 409 Conflict
    end

    Note over U,NS: Phase 3 — Payment

    U->>AG: POST /bookings/{booking_id}/pay\n{payment_method: "card", card_token}
    AG->>BS: ProcessPayment(booking_id, payment_method)
    BS->>DB: SELECT booking WHERE id=? AND status='PENDING' — verify lock not expired
    BS->>LS: TransitionToInPayment(show_id, seat_ids)
    LS->>DB: UPDATE show_seat_inventory SET status='IN_PAYMENT'\nWHERE seat_id IN (?) AND status='LOCKED' AND lock_expires_at > now()
    BS->>PS: InitiatePayment{booking_id, amount=500, idempotency_key, method}
    PS->>DB: INSERT payments(booking_id, status='PENDING', idempotency_key)
    PS->>PGW: POST /charges {amount, currency, token, idempotency_key}

    alt Payment Success
        PGW-->>PS: 200 {payment_id, status: "captured"}
        PS->>DB: BEGIN;\n  UPDATE payments SET status='SUCCESS', gateway_payment_id=?;\n  UPDATE bookings SET status='CONFIRMED', payment_id=?;\n  UPDATE show_seat_inventory SET status='BOOKED'\n    WHERE seat_id IN (?) AND version=:current_version;\n  INSERT booking_outbox(BOOKING_CONFIRMED, payload);\nCOMMIT;
        PS->>Redis: HSET show:{show_id}:seat_layout {A1:'B', A2:'B'}
        PS->>Redis: DEL seat_lock:{show_id}:A1, seat_lock:{show_id}:A2
        PS->>Redis: PUBLISH seat-updates:{show_id} {A1:BOOKED, A2:BOOKED}
        Redis-->>WS: Event
        WS-->>U: Push {A1: BOOKED, A2: BOOKED}
        Kafka->>NS: booking.confirmed{booking_id, user_email, seats, show_details}
        NS-->>U: Email confirmation + SMS
        PS-->>AG: PaymentSuccess{booking_id, ticket_id}
        AG-->>U: 200 {booking_confirmed, ticket_id, download_url}

    else Payment Failed (card declined, insufficient funds)
        PGW-->>PS: 402 {reason: "insufficient_funds"}
        PS->>DB: BEGIN;\n  UPDATE payments SET status='FAILED';\n  INSERT booking_outbox(PAYMENT_FAILED, payload);\nCOMMIT;
        PS->>Kafka: PUBLISH payment.failed{booking_id, reason}
        Kafka->>LS: payment.failed event
        LS->>DB: UPDATE show_seat_inventory SET status='AVAILABLE'\nWHERE seat_id IN (?) AND status='IN_PAYMENT'
        LS->>Redis: DEL seat_lock:{show_id}:A1, seat_lock:{show_id}:A2
        LS->>Redis: HSET show:{show_id}:seat_layout {A1:'A', A2:'A'}
        LS->>Redis: PUBLISH seat-updates:{show_id} {A1:AVAILABLE, A2:AVAILABLE}
        PS->>DB: UPDATE bookings SET status='FAILED'
        PS-->>AG: PaymentFailed{reason}
        AG-->>U: 402 {reason: "Payment declined", can_retry: true, retry_window_seconds: 300}

    else Payment Timeout (gateway unresponsive)
        Note over PS,PGW: No response after 30s
        PS->>PGW: GET /charges/{idempotency_key} — check if already processed
        alt Gateway confirms charge exists
            PGW-->>PS: 200 {status: "captured"}
            Note over PS: Treat as success, proceed with confirmation
        else Gateway confirms not charged
            PGW-->>PS: 404 Not found
            Note over PS: Treat as failed, release locks
        else Gateway still uncertain
            Note over PS: Enqueue for async reconciliation (webhook callback)
            Note over PS: Keep locks alive temporarily (extend TTL)
        end
    end
```

---

## In-Transit Seat Display

### Problem
When user A selects seats A1 and A2, other users viewing the seat layout should see them as "being selected" (amber/orange) — not as "available" (green) or "booked" (red). This prevents users from selecting seats that are likely unavailable.

### Implementation

**Seat status codes in Redis** (stored in `show:{show_id}:seat_layout` hash):

| Code | State | Display |
|------|-------|---------|
| `A` | AVAILABLE | Green |
| `L` | LOCKED / IN_PAYMENT | Amber (pulsing) |
| `B` | BOOKED | Red |
| `X` | BLOCKED | Grey |

**Real-time update path**:
```
Lock acquired → PUBLISH seat-updates:{show_id} → Redis pub/sub
                     ↓
             WebSocket Service (subscribed)
                     ↓
             Push delta event to all connected clients
                     ↓
             Client UI updates seat color from green → amber
```

**WebSocket event payload** (minimal delta, not full layout):
```json
{
  "show_id": "show_abc123",
  "timestamp": 1717632000,
  "seat_updates": [
    {"seat_id": "A1", "status": "L"},
    {"seat_id": "A2", "status": "L"}
  ]
}
```

**Reconnect / missed events handling**:
- Client disconnects and reconnects → fetch full layout via GET /shows/{id}/seats (cache hit)
- No event sourcing needed; layout is always authoritative in Redis/DB

### Lock Timer Display
- When the user who holds the lock is viewing checkout:
  - API response includes `expires_at` timestamp
  - Client shows countdown: "10:00 remaining to complete booking"
  - At T-60 seconds: offer "Extend session" (POST /bookings/{id}/extend-lock)
  - At expiry: redirect to seat selection, show "Your session expired"

---

## Seat Layout Rendering

### Static Layer (screen geometry — changes rarely)
```
Cached in CDN / S3:
  screen_layout:{screen_id} = {
    rows: [
      {label: "A", seats: [1..20], type: "STANDARD"},
      {label: "B", seats: [1..20], type: "STANDARD"},
      ...
      {label: "P", seats: [1..10], type: "RECLINER"}
    ],
    screen_position: {x, y, width}
  }
TTL: 24 hours (invalidated only on screen reconfiguration)
```

### Dynamic Layer (per-show seat availability — changes every second)
```
Redis Hash: show:{show_id}:seat_layout
  A1 → A
  A2 → L
  A3 → B
  ...
  P5 → A
TTL: None (perpetual; deleted when show completes)
```

### Client Rendering Flow
```
1. Load screen geometry from CDN (cached in browser for session)
2. Load seat availability from GET /shows/{id}/seats (Redis Hash)
3. Merge: render grid using geometry, color each seat by availability status
4. Open WebSocket for delta updates
5. On WebSocket event: patch only changed seats (O(delta) not O(layout))
```

---

## Booking Cancellation Flow

```
User: POST /bookings/{id}/cancel

Booking Service:
  1. Verify booking status = CONFIRMED and cancellation window is open
  2. BEGIN TRANSACTION
     UPDATE bookings SET status = 'CANCELLED'
     UPDATE show_seat_inventory SET status = 'CANCELLED' (transit state)
     INSERT booking_outbox (BOOKING_CANCELLED)
  3. COMMIT

Payment Service (on BOOKING_CANCELLED event):
  4. POST /refunds to payment gateway (idempotent, refund_id = booking_id)
  5. On refund confirmed:
     UPDATE payments SET status = 'REFUNDED'
     INSERT payment_outbox (REFUND_CONFIRMED)

Seat Lock Service (on REFUND_CONFIRMED event):
  6. UPDATE show_seat_inventory SET status = 'AVAILABLE'
     HSET show:{show_id}:seat_layout {seat_ids → 'A'}
     PUBLISH seat-updates:{show_id} {seats available again}

Notification Service:
  7. Send cancellation + refund confirmation email
```

**Cancellation policy**:
- > 24h before show: 100% refund
- 6–24h before show: 50% refund
- < 6h before show: no refund (seats still released for resale)
- Refund processing SLA: 5–7 business days (gateway policy)
