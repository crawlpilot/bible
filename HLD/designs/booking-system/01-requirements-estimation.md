# 01 — Requirements & Capacity Estimation

---

## Functional Requirements

### Core (Must Have)
- Browse movies by city, date, language, genre
- View available shows for a selected movie
- View seat layout for a show with real-time availability status
- Select seats — temporarily lock them for 10 minutes
- Complete payment to confirm booking
- Receive booking confirmation (email + SMS)
- Cancel booking with refund

### Extended (Nice to Have, mention then deprioritize)
- Dynamic pricing (peak show surges)
- Loyalty points / promo codes
- Group bookings (10+ seats, bulk lock)
- Accessibility seat marking (wheelchair, companion)
- Admin panel for venue/show management

### Out of Scope (explicitly call out)
- Food & beverage ordering
- Live event streaming
- Multi-city inventory federation (treat each city independently)

---

## Non-Functional Requirements

| Property | Target | Notes |
|----------|--------|-------|
| Availability | 99.99% for booking path | ~52 min downtime/year |
| Seat availability consistency | Strong consistency | No double booking, ever |
| Seat lock TTL | 10 minutes | Configurable per show type |
| Seat status update latency | < 2 seconds to all viewers | WebSocket push |
| P99 booking API latency | < 500ms | Seat lock + DB write |
| P99 seat layout load | < 200ms | Cache hit path |
| Read/Write ratio | ~100:1 | Heavily read-dominant |
| Data retention | 5 years for bookings | Legal / audit |

---

## Scale Assumptions

> State assumptions before estimating — interviewers want to see you drive the numbers, not guess.

```
Users           : 50M registered, 5M DAU
Cities          : 100 cities, 5,000 venues
Screens         : 10,000 screens total
Seats/screen    : 300 average
Shows/day       : 50,000 (5 shows × 10,000 screens)
Bookings/day    : 2M bookings (avg 2.5 seats each → 5M seat transactions/day)
Peak event      : New Avengers release → 200,000 concurrent users, single show
Seat lock TLL   : 10 minutes = 600 seconds
```

---

## Back-of-Envelope Estimation

### Read QPS (Seat Layout)

```
DAU                       = 5,000,000
Seat layout views / user  = 3 (browse before deciding)
Total reads / day         = 15,000,000
Baseline read QPS         = 15,000,000 / 86,400 ≈ 175 QPS

Peak multiplier (Avengers opening): 200,000 concurrent users
Seat layout poll / user   = 0.2 req/sec (5 sec refresh or WebSocket reconnect)
Peak read QPS             = 200,000 × 0.2 = 40,000 QPS
```

**Design target: sustain 50,000 read QPS for seat layout (cache hit path).**

### Write QPS (Seat Locks + Bookings)

```
Bookings / day            = 2,000,000
Avg seats / booking       = 2.5
Seat lock transactions    = 5,000,000 / day = 58 TPS baseline

Peak (Avengers opening):
  200,000 concurrent users × 20% initiate booking = 40,000 bookings in 60 sec
  = 667 booking TPS
  = 667 × 2.5 = 1,667 seat lock writes/sec

Design target: handle 2,000 seat lock writes/sec sustained, 5,000 burst.
```

### Storage Estimation

```
Seat inventory (show_seat_inventory):
  10,000 screens × 300 seats × 5 shows/day = 15,000,000 rows/day
  Row size ≈ 200 bytes
  Daily delta = 15M × 200B = 3 GB/day
  Retained: active shows only (7 days) = 21 GB

Bookings table:
  2M bookings/day × 500 bytes/row = 1 GB/day
  5-year retention = 1,825 GB ≈ 1.8 TB (compressible to ~400 GB)

Payments table:
  2M/day × 300 bytes = 600 MB/day → 1 TB over 5 years

Total DB storage (hot):  ~50 GB (seats, active shows, recent bookings)
Total DB storage (cold): ~3 TB (5-year booking + payment archive)

Redis (seat layout cache):
  50,000 active shows × 300 seats × 10 bytes/seat ≈ 150 MB
  Lock keys: 2,000 concurrent locks × 100 bytes = 200 KB (negligible)
  Total Redis: < 1 GB for all seat state
```

### Bandwidth Estimation

```
Seat layout payload (300 seats, status per seat):
  300 × 20 bytes (seat_id + status) + headers = ~8 KB

Read bandwidth baseline: 175 QPS × 8 KB = 1.4 MB/s
Read bandwidth peak:     40,000 QPS × 8 KB = 320 MB/s (from cache, CDN)

WebSocket seat update event: ~200 bytes per seat change
Update rate peak: 2,000 lock/sec × 200 bytes = 400 KB/s pushed to subscribers
```

---

## Capacity Summary

| Resource | Baseline | Peak | Notes |
|----------|----------|------|-------|
| Read QPS (seat layout) | 175 | 50,000 | Served from Redis cache |
| Write QPS (seat locks) | 58 | 2,000 | Redis + DB dual write |
| Write QPS (bookings) | 23 | 800 | PostgreSQL primary |
| Redis memory | — | 1 GB | Seat layout + locks |
| PostgreSQL hot data | — | 50 GB | Active shows + bookings |
| Kafka throughput | — | 5 MB/s | Booking events |
| WebSocket connections | — | 200,000 | Seat update push |
