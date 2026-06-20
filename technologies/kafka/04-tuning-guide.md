# Kafka — Tuning Guide

## Producer Tuning

### Throughput Optimisation

| Parameter | Default | Recommended (High Throughput) | Notes |
|-----------|---------|-------------------------------|-------|
| `batch.size` | 16,384 (16KB) | 131,072–1,048,576 (128KB–1MB) | Larger batches → fewer requests → higher throughput |
| `linger.ms` | 0 | 5–20ms | Wait this long before sending a batch to allow it to fill up |
| `compression.type` | none | `lz4` | LZ4: fast compression (~3x), low CPU overhead; use `snappy` for better ratio on JSON |
| `buffer.memory` | 33,554,432 (32MB) | 67,108,864–268,435,456 (64–256MB) | Total memory for all buffered records; if full, `send()` blocks |
| `max.in.flight.requests.per.connection` | 5 | 5 (with idempotence); 1 (without, for strict ordering) | With `enable.idempotence=true`, 5 in-flight is safe; otherwise set to 1 for strict ordering |

### Durability / Reliability

| Parameter | Default | Safe Production Value | Notes |
|-----------|---------|----------------------|-------|
| `acks` | `1` | `all` | Wait for all ISR replicas; no data loss if any ISR member survives |
| `retries` | `2147483647` | `2147483647` | Combined with idempotence, unlimited retries are safe |
| `delivery.timeout.ms` | 120,000 (2min) | 120,000–300,000 | Total time allowed for a record to be delivered (includes retries) |
| `retry.backoff.ms` | 100 | 100–500 | Exponential backoff between retries |
| `enable.idempotence` | `true` (Kafka 3.0+) | `true` | Deduplicates retried sends using PID + sequence number |
| `transactional.id` | unset | set per producer instance | Required for exactly-once cross-topic atomic writes |

---

## Consumer Tuning

### Throughput Optimisation

| Parameter | Default | Recommended | Notes |
|-----------|---------|-------------|-------|
| `fetch.min.bytes` | 1 | 1,024–10,240 (1KB–10KB) | Broker waits until this many bytes available; reduces requests |
| `fetch.max.wait.ms` | 500 | 500 | Max broker wait time for `fetch.min.bytes`; balance with latency requirements |
| `max.partition.fetch.bytes` | 1,048,576 (1MB) | 1–10MB | Max bytes per partition per fetch; increase for large messages or batch processing |
| `fetch.max.bytes` | 52,428,800 (50MB) | 50–100MB | Max bytes per fetch request across all partitions |
| `max.poll.records` | 500 | 100–2000 | Records per `poll()` call; lower for slow processing; higher for batch processing |

### Session Management (Critical for Stability)

| Parameter | Default | Recommended | Notes |
|-----------|---------|-------------|-------|
| `session.timeout.ms` | 45,000 (45s) | 30,000–60,000 | Consumer removed from group if no heartbeat within window |
| `heartbeat.interval.ms` | 3,000 (3s) | 3,000–10,000 | Must be < 1/3 of `session.timeout.ms` |
| `max.poll.interval.ms` | 300,000 (5min) | 300,000–600,000 | Max time between `poll()` calls; increase for slow processing (DB writes, external API calls) |

**Anti-pattern**: Processing records inside the `poll()` loop for too long triggers a `max.poll.interval.ms` timeout, causing the consumer to be kicked from the group and a rebalance triggered. Fix: offload processing to a thread pool and `poll()` frequently.

### Exactly-Once Consumer

```java
// Manual offset commit after processing
consumer.subscribe(List.of("order-events"));
while (true) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
    for (ConsumerRecord<String, String> record : records) {
        process(record);   // your business logic
    }
    // Commit only after successful processing
    consumer.commitSync();    // blocks; safe but slower
    // OR:
    consumer.commitAsync();   // non-blocking; potential for out-of-order commits on failure
}
```

---

## Broker / Topic Tuning

### Replication & Durability

| Parameter | Default | Recommended | Notes |
|-----------|---------|-------------|-------|
| `default.replication.factor` | 1 | 3 | Never 1 in production; RF=3 tolerates 1 broker failure |
| `min.insync.replicas` | 1 | 2 | Combined with `acks=all`: ensures at least 2 replicas acknowledge |
| `unclean.leader.election.enable` | `false` | `false` | Do NOT enable for critical data; allows lagging replica to become leader → data loss |
| `replica.lag.time.max.ms` | 30,000 | 30,000 | Follower removed from ISR if not caught up within this window |

### Log Retention

| Parameter | Default | Notes |
|-----------|---------|-------|
| `log.retention.hours` | 168 (7 days) | Increase for CDC topics (30+ days); tiered storage for indefinite |
| `log.retention.bytes` | -1 (unlimited) | Set a per-partition cap if disk is constrained |
| `log.segment.bytes` | 1GB | Segment rolled when size exceeds this; smaller = more frequent compaction |
| `log.cleanup.policy` | `delete` | Set to `compact` for changelog/CDC topics; `compact,delete` for both |
| `log.compaction.lag.ms` | 0 | Minimum time a record must remain before eligible for compaction |
| `delete.retention.ms` | 86,400,000 (1 day) | Tombstone records retained this long (for consumers to see the delete) |

### Performance

| Parameter | Default | Recommended | Notes |
|-----------|---------|-------------|-------|
| `num.partitions` | 1 | 10–50 per topic | Default for auto-created topics; set per-topic via create |
| `num.io.threads` | 8 | 8–16 | Disk I/O threads; increase for high-throughput topics |
| `num.network.threads` | 3 | 3–8 | Network handler threads; increase for many simultaneous connections |
| `socket.send.buffer.bytes` | 102,400 (100KB) | 1,048,576 (1MB) | OS socket send buffer |
| `socket.receive.buffer.bytes` | 102,400 (100KB) | 1,048,576 (1MB) | OS socket receive buffer |
| `log.flush.interval.messages` | unset (OS decides) | Do not set | Let the OS flush; setting this reduces throughput dramatically |
| `log.flush.interval.ms` | unset | Do not set | Same — rely on replication for durability, not fsync frequency |

**Critical**: Do NOT configure `log.flush.interval.messages` or `log.flush.interval.ms`. Kafka's durability guarantee comes from replication (ISR), not fsync. Forcing frequent flushes kills throughput with no additional safety (you already have 2+ replicas).

---

## JVM Tuning (Kafka Broker)

```bash
# Recommended JVM flags for broker (from Confluent docs)
KAFKA_HEAP_OPTS="-Xms6g -Xmx6g"
KAFKA_JVM_PERFORMANCE_OPTS="-server \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=20 \
  -XX:InitiatingHeapOccupancyPercent=35 \
  -XX:+ExplicitGCInvokesConcurrent \
  -Djava.awt.headless=true"
```

| Setting | Value | Rationale |
|---------|-------|-----------|
| Heap size | 6GB | Kafka itself doesn't use much heap; large heap for segment metadata and network buffers |
| GC | G1GC | Lower max pause than CMS; `MaxGCPauseMillis=20` targets sub-20ms GC pauses |
| OS page cache | 32GB+ (remaining RAM) | Kafka relies heavily on the OS page cache for hot segment reads — maximize free RAM |

**Rule**: Give Kafka ~6GB heap, give the OS the rest of the RAM as page cache. A broker with 64GB RAM should have 58GB available for page cache.

---

## OS-Level Tuning

```bash
# /etc/sysctl.conf — increase socket buffers
net.core.rmem_max = 134217728       # 128MB
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# File descriptors — Kafka opens many log segment files
ulimit -n 100000                    # set in /etc/security/limits.conf

# Disable swap — Kafka page cache pressure should not swap
vm.swappiness = 1

# Dirty page writeback — allow more dirty pages before writeback
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5
```

**Disk**: Use SSDs (NVMe preferred) for `log.dirs`. Kafka writes sequentially, but compaction and catch-up reads can cause random I/O. Separate log and ZooKeeper/KRaft data onto different disks.

---

## Anti-Patterns and Pitfalls

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| **Too many small messages** | High per-record overhead; low throughput | Batch at producer (`linger.ms=20`, `batch.size=256KB`) or aggregate before producing |
| **Large messages (> 1MB)** | High network overhead; large partition files; risk of OOM in consumer | Store blobs in S3/GCS; put reference URL in Kafka |
| **Using Kafka as a database** | No efficient key lookup; retention is time-based not count-based | Use it for streaming; write to a real DB (Cassandra, PostgreSQL) for durable state |
| **Not monitoring consumer lag** | Consumer falls behind silently; system appears healthy until lag causes issues | Alert on lag > threshold (e.g., > 5 minutes of data) AND lag-growing rate |
| **Setting `auto.offset.reset=latest` in production** | New consumer group skips all historical data | Use `earliest` for new consumers that need history; `latest` only for genuinely real-time consumers |
| **Not setting `group.id`** | Each consumer instance creates its own group → reads all partitions independently | Always set `group.id` for consumer groups |
| **Single partition per topic** | Limits throughput; single point of contention | Use at least 10 partitions; size based on throughput and consumer parallelism |
| **`log.flush.interval.messages=1`** | fsync on every write — destroys throughput | Remove this setting; rely on ISR replication for durability |
| **Underreplicating (RF=1)** | Single broker failure = data loss | Always RF=3 in production |
| **Consumer blocking in poll loop** | Triggers rebalance; cascades into more rebalances | Process async; poll frequently; increase `max.poll.interval.ms` if batch processing |
| **Ignoring ISR shrinkage alerts** | ISR at 1 = one more failure causes unavailability | Alert when ISR size < replication factor |

---

## Partition Sizing Calculator

```
# Given:
target_write_throughput = 500 MB/s
throughput_per_partition = 50 MB/s   (conservative for commodity hardware)
max_consumers = 50                   (peak processing parallelism needed)

# Calculate:
partitions_for_throughput = ceil(500 / 50) = 10
partitions_for_consumers  = 50

# Take the max:
recommended_partitions = max(10, 50) = 50

# Add headroom (20%):
final_partitions = 60
```

---

## FAANG Interview Callout

> "The most important producer tuning is `linger.ms` + `batch.size` — these two parameters control the throughput/latency trade-off. For analytics/logging workloads where 10ms extra latency is fine, I set `linger.ms=20` and `batch.size=256KB` with LZ4 compression — this can improve throughput 10x over defaults. For consumer stability, the most dangerous misconfiguration is not handling the `max.poll.interval.ms` timeout — if processing a batch takes longer than 5 minutes, the consumer is kicked from the group and a rebalance fires, causing other consumers to pause. The fix is to either increase `max.poll.interval.ms` or reduce `max.poll.records`. The anti-pattern I always flag in design reviews is `log.flush.interval.messages=1` — teams do this thinking it's safer, but it destroys throughput and doesn't add safety if you already have RF=3 with `acks=all`."
