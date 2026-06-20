# Snowflake ID (Distributed Unique ID Generator)
**Category**: Distributed Counter / ID Generation — monotonically increasing, globally unique, k-sortable IDs without coordination; invented by Twitter, adopted everywhere

---

## 1. The Problem It Solves

### Unique IDs at Scale Without a Bottleneck

Every entity in a distributed system needs a unique ID: tweets, orders, users, events. Options:

```
UUID v4:     128-bit random → globally unique, zero coordination
             Problem: random → no sort order, poor B+ tree insert locality
             "Hot spot" on index: every insert lands at a random leaf → page splits everywhere

Auto-increment (MySQL sequence):
             Simple, sortable, compact
             Problem: single point of failure, bottleneck at 100K+ inserts/sec
             Can't be generated client-side

Redis INCR:  Fast, sortable
             Problem: single node, or needs coordination across nodes, still a bottleneck

Snowflake:   64-bit integer, monotonically increasing per node, sortable by time
             Generated locally by any node — zero network coordination
             Fits in a long, sorts in B+ trees efficiently
```

**Snowflake gives you UUID's decentralisation plus auto-increment's sort order.**

---

## 2. Snowflake Bit Layout (Twitter, 2010)

```
 63        22 21      12 11       0
 ┌──────────┬──────────┬──────────┐
 │ timestamp│ machine  │ sequence │
 │ 41 bits  │ 10 bits  │ 12 bits  │
 └──────────┴──────────┴──────────┘
 ^
 sign bit = 0 (always positive long)

Total: 1 + 41 + 10 + 12 = 64 bits
```

### 2.1 Timestamp (41 bits)

- Milliseconds since a custom epoch (Twitter uses `2010-11-04T01:42:54.657Z`)
- 41 bits → 2^41 ms ≈ **69 years** before overflow (Twitter's epoch → ~2080)
- Monotonically increasing → IDs sort chronologically

### 2.2 Machine ID (10 bits)

- Identifies the generating node
- 2^10 = **1024 distinct nodes** can generate IDs simultaneously
- Typically split: 5 bits datacenter + 5 bits worker within datacenter

### 2.3 Sequence (12 bits)

- Counter that resets to 0 each millisecond
- 2^12 = **4096 IDs per millisecond per node**
- If exhausted within 1ms: wait until the next millisecond tick

### 2.4 Throughput

```
Single node:  4096 IDs/ms = 4,096,000 IDs/sec
1024 nodes:   4,096,000 × 1024 = ~4.2 billion IDs/sec globally
```

---

## 3. Java Implementation

### 3.1 Core Snowflake Generator

```java
public class SnowflakeIdGenerator {

    // Twitter's epoch: 2010-11-04T01:42:54.657Z
    private static final long EPOCH = 1288834974657L;

    private static final int MACHINE_ID_BITS  = 10;
    private static final int SEQUENCE_BITS    = 12;

    private static final long MAX_MACHINE_ID  = ~(-1L << MACHINE_ID_BITS);  // 1023
    private static final long MAX_SEQUENCE    = ~(-1L << SEQUENCE_BITS);     // 4095

    private static final int MACHINE_ID_SHIFT = SEQUENCE_BITS;              // 12
    private static final int TIMESTAMP_SHIFT  = SEQUENCE_BITS + MACHINE_ID_BITS; // 22

    private final long machineId;
    private long lastTimestamp = -1L;
    private long sequence = 0L;

    public SnowflakeIdGenerator(long machineId) {
        if (machineId < 0 || machineId > MAX_MACHINE_ID)
            throw new IllegalArgumentException("machineId must be 0–" + MAX_MACHINE_ID);
        this.machineId = machineId;
    }

    public synchronized long nextId() {
        long now = currentMs();

        if (now < lastTimestamp)
            throw new IllegalStateException(
                "Clock moved backward by " + (lastTimestamp - now) + "ms — refusing to generate ID");

        if (now == lastTimestamp) {
            sequence = (sequence + 1) & MAX_SEQUENCE;
            if (sequence == 0) now = waitNextMs(lastTimestamp); // sequence exhausted, spin
        } else {
            sequence = 0;
        }

        lastTimestamp = now;

        return ((now - EPOCH) << TIMESTAMP_SHIFT)
             | (machineId   << MACHINE_ID_SHIFT)
             | sequence;
    }

    private long waitNextMs(long lastMs) {
        long ms = currentMs();
        while (ms <= lastMs) ms = currentMs();
        return ms;
    }

    private long currentMs() { return System.currentTimeMillis(); }

    // --- Decompose an existing Snowflake ID ---

    public static long extractTimestamp(long id) {
        return (id >> TIMESTAMP_SHIFT) + EPOCH;
    }

    public static long extractMachineId(long id) {
        return (id >> MACHINE_ID_SHIFT) & MAX_MACHINE_ID;
    }

    public static long extractSequence(long id) {
        return id & MAX_SEQUENCE;
    }

    public static java.time.Instant extractInstant(long id) {
        return java.time.Instant.ofEpochMilli(extractTimestamp(id));
    }
}
```

### 3.2 Datacenter + Worker Split (Sonyflake / Discord style)

```java
public class SnowflakeIdGeneratorDC {

    private static final long EPOCH              = 1420070400000L; // 2015-01-01

    private static final int  DC_BITS            = 5;
    private static final int  WORKER_BITS        = 5;
    private static final int  SEQUENCE_BITS      = 12;

    private static final long MAX_DC_ID          = ~(-1L << DC_BITS);       // 31
    private static final long MAX_WORKER_ID      = ~(-1L << WORKER_BITS);   // 31
    private static final long MAX_SEQUENCE       = ~(-1L << SEQUENCE_BITS); // 4095

    private static final int WORKER_SHIFT        = SEQUENCE_BITS;
    private static final int DC_SHIFT            = SEQUENCE_BITS + WORKER_BITS;
    private static final int TIMESTAMP_SHIFT     = DC_SHIFT + DC_BITS;

    private final long datacenterId;
    private final long workerId;
    private long lastTimestamp = -1L;
    private long sequence      = 0L;

    public SnowflakeIdGeneratorDC(long datacenterId, long workerId) {
        if (datacenterId < 0 || datacenterId > MAX_DC_ID)
            throw new IllegalArgumentException("datacenterId must be 0–" + MAX_DC_ID);
        if (workerId < 0 || workerId > MAX_WORKER_ID)
            throw new IllegalArgumentException("workerId must be 0–" + MAX_WORKER_ID);
        this.datacenterId = datacenterId;
        this.workerId = workerId;
    }

    public synchronized long nextId() {
        long now = System.currentTimeMillis();

        if (now < lastTimestamp)
            throw new ClockBackwardsException(lastTimestamp - now);

        if (now == lastTimestamp) {
            sequence = (sequence + 1) & MAX_SEQUENCE;
            if (sequence == 0) {
                while ((now = System.currentTimeMillis()) <= lastTimestamp) Thread.onSpinWait();
            }
        } else {
            sequence = 0;
        }

        lastTimestamp = now;

        return ((now - EPOCH)    << TIMESTAMP_SHIFT)
             | (datacenterId     << DC_SHIFT)
             | (workerId         << WORKER_SHIFT)
             | sequence;
    }

    public static class ClockBackwardsException extends RuntimeException {
        public ClockBackwardsException(long driftMs) {
            super("Clock moved backward by " + driftMs + "ms");
        }
    }
}
```

### 3.3 Thread-Safe Pool (multiple generators per JVM)

```java
import java.util.concurrent.atomic.AtomicInteger;

public class SnowflakePool {

    private final SnowflakeIdGenerator[] workers;
    private final AtomicInteger roundRobin = new AtomicInteger(0);

    public SnowflakePool(long baseWorkerId, int poolSize) {
        this.workers = new SnowflakeIdGenerator[poolSize];
        for (int i = 0; i < poolSize; i++) {
            workers[i] = new SnowflakeIdGenerator(baseWorkerId + i);
        }
    }

    public long nextId() {
        int idx = Math.abs(roundRobin.getAndIncrement() % workers.length);
        return workers[idx].nextId();
    }
}
```

### 3.4 Worker ID Assignment — ZooKeeper Coordination

```java
import org.apache.curator.framework.CuratorFramework;
import org.apache.curator.framework.recipes.atomic.AtomicValue;
import org.apache.curator.framework.recipes.atomic.DistributedAtomicInteger;
import org.apache.curator.retry.ExponentialBackoffRetry;

public class ZookeeperWorkerIdAssigner {

    private static final String WORKER_ID_PATH = "/snowflake/worker-ids";
    private static final int MAX_WORKER_ID = 1023;

    private final CuratorFramework curator;

    public ZookeeperWorkerIdAssigner(CuratorFramework curator) {
        this.curator = curator;
    }

    public long assignWorkerId(String serviceInstanceId) throws Exception {
        // Persistent node: serviceInstanceId → workerId mapping
        String nodePath = WORKER_ID_PATH + "/" + serviceInstanceId;
        byte[] existing = null;

        try { existing = curator.getData().forPath(nodePath); } catch (Exception ignored) {}

        if (existing != null) {
            // Reuse previously assigned workerId (handles restarts)
            return Long.parseLong(new String(existing));
        }

        // Claim next available workerId atomically
        DistributedAtomicInteger counter = new DistributedAtomicInteger(
            curator, WORKER_ID_PATH + "/counter",
            new ExponentialBackoffRetry(100, 3));

        AtomicValue<Integer> result = counter.increment();
        if (!result.succeeded())
            throw new RuntimeException("Failed to increment worker ID counter");

        long workerId = result.postValue() % (MAX_WORKER_ID + 1);

        // Persist mapping
        curator.create().creatingParentsIfNeeded()
            .forPath(nodePath, Long.toString(workerId).getBytes());

        return workerId;
    }
}
```

### 3.5 Benchmark Harness

```java
import java.util.concurrent.*;

public class SnowflakeBenchmark {

    public static void main(String[] args) throws Exception {
        SnowflakeIdGenerator gen = new SnowflakeIdGenerator(1);
        int threads = 8;
        int idsPerThread = 1_000_000;

        ExecutorService pool = Executors.newFixedThreadPool(threads);
        ConcurrentHashMap<Long, Boolean> seen = new ConcurrentHashMap<>(threads * idsPerThread);

        long start = System.nanoTime();
        CountDownLatch latch = new CountDownLatch(threads);

        for (int t = 0; t < threads; t++) {
            pool.submit(() -> {
                try {
                    for (int i = 0; i < idsPerThread; i++) {
                        long id = gen.nextId();
                        if (seen.put(id, Boolean.TRUE) != null)
                            throw new RuntimeException("DUPLICATE ID: " + id);
                    }
                } finally {
                    latch.countDown();
                }
            });
        }

        latch.await();
        long elapsed = System.nanoTime() - start;
        System.out.printf("Generated %,d IDs in %.2fs = %,.0f IDs/sec%n",
            (long) threads * idsPerThread,
            elapsed / 1e9,
            threads * idsPerThread / (elapsed / 1e9));
        System.out.println("All IDs unique: " + (seen.size() == threads * idsPerThread));
        pool.shutdown();
    }
}
```

---

## 4. Variants at Other Companies

### 4.1 Instagram's ID (2012)

Instagram uses PostgreSQL sequences but sharded across logical shards. Each ID encodes:

```
63 bits total:
  [41 bits: ms since epoch]
  [13 bits: shard ID]      ← logical shard, not machine
  [10 bits: sequence]

Generation: PL/pgSQL function on each shard's Postgres instance
  → No central coordinator; each shard independently generates its range
  → All IDs for a user land on the same shard (shard_id derived from user_id)
```

### 4.2 Discord's Snowflake

Discord modified Twitter's layout slightly:

```
64 bits:
  [42 bits: ms since Discord epoch (2015-01-01)]
  [10 bits: internal worker ID]
  [12 bits: sequence]

Notable: Discord uses 42-bit timestamp (vs Twitter's 41) → 139 years before overflow
```

### 4.3 Sonyflake (Sony, Go)

```
63 bits:
  [39 bits: 10ms units since epoch] → 174 years range
  [8 bits:  sequence]               → 256 IDs per 10ms
  [16 bits: machine ID]             → 65536 machines

Trade-off: more machines (65536 vs 1024) but lower per-node throughput (25600 IDs/sec vs 4M IDs/sec)
Use case: IoT / many small devices, not high-throughput web services
```

### 4.4 UUID v7 (RFC 9562, 2024)

```
128 bits:
  [48 bits: Unix timestamp ms]  ← time-ordered!
  [4 bits:  version = 7]
  [12 bits: sub-ms precision]
  [2 bits:  variant]
  [62 bits: random]

Sortable + globally unique without coordination
No machine ID — relies on randomness for uniqueness within same ms
Compatible with UUID type columns
```

```java
import java.util.UUID;

public class UUIDv7 {

    public static UUID generate() {
        long ms = System.currentTimeMillis();
        long msHigh = ms << 16;                        // top 48 bits = timestamp
        long rand1  = (long)(Math.random() * 0x0FFF);  // 12-bit sub-ms
        long rand2  = (long)(Math.random() * Long.MAX_VALUE);

        long msb = msHigh | 0x7000L | rand1;           // version = 7
        long lsb = 0x8000000000000000L | (rand2 & 0x3FFFFFFFFFFFFFFFL); // variant = 10b

        return new UUID(msb, lsb);
    }

    // Timestamp extraction
    public static long extractTimestamp(UUID uuid) {
        return uuid.getMostSignificantBits() >>> 16;
    }
}
```

---

## 5. Clock Drift and Clock Backwards Problem

The most dangerous edge case in Snowflake: **NTP clock correction** can move the system clock backwards.

### 5.1 Detection

```java
if (now < lastTimestamp) {
    // Clock moved backward — options:
    // 1. Throw exception (Twitter's approach): fail loudly, operator must fix NTP
    // 2. Wait it out: sleep until clock catches up (only safe for small drifts)
    // 3. Use sequence extension: temporarily borrow sequence bits for extra drift bits
}
```

### 5.2 Clock Extension Strategy (Boundary-safe)

```java
public class ClockDriftSafeGenerator {

    private static final long EPOCH = 1288834974657L;
    private static final int  MAX_DRIFT_MS = 50; // tolerate up to 50ms backward drift

    private long lastTimestamp = -1L;
    private long sequence = 0L;
    private long driftOffset = 0L; // added to make IDs monotonic during drift

    public synchronized long nextId() {
        long now = System.currentTimeMillis();

        if (now < lastTimestamp) {
            long drift = lastTimestamp - now;
            if (drift > MAX_DRIFT_MS)
                throw new IllegalStateException("Clock drift " + drift + "ms exceeds threshold");
            // Borrow from sequence space to stay monotonic
            driftOffset++;
            now = lastTimestamp; // pretend time didn't go backward
        } else {
            driftOffset = 0;
        }

        if (now == lastTimestamp) {
            sequence = (sequence + 1) & 0xFFFL;
            if (sequence == 0) now = waitNextMs(now);
        } else {
            sequence = 0;
        }

        lastTimestamp = now;
        long machineId = 1L; // simplified
        return ((now - EPOCH) << 22) | (machineId << 12) | sequence;
    }

    private long waitNextMs(long last) {
        long ms;
        while ((ms = System.currentTimeMillis()) <= last) Thread.onSpinWait();
        return ms;
    }
}
```

---

## 6. Trade-Offs

| Attribute | Snowflake | UUID v4 | Auto-increment | UUID v7 |
|---|---|---|---|---|
| Globally unique | Yes | Yes | Requires coordination | Yes |
| Sortable | Yes (time-ordered) | No | Yes | Yes (time-ordered) |
| Coordination needed | No (per-node) | No | Yes (single counter) | No |
| Size | 64-bit (8 bytes) | 128-bit (16 bytes) | 32–64 bit | 128-bit (16 bytes) |
| B+ tree locality | Excellent | Poor (random) | Excellent | Good (random within ms) |
| Max throughput/node | 4M IDs/sec | Unlimited | Seq bottleneck | Unlimited |
| Clock dependency | Yes (NTP risk) | No | No | Yes (NTP risk) |
| Decode time from ID | Yes | No | No | Yes |

---

## 7. Where Snowflake-Style IDs Appear at FAANG

| Company | System | Notes |
|---|---|---|
| **Twitter** | Tweet IDs, DM IDs, user IDs | Original Snowflake; open-sourced 2010 |
| **Discord** | Message IDs, channel IDs | Modified layout, 42-bit timestamp |
| **Instagram** | Photo/video IDs | PostgreSQL-based, shard ID embedded |
| **Uber** | Trip IDs | Internal Peloton ID service (Snowflake variant) |
| **LinkedIn** | Activity IDs | Spray variant — sequence distributed across machines |
| **Shopify** | Order IDs | Snowflake behind ID service with ZooKeeper coordination |
| **Sony** | Sonyflake | 16-bit machine ID for IoT device scale |

---

## 8. FAANG Interview Callouts

**"Design a unique ID generation service for a system like Twitter at 500K tweets/sec:"**
> Deploy a Snowflake generator as a sidecar or library on every application server. Each server is assigned a unique 10-bit machine ID at startup via ZooKeeper (or a simple registry). Each generates up to 4M IDs/sec locally — zero network calls for ID generation. At 500K/sec globally with 100 app servers: 5000 IDs/sec per server — well within the 4M/sec cap. No single point of failure; machine ID reassignment handled on restart via ZooKeeper persistent node.

**"What happens to Snowflake IDs if two machines are assigned the same machine ID?"**
> IDs will collide whenever both machines generate an ID in the same millisecond with the same sequence number. This is why machine ID assignment must be atomic and coordinated — ZooKeeper ephemeral nodes, Consul, or a startup handshake with a dedicated ID service. In practice, startup failures here are loud and caught immediately.

**"Why are Snowflake IDs better than UUIDs for database primary keys?"**
> UUID v4 is random — every insert scatters across the B+ tree, causing random page reads and frequent page splits. At high insert rates this kills cache hit ratios and causes index fragmentation. Snowflake IDs are time-ordered: inserts always land near the rightmost leaf, maximising page fill, minimising splits, and keeping hot pages in buffer pool. The difference at 100K inserts/sec on MySQL InnoDB: UUIDs → 60% page utilisation, Snowflake → 95%+ page utilisation.

**Follow-up questions to expect:**
1. "How would you handle the machine ID assignment when running in Kubernetes with auto-scaling?" → Use a startup init container that claims a worker ID from a ZooKeeper/etcd ephemeral node. On pod death the ephemeral node is released and the ID can be reused. Alternatively: derive machine ID from the pod's IP address last octet (works for /24 subnets) or use a hash of pod name.
2. "What's the maximum rate of IDs before Snowflake blocks?" → 4096 IDs/ms per machine. At that rate, the generator spins (`waitNextMs`) until the clock ticks forward. In practice, this spin is <1ms. If you need more: deploy multiple worker IDs per JVM (`SnowflakePool`) or reduce timestamp precision to 10ms ticks (Sonyflake approach) to reclaim bits.
3. "Can you extract the creation time of a Tweet from its tweet ID?" → Yes: `timestamp = (tweet_id >> 22) + EPOCH`. This is intentional and documented by Twitter — it lets you binary-search for tweets around a given time, reconstruct timelines, and correlate events. Time is embedded, not stored separately.
