# Kafka — Architecture

## Origins: The Commit Log as Universal Integration Primitive

Kafka was designed at LinkedIn to replace a sprawling O(N²) web of point-to-point data pipelines. The foundational design decision was to model data as a **durable, ordered, append-only log** — a concept Jay Kreps later formalized in "The Log: What every software engineer should know about real-time data's unifying abstraction" (2013).

| Source Influence | Contribution to Kafka |
|-----------------|----------------------|
| **Unix file system** | Sequential disk writes are fast (saturate disk bandwidth); random writes are slow |
| **Database commit log** | WAL as the source of truth; everything else is derived |
| **Amazon Dynamo** | Distributed, fault-tolerant, horizontal scaling |
| **LinkedIn's internal MQ** | Battle-tested producer/consumer semantics at scale |

The core realization: if you persist all events in a sequential log, **consumers become stateless cursors** — they just track an offset. The broker doesn't need to track which consumers have received what; it only tracks log positions.

---

## Cluster Topology

```
  Producers                   Kafka Cluster                    Consumers

  Service A ──┐          ┌─────────────────────┐         ┌── Analytics (Flink)
              │          │  Broker 1            │         │
  Service B ──┼─────────►│  Broker 2 (leader)  ├─────────┼── Search Index (ES)
              │          │  Broker 3            │         │
  Service C ──┘          └─────────────────────┘         └── ML Feature Store

              ▲                    ▲
              │                    │
        ZooKeeper / KRaft   (cluster coordination:
                             broker registration,
                             topic metadata,
                             leader election)
```

A Kafka cluster consists of:
- **Brokers**: servers that store log data and serve producers/consumers
- **ZooKeeper** (legacy) or **KRaft** (Kafka 3.3+): metadata and leader election
- **Topics**: logical named streams, each partitioned across brokers
- **Producers**: write records to topics
- **Consumers**: read records from topics, organised into consumer groups

---

## Topics and Partitions

A **topic** is a named stream of records. It is split into **partitions** for parallel processing and horizontal scaling.

```
Topic: "order-events"  (6 partitions, RF=3, 3 brokers)

  Partition 0  [msg0 | msg3 | msg6 | msg9 | ...]   → Leader: Broker 1
  Partition 1  [msg1 | msg4 | msg7 | msg10 | ...]  → Leader: Broker 2
  Partition 2  [msg2 | msg5 | msg8 | msg11 | ...]  → Leader: Broker 3
  Partition 3  [msg12| msg15| ...]                 → Leader: Broker 1
  Partition 4  [msg13| msg16| ...]                 → Leader: Broker 2
  Partition 5  [msg14| msg17| ...]                 → Leader: Broker 3

  Each partition has 3 replicas spread across all 3 brokers.
  Each broker is leader for 2 partitions.
```

### Partition Key Routing

When a producer sends a record with a **partition key**, Kafka hashes it to select the partition:

```
partition = hash(key) % numPartitions
```

- Same key → same partition → **ordered delivery per key** (e.g., all events for `orderId=42` land in the same partition)
- No key → round-robin across partitions (maximises throughput; no ordering guarantee)

**Critical design choice**: The partition key determines both load distribution and ordering guarantee. Common choices:
- `userId` — all events for a user are ordered
- `orderId` — all events for an order are ordered
- `tenantId` — all events for a tenant are co-located (careful: hot partition risk if a single tenant is very large)

### Partition Count Sizing

| Consideration | Rule of Thumb |
|---------------|---------------|
| Write throughput | `numPartitions = desiredThroughput / throughputPerPartition` (typically 10–100 MB/s per partition) |
| Consumer parallelism | Max consumers in a group = numPartitions (extra consumers are idle) |
| Rebalance cost | More partitions → slower rebalance; don't over-partition |
| Recommended starting point | 10–50 partitions for most topics; 100+ for highest-throughput topics |

**You cannot reduce partition count** without recreating the topic — plan conservatively but generously.

---

## Replication: Leader-Follower + ISR

Every partition has one **leader** replica and N-1 **follower** replicas. All reads and writes go to the leader. Followers passively replicate by fetching from the leader.

```
Partition 0, RF=3:

  Broker 1 (Leader)  ──writes──►  log: [0, 1, 2, 3, 4]   ← producer writes here
       │
       │ replicate (follower fetch)
       ▼
  Broker 2 (Follower)             log: [0, 1, 2, 3, 4]   ← keeps up → in ISR
  Broker 3 (Follower)             log: [0, 1, 2, 3]      ← lagging   → removed from ISR
```

### In-Sync Replica (ISR)

The **ISR** is the set of replicas sufficiently caught up to the leader (within `replica.lag.time.max.ms`, default 30s). Only ISR members are eligible to be elected leader on failure.

| Config | Effect |
|--------|--------|
| `acks=1` | Leader acknowledges immediately — risk of data loss if leader dies before followers replicate |
| `acks=all` (or `-1`) | Leader waits for ALL ISR replicas to acknowledge — no data loss if any ISR member survives |
| `min.insync.replicas=2` | At least 2 replicas must be in ISR for the leader to accept writes — prevents silent data loss when only 1 replica is alive |

**Production recommendation**: `acks=all` + `min.insync.replicas=2` with RF=3. This tolerates one broker failure while guaranteeing durability.

### Leader Election on Failure

When a leader broker dies:
1. ZooKeeper/KRaft detects the failure
2. The controller broker selects a new leader from the ISR
3. All producers and consumers are notified of the new leader via metadata fetch
4. Recovery is complete in seconds (typically 5–30s depending on partition count)

If ISR has only 1 replica and it dies: **unclean leader election** — a lagging replica can be elected if `unclean.leader.election.enable=true` (default: false). This risks data loss but restores availability. For financial or audit data: keep this false.

---

## Consumer Groups

A **consumer group** is a set of consumers that collectively read a topic. Each partition is assigned to exactly one consumer in the group at a time.

```
Topic: "order-events" (6 partitions)

Consumer Group: "analytics-service"
  Consumer A → Partitions 0, 1
  Consumer B → Partitions 2, 3
  Consumer C → Partitions 4, 5

Consumer Group: "search-indexer"       ← independent group, reads same topic from its own offset
  Consumer X → Partitions 0, 1, 2
  Consumer Y → Partitions 3, 4, 5
```

**Key properties**:
- **Parallelism ceiling**: max consumers in a group = number of partitions. A 6-partition topic supports at most 6 concurrent consumers. Extra consumers sit idle.
- **Fault tolerance**: if a consumer dies, its partitions are reassigned to surviving consumers (rebalance)
- **Independent progress**: each consumer group maintains its own committed offsets — one group being slow doesn't affect another
- **Scale-out**: add more consumers (up to partition count) to increase throughput

### Offset Management

Consumers commit their progress to the `__consumer_offsets` internal topic (a special Kafka topic). The committed offset is the next record to be fetched, not the last processed.

```
Partition 0 log: [0] [1] [2] [3] [4] [5] ...
                              ▲
                       committed offset=3
                       (consumer will next fetch record at offset 3)
```

**enable.auto.commit=true** (default): offsets committed automatically every `auto.commit.interval.ms` (5s). Risk: if the consumer crashes between auto-commit intervals, records are reprocessed (at-least-once).

**enable.auto.commit=false**: application commits offset explicitly after processing. Enables exactly-once semantics when combined with idempotent producers.

---

## ZooKeeper vs KRaft

### ZooKeeper Mode (legacy, Kafka < 3.3)

```
Kafka Cluster                    ZooKeeper Ensemble
  Broker 1  ──────────────────►  ZK Node 1
  Broker 2  ──────────────────►  ZK Node 2 (leader)
  Broker 3  ──────────────────►  ZK Node 3
  Controller Broker
  (elected from Kafka brokers)

ZooKeeper stores: broker registrations, topic/partition metadata, ISR lists, consumer group offsets (legacy), ACLs
```

**Problems with ZooKeeper mode**:
- Separate operational system to manage (5-node ZK ensemble in production)
- Controller bottleneck — all metadata changes go through a single controller broker
- Hard partition count ceiling (~200K partitions per cluster) due to ZK watch limits
- Long recovery on leader election when ZK holds large numbers of ephemeral nodes

### KRaft Mode (Kafka 3.3+ default)

```
Kafka Cluster (KRaft)
  Broker 1 (combined broker + voter)
  Broker 2 (combined broker + voter)
  Broker 3 (combined broker + voter, active controller)

  Metadata stored in internal __cluster_metadata topic (Raft log)
  No external dependency
```

**Benefits of KRaft**:
- Eliminates ZooKeeper operational overhead
- Metadata stored in Kafka itself (Raft consensus on `__cluster_metadata`)
- Scales to millions of partitions per cluster
- Controller failover in seconds (was minutes in ZK mode for large clusters)
- Simplifies deployment: single artifact, single config

**Migration**: Kafka 3.3+ supports KRaft in production. Kafka 4.0 removes ZooKeeper support entirely.

---

## Log Segments and Retention

Each partition is stored as a series of **log segments** on disk:

```
Partition 0 on disk:
  /kafka-logs/order-events-0/
    00000000000000000000.log        ← segment starting at offset 0
    00000000000000000000.index      ← sparse offset index
    00000000000000000000.timeindex  ← time-based index
    00000000000001048576.log        ← segment starting at offset 1,048,576
    00000000000001048576.index
    00000000000002097152.log        ← active segment (being written)
```

Only the **active segment** (latest) is written to. Older segments are immutable.

**Retention policies**:
- **Time-based** (`log.retention.hours=168`, default 7 days): delete segments older than threshold
- **Size-based** (`log.retention.bytes`): delete oldest segments when total size exceeds limit
- **Log compaction** (`log.cleanup.policy=compact`): keep only the latest record per key — used for changelog topics (Kafka Streams state store, CDC)

---

## FAANG Interview Callout

> "Kafka's architecture is built around the ordered, append-only partition log. Every topic is split into partitions — partitions are the unit of parallelism, replication, and ordering. Within a partition, ordering is strict; across partitions, there's no global order. I choose a partition key that co-locates all events for a given entity (user, order) in the same partition to guarantee ordering per entity. Replication uses ISR — I set `acks=all` and `min.insync.replicas=2` so data is durable even if one broker dies. Consumer groups give me horizontal read scale: each partition goes to exactly one consumer in the group, so I can scale consumers up to the partition count. The critical insight is that consumers track their own offset — Kafka doesn't 'push' messages or track delivery; consumers pull at their own pace, which is why Kafka absorbs backpressure so well."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | What happens when a producer sends a record; how a consumer fetches |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Kafka vs RabbitMQ vs Pulsar vs Kinesis |
| [04-tuning-guide.md](04-tuning-guide.md) | Partition count, replication factor, acks, linger.ms, batch.size tuning |
