# Failure Detection and Recovery

## The Core Problem (Start Here)

You ping a server. No response in 1 second. Is the server dead? Or is the network to that server congested? Or is the server just busy with a garbage collection pause and will respond in 200ms? You cannot tell.

This is the core difficulty of failure detection in distributed systems. You have three bad options:

```
Too aggressive (short timeout = 500ms):
  Server doing GC pause (600ms) → declared DEAD → failover triggered
  → Unnecessary leader election → brief unavailability → GC finishes → two leaders!

Too conservative (long timeout = 60s):
  Server actually dies → system waits 60s before reacting
  → 60 seconds of unavailability (your SLA is 99.9% = 8.7 hours/year allowed)

Phi Accrual (adaptive):
  Model heartbeat inter-arrival statistically.
  Short GC pause: suspicion rises to φ=2, recovers when heartbeat arrives.
  True failure: φ climbs monotonically to 8 → declare dead.
  → Fewer false positives; faster true-positive detection.
```

Split-brain (two nodes both believe they are leader) is the worst-case consequence of a failure detection mistake: fencing tokens and STONITH exist specifically to make split-brain safe.

---

## The Fundamental Problem

You cannot reliably distinguish a slow node from a dead node. A message that hasn't arrived might be delayed, or the sender might be dead. This is the core impossibility at the heart of failure detection.

**FLP Impossibility (Fischer, Lynch, Paterson, 1985):** In an asynchronous system, there is no deterministic algorithm that can solve consensus in the presence of even a single process failure. Failure detection is therefore inherently probabilistic.

Every failure detector is a trade-off between:
- **Completeness:** Eventually, a failed node is detected as failed
- **Accuracy:** A live node is not incorrectly suspected
- **Detection time:** How quickly failures are detected

In practice, completeness and accuracy cannot both be perfect in an asynchronous system. All real failure detectors accept occasional false suspicions.

---

## 1. Heartbeat-Based Detection

### Basic Model

Each node sends periodic heartbeat messages to a monitor (or to all peers). If the monitor doesn't receive a heartbeat within a timeout window, it suspects the node has failed.

```
Node A ──── heartbeat (t=0) ────► Monitor
Node A ──── heartbeat (t=1s) ───► Monitor
Node A ──── heartbeat (t=2s) ───► Monitor
[Node A crashes]
[t = 2s + timeout] Monitor suspects Node A as failed
```

**Timeout selection:**
- Too short → false positives (GC pauses, network jitter cause false failures)
- Too long → slow detection, prolonged unavailability

Typical production timeouts:
- etcd: election timeout 500ms–1500ms (configurable)
- Kubernetes node eviction: pod-eviction-timeout default 5 minutes
- MySQL Orchestrator: detection_interval_seconds default 1s, timeout 5s
- ZooKeeper session timeout: 2–20s (client configurable)

### Cascading Timeouts

Under high load, nodes slow down — but are not dead. A too-short timeout causes healthy nodes to be evicted. Eviction causes load redistribution onto remaining nodes, which slow down further → cascade.

**Fix:** Adaptive timeouts; exponential backoff on reconnect; decouple "suspected" from "evicted."

### Heartbeat in Practice: etcd/Raft

Raft uses heartbeats as the mechanism for: (a) preventing elections (leader sends heartbeats to followers), and (b) detecting leader failure (followers time out when heartbeats stop). The election timeout is randomized (150–300ms) to avoid split votes.

---

## 2. Phi Accrual Failure Detector

### Motivation

Fixed-timeout heartbeats produce binary results: "up" or "down." In practice, network jitter causes heartbeats to arrive at slightly different intervals. A detector that models this variability can be much more accurate.

### The Algorithm

The Phi Accrual Failure Detector (Hayashibara et al., 2004; used in Cassandra, Akka) maintains a sliding window of inter-arrival times for heartbeats. It models this distribution as Gaussian and computes a suspicion level **φ (phi)** that scales continuously with how overdue a heartbeat is.

```
φ = -log₁₀(P_later(t))

where P_later(t) = probability that a heartbeat would arrive later than now,
given the historical inter-arrival distribution
```

**Interpretation:**
- φ = 1 → ~10% chance node is dead
- φ = 2 → ~1% chance it's alive
- φ = 5 → ~0.00001% chance it's alive
- φ = 8 → practically certain it's dead (Cassandra's default threshold)

```
φ over time for a live node:
  φ: 0.1  0.2  0.3  0.2  0.1  0.2  ...  (stable, heartbeats arriving)

φ over time when a node crashes:
  φ: 0.1  0.2  0.8  2.1  4.3  6.7  8.2 ← exceeds threshold → SUSPECTED
```

### Advantages over Fixed Timeout

| Scenario | Fixed timeout | Phi Accrual |
|----------|-------------|------------|
| Brief network jitter (50ms extra) | May trigger false positive | φ rises slightly, recovers |
| GC pause (500ms) | Timeout → false failure | φ rises, falls after heartbeat arrives |
| Node truly dead | Triggers after timeout | φ grows monotonically → declared dead |
| Slow but alive node | Binary: up or down | φ = mid-range → "suspected but not evicted" |

### Configuration (Cassandra)

```yaml
phi_convict_threshold: 8    # default; raise to reduce false positives in high-jitter networks
                             # lower to detect failures faster (risk: false positives)
```

---

## 3. SWIM Protocol (Scalable Weakly-consistent Infection-style Membership)

### The Problem with Centralized Heartbeats

In a 1000-node cluster, each node sending heartbeats to a central monitor creates O(N) load on the monitor. Receiving heartbeats from all N nodes also creates O(N) processing. Not scalable.

### SWIM Architecture

SWIM (Das, Gupta, Karp, 2002) distributes failure detection across all nodes using peer-to-peer probing. Each node randomly probes a small set of peers. If a probe fails, indirect probing through other nodes confirms before declaring failure.

**SWIM failure detection cycle (per node, every T seconds):**

```
1. SELECT random target node M
2. SEND ping to M
3. IF no ack within timeout:
     SELECT k random peers (k=3 typically)
     SEND ping-req(M) to each peer
     IF any peer ACKs (i.e., M is reachable via other path):
       M is alive (possible direct network issue)
     ELSE:
       DECLARE M as SUSPECTED
4. After suspicion timeout:
   If M hasn't refuted: DECLARE M DEAD
```

```
Direct probe:
  Node A ──── ping ────► Node M (no response)

Indirect probe (through B and C):
  Node A ──── ping-req(M) ────► Node B ──── ping ──► Node M
  Node A ──── ping-req(M) ────► Node C ──── ping ──► Node M
  
  If B or C gets a response from M: M is alive, issue was A→M path
  If neither: M is suspected dead
```

### State Dissemination: Infection-Style (Gossip)

SWIM combines failure detection with **infection-style dissemination**: when a node has new information (node death, join, etc.), it piggybacks this information on its regular probe messages. Every message spreads the news to the recipient. Information spreads like an epidemic — O(log N) rounds to reach all nodes.

**Convergence time:** O(log N) protocol rounds × T protocol period  
**Example:** 1000-node cluster, T=1s, k=3 → full convergence in ~10s

### SWIM vs Centralized Heartbeat

| Dimension | Centralized Heartbeat | SWIM |
|-----------|----------------------|------|
| Monitor load | O(N) | Distributed (O(1) per node) |
| Bandwidth | O(N) total | O(N) total (but distributed) |
| False positive rate | Higher (fixed timeout) | Lower (indirect probing) |
| Detection time | Fast (centralized) | O(log N) protocol rounds |
| Scalability | Poor | Excellent |
| Used by | Kubernetes (kubelet → API server) | Cassandra, Consul, Redis Cluster |

---

## 4. Split-Brain

### What It Is

A split-brain occurs when a network partition causes a cluster to divide into two groups, each of which believes it is the sole active partition and continues to accept writes. When the partition heals, both sides have made changes that conflict.

```
Before partition: Leader L1 with followers F1, F2, F3, F4

Network partition:
  Side A: L1, F1, F2  (minority: 3/5 nodes)
  Side B: F3, F4      (minority: 2/5 nodes)

  Side B elects a new leader L2 (if using a consensus-based system, this won't happen because 2/5 < majority)
  BUT: if using a heartbeat-only system with no quorum enforcement, both L1 and L2 may accept writes
```

In properly implemented consensus systems (Raft, Paxos), quorum enforcement prevents split-brain: only the majority partition can commit writes. The minority partition becomes unavailable.

**Split-brain is primarily a risk in:**
- Systems without quorum enforcement (MySQL with misconfigured MHA)
- Custom failover scripts without fencing
- Multiple applications sharing a resource without coordination

### Fencing Tokens

The safe solution to split-brain is **fencing tokens**: monotonically increasing numbers issued by the lock service when a leader is granted leadership. The storage system rejects writes from a client whose token is lower than the highest token it has seen.

```
Lock service:
  Leader A wins election → gets token 5
  Leader A crashes → detected
  Leader B wins new election → gets token 6
  Leader A recovers (thinks it's still leader, token 5)

  Leader B writes with token 6: storage accepts
  Leader A writes with token 5: storage REJECTS (5 < 6)
```

**Key requirement:** The storage/resource that receives writes must enforce fencing. The lock service alone is not sufficient — a zombie leader can still send writes if the storage doesn't check tokens.

*See also: `distributed-locking-and-coordination.md` for fencing token implementation.*

### STONITH (Shoot The Other Node In The Head)

In shared-storage clusters (SAN, NFS), split-brain on the storage layer causes data corruption. STONITH is the practice of forcibly killing (power-cycling, IPMI reset) the suspected old leader before the new leader takes over, ensuring only one node can write to shared storage.

**When used:** Traditional high-availability databases on shared storage (Oracle RAC, SQL Server FCI, older MySQL HA setups). Generally not needed in modern distributed databases that use quorum-based writes per node.

---

## 5. Cascading Failures

### Retry Storm (Thundering Herd)

A downstream service goes slow or fails. Upstream clients time out and retry. Retries increase load. More failures. More retries. Catastrophic amplification.

```
Service A → Service B (slowing)
  A times out after 500ms → retries
  100 clients × retry = 2x load on B
  B slows further → more timeouts → 4x load
  B falls over
  A's retry queue fills → A fails
```

**Mitigations:**
- **Exponential backoff with jitter:** Retry delay = min(cap, base × 2^attempt) + random(0, jitter)
- **Circuit breaker:** After N consecutive failures, stop retrying and return error immediately (fast fail)
- **Bulkhead isolation:** Separate thread pools/connections per downstream; one slow service can't exhaust all threads
- **Load shedding:** When queue depth exceeds threshold, drop new requests (500 > timeout)
- **Token bucket rate limiting:** Limit retry rate per client

### Bulkhead Pattern

Named after ship compartments: isolate failure domains so one failing component can't sink the ship.

```
WITHOUT bulkhead:
  All services share one connection pool (100 connections)
  Service B goes slow → all 100 connections occupied waiting for B
  Service A calls to C, D also blocked (no connections left)
  Entire system fails

WITH bulkhead:
  Service B: 30 connections (limit)
  Service C: 30 connections
  Service D: 30 connections
  Service B goes slow → only B's pool exhausted
  C and D connections unaffected
```

---

## 6. Recovery Patterns

### Crash Recovery (Fail-Stop Model)

After a crash, a node recovers by replaying its **write-ahead log (WAL)**:

```
Startup sequence:
  1. Read last checkpoint
  2. Replay WAL from checkpoint forward
  3. Re-apply committed transactions
  4. Rollback incomplete transactions
  5. Resume normal operation
```

*Cross-reference: `write-ahead-log-and-storage-internals.md`*

### Snapshot + Log Recovery

For systems with large state (Kafka consumers, Flink, stateful Raft followers):
1. Take periodic snapshots of state machine state
2. On recovery: load most recent snapshot
3. Replay log entries from snapshot's last included index forward

This bounds recovery time: replay only entries since last snapshot (not entire history).

### Raft Follower Catch-Up

When a Raft follower restarts after a long pause, it may be far behind the leader's log:
1. Leader sends recent log entries → if follower is only slightly behind, catches up via AppendEntries
2. If follower is very far behind (leader has already compacted those entries): leader sends a snapshot via InstallSnapshot RPC

### Byzantine Recovery

Byzantine faults are more severe than crash-stop: the failing node sends incorrect or malicious messages. Recovery requires:
- At least 3f+1 nodes to tolerate f Byzantine failures (vs. 2f+1 for crash-stop)
- PBFT or Tendermint-style view change protocols
- Not used in typical FAANG systems (used in blockchain, safety-critical systems)

---

## Failure Detection in Major Systems

| System | Detection Method | Detection Time | Notes |
|--------|-----------------|----------------|-------|
| Cassandra | Phi Accrual (gossip) | Seconds | phi_convict_threshold=8; gossip-based dissemination |
| etcd | Fixed heartbeat (Raft) | Election timeout (150–500ms) | Raft quorum; minority partition becomes unavailable |
| ZooKeeper | Session timeout | 2–20s (configurable) | Clients hold ephemeral nodes; ZAB protocol |
| Consul | SWIM + health checks | ~5s by default | Combines SWIM membership with HTTP/TCP health checks |
| Redis Cluster | SWIM gossip | ~15s default | cluster-node-timeout controls detection + failover |
| Kubernetes | Node lease + kubelet | 40s default (node-monitor-grace-period) | After 5min, pods evicted (pod-eviction-timeout) |
| MySQL (MHA) | Heartbeat script | ~30s | Script-based; STONITH via VIP removal |

---

## FAANG Interview Application

**When you'll be asked about this:**
- "How does Cassandra detect that a node has failed?"
- "What is split-brain and how do you prevent it?"
- "How does your system recover from a cascading failure?"
- "Walk me through what happens when the leader crashes in your distributed system"

**What they're evaluating:**
- Do you understand that failure detection is probabilistic, not perfect?
- Can you explain the trade-off between false positives and detection speed?
- Do you know the specific mechanisms used by real systems?
- Do you have practical mitigations for cascading failures (circuit breakers, bulkheads, backoff)?

**Principal-level signal:**
A senior engineer says "we use health checks to detect failures." A principal engineer says: "We use Consul's SWIM-based membership for failure detection, which gives us ~5 second detection time with a low false-positive rate. For the leader election layer, we use etcd with a 500ms election timeout — Raft's quorum enforcement prevents split-brain at the cost of availability during a partition, which we've accepted because consistency is critical for this service. For cascading failure protection, we've configured Hystrix circuit breakers with a 50ms timeout and bulkhead thread pools per downstream dependency, sized based on our capacity planning for 2x peak load. The three mechanisms are independent and protect different layers."
---

## Cross-References

- [gossip-protocols-and-epidemic-broadcast.md](./gossip-protocols-and-epidemic-broadcast.md) — SWIM protocol for cluster membership dissemination
- [distributed-locking-and-coordination.md](./distributed-locking-and-coordination.md) — fencing tokens and split-brain prevention in practice
- [write-ahead-log-and-storage-internals.md](./write-ahead-log-and-storage-internals.md) — WAL-based crash recovery (replay on restart)
- [raft-consensus.md](./raft-consensus.md) — Raft election timeout as failure detection mechanism; quorum prevents split-brain
- [multi-region-distribution.md](./multi-region-distribution.md) — region-level failure detection, RPO/RTO, and failover strategies