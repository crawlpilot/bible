# ZooKeeper — Production & Research

## Founding Research Paper

**"ZooKeeper: Wait-free coordination for Internet-scale systems"**  
Patrick Hunt, Mahadev Konar, Flavio Paiva Junqueira, Benjamin Reed  
Yahoo! Research — USENIX ATC 2010

### Core Thesis

The paper argues that existing distributed coordination approaches are flawed:
1. **Blocking primitives** (lock services like Chubby): a slow or failed client blocks the entire service
2. **Point solutions**: each distributed system reimplements the same coordination logic (leader election, config, membership) incorrectly and repeatedly

ZooKeeper's answer: expose **wait-free data objects** (znodes with watches) and let clients compose coordination primitives. The server never blocks waiting for a client; it just maintains state and delivers notifications.

### Key Claims and Their Validity

| Claim | Validity at Time | Reality Today |
|-------|----------------|--------------|
| "Wait-free coordination" is better than blocking locks | Confirmed — server stays responsive even when clients crash | Validated by ~15 years of production use |
| FIFO client ordering + linearizable writes is the right consistency model | Confirmed — sufficient for all coordination recipes | Still the model used in etcd/Consul |
| The hierarchical namespace scales to Internet workloads | Partially — works for coordination metadata; fails for large datasets | Known limitation; addressable by design discipline |
| 10,000 read requests/sec per server achievable | Conservative — modern hardware achieves 100K+/sec | Hardware improvements exceeded paper's numbers |

### What the Paper Introduced That Became Standard

1. **Ephemeral nodes** — tied to client sessions, auto-cleaned on crash — replicated in etcd leases, Consul sessions
2. **Sequential nodes with monotonic suffix** — the basis of fair distributed locks and leader election
3. **Watch-notify semantics** — edge-triggered, one-time callbacks — replicated everywhere
4. **The herd effect problem** and the chained-predecessor solution for locks/election

---

## Real-World Production Usage

### Apache Kafka (Original Architecture)

ZooKeeper was central to Kafka's original design (pre-KRaft):

```
Kafka's ZooKeeper usage (pre-3.0):

/kafka/
├── brokers/
│   ├── ids/
│   │   ├── 0   ← ephemeral: broker 0 is alive (deleted on broker crash)
│   │   └── 1   ← ephemeral: broker 1 alive
│   └── topics/
│       └── my-topic/
│           └── partitions/
│               └── 0/
│                   └── state → {"leader": 1, "isr": [1, 0]}
├── controller  ← ephemeral: which broker is the Kafka controller
│                 All brokers race to create this on startup/leader loss
└── config/     ← topic configs, client quotas

Kafka controller election flow:
  - All brokers watch /kafka/controller
  - On broker startup: try to create /kafka/controller (ephemeral)
  - First to succeed becomes controller
  - Others watch and race again when /kafka/controller is deleted
```

**Scale**: Large Kafka deployments (LinkedIn, Netflix) operated 1000+ brokers against a single ZooKeeper ensemble. This was a known bottleneck — ZooKeeper watch storms on broker loss.

**KRaft (Kafka Raft Metadata)**: Starting Kafka 3.3 (KIP-833), ZooKeeper is deprecated. Kafka 4.0 removed ZooKeeper support entirely. KRaft embeds Raft consensus directly in Kafka broker/controller nodes, eliminating the ZooKeeper dependency.

> **Interview framing**: "Kafka's migration away from ZooKeeper (KRaft) is the canonical example of why purpose-built consensus (Raft embedded in the application) often wins over a separate coordination service at scale. ZooKeeper created an operational dependency, a write throughput bottleneck on the controller path, and a watch storm problem during mass broker failures."

### Apache HBase

HBase uses ZooKeeper as its coordination backbone:

```
HBase's ZooKeeper usage:

/hbase/
├── master          ← ephemeral: active HMaster host
│                     Hot-standby masters watch this; take over on deletion
├── backup-masters/ ← ephemeral: list of standby masters
├── rs/             ← ephemeral: one node per live RegionServer
│                     HMaster watches to detect RS crashes
├── meta-region-server ← which RS hosts the hbase:meta table
├── table/          ← table state (ENABLED, DISABLED, DISABLING...)
└── region-in-transition/ ← transient state during region moves
```

**Why HBase needs ZooKeeper deeply**: HBase's HDFS-backed design requires distributed consensus to elect an HMaster, track RegionServer liveness, and coordinate region assignments. The cost: every HBase deployment requires a separate ZooKeeper ensemble (or shares one with Hadoop).

**Scale**: Uber ran HBase clusters with 200+ RegionServers against a 5-node ZooKeeper ensemble. The key lesson: ZooKeeper is highly robust when used as intended (coordination metadata), but the watch storm from losing 50+ RegionServers simultaneously can cause ZooKeeper overload.

### Apache Hadoop (HDFS HA)

HDFS High Availability uses ZooKeeper for NameNode failover:

```
HDFS NameNode HA:
  - Active NameNode holds ephemeral /hadoop-ha/nameservice/ActiveStandbyElectorLock
  - Standby NameNode watches that path
  - On lock deletion (active NN crash), standby races to acquire lock
  - ZKFC (ZooKeeper Failover Controller) process manages this election

ZKFailoverController flow:
  1. ZKFC on Active NN: write health status to ZK periodically
  2. ZKFC on Standby NN: watch Active's health node
  3. Active NN or ZKFC crashes → session expires → health node deleted
  4. Standby ZKFC detects deletion → attempts ZK election → wins → calls NN.transitionToActive()
  5. Fencing: ZKFC attempts to SSH kill old active before promoting standby (prevents split-brain writes to HDFS)
```

**Failover time**: 30–60 seconds end-to-end. The ZooKeeper session timeout (30 s) dominates — until the session expires, the old NameNode's ephemeral node persists and the standby doesn't promote.

### Dubbo (Chinese FAANG Equivalent: Alibaba)

Dubbo, Alibaba's RPC framework, uses ZooKeeper as its default service registry:

```
Dubbo service registration:
  /dubbo/
  └── com.example.PaymentService/
      ├── providers/
      │   ├── dubbo://10.0.1.5:20880/...  ← ephemeral: instance alive
      │   └── dubbo://10.0.1.6:20880/...
      └── consumers/
          └── consumer://10.0.2.1/...     ← ephemeral: consumer registered

Consumer workflow:
  1. Subscribe to /dubbo/com.example.PaymentService/providers/
  2. Gets list of all provider URLs
  3. Sets watch; receives notification on any provider start/stop
  4. Maintains local list for load balancing
```

**Scale at Alibaba**: 100,000+ ZooKeeper-registered services. At this scale, ZooKeeper watch storms during rolling deployments became a problem — 10,000 nodes changing simultaneously causes all watching consumers to fire simultaneously. Alibaba developed Nacos as a replacement.

---

## Lessons From Production Incidents

### Incident 1: The Watch Storm (LinkedIn, ~2012)

**Context**: Kafka cluster with 100 brokers. One broker crashed.  
**Expected**: ZooKeeper fires watch on /kafka/brokers/ids to Kafka controller.  
**Actual**: Watch fired to ALL clients watching /kafka/brokers/ids — 99 other brokers. Each immediately re-read and re-watched. ZooKeeper ensemble was hit with 99 simultaneous getChildren calls + watch registrations in a burst.  
**Impact**: ZooKeeper latency spiked, triggered Kafka session timeouts, triggered more broker session expirations, cascaded into a partial cluster outage.

**Lesson**: Watch storms are a real production failure mode. Mitigation: use Observers to scale read capacity; architect clients to absorb bursts with exponential backoff on reconnect; or migrate to etcd range watches (all watchers share one server-side watch object, not N individual watches).

### Incident 2: The JVM Full GC Kill (Uber, ~2016)

**Context**: 5-node ZooKeeper ensemble backing HBase. One node got a JVM full GC pause of 8 seconds (heap too large, no G1GC tuning).  
**Expected**: Followers detect pause via heartbeat, move on.  
**Actual**: 8-second GC pause → the paused node missed quorum heartbeats → leader declared it dead → leader election started → during 2-second election, ensemble was unavailable → HBase session timeouts → region server evictions → HBase partially unavailable.

**Lesson**: GC pauses > minSessionTimeout cascade into availability events. Fix: G1GC with aggressive MaxGCPauseMillis, Xms=Xmx, heap ≤ 8 GB per node, dataset < 50% of heap.

### Incident 3: Disk Full / Transaction Log Explosion

**Context**: ZooKeeper ensemble without autopurge. High write rate to Kafka's ZooKeeper namespace (frequent ISR changes).  
**Expected**: Transaction logs roll and old ones are cleaned.  
**Actual**: Transaction logs accumulated over months. `dataLogDir` disk filled. ZooKeeper could no longer fsync transaction log → writes failed → Kafka controller lost ZooKeeper connection → Kafka producer/consumer disruption.

**Lesson**: Always configure `autopurge.purgeInterval` and monitor `dataLogDir` disk usage. Set an alert at 70% disk capacity. This is the most common "boring" ZooKeeper failure mode.

---

## ZooKeeper Migration: What Companies Did Next

| Company | What They Had | What They Moved To | Why |
|---------|--------------|-------------------|-----|
| **Kafka** (community) | ZooKeeper for all metadata | KRaft (Raft in Kafka) | Eliminate external dependency, scale metadata writes |
| **Alibaba / Taobao** | ZooKeeper for service discovery | Nacos | ZK watch storms at 100K+ services; Nacos has health checks + push model |
| **Twitter** | ZooKeeper for various coordination | etcd + Consul | Operational simplicity; better tooling |
| **HashiCorp ecosystem** | Consul (ZK alternative) | Consul | Consul native — service mesh + health checks |
| **Kubernetes** | etcd (never used ZK) | etcd | Kubernetes uses etcd natively; ZK not part of cloud-native stack |

---

## FAANG Interview Framing

### System Design Scenarios Where ZooKeeper Appears

**Scenario 1: Design a Distributed Job Scheduler**
> "I'd use ZooKeeper for master election among scheduler nodes. Each scheduler creates an ephemeral sequential node under /scheduler/election/. The lowest sequence number is the active scheduler. The active scheduler watches for job submission znodes; on watch fire, it claims the job by doing a versioned setData (CAS). ZooKeeper's linearizable writes ensure exactly-one claim even under concurrent scheduler nodes."

**Scenario 2: Design a Distributed Database with Leader-Follower Replication**
> "For leader election I'd use ZooKeeper's ephemeral sequential node pattern. The leader creates /db/leader with its address. All replicas watch it. On leader crash, session expires, replicas race to create /db/leader — first wins. ZooKeeper guarantees at most one node can create the same path, so there's no split-brain in the election itself. I'd set session timeout to 30 seconds and make sure the fencing mechanism (STONITH or write fencing token) fires before the new leader accepts writes."

**Scenario 3: Design Kafka (or explain why Kafka needed ZooKeeper)**
> "Kafka needed ZooKeeper for three things: broker liveness (ephemeral nodes), controller election (who assigns partitions to brokers), and topic metadata storage. The problem at scale: every broker watches every other broker's status — O(N²) watches for an N-broker cluster. A single broker failure triggers N-1 simultaneous watch callbacks. This is why the community built KRaft — embedding consensus in Kafka itself means no external dependency and eliminates the watch fan-out problem."

### Common Interview Questions and Strong Answers

**Q: Is ZooKeeper consistent?**
> "Writes are linearizable — totally ordered across the ensemble. Reads are sequentially consistent — any server serves them locally, so you may see a slightly stale state. For reads requiring linearizability, call sync() before getData(). The consistency model is sufficient for all its intended use cases — coordination metadata doesn't change faster than you can catch up."

**Q: How does ZooKeeper prevent split-brain?**
> "By requiring a strict majority quorum for every write. With N=5, you need 3 nodes to agree. If the network splits into [3] and [2], only the majority partition can commit writes. The minority partition becomes read-only or unavailable. There's no way for both sides to commit conflicting writes simultaneously because neither side of a [2]/[2] split has majority — and odd ensemble sizes ensure a majority always exists in exactly one partition."

**Q: What's wrong with using ZooKeeper for service discovery at 10K+ services?**
> "Watch storms. With 10,000 services each registering an ephemeral node, any rolling deployment changes thousands of nodes simultaneously. If 1,000 services use ZooKeeper watchers to discover each other, you get 1,000 × (services changed) simultaneous watch events plus getChildren calls to re-read the list. The ZooKeeper ensemble, optimised for coordination metadata with low change rates, gets overwhelmed. The right answer at that scale is a dedicated service discovery system like Consul (push-based health checking, not watch-based) or a DNS-based discovery system."

---

## FAANG Interview Callout (Full Version)

> "ZooKeeper is a CP distributed coordination service built on the ZAB consensus protocol — a leader-based total-order broadcast that predates Raft. Its core primitives (ephemeral nodes auto-deleted on session expiry, sequential nodes with monotonic suffix, one-shot watches) are sufficient to implement any distributed coordination recipe: leader election, distributed locks, barriers, service discovery, config propagation. The production track record is excellent — Kafka, HBase, Hadoop, and Dubbo have run it at massive scale for a decade. The failure modes are well-understood: GC pause cascades, watch storms on mass node changes, and disk exhaustion from unmanaged transaction logs. For new projects, etcd is the better default — simpler operations, persistent range watches, linearizable reads, and a REST API. ZooKeeper remains the right answer when you're already running Kafka or HBase, or when the existing team has deep ZooKeeper expertise. The most important architectural lesson from ZooKeeper's history: coordination is a fundamentally different problem from data storage; keep your coordination metadata tiny, your ensemble small, and your client library high-level (Apache Curator, not raw ZK API)."
