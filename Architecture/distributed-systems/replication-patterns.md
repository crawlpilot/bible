# Replication Patterns

## The Core Problem (Start Here)

Netflix runs on a single PostgreSQL database. On a busy Friday night, 10 million users stream simultaneously. The database can’t handle 10 million reads/sec. You spin up 5 read replicas. Problem solved — until:

```
User updates their profile picture:
  Write → Leader (replicated async to followers)

User immediately refreshes the page → routed to Follower 3 (lag: 200ms)
  Read returns OLD profile picture
  User: "My upload didn’t work!" → uploads again → double upload

Second problem (multi-leader, active-active):
  User edits name in US datacenter → "Alice Smith"
  Same user edits name in EU datacenter (offline, syncs) → "Alice Müller"
  Both committed. Which is correct? Last-write-wins? User decides? Neither is great.
```

Replication topology determines which anomalies you accept. Single-leader is simple but has lag. Multi-leader accepts writes everywhere but must resolve conflicts. Leaderless (Dynamo-style) tunes the trade-off with quorum math (R + W > N).

---

## Why Replication

Three reasons to replicate data across multiple nodes:
1. **Fault tolerance** — survive node failures without losing data or availability
2. **Read scalability** — distribute read load across replicas
3. **Geographic locality** — serve users from nearby datacenters

Three fundamental replication topologies exist, each with distinct trade-offs.

---

## 1. Single-Leader Replication (Primary-Replica)

### Architecture

One node is the **leader** (primary/master). All writes go to the leader. The leader applies the write and propagates it to **followers** (replicas/secondaries). Reads can go to the leader (strong consistency) or followers (potentially stale).

```
                    ┌─────────────────┐
  Client Writes ───►│   LEADER        │
                    │  (accepts all   │
                    │   writes)       │
                    └────────┬────────┘
                             │ replication stream
                  ┌──────────┼──────────┐
                  ▼          ▼          ▼
             ┌────────┐ ┌────────┐ ┌────────┐
  Reads ────►│Follower│ │Follower│ │Follower│
             └────────┘ └────────┘ └────────┘
```

### Replication Methods

**Statement-based replication:** Leader logs each write statement (INSERT, UPDATE, DELETE) and sends it to followers. Problem: non-deterministic functions (NOW(), RAND(), auto-increment) produce different results on replicas.

**Write-ahead log (WAL) shipping:** Leader ships its WAL to followers, which replay the log. Used by PostgreSQL streaming replication. Tight coupling to storage format — upgrading major versions requires coordinated migration.

**Row-based (logical) replication:** Leader logs the actual row changes (before/after images), not the SQL. Used by MySQL binlog (row format), PostgreSQL logical replication. More bandwidth but deterministic; allows schema differences between leader and followers.

### Synchronous vs. Asynchronous Replication

| Mode | Description | Durability | Latency | Availability |
|------|------------|-----------|---------|-------------|
| Synchronous | Leader waits for follower ACK before returning to client | Guaranteed (data on ≥ 2 nodes) | Higher (+follower RTT) | Lower (blocked if follower slow) |
| Asynchronous | Leader returns to client immediately; follower catches up | At risk (data may be in leader log only) | Lower | Higher (follower lag doesn't affect writes) |
| Semi-sync | Leader waits for ACK from exactly 1 follower | Guaranteed on 2 nodes | Medium | Medium |

**MySQL semi-synchronous replication:** At least one follower must ACK before the leader returns to client. Default in production MySQL setups.

**PostgreSQL synchronous_commit:** Configurable per-transaction: `remote_apply` (follower has applied), `remote_write` (follower has written to OS buffer), `local` (leader WAL only), `off` (async).

### Replication Lag

Asynchronous replication introduces **replication lag** — the delay between a write on the leader and its appearance on followers. Typical values: milliseconds in LAN; seconds under high write load; minutes after follower restart.

**Replication lag anomalies:**

**Read-your-writes violation:**
```
User writes profile photo at T=100ms
User's next request is routed to follower with lag T=50ms
User sees old photo → "my upload didn't work"
```
*Fix:* Route reads to leader for 1 minute after a write; or carry a "read-after-write" token with the write's LSN and wait until the replica's LSN ≥ token.

**Monotonic reads violation:**
```
User reads at T=0 from Follower A (lag: 0ms) → sees post P
User reads at T=1 from Follower B (lag: 500ms) → doesn't see post P
User reads at T=2 from Follower A → sees post P again
```
*Fix:* Pin a user to a single replica for the session (sticky sessions).

**Consistent prefix reads violation:**
```
DB contains causal sequence: Q then A
Follower replicates A before Q (out of order replication)
User sees A before Q — reads the answer before the question
```
*Fix:* Causal tracking; ensure dependent writes replicate to the same partition/shard.

### Failover

When the leader fails:
1. Detect failure (heartbeat timeout: 30–60s default in MySQL/Postgres)
2. Elect a new leader — typically the follower with the most up-to-date replication position
3. Redirect clients to the new leader
4. Former leader (if it recovers) must become a follower

**Failover risks:**
- **Split-brain:** Old leader recovers and doesn't know it was replaced; two nodes accept writes simultaneously. Fix: STONITH (shoot the old leader), fencing tokens.
- **Data loss:** If the new leader was behind the old leader's committed writes, those writes are lost. Fix: synchronous replication; or accept the loss and use smaller RPO.
- **Stale client cache:** Clients still routing to old leader IP. Fix: virtual IP failover (AWS: Route53 health checks, or promote a replica's IP), connection pool reconnect logic.

### Production Systems

- **PostgreSQL:** Streaming replication (WAL-based), Patroni for automated failover, PgBouncer for connection pooling
- **MySQL:** Binlog replication, Group Replication (Paxos-based), ProxySQL for routing
- **MongoDB:** Replica sets, Raft-like election protocol, arbiter nodes
- **Redis:** Primary-replica with Sentinel for automated failover; Redis Cluster for sharding

---

## 2. Multi-Leader Replication

### Architecture

Multiple nodes accept writes independently. Each leader replicates its writes to all other leaders and their followers.

```
  Datacenter A              Datacenter B
  ┌──────────┐              ┌──────────┐
  │ Leader A │◄────sync────►│ Leader B │
  └────┬─────┘              └────┬─────┘
       │ replication              │ replication
  ┌────▼─────┐              ┌────▼─────┐
  │Follower 1│              │Follower 3│
  │Follower 2│              │Follower 4│
  └──────────┘              └──────────┘
```

### When to Use It

- **Multi-datacenter active-active:** writes accepted in each datacenter, replicated async between DCs. Network partition between DCs doesn't block writes.
- **Offline-capable clients:** each device is its own "leader" (Google Docs offline mode, calendar sync).
- **Collaborative editing:** multiple users editing the same document (requires CRDT or OT for conflict resolution).

### The Conflict Problem

Multi-leader inevitably creates **write conflicts** when two leaders accept concurrent writes to the same record.

```
Leader A: User changes username from "alice" to "alice_new" at T=100ms
Leader B: Same user changes username from "alice" to "alice2"   at T=101ms
(both unaware of the other's write)

When replication reaches both leaders: CONFLICT
```

**Conflict avoidance:** Route all writes for a given user/key to the same leader. Not always possible.

**Last-Write-Wins (LWW):** Each write has a timestamp; the higher timestamp wins. Simple; loses the "losing" write. Requires clock synchronization (dangerous — see `time-and-causality.md`). Used by Cassandra.

**Merge on conflict:** Keep both values and present both to the application. The application (or CRDT) merges them. Used by CouchDB (multi-value documents), Riak (siblings).

**Custom resolution logic:** Application-provided conflict handler. Used by DynamoDB Global Tables (last-writer-wins by default, or custom Lambda).

### Production Systems

- **MySQL Group Replication:** Multi-primary mode with Paxos-based conflict detection
- **CouchDB:** Multi-master, MVCC, document revision history for conflict resolution
- **DynamoDB Global Tables:** Async multi-region replication, LWW
- **Cassandra:** Multi-DC active-active, LWW per column, read repair

---

## 3. Leaderless Replication (Dynamo-Style)

### Architecture

No leader. Clients send writes/reads to multiple replicas directly (or via a coordinator that acts on the client's behalf). Consistency is enforced by **quorums**.

```
  Client
    │
    ├──── Write ────►│ Replica 1 │
    ├──── Write ────►│ Replica 2 │
    └──── Write ────►│ Replica 3 │

  Write succeeds when W replicas ACK
  Read succeeds when R replicas respond

  If R + W > N → guaranteed to overlap at least 1 up-to-date replica
```

### Quorum Reads and Writes

With N replicas, W write quorum, R read quorum:
- **R + W > N:** Guarantees that at least one replica in every read quorum has the latest write
- **W > N/2:** Protects against conflicting writes (only one majority can commit)
- **R > N/2:** Guarantees reading from a majority that includes the latest write

Common configuration: **N=3, W=2, R=2** (classic quorum, tolerates 1 failure)

| Configuration | Characteristic |
|---------------|---------------|
| W=1, R=N | Fast writes, slow reads, any write is always readable |
| W=N, R=1 | Slow writes, fast reads, durability on all nodes |
| W=2, R=2, N=3 | Balanced; tolerates 1 failure for both reads and writes |
| W=1, R=1 | Fastest, no consistency guarantee |

### Sloppy Quorum and Hinted Handoff

**Sloppy quorum:** During a network partition, if the usual quorum nodes are unreachable, the write is accepted by any W available nodes — even nodes not normally responsible for this data range.

**Hinted handoff:** The accepting node notes: "I'm holding this write temporarily on behalf of node X. When X recovers, I'll forward it."

```
Normal: Write to nodes [1, 2, 3]
Partition: Node 3 unreachable
Sloppy quorum: Write to nodes [1, 2, 4] (node 4 hints: "deliver to 3 when it's back")
Node 3 recovers: Node 4 sends the hinted write to Node 3
```

**Trade-off:** Sloppy quorum improves availability but weakens the R+W>N guarantee — a read quorum may not include the sloppy nodes that accepted writes.

### Anti-Entropy (Read Repair + Merkle Trees)

**Read repair:** When a client reads from multiple replicas and gets different values, it writes the newest value back to the stale replicas. Happens synchronously during the read. Good for frequently-read data; stale data that is never read may persist indefinitely.

**Anti-entropy background process:** A background process compares replicas and synchronizes differences. Uses **Merkle trees** (hash trees) to efficiently identify divergent ranges without comparing every row.

```
Merkle tree comparison:
Root hash mismatch → compare subtrees
  Left subtree: hash match → skip
  Right subtree: hash mismatch → compare children
    ...
    Leaf: key K differs → sync key K

Only transfer the differing rows, not the entire dataset.
```

*Cross-reference: `DSA/system-design-ds/merkle-tree.md` for Merkle tree mechanics.*

### Cassandra: Tunable Consistency

Cassandra implements leaderless replication with configurable consistency levels per operation:

| Level | Meaning |
|-------|---------|
| ONE | 1 replica must respond |
| QUORUM | ceil((RF+1)/2) replicas must respond |
| LOCAL_QUORUM | Quorum within local datacenter only |
| EACH_QUORUM | Quorum in each datacenter |
| ALL | All replicas must respond |
| ANY | Even a hint is sufficient (write) |

**RF=3, QUORUM=2:** Tolerates 1 node failure. Read+Write QUORUM ensures strong consistency.  
**RF=3, LOCAL_QUORUM:** Multi-DC setup; strong within one DC, async to others. Best balance of consistency and cross-DC latency.

---

## Replication in Kafka (In-Sync Replicas)

Kafka's replication model is a hybrid:
- **Leader-based:** Each partition has one leader broker; all reads and writes go to the leader
- **ISR (In-Sync Replicas):** A set of replicas that are "caught up" with the leader (within replica.lag.time.max.ms, default 10s)
- **Committed offset:** A message is committed only when all ISR members have acknowledged it
- **min.insync.replicas:** Minimum number of ISR required for a write to succeed. Setting min.insync.replicas=2 with replication.factor=3 means: at least 2 replicas must have the data before the producer gets an ACK.

```
Producer → Leader Partition
              │
              ├── Follower 1 (in ISR, lag: 5ms)
              ├── Follower 2 (in ISR, lag: 12ms)
              └── Follower 3 (not in ISR, lag: 12s → lagging too far)

Commit: offset N is committed when Leader + Follower 1 + Follower 2 have it (ISR quorum)
```

---

## Comparison: Three Replication Topologies

| Dimension | Single-Leader | Multi-Leader | Leaderless |
|-----------|-------------|-------------|-----------|
| Write scalability | Limited to leader | Scales across leaders | Scales across all nodes |
| Read scalability | Good (followers) | Good | Good |
| Conflict possibility | None | Yes (concurrent writes to multiple leaders) | Yes (if W+R ≤ N) |
| Consistency | Strong (sync) to eventual (async) | Eventual (async cross-leader) | Tunable |
| Fault tolerance | Fails on leader loss (until failover) | Tolerates individual leader failures | Tolerates W failures on write, R failures on read |
| Complexity | Simple | Medium (conflict handling) | Medium (quorum math, repair) |
| Best for | OLTP, strong consistency, single DC | Multi-DC active-active, offline clients | High availability, tunable consistency, Cassandra-style |

---

## FAANG Interview Application

**When you'll be asked about this:**
- "How does Cassandra replicate data? What's a quorum?"
- "How does MySQL replication work, and what happens when the primary fails?"
- "What is replication lag and how do you handle it in your design?"
- "Why does DynamoDB use leaderless replication instead of primary-replica?"

**What they're evaluating:**
- Do you know the failure modes of each replication topology?
- Can you calculate quorum sizes and explain R+W>N?
- Do you know the specific systems (Cassandra, MySQL, Postgres, Kafka) and their replication mechanisms?
- Do you understand the read anomalies (read-your-writes, monotonic reads) and how to fix them?

**Principal-level signal:**
A senior engineer says "we use Cassandra with QUORUM reads and writes." A principal engineer says: "We use LOCAL_QUORUM for the write path because QUORUM across two datacenters adds 60ms for the cross-DC replication, which violates our 50ms SLO. We accept that a full DC outage will drop availability on the impacted DC, which our SRE team has signed off on. For the read path, we use LOCAL_ONE with read repair enabled — our data is not frequently updated, so stale reads are acceptable for 99% of queries, and read repair keeps replicas converged."

---

## Cross-References

- [consistency-models.md](./consistency-models.md) — CAP theorem and PACELC; which consistency guarantees each replication topology provides
- [time-and-causality.md](./time-and-causality.md) — why LWW (last-write-wins) in multi-leader is dangerous without synchronized clocks
- [crdts-and-conflict-resolution.md](./crdts-and-conflict-resolution.md) — CRDT-based conflict resolution for multi-leader replication
- [write-ahead-log-and-storage-internals.md](./write-ahead-log-and-storage-internals.md) — WAL shipping as the physical replication mechanism (PostgreSQL streaming replication)
- [multi-region-distribution.md](./multi-region-distribution.md) — how replication topology maps to multi-region deployment (active-passive vs active-active)
