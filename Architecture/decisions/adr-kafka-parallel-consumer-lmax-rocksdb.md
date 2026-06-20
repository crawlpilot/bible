# ADR-002: Parallelised Kafka Consumer Topology with LMAX Disruptor and RocksDB-Backed Exactly-Once Delivery

**Title**: Scale Kafka Stream Processing via Per-Partition Parallelism, LMAX Disruptor Dispatch, and RocksDB Local State with Exactly-Once Semantics  
**Status**: Accepted  
**Date**: 2026-06-06  
**Authors**: [Principal Engineer]  
**Reviewers**: [Staff Engineer — Streaming Platform], [SRE Lead]  
**Deciders**: [VP Engineering]

---

## Context

Our event pipeline ingests **4M events/sec** across 512 Kafka partitions (16 topics × 32 partitions each). The pipeline performs stateful enrichment — joining a raw event stream against a user-profile change-log and an inventory snapshot — before emitting to a downstream aggregation layer.

Current state (before this ADR):

| Symptom | Observed value |
|---|---|
| End-to-end latency (p99) | 1,200 ms — SLA breach (target: ≤ 200 ms) |
| Consumer lag (peak) | 14 M records |
| CPU utilisation (consumer pods) | 18% — GC pauses dominate wall time |
| Duplicate events (at-least-once delivery) | 0.3% of daily volume — causing downstream counter inflation |

Root-cause analysis identified three bottlenecks:

1. **Single-threaded poll loop** — one thread per Kafka consumer instance serialises poll, deserialise, business logic, and produce into a sequential pipeline. Any single slow record (e.g., blocking state-store lookup) stalls the entire partition.
2. **Lock contention on shared in-memory state** — enrichment maps are guarded by `synchronized` blocks; threads pile up waiting.
3. **At-least-once delivery with manual offset commit** — on consumer restart, up to 500 ms of records are reprocessed; deduplication is best-effort and stateless.

The engineering team evaluated three approaches (see Alternatives) before settling on the architecture described below.

---

## Decision

**Adopt a three-layer parallel consumer architecture:**

```
Kafka Partition (1 thread per partition — poll loop)
        │
        ▼
  LMAX Disruptor Ring Buffer  (lock-free MPSC queue)
        │
        ├──► Worker 1  (business logic + RocksDB read)
        ├──► Worker 2
        ├──► Worker N
        │
        ▼
  Kafka Producer (transactional) + RocksDB write
        │
        ▼
  Offset commit (inside Kafka transaction → EOS)
```

### Layer 1 — One Poll Thread per Partition

Kafka Streams assigns each partition to a **StreamTask**. Each task runs its own poll loop on a dedicated thread — no partition ever waits for another. Parallelism ceiling = number of partitions (512 in our case).

**Configuration:**
```properties
num.stream.threads=64                 # JVM instances × threads; partitions spread across them
max.poll.records=500                  # bound poll latency; keep < poll.interval.ms
max.poll.interval.ms=300000
```

The poll thread's **only job** is to deserialise and publish to the Disruptor ring buffer. It never touches business logic or state.

---

### Layer 2 — LMAX Disruptor as the Intra-Process Dispatch Bus

#### How the Disruptor Works

The LMAX Disruptor is a **lock-free, cache-line-optimised ring buffer** designed to eliminate the two dominant costs of `java.util.concurrent.LinkedBlockingQueue`:
- Lock acquisition (kernel context switch)
- False sharing (multiple threads writing adjacent cache lines)

Core mechanics:

```
Ring Buffer (power-of-2 size, e.g. 65536 slots)
┌───────────────────────────────────────────────┐
│  slot[0]  slot[1]  ...  slot[65535]           │
└───────────────────────────────────────────────┘
        ▲                         ▲
  Producer cursor            Consumer cursors
  (single AtomicLong)        (one per worker, padded to 64 bytes)
```

1. **Publisher** claims the next sequence number via `AtomicLong.getAndIncrement()` — a single CAS, no lock.
2. **Event** is written into the pre-allocated slot (ring buffer slots are allocated once at startup; no GC pressure from object creation).
3. **Consumers** each maintain their own sequence cursor, padded with 56 bytes on each side to fill a full 64-byte cache line — prevents false sharing between worker threads reading adjacent cursors.
4. **Wait strategy** is configurable:
   - `BusySpinWaitStrategy` — burns a CPU core; sub-microsecond latency; use only when CPU is not the bottleneck
   - `YieldingWaitStrategy` — calls `Thread.yield()` after spin; good balance for our workload
   - `BlockingWaitStrategy` — uses a lock+condition; lowest CPU, highest latency; avoid for hot paths

**Throughput characteristic:** Under our benchmarks (AWS r6i.8xlarge, 32 vCPU), the Disruptor sustained **18M events/sec** single-producer / multi-consumer vs **3.2M events/sec** for `ArrayBlockingQueue` at the same concurrency.

#### Why lock-free matters here

Our poll thread publishes at ~8K events/sec per partition. With 8 worker threads sharing the ring buffer, the critical section duration is a single `compareAndSet` (≈ 8 ns) vs a mutex acquire/release cycle (≈ 200–500 ns under contention). At 4M events/sec aggregate, this difference is ~800 ms of saved lock-contention time per second.

**Configuration:**
```java
Disruptor<KafkaEvent> disruptor = new Disruptor<>(
    KafkaEvent::new,
    65_536,                        // ring buffer size — must be power of 2
    DaemonThreadFactory.INSTANCE,
    ProducerType.SINGLE,           // one poll thread per partition
    new YieldingWaitStrategy()
);
disruptor.handleEventsWith(worker1, worker2, ..., workerN);
```

Each **worker handler** executes: deserialise payload → enrich from RocksDB → emit to transactional Kafka producer.

---

### Layer 3 — RocksDB Local State Store + Kafka Transactions for Exactly-Once Semantics

#### RocksDB as Embedded State Store

Kafka Streams uses RocksDB as its default persistent state store. Each StreamTask owns a private RocksDB instance (no sharing across tasks), storing:

- **User profile changelog** — compacted from a `__consumer_offsets`-style topic; ~400 GB per node after bloom-filter compression
- **Inventory snapshot** — point-in-time copy replicated from source-of-truth DB via CDC

RocksDB read path:
```
Lookup key
  │
  ├─ Block cache (LRU, 8 GB per instance) ──► hit: ~1 µs
  │
  ├─ Bloom filter (10 bits/key, FPR 1%) ──► skip SSTable: ~10 µs
  │
  └─ SSTable disk read (NVMe SSD) ──► ~100 µs
```

**Key tuning:**
```properties
# Per StreamTask RocksDB instance
rocksdb.block.cache.size=8589934592       # 8 GB
rocksdb.bloom.filter.bits.per.key=10
rocksdb.compaction.style=LEVEL
rocksdb.max.write.buffer.number=4
rocksdb.write.buffer.size=134217728       # 128 MB MemTable
rocksdb.target.file.size.base=134217728
```

#### Exactly-Once Semantics (EOS) via Kafka Transactions

Kafka's EOS guarantee requires **transactional producers** + **read_committed consumer isolation**. The protocol:

```
1. Producer initialises with transactional.id (one per StreamTask, stable across restarts)
2. BEGIN transaction
3. Write output records to output topic(s)
4. Write changelog records to state store backing topic
5. Send offsets-to-commit to __consumer_offsets via sendOffsetsToTransaction()
6. COMMIT transaction
   → Kafka broker writes commit marker to all involved partitions atomically
   → Only on success does the consumer position advance
```

If the consumer crashes between step 3 and step 6, the uncommitted output records are invisible to downstream `read_committed` consumers. On restart, the StreamTask resumes from the last committed offset — records are reprocessed but idempotent producers (each record has a `producerId + sequenceNumber`) prevent broker-side duplicates.

**RocksDB's role in EOS:** The state store changelog is included in the same Kafka transaction as the output. This means if a crash occurs, both the output records **and** the state store update are rolled back together — the local RocksDB state is restored from the changelog on task restart, ensuring exactly-once state transitions.

**Configuration:**
```properties
processing.guarantee=exactly_once_v2     # EOS v2: one txn coordinator per StreamTask (vs v1: one per consumer group)
transaction.timeout.ms=60000
enable.idempotence=true
acks=all
```

EOS v2 (`exactly_once_v2`) reduces coordinator load by eliminating the epoch bump on consumer group rebalance — critical when we have 512 StreamTasks fencing against the broker.

---

## Trade-offs

### Parallelism per Partition

| Dimension | Benefit | Cost |
|---|---|---|
| Throughput | Linear scaling up to partition count (512×) | Partition count is the hard ceiling — cannot parallelize within a single partition without sacrificing ordering |
| Latency | Eliminates head-of-line blocking between partitions | Thread-per-partition model: 512 threads minimum; context switch overhead at idle |
| Ordering | Per-key ordering preserved (same key → same partition → same task) | Cross-partition joins require repartitioning topic (network hop) |
| Operational | Standard Kafka Streams — well-understood failure model | Consumer group rebalance pauses all tasks; with EOS v2, rebalance adds ~1–2 sec pause |

### LMAX Disruptor

| Dimension | Benefit | Cost |
|---|---|---|
| Latency | Sub-microsecond hand-off from poll to worker | `BusySpinWaitStrategy` burns full CPU core; must capacity-plan for it |
| Throughput | 5–6× over `ArrayBlockingQueue` in our benchmarks | Cognitive overhead — harder to reason about back-pressure than `BlockingQueue` |
| GC | Pre-allocated ring buffer; no object churn | Ring buffer size is fixed at startup; oversizing wastes heap, undersizing causes producer stall |
| Observability | Disruptor exposes `remainingCapacity()` — easy to alert on | Not natively integrated with Micrometer; requires custom metrics bridge |
| Complexity | Lock-free code is provably correct for the ring buffer pattern | Wrong sequence ordering in `EventHandler` chains can introduce silent bugs; requires expert review |

### RocksDB Local State + EOS

| Dimension | Benefit | Cost |
|---|---|---|
| Read latency | Block cache hit ~1 µs vs remote DB ~5–50 ms | Cache warm-up after restart: cold start adds ~30–120 sec lag before reaching steady-state throughput |
| Durability | Changelog-backed; recoverable from Kafka on any node | Changelog replay time scales with state size; 400 GB = ~20 min recovery on cold node |
| Exactly-once | Eliminates all duplicate processing — removes downstream deduplication logic | Throughput penalty: ~15% vs at-least-once (transaction coordinator round-trip per batch) |
| State size | Local NVMe; no network I/O for state reads | Not horizontally shareable — state is local to StreamTask; repartitioning required for global aggregations |
| Rebalance | Kafka Streams transfers changelog offset to new task owner on rebalance | Standby replicas (`num.standby.replicas=1`) required to avoid cold-start; doubles changelog storage |

---

## Consequences

### Positive
- p99 end-to-end latency reduced from 1,200 ms → **85 ms** (measured over 72-hour load test at 4.2M events/sec)
- Consumer lag at peak reduced from 14 M → **< 50K** records
- Duplicate rate reduced from 0.3% → **0.0%** (verified via downstream counter reconciliation)
- Poll-thread CPU utilisation increased from 18% → 62% (useful work, not GC)

### Negative / Risks
- **Operational complexity**: Three subsystems (Kafka Streams, Disruptor, RocksDB) each with distinct tuning surfaces. Requires runbook coverage for: Disruptor stall (ring buffer full), RocksDB compaction debt, EOS zombie transaction (broker rejects fenced producer).
- **Rebalance sensitivity**: EOS v2 still pauses processing during consumer group rebalance. With 512 tasks, a single pod eviction triggers a full rebalance affecting all consumers. Mitigation: use static group membership (`group.instance.id`) + `session.timeout.ms=45000` to avoid unnecessary rebalances.
- **RocksDB cold-start**: Standby replicas (`num.standby.replicas=1`) must be provisioned to keep recovery time < 60 seconds. This doubles storage cost for state stores (~800 GB NVMe per pair).
- **Disruptor ring buffer sizing**: If workers fall behind (e.g., RocksDB compaction spike), the ring buffer fills and the poll thread stalls, which eventually triggers a `max.poll.interval.ms` breach and consumer group rebalance. Monitor `disruptor.remaining_capacity` and alert at < 20% to catch this before it cascades.

---

## Alternatives Considered

### Alternative 1: Increase Kafka Partition Count Only (No Disruptor, No EOS)

Simple horizontal scaling — add more pods, each consuming a subset of partitions.

**Rejected because:**
- Does not address the single-threaded poll-loop bottleneck within a partition
- At-least-once semantics means duplicate problem persists
- Partition reassignment at scale (512 → 2048) requires broker-side partition movement, a multi-hour operation with replication traffic

### Alternative 2: Virtual Thread (Project Loom) per Record

Use Java 21 virtual threads to run each record's processing logic concurrently within a single poll loop.

**Rejected because:**
- Virtual threads yield on blocking I/O (good) but RocksDB is accessed via JNI (off-heap) — not a blocking I/O operation in the JVM scheduler's view; virtual threads do not yield on JNI calls
- No native integration with Kafka Streams task model
- Early benchmarks showed no meaningful latency improvement over platform threads for our RocksDB-dominated workload

### Alternative 3: Apache Flink Instead of Kafka Streams

Flink provides native EOS, stateful processing, and a more expressive API.

**Partially accepted, deferred:** Flink is on the 12-month roadmap for complex multi-stream joins. For the current enrichment pipeline (single changelog join), Kafka Streams + this ADR's architecture delivers equivalent throughput with lower operational surface area and zero additional infrastructure. Revisit when cross-stream windowed aggregations are required.

### Alternative 4: External State Store (Redis Cluster) Instead of RocksDB

Replace local RocksDB with a centralised Redis cluster for state reads.

**Rejected because:**
- Network round-trip for each enrichment lookup adds 1–5 ms per record; at 4M events/sec this is the dominant latency term
- Redis cluster introduces a shared-failure domain — one cluster serves all 512 StreamTasks; a Redis failover pauses the entire pipeline
- RocksDB with changelog achieves the same durability guarantee without the network hop

---

## Rollout Plan

| Phase | Scope | Success Criteria | Rollback |
|---|---|---|---|
| 1 — Shadow mode | 2 partitions, read-only Disruptor, no EOS | Disruptor stall rate = 0; p99 latency < 100 ms | Disable Disruptor; revert to sync poll loop |
| 2 — Canary EOS | 10% of partitions, EOS v2 enabled | Zero duplicates; rebalance time < 3 sec | `processing.guarantee=at_least_once`; flush deduplication cache |
| 3 — Full rollout | All 512 partitions | p99 < 200 ms at 4M events/sec sustained for 7 days | Feature flag: roll back to pre-ADR consumer config |

---

## FAANG Interview Callouts

**"Why not just add more partitions?"**  
Adding partitions helps with throughput ceiling but does not fix within-partition head-of-line blocking or delivery semantics. Partitions are the unit of parallelism in Kafka; the Disruptor is the unit of parallelism *within* a partition's processing pipeline — they address orthogonal bottlenecks.

**"How does EOS interact with consumer group rebalance?"**  
On rebalance, the old task owner's in-flight transaction is aborted (the producer epoch is bumped via `fencing`). The new task owner reads from the last committed offset. No data is lost; at most one batch is reprocessed — but idempotent producers ensure the broker rejects the re-sent batch as a duplicate if the commit already landed.

**"What's the failure mode if RocksDB compaction can't keep up?"**  
Write amplification debt accumulates. Read latency on SSTable tiers climbs (bloom filter bypasses increase). Monitor `rocksdb.estimate.pending.compaction.bytes`; if it exceeds 10 GB, throttle producer rate (`rocksdb.rate.limiter.bytes.per.sec`) to give compaction headroom. In production at Confluent scale, this is the #1 operational failure mode for Kafka Streams stateful applications.

**"Why LMAX Disruptor over Akka or Reactor?"**  
Akka and Reactor are better choices when the processing graph is dynamic (conditional fan-out, async I/O, back-pressure propagation to upstream). The Disruptor is optimal when the processing graph is static and latency is the dominant concern — it trades flexibility for the lowest possible dispatch overhead. Our enrichment pipeline is a fixed two-stage DAG (enrich → emit), making Disruptor the right tool.

---

## References

- Martin Thompson et al., *Disruptor: High performance alternative to bounded queues for exchanging data between concurrent threads*, LMAX, 2011
- Kafka KIP-447: Producer scalability for exactly once semantics (`exactly_once_v2`)
- Kafka Streams EOS documentation: `processing.guarantee` configuration
- RocksDB tuning guide: `https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide`
- Discord engineering blog: *How Discord Stores Trillions of Messages* (RocksDB at scale)
- Confluent blog: *Enabling Exactly-Once in Kafka Streams*
