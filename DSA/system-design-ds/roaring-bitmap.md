# Roaring Bitmap
**Category**: Compressed Bitmap — used in Druid, Clickhouse, Elasticsearch, Spark for fast set operations on integer IDs

---

## 1. The Problem It Solves

### Set Operations at Analytical Scale

Analytics queries often boil down to set operations on integer IDs:
- "Users who visited page A AND page B" → intersection
- "Users who visited page A OR page B" → union
- "Users who visited page A but NOT page B" → difference

A naive `BitSet` for user IDs 0..1B requires 1B / 8 = 125 MB RAM. With 1000 such sets (1000 event types), that's 125 GB just for bitmaps.

A `HashSet<Integer>` trades memory efficiency for density — sparse sets waste less, dense sets waste more.

**Roaring Bitmap** adapts its internal representation per chunk of 65536 values:
- **Dense chunks**: standard 65536-bit array (8 KB per chunk)
- **Sparse chunks**: sorted array of 16-bit values (2 bytes per element)
- **Very dense chunks**: run-length encoded (2 bytes per run)

```
Result: 3–5× smaller than BitSet for typical data, 10–50× smaller than HashSet
        AND/OR/NOT operations in O(N/word_size) using SIMD bitwise ops
```

---

## 2. Structure

### 2.1 Two-Level Layout

Every integer is split into a **high 16 bits** (chunk key) and a **low 16 bits** (value within chunk):

```
Integer value: 0x00123456
               ──────────
  High 16:     0x0012  → chunk 18  (index into container array)
  Low 16:      0x3456  → value within chunk

Total possible chunks: 2^16 = 65536
Each chunk covers a range of 65536 consecutive integers.
```

### 2.2 Container Types

```
ArrayContainer   (sparse: ≤ 4096 elements in chunk)
  → Sorted short[] of low-16-bit values
  → 2 bytes × cardinality ≤ 8 KB
  → Linear scan for intersection, merge for union

BitmapContainer  (dense: > 4096 elements in chunk)
  → long[1024] — 64 bits × 1024 = 65536 bits = 8 KB fixed
  → Bitwise AND/OR for intersection/union: 1024 long ops

RunContainer     (run-length encoded: after calling runOptimize())
  → [(start1, length1), (start2, length2), ...]
  → Very efficient for sequential IDs like timestamps
  → 4 bytes per run
```

Threshold: switching from Array → Bitmap at 4096 elements keeps both at ≤ 8 KB.

---

## 3. Java Implementation

### 3.1 Simplified Roaring Bitmap (illustrative)

```java
import java.util.*;

public class RoaringBitmap {

    private static final int CHUNK_SIZE = 65536;   // 2^16
    private static final int ARRAY_THRESHOLD = 4096; // switch array → bitmap

    // Chunk key → container
    private final TreeMap<Integer, Container> chunks = new TreeMap<>();

    public void add(int value) {
        int chunkKey = value >>> 16;
        int lowBits = value & 0xFFFF;
        chunks.computeIfAbsent(chunkKey, k -> new ArrayContainer()).add(lowBits);
    }

    public void add(int rangeStart, int rangeEnd) {
        for (int v = rangeStart; v <= rangeEnd; v++) add(v);
    }

    public boolean contains(int value) {
        Container c = chunks.get(value >>> 16);
        return c != null && c.contains(value & 0xFFFF);
    }

    public long cardinality() {
        return chunks.values().stream().mapToLong(Container::cardinality).sum();
    }

    // AND (intersection)
    public RoaringBitmap and(RoaringBitmap other) {
        RoaringBitmap result = new RoaringBitmap();
        for (Map.Entry<Integer, Container> entry : this.chunks.entrySet()) {
            Container otherChunk = other.chunks.get(entry.getKey());
            if (otherChunk != null) {
                Container intersected = entry.getValue().and(otherChunk);
                if (intersected.cardinality() > 0) result.chunks.put(entry.getKey(), intersected);
            }
        }
        return result;
    }

    // OR (union)
    public RoaringBitmap or(RoaringBitmap other) {
        RoaringBitmap result = new RoaringBitmap();
        Set<Integer> allKeys = new HashSet<>(this.chunks.keySet());
        allKeys.addAll(other.chunks.keySet());
        for (int key : allKeys) {
            Container a = this.chunks.get(key);
            Container b = other.chunks.get(key);
            if (a == null) result.chunks.put(key, b.copy());
            else if (b == null) result.chunks.put(key, a.copy());
            else result.chunks.put(key, a.or(b));
        }
        return result;
    }

    // AND NOT (difference)
    public RoaringBitmap andNot(RoaringBitmap other) {
        RoaringBitmap result = new RoaringBitmap();
        for (Map.Entry<Integer, Container> entry : this.chunks.entrySet()) {
            Container otherChunk = other.chunks.get(entry.getKey());
            Container diff = otherChunk == null
                ? entry.getValue().copy()
                : entry.getValue().andNot(otherChunk);
            if (diff.cardinality() > 0) result.chunks.put(entry.getKey(), diff);
        }
        return result;
    }

    public Iterator<Integer> iterator() {
        return new Iterator<>() {
            private final Iterator<Map.Entry<Integer, Container>> chunkIter = chunks.entrySet().iterator();
            private Map.Entry<Integer, Container> currentChunk = null;
            private Iterator<Integer> valueIter = Collections.emptyIterator();

            public boolean hasNext() {
                while (!valueIter.hasNext() && chunkIter.hasNext()) {
                    currentChunk = chunkIter.next();
                    valueIter = currentChunk.getValue().iterator();
                }
                return valueIter.hasNext();
            }

            public Integer next() {
                return (currentChunk.getKey() << 16) | valueIter.next();
            }
        };
    }

    // ─── Container interface ────────────────────────────────────────────────

    private interface Container {
        void add(int lowBits);
        boolean contains(int lowBits);
        long cardinality();
        Container and(Container other);
        Container or(Container other);
        Container andNot(Container other);
        Container copy();
        Iterator<Integer> iterator();
    }

    // ─── ArrayContainer ─────────────────────────────────────────────────────

    private class ArrayContainer implements Container {
        short[] values = new short[0];
        int size = 0;

        public void add(int v) {
            int idx = Arrays.binarySearch(values, 0, size, (short) v);
            if (idx >= 0) return; // duplicate
            idx = -(idx + 1);
            if (size == values.length) values = Arrays.copyOf(values, Math.max(4, size * 2));
            System.arraycopy(values, idx, values, idx + 1, size - idx);
            values[idx] = (short) v;
            size++;
            // Promote to BitmapContainer if dense
            if (size > ARRAY_THRESHOLD) promoteAndReplace();
        }

        private void promoteAndReplace() {
            // This would replace 'this' in the parent map — simplified: done in add() wrapper
        }

        public boolean contains(int v) {
            return Arrays.binarySearch(values, 0, size, (short) v) >= 0;
        }

        public long cardinality() { return size; }

        public Container and(Container other) {
            ArrayContainer result = new ArrayContainer();
            for (int i = 0; i < size; i++) {
                int v = values[i] & 0xFFFF;
                if (other.contains(v)) result.add(v);
            }
            return result;
        }

        public Container or(Container other) {
            if (other instanceof BitmapContainer) return other.or(this);
            ArrayContainer result = new ArrayContainer();
            for (int i = 0; i < size; i++) result.add(values[i] & 0xFFFF);
            Iterator<Integer> it = other.iterator();
            while (it.hasNext()) result.add(it.next());
            return result;
        }

        public Container andNot(Container other) {
            ArrayContainer result = new ArrayContainer();
            for (int i = 0; i < size; i++) {
                int v = values[i] & 0xFFFF;
                if (!other.contains(v)) result.add(v);
            }
            return result;
        }

        public Container copy() {
            ArrayContainer c = new ArrayContainer();
            c.values = Arrays.copyOf(values, size);
            c.size = size;
            return c;
        }

        public Iterator<Integer> iterator() {
            return new Iterator<>() {
                int i = 0;
                public boolean hasNext() { return i < size; }
                public Integer next() { return values[i++] & 0xFFFF; }
            };
        }
    }

    // ─── BitmapContainer ────────────────────────────────────────────────────

    private class BitmapContainer implements Container {
        long[] bitmap = new long[1024]; // 64 × 1024 = 65536 bits
        int cardinality = 0;

        public void add(int v) {
            int word = v >>> 6, bit = v & 63;
            long prev = bitmap[word];
            bitmap[word] |= (1L << bit);
            if (bitmap[word] != prev) cardinality++;
        }

        public boolean contains(int v) {
            return (bitmap[v >>> 6] & (1L << (v & 63))) != 0;
        }

        public long cardinality() { return cardinality; }

        public Container and(Container other) {
            if (other instanceof BitmapContainer bc) {
                BitmapContainer result = new BitmapContainer();
                for (int i = 0; i < 1024; i++) {
                    result.bitmap[i] = bitmap[i] & bc.bitmap[i];
                    result.cardinality += Long.bitCount(result.bitmap[i]);
                }
                return result.cardinality <= ARRAY_THRESHOLD ? toArray(result) : result;
            }
            return other.and(this);
        }

        public Container or(Container other) {
            if (other instanceof BitmapContainer bc) {
                BitmapContainer result = new BitmapContainer();
                for (int i = 0; i < 1024; i++) {
                    result.bitmap[i] = bitmap[i] | bc.bitmap[i];
                    result.cardinality += Long.bitCount(result.bitmap[i]);
                }
                return result;
            }
            BitmapContainer result = new BitmapContainer();
            System.arraycopy(bitmap, 0, result.bitmap, 0, 1024);
            result.cardinality = cardinality;
            Iterator<Integer> it = other.iterator();
            while (it.hasNext()) result.add(it.next());
            return result;
        }

        public Container andNot(Container other) {
            if (other instanceof BitmapContainer bc) {
                BitmapContainer result = new BitmapContainer();
                for (int i = 0; i < 1024; i++) {
                    result.bitmap[i] = bitmap[i] & ~bc.bitmap[i];
                    result.cardinality += Long.bitCount(result.bitmap[i]);
                }
                return result.cardinality <= ARRAY_THRESHOLD ? toArray(result) : result;
            }
            BitmapContainer result = (BitmapContainer) copy();
            Iterator<Integer> it = other.iterator();
            while (it.hasNext()) {
                int v = it.next();
                if (result.contains(v)) { result.bitmap[v >>> 6] &= ~(1L << (v & 63)); result.cardinality--; }
            }
            return result.cardinality <= ARRAY_THRESHOLD ? toArray(result) : result;
        }

        private Container toArray(BitmapContainer bc) {
            ArrayContainer ac = new ArrayContainer();
            for (Iterator<Integer> it = bc.iterator(); it.hasNext(); ) ac.add(it.next());
            return ac;
        }

        public Container copy() {
            BitmapContainer c = new BitmapContainer();
            System.arraycopy(bitmap, 0, c.bitmap, 0, 1024);
            c.cardinality = cardinality;
            return c;
        }

        public Iterator<Integer> iterator() {
            return new Iterator<>() {
                int word = 0;
                long bits = bitmap[0];
                public boolean hasNext() {
                    while (bits == 0 && word < 1023) bits = bitmap[++word];
                    return bits != 0;
                }
                public Integer next() {
                    int bit = Long.numberOfTrailingZeros(bits);
                    bits &= bits - 1;
                    return (word << 6) | bit;
                }
            };
        }
    }
}
```

### 3.2 Usage with RoaringBitmap library (production)

```java
import org.roaringbitmap.RoaringBitmap;

// Segment filter: users active in last 30 days
RoaringBitmap activeLast30 = new RoaringBitmap();
RoaringBitmap purchasedThisMonth = new RoaringBitmap();
RoaringBitmap mobileUsers = new RoaringBitmap();

// Populate from database/Kafka...
activeLast30.add(1, 5, 10, 15, 20);
purchasedThisMonth.add(5, 10, 25, 30);
mobileUsers.add(1, 5, 10, 15, 25, 30);

// "Active AND purchased AND mobile" — targeting segment
RoaringBitmap targetSegment = RoaringBitmap.and(
    RoaringBitmap.and(activeLast30, purchasedThisMonth),
    mobileUsers
);
System.out.println("Target users: " + targetSegment.getCardinality()); // fast!

// Serialise for storage / transfer
byte[] bytes = new byte[targetSegment.serializedSizeInBytes()];
targetSegment.serialize(new java.io.DataOutputStream(
    new java.io.ByteArrayOutputStream(bytes.length)));
```

---

## 4. How Druid Uses Roaring Bitmaps

```
Druid column storage (per segment file):
  Column "country":
    values:    [US, UK, DE, US, IN, UK, ...]
    dictionary: {US=0, UK=1, DE=2, IN=3}
    bitmap per value:
      US → RoaringBitmap {0, 3, 6, ...}  (row indices where country=US)
      UK → RoaringBitmap {1, 5, ...}
      DE → RoaringBitmap {2, ...}
      IN → RoaringBitmap {4, ...}

  Query: WHERE country IN ('US', 'UK') AND platform = 'mobile'
    → OR(bitmaps[US], bitmaps[UK])  → union result
    → AND with bitmaps[mobile]      → intersection
    → Resulting bitmap: row indices to read
    → Fetch only those rows from value columns
```

Without bitmaps: full column scan. With bitmaps: skip irrelevant rows at column-block granularity.

---

## 5. Trade-Offs vs Alternatives

| Approach | Memory (dense) | Memory (sparse) | AND/OR speed | Sorted iteration |
|---|---|---|---|---|
| `BitSet` (java.util) | Optimal (1 bit/elem) | Wasteful | Fast (SIMD) | O(N/64) |
| `HashSet<Integer>` | 32–48 bytes/elem | Good | Slow (hash lookup) | O(N log N) |
| `TreeSet<Integer>` | ~48 bytes/elem | Good | O(N) merge | O(N) |
| Roaring Bitmap | Near-optimal | Very good | Fastest (adaptive) | O(N/64) or O(k) |
| WAH/CONCISE | Good | OK | Good | Slower than Roaring |

**RoaringBitmap typically 3–5× faster than WAH and 2–4× smaller than plain BitSet for real-world datasets.**

---

## 6. Where Roaring Bitmaps Appear at FAANG

| System | Use | Notes |
|---|---|---|
| **Apache Druid** | Column segment filters | Per-column, per-value bitmaps; AND/OR for WHERE |
| **Clickhouse** | Bitmap functions | `bitmapAnd`, `bitmapOr` for cohort analysis |
| **Elasticsearch** | Document filter cache | Roaring bitmap per filter query per shard |
| **Apache Spark** | Bloom filter alternative | `RoaringBitmap` in exchange shuffle metadata |
| **Apache Lucene 9+** | DocID set intersections | `RoaringDocIdSet` in query execution |
| **LinkedIn** | Ad targeting segments | Audience segment intersection for ad delivery |
| **Pinterest** | Board membership | Which users follow which boards |

---

## 7. FAANG Interview Callouts

**"Design a real-time user segmentation system for ad targeting (100M users, 1000 segments):"**
> Store each segment as a Roaring Bitmap of user IDs, serialised to Redis or an object store. Segment intersection query (`segment_A AND segment_B`) = bitwise AND of two bitmaps. Memory: 1000 segments × ~10 MB average per segment (compressed) = ~10 GB, fits in a large Redis instance. Targeting latency: AND of two 100M-user bitmaps ≈ 3–5 ms on a single core. For sub-millisecond: shard by user ID range and run in parallel.

**"Why does Druid use bitmaps instead of a hash index?":**
> Druid's primary access pattern is: given a WHERE filter on a low-cardinality column, quickly determine which rows match. Bitmaps support fast AND/OR across multiple filter conditions and naturally compress sequential/run-length data. Hash indexes don't support range queries or multi-condition intersections at this speed. Roaring Bitmaps integrate with Druid's SIMD-accelerated query processing pipeline.

**Follow-up questions to expect:**
1. "How do you keep segment bitmaps up to date in real-time?" → Append-only: new user events trigger bitmap OR-updates. Batch rebuild nightly from full data. Incremental updates use a delta bitmap per minute-bucket, merged at query time.
2. "What's the memory overhead for a bitmap with 1M random IDs out of 100M?" → Dense: ~12.5 MB (100M bits). Roaring: ~1M × 2 bytes = 2 MB (array containers, 1M < 4096 × number_of_chunks). About 6× compression.
3. "Can Roaring Bitmaps represent user IDs that are UUIDs (128-bit)?" → Not directly — Roaring Bitmaps are for 32-bit (or extended 64-bit) integers. For UUIDs: map UUIDs to dense sequential integers via a dictionary, store the bitmap over the integer IDs. The dictionary is the expensive part; the bitmap operations remain fast.
