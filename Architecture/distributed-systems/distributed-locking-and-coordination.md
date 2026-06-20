# Distributed Locking and Coordination

## The Core Problem (Start Here)

On a single machine, locking is simple: only one thread grabs a mutex at a time; the OS ensures fairness. In a distributed system, this guarantee evaporates.

Consider a bank that runs two processes for double-spend prevention: process A and process B each check "does user have enough balance?" before charging. Both check at the same moment, both see a balance of $100, both approve a $90 charge — the user gets two charges approved and your account goes negative. You needed a distributed lock to prevent this.

**The three problems that make distributed locks hard:**

1. **Network partitions:** A process can hold a lock but become unreachable — the lock is held but no work gets done. Other processes are blocked waiting for a lock that will never be released.

2. **Process pauses:** A process acquires a lock, then the JVM does a 30-second GC pause (or the process is paged out, or a kernel debugger is attached). The lock expires; another process acquires it. Both processes now believe they hold the lock simultaneously.

3. **Clock drift:** Lock TTLs are time-based. If one machine's clock is wrong, TTL calculations are wrong.

```
Dangerous scenario (process pause + lock expiry):

t=0:  Process A acquires lock (TTL = 10s)
t=9:  JVM GC pause begins on Process A
t=10: Lock expires (no renewal — A was paused)
t=10: Process B acquires the same lock
t=11: Process A wakes up from GC pause
      A still thinks it holds the lock ← BOTH A AND B NOW "HOLD" THE LOCK
      A writes to storage
      B writes to storage
      → Data corruption
```

The correct solution is **fencing tokens** — described next.

---

## Fencing Tokens: The Only Safe Solution

### The Pattern

Every time a lock is acquired (or renewed), the lock server returns a **monotonically increasing fencing token**. When the client writes to storage, it includes the token. The storage server **rejects writes with a token older than the last seen token**.

```
t=0:  Process A acquires lock → token = 33
t=1:  Process B tries → blocked (lock held)
t=9:  Lock expires (A paused during GC)
t=10: Process B acquires lock → token = 34  ← higher token
t=11: Process A wakes up, tries to write with token = 33
      Storage: "I already saw token 34 from B. Rejecting A's write with token 33."
      Process A's write is rejected safely.
```

**Critical requirement:** The storage layer must enforce fencing. A lock service alone cannot prevent stale writes — the storage must be fencing-token-aware.

This is why distributed locking is fundamentally a **cooperative protocol**: both the lock service AND the storage backend must participate.

---

## ZooKeeper-Based Distributed Locks

### How It Works

ZooKeeper's sequential ephemeral nodes are the classic primitive for distributed locking:

```
1. Client creates ephemeral sequential node under /locks/mylock:
   → /locks/mylock/0000000042   (ZK assigns sequence number)

2. Client checks: am I the lowest-numbered node?
   → YES: I hold the lock. Proceed.
   → NO: Watch the next-lowest node (not all nodes — avoids herd effect)

3. Releasing: client deletes its ephemeral node.
   → ZK notifies the next-lowest node's watcher.
   → That client now holds the lock.

4. If client crashes: ephemeral node is auto-deleted by ZK session expiry.
```

### The Herd Effect (and the Fix)

**Naïve implementation:** each waiter watches the root node `/locks/mylock`. When any node is deleted, ALL waiters wake up, all check for lowest node, only one wins — N-1 wakeups wasted.

**Fix:** Each waiter watches only the node immediately preceding it in sequence. Only one client wakes up when a lock is released — O(1) notification cost.

```
Nodes:  42, 43, 44, 45
Node 42 holds lock.
43 watches 42. 44 watches 43. 45 watches 44.

Node 42 releases → only 43 is notified → 43 acquires lock.
```

### ZooKeeper Limitations

- ZooKeeper uses **fixed heartbeat-based failure detection** (not adaptive). Session timeout = zookeeper.session.timeout.ms (default 30s). Long GC pauses can cause false session expiry.
- ZooKeeper is not designed for high-throughput locking (1000s of clients contending on one lock). Each lock acquisition requires a ZK quorum write.
- ZooKeeper is typically a 3–5 node cluster; it's a coordination service, not a general storage layer.

---

## etcd-Based Distributed Locks

### The Lease Primitive

etcd uses **leases** (TTL-based) for distributed locking:

```python
# Using etcd3 Python client
import etcd3

client = etcd3.client()

# Create lease with 30-second TTL
lease = client.lease(30)

# Acquire lock (CAS: create key only if it doesn't exist)
acquired = client.put_if_not_exists(
    '/locks/my-resource',
    value=socket.gethostname().encode(),
    lease=lease
)

if acquired:
    try:
        lease_thread = lease.refresh_loop()  # background thread renews lease
        # ... do work ...
    finally:
        lease.revoke()   # release lock
        lease_thread.cancel()
else:
    # Someone else holds lock; retry or fail fast
    pass
```

### The Compare-And-Swap (CAS) Primitive

etcd's `txn` (transaction) with `version = 0` check is the correct way to atomically acquire a lock:

```
txn:
  IF   (key "/lock" version == 0)  ← key doesn't exist
  THEN (put "/lock" value=myid lease=30s)
  ELSE (fail)

This is atomic at the etcd Raft level — no race condition.
```

**Lease refresh:** A background goroutine/thread calls `lease.KeepAlive()` every `TTL/3` seconds. If the client crashes, the lease expires and the key is automatically deleted — releasing the lock.

**Production:** Kubernetes uses etcd leases for controller-manager and scheduler leader election. Only one replica of each is active at a time.

---

## Redlock Algorithm (Redis)

### Antirez's Proposal

Redlock (proposed by Redis creator Salvatore Sanfilippo) is a distributed lock algorithm over **N independent Redis nodes** (no replication):

```
To acquire lock:
1. Get current timestamp t1
2. Try to SET key NX (not exists) EX ttl on N Redis nodes
3. Count successes (S)
4. Lock is acquired if: S >= ceil(N/2) + 1 (majority)
                        AND elapsed time < TTL
5. Actual TTL = original TTL - elapsed

To release:
1. DEL key from all N nodes (only if value matches — use Lua script)
```

### The Debate

**Martin Kleppmann's critique (2016):** Redlock is unsafe because it relies on timing assumptions that can be violated:

1. **Process pause after quorum but before use:** A process acquires Redlock (majority of nodes agree), then GC-pauses. TTL expires. Another process acquires the lock. Original process wakes up, still thinks it holds the lock. **Without fencing tokens, both processes believe they hold the lock.**

2. **Clock jump:** If any Redis node's clock jumps forward (NTP or sysadmin error), keys expire sooner than expected — same race condition.

3. **Network delays:** Acquiring the lock takes time proportional to network RTT. During that time, the validity window shrinks.

**Antirez's response:** Redlock is designed for environments where semi-correctness is acceptable — process pauses are rare, and the probability of a race is low. With fencing tokens, even Redlock becomes safe.

### When Redlock Is Acceptable

| Scenario | Verdict |
|---|---|
| Preventing concurrent expensive recomputation (stampede protection) | ✓ Acceptable (double computation is expensive, not catastrophic) |
| Rate limiting (two requests processed instead of one) | ✓ Acceptable |
| Financial transactions, exact-once payment processing | ✗ Use etcd/ZK + fencing tokens |
| Protecting critical invariants (inventory ≥ 0) | ✗ Use database-level serializable transactions |

---

## Leader Election vs. Distributed Locking

These are the same problem with different framing:

- **Distributed lock:** exclusive access to a resource for a duration
- **Leader election:** one node is designated "leader" and has authority to act

Both use the same primitives (ZooKeeper ephemeral nodes, etcd leases, Paxos). The difference is semantic: a lock is typically short-duration (milliseconds to seconds); leader election is longer-duration (minutes to hours).

**Kubernetes leader election pattern:**

```yaml
# controller-manager uses a Lease object in kube-system
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: kube-controller-manager
  namespace: kube-system
spec:
  holderIdentity: controller-manager-pod-xyz  # current leader
  leaseDurationSeconds: 15
  renewTime: "2024-01-01T10:05:00Z"
  acquireTime: "2024-01-01T10:00:00Z"
```

Each candidate tries to set `holderIdentity` to itself using a CAS on `resourceVersion`. The winner becomes leader; others back off and retry every `leaseDurationSeconds`.

---

## Distributed Semaphores and Rate Limiting

### Distributed Semaphore

A semaphore allows N concurrent holders (vs. lock = 1). Implementation over etcd:

```python
MAX_CONCURRENCY = 10

def acquire_semaphore(client, resource_id, holder_id):
    # Count current holders
    holders = [k for k, _ in client.get_prefix(f"/semaphore/{resource_id}/")]
    if len(holders) < MAX_CONCURRENCY:
        client.put(f"/semaphore/{resource_id}/{holder_id}", b"1",
                   lease=client.lease(30))
        return True
    return False
```

### Token Bucket Over etcd

For distributed rate limiting, a token bucket can be implemented over etcd with Lua scripts on Redis (atomic decrement) or CAS on etcd:

```
Token bucket state:  { tokens: 100, last_refill: 1700000000 }

Consume token (atomic CAS on etcd):
  IF tokens >= 1:
    tokens = tokens - 1
    RETURN allow
  ELSE:
    RETURN deny
```

**Production:** Envoy rate limiting sidecar, API Gateway rate limiting, per-user request quotas.

---

## Comparison Table

| Mechanism | TTL-based | Fencing Tokens | Failure Detection | Production Use |
|---|---|---|---|---|
| **ZooKeeper ephemeral + sequential** | Session timeout (30s) | Via sequence number | Fixed heartbeat | HBase, Kafka (pre-KIP-833) |
| **etcd Lease + CAS** | Configurable TTL | Via `revision` (monotonic) | Adaptive | Kubernetes, Consul |
| **Redlock (Redis)** | Configurable TTL | Not built-in | Clock-based | Cache stampede prevention |
| **Database row lock** | Transaction-scoped | Implicit (MVCC version) | DB session | MySQL FOR UPDATE, Postgres advisory locks |

---

## Cross-References

- [failure-detection-and-recovery.md](./failure-detection-and-recovery.md) — how split-brain is detected and fencing (STONITH) is applied
- [paxos-and-consensus-variants.md](./paxos-and-consensus-variants.md) — ZooKeeper and etcd use Paxos/Raft internally
- [distributed-transactions.md](./distributed-transactions.md) — when you need coordination beyond a lock (multi-resource atomicity)

---

## Production Examples

| System | Mechanism | Purpose |
|---|---|---|
| **Kubernetes** | etcd Lease | controller-manager and scheduler leader election |
| **HBase** | ZooKeeper ephemeral | RegionServer assignment; master election |
| **Kafka (pre-KRaft)** | ZooKeeper | Broker leader election, controller election |
| **Kafka (KRaft mode)** | Raft-based (internal) | Eliminated ZooKeeper dependency |
| **Elasticsearch** | etcd-style CAS in internal Raft | Master node election, shard allocation |
| **Apache Hadoop YARN** | ZooKeeper | ResourceManager HA |
| **Chubby (Google)** | Multi-Paxos | Google's internal lock service; inspired ZooKeeper |

---

## FAANG Interview Application

**Likely questions:**
- "Design a distributed lock service for 100K concurrent clients."
- "Why is it dangerous to use Redis for a distributed lock in a financial transaction system?"
- "Explain fencing tokens. What problem do they solve that TTL-based locks don't?"
- "How does Kubernetes ensure only one scheduler replica is active at a time?"

**What interviewers evaluate:**
- Do you understand the process-pause / GC problem that makes naive TTL locks unsafe?
- Do you know fencing tokens and why the storage layer must participate?
- Can you reason about the Redlock debate and when it's/isn't safe?
- Do you know the practical primitives (etcd Lease + CAS, ZK sequential ephemeral)?

**Principal-level signal:**
> "Distributed locks are a code smell at high scale. If you find yourself reaching for a distributed lock for every write, you have a design problem. The correct question is: can I restructure this as a single-resource compare-and-swap, a CRDT, or a queue-based serialization? Locks are appropriate for coordinating rare, exclusive operations — like leader election or migrating a resource. For high-throughput mutual exclusion, redesign the data model so competing writers work on non-overlapping keys, or use optimistic concurrency (CAS) with retry. Reserve distributed locks for where they're truly necessary, and always pair them with fencing tokens at the storage layer."
