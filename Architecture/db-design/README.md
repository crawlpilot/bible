# Database Design Patterns

Reference files for database design decisions, locking strategies, and concurrency control — calibrated to principal engineer interviews.

---

## Files in This Folder

| File | Topic |
|---|---|
| [optimistic-locking.md](./optimistic-locking.md) | Version-based conflict detection; CAS; ORM support; retry logic |
| [pessimistic-locking.md](./pessimistic-locking.md) | SELECT FOR UPDATE; shared vs exclusive; deadlock detection; when to commit first |
| [row-level-locking.md](./row-level-locking.md) | Lock granularity; InnoDB gap locks; MVCC vs lock-based; HOT updates in PostgreSQL |

---

## The Core Decision: Optimistic vs Pessimistic

```
Low contention, mostly reads, retries are cheap?
  → Optimistic locking (no locks held; check at commit)

High contention, write-heavy, retry is expensive or unacceptable?
  → Pessimistic locking (hold lock for duration of transaction)

Multiple rows in one transaction, need exclusive access to a range?
  → Pessimistic + row-level locks (SELECT FOR UPDATE with proper indexing)
```

---

## Cross-References

- [Architecture/distributed-systems/consistency-models.md](../distributed-systems/consistency-models.md) — write skew anomaly; isolation levels that require locking
- [Architecture/distributed-systems/distributed-transactions.md](../distributed-systems/distributed-transactions.md) — 2PC, SAGA; when row locking extends across service boundaries
- [Architecture/distributed-systems/partitioning-strategies.md](../distributed-systems/partitioning-strategies.md) — how sharding interacts with cross-shard locking
