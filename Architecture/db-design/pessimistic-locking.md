# Pessimistic Locking

## The Core Problem (Start Here)

You're transferring money: debit account A by $500, credit account B by $500. Between your read of account A's balance ($1000) and your write ($500), another transaction reads A and initiates a concurrent debit for $800. Without locking, both transactions see balance=$1000, both succeed, and the account ends up at -$300 instead of $200.

The optimistic approach (version check at commit) doesn't work here because by the time you detect the conflict, the damage is potential — and the retry is complex. You need **exclusive access from the moment you read the balance until you commit the transfer**.

That's pessimistic locking: **acquire a lock before you read, hold it through your entire transaction, release only on commit/rollback**. Nobody else can read or write the locked rows until you're done.

```
WITHOUT pessimistic locking (lost update):
  T1 reads A.balance = $1000
  T2 reads A.balance = $1000
  T1 writes A.balance = $500  (debits $500)
  T2 writes A.balance = $200  (debits $800 from the $1000 it read)
  Result: A.balance = $200  ← T1's debit silently lost

WITH pessimistic locking:
  T1: SELECT balance FROM accounts WHERE id=A FOR UPDATE;  ← acquires exclusive lock
  T2: SELECT balance FROM accounts WHERE id=A FOR UPDATE;  ← BLOCKED (waiting for T1)
  T1: UPDATE accounts SET balance = 500 WHERE id=A;
  T1: COMMIT;  ← lock released
  T2: unblocks, reads balance=$500, applies its $800 debit → detects insufficient funds
  Result: correct; T2 gets a clean error
```

---

## Lock Types

### Exclusive Lock (X-Lock / Write Lock)

`SELECT ... FOR UPDATE` — acquires an exclusive lock. **No other transaction can read (in locking reads) or write the row** until the lock is released.

```sql
BEGIN;
  SELECT balance FROM accounts WHERE id = 42 FOR UPDATE;
  -- Row is now X-locked. Any other FOR UPDATE or FOR SHARE on this row BLOCKS.
  UPDATE accounts SET balance = balance - 500 WHERE id = 42;
COMMIT;  -- lock released
```

### Shared Lock (S-Lock / Read Lock)

`SELECT ... FOR SHARE` (PostgreSQL, MySQL 8.0+) — acquires a shared lock. **Multiple transactions can hold shared locks simultaneously**, but an exclusive lock blocks until all shared locks are released.

```sql
BEGIN;
  SELECT * FROM orders WHERE order_id = 99 FOR SHARE;
  -- Other transactions can also FOR SHARE this row.
  -- But FOR UPDATE on this row will BLOCK until all shared locks are released.
  -- Use case: read data that mustn't be modified while you compute something.
COMMIT;
```

### Lock Compatibility Matrix

|  | No Lock | S-Lock (FOR SHARE) | X-Lock (FOR UPDATE) |
|---|---|---|---|
| **No Lock** | ✅ Compatible | ✅ Compatible | ✅ Compatible |
| **S-Lock** | ✅ Compatible | ✅ Compatible | ❌ Blocks |
| **X-Lock** | ✅ Compatible | ❌ Blocks | ❌ Blocks |

*Normal SELECTs (without FOR UPDATE/FOR SHARE) don't acquire locks in PostgreSQL (MVCC) or MySQL InnoDB (MVCC). They always succeed immediately.*

---

## `SELECT FOR UPDATE` in Different Databases

### PostgreSQL

```sql
-- Basic exclusive lock
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE;

-- Skip locked rows (non-blocking scan — useful for job queues)
SELECT * FROM jobs WHERE status = 'pending' LIMIT 1 FOR UPDATE SKIP LOCKED;

-- Nowait — fail immediately instead of blocking
SELECT * FROM accounts WHERE id = 42 FOR UPDATE NOWAIT;
-- Raises: ERROR: could not obtain lock on row in relation "accounts"

-- Lock multiple tables
SELECT i.*, p.name
FROM   inventory i
JOIN   products p ON p.id = i.product_id
WHERE  i.product_id = 42
FOR UPDATE OF i;  -- only lock the inventory row, not the products row
```

### MySQL / InnoDB

```sql
-- Basic exclusive lock
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE;

-- Shared lock (MySQL 8.0+)
SELECT * FROM inventory WHERE product_id = 42 FOR SHARE;
-- Legacy syntax: LOCK IN SHARE MODE

-- Skip locked (MySQL 8.0+)
SELECT * FROM jobs WHERE status = 'pending' LIMIT 1 FOR UPDATE SKIP LOCKED;

-- NOWAIT (MySQL 8.0+)
SELECT * FROM accounts WHERE id = 42 FOR UPDATE NOWAIT;
-- Raises: ERROR 3572: Statement aborted because lock(s) could not be acquired immediately
```

**Critical MySQL caveat:** `FOR UPDATE` in MySQL locks **index records, not just rows**. If your WHERE clause doesn't use an index, MySQL locks the entire table via a table lock or locks all rows via a full index scan. Always confirm your query uses an index before using `FOR UPDATE` in production.

```sql
-- DANGEROUS: product_name is not indexed → full table scan → locks ALL rows
SELECT * FROM inventory WHERE product_name = 'Widget' FOR UPDATE;

-- SAFE: product_id is a primary key → single row lock
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE;

EXPLAIN SELECT * FROM inventory WHERE product_name = 'Widget' FOR UPDATE;
-- Check: type = 'ALL' (full table scan) means all rows will be locked
```

### Oracle

```sql
-- Exclusive lock
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE;

-- With NOWAIT
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE NOWAIT;

-- Wait up to N seconds
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE WAIT 5;
```

### SQL Server

```sql
-- Exclusive lock (using table hints)
SELECT * FROM inventory WITH (UPDLOCK, ROWLOCK) WHERE product_id = 42;

-- Or as part of a transaction:
BEGIN TRANSACTION;
  SELECT * FROM inventory WITH (XLOCK, ROWLOCK) WHERE product_id = 42;
  UPDATE inventory SET stock = stock - 1 WHERE product_id = 42;
COMMIT;
```

---

## SKIP LOCKED: The Job Queue Pattern

`SKIP LOCKED` is one of the most powerful pessimistic locking patterns for distributed job queues:

```sql
-- Worker process (multiple workers running concurrently):
BEGIN;
  SELECT id, payload
  FROM   jobs
  WHERE  status = 'pending'
  ORDER  BY created_at
  LIMIT  1
  FOR UPDATE SKIP LOCKED;      -- grab the first row not locked by another worker

  -- Process the job...
  UPDATE jobs SET status = 'done' WHERE id = ?;
COMMIT;
```

Without `SKIP LOCKED`: all N workers block on the same row, serializing throughput to a single-threaded queue.

With `SKIP LOCKED`: each worker gets its own row immediately — N workers process N jobs in parallel with zero contention.

**Supported in:** PostgreSQL 9.5+, MySQL 8.0+, Oracle 12c+, SQL Server 2005+ (via `READPAST`)

---

## Deadlocks

### What Is a Deadlock

T1 holds lock on row A and waits for row B. T2 holds lock on row B and waits for row A. Neither can proceed — circular wait.

```
T1: LOCK(A) → waiting for LOCK(B)
T2: LOCK(B) → waiting for LOCK(A)
     ↑_______________________________↑ deadlock
```

### How Databases Handle Deadlocks

Both PostgreSQL and MySQL have deadlock detectors that run periodically:
- Detection: look for cycles in the lock-wait graph
- Resolution: pick one transaction as the "victim" and rollback it
- The other transaction proceeds

```
PostgreSQL error:
  ERROR:  deadlock detected
  DETAIL: Process 1234 waits for ShareLock on transaction 5678;
          blocked by process 5678.
          Process 5678 waits for ShareLock on transaction 1234;
          blocked by process 1234.
  HINT:  See server log for query details.

MySQL error:
  ERROR 1213 (40001): Deadlock found when trying to get lock;
  try restarting transaction
```

Your application must catch the deadlock error and **retry the entire transaction**:

```python
from psycopg2 import OperationalError
import time, random

def transfer_funds(from_id: int, to_id: int, amount: float, max_retries: int = 3):
    for attempt in range(max_retries):
        try:
            with db.transaction():
                # Always lock in a consistent order (low ID first) to avoid deadlock
                low_id, high_id = sorted([from_id, to_id])
                db.execute("SELECT * FROM accounts WHERE id = %s FOR UPDATE", [low_id])
                db.execute("SELECT * FROM accounts WHERE id = %s FOR UPDATE", [high_id])

                from_acc = db.fetchone("SELECT balance FROM accounts WHERE id = %s", [from_id])
                if from_acc.balance < amount:
                    raise InsufficientFundsError()

                db.execute("UPDATE accounts SET balance = balance - %s WHERE id = %s", [amount, from_id])
                db.execute("UPDATE accounts SET balance = balance + %s WHERE id = %s", [amount, to_id])
                return  # success

        except OperationalError as e:
            if "deadlock" in str(e).lower() and attempt < max_retries - 1:
                time.sleep(random.uniform(0.01, 0.1))  # backoff before retry
                continue
            raise
```

### Deadlock Prevention: Lock Ordering

**The single most effective deadlock prevention technique:** always acquire locks in the same global order.

```
BAD (deadlock-prone):
  T1: locks account 100, then locks account 200
  T2: locks account 200, then locks account 100
  → T1 waits for T2; T2 waits for T1 → deadlock

GOOD (consistent ordering):
  T1: locks min(100,200)=100 first, then 200
  T2: locks min(200,100)=100 first (waits for T1), then 200
  → T2 waits for T1 to finish; no deadlock
```

### Lock Timeout

Don't wait forever. Configure a lock timeout:

```sql
-- PostgreSQL: set for current session
SET lock_timeout = '5s';

-- PostgreSQL: set for single statement  
SET LOCAL lock_timeout = '2s';

-- MySQL: set for current session (seconds)
SET innodb_lock_wait_timeout = 5;

-- Application-level: use NOWAIT and retry with backoff
SELECT * FROM accounts WHERE id = 42 FOR UPDATE NOWAIT;
-- On exception: retry after backoff
```

---

## Pessimistic Lock Duration: Keep Transactions Short

Every millisecond a pessimistic lock is held, other transactions wait. The primary performance rule:

**Acquire the lock as late as possible. Release (COMMIT) as early as possible.**

```
BAD: hold lock during external API call
  BEGIN;
    SELECT balance FROM accounts WHERE id=42 FOR UPDATE;  ← lock acquired
    response = call_fraud_detection_api(...)               ← 200ms external call
    UPDATE accounts SET balance = ...;                     ← lock released only here
  COMMIT;
  -- The fraud API call is 200ms. During that time, ALL other transactions on
  -- account 42 are blocked. At 1000 TPS, this is catastrophic.

GOOD: lock only for the critical section
  fraud_ok = call_fraud_detection_api(...)      ← external call outside transaction

  BEGIN;
    SELECT balance FROM accounts WHERE id=42 FOR UPDATE;  ← lock acquired
    if fraud_ok and balance >= amount:
      UPDATE accounts SET balance = balance - amount;
  COMMIT;                                                   ← lock released
  -- Lock held for ~1ms (just the DB operations). Much better.
```

---

## Advisory Locks

PostgreSQL provides **advisory locks** — named locks not tied to any specific row or table. Useful for coordinating across processes without involving a specific DB row.

```sql
-- Acquire an advisory lock by integer key (any integer you choose)
-- pg_try_advisory_lock: non-blocking; returns false if lock held
SELECT pg_try_advisory_lock(12345);    -- application-defined key

-- pg_advisory_lock: blocking; waits until acquired
SELECT pg_advisory_lock(12345);

-- Release:
SELECT pg_advisory_unlock(12345);

-- Session-level (released on session close) vs transaction-level:
SELECT pg_try_advisory_xact_lock(12345);  -- auto-released on COMMIT/ROLLBACK
```

**Use case:** "Only one instance of a batch job runs at a time":

```python
def run_batch_job():
    JOB_LOCK_ID = 1001  # arbitrary stable integer

    with db.connection() as conn:
        acquired = conn.execute(
            "SELECT pg_try_advisory_lock(%s)", [JOB_LOCK_ID]
        ).scalar()

        if not acquired:
            logger.info("Another instance is already running; skipping.")
            return

        try:
            execute_batch_job()
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", [JOB_LOCK_ID])
```

MySQL equivalent: `GET_LOCK('job_name', timeout)` / `RELEASE_LOCK('job_name')`.

---

## Trade-off Analysis

### Advantages

| Advantage | Explanation |
|---|---|
| **Conflict-free execution** | Lock holder is guaranteed to succeed; no retries needed |
| **Correct for high contention** | Serialises competing writers; no retry amplification |
| **Prevents read-modify-write races** | The lock is held from READ to WRITE; race impossible |
| **Predictable latency** | Each transaction waits its turn; no retry jitter |
| **Works for complex multi-row operations** | Lock multiple rows; entire operation is atomic and serialised |

### Disadvantages

| Disadvantage | Explanation |
|---|---|
| **Reduced concurrency** | Writers block all other writers (and sometimes readers) |
| **Deadlock risk** | Requires careful lock ordering; deadlock detection adds overhead |
| **Lock duration = latency** | Long transactions holding locks degrade the whole system |
| **Not suitable for distributed systems** | A `FOR UPDATE` lock is local to one database; doesn't span services |
| **Hot rows = bottleneck** | All writes to the same row serialise; throughput capped at 1/lock_duration |

---

## When to Use / When Not to Use

### Use Pessimistic Locking When:
- **Financial operations** — balance transfers, inventory reservation, ticket booking — correctness is non-negotiable
- **High contention on known hot rows** — auctions (multiple bidders on one item), stock trading
- **Read-modify-write where the value matters** — you must guarantee that what you read is what you write against
- **Short, bounded transactions** — milliseconds, not seconds; the lock hold time is predictable
- **SKIP LOCKED job queues** — guaranteed exactly-one claim of each job across N workers

### Don't Use Pessimistic Locking When:
- **Distributed transactions across microservices** — a DB row lock doesn't span services; use SAGA instead
- **Long user-facing workflows** — "user editing a document for 5 minutes" while holding a lock = unacceptable contention
- **Read-heavy with rare writes** — readers blocked unnecessarily; use MVCC (the default in PostgreSQL/MySQL)
- **Unknown lock order** — if you can't control lock acquisition order, deadlocks become likely at scale
- **Globally distributed data** — row locks don't work across datacenters; use CRDTs or single-region writes

---

## Real-World Examples

| System / Pattern | Pessimistic Locking Use |
|---|---|
| **Bank transfer** | `SELECT FOR UPDATE` on both accounts, in consistent ID order |
| **Ticket booking** (Ticketmaster) | `SELECT seat FOR UPDATE` during checkout; cancel if user doesn't pay in 10 min |
| **Airline seat selection** | Lock row for seat during payment flow |
| **Distributed job queue** | `SELECT FOR UPDATE SKIP LOCKED` in PostgreSQL / MySQL |
| **PostgreSQL advisory locks** | Singleton batch jobs; leader election for background workers |
| **InnoDB gap locks** | Prevent phantom inserts in a range; used in SERIALIZABLE isolation |

---

## FAANG Interview Application

**Likely questions:**
- "How does `SELECT FOR UPDATE` work? When would you use it?"
- "What is a deadlock? How do you detect and prevent it?"
- "Pessimistic vs optimistic locking — how do you decide which to use?"
- "How would you design a distributed job queue that prevents two workers from processing the same job?"

**Principal-level signal:**
> "Pessimistic locking (`SELECT FOR UPDATE`) is the right tool when correctness trumps throughput and transaction duration is short. The classic example is a bank transfer: read-modify-write where any race leads to incorrect balance. The implementation discipline is: always lock in a consistent global order (low account ID first) to prevent deadlocks, configure a lock timeout to prevent indefinite waits, and never hold a lock over an external API call. For job queues, `SKIP LOCKED` is a game-changer — it lets N workers process N jobs in parallel with zero contention, which is exactly what you want from a distributed queue. The failure mode to avoid is long-held locks: a 5-second transaction holding an exclusive row lock will cause cascading timeouts at any meaningful write throughput."

---

## Cross-References

- [optimistic-locking.md](./optimistic-locking.md) — version-based conflict detection; when to prefer optimistic
- [row-level-locking.md](./row-level-locking.md) — how InnoDB and PostgreSQL implement row-level locks; gap locks; lock escalation
- [Architecture/distributed-systems/consistency-models.md](../distributed-systems/consistency-models.md) — serializable isolation (which requires pessimistic or SSI); write skew anomaly
- [Architecture/distributed-systems/distributed-transactions.md](../distributed-systems/distributed-transactions.md) — what to do when pessimistic locks must span multiple services (SAGA)
- [Architecture/distributed-systems/distributed-locking-and-coordination.md](../distributed-systems/distributed-locking-and-coordination.md) — distributed locks across services (ZooKeeper, etcd) for cross-service pessimistic coordination
