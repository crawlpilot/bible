# Paxos and Consensus Variants

## The Core Problem (Start Here)

Three servers must agree on who is the leader. Simple enough — until messages get lost.

Imagine three database replicas: A, B, and C. A proposes "I'll be leader". B says "OK". C's network drops. A assumes majority (A+B = 2/3) and becomes leader. Meanwhile C never heard from A, times out, and proposes itself as leader — B says "OK" to C too (B forgot it already voted for A). Now A and C are both leaders. Both accept writes. Both disagree. Data corruption.

This is the consensus problem. Paxos solves it with a deceptively simple insight: **once a value has been accepted by a majority, any future majority must overlap with the first one by at least one node**. That overlapping node ensures the new proposal cannot contradict the already-accepted value.

```
The key insight (Paxos safety invariant):

  Round 1: A proposes "Leader=A", gets accepted by {A, B}  (majority of 3)
  Round 2: C proposes "Leader=C", must get votes from majority
           C’s majority must include A or B (the only majority options from {A,B,C})
           A or B will report: "I already accepted Leader=A in round 1"
           → C must adopt "Leader=A" (cannot contradict the accepted value)

  Result: Even if C tries to win, it must adopt the same value. Safety guaranteed.
```

The Byzantine Generals Problem is a harder variant: what if some nodes actively lie? Paxos assumes nodes crash but don't lie. BFT (Byzantine Fault Tolerance) handles lying nodes, but requires 3f+1 nodes to tolerate f liars.

---

## Why Study Paxos

Paxos is the foundational consensus algorithm that every other consensus protocol is compared against. Google's Chubby, early versions of Google's distributed systems, Apache Zookeeper's ZAB protocol, and countless research papers are built on or compared to Paxos. Understanding it deeply separates principal engineers from senior engineers in distributed systems discussions.

---

## The Consensus Problem

**Formal definition:** A set of N processes must agree on a single value, with three properties:
- **Validity:** The decided value was proposed by some process (no values appear from nowhere)
- **Agreement:** No two non-faulty processes decide different values
- **Termination:** Every non-faulty process eventually decides (liveness)

**FLP Impossibility:** In an asynchronous system (no bounds on message delay), consensus is impossible if even one process can fail. Real systems work around this by using timeouts (accepting the possibility of incorrect suspicion) or bounded message delivery assumptions.

---

## Single-Decree Paxos

**Goal:** Get a set of nodes to agree on a single value (not a sequence of values).

### Roles

| Role | Description |
|------|-------------|
| **Proposer** | Initiates the protocol; proposes values |
| **Acceptor** | Votes on proposals; stores the accepted value |
| **Learner** | Learns the decided value; may be the same nodes as acceptors |

Typically, all nodes play all three roles.

### Phase 1: Prepare / Promise

```
Proposer                    Acceptors (majority)
    │                            │
    │── Prepare(n) ─────────────►│   n = unique proposal number (ballot)
    │                            │   Each acceptor:
    │                            │   IF n > highest seen promise:
    │                            │     Update promise: "won't accept < n"
    │                            │     Reply: Promise(n, accepted_value, accepted_n)
    │◄─ Promise(n, v_a, n_a) ────│   (v_a = previously accepted value, if any)
    │◄─ Promise(n, ∅, ∅) ────────│   (no previous acceptance)
```

**Proposer receives majority of promises:**
- If any acceptor reported a previously accepted value: proposer must use the value with the highest `accepted_n`
- If no previously accepted values: proposer is free to choose its own value

### Phase 2: Accept / Accepted

```
Proposer                    Acceptors (majority)
    │                            │
    │── Accept(n, v) ───────────►│   v = chosen value (either its own or highest accepted_n)
    │                            │   Each acceptor:
    │                            │   IF n ≥ promised_n:
    │                            │     Store (n, v) as accepted
    │                            │     Reply: Accepted(n, v)
    │◄─ Accepted(n, v) ──────────│
    │◄─ Accepted(n, v) ──────────│
    │                            │
    │ [receives majority Accepted → value v is DECIDED]
```

### Safety Invariant

**Once a value is chosen, no different value can be chosen.**

Proof sketch:
- Value v is chosen = majority accepted (n, v)
- Any future proposal must get promises from a majority
- At least one overlapping acceptor has accepted (n, v)
- It reports (n, v) in its promise → proposer must adopt v (highest accepted value)
- All future proposals also propose v

### Paxos Liveness Problem: Dueling Proposers

Two proposers can indefinitely prevent progress by preempting each other:

```
P1 sends Prepare(1) → gets promises
P2 sends Prepare(2) → invalidates P1's promises
P1 sends Prepare(3) → invalidates P2's ballot
P2 sends Prepare(4) → ...
```

**Fix:** Randomized backoff; leader election to ensure only one active proposer at a time (leads to Multi-Paxos).

---

## Multi-Paxos: Replicating a Log

Single-decree Paxos agrees on one value. A replicated state machine needs to agree on a sequence of commands (a log). Multi-Paxos achieves this by electing a stable leader and using a single Phase 1 per leader term (not per log entry).

### Key Optimization: Stable Leader

Once a leader completes Phase 1 for log index i, it can skip Phase 1 for all subsequent log entries and go straight to Phase 2 (Accept). This reduces the per-entry cost from 2 RTTs to 1 RTT.

```
Standard Paxos (per entry):
  Entry 1: Prepare → Promise → Accept → Accepted  (2 RTTs)
  Entry 2: Prepare → Promise → Accept → Accepted  (2 RTTs)

Multi-Paxos with stable leader:
  Phase 1 (once per term): Prepare → Promise (1 RTT)
  Entry 1: Accept → Accepted  (1 RTT)
  Entry 2: Accept → Accepted  (1 RTT)
  Entry N: Accept → Accepted  (1 RTT)
```

### What the Original Lamport Paper Doesn't Specify

Multi-Paxos as described by Lamport is intentionally underspecified. Real implementations must decide:
- How to elect a leader and handle leader failure
- How to fill gaps in the log (when some entries are missing)
- How to handle the case where multiple proposers start simultaneously
- When an entry is considered "committed" (applied to state machine)
- How to handle configuration changes (cluster membership)

These underspecifications led to many incompatible "Paxos-like" implementations, and is why Raft was created. (See `raft-consensus.md` for contrast.)

### Raft vs. Multi-Paxos

| Dimension | Multi-Paxos | Raft |
|-----------|-------------|------|
| Phase 1 per entry | No (skip with stable leader) | No (term-based; equivalent) |
| Log gaps | Possible (entries can be committed out of order) | Not possible (entries must be committed in order) |
| Leader election | Underspecified | Fully specified (randomized timeout, log comparison) |
| Leader completeness | Must replay from the beginning to fill gaps | Always has all committed entries (election restriction) |
| Configuration change | Underspecified | Joint consensus or single-server changes |
| Specification completeness | Partial | Complete |

**Performance difference:** Multi-Paxos allows out-of-order log entries (some implementations can commit entries out of order if there are no dependencies). Raft enforces strict ordering. In practice, the performance difference is small for typical workloads.

---

## EPaxos (Egalitarian Paxos)

### The Leader Bottleneck Problem

In Multi-Paxos / Raft, all writes must go through a single leader. The leader becomes the throughput bottleneck for write-intensive workloads.

### EPaxos Design

EPaxos (Moraru, Andersen, Kaminsky, 2013) allows **any replica to commit any command** without a leader, as long as there are no conflicts.

**Key insight:** Commands that operate on different keys are **commutative** — they can be reordered without changing the result. EPaxos exploits this to allow parallel commit paths for non-conflicting commands.

```
Replica 1 commits: SET key_a = 1  (no conflict with key_b)
Replica 2 commits: SET key_b = 2  (simultaneously, no conflict)
Both succeed without coordination
```

**For conflicting commands** (both write to the same key):
```
Replica 1 proposes: SET key_x = 1
Replica 2 proposes: SET key_x = 2  (conflict!)
Dependency tracking determines ordering
```

### EPaxos Performance

| Metric | Multi-Paxos | EPaxos |
|--------|-------------|--------|
| Throughput (non-conflicting) | Limited by leader | N× leader (parallelizable) |
| Throughput (conflicting) | Limited by leader | Similar to Multi-Paxos |
| Latency (single DC) | 1 RTT (stable leader) | 1 RTT (fast path) |
| Latency (multi-DC) | 1 RTT to leader + replication | 1 RTT to nearest majority |
| Complexity | Medium | High |
| Production adoption | Widespread | Limited (mainly research) |

**Why EPaxos isn't everywhere:** Correctness is extremely hard to verify. Dependency tracking and ordering resolution create complex edge cases. The single-leader bottleneck is usually not the actual bottleneck (network bandwidth and storage I/O often are).

---

## Byzantine Fault Tolerance

### The Byzantine Generals Problem

Lamport, Shostak, and Pease (1982) formalized the problem: N generals must agree on an attack plan; some may be traitors sending conflicting messages.

**Result:** With f traitors, you need at least **3f + 1** generals to achieve consensus.

Why 3f+1 (not 2f+1 as in crash-stop)?

```
With 3f+1 nodes:
  f nodes may be Byzantine (send conflicting messages)
  f nodes may be crashed/unreachable
  f+1 nodes are guaranteed to be honest and responsive

  A quorum of 2f+1 nodes is always achievable (3f+1 - f crashed = 2f+1)
  Within any quorum of 2f+1: at most f are Byzantine → majority (f+1) are honest

With 2f+1 nodes (as in Raft):
  If f nodes are Byzantine, they can masquerade as correct nodes
  A quorum of f+1 honest nodes cannot form without including Byzantines
```

### PBFT (Practical Byzantine Fault Tolerance)

Castro and Liskov (1999) showed that BFT consensus is practical with O(n²) messages.

**Normal case operation (3 phases):**

```
Client           Primary (Leader)        Replicas (f+1 of n-f)
  │                     │                        │
  │── Request ─────────►│                        │
  │                     │── PRE-PREPARE ─────────►│
  │                     │   (sequence number n,   │
  │                     │    digest of request)   │
  │                     │                        │ Each replica:
  │                     │◄── PREPARE ─────────────│ broadcasts PREPARE
  │                     │◄── PREPARE ─────────────│ waits for 2f+1 prepares
  │                     │                        │
  │                     │── COMMIT ──────────────►│ broadcasts COMMIT
  │                     │◄── COMMIT ───────────────│ waits for 2f+1 commits
  │                     │                        │
  │◄── Reply ───────────│                        │ All execute and reply
```

**Three phases:**
1. **Pre-prepare:** Leader sequences the request
2. **Prepare:** Replicas agree on the sequence number (prevents leader from equivocating)
3. **Commit:** Replicas agree to execute (prevents view changes from undoing executed requests)

### PBFT Performance

- **Messages per operation:** O(n²) — each of n nodes broadcasts to n nodes
- **Throughput:** ~10,000 req/s for 4 nodes (1 Byzantine fault) on a LAN
- **Not scalable:** Each additional node squares the message complexity
- **Practical limit:** ~100 nodes maximum; mostly used for small trusted clusters

### View Change (Leader Rotation)

When the primary is Byzantine or crashes, PBFT performs a view change:
- New view number v+1
- New primary is (v+1) mod n
- All replicas broadcast their log state
- New primary computes the "merged" log and broadcasts it
- O(n²) messages for view change as well

### Modern BFT: HotStuff and Tendermint

**HotStuff** (Facebook/Meta, 2019; basis for Diem/Libra blockchain): Achieves O(n) communication complexity for BFT by using threshold signatures and a linear view change. The leader aggregates signatures from n-f replicas rather than having all replicas broadcast to all.

**Tendermint** (used in Cosmos blockchain): Similar to PBFT but simpler; O(n²) but with better practical performance. Uses rotating leaders.

### Where BFT Is Used

| System | BFT Algorithm | Why |
|--------|--------------|-----|
| Hyperledger Fabric | PBFT variants | Enterprise blockchain; nodes are partially untrusted |
| Cosmos/Tendermint | Tendermint BFT | Public blockchain; validators may be adversarial |
| Diem (Libra) | HotStuff | Public blockchain; scalable BFT needed |
| Ethereum (PoS) | Casper FFG | Consensus over validator votes |
| Safety-critical systems | Various | Aerospace, nuclear; Byzantine sensors tolerated |

**Why BFT is NOT used in typical distributed databases:** Crash-stop model is sufficient. If nodes are in your own datacenter, you trust them. BFT is expensive and complex. 

---

## Google Chubby: Multi-Paxos in Production

Chubby (Mike Burrows, 2006) is Google's distributed lock service and file system for loosely-coupled distributed systems. It's the precursor to ZooKeeper.

**Key design choices:**
- Uses Multi-Paxos for replication across 5 cells (tolerates 2 failures)
- Exposes a file-system-like API (directories and files) rather than a raw consensus API
- Clients use **leases** to cache data and avoid hitting Chubby on every read
- Clients hold **advisory locks** (not mandatory locks) — Chubby doesn't enforce that only the lock holder can access the resource; clients are trusted to respect the lock

**Why file-system interface?** Locks, configuration, and small data can all be represented as files. Existing familiarity. The coarse-grained locking model (you get a lock on a file, not a row in a table) is appropriate for coordination.

**Chubby vs. ZooKeeper:**
- ZooKeeper: open-source, hierarchical namespace, watches (notifications), client-maintained session
- Chubby: Google-internal, leases, advisory locks, stronger read consistency guarantee
- Both use similar consensus protocols (ZAB for ZooKeeper, Paxos for Chubby)

---

## FAANG Interview Application

**When you'll be asked about this:**
- "How does Paxos work at a high level? How does it differ from Raft?"
- "When would you use BFT vs. crash-stop consensus?"
- "Google Spanner uses Paxos — how does that work?"
- "What's the performance trade-off between Multi-Paxos and EPaxos?"

**What they're evaluating:**
- Can you explain Single-Decree Paxos clearly, including Phase 1 and Phase 2?
- Do you understand the dueling proposers liveness issue?
- Can you articulate why Multi-Paxos exists (performance optimization for logs)?
- Do you know when BFT is actually needed vs. when it's overkill?

**Principal-level signal:**
Most candidates know "Paxos is a consensus algorithm." A principal engineer explains: "Single-decree Paxos gets a cluster to agree on one value in 2 RTTs. Multi-Paxos amortizes Phase 1 across log entries by maintaining a stable leader — after leader election, each entry only needs 1 RTT. Raft is essentially Multi-Paxos with a complete specification for log management, leader election, and membership changes. Google uses Multi-Paxos in Spanner as the replication protocol for each shard (Paxos group), combined with 2PC across shards for distributed transactions. The key interview insight is that Raft and Multi-Paxos are equivalent in the common case but Raft is implementation-complete while Multi-Paxos requires significant design decisions."

---

## Cross-References

- [raft-consensus.md](./raft-consensus.md) — complete Raft specification; how it differs from Multi-Paxos; production implementations
- [distributed-transactions.md](./distributed-transactions.md) — Spanner’s 2PC over Paxos groups; TrueTime commit-wait protocol
- [distributed-locking-and-coordination.md](./distributed-locking-and-coordination.md) — Chubby (Multi-Paxos for lock service); etcd (Raft for coordination)
- [failure-detection-and-recovery.md](./failure-detection-and-recovery.md) — FLP impossibility; how real systems work around it with timeouts
- [consistency-models.md](./consistency-models.md) — linearizability as the consistency guarantee that consensus algorithms provide
