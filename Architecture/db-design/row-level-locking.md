# Row-Level Locking

## The Core Problem (Start Here)

Early databases used **table-level locks**: when any transaction wrote to a table, the entire table was locked — every other writer was blocked. An e-commerce site with 1 million products would have every product update serialised through a single queue. Write throughput: catastrophically low.

Row-level locking lets transactions lock *only the specific rows they touch*, so concurrent writes to different rows proceed without any contention:

```
Table-level locking:
  T1 updates product_id=1  → LOCKS THE ENTIRE products TABLE
  T2 updates product_id=2  → BLOCKED (waiting for T1 to finish)
  T3 updates product_id=3  → BLOCKED
  → Throughput: 1 write at a time

Row-level locking:
  T1 updates product_id=1  → locks only row 1
  T2 updates product_id=2  → locks only row 2 (no conflict with T1)
  T3 updates product_id=3  → locks only row 3 (no conflict)
  → Throughput: N writes in parallel, each on different rows
```

But row-level locking introduces subtlety: **index-based locking** (MySQL InnoDB), **gap locks** (prevent phantom inserts), **lock escalation** (too many row locks → table lock), and **MVCC** (PostgreSQL avoids most read locks entirely through versioning).

---

## Lock Granularity Hierarchy

Locks can be held at different granularities. Coarser = more contention, lower overhead. Finer = less contention, higher overhead.

```
COARSEST                                          FINEST
    │                                                │
Database → Schema → Table → Page → Row → Column
    │            │        │      │     │
  Rarely       DDL     Legacy  Mostly Rarely
  used         ops     DBs     used   used
```

### Intention Locks

Before placing a row lock, most databases first place an **intention lock** on the table to signal "I have/will have a lock on a row in this table." This allows a DDL operation (like `ALTER TABLE`) to check if any row-level locks exist without scanning every row.

```
Before T1 gets a row X-lock:
  1. T1 places IX (Intention Exclusive) on the TABLE ← signals "I have X-locks below"
  2. T1 places X-lock on the ROW

DDL operation (ALTER TABLE):
  Needs table S-lock to read structure.
  Sees IX on table → knows row-level X-locks exist → waits.
```

| Intention Lock | Meaning |
|---|---|
| **IS** (Intention Shared) | Transaction intends to place S-locks on rows in this table |
| **IX** (Intention Exclusive) | Transaction intends to place X-locks on rows in this table |
| **SIX** (Shared + Intention Exclusive) | Table S-lock held + intend to X-lock individual rows |

---

## MySQL InnoDB: Row Locking Internals

### How InnoDB Locks Rows

InnoDB is an **index-organized storage engine** — data is stored in the primary key B-tree. **InnoDB locks are placed on index records, not on heap rows**. This has a critical consequence: if your query doesn't use an index, InnoDB must scan and lock many or all index records.

```
Table: inventory (product_id PK, stock INT, category VARCHAR)
Indexes: PRIMARY KEY(product_id), INDEX idx_category(category)

-- Locks ONLY the single primary key record for product_id=42:
SELECT * FROM inventory WHERE product_id = 42 FOR UPDATE;

-- Locks ALL rows in the category 'electronics' index range + gaps:
SELECT * FROM inventory WHERE category = 'electronics' FOR UPDATE;

-- DANGER: no usable index → full scan → locks EVERY row:
SELECT * FROM inventory WHERE stock < 5 FOR UPDATE;
-- (assuming no index on stock)
```

### InnoDB Lock Types

| Lock Type | Description | Used For |
|---|---|---|
| **Record Lock** | Lock on a single index record | Exact match on unique index |
| **Gap Lock** | Lock on gap between index records | Prevent phantom inserts in a range |
| **Next-Key Lock** | Record lock + gap lock on preceding gap | Default for most range queries |
| **Insert Intention Lock** | Special gap lock for INSERT statements | Allow concurrent inserts into the same gap |

### Gap Locks: Preventing Phantom Reads

A **gap lock** locks the space between two index records, preventing other transactions from inserting into that gap.

```
Table: orders (order_id PK)
Existing rows: order_id ∈ {10, 20, 30}

T1: SELECT * FROM orders WHERE order_id BETWEEN 15 AND 25 FOR UPDATE;
    Acquires next-key lock on:
      - Gap (10, 20) ← no rows here, but gap is locked
      - Record lock on row 20
      - Gap (20, 30) ← locked

T2: INSERT INTO orders (order_id) VALUES (18);  ← BLOCKED by gap lock (10,20)
T3: INSERT INTO orders (order_id) VALUES (22);  ← BLOCKED by gap lock (20,30)

This prevents T1 from seeing different rows if it re-runs the range query (phantom read prevention).
```

Gap locks are used in **REPEATABLE READ** (MySQL's default) and **SERIALIZABLE** isolation. They do **not exist in READ COMMITTED** — which is why READ COMMITTED allows phantom reads.

```sql
-- Disable gap locking (use with care — allows phantom reads):
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- or:
SET SESSION innodb_lock_mode = 'record only';  -- no gap locks
```

### Checking InnoDB Locks

```sql
-- Who holds locks:
SELECT * FROM performance_schema.data_locks;
-- or (older MySQL):
SELECT * FROM information_schema.INNODB_LOCKS;

-- Who is waiting:
SELECT * FROM performance_schema.data_lock_waits;

-- Running transactions:
SELECT * FROM information_schema.INNODB_TRX;
```

---

## PostgreSQL: Row Locking with MVCC

### How PostgreSQL Avoids Most Read Locks

PostgreSQL uses **MVCC (Multi-Version Concurrency Control)**. Instead of locking rows for reads, it maintains multiple versions of each row (one per transaction that modified it). Readers always see a consistent snapshot without blocking writers.

```
Row tuple structure in PostgreSQL:
  xmin = transaction ID that created this version
  xmax = transaction ID that deleted/updated this version (0 if current)
  data = actual column values

T1 (txid=100) reads row at T=0:
  Sees the version where xmin <= 100 and (xmax = 0 or xmax > 100)
  → Always gets a consistent snapshot, never blocked by writers

T2 (txid=101) updates the same row simultaneously:
  Creates a NEW tuple version with xmin=101, xmax=0
  Marks OLD tuple version with xmax=101
  → T1 still reads the old version; T2's changes invisible to T1 until T1 re-reads
```

### Row-Level Lock Types in PostgreSQL

| Lock Mode | SQL | Blocks |
|---|---|---|
| `FOR UPDATE` | Exclusive | Other `FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE`, `FOR KEY SHARE` |
| `FOR NO KEY UPDATE` | Almost exclusive | `FOR UPDATE`, `FOR SHARE`; NOT `FOR KEY SHARE` |
| `FOR SHARE` | Shared | `FOR UPDATE`, `FOR NO KEY UPDATE`; NOT `FOR SHARE` or `FOR KEY SHARE` |
| `FOR KEY SHARE` | Weakest shared | Only `FOR UPDATE` |

**Why four levels?** PostgreSQL needs to allow `DELETE` and `UPDATE` to run concurrently with `SELECT FOR KEY SHARE` on foreign key checks — a parent row being referenced via FK should allow child inserts/updates to proceed.

```sql
-- FOR NO KEY UPDATE: same as FOR UPDATE but allows FK references to proceed
SELECT * FROM orders WHERE order_id = 99 FOR NO KEY UPDATE;
-- (Another transaction inserting order_items referencing order_id=99 can proceed)

-- FOR KEY SHARE: very weak; only blocks DELETE/UPDATE of the primary key
SELECT * FROM orders WHERE order_id = 99 FOR KEY SHARE;
-- Use case: "I'm holding a reference to this; don't delete it"
```

### Viewing Row Locks in PostgreSQL

```sql
-- Active row-level locks:
SELECT pid, relation::regclass, mode, granted, transactionid
FROM   pg_locks
WHERE  relation IS NOT NULL;

-- What's blocking what:
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.query AS blocking_query
FROM   pg_stat_activity blocked
JOIN   pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE  cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

### HOT Updates in PostgreSQL

**Heap Only Tuple (HOT)** is PostgreSQL's optimization that avoids updating index entries when non-indexed columns change:

```
Normal UPDATE (non-HOT):
  Old row tuple: xmax = txid
  New row tuple: xmin = txid
  UPDATE all index entries pointing to this row  ← expensive (all indexes touched)

HOT UPDATE (column changed is not in any index):
  Old row tuple: xmax = txid, HOT flag set
  New row tuple: xmin = txid, in same heap page
  Indexes NOT updated  ← just a chain pointer on the heap page
  
  Result: 1/10th the index maintenance cost for updates to non-indexed columns
```

**When HOT fires:** The updated column is not part of any index, AND the new version fits in the same heap page (no page overflow).

**Implication:** Over-indexing a table prevents HOT updates. If every column is indexed, every UPDATE touches every index. Add indexes only when needed for query performance.

---

## Lock Escalation

Lock escalation happens when a transaction holds too many row locks and the database automatically converts them to a table lock. This trades overhead for simplicity — but kills concurrency.

### MySQL InnoDB Lock Escalation

InnoDB does **not** automatically escalate row locks to table locks (unlike SQL Server). However, effectively the same outcome can occur:

- Full table scan with `FOR UPDATE` → every row locked → equivalent to table lock in practice
- `LOCK TABLES table_name WRITE` → explicit table lock (rarely needed in modern code)

**SQL Server** has explicit lock escalation:
```sql
-- Disable lock escalation for a table (useful for high-concurrency tables):
ALTER TABLE inventory SET (LOCK_ESCALATION = DISABLE);
```

### PostgreSQL Lock Escalation

PostgreSQL does not escalate row locks to table locks within a transaction. However, DDL operations (`ALTER TABLE`, `TRUNCATE`, `VACUUM FULL`) acquire table-level `AccessExclusiveLock`, which blocks all other activity.

```sql
-- ALTER TABLE is dangerous on live tables; it acquires AccessExclusiveLock:
ALTER TABLE inventory ADD COLUMN weight FLOAT;
-- This blocks ALL reads and writes to inventory until complete

-- Safe alternative: use pg_repack or logical replication for zero-downtime schema changes
```

---

## MVCC vs Lock-Based Concurrency Control

| | MVCC (PostgreSQL) | Lock-based (MySQL with SERIALIZABLE) |
|---|---|---|
| Read blocks write? | No (readers see snapshot) | Yes (S-lock blocks X-lock) |
| Write blocks read? | No (old version visible to readers) | Yes (X-lock blocks S-lock) |
| Write blocks write? | Yes (X-lock on conflicting rows) | Yes |
| Phantom read prevention | SSI (Serializable Snapshot Isolation) | Gap locks |
| Read-heavy workloads | Excellent (no read locks) | Good |
| Write-heavy workloads | Good (no reader/writer contention) | OK |
| Storage overhead | Higher (multiple row versions) | Lower (single row version) |
| Vacuum required? | Yes (PostgreSQL autovacuum removes dead tuples) | No |

### PostgreSQL SSI (Serializable Snapshot Isolation)

PostgreSQL's `SERIALIZABLE` isolation uses **SSI** — a lock-free mechanism that detects serialization anomalies (write skew, read skew) by tracking read/write dependencies between transactions and aborting transactions that would violate serializability.

```sql
-- Enable SSI:
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  SELECT * FROM inventory WHERE category = 'electronics';  -- read set tracked
  UPDATE inventory SET stock = stock - 1 WHERE product_id = 42;  -- write set tracked
COMMIT;
-- On conflict: ERROR: could not serialize access due to concurrent update
```

MySQL's `SERIALIZABLE` uses **gap locks** instead of SSI — same goal (prevent phantoms and write skew) but via physical locking rather than dependency tracking.

---

## Deadlock Example: InnoDB Gap Locks

Gap locks themselves can deadlock — two transactions each waiting for a gap the other holds:

```
Both T1 and T2 try to insert into the same gap:

T1: INSERT INTO orders (id) VALUES (15);  ← wants to insert into gap (10, 20)
T2: INSERT INTO orders (id) VALUES (17);  ← also wants to insert into gap (10, 20)

Each transaction acquires an Insert Intention Lock on the gap.
Insert Intention Locks are compatible with each other.
Both proceed...

Then T1 also does: DELETE FROM orders WHERE id = 20;
And T2 also does: DELETE FROM orders WHERE id = 20;
Both want X-lock on record 20 → deadlock!
```

**Mitigation:** Avoid overlapping range operations in concurrent transactions. Use `READ COMMITTED` if phantom read prevention is not required (eliminates gap locks).

---

## Row Lock Timeout Configuration

```sql
-- PostgreSQL: statement-level timeout (milliseconds)
SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- MySQL: InnoDB lock wait timeout (seconds, default=50)
SET innodb_lock_wait_timeout = 10;
SET GLOBAL innodb_lock_wait_timeout = 10;

-- Always handle lock timeout errors in application code:
-- PostgreSQL: ERROR: canceling statement due to lock timeout
-- MySQL: ERROR 1205 (HY000): Lock wait timeout exceeded
```

---

## Trade-off Summary

| Dimension | Table-Level | Page-Level | Row-Level |
|---|---|---|---|
| Concurrency | Very low | Low | High |
| Overhead per lock | Low | Low | High (many locks possible) |
| Deadlock risk | Low | Medium | High |
| Lock escalation | N/A | N/A | Possible (SQL Server) |
| Supported by | Legacy DBs | Some DBs | MySQL InnoDB, PostgreSQL, Oracle, SQL Server |
| Use case | DDL, OLAP bulk loads | Mostly historical | OLTP, any modern workload |

---

## When to Use / When Not to Use Row-Level Locking Explicitly

### Use Explicit Row Locks (`FOR UPDATE`) When:
- **Read-modify-write on a specific row** — must guarantee no change between read and write
- **Job queues** — `FOR UPDATE SKIP LOCKED` for parallel job workers
- **Reservation systems** — "hold this seat while user pays"
- **Short, bounded transactions** — milliseconds; predictable lock hold time

### Don't Use Explicit Row Locks When:
- **Read-only queries** — PostgreSQL MVCC means `SELECT` never blocks; `FOR SHARE` is rarely needed
- **Large range queries** — locking thousands of rows serialises all concurrent access to those rows
- **Cross-service transactions** — a row lock doesn't span microservices
- **Long user-facing operations** — lock held for seconds while a human interacts with the UI

---

## FAANG Interview Application

**Likely questions:**
- "How does InnoDB implement row-level locking? What is a gap lock?"
- "How does PostgreSQL handle concurrent reads and writes differently from MySQL?"
- "What is MVCC and why is it better for read-heavy workloads?"
- "What causes a deadlock in a database? How do you prevent it?"
- "How would you design a distributed job queue using PostgreSQL?"

**Principal-level signal:**
> "InnoDB row locks are placed on index records, not heap rows — so a `FOR UPDATE` without a usable index escalates to a full scan that locks every row in the table. PostgreSQL avoids this class of problem with MVCC: readers never need locks because they always see their snapshot version, so `FOR UPDATE` is only needed when you're doing a read-modify-write and need to prevent concurrent modifications. Gap locks in InnoDB are important to understand for range queries: they prevent phantoms but can cause deadlocks when two transactions try to insert into the same gap. If I'm designing a high-throughput write system, I'd choose `READ COMMITTED` to eliminate gap locks and accept that phantom reads are prevented at the application layer instead."

---

## Cross-References

- [optimistic-locking.md](./optimistic-locking.md) — application-level conflict detection as an alternative to row locks
- [pessimistic-locking.md](./pessimistic-locking.md) — `SELECT FOR UPDATE` usage; SKIP LOCKED job queue pattern; deadlock handling
- [Architecture/distributed-systems/consistency-models.md](../distributed-systems/consistency-models.md) — isolation levels (READ COMMITTED, REPEATABLE READ, SERIALIZABLE) and how row locking enforces them
- [Architecture/distributed-systems/write-ahead-log-and-storage-internals.md](../distributed-systems/write-ahead-log-and-storage-internals.md) — MVCC tuple versioning and how PostgreSQL stores row versions in heap pages
