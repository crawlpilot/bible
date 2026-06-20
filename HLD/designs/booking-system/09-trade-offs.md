# 09 — Trade-offs & Architectural Decisions

---

## Decision 1: Optimistic vs Pessimistic Locking for Seat Booking

**Context**: When a user selects a seat, we must prevent another user from booking the same seat simultaneously.

| Dimension | Optimistic Locking | Pessimistic Locking (SELECT FOR UPDATE) |
|-----------|-------------------|----------------------------------------|
| **Mechanism** | Version counter; fail on version mismatch | DB row-level lock held until transaction commits |
| **Contention** | No lock held during user think time | Lock held for up to 10 minutes (payment window) |
| **Throughput** | High — no blocking on reads | Low under contention — rows queue behind lock |
| **DB connections** | Released quickly | Long-held transaction keeps connection open |
| **Failure mode** | Conflict error → retry | Timeout / deadlock on highly contended seats |
| **Use case fit** | Good for read-mostly with occasional conflicts | Good for short, guaranteed-to-complete transactions |

**Decision**: Pessimistic locking for lock acquisition (the 10ms DB write), but optimistic locking for payment confirmation (the LOCKED → BOOKED transition uses the version counter to guard against concurrent state changes).

**Rationale**: The lock acquisition must be atomic — there's no sensible retry logic for a user trying to book a seat someone else just locked. The conditional `UPDATE ... WHERE status='AVAILABLE'` achieves this without holding a long-lived transaction.

---

## Decision 2: Redis-Only vs DB-Only vs Redis + DB Dual Write

| Dimension | Redis Only | DB Only | Redis + DB |
|-----------|-----------|---------|------------|
| **Lock latency** | < 1ms | 5–10ms | < 1ms (fast path) |
| **Durability** | Lost on crash | Durable | Both |
| **Correctness on Redis failure** | Seat locks lost → potential double booking | Safe (single source) | DB authoritative; falls back to DB-only mode |
| **Read scalability** | Excellent | Needs replicas | Redis handles all reads |
| **Complexity** | Simple | Simple | Higher — need consistency protocol |
| **Double-booking risk** | High (Redis crash, network partition) | None | Managed (Redis is gate, DB is truth) |

**Decision**: Redis + DB dual write. Redis is the fast gate (first barrier to prevent most conflicts at microsecond speed). DB is the source of truth. The DB conditional UPDATE is the authoritative anti-double-booking mechanism.

**Key invariant**: If Redis and DB ever diverge, DB wins. A seat marked AVAILABLE in Redis but BOOKED in DB is treated as BOOKED.

---

## Decision 3: Kafka vs SQS vs Synchronous RPC for Event Publishing

| Dimension | Kafka | AWS SQS | Synchronous gRPC |
|-----------|-------|---------|-----------------|
| **Exactly-once delivery** | Yes (idempotent producers + transactions) | At-least-once (deduplication available) | No (retries cause duplicates) |
| **Message ordering** | Per partition (partition by show_id) | Per FIFO queue | Synchronous ordering |
| **Fan-out (multiple consumers)** | Native (consumer groups) | Separate queues per consumer | N caller-side calls |
| **Replay / audit** | Yes (configurable retention) | No (deleted on consume) | No |
| **Coupling** | Loose | Loose | Tight |
| **Latency** | 5–50ms | 50–200ms | < 5ms |
| **Operational complexity** | High (manage brokers) | Low (managed) | Low |

**Decision**: Kafka for booking events (BOOKING_CONFIRMED, PAYMENT_FAILED, etc.).

**Rationale**: 
- Multiple consumers need the same event (Notification Service, Analytics, Seat Lock Service for rollback) — Kafka consumer groups make this trivial
- Replay is critical for debugging payment/rollback incidents
- The Outbox pattern requires a broker that supports exactly-once publish — Kafka's idempotent producer + transactional producer handles this
- MSK (managed Kafka on AWS) reduces operational overhead significantly

---

## Decision 4: PostgreSQL vs NoSQL for Seat Inventory

| Dimension | PostgreSQL | Cassandra | DynamoDB |
|-----------|-----------|-----------|----------|
| **ACID transactions** | Full | Limited (LWT, but not multi-row) | Conditional writes (single-item only) |
| **Multi-row atomic updates** | Yes (UPDATE ... WHERE IN (...)) | No (each partition key separate) | No (multi-item transactions limited) |
| **Optimistic locking** | Version counter + conditional UPDATE | Compare-and-set per row | Condition expressions per item |
| **Query flexibility** | Full SQL | Limited (partition key required) | Limited (partition + sort key) |
| **Scale-out** | Read replicas + partitioning | Native horizontal scale | Fully managed |
| **Consistency** | Strong (default) | Tunable (eventual by default) | Configurable |

**Decision**: PostgreSQL.

**Rationale**: The booking flow requires multi-row atomic updates (lock N seats, confirm N seats in one transaction). Cassandra and DynamoDB cannot atomically update multiple rows across partition keys — you'd need an application-level saga for every seat selection, introducing complexity where correctness is most critical. PostgreSQL's row-level locking and ACID guarantees make the no-double-booking invariant straightforward to implement correctly.

**Scale concern addressed**: Read replicas handle the 50,000 QPS read load. The write load (2,000 TPS) is well within PostgreSQL's capacity on modern hardware (RDS db.r6g.4xlarge handles 15,000+ TPS for small rows). Table partitioning handles data growth.

---

## Decision 5: WebSocket vs Long Polling vs SSE for Real-Time Seat Updates

| Dimension | WebSocket | Long Polling | Server-Sent Events (SSE) |
|-----------|----------|-------------|--------------------------|
| **Bidirectional** | Yes | Simulates it | No (server → client only) |
| **Connection overhead** | One persistent connection | New HTTP per poll | One persistent connection |
| **Latency** | < 100ms push | 1–5s poll interval | < 100ms push |
| **Proxy/firewall compatibility** | Sometimes blocked | Always works | Usually works |
| **Mobile battery impact** | Low (persistent) | High (frequent reconnect) | Low |
| **Server fan-out** | Needs sticky sessions or pub/sub | Stateless | Needs sticky sessions or pub/sub |
| **Fallback** | Polling | — | Polling |

**Decision**: WebSocket as primary, polling as fallback.

**Rationale**: For seat layout with 200,000 viewers, a 5-second polling interval generates 40,000 requests/second even when nothing changes. WebSocket pushes only deltas when seats change — far more efficient. SSE would also work but WebSocket supports bidirectional communication (useful for sending heartbeats, extending lock TTL).

**Fallback**: Clients that can't maintain WebSocket (network restrictions, mobile background state) fall back to GET /shows/{id}/seats every 5 seconds.

---

## Decision 6: Lock TTL — 10 Minutes

**Why 10 minutes?**

- Too short (< 5 min): Users on slow connections, elderly users, users comparison-shopping between tabs may not complete checkout in time → poor UX, abandoned bookings
- Too long (> 15 min): Seats locked by users who walked away never return to inventory → effective supply reduction during peak demand
- Industry standard: BookMyShow, Ticketmaster, IRCTC all use 8–15 minutes

**10 minutes is the balance** between user experience and inventory efficiency. Configurable per show type:
- Normal shows: 10 minutes
- High-demand (Avengers opening): 8 minutes (reduce hoarding)
- Flash sales: 5 minutes (maximum turnover)

---

## Decision 7: Seat Layout Storage — JSONB vs Normalized

| Approach | Normalized (seats table) | JSONB layout_config |
|---------|--------------------------|---------------------|
| **Queryability** | Full SQL queries | Limited (JSON operators) |
| **Update granularity** | Per-seat row update | Full document replace |
| **Join complexity** | Simple (seat_id FK) | Complex (JSON path extraction) |
| **Data size** | 1 row per seat (300 rows per screen) | 1 row per screen |
| **Use case** | Seat availability (dynamic) | Screen geometry (static) |

**Decision**: Hybrid.
- `seats` table: normalized rows, one per physical seat — used for availability, pricing, booking references
- `screens.layout_config`: JSONB for the physical geometry (positions, row labels, rendering metadata) — queried rarely, only for rendering

This separates the hot path (seat availability changes) from the cold path (screen geometry changes once a year).

---

## Dynamic Pricing Extension

**Not in initial design** but common follow-up question:

```
Current price:  STATIC — set at show creation, stored in show_seat_inventory.price

Dynamic pricing would require:
  1. Pricing Service: watches occupancy rate and demand signals
  2. Rule engine: 
     - < 20% seats sold at T-24h: discount 10%
     - > 80% seats sold: surcharge 20%
     - Peak time slots (evening/weekend): base surcharge
  3. Price updates: UPDATE show_seat_inventory SET price = new_price
     - Batch update (all seats at once): invalidates seat layout cache
  4. Display: show "prices from ₹350" on browse page + actual price in seat picker

Complexity added:
  - Price shown to user at selection time may differ from price at payment time
  - Need to lock in price at seat selection → store price in bookings.seat_details JSONB
  - Price changes after lock: user pays the price they saw at selection (committed)
```

---

---

## Decision 8: Elasticsearch vs PostgreSQL Full-Text vs Typesense vs Redis for Search

**Context**: Users need to search movies ("avengers"), browse shows by city/date/format, find venues near them, and get autocomplete suggestions — all at < 100ms.

| Dimension | Elasticsearch | PostgreSQL Full-Text (`tsvector`) | Typesense | Redis (sorted sets / FT module) |
|-----------|-------------|----------------------------------|-----------|--------------------------------|
| **Fuzzy / typo tolerance** | Excellent (`fuzziness: AUTO`) | Limited (no built-in fuzzy) | Excellent (built-in) | Basic (FT module: prefix only) |
| **Geo search** | Native (`geo_point`, `geo_distance`) | PostGIS extension needed | Native | No |
| **Faceted aggregations** | Native (terms, range aggs) | Requires GROUP BY + indexes | Limited | No |
| **Autocomplete** | Edge n-gram + completion suggester | Trigram index + LIKE | Built-in | Sorted set prefix trick |
| **Scale (QPS)** | 50K+ read QPS with replicas | ~5K with read replicas | 10K+ | 100K+ (in-memory) |
| **Operational complexity** | High (cluster, ILM, mappings) | Low (already have PG) | Low (single binary) | Medium |
| **Consistency with source** | Eventually consistent (1–2s lag) | Strong (same DB) | Eventually consistent | Eventually consistent |
| **Analytics / aggregations** | Excellent | Good (slower on large tables) | Basic | No |
| **Cost** | High (dedicated cluster) | Low (reuse existing) | Low | Medium |

**Decision**: Elasticsearch for search.

**Rationale**:
- The 50ms autocomplete + 100ms multi-filter requirement cannot be met by PostgreSQL full-text at 500K QPS read load — even with read replicas, `tsvector` queries on 50K shows with geo filters require table scans or complex GiST indexes that degrade under join pressure.
- PostgreSQL full-text works at startup (<100K MAU) and should be the v1 implementation — avoids Elasticsearch operational burden early.
- **Migration path**: Start with `tsvector` in PostgreSQL → observe when p99 search latency exceeds 150ms → migrate to Elasticsearch. Keep PostgreSQL as the source of truth; ES is rebuilt from Kafka events.
- Typesense is compelling for simplicity but lacks geo aggregations and mature ILM tooling at BookMyShow scale.
- Redis FT module is appropriate for autocomplete only — it is used as L1 cache in front of ES, not as a replacement.

**When NOT to use Elasticsearch**:
- Transactional data (never store booking records in ES)
- Data that requires strong consistency (seat availability counts — use Redis Hash)
- Joins (ES is a document store; cross-index joins require application logic)

---

## Decision 9: MongoDB vs Cassandra vs PostgreSQL vs DynamoDB for Movie/Venue Metadata

**Context**: Movies and venues have rich, nested, irregular schemas: cast arrays, trailer URLs, amenity lists, geo coordinates, multi-language titles, flexible metadata fields that differ by content type (documentary vs concert vs sports event).

| Dimension | MongoDB | Cassandra | PostgreSQL | DynamoDB |
|-----------|---------|-----------|-----------|---------|
| **Schema flexibility** | Excellent — BSON documents, nested arrays | Poor — wide column, schema changes are hard | Moderate — JSONB for flex fields | Good — schemaless items |
| **Rich nested queries** | Excellent — native nested document queries | Very limited — no nested queries | Good — JSONB operators | Limited — only primary key queries natively |
| **Geo queries** | Excellent — 2dsphere index | None natively | PostGIS extension | None |
| **ACID transactions** | Multi-document ACID (v4.0+) | LWT (limited, slow) | Full ACID | Single-item conditional writes |
| **Read pattern** | Point lookup by ID + range queries | Excellent for wide-row patterns (time-series) | Excellent | Point lookup only |
| **Write pattern** | Flexible, good throughput | Excellent write throughput (LSM tree) | Good | Excellent |
| **Horizontal scale** | Sharding (mongos router) | Native (consistent hashing) | Partitioning (complex) | Fully managed |
| **Operational complexity** | Medium | High (tuning, compaction, tombstones) | Low (team already has it) | Low (managed) |
| **Cost** | Medium | Medium | Low (shared) | Pay-per-request (can be high) |
| **Query language** | MQL (expressive) | CQL (SQL-like but limited) | Full SQL | SDK-based |

**Decision**: MongoDB for movie and venue metadata.

**Rationale**:
- A movie document is a self-contained object: `{title, cast[], crew[], genres[], trailers[], certificates{}, synopsis_by_language{}}`. MongoDB's document model maps directly — no normalization overhead, no JOIN latency.
- **Cassandra is the wrong tool here**: Cassandra excels at time-series writes (IoT, logs, user activity streams) and partition-key-based reads. Movie metadata has irregular nesting and rich query patterns (find all action movies in Hindi with rating > 8) that Cassandra cannot handle without full-table scans or denormalized pre-computed tables for each query pattern.
- **PostgreSQL JSONB** is a reasonable alternative and should be v1 (reuses existing infra). The inflection point to MongoDB is when: (a) JSONB query patterns grow complex enough to require GIN index tuning for nested arrays, or (b) the team needs native 2dsphere geo for venue proximity (PostGIS is an option but adds complexity).
- **DynamoDB** would work for pure key-value access (get movie by ID) but fails for discovery queries (browse by genre, language, release date) without complex GSI design.

**Read-only metadata pattern**:
```
Movies and venues change rarely (a movie's cast doesn't change after release).
Pattern:
  Write: PostgreSQL (canonical, audited) → sync to MongoDB via Kafka
  Read: MongoDB → Redis cache (TTL 5min) → CDN (static metadata pages)
  
This decouples the flexible-schema read path from the ACID write path.
```

---

## Decision 10: When to Use Redis vs Other Stores

Redis serves three distinct roles in this system. Each has different alternatives.

### Role A: Distributed Lock (Seat Locks)

| Option | Mechanism | Atomicity | TTL | Verdict |
|--------|-----------|-----------|-----|---------|
| **Redis** | `SET NX EX` | Atomic (single-threaded) | Native | **Chosen** |
| PostgreSQL advisory lock | `pg_try_advisory_lock` | Yes | No native TTL | Fallback only — no TTL means manual cleanup |
| Zookeeper / etcd | Ephemeral znodes | Strong | Session-based | Operationally heavy for seat-level locks |
| In-process mutex | Language primitives | No (multi-pod) | N/A | Invalid for distributed system |

**Decision**: Redis `SET NX EX`. The TTL is the core feature — it self-heals without a cleanup job. Postgres advisory locks are the fallback when Redis is down (no TTL, so the sweeper job handles expiry manually).

### Role B: Seat Availability Cache (Redis Hash per show)

| Option | Atomicity per seat | Full layout fetch | Real-time pub/sub | Verdict |
|--------|------------------|------------------|------------------|---------|
| **Redis Hash** | `HSET` per field | `HGETALL` O(1) | Native Pub/Sub | **Chosen** |
| Memcached | No (get-modify-put) | Full blob only | None | Loses atomicity; no pub/sub |
| Single JSON in Redis | No (string R-M-W) | O(1) get | Native | Atomic update requires Lua; bulky |
| Hazelcast / Infinispan | Yes | Yes | Yes | Heavy operational footprint |

**Decision**: Redis Hash. `HSET layout:{show_id} A1 LOCKED` is a single atomic field update. `HGETALL` returns all 300 seat statuses in one round-trip. The pub/sub channel for WebSocket fan-out is free with Redis.

**Memcached vs Redis**: Memcached is simpler and faster for pure string caching (no data structures, no persistence, no pub/sub). It has no role in this system beyond a hypothetical L1 for show metadata — and Redis already serves that role. Never use Memcached when you need atomic field-level updates or pub/sub.

### Role C: Caching (Show Metadata, Search Results, Idempotency Keys)

| Pattern | When | TTL |
|---------|------|-----|
| Cache-aside (lazy) | Show metadata (changes rarely) | 5 minutes |
| Write-through | Seat availability (changes constantly) | None (explicit invalidation) |
| Read-through | Search results | 60 seconds |
| Write-behind | Never in this system (risk: data loss) | — |

---

## Decision 11: Cassandra — When It Would Be the Right Choice

Cassandra was explicitly **not chosen** for any datastore in this design. It deserves a clear explanation of when it IS the right tool, so you can defend the decision in an interview.

**Cassandra excels at**:
- **Append-heavy time-series**: user activity logs, click streams, sensor data, audit trails where the write pattern is `INSERT INTO events (user_id, timestamp, event_data)` with no updates
- **Wide-row read patterns**: "give me all activity for user X sorted by timestamp" — perfect partition key (user_id) + clustering column (timestamp)
- **Multi-datacenter active-active writes**: Cassandra's eventual consistency model with tunable CL handles cross-DC writes natively — PostgreSQL cannot do active-active writes

**Why Cassandra fails here**:
1. **No multi-row atomicity**: locking 3 seats atomically requires touching 3 rows (`show_id=X, seat_id=A1/A2/A3`). Cassandra's LWT (Lightweight Transactions) is single-partition only — you can't CAS across partition keys without a distributed saga, which adds complexity exactly where correctness is hardest.
2. **No joins or flexible queries**: "find all AVAILABLE seats for show X" → in Cassandra, `show_id` is the partition key. This works. But "find all shows with > 50 seats available in Mumbai on Friday in IMAX format" → requires denormalized tables for each access pattern. Every new query pattern needs a new table.
3. **Tombstone accumulation**: LOCKED → AVAILABLE transitions create tombstones (Cassandra's delete mechanism). A seat that gets locked and released 10 times in an hour accumulates 10 tombstones. On read, Cassandra must merge all versions. Under booking churn, this degrades read performance significantly.
4. **Operational burden**: Cassandra requires careful tuning (compaction strategies, gc_grace_seconds, replication factor, repair schedules). For a team already running PostgreSQL, the operational cost is not justified when Cassandra's strengths don't match the problem.

**If Cassandra HAD a role here**: User booking history as an append log. Every booking event (INITIATED, LOCKED, CONFIRMED, CANCELLED) appended as an immutable row. Partition by `user_id`, clustering by `event_timestamp`. Query: "show me all booking events for user X in the last 30 days" — perfect Cassandra access pattern. In this design, the `bookings` table in PostgreSQL serves this role adequately at current scale; Cassandra would be considered if booking event volume exceeded 500M rows/day.

---

## Decision 12: Polyglot Persistence — Justifying Multiple Databases

A common interviewer challenge: *"Why not just use PostgreSQL for everything? You're introducing operational complexity."*

**Full system database map with justification**:

```
PostgreSQL  ← Bookings, payments, seat inventory, shows
             WHY: ACID required. Multi-row atomic lock acquisition.
                  Financial audit trail. Row-level CAS.

MongoDB     ← Movies, venues, screen layout configs
             WHY: Rich nested documents (cast, trailers, amenities).
                  Flexible schema (documentary ≠ concert ≠ movie fields).
                  Geo indexes for venue proximity.

Elasticsearch ← Search index (movies, shows, venues)
             WHY: Full-text fuzzy search. Multi-filter faceted queries.
                  Geo-distance sorting. 50ms autocomplete.
                  PostgreSQL full-text cannot sustain 50K QPS at this scale.

Redis       ← Seat locks, seat availability Hash, session, caches
             WHY: Atomic TTL-based locking (NX EX). Sub-millisecond ops.
                  Pub/sub for WebSocket fan-out.
                  Memcached cannot do atomic field updates or pub/sub.

Kafka       ← Event streaming between services
             WHY: Decoupling, exactly-once delivery, replay, multi-consumer.
                  Not a database, but the connective tissue.
```

**The right question is not "one DB or many" — it is "which DB fits each data's access pattern"**:

| Data Type | Access Pattern | Winner |
|-----------|---------------|--------|
| Financial transactions | ACID, multi-row, strong consistency | PostgreSQL |
| Flexible content metadata | Nested docs, geo, flexible schema | MongoDB |
| Search/discovery | Full-text, fuzzy, facets, geo-sort | Elasticsearch |
| Ephemeral locks + cache | TTL, atomicity, pub/sub, < 1ms | Redis |
| Time-series event log | Append-only, partition by ID + time | Cassandra (not yet needed) |
| Analytics / reporting | Column-oriented aggregations | ClickHouse / BigQuery (future) |

**Operational cost mitigation**:
- Managed services reduce overhead: RDS PostgreSQL, MongoDB Atlas, Elastic Cloud, ElastiCache, MSK
- Each store owned by one team (Inventory team owns Redis + Postgres; Search team owns ES + Mongo)
- Single failure domain: ES going down doesn't affect booking (search degrades, booking continues)

---

## Trade-off Summary

| Decision | Chose | Didn't Choose | Key Reason |
|----------|-------|--------------|------------|
| Lock mechanism | Redis SETNX + DB CAS | Redis-only, SELECT FOR UPDATE | DB = authoritative truth; TTL = self-healing |
| Seat inventory DB | PostgreSQL | Cassandra, DynamoDB | Multi-row ACID for atomic seat lock |
| Locking strategy | Conditional UPDATE WHERE status=AVAILABLE | SELECT FOR UPDATE | No long-lived transactions blocking readers |
| Payment failure | Saga + compensating transactions | 2PC | External gateway can't join distributed tx |
| Real-time updates | WebSocket + Redis pub/sub | Long polling | Efficiency at 200K concurrent viewers |
| Event streaming | Kafka | SQS, RabbitMQ | Exactly-once, replay, multi-consumer fan-out |
| Lock TTL | 10 minutes | Fixed 5 or 15 min | UX vs inventory efficiency balance |
| Search engine | Elasticsearch | PostgreSQL full-text, Typesense | Fuzzy, geo, facets, autocomplete at 50K QPS |
| Metadata store | MongoDB | Cassandra, DynamoDB, PG JSONB | Nested docs, geo index, flexible schema |
| Availability cache | Redis Hash | Memcached, single Redis string | Atomic per-field HSET; free pub/sub |
| Cassandra | Not used | — | Wrong access patterns; tombstone risk; no multi-row CAS |
