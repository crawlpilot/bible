# Raft Consensus Protocol

**Paper:** "In Search of an Understandable Consensus Algorithm"  
**Authors:** Diego Ongaro and John Ousterhout (Stanford University)  
**Published:** USENIX ATC 2014 — Best Paper Award  
**Thesis:** Diego Ongaro's PhD dissertation (2014)

---

## The Problem Raft Solves

### Distributed Consensus

In a distributed system, multiple servers must agree on a single value or a sequence of operations — even when some servers fail or messages are delayed. This is the **consensus problem**.

**Why it's hard:**
- Servers fail (crash, restart, become unreachable)
- Networks partition (messages delayed, dropped, reordered)
- You cannot distinguish a slow server from a dead server
- CAP theorem: during a partition, you must choose between consistency and availability

**What consensus enables:**
- Replicated state machines — all replicas apply the same commands in the same order → identical state
- Fault-tolerant coordination — leader election, distributed locks, configuration management
- Strong consistency guarantees — linearizability across a cluster

### The Replicated State Machine Model

```
  Client
    │
    ▼
┌───────────────────────────────────────────────────────┐
│ Server 1 (Leader)     Server 2 (Follower)   Server 3  │
│ ┌─────────────┐       ┌─────────────┐       ┌───────┐ │
│ │  Log        │  ───► │  Log        │  ───► │  Log  │ │
│ │  [x←3]      │       │  [x←3]      │       │ [x←3] │ │
│ │  [y←1]      │       │  [y←1]      │       │ [y←1] │ │
│ └──────┬──────┘       └──────┬──────┘       └───┬───┘ │
│        │                     │                   │     │
│        ▼                     ▼                   ▼     │
│  State Machine         State Machine       State Machine│
│  x=3, y=1              x=3, y=1            x=3, y=1   │
└───────────────────────────────────────────────────────┘
```

**Invariant:** If two state machines start in the same state and apply the same sequence of log entries, they end in the same state.

Consensus ensures every non-faulty server applies the same log entries in the same order.

---

## Why Not Paxos?

Paxos was the dominant consensus algorithm for 20 years (Lamport, 1989, 1998). Raft was designed as a direct response to Paxos's problems.

| Dimension | Paxos | Raft |
|-----------|-------|------|
| Understandability | Notoriously hard to understand | Designed for understandability first |
| Specification | Single-decree (one value); Multi-Paxos underspecified | Specifies full replicated log management |
| Leader election | Underspecified | Explicit, deterministic algorithm |
| Log management | Not described in original paper | Log matching, compaction, membership change all specified |
| Implementation difficulty | High — many implementation variants exist | Lower — single canonical algorithm |
| Real-world implementations | Few direct; many "Paxos-inspired" variants | Many direct: etcd, CockroachDB, TiKV, Consul |

Ongaro's user study in the paper showed participants consistently understood Raft better than Paxos after studying both — the paper's core empirical claim.

---

## How Raft Works

Raft decomposes consensus into three relatively independent subproblems:

1. **Leader election** — choose one server as leader; re-elect if it fails
2. **Log replication** — leader accepts entries, replicates to followers, ensures agreement
3. **Safety** — ensure at most one leader per term; ensure committed entries are never lost

### Cluster Topology

Raft operates over a cluster of `2f + 1` servers, tolerating up to `f` failures. A **majority** (`f + 1`) is required for every operation.

| Cluster size | Faults tolerated | Majority needed |
|-------------|-----------------|----------------|
| 3 | 1 | 2 |
| 5 | 2 | 3 |
| 7 | 3 | 4 |

### Server States

Each server is in one of three states at any time:

```
           timeout / no heartbeat
    ┌──────────────────────────────────┐
    │                                  ▼
 Follower ──── starts election ──► Candidate ──── wins election ──► Leader
    ▲                                  │                               │
    └──────── discovers leader ◄───────┘                               │
    └──────── discovers higher term ◄─────────────────────────────────┘
```

- **Follower**: Passive. Responds to requests from leaders and candidates. If it receives no heartbeat within the election timeout, it becomes a candidate.
- **Candidate**: Attempts to be elected leader. Votes for itself, sends RequestVote RPCs to all others.
- **Leader**: Handles all client requests. Sends periodic heartbeats (empty AppendEntries RPCs) to prevent elections. Replicates log entries to followers.

---

## Terms

Raft divides time into **terms** — monotonically increasing integers. Terms serve as a logical clock.

```
Term 1          Term 2    Term 3 (no leader)  Term 4
│← Election →│← Leader →│← Election, split →│← Leader →│
     │                          │
  Leader                  No consensus;
  elected                 new election
```

- Each term begins with an election
- If a candidate wins → it is leader for the rest of the term
- If no winner (split vote) → term ends; new term starts
- Each server tracks `currentTerm`; when it receives a message with a higher term, it updates its term and reverts to follower

**Key invariant:** At most one leader can be elected per term. This is enforced by the voting rule — each server votes for at most one candidate per term.

---

## Leader Election in Detail

### Triggering an Election

A follower becomes a candidate when its **election timeout** expires without receiving a heartbeat from the current leader. The timeout is chosen randomly from a range (e.g., 150–300ms) to reduce split votes.

### Election Process

```
Candidate (S1)           Follower (S2)           Follower (S3)
    │                         │                        │
    │── RequestVote ──────────►│                        │
    │── RequestVote ──────────────────────────────────►│
    │                         │                        │
    │◄─ vote granted ─────────│                        │
    │◄─ vote granted ─────────────────────────────────│
    │                         │                        │
   [wins majority → becomes leader]
    │                         │                        │
    │── AppendEntries (heartbeat) ──────────────────►│
    │── AppendEntries (heartbeat) ──────────────────►│
```

**RequestVote RPC:**
```
Arguments:
  term          // candidate's current term
  candidateId
  lastLogIndex  // index of candidate's last log entry
  lastLogTerm   // term of candidate's last log entry

Response:
  term          // currentTerm (so candidate can update itself)
  voteGranted   // true if candidate receives vote
```

**Voting rule (two conditions must both be true):**
1. The candidate's term ≥ voter's currentTerm
2. The candidate's log is at least as up-to-date as the voter's log (**election restriction** — see Safety section)

Each server grants at most one vote per term (first-come, first-served).

### Split Votes

If two candidates start simultaneously, votes may split — neither reaches majority. The term expires, and each candidate randomly delays before starting a new election. The randomized timeout makes it unlikely both restart at the same time.

---

## Log Replication in Detail

### Log Structure

Each entry in the log contains:
- **Index**: 1-based position in the log
- **Term**: the term when the leader created this entry
- **Command**: the state machine command

```
Index:   1    2    3    4    5    6    7
Term:    1    1    1    2    3    3    3
Command: x←3  y←1  y←9  x←2  z←1  y←7  x←5
                                    ↑
                              commitIndex=6
                              (entries 1-6 are committed)
```

### AppendEntries RPC

The leader uses this for two purposes: heartbeats (empty) and log replication.

```
Arguments:
  term          // leader's current term
  leaderId      // so followers can redirect clients
  prevLogIndex  // index of log entry immediately before new ones
  prevLogTerm   // term of prevLogIndex entry
  entries[]     // log entries to store (empty for heartbeat)
  leaderCommit  // leader's commitIndex

Response:
  term          // currentTerm, for leader to update itself
  success       // true if follower contained matching prevLogIndex/prevLogTerm
```

### Replication Flow

```
Client                    Leader                  Follower (majority)
  │                          │                          │
  │── command ──────────────►│                          │
  │                          │ append to local log      │
  │                          │── AppendEntries ────────►│
  │                          │                          │ append to log
  │                          │◄─ success ───────────────│
  │                          │                          │
  │                    [majority replied success]
  │                          │ advance commitIndex      │
  │                          │── AppendEntries ────────►│ (next heartbeat carries
  │◄─ response ──────────────│   (leaderCommit updated)  │  updated commitIndex)
  │                          │                          │ apply to state machine
```

**An entry is committed** once the leader knows it has been stored on a majority of servers. The leader then applies it to its state machine and notifies followers via the next AppendEntries.

### Log Consistency Check

The `prevLogIndex` and `prevLogTerm` fields enforce the **Log Matching Property**:

> If two log entries have the same index and term, they are identical. All entries before them are also identical.

A follower rejects an AppendEntries if its log doesn't contain an entry at `prevLogIndex` with term `prevLogTerm`. The leader then decrements `nextIndex` for that follower and retries — walking back until finding the divergence point, then replaying from there.

This means the leader's log always wins — followers overwrite conflicting entries.

---

## Safety

Safety is Raft's guarantee that committed entries are never lost, even across leader changes.

### The Election Restriction

**A candidate can only win an election if its log is at least as up-to-date as the majority of the cluster.**

"Up-to-date" comparison:
1. If logs have different last terms → the log with the higher last term is more up-to-date
2. If logs have the same last term → the longer log is more up-to-date

**Why this works:** Any committed entry must be present on a majority of servers. A new leader must have received votes from a majority. At least one server in any two majorities overlaps → that server voted for the leader → the leader had a log at least as up-to-date as the overlap server → the leader has the committed entry.

```
Committed entry at index 7:
  Server 1: [... 7]  ← voted for new leader
  Server 2: [... 7]  ← voted for new leader
  Server 3: [... 7]  ← new leader (has entry at index 7)
  Server 4: [... 5]  ← did NOT vote (log too short)
  Server 5: [... 5]  ← did NOT vote (log too short)

New leader has the committed entry. ✓
```

### Only-Leader-Append Rule

Leaders never overwrite or delete their own log entries. They only append. Followers may have entries overwritten by the leader's log, but only uncommitted entries can be overwritten.

### Commit Rules

A leader commits an entry when it has been replicated to a majority. However, there is a subtle case: a leader cannot commit entries from *previous* terms by count alone — only by committing a current-term entry that happens to drag older entries along.

This prevents the following scenario:

```
Scenario (unsafe without the rule):
  Term 2 entry at index 3 replicated to S1, S2, S3 (majority).
  Leader (S1) crashes. S5 becomes leader (term 3).
  S5 has an older log but wins election from S3, S4, S5.
  S5 replicates its own entry at index 3, overwriting the term-2 entry.
  
  If the term-2 entry had been "committed", this violates safety.

Raft's fix: Leaders commit only entries from their own term.
  Entries from prior terms are committed implicitly when a current-term entry is committed.
```

---

## Cluster Membership Changes

### The Problem

Changing cluster size naively (e.g., switching from 3 to 5 servers instantaneously) creates a window where two disjoint majorities could exist:

```
Old config: {S1, S2, S3}     majority = 2
New config: {S1, S2, S3, S4, S5}  majority = 3

Transition window: old majority {S1,S2} and new majority {S3,S4,S5}
could elect two different leaders simultaneously.
```

### Joint Consensus (Original Raft)

Raft's original approach uses a two-phase transition through a **joint configuration** C_old,new:
- The cluster operates under both configurations simultaneously
- Log entries must be committed on a majority in both C_old AND C_new
- Only after C_old,new is committed does the cluster transition to C_new

### Single-Server Changes (Simplified, Practical)

Diego Ongaro's dissertation also describes a simpler approach: add or remove one server at a time. Since single-server changes can never create two disjoint majorities (going from 3→4 or 5→4 is safe), this is used in most real implementations (etcd, Consul).

---

## Log Compaction (Snapshots)

Without compaction, the log grows unboundedly and replay after restart takes too long.

### Snapshot Approach

Each server independently takes a snapshot of its state machine state up to some commit index, then discards the log entries covered by the snapshot.

```
Before snapshot:
Index:   1    2    3    4    5    6    7    8    9
         [committed entries]           [future]

After snapshot at index 6:
┌──────────────────────┐    7    8    9
│  Snapshot            │   [kept for replication]
│  lastIncludedIndex=6 │
│  lastIncludedTerm=3  │
│  State: {x:3,y:1}    │
└──────────────────────┘
```

**InstallSnapshot RPC:** Used when a leader needs to send state to a very lagging follower (its log no longer covers the entries the follower needs). The leader ships the entire snapshot to the follower.

---

## The Paper: "In Search of an Understandable Consensus Algorithm"

### Core Thesis

Ongaro and Ousterhout's central argument: **understandability should be a first-class design goal for consensus algorithms**. Paxos was designed for correctness; Raft was designed for correctness *and* understandability. Understandable algorithms are less likely to be implemented incorrectly.

### Design Decisions Motivated by Understandability

| Decision | Alternative | Why Raft chose its approach |
|----------|------------|----------------------------|
| Strong leader | Symmetric peers | Simpler data flow — all decisions centralized at leader |
| Randomized election timeouts | Ranked (priority) elections | Avoids complex ranking logic; randomization breaks ties naturally |
| Joint consensus for membership | Other multi-phase approaches | Provides a clean, analyzable safety argument |
| Log matching property | Other log consistency schemes | Single invariant that's easy to reason about |

### Empirical Evaluation

The paper's most unusual claim is backed by a user study:
- 43 students at Stanford (enrolled in two courses)
- Half studied Raft first, then Paxos; half the reverse
- Raft questions answered correctly at a statistically higher rate
- Qualitative interviews: students found Raft more intuitive

This was controversial — user studies in distributed systems papers were rare. But it grounded the "understandability" claim in data.

### Correctness Properties Proved in the Paper

| Property | Guarantee |
|----------|-----------|
| Election Safety | At most one leader per term |
| Leader Append-Only | Leader never overwrites its log |
| Log Matching | If two logs have same (index, term), all prior entries identical |
| Leader Completeness | If entry committed in term T, all future leaders have it |
| State Machine Safety | If server applies entry at index i, no other server applies a different entry at index i |

### Key Theorem: Leader Completeness

This is the core safety theorem. Proof sketch (by contradiction):
1. Assume entry E committed in term T is missing from leader L in term U (U > T)
2. E was committed → present on majority M_T
3. L was elected → received votes from majority M_U
4. M_T ∩ M_U ≠ ∅ (by pigeonhole) → server V is in both
5. V voted for L → L's log was at least as up-to-date as V's
6. V has E (it's in M_T and E was committed before V voted for L)
7. But L's log is at least as up-to-date as V's → L has E. Contradiction. □

---

## Performance Characteristics

### Normal Operation (no failures)

- **Write latency:** 1 network round-trip (leader → followers) + disk write = ~1–5ms in a LAN cluster
- **Throughput:** Pipelining allows multiple in-flight log entries; batching amortizes fsync cost
- **Read performance:** Reads from leader guarantee linearizability; followers can serve stale reads

### Under Failures

- **Leader crash detection:** Election timeout (150–300ms typical); new leader elected in 1–2 timeouts
- **Follower crash:** No impact on availability; leader retries indefinitely
- **Network partition:** Minority partition loses availability (cannot form majority); majority partition continues normally

### Practical Latency Numbers (etcd benchmark, 3-node cluster, same datacenter)

| Operation | Typical latency |
|-----------|----------------|
| Write (linearizable) | 1–5 ms |
| Read (linearizable via leader) | 1–5 ms |
| Read (serializable, follower) | < 1 ms |
| Leader election | 150–500 ms |

---

## Where Raft Is Used in Production

### etcd

The most widely deployed Raft implementation. Powers Kubernetes (control plane state, service discovery, distributed locks).
- All Kubernetes cluster state stored in etcd
- Every API server write goes through Raft consensus
- At 1000-node clusters, etcd handles ~1000 writes/sec with 3-5 node etcd clusters
- etcd v3 uses a custom Raft library (`go.etcd.io/raft`) extracted as a standalone package

### CockroachDB

Distributed SQL database; uses Raft per range (key range shard).
- Each 64MB range is an independent Raft group
- A 3-node cluster may have thousands of Raft groups running simultaneously
- **Multi-Raft optimization:** batches Raft messages across groups to reduce RPC overhead
- Uses joint consensus for range splits and merges

### TiKV / TiDB

TiKV (used by TiDB, the distributed MySQL-compatible DB) implements Raft per region (also ~96MB key ranges). TiDB's TiFlash columnar storage also uses Raft for replication.

### Consul

HashiCorp's service mesh and KV store uses Raft (via HashiCorp's own `hashicorp/raft` library — the most widely adopted Raft library after etcd's). Consul uses Raft for its catalog, health checks, and config store.

### Others

| System | Use of Raft |
|--------|-------------|
| InfluxDB (IOx) | Raft for replication in new storage engine |
| ScyllaDB | Raft-based tablets mode (replacing Gossip + LWT for topology) |
| YugabyteDB | Raft per tablet (similar to CockroachDB/TiKV) |
| MongoDB | Uses a Raft-like protocol (not pure Raft) for replica set elections |
| Kafka (KRaft mode) | Replaces ZooKeeper; uses Raft for controller quorum (since Kafka 3.x, generally available 4.0) |
| ClickHouse Keeper | ZooKeeper replacement using Raft (used instead of ZooKeeper for ClickHouse coordination) |
| NATS JetStream | Raft for stream metadata and replication |

---

## Raft vs. Other Consensus Protocols

### Raft vs. Paxos

| Dimension | Raft | Multi-Paxos |
|-----------|------|-------------|
| Leader | Explicit, single leader | Implicit; "distinguished proposer" |
| Log entries | Append-only from leader | Can be filled by any acceptor |
| Correctness argument | Single self-contained proof | Distributed across papers |
| Implementation | One canonical algorithm | Many incompatible variants |
| Membership change | Specified (joint/single-server) | Not specified in original |

### Raft vs. Viewstamped Replication (VR)

VR (Liskov & Cowling, 2012) is structurally similar to Raft — both have a view (term), a leader, log replication, and commit. Raft was designed independently and makes different low-level choices. VR uses a "prepare" + "commit" two-message commit vs. Raft's single AppendEntries.

### Raft vs. Zab (ZooKeeper Atomic Broadcast)

Zab is ZooKeeper's protocol. Conceptually similar to Raft but:
- Designed specifically for ZooKeeper's primary-backup model
- Epochs instead of terms; zxid for log position
- Transactions go through a 2-phase "propose + commit" flow
- Less general than Raft (not a pure RSM protocol)

### Raft vs. EPaxos (Egalitarian Paxos)

EPaxos allows any replica to commit non-conflicting commands in parallel without a leader bottleneck. Higher throughput for independent operations; much more complex correctness argument. No major production deployment as widely adopted as Raft.

---

## Raft Failure Modes and Edge Cases

### Network Partition Scenarios

**Scenario 1: Leader is partitioned into minority**
```
  Partition A (minority): Old Leader (S1), S2
  Partition B (majority): S3, S4, S5

  - S1 keeps sending heartbeats to S2; neither can commit (no majority)
  - S3/S4/S5 elect a new leader in a higher term
  - When partition heals: S1 receives message with higher term → reverts to follower
  - S1's uncommitted entries are overwritten by new leader's log
```

**Scenario 2: Follower isolated**
- No impact on availability
- Follower's log diverges
- When it reconnects, leader sends missing entries (or snapshot if too far behind)

### Spurious Leader Elections

If the leader is slow to send heartbeats (GC pause, high CPU), followers may time out and start elections unnecessarily. Mitigation: PreVote extension (Ongaro's dissertation) — candidate checks if it *would* win an election before incrementing its term, preventing disruptive term increments.

### Linearizable Reads Without Log Entries

Naively, a leader could serve a stale read if it doesn't know it's been superseded. Two solutions:
1. **ReadIndex:** Leader sends a heartbeat to confirm it's still leader before responding to reads
2. **Lease-based reads:** Leader holds a timed lease; reads can be served without RPC during the lease window (requires synchronized clocks; used in CockroachDB and TiKV)

---

## Implementation Notes

### The Five Most Common Implementation Bugs

1. **Not handling `currentTerm` updates atomically with role change** — if a node receives a higher term in a response but doesn't immediately revert to follower, split-brain can occur
2. **Voting for a candidate that's behind in log** — violates election restriction; leads to data loss
3. **Committing entries from previous terms by count** — the safety bug described in the paper; fixed by committing only current-term entries
4. **Not persisting `currentTerm`, `votedFor`, and the log before responding to RPCs** — fsync must happen before ACK; otherwise a crash-recovery can violate invariants
5. **Applying committed entries before persisting them** — the commit must survive restart before affecting the state machine

### Persistence Requirements

Three things must be persisted to stable storage before responding to any RPC:
- `currentTerm` — prevent voting for two candidates in the same term after restart
- `votedFor` — prevent the same
- `log[]` — prevent loss of acknowledged entries

Everything else (commitIndex, lastApplied, leader state, nextIndex, matchIndex) can be reconstructed.

---

## FAANG Interview Application

**Likely interview questions:**
- "How does Raft achieve consensus? Walk me through a write operation."
- "What happens if the Raft leader crashes? How is a new leader elected?"
- "How does etcd use Raft, and what are its consistency guarantees?"
- "What's the difference between Raft and Paxos?"
- "In your distributed cache design, how would you handle leader election for replicas?"
- "What are the trade-offs of using Raft vs. a gossip-based protocol like Cassandra's?"

**What interviewers are probing:**
- Do you understand the consistency model (linearizable writes, quorum reads)?
- Can you reason about failure modes — what happens when N of 5 nodes fail?
- Do you know what systems in the stack you're designing use Raft?
- Can you articulate the CAP trade-off Raft makes (CP — sacrifices availability during partition)?

**Principal-level framing:**

When designing any system that requires strong consistency:
- **Choose Raft-based stores (etcd, Consul, ZooKeeper) for coordination data** — small datasets, high consistency requirements: locks, leader election, config, service registry
- **Do not put application data in Raft-based stores** — they are not designed for high-throughput application writes; etcd recommends < 8GB total data
- **Understand the availability trade-off** — a 3-node Raft cluster can survive 1 failure; if you need 2-failure tolerance, you need 5 nodes. Sizing matters.
- **Latency budget** — Raft adds 1 RTT to every write. In a 3-region setup, this can be 50–150ms. If your SLO can't absorb this, Raft (or any CP system) is the wrong choice.

**The key insight to deliver in an interview:**

> Raft trades availability for consistency — during a partition, the minority partition becomes unavailable rather than accepting writes that might conflict with the majority. This is the right trade-off for coordination data (locks, config, leader election) but the wrong trade-off for user-facing writes at scale. That's why you'd use etcd to elect a shard leader, but Cassandra (AP) to store the shard data.

---

## Cross-References

- [paxos-and-consensus-variants.md](./paxos-and-consensus-variants.md) — Single-decree Paxos, Multi-Paxos, EPaxos; what Raft improves on
- [distributed-locking-and-coordination.md](./distributed-locking-and-coordination.md) — etcd (Raft-based) used for distributed locks, leader election, and fencing tokens
- [failure-detection-and-recovery.md](./failure-detection-and-recovery.md) — election timeout as failure detector; quorum enforcement preventing split-brain
- [consistency-models.md](./consistency-models.md) — linearizability guarantee Raft provides (ReadIndex protocol for linearizable reads)
- [write-ahead-log-and-storage-internals.md](./write-ahead-log-and-storage-internals.md) — Raft log as a WAL; snapshot + log recovery; the log as universal primitive
---

## Cross-References

- [paxos-and-consensus-variants.md](./paxos-and-consensus-variants.md) — Single-decree Paxos, Multi-Paxos, EPaxos; what Raft improves on
- [distributed-locking-and-coordination.md](./distributed-locking-and-coordination.md) — etcd (Raft-based) used for distributed locks, leader election, and fencing tokens
- [failure-detection-and-recovery.md](./failure-detection-and-recovery.md) — election timeout as failure detector; quorum enforcement preventing split-brain
- [consistency-models.md](./consistency-models.md) — linearizability guarantee Raft provides (ReadIndex protocol for linearizable reads)
- [write-ahead-log-and-storage-internals.md](./write-ahead-log-and-storage-internals.md) — Raft log as a WAL; snapshot + log recovery; the log as universal primitive