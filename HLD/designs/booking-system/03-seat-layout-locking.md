# Seat Layout, State Machine & Locking

> This is the most technically complex and most-questioned part of a booking system design. Be precise about the atomicity guarantees.

---

## Seat State Machine

Every seat in a show has exactly one state at any moment:

```
                    ┌─────────────────┐
                    │                 │
         ┌──────────▼──────────┐      │ lock expired (TTL)
         │     AVAILABLE       │      │ OR payment failed
         │   (default state)   │      │
         └──────────┬──────────┘      │
                    │                 │
              user selects            │
              seat(s)                 │
                    │                 │
         ┌──────────▼──────────┐      │
         │       LOCKED        ├──────┘
         │  (in-transit, TTL)  │
         └──────────┬──────────┘
                    │
              payment success
                    │
         ┌──────────▼──────────┐
         │       BOOKED        │
         │   (permanent)       │
         └──────────┬──────────┘
                    │
           cancellation within
              refund policy
                    │
         ┌──────────▼──────────┐
         │     AVAILABLE       │
         └─────────────────────┘
```

### State Visibility to Other Users

| State | Seat Color (UI) | Selectable? |
|-------|----------------|-------------|
| AVAILABLE | Green | Yes |
| LOCKED | Yellow / Striped | No — "being booked" tooltip |
| BOOKED | Red / Dark | No |

The yellow "in-transit" state is critical UX — it tells other users "someone is mid-checkout, don't wait on this seat."

---

## The Double-Booking Problem

### Why It's Hard

- **Race condition**: Two users select the same seat simultaneously
- **Distributed system**: Multiple Booking Service pods run concurrently
- **Cache inconsistency**: Redis may lag DB state by milliseconds
- **Retries**: Payment timeout causes retry → must not re-lock

The solution requires **atomic, idempotent lock acquisition** across both Redis and MySQL.

---

## Two-Phase Locking Protocol

### Phase 1: Redis Lock (Fast Path — < 5ms)

```
Command: SET seat:{show_id}:{seat_id} {user_id} EX 600 NX

NX = Only set if key does NOT exist (atomic check-and-set)
EX = Expire after 600 seconds (auto-release)
```

**Returns**:
- `OK` → Lock acquired for this user
- `nil` → Lock already held by another user → seat is LOCKED

**Why Redis first?**
- Redis `SET NX EX` is O(1) atomic — no race between check and set
- Single-threaded command processing eliminates concurrent write races
- Failure is instant and cheap — no DB contention

**Multi-seat atomic lock (Lua script)**:

```lua
-- Atomically lock N seats or lock none (all-or-nothing)
local keys = KEYS        -- seat:{show}:A1, seat:{show}:A2, ...
local user_id = ARGV[1]
local ttl = tonumber(ARGV[2])

for i = 1, #keys do
    if redis.call('EXISTS', keys[i]) == 1 then
        -- At least one seat already locked, roll back all acquired locks
        for j = 1, i - 1 do
            redis.call('DEL', keys[j])
        end
        return 0  -- failure
    end
end

-- All available — lock them all
for i = 1, #keys do
    redis.call('SET', keys[i], user_id, 'EX', ttl)
end
return 1  -- success
```

> **Critical**: The Lua script runs atomically in Redis. No other command executes between the EXISTS checks and the SETs. This is how we prevent A1+A2 from being split across two users.

### Phase 2: DB Confirmation (Durability — < 20ms)

Even if Redis is the fast-path gate, **MySQL is the source of truth**. Redis can fail, flush, or lose data on restart.

```sql
-- Compare-and-swap: only update if currently AVAILABLE
UPDATE show_seats
SET 
    status = 'LOCKED',
    locked_by_user_id = ?,
    lock_expires_at = DATE_ADD(NOW(), INTERVAL 600 SECOND),
    booking_id = ?
WHERE 
    show_id = ?
    AND seat_id = ?
    AND status = 'AVAILABLE';    -- ← This is the guard

-- Check affected rows:
-- 1 row updated = success
-- 0 rows updated = seat was already locked/booked by another transaction
```

**Why `WHERE status = 'AVAILABLE'` and not `SELECT FOR UPDATE`?**

`SELECT FOR UPDATE` would acquire a shared lock and block other readers. Our approach:
- The `WHERE status = 'AVAILABLE'` CAS (Compare-And-Swap) is a **lost update prevention** pattern
- If two concurrent transactions try to update the same seat, MySQL InnoDB row-level lock serializes them at the row level
- First writer wins (1 row affected), second writer fails (0 rows affected)
- No read blocking, only write contention

### Combined Protocol

```
acquire_seat_lock(show_id, seat_ids, user_id, booking_id):
  
  Step 1: Execute Lua script on Redis
    result = redis.eval(ATOMIC_LOCK_SCRIPT, seat_ids, user_id, TTL=600)
    if result == 0:
      return SEAT_UNAVAILABLE   # Fast fail, no DB hit

  Step 2: Confirm in MySQL (within a transaction)
    BEGIN;
    for each seat_id:
      rows_affected = execute(
        "UPDATE show_seats SET status=LOCKED ... WHERE status=AVAILABLE"
      )
      if rows_affected == 0:
        ROLLBACK;
        release_redis_locks(seat_ids)  # compensate Redis
        return SEAT_UNAVAILABLE
    COMMIT;

  Step 3: Update Redis layout cache
    HSET layout:{show_id} {seat_id} LOCKED  [for each seat]

  return SUCCESS
```

**What if Step 2 fails after Step 1 succeeds?**
- Redis has the lock (seat shows as yellow to others)
- MySQL has seat as AVAILABLE
- Lock Expiry Sweeper catches this at next 30s run, or Redis TTL self-heals
- In practice: Booking Service rolls back Redis immediately in the failure path

---

## Seat Layout Structure

### Screen Layout Config (stored in S3 + MongoDB)

```json
{
  "screen_id": "SCR_001",
  "venue_id": "VEN_PVR_MUMBAI",
  "name": "Screen 4 - IMAX",
  "total_seats": 350,
  "sections": [
    {
      "name": "PREMIUM",
      "rows": ["A", "B", "C"],
      "seats_per_row": 20,
      "price_multiplier": 2.0
    },
    {
      "name": "GOLD",
      "rows": ["D", "E", "F", "G", "H"],
      "seats_per_row": 30,
      "price_multiplier": 1.5
    },
    {
      "name": "SILVER",
      "rows": ["I", "J", "K", "L", "M", "N", "O"],
      "seats_per_row": 30,
      "price_multiplier": 1.0
    }
  ],
  "special_seats": [
    {"seat_id": "A10", "type": "COUPLE", "blocks_adjacent": ["A11"]},
    {"seat_id": "M1", "type": "WHEELCHAIR", "aisle_access": true}
  ]
}
```

### Show Seat Availability (per-show runtime state in Redis)

```
Redis Hash: layout:{show_id}
Fields: seat_id → status

HSET layout:SHOW_001 A1 AVAILABLE A2 AVAILABLE ... A20 AVAILABLE
           layout:SHOW_001 B1 BOOKED B2 BOOKED ...
           layout:SHOW_001 C5 LOCKED C6 LOCKED ...

HGETALL layout:SHOW_001  → returns all 350 fields in one command
```

This single `HGETALL` call returns the complete seat map for rendering — **no N+1 queries**.

### Seat Layout API Response

```json
{
  "show_id": "SHOW_001",
  "movie": "Avengers: Endgame",
  "screen": "Screen 4 - IMAX",
  "starts_at": "2025-04-26T19:00:00+05:30",
  "base_price": 200,
  "layout": {
    "sections": [
      {
        "name": "PREMIUM",
        "price": 400,
        "rows": [
          {
            "row": "A",
            "seats": [
              {"id": "A1", "number": 1, "status": "AVAILABLE"},
              {"id": "A2", "number": 2, "status": "LOCKED"},
              {"id": "A3", "number": 3, "status": "BOOKED"},
              {"id": "A4", "number": 4, "status": "AVAILABLE"}
            ]
          }
        ]
      }
    ]
  },
  "last_updated": "2025-04-26T10:15:30Z"
}
```

---

## Lock Expiry and Cleanup

### Happy Path: User Completes Payment

```
Payment confirmed →
  Redis: DEL seat:{show}:{seat_id}  (for each seat)
  Redis: HSET layout:{show_id} {seat_id} BOOKED  (for each seat)
  MySQL: UPDATE show_seats SET status=BOOKED
```

### Unhappy Path: User Abandons / Payment Fails

**TTL Auto-Expiry (primary mechanism)**:
- Redis key expires after 600 seconds automatically
- Seat re-appears as AVAILABLE on next layout fetch (Redis HSET updated by sweeper)

**Active Sweeper (secondary mechanism)**:
```sql
-- Runs every 30 seconds
UPDATE show_seats
SET status = 'AVAILABLE', locked_by_user_id = NULL, lock_expires_at = NULL
WHERE status = 'LOCKED' AND lock_expires_at < NOW();

-- For each row updated:
-- 1. Publish Kafka event: lock.expired {show_id, seat_id}
-- 2. Inventory Service: HDEL layout:{show_id} {seat_id} or HSET status=AVAILABLE
```

**Why both TTL and sweeper?**
- Redis TTL handles 99.9% of cases automatically
- Sweeper ensures MySQL and Redis stay in sync after Redis restarts or node failover events (where data was in-memory and lost)

### Lock Refresh (Heartbeat Extension)

If user is actively on the payment page, mobile/web client heartbeats every 2 minutes:

```
POST /bookings/{booking_id}/extend-lock

Server:
  EXPIRE seat:{show}:{seat_id} 600   # Reset TTL to full 10 minutes
  UPDATE show_seats SET lock_expires_at = DATE_ADD(NOW(), INTERVAL 600 SECOND)
```

Maximum extensions: 2 (so maximum total hold time = 30 minutes). After that, the booking is forcibly expired.

---

## Anti-Patterns to Avoid

| Anti-pattern | Problem | Our solution |
|---|---|---|
| `GET` then `SET` in Redis | Race condition between check and set | Atomic `SET NX` |
| `SELECT FOR UPDATE` on all reads | Blocks readers, kills read throughput | CAS `UPDATE WHERE status=AVAILABLE` |
| Single DB row for show-level seat count | Contention on the counter | Per-seat rows with independent row locks |
| Trust Redis as sole truth | Redis can lose data on failover | MySQL is the durable source of truth |
| Lock all seats in serial loops | Partial lock state if mid-loop failure | Lua script: all-or-nothing atomic lock |
