# Write-Ahead Log and Storage Internals

## The Core Problem (Start Here)

Your PostgreSQL database is writing a row update. The update touches both an index page and a data page on disk. Your machine loses power between the two writes. When it restarts, the data page has the new value but the index points to the old location. Your database is now corrupt.

This happens because **disk writes are not atomic**. A single logical operation (update a row) requires multiple physical writes. If any write is interrupted, you get a partially-applied state.

```
DANGEROUS (writes without WAL):
  UPDATE users SET name='Alice' WHERE id=1;

  Physical writes:
    1. Write new row data to data page         ← power cut here
    2. Update index entries to point to new row
    3. Update visibility info (MVCC)
    
  After power cut: data page updated, but index still points to old row → corruption
```

The solution: **Write to a log first, apply to data structures second.** The log is append-only and sequential — a partial log write is detectable and safely replayable.

```
SAFE (with WAL):
  1. Write the operation to the WAL log (append-only, sequential) ← this is fast
  2. Acknowledge success to client (data is durable because it's in the log)
  3. Apply to data pages (asynchronously, in background)

  After power cut: replay WAL from last checkpoint → restore exact state → no corruption
```

---

## The WAL Mechanism

### Anatomy of a WAL Record

```
┌─────────────────────────────────────────────────────────┐
│ WAL Record                                              │
│                                                         │
│  LSN (Log Sequence Number): 0/1A3F8C8                  │  ← unique monotone ID
│  Transaction ID: 12345                                   │
│  Record Type: HEAP_HOT_UPDATE                           │
│  Target: relation=16385, block=42, offset=8             │  ← which page to modify
│  Old data: [previous row bytes]                         │  ← for UNDO
│  New data: [new row bytes]                              │  ← for REDO
│  Checksum: 0x4A2F                                       │
└─────────────────────────────────────────────────────────┘
```

**LSN (Log Sequence Number):** A monotonically increasing 64-bit integer identifying each WAL record's position in the log. Critical for replication (replicas say "I've applied up to LSN 0/1A3F8C8, give me what comes next").

### Write Path (PostgreSQL)

```
Client: UPDATE users SET name='Alice' WHERE id=1

1. Generate WAL record for the update
2. Acquire WAL write lock (brief)
3. Copy WAL record to WAL buffer in shared memory
4. Release WAL write lock
5. [If synchronous_commit=on] Call fsync() to flush WAL buffer to disk
6. Return success to client

Background WAL writer:
  - Periodically flushes WAL buffer to disk segments (not on every write)
  - Checkpoint process: periodically writes dirty data pages to disk, records checkpoint LSN

Recovery after crash:
  1. Read last checkpoint LSN from pg_control
  2. Replay WAL records from checkpoint LSN to end of log
  3. All operations from committed transactions are re-applied
  4. Uncommitted transactions are ignored (or rolled back via UNDO records)
```

### WAL Durability Knobs (PostgreSQL)

```ini
# postgresql.conf
synchronous_commit = on        # fsync WAL on every commit (durable, slower)
synchronous_commit = off       # async commit (faster, risk of losing last ~200ms of commits on crash)
synchronous_commit = remote_write  # wait for replica to receive but not fsync (between sync/async)

wal_level = minimal            # minimal logging (no replication possible)
wal_level = replica            # supports streaming replication (default)
wal_level = logical            # supports logical decoding (CDC, publication/subscription)

checkpoint_timeout = 5min      # how often to write dirty pages to disk
max_wal_size = 1GB             # max WAL size before triggering checkpoint
wal_segment_size = 16MB        # size of each WAL segment file (individual file on disk)
```

**`synchronous_commit = off` trade-off:**
- Speed: writes ~3× faster (no fsync on each commit)
- Risk: crash can lose last ~200ms of committed transactions (transactions *were* committed, just not fsynced yet)
- Not corruption: WAL is still written, just not flushed; on recovery, only flushed records are replayed
- Use case: acceptable for analytics writes, logging, metrics — not for financial data

---

## WAL as Replication Mechanism

This is one of the most important insights in distributed systems: **the WAL is also the replication log**.

```
Primary (PostgreSQL):
  WAL: [record1][record2][record3][record4][record5]...
                                            │
                                            │ streaming (TCP)
                                            ▼
  Replica (PostgreSQL):
  WAL: [record1][record2][record3][record4][record5]...
       Applied to data pages in order → exact replica of primary
```

### Streaming Replication Flow

```
Primary: WAL writer creates segment files: 000000010000000000000001
                                                     │
                                           wal sender process
                                                     │ TCP streaming
                                                     ▼
Replica:                                   wal receiver process
                                                     │
                                           Recovery/replay process
                                                     │
                                           Data pages on replica disk
```

**Replica reports back:**
- `write_lsn`: LSN written to replica's WAL (in memory)
- `flush_lsn`: LSN flushed to replica's disk
- `replay_lsn`: LSN applied to replica's data pages

Primary uses `replay_lsn` to determine replication lag. `pg_stat_replication` view shows per-replica lag.

### Logical Replication vs Physical Replication

| | Physical Replication | Logical Replication |
|---|---|---|
| What's sent | Raw WAL bytes (page-level changes) | Logical changes (row-level: INSERT/UPDATE/DELETE) |
| Schema match required | Yes (exact byte-for-byte) | No (tables can differ) |
| Cross-version | No | Yes (PostgreSQL 10+ → 11+) |
| Selective tables | No (entire cluster) | Yes (per table/publication) |
| CDC (Debezium) | No | Yes (read from replication slot) |
| Use case | Hot standby, HA | Data integration, zero-downtime migration, CDC |

**Replication slots:**
```sql
-- Create logical replication slot (Debezium uses this for CDC)
SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- This causes PostgreSQL to retain WAL segments until the slot consumer reads them
-- WARNING: If consumer stops, WAL accumulates → disk full!
-- Monitor: SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn))
--          FROM pg_replication_slots;
```

---

## MySQL Binary Log (binlog)

MySQL's equivalent of PostgreSQL WAL. Key differences:

```
PostgreSQL WAL:               MySQL binlog:
  Physical (page-level)         Logical (statement or row-level)
  REDO/UNDO combined            Append-only (no UNDO — UNDO is in InnoDB's redo log)
  Single log                    Two separate logs: InnoDB redo log + MySQL binlog

MySQL write path (simplified):
  1. InnoDB redo log: physical changes for crash recovery (WAL)
  2. InnoDB applies to buffer pool (in-memory pages)
  3. MySQL binlog: logical row changes for replication

Two-phase commit in MySQL:
  1. Write to InnoDB redo log (prepared state)
  2. Write to binlog
  3. Commit InnoDB redo log
  → If crash between step 1 and 3: recovery uses binlog to determine commit state
```

MySQL binlog formats:
- **STATEMENT**: logs SQL statements (smaller, but non-deterministic statements are dangerous)
- **ROW**: logs before/after images of each row (larger, always correct)
- **MIXED**: statement by default, row when non-deterministic

---

## The Log as a Universal Primitive

### Jay Kreps: "The Log: What every software engineer should know"

Jay Kreps (Kafka co-creator) articulated that the **append-only log is the unifying primitive** for distributed systems. Everything is a log:

```
Database WAL → log of state changes for recovery
Replication log → log of changes shipped to replicas
Kafka topic → distributed log for event streaming
ZooKeeper ZAB → replicated log for consensus
Raft log → replicated log entries for state machine replication
Event sourcing → log of domain events as primary source of truth
```

**The central insight:** A log defines a total ordering of events. If two replicas consume the same log in the same order, they will arrive at the same state. This is the foundation of log-based replication.

```
Log position 0: INSERT user(id=1, name='Alice')
Log position 1: UPDATE user(id=1, name='Alice Smith')
Log position 2: DELETE user(id=2)

Replica A: reads positions 0, 1, 2 → state: {user 1: 'Alice Smith'}
Replica B: reads positions 0, 1, 2 → state: {user 1: 'Alice Smith'}

Both replicas agree ← because they consumed the same log in the same order.
```

---

## LSM Tree: WAL + MemTable + SSTable

The Log-Structured Merge tree uses the WAL as an integral component:

```
Write path:
  1. Write to WAL (for durability) ← sequential disk write, very fast
  2. Write to MemTable (in-memory sorted data structure, usually a skip list)
  3. Return success to client

  (WAL + MemTable together are the "durable in-memory store")

  When MemTable reaches size threshold (~64MB in RocksDB):
  4. Freeze MemTable → become Immutable MemTable
  5. Flush Immutable MemTable to disk as Level-0 SSTable file
  6. Discard WAL records up to the flushed LSN

Background compaction:
  7. Merge smaller SSTables into larger ones (eliminate tombstones, merge duplicates)
  8. Produces new SSTable, deletes old ones

Read path:
  1. Check MemTable (most recent data)
  2. Check each SSTable level, newest first
  3. Use Bloom filter per SSTable to skip files that don't contain the key
  4. Binary search within SSTable block index to find correct block
  5. Read and decompress block, find key

                 ┌─────────────────────────────────┐
  Write ────────►│ WAL (disk, sequential)           │
                 └─────────────────────────────────┘
                 ┌─────────────────────────────────┐
  Write ────────►│ MemTable (memory, sorted)        │
                 └──────────┬──────────────────────┘
                            │ flush when full
                            ▼
                 ┌─────────────────────────────────┐
                 │ Level 0 SSTables (disk)          │ ← 4–8 files, unordered ranges
                 └──────────┬──────────────────────┘
                            │ compact
                            ▼
                 ┌─────────────────────────────────┐
                 │ Level 1 SSTables (disk)          │ ← 10× size, non-overlapping ranges
                 └──────────┬──────────────────────┘
                            │ compact
                            ▼
                 ┌─────────────────────────────────┐
                 │ Level N SSTables (disk)          │ ← 10× per level
                 └─────────────────────────────────┘
```

**Why WAL is essential for LSM trees:**
- MemTable is in memory — power loss destroys it
- WAL records survive power loss
- On recovery: read WAL since last flush → replay into fresh MemTable → online

**Compaction strategies:**
| | Leveled Compaction | Tiered (Size-Tiered) Compaction |
|---|---|---|
| Read amplification | Low (~10 files touched per read) | High (many overlapping files) |
| Write amplification | High (data rewritten many times) | Low |
| Space amplification | Low | High (tombstones + duplicates retained longer) |
| Use case | Read-heavy workloads (HBase, default RocksDB) | Write-heavy workloads (Cassandra STCS) |

---

## Kafka as a Distributed Commit Log

Kafka is fundamentally an **immutable, append-only, distributed log**:

```
Kafka topic partition = a log file on disk

Producer appends to tail:
  log: [msg0][msg1][msg2][msg3][msg4]
                                  ↑ append here

Consumer reads from any offset:
  Consumer group A: offset=0 → reads all messages
  Consumer group B: offset=3 → reads from msg3 onwards
  Multiple consumers can read same log independently (unlike traditional queues)
```

**Kafka segment files:**
```
Partition directory: /data/kafka/my-topic-0/
  00000000000000000000.log     ← messages 0–999999 (data)
  00000000000000000000.index   ← sparse index: (relative_offset → file_position)
  00000000000000000000.timeindex ← sparse index: (timestamp → offset)
  00000000000001000000.log     ← messages 1000000–1999999
  ...
```

**Log retention:**
- **Time-based:** `log.retention.hours=168` (7 days default) — delete segments older than N
- **Size-based:** `log.retention.bytes` — delete oldest segments when total size exceeded
- **Compaction:** `cleanup.policy=compact` — retain only the latest value per key (like a KV store)

**Log compaction:**
```
Before compaction:
  [k=user:1, name=Alice] [k=user:2, name=Bob] [k=user:1, name=AliceS] [k=user:2, deleted]

After compaction:
  [k=user:1, name=AliceS] [k=user:2, tombstone (null value)]

  → All consumer groups that haven't read the old user:1 record get the latest state
  → Tombstones eventually deleted after configurable retention
```

This makes Kafka suitable as a **changelog store for event-sourced systems**: the compacted log is effectively a table of current state.

---

## WAL in Distributed Replication (Cross-System)

### Debezium: Database WAL → Event Stream

```
PostgreSQL WAL
    │
    │ logical replication slot (pg_recvlogical)
    ▼
Debezium Connector (Kafka Connect)
    │ reads WAL change events
    │ converts to Kafka records with schema (Avro/JSON)
    ▼
Kafka topic: my.public.users
    │ change events: {before: {name: "Alice"}, after: {name: "Alice Smith"}, op: "u"}
    ▼
Downstream consumers: search index, cache invalidation, analytics, audit log
```

**This is the Outbox pattern enabler** (see `idempotency-and-exactly-once.md`): Debezium reads the outbox table from the WAL and publishes to Kafka, guaranteeing no event is missed.

---

## WAL in RAFT

Raft's replicated log is structurally identical to a WAL:

```
Leader's log:
  index=1: [term=1, op: SET x=1]
  index=2: [term=1, op: SET y=2]
  index=3: [term=2, op: SET x=5]

Follower's log (after replication):
  index=1: [term=1, op: SET x=1]
  index=2: [term=1, op: SET y=2]
  index=3: [term=2, op: SET x=5]  ← committed when majority have this entry
```

The leader appends to its log, replicates to followers, and commits once a majority ACKs. State machine applies committed entries. This is identical to WAL-based crash recovery, except the "crash" is a leader failure and the "recovery" is a new leader replaying the log.

---

## Performance Numbers

| Operation | Typical Latency | Why |
|---|---|---|
| WAL append (no fsync) | 0.01–0.1ms | Sequential write to memory buffer |
| WAL fsync (SSD) | 0.1–1ms | SSD flush |
| WAL fsync (HDD) | 5–20ms | HDD seeks |
| MemTable write | 0.01ms | DRAM |
| SSTable read (cached) | 0.1–1ms | OS page cache |
| SSTable read (uncached) | 1–10ms | SSD random read |
| PostgreSQL INSERT (fsync on) | 1–5ms | Mostly WAL fsync time |
| Kafka produce (acks=1) | 1–5ms | Network + leader disk |
| Kafka produce (acks=all, ISR=3) | 5–20ms | Replication to all in-sync replicas |

---

## Cross-References

- [replication-patterns.md](./replication-patterns.md) — WAL-based streaming replication
- [idempotency-and-exactly-once.md](./idempotency-and-exactly-once.md) — Outbox pattern with Debezium + WAL
- [distributed-transactions.md](./distributed-transactions.md) — Two-phase commit and WAL interactions
- `technologies/kafka/` — Kafka internals including segment files and log compaction
- `technologies/cassandra/02-read-write-path.md` — LSM tree in Cassandra (MemTable + SSTable)

---

## FAANG Interview Application

**Likely questions:**
- "How does a database survive a power outage without losing committed data?"
- "What is write-ahead logging? Walk me through how PostgreSQL uses it."
- "How does Kafka replication work? What guarantees does it provide?"
- "What is an LSM tree? How is it different from a B-tree for writes?"
- "How does Debezium work? Why is it better than application-level dual-writes?"

**What interviewers evaluate:**
- Do you understand why WAL is necessary (disk writes are not atomic)?
- Can you trace a write from application → WAL → data page → replica?
- Do you know the trade-off between `synchronous_commit=on` and `off`?
- Can you explain why Kafka is called a "distributed commit log"?

**Principal-level signal:**
> "The WAL is the most important primitive in storage systems. It solves three problems simultaneously: crash recovery (replay the log), replication (ship the log to replicas), and CDC (read the log for change capture). Once you understand that a Kafka topic, a Raft log, a database WAL, and an event-sourced domain event log are all the same abstract structure — an immutable, totally-ordered, append-only sequence of records — the entire landscape of distributed systems snaps into focus. The differences are in what the records contain and who reads them. JAY KREPS' insight was that this unification isn't just aesthetic: you can build the entire Kafka Connect ecosystem (CDC from databases, change streams to search indexes, event sourcing) by treating every system's internal log as a first-class API."
