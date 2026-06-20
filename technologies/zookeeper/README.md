# Apache ZooKeeper — Overview & Decision Guide

**Type**: Distributed Coordination Service  
**CAP Position**: CP (Consistency + Partition Tolerance)  
**Consistency Model**: Linearizable writes; sequential consistency for reads  
**Data Model**: Hierarchical namespace of znodes (like a filesystem in RAM)  
**Replication Model**: Leader-based; all writes serialised through leader via ZAB  
**Origin**: Yahoo! Research (2006), open-sourced 2007, Apache top-level 2011

---

## What Is ZooKeeper?

Apache ZooKeeper was built at Yahoo! to solve a recurring problem: every distributed system they built needed the same small set of coordination primitives — locks, leader election, configuration propagation, group membership. Each team was reinventing these primitives badly. ZooKeeper extracted them into a single, reliable, dedicated service.

The core insight: **coordination problems are fundamentally different from data storage problems**. You need far stronger consistency guarantees (CP, not AP), far smaller data volumes (kilobytes, not terabytes), and well-understood primitives (watches, ephemeral nodes, sequential nodes) that composition into higher-level recipes.

ZooKeeper stores all its data in memory, replicates it to a quorum of nodes, and guarantees that all writes are totally ordered and durable before acknowledging them. This makes it fundamentally unsuitable for large data but ideal for the small, consistency-critical metadata that distributed systems depend on.

---

## Quick-Reference Card

| Property | Value |
|----------|-------|
| CAP | CP — prefers consistency and partition tolerance over availability |
| Consistency | Linearizable writes; sequential reads (reads may lag leader) |
| Data model | Hierarchical tree of znodes (max 1 MB per node by default) |
| Write path | Client → Leader → ZAB broadcast to quorum → ACK to client |
| Read path | Client → any server → local in-memory read (potentially stale) |
| Replication | Leader-based, ZAB (ZooKeeper Atomic Broadcast) protocol |
| Durability | Write log + periodic snapshots to disk; data primarily in RAM |
| Ensemble size | Always odd: 3 (tolerates 1 failure), 5 (tolerates 2), 7 (tolerates 3) |
| Watch semantics | One-time callback on znode change; must re-register after firing |
| Session semantics | Ephemeral nodes and watches tied to client session; deleted on disconnect |
| Throughput | ~10K–50K writes/sec; reads scale with ensemble size |
| Latency | Sub-millisecond reads; 1–10 ms writes (quorum round-trip) |

---

## Design Philosophy

ZooKeeper is designed around three core principles:

### 1. Wait-Free Data Objects over Blocking Primitives
ZooKeeper does not expose locks directly. Instead it exposes **wait-free operations** on a hierarchical namespace, and clients build locks, barriers, and elections themselves using these primitives. This prevents slow clients from blocking the ensemble and eliminates server-side deadlock.

### 2. FIFO Client Order + Linearizable Writes
All requests from a single client are executed in FIFO order. All write requests are linearizable across the entire ensemble. This gives a programmable guarantee: "if I observe a write, every subsequent read by any client observing the same session will see it."

### 3. Small Coordination Data, Not General Storage
Every design decision reinforces that ZooKeeper is for metadata, not data:
- Default max znode size: 1 MB (configurable but discouraged to raise)
- All data in RAM on every server — the entire dataset must fit in memory
- No secondary indexes, no queries, no scans — just path-based gets

---

## Decision Drivers: When to Choose ZooKeeper

**Choose ZooKeeper when ALL of the following are true:**

1. **You need distributed coordination primitives** — leader election, distributed locks, barriers, group membership, configuration management
2. **Strong consistency is required** — all participants must observe the same state in the same order
3. **Data volumes are tiny** — you are storing configuration and metadata, not application data (kilobytes to low megabytes total)
4. **Your stack already includes ZooKeeper** — Kafka, HBase, Hadoop, Storm all depend on it; adding another ensemble is free
5. **You need watch-driven reactivity** — clients need to be notified when coordination state changes, not poll

**The single most important question**: *Is your problem a coordination problem (consensus, locking, leader election, config propagation) or a data storage problem?* ZooKeeper solves the former definitively. For the latter, use any database.

---

## Use Cases

| Use Case | How ZooKeeper Solves It | Example |
|----------|------------------------|---------|
| **Leader election** | Ephemeral sequential nodes: the node with the lowest sequence number is leader; others watch the predecessor | Kafka controller election, HBase master election, Hadoop NameNode HA |
| **Distributed locks** | Create ephemeral sequential node; if you have lowest, you hold the lock; else watch the predecessor | Apache Curator `InterProcessMutex` |
| **Service registry / discovery** | Ephemeral nodes under `/services/name/`; each instance creates one at startup; deleted on crash | Pre-Kubernetes microservices, Dubbo RPC framework |
| **Configuration management** | Store config under a znode; all services watch it; on change, get callback and re-read | Kafka broker config, HBase region assignment |
| **Distributed barriers** | Create a znode; workers wait on it; when creator deletes it, all workers proceed | MapReduce job coordination |
| **Group membership** | Each member creates ephemeral znode in a group path; watch parent to detect arrivals/departures | Distributed cache cluster membership |
| **Sequence number generation** | Sequential znodes provide a globally ordered, monotonically increasing counter | Unique task ID generation |
| **Two-phase commit coordination** | Use znodes as transaction state machine; watchers advance the protocol | Distributed transaction coordinators |

---

## Anti-Patterns: When NOT to Use ZooKeeper

| Situation | Why ZooKeeper Fails | Better Alternative |
|-----------|--------------------|--------------------|
| **General key-value store** | Data must fit in RAM; 1 MB node limit; no scan/query | Redis, etcd, Consul KV |
| **High-throughput writes** | ~10–50K writes/sec ceiling; all serialised through leader | Redis, Kafka, Cassandra |
| **Large blobs or files** | Not designed for it — will exhaust heap | S3, HDFS, object storage |
| **New projects without ZK dependency** | etcd is simpler, better API, cloud-native | etcd, Consul |
| **Multi-datacenter active-active** | ZAB requires quorum; cross-DC latency kills write throughput | Consul (multi-DC), Raft-based systems |
| **Watching millions of nodes** | Watch registration is per-client per-node; at scale causes GC pressure | etcd range watches, Consul |
| **Replacing a message queue** | No pub-sub, no consumer groups | Kafka, RabbitMQ |
| **Schema-driven config** | No structured query, no types | Consul KV with Nomad/Vault, AWS AppConfig |

---

## Key Numbers (Production Scale)

| Metric | Typical Production | Notes |
|--------|--------------------|-------|
| Ensemble size | 3 or 5 nodes | 5 for high availability; 7 rarely needed |
| Write throughput | 10K–50K ops/sec | All go through leader; single bottleneck |
| Read throughput | 100K–500K ops/sec | Reads served locally by any follower |
| Read latency (local) | < 1 ms | In-memory, no disk I/O |
| Write latency (quorum) | 1–10 ms | Network round-trip to quorum |
| Leader election time | 200 ms–2 s | Depends on tick time and network |
| Max dataset size | 1–10 GB | Must fit in RAM on every node |
| Max clients | 60K–100K concurrent | Per-ensemble; observers help scale reads |
| Session timeout range | 2× tickTime minimum | Default tick = 2000 ms → min session = 4 s |

---

## File Map

| File | What's Inside |
|------|--------------|
| [01-architecture.md](01-architecture.md) | ZAB protocol, leader election, data model (znodes), watches, sessions |
| [02-read-write-path.md](02-read-write-path.md) | Write/read flow, epoch, ZXID, snapshot + transaction log, session lifecycle |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | CAP analysis, etcd vs Consul vs ZooKeeper comparison, decision flowchart |
| [04-tuning-guide.md](04-tuning-guide.md) | tickTime, syncLimit, JVM heap, snapshot policy, anti-patterns |
| [05-production-and-research.md](05-production-and-research.md) | Original paper, Kafka/HBase/Hadoop usage, KRaft migration, FAANG framing |

---

## FAANG Interview Callout (30-second version)

> "ZooKeeper is a CP coordination service — it gives you linearizable writes and watch-driven notifications at the cost of availability during leader election. The data model is a hierarchical tree of znodes stored entirely in RAM; clients build distributed primitives like locks and leader election on top of ephemeral sequential nodes. The ZAB protocol ensures all writes are totally ordered and replicated to a quorum before ACK. The key trade-off: ZooKeeper is great for coordination metadata — kilobytes of config, lock state, group membership — but terrible as a general KV store because everything must fit in memory and write throughput tops out around 50K/sec. For new systems I'd evaluate etcd first; for Kafka/HBase ecosystems, ZooKeeper is the right answer."
