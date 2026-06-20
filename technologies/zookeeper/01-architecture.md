# ZooKeeper — Architecture

## Origins: The Chubby Problem, Open-Sourced

ZooKeeper was inspired by Google Chubby (2006) — Google's internal distributed lock service. Yahoo! needed the same coordination primitives but for open-source software. The paper "ZooKeeper: Wait-free coordination for Internet-scale systems" (USENIX ATC 2010) formalised the design. The key architectural departure from Chubby: ZooKeeper exposes **wait-free operations** rather than blocking lock primitives, pushing synchronisation logic to clients while keeping the server simple and always responsive.

---

## Ensemble Topology

ZooKeeper runs as a **replicated group of servers** called an **ensemble**. Ensembles must be odd-numbered to form a simple majority quorum.

```
                        ┌─────────────────────────────────┐
                        │         ZooKeeper Ensemble       │
                        │                                  │
                Client ─┤──► Leader  ◄──► Follower 1      │
                        │      │     ◄──► Follower 2      │
                        │      │     ◄──► Observer 1      │
                        │      └─── (ZAB broadcast)       │
                        └─────────────────────────────────┘

  Quorum for writes: ⌊N/2⌋ + 1 nodes must ACK
    N=3: 2 nodes must ACK (tolerates 1 failure)
    N=5: 3 nodes must ACK (tolerates 2 failures)
    N=7: 4 nodes must ACK (tolerates 3 failures)
```

### Role Definitions

| Role | Participates in Quorum | Can Handle Reads | Can Handle Writes | Notes |
|------|----------------------|-----------------|------------------|-------|
| **Leader** | Yes | Yes (local) | Yes (initiates ZAB) | One per ensemble; elected via ZAB |
| **Follower** | Yes | Yes (local, potentially stale) | Forwards to leader | Participates in leader election |
| **Observer** | No | Yes (local) | Forwards to leader | Scales read throughput; no election overhead |

**Observers** are a critical scaling mechanism: add observers to scale read throughput without increasing quorum size (which would slow writes). Observers sync from the leader but do not vote.

---

## ZAB Protocol (ZooKeeper Atomic Broadcast)

ZAB is the consensus protocol that underpins ZooKeeper. It is **not Paxos** and **not Raft** — it was designed specifically for the primary-backup replication pattern with a single leader.

ZAB operates in two phases:

### Phase 1: Leader Election (Recovery Mode)

Triggered when the ensemble starts or when the leader fails. Uses a **fast leader election** algorithm:

```
1. Every node broadcasts its vote: (myZXID, myServerId)
   where ZXID is the highest transaction ID this node has seen

2. Voting rule:
   - Accept a vote if the candidate has a higher ZXID (more up-to-date)
   - Break ties by server ID (higher ID wins)
   - Replace your own vote if you receive a "better" one

3. A candidate wins when it has received QUORUM votes for itself

4. Winning node transitions to LEADING state
   Remaining nodes transition to FOLLOWING state

5. New leader synchronises all followers to its state before accepting writes
   (sends DIFF for small divergence, SNAP for large divergence, TRUNC if follower is ahead)
```

**Duration**: typically 200 ms – 2 s depending on network and `electionAlg`. During this period the ensemble is **unavailable for writes**.

### Phase 2: Broadcast Mode (Normal Operation)

Once a leader is elected, it processes client writes using a two-phase broadcast:

```
Write request lifecycle:

  Client ──WRITE──► Leader
                      │
                      ├─ 1. Assign ZXID (epoch:counter, monotonically increasing)
                      ├─ 2. Write to transaction log (WAL) locally
                      ├─ 3. Broadcast PROPOSAL(ZXID, txn) to all followers
                      │
                    Followers
                      ├─ 4. Each follower writes to its own transaction log
                      ├─ 5. Each follower sends ACK(ZXID) back to leader
                      │
                      ├─ 6. Leader waits for QUORUM ACKs
                      ├─ 7. Leader sends COMMIT(ZXID) to all followers
                      ├─ 8. Leader applies txn to in-memory data tree
                      ├─ 9. Leader sends response to client
                      │
                    Followers
                      └─ 10. Apply txn to their own in-memory data tree
```

**Key guarantee**: A write is acknowledged to the client only after it has been durably written to the transaction log on a quorum of nodes. The in-memory apply (step 8) happens after the ACK.

### ZXID Structure

Every transaction in ZooKeeper has a 64-bit **ZXID** (ZooKeeper Transaction ID):

```
  ZXID = | epoch (32 bits) | counter (32 bits) |
                 │                    │
                 │                    └── monotonically increasing within epoch
                 └── incremented every time a new leader is elected
```

The epoch component prevents conflicts from split-brain: a deposed leader's ZXIDs (old epoch) are always less than the new leader's ZXIDs, so followers can detect stale proposals and reject them.

---

## Data Model: The ZNode Tree

ZooKeeper's namespace is a **hierarchical tree of znodes**, structurally identical to a filesystem but stored entirely in RAM.

```
/
├── zookeeper/               ← reserved for ZK internal use
│   └── quota/
├── kafka/
│   ├── brokers/
│   │   ├── ids/
│   │   │   ├── 0            ← ephemeral: broker 0 is alive
│   │   │   └── 1            ← ephemeral: broker 1 is alive
│   │   └── topics/
│   └── controller           ← ephemeral: current Kafka controller
├── hbase/
│   └── master               ← ephemeral: current HBase master
└── services/
    └── payments/
        ├── instance-0001    ← ephemeral sequential: service instance
        └── instance-0002
```

### ZNode Types

| Type | Persistence | Sequence | Use Case |
|------|-------------|----------|---------|
| **Persistent** | Survives client disconnect | No | Configuration, namespace structure |
| **Ephemeral** | Deleted when creating session ends | No | Service presence, lock acquisition |
| **Persistent Sequential** | Survives disconnect | Yes (monotonic suffix) | Ordered task queues |
| **Ephemeral Sequential** | Deleted on session end | Yes (monotonic suffix) | Leader election, fair distributed locks |
| **Container** (3.5+) | Deleted when last child deleted | No | Namespace containers |
| **TTL** (3.5+) | Deleted if no update within TTL | No | Cache entries |

**Sequential suffix**: when a sequential node is created at `/lock/node`, ZooKeeper appends a 10-digit monotonically increasing number: `/lock/node0000000001`, `/lock/node0000000002`, etc. The counter is per-parent-path and persists across leader elections.

### ZNode Metadata (Stat Structure)

Every znode carries a **Stat** structure:

```
czxid      — ZXID of the transaction that created this znode
mzxid      — ZXID of the transaction that last modified it
ctime      — creation time (ms since epoch)
mtime      — last modified time
version    — number of changes to data (optimistic concurrency control)
cversion   — number of changes to children
aversion   — number of changes to ACL
ephemeralOwner — session ID of owner (0 if persistent)
dataLength — length of data in bytes
numChildren — number of child znodes
pzxid      — ZXID of the last modification to children list
```

**`version` field is critical** for conditional updates:

```java
// Optimistic concurrency: only update if version matches (no one else changed it)
zk.setData("/config/feature-flag", newValue, expectedVersion);
// throws KeeperException.BadVersionException if version mismatches
```

---

## Watches

Watches are the **notification mechanism** — clients register a one-time callback to be notified when a znode changes.

```
  Client                         ZooKeeper Server
    │                                   │
    ├── getData("/lock", watch=true) ──►│
    │◄── data + stat ───────────────────┤  (watch registered on server)
    │                                   │
    │   [some other client changes /lock]
    │                                   │
    │◄── WatchedEvent(NodeDataChanged) ─┤  (watch fires, is removed)
    │                                   │
    ├── getData("/lock", watch=true) ──►│  (must re-register to keep watching)
```

### Watch Types

| Operation | Watch Triggers On |
|-----------|------------------|
| `getData(path, watch)` | NodeDeleted, NodeDataChanged |
| `getChildren(path, watch)` | NodeDeleted, NodeChildrenChanged |
| `exists(path, watch)` | NodeCreated, NodeDeleted, NodeDataChanged |

### Critical Watch Semantics

1. **One-time**: a watch fires exactly once, then is removed. The client must re-register after every notification.
2. **Ordered with data**: watches are delivered in order; if client reads data and sets a watch in one call, it will never miss an update that happened after the read.
3. **Not guaranteed delivery on session disconnect**: if the session expires, pending watches are lost — the client must reconnect and re-read state from scratch.
4. **Event only, not value**: a WatchedEvent tells you the path and type of change, not the new value. You must perform a follow-up `getData` or `getChildren` to fetch the current state.

**Pattern for correctness**:
```java
// Always re-read AFTER setting the watch to avoid TOCTOU races
Stat stat = new Stat();
byte[] data = zk.getData("/config", myWatcher, stat);
processConfig(data);

// In myWatcher:
public void process(WatchedEvent event) {
    if (event.getType() == EventType.NodeDataChanged) {
        Stat stat = new Stat();
        byte[] data = zk.getData("/config", this, stat);  // re-register watch
        processConfig(data);
    }
}
```

---

## Sessions

A **session** is the connection contract between a client and the ZooKeeper ensemble.

```
  Client lifecycle:

  CONNECTING ──(connected)──► CONNECTED ──(timeout/disconnect)──► CONNECTING
                                  │
                                  │ (session expired by server)
                                  ▼
                               CLOSED  ──► all ephemeral nodes deleted
                                           all watches invalidated
```

### Session Mechanics

| Property | Detail |
|----------|--------|
| **Session ID** | 64-bit globally unique, assigned by leader on session creation |
| **Session timeout** | Negotiated at connect; must be > 2× tickTime; default 30 s |
| **Heartbeat** | Client sends PING every tickTime/3; server expects one every sessionTimeout |
| **Transparent failover** | On server failure, client reconnects to another server using same session ID |
| **Expiry** | If no heartbeat received within sessionTimeout, server marks session expired; client gets SessionExpiredException on reconnect |

### Ephemeral Node Lifecycle

Ephemeral nodes are the foundation of ZooKeeper's coordination recipes:

```
  Service Instance Startup:
    1. Connect to ZooKeeper ensemble
    2. Create ephemeral node: /services/payments/instance-<sessionId>
    3. Data: { host: "10.0.1.5", port: 8080, version: "2.4.1" }

  Service Instance Crash / Network Partition:
    - Session timeout elapses (30 s default)
    - ZooKeeper deletes the ephemeral node
    - All clients watching /services/payments/ receive NodeChildrenChanged
    - Service discovery clients re-read the children list and remove stale instance
```

---

## Leader Election Recipe (Ephemeral Sequential)

The canonical ZooKeeper leader election using ephemeral sequential nodes:

```
  Participants: A, B, C

  Step 1: Each creates an ephemeral sequential node under /election/
    A creates: /election/n_0000000001
    B creates: /election/n_0000000002
    C creates: /election/n_0000000003

  Step 2: Each lists /election/ children and finds its own position
    A has n_0000000001 → lowest → A is LEADER
    B has n_0000000002 → watches predecessor: n_0000000001
    C has n_0000000003 → watches predecessor: n_0000000002

  Step 3: A (leader) crashes
    n_0000000001 is deleted (ephemeral, session expired)
    B receives watch notification (predecessor deleted) → B becomes LEADER
    C now watches: n_0000000002

  Step 4: B crashes
    n_0000000002 deleted → C becomes LEADER
```

**Why watch the predecessor, not the smallest?** If everyone watched the smallest node, a single deletion would generate a **herd effect** — all N-1 waiters fire simultaneously, all re-read children, all set new watches. This is O(N) load spike. By chaining watches (each node watches only its predecessor), only one node wakes up per transition.

---

## Distributed Lock Recipe

```java
// Apache Curator handles this for you — shown here to understand internals
String lockPath = "/locks/payment-processor";

// Attempt to acquire
String myNode = zk.create(lockPath + "/lock-", new byte[0],
    ZooDefs.Ids.OPEN_ACL_UNSAFE, CreateMode.EPHEMERAL_SEQUENTIAL);

while (true) {
    List<String> children = zk.getChildren(lockPath, false);
    Collections.sort(children);
    
    if (myNode.endsWith(children.get(0))) {
        return; // I hold the lock
    }
    
    // Watch predecessor to avoid herd effect
    String predecessor = children.get(children.indexOf(myNode.split("/")[3]) - 1);
    CountDownLatch latch = new CountDownLatch(1);
    Stat stat = zk.exists(lockPath + "/" + predecessor, event -> latch.countDown());
    if (stat != null) {
        latch.await(); // wait for predecessor to release
    }
    // loop and re-check
}

// Release: delete myNode (happens automatically on session expiry too)
zk.delete(myNode, -1);
```

---

## FAANG Interview Callout

> "ZooKeeper's architecture is a leader-based replicated state machine driven by ZAB. All writes go through the leader, get a globally ordered ZXID, and are replicated to a quorum before ACKing the client. This gives linearizable writes. Reads are served locally by any node — fast but potentially stale. The data model is a hierarchical tree of znodes; the critical primitives are ephemeral nodes (auto-deleted on session expiry) and sequential nodes (atomically assigned monotonically increasing suffix). On top of these two primitives, you build leader election by chaining watches on sequential nodes, distributed locks by racing to create ephemeral nodes, and service discovery by listing ephemeral children. The ensemble must be odd-sized for quorum math; 5 nodes tolerates 2 simultaneous failures."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | Detailed write/read flow, snapshot + transaction log, session handling |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | ZooKeeper vs etcd vs Consul — when to use each |
| [04-tuning-guide.md](04-tuning-guide.md) | tickTime, JVM heap, session timeout tuning |
