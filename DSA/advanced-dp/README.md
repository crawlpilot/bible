# Advanced DP Patterns

> Beyond basic 1D DP (Fibonacci, house robber) and 2D grid DP (unique paths, minimum path sum), FAANG hard problems test four specialized DP patterns: **string DP** (comparing/transforming two strings), **interval DP** (splitting a range to optimize), **digit DP** (counting numbers with digit constraints), and **DP with bitmask** (exponential state over small sets). This file covers all four.

---

## 1 — How to Recognize the Subtype

| Signal | Pattern |
|--------|---------|
| "Given two strings, find LCS / edit distance / common subsequence" | **String DP** |
| "Given a string, palindrome partition / burst balloons / matrix chain" | **Interval DP** |
| "Count integers in [1..N] satisfying digit property" | **Digit DP** |
| "Subsets of ≤ 20 elements, TSP, assignment problem" | **Bitmask DP** |
| "K transactions / at most K operations" | **DP with limited budget** |
| "Knapsack with items: unlimited / 0-1 / bounded / grouped" | **Knapsack variants** |

---

## 2 — String DP

### 2A — Longest Common Subsequence (LCS) — LC 1143

**State**: `dp[i][j]` = LCS length of `s1[0..i-1]` and `s2[0..j-1]`.

**Recurrence**:
```
if s1[i-1] == s2[j-1]:  dp[i][j] = dp[i-1][j-1] + 1
else:                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
```

```java
int lcs(String s1, String s2) {
    int m = s1.length(), n = s2.length();
    int[][] dp = new int[m + 1][n + 1];  // extra row/col for empty prefix base case

    for (int i = 1; i <= m; i++)
        for (int j = 1; j <= n; j++)
            dp[i][j] = s1.charAt(i-1) == s2.charAt(j-1)
                ? dp[i-1][j-1] + 1
                : Math.max(dp[i-1][j], dp[i][j-1]);

    return dp[m][n];
}
// Time: O(m*n), Space: O(m*n) → optimized to O(n) with rolling row
```

**Space-optimized (O(n))**:
```java
int lcsOptimized(String s1, String s2) {
    int m = s1.length(), n = s2.length();
    int[] prev = new int[n + 1], curr = new int[n + 1];

    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++)
            curr[j] = s1.charAt(i-1) == s2.charAt(j-1)
                ? prev[j-1] + 1
                : Math.max(prev[j], curr[j-1]);
        int[] tmp = prev; prev = curr; curr = tmp;
        Arrays.fill(curr, 0);
    }
    return prev[n];
}
```

---

### 2B — Edit Distance (LC 72)

**State**: `dp[i][j]` = min operations to convert `s1[0..i-1]` to `s2[0..j-1]`.

**Operations**: insert, delete, replace (each costs 1).

```java
int minDistance(String s1, String s2) {
    int m = s1.length(), n = s2.length();
    int[][] dp = new int[m + 1][n + 1];

    // Base cases: converting to/from empty string
    for (int i = 0; i <= m; i++) dp[i][0] = i;  // delete all chars of s1
    for (int j = 0; j <= n; j++) dp[0][j] = j;  // insert all chars of s2

    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (s1.charAt(i-1) == s2.charAt(j-1)) {
                dp[i][j] = dp[i-1][j-1];              // no operation needed
            } else {
                dp[i][j] = 1 + Math.min(
                    dp[i-1][j-1],    // replace
                    Math.min(
                        dp[i-1][j],  // delete from s1
                        dp[i][j-1]   // insert into s1
                    )
                );
            }
        }
    }
    return dp[m][n];
}
// Time: O(m*n), Space: O(m*n)
```

---

### 2C — Longest Increasing Subsequence (LIS) — LC 300

**O(n²) DP**: `dp[i]` = LIS length ending at `nums[i]`.

```java
int lisDP(int[] nums) {
    int n = nums.length, maxLen = 1;
    int[] dp = new int[n];
    Arrays.fill(dp, 1);   // every element is an LIS of length 1

    for (int i = 1; i < n; i++)
        for (int j = 0; j < i; j++)
            if (nums[j] < nums[i])
                dp[i] = Math.max(dp[i], dp[j] + 1);
    for (int v : dp) maxLen = Math.max(maxLen, v);
    return maxLen;
}
```

**O(n log n) — Patience Sorting / Binary Search**:
```java
int lisOptimal(int[] nums) {
    List<Integer> tails = new ArrayList<>();  // tails[i] = smallest tail of all LIS of length i+1

    for (int num : nums) {
        // Binary search for leftmost index where tails[i] >= num
        int lo = 0, hi = tails.size();
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (tails.get(mid) < num) lo = mid + 1;
            else hi = mid;
        }
        if (lo == tails.size()) tails.add(num);   // extend the LIS
        else tails.set(lo, num);                   // replace to keep tails minimal
    }
    return tails.size();
}
// Time: O(n log n), Space: O(n)
// Note: tails is NOT the actual LIS, just the length is correct.
```

---

### 2D — Distinct Subsequences (LC 115) and Interleaving String (LC 97)

**Distinct subsequences** — `dp[i][j]` = ways to form `t[0..j-1]` using `s[0..i-1]`:
```java
long numDistinct(String s, String t) {
    int m = s.length(), n = t.length();
    long[][] dp = new long[m + 1][n + 1];
    for (int i = 0; i <= m; i++) dp[i][0] = 1;  // empty t matches once

    for (int i = 1; i <= m; i++)
        for (int j = 1; j <= n; j++) {
            dp[i][j] = dp[i-1][j];  // skip s[i-1]
            if (s.charAt(i-1) == t.charAt(j-1))
                dp[i][j] += dp[i-1][j-1];  // use s[i-1] to match t[j-1]
        }
    return dp[m][n];
}
```

---

## 3 — Interval DP

**Pattern**: The answer for range `[i, j]` depends on splitting it at some `k` into `[i, k]` and `[k+1, j]`. Fill the DP table by increasing length.

### 3A — Burst Balloons (LC 312)

You burst balloon `k` LAST in `[i, j]`. The borders `i-1` and `j+1` are still intact when k is burst.

```java
int maxCoins(int[] nums) {
    int n = nums.length;
    // Pad with 1s on both sides
    int[] balloons = new int[n + 2];
    balloons[0] = balloons[n + 1] = 1;
    for (int i = 0; i < n; i++) balloons[i + 1] = nums[i];
    int N = n + 2;

    int[][] dp = new int[N][N];
    // dp[i][j] = max coins from bursting all balloons strictly between i and j

    for (int len = 2; len < N; len++) {         // window length
        for (int i = 0; i < N - len; i++) {
            int j = i + len;
            for (int k = i + 1; k < j; k++) {  // k is the LAST balloon burst in (i,j)
                dp[i][j] = Math.max(dp[i][j],
                    dp[i][k] + balloons[i] * balloons[k] * balloons[j] + dp[k][j]);
            }
        }
    }
    return dp[0][N - 1];
}
// Time: O(n³), Space: O(n²)
```

### 3B — Palindrome Partitioning II (LC 132)

Minimum cuts to make every substring a palindrome.

```java
int minCut(String s) {
    int n = s.length();
    // Precompute isPalin[i][j] using Manacher / expand-around-center
    boolean[][] isPalin = new boolean[n][n];
    for (int i = n - 1; i >= 0; i--)
        for (int j = i; j < n; j++)
            isPalin[i][j] = s.charAt(i) == s.charAt(j) && (j - i <= 2 || isPalin[i+1][j-1]);

    int[] dp = new int[n];  // dp[i] = min cuts for s[0..i]
    for (int i = 0; i < n; i++) {
        if (isPalin[0][i]) { dp[i] = 0; continue; }  // whole prefix is palindrome
        dp[i] = i;  // worst case: cut after every char
        for (int j = 1; j <= i; j++)
            if (isPalin[j][i])
                dp[i] = Math.min(dp[i], dp[j - 1] + 1);
    }
    return dp[n - 1];
}
// Time: O(n²), Space: O(n²) for isPalin
```

### 3C — Matrix Chain Multiplication

Minimize scalar multiplications to compute `A₁ × A₂ × ... × Aₙ`.

```java
int matrixChain(int[] dims) {
    // dims[i-1] x dims[i] is the dimension of matrix i
    int n = dims.length - 1;
    int[][] dp = new int[n][n];

    for (int len = 2; len <= n; len++) {          // subchain length
        for (int i = 0; i <= n - len; i++) {
            int j = i + len - 1;
            dp[i][j] = Integer.MAX_VALUE;
            for (int k = i; k < j; k++) {
                int cost = dp[i][k] + dp[k+1][j] + dims[i] * dims[k+1] * dims[j+1];
                dp[i][j] = Math.min(dp[i][j], cost);
            }
        }
    }
    return dp[0][n - 1];
}
// Time: O(n³), Space: O(n²)
```

---

## 4 — Digit DP

**Pattern**: Count integers in `[1..N]` (or `[L..R]`) that satisfy a digit-level property. State: `(position, tight constraint, accumulated digit property)`.

### Template: Count Numbers ≤ N with No Two Consecutive Same Digits

```java
// Generic digit DP template
String N;
int[][] memo;

int digitDP(int pos, boolean tight, boolean started, int lastDigit) {
    if (pos == N.length()) return started ? 1 : 0;
    if (memo[pos][lastDigit] != -1 && !tight) return memo[pos][lastDigit];

    int limit = tight ? (N.charAt(pos) - '0') : 9;
    int result = 0;

    for (int d = 0; d <= limit; d++) {
        if (!started && d == 0) {
            result += digitDP(pos + 1, tight && d == limit, false, -1);
        } else if (!started || d != lastDigit) {  // property: no two consecutive same digits
            result += digitDP(pos + 1, tight && d == limit, true, d);
        }
    }
    if (!tight) memo[pos][lastDigit] = result;
    return result;
}
// Call: digitDP(0, true, false, -1)
```

**Key state dimensions**:
- `pos` — which digit position (0 to len-1)
- `tight` — are we still bounded by N's digits? (boolean)
- `started` — have we placed a non-zero digit yet? (handles leading zeros)
- `property` — whatever we're tracking (last digit, digit sum mod k, count of 1s, etc.)

---

## 5 — Bitmask DP

**Pattern**: When n ≤ 20, represent a subset of elements as a bitmask (bit k set = element k included). State: `dp[mask]` or `dp[mask][last]`.

### 5A — Minimum Cost to Visit All Nodes (TSP variant) — LC 847

```java
int shortestPathLength(int[][] graph) {
    int n = graph.length;
    int fullMask = (1 << n) - 1;
    int[][] dist = new int[n][1 << n];
    for (int[] row : dist) Arrays.fill(row, Integer.MAX_VALUE);

    Queue<int[]> queue = new LinkedList<>();
    for (int i = 0; i < n; i++) {
        dist[i][1 << i] = 0;
        queue.offer(new int[]{i, 1 << i});  // [node, visited mask]
    }

    while (!queue.isEmpty()) {
        int[] cur = queue.poll();
        int node = cur[0], mask = cur[1];
        if (mask == fullMask) return dist[node][mask];

        for (int next : graph[node]) {
            int newMask = mask | (1 << next);
            if (dist[node][mask] + 1 < dist[next][newMask]) {
                dist[next][newMask] = dist[node][mask] + 1;
                queue.offer(new int[]{next, newMask});
            }
        }
    }
    return -1;
}
// Time: O(n² * 2ⁿ), Space: O(n * 2ⁿ)
```

### 5B — Partition to K Equal Sum Subsets (LC 698)

```java
boolean canPartitionKSubsets(int[] nums, int k) {
    int total = Arrays.stream(nums).sum();
    if (total % k != 0) return false;
    int target = total / k;
    Arrays.sort(nums);  // sort descending helps pruning
    int n = nums.length;
    boolean[] dp = new boolean[1 << n];
    int[] bucketSum = new int[1 << n];
    dp[0] = true;

    for (int mask = 0; mask < (1 << n); mask++) {
        if (!dp[mask]) continue;
        for (int i = 0; i < n; i++) {
            if ((mask & (1 << i)) == 0) {           // element i not yet used
                int newMask = mask | (1 << i);
                if (bucketSum[mask] % target + nums[i] <= target) {
                    bucketSum[newMask] = bucketSum[mask] + nums[i];
                    dp[newMask] = true;
                }
            }
        }
    }
    return dp[(1 << n) - 1];
}
// Time: O(n * 2ⁿ), Space: O(2ⁿ)
```

---

## 6 — Knapsack Variants

### 0/1 Knapsack

Each item used at most once. `dp[j]` = max value with capacity j.

```java
int knapsack01(int[] weights, int[] values, int capacity) {
    int n = weights.length;
    int[] dp = new int[capacity + 1];

    for (int i = 0; i < n; i++)
        for (int j = capacity; j >= weights[i]; j--)  // REVERSE to avoid using item twice
            dp[j] = Math.max(dp[j], dp[j - weights[i]] + values[i]);

    return dp[capacity];
}
```

### Unbounded Knapsack (Complete Knapsack)

Each item used unlimited times. Forward loop (allows reuse).

```java
int knapsackUnbounded(int[] weights, int[] values, int capacity) {
    int n = weights.length;
    int[] dp = new int[capacity + 1];

    for (int i = 0; i < n; i++)
        for (int j = weights[i]; j <= capacity; j++)  // FORWARD to allow reuse
            dp[j] = Math.max(dp[j], dp[j - weights[i]] + values[i]);

    return dp[capacity];
}
// Coin Change (LC 322) is unbounded knapsack for minimum count
```

### Partition Equal Subset Sum (LC 416) — 0/1 Knapsack

```java
boolean canPartition(int[] nums) {
    int total = Arrays.stream(nums).sum();
    if (total % 2 != 0) return false;
    int target = total / 2;
    boolean[] dp = new boolean[target + 1];
    dp[0] = true;

    for (int num : nums)
        for (int j = target; j >= num; j--)  // reverse — 0/1 knapsack
            dp[j] = dp[j] || dp[j - num];

    return dp[target];
}
```

---

## 7 — DP on Trees

**Pattern**: DFS returns computed values from children; parent combines them.

### Maximum Path Sum in Binary Tree (LC 124)

```java
int maxSum;

int maxPathSum(TreeNode root) {
    maxSum = Integer.MIN_VALUE;
    dfs(root);
    return maxSum;
}

int dfs(TreeNode node) {
    if (node == null) return 0;
    int left  = Math.max(0, dfs(node.left));   // 0 = don't include negative branch
    int right = Math.max(0, dfs(node.right));
    // Update global max: path through this node
    maxSum = Math.max(maxSum, node.val + left + right);
    // Return max single-side path (can't branch upward)
    return node.val + Math.max(left, right);
}
```

### Binary Tree Maximum Path Sum generalization

Any "DP on tree" problem uses this pattern:
- `dfs(node)` returns: the best value for the single path going UP through this node.
- Before returning, update a global best using the two-child combination.

---

## 8 — Complexity Reference

| DP Type | Time | Space |
|---------|------|-------|
| String DP (LCS, Edit Distance) | O(m × n) | O(m × n) → O(n) rolling |
| LIS naive | O(n²) | O(n) |
| LIS optimal | O(n log n) | O(n) |
| Interval DP | O(n³) | O(n²) |
| Digit DP | O(len × 10 × states) | O(len × states) |
| Bitmask DP | O(n × 2ⁿ) | O(2ⁿ) or O(n × 2ⁿ) |
| 0/1 Knapsack | O(n × W) | O(W) |

---

## 9 — FAANG Interview Moves

1. **String DP setup**: Always use 1-indexed DP with extra row/col for empty string base cases. `dp[0][j] = j` (insert j chars), `dp[i][0] = i` (delete i chars).
2. **LIS follow-up**: After O(n²) solution, interviewers will push for O(n log n). Mention patience sorting — "maintain tails array, binary search for insertion point."
3. **Interval DP order**: Always fill by increasing SUBPROBLEM LENGTH, not by i or j directly. `for (int len = 2; len <= n; len++)`.
4. **Bitmask DP limit**: State this explicitly: "This works for n ≤ 20. For n ≤ 15, safe. For n > 25, need a polynomial approach."
5. **Digit DP tight constraint**: The `tight` boolean is the most common source of bugs. If `tight = true` and the current digit `d = limit`, the next state is also tight. If `d < limit`, the next state is NOT tight.
6. **Knapsack direction trick**: "Reverse loop = 0/1 (each item once). Forward loop = unbounded (item reusable)." State this explicitly — it's a known insight interviewers look for.

---

## 10 — Visual: DP Table for Edit Distance

```
s1 = "horse", s2 = "ros"
     ""  r  o  s
""  [ 0, 1, 2, 3 ]
h   [ 1, 1, 2, 3 ]
o   [ 2, 2, 1, 2 ]
r   [ 3, 2, 2, 2 ]
s   [ 4, 3, 3, 2 ]
e   [ 5, 4, 4, 3 ]

Reading dp[5][3] = 3:
  "horse" → "rorse" (replace h→r)
  "rorse" → "rose"  (delete r)
  "rose"  → "ros"   (delete e)
  3 operations ✓

At each cell dp[i][j]:
  If chars match:      diagonal (dp[i-1][j-1])     — free
  If chars differ:     1 + min(diagonal, up, left)  — replace, delete, insert
  
Table fills left-to-right, top-to-bottom. 
Each cell only needs the cell above, left, and diagonally up-left.
→ Can optimize to O(n) space with a single rolling row.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given string `s` and string `t`, return the minimum number of characters to delete from `s` and `t` to make them equal. *(LC 583 — Delete Operation for Two Strings)*

**Step 1 — Read**: Input = `s`, `t`. Output = minimum total deletions from both strings to make them equal. The result of deletions must be the same string (a common subsequence).

**Step 2 — Identify**: The best we can do is keep the **Longest Common Subsequence (LCS)** and delete everything else. `deletions = (m - lcs) + (n - lcs) = m + n - 2 * lcs`. This is **String DP → LCS**.

**Step 3 — Plan**:
- Compute LCS of `s` and `t`.
- Answer = `s.length() + t.length() - 2 * lcs`.

**Step 4 — Code**:
```java
int minDeleteToEqual(String s, String t) {
    int m = s.length(), n = t.length();
    int[][] dp = new int[m + 1][n + 1];

    for (int i = 1; i <= m; i++)
        for (int j = 1; j <= n; j++)
            dp[i][j] = s.charAt(i-1) == t.charAt(j-1)
                ? dp[i-1][j-1] + 1
                : Math.max(dp[i-1][j], dp[i][j-1]);

    int lcsLen = dp[m][n];
    return (m - lcsLen) + (n - lcsLen);
}
// Time: O(m*n), Space: O(m*n)
```

**Step 5 — Verify** on `s="sea"`, `t="eat"`:
- LCS of "sea" and "eat" = "ea" (length 2).
- Deletions = (3-2) + (3-2) = 1 + 1 = 2. ✓ (delete 's' from sea, delete 't' from eat → "ea")

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| One empty string (LCS) | `dp[i][0] = dp[0][j] = 0` — handled by default | No fix needed if DP table initialized to 0 |
| LIS with duplicates (strictly increasing) | Strict: `nums[j] < nums[i]`. Non-strict: `nums[j] <= nums[i]` | Change comparison operator to match problem |
| Burst balloons with 0 values | `balloons[k] = 0` gives 0 coin — no issue | No special handling; 0 values just mean no contribution |
| Knapsack: items with weight 0 | Forward loop causes infinite additions | Guard: `if (weights[i] == 0) skip` or item value must be positive |
| Digit DP: negative numbers | Range queries like `f(N) - f(L-1)` handle [L,R] | Convert: `count(R) - count(L-1)` |
| Bitmask DP: n > 30 | `1 << n` overflows int | Use `1L << n` and long bitmask; feasibility limit is ~20-22 |

```java
// LCS can reconstruct the actual subsequence (backtracking through dp table):
String reconstructLCS(String s, String t, int[][] dp) {
    int i = s.length(), j = t.length();
    StringBuilder sb = new StringBuilder();
    while (i > 0 && j > 0) {
        if (s.charAt(i-1) == t.charAt(j-1)) { sb.append(s.charAt(i-1)); i--; j--; }
        else if (dp[i-1][j] > dp[i][j-1]) i--;
        else j--;
    }
    return sb.reverse().toString();
}

// Space-optimize any string DP with 2 rows:
int[] prev = new int[n + 1], curr = new int[n + 1];
// After inner loop: swap(prev, curr); Arrays.fill(curr, 0);
```

---

## 😵 Commonly Confused With

**vs Backtracking**: Backtracking enumerates ALL solutions and prunes invalid ones. DP finds the count/min/max over all valid solutions without explicit enumeration. Deciding question: *Do you need to output ALL valid subsequences/arrangements (backtracking), or just the best count/value (DP)?*

**vs Greedy**: Greedy makes irrevocable local choices. DP explores all choices but remembers results to avoid recomputation. Deciding question: *Can a locally optimal choice ever be wrong for a future step? If yes — DP. Provably never? — Greedy.*

**vs Divide & Conquer**: D&C splits into independent subproblems (no overlap). DP solves overlapping subproblems (same subproblem may be needed many times). Deciding question: *Do the two halves share subproblems (DP), or are they independent (D&C)?*

**Bitmask DP vs Union-Find**: Bitmask DP tracks exact subsets of a small set. Union-Find tracks dynamic connectivity in a large graph. Deciding question: *Is n small (≤20) and you need to reason about exact subsets (bitmask DP), or n is large and you need connectivity (Union-Find)?*

---

## 11 — Canonical LeetCode Problems

| Pattern | Problem | Key State |
|---------|---------|-----------|
| LCS | LC 1143 | `dp[i][j]` = LCS of prefixes |
| Edit Distance | LC 72 | `dp[i][j]` = min ops to align prefixes |
| LIS O(n²) | LC 300 | `dp[i]` = LIS ending at i |
| LIS O(n log n) | LC 300 follow-up | `tails` array + binary search |
| Delete to make equal | LC 583 | `m + n - 2 * LCS` |
| Distinct subsequences | LC 115 | `dp[i][j]` = ways to form t[0..j-1] in s[0..i-1] |
| Interleaving string | LC 97 | `dp[i][j]` = can s1[0..i-1] and s2[0..j-1] form t[0..i+j-1] |
| Burst Balloons | LC 312 | `dp[i][j]` = max coins bursting all in (i,j) open interval |
| Palindrome Partition II | LC 132 | `dp[i]` = min cuts for s[0..i] |
| Partition Equal Subset | LC 416 | 0/1 knapsack with target = sum/2 |
| Coin Change | LC 322 | Unbounded knapsack min count |
| Coin Change II | LC 518 | Unbounded knapsack count ways |
| Max Path Sum Binary Tree | LC 124 | Postorder DFS + global max update |
| Shortest Path Visiting All Nodes | LC 847 | BFS + bitmask state |
| Partition K Equal Subsets | LC 698 | Bitmask DP |
