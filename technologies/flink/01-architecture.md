# Flink — Architecture

## Origins: Stratosphere → Flink

Flink began as the Stratosphere research project at TU Berlin (2010), targeting large-scale parallel data processing. The key architectural insight that separated it from Hadoop MapReduce and early Spark: **treat streams as the fundamental primitive, and batch as a special case of a bounded stream** — not the other way around.

| Influence | Contribution |
|-----------|-------------|
| **Dataflow model (Google 2015)** | Event time, watermarks, windows, triggers — Flink implements the full Dataflow model |
| **Chandy-Lamport (1985)** | Distributed snapshot algorithm adapted as Flink's checkpoint mechanism |
| **Naiad (Microsoft Research)** | Timely dataflow — cyclic dataflow graphs for iterative computation |
| **Dryad (Microsoft)** | DAG-based distributed execution engine |

---

## Cluster Architecture

```
  Client (submits job)
       │
       │ JobGraph (logical DAG)
       ▼
  ┌─────────────────────────────────────┐
  │         JobManager                  │
  │  ┌──────────────────────────────┐   │
  │  │ Dispatcher          REST API │   │  ← job submission, monitoring
  │  │ ResourceManager              │   │  ← slot allocation, TaskManager lifecycle
  │  │ JobMaster (per job)          │   │  ← execution graph, checkpoint coordination
  │  └──────────────────────────────┘   │
  └─────────────────────────────────────┘
       │  slot requests
       ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │ TaskManager 1│  │ TaskManager 2│  │ TaskManager 3│
  │  Slot  Slot  │  │  Slot  Slot  │  │  Slot  Slot  │
  │  [op1][op2]  │  │  [op3][op4]  │  │  [op5][op6]  │
  └──────────────┘  └──────────────┘  └──────────────┘
```

### JobManager

The **JobManager** is the master coordinator. In high-availability mode, multiple JobManagers run (one active, rest on standby) with leadership tracked via ZooKeeper or Kubernetes.

Responsibilities:
- **Dispatcher**: accepts job submissions, creates a JobMaster per job
- **ResourceManager**: manages TaskManager registration and slot requests (YARN, K8s, or standalone)
- **JobMaster**: owns one job's execution — schedules tasks, monitors heartbeats, coordinates checkpoints, handles failures

### TaskManager

The **TaskManager** is the worker process. Each TM:
- Registers with the ResourceManager on startup
- Exposes a configured number of **task slots**
- Each slot is a fixed fraction of TM resources (memory, but NOT CPU — slots share CPUs)
- Runs one **sub-task** (one parallel instance of one operator) per slot

```
TaskManager (4 slots, 16GB RAM):
  Slot 0 (4GB): running sub-task for operator Source[0]
  Slot 1 (4GB): running sub-task for operator Filter[0]
  Slot 2 (4GB): running sub-task for operator Aggregate[0]
  Slot 3 (4GB): running sub-task for operator Sink[0]
```

**Slot sharing**: By default, Flink allows sub-tasks from different operators of the same job to share a slot. This means one slot can run an entire pipeline chain (Source → Filter → Map → Sink), which improves resource utilisation and reduces inter-slot network hops.

---

## Execution Graph: From Job to Tasks

A Flink job goes through four representations:

```
StreamGraph           →  JobGraph          →  ExecutionGraph       →  Physical Execution
(user API calls)         (logical DAG,         (parallel instances,    (tasks on TaskManagers)
                          chaining applied)     vertices + edges)

map().filter()           Source → Filter       Source[0] Source[1]      TM1:Slot0 TM2:Slot0
  .keyBy().window()      → KeyBy → Window      Filter[0] Filter[1]      TM1:Slot1 TM2:Slot1
  .reduce().sink()       → Reduce → Sink       ...                      ...
```

**Operator chaining**: Flink fuses consecutive operators (same parallelism, no shuffle boundary) into a single **task** running in one thread. This eliminates serialization and network overhead between chained operators.

---

## Parallelism

Every operator in Flink has a **parallelism** — the number of parallel sub-tasks. The job's default parallelism is set at submission; individual operators can override it.

```
Source (parallelism=4)  →  Map (parallelism=4)  →  keyBy()  →  Window (parallelism=4)
   [S0][S1][S2][S3]          [M0][M1][M2][M3]                    [W0][W1][W2][W3]

After keyBy(), records are shuffled by key:
  Key "user:1" always goes to W1
  Key "user:2" always goes to W0
  (determined by hash(key) % parallelism)
```

**Sizing rule**: `total_slots_needed = max_parallelism_across_operators`. If your highest-parallelism operator is 16, you need ≥ 16 slots in the cluster.

---

## State Backends

Flink manages operator state transparently. The **state backend** determines where state is stored during execution and how it is checkpointed.

| Backend | State Storage | Checkpoint Storage | Best For |
|---------|--------------|-------------------|---------|
| **HashMapStateBackend** (default) | JVM heap | Filesystem (HDFS, S3) | Small–medium state (< few GB total); fast access |
| **EmbeddedRocksDBStateBackend** | RocksDB on local disk (off-heap) | Filesystem (HDFS, S3) | Large state (hundreds of GB to TB); spills to disk |

### RocksDB State Backend

```
Operator key-value state (e.g., running sum per userId):

  JVM process
  ├── Flink Task Thread
  │     ↕ JNI (native call)
  └── RocksDB instance (native, off-heap)
        ├── MemTable (in-memory write buffer)
        ├── SSTable files (on local SSD)
        └── WAL (write-ahead log)

On checkpoint: RocksDB takes an incremental snapshot → uploads diffs to S3/HDFS
```

**RocksDB trade-offs**:
- Pros: state can exceed JVM heap; no GC pressure from large state; incremental checkpoints
- Cons: ~2–10x slower state access (JNI overhead + potential disk I/O); requires local SSD for good performance

---

## Fault Tolerance: Chandy-Lamport Distributed Snapshots

Flink's exactly-once fault tolerance is based on the **Chandy-Lamport algorithm** (1985), adapted for streaming dataflows.

### Checkpoint Mechanism

```
Stream of records:   [r1][r2][r3] || [B1] || [r4][r5][r6] || [B2] || ...
                                     checkpoint barrier 1      checkpoint barrier 2

1. JobManager triggers checkpoint: sends barrier to all source operators
2. Source operators emit the barrier downstream after their current records
3. Each operator, upon receiving barriers from ALL upstream inputs:
   a. Snapshots its current state to the configured state backend
   b. Forwards the barrier downstream
4. When all sink operators report barrier received, checkpoint is complete
5. JobManager stores the completed checkpoint metadata

On failure:
  → All operators reset to their state at the last completed checkpoint
  → Sources replay records since that checkpoint offset
  → Exactly-once: each record affects state exactly once
```

### Barrier Alignment (default, exactly-once)

```
Operator with 2 inputs:

  Input A: [r1a][r2a] | [B1] |
  Input B: [r1b]           | [B1] |

  Operator waits for B1 on BOTH inputs before snapshotting.
  Records arriving after B1 on Input A are buffered (not processed) until B1 arrives on Input B.
  → This ensures the snapshot is consistent: captures state after processing r1a, r2a, r1b but not r2b+.
  → Trade-off: buffering causes latency spikes when inputs are skewed.
```

### Unaligned Checkpoints (Flink 1.11+)

Unaligned checkpoints avoid the buffering overhead by including in-flight records (those between barriers) as part of the checkpoint state:

- Pros: checkpoint time is not affected by input skew; better latency during checkpointing
- Cons: larger checkpoint size (includes in-flight data); more complex recovery

Use unaligned checkpoints when checkpoint times are long due to barrier alignment stalls.

### Savepoints vs Checkpoints

| | Checkpoint | Savepoint |
|--|-----------|-----------|
| **Triggered by** | Flink automatically (interval) | User manually (CLI: `flink savepoint <jobId>`) |
| **Purpose** | Fault recovery | Planned: job upgrades, rescaling, migration |
| **Lifecycle** | Automatically deleted when superseded | Retained until manually deleted |
| **Operator IDs** | Internal (auto-generated) | Stable (user assigns via `.uid("myop")`) |
| **Format** | Implementation-specific | Stable, versioned |

**Always assign `.uid()` to stateful operators** — this is how Flink maps savepoint state to operators when rescaling or updating code.

---

## Event Time and Watermarks

### Time Semantics

| Time Model | Definition | Use When |
|-----------|-----------|---------|
| **Event time** | Timestamp embedded in the event (e.g., `event.timestamp`) | Out-of-order events; correct results regardless of processing delay |
| **Processing time** | Wall clock time when the record is processed | Lowest latency; acceptable when ordering doesn't matter |
| **Ingestion time** | Timestamp assigned when the record enters Flink | Middle ground; no out-of-order within Flink but can't correct upstream delays |

### Watermarks

A **watermark** is a timestamp assertion: "all events with `event_time < W` have arrived." Watermarks flow through the DAG alongside records. Window computations trigger when the watermark surpasses the window's end time.

```
Event stream (arrival order):  e(t=10), e(t=8), e(t=11), e(t=9), e(t=13), e(t=7) ...
                                                                           ↑
                                                                   out-of-order (late)

Watermark strategy: maxEventTimeSeen - 5s (5-second allowed lateness)

  After seeing t=13:  watermark = 13 - 5 = 8
  Window [0,10) triggers when watermark ≥ 10
  Events with t < watermark that arrive later → late data (configurable: drop, side-output, or update)
```

**WatermarkStrategy in Flink:**

```java
DataStream<Event> stream = env
    .fromSource(kafkaSource, 
        WatermarkStrategy
            .<Event>forBoundedOutOfOrderness(Duration.ofSeconds(5))  // 5s max lateness
            .withTimestampAssigner((event, ts) -> event.getTimestamp()),
        "kafka-source");
```

---

## FAANG Interview Callout

> "Flink's architecture separates coordination (JobManager) from execution (TaskManagers). The JobManager runs the JobMaster which schedules tasks onto slots in TaskManagers and coordinates checkpoints. The core fault-tolerance mechanism is the Chandy-Lamport distributed snapshot: the JobManager periodically injects checkpoint barriers into the source streams; when a barrier has flowed through every operator and been acknowledged by the sink, Flink records that checkpoint as complete. On failure, all operators reload their state from the last complete checkpoint and replay input records from that point — exactly-once. The key operational decision is the state backend: HashMapStateBackend for small state (fast, in JVM heap), RocksDB for large state (slower JNI access, but survives beyond heap size). I always assign stable UIDs to stateful operators so that savepoints survive job upgrades."

---

## Related Files

| File | Topic |
|------|-------|
| [02-read-write-path.md](02-read-write-path.md) | How records flow through operators; windows; state access |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Flink vs Spark Streaming vs Kafka Streams vs Storm |
| [04-tuning-guide.md](04-tuning-guide.md) | Parallelism, RocksDB tuning, checkpoint config, backpressure |
