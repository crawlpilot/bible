# 10 — Failure Modes & Resilience

---

## Failure Analysis Framework

For each component, we ask:
1. **What fails?** (specific failure mode)
2. **What is the blast radius?** (who is affected)
3. **How does the system detect it?** (signal)
4. **What is the degraded behavior?** (is it safe to continue?)
5. **How does it recover?** (automatic vs manual)

---

## Component Failure Matrix

### Redis Cluster Failure

| Attribute | Details |
|-----------|---------|
| **Failure mode** | Network partition, node crash, OOM kill |
| **Blast radius** | Seat lock acquisition (fast path) + WebSocket updates + seat layout reads |
| **Detection** | Redis health check fails; circuit breaker opens in < 5 seconds |
| **Degraded behavior** | Fall back to DB-only locking (slower: 5–10ms). Seat layout served from DB read replica. WebSocket updates disabled; clients fall back to polling. |
| **Recovery** | Redis cluster auto-failover (AWS ElastiCache: < 60 seconds). On recovery: warm Redis cache from DB query. Resume WebSocket push. |
| **Correctness** | SAFE. DB is authoritative. No double booking possible even without Redis. |
| **SLA impact** | Booking throughput drops ~70% (DB contention). Layout load latency increases 5×. |

**Implementation**: Circuit breaker in Seat Lock Service. State: CLOSED → OPEN → HALF-OPEN.
```
On Redis connect failure × 3 in 10s: OPEN circuit → route to DB fallback
Every 30s: HALF-OPEN → probe Redis → if healthy, CLOSE circuit
```

---

### PostgreSQL Primary Failure

| Attribute | Details |
|-----------|---------|
| **Failure mode** | Instance crash, hardware failure, AZ outage |
| **Blast radius** | ALL WRITES blocked: seat locking, booking creation, payment recording |
| **Detection** | Connection timeout; RDS health check; application DB connection failure |
| **Degraded behavior** | WRITE PATH: completely down during failover window. READ PATH: read replicas still serve seat layouts, movie browsing. New booking attempts: 503 Service Unavailable. |
| **Recovery** | RDS Multi-AZ: automatic failover to standby in 30–60 seconds. DNS update points to new primary. Application reconnects automatically. |
| **Correctness** | SAFE. No writes during failover → no inconsistency. After failover, normal operation resumes. |
| **SLA impact** | ~60 seconds of booking unavailability per failover event. Estimated < 4 events/year with RDS Multi-AZ. |

**Cross-region DR** (for AZ-level failure or regional catastrophe):
```
RTO: 5 minutes (manual failover trigger via Route53 weight update)
RPO: 30 seconds (async replication lag to Singapore replica)
Data loss window: last 30 seconds of transactions
Trigger: automated health check + PagerDuty alert to on-call SRE
```

---

### Payment Gateway Failure (Razorpay / Stripe)

| Attribute | Details |
|-----------|---------|
| **Failure mode** | Gateway downtime, API timeout, degraded response |
| **Blast radius** | Payment collection blocked. Seat locks accumulate (users can't complete payment). |
| **Detection** | HTTP 5xx from gateway; P99 latency > 5s; circuit breaker trips |
| **Degraded behavior** | New payment attempts: 503 with "Payment temporarily unavailable, please try again". Existing locks preserved for up to 20 minutes (auto-extend while gateway is down). |
| **Recovery** | Gateway recovers → circuit breaker half-opens → resumes. Outstanding locks either convert to bookings (if payment comes through via webhook) or expire. |
| **Correctness** | SAFE. Money is not charged during gateway downtime. Seat locks may expire, returning seats to pool. |
| **SLA impact** | Revenue loss during downtime. User trust impact if frequent. |

**Multi-gateway fallback**:
```
Primary:   Razorpay (preferred: lower fees, UPI support)
Secondary: Stripe (fallback: international cards)
Tertiary:  PayU (backup)

Circuit breaker per gateway:
  On Razorpay failure → automatically route to Stripe
  On both failure → queue payment for retry + display "service degraded"
```

---

### Kafka Cluster Failure

| Attribute | Details |
|-----------|---------|
| **Failure mode** | Broker crash, topic partition leader election |
| **Blast radius** | Event publishing delayed. Notification Service doesn't receive events. Outbox relay buffers events locally. |
| **Detection** | Producer send failures; consumer lag spike |
| **Degraded behavior** | Booking completes (synchronous path is unaffected). Kafka events queue in `booking_outbox` table. Notification emails/SMS delayed. Seat status updates to Redis still happen (separate from Kafka). |
| **Recovery** | MSK auto-recovers in < 60 seconds. Outbox relay resumes publishing queued events in order. |
| **Correctness** | SAFE. Outbox ensures events are not lost. At-least-once delivery on recovery with deduplication at consumer. |
| **SLA impact** | Notification delay (up to 5 minutes). No booking impact. |

---

### WebSocket Service Failure

| Attribute | Details |
|-----------|---------|
| **Failure mode** | Pod crash, OOM, deployment rollout |
| **Blast radius** | Real-time seat updates stop for affected connections |
| **Detection** | Client-side WebSocket close event |
| **Degraded behavior** | Client falls back to 5-second polling automatically (client-side logic: if WS closes, start polling). |
| **Recovery** | Kubernetes restarts pod in < 30 seconds. Clients reconnect WebSocket and receive fresh snapshot. |
| **Correctness** | SAFE. Client gets fresh seat layout on reconnect or via polling. |
| **SLA impact** | 30–60 seconds of non-real-time seat updates. Polling adds ~5 seconds staleness. |

---

### Lock Expiry Race Condition

**Scenario**: User A's lock expires at T=600s. At T=599s, User A submits payment. At T=600s, Redis key expires and background job tries to release the lock.

```
T=599s: User A's payment request arrives
T=600s: Redis keyspace notification fires → background job queries DB
        UPDATE show_seat_inventory SET status='AVAILABLE'
        WHERE status='LOCKED' AND lock_expires_at < now()

T=599s: Payment Service transitions seat to 'IN_PAYMENT':
        UPDATE show_seat_inventory SET status='IN_PAYMENT'
        WHERE seat_id=? AND status='LOCKED' AND lock_expires_at > now()

Resolution:
  - The two DB updates race on the same row
  - If IN_PAYMENT update commits first:
    lock_expires_at > now() is TRUE → IN_PAYMENT succeeds
    Background job finds status='IN_PAYMENT' (not LOCKED) → skips it
    CORRECT: Payment proceeds

  - If background job commits first:
    status changes to 'AVAILABLE'
    Payment Service's conditional update sees status='LOCKED' is FALSE → 0 rows updated
    Payment Service returns "lock expired" error to user
    User receives "session expired" response
    CORRECT: No double booking, no phantom payment

The WHERE clauses make both updates safe to race.
```

---

### Double Booking Prevention: Proof

**Claim**: Two concurrent users (Alice and Bob) cannot both receive BOOKED confirmation for the same seat.

```
Scenario: Alice and Bob both try to book seat A1 simultaneously.

Step 1 (Redis):
  Alice: SETNX seat_lock:show123:A1 {alice} EX 600 → returns 1 (wins)
  Bob:   SETNX seat_lock:show123:A1 {bob}   EX 600 → returns 0 (loses)
  Bob receives 409 Conflict immediately. ✓ (Bob eliminated)

Step 2 (DB, only Alice reaches this):
  Alice: UPDATE show_seat_inventory SET status='LOCKED'
         WHERE show_id='show123' AND seat_id='A1' AND status='AVAILABLE'
  → 1 row updated (A1 was AVAILABLE). ✓

Step 3 (DB, payment confirmation):
  Alice: UPDATE show_seat_inventory SET status='BOOKED', version=version+1
         WHERE seat_id='A1' AND status='IN_PAYMENT' AND version=:expected_version
  → 1 row updated. ✓

Result: Only Alice has a BOOKED record. Bob was rejected at Step 1.

Edge case: Redis fails between Step 1 and Step 2.
  If Redis SETNX succeeds but Redis crashes before response:
    Alice's client retries (no Redis SETNX to re-acquire — key may be gone from crash)
    Alice's retry: SETNX returns 0 (key gone) or 1 (key survived in new cluster)
    If key gone: Alice goes to DB fallback path (SELECT FOR UPDATE NOWAIT)
    If key survived: Alice continues normally
  DB conditional UPDATE is always the backstop. ✓
```

---

## Cascade Failure Prevention

### Rate Limiting
```
User-level:   5 booking initiations / minute
IP-level:     20 booking initiations / minute
Global:       Circuit breaker at 90% DB connection pool utilization
Flash sale:   Virtual queue absorbs demand spike (see 03-seat-locking-design.md)
```

### Bulkhead Pattern
```
Booking Service → Seat Lock Service: dedicated thread pool (50 threads)
Booking Service → Payment Service:  dedicated thread pool (30 threads)
Booking Service → Notification:     async (Kafka), no thread pool impact

If Payment Service is slow → doesn't starve Seat Lock Service
```

### Timeout Hierarchy
```
Client → API Gateway:     30 seconds
API Gateway → Service:    25 seconds
Service → Redis:           1 second (fail fast; fall back to DB)
Service → PostgreSQL:     10 seconds (most operations < 50ms)
Service → Payment Gateway: 30 seconds (gateway is slow sometimes)
Service → Kafka:           5 seconds (should be < 100ms normally)
```

---

## Monitoring & Alerts

| Metric | Alert Condition | Severity | Action |
|--------|----------------|----------|--------|
| Double booking incidents | > 0 in 1 min | P0 | Page on-call immediately; halt booking |
| Seat lock acquisition failure rate | > 5% | P1 | Investigate Redis + DB contention |
| Payment gateway error rate | > 10% | P1 | Activate secondary gateway |
| DB replica lag | > 30 seconds | P1 | Stop serving reads from lagging replica |
| Redis memory > 80% | Threshold crossed | P2 | Scale Redis cluster; purge completed shows |
| Kafka consumer lag | > 10,000 events | P2 | Scale consumers; investigate backlog |
| Lock expiry rate | > 20%/hour | P3 | Investigate payment gateway latency |
| WebSocket connection errors | > 1% | P3 | Check WS pod health; restart if needed |
| Booking confirmation P99 > 2s | Threshold | P2 | Profile slow transactions |

---

## Disaster Recovery Runbook (Key Scenarios)

**Scenario: Double booking detected**
```
1. IMMEDIATELY: Halt all new booking writes (feature flag: booking.writes.enabled = false)
2. Identify affected bookings via: SELECT * FROM bookings WHERE show_id=? GROUP BY (show_id, seat_id) HAVING count(*) > 1
3. Contact affected users, issue refunds for duplicate bookings
4. Root cause analysis: check Redis/DB event logs around the incident time
5. Fix + re-enable booking writes
6. Post-mortem within 24 hours
```

**Scenario: Surge traffic (Avengers opening)**
```
Pre-event (1 hour before):
  1. Scale EKS nodes: +50% Booking Service pods
  2. Enable virtual queue mode for hot shows
  3. Pre-warm Redis seat layout cache
  4. Increase DB connection pool limits
  5. Enable aggressive CDN caching for movie discovery

During event:
  1. Monitor seat lock acquisition rate (dashboard)
  2. Circuit breaker thresholds active
  3. On-call SRE on standby

Post-event:
  1. Scale down after 2 hours
  2. Review metrics: missed bookings due to throttling
```
