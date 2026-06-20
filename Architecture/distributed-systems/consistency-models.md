# Consistency Models in Distributed Systems

## The Core Problem (Start Here)

Two users open the booking app at the same moment. Both see "1 room left" for the same hotel. Both click "Book Now". Both get a confirmation email. Now two people show up at the hotel with valid reservations for the same room.

This is a consistency failure — both users read the same stale state and acted on it without knowing about each other's concurrent write. The hotel's system needed a stronger consistency guarantee.

But strong consistency has a cost: to prevent this, the system must coordinate between servers before confirming either booking. In a global system, that coordination adds latency. The question is not "should we have strong consistency" but "which operations need it, and what are we willing to pay?"

```
Server A (US-East):          Server B (EU-West):
  reads: rooms_left = 1        reads: rooms_left = 1
  writes: rooms_left = 0       writes: rooms_left = 0
  
Both succeed → both users confirmed → overbooking

Fix options:
  1. Linearizability: coordinate before confirming → one write wins, other retries
  2. Optimistic locking: compare-and-swap on rooms_left (only decrement if still 1)
  3. Accept eventual: book both, compensate later (airline-style overbooking)
```

---

## Why Consistency Models Matter

Every distributed system makes a promise about what a client will observe after a write. Consistency models are the formal vocabulary for those promises. Choosing the wrong model leads to data loss, stale reads, or over-engineered systems that sacrifice availability unnecessarily.

At the principal engineer level, you must be able to: (1) name the model a system offers, (2) explain what anomalies are possible under weaker models, and (3) choose the right model for a given workload.

---

## The Consistency Spectrum

From strongest (most restrictions, most overhead) to weakest (fewest restrictions, lowest overhead):

```
STRONGEST                                                        WEAKEST
    │                                                               │
Linearizability → Serializability → Causal → Read-Your-Writes → Eventual
    │                   │              │             │               │
  Single op          Transactions   Causality     Session         No
  appears            appear          preserved    guarantee       guarantee
  atomic             atomic
```

---

## 1. Linearizability (Atomic Consistency)

**Definition:** Every operation appears to take effect instantaneously at a single point between its invocation and its response. After a write completes, all subsequent reads (by any client) see that write or a later one.

**Mental model:** The system behaves as if there is a single copy of the data and all operations are serialized.

**What it allows:**
- Client A writes x=1, then client B reads x → B sees 1

**What it prohibits:**
- Client A writes x=1, client B reads x and sees 0 (stale), then client A reads x and sees 1

```
Timeline:
Client A:  ──── write(x=1) ────┤
Client B:                       ├── read(x) → must see 1
```

**Implementation cost:** Requires coordination on every operation. Typically implemented with consensus (Raft, Paxos) or single-leader serialization. 1–5ms per operation in a LAN cluster; 50–150ms in a multi-region cluster.

**Real-world systems:** etcd, ZooKeeper, Google Spanner, CockroachDB (default), HBase

---

## 2. Sequential Consistency

**Definition:** Operations appear to execute in some sequential order that is consistent with the program order of each individual client. Unlike linearizability, the order need not respect real time.

**What it allows:**
- Client A writes x=1; client B reads x and sees 0 (temporarily), but eventually sees 1. The key: clients have a consistent view of the *ordering* of all operations.

**What it prohibits:**
- Different clients see operations in different orders

**Key difference from linearizability:** Linearizability requires real-time ordering. Sequential consistency only requires consistency of ordering across clients.

**Real-world systems:** CPU cache coherency protocols (MESI), some GPU memory models

---

## 3. Serializability

**Definition:** Transactions appear to execute serially (one after another) in some order. Used for multi-operation transactions (not single operations like linearizability).

**What it allows:** Concurrent transactions execute as if they ran sequentially. The serial order does not need to match real time.

**What it prohibits:** Any anomaly that a serial execution would prevent (dirty reads, non-repeatable reads, phantoms).

**Relationship to linearizability:** Linearizability + Serializability = **Strict Serializability** (the strongest model; what Spanner offers).

**Real-world systems:** PostgreSQL (with SERIALIZABLE isolation), MySQL InnoDB (serializable level), Spanner

---

## 4. Snapshot Isolation (SI)

**Definition:** Each transaction reads from a consistent snapshot of the database taken at the transaction's start. Writes are checked for conflicts at commit time.

**What it prevents:** Dirty reads, non-repeatable reads, most phantoms

**Anomaly it allows:** **Write skew** — two transactions read overlapping data, each writes non-overlapping data, but the combined result violates a constraint.

**Example of write skew:**
```
Hospital: must have at least 1 doctor on call
T1: reads doctors = [A, B]; sees 2 on call; removes A (writes: on_call_A = false)
T2: reads doctors = [A, B]; sees 2 on call; removes B (writes: on_call_B = false)
Result: 0 doctors on call — violated constraint, but neither transaction "saw" the other's write
```

**Real-world systems:** PostgreSQL (REPEATABLE READ), Oracle, MySQL InnoDB (default), CockroachDB (serializable mode handles write skew; SI does not)

---

## 5. Causal Consistency

**Definition:** Operations that are causally related (write happens-before read) are seen in causal order by all clients. Concurrent (causally unrelated) operations may be seen in different orders.

**What it allows:** Client A reads x, then writes y. Client B sees the write to y and must also see the earlier write to x. But two independent writes have no required ordering.

**What it prohibits:** Reading the reply before the post, seeing an effect before its cause.

**Why it matters:** Causal consistency is achievable without coordination overhead across partitions — unlike linearizability. It's the strongest model that doesn't require global coordination.

**Implementation:** Vector clocks or causal tokens track causal dependencies.

**Real-world systems:** COPS (Causal + Consistent), MongoDB causal sessions, some Cassandra configurations with client-side timestamp tracking

---

## 6. Read-Your-Writes (Session Consistency)

**Definition:** After a client writes a value, subsequent reads by the same client always see that write. Other clients may temporarily see stale data.

**What it allows:** Client reads its own writes, even if replicas are lagging.

**What it prohibits:** A client writes x=1, then immediately reads x and gets 0.

**Implementation:** Route client reads to the replica that processed the write, or use sticky sessions, or carry a session token with the minimum version needed.

**Real-world systems:** DynamoDB (strongly consistent reads option), Cassandra (QUORUM reads), relational DBs routing to primary

---

## 7. Eventual Consistency

**Definition:** If no new writes are made, all replicas will eventually converge to the same value. No guarantee about when, or what intermediate values are visible.

**What it allows:** Temporarily inconsistent reads. Client A writes x=1; client B may read x=0 indefinitely (in practice, seconds to minutes).

**Why use it:** Maximum availability and performance. Works correctly under network partitions.

**Real-world systems:** Cassandra (ONE/ANY consistency level), DynamoDB (eventually consistent reads), DNS, CDN caches

---

## Isolation Levels (SQL Transactions)

Isolation levels are the relational database manifestation of consistency trade-offs within transactions.

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read | Write Skew |
|----------------|-----------|--------------------|--------------| -----------|
| Read Uncommitted | ✅ possible | ✅ possible | ✅ possible | ✅ possible |
| Read Committed | ✗ prevented | ✅ possible | ✅ possible | ✅ possible |
| Repeatable Read | ✗ prevented | ✗ prevented | ✅ possible | ✅ possible |
| Snapshot Isolation | ✗ prevented | ✗ prevented | ✗ prevented | ✅ possible |
| Serializable | ✗ prevented | ✗ prevented | ✗ prevented | ✗ prevented |

**Dirty Read:** Reading uncommitted data from another transaction.  
**Non-Repeatable Read:** Reading the same row twice and getting different values (another transaction committed between reads).  
**Phantom Read:** Re-executing a range query and getting different rows (another transaction inserted/deleted).  
**Write Skew:** Two transactions read overlapping data, each writes based on what they read, combined result violates invariant (see hospital example above).

---

## CAP Theorem

### What It Actually Says

In the presence of a **network Partition**, a distributed system must choose between **Consistency** and **Availability**.

```
        Consistency
           /\
          /  \
         /    \
        /      \
       /   CA   \  ← Only achievable without partitions
      /          \
     /    C | A   \
    /──────┼───────\
Avail.    P     Partition
```

**C (Consistency):** Every read receives the most recent write or an error (i.e., linearizability).  
**A (Availability):** Every request receives a response (not an error), though it may be stale.  
**P (Partition Tolerance):** The system continues to operate despite network partitions.

**The myth:** "Choose 2 of 3." In reality, network partitions are not optional in a distributed system — they will happen. So the real choice is: **during a partition, do you return stale data (AP) or return an error (CP)?**

### CP vs AP Behaviour

| Scenario | CP system | AP system |
|----------|-----------|-----------|
| No partition | Consistent + Available | Consistent + Available |
| Network partition | Return error or block writes | Return stale data; accept writes (may conflict) |
| Partition heals | Resumes normally | Reconciles conflicts |
| Examples | etcd, ZooKeeper, HBase | Cassandra, DynamoDB, CouchDB |

---

## PACELC: CAP's More Useful Extension

CAP only addresses behavior during partitions. PACELC (Daniel Abadi, 2012) adds the trade-off during normal operation:

> **P**artition: **A** availability vs **C** consistency  
> **E**lse (no partition): **L** latency vs **C** consistency

```
System            P → A/C    E → L/C
─────────────────────────────────────
Cassandra         A          L  (eventual, low latency)
DynamoDB          A          L  (eventual by default)
etcd              C          C  (linearizable, higher latency)
Spanner           C          C  (external consistency, TrueTime)
MySQL (primary)   C          C  (ACID, higher latency)
Riak              A          L  (eventual, low latency)
CockroachDB       C          C  (serializable)
```

**Why PACELC matters:** During normal operation (99.99%+ of the time), you're not in a partition. The real trade-off is latency vs. consistency on every operation.

---

## ACID vs BASE

### ACID (Traditional RDBMS)
| Property | Meaning |
|----------|---------|
| **Atomicity** | All operations in a transaction succeed or all are rolled back. No partial writes. |
| **Consistency** | Transactions bring the database from one valid state to another. Constraints, triggers, and foreign keys hold. |
| **Isolation** | Concurrent transactions are isolated from each other. Appears as if serialized. |
| **Durability** | Committed transactions survive crashes (WAL, fsync). |

**Cost:** Coordination, locking, and synchronous writes. Limits scalability.

### BASE (Distributed / NoSQL)
| Property | Meaning |
|----------|---------|
| **Basically Available** | The system remains operational even if some nodes are unavailable. Partial availability is preferred over total unavailability. |
| **Soft State** | The system state may change over time even without new input (due to eventual consistency catching up). |
| **Eventually Consistent** | Given no new updates, the system will eventually converge to a consistent state. |

**Cost:** Application must handle stale reads, conflicts, and idempotent operations.

---

## Real-World Consistency Matrix

| System | Default Consistency | Strongest Available | Notes |
|--------|--------------------|--------------------|-------|
| **Cassandra** | Eventual (ONE) | Linearizable (LWT + QUORUM) | Lightweight transactions for CAS; expensive |
| **DynamoDB** | Eventual | Strong (per-item) | Strongly consistent reads available; not transactions by default |
| **DynamoDB Transactions** | Serializable | Serializable | 2x WCU cost |
| **Spanner** | External Consistency | External Consistency | Linearizable + serializable across transactions globally |
| **CockroachDB** | Serializable | Serializable | Default; linearizable single-key ops |
| **etcd** | Linearizable | Linearizable | All writes go through Raft |
| **Redis (single node)** | Linearizable | Linearizable | Single-threaded; no replication anomalies |
| **Redis Cluster** | Eventual | Best effort | Async replication; can lose writes on failover |
| **MongoDB (default)** | Read Committed | Causal (sessions) | Majority write concern + snapshot isolation available |
| **MySQL (InnoDB)** | Read Committed | Serializable | Repeatable Read default; configurable |
| **HBase** | Strong (per row) | Strong (per row) | Row-level linearizability; no multi-row transactions natively |
| **Kafka** | Per-partition ordering | EOS (across partitions) | Exactly-once across topics with transactions |

---

## Choosing a Consistency Model: Decision Framework

```
Does the workload require multi-row transactions?
  YES → ACID: PostgreSQL, CockroachDB, Spanner
  NO → continue

Is the workload globally distributed (multiple regions)?
  YES → Is strong consistency needed globally?
    YES → Spanner / CockroachDB multi-region (high latency, high cost)
    NO → Cassandra multi-DC / DynamoDB Global Tables (eventual, low latency)
  NO → continue

Is low latency (< 5ms) the primary requirement?
  YES → Cassandra / DynamoDB eventual consistency
  NO → continue

Is read-your-writes sufficient (no cross-client consistency needed)?
  YES → Session consistency: DynamoDB strongly consistent reads, Cassandra LOCAL_QUORUM
  NO → Linearizability: etcd, CockroachDB, Spanner
```

---

## Anomalies Reference Card

| Anomaly | Description | Prevented by |
|---------|------------|-------------|
| **Dirty Read** | Read uncommitted write | Read Committed+ |
| **Lost Update** | Two concurrent writes, one is overwritten | Atomic write operations, OCC |
| **Non-Repeatable Read** | Same row read twice, different value | Repeatable Read+ |
| **Phantom Read** | Range query returns different rows | Serializable / Snapshot |
| **Write Skew** | Two transactions read same, write different, violate constraint | Serializable (not Snapshot) |
| **Read Skew** | Inconsistent snapshot during transaction | Snapshot Isolation+ |
| **Stale Read** | Reading data from before a recent committed write | Linearizability (eliminates) |
| **Causality Violation** | Seeing an effect before its cause | Causal Consistency+ |

---

## FAANG Interview Application

**When you'll be asked about this:**
- "What consistency guarantees does [Cassandra/DynamoDB/your design] offer?"
- "What's the difference between consistency in CAP and ACID?"
- "Walk me through what happens if two users write to the same record concurrently in your design"
- "Why can't we just use eventual consistency for everything?"

**What they're evaluating:**
- Do you know the precise definitions, not just buzzwords?
- Can you identify which anomaly a given workload must prevent?
- Do you understand the latency/cost implications of each model?

**Principal-level signal:**
A senior engineer says "we use strong consistency for writes." A principal engineer says: "We use CockroachDB with serializable isolation for the payment flow because write skew on the account balance is the failure mode we can't accept. For the user profile service, we use DynamoDB with eventually consistent reads because stale profiles are acceptable and the 2x latency of strongly consistent reads would violate our p99 SLO. These are different consistency models for different data, by design."

---

## Cross-References

- [distributed-transactions.md](./distributed-transactions.md) — ACID properties and how 2PC/SAGA achieve different isolation levels
- [replication-patterns.md](./replication-patterns.md) — Cassandra tunable consistency levels (ONE / QUORUM / ALL) in practice
- [partitioning-strategies.md](./partitioning-strategies.md) — how scatter-gather reads interact with quorum consistency
- [raft-consensus.md](./raft-consensus.md) — how Raft achieves linearizable reads (ReadIndex protocol)
- [multi-region-distribution.md](./multi-region-distribution.md) — CAP trade-offs at the regional level (active-passive vs active-active)
