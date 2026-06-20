# CRDTs and Conflict Resolution

## The Core Problem (Start Here)

Suppose two people edit the same shared shopping cart offline — Alice on a plane, Bob in a subway tunnel — then reconnect. Alice added "milk"; Bob added "bread". When they sync, both additions should survive. This is easy: just union the two sets.

Now suppose Alice added "milk" and Bob *removed* "milk" while offline. Who wins? Without additional information, you can't know. **Concurrent conflicting updates are the fundamental challenge of distributed data.**

Most systems avoid this by forcing all writes through a single leader (no concurrent writes to the same data). But that limits availability: if the leader is unreachable, you can't write. CRDTs offer an alternative: **design your data structure so that any two replicas can always be merged, and the merge is always correct — regardless of order or timing.**

```
Alice's replica:  { milk, eggs }
Bob's replica:    { milk, bread }   (concurrent edit, no coordination)
After merge:      { milk, eggs, bread }  ← correct, no conflicts
```

---

## The Conflict Problem: Four Approaches

| Approach | Description | Data Loss? | Coordination Required? |
|---|---|---|---|
| **Single-leader** | All writes go through one node | No | Yes (bottleneck) |
| **Last-Write-Wins (LWW)** | Higher timestamp wins | Yes (losing write) | No |
| **Operational Transformation (OT)** | Transform conflicting operations | No | Yes (central server) |
| **CRDTs** | Merge function defined by data structure | No | No |

---

## Last-Write-Wins (LWW)

### How It Works

Each value carries a timestamp. On conflict, the higher timestamp wins.

```
Node A writes:  x = "hello"  at t=100
Node B writes:  x = "world"  at t=99   (concurrent, Bob's clock is slightly behind)
After sync:     x = "hello"  ← "world" is silently discarded
```

### When LWW Is Acceptable

- **Immutable data** (append-only logs, audit events) — no real conflicts
- **Cache invalidation** — losing an intermediate state is fine
- **Single-writer per key** — no real concurrency on that key

### When LWW Is Not Acceptable

- **Counters** — both nodes increment; LWW picks one, losing the other increment
- **User edits** — silent data loss breaks user trust
- **Financial records** — losing a debit is a serious bug

**Cassandra uses LWW by default** for its regular column types. With sufficient application discipline (single writer per key, idempotent writes), this is workable. For mutable multi-writer data, use Cassandra's CRDT column types instead.

---

## Operational Transformation (OT)

### The Google Docs Approach

OT was the foundation for Google Wave and early Google Docs. The idea: don't just apply operations, *transform* them relative to concurrent operations so they remain consistent.

```
Document: "hello"
User A: insert "!" at position 5  → "hello!"
User B: insert " world" at position 5  → "hello world"

Both applied naively → different results depending on order.

With OT:
  If B's op arrives first: A's op must be transformed to insert at position 11
  Result: "hello world!" regardless of arrival order
```

**Why OT is hard:** The transformation function `transform(opA, opB)` must be defined for every pair of operation types. With rich documents (insert, delete, format, move), this combinatorial explosion makes OT notoriously difficult to implement correctly. OT also typically requires a central server to serialize operations.

**Google's replacement:** Google Docs now uses a different approach (partly CRDT-based with a central sequencer) for better reliability.

---

## CRDTs: Mathematical Foundation

### What Makes a Data Structure a CRDT

A CRDT (Conflict-free Replicated Data Type) is a data structure that satisfies one of two equivalent definitions:

**State-based CRDT (CvRDT):** The state forms a **join-semilattice**:
- There is a partial order on states
- Any two states have a **least upper bound (LUB)** — the "merge" operation
- The state only ever moves up the lattice (monotonically grows)

```
Integer max CRDT:     {1, 5, 3} → max = 5
                       {1, 5, 3, 7} → max = 7   (monotonically grows)

merge(state_A, state_B) = LUB = element-wise max
```

**Op-based CRDT (CmRDT):** Operations are commutative — applying them in any order gives the same result.

```
Commutative:     add(milk) then add(bread) = add(bread) then add(milk)  ✓
Not commutative: "set counter to 5" then "add 3" ≠ "add 3" then "set to 5"  ✗
```

**Key property:** CRDTs guarantee **Strong Eventual Consistency (SEC)**: any two replicas that have received the same set of updates (in any order) will be in the same state.

---

## CRDT Types: Counters

### G-Counter (Grow-only Counter)

**Problem:** A single integer can't be safely incremented on multiple nodes (two nodes each add 1 → you need to know it's been incremented twice, not once).

**Solution:** Each node maintains its own counter; the total is the sum.

```
State:  { node1: 5, node2: 3, node3: 2 }
Value:  5 + 3 + 2 = 10

Node 1 increments:  state = { node1: 6, node2: 3, node3: 2 }  value = 11
Node 2 increments:  state = { node1: 5, node2: 4, node3: 2 }  value = 11

Merge (LUB = element-wise max):
  { node1: max(6,5), node2: max(3,4), node3: max(2,2) }
= { node1: 6, node2: 4, node3: 2 }   value = 12  ✓
```

### PN-Counter (Positive-Negative Counter)

Combines two G-Counters: one for increments (P), one for decrements (N).

```
Value = sum(P) - sum(N)
P state: { node1: 10, node2: 3 }
N state: { node1: 2,  node2: 1 }
Value = 13 - 3 = 10
```

**Merge:** merge P and N separately (element-wise max on each).

**Production use:** Redis CRDT (Redis Enterprise), distributed like/dislike counts, inventory reservation counts.

---

## CRDT Types: Sets

### G-Set (Grow-only Set)

Only supports `add`. Elements are never removed. Merge = union.

```
Node A: { apple, banana }
Node B: { banana, cherry }
Merge:  { apple, banana, cherry }  ← union
```

### 2P-Set (Two-Phase Set)

Adds a tombstone set: elements can be added or removed, but once removed, they can never be re-added.

```
Add-set A: { apple, banana }
Remove-set R: { apple }
Value: A - R = { banana }

Merge: union both add-sets, union both remove-sets.
Limitation: Can't re-add "apple" after it's in R.
```

### OR-Set (Observed-Remove Set)

The most practical set CRDT. Each `add` operation creates a unique tag. Removing an element removes all its tags seen so far — but a concurrent `add` creates a new tag that survives.

```
Node A adds "milk":  milk gets tag (A, 1)   set = { (milk, A1) }
Node B removes "milk":  removes observed tags → removes (A, 1)
Concurrent: Node A adds "milk" again with tag (A, 2)

After merge:  (A, 1) was removed; (A, 2) survived → milk is in the set
```

**This resolves the classic add-remove conflict: the latest add wins, even under concurrency.**

**Production use:** Amazon shopping cart (Dynamo paper), Riak Sets, collaborative element lists.

---

## CRDT Types: Registers

### LWW-Register (Last-Write-Wins Register)

A single value with a timestamp. On merge, higher timestamp wins. The simplest possible register — but has data loss as shown earlier.

### MV-Register (Multi-Value Register)

Stores all concurrent values as "siblings" — doesn't silently discard any. The application or user resolves the conflict.

```
Node A writes: x = "red"   with version [A:1, B:0]
Node B writes: x = "blue"  with version [A:0, B:1]   (concurrent)

Merge: x has siblings: { "red", "blue" }
Application: show both to user, ask them to pick → or custom merge logic
```

**Production:** Riak CRDT registers. Dynamo's "shopping cart siblings" — the app merges by presenting both carts to the user, who resolves the conflict (or the app takes the union).

---

## CRDT Types: Sequences (Text Editing)

### RGA (Replicated Growable Array)

Enables collaborative text editing without a central server. Each character insertion includes a globally unique identifier and a reference to the preceding character.

```
Document: ""
Alice inserts "H" after start:  [H(alice,1)]
Bob inserts "i" after start (concurrent): [i(bob,1)]

Merge conflict: both inserted after "start"
Resolution: total order on IDs (e.g., alice < bob alphabetically)
Result: [H(alice,1), i(bob,1)] → "Hi"
```

**Production:** Figma's multiplayer editing, some versions of collaborative code editors. Alternative: YATA algorithm (used in Yjs, the library behind many collaborative editors including VS Code Live Share).

---

## CRDT vs. Consensus: When to Use Each

| Scenario | CRDT | Consensus (Raft/Paxos) | Why |
|---|---|---|---|
| Distributed counter (likes, views) | ✓ G-Counter | ✗ Overkill | CRDT handles concurrent increments; no coordination needed |
| Shopping cart merging | ✓ OR-Set | ✗ Latency cost | Cart can be eventually consistent; merge is semantically correct |
| Collaborative text editing | ✓ RGA/YATA | ✗ Latency | Sub-ms merge without network roundtrip |
| Bank account balance (overdraft prevention) | ✗ Need invariant enforcement | ✓ Consensus | CRDTs can't enforce "balance ≥ 0" across concurrent decrements |
| User profile (name, email) | LWW or ✓ MV-Register | ✗ Overkill | Single writer per field; LWW acceptable |
| Leader election, locks | ✗ Not designed for this | ✓ Required | Requires strong consistency guarantees |
| Inventory (must not oversell) | ✗ No invariant enforcement | ✓ Required | Need to enforce count ≥ 0 |

**The core limitation of CRDTs:** They can only express monotonically growing or commutative state. They cannot enforce **invariants** (like "balance ≥ 0") across concurrent conflicting operations without coordination.

---

## Production Deployments

| System | CRDT Type | Use Case |
|---|---|---|
| **Amazon Dynamo** | Vector clock + OR-Set merge | Shopping cart, add wins on conflict |
| **Riak** | G-Counter, PN-Counter, OR-Set, MV-Register | First major OSS CRDT database |
| **Redis Enterprise (Redis CRDT)** | G-Counter, PN-Counter, OR-Set, LWW-Register | Multi-region Redis with conflict resolution |
| **Figma** | CRDT sequence (custom) | Real-time multiplayer design editing |
| **Apple Notes** | CRDT (proprietary) | Offline editing sync on Apple devices |
| **Apache Cassandra** | Counter column (PN-Counter semantics) | Distributed counters |
| **Yjs / Automerge** | CRDT libraries | Collaborative editors (VS Code, Notion-style apps) |

---

## Cross-References

- [replication-patterns.md](./replication-patterns.md) — multi-leader conflict detection
- [time-and-causality.md](./time-and-causality.md) — vector clocks used in OR-Set tags
- [multi-region-distribution.md](./multi-region-distribution.md) — CRDTs for globally distributed data

---

## FAANG Interview Application

**Likely questions:**
- "Two users edit a document offline and come back online. How do you merge the changes?"
- "Design a distributed counter for a 'likes' feature at 100M events/day. How do you avoid coordination?"
- "What's the difference between a G-Set and an OR-Set? When would you use each?"
- "Why can't you use a CRDT to enforce 'don't sell more inventory than you have'?"

**What interviewers evaluate:**
- Do you understand when CRDTs apply and when they don't?
- Can you explain the mathematical invariant (join-semilattice / commutative operations)?
- Do you know real-world examples (Dynamo shopping cart, Figma, Riak)?
- Can you reason about the invariant-enforcement limitation?

**Principal-level signal:**
> "CRDTs are an architectural choice that trades invariant enforcement for availability. For a shopping cart, losing a 'remove item' operation is less bad than making the cart unavailable during a partition — so an OR-Set is the right call. For inventory management, you cannot oversell, so you need coordination (2PC or Paxos-based locks). The insight is: identify which operations need invariant enforcement and which don't. Often you can use CRDTs for the 'soft state' (UI, notifications, counts) and consensus for the 'hard state' (financial records, inventory)."
