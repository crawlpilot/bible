# Trade-off: Strong vs Eventual Consistency

**Category**: HLD · Distributed Systems · Architecture Decision  
**FAANG interview trigger**: "What consistency model would you use for X?" / "How do you handle concurrent writes in a distributed system?" / "What happens when a network partition occurs?"

---

## Context

Consistency in distributed systems is not binary. There is a spectrum of consistency models, each with different guarantees about what a reader sees after a write. Choosing the right model requires understanding the use case's tolerance for stale data, the cost of coordination, and what "incorrect" behavior looks like to users.

This trade-off is rooted in the CAP theorem: in the presence of a network partition (P), a system must choose between Consistency (C) and Availability (A). In practice, partitions are rare but do occur, so the real question is: which direction do you fail?

---

## The Consistency Spectrum

From strongest to weakest:

| Model | Guarantee | Example |
|-------|-----------|---------|
| **Linearizability** (strong) | Read always returns the most recent write; operations appear instantaneous and atomic | Zookeeper, etcd, Spanner |
| **Sequential consistency** | All operations appear in the same order to all observers (not necessarily wall-clock order) | Older single-datacenter DB systems |
| **Causal consistency** | Causally related writes are seen in order; concurrent writes may be seen in any order | MongoDB multi-master, some Cassandra configs |
| **Read-your-writes** | A client always sees its own writes | PostgreSQL (same connection), DynamoDB (strong reads) |
| **Monotonic reads** | A client never sees data go backward in time | Often guaranteed within a session |
| **Eventual consistency** (weak) | Given no new writes, all replicas will eventually converge | Cassandra (ONE consistency), DynamoDB (eventual reads), DNS |

---

## Strong Consistency

**Definition**: After a write completes, any subsequent read from any node returns that write's value. No reader ever sees stale data.

**Implementation**: requires coordination between nodes before acknowledging a write. Common approaches:
- **Synchronous replication**: primary waits for all (or a quorum of) replicas to acknowledge before responding
- **Two-phase commit (2PC)**: coordinator gets votes from all participants before committing
- **Paxos/Raft consensus**: quorum agreement on each write (etcd, CockroachDB, Spanner)

**Latency cost of strong consistency**:
```
Multi-region strong consistency example:
  Write → replicate to EU (180ms RTT) → replicate to APAC (250ms RTT)
  Total write latency ≥ 250ms (must wait for slowest replica in a quorum)

Same-region strong consistency:
  Write → synchronous replica acknowledgment (2–10ms cross-AZ)
  Total write latency: 5–15ms — acceptable for most use cases
```

**When to choose strong consistency:**

1. **Financial transactions**: bank transfers, payment processing, ledger entries. Reading stale balance after a debit would show incorrect available funds.

2. **Inventory systems**: reserving the last unit of a product. Stale inventory reads lead to overselling (selling more units than exist).

3. **Authentication and authorization**: permission changes must be immediately visible. A user who has been de-provisioned must not be able to access resources via a stale read.

4. **Leader election and distributed coordination**: only one node should believe it is the leader. Zookeeper and etcd provide linearizable reads specifically for this use case.

5. **Configuration management**: a feature flag change from "10% rollout" to "0% rollout" (emergency disable) must be immediately visible to all servers.

**Real examples**: Google Spanner provides external consistency (equivalent to linearizability) across global datacenters via TrueTime. Stripe's payment system uses strong consistency for the core payment ledger.

---

## Eventual Consistency

**Definition**: Given no new writes, all replicas will eventually converge to the same value. A read may return stale data.

**Staleness window**: how long before replicas converge? In practice:
- Same datacenter: milliseconds to seconds
- Cross-datacenter: seconds to minutes
- DNS propagation: minutes to hours (TTL-dependent)

**Conflict resolution** (what happens when two nodes accept concurrent writes to the same key?):
- **Last Write Wins (LWW)**: the write with the higher timestamp wins. Simple, but loses the losing write entirely. Used by Cassandra (default), DynamoDB.
- **CRDT (Conflict-free Replicated Data Types)**: data structures that merge concurrent modifications without conflict. Counters (G-Counter), sets (G-Set), registers (LWW-Register). Used by Riak, Redis CRDT module.
- **Application-layer merge**: the application reads both versions and decides how to merge. Used by Amazon Shopping Cart (the "weird bag" problem — adding an item in two tabs shows both items after merge).
- **Version vectors**: track causality to distinguish concurrent writes from sequential writes. Used by Dynamo-style systems.

**When to choose eventual consistency:**

1. **Social media feeds**: if a user sees a post that was created 2 seconds ago vs. 5 seconds ago, the user experience is identical. Eventual consistency is invisible at this staleness window.

2. **Product catalog / content**: product descriptions, prices, images change infrequently. A 10-second staleness window is acceptable.

3. **Analytics and metrics**: page view counts, like counts, click-through rates. Approximate numbers within 1% are fine; strong consistency would make every counter increment a distributed transaction.

4. **User activity logs**: "User X clicked Y" — the order across shards doesn't matter for analytics.

5. **CDN and DNS**: cache-propagation delays are inherent. CDN invalidation is eventual by design.

6. **Shopping cart contents** (with care): the Amazon shopping cart is eventually consistent — concurrent adds from two devices converge without losing items. The trade-off is accepting the risk that a delete might not propagate before the next add.

---

## The PACELC Model (Extension of CAP)

CAP only addresses behavior during partitions. PACELC extends it:
- **P**: during a **P**artition, choose between **A**vailability and **C**onsistency (CAP)
- **EL**: **E**lse (no partition), choose between **L**atency and **C**onsistency

Most systems have different tradeoffs along both dimensions:

| System | Partition behavior | Normal operation |
|--------|-------------------|-----------------|
| Cassandra | PA (available, eventual) | EL (low latency, eventual) |
| DynamoDB (default) | PA | EL |
| DynamoDB (strong reads) | PC | EC |
| CockroachDB | PC | EC |
| Google Spanner | PC | EC |
| HBase | PC | EC |
| Zookeeper | PC | EC |

**The key insight**: even in the absence of partitions, you're trading consistency for latency. Synchronous replication to N replicas adds N-1 round trips to every write.

---

## Tunable Consistency (Cassandra Model)

Cassandra lets you choose consistency level per operation:

```
QUORUM read + QUORUM write → strong consistency (at the cost of latency)
ONE read + ANY write → maximum availability (high staleness risk)

Rule for strong consistency: read_consistency + write_consistency > replication_factor
Example: RF=3, QUORUM=2: 2+2=4 > 3 → linearizable reads
```

| Consistency Level | Nodes Required | Trade-off |
|------------------|---------------|----------|
| ANY | 1 (even hinted handoff) | Highest availability, can lose data |
| ONE | 1 | Fast, may be stale |
| QUORUM | (RF/2)+1 | Balanced — strong consistency |
| LOCAL_QUORUM | Quorum in local DC | Low latency, eventual cross-DC |
| ALL | All replicas | Slowest, highest consistency |

---

## Decision Framework

```
Does incorrect/stale data cause a financial or security consequence?
├── Yes → Strong consistency (Spanner, CockroachDB, Postgres, DynamoDB strong reads)
└── No → What is the acceptable staleness window?
        ├── Milliseconds → Strong or LOCAL_QUORUM in Cassandra
        ├── Seconds → Eventual with monitoring
        └── Minutes+ → Pure eventual (DNS, CDN, analytics)

Is the workload write-heavy across many nodes?
├── Yes → Eventual consistency (strong consistency's coordination cost is prohibitive)
└── No → Strong consistency may be affordable

Is the workload multi-region active-active?
├── Yes → Eventual (strong consistency across regions adds 100–300ms latency per write)
           Unless: Spanner/TrueTime (external consistency at 5–15ms cross-region latency overhead)
└── No → Strong consistency is practical
```

---

## Practical Patterns

### Read-Your-Writes Without Global Strong Consistency
Route a user's reads to the same replica that handled their writes. This gives read-your-writes consistency (the user sees their own changes) without requiring global coordination.

Implementation: sticky sessions to a replica, or write a "version token" to the client that the read path uses to route to an up-to-date replica.

### Eventual Consistency + Conflict Detection
Accept eventual consistency but detect and surface conflicts to users (Google Docs' "someone else is editing" message, Git merge conflicts). The conflict detection is a user-layer compensation for the lack of write-time coordination.

### Saga for Distributed Transactions
When you need consistency across multiple services but can't afford 2PC:
- Break the transaction into steps
- Each step publishes an event
- On failure, issue compensating transactions (reverse the completed steps)
- Consistency is eventual; atomicity is not guaranteed at an instant but converges

---

## FAANG Interview Callouts

**Demonstrate this thinking:**
- "For the payment ledger, I need strong consistency — a transfer from account A to B must be atomic and immediately visible. I'd use CockroachDB or Spanner for the financial data, accepting the higher write latency in exchange for linearizable reads."
- "For the activity feed, I'd use eventual consistency — DynamoDB with eventual reads. If a user sees a post 3 seconds after it was created, that's fine. This lets me scale to millions of writes per second without coordination overhead."
- "For inventory, I need strong consistency at the point of reservation — I can't oversell. But the product catalog (descriptions, images) can be eventually consistent — a 10-second staleness window is imperceptible to users."
- "For the leaderboard, I'd use Redis sorted sets — eventually consistent across replicas — with a note that leaderboard positions may be seconds behind. That's acceptable for a game leaderboard."

**Red flags:**
- "I'll use eventual consistency everywhere for performance" — this ignores use cases where stale reads cause real business problems
- "I'll use strong consistency everywhere for correctness" — this ignores the latency cost, especially in multi-region deployments
- Not mentioning PACELC (CAP is incomplete — the latency/consistency trade-off under normal operation is equally important)
- Conflating "eventual consistency" with "no data loss" — eventual consistency says nothing about durability, only about convergence time
