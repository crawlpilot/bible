# Segment Tree & Fenwick Tree (BIT)

> When you need **both** point updates **and** range queries (sum, min, max) in O(log n), a plain prefix-sum array won't work. Segment Tree gives O(log n) for both; Fenwick Tree (BIT) gives O(log n) with a simpler implementation when the operation is invertible (sum, XOR).

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem need **range queries** (sum/min/max from index L to R)?
- [ ] Are there **point updates** (change a single element) between queries?
- [ ] Does it ask for **count of elements in a range** satisfying a condition?
- [ ] Is there a need for **range updates + range queries** (lazy propagation)?
- [ ] Does the problem involve "count of smaller/larger elements to the right/left"?

**Trigger phrases**: "update index, query range", "range sum with updates", "count of inversions", "count smaller numbers after self", "number of range sum ≥ k", "maximum subarray sum after updates"

**When to choose which**:
| Problem | Use |
|---------|-----|
| Range sum + point update | Fenwick Tree (BIT) — simpler |
| Range min/max + point update | Segment Tree |
| Range sum + range update | Segment Tree with Lazy Propagation |
| Count of elements in range | Coordinate-compressed Fenwick or Segment Tree |
| 2D range sum + updates | 2D Fenwick Tree |

---

## 2 — Fenwick Tree (Binary Indexed Tree)

### Core Idea

**Trick**: `i & (-i)` isolates the lowest set bit of `i`. Each index `i` in the BIT array stores the sum of `freq[(i - lowbit + 1)..i]`, where `lowbit = i & (-i)`.

- **Update**: add delta at position `i`, then move to `i + (i & -i)` (next responsible index).
- **Query prefix sum [1..i]**: sum positions `i`, then `i - (i & -i)`, repeatedly until 0.

```java
class FenwickTree {
    private final int[] tree;
    private final int n;

    FenwickTree(int n) {
        this.n = n;
        this.tree = new int[n + 1];   // 1-indexed
    }

    // Add delta at position i (1-indexed)
    void update(int i, int delta) {
        for (; i <= n; i += i & (-i))
            tree[i] += delta;
    }

    // Prefix sum [1..i]
    int query(int i) {
        int sum = 0;
        for (; i > 0; i -= i & (-i))
            sum += tree[i];
        return sum;
    }

    // Range sum [l..r] (1-indexed)
    int query(int l, int r) {
        return query(r) - query(l - 1);
    }
}
```

**Build from array in O(n)**:
```java
FenwickTree buildFromArray(int[] arr) {
    FenwickTree bt = new FenwickTree(arr.length);
    for (int i = 0; i < arr.length; i++)
        bt.update(i + 1, arr[i]);   // 1-indexed
    return bt;
}
```

**Time**: O(log n) per update and query. **Space**: O(n).

---

## 3 — Segment Tree (Point Update, Range Query)

### Core Idea

Build a **complete binary tree** where:
- Leaf nodes hold individual array values.
- Internal nodes hold the aggregate (sum / min / max) of their subtree.
- Parent of node `i` is `i/2`; children of `i` are `2i` (left) and `2i+1` (right).
- Tree array has size `4n` to be safe (2 × next power of 2).

```java
class SegmentTree {
    private final int[] tree;
    private final int n;

    SegmentTree(int[] arr) {
        n = arr.length;
        tree = new int[4 * n];
        build(arr, 1, 0, n - 1);
    }

    private void build(int[] arr, int node, int start, int end) {
        if (start == end) {
            tree[node] = arr[start];
        } else {
            int mid = (start + end) / 2;
            build(arr, 2 * node, start, mid);
            build(arr, 2 * node + 1, mid + 1, end);
            tree[node] = tree[2 * node] + tree[2 * node + 1];   // change to Math.min/max for min/max tree
        }
    }

    // Update arr[idx] to val
    void update(int node, int start, int end, int idx, int val) {
        if (start == end) {
            tree[node] = val;
        } else {
            int mid = (start + end) / 2;
            if (idx <= mid) update(2 * node, start, mid, idx, val);
            else            update(2 * node + 1, mid + 1, end, idx, val);
            tree[node] = tree[2 * node] + tree[2 * node + 1];
        }
    }

    // Range sum query [l..r]
    int query(int node, int start, int end, int l, int r) {
        if (r < start || end < l) return 0;          // out of range → identity element (0 for sum, INF for min)
        if (l <= start && end <= r) return tree[node]; // fully inside range
        int mid = (start + end) / 2;
        return query(2 * node, start, mid, l, r)
             + query(2 * node + 1, mid + 1, end, l, r);
    }

    // Convenience wrappers (root=1, range=[0, n-1])
    void update(int idx, int val)   { update(1, 0, n - 1, idx, val); }
    int  query(int l, int r)        { return query(1, 0, n - 1, l, r); }
}
```

**Time**: O(n) build, O(log n) update/query. **Space**: O(n).

---

## 4 — Segment Tree with Lazy Propagation (Range Update)

When you need to **update a range** (add delta to all elements in [l..r]) AND query a range, you need lazy propagation to defer updates.

```java
class LazySegTree {
    int[] tree, lazy;
    int n;

    LazySegTree(int[] arr) {
        n = arr.length;
        tree = new int[4 * n];
        lazy = new int[4 * n];
        build(arr, 1, 0, n - 1);
    }

    void build(int[] arr, int node, int s, int e) {
        if (s == e) { tree[node] = arr[s]; return; }
        int m = (s + e) / 2;
        build(arr, 2*node, s, m);
        build(arr, 2*node+1, m+1, e);
        tree[node] = tree[2*node] + tree[2*node+1];
    }

    void pushDown(int node, int s, int e) {
        if (lazy[node] != 0) {
            int m = (s + e) / 2;
            // Apply lazy to children
            tree[2*node]   += lazy[node] * (m - s + 1);
            tree[2*node+1] += lazy[node] * (e - m);
            lazy[2*node]   += lazy[node];
            lazy[2*node+1] += lazy[node];
            lazy[node] = 0;
        }
    }

    // Range update: add delta to all elements in [l..r]
    void update(int node, int s, int e, int l, int r, int delta) {
        if (r < s || e < l) return;
        if (l <= s && e <= r) {
            tree[node] += delta * (e - s + 1);
            lazy[node] += delta;
            return;
        }
        pushDown(node, s, e);
        int m = (s + e) / 2;
        update(2*node, s, m, l, r, delta);
        update(2*node+1, m+1, e, l, r, delta);
        tree[node] = tree[2*node] + tree[2*node+1];
    }

    int query(int node, int s, int e, int l, int r) {
        if (r < s || e < l) return 0;
        if (l <= s && e <= r) return tree[node];
        pushDown(node, s, e);
        int m = (s + e) / 2;
        return query(2*node, s, m, l, r) + query(2*node+1, m+1, e, l, r);
    }

    void update(int l, int r, int delta) { update(1, 0, n-1, l, r, delta); }
    int  query(int l, int r)             { return query(1, 0, n-1, l, r); }
}
```

---

## 5 — Count Smaller Numbers After Self (LC 315) — Coordinate Compression + BIT

**Key pattern**: "count of elements to the right that are smaller" → process from RIGHT to LEFT, use BIT to count how many elements already processed are less than current.

```java
List<Integer> countSmaller(int[] nums) {
    int n = nums.length;
    // Coordinate compress: map values to 1..m
    int[] sorted = nums.clone();
    Arrays.sort(sorted);
    // rank[i] = compressed rank of nums[i]
    Map<Integer, Integer> rank = new HashMap<>();
    int r = 1;
    for (int v : sorted) rank.putIfAbsent(v, r++);

    FenwickTree bt = new FenwickTree(rank.size());
    Integer[] result = new Integer[n];

    for (int i = n - 1; i >= 0; i--) {
        int compressedRank = rank.get(nums[i]);
        result[i] = compressedRank > 1 ? bt.query(compressedRank - 1) : 0;
        bt.update(compressedRank, 1);
    }
    return Arrays.asList(result);
}
// Time: O(n log n), Space: O(n)
```

---

## 6 — Range Sum Query (Mutable) — LC 307

Classic textbook problem: update index, query range sum.

```java
class NumArray {
    private FenwickTree bt;
    private int[] nums;

    NumArray(int[] nums) {
        this.nums = nums.clone();
        bt = new FenwickTree(nums.length);
        for (int i = 0; i < nums.length; i++) bt.update(i + 1, nums[i]);
    }

    void update(int index, int val) {
        int delta = val - nums[index];
        nums[index] = val;
        bt.update(index + 1, delta);   // BIT is 1-indexed
    }

    int sumRange(int left, int right) {
        return bt.query(left + 1, right + 1);  // convert 0-indexed to 1-indexed
    }
}
```

---

## 7 — Complexity Reference

| Operation | Array (prefix sum) | Fenwick Tree | Segment Tree |
|-----------|--------------------|--------------|--------------|
| Build | O(n) | O(n log n) | O(n) |
| Point update | O(n) rebuild | O(log n) | O(log n) |
| Range query | O(1) | O(log n) | O(log n) |
| Range update | O(n) | Not directly | O(log n) with lazy |
| Space | O(n) | O(n) | O(4n) |

---

## 8 — FAANG Interview Moves

1. **Choose BIT when possible**: If the operation is commutative, associative, and has an inverse (sum, XOR) → BIT is simpler to code correctly. Min/Max have no inverse → must use Segment Tree.
2. **1-indexed is non-negotiable for BIT**: The trick `i & (-i)` breaks at index 0. Always convert from 0-indexed problem to 1-indexed BIT.
3. **Coordinate compression**: When values are large (up to 10⁹) but count is small (≤ 10⁵), compress to rank [1..n] before inserting into BIT or Segment Tree.
4. **Lazy propagation is O(log n) amortized**: The deferred update only propagates when you need to visit children — so each node is visited O(log n) times total.
5. **Identity element**: For sum = 0, for min = +∞, for max = -∞. Use the right identity in out-of-range returns.

---

## 9 — Visual: Fenwick Tree Structure

```
Array (1-indexed): [1, 3, 5, 7, 9, 11]
Index:              1  2  3  4  5   6

BIT stores:
  tree[1] = arr[1]            = 1      (lowbit=1, covers [1,1])
  tree[2] = arr[1]+arr[2]     = 4      (lowbit=2, covers [1,2])
  tree[3] = arr[3]            = 5      (lowbit=1, covers [3,3])
  tree[4] = arr[1..4]         = 16     (lowbit=4, covers [1,4])
  tree[5] = arr[5]            = 9      (lowbit=1, covers [5,5])
  tree[6] = arr[5]+arr[6]     = 20     (lowbit=2, covers [5,6])

query(5) = prefix sum [1..5]:
  i=5 → sum += tree[5]=9;    i = 5 - (5&-5) = 5 - 1 = 4
  i=4 → sum += tree[4]=16;   i = 4 - (4&-4) = 4 - 4 = 0
  i=0 → stop.   sum = 25 ✓  (1+3+5+7+9=25)

update(3, +2):   add 2 at position 3
  i=3 → tree[3] += 2;  i = 3 + (3&-3) = 3 + 1 = 4
  i=4 → tree[4] += 2;  i = 4 + (4&-4) = 4 + 4 = 8 > n → stop
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an integer array `nums`, return an array `result` where `result[i]` is the count of numbers in the right part of the array that are strictly smaller than `nums[i]`. *(LC 315 variant — but let's build from scratch.)*

**Step 1 — Read**: Input = `int[] nums`. Output = `int[]` where `result[i]` = count of `j > i` with `nums[j] < nums[i]`.

**Step 2 — Identify**: For each index, we need to count future (right-side) elements smaller than the current. Brute force = O(n²). If we process RIGHT to LEFT and maintain a sorted frequency structure, each query becomes "how many inserted values are < current". A Fenwick Tree over coordinate-compressed values gives O(log n) per step.

**Step 3 — Plan**:
1. Coordinate compress: map values to ranks 1..m (m = number of distinct values).
2. Process from right to left. For `nums[i]` with compressed rank `r`:
   - `result[i]` = `bt.query(r - 1)` (count of values with rank < r already inserted).
   - `bt.update(r, 1)` (record this value as inserted).
3. Return result.

**Step 4 — Code**:
```java
int[] countSmallerAfterSelf(int[] nums) {
    int n = nums.length;
    int[] sorted = nums.clone();
    Arrays.sort(sorted);

    // Coordinate compress
    Map<Integer, Integer> rank = new HashMap<>();
    int r = 1;
    for (int v : sorted) rank.putIfAbsent(v, r++);

    int m = rank.size();
    int[] tree = new int[m + 1];   // inline BIT
    int[] result = new int[n];

    for (int i = n - 1; i >= 0; i--) {
        int cr = rank.get(nums[i]);
        // query prefix [1..cr-1]
        int cnt = 0;
        for (int j = cr - 1; j > 0; j -= j & (-j)) cnt += tree[j];
        result[i] = cnt;
        // update position cr
        for (int j = cr; j <= m; j += j & (-j)) tree[j]++;
    }
    return result;
}
// Time: O(n log n), Space: O(n)
```

**Step 5 — Verify** on `[5, 2, 6, 1]`:
- Ranks: {1:1, 2:2, 5:3, 6:4}.
- Process right to left:
  - i=3: nums[3]=1, rank=1. query(0)=0. result[3]=0. update rank 1.
  - i=2: nums[2]=6, rank=4. query(3)=count of 1,2,3 = 1. result[2]=1. update rank 4.
  - i=1: nums[1]=2, rank=2. query(1)=1. result[1]=1. update rank 2.
  - i=0: nums[0]=5, rank=3. query(2)=2 (ranks 1 and 2 inserted). result[0]=2.
- Output: [2, 1, 1, 0]. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| BIT index 0 | `i & (-i)` = 0 → infinite loop | All BIT operations must use 1-indexed; add 1 to 0-indexed inputs |
| Negative values in coordinate compression | Negative ranks break BIT | Shift all values: `val - min_val + 1` before compression |
| Segment Tree size | `4 * n` might not be enough for odd n | Use `4 * n` always (safe upper bound) or next power of 2 |
| Range update + range query (lazy) | Without pushDown, children see stale values | Call `pushDown(node, s, e)` at the start of every non-leaf visit |
| Duplicate values in BIT | `rank.putIfAbsent` handles: duplicates get same rank | Correct — count of rank r = frequency of that value |
| Max segment tree returns wrong minimum | Using sum as aggregate but need min | Change merge: `tree[node] = Math.min(tree[2*node], tree[2*node+1])` and identity = Integer.MAX_VALUE |

```java
// Segment Tree for RANGE MINIMUM (change 3 lines):
// Build:    tree[node] = Math.min(tree[2*node], tree[2*node+1]);
// Update:   tree[node] = Math.min(tree[2*node], tree[2*node+1]);
// Out-of-range return: return Integer.MAX_VALUE;  (not 0)

// Coordinate compression template (reusable):
int[] vals = Arrays.stream(nums).distinct().sorted().toArray();
Map<Integer, Integer> rank = new HashMap<>();
for (int i = 0; i < vals.length; i++) rank.put(vals[i], i + 1);  // 1-indexed rank
```

---

## 😵 Commonly Confused With

**vs Prefix Sum Array**: Prefix sum is O(1) per query but O(n) per update. Segment Tree / BIT gives O(log n) for BOTH. Deciding question: *Are there updates after building the array? If yes → Segment Tree/BIT. If query-only → simple prefix sum.*

**vs Sorted Array / TreeMap for range queries**: A TreeMap `headMap(x).size()` gives rank queries in O(log n). For counting problems, BIT with coordinate compression is equivalent but faster in practice. Deciding question: *Do you need the actual elements in sorted order (TreeMap), or just counts/sums in a range (BIT)?*

**vs Merge Sort (for inversion count)**: Merge sort counts inversions in O(n log n) in one pass. BIT with coordinate compression also does O(n log n). Deciding question: *One-time count of all inversions (merge sort — no extra space for BIT), or repeated queries after dynamic updates (BIT)?*

---

## 10 — Canonical LeetCode Problems

| Problem | Approach |
|---------|----------|
| LC 307 — Range Sum Query Mutable | Fenwick Tree (point update, range sum) |
| LC 315 — Count of Smaller Numbers After Self | BIT + coordinate compression, right-to-left |
| LC 493 — Reverse Pairs | BIT + coord compression OR merge sort |
| LC 2250 — Count Number of Rectangles Containing Each Point | BIT + coordinate compression |
| LC 327 — Count of Range Sum | Merge sort or BIT on prefix sums |
| LC 732 — My Calendar III | Segment Tree with lazy propagation |
| LC 218 — Skyline Problem | Segment Tree or sorted map + sweep |
| LC 1649 — Create Sorted Array through Instructions | BIT + coordinate compression |
