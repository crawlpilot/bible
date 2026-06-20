# Prefix Sum

> Precompute a running cumulative sum so that any range query `sum(i, j)` costs O(1) instead of O(n). Extend to 2D for matrix range queries.

---

## 1 — How to Recognize This Pattern

Ask yourself ALL of these:
- [ ] Problem asks for **sum of a subarray / submatrix** repeatedly
- [ ] You need to count subarrays whose sum equals / at most / at least some value K
- [ ] Multiple range queries on a static array
- [ ] Brute force recomputes the sum from scratch each time → O(n) per query

**Trigger phrases**: "subarray sum equals k", "range sum query", "number of subarrays with sum divisible by k", "sum between indices i and j", "product of array except self", "minimum size subarray sum"

**Key insight**: `sum(i, j) = prefix[j+1] - prefix[i]`

---

## 2 — Flavor Detection

| Flavor | Signal | Technique |
|--------|--------|-----------|
| **1D range sum** | Static array, many range queries | `prefix[i] = prefix[i-1] + arr[i]` |
| **Subarray sum = K** | Count subarrays with exact sum | HashMap: count of `prefix[i] - K` seen so far |
| **Subarray sum divisible by K** | Modular condition | HashMap on `prefix[i] % K` (normalize negative mods) |
| **Max subarray sum** | Kadane's variant | Running min prefix sum |
| **2D prefix sum** | Submatrix sum queries | `prefix[r][c] = arr[r][c] + prefix[r-1][c] + prefix[r][c-1] - prefix[r-1][c-1]` |
| **Product except self** | No division allowed | Left product pass + right product pass |
| **Binary indexed tree** | Range sum + point updates | Fenwick Tree (see system-design-ds) |

---

## 3 — 1D Prefix Sum

```java
// Build prefix array — O(n) time, O(n) space
// prefix[i] = sum of arr[0..i-1]  (1-indexed, prefix[0] = 0 sentinel)
int[] buildPrefix(int[] arr) {
    int[] prefix = new int[arr.length + 1];
    for (int i = 0; i < arr.length; i++)
        prefix[i + 1] = prefix[i] + arr[i];
    return prefix;
}

// Range sum query — O(1) time
int rangeSum(int[] prefix, int i, int j) {
    return prefix[j + 1] - prefix[i];   // sum of arr[i..j] inclusive
}
```

**Range Sum Query — Immutable (LC 303)**:
```java
class NumArray {
    private int[] prefix;

    NumArray(int[] nums) {
        prefix = new int[nums.length + 1];
        for (int i = 0; i < nums.length; i++)
            prefix[i + 1] = prefix[i] + nums[i];
    }

    int sumRange(int left, int right) {
        return prefix[right + 1] - prefix[left];
    }
}
// Constructor: O(n), Query: O(1), Space: O(n)
```

---

## 4 — Subarray Sum Equals K (LC 560) — Most Important

**Key insight**: `sum(i, j) = K` means `prefix[j] - prefix[i-1] = K`, i.e., we've seen `prefix[j] - K` before.

```java
int subarraySum(int[] nums, int k) {
    Map<Integer, Integer> countMap = new HashMap<>();
    countMap.put(0, 1);     // empty prefix has sum 0 — critical base case

    int prefixSum = 0, result = 0;
    for (int num : nums) {
        prefixSum += num;
        // How many times have we seen prefixSum - k?
        result += countMap.getOrDefault(prefixSum - k, 0);
        countMap.merge(prefixSum, 1, Integer::sum);
    }
    return result;
}
// Time: O(n), Space: O(n)
```

**Why `countMap.put(0, 1)`?**: Handles the case where a prefix itself equals K (subarray starts at index 0).

---

## 5 — Subarray Sum Divisible by K (LC 974)

**Key insight**: `(prefix[j] - prefix[i]) % K == 0` means `prefix[j] % K == prefix[i] % K`.  
Count pairs with the same remainder.

```java
int subarraysDivByK(int[] nums, int k) {
    Map<Integer, Integer> remCount = new HashMap<>();
    remCount.put(0, 1);   // base case: empty prefix, remainder 0

    int prefixSum = 0, result = 0;
    for (int num : nums) {
        prefixSum += num;
        int rem = ((prefixSum % k) + k) % k;   // normalize negative modulo
        result += remCount.getOrDefault(rem, 0);
        remCount.merge(rem, 1, Integer::sum);
    }
    return result;
}
// Time: O(n), Space: O(k)
```

**Why `((prefixSum % k) + k) % k`?** Java's `%` returns negative values for negative inputs. Adding `k` before taking mod again normalizes to [0, k-1].

---

## 6 — Continuous Subarray Sum (Multiple of K) (LC 523)

Goal: find if there's a subarray of length ≥ 2 with sum divisible by K.

```java
boolean checkSubarraySum(int[] nums, int k) {
    Map<Integer, Integer> remToIndex = new HashMap<>();
    remToIndex.put(0, -1);   // base case: sum 0 at index -1

    int prefixSum = 0;
    for (int i = 0; i < nums.length; i++) {
        prefixSum += nums[i];
        int rem = prefixSum % k;
        if (remToIndex.containsKey(rem)) {
            if (i - remToIndex.get(rem) >= 2) return true;  // length >= 2
        } else {
            remToIndex.put(rem, i);   // only store FIRST occurrence
        }
    }
    return false;
}
// Time: O(n), Space: O(k)
```

---

## 7 — Longest Subarray with Sum ≤ K (Sliding Window Alternative)

When all elements are **positive**, use sliding window. When elements can be **negative**, use prefix sum + binary search or deque.

```java
// All positives: sliding window
int longestSubarrayPositive(int[] nums, int k) {
    int left = 0, sum = 0, maxLen = 0;
    for (int right = 0; right < nums.length; right++) {
        sum += nums[right];
        while (sum > k) sum -= nums[left++];
        maxLen = Math.max(maxLen, right - left + 1);
    }
    return maxLen;
}

// With negatives: prefix sum + sorted structure
// Variant: Maximum Size Subarray Sum Equals k (LC 325)
int maxSubArrayLen(int[] nums, int k) {
    Map<Integer, Integer> firstSeen = new HashMap<>();
    firstSeen.put(0, -1);
    int prefixSum = 0, maxLen = 0;
    for (int i = 0; i < nums.length; i++) {
        prefixSum += nums[i];
        if (firstSeen.containsKey(prefixSum - k))
            maxLen = Math.max(maxLen, i - firstSeen.get(prefixSum - k));
        firstSeen.putIfAbsent(prefixSum, i);   // only store FIRST occurrence for max length
    }
    return maxLen;
}
```

---

## 8 — 2D Prefix Sum (Matrix Range Sum)

```java
class NumMatrix {
    private int[][] prefix;

    NumMatrix(int[][] matrix) {
        int m = matrix.length, n = matrix[0].length;
        prefix = new int[m + 1][n + 1];       // 1-indexed

        for (int r = 1; r <= m; r++)
            for (int c = 1; c <= n; c++)
                prefix[r][c] = matrix[r-1][c-1]
                             + prefix[r-1][c]
                             + prefix[r][c-1]
                             - prefix[r-1][c-1];   // inclusion-exclusion
    }

    // Sum of submatrix from (r1,c1) to (r2,c2) — 0-indexed
    int sumRegion(int r1, int c1, int r2, int c2) {
        return prefix[r2+1][c2+1]
             - prefix[r1][c2+1]
             - prefix[r2+1][c1]
             + prefix[r1][c1];                     // add back double-subtracted corner
    }
}
// Constructor: O(m*n), Query: O(1), Space: O(m*n)
// LC 304 — Range Sum Query 2D
```

**2D inclusion-exclusion formula** (memorize this):
```
prefix[r][c] = grid[r][c]
             + prefix[r-1][c]    ← top
             + prefix[r][c-1]    ← left
             - prefix[r-1][c-1]  ← top-left added twice, remove once
```

---

## 9 — Number of Submatrices That Sum to Target (LC 1074)

Fix top and bottom row boundaries, then reduce to 1D subarray sum = target.

```java
int numSubmatrixSumTarget(int[][] matrix, int target) {
    int m = matrix.length, n = matrix[0].length;
    // Compute row-wise prefix sum in-place
    for (int[] row : matrix)
        for (int c = 1; c < n; c++)
            row[c] += row[c-1];

    int count = 0;
    for (int c1 = 0; c1 < n; c1++) {
        for (int c2 = c1; c2 < n; c2++) {
            // Column sum from c1..c2 for each row is matrix[r][c2] - (c1>0 ? matrix[r][c1-1] : 0)
            Map<Integer, Integer> map = new HashMap<>();
            map.put(0, 1);
            int prefixSum = 0;
            for (int r = 0; r < m; r++) {
                prefixSum += matrix[r][c2] - (c1 > 0 ? matrix[r][c1-1] : 0);
                count += map.getOrDefault(prefixSum - target, 0);
                map.merge(prefixSum, 1, Integer::sum);
            }
        }
    }
    return count;
}
// Time: O(n² × m), Space: O(m)
```

---

## 10 — Product of Array Except Self (LC 238)

No division allowed → left product pass + right product pass.

```java
int[] productExceptSelf(int[] nums) {
    int n = nums.length;
    int[] result = new int[n];

    // Left pass: result[i] = product of all nums[0..i-1]
    result[0] = 1;
    for (int i = 1; i < n; i++)
        result[i] = result[i-1] * nums[i-1];

    // Right pass: multiply by product of all nums[i+1..n-1]
    int rightProduct = 1;
    for (int i = n - 1; i >= 0; i--) {
        result[i] *= rightProduct;
        rightProduct *= nums[i];
    }
    return result;
}
// Time: O(n), Space: O(1) extra (output array doesn't count)
```

---

## 11 — Running Maximum / Minimum (Prefix Variant)

Used in "trap rain water" and stock problems:

```java
// Maximum water trapping (LC 42) — prefix max from left + right
int trap(int[] height) {
    int n = height.length;
    int[] leftMax = new int[n], rightMax = new int[n];

    leftMax[0] = height[0];
    for (int i = 1; i < n; i++)
        leftMax[i] = Math.max(leftMax[i-1], height[i]);

    rightMax[n-1] = height[n-1];
    for (int i = n-2; i >= 0; i--)
        rightMax[i] = Math.max(rightMax[i+1], height[i]);

    int water = 0;
    for (int i = 0; i < n; i++)
        water += Math.min(leftMax[i], rightMax[i]) - height[i];

    return water;
}
// Time: O(n), Space: O(n)   [Two-pointer version: O(1) space]
```

---

## 12 — Visual: Prefix Sum Construction & Query

```
Array:    [ 3,  1,  4,  1,  5,  9,  2 ]
Index:      0   1   2   3   4   5   6

Build prefix (1-indexed, prefix[0]=0):
prefix[0] = 0
prefix[1] = 0 + 3 = 3
prefix[2] = 3 + 1 = 4
prefix[3] = 4 + 4 = 8
prefix[4] = 8 + 1 = 9
prefix[5] = 9 + 5 = 14
prefix[6] = 14 + 9 = 23
prefix[7] = 23 + 2 = 25

Query sum(2, 5) = arr[2]+arr[3]+arr[4]+arr[5] = 4+1+5+9 = 19
                = prefix[6] - prefix[2]
                = 23        - 4          = 19  ✓

Formula:  sum(i, j) = prefix[j+1] - prefix[i]
                              ↑               ↑
                        j is INCLUSIVE      i is the left boundary (exclusive prefix)
```

**Subarray sum = K using HashMap** — why `countMap.put(0,1)` matters:
```
Array: [3, 4, 7, 2, -3, 1, 4, 2], K=7

prefix:  0   3   7   14  16  13  14  18  20
         ↑   ↑   ↑
         |   |   prefix[2]=7, prefix[2]-7=0 → 0 is in map (count=1) → found [3,4]!
         |   prefix[1]=3, 3-7=-4 → not in map
         base case (empty prefix, sum=0)

Without countMap.put(0,1): we'd miss subarrays starting at index 0!
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an integer array, count the number of subarrays whose sum equals exactly zero. *(Variant of LC 560 with K=0 — but let's walk through recognizing it.)*

**Step 1 — Read**: Input = int[] (can be negative), output = int (count of subarrays). "Subarray" = contiguous.

**Step 2 — Identify**: "subarray sum = K" (here K=0) with potentially negative numbers. Sliding window breaks with negatives (shrinking doesn't guarantee sum decrease). → **Prefix Sum + HashMap**. Two pointers won't work either (unsorted, negatives).

**Step 3 — Plan**:
- `prefix[j] - prefix[i] = 0` means `prefix[j] = prefix[i]` — two indices with the same prefix sum.
- Count how many times each prefix sum has appeared so far.
- When we see prefix sum P again, all previous indices with sum P form a valid subarray ending here.
- Put 0→1 in map first (empty prefix).

**Step 4 — Code**:
```java
int subarraySumZero(int[] nums) {
    Map<Integer, Integer> countMap = new HashMap<>();
    countMap.put(0, 1);   // one "empty prefix" with sum 0
    int prefixSum = 0, count = 0;
    for (int num : nums) {
        prefixSum += num;
        count += countMap.getOrDefault(prefixSum, 0);  // previous same sums
        countMap.merge(prefixSum, 1, Integer::sum);
    }
    return count;
}
// Time: O(n), Space: O(n)
```

**Step 5 — Verify** on `[1, -1, 3, -3, 2]`:
- prefix: 0,1,0,3,0,2
- prefix=1: not in map (beyond 0). put 1→1
- prefix=0: map has 0→1. count=1. put 0→2
- prefix=3: not in map. put 3→1
- prefix=0: map has 0→2. count=3. put 0→3
- prefix=2: not in map.
- Return 3: subarrays [1,-1], [-1,3,-3], [1,-1,3,-3] ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Missing `countMap.put(0,1)` | Misses subarrays starting at index 0 | Always initialize with 0→1 |
| Negative modulo in Java | `(-7) % 3 = -1` (wrong, expect 2) | Use `((sum % k) + k) % k` for all modulo operations |
| 2D prefix: wrong inclusion-exclusion | Double-subtract corner | Formula: `p[r][c] - p[r-1][c] - p[r][c-1] + p[r-1][c-1]` (add back corner) |
| Target = 0 for subarray sum | Works naturally — same as any K | No special handling needed |
| Large prefix sums overflow int | `sum * sum` or long chains | Use `long` for prefix accumulation |

```java
// Modulo normalization (always use this for divisibility problems):
int rem = ((prefixSum % k) + k) % k;   // handles negative prefixSum correctly

// "Length >= 2" constraint (LC 523):
// Store FIRST occurrence only (not every occurrence):
if (!firstSeen.containsKey(rem)) firstSeen.put(rem, i);
// Then check: i - firstSeen.get(rem) >= 2

// Product except self (no division):
int leftProd = 1;
for (int i = 0; i < n; i++) { result[i] = leftProd; leftProd *= nums[i]; }
int rightProd = 1;
for (int i = n-1; i >= 0; i--) { result[i] *= rightProd; rightProd *= nums[i]; }
```

---

## 😵 Commonly Confused With

**vs Sliding Window**: Sliding window works when all elements are non-negative (shrinking always decreases the sum). Prefix sum + HashMap works even with negative numbers. Deciding question: *Can any element be negative?* Yes → Prefix Sum + HashMap. No (and you want O(1) space) → Sliding Window.

**vs Two Pointers on sorted array**: Two pointers find if a pair sums to K. Prefix sum counts how many contiguous subarrays sum to K. Deciding question: *Single pair in a sorted array (TP), or arbitrary subarray count/length (Prefix Sum)?*

**vs Segment / Fenwick Tree**: Prefix sum answers range queries on a STATIC array in O(1). If the array gets UPDATED between queries, you need a Fenwick Tree (O(log n) update + O(log n) query) or Segment Tree. Deciding question: *Does the array change after you build the prefix array?*

## 13 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| 1D range sum | LC 303 (immutable), LC 307 (mutable → Fenwick tree) |
| Subarray sum = K | LC 560 ★, LC 325 (max length), LC 930 (binary array) |
| Divisibility | LC 974, LC 523 |
| 2D prefix | LC 304 (range sum 2D), LC 1074 (count submatrices) |
| Prefix + sorting | LC 862 (shortest subarray sum ≥ K, with deque) |
| Product prefix | LC 238 |
| Running max/min | LC 42 (trap water), LC 84 (histogram via stack is better) |

---

## 13 — System Design Connection

Prefix sums underpin:
- **Time-series aggregation**: sliding window analytics (Prometheus range vectors, InfluxDB) use incremental prefix sums to compute rates
- **Distributed prefix sum (parallel prefix)**: MapReduce aggregation uses parallel prefix scan
- **Segment trees and Fenwick trees** (see `system-design-ds/segment-fenwick-tree.md`): dynamic prefix sum with point updates, used in leaderboards and range analytics
