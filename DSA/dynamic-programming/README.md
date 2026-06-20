# Dynamic Programming

> Break a problem into overlapping subproblems. Solve each subproblem once and store the result. Combine subproblem solutions to answer the original problem.

---

## 1 — How to Recognize This Pattern

**Two mandatory properties must both be true**:
1. **Optimal substructure**: the optimal solution to the problem contains optimal solutions to subproblems
2. **Overlapping subproblems**: the same subproblem is solved multiple times in a naive recursion

Ask yourself:
- [ ] Can I express the answer in terms of answers to smaller versions of the same problem?
- [ ] Does a brute-force recursion produce the same subproblem multiple times?
- [ ] Does the problem ask for a **count, maximum, minimum, or boolean** answer?
- [ ] Is making a **local greedy choice** insufficient? (Then DP is likely needed)

**Trigger phrases**: "number of ways", "minimum cost", "maximum profit", "longest subsequence", "can you reach", "minimum steps", "count paths", "optimal strategy"

**NOT DP**: if you need all solutions (→ backtracking), or if greedy always works (→ greedy).

---

## 2 — Flavor Detection

| Flavor | Signal | State Dimensions |
|--------|--------|-----------------|
| **1D DP** | Single sequence, choices at each index | `dp[i]` |
| **2D DP (two sequences)** | LCS, edit distance, regex matching | `dp[i][j]` — one per sequence |
| **Interval DP** | Burst balloons, matrix chain multiplication | `dp[i][j]` — subarray from i to j |
| **0/1 Knapsack** | Each item used at most once; capacity constraint | `dp[i][w]` — item i, weight w |
| **Unbounded Knapsack** | Coin change; items can be reused infinitely | `dp[w]` — capacity only |
| **Grid DP** | Paths in a grid, obstacles | `dp[r][c]` |
| **State machine DP** | Stock buy/sell, cooldown, transaction limit | `dp[day][state]` |
| **Bitmask DP** | Subset of visited nodes (TSP, assignment) | `dp[mask][node]` |
| **Tree DP** | Answer depends on subtree properties | Recursive + memoization |

---

## 3 — Framework: Define → Recurrence → Base → Order → Optimize

```
1. DEFINE the state clearly:
   dp[i] = "maximum profit using the first i items"
   dp[i][j] = "minimum operations to transform s[0..i] to t[0..j]"

2. WRITE the recurrence (the "if I knew the smaller answer, how do I get the bigger answer"):
   dp[i] = max(dp[i-1], dp[i-1] + arr[i])   (Kadane's max subarray)

3. IDENTIFY base cases (smallest valid inputs, usually dp[0] or dp[0][0])

4. DETERMINE the computation ORDER (ensure smaller subproblems are computed first):
   Usually bottom-up: fill dp[] left-to-right, or dp[][] row by row

5. OPTIMIZE space (if dp[i] depends only on dp[i-1], use two variables instead of array)
```

---

## 4 — 1D DP

**Climbing Stairs / Fibonacci (LC 70)**:
```java
// dp[i] = ways to reach step i
int climbStairs(int n) {
    if (n <= 2) return n;
    int prev2 = 1, prev1 = 2;
    for (int i = 3; i <= n; i++) {
        int curr = prev1 + prev2;
        prev2 = prev1;
        prev1 = curr;
    }
    return prev1;
}
```

**House Robber (LC 198) — skip adjacent**:
```java
// dp[i] = max money robbing houses 0..i
// dp[i] = max(dp[i-1], dp[i-2] + nums[i])
int rob(int[] nums) {
    int prev2 = 0, prev1 = 0;
    for (int num : nums) {
        int curr = Math.max(prev1, prev2 + num);
        prev2 = prev1;
        prev1 = curr;
    }
    return prev1;
}
```

**Maximum Subarray — Kadane's (LC 53)**:
```java
// dp[i] = max subarray sum ending at index i
// dp[i] = max(arr[i], dp[i-1] + arr[i])
int maxSubArray(int[] nums) {
    int maxSum = nums[0], curr = nums[0];
    for (int i = 1; i < nums.length; i++) {
        curr = Math.max(nums[i], curr + nums[i]);  // restart or extend
        maxSum = Math.max(maxSum, curr);
    }
    return maxSum;
}
```

**Longest Increasing Subsequence — LIS (LC 300)**:
```java
// dp[i] = length of LIS ending at index i
// dp[i] = max(dp[j] + 1) for all j < i where nums[j] < nums[i]
int lengthOfLIS(int[] nums) {
    int n = nums.length;
    int[] dp = new int[n];
    Arrays.fill(dp, 1);
    int best = 1;

    for (int i = 1; i < n; i++) {
        for (int j = 0; j < i; j++) {
            if (nums[j] < nums[i]) dp[i] = Math.max(dp[i], dp[j] + 1);
        }
        best = Math.max(best, dp[i]);
    }
    return best;
}
// O(n²). Can be reduced to O(n log n) with binary search + patience sorting.
```

**Word Break (LC 139)**:
```java
// dp[i] = can we segment s[0..i-1] using the dictionary
boolean wordBreak(String s, List<String> wordDict) {
    Set<String> dict = new HashSet<>(wordDict);
    boolean[] dp = new boolean[s.length() + 1];
    dp[0] = true;                           // empty string is always valid

    for (int i = 1; i <= s.length(); i++) {
        for (int j = 0; j < i; j++) {
            if (dp[j] && dict.contains(s.substring(j, i))) {
                dp[i] = true;
                break;
            }
        }
    }
    return dp[s.length()];
}
```

---

## 5 — 2D DP (Two Sequences)

**Longest Common Subsequence — LCS (LC 1143)**:
```java
// dp[i][j] = LCS of s1[0..i-1] and s2[0..j-1]
// if s1[i-1] == s2[j-1]: dp[i][j] = dp[i-1][j-1] + 1
// else:                  dp[i][j] = max(dp[i-1][j], dp[i][j-1])
int longestCommonSubsequence(String text1, String text2) {
    int m = text1.length(), n = text2.length();
    int[][] dp = new int[m + 1][n + 1];

    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (text1.charAt(i - 1) == text2.charAt(j - 1))
                dp[i][j] = dp[i-1][j-1] + 1;
            else
                dp[i][j] = Math.max(dp[i-1][j], dp[i][j-1]);
        }
    }
    return dp[m][n];
}
```

**Edit Distance (LC 72)**:
```java
// dp[i][j] = min operations to convert word1[0..i-1] to word2[0..j-1]
// if word1[i-1] == word2[j-1]: dp[i][j] = dp[i-1][j-1]
// else: dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
//                          (delete)      (insert)    (replace)
int minDistance(String word1, String word2) {
    int m = word1.length(), n = word2.length();
    int[][] dp = new int[m + 1][n + 1];

    for (int i = 0; i <= m; i++) dp[i][0] = i;   // delete all chars from word1
    for (int j = 0; j <= n; j++) dp[0][j] = j;   // insert all chars of word2

    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (word1.charAt(i-1) == word2.charAt(j-1))
                dp[i][j] = dp[i-1][j-1];
            else
                dp[i][j] = 1 + Math.min(dp[i-1][j-1], Math.min(dp[i-1][j], dp[i][j-1]));
        }
    }
    return dp[m][n];
}
```

---

## 6 — Knapsack DP

**0/1 Knapsack — each item used at most once**:
```java
// dp[i][w] = max value using first i items with capacity w
int knapsack(int[] weights, int[] values, int capacity) {
    int n = weights.length;
    int[] dp = new int[capacity + 1];  // space-optimized: 1D array (iterate w right to left)

    for (int i = 0; i < n; i++) {
        for (int w = capacity; w >= weights[i]; w--) {  // RIGHT TO LEFT = avoid reuse
            dp[w] = Math.max(dp[w], dp[w - weights[i]] + values[i]);
        }
    }
    return dp[capacity];
}
```

**Coin Change — unbounded knapsack (LC 322)**:
```java
// dp[amount] = fewest coins to make amount
// dp[0] = 0; dp[i] = min(dp[i - coin] + 1) for each coin
int coinChange(int[] coins, int amount) {
    int[] dp = new int[amount + 1];
    Arrays.fill(dp, amount + 1);   // sentinel: larger than any valid answer
    dp[0] = 0;

    for (int i = 1; i <= amount; i++) {
        for (int coin : coins) {
            if (coin <= i) dp[i] = Math.min(dp[i], dp[i - coin] + 1);
        }
    }
    return dp[amount] > amount ? -1 : dp[amount];
}
```

**Coin Change II — count ways (LC 518)**:
```java
// dp[amount] = number of combinations to make amount
// Outer loop: coins (avoid counting permutations)
int change(int amount, int[] coins) {
    int[] dp = new int[amount + 1];
    dp[0] = 1;
    for (int coin : coins)                    // iterate coins in outer loop
        for (int i = coin; i <= amount; i++)
            dp[i] += dp[i - coin];
    return dp[amount];
}
// Key: outer=coins, inner=amounts → each combination counted once
// If outer=amounts, inner=coins → permutations (different ordering = different)
```

---

## 7 — Grid DP

**Unique Paths (LC 62)**:
```java
// dp[r][c] = number of paths to reach cell (r,c) from (0,0) moving only right/down
int uniquePaths(int m, int n) {
    int[] dp = new int[n];
    Arrays.fill(dp, 1);   // top row: 1 path to every cell (only right)

    for (int r = 1; r < m; r++)
        for (int c = 1; c < n; c++)
            dp[c] += dp[c - 1];   // dp[c] = from above + from left

    return dp[n - 1];
}
```

**Minimum Path Sum (LC 64)**:
```java
int minPathSum(int[][] grid) {
    int m = grid.length, n = grid[0].length;
    int[] dp = new int[n];
    dp[0] = grid[0][0];
    for (int c = 1; c < n; c++) dp[c] = dp[c-1] + grid[0][c];  // top row

    for (int r = 1; r < m; r++) {
        dp[0] += grid[r][0];                                      // left column
        for (int c = 1; c < n; c++)
            dp[c] = Math.min(dp[c], dp[c-1]) + grid[r][c];       // min of above or left
    }
    return dp[n-1];
}
```

---

## 8 — State Machine DP (Stock Problems)

**Best time to buy and sell stock with cooldown (LC 309)**:

```
States: HOLDING (have stock), SOLD (just sold, in cooldown), REST (no stock, not in cooldown)
Transitions:
  HOLDING[i] = max(HOLDING[i-1],  REST[i-1] - price[i])   // hold or buy
  SOLD[i]    = HOLDING[i-1] + price[i]                      // sell
  REST[i]    = max(REST[i-1], SOLD[i-1])                    // rest or come off cooldown
```

```java
int maxProfit(int[] prices) {
    int holding = Integer.MIN_VALUE, sold = 0, rest = 0;
    for (int price : prices) {
        int prevHolding = holding, prevSold = sold, prevRest = rest;
        holding = Math.max(prevHolding, prevRest - price);
        sold    = prevHolding + price;
        rest    = Math.max(prevRest, prevSold);
    }
    return Math.max(sold, rest);
}
```

**Stock with at most k transactions (LC 188)**:
```java
// dp[k][day] = max profit with at most k transactions up to day d
// Compressed: track buy/sell per transaction k
```

---

## 9 — Interval DP

**Burst Balloons (LC 312)** — think about which balloon to pop LAST:
```java
// dp[i][j] = max coins from bursting all balloons in (i, j) exclusively
// dp[i][j] = max over all k in (i,j): dp[i][k] + nums[i]*nums[k]*nums[j] + dp[k][j]
int maxCoins(int[] nums) {
    int n = nums.length;
    int[] a = new int[n + 2];
    a[0] = a[n + 1] = 1;
    for (int i = 0; i < n; i++) a[i + 1] = nums[i];
    int m = n + 2;
    int[][] dp = new int[m][m];

    for (int len = 2; len < m; len++) {
        for (int i = 0; i < m - len; i++) {
            int j = i + len;
            for (int k = i + 1; k < j; k++) {
                dp[i][j] = Math.max(dp[i][j], dp[i][k] + a[i]*a[k]*a[j] + dp[k][j]);
            }
        }
    }
    return dp[0][m - 1];
}
```

---

## 10 — Top-Down (Memoization) Template

When bottom-up is hard to formulate, memoize recursion:

```java
Map<String, Integer> memo = new HashMap<>();

int solve(int[] arr, int i, int remaining) {
    if (i == arr.length) return remaining == 0 ? 1 : 0;   // base case

    String key = i + "," + remaining;
    if (memo.containsKey(key)) return memo.get(key);       // cache hit

    // Recurrence
    int result = solve(arr, i + 1, remaining)              // skip
               + solve(arr, i + 1, remaining - arr[i]);    // take

    memo.put(key, result);                                  // cache result
    return result;
}
```

---

## 11 — Space Optimization Rules

| If dp[i][j] depends on... | Optimize to... |
|---------------------------|---------------|
| dp[i-1][j] and dp[i][j-1] | One 1D array, filled left-to-right |
| dp[i-1][j-1] | One 1D array + a prev variable |
| dp[i-1] only | Two variables (prev, curr) |
| Only the previous row | One row array |

**O(n²) → O(n) space template**:
```java
// If dp[i] depends only on dp[i-1]:
int prev = dp[0];
for (int i = 1; i <= n; i++) {
    int curr = recurrence(prev, i);
    prev = curr;
}
return prev;
```

---

## 12 — Complexity Reference

| Flavor | Time | Space |
|--------|------|-------|
| 1D DP | O(n²) or O(n) | O(n) or O(1) |
| 2D DP (LCS, Edit Distance) | O(m × n) | O(min(m,n)) |
| Knapsack (0/1) | O(n × W) | O(W) |
| Coin Change | O(n × amount) | O(amount) |
| Grid DP | O(m × n) | O(n) |
| Interval DP | O(n³) | O(n²) |
| LIS (O(n log n)) | O(n log n) | O(n) |

---

## 13 — FAANG Interview Moves

1. **Define the state in plain English first**: "dp[i] = the maximum profit achievable using the first i stocks." Interviewers penalise jumping to code before the state is clear.
2. **Recurrence before code**: write the recurrence relation mathematically, then translate.
3. **Base cases explicitly**: state dp[0] and dp[0][0] before the loop.
4. **Coin change I vs II**: "If order matters → outer=amount, inner=coins. If order doesn't matter (count combinations) → outer=coins, inner=amount."
5. **Mention space optimization** after the O(n²) solution: "Because dp[i] only depends on dp[i-1], I can reduce to O(1) / O(n) space by rolling the array."
6. **Draw the state transition diagram** for stock problems — a DAG of states is clearer than prose.

---

## 14 — Visual: DP Table Being Filled

**Knapsack example**: items with weights [1,3,4], values [1,4,5], capacity W=4.

```
dp[i][w] = max value using first i items with capacity w

      w=0  w=1  w=2  w=3  w=4
i=0:   0    0    0    0    0     (no items)
i=1:   0    1    1    1    1     (item1: w=1,v=1)
i=2:   0    1    1    4    5     (item2: w=3,v=4 — can fit at w=3,4)
i=3:   0    1    1    4    5     (item3: w=4,v=5 — fits at w=4 → max(5, dp[2][4]=5)=5)

Reading: dp[2][4]=5 comes from:
  Option A: skip item2 → dp[1][4] = 1
  Option B: take item2 → dp[1][4-3] + 4 = dp[1][1] + 4 = 1 + 4 = 5
  max(1, 5) = 5 ← take item2
```

**1D DP for climbing stairs** — state transitions:
```
  dp[0]=1  dp[1]=1  dp[2]=2  dp[3]=3  dp[4]=5  dp[5]=8
                      ↑           ↑
              dp[2] = dp[1] + dp[0]   (came from step 1 or step 0)
              dp[3] = dp[2] + dp[1]
              Pattern: dp[i] = dp[i-1] + dp[i-2]  (Fibonacci)
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a list of non-negative integers `nums`, find the maximum sum of elements such that **no two chosen elements are adjacent**. *(House Robber — but let's walk through discovering the DP from scratch.)*

**Step 1 — Read**: Input = int[] (non-negative), output = int (max sum), constraint = no two adjacent.

**Step 2 — Identify**: Can we be greedy (always take the bigger of adjacent pairs)? No — taking a small middle element blocks two larger neighbors. Choices conflict with future choices → **DP**. Does it have overlapping subproblems? "Max from index i" = "max of (take i + max from i+2) vs (skip i + max from i+1)" — yes, the same suffix appears repeatedly → **memoize**.

**Step 3 — Plan** (5-step framework):
1. **State**: `dp[i]` = max money robbing houses `0..i`
2. **Recurrence**: `dp[i] = max(dp[i-1], dp[i-2] + nums[i])`  
   (either skip house i → same as dp[i-1], or rob house i → add its value to best-before-previous)
3. **Base cases**: `dp[0] = nums[0]`, `dp[1] = max(nums[0], nums[1])`
4. **Order**: left to right (dp[i] needs dp[i-1] and dp[i-2])
5. **Optimize**: only need last 2 values → O(1) space

**Step 4 — Code**:
```java
int rob(int[] nums) {
    if (nums.length == 1) return nums[0];
    int prev2 = nums[0];
    int prev1 = Math.max(nums[0], nums[1]);
    for (int i = 2; i < nums.length; i++) {
        int curr = Math.max(prev1, prev2 + nums[i]);
        prev2 = prev1;
        prev1 = curr;
    }
    return prev1;
}
// Time: O(n), Space: O(1)
```

**Step 5 — Verify** on `[2, 7, 9, 3, 1]`:
- prev2=2, prev1=7
- i=2: curr=max(7, 2+9)=11. prev2=7, prev1=11
- i=3: curr=max(11, 7+3)=11. prev2=11, prev1=11
- i=4: curr=max(11, 11+1)=12. → return 12 ✓ (rob houses 0,2,4 = 2+9+1=12)

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| `n=0` (empty) | `dp[0]` undefined | Return 0 before building dp |
| `n=1` | `dp[-1]` in base case | Handle `if (n==1) return nums[0]` |
| Negative values allowed | Max might be 0 (take nothing) | Initialize result to 0, not `dp[0]` |
| Huge values (overflow) | `dp[i] + nums[i]` overflows int | Use `long[]` for dp |
| 2D DP, row 0 needs row -1 | Index -1 crashes | Add a sentinel row: `dp = new int[m+1][n+1]`, offset by 1 |
| "Exactly K" vs "at most K" items | Off-by-one in dimension | Add dimension for count: `dp[i][k]` = best using exactly k items |

```java
// Base case indexing tweak (1-indexed dp avoids -1 access):
int[] dp = new int[n + 1];   // dp[0] = 0 (base: 0 items)
for (int i = 1; i <= n; i++)
    dp[i] = /* recurrence using dp[i-1], dp[i-2], etc. */;

// 2D DP with 1-indexed offset to avoid checking i>0 && j>0 everywhere:
int[][] dp = new int[m + 1][n + 1];
for (int i = 1; i <= m; i++)
    for (int j = 1; j <= n; j++)
        dp[i][j] = /* uses dp[i-1][j], dp[i][j-1] safely */;
```

---

## 😵 Commonly Confused With

**vs Greedy**: Greedy makes one decision at each step and never looks back. DP explores multiple options and picks the best. Deciding question: *Does a locally optimal choice at step i ever prevent a better global outcome?* If yes → DP. If local always leads to global optimal → Greedy.

**vs Backtracking**: Both explore choices recursively. Deciding question: *Do you need to count/minimize/maximize (aggregate answer) or enumerate all individual solutions?* Aggregate → DP (memoize overlapping subproblems). All solutions → Backtracking.

**vs Divide and Conquer**: D&C splits into independent subproblems (merge sort — left half and right half never interact). DP has overlapping subproblems that share state. Deciding question: *Do the subproblems reuse the same computation?* Yes → DP. No → D&C.
