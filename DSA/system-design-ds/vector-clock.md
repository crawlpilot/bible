# Vector Clock & Lamport Timestamp
**Category**: Logical Clocks — distributed causality tracking; used in DynamoDB, Riak, CRDTs, distributed databases

---

## 1. The Problem It Solves

### Ordering Events in Distributed Systems

In a distributed system, wall-clock time cannot be trusted for event ordering:
- Clocks on different machines drift (NTP accuracy: ~1–10ms)
- Two events on different machines can have the same timestamp
- You can't tell if event A *caused* event B just from timestamps

```
Machine A: writes key=X at 10:00:00.001
Machine B: writes key=X at 10:00:00.001  ← Which one wins? Same timestamp!

NTP drift of 5ms: A thinks it wrote at 9:59:59.998, B at 10:00:00.003
  → B "wins" even though A may have written after reading B's value
```

**Logical clocks** track causality: does event A *happen-before* event B?

---

## 2. Lamport Timestamp

### 2.1 Algorithm

Every process maintains a counter `L`. Rules:

1. **Local event**: increment `L++`.
2. **Send message**: increment `L++`, attach `L` to message.
3. **Receive message**: `L = max(L_local, L_received) + 1`.

```
Process A: L=0
Process B: L=0
Process C: L=0

A sends to B: A.L=1, message carries L=1
B receives:   B.L = max(0, 1) + 1 = 2
B sends to C: B.L=3, message carries L=3
C receives:   C.L = max(0, 3) + 1 = 4
```

**Property**: if A → B (A happened-before B), then `L(A) < L(B)`.

**Limitation**: `L(A) < L(B)` does NOT imply A → B. Two concurrent events can have different Lamport timestamps with no causal relationship.

```
A: L=5 (local event)
B: L=3 (concurrent, no message exchange)
→ L(B) < L(A) but neither happened-before the other
```

---

## 3. Vector Clock

### 3.1 Algorithm

Each process maintains a **vector of counters** — one per process. `V[i]` = number of events process `i` has had that this process knows about.

1. **Local event**: `V[self]++`.
2. **Send message**: `V[self]++`, attach full vector `V` to message.
3. **Receive message**: `V[self]++`, `V[j] = max(V[j], V_received[j])` for all `j`.

### 3.2 Causality Comparison

```
V1 < V2 (V1 happened-before V2) iff:
  V1[i] <= V2[i] for all i  AND  V1[j] < V2[j] for some j

V1 || V2 (concurrent) iff:
  neither V1 < V2 nor V2 < V1
  (V1[i] > V2[i] for some i AND V1[j] < V2[j] for some j)
```

```
Example with 3 processes [A, B, C]:

Initial: A=[0,0,0], B=[0,0,0], C=[0,0,0]

A does local event:   A=[1,0,0]
A sends to B:         A=[2,0,0], B receives → B=[2,1,0]  (B's own event + max)
B sends to C:         B=[2,2,0], C receives → C=[2,2,1]
A does local event:   A=[3,0,0]  ← concurrent with B and C's events

Compare A=[3,0,0] vs C=[2,2,1]:
  A[0]=3 > C[0]=2 → not A ≤ C
  A[1]=0 < C[1]=2 → not C ≤ A
  → CONCURRENT: A || C
```

---

## 4. Java Implementation

### 4.1 Lamport Clock

```java
import java.util.concurrent.atomic.AtomicLong;

public class LamportClock {

    private final AtomicLong counter = new AtomicLong(0);
    private final String nodeId;

    public LamportClock(String nodeId) { this.nodeId = nodeId; }

    // Tick for a local event, returns new timestamp
    public long tick() { return counter.incrementAndGet(); }

    // Tick before sending a message
    public long sendTick() { return counter.incrementAndGet(); }

    // Update on receiving a message with timestamp t
    public long receiveTick(long remoteTimestamp) {
        long updated;
        long current;
        do {
            current = counter.get();
            updated = Math.max(current, remoteTimestamp) + 1;
        } while (!counter.compareAndSet(current, updated));
        return updated;
    }

    public long current() { return counter.get(); }
    public String nodeId() { return nodeId; }

    @Override
    public String toString() { return nodeId + "@" + counter.get(); }
}
```

### 4.2 Vector Clock

```java
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class VectorClock {

    // nodeId → logical time
    private final Map<String, Long> vector;
    private final String nodeId;

    public VectorClock(String nodeId) {
        this.nodeId = nodeId;
        this.vector = new ConcurrentHashMap<>();
        vector.put(nodeId, 0L);
    }

    private VectorClock(String nodeId, Map<String, Long> vector) {
        this.nodeId = nodeId;
        this.vector = new ConcurrentHashMap<>(vector);
    }

    // Increment own entry (local event or send)
    public synchronized VectorClock tick() {
        vector.merge(nodeId, 1L, Long::sum);
        return this;
    }

    // Merge with received clock (on receive event)
    public synchronized VectorClock merge(VectorClock received) {
        for (Map.Entry<String, Long> entry : received.vector.entrySet()) {
            vector.merge(entry.getKey(), entry.getValue(),
                         (local, remote) -> Math.max(local, remote));
        }
        vector.merge(nodeId, 1L, Long::sum); // own increment on receive
        return this;
    }

    // Causal comparison
    public enum Relation { BEFORE, AFTER, CONCURRENT, EQUAL }

    public Relation compareTo(VectorClock other) {
        Set<String> allNodes = new HashSet<>(this.vector.keySet());
        allNodes.addAll(other.vector.keySet());

        boolean thisLessThanOther = false;
        boolean otherLessThanThis = false;

        for (String node : allNodes) {
            long myVal    = this.vector.getOrDefault(node, 0L);
            long otherVal = other.vector.getOrDefault(node, 0L);
            if (myVal < otherVal) thisLessThanOther = true;
            if (myVal > otherVal) otherLessThanThis = true;
        }

        if (!thisLessThanOther && !otherLessThanThis) return Relation.EQUAL;
        if (thisLessThanOther && !otherLessThanThis)  return Relation.BEFORE;
        if (!thisLessThanOther)                       return Relation.AFTER;
        return Relation.CONCURRENT;
    }

    public boolean happensBefore(VectorClock other) {
        return compareTo(other) == Relation.BEFORE;
    }

    public boolean isConcurrentWith(VectorClock other) {
        return compareTo(other) == Relation.CONCURRENT;
    }

    public VectorClock copy() { return new VectorClock(nodeId, vector); }

    @Override
    public String toString() {
        return new TreeMap<>(vector).toString();
    }
}
```

### 4.3 Versioned Value with Vector Clock (DynamoDB-style)

```java
import java.util.*;

public class VersionedStore {

    public record VersionedValue(String value, VectorClock clock) {}

    // key → list of concurrent versions (siblings)
    private final Map<String, List<VersionedValue>> store = new HashMap<>();
    private final String nodeId;

    public VersionedStore(String nodeId) { this.nodeId = nodeId; }

    public void put(String key, String value, VectorClock clientClock) {
        VectorClock newClock = (clientClock != null ? clientClock.copy() : new VectorClock(nodeId))
            .tick();

        List<VersionedValue> existing = store.getOrDefault(key, Collections.emptyList());
        List<VersionedValue> survivors = new ArrayList<>();

        for (VersionedValue v : existing) {
            VectorClock.Relation rel = newClock.compareTo(v.clock());
            if (rel != VectorClock.Relation.AFTER) {
                survivors.add(v); // keep versions not dominated by the new one
            }
        }
        survivors.add(new VersionedValue(value, newClock));
        store.put(key, survivors);
    }

    public List<VersionedValue> get(String key) {
        return store.getOrDefault(key, Collections.emptyList());
    }

    // Returns true if there are conflicting concurrent versions (needs reconciliation)
    public boolean hasConflict(String key) {
        return store.getOrDefault(key, Collections.emptyList()).size() > 1;
    }

    // Last-write-wins reconciliation (requires Lamport timestamp)
    public String reconcileLWW(String key) {
        return store.getOrDefault(key, Collections.emptyList())
            .stream()
            .max(Comparator.comparingLong(v -> v.clock().current()))
            .map(VersionedValue::value)
            .orElse(null);
    }
}
```

### 4.4 Distributed Write Coordinator (Amazon Dynamo Pattern)

```java
import java.util.*;

public class DynamoNode {

    private final String nodeId;
    private final VectorClock clock;
    private final Map<String, VersionedStore.VersionedValue> localData = new HashMap<>();

    public DynamoNode(String nodeId) {
        this.nodeId = nodeId;
        this.clock = new VectorClock(nodeId);
    }

    // Write: increment own clock, store with new clock
    public VectorClock write(String key, String value) {
        clock.tick();
        VectorClock writeClock = clock.copy();
        localData.put(key, new VersionedStore.VersionedValue(value, writeClock));
        return writeClock;
    }

    // Read-repair: on read, return all concurrent versions to client
    public List<VersionedStore.VersionedValue> read(String key,
                                                     List<VersionedStore.VersionedValue> replicas) {
        // Collect all versions from this node + replicas
        List<VersionedStore.VersionedValue> all = new ArrayList<>(replicas);
        VersionedStore.VersionedValue local = localData.get(key);
        if (local != null) all.add(local);

        // Remove dominated versions (keep only maximal versions)
        List<VersionedStore.VersionedValue> maximal = new ArrayList<>();
        for (VersionedStore.VersionedValue v : all) {
            boolean dominated = all.stream().anyMatch(
                other -> other != v && v.clock().happensBefore(other.clock())
            );
            if (!dominated) maximal.add(v);
        }
        return maximal; // size > 1 means conflict — return to client for resolution
    }

    // Sync: update local vector clock from received
    public void receiveSync(VectorClock remoteClock) {
        clock.merge(remoteClock);
    }

    public String nodeId() { return nodeId; }
}
```

---

## 5. Hybrid Logical Clocks (HLC)

Used in **CockroachDB** and **YugabyteDB**: combines physical time (wall clock) with logical time:

```
HLC timestamp: (wallTime, logicalCounter)

Rules:
  Local event:  if wall_now > hlc.wall → hlc = (wall_now, 0)
                else                    → hlc = (hlc.wall, hlc.logical + 1)
  Send:         same as local, attach HLC to message
  Receive(m):   hlc.wall    = max(hlc.wall, m.wall, wall_now)
                hlc.logical = if (hlc.wall == m.wall == wall_now) → max(hlc.logical, m.logical) + 1
                              elif (hlc.wall == m.wall)           → max(hlc.logical, m.logical) + 1
                              elif (hlc.wall == wall_now)         → hlc.logical + 1
                              else                                 → 0
```

**Benefit**: HLC timestamps are close to wall time (bounded drift), monotonically increasing, and capture causality. CockroachDB uses them to assign globally consistent MVCC timestamps without a global lock.

```java
public class HybridLogicalClock {

    private long wallTime = 0;
    private int logical = 0;
    private final java.time.Clock clock;

    public HybridLogicalClock(java.time.Clock clock) { this.clock = clock; }

    public synchronized long[] tick() {
        long now = clock.millis();
        if (now > wallTime) { wallTime = now; logical = 0; }
        else                { logical++; }
        return new long[]{wallTime, logical};
    }

    public synchronized long[] receive(long remoteWall, int remoteLogical) {
        long now = clock.millis();
        long newWall = Math.max(Math.max(wallTime, remoteWall), now);
        if (newWall == wallTime && newWall == remoteWall)
            logical = Math.max(logical, remoteLogical) + 1;
        else if (newWall == wallTime)
            logical++;
        else if (newWall == remoteWall)
            logical = remoteLogical + 1;
        else
            logical = 0;
        wallTime = newWall;
        return new long[]{wallTime, logical};
    }
}
```

---

## 6. Comparison

| Clock | Causality | Space | Wall-time | Conflict detection | Used in |
|---|---|---|---|---|---|
| Wall clock | No | O(1) | Yes | No | Naive systems |
| Lamport | Partial (one-way) | O(1) | No | No | Message ordering |
| Vector Clock | Complete | O(N) nodes | No | Yes (concurrent) | DynamoDB, Riak |
| Version Vector | Complete | O(N) nodes | No | Yes | Cassandra (lightweight txn) |
| HLC | Complete | O(1) | Approximate | Yes | CockroachDB, YugabyteDB |
| TrueTime (Google) | Complete | O(1) | Yes (bounded) | No (wait out uncertainty) | Google Spanner |

---

## 7. FAANG Interview Callouts

**"Two replicas in DynamoDB both accept a write to the same key during a partition. How does DynamoDB resolve this?"**
> DynamoDB uses version vectors (a variant of vector clocks). On reconciliation, compare the version vectors: if one dominates the other (happened-before), the newer one wins. If they are concurrent (neither dominates), both versions are surfaced to the application as siblings — the app must provide a reconciliation function (last-write-wins by default, or application-defined merge for CRDTs like shopping carts).

**"Why can't Cassandra use vector clocks like DynamoDB?"**
> Cassandra chose write timestamp (client-provided or server-assigned microsecond) with LWW semantics for simplicity and throughput. Vector clocks require O(N) space where N = number of replicas, add overhead to every read/write, and push conflict resolution to the application. At Cassandra's scale with hundreds of nodes, vector clocks become operationally complex. The trade-off: Cassandra loses some write ordering guarantees in exchange for simpler, faster operations.

**Follow-up questions to expect:**
1. "What is the space complexity problem with vector clocks?" → O(N) per key per version, where N = number of processes. At 1000 nodes, each key carries a 1000-entry vector. DynamoDB's fix: server-side vector clocks only (not per-client), and prune old entries — `vector clock explosion` is a real operational issue in early Amazon Dynamo.
2. "How does Google Spanner achieve linearisability without vector clocks?" → TrueTime API provides a time interval [earliest, latest] with bounded uncertainty (~7ms). Spanner waits `commit_wait` = uncertainty interval before returning a committed transaction, ensuring all future reads see a timestamp strictly after the commit. Causality guaranteed by wall time + wait, not logical clocks.
3. "What's the difference between a vector clock and a version vector?" → Vector clocks track per-process event counts for ordering any events. Version vectors track per-replica write counts for a specific key — used to detect whether one replica's value for a key dominates another's. Structurally identical; semantically scoped to one object vs system-wide.
