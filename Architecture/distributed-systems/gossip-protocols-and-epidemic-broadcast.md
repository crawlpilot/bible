# Gossip Protocols and Epidemic Broadcast

## The Core Idea

Gossip protocols spread information through a network the same way diseases spread through a population: each infected node infects a small number of others; those nodes infect others; eventually all nodes are infected. The key property: O(log N) rounds to reach all N nodes, with no central coordinator.

```
Round 1: Node A knows the update
  A → B (tells B)
  A → C (tells C)

Round 2: A, B, C know the update
  A → D, B → E, C → F

Round 3: A, B, C, D, E, F know
  ...

Rounds to full dissemination: log₂(N)
```

For a 1024-node cluster: ~10 rounds × protocol period (1s) = ~10 seconds to full convergence.

---

## Epidemic Dissemination Model

Based on the SIR model from epidemiology:

| State | Meaning |
|-------|---------|
| **S** Susceptible | Node doesn't have the information yet |
| **I** Infected | Node has the information and is spreading it |
| **R** Removed | Node has the information and has stopped spreading it (after fanout rounds) |

**Parameters:**
- **Fanout (k):** Number of nodes each infected node contacts per round (typically 3–5)
- **Protocol period (T):** How often gossip rounds execute (typically 1s)
- **Message lifetime:** How many rounds a node keeps "spreading" an update

**Convergence guarantee:** With fanout k and N nodes, probability that a given node has not received the message after r rounds is approximately:

```
P(not received) ≈ (1 - 1/N)^(k × r)
```

For N=1000, k=3, r=10: P(not received) ≈ (0.999)^30 ≈ 0.97% → 99%+ of nodes informed.

---

## Push, Pull, and Push-Pull Gossip

### Push Gossip
Infected nodes randomly select k peers and **push** their state to them.
- **Strength:** Fast early convergence (exponential spread)
- **Weakness:** Slow to reach the last few nodes; redundant messages near full convergence

### Pull Gossip
Each node periodically selects k peers and **pulls** their state.
- **Strength:** Efficient near convergence (only pulls what's missing)
- **Weakness:** Slow early propagation (nodes must poll)

### Push-Pull Gossip (Optimal)
1. Node A selects random peer B
2. A sends its state summary to B
3. B responds with updates A is missing AND requests what B is missing

**Best of both worlds:** Fast early convergence (push), efficient completion (pull).  
**Used by:** Cassandra (with digests), Consul memberlist, Redis Cluster

```
Push-Pull exchange:
A ─── {my_state_digest} ─────►B
A ◄── {updates_A_missing} ────B
A ─── {updates_B_missing} ────►B
```

---

## SWIM Protocol (Membership and Failure Detection)

SWIM (Scalable Weakly-consistent Infection-style Membership) combines failure detection with gossip-based dissemination. See `failure-detection-and-recovery.md` for the full failure detection algorithm. Here we focus on the membership dissemination aspect.

### State Machine for a Node

```
ALIVE ──────────────────────────────►
  │ suspected by peer                │ confirmed alive (refutation)
  ▼                                  │
SUSPECTED ────── timeout ──────►DEAD │
                                  │  │
                                  ▼  │
                               REMOVED from membership ◄──────────────
```

### Piggybacking on Probe Messages

SWIM's key efficiency: every probe message (ping, ping-req, ack) carries piggyback updates — state changes for other nodes. No extra messages needed for dissemination.

```
A pings B (normal SWIM probe):
  Message body: [ping] + [piggybacked: "Node C is SUSPECTED since T=100"]

B acks A:
  Message body: [ack] + [piggybacked: "Node D joined at T=110", "Node C refuted suspicion"]
```

Each update is propagated for `log(N)` rounds (tracked by a "piggyback counter"). After that, the update is dropped as it's likely spread to the whole cluster.

### SWIM Membership Guarantees

SWIM provides **weakly consistent** membership — all nodes will eventually agree on membership, but at any given moment, different nodes may have slightly different views.

**Not suitable for:** Strong consistency applications (distributed locks, leader election). Use ZooKeeper or etcd for those.  
**Suitable for:** Service discovery, cluster membership tracking, cache invalidation broadcast.

---

## Anti-Entropy Gossip

Anti-entropy is the process of comparing replica states and synchronizing differences. Cassandra uses gossip-driven anti-entropy for database repair.

### Merkle Tree-Based Anti-Entropy

Cassandra's repair process:

```
Node A and Node B both have Keyspace K, Table T, Token Range [0, 100]

Step 1: Build Merkle trees
  Node A: hash each row → hash of each subtree → root hash
  Node B: same

Step 2: Exchange root hashes via gossip
  A.root ≠ B.root → divergence exists

Step 3: Walk the trees to find divergence
  A sends subtree hash for [0,50] → B compares → match → skip left side
  A sends subtree hash for [50,100] → B compares → mismatch → go deeper
  ...
  Found: rows 73–75 differ

Step 4: Sync only the differing rows
```

*Cross-reference: `DSA/system-design-ds/merkle-tree.md` for Merkle tree mechanics.*

**Cassandra repair modes:**
- **Full repair:** Compare entire token range
- **Incremental repair:** Compare only data written since last repair (uses "repaired" metadata flag)
- **SubrangeRepair:** Repair a specific token range for targeted recovery

---

## Gossip for Cluster State Dissemination

Beyond failure detection, gossip is used to disseminate cluster-wide state:

### Cassandra: System Metadata via Gossip

Cassandra gossips:
- Node lifecycle state: NORMAL, JOINING, LEAVING, REMOVED
- Token assignments (which node owns which key range)
- Schema version (to detect schema mismatches)
- Node load (for load-aware read routing)

Each Cassandra node maintains a heartbeat state with version numbers. Nodes exchange heartbeat states and only pull updates where the remote version is higher.

### Consul: Memberlist

HashiCorp's `memberlist` library (used by Consul, Serf, Nomad) implements SWIM with extensions:

1. **Gossip period:** 200ms
2. **Indirect pings:** 3 indirect nodes
3. **Probe timeout:** 500ms direct, 500ms indirect
4. **Suspicion timeout:** Before declaring dead, holds suspect state for max(4ms × log(N+1), 0.5s)

Memberlist is also used for service health gossip — each node gossips the health status of services it's running.

### Redis Cluster: Gossip for Topology

Redis Cluster uses gossip to propagate cluster topology (slot assignments, node addresses, node failures). Every 100ms, each node sends `PING` messages to a random set of other nodes including:
- Current epoch (cluster-wide version)
- My IP/port/flags
- Gossip section: info about 3 random other nodes I know about

---

## Epidemic Broadcast Trees (EBT)

A more efficient approach for large-scale pub/sub: instead of random gossip, build a spanning tree for efficient broadcast, but fall back to gossip for redundancy.

**Lazy push + eager push:**
- **Eager push:** Send full message to tree children
- **Lazy push:** Send just a message ID (graft hint) to non-tree neighbors

If a non-tree neighbor doesn't receive the full message within a timeout, it sends a `GRAFT` message to request the full content — rebuilding the spanning tree around a failed link.

**Used by:** HyParView and Plumtree (academic), partially in Riak's data dissemination

---

## Gossip Limitations

| Limitation | Description | Mitigation |
|-----------|------------|-----------|
| Eventual consistency only | Nodes may temporarily have different views | Use consensus (Raft/ZooKeeper) for strong consistency needs |
| Message amplification | Each update sent to k peers × multiple rounds = bandwidth | Digest-based exchange; limit gossip to topology state, not data |
| False positives on failure | Network jitter can trigger SWIM suspicion | Phi Accrual threshold tuning; indirect probing |
| Slow convergence at tail | Last 1% of nodes may take many rounds | Increase fanout near convergence; periodic full sync |
| No causality enforcement | Updates may arrive out of order | Version vectors; causal tokens |

---

## When to Use Gossip vs. Consensus

| Use case | Use Gossip | Use Consensus (Raft/ZooKeeper) |
|----------|-----------|-------------------------------|
| Cluster membership | ✅ | ❌ (overkill) |
| Service health/discovery | ✅ | ✅ (etcd, Consul with Raft) |
| Configuration management | ❌ | ✅ (etcd) |
| Leader election | ❌ | ✅ (required) |
| Distributed locks | ❌ | ✅ (required) |
| Anti-entropy / repair | ✅ | ❌ |
| Metadata dissemination (read-mostly) | ✅ | ✅ (if strongly consistent reads needed) |
| Counter aggregation (approximate) | ✅ | ❌ |

---

## FAANG Interview Application

**When you'll be asked about this:**
- "How does Cassandra know when a node joins or leaves the ring?"
- "How does Consul propagate cluster membership information?"
- "How would you design a system to efficiently broadcast configuration changes to 10,000 services?"
- "What's the trade-off between gossip-based and consensus-based cluster state management?"

**What they're evaluating:**
- Do you understand why gossip scales (O(log N)) and what it sacrifices (consistency)?
- Can you explain the SWIM protocol end-to-end?
- Do you know which real systems use gossip and for what purpose?
- Can you articulate when gossip is appropriate vs. when you need consensus?

**Principal-level signal:**
A senior engineer says "Cassandra uses gossip for failure detection." A principal engineer explains: "Cassandra uses Phi Accrual for local failure detection (each node independently suspects peers based on heartbeat inter-arrival distribution) and SWIM for membership dissemination (infection-style propagation of join/leave/failure events). The gossip layer is eventually consistent — two nodes might have slightly different views of cluster membership at any instant, which is acceptable because Cassandra's consistency model is tunable and the coordinator re-routes to live nodes on error. If we needed strong membership consistency (e.g., for distributed locking), we'd use etcd's Raft-based consensus instead."

---

## Cross-References

- [failure-detection-and-recovery.md](./failure-detection-and-recovery.md) — Phi Accrual failure detector in detail; cascading failures; STONITH
- [replication-patterns.md](./replication-patterns.md) — Cassandra leaderless replication; anti-entropy repair process; Merkle trees
- [paxos-and-consensus-variants.md](./paxos-and-consensus-variants.md) — when to use consensus (leader election, locks) instead of gossip
- [raft-consensus.md](./raft-consensus.md) — alternative cluster membership approach using strong consensus (etcd, Consul KV)
