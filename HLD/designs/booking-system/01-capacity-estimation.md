# Capacity Estimation — Movie Booking Platform

> Back-of-envelope math done before designing. State your assumptions clearly in the interview.

---

## Assumptions

| Parameter | Value | Source / Reasoning |
|-----------|-------|--------------------|
| Monthly Active Users | 75M | BookMyShow India scale |
| Daily Active Users | ~10M (13% of MAU) | Industry benchmark |
| Bookings per day (average) | 1.5M | ~15% DAU converts |
| Bookings per day (peak — Diwali/blockbuster) | 3M | 2× average |
| Average seats per booking | 2.5 | Mix of solo and group |
| Lock-to-booking conversion rate | 40% | Many users lock, fewer complete |
| Shows per day | 50K | 10K screens × 5 shows each |
| Seats per screen (average) | 200 | Mix of small/large halls |
| Lock TTL | 600 seconds | 10-minute payment window |
| Read:Write ratio (seat layout) | 1000:1 | Far more views than bookings |

---

## QPS Estimation

### Write QPS (Booking Critical Path)

```
Locks initiated/day   = Bookings / conversion_rate = 3M / 0.4 = 7.5M
Lock QPS (average)    = 7.5M / 86,400 ≈ 87 QPS
Lock QPS (peak)       = 87 × 40× spike factor ≈ 3,500 QPS

Booking confirms/day  = 3M
Confirm QPS (average) = 3M / 86,400 ≈ 35 QPS
Confirm QPS (peak)    = 35 × 40 ≈ 1,400 QPS
```

> **Key insight**: A single blockbuster release (Avengers, KGF) can generate **50K concurrent users** in the first minute. That's a **500× spike** over baseline for ONE show.

### Read QPS (Seat Layout)

```
Seat layout views/day = DAU × views_per_user_session = 10M × 5 = 50M
Layout read QPS (avg) = 50M / 86,400 ≈ 580 QPS
Layout read QPS (peak)= 580 × 100 ≈ 58,000 QPS
```

This is why seat layout **must be served from cache**, not DB.

### Seat State Invalidation Events

```
Lock events/day       = 7.5M (acquired) + 7.5M (released/expired) ≈ 15M
Invalidation QPS (avg)= 15M / 86,400 ≈ 175 QPS
Invalidation QPS (peak)= 175 × 40 ≈ 7,000 QPS
```

---

## Storage Estimation

### MySQL (Booking & Seat State)

```
show_seats table:
  Shows/day            = 50K
  Seats/show           = 200
  Rows/day             = 50K × 200 = 10M rows/day
  Row size             = 100 bytes (show_id, seat_id, status, lock_expires, booking_id)
  Daily writes         = 10M × 100B ≈ 1GB/day
  Retention (1 year)   = 1GB × 365 ≈ 365GB

bookings table:
  3M rows/day × 500 bytes = 1.5GB/day
  1 year = ~550GB

Total MySQL storage   ≈ 1TB/year (with indexes, 2× raw data → 2TB)
```

> Partition `show_seats` by `show_date` for easy archiving. Shows older than 30 days move to cold storage.

### Redis (Locks + Availability Cache)

```
Active show window    = 3 hours (shows that are currently bookable)
Shows active at once  = 50K total/day × (3h/24h) ≈ 6,250 shows

Per-show Redis Hash:
  Seats per show       = 200
  Bytes per seat field = 50 bytes (field_name + status + user_id)
  Per-show hash size   = 200 × 50B = 10KB

Total Redis for seat layout:
  6,250 shows × 10KB ≈ 62MB                [tiny]

Seat locks (active):
  Concurrent locks     ≈ 3,500 QPS × 600s TTL ≈ 2.1M keys
  Per key size         = 100 bytes
  Total lock memory    = 2.1M × 100B ≈ 210MB

Total Redis working set ≈ 500MB (very manageable)
Recommended instance  : r6g.large (13GB) with plenty of headroom
```

### MongoDB (Movies + Venues)

```
Movies in DB          = 10K active, 1M historical
Avg movie doc size    = 5KB (metadata, cast, trailers)
Total                 = 1M × 5KB = 5GB

Venues                = 10K screens × 2KB each = 20MB
```

### Elasticsearch (Search Index)

```
Indexed documents     = 50K shows/day, kept for 30 days = 1.5M docs
Avg doc size          = 1KB
Index size            = 1.5M × 1KB × 5 (shards + replicas) ≈ 7.5GB
```

### S3 (Static + Seat Layout Snapshots)

```
Movie posters         = 10K × 500KB = 5GB
Seat layout configs   = 10K screens × 10KB = 100MB
Booking PDF tickets   = 3M/day × 50KB = 150GB/day  ← significant
  (6 months retention)= 150GB × 180 = 27TB
```

---

## Network / Bandwidth

```
Seat layout response  = 10KB per response
Layout QPS (peak)     = 58,000
Bandwidth (peak)      = 58,000 × 10KB ≈ 580MB/s outbound

With CDN (90% cache hit):
  Origin bandwidth    = 58MB/s (10%)     ← manageable
  CDN bandwidth       = 522MB/s (90%)    ← CloudFront handles this
```

---

## Summary Table

| Resource | Average | Peak |
|----------|---------|------|
| Lock write QPS | 87 | 3,500 |
| Layout read QPS | 580 | 58,000 |
| MySQL IOPS | ~500 | ~20,000 |
| Redis ops/sec | ~5,000 | ~200,000 |
| Redis memory | 500MB | 2GB |
| MySQL storage | — | 2TB/year |
| S3 (tickets) | — | 27TB/6mo |

---

## Scaling Thresholds (When to Re-architect)

| Current tier | Breaks at | Next action |
|--------------|-----------|-------------|
| Single Redis primary | ~500K ops/sec | Redis Cluster (shard by show_id) |
| Single MySQL writer | ~50K IOPS | MySQL read replicas + write sharding by show_id |
| Monolithic Booking Service | ~10K RPS | Horizontal pod autoscaling + queue-based lock acquisition |
