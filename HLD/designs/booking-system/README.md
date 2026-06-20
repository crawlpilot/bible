# BookMyShow — Movie Booking Platform

**Interview Level:** Principal / Staff Engineer  
**Design Framework:** RESHADED  
**Scale Target:** 50M users, 10,000 screens, zero double-bookings  
**Hard Invariant:** A seat confirmed by one user must never be confirmed by another.

---

## File Index

| File | Topic |
|------|-------|
| [00 — RESHADED Overview](00-overview.md) | Full RESHADED walkthrough, interviewer Q&A |
| [01 — Requirements & Estimation](01-requirements-estimation.md) | Functional / NFR, QPS math, storage sizing |
| [01 — Capacity Deep Dive](01-capacity-estimation.md) | Detailed back-of-envelope: QPS, Redis/MySQL/S3 sizing |
| [02 — High-Level Architecture](02-high-level-architecture.md) | Service decomposition, Mermaid diagram, tech stack |
| [02 — Architecture Detail](02-architecture.md) | Component diagram, data flow, real-time WebSocket path |
| [03 — Seat Locking Design](03-seat-locking-design.md) | Distributed locks, state machine, no-double-booking proof |
| [03 — Seat Layout & Locking](03-seat-layout-locking.md) | Lua atomic script, two-phase lock protocol, layout JSON |
| [04 — Booking Flow](04-booking-flow.md) | End-to-end sequence, seat layout display, in-transit seats |
| [05 — Payment & Rollback](05-payment-failure-rollback.md) | Saga pattern, failure modes, compensation transactions |
| [06 — Caching Strategy](06-caching-strategy.md) | Layout cache, Redis pub/sub, CDN, invalidation |
| [07 — Data Models](07-data-models.md) | PostgreSQL schema, indexes, partitioning |
| [08 — API Contracts](08-api-contracts.md) | REST endpoints, request/response, error codes |
| [09 — Trade-offs](09-trade-offs.md) | DB choices (ES vs PG, Mongo vs Cassandra vs SQL, Redis roles), locking, Saga, WebSocket |
| [10 — Failure Modes](10-failure-modes.md) | Component failure analysis, degraded-mode behavior |
| [11 — Search Flow](11-search-flow.md) | Elasticsearch design, index mappings, sync strategy, autocomplete, geo |

---

## Key Design Decisions (TL;DR for Interviewers)

| Decision | Choice | Primary Reason |
|----------|--------|----------------|
| Seat lock mechanism | Redis SETNX + DB optimistic lock | Speed (Redis) + correctness guarantee (DB) |
| Double-booking prevention | Dual-write with DB as source of truth | Redis can fail; DB ACID is authoritative |
| Payment failure handling | Saga compensating transactions | Avoid distributed 2PC; decouple services |
| Real-time seat status | Redis pub/sub → WebSocket push | Sub-second updates without polling |
| Seat layout caching | Redis Hash per show | Atomic per-seat HSET; O(1) status lookup |
| Database choice | PostgreSQL | ACID, optimistic concurrency, row-level locks |
| Event streaming | Kafka | Exactly-once, replay, multi-consumer fan-out |

---

## Critical Flows

```
Seat Selection  →  [Redis Lock]  →  [DB Lock]  →  Payment  →  [DB Confirm]  →  [Cache Update]
                         ↓ fail              ↓ fail          ↓ fail
                    Conflict 409        Rollback lock    Saga compensation
```

---

## Interviewer Follow-up Questions (anticipate these)

1. **"What happens if the Redis cluster goes down mid-booking?"**  
   → See [03 — Seat Locking Design § Redis Failure Fallback](03-seat-locking-design.md#redis-failure-fallback)

2. **"How do you handle 50,000 users hitting the same show the moment tickets open?"**  
   → See [03 — Seat Locking Design § Flash Sale Contention](03-seat-locking-design.md#flash-sale-contention)

3. **"Payment gateway confirmed payment but your DB update failed — what now?"**  
   → See [05 — Payment & Rollback § Partial Failure Scenarios](05-payment-failure-rollback.md#partial-failure-scenarios)

4. **"How do you show seats as 'being selected' without booking them?"**  
   → See [04 — Booking Flow § In-Transit Seat Display](04-booking-flow.md#in-transit-seat-display)

5. **"How would you add dynamic pricing (surge during peak shows)?"**  
   → See [09 — Trade-offs § Dynamic Pricing Extension](09-trade-offs.md#dynamic-pricing-extension)
