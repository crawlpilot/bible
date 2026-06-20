# Time and Causality in Distributed Systems

## The Core Problem (Start Here)

Imagine two friends, Alice and Bob, editing a shared Google Doc at the same time — each on their own laptop with their own clock. Alice's laptop clock says 10:00:01 AM when she types "Hello". Bob's clock says 10:00:00 AM when he types "World". If we sort by timestamp, "World" appears before "Hello" — even though Alice typed first in wall-clock reality.

This is the fundamental problem: **physical clocks on different machines are not perfectly synchronized, and even a few milliseconds of drift can invert the apparent order of events.** In distributed systems, this breaks assumptions that feel obvious on a single machine.

```
Reality:     Alice types first   →   Bob types second
Clocks:      Alice clock = 10:00:01   Bob clock = 10:00:00
Naive sort:  "World" (00) before "Hello" (01)   ← WRONG ORDER
```

The solution isn't "use better clocks" — it's to reason about **causality** (what event caused what) rather than absolute time.

---

## Why Physical Clocks Cannot Be Trusted

### Clock Drift

Every computer has a quartz crystal oscillator that ticks slightly differently from every other. Left uncorrected, a typical server clock drifts by **~1 second per day** (10–50 ppm). NTP (Network Time Protocol) corrects this periodically, but:

- NTP synchronization accuracy over the internet: **±100ms**
- NTP over a datacenter LAN: **±1ms**
- NTP can step the clock forward **or backward** — a timestamp from "the future" can appear, then time goes backward

### The Leap Second Problem

UTC adds a "leap second" roughly every 18 months to account for Earth's irregular rotation. On June 30, 2012, a leap second caused Linux kernels to enter a busy loop — taking down Reddit, Foursquare, LinkedIn, and others. The problem: code assumed `time.now()` always increases monotonically.

### Monotonic vs. Wall-Clock Time

| Clock Type | Purpose | Can Go Backward? |
|---|---|---|
| **Wall clock** (`System.currentTimeMillis()`, `time.time()`) | Human-readable time of day | Yes (NTP corrections, leap seconds) |
| **Monotonic clock** (`System.nanoTime()`, `CLOCK_MONOTONIC`) | Measuring elapsed time | No (guaranteed to increase) |

**Rule:** Use wall clock only for human display. Use monotonic clock for measuring durations. Use logical clocks (below) for ordering distributed events.

---

## Lamport Logical Clocks

### Intuition

Leslie Lamport's 1978 paper "Time, Clocks, and the Ordering of Events in a Distributed System" introduced a simple idea: instead of asking "what time did this happen?", ask "did this event happen before or after that one?"

**The happens-before relation (→):** Event A → B means A causally precedes B — A could have influenced B.

Three cases where A → B:
1. A and B are on the same process, and A happens first
2. A is "send message" and B is "receive that message"
3. There exists C such that A → C and C → B (transitivity)

If neither A → B nor B → A, they are **concurrent** — neither could have influenced the other.

### The Algorithm

Each process maintains a counter `L`. Rules:

```
Before executing any event:     L = L + 1
Before sending a message:       L = L + 1; attach L to message
Upon receiving a message(ts):   L = max(L, ts) + 1
```

**Example — three processes:**

```
Process P1:   L=1        L=2                L=4
              [a]  ─────────────────────→  [d]
                                    ↑
Process P2:        L=1    L=2    L=3 receive(from P1 L=2)
                   [b]    [c]   receive(ts=2) → L=max(1,2)+1=3

Process P3:   L=1                          L=2
              [e]                          [f]
```

**What Lamport clocks guarantee:**
- If A → B, then `clock(A) < clock(B)` ✓
- **But:** `clock(A) < clock(B)` does NOT imply A → B

This means: Lamport clocks can tell you "these events are NOT concurrent" but cannot tell you "these events ARE causally related."

---

## Vector Clocks

### The Problem with Lamport Clocks

With Lamport clocks, if process P1 has clock=5 and P2 has clock=5, you can't tell if they're concurrent or one caused the other. Vector clocks solve this.

### The Algorithm

Each process maintains a **vector of counters**, one per process:

```
N processes → vector [L₁, L₂, ..., Lₙ]
```

Rules:
```
Local event on process Pᵢ:    Lᵢ = Lᵢ + 1
Send message from Pᵢ:         Lᵢ = Lᵢ + 1; attach full vector
Receive message at Pᵢ (vec):  Lⱼ = max(Lⱼ, vec[j]) for all j; Lᵢ = Lᵢ + 1
```

**Comparing vectors:**
- V1 < V2 if every component of V1 ≤ every component of V2, and at least one is strictly less
- V1 ∥ V2 (concurrent) if neither V1 < V2 nor V2 < V1

**Example — shopping cart conflict (Amazon Dynamo style):**

```
User adds "Milk" on phone:         cart = {milk}     version = [1,0]
User adds "Bread" on laptop:       cart = {bread}    version = [0,1]
Network reconnects:
  [1,0] and [0,1] are concurrent → neither dominates
  Result: two "sibling" versions → show conflict to user, or merge
```

This is exactly how Amazon Dynamo handles shopping cart conflicts: detect concurrent writes via vector clocks, then either auto-merge (union of items) or present conflict to client.

### Vector Clock Limitations

- **Size:** Vector grows linearly with number of processes — impractical at large scale (1000 nodes)
- **Solution — Dotted Version Vectors (DVV):** Used in Riak. Reduces vector size by attaching a single "dot" (node, counter) to each value, separating causality tracking from value identity.

---

## Hybrid Logical Clocks (HLC)

### Motivation

Vector clocks capture causality but lose physical time — you can't tell if an event happened "3 hours ago" or "yesterday." Hybrid Logical Clocks combine both.

### The Algorithm

Each node maintains: `(physical_time, logical_counter)` = `(pt, c)`

```
Local event:
  l = max(pt, HLC.pt)
  if l == HLC.pt: c = HLC.c + 1
  else: c = 0
  HLC = (l, c)

Send/receive message with (m_pt, m_c):
  l = max(pt, HLC.pt, m_pt)
  if l == HLC.pt == m_pt: c = max(HLC.c, m_c) + 1
  elif l == HLC.pt: c = HLC.c + 1
  elif l == m_pt: c = m_c + 1
  else: c = 0
  HLC = (l, c)
```

**Properties:**
- HLC ≥ physical clock (HLC never goes below wall clock)
- If A → B, then HLC(A) < HLC(B)  ← causality preserved
- HLC ≈ physical time (bounded by NTP sync accuracy)
- **Size:** Just 64 bits (48-bit physical + 16-bit logical counter)

**Production use:**
- **CockroachDB:** HLC for MVCC timestamp ordering across nodes
- **YugabyteDB:** HLC for cross-shard transaction ordering

---

## Google TrueTime

### The Premise

What if instead of pretending physical clocks are accurate, you explicitly acknowledge the uncertainty?

TrueTime returns `[earliest, latest]` — a guaranteed interval containing the true current time. Built on:
- GPS clocks: accurate to ~40 nanoseconds
- Atomic clocks: long-term stability
- Each datacenter has both; TrueTime API exposes the worst-case uncertainty across the two

Typical TrueTime uncertainty (epsilon): **1–7 ms**

### The Commit-Wait Protocol (Spanner)

Spanner uses TrueTime to achieve **external consistency**: if transaction T2 starts after T1 commits in wall-clock reality, then `commit_timestamp(T1) < commit_timestamp(T2)`.

```
T1 commits at Spanner:
  1. Get TrueTime interval: TT.now() = [t_earliest, t_latest]
  2. Assign commit timestamp s = t_latest  (guaranteed ≤ true now)
  3. WAIT until TT.now().earliest > s      ← "commit wait"
     (wait until the clock uncertainty passes, so s is safely in the past)
  4. Release locks, apply commit

T2 starts after T1 commit in wall-clock time:
  TT.now().earliest > s (guaranteed by commit-wait)
  So T2's timestamp will be > s → T1's timestamp < T2's
```

**Commit-wait latency:** typically 1–14ms (2× epsilon). This is the price Spanner pays for external consistency.

```
Without TrueTime (most systems):
  Can't do commit-wait → must use 2PC across regions → 100s of ms

With TrueTime:
  Commit-wait cost = 1-14ms locally → no inter-region RTT for timestamp ordering
```

---

## Practical Comparison Table

| Mechanism | Captures Causality | Physical Time | Size | Clock Ordering Guarantee | Used In |
|---|---|---|---|---|---|
| Physical clock (NTP) | No | Yes (±100ms) | 64-bit | None | Logging, metrics |
| Lamport clock | Partial (→ gives <, not vice versa) | No | 64-bit | A→B implies clock(A)<clock(B) | Basic causality |
| Vector clock | Yes (exact) | No | O(n) bits | Concurrent detection | Dynamo, Riak |
| HLC | Yes | ~Yes (bounded) | 64-bit | A→B implies HLC(A)<HLC(B), HLC≈wall | CockroachDB, YugabyteDB |
| TrueTime | Yes | Yes (bounded uncertainty) | 2×64-bit | External consistency | Spanner |

---

## "You Don't Have TrueTime" — Practical Answer

In a FAANG interview, if asked "how do you order global events without TrueTime?":

**Option 1: Accept causal consistency (most systems)**
- Use vector clocks or HLC to detect concurrent events
- Resolve conflicts with LWW, CRDT merge, or user-visible conflict
- Example: Cassandra, DynamoDB

**Option 2: Global sequencer service**
- One service assigns monotonically increasing sequence numbers to all writes
- Bottleneck but simple; shard the sequencer for scale
- Example: Twitter Snowflake, Flicker ID generator, Facebook's lease-epoch approach

**Option 3: Paxos/Raft for global ordering**
- Use a consensus group to totally order all writes
- Expensive (multi-RTT for cross-region), but gives strict serializability
- Example: Google Chubby, etcd (single region)

**Option 4: HLC + bounded clock skew assumption**
- Set max_clock_skew = 500ms; wait 500ms after commit before reading
- Gives "external consistency" modulo the skew assumption
- Example: CockroachDB

---

## Cross-References

- See [DSA/system-design-ds/vector-clock.md](../../DSA/system-design-ds/) for vector clock implementation details
- See [paxos-and-consensus-variants.md](./paxos-and-consensus-variants.md) for consensus-based ordering
- See [distributed-transactions.md](./distributed-transactions.md) for TrueTime + Spanner 2PC integration
- See [replication-patterns.md](./replication-patterns.md) for replication lag and read anomalies

---

## Production Examples

| System | Mechanism | Why |
|---|---|---|
| **Amazon Dynamo** | Vector clocks | Detect shopping cart conflicts; auto-merge or surface to user |
| **Riak** | Dotted Version Vectors | Improved vector clocks: fixed size, better sibling semantics |
| **CockroachDB** | HLC | Cross-shard MVCC ordering; bounded skew assumption |
| **YugabyteDB** | HLC | Same as CockroachDB, distributed MVCC |
| **Google Spanner** | TrueTime + commit-wait | External consistency across global datacenters |
| **Cassandra** | LWW with wall clock | Simple; accepts data loss on concurrent writes |
| **Apache Flink** | Watermarks (event-time processing) | Out-of-order event handling with bounded lateness |

---

## FAANG Interview Application

**Likely questions:**
- "Two users update the same record in different datacenters at the same time. How do you detect and resolve the conflict?"
- "Explain how Google Spanner achieves external consistency. What makes it different from other databases?"
- "You're designing a globally distributed ledger. How do you ensure transaction ordering?"
- "What is a Lamport clock? What can it tell you that a physical clock can't?"

**What interviewers evaluate at principal level:**
- Do you distinguish between wall-clock ordering and causal ordering?
- Can you explain why "last write wins" with physical timestamps can lose data?
- Do you know the practical trade-offs between HLC and TrueTime?
- Can you identify when full external consistency is needed vs. when causal consistency suffices?

**Principal-level signal:**
> "For most systems, causal consistency via HLC is sufficient and dramatically cheaper than Spanner-style external consistency. HLC gives you 64-bit timestamp overhead, causality preservation, and physical-time approximation. External consistency (Spanner) adds 1–14ms commit-wait and GPS/atomic clock infrastructure — justified only when you need cross-region serializable transactions, like in a financial ledger or inventory system. For a user-profile store, LWW with an HLC is perfectly acceptable."
