# Kafka — Read/Write Path

## Producer Write Path

```
Producer Application
       │
       │  1. Serialize key/value (configured serializer)
       │  2. Determine target partition
       │     - Key present → hash(key) % numPartitions
       │     - No key      → round-robin / sticky partition (batch fills up)
       │
       ▼
  RecordAccumulator (in-memory buffer)
  ┌────────────────────────────────────────────────────┐
  │  Partition 0 batch: [rec0, rec1, rec2, ...]         │
  │  Partition 1 batch: [rec3, rec4, ...]               │  ← batch.size = 16KB (default)
  │  Partition 2 batch: [rec5, ...]                     │  ← linger.ms = 0ms (default)
  └────────────────────────────────────────────────────┘
       │
       │  3. Sender thread flushes batch when:
       │     - batch.size reached, OR
       │     - linger.ms elapsed
       │
       ▼
  Kafka Broker (Partition Leader)
  ┌────────────────────────────────────────────────────┐
  │  4. Validate CRC, check leader status               │
  │  5. Append to OS page cache (sequential write)      │
  │  6. Replicate to ISR followers                      │
  │  7. Send ack to producer (when acks=all: wait for   │
  │     all ISR members to acknowledge)                 │
  └────────────────────────────────────────────────────┘
       │
       ▼
  OS Page Cache → Segment File (fdatasync on flush.ms or flush.messages)
```

### Producer Configuration: Durability vs Throughput Trade-offs

| Config | Safe Value | High-Throughput Value | Trade-off |
|--------|-----------|----------------------|-----------|
| `acks` | `all` | `1` | `all` = no data loss; `1` = faster but lose in-flight msgs if leader dies |
| `min.insync.replicas` | `2` | `1` | `2` = survives 1 broker failure; `1` = loses data if leader dies before replication |
| `linger.ms` | `5–20ms` | `0` | Delay allows larger batches → higher throughput; `0` = lowest latency |
| `batch.size` | `64KB–1MB` | `1MB` | Larger batches = better compression + fewer requests |
| `compression.type` | `lz4` or `snappy` | `lz4` | ~3–5x compression on JSON; LZ4 fastest; Snappy better ratio |
| `buffer.memory` | `64MB` | `256MB` | Accumulator pool; if full, `send()` blocks for `max.block.ms` |
| `retries` | `Integer.MAX_VALUE` | `Integer.MAX_VALUE` | Combined with idempotence, retries are safe without duplicates |
| `enable.idempotence` | `true` | `true` | Deduplicates retried sends using producer ID + sequence number |

### Idempotent Producer

Without idempotence, a retry after a network timeout can produce a duplicate:

```
Producer sends record → Network timeout → Producer retries → Broker wrote both → DUPLICATE
```

With `enable.idempotence=true`, each record has a `(ProducerID, SequenceNumber)`. The broker deduplicates:

```
Producer (PID=42) sends: seq=5, value="order_placed"
Network timeout
Producer retries:          seq=5, value="order_placed"   ← broker recognises seq=5 already written → drops
```

The broker maintains a window of the last 5 sequence numbers per producer per partition. Exactly-once **within a session** (PID resets on producer restart; combine with transactions for cross-session exactly-once).

### Exactly-Once via Transactions

```java
producer.initTransactions();
try {
    producer.beginTransaction();
    producer.send(new ProducerRecord<>("output-topic", key, processedValue));
    consumer.commitSync(offsetsToCommit);          // atomic: commit offset + produce in one txn
    producer.sendOffsetsToTransaction(offsetsToCommit, consumerGroupMetadata);
    producer.commitTransaction();
} catch (ProducerFencedException e) {
    producer.close();    // another instance of same transactional.id took over
} catch (KafkaException e) {
    producer.abortTransaction();
}
```

Transactions guarantee that the output record and the input offset commit are **atomic** — either both happen or neither does. This is the foundation of Kafka Streams' exactly-once processing semantics (EOS).

---

## Broker Storage: Log Segments

Each partition on a broker is a directory of log segment files:

```
/kafka-logs/order-events-0/
  00000000000000000000.log          active segment: offset 0 → N-1
  00000000000000000000.index        sparse offset index (offset → byte position)
  00000000000000000000.timeindex    time index (timestamp → offset)
  00000000001073741824.log          closed segment: offset 1,073,741,824+
  ...
```

### Log Segment Roll

A new segment is created when:
- Active segment exceeds `log.segment.bytes` (default 1GB)
- Active segment is older than `log.roll.ms` (default 7 days)

Closed segments become eligible for compaction or deletion based on retention policy.

### Offset Index (Sparse Index)

Kafka does **not** maintain a dense index (one entry per record). It keeps a **sparse index** — one entry every `log.index.interval.bytes` (default 4KB). To find offset N:

```
1. Binary search index file → find closest lower entry (e.g., offset 95 → byte 12,480)
2. Scan log file forward from byte 12,480 until offset N found
```

This keeps index files small (< 10MB for billion-record partitions) while bounding scan cost.

### Zero-Copy Optimization

Kafka uses the OS `sendfile()` / `transferTo()` syscall to send segment data to consumers:

```
Normal path (no zero-copy):
  Disk → OS page cache → kernel buffer → user buffer → socket buffer → NIC
                         (2 kernel↔user copies)

Kafka zero-copy (sendfile):
  Disk → OS page cache → socket buffer → NIC
                         (0 kernel↔user copies)
```

This is why Kafka can saturate network bandwidth with minimal CPU — the OS handles all data movement. Combined with sequential disk I/O (sequential reads are as fast as memory on modern SSDs), Kafka achieves GB/s throughput per broker.

---

## Consumer Read Path

Kafka consumers use a **pull model** — they request batches from brokers rather than having messages pushed.

```
Consumer Application
       │
       │  1. KafkaConsumer.poll(timeout)
       │
       ▼
  Consumer Coordinator (GroupCoordinator broker)
  ┌─────────────────────────────────────────────┐
  │  - Partition assignment (which partitions   │
  │    this consumer instance owns)             │
  │  - Heartbeat tracking (session.timeout.ms)  │
  │  - Rebalance trigger on join/leave          │
  └─────────────────────────────────────────────┘
       │
       │  2. Fetch request to each partition's leader broker
       │     FetchRequest { topicPartition, offset, maxBytes=1MB }
       │
       ▼
  Partition Leader Broker
  ┌─────────────────────────────────────────────┐
  │  3. Read from page cache (if warm) or disk  │
  │  4. Return batch up to fetch.max.bytes      │
  │     (blocks for fetch.min.bytes if empty,   │
  │      up to fetch.max.wait.ms)               │
  └─────────────────────────────────────────────┘
       │
       ▼
  Consumer Application
  4. Deserialize records
  5. Process records
  6. Commit offset (manual or auto)
```

### Consumer Fetch Configuration

| Config | Default | Tuning Guidance |
|--------|---------|----------------|
| `fetch.min.bytes` | 1 byte | Increase to 1KB–10KB for batch consumers to reduce request overhead |
| `fetch.max.wait.ms` | 500ms | Max time broker waits to accumulate `fetch.min.bytes` |
| `max.partition.fetch.bytes` | 1MB | Max bytes returned per partition per request |
| `max.poll.records` | 500 | Records returned per `poll()` call; lower for slow processing to avoid session timeout |
| `max.poll.interval.ms` | 5 min | Max time between `poll()` calls; if exceeded, consumer is removed from group and rebalance triggers |
| `session.timeout.ms` | 45s | Heartbeat timeout; consumer removed if no heartbeat within this window |
| `heartbeat.interval.ms` | 3s | Should be 1/3 of `session.timeout.ms` |

### Consumer Lag

**Consumer lag** = latest offset in partition − committed offset of consumer group.

```
Partition 0:  latest offset = 10,000
Consumer lag: committed offset = 9,800
              lag = 200 records

Lag monitoring:
  kafka-consumer-groups.sh --describe --group analytics-service
  JMX: kafka.consumer.consumer-fetch-manager-metrics.records-lag-max
  Prometheus: kafka_consumer_group_lag (via kafka-exporter or Confluent Control Center)
```

Healthy lag = near-zero for real-time consumers. Acceptable lag = < 1 minute of messages. Alert threshold: lag growing (not just absolute value — a flat lag is acceptable if the consumer is keeping pace).

---

## Log Compaction

For topics where only the **latest value per key** matters (e.g., user profile updates, database CDC), use log compaction instead of time-based deletion:

```
Before compaction:
  offset: 0  key=user:1  value={"name":"Alice","city":"NY"}
  offset: 1  key=user:2  value={"name":"Bob","city":"LA"}
  offset: 2  key=user:1  value={"name":"Alice","city":"SF"}   ← update
  offset: 3  key=user:3  value={"name":"Carol","city":"Chicago"}
  offset: 4  key=user:2  value=null                           ← tombstone (delete)
  offset: 5  key=user:1  value={"name":"Alice","city":"Austin"} ← latest

After compaction (tail is preserved, head is cleaned):
  offset: 2  key=user:1  value={"name":"Alice","city":"SF"}   ← kept (not yet superseded at compaction time)
  offset: 3  key=user:3  value={"name":"Carol","city":"Chicago"}
  offset: 5  key=user:1  value={"name":"Alice","city":"Austin"} ← latest value kept
```

Log compaction runs in the background via the Log Cleaner thread. It processes the "dirty" (uncompacted) tail of the log, building a map of key → latest offset, then rewrites cleaned segments.

**Use cases for compaction**:
- Kafka Streams state changelog topics (restore processor state on restart)
- CDC source topics (downstream consumers can reconstruct current state)
- Configuration / feature flag topics (always want the latest value)

---

## FAANG Interview Callout

> "On the write path, the producer batches records in the RecordAccumulator, then the sender thread flushes to the partition leader. With `acks=all`, the leader waits for all ISR replicas to write before acknowledging — this is the durability guarantee. Kafka uses the OS page cache and sequential writes, which is why throughput is so high. On the read path, consumers pull batches via a fetch request that blocks until `fetch.min.bytes` is available — this is natural backpressure. Zero-copy via `sendfile()` means broker CPU is near-zero for reads. The key operational metric is consumer lag — if lag is growing, consumers can't keep up with producers. The fix is usually to add partitions and scale consumer instances proportionally."

---

## Related Files

| File | Topic |
|------|-------|
| [01-architecture.md](01-architecture.md) | Brokers, partitions, ISR, consumer groups |
| [04-tuning-guide.md](04-tuning-guide.md) | Detailed parameter reference and anti-patterns |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | Exactly-once semantics comparison across systems |
