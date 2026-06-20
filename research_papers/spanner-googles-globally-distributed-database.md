# Spanner: Google's Globally-Distributed Database — Deep Dive

**Paper:** Spanner: Google's Globally-Distributed Database  
**Authors:** Corbett, Dean, Epstein, Fikes, Frost, Furman, Ghemawat, Gubarev, Heiser, Hochschild, Hsieh, Kanthak, Kogan, Li, Lloyd, Melnik, Mwaura, Nagle, Quinlan, Rao, Rolig, Saito, Szymaniak, Taylor, Wang, Woodford (Google)  
**Published:** OSDI 2012  
**Production use:** Google AdWords, Google Play, Google F1, Google Maps (2012–present)  
**Impact:** Introduced TrueTime — the concept that global serializable transactions are possible without coordination overhead if you can bound clock uncertainty

---

## Why This Paper Matters

Before Spanner, the distributed systems community widely accepted a trade-off: **you can have either global distribution OR strong consistency, not both**. This was the practical interpretation of the CAP theorem and the reason NoSQL databases (Cassandra, DynamoDB) chose eventual consistency.

Spanner broke this assumption in production:
- **Externally consistent (serializable) transactions** across datacenters on different continents
- **SQL queries** across a sharded, globally distributed database
- **Non-blocking reads** at any point in the past
- **Automatic resharding** and replication management

The key insight: **if you can bound clock uncertainty precisely enough, you can use time itself as a synchronization primitive** — eliminating the need for traditional distributed locking for read-only transactions.

Spanner runs Google's most critical global systems. This is not a research prototype.

---

## The Problem Spanner Solves

### Google's Scale (at time of publication)
- Hundreds of datacenters worldwide
- Millions of machines
- AdWords: global ad serving — a transaction that charges an advertiser must be consistent worldwide
- Google Play: purchases must not be applied twice or lost across regions

### Why Existing Options Failed

| Option | Problem for Google |
|--------|-------------------|
| MySQL / Postgres (single DC) | No global distribution, single point of failure |
| Bigtable (Google's NoSQL) | No cross-row transactions, eventual consistency only |
| Megastore (Google internal) | Paxos-based, poor write latency (~100ms+), limited SQL |
| Sharded MySQL | Manual resharding, no cross-shard transactions |
| Cassandra/DynamoDB | Eventual consistency, can't support AdWords billing |

**The need:** A system that behaves like a single global database — ACID transactions, SQL, arbitrary reads and writes — but physically runs across continents with no single point of failure.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                        Universe                          │
│                                                          │
│  ┌─────────────────┐   ┌─────────────────┐               │
│  │   Zone (DC 1)   │   │   Zone (DC 2)   │  ...          │
│  │                 │   │                 │               │
│  │  ┌───────────┐  │   │  ┌───────────┐  │               │
│  │  │Zonemaster │  │   │  │Zonemaster │  │               │
│  │  └─────┬─────┘  │   │  └─────┬─────┘  │               │
│  │        │        │   │        │        │               │
│  │  ┌─────▼──────────────────────▼─────┐  │               │
│  │  │         Spanservers (1000s)      │  │               │
│  │  │  ┌──────────────────────────┐   │  │               │
│  │  │  │  Tablet (key range)      │   │  │               │
│  │  │  │  - Paxos state machine   │   │  │               │
│  │  │  │  - Lock table            │   │  │               │
│  │  │  │  - Transaction manager   │   │  │               │
│  │  │  └──────────────────────────┘   │  │               │
│  │  └──────────────────────────────────┘  │               │
│  └─────────────────┘   └─────────────────┘               │
│                                                          │
│  ┌───────────────────────────────────────────────────┐   │
│  │           Universe Master (monitoring)            │   │
│  └───────────────────────────────────────────────────┘   │
│  ┌───────────────────────────────────────────────────┐   │
│  │           Placement Driver (global resharding)    │   │
│  └───────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### Key Components

**Universe:** A single Spanner deployment (Google runs a handful: test, production)

**Zone:** One deployment of Spanner within a datacenter. The unit of administrative isolation and physical locality. Thousands of spanservers per zone.

**Spanserver:** The workhorse machine. Each spanserver manages 100–1000 tablets.

**Tablet:** A bag of key-value mappings of the form `(key, timestamp) → value`. Not a single key — a range of the key space. The unit of data placement and replication.

**Paxos group:** Each tablet's data is replicated across multiple spanservers (typically 5) using Paxos. One spanserver is the Paxos leader and handles all writes for that tablet.

**Placement Driver:** Moves tablet replicas between zones to maintain placement constraints and balance load. Runs globally.

---

## Data Model

Spanner's data model is hierarchically organized tables — a deliberate design to enable data locality.

### Interleaved Tables

```sql
-- Parent table
CREATE TABLE Users (
  UserId INT64 NOT NULL,
  Name STRING(MAX)
) PRIMARY KEY (UserId);

-- Child table physically interleaved within Users
CREATE TABLE Albums (
  UserId INT64 NOT NULL,
  AlbumId INT64 NOT NULL,
  Title STRING(MAX)
) PRIMARY KEY (UserId, AlbumId),
  INTERLEAVE IN PARENT Users ON DELETE CASCADE;
```

Physical storage layout:

```
Key                         Value
─────────────────────────────────────────────
Users(1)                  → {Name: "Alice"}
Albums(1, 1)              → {Title: "Vacation"}    ← physically adjacent
Albums(1, 2)              → {Title: "Wedding"}     ← physically adjacent
Users(2)                  → {Name: "Bob"}
Albums(2, 1)              → {Title: "Birthday"}    ← physically adjacent
```

**Why interleaving matters:** A query for all albums of a user (the common case) reads a contiguous range of bytes from one tablet — no cross-shard join required. This is locality-aware sharding made declarative.

### Versioned Data (MVCC)

Every cell in Spanner stores **multiple timestamped versions**:

```
(key="alice", col="balance", ts=T1) → 1000
(key="alice", col="balance", ts=T2) → 1200
(key="alice", col="balance", ts=T3) → 950
```

- Writes add a new version at the commit timestamp
- Reads at timestamp T return the latest version ≤ T
- Old versions are garbage collected based on configurable retention (e.g., 1 hour)
- This is the foundation of non-blocking historical reads

---

## The Central Innovation: TrueTime

This is the paper's most important contribution. Everything else — external consistency, non-blocking reads, commit wait — depends on it.

### The Problem: Clocks Lie

In distributed systems, clocks on different machines drift. NTP (Network Time Protocol) synchronizes clocks, but with uncertainty of ~10–100ms depending on network conditions. This means:

- Machine A thinks the time is T
- Machine B thinks the time is T + 15ms
- You cannot determine which event happened "first" purely from timestamps

This is why traditional distributed databases use **Lamport clocks** (logical time) or **vector clocks** — they don't trust wall-clock time.

### TrueTime: Bounded Uncertainty API

Google built a custom time API that, instead of returning a single timestamp, returns an **interval** representing the true current time:

```
TT.now()   → TTinterval {earliest: T_earliest, latest: T_latest}
TT.after(t) → true if t has definitely passed
TT.before(t) → true if t has definitely not arrived
```

The key guarantee: **the true current time is always within [earliest, latest]**.

The interval width (ε) is typically **1–7 milliseconds** at Google, with a 99.9th percentile of ~7ms.

### TrueTime Hardware

Google achieves this with **two independent time references per datacenter**:

1. **GPS receivers** — accurate to nanoseconds but vulnerable to antenna/GPS signal failure
2. **Atomic clocks (oscillators)** — extremely stable but drift ~30μs/s without external reference

Each datacenter has GPS-equipped **time master servers**. Regular spanserver daemons (timeslave) poll multiple masters (both GPS-based and atomic-clock-based) and apply a Marzullo intersection algorithm to produce a conservative uncertainty interval ε.

```
Timeslave daemon polls:
  GPS master A  → [T-2ms, T+2ms]
  GPS master B  → [T-1ms, T+3ms]
  Atomic master → [T-4ms, T+4ms]
  
Conservative interval: [T-1ms, T+3ms]  (intersection approach)
```

If a timeslave loses contact with all masters, ε grows over time (atomic clock drift: ~30μs/s). The daemon raises an alert if ε exceeds a threshold.

---

## External Consistency and Commit Wait

### What is External Consistency?

External consistency is stronger than serializability:

> If transaction T1 commits before transaction T2 begins (in real time), then T1's commit timestamp must be less than T2's commit timestamp.

This means the database's ordering of transactions perfectly reflects real-world causality. No "reading the past" anomalies.

### How Spanner Achieves It: Commit Wait

When a read-write transaction is ready to commit:

1. The Paxos leader acquires the commit timestamp `s` = `TT.now().latest`
   - This guarantees: the real commit time is **at most** `s`

2. The leader **waits** until `TT.after(s)` is true — i.e., until it is certain that `s` is in the past
   - This guarantees: the real commit time is **at least** `s`

3. Only then does it apply the commit and release locks

```
Timeline:
                    s = TT.now().latest
                    │
T_abs (true time):  ───────────────[s-ε ────── s+ε]───────────────►
                                    ↑          ↑
                               commit wait: wait until T_abs > s+ε
                               (TT.after(s) returns true)
```

**The invariant:** The transaction's commit timestamp `s` is guaranteed to be in the past by the time the commit is visible. Any later transaction that starts after this commit gets a higher `TT.now().latest`, so its timestamp will be > `s`.

**Cost:** Commit wait delays the commit by approximately ε ≈ 1–7ms. This is the price of external consistency.

---

## Transaction Types

Spanner supports three distinct transaction types, each with different performance characteristics:

### 1. Read-Write Transactions (Standard ACID)

Used for any transaction that writes data.

**Protocol: Two-Phase Locking + Two-Phase Commit**

```
Phase 1: Lock acquisition
  Client → Coordinator: BEGIN
  For each read: acquire shared lock at the Paxos leader
  For each write: buffer locally (not yet sent to servers)

Phase 2: Prepare
  Client → Coordinator: COMMIT
  Coordinator → Participant Paxos leaders: PREPARE
  Each participant: acquire write locks, log prepare record via Paxos
  Participants → Coordinator: prepared timestamp + ok

Phase 3: Commit
  Coordinator chooses commit timestamp s = max(all prepared timestamps, TT.now().latest)
  Coordinator logs commit via Paxos
  Coordinator: waits until TT.after(s)   ← commit wait
  Coordinator applies writes, releases locks
  Coordinator → Participants: COMMIT with timestamp s
  Participants apply writes with timestamp s
```

**Latency:** ~10–100ms depending on number of participants and geographic span.

**Wound-Wait deadlock prevention:** Older transactions wound (abort) younger ones waiting for their locks.

### 2. Read-Only Transactions (Non-Blocking)

A read-only transaction that reads data at a consistent snapshot. No locks required. No Paxos writes.

**Two modes:**

**a) Strong reads (default):**
- Timestamp: `s = TT.now().latest`
- Wait until `safeTime ≥ s` at the replica (the replica has applied all writes with timestamp ≤ s)
- Executes locally, no lock acquisition, no coordinator, no 2PC
- Reads the latest externally consistent state

**b) Bounded staleness reads:**
- Client specifies: "I'll accept data up to 15 seconds old"
- System picks the closest/cheapest replica that satisfies the staleness bound
- Zero wait in most cases (the replica is already up to date enough)
- Used for analytics, dashboards — much lower latency

**Why non-blocking?** MVCC: old versions are stored. A read at timestamp T never conflicts with concurrent writes (which create new versions at higher timestamps).

### 3. Snapshot Reads (Historical)

Read data as of a specific past timestamp:

```sql
SELECT balance FROM Accounts WHERE AccountId = 123
  AS OF SYSTEM TIME '2024-01-15 12:00:00';
```

- Reads the version of each cell with timestamp ≤ the specified time
- No locks
- Executes at any replica that has data up to that timestamp
- Useful for: auditing, analytics, debugging, time-travel queries

**Retention window:** Default 1 hour. Data before the retention window is garbage collected.

---

## The Paxos Layer

Each tablet's data is replicated using **Multi-Paxos** with a long-lived leader.

### Leader Leases

Rather than running Paxos for every write (which requires a majority quorum for every operation), Spanner uses **timed leader leases** (default 10 seconds):

```
Leader acquires lease by getting votes from a quorum of replicas
Leader can serve reads and writes without re-running Paxos for each one
  (as long as lease is valid)
Lease renewal: leader sends heartbeats before lease expires
```

**Disjointness invariant:** Leases from different leaders must not overlap — enforced using TrueTime. A new leader cannot start serving until it knows the previous leader's lease has expired (using TT.after(lease_expiry)).

### Paxos Write Path

```
Client write → Leader spanserver
  → Log write to Paxos (replicated to majority of replicas)
  → Apply to in-memory tablet state
  → Return to client (once majority acknowledge)
```

Reads from the leader: served from in-memory state (no disk I/O for warm data).

Reads from follower replicas: must wait for `safeTime ≥ read_timestamp` — the replica must have applied all writes up to that timestamp.

---

## Concurrency Control and Timestamps

### The Monotonicity Invariant

The most important correctness property for reads:

> **A Paxos leader must assign timestamps to Paxos writes in monotonically increasing order.**

Why? If the leader assigns timestamp T2 < T1 to a later write, a read at T2 would miss that write while a read at T1 would include it — inconsistency.

**TrueTime enforcement:** The leader only assigns timestamp `s` if `s > TT.now().earliest` of all previous writes. Since TrueTime intervals are disjoint across time, this is guaranteed without communication.

### Safe Time for Followers

A follower replica can serve a read at timestamp T only if it has received and applied all Paxos writes with timestamp ≤ T. The `safeTime` at a replica is computed as:

```
safeTime = min(
  max applied Paxos write timestamp,
  min prepared timestamp across all in-progress transactions
)
```

The second term is critical: a transaction that has prepared (locked) but not yet committed might later commit with a timestamp below T. The follower must wait until all such transactions commit or abort.

---

## F1: Spanner's SQL Layer

In 2013, Google published the F1 paper — a SQL engine built on top of Spanner that replaced Google AdWords' sharded MySQL.

**What F1 adds:**
- Full SQL: joins, aggregations, subqueries, DML
- Protocol buffer schema support (Spanner rows can store protobufs)
- Distributed query execution: parallel scans across shards
- Change history: every mutation tracked with timestamps
- Secondary indexes: both local (same tablet) and global (cross-shard, async)

**The AdWords migration:** 100TB+ of data, thousands of tables, migrated from MySQL to Spanner with zero downtime using the dual-write + gradual cutover pattern.

---

## Performance Numbers (From the Paper)

### Latency (5 replicas, 3 datacenters)

| Operation | Mean | 99th percentile |
|-----------|------|----------------|
| Read (1KB, single DC) | 1.0ms | 1.4ms |
| Read (1KB, multi-DC) | 1.0ms | 2.0ms |
| Write (1KB, single DC) | 8.0ms | 12ms |
| Write (1KB, multi-DC) | 14ms | 18ms |

Write latency = Paxos replication (~6ms one-way to another DC) + commit wait (~4–7ms ε)

### Throughput

- Single spanserver: ~250 reads/sec per core
- Single Spanner deployment: hundreds of thousands of QPS across thousands of spanservers
- AdWords F1: 4.6M SQL queries/sec, peak; 1.5M–4.5M reads/sec

### TrueTime Epsilon

| Percentile | ε |
|-----------|---|
| 50th | 1ms |
| 99th | 7ms |
| 99.9th | 7ms |

ε is the commit wait penalty. 7ms worst case means writes are never delayed more than 7ms for external consistency.

---

## CAP Theorem Positioning

| Property | Spanner's choice |
|----------|-----------------|
| **C**onsistency | ✅ External consistency (stronger than serializable) |
| **A**vailability | ✅ High (5-replica Paxos, 2 failures tolerated) |
| **P**artition tolerance | Sacrificed: network partition reduces availability (Paxos can't make progress without majority) |

Spanner is **CP**, not AP. During a partition, writes block rather than proceeding with potential inconsistency. Google accepts this because:
- Google's backbone network has extremely low partition rates
- Correctness > availability for billing/financial data
- Users tolerate brief unavailability more than incorrect charges

---

## Trade-offs and Limitations

| Dimension | Spanner | Trade-off |
|-----------|---------|-----------|
| Consistency | External (strongest possible) | Commit wait adds 1–7ms to every write |
| Latency | Low (within DC), higher (cross-DC) | Cross-DC writes ~14ms due to Paxos + commit wait |
| Availability | High (2F+1 Paxos, survives 2 failures) | Partition halts writes (CP, not AP) |
| Scalability | Horizontal, automatic sharding | 2PC across shards adds latency; avoid cross-shard hot spots |
| Portability | Requires GPS + atomic clock infrastructure | TrueTime not reproducible outside Google (CockroachDB approximates with HLC) |
| SQL | Full ANSI SQL (F1) | Interleaved tables require schema planning for locality |
| Cost | Expensive at small scale | Paxos replication to 5 replicas = 5× write amplification |

---

## Open Source Equivalents

TrueTime is Google-proprietary (GPS clocks in every DC). The database community has built equivalents:

| System | TrueTime equivalent | Consistency model |
|--------|--------------------|--------------------|
| **CockroachDB** | Hybrid Logical Clocks (HLC) | Serializable (not external) |
| **YugabyteDB** | HLC | Serializable |
| **TiDB** | Timestamp oracle (centralized) | Snapshot isolation |
| **Google Cloud Spanner** | TrueTime (real thing, managed) | External consistency |
| **FaunaDB** | Calvin protocol | Strict serializability |

**CockroachDB vs Spanner:** CockroachDB uses HLC (logical clocks + wall-clock blending) which approximates TrueTime but cannot guarantee external consistency — it achieves serializability but allows a read that starts after a commit to potentially miss it by a few milliseconds. For most workloads this is fine; for AdWords billing it is not.

---

## Spanner vs DynamoDB vs Cassandra

| Dimension | Spanner | DynamoDB | Cassandra |
|-----------|---------|----------|-----------|
| Consistency | External (CP) | Eventually consistent (AP), optional strong | Tunable (quorum) |
| Transactions | Full ACID, multi-row, multi-table | Single-item atomic; limited multi-item (TransactWrite) | No multi-row transactions natively |
| SQL | Full SQL (F1/Cloud Spanner) | PartiQL (limited) | CQL (Cassandra Query Language, limited) |
| Distribution | Global, automatic | Global (DynamoDB Global Tables) | Multi-DC ring |
| Latency (write) | 8–14ms | ~10ms (single-region) | 1–5ms |
| Horizontal scale | Yes (automatic resharding) | Yes (automatic) | Yes (ring expansion) |
| Schema | Relational + interleaved | Schemaless key-value | Wide column |
| When to use | Financial, billing, global inventory | High-throughput key-value, flexible schema | Time-series, write-heavy, IoT |

---

## Key Design Decisions as ADRs

### ADR 1: TrueTime instead of Lamport Clocks
**Context:** Need to assign globally meaningful timestamps to transactions without global coordination.  
**Decision:** Use physical time with bounded uncertainty (TrueTime) rather than logical clocks.  
**Consequences:** Commit wait introduces latency; physical infrastructure (GPS + atomic clocks) required; external consistency achievable.

### ADR 2: Paxos-based replication instead of primary-backup
**Context:** Need fault tolerance with well-defined consistency guarantees.  
**Decision:** Multi-Paxos with long-lived leases.  
**Consequences:** Can tolerate f failures with 2f+1 replicas; lease mechanism enables fast reads from leader; lease management requires TrueTime disjointness.

### ADR 3: 2PC across Paxos groups for distributed transactions
**Context:** Transactions can span multiple shards (Paxos groups).  
**Decision:** Two-phase commit coordinated by one Paxos group.  
**Consequences:** Cross-shard transactions add one Paxos round-trip; 2PC is safe (no coordinator failure issue) because the coordinator is itself a Paxos group.

### ADR 4: Interleaved table hierarchy
**Context:** Related data (Users + Albums) must be colocated for performance.  
**Decision:** Allow child tables to be physically interleaved within parent tables.  
**Consequences:** Parent-child reads are local (fast); cross-hierarchy joins still require distributed execution; schema design becomes a performance concern.

---

## Interview Framing

**Q: How does Spanner achieve external consistency?**
> Spanner combines three mechanisms. First, TrueTime gives each machine a real-time interval [earliest, latest] where the true time is guaranteed to fall. Second, write transactions acquire a commit timestamp `s = TT.now().latest` — ensuring s is an upper bound on the real commit time. Third, commit wait: the coordinator delays applying the commit until TT.after(s) is true, ensuring s is now also a lower bound. After commit wait, any transaction that starts will see TT.now().earliest > s, so its timestamp will be greater than s. This guarantees causal ordering without a global coordinator or Lamport clocks.

**Q: Why does Spanner use Paxos instead of primary-backup replication?**
> Primary-backup is simpler but has an availability gap during leader failover — the new primary must be sure the old one is dead before serving writes, which requires a timeout. Paxos handles leader election as part of the protocol: a new leader can only win an election if it has received the latest state from a quorum, so it's always safe to serve writes immediately. The leader lease mechanism (using TrueTime disjointness) means the new leader knows for certain the old lease has expired — no timeout required.

**Q: How does Spanner serve non-blocking reads?**
> MVCC: every cell stores versioned values timestamped at commit time. A read-only transaction picks a timestamp T = TT.now().latest (for strong consistency) or a past timestamp (for bounded staleness), then reads the latest version of each cell with timestamp ≤ T. No locks required — writes create new versions rather than overwriting old ones. The only wait is for the replica to have applied all writes with timestamp ≤ T (safeTime ≥ T). For bounded staleness reads, even this wait is usually zero.

**Q: What is the performance cost of TrueTime?**
> Commit wait — every write transaction is delayed by approximately ε (the TrueTime uncertainty interval) before its result is visible. At Google's TrueTime implementation, ε is typically 1–7ms. So the minimum write latency is 7ms (plus Paxos replication time, typically another 7ms cross-DC). For Google's use cases — billing, ad clicks, financial transactions — 14ms write latency is acceptable in exchange for external consistency. For sub-millisecond latency requirements, you'd use a system without external consistency guarantees.

**Q: How does Spanner scale?**
> Spanner scales by splitting and moving tablets. The placement driver continuously monitors load and tablet sizes. When a tablet grows too large (typically ~several GB) or becomes a hot spot, it splits it into two smaller tablets. Each tablet is independently managed by a Paxos group and can be moved to a different zone for load balancing. Adding machines to a zone increases capacity and throughput. This is fully automatic — applications don't need to manage shards. The schema design (interleaved tables) is the main performance lever the application controls.

---

## Summary: What Spanner Proved

1. **External consistency at global scale is achievable** — not just theoretically, but in production at Google scale
2. **Physical time with bounded uncertainty is a valid synchronization primitive** — TrueTime enables commit ordering without a global coordinator
3. **CAP theorem is not a hard wall** — with the right infrastructure, you can have consistency + availability in normal operation (only sacrifice availability during actual network partitions, which are rare)
4. **Relational databases can scale horizontally** — the assumption that SQL = no horizontal scale was wrong; it requires careful schema design (interleaving) and automatic resharding
5. **Paxos in production is practical** — the performance concern about Paxos was addressed by long-lived leader leases, which reduce Paxos to one round-trip per write in the common case

Spanner changed the industry's understanding of what distributed databases can guarantee. Systems like CockroachDB, YugabyteDB, and Google Cloud Spanner are all direct descendants of the ideas in this paper.
