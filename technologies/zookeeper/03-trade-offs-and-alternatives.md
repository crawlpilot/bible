# ZooKeeper — Trade-offs & Alternatives

## CAP / PACELC Position

### CAP: CP

ZooKeeper is a **CP system** — it chooses Consistency over Availability when a network partition occurs.

```
  Scenario: 5-node ensemble, network splits into [3] and [2]

  Partition [3]: has quorum → continues to accept writes
  Partition [2]: does NOT have quorum → refuses writes, may refuse reads (if sync required)

  Result: the [2]-node partition is UNAVAILABLE for writes.
  ZooKeeper never sacrifices consistency: no divergent state is possible.
```

### During Leader Election

ZooKeeper is **unavailable for writes** during leader election (typically 200 ms–2 s). This is a known, accepted trade-off. Any system depending on ZooKeeper for writes must handle this window.

```
  Impact on clients:
  - Writes are queued or rejected (KeeperException.ConnectionLossException)
  - Reads from followers continue if sync() is not required
  - Ephemeral nodes are NOT deleted during election (session timeout not triggered)
  - Sessions remain valid as long as reconnection happens within sessionTimeout
```

### PACELC: PC/EL

| Scenario | ZooKeeper Behaviour |
|----------|-------------------|
| **Partition (P)** | Chooses **C**onsistency — minority partition refuses writes |
| **No Partition (E)** | Chooses **L**atency optimisation for reads (local reads), **C**onsistency for writes (quorum) |

---

## Core ZooKeeper Trade-offs

### Trade-off 1: Linearizable Writes vs. Write Throughput

| Property | Detail |
|----------|--------|
| All writes serialised through leader | Theoretically ~10K–50K writes/sec maximum |
| Each write requires quorum disk fsync | 2× fsync + quorum network round-trip per write |
| No batching by default | Each client write is one ZAB broadcast |
| **Recommendation** | ZooKeeper is NOT for high-write workloads. If you need > 1K writes/sec sustained for application data, use a different system. ZooKeeper's write ceiling is fine for coordination metadata (config changes, lock acquisitions) which are naturally low-rate. |

### Trade-off 2: Read Scalability vs. Read Consistency

| Option | Consistency | Latency | How |
|--------|------------|---------|-----|
| Direct read from any server | Sequential (potentially stale) | < 1 ms | Default behaviour |
| `sync()` then read | Linearizable | 1–5 ms (+ leader round-trip) | Explicit sync before read |
| Read from leader only | Linearizable | 1–5 ms | Not directly supported; use sync() |

**Recommendation**: Default reads (no sync) are correct for the overwhelming majority of ZooKeeper use cases. Coordination recipes — leader election, locks — are designed to work correctly with sequential consistency. Only use sync() when the application semantics require read-your-writes across different sessions.

### Trade-off 3: Ensemble Size vs. Write Latency

| Ensemble | Failures Tolerated | Quorum Size | Write Latency Impact |
|----------|------------------|-------------|---------------------|
| 3 nodes | 1 | 2 | Fastest: 1 follower must ACK |
| 5 nodes | 2 | 3 | ~20% slower: 2 followers must ACK |
| 7 nodes | 3 | 4 | ~40% slower: 3 followers must ACK |
| 9 nodes | 4 | 5 | Rarely justified |

**Recommendation**: 3 nodes for most deployments (tolerates 1 failure, simple to operate). 5 nodes for high-availability requirements (tolerates planned maintenance + 1 unexpected failure). Never use even-numbered ensembles — they can't form a majority during even splits.

### Trade-off 4: Memory-Resident Data vs. Dataset Size

ZooKeeper loads the entire dataset into RAM on every node. This means:

- **Advantage**: sub-millisecond reads, no cache warming
- **Disadvantage**: dataset bounded by available heap per node
- **Practical limit**: 1–10 GB total data; beyond this, GC pressure causes watch latency spikes and session timeouts

**Recommendation**: Never use ZooKeeper for application data. If you're storing more than a few GB in ZooKeeper, the data model is wrong — move data to an appropriate store and keep only pointers/metadata in ZooKeeper.

### Trade-off 5: Watch One-Time Semantics vs. Complexity

Watches fire once and are removed. Clients must re-register after every event. This leads to:

- **Herd effect** risk if all clients watch the same high-change node
- **Race conditions** if client doesn't re-read and re-watch atomically
- **Complexity**: every watch handler must defensively handle "node gone" and "session expired"

**Recommendation**: Use Apache Curator's high-level recipes (`NodeCache`, `PathChildrenCache`, `TreeCache`) which manage watch re-registration, reconnection, and initialisation automatically. Never write raw ZooKeeper watch code in production.

---

## ZooKeeper vs. etcd

etcd is the primary modern alternative for new projects. Both are distributed coordination stores, but they differ significantly.

| Dimension | ZooKeeper | etcd |
|-----------|-----------|------|
| **Consensus protocol** | ZAB (ZooKeeper Atomic Broadcast) | Raft |
| **Data model** | Hierarchical tree (filesystem-like) | Flat key-value with range queries |
| **API** | Custom binary protocol + Java/C clients | gRPC + HTTP/JSON (REST-friendly) |
| **Watch semantics** | One-time, per-node | Persistent, range watches — watch a prefix |
| **Read consistency** | Sequential (potentially stale) by default | Linearizable by default (optionally serialised for speed) |
| **Authentication** | ACL-based (World, Auth, Digest, IP, SASL) | TLS client certs + RBAC (Kubernetes-style) |
| **Versioning** | Per-znode version, ZXID | Global revision number across all keys |
| **Transactions** | One atomic operation at a time | Multi-key transactions (`txn` with compare-and-swap) |
| **Lease (ephemeral equivalent)** | Ephemeral nodes via sessions | Leases (TTL-based); keys attached to lease |
| **Max value size** | 1 MB (configurable) | 1.5 MB (configurable) |
| **Typical write throughput** | 10K–50K writes/sec | 10K–100K writes/sec |
| **Operational model** | JVM-based, complex JVM tuning | Single Go binary, simple ops |
| **Kubernetes** | Not used | **Kubernetes backing store** |
| **Primary users** | Kafka (legacy), HBase, Hadoop, Dubbo | Kubernetes, CoreDNS, etcd-based service discovery |
| **Client library quality** | Raw API is complex; use Curator | Clean gRPC API; most languages have good clients |
| **Multi-tenancy** | Single namespace | Multiple namespaces via key prefix conventions |

### When to Choose etcd Over ZooKeeper

- **New project** with no existing ZooKeeper dependency
- **Kubernetes ecosystem** — etcd is already present
- **Range watches needed** — watch entire `/services/` prefix, not individual nodes
- **REST API required** — etcd's HTTP API is easier to integrate and debug
- **Simpler operations** — single Go binary vs. JVM tuning
- **Multi-key transactions** — etcd `txn` can check + set multiple keys atomically

### When to Stick With ZooKeeper

- **Kafka** — until KRaft is fully mature (Kafka 3.7+ no longer requires ZooKeeper for new deployments, but existing deployments are slow to migrate)
- **HBase / Hadoop** — deeply coupled to ZooKeeper; migration is non-trivial
- **Existing ZooKeeper investment** — if you already operate it, it works, and the team knows it
- **Hierarchical namespace is a genuine fit** — e.g., directory-tree-style config

---

## ZooKeeper vs. Consul

| Dimension | ZooKeeper | Consul |
|-----------|-----------|--------|
| **Primary use case** | Distributed coordination | Service discovery + health checking + KV |
| **Consensus** | ZAB | Raft (per-datacenter) |
| **Health checking** | None (ephemeral nodes approximate health) | First-class: HTTP, TCP, script, gRPC checks |
| **Multi-datacenter** | Difficult (cross-DC latency kills writes) | Native: separate Raft clusters per DC, gossip between DCs |
| **Service mesh** | Not applicable | Consul Connect (mTLS sidecar proxy) |
| **DNS interface** | No | Yes — Consul has a built-in DNS server for service discovery |
| **UI** | None | Web UI for services, health, and KV |
| **ACL model** | ZooKeeper ACLs (complex) | Token-based RBAC (simpler) |

### When to Choose Consul Over ZooKeeper

- **Service discovery with health checks** — Consul's health check system is far superior; ZooKeeper's ephemeral node approximation has a lag equal to session timeout
- **Multi-datacenter** — Consul is designed for it; ZooKeeper cross-DC deployments are operationally painful
- **HashiCorp ecosystem** — if you use Vault, Nomad, Terraform, Consul integrates naturally
- **DNS-based discovery** — services that resolve peers via DNS benefit from Consul's DNS interface

---

## ZooKeeper vs. Redis (Redlock)

Redis is sometimes used for distributed locking via the Redlock algorithm. This comparison is important to articulate clearly in interviews.

| Dimension | ZooKeeper | Redis Redlock |
|-----------|-----------|---------------|
| **Consistency model** | CP — linearizable writes | Probabilistic — relies on timing assumptions |
| **Correctness under failure** | Correct: quorum write, ZAB total order | **Disputed**: Martin Kleppmann showed Redlock is unsafe under certain clock skew and GC pause scenarios |
| **Session-based lock expiry** | Automatic via ephemeral nodes | TTL-based (requires careful setting) |
| **Write throughput** | ~50K/sec | ~100K–1M/sec |
| **Operational simplicity** | Complex (JVM, ensemble) | Simple (Redis is widely deployed) |

**Recommendation**: **Never use Redlock for correctness-critical distributed locking** (financial transactions, inventory). Use ZooKeeper or etcd. Redis + Redlock is acceptable for best-effort locking where incorrect lock acquisition causes degraded performance but not data corruption.

> Martin Kleppmann's 2016 analysis: "How to do distributed locking" — concludes Redlock is not safe because it relies on bounded clock drift which is not guaranteed in real systems.

---

## Decision Flowchart

```
Need distributed coordination?
│
├─ Yes: What type?
│   │
│   ├─ Leader election / distributed locks / barriers
│   │   │
│   │   ├─ Already using Kafka/HBase/Hadoop?
│   │   │   ├─ Yes → ZooKeeper (it's already there, Curator for recipes)
│   │   │   └─ No  → etcd (simpler ops, better API, active development)
│   │   │
│   ├─ Service discovery with health checks?
│   │   └─ Consul (purpose-built, DNS interface, multi-DC)
│   │
│   ├─ Kubernetes ecosystem?
│   │   └─ etcd (already present in every cluster)
│   │
│   └─ Config management only, tiny scale?
│       └─ etcd or even a database (PostgreSQL LISTEN/NOTIFY)
│
└─ No: Rethink the problem
    ├─ High-throughput KV store → Redis, DynamoDB
    ├─ Config store with history → AWS AppConfig, Vault
    └─ Message queue → Kafka, RabbitMQ
```

---

## Summary Trade-off Table

| Concern | ZooKeeper | etcd | Consul |
|---------|-----------|------|--------|
| Coordination correctness | Excellent | Excellent | Good |
| Write throughput | Low (50K/sec) | Medium (100K/sec) | Medium |
| Read throughput | High (local reads) | High | High |
| Operational complexity | High (JVM) | Low (Go binary) | Medium |
| Multi-datacenter | Poor | Moderate | Excellent |
| Service health checking | No | No | Yes |
| Modern API (gRPC/REST) | No | Yes | Yes |
| Kubernetes integration | No | Yes (native) | Yes (plugin) |
| Best for legacy Hadoop/Kafka | Yes | No | No |
| Best for new projects | Only if Kafka/HBase | Yes | Yes (if service mesh needed) |

---

## FAANG Interview Callout

> "ZooKeeper vs. etcd is the most common comparison question. Both are CP coordination stores using different consensus protocols — ZAB vs. Raft. The practical differences are: etcd has persistent range watches (watch a key prefix, not individual keys), a REST/gRPC API, simpler operations (single Go binary), and linearizable reads by default. ZooKeeper has hierarchical namespace, richer ACLs, and is the right choice if your stack already runs Kafka, HBase, or Hadoop. For new greenfield projects I always recommend etcd unless there's a compelling reason for ZooKeeper. The Redlock vs. ZooKeeper question is a trap — Redlock is probabilistically unsafe under GC pauses and clock skew; use ZooKeeper or etcd ephemeral nodes for correctness-critical distributed locks."
