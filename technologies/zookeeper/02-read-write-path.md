# ZooKeeper — Read & Write Path

## Storage Architecture

ZooKeeper's persistence model has two complementary components:

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    ZooKeeper Server Process                  │
  │                                                             │
  │  ┌──────────────────────────────────┐                       │
  │  │      In-Memory Data Tree         │  ← primary data store │
  │  │  (DataTree: all znodes + ACLs)   │    must fit in RAM    │
  │  └──────────────────────────────────┘                       │
  │             ▲                ▲                               │
  │             │                │                               │
  │  ┌──────────┴────────┐  ┌────┴──────────────┐               │
  │  │  Transaction Log  │  │   Snapshot File   │               │
  │  │  (WAL: append)    │  │  (fuzzy snapshot  │               │
  │  │  txn1,txn2,txn3...│  │   of DataTree)    │               │
  │  └───────────────────┘  └───────────────────┘               │
  │         (disk)                  (disk)                       │
  └─────────────────────────────────────────────────────────────┘
```

### Transaction Log (WAL)

Every committed write is appended to the transaction log before being applied to the in-memory tree:

- Stored in `dataLogDir` (should be on a **dedicated disk** separate from snapshots)
- Entries are force-synced (`fsync`) to disk before ACK — this is the durability guarantee
- Log is pre-allocated in blocks (default 64 MB) to avoid filesystem allocation overhead
- Log files are named `log.<lowestZXID>` (the ZXID of the first transaction in that file)
- Automatically cleaned up by `autopurge` or manually with `zkCleanup.sh`

**Critical**: `dataLogDir` should be on a separate disk/volume from snapshot and data directories. The transaction log is the hot path — mixing it with other I/O introduces latency spikes that can cause session timeouts.

### Snapshot

Periodic full serialisation of the in-memory DataTree to disk:

- Triggered when `snapCount` transactions have been logged since the last snapshot (default: 100,000)
- ZooKeeper uses **fuzzy snapshots**: the snapshot is taken concurrently with ongoing writes, so the resulting snapshot file represents a consistent-ish but not perfectly atomic state
- On recovery, the server loads the most recent snapshot, then replays all transaction log entries with ZXID > snapshot's last ZXID
- Snapshot files grow as large as the dataset; typical production snapshots are 100 MB – 1 GB

**Fuzzy snapshot correctness**: Since transactions are idempotent (applying the same transaction twice produces the same result), replaying transactions that were already applied during the snapshot is safe — they produce no net change.

---

## Write Path (Detail)

```
Step-by-step write: setData("/config/timeout", "30000")

CLIENT
  │
  ├─[1]─ Send REQUEST to connected server (may be any server)
  │
FOLLOWER (if client connected to follower)
  │
  ├─[2]─ Forward request to LEADER
  │
LEADER
  ├─[3]─ Assign ZXID: epoch=5, counter=1042 → ZXID = 0x0000000500000412
  ├─[4]─ Serialise transaction: {ZXID, path, data, version}
  ├─[5]─ Append to local transaction log + fsync
  ├─[6]─ Broadcast PROPOSAL(ZXID, txn) to all FOLLOWERS
  │
FOLLOWERS (each independently)
  ├─[7]─ Validate proposal (ZXID is next expected)
  ├─[8]─ Append txn to local transaction log + fsync
  ├─[9]─ Send ACK(ZXID) to leader
  │
LEADER
  ├─[10]─ Wait for QUORUM ACKs (⌊N/2⌋ + 1)
  ├─[11]─ Apply txn to in-memory DataTree
  ├─[12]─ Broadcast COMMIT(ZXID) to all followers
  ├─[13]─ Send SUCCESS response to client (via original follower if applicable)
  │
FOLLOWERS
  └─[14]─ Apply txn to own in-memory DataTree (after receiving COMMIT)

Total latency: ~1–5 ms (LAN); ~10–50 ms (cross-AZ)
```

### Write Latency Breakdown

| Step | Typical Time | Bottleneck |
|------|-------------|------------|
| Client → server network | 0.1–0.5 ms | Network latency |
| Follower → leader forward | 0.1–0.5 ms | If client on follower |
| Leader transaction log fsync | 0.5–2 ms | **Disk I/O — #1 bottleneck** |
| Leader → follower broadcast | 0.1–0.5 ms (LAN) | Network |
| Follower fsync + ACK | 0.5–2 ms | Disk I/O on follower |
| Quorum wait | max(follower fsync latencies) | Quorum dependency |
| **Total (3-node, LAN, SSD)** | **1–5 ms** | |
| **Total (5-node, cross-AZ)** | **10–30 ms** | |

**Implication**: Use SSDs for `dataLogDir`. The fsync on the transaction log is synchronous and on the critical write path. Spinning disks with seek times > 5 ms will make writes > 10 ms even on a local network.

---

## Read Path (Detail)

```
Step-by-step read: getData("/config/timeout")

CLIENT
  │
  ├─[1]─ Send READ REQUEST to connected server (any server: leader, follower, observer)
  │
SERVER (local, no consensus required)
  ├─[2]─ Look up path in in-memory DataTree
  ├─[3]─ Return data + Stat (version, ZXID of last modification, etc.)
  │
CLIENT
  └─[4]─ Receive response

Total latency: < 1 ms (local RAM lookup, no network to leader)
```

### Read Staleness

Reads in ZooKeeper are **not linearizable by default** — a follower may return data that has not yet applied the most recent committed write if the follower lags behind the leader.

```
Timeline:
  t=0: Client A writes /config = "new-value" (ACKed by leader after quorum)
  t=1: Leader commits, follower-1 applies
  t=2: Follower-2 receives COMMIT but hasn't applied yet
  t=3: Client B reads /config from follower-2 → gets "old-value"  ← stale read
  t=4: Follower-2 applies → subsequent reads return "new-value"
```

**For strong consistency reads**, use `sync()` before `getData()`:

```java
// sync() forces the server to catch up to the leader before serving the read
zk.sync("/config", (rc, path, ctx) -> {
    zk.getData("/config", false, (rc2, path2, ctx2, data, stat) -> {
        // guaranteed to see latest committed write
    }, null);
}, null);
```

`sync()` is not free — it adds a round-trip to the leader. Use it only when you need read-your-writes consistency or when consistency is more important than latency.

---

## Session Lifecycle (Detail)

```
  Client connect flow:

  1. Client picks a server from the provided server list
     (round-robin by default in official client; random in Curator)

  2. Sends ConnectRequest:
     { protocolVersion, lastZxidSeen, sessionTimeout, sessionId=0, password=[] }

  3. Server responds with ConnectResponse:
     { protocolVersion, sessionTimeout (negotiated), sessionId, password }
     sessionTimeout = max(minSessionTimeout, min(maxSessionTimeout, requested))
     minSessionTimeout = 2 × tickTime
     maxSessionTimeout = 20 × tickTime  (configurable)

  4. Client sends PING every tickTime/3 ms to keep session alive

  5. If server doesn't receive PING within sessionTimeout:
     - Session marked EXPIRED
     - All ephemeral nodes for this session deleted
     - All watches for this session invalidated

  6. Client reconnecting after transient disconnect:
     - Sends ConnectRequest with saved sessionId + password
     - If sessionId still valid on server: session restored, no data loss
     - If sessionId expired: client gets SessionExpiredException; must rebuild state
```

### Session Expiry vs Disconnect

| Event | Client State | Ephemeral Nodes | Watches | Recovery |
|-------|-------------|----------------|---------|---------|
| Transient disconnect | CONNECTING | **Preserved** (not yet expired) | **Preserved** | Transparent reconnect with same session |
| Session timeout | CLOSED (SessionExpired) | **Deleted** | **Invalidated** | Must reconnect, re-create ephemeral nodes, re-register watches |
| Server crash (within timeout) | CONNECTING | Preserved if reconnects in time | Preserved | Reconnect to other server |

**Critical operational implication**: Set session timeout based on the longest acceptable leader election window, not the fastest network. If leader election takes 3 seconds and session timeout is 2 seconds, sessions expire during every leader election — cascading failures as all ephemeral nodes (service registrations, locks) are deleted.

---

## Recovery Path

When a ZooKeeper server restarts after a crash:

```
Startup sequence:

  1. Load most recent snapshot from disk into DataTree (memory)
     Snapshot file name encodes the highest ZXID it contains: snapshot.ZXID

  2. Scan transaction log files for entries with ZXID > snapshot's ZXID

  3. Replay each transaction log entry in order:
     - Apply to in-memory DataTree
     - This catches up to the state at crash time

  4. Server joins ensemble:
     - Contacts leader (or triggers election if no leader)
     - Leader sends DIFF: all committed transactions since this server's lastZXID
     - If diff is too large: SNAP — leader sends a full snapshot
     - Server applies diff/snap, transitions to FOLLOWING state

  5. Server ready to serve reads; followers ready to forward writes
```

### Recovery Time Estimation

| Snapshot Size | Transactions Since Snapshot | Estimated Recovery |
|--------------|----------------------------|-------------------|
| 100 MB | 10K txns | ~1–3 s |
| 500 MB | 100K txns | ~5–10 s |
| 1 GB | 1M txns | ~30–60 s |
| > 1 GB | Backlogged | Minutes — indicates config problem (snapCount too high) |

**Tuning**: Set `snapCount` lower (e.g., 10,000) to produce more frequent, smaller snapshots. This reduces replay time but increases snapshot I/O. Production sweet spot: 10,000–50,000.

---

## Watch Delivery Guarantees

ZooKeeper guarantees watches are delivered in the following order relative to events:

1. **Watches are ordered**: if A happened before B, watch for A fires before watch for B
2. **Watches are ordered with respect to data**: if a client sets a watch and receives the watch event, any subsequent read will see a state at least as recent as the event that triggered the watch
3. **Watches survive server failover**: watches registered with a follower are preserved when the client reconnects to a different server in the same session

**What watches do NOT guarantee**:
- That the watch fires before the same change is visible to other clients
- That the watch fires at all if the session expires
- The new value of the changed node (the event only contains path + type)

---

## FAANG Interview Callout

> "ZooKeeper's write path is a two-phase commit across the ensemble: the leader assigns a globally ordered ZXID, appends to its transaction log with fsync, broadcasts to followers who also fsync and ACK, and only after quorum ACKs does the leader commit to memory and respond to the client. This means write latency is dominated by disk fsync — put the transaction log on a dedicated SSD. Reads are local in-memory lookups on any server, so they're sub-millisecond but potentially stale. For strong consistency reads, call sync() first to force the server to catch up to the leader. The critical operational risk is session timeout during leader election: if your session timeout is shorter than your leader election window, all ephemeral nodes get deleted during every leader election, which can cause cascading failures in systems that depend on ZooKeeper for service discovery or distributed locking."
