# Count-Min Sketch
**Category**: Probabilistic Data Structure — frequency estimation for high-cardinality streams

---

## 1. The Problem It Solves

### Frequency Counting at Streaming Scale

"What are the most frequent queries in the last 5 minutes across 10B events/day?"

An exact counter per key requires storing every distinct key:
```
1B distinct URLs × 8 bytes per counter  =  8 GB RAM (exact HashMap)
1B distinct IPs  × 8 bytes per counter  =  8 GB RAM
```

At streaming ingestion rates this is often impractical. Count-Min Sketch estimates frequency for any key using **fixed memory**, with a tunable error bound:

```
ε = 0.001, δ = 0.01  →  width w = 2718, depth d = 7 counters
                     →  ~19 KB RAM, regardless of how many distinct keys
```

The estimate for any key `k` is at most `f(k) + ε·N` where N is total events seen — with probability ≥ (1 - δ).

---

## 2. Algorithm

### 2.1 Data Structure

```
d × w array of counters, all initialised to 0
d independent hash functions h1, h2, … hd (each maps key → [0, w))
```

### 2.2 Update(key, count)
For each row `i` from 1 to `d`: `table[i][h_i(key)] += count`

### 2.3 Query(key) → estimated frequency
For each row `i`: read `table[i][h_i(key)]`
Return `min(table[1][h1(key)], table[2][h2(key)], ..., table[d][hd(key)])`

### 2.4 Why Min?

Multiple keys hash to the same counter cell (hash collision). A counter can only be **over-counted** (other keys add to it), never under-counted. Taking the minimum across d independent hash functions minimises the overcount — with high probability, at least one row has no collision on that cell.

```
Actual frequency of key X: f(X) = 10
Hash collision with key Y (f(Y)=500) in row 1: cell = 510
No collision in row 2: cell = 10
No collision in row 3: cell = 10
min(510, 10, 10) = 10  ← correct estimate
```

---

## 3. Math: Sizing the Sketch

### 3.1 Optimal Parameters

Given:
- `ε` = max additive error as fraction of total N (e.g., 0.001 = 0.1%)
- `δ` = probability that estimate exceeds error bound

```
Width:  w = ⌈e / ε⌉    (e ≈ 2.718)
Depth:  d = ⌈ln(1/δ)⌉
```

| ε (error) | δ (failure prob) | w | d | Memory (int counters) |
|---|---|---|---|---|
| 0.01 | 0.01 | 272 | 5 | ~5.4 KB |
| 0.001 | 0.01 | 2718 | 5 | ~54 KB |
| 0.0001 | 0.01 | 27183 | 5 | ~540 KB |
| 0.001 | 0.001 | 2718 | 7 | ~76 KB |

**Rule of thumb**: ~1 MB gives sub-0.001% error with 99.9% confidence for any stream size.

### 3.2 Error Guarantee

```
P[estimate(key) ≤ f(key) + ε·N] ≥ 1 - δ

where N = total events processed
```

The estimate is always ≥ f(key) (no false negatives in frequency). The overestimate is bounded with high probability.

---

## 4. Java Implementation

### 4.1 Core Count-Min Sketch

```java
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLongArray;

public class CountMinSketch {

    private final int width;
    private final int depth;
    private final long[][] table;
    private final long[] hashSeeds;
    private long totalCount = 0;

    public CountMinSketch(double epsilon, double delta) {
        this.width = (int) Math.ceil(Math.E / epsilon);
        this.depth = (int) Math.ceil(Math.log(1.0 / delta));
        this.table = new long[depth][width];
        this.hashSeeds = new long[depth];
        for (int i = 0; i < depth; i++) {
            hashSeeds[i] = (long) (i * 0x9e3779b97f4a7c15L + 0xdeadbeef12345678L);
        }
    }

    public CountMinSketch(int width, int depth) {
        this.width = width;
        this.depth = depth;
        this.table = new long[depth][width];
        this.hashSeeds = new long[depth];
        for (int i = 0; i < depth; i++) {
            hashSeeds[i] = (long) (i * 0x9e3779b97f4a7c15L);
        }
    }

    public void add(String key) {
        add(key, 1);
    }

    public void add(String key, long count) {
        byte[] bytes = key.getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < depth; i++) {
            int col = columnIndex(bytes, i);
            table[i][col] += count;
        }
        totalCount += count;
    }

    public long estimate(String key) {
        byte[] bytes = key.getBytes(StandardCharsets.UTF_8);
        long min = Long.MAX_VALUE;
        for (int i = 0; i < depth; i++) {
            long count = table[i][columnIndex(bytes, i)];
            if (count < min) min = count;
        }
        return min;
    }

    // Estimate frequency as fraction of total stream
    public double estimateFrequency(String key) {
        if (totalCount == 0) return 0;
        return (double) estimate(key) / totalCount;
    }

    // Merge another sketch into this one (must have same dimensions)
    public void merge(CountMinSketch other) {
        if (this.width != other.width || this.depth != other.depth) {
            throw new IllegalArgumentException("Incompatible sketch dimensions");
        }
        for (int i = 0; i < depth; i++) {
            for (int j = 0; j < width; j++) {
                table[i][j] += other.table[i][j];
            }
        }
        totalCount += other.totalCount;
    }

    public long totalCount() { return totalCount; }
    public int width() { return width; }
    public int depth() { return depth; }
    public long memorySizeBytes() { return (long) depth * width * Long.BYTES; }

    private int columnIndex(byte[] bytes, int row) {
        long hash = murmur3(bytes, hashSeeds[row]);
        return (int) ((hash & Long.MAX_VALUE) % width);
    }

    private static long murmur3(byte[] data, long seed) {
        long h = seed;
        for (byte b : data) {
            h ^= (b & 0xFFL) * 0xc4ceb9fe1a85ec53L;
            h = Long.rotateLeft(h, 31) * 0x517cc1b727220a95L;
        }
        h ^= data.length;
        h ^= h >>> 33;
        h *= 0xff51afd7ed558ccdL;
        h ^= h >>> 33;
        return h;
    }
}
```

### 4.2 Heavy Hitters (Top-K) Using Count-Min Sketch

```java
import java.util.*;

public class HeavyHitters<K> {

    private final CountMinSketch sketch;
    private final int k;
    // Min-heap: tracks top-K candidates, key = frequency estimate
    private final PriorityQueue<Map.Entry<K, Long>> minHeap;
    private final Map<K, Long> topKCache;

    public HeavyHitters(double epsilon, double delta, int k) {
        this.sketch = new CountMinSketch(epsilon, delta);
        this.k = k;
        this.minHeap = new PriorityQueue<>(Comparator.comparingLong(Map.Entry::getValue));
        this.topKCache = new LinkedHashMap<>();
    }

    public void add(K key) {
        sketch.add(key.toString());
        long freq = sketch.estimate(key.toString());

        if (topKCache.containsKey(key)) {
            topKCache.put(key, freq);
            rebuildHeap();
        } else if (minHeap.size() < k) {
            topKCache.put(key, freq);
            minHeap.offer(Map.entry(key, freq));
        } else {
            long minFreq = minHeap.isEmpty() ? 0 : minHeap.peek().getValue();
            if (freq > minFreq) {
                Map.Entry<K, Long> evicted = minHeap.poll();
                topKCache.remove(evicted.getKey());
                topKCache.put(key, freq);
                minHeap.offer(Map.entry(key, freq));
            }
        }
    }

    public List<Map.Entry<K, Long>> topK() {
        List<Map.Entry<K, Long>> result = new ArrayList<>(topKCache.entrySet());
        result.sort((a, b) -> Long.compare(b.getValue(), a.getValue()));
        return result;
    }

    public long estimate(K key) {
        return sketch.estimate(key.toString());
    }

    private void rebuildHeap() {
        minHeap.clear();
        minHeap.addAll(topKCache.entrySet());
    }
}
```

### 4.3 Rate Limiter Using Count-Min Sketch

```java
import java.time.Instant;

public class SketchRateLimiter {

    // Two sketches for sliding window: current minute and previous minute
    private CountMinSketch current;
    private CountMinSketch previous;
    private long currentWindowStart;
    private final long windowMs;
    private final long maxRequests;

    public SketchRateLimiter(long windowMs, long maxRequests, double epsilon) {
        this.windowMs = windowMs;
        this.maxRequests = maxRequests;
        this.current = new CountMinSketch(epsilon, 0.01);
        this.previous = new CountMinSketch(epsilon, 0.01);
        this.currentWindowStart = Instant.now().toEpochMilli();
    }

    public synchronized boolean allow(String clientId) {
        rotate();
        long now = Instant.now().toEpochMilli();
        double elapsed = (now - currentWindowStart) / (double) windowMs;

        // Sliding window estimate: weight previous window by how much has elapsed
        long prevCount = previous.estimate(clientId);
        long currCount = current.estimate(clientId);
        long slidingCount = Math.round(prevCount * (1.0 - elapsed)) + currCount;

        if (slidingCount < maxRequests) {
            current.add(clientId);
            return true;
        }
        return false;
    }

    private void rotate() {
        long now = Instant.now().toEpochMilli();
        if (now - currentWindowStart >= windowMs) {
            previous = current;
            current = new CountMinSketch(current.width(), current.depth());
            currentWindowStart = now;
        }
    }
}
```

### 4.4 Streaming Top-N with Windowing

```java
import java.util.concurrent.*;
import java.util.*;

public class StreamingTopN {

    private final int n;
    private final long windowMs;
    private volatile CountMinSketch sketch;
    private final ScheduledExecutorService scheduler;

    public StreamingTopN(int n, long windowMs, double epsilon) {
        this.n = n;
        this.windowMs = windowMs;
        this.sketch = new CountMinSketch(epsilon, 0.01);
        this.scheduler = Executors.newSingleThreadScheduledExecutor();
        // Reset sketch each window — stateless rolling window
        scheduler.scheduleAtFixedRate(
            this::resetSketch, windowMs, windowMs, TimeUnit.MILLISECONDS);
    }

    public void record(String key) {
        sketch.add(key);
    }

    public long frequency(String key) {
        return sketch.estimate(key);
    }

    private synchronized void resetSketch() {
        this.sketch = new CountMinSketch(sketch.width(), sketch.depth());
    }

    public void shutdown() { scheduler.shutdown(); }
}
```

---

## 5. Count-Min Sketch vs Alternatives

| Approach | Memory | Error | Heavy Hitters | Deletions | Merge |
|---|---|---|---|---|---|
| HashMap (exact) | O(N) grows | 0% | Yes (sort) | Yes | Yes (union) |
| Count-Min Sketch | O(w×d) fixed | ε·N (overcount) | With min-heap | With CMS-CU | Yes (sum) |
| Count Sketch | O(w×d) fixed | ε·‖f‖₂ (signed) | Yes | Yes (signed) | Yes (sum) |
| Lossy Counting | O(1/ε × log N) | ε·N | Yes | No | Harder |
| Space Saving | O(1/ε) | ε·N | Exact top-k IDs | No | No |

**Count Sketch** (Charikar et al.) uses signed increments (±1) and median estimator — unbiased estimate with ±ε·‖f‖₂ error. Better when the stream has heavy hitters dominating; worse for uniform distributions.

---

## 6. Where Count-Min Sketch Appears at FAANG

### 6.1 Trending Topics (Twitter, Facebook)
Count queries/posts per hashtag or keyword in a 5-minute sliding window across millions of events/sec. CMS fits in a few MB; exact counting would require GBs per window. Top-K over the sketch identifies trending topics.

### 6.2 Network Traffic Analysis (Cloudflare, Akamai)
Count packets per source IP to detect DDoS flooding. 1B distinct IPs × 8 bytes = 8 GB exact. CMS with ε=0.0001: ~5 MB, identifies IPs contributing ≥0.01% of traffic.

### 6.3 Database Query Optimisation (PostgreSQL, SQL Server)
Cardinality estimation for query planning uses CMS or similar sketches. The sketch estimates how many rows match a filter predicate without full table scan.

### 6.4 Flink / Spark Streaming
Built-in `CountMinSketch` in `org.apache.spark.util.sketch.CountMinSketch`. Used in streaming SQL `APPROX_COUNT_DISTINCT`, approximate GROUP BY aggregations, and join cardinality estimation.

### 6.5 Rate Limiting at Scale (Stripe, Uber)
Per-API-key request counting with CMS avoids a separate Redis entry per key. One CMS per time bucket, stored in a few KB. Query: is this key's frequency above threshold? If yes, reject.

---

## 7. FAANG Interview Callouts

**"Design a system to find top-100 trending search queries in real-time over a sliding 5-minute window across 1M QPS:"**
> Use a Count-Min Sketch per minute-bucket (d=5, w=2718 for ε=0.001). On each query: `sketch.add(queryToken)`. To query trending: maintain a min-heap of ~1000 candidate queries updated per batch. Each minute: rotate bucket, merge last 5 buckets for sliding window estimate. Memory: 5 sketches × 5×2718×8 bytes ≈ 540 KB. At 1M QPS: no per-key memory allocation needed, counter increments in O(d) = O(5).

**"What's the difference between Count-Min Sketch and HyperLogLog?":**
> HyperLogLog estimates **cardinality** (how many distinct keys). Count-Min Sketch estimates **frequency** (how many times a specific key appeared). They answer different questions and can't substitute for each other. Both use O(1) fixed memory regardless of distinct key count.

**Follow-up questions to expect:**
1. "How would you handle counter overflow in Count-Min Sketch?" → Use 64-bit counters (rare overflow). Or split into multiple sketches per time window and let old windows expire (FIFO rotation). Conservative Update (CMS-CU) variant: only increment cells where estimate equals the true cell — reduces overcount and extends effective range.
2. "Can Count-Min Sketch over-estimate by more than ε·N?" → Yes, but with probability at most δ. The error guarantee is probabilistic. Increasing depth d reduces δ exponentially: d=7 → δ≤0.001; d=10 → δ<0.0001.
3. "How would you use Count-Min Sketch in a distributed system?" → Each node maintains its own sketch. For a global query, serialize the w×d counter arrays, ship them to a coordinator, and sum corresponding cells (not max — CMS merges by addition). Result is a valid global sketch with combined N.
