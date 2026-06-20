# Kafka Streams — Tuning Guide

## Core Application Configuration

| Parameter | Default | Recommended | Notes |
|-----------|---------|-------------|-------|
| `application.id` | (required) | Unique per app | Used as Kafka consumer group ID and prefix for internal topics |
| `bootstrap.servers` | (required) | All brokers | Comma-separated list |
| `num.stream.threads` | 1 | `num_cpu_cores / 2` to `num_cpu_cores` | Threads per instance; each thread handles 1+ tasks |
| `processing.guarantee` | `at_least_once` | `exactly_once_v2` | For any data where duplicates matter |
| `commit.interval.ms` | 30000 (at-least-once) / 100 (EOS) | 100–1000ms | How often offsets and state are committed; lower = less reprocessing on restart |
| `replication.factor` | 1 | 3 | Replication factor for internal topics (repartition, changelog) |
| `num.standby.replicas` | 0 | 1–2 | Pre-warm state on standby instances; dramatically reduces failover time |
| `acceptable.recovery.lag` | 10000 | 0 (strict) or 10000 | Max lag a standby can have and still be considered for active assignment |

---

## State Store and RocksDB Tuning

### RocksDB Configuration

Kafka Streams exposes RocksDB configuration via `RocksDBConfigSetter`:

```java
public class CustomRocksDBConfig implements RocksDBConfigSetter {
    @Override
    public void setConfig(String storeName, Options options, Map<String, Object> configs) {
        BlockBasedTableConfig tableConfig = new BlockBasedTableConfig();
        tableConfig.setBlockCacheSize(256 * 1024 * 1024L);   // 256MB block cache per store
        tableConfig.setBlockSize(16 * 1024L);                 // 16KB block size
        tableConfig.setFilterPolicy(new BloomFilter(10, false)); // bloom filter for point lookups

        options.setTableFormatConfig(tableConfig);
        options.setWriteBufferSize(64 * 1024 * 1024L);        // 64MB write buffer
        options.setMaxWriteBufferNumber(3);                    // up to 3 write buffers
        options.setMaxBackgroundJobs(4);                       // background compaction threads
        options.setCompressionType(CompressionType.LZ4_COMPRESSION); // LZ4 for speed
        options.setBottommostCompressionType(CompressionType.ZSTD_COMPRESSION); // ZSTD for oldest data
    }
}

// Register in config:
props.put(StreamsConfig.ROCKSDB_CONFIG_SETTER_CLASS_CONFIG, CustomRocksDBConfig.class);
```

| Parameter | Recommended | Notes |
|-----------|-------------|-------|
| Block cache | 256MB–2GB per store | Keeps hot state in memory; reduce disk I/O |
| Write buffer | 64–256MB | Larger = fewer L0 files = fewer compactions |
| Max write buffers | 2–4 | Buffers before RocksDB flushes to L0 |
| Bloom filter | 10 bits/key | Eliminates disk read for non-existent keys |
| Background jobs | 4 | Compaction threads; increase for write-heavy stores |
| Compression | LZ4 for upper levels, ZSTD for bottommost | LZ4 = fast; ZSTD = better ratio for cold data |

### Record Cache

Kafka Streams maintains an in-memory **record cache** per stream thread, used to deduplicate state store updates before flushing:

```properties
# Total cache across all stores per thread (default 10MB)
statestore.cache.max.bytes=104857600   # 100MB per thread
```

The cache reduces:
- RocksDB writes (deduplicates rapid updates to the same key)
- Changelog topic produces (fewer records = cheaper Kafka writes)
- Downstream KTable update frequency (batches updates before emitting)

**Trade-off**: larger cache = fewer downstream KTable updates per commit interval (higher latency for downstream consumers of the changelog). For low-latency KTable subscriptions, reduce cache or set `commit.interval.ms` lower.

---

## Throughput Tuning

### Producer Configuration (for output and changelog)

```properties
# Configure internal producer via StreamsConfig
producerPrefix(ProducerConfig.ACKS_CONFIG)=all
producerPrefix(ProducerConfig.COMPRESSION_TYPE_CONFIG)=lz4
producerPrefix(ProducerConfig.BATCH_SIZE_CONFIG)=65536      # 64KB
producerPrefix(ProducerConfig.LINGER_MS_CONFIG)=5
```

### Consumer Configuration (for input)

```properties
consumerPrefix(ConsumerConfig.FETCH_MIN_BYTES_CONFIG)=65536   # wait for 64KB
consumerPrefix(ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG)=500
consumerPrefix(ConsumerConfig.MAX_POLL_RECORDS_CONFIG)=1000
```

### Maximising Throughput

```
Total throughput = num.stream.threads × throughput_per_thread
Throughput per thread = limited by: processing speed, state store access speed, output Kafka write speed

Bottleneck diagnosis:
  CPU bound → increase num.stream.threads (up to num_cores)
  RocksDB bound → increase block cache; add SSD; reduce state per key
  Output Kafka bound → increase producer batch size and linger.ms
  Input Kafka bound → increase max.poll.records and fetch.min.bytes
```

---

## Standby Replicas and Failover

```properties
num.standby.replicas=1
```

With 1 standby:
- The Streams client assigns a second instance to shadow each active task
- The standby instance consumes the changelog topic continuously, maintaining a near-current copy of RocksDB
- On active instance failure, the standby is promoted — RocksDB is already warm → failover completes in seconds vs minutes

```
Active instance (Task 0 — order-count-store):
  Local RocksDB: user:1=42, user:2=17, user:3=99
  Changelog: offset=5000 (fully caught up)

Standby instance (Task 0 standby):
  Local RocksDB: user:1=42, user:2=17, user:3=99
  Changelog: offset=4998 (2 records behind — near real-time)

Active crashes:
  Standby is assigned Task 0
  Replays 2 changelog records (ms)
  Resumes consuming order-events[0] from committed offset
  Recovery: < 5 seconds
```

**Without standby** (default): new instance must replay entire changelog from offset 0 → can take minutes for large state.

---

## Partition and Scaling Guidelines

### Scaling Rule

```
Max parallel instances = num_partitions_of_input_topic

If you have 12 partitions:
  1 instance, 12 stream threads   → 12 tasks per instance
  4 instances, 3 stream threads   → 3 tasks per instance
  12 instances, 1 stream thread   → 1 task per instance (max parallelism)
  13+ instances                   → extra instances are idle (no tasks to assign)
```

### When to Repartition

If a join or aggregation requires a different key than the input topic's key:

```java
// This selectKey triggers an internal repartition topic:
stream.selectKey((k, v) -> v.getUserId())   // was keyed by orderId
      .join(userTable, ...);

// Repartition topic: "my-app-stream-name-repartition"
// Partition count = input topic partition count
// Cost: one extra Kafka write + read per record
```

Minimise repartitions: design your input topic partition key to align with your primary join/group-by key.

---

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| **`num.stream.threads=1` always** | Underutilises CPU; single thread bottleneck | Set to num_cores/2 to num_cores |
| **Missing `num.standby.replicas`** | Failover triggers full changelog replay (minutes) | Set to 1 in production |
| **Unbounded state without TTL** | State grows forever; disk exhaustion | Use windowed stores; implement `punctuate()` cleanup |
| **KStream-KTable join without co-partitioning** | Runtime TopologyException | Ensure both topics have same partition count and key partitioner |
| **Blocking calls in process()** | Stalls the stream thread; backpressure to Kafka | Use async pattern: produce to a side topic; consume response asynchronously |
| **GlobalKTable for large tables** | Every instance loads the full table → OOM | Use KTable for large tables; GlobalKTable only for small reference data (< 100MB) |
| **Not naming state stores** | Cannot reference store for interactive queries | Always name stores: `Materialized.as("store-name")` |
| **Small `statestore.cache.max.bytes`** | Excessive RocksDB writes; excessive changelog produce | Increase to 64–256MB per stream thread |
| **`replication.factor=1` for internal topics** | Internal topic (changelog, repartition) data loss on broker failure | Set `replication.factor=3` |
| **`commit.interval.ms` too high** | On crash, reprocesses more records (up to interval window) | Keep at 100–1000ms; balance with throughput overhead |

---

## Monitoring: Key Metrics

| Metric | JMX MBean | Alert Condition |
|--------|-----------|----------------|
| `process-rate` | `kafka.streams:type=stream-metrics,client-id=...` | Drop → bottleneck or error |
| `commit-rate` | stream-metrics | < expected rate → commit stalling |
| `poll-rate` | consumer metrics | Low → consumer is blocked |
| `restore-consumer-records-lag` | stream-task-metrics | > 0 during steady-state → standby catching up |
| `record-e2e-latency-avg` | task metrics | Growing → downstream backpressure |
| `rocksdb-bytes-written-rate` | rocksdb-state-metrics | Very high → too many state writes; tune cache |
| Consumer group lag | Kafka broker | Growing → instances can't keep up with input rate |
| JVM GC pause time | JVM metrics | > 200ms → GC pressure from large heap usage |

```bash
# Check Kafka Streams consumer group lag
kafka-consumer-groups.sh \
  --bootstrap-server broker:9092 \
  --describe \
  --group my-streams-app
```

---

## JVM Tuning

```bash
# Kafka Streams runs in your application's JVM
# Recommended for large-state applications:
-Xms2g -Xmx2g                          # Fix heap size; avoid expansion GC
-XX:+UseG1GC
-XX:MaxGCPauseMillis=20
-XX:InitiatingHeapOccupancyPercent=35

# RocksDB is off-heap — heap size does NOT need to be large for state
# Heap mostly used for: network buffers, deserialized records in flight, application objects
# Rule: 1–4GB heap for most applications; allocate remaining RAM to OS page cache (changelog reads)
```

---

## FAANG Interview Callout

> "The most impactful Kafka Streams tuning is `num.standby.replicas=1` — without it, a failed instance can mean minutes of changelog replay before a task is reassigned. With standby, the replacement instance has the state pre-warmed and is back in seconds. The second most important tuning is the record cache (`statestore.cache.max.bytes`): increasing it from the default 10MB to 64–256MB per stream thread dramatically reduces RocksDB write amplification and changelog produce rate. For throughput, I scale `num.stream.threads` to match CPU cores and ensure input partition count ≥ target concurrency. The anti-pattern I always flag: using GlobalKTable for a large reference dataset — it replicates the full dataset to every instance, which causes OOM. Use KTable for anything > 100MB; reserve GlobalKTable for small lookup tables like country codes or feature flags."
