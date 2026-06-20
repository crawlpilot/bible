# Distributed Transactions

## The Core Problem (Start Here)

You're booking a flight. The system must: (1) charge your card $500, (2) reserve seat 24A, (3) issue a boarding pass. These happen in three separate services. The card charge succeeds. The seat reservation service crashes mid-write.

You were charged $500. You have no seat. The system is in an inconsistent state.

This is the distributed transaction problem. With a single database, you'd wrap it in `BEGIN`/`COMMIT` and atomicity is guaranteed. With three separate services, there is no global transaction manager — you must build one.

```
Single DB (easy):
  BEGIN;
    charge_card(500);          ← succeeds
    reserve_seat('24A');       ← succeeds
    issue_boarding_pass();     ← crash here
  ROLLBACK;                    ← all three undone atomically

Distributed (hard):
  PaymentService.charge(500);           ← commits locally (DONE)
  SeatService.reserve('24A');           ← crash here
  BoardingPassService.issue();          ← never called

  On recovery: card charged, no seat. No automatic rollback across services.
  Options: 2PC (lock and coordinate), SAGA (compensate), or accept the inconsistency.
```

The 3-phase commit (3PC) was invented to fix 2PC's blocking problem, but introduces a worse one: under a network partition, two nodes in different partitions may each decide independently — one commits, one aborts. This **split-brain decision** (the example the user referenced) is why 3PC is almost never used in production; Paxos/Raft-based coordinators solve the problem correctly instead.

---

## The Problem

A single database transaction is easy: atomically update rows, ACID guarantees everything. Across multiple services or databases, atomicity breaks — you must coordinate commits across systems that may fail independently.

The challenge: how do you ensure "all-or-nothing" semantics when the systems involved are:
- Separate databases (order DB + inventory DB + payment DB)
- Separate microservices with their own storage
- Geographically distributed nodes with high latency between them

---

## Two-Phase Commit (2PC)

### The Protocol

The classic solution for distributed atomicity. A **coordinator** manages two phases across multiple **participants** (resource managers).

```
Coordinator           Participant 1       Participant 2
    │                      │                    │
    │──── PREPARE ─────────►│                    │
    │──── PREPARE ────────────────────────────►│
    │                      │                    │
    │ [waits for votes]     │ check, lock rows   │ check, lock rows
    │                      │                    │
    │◄─── VOTE YES ─────────│                    │
    │◄─── VOTE YES ──────────────────────────────│
    │                      │                    │
    │ [all YES → COMMIT]    │                    │
    │                      │                    │
    │──── COMMIT ──────────►│                    │
    │──── COMMIT ──────────────────────────────►│
    │                      │                    │
    │◄─── ACK ──────────────│                    │
    │◄─── ACK ───────────────────────────────────│
```

**Phase 1 (Prepare):**
- Coordinator sends PREPARE to all participants
- Each participant: writes to WAL, acquires locks, checks constraints, votes YES or NO
- If any participant votes NO → coordinator sends ABORT

**Phase 2 (Commit/Abort):**
- If all voted YES → coordinator writes "commit" to its WAL, then sends COMMIT to all
- Each participant commits, releases locks, ACKs

### The Blocking Problem

2PC is a **blocking protocol** — if the coordinator fails after Phase 1 but before Phase 2, participants are stuck holding locks indefinitely.

```
FAILURE SCENARIO:
  Coordinator sends PREPARE; both participants vote YES
  Coordinator crashes before sending COMMIT
  
  Participants: holding locks, waiting for COMMIT or ABORT
  Cannot proceed without the coordinator's decision
  System is BLOCKED until coordinator recovers
```

**Why this is serious:**
- Held locks block other transactions
- Recovery requires coordinator to come back online and replay from its WAL
- If coordinator's WAL is corrupted → manual intervention required

### 2PC Failure Matrix

| Failure Point | Result |
|---------------|--------|
| Participant fails before PREPARE response | Coordinator aborts |
| Participant fails after voting YES | Coordinator waits; participant recovers, replays from WAL |
| Coordinator fails before sending PREPARE | No effect; new coordinator retries |
| Coordinator fails after all YES, before COMMIT | **Blocking** — participants hold locks |
| Coordinator fails after sending COMMIT to some | Participants that received COMMIT commit; others recover by querying coordinator |
| Network partition after PREPARE | Blocking; participants cannot determine outcome |

### Performance Characteristics

- **Latency:** 2 RTTs minimum + participant disk writes (typically 20–100ms in LAN)
- **Lock hold time:** Locks held from Phase 1 vote until Phase 2 ACK — contention risk
- **Throughput:** Serialized per-transaction coordinator log write is a bottleneck

### Where 2PC Is Used

- **MySQL XA transactions** — across multiple MySQL instances
- **PostgreSQL two-phase commit** — `PREPARE TRANSACTION` / `COMMIT PREPARED`
- **Java EE JTA** — across multiple JDBC datasources
- **Spanner** — uses 2PC but with Paxos groups as participants (making participants themselves fault-tolerant)
- **CockroachDB** — internally uses 2PC with transaction coordinator as a participant

---

## Three-Phase Commit (3PC)

### What It Adds

3PC adds a third phase to solve 2PC's blocking problem by introducing a **pre-commit** phase that creates a protocol where participants can make a decision unilaterally during recovery.

```
Phase 1: CANCOMMIT? (like PREPARE)
Phase 2: PRECOMMIT  (tells everyone "we will commit unless you hear otherwise")
Phase 3: DOCOMMIT   (final commit)
```

The key: after receiving PRECOMMIT, a participant knows the coordinator intends to commit. If the coordinator dies, other participants can unilaterally commit (or abort based on timeout).

### Why 3PC Is Rarely Used

3PC is non-blocking only in the absence of network partitions. Under a network partition:
- Partitioned participants may make inconsistent decisions
- 3PC can violate atomicity during split-brain

In practice: network partitions happen, so 3PC's non-blocking guarantee doesn't hold. Real systems use Paxos/Raft for the coordinator (making it fault-tolerant) or use SAGA instead.

**3PC is mostly a theoretical stepping stone.** Almost no major production system uses it directly.

---

## SAGA Pattern

### The Alternative to 2PC

SAGA (Hector Garcia-Molina, 1987; adapted for microservices by Chris Richardson) decomposes a long-running transaction into a sequence of local transactions, each publishing an event or message. If any step fails, compensating transactions undo the previous steps.

**Key difference from 2PC:** No locking across services. Each step commits locally and immediately. If later steps fail, compensating transactions semantically undo the earlier commits.

### SAGA Execution Flows

```
Order Service    Inventory Service    Payment Service
    │                  │                    │
    │ Create order      │                    │
    │ (commits locally) │                    │
    │──── OrderCreated ►│                    │
    │                   │ Reserve inventory  │
    │                   │ (commits locally)  │
    │                   │──── Reserved ─────►│
    │                   │                    │ Charge card
    │                   │                    │ (commits locally)
    │                   │                    │── PaymentCompleted
    │◄──────────────────────────────────────┤
    │ Fulfill order     │                    │
```

**Compensation flow (payment fails):**
```
Payment fails
    │──── PaymentFailed ─────────────────────►│
    │                   │ Release inventory   │
    │                   │◄────────────────────┤
    │◄── InventoryReleased                    │
    │ Cancel order      │                     │
```

### Choreography vs. Orchestration

| Dimension | Choreography | Orchestration |
|-----------|-------------|--------------|
| Control | Decentralized — services react to events | Centralized — saga orchestrator commands services |
| Coupling | Services know each other's events | Services only know the orchestrator |
| Observability | Hard to track overall state | Easy — orchestrator holds state |
| Failure handling | Each service handles its failures | Orchestrator manages compensation |
| Scalability | Better (no central bottleneck) | Orchestrator can become bottleneck |
| Testing | Complex — must trace event chains | Simpler — test orchestrator logic |
| Best for | Simple, linear flows | Complex branching flows |

**Choreography example:** Each service publishes events (OrderCreated, InventoryReserved, PaymentCharged). Downstream services subscribe to events they care about and publish their own events.

**Orchestration example:** An Order Saga Orchestrator explicitly calls InventoryService.reserve(), then PaymentService.charge(), and handles failures by calling compensating methods.

### SAGA Failure Modes

**Countermeasures for SAGA anomalies:**

| Anomaly | Description | Countermeasure |
|---------|------------|---------------|
| Dirty reads | T2 reads uncommitted data from T1 that later aborts | Semantic locks (mark data as pending) |
| Non-repeatable reads | T1 reads data changed by completed T2 | Re-read data before writing |
| Lost updates | T1 and T2 both update same record | Pessimistic locking within a service |
| Ordering | Events arrive out of order | Correlation IDs + idempotent handlers |

**Semantic locking:** Mark a record as "PENDING" when a SAGA starts operating on it. Other transactions reject operations on PENDING records. Release the lock when the SAGA completes or compensates.

### The Outbox Pattern

The critical reliability enhancement for SAGA (and any event-driven system):

**Problem:** How do you atomically commit a DB change AND publish an event? Without atomicity, you can commit to DB and fail before publishing the event — the SAGA step is "done" but nobody knows.

```
NAIVE (BROKEN) APPROACH:
  1. BEGIN TRANSACTION
  2. UPDATE orders SET status='PENDING'
  3. COMMIT TRANSACTION
  4. kafka.publish("OrderCreated")  ← can fail here; DB committed but event not sent
```

```
OUTBOX PATTERN (CORRECT):
  1. BEGIN TRANSACTION
  2. UPDATE orders SET status='PENDING'
  3. INSERT INTO outbox(event_type, payload) VALUES ('OrderCreated', {...})
  4. COMMIT TRANSACTION           ← atomic: either both happen or neither
  5. Background relay reads outbox and publishes to Kafka
  6. On successful publish: DELETE FROM outbox WHERE id = X
```

The outbox table is in the **same database** as the business data, so both the business update and the event record are covered by a single local ACID transaction. The relay can be a polling job, a CDC (Change Data Capture) connector, or Debezium reading the PostgreSQL WAL.

---

## Distributed ACID: Google Spanner Model

Spanner achieves global ACID transactions using:
1. **Paxos groups** — each shard is replicated by a Paxos group (fault-tolerant participant)
2. **TrueTime** — GPS + atomic clocks give bounded clock uncertainty
3. **Two-Phase Commit** — across Paxos groups, but each participant is fault-tolerant

### Commit Wait Protocol

Spanner's key insight for external consistency: commit timestamps must be after any previous committed transaction's timestamp.

```
commit_ts > TrueTime.now().latest
// Wait until TrueTime.now().earliest > commit_ts
// Then release the commit to readers
```

Because TrueTime gives a guaranteed upper bound on clock uncertainty (ε ≈ 7ms), Spanner waits at most 2ε before making a commit visible. This ensures all subsequent reads see a timestamp strictly after the write.

**Cost:** 7–14ms latency added to every write (commit wait). This is why Spanner is not zero-latency — it trades latency for global external consistency.

### Why Most Systems Can't Do This

TrueTime requires:
- Dedicated GPS receivers + atomic clock hardware in every datacenter
- Tight network synchronization (sub-millisecond)
- Google's private fiber between datacenters

Without TrueTime, you need HLC (Hybrid Logical Clocks) — used by CockroachDB and YugabyteDB — which gives similar guarantees with bounded drift but requires periodic global synchronization.

---

## Comparison: 2PC vs SAGA vs Spanner

| Dimension | 2PC | SAGA | Spanner |
|-----------|-----|------|---------|
| Atomicity | True atomicity | Eventual atomicity via compensation | True atomicity |
| Isolation | Full ACID isolation | Reduced (intermediate states visible) | Full ACID isolation |
| Availability | Low (blocking on coordinator failure) | High (local commits; compensation async) | High (Paxos per shard) |
| Latency | 2 RTTs + participant disk writes | 1 RTT per step (no cross-service locking) | 2 RTTs + commit wait (~14ms) |
| Failure recovery | Coordinator must recover; participants blocked | Compensating transactions | Paxos election (150–500ms) |
| Cross-DB support | Yes (XA) | Yes | Only within Spanner |
| Rollback semantics | True rollback | Compensating (semantic undo, not physical undo) | True rollback |
| Best for | Same-datacenter, tightly coupled systems | Microservices, cross-service workflows | Global strong consistency at scale |

---

## When to Use What

```
Is the transaction across multiple microservices or databases?
  YES → continue
  NO → use local ACID transaction

Are intermediate states tolerable (e.g., order is "pending" while payment processes)?
  YES → SAGA (with outbox pattern)
  NO → continue

Is the workload within a single geographic region?
  YES → 2PC (if systems support XA) or 2PC within a distributed SQL DB
  NO → continue

Do you need global external consistency (Spanner-level)?
  YES → Spanner, CockroachDB, YugabyteDB
  NO → SAGA with strong idempotency + compensation
```

---

## Change Data Capture (CDC) + Outbox

The most production-grade way to implement the outbox pattern at scale:

```
PostgreSQL WAL
     │
     ▼
  Debezium         Debezium reads WAL, reads outbox table changes
     │             and publishes them as Kafka events
     ▼
  Kafka Topic      At-least-once delivery; consumers must be idempotent
     │
     ▼
  Consumers        Process events; use idempotency keys to deduplicate
```

**Advantages:** 
- No polling overhead (WAL streaming)
- Guaranteed ordering within a partition
- Works even if the application doesn't know about Debezium

**Disadvantage:** Operational complexity (running Debezium, managing Kafka connector offsets)

---

## FAANG Interview Application

**When you'll be asked about this:**
- "How do you ensure consistency across multiple microservices in a payment flow?"
- "How does your booking system handle partial failures — what if the inventory is reserved but payment fails?"
- "What's the difference between 2PC and SAGA?"
- "How does Google Spanner achieve global ACID transactions?"

**What they're evaluating:**
- Do you know that 2PC blocks and why that's a problem?
- Can you design a SAGA with compensating transactions end-to-end?
- Do you know the outbox pattern (the most common gap in candidate knowledge)?
- Can you explain Spanner's TrueTime approach without hand-waving?

**Principal-level signal:**
A senior engineer says "use SAGA for microservices transactions." A principal engineer says: "We use SAGA with the outbox pattern for the order flow because intermediate states are acceptable (order is pending while payment clears). We use CockroachDB transactions for the payment ledger itself because we need true ACID — a partial write to the accounting table is not compensable. The SAGA handles cross-service coordination; the RDBMS handles within-service atomicity. These are different problems with different tools."

---

## Cross-References

- [consistency-models.md](./consistency-models.md) — ACID vs BASE; isolation levels that 2PC and SAGA are designed to achieve
- [idempotency-and-exactly-once.md](./idempotency-and-exactly-once.md) — outbox pattern deep-dive, Kafka EOS, idempotency keys
- [write-ahead-log-and-storage-internals.md](./write-ahead-log-and-storage-internals.md) — WAL as the foundation for outbox + CDC (Debezium)
- [paxos-and-consensus-variants.md](./paxos-and-consensus-variants.md) — Spanner’s Paxos groups as fault-tolerant 2PC participants
- [replication-patterns.md](./replication-patterns.md) — Kafka ISR and durability guarantees underpinning SAGA event delivery
- [failure-detection-and-recovery.md](./failure-detection-and-recovery.md) — what happens when the 2PC coordinator crashes (the blocking problem)
