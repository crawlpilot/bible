# Optimistic Locking

## The Core Problem (Start Here)

An e-commerce site sells the last pair of shoes in size 9. Two customers open the product page at the same time. Both see `stock = 1`. Both click "Add to Cart". Both proceed to checkout. Both get an order confirmation. The warehouse ships to Customer A. Customer B's order can't be fulfilled — but they already paid.

With **pessimistic locking**, you'd hold a database lock on that stock row from the moment the customer views it until they complete checkout — potentially minutes. Nobody else can buy shoes during that time. That kills throughput.

With **optimistic locking**, you don't hold any lock. Instead, when Customer B tries to update `stock = 0`, the database checks: "has this row changed since B read it?" It has — Customer A already decremented it. B's update is rejected. B retries and sees `stock = 0`, gets a "sold out" message.

```
WITHOUT optimistic locking (lost update anomaly):
  Customer A reads: stock=1
  Customer B reads: stock=1
  Customer A writes: stock=0  ← succeeds
  Customer B writes: stock=0  ← also succeeds (should have failed!)
  Result: -1 effective stock, two orders for 1 item

WITH optimistic locking (version check):
  Customer A reads: stock=1, version=7
  Customer B reads: stock=1, version=7
  Customer A writes: UPDATE SET stock=0, version=8 WHERE version=7 → 1 row updated ✓
  Customer B writes: UPDATE SET stock=0, version=8 WHERE version=7 → 0 rows updated ✗
  Customer B: retry → sees stock=0, version=8 → "sold out"
```

---

## How Optimistic Locking Works

Optimistic locking is **not a database lock** — it is an **application-level concurrency control technique** that works by detecting conflicts at write time rather than preventing them at read time.

The key insight: **conflicts are rare** (optimistic assumption). Don't pay the cost of locking for every read; only pay for conflict detection on write.

### The Version Column Pattern

Add a `version` (or `updated_at` timestamp) column to every row you need to protect:

```sql
CREATE TABLE inventory (
    product_id  BIGINT PRIMARY KEY,
    stock       INT NOT NULL,
    version     INT NOT NULL DEFAULT 0
);
```

**Read:**
```sql
SELECT product_id, stock, version
FROM inventory
WHERE product_id = 42;
-- Returns: product_id=42, stock=1, version=7
```

**Write (optimistic update):**
```sql
UPDATE inventory
SET    stock   = stock - 1,
       version = version + 1        -- increment version atomically with the write
WHERE  product_id = 42
AND    version    = 7;               -- the version we read; reject if someone else changed it

-- Check affected rows:
-- rows_affected = 1 → success, no conflict
-- rows_affected = 0 → conflict, someone else updated first → retry or fail
```

**Why `rows_affected = 0` means conflict:** The `AND version = 7` clause is the guard. If another transaction incremented the version between your read and write, the WHERE clause matches zero rows.

### The Timestamp Variant

Instead of an integer version, use `updated_at`:

```sql
UPDATE orders
SET    status     = 'shipped',
       updated_at = NOW()
WHERE  order_id   = 123
AND    updated_at = '2026-06-09 10:00:00.123456';
```

**Danger:** Timestamp-based optimistic locking requires sub-millisecond precision (`TIMESTAMP(6)` in MySQL, `TIMESTAMPTZ` in PostgreSQL). On systems with low-resolution timestamps, two updates within the same millisecond can both succeed — silent data corruption. **Prefer integer versions**.

### CAS (Compare-And-Swap) Pattern

For simple numeric fields, CAS is optimistic locking without a version column:

```sql
-- Decrement stock only if it's still what we read
UPDATE inventory
SET stock = 9
WHERE product_id = 42
AND   stock      = 10;  -- the value we read; reject if it changed
```

Simple, but fragile: the **ABA problem** — if stock goes from 10 → 9 → 10 between your read and write, your CAS succeeds even though the row changed twice. Version numbers don't have this problem because they only ever increment.

---

## ORM / Framework Support

### JPA / Hibernate (`@Version`)

```java
@Entity
public class Inventory {
    @Id
    private Long productId;

    private int stock;

    @Version
    private int version;  // JPA manages this automatically
}

// Usage:
Inventory inv = em.find(Inventory.class, 42L);  // reads version=7
inv.setStock(inv.getStock() - 1);
em.merge(inv);  // emits: UPDATE inventory SET stock=?, version=8 WHERE product_id=42 AND version=7
                // throws OptimisticLockException if 0 rows updated
```

Hibernate generates the versioned UPDATE automatically. On conflict it throws `jakarta.persistence.OptimisticLockException`.

### Spring Data JPA

```java
@Repository
public interface InventoryRepository extends JpaRepository<Inventory, Long> {}

// Service layer:
@Retryable(value = ObjectOptimisticLockingFailureException.class, maxAttempts = 3)
@Transactional
public void decrementStock(Long productId, int quantity) {
    Inventory inv = inventoryRepository.findById(productId)
        .orElseThrow(() -> new ProductNotFoundException(productId));
    if (inv.getStock() < quantity) throw new InsufficientStockException();
    inv.setStock(inv.getStock() - quantity);
    // save() triggers version check; throws ObjectOptimisticLockingFailureException on conflict
    inventoryRepository.save(inv);
}
```

### SQLAlchemy (Python)

```python
from sqlalchemy import Column, Integer
from sqlalchemy.orm import DeclarativeBase

class Inventory(Base):
    __tablename__ = 'inventory'
    product_id = Column(Integer, primary_key=True)
    stock      = Column(Integer)
    version    = Column(Integer, nullable=False, default=0)

    __mapper_args__ = {
        'version_id_col': version  # SQLAlchemy manages optimistic locking
    }
```

### GORM (Go)

GORM doesn't have native `@Version` support — implement manually:

```go
result := db.Model(&Inventory{}).
    Where("product_id = ? AND version = ?", productID, currentVersion).
    Updates(map[string]interface{}{
        "stock":   gorm.Expr("stock - ?", quantity),
        "version": gorm.Expr("version + 1"),
    })

if result.RowsAffected == 0 {
    return ErrOptimisticLockConflict
}
```

---

## Retry Strategy

Optimistic locking only works if you retry on conflict. Naive retry is dangerous — exponential backoff with jitter prevents thundering herd:

```python
import random, time

def decrement_stock_with_retry(product_id: int, quantity: int, max_retries: int = 5):
    base_delay = 0.05  # 50ms

    for attempt in range(max_retries):
        try:
            return decrement_stock(product_id, quantity)
        except OptimisticLockConflict:
            if attempt == max_retries - 1:
                raise StockUnavailableError("Too many conflicts, please retry later")

            delay = min(base_delay * (2 ** attempt), 1.0)       # cap at 1s
            jitter = random.uniform(0, delay * 0.5)              # ±50% jitter
            time.sleep(delay + jitter)
```

**When NOT to retry blindly:**
- If the conflict means "someone else already took the last unit" → don't retry, show "sold out"
- If retries themselves are expensive (complex reads) → cap retries aggressively

---

## Database Support

Optimistic locking is **application-level** — it works in any database that supports atomic row updates with a WHERE clause. The database has no concept of "optimistic lock"; it just executes the conditional UPDATE.

| Database | Version column type | Rows-affected check |
|---|---|---|
| **PostgreSQL** | `INTEGER` or `BIGINT` (preferred), or `TIMESTAMPTZ(6)` | `cursor.rowcount` (psycopg2), `affected_rows` (JDBC) |
| **MySQL / MariaDB** | `INT` or `BIGINT UNSIGNED`, or `DATETIME(6)` | `ROW_COUNT()`, `getUpdateCount()` |
| **SQLite** | `INTEGER` | `cursor.rowcount` |
| **Oracle** | `NUMBER` or `TIMESTAMP(6)` | `SQL%ROWCOUNT` |
| **SQL Server** | `INT` or `ROWVERSION` (built-in 8-byte version) | `@@ROWCOUNT` |

### SQL Server `ROWVERSION`

SQL Server has a native optimistic lock column — `rowversion` (formerly `timestamp`) — that is automatically incremented by the database on every write, without application involvement:

```sql
CREATE TABLE inventory (
    product_id BIGINT PRIMARY KEY,
    stock      INT NOT NULL,
    row_ver    ROWVERSION NOT NULL  -- auto-updated by SQL Server on every write
);

-- Read:
SELECT product_id, stock, row_ver FROM inventory WHERE product_id = 42;
-- Returns: row_ver = 0x0000000000001234 (binary, 8 bytes)

-- Write:
UPDATE inventory SET stock = stock - 1
WHERE  product_id = 42
AND    row_ver    = 0x0000000000001234;
```

No application code needed to manage the version — SQL Server does it.

---

## Trade-off Analysis

### Advantages

| Advantage | Explanation |
|---|---|
| **No lock contention** | Readers never block writers; writers never block readers |
| **High throughput** | Scales linearly with concurrent readers; ideal for read-heavy workloads |
| **No deadlocks** | Locks are never held across transactions; deadlock is impossible |
| **Works across services** | Version check can span microservices (each service checks version before writing) |
| **Database-agnostic** | Works in any SQL or NoSQL DB that supports conditional writes |

### Disadvantages

| Disadvantage | Explanation |
|---|---|
| **Retry complexity** | Application must implement retry logic; simplistic retries can cause retry storms |
| **High contention = poor performance** | If 100 threads compete for the same row, 99 fail and retry every time → amplifies database load |
| **ABA problem (CAS variant)** | CAS without version numbers can miss intermediate updates |
| **Lost updates on bulk operations** | Updating thousands of rows optimistically and getting a conflict means re-running the entire operation |
| **Not suitable for long-lived operations** | A 5-minute user workflow with optimistic lock: by the time the user submits, the version is stale — frustrating UX |

---

## When to Use / When Not to Use

### Use Optimistic Locking When:
- **Low contention** — most of the time, concurrent writes to the same row are rare
- **Read-heavy, write-occasional** — user profile updates, settings, product catalog
- **Short transactions** — the time between read and write is milliseconds, not seconds/minutes
- **Retry is cheap and acceptable** — re-reading 1 row and re-applying a simple change is trivial
- **Distributed systems / microservices** — version checks work across service boundaries without distributed locks
- **Multi-leader replication** — version column survives async replication and enables conflict detection at application level

### Don't Use Optimistic Locking When:
- **High contention on hot rows** — bank account balance updated by 1000 concurrent transfers → 999 retries per second → database overload. Use pessimistic locking or queue-based serialization.
- **Long-lived user workflows** — "user edits a document for 5 minutes then saves" → version stale, UX nightmare. Use explicit "check out" (pessimistic lock) or CRDT.
- **Multi-row atomicity required** — if you need to update rows A and B consistently, and A succeeds but B conflicts, you've partially applied. Pessimistic locks or full transaction serialization is safer.
- **Idempotency keys** — if you're implementing idempotent payment processing, an optimistic lock race may mean the payment is neither committed nor retried cleanly. See [idempotency-and-exactly-once.md](../distributed-systems/idempotency-and-exactly-once.md).

---

## Performance Characteristics

| Scenario | Optimistic | Pessimistic |
|---|---|---|
| 100 concurrent readers, 1 writer | Excellent (readers not blocked) | Good (readers blocked while writer holds lock) |
| 100 concurrent writers, same row | Poor (99 retries per batch) | OK (99 wait in queue, execute serially) |
| 1000 TPS, 1% conflict rate | Excellent | Good |
| 1000 TPS, 50% conflict rate | Poor (load amplification) | Better (orderly serialization) |
| Cross-service transaction | Works (version propagated) | Hard (distributed lock required) |
| Lock duration | Zero (no locks held) | Duration of transaction |

---

## Real-World Examples

| System | Use of Optimistic Locking |
|---|---|
| **Hibernate/JPA applications** | `@Version` on every entity; retry on `OptimisticLockException` |
| **Stripe API** | Idempotency keys are a form of optimistic conflict detection |
| **GitHub / Git** | Branching + merge conflict is optimistic concurrency at the VCS level |
| **DynamoDB** | `ConditionExpression: attribute_not_exists(version) OR version = :expected` |
| **etcd CAS** | `txn().If(Compare(version, "=", expected)).Then(Put(key, value)).Commit()` |
| **Apache Kafka** | Producer sequence numbers for idempotent delivery (optimistic dedup) |

---

## FAANG Interview Application

**Likely questions:**
- "Two users try to book the last hotel room simultaneously. How do you prevent double booking?"
- "What is optimistic locking? How does it differ from pessimistic locking?"
- "What is the lost update problem? How do you solve it?"
- "When would optimistic locking make things worse, not better?"

**Principal-level signal:**
> "Optimistic locking is the right default for low-contention workloads: it eliminates lock contention and deadlock entirely and scales read throughput linearly. The failure mode is high-contention hot rows — a bank account receiving thousands of concurrent micro-payments would see catastrophic retry amplification with optimistic locking. For that pattern, I'd use a queue-based serialization approach (all updates to account A go through a single consumer) or fall back to `SELECT FOR UPDATE`. The other failure mode is long-lived user workflows: if a user spends 10 minutes editing a document and gets a 'version conflict, please redo your work' error on save, that's a UX disaster. For those, I'd use either an explicit check-out lock (pessimistic) with a TTL, or a CRDT that merges edits instead of rejecting them."

---

## Cross-References

- [pessimistic-locking.md](./pessimistic-locking.md) — `SELECT FOR UPDATE`; when to prefer pessimistic; deadlock handling
- [row-level-locking.md](./row-level-locking.md) — how row-level locks in InnoDB/PostgreSQL interact with optimistic patterns
- [Architecture/distributed-systems/consistency-models.md](../distributed-systems/consistency-models.md) — lost update anomaly; write skew; isolation levels
- [Architecture/distributed-systems/idempotency-and-exactly-once.md](../distributed-systems/idempotency-and-exactly-once.md) — idempotency keys as an alternative concurrency control for payment flows
- [Architecture/distributed-systems/crdts-and-conflict-resolution.md](../distributed-systems/crdts-and-conflict-resolution.md) — CRDT as an alternative to optimistic locking for multi-writer convergence
