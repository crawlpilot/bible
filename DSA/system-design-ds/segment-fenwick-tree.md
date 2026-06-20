# Segment Tree & Fenwick Tree (BIT)
**Category**: Range Query Data Structures — used in analytics, leaderboards, time-series aggregation, interval queries

---

## 1. The Problem It Solves

### Range Queries on Mutable Arrays

Given an array of values, support two operations efficiently:
1. **Point update**: change `arr[i] = v`
2. **Range query**: compute aggregate (sum, min, max) over `arr[l..r]`

| Structure | Update | Range Query | Space |
|---|---|---|---|
| Plain array | O(1) | O(N) scan | O(N) |
| Prefix sum array | O(N) rebuild | O(1) | O(N) |
| **Fenwick Tree (BIT)** | **O(log N)** | **O(log N)** | O(N) |
| **Segment Tree** | **O(log N)** | **O(log N)** | O(4N) |

**Fenwick Tree (Binary Indexed Tree)**: simpler implementation, lower constant factor, supports prefix sums only (extends to range queries via two prefix queries).

**Segment Tree**: more general — supports arbitrary associative operations (sum, min, max, GCD, XOR, custom), range updates with lazy propagation, non-invertible operations.

---

## 2. Fenwick Tree (BIT)

### 2.1 Concept

Each index `i` in a Fenwick tree stores the sum of `lowbit(i)` elements ending at `i`, where `lowbit(i) = i & (-i)` extracts the lowest set bit.

```
Array:        [3, 2, -1, 6, 5, 4, -3, 3, 7, 2, 3]  (1-indexed)
Indices:       1  2   3  4  5  6   7  8  9 10 11

BIT[1]  = arr[1]               = 3    (covers 1 element)
BIT[2]  = arr[1] + arr[2]      = 5    (covers 2 elements, lowbit(2)=2)
BIT[3]  = arr[3]               = -1   (covers 1 element)
BIT[4]  = arr[1..4] sum        = 10   (covers 4 elements, lowbit(4)=4)
BIT[6]  = arr[5] + arr[6]      = 9    (covers 2 elements, lowbit(6)=2)
BIT[8]  = arr[1..8] sum        = 19   (covers 8 elements, lowbit(8)=8)
```

**prefix_sum(i)**: walk from `i` upward, stripping the lowest set bit each time.
**update(i, delta)**: walk from `i` downward, adding the lowest set bit each time.

### 2.2 Operations

```
prefix_sum(7):  BIT[7] + BIT[6] + BIT[4] = -3 + 9 + 10 = 16
  7  = 0b0111 → strip lowbit → 0b0110 = 6 → strip → 0b0100 = 4 → strip → 0 (stop)

range_sum(l, r) = prefix_sum(r) - prefix_sum(l - 1)

update(5, +2):  BIT[5] += 2, BIT[6] += 2, BIT[8] += 2, BIT[16] ...
  5 = 0b0101 → add lowbit → 0b0110 = 6 → add → 0b1000 = 8 → add → ...
```

---

## 3. Segment Tree

### 3.1 Concept

A complete binary tree where each node stores the aggregate (sum/min/max) of a range. Leaf nodes = individual elements. Internal nodes = combined result of children.

```
Array: [1, 3, 5, 7, 9, 11]

Segment tree (sum):
                  [0..5]=36
                /           \
          [0..2]=9         [3..5]=27
          /     \          /       \
      [0..1]=4 [2..2]=5 [3..4]=16 [5..5]=11
      /    \            /     \
  [0..0]=1 [1..1]=3 [3..3]=7 [4..4]=9
```

**Point update**: update the leaf, then propagate up O(log N) nodes.
**Range query**: decompose into O(log N) non-overlapping nodes, combine their values.

---

## 4. Java Implementation

### 4.1 Fenwick Tree (Sum)

```java
public class FenwickTree {

    private final long[] tree;
    private final int n;

    public FenwickTree(int n) {
        this.n = n;
        this.tree = new long[n + 1]; // 1-indexed
    }

    public FenwickTree(int[] arr) {
        this.n = arr.length;
        this.tree = new long[n + 1];
        for (int i = 0; i < n; i++) update(i + 1, arr[i]);
    }

    // Add delta to position i (1-indexed)
    public void update(int i, long delta) {
        for (; i <= n; i += i & (-i)) tree[i] += delta;
    }

    // Prefix sum [1..i] (1-indexed)
    public long prefixSum(int i) {
        long sum = 0;
        for (; i > 0; i -= i & (-i)) sum += tree[i];
        return sum;
    }

    // Range sum [l..r] (1-indexed, inclusive)
    public long rangeSum(int l, int r) {
        return prefixSum(r) - prefixSum(l - 1);
    }

    // Point query: value at index i
    public long pointQuery(int i) {
        return rangeSum(i, i);
    }

    // Set arr[i] = value (requires knowing current value)
    public void set(int i, long value) {
        update(i, value - pointQuery(i));
    }

    // Find smallest index with prefix sum >= target (binary search on BIT)
    public int findKth(long target) {
        int pos = 0;
        for (int pw = Integer.highestOneBit(n); pw > 0; pw >>= 1) {
            if (pos + pw <= n && tree[pos + pw] < target) {
                pos += pw;
                target -= tree[pos];
            }
        }
        return pos + 1;
    }
}
```

### 4.2 2D Fenwick Tree (for grid aggregations)

```java
public class FenwickTree2D {

    private final long[][] tree;
    private final int rows, cols;

    public FenwickTree2D(int rows, int cols) {
        this.rows = rows; this.cols = cols;
        this.tree = new long[rows + 1][cols + 1];
    }

    public void update(int r, int c, long delta) {
        for (int i = r; i <= rows; i += i & (-i))
            for (int j = c; j <= cols; j += j & (-j))
                tree[i][j] += delta;
    }

    public long prefixSum(int r, int c) {
        long sum = 0;
        for (int i = r; i > 0; i -= i & (-i))
            for (int j = c; j > 0; j -= j & (-j))
                sum += tree[i][j];
        return sum;
    }

    // Sum of rectangle [r1,c1] to [r2,c2] (1-indexed, inclusive)
    public long rangeSum(int r1, int c1, int r2, int c2) {
        return prefixSum(r2, c2)
             - prefixSum(r1 - 1, c2)
             - prefixSum(r2, c1 - 1)
             + prefixSum(r1 - 1, c1 - 1);
    }
}
```

### 4.3 Segment Tree (Sum, with Range Update via Lazy Propagation)

```java
public class SegmentTree {

    private final long[] tree;
    private final long[] lazy;
    private final int n;

    public SegmentTree(int[] arr) {
        this.n = arr.length;
        this.tree = new long[4 * n];
        this.lazy = new long[4 * n];
        build(arr, 1, 0, n - 1);
    }

    private void build(int[] arr, int node, int start, int end) {
        if (start == end) { tree[node] = arr[start]; return; }
        int mid = (start + end) / 2;
        build(arr, 2 * node, start, mid);
        build(arr, 2 * node + 1, mid + 1, end);
        tree[node] = tree[2 * node] + tree[2 * node + 1];
    }

    private void pushDown(int node, int start, int end) {
        if (lazy[node] != 0) {
            int mid = (start + end) / 2;
            tree[2 * node]     += lazy[node] * (mid - start + 1);
            tree[2 * node + 1] += lazy[node] * (end - mid);
            lazy[2 * node]     += lazy[node];
            lazy[2 * node + 1] += lazy[node];
            lazy[node] = 0;
        }
    }

    // Point update: arr[i] += delta (0-indexed)
    public void pointUpdate(int i, long delta) {
        pointUpdate(1, 0, n - 1, i, delta);
    }

    private void pointUpdate(int node, int start, int end, int i, long delta) {
        if (start == end) { tree[node] += delta; return; }
        pushDown(node, start, end);
        int mid = (start + end) / 2;
        if (i <= mid) pointUpdate(2 * node, start, mid, i, delta);
        else          pointUpdate(2 * node + 1, mid + 1, end, i, delta);
        tree[node] = tree[2 * node] + tree[2 * node + 1];
    }

    // Range update: add delta to all arr[l..r] (0-indexed, inclusive)
    public void rangeUpdate(int l, int r, long delta) {
        rangeUpdate(1, 0, n - 1, l, r, delta);
    }

    private void rangeUpdate(int node, int start, int end, int l, int r, long delta) {
        if (r < start || end < l) return;
        if (l <= start && end <= r) {
            tree[node] += delta * (end - start + 1);
            lazy[node] += delta;
            return;
        }
        pushDown(node, start, end);
        int mid = (start + end) / 2;
        rangeUpdate(2 * node, start, mid, l, r, delta);
        rangeUpdate(2 * node + 1, mid + 1, end, l, r, delta);
        tree[node] = tree[2 * node] + tree[2 * node + 1];
    }

    // Range sum query [l..r] (0-indexed, inclusive)
    public long rangeQuery(int l, int r) {
        return rangeQuery(1, 0, n - 1, l, r);
    }

    private long rangeQuery(int node, int start, int end, int l, int r) {
        if (r < start || end < l) return 0;
        if (l <= start && end <= r) return tree[node];
        pushDown(node, start, end);
        int mid = (start + end) / 2;
        return rangeQuery(2 * node, start, mid, l, r)
             + rangeQuery(2 * node + 1, mid + 1, end, l, r);
    }
}
```

### 4.4 Segment Tree (Range Min with Lazy Propagation)

```java
public class RangeMinSegmentTree {

    private final long[] tree, lazy;
    private final int n;
    private static final long INF = Long.MAX_VALUE / 2;

    public RangeMinSegmentTree(int n) {
        this.n = n;
        tree = new long[4 * n];
        lazy = new long[4 * n];
        Arrays.fill(tree, INF);
    }

    public void update(int l, int r, long val) { update(1, 0, n - 1, l, r, val); }
    public long query(int l, int r)            { return query(1, 0, n - 1, l, r); }

    private void push(int node) {
        if (lazy[node] != 0) {
            for (int child : new int[]{2 * node, 2 * node + 1}) {
                tree[child] = Math.min(tree[child], lazy[node]);
                lazy[child] = Math.min(lazy[child], lazy[node]);
            }
            lazy[node] = 0;
        }
    }

    private void update(int node, int s, int e, int l, int r, long val) {
        if (r < s || e < l) return;
        if (l <= s && e <= r) {
            tree[node] = Math.min(tree[node], val);
            lazy[node] = Math.min(lazy[node], val);
            return;
        }
        push(node);
        int m = (s + e) / 2;
        update(2 * node, s, m, l, r, val);
        update(2 * node + 1, m + 1, e, l, r, val);
        tree[node] = Math.min(tree[2 * node], tree[2 * node + 1]);
    }

    private long query(int node, int s, int e, int l, int r) {
        if (r < s || e < l) return INF;
        if (l <= s && e <= r) return tree[node];
        push(node);
        int m = (s + e) / 2;
        return Math.min(query(2 * node, s, m, l, r),
                        query(2 * node + 1, m + 1, e, l, r));
    }
}
```

### 4.5 System Design Application: Real-Time Analytics

```java
import java.util.concurrent.ConcurrentHashMap;

public class TimeSeriesAggregator {

    // 1-hour window at 1-second resolution = 3600 slots
    private static final int SLOTS = 3600;
    private final FenwickTree countTree  = new FenwickTree(SLOTS);
    private final FenwickTree revenueTree = new FenwickTree(SLOTS);
    private int currentSlot = 0;

    public void recordEvent(long timestampMs, double revenueUsd) {
        int slot = (int) ((timestampMs / 1000) % SLOTS) + 1; // 1-indexed
        countTree.update(slot, 1);
        revenueTree.update(slot, (long)(revenueUsd * 100)); // store cents
    }

    // Total events in last N seconds
    public long eventsInLastSeconds(int seconds) {
        int end = currentSlot;
        int start = Math.max(1, end - seconds + 1);
        return countTree.rangeSum(start, end);
    }

    // Total revenue in last N seconds (in dollars)
    public double revenueInLastSeconds(int seconds) {
        int end = currentSlot;
        int start = Math.max(1, end - seconds + 1);
        return revenueTree.rangeSum(start, end) / 100.0;
    }

    // Rank of a score in a leaderboard (how many players have score ≤ x)
    public static class ScoreLeaderboard {
        private static final int MAX_SCORE = 1_000_000;
        private final FenwickTree scores = new FenwickTree(MAX_SCORE);

        public void addScore(int score) { scores.update(score, 1); }
        public void removeScore(int score) { scores.update(score, -1); }

        // How many players have score <= x
        public long rank(int score) { return scores.prefixSum(score); }

        // Score of the k-th percentile player
        public int percentileScore(double percentile, int totalPlayers) {
            long target = (long)(percentile * totalPlayers / 100.0);
            return scores.findKth(target);
        }
    }
}
```

---

## 5. Fenwick Tree vs Segment Tree

| Attribute | Fenwick Tree | Segment Tree |
|---|---|---|
| Implementation | ~20 lines | ~80–100 lines |
| Point update | O(log N) | O(log N) |
| Range query | O(log N) | O(log N) |
| Range update | O(log N) with BIT difference array | O(log N) with lazy |
| Non-invertible ops (min/max) | Not directly | Yes |
| 2D support | O(log² N) | Complex |
| Memory | O(N) | O(4N) |
| Constant factor | Very low | ~2× BIT |

**Rule of thumb**: use Fenwick Tree for sum/count queries (simpler, faster). Use Segment Tree when you need min/max, custom merge functions, or complex range updates with lazy propagation.

---

## 6. Where These Appear in System Design

| System | Use | Structure |
|---|---|---|
| **Druid / ClickHouse** | Approximate range aggregations | Segment tree per time partition |
| **Apache Flink** | Keyed state range aggregations | Fenwick tree for sliding window sums |
| **Elasticsearch** | Date histogram aggregations | Pre-computed per-bucket counts (BIT-like) |
| **Database engines** | Count/sum in B+ tree nodes | Augmented B+ tree (sum stored per node) |
| **Redis ZADD** | Rank computation in skip list | Per-level span counts (BIT equivalent) |
| **Ad auctions** | Budget pacing (spend rate) | Fenwick tree over time slots |
| **Gaming leaderboards** | Percentile rank | BIT over score distribution |

---

## 7. FAANG Interview Callouts

**"Design a leaderboard that supports: add score, remove score, get rank of user, get top-K:"**
> Use a Fenwick Tree over the score domain [0, MAX_SCORE]. Add score → `update(score, +1)`. Remove → `update(score, -1)`. Rank of user with score X → `prefixSum(X)` = number of players with score ≤ X, O(log MAX_SCORE). Top-K → binary search on prefixSum to find the score threshold, O(log² N). Redis ZADD does exactly this internally with its skip list span counts.

**"How would you answer 'total purchases in the last N seconds' efficiently at 100K events/sec?"**
> Circular Fenwick Tree over time slots (1-second resolution). On event: `update(slot, 1)`. Query last N seconds: `rangeSum(currentSlot - N + 1, currentSlot)`, O(log slots). Slot count = window in seconds. Reset: on each tick advance current slot, zero-out the new slot before writing. Memory: 3600 slots × 8 bytes = 28 KB for a 1-hour window.

**Follow-up questions to expect:**
1. "What if the score range is too large for a Fenwick Tree?" → Coordinate compress: map actual scores to rank 0..K where K = distinct scores. Use a sorted set to maintain the mapping. Or use a balanced BST (treap/skip list) with augmented subtree counts — Redis does this.
2. "How do you handle concurrent updates to a Fenwick Tree?" → Either add a `synchronized` block per update (acceptable if update rate < 1M/s), or shard by key range and run one BIT per shard with independent locks, or use a lock-free variant with `AtomicLongArray` (valid for pure additions with no reads of intermediate state).
3. "Can a Segment Tree support dynamic inserts (new elements, not just updates)?" → Not natively — it's built over a fixed array. For dynamic inserts: use a balanced BST with augmented subtree sums (an order-statistics tree), or rebuild the segment tree periodically from sorted data, or use a BTree with per-node aggregates.
