# Flink — Record Flow, Windows, and State

## Record Flow Through the DAG

```
Kafka Source (parallelism=4)
  Consumer[0]  Consumer[1]  Consumer[2]  Consumer[3]
      │             │             │             │
      │  deserialize + assign timestamps + emit watermarks
      ▼             ▼             ▼             ▼
Map / Filter operators (chained — same thread, no serialization)
      │             │             │             │
      │  keyBy(userId) → hash-partition by key
      ▼             ▼             ▼             ▼
Window Operator[0..3]  — each holds state for keys assigned to it
      │             │             │             │
      │  window fires → emit aggregated result
      ▼             ▼             ▼             ▼
Sink (Kafka / Cassandra / Elasticsearch)
```

### Network Transport Between Operators

When operators are NOT chained (different parallelism or explicit `shuffle()`), records are serialized and sent over the network via **Netty**:

```
Upstream Task → serialize (Flink TypeSerializer, Avro, or Kryo) →
  NetworkBuffer pool → TCP channel → downstream Task → deserialize
```

Flink uses **credit-based flow control**: downstream tasks grant "credits" (buffer slots) to upstream. If downstream is slow, upstream stops sending → **backpressure** propagates upstream naturally. No record loss on overload — just slowdown.

---

## Windows

Windows are the primary mechanism for grouping an infinite stream into finite chunks for aggregation.

### Window Types

```
Tumbling Window (size=5min, no overlap):
  [0:00─0:05) [0:05─0:10) [0:10─0:15) ...
  Each event belongs to exactly one window.

Sliding Window (size=10min, slide=5min):
  [0:00─0:10) [0:05─0:15) [0:10─0:20) ...
  Each event belongs to ceil(size/slide) = 2 windows → higher compute cost.

Session Window (gap=5min):
  Events clustered by inactivity gap.
  [e1,e2,e3]──gap>5min──[e4,e5]──gap>5min──[e6] ...
  Window closes after 5min of silence per key.

Global Window: all events for a key in one window; requires custom trigger.
```

### Window Lifecycle

```java
stream
    .keyBy(event -> event.getUserId())
    .window(TumblingEventTimeWindows.of(Time.minutes(5)))
    .allowedLateness(Time.seconds(30))             // accept late events up to 30s after window closes
    .sideOutputLateData(lateOutputTag)             // route very-late events to a side stream
    .aggregate(new MyAggregateFunction(),          // incremental aggregation (state = partial agg)
               new MyWindowFunction());            // final result computation when window fires
```

**Incremental vs full-window aggregation**:
- `aggregate()` / `reduce()`: accumulate state incrementally; only the accumulator is stored per window → low memory
- `apply()` / `process()`: all events buffered until window fires → allows complex logic but high memory cost

### Window Triggers

The trigger decides when a window fires:
- **EventTimeTrigger** (default for event-time windows): fires when watermark surpasses window end
- **ProcessingTimeTrigger**: fires on wall clock
- **CountTrigger**: fires after N elements
- **ContinuousEventTimeTrigger**: fires periodically within a window (early results)

---

## Keyed State

Flink state is **keyed** — each parallel instance of a stateful operator owns state for a subset of keys. State types:

| State Type | Description | Example |
|-----------|-------------|---------|
| `ValueState<T>` | Single value per key | Last seen event per user |
| `ListState<T>` | Ordered list per key | All events in current session |
| `MapState<K,V>` | Key-value map per key | Feature map per userId |
| `ReducingState<T>` | Running aggregate (reduce) | Running sum per user |
| `AggregatingState<IN,OUT>` | Running aggregate (custom) | Running average per user |

```java
public class FraudDetector extends KeyedProcessFunction<String, Transaction, Alert> {

    // Declare state: flagged = whether this user is currently flagged
    private transient ValueState<Boolean> flagState;
    private transient ValueState<Long>    timerState;

    @Override
    public void open(Configuration config) {
        // Register state on startup — Flink restores this from checkpoint on recovery
        flagState  = getRuntimeContext().getState(new ValueStateDescriptor<>("flag", Boolean.class));
        timerState = getRuntimeContext().getState(new ValueStateDescriptor<>("timer", Long.class));
    }

    @Override
    public void processElement(Transaction txn, Context ctx, Collector<Alert> out) throws Exception {
        Boolean flag = flagState.value();
        if (flag != null && flag) {
            if (txn.getAmount() > 1000) {
                out.collect(new Alert(txn.getUserId()));   // emit fraud alert
            }
            clean();
        }
        if (txn.getAmount() < 1.0) {
            flagState.update(true);
            // Register timer: clear flag after 1 minute
            long timer = ctx.timerService().currentProcessingTime() + 60_000L;
            ctx.timerService().registerProcessingTimeTimer(timer);
            timerState.update(timer);
        }
    }

    @Override
    public void onTimer(long timestamp, OnTimerContext ctx, Collector<Alert> out) throws Exception {
        clean();   // flag expired — no large transaction followed the small one
    }

    private void clean() throws Exception {
        timerState.value(); // cancel timer
        flagState.clear();
        timerState.clear();
    }
}
```

---

## Checkpoint Barrier Flow

```
Source emits:  [r1][r2][r3][BARRIER-1][r4][r5][BARRIER-2]...
                                │
                    JobManager triggered checkpoint #1
                                │
         Operator A receives BARRIER-1:
           → snapshots ValueState for all owned keys → S3: checkpoint/op-a/1.bin
           → forwards BARRIER-1 downstream

         Operator B (2 inputs: A and C):
           → receives BARRIER-1 from A → buffers further records from A
           → waits for BARRIER-1 from C (alignment)
           → once both received: snapshots state → forwards BARRIER-1

         Sink acknowledges BARRIER-1 to JobManager
         JobManager: all operators acked → Checkpoint #1 COMPLETE
         JobManager: notifies sources to retain records from checkpoint #1 offset onward
```

### Checkpoint Storage

| Storage | Config | Use When |
|---------|--------|---------|
| `FileSystemCheckpointStorage` | `state.checkpoints.dir: s3://...` | Production: durable, survives cluster restart |
| `JobManagerCheckpointStorage` | In-memory at JobManager | Development only; lost on JM restart |

```yaml
# flink-conf.yaml
state.backend: rocksdb
state.checkpoints.dir: s3://my-bucket/flink-checkpoints
state.savepoints.dir: s3://my-bucket/flink-savepoints
execution.checkpointing.interval: 60000         # checkpoint every 60s
execution.checkpointing.mode: EXACTLY_ONCE
execution.checkpointing.timeout: 600000         # fail checkpoint if > 10min
execution.checkpointing.max-concurrent-checkpoints: 1
execution.checkpointing.min-pause: 30000        # min 30s between checkpoint start
```

---

## Exactly-Once End-to-End

Flink's internal exactly-once is guaranteed by checkpoints. For **end-to-end** exactly-once (source → Flink → sink), both source and sink must support it:

| Component | Requirement | Example |
|-----------|-------------|---------|
| **Source** | Replayable from a committed offset | Kafka (committed offset per partition) |
| **Flink internal** | Chandy-Lamport checkpoint | Built-in |
| **Sink** | Idempotent writes OR two-phase commit | Kafka (transactions), Cassandra (idempotent via `IF NOT EXISTS`), JDBC (XA transactions) |

### Two-Phase Commit Sink (Kafka)

```
Checkpoint N starts:
  Flink Kafka Sink begins a Kafka transaction for new records.

Checkpoint N completes:
  Pre-commit: Flink Kafka Sink calls producer.commitTransaction() (phase 1).
  JobManager stores checkpoint metadata including Kafka transaction state.

On recovery:
  If checkpoint N completed → commit Kafka transactions from checkpoint N.
  If checkpoint N incomplete → abort Kafka transactions.
  → Consumer with isolation.level=read_committed never sees aborted records.
```

---

## Backpressure

When a downstream operator is slow, Flink propagates backpressure upstream via the credit-based flow control:

```
Slow Sink → no credits available → Sink Task blocks on write
         → Network buffer pool exhausted for that channel
         → Upstream Window operator: buffer full → blocks on emit
         → Upstream Map operator: blocks → slows source reads
         → Kafka consumer: stops polling → Kafka broker sees no fetch requests

Result: natural throttling without data loss. Observable via Flink Web UI backpressure tab.
```

**Diagnosing backpressure**: Flink UI shows "HIGH" backpressure on the slow operator. The bottleneck is the operator *downstream* of the one showing backpressure (the slow one is blocking its upstream).

---

## FAANG Interview Callout

> "The record flow in Flink is push-based within a TaskManager (operators in the same slot share a thread and pass records directly) and network-buffered between TaskManagers (Netty TCP with credit-based flow control). Backpressure is native — when a sink is slow, it stops granting credits, which propagates upstream until the Kafka consumer stops polling. This is much cleaner than Spark's micro-batch model where a slow batch blocks the next batch. For windows, I prefer `aggregate()` over `apply()` — it maintains only an accumulator per window rather than buffering all events. For state, I register it via `ValueStateDescriptor` in `open()` and Flink automatically snapshots it during checkpoints and restores it on recovery — I never need to manage state persistence manually."
