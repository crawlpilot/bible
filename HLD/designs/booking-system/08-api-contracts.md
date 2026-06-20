# 08 — API Contracts

All APIs are RESTful, JSON-encoded, authenticated via Bearer JWT. Idempotency-Key header required for all write operations.

---

## 1. Movie Discovery

### GET /movies
Browse movies by city and date.

**Query params**: `city`, `date` (YYYY-MM-DD), `language`, `genre`, `page`, `limit`

```
GET /movies?city=mumbai&date=2026-06-07&language=hindi&page=1&limit=20
Authorization: Bearer {jwt}

Response 200:
{
  "movies": [
    {
      "id": "movie_abc123",
      "title": "Avengers: Doomsday",
      "language": "Hindi",
      "genre": ["ACTION", "SCI-FI"],
      "duration_min": 170,
      "rating": "U/A",
      "poster_url": "https://cdn.bookmyshow.com/posters/avengers.jpg",
      "shows_available": 28,
      "next_show": "2026-06-07T14:30:00+05:30"
    }
  ],
  "pagination": { "total": 45, "page": 1, "limit": 20 }
}

Cached: CDN max-age=60s | Redis TTL=300s
```

---

### GET /movies/{movie_id}/shows
List all shows for a movie in a city on a date.

```
GET /movies/movie_abc123/shows?city=mumbai&date=2026-06-07
Authorization: Bearer {jwt}

Response 200:
{
  "movie": { "id": "...", "title": "...", "duration_min": 170 },
  "shows": [
    {
      "id": "show_xyz789",
      "venue": { "id": "...", "name": "PVR Juhu", "city": "Mumbai" },
      "screen": { "name": "IMAX Screen 1", "type": "IMAX" },
      "start_time": "2026-06-07T14:30:00+05:30",
      "format": "IMAX",
      "language": "Hindi",
      "status": "OPEN_FOR_BOOKING",
      "available_seats": 187,
      "total_seats": 300,
      "price_tiers": {
        "STANDARD": 350,
        "PREMIUM": 550,
        "RECLINER": 800
      }
    }
  ]
}

Cached: Redis TTL=60s (shows change frequently as seats are booked)
```

---

## 2. Seat Layout

### GET /shows/{show_id}/seats
Return seat layout with real-time availability.

```
GET /shows/show_xyz789/seats
Authorization: Bearer {jwt}

Response 200:
{
  "show_id": "show_xyz789",
  "screen": {
    "id": "screen_abc",
    "name": "IMAX Screen 1",
    "layout_version": 3
  },
  "seats": [
    {
      "id": "seat_a1",
      "row": "A",
      "number": 1,
      "type": "STANDARD",
      "status": "AVAILABLE",  // AVAILABLE | LOCKED | BOOKED | BLOCKED
      "price": 350,
      "position": { "x": 0, "y": 0 }
    },
    {
      "id": "seat_a2",
      "row": "A",
      "number": 2,
      "type": "STANDARD",
      "status": "LOCKED",     // Being selected by another user
      "price": 350,
      "position": { "x": 1, "y": 0 }
    }
  ],
  "price_legend": {
    "STANDARD": 350,
    "PREMIUM": 550,
    "RECLINER": 800
  },
  "cached_at": "2026-06-07T14:25:10Z"
}

Cache: Redis Hash (HGETALL) — near-real-time (updated on every seat state change)
Headers: Cache-Control: no-store  (client must not cache; always fresh from Redis)
```

---

## 3. Booking

### POST /bookings/initiate
Temporarily lock selected seats for 10 minutes.

```
POST /bookings/initiate
Authorization: Bearer {jwt}
Idempotency-Key: {client-generated UUID}

Request:
{
  "show_id": "show_xyz789",
  "seat_ids": ["seat_a1", "seat_b3", "seat_b4"]
}

Response 201 — Seats locked:
{
  "booking_id": "booking_qrs456",
  "status": "PENDING",
  "seats": [
    { "id": "seat_a1", "row": "A", "number": 1, "type": "STANDARD", "price": 350 },
    { "id": "seat_b3", "row": "B", "number": 3, "type": "STANDARD", "price": 350 },
    { "id": "seat_b4", "row": "B", "number": 4, "type": "STANDARD", "price": 350 }
  ],
  "subtotal": 1050,
  "taxes": 157.50,
  "total": 1207.50,
  "expires_at": "2026-06-07T14:35:10Z",  // 10-minute TTL
  "expires_in_seconds": 600
}

Response 409 — Conflict (seats already locked/booked):
{
  "error": "SEAT_CONFLICT",
  "message": "Some seats are no longer available",
  "conflict_seats": [
    { "id": "seat_a1", "status": "LOCKED" }
  ]
}

Response 400 — Invalid request:
{
  "error": "INVALID_REQUEST",
  "message": "Cannot book more than 10 seats per transaction",
  "code": "MAX_SEATS_EXCEEDED"
}

Response 429 — Rate limited:
{
  "error": "RATE_LIMITED",
  "retry_after_seconds": 30
}
```

---

### GET /bookings/{booking_id}
Get current booking status (for polling during payment uncertainty).

```
GET /bookings/booking_qrs456
Authorization: Bearer {jwt}

Response 200:
{
  "booking_id": "booking_qrs456",
  "status": "PENDING",          // PENDING | CONFIRMED | FAILED | CANCELLED
  "show": { "id": "...", "movie": "...", "start_time": "..." },
  "seats": [...],
  "total": 1207.50,
  "expires_at": "2026-06-07T14:35:10Z",
  "payment_status": null        // null | PENDING | SUCCESS | FAILED
}

Response 200 (CONFIRMED):
{
  "booking_id": "booking_qrs456",
  "status": "CONFIRMED",
  "ticket_id": "BMS-2026-QRS456",
  "download_url": "https://cdn.bookmyshow.com/tickets/BMS-2026-QRS456.pdf",
  "seats": [...],
  "payment_status": "SUCCESS"
}
```

---

### POST /bookings/{booking_id}/pay
Initiate payment for locked seats.

```
POST /bookings/booking_qrs456/pay
Authorization: Bearer {jwt}
Idempotency-Key: {client-generated UUID}

Request:
{
  "payment_method": "CARD",
  "card_token": "tok_xyz_from_gateway_sdk",   // Tokenized by client-side gateway SDK
  "save_card": false
}

Response 200 — Payment successful:
{
  "booking_id": "booking_qrs456",
  "status": "CONFIRMED",
  "ticket_id": "BMS-2026-QRS456",
  "payment": {
    "id": "pay_abc789",
    "amount": 1207.50,
    "status": "SUCCESS",
    "gateway_payment_id": "pay_razorpay_xyz"
  },
  "download_url": "https://cdn.bookmyshow.com/tickets/BMS-2026-QRS456.pdf"
}

Response 402 — Payment failed:
{
  "error": "PAYMENT_FAILED",
  "reason": "INSUFFICIENT_FUNDS",
  "message": "Payment declined. Seats have been released.",
  "can_retry": true,
  "retry_message": "Please select seats again to retry."
}

Response 408 — Payment timeout (async resolution):
{
  "error": "PAYMENT_PENDING",
  "message": "Payment is being processed. Please wait.",
  "poll_url": "/bookings/booking_qrs456",
  "retry_after_seconds": 10
}

Response 410 — Booking expired:
{
  "error": "BOOKING_EXPIRED",
  "message": "Your seat hold expired. Please select seats again."
}
```

---

### POST /bookings/{booking_id}/cancel
Cancel a confirmed booking.

```
POST /bookings/booking_qrs456/cancel
Authorization: Bearer {jwt}
Idempotency-Key: {client-generated UUID}

Response 200:
{
  "booking_id": "booking_qrs456",
  "status": "CANCELLED",
  "refund": {
    "amount": 1207.50,
    "policy": "FULL_REFUND",
    "expected_by": "2026-06-14",
    "refund_id": "refund_abc123"
  }
}

Response 422:
{
  "error": "CANCELLATION_NOT_ALLOWED",
  "reason": "Show starts in less than 1 hour. Cancellation window has closed."
}
```

---

## 4. WebSocket — Real-Time Seat Updates

```
WS /ws/shows/{show_id}/seats
Authorization: Bearer {jwt}  (sent as query param: ?token={jwt})

On connect: server sends full snapshot
→ {
    "type": "SNAPSHOT",
    "show_id": "show_xyz789",
    "seats": { "seat_a1": "A", "seat_a2": "L", "seat_b3": "B", ... }
  }

On seat state change (pushed by server):
→ {
    "type": "DELTA",
    "show_id": "show_xyz789",
    "timestamp": 1717890000,
    "updates": [
      { "seat_id": "seat_a1", "status": "L" },
      { "seat_id": "seat_a2", "status": "A" }
    ]
  }

On lock expiry (seat released):
→ {
    "type": "DELTA",
    "updates": [{ "seat_id": "seat_a2", "status": "A" }]
  }

Client heartbeat:
→ PING (every 30s)
← PONG

Connection limits: 1 WebSocket per user per show (enforce at gateway)
```

---

## 5. Admin APIs

### POST /admin/shows
Create a new show and seed seat inventory.

```
POST /admin/shows
Authorization: Bearer {admin-jwt}

Request:
{
  "movie_id": "movie_abc123",
  "screen_id": "screen_def456",
  "start_time": "2026-06-07T14:30:00+05:30",
  "format": "IMAX",
  "language": "Hindi",
  "base_price": 350,
  "price_tiers": { "STANDARD": 350, "PREMIUM": 550, "RECLINER": 800 }
}

Response 201:
{
  "show_id": "show_xyz789",
  "seats_seeded": 300
}

Background:
  INSERT INTO shows (...)
  INSERT INTO show_seat_inventory (show_id, seat_id, status='AVAILABLE', price=...)
    SELECT id, ... FROM seats WHERE screen_id = :screen_id AND is_active = true;
  HSET show:{show_id}:seat_layout ...  (seed Redis cache)
```

---

## Error Code Reference

| HTTP Status | Error Code | Description |
|------------|-----------|-------------|
| 400 | INVALID_REQUEST | Malformed request body |
| 400 | MAX_SEATS_EXCEEDED | More than 10 seats in one booking |
| 401 | UNAUTHORIZED | Invalid or expired JWT |
| 403 | FORBIDDEN | User not allowed to perform action |
| 404 | NOT_FOUND | Show, seat, or booking not found |
| 409 | SEAT_CONFLICT | Seat already locked or booked by another user |
| 410 | BOOKING_EXPIRED | Lock TTL expired |
| 422 | CANCELLATION_NOT_ALLOWED | Outside cancellation window |
| 429 | RATE_LIMITED | Too many requests |
| 402 | PAYMENT_FAILED | Card declined / gateway rejection |
| 408 | PAYMENT_PENDING | Gateway response timeout, poll for result |
| 500 | INTERNAL_ERROR | Unexpected server error |
| 503 | SERVICE_UNAVAILABLE | Booking system in maintenance |
