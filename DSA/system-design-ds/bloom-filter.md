# Bloom Filter
**Category**: Probabilistic Data Structure — space-efficient membership testing

---

## 1. The Problem It Solves

### Naive Membership Check

To answer "have we seen key X before?" with 100% accuracy you need an exact set — a `HashSet`. At scale that becomes expensive:

```
10 billion URLs  ×  ~50 bytes each  =  ~500 GB RAM  (HashSet)
Same set in Bloom filter at 1% FPR  =  ~11.4 GB RAM  — 44× smaller
```

A Bloom filter answers "definitely NOT in set" or "PROBABLY in set" using a **fixed-size bit array** — no false negatives, tunable false positive rate.

---

## 2. Algorithm

### 2.1 Data Structure

```
Bit array of m bits, all initialised to 0
k independent hash functions h1, h2, … hk (each maps key → [0, m)
```

### 2.2 Insert(key)
Compute `h1(key), h2(key), … hk(key)` → set those bit positions to 1.

### 2.3 Query(key)
Compute the same k positions. If **all** bits are 1 → "probably present". If **any** bit is 0 → "definitely absent".

### 2.4 Why No False Negatives?
A key's bits are never cleared. Once set, they remain 1. So a key that was inserted will always have all its bits set.

### 2.5 Why False Positives?
Bits set by *other* keys can coincidentally match the k positions of a queried key that was never inserted.

---

## 3. Math: Sizing the Filter

### 3.1 Optimal Parameters

Given:
- `n` = expected number of inserted elements
- `p` = desired false positive rate (e.g., 0.01 = 1%)

**Optimal bit array size:**
```
m = -n * ln(p) / (ln(2))²
```

**Optimal number of hash functions:**
```
k = (m / n) * ln(2)
```

| n (elements) | p (FPR) | m (bits) | k (hash fns) | Memory |
|---|---|---|---|---|
| 1 M | 1% | ~9.6 M bits | 7 | ~1.2 MB |
| 1 M | 0.1% | ~14.4 M bits | 10 | ~1.8 MB |
| 1 B | 1% | ~9.6 B bits | 7 | ~1.2 GB |
| 1 B | 0.1% | ~14.4 B bits | 10 | ~1.8 GB |

**Rule of thumb**: ~10 bits per element gives ~1% FPR.

### 3.2 Actual FPR Given m, n, k

```
FPR = (1 - e^(-kn/m))^k
```

---

## 4. Java Implementation

### 4.1 Basic Implementation (thread-safe)

```java
import java.nio.charset.StandardCharsets;
import java.util.BitSet;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class BloomFilter<T> {

    private final BitSet bits;
    private final int m;           // bit array size
    private final int k;           // number of hash functions
    private final AtomicInteger count = new AtomicInteger(0);
    private final ReadWriteLock lock = new ReentrantReadWriteLock();

    // salt strings to simulate k independent hash functions via double hashing
    private final long[] hashSeeds;

    public BloomFilter(long expectedElements, double falsePositiveRate) {
        this.m = optimalBitSize(expectedElements, falsePositiveRate);
        this.k = optimalHashCount(m, expectedElements);
        this.bits = new BitSet(m);
        this.hashSeeds = new long[k];
        for (int i = 0; i < k; i++) {
            hashSeeds[i] = (long) (i * 0x9e3779b97f4a7c15L);
        }
    }

    public void add(T item) {
        byte[] bytes = item.toString().getBytes(StandardCharsets.UTF_8);
        lock.writeLock().lock();
        try {
            for (int i = 0; i < k; i++) {
                bits.set(indexFor(bytes, i));
            }
            count.incrementAndGet();
        } finally {
            lock.writeLock().unlock();
        }
    }

    public boolean mightContain(T item) {
        byte[] bytes = item.toString().getBytes(StandardCharsets.UTF_8);
        lock.readLock().lock();
        try {
            for (int i = 0; i < k; i++) {
                if (!bits.get(indexFor(bytes, i))) return false;
            }
            return true;
        } finally {
            lock.readLock().unlock();
        }
    }

    private int indexFor(byte[] bytes, int seed) {
        long hash = murmur3Mix(bytes, hashSeeds[seed]);
        // ensure positive index
        return (int) ((hash & Long.MAX_VALUE) % m);
    }

    private long murmur3Mix(byte[] data, long seed) {
        long h = seed;
        for (byte b : data) {
            h ^= (b & 0xFFL) * 0xc4ceb9fe1a85ec53L;
            h = Long.rotateLeft(h, 31) * 0x517cc1b727220a95L;
        }
        h ^= h >>> 33;
        h *= 0xff51afd7ed558ccdL;
        h ^= h >>> 33;
        return h;
    }

    public double currentFalsePositiveRate() {
        double bitsSetRatio = (double) bits.cardinality() / m;
        return Math.pow(bitsSetRatio, k);
    }

    public int count() { return count.get(); }
    public int bitArraySize() { return m; }
    public int numHashFunctions() { return k; }

    private static int optimalBitSize(long n, double p) {
        return (int) Math.ceil(-n * Math.log(p) / (Math.log(2) * Math.log(2)));
    }

    private static int optimalHashCount(int m, long n) {
        return Math.max(1, (int) Math.round((double) m / n * Math.log(2)));
    }
}
```

### 4.2 Usage

```java
// URL deduplication — 10M URLs, 0.1% FPR
BloomFilter<String> seen = new BloomFilter<>(10_000_000, 0.001);

seen.add("https://example.com/page1");
seen.add("https://example.com/page2");

System.out.println(seen.mightContain("https://example.com/page1")); // true (probably)
System.out.println(seen.mightContain("https://example.com/page3")); // false (definitely)
System.out.printf("Bit array: %d bits (%.1f MB)%n",
    seen.bitArraySize(), seen.bitArraySize() / 8.0 / 1024 / 1024);
// → Bit array: 143775072 bits (17.2 MB) for 10M elements at 0.1% FPR
```

### 4.3 Counting Bloom Filter (Supports Deletes)

Standard Bloom filters cannot delete elements. A counting variant replaces each bit with a small counter:

```java
public class CountingBloomFilter<T> {

    private final int[] counters; // 4-bit counters packed, or full int[] for simplicity
    private final int m;
    private final int k;

    public CountingBloomFilter(long expectedElements, double falsePositiveRate) {
        this.m = optimalBitSize(expectedElements, falsePositiveRate);
        this.k = optimalHashCount(m, expectedElements);
        this.counters = new int[m];
    }

    public void add(T item) {
        byte[] bytes = item.toString().getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < k; i++) {
            int idx = indexFor(bytes, i);
            if (counters[idx] < Integer.MAX_VALUE) counters[idx]++;
        }
    }

    public boolean remove(T item) {
        if (!mightContain(item)) return false;
        byte[] bytes = item.toString().getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < k; i++) {
            int idx = indexFor(bytes, i);
            if (counters[idx] > 0) counters[idx]--;
        }
        return true;
    }

    public boolean mightContain(T item) {
        byte[] bytes = item.toString().getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i < k; i++) {
            if (counters[indexFor(bytes, i)] == 0) return false;
        }
        return true;
    }

    private int indexFor(byte[] bytes, int seed) {
        long h = seed * 0x9e3779b97f4a7c15L;
        for (byte b : bytes) h = h * 31 + b;
        h ^= h >>> 16;
        return (int) ((h & Long.MAX_VALUE) % m);
    }

    private static int optimalBitSize(long n, double p) {
        return (int) Math.ceil(-n * Math.log(p) / (Math.log(2) * Math.log(2)));
    }

    private static int optimalHashCount(int m, long n) {
        return Math.max(1, (int) Math.round((double) m / n * Math.log(2)));
    }
}
```

**Trade-off**: Counting filter uses 4–8× more memory than standard; overflow (counter saturation) can cause false negatives.

---

## 5. Variants

### 5.1 Scalable Bloom Filter
Chains multiple Bloom filters. When the current filter exceeds a fill threshold (~50%), a new larger filter is added. Supports unbounded inserts while maintaining a target FPR.

### 5.2 Partitioned Bloom Filter
Divides the m-bit array into k equal partitions; hash function i writes only into partition i. Improves cache locality, slightly worse FPR math.

### 5.3 Distributed Bloom Filter (used in Cassandra)
Serialise the bit array → replicate to all nodes. Each node independently checks membership. Compacted as part of SSTable metadata (one filter per SSTable).

---

## 6. Where Bloom Filters Appear in System Design

### 6.1 Cassandra — Avoiding Disk Reads

```
Read path (without Bloom filter):
  Query key → check ALL SSTables on disk → O(n) disk seeks

Read path (with Bloom filter):
  Query key → check each SSTable's Bloom filter (in RAM)
             → skip SSTables where filter says "definitely not"
             → disk read only when filter says "probably yes"
  
Result: 70–90% of disk seeks eliminated for typical workloads.
  FPR tunable: lower FPR (larger filter) → fewer false disk reads,
               more RAM usage. Default in Cassandra: bloom_filter_fp_chance = 0.01
```

### 6.2 Google Bigtable / HBase
Same pattern as Cassandra: per-SSTable Bloom filter stored in the block index to skip SSTables during reads.

### 6.3 Chrome Safe Browsing
Locally-stored Bloom filter of ~300K malicious URLs, checked before any network call. Reduces safe-browsing API calls by ~90%.

### 6.4 CDN / Proxy Caching (Akamai)
One-hit-wonder problem: 75% of objects are requested only once. Caching them on first request wastes cache space.
Solution: cache only if the Bloom filter says the URL was seen before → only cache objects with ≥2 requests.

### 6.5 Database Query Optimiser (e.g., PostgreSQL bloom index)
Bloom filter on composite columns to quickly eliminate rows before full scan.

### 6.6 Rate Limiting (Token Bucket + Bloom Filter)
Track "seen IPs" in a Bloom filter at the edge. First occurrence always allowed through (no false negatives); second occurrence checked against rate limiter. Reduces central Redis calls.

---

## 7. Trade-Offs

| Attribute | Bloom Filter | HashSet | Counting BF |
|---|---|---|---|
| Space | O(m) fixed | O(n) grows | O(m) fixed × 4–8 |
| Lookup | O(k) | O(1) average | O(k) |
| False negatives | Never | Never | Never (if no overflow) |
| False positives | Yes (tunable) | No | Yes (tunable) |
| Deletion | No | Yes | Yes |
| Serialisable | Yes (bit array) | Yes | Yes |
| Thread safety | With locks | With ConcurrentHashMap | With locks |

---

## 8. FAANG Interview Callouts

**"Can you use a Bloom filter here?"** — safe when:
- The consequence of a false positive is a wasted (but cheap) secondary lookup, NOT a wrong answer.
- You can tolerate "probably yes" + confirm via actual storage on hit.
- Memory budget is the primary constraint.

**Never use when** you need guaranteed membership accuracy (financial transactions, auth tokens) or need to delete frequently without the counting overhead.

**Follow-up questions to expect:**
1. "What FPR would you choose for your Cassandra read path and why?" → Trade off RAM vs disk I/O; at scale, 1% FPR → each SSTable read costs ~10 bits/element ≈ acceptable.
2. "How would you handle Bloom filter warm-up after a node restart?" → Rebuild from SSTable data on startup (Cassandra does this on bootstrap).
3. "How do you merge two Bloom filters?" → Bitwise OR of the two bit arrays — valid only if they have identical m and k.
