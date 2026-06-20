# HyperLogLog (HLL)
**Category**: Probabilistic Data Structure — cardinality estimation (count-distinct)

---

## 1. The Problem It Solves

### Count-Distinct at Scale

"How many unique visitors did this page have today?"

Exact answer requires storing every distinct visitor ID:
```
10B events/day, 64-bit user IDs → 10B × 8 bytes = 80 GB RAM (exact HashSet)
```

HyperLogLog estimates cardinality with **~0.81% error** using only **~1.5 KB RAM** — a 53 million× reduction.

This is the algorithm behind:
- `PFCOUNT` in Redis
- `APPROX_COUNT_DISTINCT` in BigQuery, Redshift
- Unique visitor counting at Facebook, Google Analytics, Cloudflare

---

## 2. Intuition — The Probabilistic Trick

### 2.1 Single Estimator: Trailing Zeros

Hash each element to a uniform bit string. Observe the maximum number of **leading zeros** seen across all hashes. If the max leading zeros is `k`, the cardinality is approximately `2^k`.

```
Hash(user_123) = 00001010...    leading zeros = 4 → estimate ~16
Hash(user_456) = 01011001...    leading zeros = 1 → estimate ~2
Hash(user_789) = 00000110...    leading zeros = 5 → estimate ~32

Max leading zeros = 5  →  estimate cardinality ≈ 2^5 = 32
```

**Problem**: single estimator has very high variance (±50% typical).

### 2.2 HyperLogLog: Stochastic Averaging

Split the hash into two parts:
- First `b` bits → **bucket index** (selects one of `m = 2^b` buckets)
- Remaining bits → **run of leading zeros** for this bucket

Each bucket independently tracks its max leading zeros. Final estimate combines all buckets using the **harmonic mean** to cancel outliers.

```
m = 64 buckets (b = 6), remaining 58 bits for leading-zero counting

Element hashed → first 6 bits = 0b101010 = bucket 42
                 remaining 58 bits = 0001110... → 3 leading zeros
                 M[42] = max(M[42], 3)

Final estimate:  E = α_m × m² × (Σ 2^(-M[j]))^(-1)
```

Where `α_m` is a bias-correction constant (~0.7213 for large m).

---

## 3. Math

### 3.1 Accuracy vs Memory

```
m = number of registers (buckets) = 2^b
Standard error ≈ 1.04 / √m

m = 16     → error 26%,  memory ~16 × 5 bits = 10 bytes
m = 256    → error 6.5%, memory ~256 × 5 bits = 160 bytes
m = 1024   → error 3.3%, memory ~1024 × 5 bits = 640 bytes
m = 16384  → error 0.81%, memory ~16384 × 5 bits = ~12 KB   ← Redis default
```

**Redis HyperLogLog**: uses m=16384, 6-bit registers → **12 KB per HLL**, error ~0.81%.

### 3.2 Register Size

Each register needs to hold the max leading zero count. For a 64-bit hash with b=14 (m=16384), the remaining 50 bits can have at most 50 leading zeros, so 6 bits per register suffices (max value 63 > 50).

### 3.3 Merge Property

HyperLogLog is **mergeable**: UNION(HLL_A, HLL_B) = take the element-wise max of corresponding registers.

```
m registers in A: [3, 1, 5, 2, ...]
m registers in B: [1, 4, 2, 7, ...]
Merged:           [3, 4, 5, 7, ...]   (element-wise max)
```

This makes HLL ideal for distributed counting: each shard maintains its own HLL, merge at query time.

---

## 4. Java Implementation

### 4.1 Core HyperLogLog

```java
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public class HyperLogLog {

    private final int b;          // index bits
    private final int m;          // number of registers = 2^b
    private final byte[] registers;
    private final double alphaMM; // bias correction constant × m²

    public HyperLogLog(int b) {
        if (b < 4 || b > 16) throw new IllegalArgumentException("b must be 4..16");
        this.b = b;
        this.m = 1 << b;
        this.registers = new byte[m];
        this.alphaMM = alpha(m) * (double) m * m;
    }

    public void add(String value) {
        long hash = murmur3_64(value.getBytes(StandardCharsets.UTF_8), 0xdeadbeefL);
        int bucketIndex = (int) (hash >>> (64 - b)) & (m - 1);
        // Count leading zeros in remaining (64 - b) bits
        long remaining = hash << b;
        byte leadingZeros = (byte) (Long.numberOfLeadingZeros(remaining | (1L << (b - 1))) + 1);
        if (leadingZeros > registers[bucketIndex]) {
            registers[bucketIndex] = leadingZeros;
        }
    }

    public long estimate() {
        double sum = 0.0;
        int zeros = 0;
        for (byte reg : registers) {
            sum += Math.pow(2.0, -reg);
            if (reg == 0) zeros++;
        }

        double estimate = alphaMM / sum;

        // Small range correction (linear counting)
        if (estimate <= 2.5 * m && zeros > 0) {
            estimate = m * Math.log((double) m / zeros);
        }
        // Large range correction (not needed for 64-bit hashes — overflow negligible)

        return Math.round(estimate);
    }

    // Merge another HLL into this one (union)
    public void merge(HyperLogLog other) {
        if (this.m != other.m) throw new IllegalArgumentException("Incompatible HLL sizes");
        for (int i = 0; i < m; i++) {
            if (other.registers[i] > this.registers[i]) {
                this.registers[i] = other.registers[i];
            }
        }
    }

    public HyperLogLog mergedWith(HyperLogLog other) {
        HyperLogLog result = new HyperLogLog(b);
        System.arraycopy(this.registers, 0, result.registers, 0, m);
        result.merge(other);
        return result;
    }

    public byte[] toBytes() { return Arrays.copyOf(registers, m); }

    public static HyperLogLog fromBytes(int b, byte[] registers) {
        HyperLogLog hll = new HyperLogLog(b);
        System.arraycopy(registers, 0, hll.registers, 0, hll.m);
        return hll;
    }

    private static double alpha(int m) {
        switch (m) {
            case 16:  return 0.673;
            case 32:  return 0.697;
            case 64:  return 0.709;
            default:  return 0.7213 / (1 + 1.079 / m);
        }
    }

    // 64-bit Murmur3-inspired finalisation
    private static long murmur3_64(byte[] data, long seed) {
        long h = seed;
        for (byte b : data) {
            h ^= (b & 0xFFL);
            h *= 0xff51afd7ed558ccdL;
            h ^= h >>> 33;
        }
        h ^= data.length;
        h ^= h >>> 33;
        h *= 0xc4ceb9fe1a85ec53L;
        h ^= h >>> 33;
        return h;
    }
}
```

### 4.2 Usage

```java
// Count distinct users across 3 partitions
HyperLogLog hll1 = new HyperLogLog(14); // 2^14 = 16384 registers, ~0.81% error
HyperLogLog hll2 = new HyperLogLog(14);
HyperLogLog hll3 = new HyperLogLog(14);

// Partition 1 processes events
for (String userId : partition1Events) hll1.add(userId);
// Partition 2
for (String userId : partition2Events) hll2.add(userId);
// Partition 3
for (String userId : partition3Events) hll3.add(userId);

// Merge at query time
HyperLogLog merged = hll1.mergedWith(hll2).mergedWith(hll3); // wait — chain merge
hll1.merge(hll2);
hll1.merge(hll3);
long distinctUsers = hll1.estimate();
System.out.printf("Distinct users: ~%,d (±0.81%%)%n", distinctUsers);
```

### 4.3 Distributed HLL Counter (sketch of Redis-backed approach)

```java
import redis.clients.jedis.Jedis;

public class DistributedHLLCounter {

    private final Jedis jedis;
    private final String keyPrefix;

    public DistributedHLLCounter(Jedis jedis, String keyPrefix) {
        this.jedis = jedis;
        this.keyPrefix = keyPrefix;
    }

    // Redis PFADD internally uses HyperLogLog
    public void record(String dimension, String userId) {
        String key = keyPrefix + ":" + dimension;
        jedis.pfadd(key, userId);
    }

    // Exact unique count (±0.81%)
    public long count(String dimension) {
        return jedis.pfcount(keyPrefix + ":" + dimension);
    }

    // Merge multiple dimensions for union count (e.g., unique users across pages)
    public long countUnion(String... dimensions) {
        String[] keys = Arrays.stream(dimensions)
            .map(d -> keyPrefix + ":" + d)
            .toArray(String[]::new);
        return jedis.pfcount(keys); // Redis merges internally
    }

    // Merge two HLLs into a destination key
    public void mergeInto(String destDimension, String... sourceDimensions) {
        String destKey = keyPrefix + ":" + destDimension;
        String[] sourceKeys = Arrays.stream(sourceDimensions)
            .map(d -> keyPrefix + ":" + d)
            .toArray(String[]::new);
        jedis.pfmerge(destKey, sourceKeys);
    }
}
```

### 4.4 Sliding Window HLL (time-windowed cardinality)

```java
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.LinkedList;

public class SlidingWindowHLL {

    private record WindowSlice(Instant timestamp, HyperLogLog hll) {}

    private final LinkedList<WindowSlice> slices = new LinkedList<>();
    private final long windowSeconds;
    private final long sliceDurationSeconds;
    private final int hllBits;
    private HyperLogLog activeSlice;
    private Instant activeSliceStart;

    public SlidingWindowHLL(long windowSeconds, long sliceDurationSeconds, int hllBits) {
        this.windowSeconds = windowSeconds;
        this.sliceDurationSeconds = sliceDurationSeconds;
        this.hllBits = hllBits;
        this.activeSlice = new HyperLogLog(hllBits);
        this.activeSliceStart = Instant.now();
    }

    public synchronized void add(String element) {
        Instant now = Instant.now();
        if (ChronoUnit.SECONDS.between(activeSliceStart, now) >= sliceDurationSeconds) {
            slices.addLast(new WindowSlice(activeSliceStart, activeSlice));
            activeSlice = new HyperLogLog(hllBits);
            activeSliceStart = now;
        }
        activeSlice.add(element);
        evictOldSlices(now);
    }

    public synchronized long estimate() {
        HyperLogLog merged = new HyperLogLog(hllBits);
        for (WindowSlice slice : slices) merged.merge(slice.hll());
        merged.merge(activeSlice);
        return merged.estimate();
    }

    private void evictOldSlices(Instant now) {
        Instant cutoff = now.minusSeconds(windowSeconds);
        slices.removeIf(s -> s.timestamp().isBefore(cutoff));
    }
}
```

---

## 5. HyperLogLog vs Alternatives

| Approach | Memory (1B elements) | Error | Supports Delete | Merge |
|---|---|---|---|---|
| HashSet (exact) | ~8 GB | 0% | Yes | Yes (union) |
| HyperLogLog | ~12 KB | ~0.81% | No | Yes (max) |
| Linear Counting | ~500 MB at 1% error | ~1% | No | Yes (OR) |
| FM Sketch (original) | ~100 KB | ~5% | No | Yes |
| KMV Sketch | ~800 bytes at 1% error | ~1% | No | Yes (union) |

---

## 6. Where HyperLogLog Appears at FAANG

### 6.1 Redis `PFADD` / `PFCOUNT`
Every Redis instance includes HyperLogLog natively. `PFCOUNT key` estimates cardinality. `PFMERGE dest src1 src2` merges for union counts. Used in rate limiting, real-time analytics dashboards.

### 6.2 Google BigQuery `APPROX_COUNT_DISTINCT`
Returns HLL estimate, ~10–20× faster than exact `COUNT(DISTINCT ...)` on petabyte queries. Underlying HLL sketches can be extracted and merged via `HLL_COUNT.MERGE_PARTIAL`.

### 6.3 Amazon Redshift
`APPROXIMATE COUNT(DISTINCT col)` uses HLL. Sub-second on billions of rows vs minutes for exact count.

### 6.4 Apache Flink / Spark Streaming
Maintain rolling HLL sketches per key in streaming jobs. Checkpoint the register array; restore and continue. No need to replay all events.

### 6.5 Facebook Analytics (TAO / Hive)
Count distinct users who interacted with a piece of content. Daily aggregation stores per-content HLL sketches; query merges them on demand.

### 6.6 Cloudflare DDoS Detection
Maintain per-minute HLL of distinct source IPs per destination. A sudden 10× spike in estimated unique sources → DDoS signal.

---

## 7. FAANG Interview Callouts

**Design a system to count unique visitors per page per day across 1B pages:**
> Maintain one HLL per (page, date) in Redis. Each event: `PFADD page:{id}:{date} {user_id}`. Query: `PFCOUNT page:{id}:{date}`. Storage: 12 KB × 1B pages = ~12 TB. At 10% active pages per day: ~1.2 TB Redis. Accept ~0.81% error — exact counts don't justify the cost. For weekly counts: `PFMERGE` daily keys.

**What's the cardinality of a single HLL register?**
> Each register holds the max leading zero count seen for its bucket. 6 bits → max value 63. With 64-bit hashes, a run of 63 leading zeros is astronomically improbable — so the register never saturates in practice.

**Follow-up questions to expect:**
1. "How would you handle cardinality for intersections (AND), not just unions?" → HLL doesn't directly support intersection. Use inclusion-exclusion: |A ∩ B| = |A| + |B| - |A ∪ B|. This has high error for near-equal sets. MinHash is better for intersection estimation.
2. "How would you persist and recover an HLL counter after a crash?" → Serialise the 12 KB register array to disk / Redis snapshot. On recovery, reload and continue adding — no events need replaying.
3. "If two teams both count unique users for overlapping event sets, how do you get the global distinct count?" → Each team serialises their HLL register bytes, send to a merger service, element-wise max → single global estimate. O(m) merge regardless of element count.
