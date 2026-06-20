# 07 — Data Models

---

## Entity Relationship Overview

```
venues (1) ──< screens (1) ──< seats
                  │
                  └──< shows (1) ──< show_seat_inventory
                                          │
                                     bookings (1) ──< booking_seats
                                          │
                                     payments
                                          │
                                     booking_outbox
```

---

## Schema

### venues

```sql
CREATE TABLE venues (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    address         TEXT,
    latitude        DECIMAL(9,6),
    longitude       DECIMAL(9,6),
    metadata        JSONB,                  -- amenities, parking, wheelchair access
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_venues_city ON venues(city);
```

### screens

```sql
CREATE TABLE screens (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    venue_id        UUID        NOT NULL REFERENCES venues(id),
    name            VARCHAR(50) NOT NULL,   -- "Screen 1", "IMAX Hall"
    total_seats     INT         NOT NULL,
    screen_type     VARCHAR(20) NOT NULL,   -- STANDARD, IMAX, 4DX, DOLBY
    layout_version  INT         NOT NULL DEFAULT 1,
    layout_config   JSONB,                  -- physical grid: rows, seat numbers, positions
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_screens_venue ON screens(venue_id);
```

**`layout_config` structure** (stored in S3, referenced here by version):
```json
{
  "rows": [
    {"label": "A", "seats": 20, "type": "STANDARD", "y": 0},
    {"label": "B", "seats": 20, "type": "STANDARD", "y": 1},
    {"label": "P", "seats": 10, "type": "RECLINER",  "y": 15}
  ],
  "screen": {"x": 10, "width": 20},
  "total": 300
}
```

### seats

```sql
CREATE TABLE seats (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    screen_id       UUID        NOT NULL REFERENCES screens(id),
    row_label       CHAR(3)     NOT NULL,   -- A, B, ..., Z, AA
    seat_number     SMALLINT    NOT NULL,   -- 1, 2, ..., 30
    seat_type       VARCHAR(20) NOT NULL,   -- STANDARD, PREMIUM, RECLINER, VIP
    position_x      SMALLINT,              -- grid x for UI rendering
    position_y      SMALLINT,              -- grid y for UI rendering
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    UNIQUE (screen_id, row_label, seat_number)
);

CREATE INDEX idx_seats_screen ON seats(screen_id);
```

### movies

```sql
CREATE TABLE movies (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title           VARCHAR(255) NOT NULL,
    original_title  VARCHAR(255),
    language        VARCHAR(50)  NOT NULL,
    genre           VARCHAR[]    NOT NULL,   -- ['ACTION', 'THRILLER']
    duration_min    SMALLINT     NOT NULL,
    rating          VARCHAR(5),              -- U, U/A, A, S
    release_date    DATE,
    poster_url      TEXT,
    trailer_url     TEXT,
    synopsis        TEXT,
    cast            JSONB,                   -- [{name, role, image_url}]
    metadata        JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_movies_release ON movies(release_date);
CREATE INDEX idx_movies_language ON movies(language);
```

### shows

```sql
CREATE TABLE shows (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    movie_id        UUID         NOT NULL REFERENCES movies(id),
    screen_id       UUID         NOT NULL REFERENCES screens(id),
    start_time      TIMESTAMPTZ  NOT NULL,
    end_time        TIMESTAMPTZ  NOT NULL,
    language        VARCHAR(50)  NOT NULL,  -- movie may screen in multiple languages
    format          VARCHAR(20)  NOT NULL,  -- 2D, 3D, IMAX, 4DX
    status          VARCHAR(20)  NOT NULL DEFAULT 'UPCOMING',
    -- UPCOMING, OPEN_FOR_BOOKING, IN_PROGRESS, COMPLETED, CANCELLED
    base_price      DECIMAL(10,2) NOT NULL,
    price_tiers     JSONB,                  -- {STANDARD: 200, PREMIUM: 350, RECLINER: 500}
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_show_time CHECK (end_time > start_time)
);

CREATE INDEX idx_shows_movie_time  ON shows(movie_id, start_time);
CREATE INDEX idx_shows_screen_time ON shows(screen_id, start_time);
CREATE INDEX idx_shows_city_time   ON shows(start_time)
    INCLUDE (movie_id, screen_id, status);  -- covering index for browse queries
```

### show_seat_inventory

```sql
-- One row per (show, seat). This is the hot table — high write contention.
CREATE TABLE show_seat_inventory (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    show_id             UUID         NOT NULL REFERENCES shows(id),
    seat_id             UUID         NOT NULL REFERENCES seats(id),

    -- Availability state
    status              VARCHAR(15)  NOT NULL DEFAULT 'AVAILABLE',
    -- AVAILABLE | LOCKED | IN_PAYMENT | BOOKED | CANCELLED | BLOCKED

    -- Lock metadata (populated when LOCKED or IN_PAYMENT)
    locked_by_user      UUID,
    lock_id             UUID,               -- booking_id of the active lock
    lock_expires_at     TIMESTAMPTZ,

    -- Booking reference (populated when BOOKED)
    booking_id          UUID,

    -- Pricing (can differ from show base price: dynamic, promo)
    price               DECIMAL(10,2) NOT NULL,

    -- Optimistic locking
    version             INT          NOT NULL DEFAULT 0,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    UNIQUE (show_id, seat_id),

    CONSTRAINT chk_lock_fields CHECK (
        (status = 'AVAILABLE' AND locked_by_user IS NULL) OR
        (status IN ('LOCKED', 'IN_PAYMENT') AND locked_by_user IS NOT NULL) OR
        (status IN ('BOOKED', 'CANCELLED', 'BLOCKED'))
    )
);

-- Primary lookup: all seats for a show
CREATE INDEX idx_ssi_show         ON show_seat_inventory(show_id, status);

-- Cleanup job: find expired locks
CREATE INDEX idx_ssi_lock_expiry  ON show_seat_inventory(lock_expires_at)
    WHERE status IN ('LOCKED', 'IN_PAYMENT');

-- Booking reference lookup
CREATE INDEX idx_ssi_booking      ON show_seat_inventory(booking_id)
    WHERE booking_id IS NOT NULL;
```

**Partitioning strategy** (when table exceeds 500M rows):
```sql
-- Partition by show start_time month
-- Old shows (completed) are cold partitions → archive to S3, remove from hot DB
ALTER TABLE show_seat_inventory PARTITION BY RANGE (show_id)
-- Or range-partition on a derived column for uniform distribution
-- In practice: UUID-based range partitioning or hash partitioning by show_id
```

### bookings

```sql
CREATE TABLE bookings (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL,
    show_id         UUID         NOT NULL REFERENCES shows(id),

    -- Seat snapshot (denormalized for fast receipt generation)
    seat_ids        UUID[]       NOT NULL,
    seat_details    JSONB,                  -- [{seat_id, row, number, type, price}]

    total_amount    DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    final_amount    DECIMAL(10,2) NOT NULL,

    status          VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    -- PENDING | CONFIRMED | FAILED | CANCELLED

    payment_id      UUID,                   -- FK to payments.id
    idempotency_key UUID         NOT NULL,

    -- Saga state (for orchestration)
    saga_state      JSONB,

    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    confirmed_at    TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ,
    failure_reason  TEXT,

    UNIQUE (idempotency_key)
);

CREATE INDEX idx_bookings_user       ON bookings(user_id, created_at DESC);
CREATE INDEX idx_bookings_show       ON bookings(show_id);
CREATE INDEX idx_bookings_status     ON bookings(status, created_at)
    WHERE status IN ('PENDING', 'FAILED');  -- partial index for active monitoring
```

### payments

```sql
CREATE TABLE payments (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id          UUID         NOT NULL REFERENCES bookings(id),
    user_id             UUID         NOT NULL,

    amount              DECIMAL(10,2) NOT NULL,
    currency            CHAR(3)      NOT NULL DEFAULT 'INR',

    -- Gateway details
    gateway             VARCHAR(50)  NOT NULL,   -- RAZORPAY, STRIPE, UPI
    gateway_order_id    VARCHAR(255),             -- gateway's order identifier
    gateway_payment_id  VARCHAR(255),             -- gateway's payment identifier
    gateway_response    JSONB,                    -- raw gateway response (audit)

    status              VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    -- PENDING | SUCCESS | FAILED | REFUNDED | PARTIALLY_REFUNDED

    idempotency_key     UUID         NOT NULL,

    refund_amount       DECIMAL(10,2),
    refund_id           VARCHAR(255),
    refund_reason       TEXT,
    refunded_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    UNIQUE (idempotency_key),
    UNIQUE (gateway_payment_id) WHERE gateway_payment_id IS NOT NULL
);

CREATE INDEX idx_payments_booking  ON payments(booking_id);
CREATE INDEX idx_payments_status   ON payments(status, created_at)
    WHERE status = 'PENDING';
```

### booking_outbox

```sql
CREATE TABLE booking_outbox (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id      UUID         NOT NULL,
    event_type      VARCHAR(50)  NOT NULL,
    -- BOOKING_CONFIRMED | BOOKING_FAILED | BOOKING_CANCELLED
    -- PAYMENT_CAPTURED | PAYMENT_FAILED | REFUND_PROCESSED | SEATS_RELEASED

    payload         JSONB        NOT NULL,
    status          VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    -- PENDING | PUBLISHED | DEAD

    retry_count     SMALLINT     NOT NULL DEFAULT 0,
    last_error      TEXT,

    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at    TIMESTAMPTZ
);

-- Relay process queries this constantly
CREATE INDEX idx_outbox_pending ON booking_outbox(status, created_at)
    WHERE status = 'PENDING';
```

---

## Indexing Strategy

| Table | Hot Queries | Indexes |
|-------|-------------|---------|
| `show_seat_inventory` | All seats for a show | `(show_id, status)` |
| `show_seat_inventory` | Expired locks cleanup | `(lock_expires_at) WHERE status IN ('LOCKED', 'IN_PAYMENT')` |
| `bookings` | User's booking history | `(user_id, created_at DESC)` |
| `shows` | Movie shows in city today | `(start_time) INCLUDE (movie_id, screen_id, status)` |
| `payments` | Unresolved pending payments | `(status, created_at) WHERE status='PENDING'` |
| `booking_outbox` | Unpublished events | `(status, created_at) WHERE status='PENDING'` |

---

## Database Sizing

```
show_seat_inventory (hot, active shows only):
  10,000 screens × 5 shows/day × 300 seats = 15M rows/day
  Row size: ~300 bytes
  7-day rolling window (active shows): 15M × 7 × 300B = 31.5 GB

bookings (all time):
  2M/day × 365 days × 5 years = 3.65B rows
  Row size: ~600 bytes (with JSONB seat_details)
  Total: 2.19 TB (compressed: ~500 GB with zstd)

Archive strategy:
  - After show completes: archive show_seat_inventory to S3 (Parquet format)
  - After 1 year: archive bookings to S3 (cold storage, queryable via Athena)
  - Hot DB stays small: ~100 GB for active data + recent history
```
