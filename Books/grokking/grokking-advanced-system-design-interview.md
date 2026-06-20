# Grokking the Advanced System Design Interview
**Author**: Educative.io  
**Edition**: Educative, 2023 (continuously updated)  
**Category**: Distributed Systems · Storage Internals · Consensus · Streaming · FAANG Infrastructure

> "Understanding Dynamo, Cassandra, and Kafka from their research papers is the difference between reciting a design and understanding why the design has to be that way."

---

## Why This Book Matters for FAANG PE Interviews

The basic Grokking covers application-scale design. This book goes one level deeper — into the internals of the infrastructure that application designs run on. At the principal engineer level, FAANG interviewers assume you know how to design a URL shortener. They want to know if you understand *why* Cassandra uses sloppy quorum, *why* Kafka uses a partitioned append-only log, and *why* distributed coordination is fundamentally harder than it looks.

This book is organised around five real systems — Dynamo, Cassandra, Kafka, GFS/HDFS, and ZooKeeper — each studied from its original research paper perspective. The final section codifies the distributed systems patterns that appear across all of them.

**Direct interview mapping:**
- "Design a distributed key-value store" → Dynamo architecture end-to-end
- "How does Cassandra achieve high availability?" → Sloppy quorum, hinted handoff, gossip
- "Design a message queue for 10TB/day" → Kafka log + consumer groups + ISR
- "How do you implement distributed leader election?" → ZooKeeper ephemeral nodes + watches
- "What is the difference between HDFS and S3?" → Namenode vs. object store; consistency models

---

## TL;DR — 4 Ideas to Internalize

1. **Eventual consistency is a choice, not a failure.** Dynamo and Cassandra choose AP intentionally — the systems they power (Amazon shopping cart, Netflix) can tolerate stale reads in exchange for availability during partitions. Know when this trade is right and when it is not.
2. **Append-only logs are one of the most powerful primitives in distributed systems.** Kafka's partitioned log, GFS's record-append, and write-ahead logging all derive their guarantees from the same invariant: you can always recover state by replaying the log.
3. **Consensus is expensive — avoid it on the hot path.** ZooKeeper and etcd are not designed for high-throughput request handling. Use them for coordination (leader election, config) — not for data storage.
4. **Every distributed system is a trade-off between consistency, availability, and latency.** The PACELC theorem extends CAP: even when there is no partition (the normal case), you trade Latency vs. Consistency. Spanner chooses C over L; Cassandra chooses L over C.

---

## Part 1 — Dynamo: Amazon's Highly Available Key-Value Store

Amazon's 2007 Dynamo paper defined the architecture for a generation of distributed databases (Cassandra, Riak, Voldemort). Understanding Dynamo is understanding the AP side of distributed storage.

### Design Goal

Always writable, even during network partitions. Amazon's shopping cart must accept adds even when nodes are down. Eventual consistency is acceptable; "always writeable" is not negotiable.

### Core Architecture

```
                    ┌─────────────────────────────────┐
                    │  Consistent Hashing Ring         │
                    │                                  │
                    │  [A] ──► [B] ──► [C] ──► [D]   │
                    │   ↑                         │   │
                    │   └─────────────────────────┘   │
                    └─────────────────────────────────┘

Each key hashes to a position on the ring.
Each node owns keys from its predecessor to itself.
Virtual nodes: each physical node gets multiple positions.
```

### Component 1: Consistent Hashing + Virtual Nodes

**Problem with standard modular hashing:** When you add/remove a node, K/N keys must be reassigned (K = total keys, N = nodes). With 1M keys and 100 nodes, adding a node reshuffles 10K keys. For 1B keys, this is a 10M key migration — unavoidable downtime.

**Consistent hashing solution:** Keys and nodes are placed on a ring (0–2³²). Each key belongs to the first node clockwise from its hash. When a node is added, only the keys between the new node and its predecessor move — approximately K/N keys (the minimum possible).

**Virtual nodes:** Without virtual nodes, if nodes are at positions 0, 1000, 2000 on a 4096-position ring, distribution is very uneven. Virtual nodes place each physical node at K positions on the ring. With K=100 virtual nodes, each physical node owns ~100/total_virtual_nodes share of keys regardless of absolute ring positions. This also means removing a physical node distributes its load across all remaining nodes evenly.

### Component 2: Data Replication

Each key is replicated on N consecutive nodes clockwise from the coordinator node (typically N=3 in production).

```
Ring: A → B → C → D → E
key hash → coordinator A
Replication factor N=3: A writes to A, B, C
```

This is called the **preference list** — the ordered list of nodes responsible for a key.

### Component 3: Sloppy Quorum + Hinted Handoff

**Standard quorum:** For N replicas, require W writes and R reads such that R + W > N. With N=3, W=2, R=2 → you can tolerate 1 node failure with consistent reads.

**Problem:** If one of the 3 preference list nodes is down, a strict quorum write fails. Dynamo's always-write requirement cannot tolerate this.

**Sloppy quorum:** If a preference list node is down, write to the next healthy node on the ring instead — a "sloppy" member of the quorum. The hinted handoff mechanism stores a "hint" on the temporary node: "This data belongs to node C; send it to C when C recovers."

**Result:** Writes always succeed (high availability). Consistency is eventually restored via hinted handoff when the target node returns.

### Component 4: Vector Clocks for Conflict Resolution

When multiple nodes accept writes concurrently (sloppy quorum allows this), they may have different versions of a value. Vector clocks detect causality.

```
Initial state: key "cart" = {item1}
  Server A: version [A:1]

Client updates on A: key "cart" = {item1, item2}
  Server A: version [A:2]

Meanwhile, partition. Client updates on B: key "cart" = {item1, item3}
  Server B: version [A:1, B:1]  (branched from [A:1])

After partition heals:
  Server A has [A:2] = {item1, item2}
  Server B has [A:1, B:1] = {item1, item3}
  Neither descends from the other → CONFLICT

Dynamo passes both versions to the client to resolve (semantic reconciliation).
Shopping cart: union = {item1, item2, item3} — sensible.
```

Vector clocks detect whether version A happened before B, after B, or concurrently. Concurrent → conflict → application-level resolution.

### Component 5: Anti-Entropy with Merkle Trees

**Problem:** Even with hinted handoff, replicas can diverge (missed hints, long partitions). How do you efficiently identify which keys are out of sync?

**Merkle tree approach:** Each node builds a Merkle (hash) tree of its key ranges. The root hash represents the entire key range. If two nodes' root hashes match, their data is identical — no sync needed. If they differ, walk down the tree to find the differing subtree in O(log N) time instead of comparing all keys.

Dynamo runs anti-entropy in the background, continuously comparing Merkle trees between replicas and syncing divergent keys.

### Component 6: Gossip Protocol for Failure Detection

**Gossip (epidemic protocol):** Each node periodically selects a random peer and exchanges membership state (which nodes are alive, which are suspected down). Information propagates through the cluster like a rumor — O(log N) rounds for information to reach all N nodes.

**Advantages:** No central coordinator needed. Scales to thousands of nodes. Resilient to any single failure.

**Failure detection:** Nodes use a heartbeat counter. If a node's heartbeat has not advanced after a configurable interval, it is marked "suspected." After a longer interval without recovery, it is marked "down."

### Dynamo vs. Alternatives

| Dimension | Dynamo / DynamoDB | Cassandra | ZooKeeper |
|-----------|------------------|-----------|-----------|
| **CAP** | AP | AP (tunable) | CP |
| **Consistency** | Eventual (tunable) | Tunable (ONE/QUORUM/ALL) | Strong |
| **Replication** | Multi-master | Multi-master | Leader-based (Paxos) |
| **Data model** | Key-value | Wide-column | Hierarchical (znodes) |
| **Coordination** | No | No | Yes (lock, leader election) |
| **Best for** | Shopping cart, session store | Time-series, event log, IoT | Config, lock, service discovery |

**FAANG signal:** "Explain the difference between a sloppy quorum and a strict quorum, and when you'd use each." → Sloppy quorum: always available, eventual consistency. Strict quorum: consistent reads, may reject writes under failure.

---

## Part 2 — Cassandra: Wide-Column Store at Scale

Cassandra is Dynamo's data model merged with BigTable's column family storage. It inherits Dynamo's ring topology, consistent hashing, virtual nodes, gossip, and sloppy quorum — and adds a richer data model and a tunable consistency layer.

### Data Model: Wide-Column

```
Table: user_activity
Primary key: (user_id, timestamp)    ← partition key + clustering key

Row: user_id="u123", timestamp=2024-01-15T10:00, action="login", ip="1.2.3.4"
Row: user_id="u123", timestamp=2024-01-15T11:00, action="purchase", item_id="p456"
Row: user_id="u456", timestamp=2024-01-16T09:00, action="view", item_id="p789"

Physical storage:
  Partition "u123": sorted by timestamp → efficient range scan
  Partition "u456": separate partition → different node
```

All rows with the same partition key are stored together on the same node. Clustering key sorts rows within a partition. This makes range queries on the clustering key (e.g., "all activity for user u123 in January") extremely efficient — they are sequential disk reads.

**Access pattern first:** Cassandra data models are designed around the query, not the entities. If you need to query by `(user_id, date_range)`, that's your partition key + clustering key.

### Read Path

```
1. Client sends READ to coordinator node (determined by consistent hash of partition key)
2. Coordinator queries the N nodes in the preference list
3. Based on consistency level:
   - ONE: return first response received
   - QUORUM: wait for majority (N/2 + 1) to respond, return most recent
   - ALL: wait for all N replicas
4. Read repair: if coordinator detects stale replica, sends async repair write
```

**Bloom filter:** Before reading an SSTable from disk, Cassandra checks a per-SSTable Bloom filter. If the Bloom filter says the key is NOT in that SSTable (with 100% certainty), skip the SSTable. This avoids many disk reads.

### Write Path

```
1. Write to CommitLog (sequential append — fast, durable)
2. Write to MemTable (in-memory sorted structure — fast writes)
3. ACK to client (based on consistency level — e.g., QUORUM: 2 of 3 nodes acked)
4. When MemTable is full: flush to SSTable on disk (immutable sorted file)
5. Background compaction: merge multiple SSTables into fewer, larger ones
```

**SSTables are immutable.** Deletes are written as tombstones (a special marker). Compaction eventually removes tombstones and merges files.

**Compaction strategies:**

| Strategy | When to use | Trade-off |
|----------|-------------|-----------|
| **SizeTiered (STCS)** | Default; write-heavy | Efficient writes; read amplification during compaction |
| **Leveled (LCS)** | Read-heavy; bounded space amplification | Better reads; higher write amplification |
| **TimeWindow (TWCS)** | Time-series data with TTL | Efficient expiry; poor for mixed timestamps |

### Tunable Consistency

```
Consistency level ONE:    fastest reads/writes; stale reads possible
Consistency level QUORUM: (N/2+1) nodes agree; tolerates 1 failure with N=3
Consistency level ALL:    all replicas agree; highest consistency; lowest availability
Consistency level LOCAL_QUORUM: quorum within the local datacenter; geo-distributed
```

**The sweet spot for FAANG interviews:** QUORUM reads + QUORUM writes. With N=3: W=2, R=2. R+W > N (4 > 3) → guaranteed to read at least one up-to-date value. Tolerates 1 node failure. Standard production configuration.

**FAANG signal:** "What consistency level would you choose for a financial ledger vs. a product catalog?" → Ledger: QUORUM or ALL (no staleness). Product catalog: ONE or LOCAL_ONE (eventual consistency fine, ultra-low latency needed).

---

## Part 3 — Kafka: Distributed Message Streaming

Kafka is the most common solution for high-throughput, fault-tolerant, replayable message streaming. The core insight is that a partitioned, append-only, replicated log is simultaneously a message queue, an event stream, and a replayable changelog.

### Core Architecture

```
Producers ──► Topic (Partitioned Log) ──► Consumers (Consumer Groups)

Topic: user_events
  Partition 0: [msg0][msg1][msg2][msg3]...  ← append-only, immutable
  Partition 1: [msg0][msg1][msg2]...
  Partition 2: [msg0][msg1]...

Consumer Group "analytics":
  Consumer A: reads Partition 0
  Consumer B: reads Partition 1
  Consumer C: reads Partition 2
```

Each consumer in a group reads a disjoint set of partitions. Adding consumers to a group scales consumption linearly — up to the number of partitions.

### Offset Management

**Consumer offset:** Each consumer tracks its position in each partition as an integer offset. The consumer, not the broker, owns the offset. This means:
- Consumers can replay messages by resetting to an earlier offset
- A crashed consumer can resume exactly where it left off
- Different consumer groups can read the same partition at different offsets simultaneously

**Offset storage:** Committed offsets are stored in the internal `__consumer_offsets` topic.

### Replication: ISR (In-Sync Replicas)

```
Partition 0:
  Leader: Broker 1  ← all writes go here
  ISR:    [Broker 1, Broker 2, Broker 3]
```

**ISR = the set of replicas that are fully caught up with the leader.** A replica falls out of ISR if it falls more than `replica.lag.max.messages` behind. The leader only acks a write to the producer when `acks` replicas in the ISR have written it:
- `acks=0`: no ack — fire and forget
- `acks=1`: leader acked (default) — lost if leader crashes before replication
- `acks=all` (or `-1`): all ISR replicas acked — strongest guarantee

**FAANG signal:** "What happens if the Kafka leader dies?" → ZooKeeper (or KRaft in newer Kafka) triggers leader election. A broker in the ISR becomes the new leader. Producers fail briefly, retry, and reconnect. Consumer offsets are preserved. Data in ISR is guaranteed not lost.

### Delivery Guarantees

| Guarantee | Producer config | Consumer behavior |
|-----------|----------------|-------------------|
| **At-most-once** | `acks=0`, no retry | Commit before processing |
| **At-least-once** | `acks=all`, retry on failure | Commit after processing |
| **Exactly-once** | Idempotent producer + transactional API | Transactional consumer |

**At-least-once + idempotent consumer = effectively exactly-once.** Most production systems use at-least-once with idempotent processing (deduplication by message key).

### Consumer Group Rebalancing

When a consumer joins or leaves a group, partitions are reassigned. During a rebalance, consumption pauses. Strategies:
- **Eager (default):** All consumers drop all partitions; reassign from scratch. Simpler; stops all consumption momentarily.
- **Cooperative (incremental):** Only affected partitions are revoked. Reduces pause duration. Preferred for high-throughput systems.

### Compacted Topics

Kafka supports log compaction: for each key, only the latest message is retained. Used for changelog streams — e.g., user profile updates where you only need the latest state per user.

```
Topic: user_profiles (compacted)
Before: [u1:v1][u2:v1][u1:v2][u3:v1][u2:v2]
After compaction: [u1:v2][u2:v2][u3:v1]
```

**FAANG signal:** "When would you use a compacted topic vs. a regular topic?" → Compacted: state reconstruction (event sourcing, CDC, materialized view). Regular: event stream for analytics, where historical events matter.

### Kafka vs. SQS/RabbitMQ

| Dimension | Kafka | SQS (Standard) | RabbitMQ |
|-----------|-------|-----------------|----------|
| **Ordering** | Per-partition | Best-effort | Per-queue |
| **Retention** | Configurable (days/weeks/forever) | 4–14 days | Until ack |
| **Replay** | Yes (rewind offset) | No | No |
| **Throughput** | Very high (GB/s per cluster) | High | Medium |
| **Consumer model** | Pull (consumer controls offset) | Push or pull | Push |
| **Best for** | Event streaming, CDC, audit log | Simple async tasks | Complex routing, RPC |

---

## Part 4 — GFS and HDFS: Distributed File Storage

The Google File System (2003) and Hadoop Distributed File System are architecturally identical in their key decisions. Understanding them explains how distributed file storage works at petabyte scale.

### Architecture

```
┌──────────────────────────────────────────────────┐
│  Master / Namenode  (single master, replicated)  │
│  - File namespace (filename → chunk list)        │
│  - Chunk locations (chunk ID → chunkserver list) │
│  - In-memory; persisted via edit log + checkpoint│
└──────────────────────────────────────────────────┘
             │ metadata only
             │
   ┌─────────┼─────────┐
   ▼         ▼         ▼
ChunkServer  ChunkServer  ChunkServer
(Datanode)   (Datanode)   (Datanode)
  [chunk A]  [chunk A]  [chunk A]  ← 3-way replication
  [chunk B]  [chunk C]  [chunk D]
```

**Data never flows through the master.** The client asks the master "where is chunk X of file F?" and then reads/writes directly to the chunkserver(s). This keeps the master's load minimal and data throughput independent of master capacity.

### Chunk Size: 64MB (GFS) / 128MB (HDFS default)

Large chunks reduce the number of chunks per file and reduce master metadata overhead. Trade-off: small files become one chunk each, but multiple small files can create hot chunkservers if they all land on the same node.

### Replication: Rack-Aware Placement

Default: 3 replicas. Standard placement:
- Replica 1: local rack, chunkserver A
- Replica 2: local rack, chunkserver B (different machine, same rack)
- Replica 3: different rack entirely

This tolerates: (a) any single chunkserver failure (b) any single rack failure or network switch failure.

### Writes: Record Append

GFS uses a pipelined record-append model:
```
Client ──► Chunkserver 1 (primary) ──► CS 2 ──► CS 3

1. Client sends data to primary and all replicas simultaneously (pipelined)
2. Primary serializes concurrent appends and assigns byte offsets
3. Primary sends "do it" to replicas at specific offset
4. All replicas ACK primary; primary ACKs client
```

GFS is optimised for append-only, large sequential writes (MapReduce output). Random writes are unsupported.

### Fault Tolerance

**Chunkserver failure:** Master detects via heartbeat. Re-replicates missing chunks on surviving chunkservers until replication factor is restored.

**Master failure:** Edit log + periodic checkpoints. Secondary master can replay logs to recover state. In practice: use a shadow master for high availability.

**FAANG signal:** "Why does HDFS use a single namenode if it's a single point of failure?" → By design: a single master simplifies consistency. The original GFS paper acknowledged this trade-off. HDFS HA (Hadoop 2.0+) uses two namenodes in active-standby with ZooKeeper for failover.

### GFS/HDFS vs. Object Storage (S3)

| Dimension | HDFS | Amazon S3 |
|-----------|------|-----------|
| **API** | POSIX-like filesystem | Object (PUT/GET/LIST) |
| **Consistency** | Strong (single master serialises) | Eventual (now strong per 2020 update) |
| **Compute locality** | Yes (data local to CPU) | No (compute and storage separate) |
| **Operational complexity** | High (manage cluster) | Zero (fully managed) |
| **Best for** | Hadoop batch processing, co-located compute | Cloud-native storage, microservices, backup |

---

## Part 5 — Chubby / ZooKeeper: Distributed Coordination

ZooKeeper is the open-source implementation of Google's Chubby lock service. It provides strongly consistent, hierarchical coordination for distributed systems.

### What ZooKeeper Is For

ZooKeeper is NOT a general-purpose database or message queue. It is a coordination service for:
- **Leader election:** which service instance is the current primary?
- **Distributed locks:** mutual exclusion across distributed processes
- **Service discovery:** where are the current healthy instances of service X?
- **Configuration management:** what is the current value of feature flag Y?
- **Barrier synchronisation:** wait until all workers have reached phase 2

### Architecture: ZNodes

ZooKeeper stores data in a hierarchical tree of ZNodes — similar to a filesystem:

```
/
├── /services
│   ├── /services/api  ← service registry
│   │   ├── /services/api/instance-1  (ephemeral, value = "10.0.0.1:8080")
│   │   ├── /services/api/instance-2  (ephemeral, value = "10.0.0.2:8080")
│   └── /services/db
│       └── /services/db/leader        (value = "10.0.0.5:5432")
├── /config
│   └── /config/feature-flags          (value = JSON blob)
└── /locks
    └── /locks/resource-a              (ephemeral sequential)
```

**ZNode types:**
- **Persistent:** survives client disconnection. Used for configuration.
- **Ephemeral:** deleted when the creating client session ends. Used for service registration, leader identity.
- **Sequential:** ZooKeeper appends a monotonic counter to the name. Used for ordered processing (locks, queues).

### Watches: Event-Driven Notifications

A client can set a watch on a ZNode. When that ZNode is created, deleted, or modified, ZooKeeper notifies the client. This is the primitive that makes ZooKeeper efficient — clients do not need to poll.

```python
# Leader election via ephemeral sequential nodes:
# Each candidate creates /election/candidate-NNNN (sequential + ephemeral)
# The candidate with the lowest NNNN is the leader
# Each non-leader watches the next smaller node
# If the watched node is deleted (leader died), the next candidate becomes leader
# No thundering herd — only one candidate is notified per leader failure
```

### Consensus: Zab Protocol

ZooKeeper uses the **Zab (ZooKeeper Atomic Broadcast)** protocol — functionally similar to Raft/Paxos. A cluster of 2f+1 ZooKeeper servers can tolerate f failures while maintaining consistency.

- All writes go to the leader
- Leader proposes a write to a quorum of followers
- Followers ACK
- Leader commits and broadcasts the commit
- **All reads can be served by any server** (may be slightly stale) OR **Linearizable reads** require a sync() call first

**FAANG signal:** "Why do you run ZooKeeper with 3 or 5 nodes, not 4 or 6?" → With 2f+1 nodes, you need f+1 for a quorum. With 4 nodes (f=1, quorum=3) you don't gain any extra fault tolerance over 3 nodes (also requires 2 of 3). Odd numbers are optimal for quorum-based systems.

### Distributed Lock with ZooKeeper

```python
# Lock acquire:
path = zk.create("/locks/mylock-", ephemeral=True, sequential=True)
# path = "/locks/mylock-0000000042"

children = sorted(zk.get_children("/locks"))
my_index = children.index("mylock-0000000042")

if my_index == 0:
    # I have the lock — lowest sequence number
    pass
else:
    # Watch the node with index my_index - 1
    predecessor = children[my_index - 1]
    zk.exists(f"/locks/{predecessor}", watch=self.on_predecessor_deleted)
    # Wait for notification...

# Lock release:
zk.delete(path)  # or session expires → ephemeral node deleted automatically
```

This pattern eliminates the thundering herd: only one waiter is woken when the lock is released.

---

## Part 6 — Distributed System Patterns Cheat Sheet

These 7 patterns appear across all the systems above. Know when to cite each.

---

### Pattern 1: Write-Ahead Log (WAL)

**What it is:** Before applying any change, write the intent to a durable sequential log. If the system crashes, replay the log to recover.

**Where it appears:**
- Kafka: the partition log IS the WAL
- PostgreSQL: pg_wal ensures crash recovery
- HBase/BigTable: the edit log before MemTable writes
- Cassandra: CommitLog before MemTable

**Interview trigger:** "How do you ensure data durability in your design?" → "Writes go to a write-ahead log first. If the node crashes before flushing to the main store, we replay the log on recovery."

---

### Pattern 2: Bloom Filter

**What it is:** A probabilistic data structure that answers "is this key definitely NOT in the set?" with 100% accuracy. May produce false positives (says "might be in set" when it's not). Never false negatives.

**Space complexity:** O(n × k / ln2) bits where n = elements, k = hash functions. A 10M element Bloom filter with 1% false positive rate needs ~11.4 MB.

**Where it appears:**
- Cassandra: each SSTable has a Bloom filter to avoid unnecessary disk reads
- Web crawlers: "have we seen this URL?"
- CDN edge nodes: "is this content likely cached here?"
- DynamoDB: filter potential key existence before more expensive lookup

**Interview trigger:** "How do you efficiently check if a record exists without reading the full dataset?" → Bloom filter. Follow-up: "How do you handle false positives?" → They cause an unnecessary (but not incorrect) lookup of the main store — acceptable cost.

---

### Pattern 3: Heartbeat

**What it is:** Periodic "I'm alive" signal between nodes. If heartbeats stop, the sender is marked down.

**Where it appears:** Every distributed system — ZooKeeper, Cassandra gossip, Kafka broker health, Kubernetes liveness probes.

**Failure detection precision:** A longer heartbeat interval means: slower failure detection (higher time-to-detect) but fewer false positives (a transient network blip doesn't immediately mark a node dead). Trade-off: detection latency vs. false positive rate.

---

### Pattern 4: Quorum

**What it is:** A majority agreement. A quorum of W writes + R reads from N replicas satisfies R + W > N → at least one replica overlap → always read at least one up-to-date value.

**Variations:**
- Strict quorum: W + R > N among the preference list
- Sloppy quorum: W + R > N among any N available nodes (Dynamo)

**Interview trigger:** "How do you ensure a distributed system returns consistent data?" → Quorum read + write with R + W > N. With N=3, W=2, R=2: tolerates 1 failure; any read overlaps with at least one write.

---

### Pattern 5: Checksum

**What it is:** A hash of data stored alongside the data. On read, recompute the hash and compare. If they differ, data is corrupted.

**Where it appears:**
- Cassandra: CRC32 checksum per SSTable block
- GFS: 64KB chunks each have a 32-bit checksum
- Kafka: CRC32 per message batch
- TCP: header checksum

**Interview trigger:** "How do you detect silent data corruption in a storage system?" → Store a checksum (CRC32 or SHA-256) with each stored block. Recompute on read and compare. Flag and re-fetch from another replica on mismatch.

---

### Pattern 6: Lease

**What it is:** A time-bound grant of authority. The lease holder can act with authority for duration T. After T, authority expires automatically unless renewed. Used instead of locks because a crashed holder's lease expires without needing an explicit release.

**Where it appears:**
- ZooKeeper: session leases (ephemeral nodes auto-expire with session)
- GFS: chunkserver master leases (primary role expires in 60s unless renewed)
- Distributed caches: "I hold the authoritative copy for 30 seconds"
- Kubernetes: node leases (kubelet renews lease; if not renewed, node is considered down)

**Interview trigger:** "How do you avoid split-brain in a leader election?" → Leases. The leader must renew its lease before it expires. If the lease expires, followers can elect a new leader without waiting for the old one to release.

---

### Pattern 7: Split Brain

**What it is:** A network partition causes two segments of a cluster to each believe they are the leader / authoritative copy. Both accept writes. When partition heals, you have two diverged histories.

**Prevention strategies:**
- **Quorum-based writes:** A write only succeeds with majority agreement. With N=3, both partition sides would need 2 nodes — impossible (one side gets 2, the other gets 1).
- **Leader leases:** The old leader's lease expires during the partition. No writes accepted without a valid lease. New leader elected in the majority partition.
- **Fencing tokens:** The new leader issues a fencing token (monotonic integer). Old leader's writes to storage are rejected if they carry a lower token.

**FAANG signal:** "How does your design handle a split-brain scenario?" → Quorum. The minority partition stops accepting writes. The majority partition continues. After reconnection, the minority partition catches up via log replication.

---

## Distributed Systems Patterns Quick-Reference

| When you need... | Pattern | Where used |
|-----------------|---------|-----------|
| Crash recovery | Write-ahead log | Kafka, Postgres, Cassandra |
| Avoid disk read when key absent | Bloom filter | Cassandra, crawlers, CDN |
| Node failure detection | Heartbeat | Every distributed system |
| Read-write consistency across replicas | Quorum | Dynamo, Cassandra, ZooKeeper |
| Data corruption detection | Checksum | GFS, Kafka, Cassandra |
| Auto-release locks on crash | Lease | ZooKeeper, GFS, Kubernetes |
| Prevent dual-primary after partition | Quorum + Fencing | Raft, ZooKeeper, database HA |
| Uniform key distribution across nodes | Consistent hashing + virtual nodes | Cassandra, Dynamo, Memcached |
| Efficient set membership (probabilistic) | Bloom filter | Cassandra SSTable, crawlers |
| Causality tracking in multi-master | Vector clock | Dynamo, Riak |

---

## Actionable Takeaways for FAANG Preparation

1. **Dynamo is the source material.** If an interviewer asks about Cassandra, DynamoDB, or any AP distributed store, anchor your explanation in the Dynamo paper. Sloppy quorum, hinted handoff, vector clocks, Merkle trees — these are the Dynamo primitives that everything else builds on.

2. **Know the Kafka guarantees matrix cold.** `acks=0/1/all`, at-most-once / at-least-once / exactly-once, and when each combination is appropriate — this appears in system design for any pipeline-heavy problem.

3. **Cite the PACELC framework, not just CAP.** CAP is about behavior during partitions. PACELC extends it: even without a partition, there is a Latency vs. Consistency trade-off. Cassandra with LOCAL_ONE is low-latency, low-consistency. Cassandra with QUORUM is higher-latency, higher-consistency. Spanner with TrueTime is the highest-consistency, highest-latency option.

4. **ZooKeeper is for coordination, not data.** A common design mistake is using ZooKeeper to store application data. It is not designed for that. It is designed for metadata, configuration, and coordination artifacts (leases, locks, leader identity). Maximum ZNode size is 1MB by design.

---

## Common Interviewer Follow-Up Questions

**"Design a distributed key-value store. How do you handle writes when a node is down?"**

> "I'd model this on Dynamo's approach. Every key is replicated on N nodes using consistent hashing — with N=3. Writes use a sloppy quorum: I need W=2 nodes to acknowledge before returning success. If one of the 3 preference list nodes is down, I write to the next healthy node on the ring instead and include a hint: 'deliver this to node C when it recovers.' The hinted handoff ensures eventual consistency. The coordinator accepts the write and returns success to the client. When node C recovers, the hint is delivered, and the replica catches up. For detecting divergence after long partitions, I run background anti-entropy using Merkle trees — two replicas exchange their Merkle root hashes and drill down to find only the divergent key ranges."

**"How does Kafka guarantee exactly-once delivery?"**

> "Kafka achieves exactly-once through two mechanisms combined. First, idempotent producers: the broker deduplicates producer retries using a producer ID and sequence number per partition. Even if the producer retries after a network failure, the broker detects the duplicate and discards it. Second, transactional writes: the producer can atomically write to multiple partitions and commit or abort the transaction. The consumer reads only committed messages when using `isolation.level=read_committed`. The combination gives exactly-once semantics end-to-end. In practice, most systems use at-least-once delivery with idempotent consumer processing — simpler, and effectively equivalent if the consumer can identify duplicates by message key."

**"When would you choose ZooKeeper over a database for leader election?"**

> "A database could implement leader election via a unique constraint row (the leader writes its ID; a second writer fails on uniqueness). But this has two problems: (1) Lease expiry — if the leader dies, the lock row is never released unless you add a separate TTL mechanism. ZooKeeper's ephemeral nodes are deleted automatically when the session expires. (2) Notification — the database model requires polling to detect leadership changes. ZooKeeper's watch mechanism notifies clients immediately. ZooKeeper was designed specifically for this pattern: the ephemeral sequential node trick for leader election is 5 lines of code that is race-condition free, fencing-safe, and notification-based. I'd use ZooKeeper (or etcd, its modern equivalent) for distributed coordination and keep the database for application data."

**"What is the PACELC theorem and how does it change how you evaluate distributed databases?"**

> "CAP theorem only addresses behavior under network partition — which is the exceptional case. PACELC (Daniel Abadi, 2012) covers the normal case too: even when there's no partition (P), there's a trade-off between Latency (L) and Consistency (C). Every distributed system has four possible operating points: PA/EL (dynamo mode: highly available + low latency, eventual consistency always), PC/EL (ZooKeeper: consistent during partition, but still low latency during normal ops — not accurate actually), PA/EC (Cassandra QUORUM: tolerates partition with AP, but trades latency for consistency in normal ops), PC/EC (Spanner: consistent always, pays the latency cost via TrueTime wait). In practice: for user-facing, latency-sensitive systems, I lean PA/EL with idempotent clients. For financial systems or anything requiring exact consistency, PC/EC with the latency accepted."
