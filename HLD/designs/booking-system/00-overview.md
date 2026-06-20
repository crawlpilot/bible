# HLD: Movie Booking Platform (BookMyShow-scale)

> **Interview Mode**: Principal Engineer — RESHADED Framework  
> **Scope**: End-to-end design covering seat locking, no-double-booking guarantees, payment Saga, caching, and failure resilience at 75M MAU scale.

---

## Table of Contents

| File | Contents |
|------|----------|
| [00-overview.md](00-overview.md) | RESHADED walkthrough, requirements, constraints |
| [01-capacity-estimation.md](01-capacity-estimation.md) | Back-of-envelope: QPS, storage, bandwidth |
| [02-architecture.md](02-architecture.md) | Component diagram, data flow, service map |
| [03-seat-layout-locking.md](03-seat-layout-locking.md) | Seat state machine, Redis locking, no-double-booking |
| [04-booking-flow.md](04-booking-flow.md) | Full booking Saga, payment, rollback |
| [05-caching-strategy.md](05-caching-strategy.md) | Redis strategy, seat availability, layout invalidation |
| [06-data-models.md](06-data-models.md) | DB schema, indexes, partitioning |
| [07-api-contracts.md](07-api-contracts.md) | REST API definitions |
| [08-trade-offs.md](08-trade-offs.md) | Key architectural decisions and alternatives |
| [09-failure-modes.md](09-failure-modes.md) | Failure analysis, resilience patterns |

---

## R — Requirements

### Functional Requirements (in scope)

1. **Browse** movies, cinemas, shows by city/language/date
2. **View seat layout** for a show — real-time availability with locked/booked states visible
3. **Select and temporarily lock seats** (10-minute window)
4. **Complete payment** — confirm booking, send e-ticket
5. **Payment failure rollback** — release locks, seats go back to available
6. **Cancellation** — partial/full refunds within policy window
7. **Show search** — by movie name, venue, date, language, format (IMAX, 4DX)

### Non-Functional Requirements

| Property | Target |
|----------|--------|
| Seat lock acquisition | < 100ms p99 |
| Seat layout load | < 200ms p99 |
| No double-booking | Hard guarantee (zero tolerance) |
| Availability | 99.99% (< 52 min/year downtime) |
| Consistency | Strong for booking; eventual for browse/search |
| Peak throughput | 50K concurrent users during blockbuster release |
| Lock TTL | 10 minutes (configurable per show) |

### Out of Scope

- Loyalty/rewards engine
- Cinema operator dashboard
- Dynamic pricing ML model (price is set per show)
- Streaming/OTT content
- Food & beverage ordering

---

## E — Estimation

*See [01-capacity-estimation.md](01-capacity-estimation.md) for full breakdown.*

**Key numbers:**
- **75M MAU**, **3M bookings/day** (peak), **50K concurrent** during Avengers-scale releases
- **~3,500 QPS** booking writes at peak; **~500K QPS** seat layout reads
- Lock contention hot spot: single show can see **5K simultaneous seat selectors**

---

## S — Storage

*See [06-data-models.md](06-data-models.md) for schema.*

- **MySQL (InnoDB)** — ACID bookings, seat status, financial records
- **Redis Cluster** — seat locks, seat availability bitmap, session state
- **MongoDB** — movies, venues, rich metadata (flexible schema)
- **Elasticsearch** — full-text show/movie search
- **S3 + CloudFront** — seat layout JSONs, movie posters, static assets

---

## H — High-Level Design

*See [02-architecture.md](02-architecture.md) for component diagram.*

Core services:
1. **Show Service** — browse, search, seat layout view
2. **Booking Service** — seat lock + booking lifecycle (owns the Saga)
3. **Payment Service** — payment gateway integration, refund orchestration
4. **Notification Service** — email/SMS/push for confirmations
5. **Inventory Service** — seat state, lock management

---

## A — APIs

*See [07-api-contracts.md](07-api-contracts.md).*

Key flows:
- `GET /shows/{id}/seats` — seat layout with live availability
- `POST /bookings` — initiate booking, acquire seat locks
- `POST /bookings/{id}/pay` — trigger payment
- `DELETE /bookings/{id}` — cancel and release seats

---

## D — Detail Deep-Dive

### The Hard Problem: No Double-Booking

This is the crux of the interview. The solution requires **two-phase locking**:

1. **Phase 1 — Optimistic Redis Lock**: Atomic `SET seat:{showId}:{seatId} {userId} EX 600 NX`
2. **Phase 2 — Pessimistic DB Lock**: `UPDATE show_seats SET status='LOCKED' WHERE status='AVAILABLE'` with row-level lock

Both must succeed, or the reservation is rejected. See [03-seat-layout-locking.md](03-seat-layout-locking.md).

### The Hard Problem: Payment Failure Rollback

Booking spans multiple services (Inventory → Payment → Notification). Uses the **Saga Choreography** pattern with compensating transactions. See [04-booking-flow.md](04-booking-flow.md).

### The Hard Problem: Seat Layout Caching at Scale

Single show layout served 500K+ times. Redis Hash per show with per-seat field; invalidated atomically on lock acquisition. See [05-caching-strategy.md](05-caching-strategy.md).

---

## E — Evaluate

### Where This Design Wins

- **Zero double-booking**: Redis NX + DB CAS gives two independent enforcement layers
- **In-transit visibility**: Locked seats (Redis TTL active) shown as yellow to other users
- **Fast reads**: Seat layout served from Redis; DB never hit for availability reads
- **Graceful degradation**: If Redis fails, fall back to DB-only pessimistic lock (slower but correct)

### Bottlenecks

| Bottleneck | Mitigation |
|------------|-----------|
| Redis lock hot spot on popular show | Shard by show_id; Redis Cluster consistent hashing |
| MySQL write contention on show_seats | Row-level lock scoped to (show_id, seat_id); batch commits |
| Lock expiry sweep at TTL boundary | Background job every 30s; Kafka event for expired locks |
| Payment gateway latency | Async payment with webhook; user sees "processing" state |

---

## D — Distinctive Features (Differentiation for Interview)

1. **Seat Layout as Event Stream**: Instead of polling, push seat state changes via WebSocket/SSE — users see seats turning red/yellow in real-time
2. **Graduated Lock TTL**: First 2 minutes of a show going on sale → 5-min TTL to reduce lock squatting; normal hours → 10-min TTL
3. **Ghost Booking Prevention**: Idempotency key on `POST /bookings` prevents duplicate requests from creating two bookings
4. **Lock Refresh**: Mobile app heartbeats every 2 minutes to extend TTL if user is actively on payment page
5. **Overbooking Circuit Breaker**: If >90% seats locked simultaneously, flag show for monitoring — likely a bot attack

---

## Follow-Up Interviewer Questions

1. *"Your Redis is down. How do you ensure no double booking?"* → DB-only path with advisory lock or SELECT FOR UPDATE, with circuit breaker switching automatically
2. *"A user's lock expired at minute 10 but their payment succeeded at minute 11. What happens?"* → Idempotency check: if seat is re-locked by another user, trigger immediate refund; compensating transaction fires
3. *"How do you handle a show with 100K people trying to book 500 seats in the first second?"* → Rate limiting per show_id at API gateway, ticket queue (virtual waiting room), graduated release
