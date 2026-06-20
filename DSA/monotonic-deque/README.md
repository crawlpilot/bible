# Monotonic Deque (Sliding Window Maximum / Minimum)

> A monotonic deque maintains a sorted invariant across both ends of a double-ended queue. Unlike a monotonic stack (which answers "nearest greater to the left"), a monotonic deque answers "maximum/minimum within a sliding window" in **O(1) per query** after **O(n) total** processing.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem need the **maximum or minimum in every subarray of size k**?
- [ ] Is there a sliding window with a **"best element" constraint** that must be efficient?
- [ ] Does a **heap seem too slow** (O(n log k)) and you need O(n)?
- [ ] Does the problem need the minimum of the last k elements as they slide?
- [ ] Is the window size fixed, and you need to maintain a running extremum?

**Trigger phrases**: "sliding window maximum", "maximum of every window of size k", "constrained subarray where max-min ≤ limit", "shortest subarray with condition involving maximum", "jump game with sliding window"

**Key distinction from monotonic stack**:
| | Monotonic Stack | Monotonic Deque |
|-|-----------------|-----------------|
| **Answers** | Nearest greater/smaller to left or right | Max/min within a sliding window |
| **Window** | Growing prefix of array | Fixed or variable size window |
| **Removes from** | Top only (LIFO) | Front (out-of-window) AND back (monotone) |

---

## 2 — Core Template: Sliding Window Maximum (LC 239)

**Invariant**: The deque stores indices in **decreasing order of value** (largest at front). When the window slides, remove expired indices from the front. When a new element arrives, pop smaller elements from the back (they can never be the max in any future window).

```java
int[] maxSlidingWindow(int[] nums, int k) {
    int n = nums.length;
    int[] result = new int[n - k + 1];
    Deque<Integer> deque = new ArrayDeque<>();  // stores INDICES, front = max index

    for (int i = 0; i < n; i++) {
        // 1. Remove indices no longer in the window (expired)
        while (!deque.isEmpty() && deque.peekFirst() < i - k + 1)
            deque.pollFirst();

        // 2. Remove indices whose values are ≤ nums[i] from the back
        //    (they can never be the maximum of any window ending at i or later)
        while (!deque.isEmpty() && nums[deque.peekLast()] <= nums[i])
            deque.pollLast();

        deque.offerLast(i);

        // 3. Record result once first window is complete
        if (i >= k - 1)
            result[i - k + 1] = nums[deque.peekFirst()];
    }
    return result;
}
// Time: O(n) — each element added and removed at most once.
// Space: O(k) — deque holds at most k indices.
```

**Sliding Window Minimum** — same template, flip `<=` to `>=` in the removal step (or negate all values):
```java
// Change: while (!deque.isEmpty() && nums[deque.peekLast()] >= nums[i])
```

---

## 3 — Variable Window: Longest Subarray with Max-Min ≤ Limit (LC 1438)

Use **two deques**: one for max, one for min. Shrink the window when `max - min > limit`.

```java
int longestSubarray(int[] nums, int limit) {
    Deque<Integer> maxDeque = new ArrayDeque<>();  // decreasing (front = max)
    Deque<Integer> minDeque = new ArrayDeque<>();  // increasing (front = min)
    int left = 0, result = 0;

    for (int right = 0; right < nums.length; right++) {
        // Maintain max deque
        while (!maxDeque.isEmpty() && nums[maxDeque.peekLast()] <= nums[right])
            maxDeque.pollLast();
        maxDeque.offerLast(right);

        // Maintain min deque
        while (!minDeque.isEmpty() && nums[minDeque.peekLast()] >= nums[right])
            minDeque.pollLast();
        minDeque.offerLast(right);

        // Shrink window from left if constraint violated
        while (nums[maxDeque.peekFirst()] - nums[minDeque.peekFirst()] > limit) {
            left++;
            if (maxDeque.peekFirst() < left) maxDeque.pollFirst();
            if (minDeque.peekFirst() < left) minDeque.pollFirst();
        }
        result = Math.max(result, right - left + 1);
    }
    return result;
}
// Time: O(n), Space: O(n) worst case
```

---

## 4 — Jump Game VI (LC 1696) — DP + Monotonic Deque

"You can jump at most k steps. Maximize the score." — DP transition optimized with deque.

Without deque: `dp[i] = nums[i] + max(dp[i-k]..dp[i-1])` → O(nk).
With deque: maintain max of the last k dp values → O(n).

```java
int maxResult(int[] nums, int k) {
    int n = nums.length;
    int[] dp = new int[n];
    dp[0] = nums[0];
    Deque<Integer> deque = new ArrayDeque<>();  // stores indices, front = max dp index
    deque.offerLast(0);

    for (int i = 1; i < n; i++) {
        // Remove indices out of window [i-k, i-1]
        while (!deque.isEmpty() && deque.peekFirst() < i - k)
            deque.pollFirst();

        dp[i] = nums[i] + dp[deque.peekFirst()];  // max dp in window

        // Maintain decreasing dp deque
        while (!deque.isEmpty() && dp[deque.peekLast()] <= dp[i])
            deque.pollLast();
        deque.offerLast(i);
    }
    return dp[n - 1];
}
// Time: O(n), Space: O(n)
```

---

## 5 — Shortest Subarray with Sum ≥ K (LC 862) — Deque on Prefix Sum

Prefix sum array + monotonic deque: find shortest subarray where `prefix[j] - prefix[i] >= k` with minimum `j - i`.

```java
int shortestSubarray(int[] nums, int k) {
    int n = nums.length;
    long[] prefix = new long[n + 1];
    for (int i = 0; i < n; i++) prefix[i + 1] = prefix[i] + nums[i];

    int result = Integer.MAX_VALUE;
    Deque<Integer> deque = new ArrayDeque<>();  // indices of prefix array, increasing prefix values

    for (int j = 0; j <= n; j++) {
        // Check if we can shrink from the left (prefix[j] - prefix[deque.front] >= k)
        while (!deque.isEmpty() && prefix[j] - prefix[deque.peekFirst()] >= k) {
            result = Math.min(result, j - deque.pollFirst());
        }
        // Maintain increasing prefix sum deque
        while (!deque.isEmpty() && prefix[deque.peekLast()] >= prefix[j])
            deque.pollLast();
        deque.offerLast(j);
    }
    return result == Integer.MAX_VALUE ? -1 : result;
}
// Time: O(n), Space: O(n)
// Why does negative numbers make this hard? They mean prefix sums aren't monotone,
// so you can't use a simple two-pointer. The deque handles non-monotone prefix sums.
```

---

## 6 — Complexity Reference

| Problem Type | Brute Force | Monotonic Deque |
|-------------|-------------|-----------------|
| Sliding window max/min | O(nk) | O(n) time, O(k) space |
| Longest subarray max-min ≤ limit | O(n²) | O(n) time, O(n) space |
| DP with sliding window max | O(nk) | O(n) time, O(n) space |
| Shortest subarray sum ≥ k (with negatives) | O(n²) | O(n) time, O(n) space |

---

## 7 — FAANG Interview Moves

1. **Always store indices, not values**: You need to know when an element is "out of window" by checking its index against `i - k`. Values alone don't tell you the position.
2. **Remove from front when expired, back when dominated**: Two separate invariants. Front = out-of-window check. Back = monotone ordering.
3. **For max window: use `<=` when cleaning back**: If `nums[back] <= nums[i]`, pop it. The new element is at least as good (farther right AND same or larger). For min window, flip to `>=`.
4. **Variable windows use two deques**: When the window size varies (not fixed k), use separate max-deque and min-deque, shrink from the left.
5. **Deque for DP optimization**: Any DP of the form `dp[i] = nums[i] + max(dp[i-k..i-1])` can be optimized with a deque from O(nk) to O(n). Spot this pattern.

---

## 8 — Visual: Sliding Window Maximum

```
nums = [1, 3, -1, -3, 5, 3, 6, 7],  k = 3

Window [1,3,-1]:  deque process:
  i=0: push 0. deque=[0]
  i=1: 3>1, pop 0; push 1. deque=[1]
  i=2: -1<3, push 2. deque=[1,2]
  Window complete (i=2): result[0] = nums[deque.front] = nums[1] = 3

Window [3,-1,-3]:
  i=3: -3<-1, push 3. deque=[1,2,3]
  Check front: deque.front=1 = i-k+1=1 → still in window.
  result[1] = nums[1] = 3

Window [-1,-3,5]:
  i=4: 5>-3, pop 3; 5>-1, pop 2; 5>3, pop 1; push 4. deque=[4]
  result[2] = nums[4] = 5

Window [-3,5,3]:
  i=5: 3<5, push 5. deque=[4,5]
  result[3] = nums[4] = 5

Window [5,3,6]:
  i=6: 6>3, pop 5; 6>5, pop 4; push 6. deque=[6]
  result[4] = nums[6] = 6

Window [3,6,7]:
  i=7: 7>6, pop 6; push 7. deque=[7]
  result[5] = nums[7] = 7

Result: [3, 3, 5, 5, 6, 7]

Deque invariant: ALWAYS DECREASING from front to back (front = max in window)
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given `nums` and integer `k`, find the **minimum** of each sliding window of size `k`. *(Variant of LC 239 — Sliding Window Minimum)*

**Step 1 — Read**: Same structure as sliding window max. Output = minimum of each window of size k.

**Step 2 — Identify**: "Minimum of each window" → **Monotonic Deque**. The only change from the max version: maintain an **increasing** deque (front = minimum). Pop from back when new element is smaller.

**Step 3 — Plan**:
- Use increasing deque (front = smallest).
- When adding `nums[i]`: pop from back while `nums[back] >= nums[i]` (back element can never be the min while i is in the window — i is smaller AND farther right).
- Remove front if it's out of the window: `front < i - k + 1`.
- Record result when `i >= k - 1`.

**Step 4 — Code**:
```java
int[] minSlidingWindow(int[] nums, int k) {
    int n = nums.length;
    int[] result = new int[n - k + 1];
    Deque<Integer> deque = new ArrayDeque<>();  // increasing (front = min)

    for (int i = 0; i < n; i++) {
        // Remove out-of-window from front
        while (!deque.isEmpty() && deque.peekFirst() < i - k + 1)
            deque.pollFirst();

        // Remove elements from back that are >= nums[i] (can never be the min)
        while (!deque.isEmpty() && nums[deque.peekLast()] >= nums[i])
            deque.pollLast();

        deque.offerLast(i);

        if (i >= k - 1)
            result[i - k + 1] = nums[deque.peekFirst()];
    }
    return result;
}
```

**Step 5 — Verify** on `[4, 2, 5, 1, 3]`, k=3:
- i=0: push 0. deque=[0].
- i=1: 2<4, pop 0; push 1. deque=[1].
- i=2: 5>2, push 2. deque=[1,2]. result[0]=nums[1]=2.
- i=3: 1<5, pop 2; 1<2, pop 1; push 3. deque=[3]. result[1]=nums[3]=1.
- i=4: 3>1, push 4. Check front: 3 >= i-k+1=2, still in. deque=[3,4]. result[2]=nums[3]=1.
- Output: [2, 1, 1]. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| k = 1 | Every element is its own window | Works correctly — deque always has one element |
| k = n | One window covering everything | Works — front is the overall max/min |
| All equal elements | Deque never pops from back (using strict < or >) | Use `<=`/`>=` in back-removal to keep only one copy |
| k > n | Invalid window | Return empty array; add check `if (k > n) return new int[0]` |
| DP + deque: dp values not monotone | Can't just use simple prefix max | Use deque on dp values: pop back while `dp[back] <= dp[i]` |
| Negative numbers | No special handling needed | Deque index-based — works with any values |

```java
// The two removal conditions are SEPARATE and have different triggers:
// 1. FRONT removal — when? always at start of each iteration:
while (!deque.isEmpty() && deque.peekFirst() < i - k + 1) deque.pollFirst();

// 2. BACK removal — when? before adding new element:
while (!deque.isEmpty() && nums[deque.peekLast()] <= nums[i]) deque.pollLast();
// For MIN deque, flip to: nums[deque.peekLast()] >= nums[i]

// For variable window (no fixed k): only do front-removal when your constraint is violated.
```

---

## 😵 Commonly Confused With

**vs Monotonic Stack**: A monotonic stack answers "nearest greater/smaller to left/right" (a permanent past relationship). A monotonic deque answers "best element in a current sliding window" (a moving window relationship). Deciding question: *Is the window fixed-size and sliding (deque), or are you finding the nearest element in the past (stack)?*

**vs Heap for sliding window max**: A max-heap (priority queue) gives the maximum in O(log k) per operation but requires lazy deletion (mark expired, skip on peek) which is more complex. Deque gives O(1) per operation. Deciding question: *Is the window size fixed and you need pure speed (deque — O(n) total), or variable with complex priority ordering beyond max/min (heap)?*

**vs Sliding Window for subarray sum**: The sliding window pattern for sums expands/shrinks based on a sum condition. The monotonic deque pattern is specifically for tracking max/min as the window moves. Deciding question: *Are you tracking a running aggregate (sum, count) that grows/shrinks monotonically as the window moves (sliding window), or the extreme value in the current window (monotonic deque)?*

---

## 9 — Canonical LeetCode Problems

| Problem | Approach |
|---------|----------|
| LC 239 — Sliding Window Maximum | Monotonic decreasing deque, O(n) |
| LC 1438 — Longest Subarray with Max-Min ≤ Limit | Two deques (max + min) |
| LC 1696 — Jump Game VI | DP + monotonic deque for O(n) |
| LC 862 — Shortest Subarray with Sum ≥ K | Deque on prefix sums (handles negatives) |
| LC 918 — Maximum Sum Circular Subarray | Deque on prefix sums |
| LC 1425 — Constrained Subsequence Sum | DP + sliding window max deque |
| LC 2398 — Maximum Number of Robots Within Budget | Two deques (sum + max) |
