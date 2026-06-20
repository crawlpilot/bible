# Flink — Tuning Guide

## Parallelism

| Config | Default | Recommended | Notes |
|--------|---------|-------------|-------|
| `parallelism.default` | 1 | `num_cpu_cores × num_task_managers` | Set in `flink-conf.yaml`; operator-level overrides possible |
| Per-operator `.setParallelism(N)` | Inherits default | Source = partition count; downstream = multiple | Match source parallelism to Kafka partition count |
| `taskmanager.numberOfTaskSlots` | 1 | 2–4 per TM | More slots = more concurrent sub-tasks; CPU is shared |

**Parallelism sizing rule**:
```
Source parallelism   = Kafka partition count (1:1 consumer-to-partition)
Map/Filter           = Same as source (no shuffle)
keyBy → Window       = 1–4× source parallelism (state spread across key groups)
Sink                 = Match sink throughput capacity (don't bottleneck writes)
```

---

## Memory Configuration (Flink 1.10+ unified memory model)

```
Total Process Memory (taskmanager.memory.process.size, e.g. 8GB):
  ├── Total Flink Memory (taskmanager.memory.flink.size)
  │     ├── Framework Heap (taskmanager.memory.framework.heap.size, default 128MB)
  │     ├── Framework Off-Heap (128MB)
  │     ├── Task Heap (taskmanager.memory.task.heap.size)       ← JVM heap for tasks
  │     ├── Task Off-Heap (taskmanager.memory.task.off-heap.size)
  │     ├── Managed Memory (taskmanager.memory.managed.fraction, default 0.4)
  │     │     └── Used by RocksDB, sort buffers, batch operators
  │     └── Network Memory (fraction of Flink memory, default 0.1)
  │           └── Network buffers for data transfer between tasks
  └── JVM Overhead (metaspace, code cache, etc.)
```

### Key Memory Settings

| Setting | Recommended | Notes |
|---------|-------------|-------|
| `taskmanager.memory.process.size` | 4–16GB | Start here; tune based on state size |
| `taskmanager.memory.managed.fraction` | 0.4 | 40% for RocksDB; increase for large state jobs |
| `taskmanager.memory.network.fraction` | 0.1 | Network buffers; increase for high-parallelism jobs |
| `taskmanager.memory.jvm-metaspace.size` | 256MB | Increase if using many classes / Kryo serialization |

---

## Checkpoint Configuration

```yaml
# flink-conf.yaml
execution.checkpointing.interval: 60000           # checkpoint every 60s
execution.checkpointing.mode: EXACTLY_ONCE         # or AT_LEAST_ONCE (lower overhead)
execution.checkpointing.timeout: 600000            # cancel checkpoint if > 10min
execution.checkpointing.max-concurrent-checkpoints: 1
execution.checkpointing.min-pause: 30000           # minimum gap between checkpoints

# Unaligned checkpoints (reduces latency during checkpointing)
execution.checkpointing.unaligned: true            # Flink 1.11+
execution.checkpointing.aligned-checkpoint-timeout: 0  # switch to unaligned immediately

# State backend
state.backend: rocksdb
state.checkpoints.dir: s3://bucket/flink/checkpoints
state.savepoints.dir: s3://bucket/flink/savepoints

# Incremental checkpoints (RocksDB only — critical for large state)
state.backend.incremental: true
```

### Checkpoint Interval vs Recovery Time

```
Checkpoint interval:  1 min → recovery replays 1 min of data (fast recovery, high overhead)
Checkpoint interval: 10 min → recovery replays 10 min of data (slow recovery, lower overhead)

Rule of thumb:
  - Jobs with strict RTO: checkpoint every 1–5 minutes
  - High-throughput jobs where checkpoint overhead is felt: checkpoint every 10–30 minutes
  - Monitor: checkpoint duration should be < checkpoint interval (otherwise cluster is always checkpointing)
```

---

## RocksDB State Backend Tuning

RocksDB is a LSM-tree (same as Cassandra's SSTable model). Key parameters:

| Parameter | Where Set | Recommended | Notes |
|-----------|-----------|-------------|-------|
| Block cache size | `RocksDBOptionsFactory` | 256MB–2GB per TM | Cache hot state in memory; reduce disk I/O |
| Write buffer size | Per CF | 64MB–256MB | Larger = fewer compactions; more memory |
| Max write buffers | Per CF | 2–3 | Number of write buffers before flush |
| Bloom filter | Per CF | Enabled | Reduces reads for non-existent keys |
| Compaction style | Per CF | `LEVEL` (default) | `LEVEL` for read-heavy; `UNIVERSAL` for write-heavy |
| Predefined options | `PredefinedOptions` | `SPINNING_DISK_OPTIMIZED_HIGH_MEM` (SSD: `FLASH_SSD_OPTIMIZED`) | Tuned presets |

```java
// Set RocksDB options in job code
EmbeddedRocksDBStateBackend rocksDB = new EmbeddedRocksDBStateBackend(true); // incremental=true
rocksDB.setRocksDBOptions(new DefaultConfigurableOptionsFactory()
    .setMaxBackgroundJobs(4)
    .setWriteBufferSize("128mb")
    .setMaxWriteBufferNumber("3"));
env.setStateBackend(rocksDB);
```

**Critical**: RocksDB needs **local SSD**. If state spills to spinning disks, compaction I/O will degrade throughput severely.

---

## Backpressure Diagnosis and Resolution

**Step 1**: Identify bottleneck in Flink Web UI → "Job Graph" → click operators → "Back Pressure" tab.
- `OK`: no backpressure
- `LOW`: mild slowdown
- `HIGH`: blocked most of the time → this operator is the bottleneck

**Step 2**: The bottleneck is the operator *causing* backpressure, which is *downstream* of the operator showing HIGH backpressure.

```
Source [OK] → Map [OK] → Window [HIGH] → Sink [BOTTLENECK]
                                 ↑
                    Window is backed up because Sink is slow
```

**Step 3**: Fix based on root cause:

| Cause | Fix |
|-------|-----|
| Sink writes are slow | Increase sink parallelism; batch sink writes; use async sink |
| State access is slow (RocksDB) | Add block cache; move hot keys to heap state; add SSD |
| GC pauses causing stalls | Reduce heap usage; tune G1GC; increase managed memory fraction |
| Network bandwidth saturated | Reduce parallelism between remote TMs; enable compression |
| Window too large / too many keys | Reduce window size; pre-aggregate with `aggregate()` not `apply()` |

---

## Network Buffer Tuning

```yaml
taskmanager.network.memory.fraction: 0.1        # 10% of Flink memory
taskmanager.network.memory.min: 64mb
taskmanager.network.memory.max: 1gb

# Per-gate (downstream) buffers — increase for high-parallelism
taskmanager.network.memory.buffers-per-channel: 2     # default 2; increase to 8 for long pipelines
taskmanager.network.memory.floating-buffers-per-gate: 8
```

If you see `OutOfMemoryError: Direct buffer memory` → increase network memory fraction or reduce parallelism.

---

## Serialization

Flink serializes records between operators. Prefer **POJO types** or **Avro/Protobuf** over generic Java objects:

| Approach | Performance | Notes |
|----------|-------------|-------|
| POJO (all fields public or getter/setter) | Fast | Flink generates efficient TypeSerializer |
| Avro / Protobuf (via Flink connectors) | Fast | Schema-evolved; good for Kafka integration |
| Kryo (fallback for unknown types) | Slow | Reflection-based; 2–5x slower than POJO |
| Java Serializable | Very slow | Avoid; Flink will warn |

```java
// Force Kryo for a type (last resort)
env.getConfig().registerTypeWithKryoSerializer(MyClass.class, MyKryoSerializer.class);

// Disable Kryo fallback to catch unregistered types early (recommended in production)
env.getConfig().disableGenericTypes();
```

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| **Large objects in state** | GC pressure (HashMapState) or slow RocksDB writes | Store only the minimal accumulator; reference large objects in external store |
| **No `.uid()` on stateful operators** | Cannot restore savepoint after code change or rescale | Always assign stable UIDs: `.uid("my-operator")` |
| **Checkpoint interval < checkpoint duration** | Cluster is always checkpointing; no throughput headroom | Increase interval or reduce state size; enable incremental checkpoints |
| **High-cardinality key with tiny state per key** | Millions of RocksDB SST files; compaction overhead | Batch keys (e.g., hash to 1000 buckets) or use TTL to expire old keys |
| **Blocking I/O in process()** | Stalls the entire slot thread; cascades as backpressure | Use `AsyncDataStream.unorderedWait()` for async I/O (HTTP calls, DB reads) |
| **Missing TTL on state** | State grows unboundedly; OOM or disk exhaustion | Register TTL: `StateTtlConfig.newBuilder(Time.hours(24)).build()` |
| **`apply()` over `aggregate()` for large windows** | Buffers all events; massive memory pressure at window close | Use `aggregate()` to maintain only accumulator state |
| **Single global parallelism for all operators** | Source parallelism ≠ sink parallelism — unnecessary serialization | Set parallelism per operator to match upstream/downstream rates |
| **Ignoring watermark lateness** | Late events silently dropped or incorrect results | Set `allowedLateness()`; route late data to side output for inspection |

---

## Key Metrics to Monitor

| Metric | Source | Alert Condition |
|--------|--------|----------------|
| `lastCheckpointDuration` | JMX / Prometheus | > checkpoint interval (checkpointing never completes) |
| `lastCheckpointSize` | JMX | Growing → state growth; investigate TTL |
| `numRecordsInPerSecond` | Task metric | Drop → upstream slowdown or backpressure |
| `backPressuredTimeMsPerSecond` | Task metric | > 500ms/s → significant backpressure |
| `numLateRecordsDropped` | Window operator | > 0 → watermark lag too aggressive; increase allowed lateness |
| `KafkaConsumer.records-lag-max` | Kafka consumer group | Growing → Flink can't keep up with Kafka |
| RocksDB `estimate-live-data-size` | RocksDB metrics | Growing → state is not expiring; check TTL |

---

## FAANG Interview Callout

> "The most impactful Flink tuning is getting the checkpoint interval right — too frequent and you spend 20% of your throughput on checkpointing; too infrequent and recovery replays hours of data. For large-state jobs, incremental RocksDB checkpoints are non-negotiable — full snapshots of TB-scale state are impractical. The anti-pattern I always catch in reviews is missing `.uid()` on stateful operators: without it, a job upgrade or rescale will fail to restore the savepoint. For backpressure, the key insight is that the operator showing HIGH backpressure in the UI is not the bottleneck — its downstream neighbour is. And for blocking I/O (external API calls inside a process function), I always switch to `AsyncDataStream.unorderedWait()` to avoid stalling the task thread."
