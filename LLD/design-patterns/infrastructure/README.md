# Infrastructure / Resource Management Patterns

These patterns operate below the application layer — governing how resources (connections, threads, locks, leadership) are managed across a process or distributed cluster. They are not in the GoF catalogue but are first-class vocabulary for FAANG principal engineer interviews in system design, LLD, and distributed systems discussions.

## When to Reach for an Infrastructure Pattern

- An expensive resource (DB connection, thread, GPU handle) must be shared across requests (Object Pool)
- Inbound request rate must be bounded to protect downstream capacity (Rate Limiter)
- Exactly one node in a cluster must perform a coordinating action (Leader Election)
- A data structure is read far more often than it is written and performance matters (Read-Write Lock)

## Patterns in This Category

| Pattern | Intent | Complexity | Interview Frequency |
|---------|--------|-----------|---------------------|
| [Object Pool](../modern/38-object-pool.md) | Pre-allocate and reuse expensive objects — DB connections, threads, HTTP clients | Medium | Common |
| [Rate Limiter](42-rate-limiter.md) | Bound inbound request rate per client — Token Bucket, Sliding Window, Fixed Window | Medium | Very Common |
| [Leader Election](43-leader-election.md) | Elect exactly one coordinator node in a cluster; survive failures | High | Common |
| [Read-Write Lock](44-read-write-lock.md) | Concurrent reads / exclusive writes — maximise throughput for read-heavy data | Medium | Common |

> **Object Pool** lives in `modern/38-object-pool.md` because connection pooling is a modern infrastructure concern with distributed implications (PgBouncer, HikariCP), but it is indexed here as part of the infrastructure pattern family.

---

## Key Distinctions

### Object Pool vs Flyweight
- **Flyweight**: shares **read-only immutable** state (e.g., product metadata); unlimited concurrent access; never "returned"
- **Object Pool**: manages **mutable, exclusively-held** objects (e.g., DB connections); one holder at a time; must be returned

### Rate Limiter vs Circuit Breaker vs Bulkhead
- **Rate Limiter**: controls **inbound request rate** — limits how fast clients can call you
- **Circuit Breaker**: detects **outbound failure** — stops you from calling a broken dependency
- **Bulkhead**: **isolates resource pools** — a slow dependency cannot starve unrelated features

### Leader Election vs Distributed Lock
- **Distributed Lock**: short-duration exclusive access to a shared resource (milliseconds to seconds)
- **Leader Election**: long-duration exclusive coordinator role (minutes to indefinite); includes heartbeat/renewal and automatic failover

### Read-Write Lock vs Mutex vs Atomic
- **Mutex** (`synchronized`): exclusive for all — correct everywhere; use when writes are as frequent as reads
- **Read-Write Lock**: concurrent reads, exclusive writes — use when reads >> writes
- **Atomic** (`AtomicInteger`): compare-and-swap on a single value — fastest; use for counters, flags, and reference swaps
- **StampedLock**: optimistic reads (no lock acquisition) + pessimistic fallback — use when reads are > 99% and contention is low

---

## Algorithm Comparison: Rate Limiting

| Algorithm | Memory | Burst Handling | Precision | Recommendation |
|-----------|--------|---------------|-----------|----------------|
| Fixed Window Counter | O(1) | 2× burst at boundary | Low | Simple; acceptable for internal quotas |
| Sliding Window Log | O(window size) | Exact | High | Memory-intensive; use for audit/billing |
| Sliding Window Counter | O(1) | ~±10% approximation | Medium | Best balance — production standard |
| Token Bucket | O(1) | Yes, up to capacity | Medium | Industry standard (AWS, Stripe, Nginx) |
| Leaky Bucket | O(queue depth) | Smoothed, no burst | High | Traffic shaping; rate enforcement |

## Pattern Selection Guide

```
RESOURCE MANAGEMENT PROBLEM?
  → Expensive objects to create repeatedly   → Object Pool
  → Inbound request rate needs bounding      → Rate Limiter
  → Exactly one coordinator in cluster       → Leader Election
  → Concurrent reads, rare writes            → Read-Write Lock
```
