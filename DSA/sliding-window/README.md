# Sliding Window

> Use a window (a contiguous range of elements) that slides across the input, maintaining a running aggregate to avoid recomputation from scratch.

---

## 1 — How to Recognize This Pattern

Ask yourself ALL of these:
- [ ] Input is a **string, array, or linked list** (sequential)
- [ ] Problem asks about a **contiguous subarray or substring**
- [ ] You need to **maximize, minimize, or count** something within that range
- [ ] Recomputing from scratch each time would be O(n²) — sliding should cut it to O(n)

**Trigger phrases**: "longest substring", "smallest subarray", "maximum average", "contains all characters", "at most K distinct", "exactly K", "minimum window"

**Anti-pattern** (don't use sliding window): problem requires non-contiguous elements → use DP or two pointers on sorted input.

---

## 2 — Flavor Detection

| Flavor | Signal | Key Insight |
|--------|--------|-------------|
| **Fixed window** | Window size `k` given explicitly | Slide one in, one out per step |
| **Variable window (grow)** | "Longest/maximum satisfying Y" | Expand right; shrink left when condition VIOLATED |
| **Variable window (shrink)** | "Smallest/minimum satisfying Y" | Expand right; shrink left when condition MET |
| **String window (anagram)** | "All occurrences of pattern P" | Fixed-size freq-map comparison |
| **At most K → exactly K** | "Exactly K distinct" | `f(exactly K) = f(at most K) - f(at most K-1)` |
| **Monotone queue** | "Max/min inside every window of size k" | Deque maintains sorted order in O(n) |

---

## 3 — Fixed Window Solution Steps

**Problem shape**: Window size `k` is given; compute something for every window of that size.

```
Step 1: Build initial window [0..k-1] and compute aggregate
Step 2: Slide — for i from k to n-1:
        a. Add element entering window: arr[i]
        b. Remove element leaving window: arr[i - k]
        c. Update aggregate incrementally
        d. Record result for this window
Step 3: Return the best result
```

**Java template**:
```java
int maxSumSubarrayOfSizeK(int[] arr, int k) {
    int windowSum = 0;
    for (int i = 0; i < k; i++) windowSum += arr[i]; // Step 1: initial window

    int best = windowSum;
    for (int i = k; i < arr.length; i++) {
        windowSum += arr[i];       // add incoming
        windowSum -= arr[i - k];   // remove outgoing
        best = Math.max(best, windowSum);
    }
    return best;
}
```

**Anagram / permutation match (fixed window + freq map)**:
```java
// LC 438 — Find All Anagrams in a String
List<Integer> findAnagrams(String s, String p) {
    int[] need = new int[26], have = new int[26];
    for (char c : p.toCharArray()) need[c - 'a']++;

    List<Integer> res = new ArrayList<>();
    int k = p.length();

    for (int i = 0; i < s.length(); i++) {
        have[s.charAt(i) - 'a']++;             // add right edge

        if (i >= k) have[s.charAt(i - k) - 'a']--; // remove left edge

        if (Arrays.equals(need, have)) res.add(i - k + 1);
    }
    return res;
}
```

**Canonical problems**: Maximum sum subarray size k, Find all anagrams (LC 438), Permutation in string (LC 567), Maximum average subarray (LC 643).

---

## 4 — Variable Window (Longest / Maximum) Solution Steps

**Problem shape**: "Longest subarray/substring where [condition holds]."  
Shrink from left when the condition is **VIOLATED**.

```
Step 1: left = 0, best = 0, state = {}
Step 2: for right in 0..n-1:
        a. Add arr[right] into state
        b. While window VIOLATES condition:
              remove arr[left] from state
              left++
        c. best = max(best, right - left + 1)
Step 3: return best
```

**Java template — longest substring with at most K distinct chars**:
```java
// LC 340
int lengthOfLongestSubstringKDistinct(String s, int k) {
    Map<Character, Integer> freq = new HashMap<>();
    int left = 0, best = 0;

    for (int right = 0; right < s.length(); right++) {
        char rc = s.charAt(right);
        freq.merge(rc, 1, Integer::sum);           // add right

        while (freq.size() > k) {                  // violated: too many distinct
            char lc = s.charAt(left++);
            freq.merge(lc, -1, Integer::sum);
            if (freq.get(lc) == 0) freq.remove(lc);
        }

        best = Math.max(best, right - left + 1);
    }
    return best;
}
```

**Longest substring without repeating characters (LC 3)**:
```java
int lengthOfLongestSubstring(String s) {
    Map<Character, Integer> freq = new HashMap<>();
    int left = 0, best = 0;

    for (int right = 0; right < s.length(); right++) {
        char c = s.charAt(right);
        freq.merge(c, 1, Integer::sum);

        while (freq.get(c) > 1) {                 // violated: duplicate
            char lc = s.charAt(left++);
            freq.merge(lc, -1, Integer::sum);
        }
        best = Math.max(best, right - left + 1);
    }
    return best;
}
```

**Canonical problems**: LC 3, LC 340, LC 904 (fruit into baskets / at most 2 distinct), LC 1004 (max consecutive ones III).

---

## 5 — Variable Window (Smallest / Minimum) Solution Steps

**Problem shape**: "Smallest window satisfying [condition]."  
Shrink from left while the condition is **STILL MET** (to minimise window size).

```
Step 1: left = 0, minLen = ∞, state = {}
Step 2: for right in 0..n-1:
        a. Add arr[right] into state
        b. While window SATISFIES condition:   ← opposite of max-window
              minLen = min(minLen, right - left + 1)
              remove arr[left] from state
              left++
Step 3: return minLen
```

**Java template — Minimum Window Substring (LC 76)**:
```java
String minWindow(String s, String t) {
    int[] need = new int[128], have = new int[128];
    for (char c : t.toCharArray()) need[c]++;

    int required = (int) t.chars().distinct().count();
    int formed = 0, left = 0;
    int bestLen = Integer.MAX_VALUE, bestL = 0;

    for (int right = 0; right < s.length(); right++) {
        char rc = s.charAt(right);
        have[rc]++;
        if (need[rc] > 0 && have[rc] == need[rc]) formed++;

        while (formed == required) {              // condition satisfied → shrink
            if (right - left + 1 < bestLen) {
                bestLen = right - left + 1;
                bestL = left;
            }
            char lc = s.charAt(left++);
            have[lc]--;
            if (need[lc] > 0 && have[lc] < need[lc]) formed--;
        }
    }
    return bestLen == Integer.MAX_VALUE ? "" : s.substring(bestL, bestL + bestLen);
}
```

**Smallest subarray with sum ≥ target (LC 209)**:
```java
int minSubArrayLen(int target, int[] nums) {
    int left = 0, sum = 0, minLen = Integer.MAX_VALUE;
    for (int right = 0; right < nums.length; right++) {
        sum += nums[right];
        while (sum >= target) {               // satisfied → shrink
            minLen = Math.min(minLen, right - left + 1);
            sum -= nums[left++];
        }
    }
    return minLen == Integer.MAX_VALUE ? 0 : minLen;
}
```

---

## 6 — Exactly K → At Most K Trick

When asked "number of subarrays with **exactly** K distinct":

```java
// LC 992 — Subarrays with K Different Integers
int subarraysWithKDistinct(int[] nums, int k) {
    return atMostK(nums, k) - atMostK(nums, k - 1);
}

int atMostK(int[] nums, int k) {
    Map<Integer, Integer> freq = new HashMap<>();
    int left = 0, count = 0;
    for (int right = 0; right < nums.length; right++) {
        freq.merge(nums[right], 1, Integer::sum);
        while (freq.size() > k) {
            int lv = nums[left++];
            freq.merge(lv, -1, Integer::sum);
            if (freq.get(lv) == 0) freq.remove(lv);
        }
        count += right - left + 1;   // all subarrays ending at right with ≤ k distinct
    }
    return count;
}
```

---

## 7 — Monotone Queue (Sliding Window Maximum)

For sliding window **maximum** in O(n) — deque stores indices, front = index of current max.

```java
// LC 239 — Sliding Window Maximum
int[] maxSlidingWindow(int[] nums, int k) {
    int n = nums.length;
    int[] result = new int[n - k + 1];
    Deque<Integer> dq = new ArrayDeque<>();  // stores indices

    for (int i = 0; i < n; i++) {
        // Remove indices out of window
        while (!dq.isEmpty() && dq.peekFirst() <= i - k) dq.pollFirst();

        // Maintain decreasing order: remove smaller elements from back
        while (!dq.isEmpty() && nums[dq.peekLast()] < nums[i]) dq.pollLast();

        dq.offerLast(i);

        if (i >= k - 1) result[i - k + 1] = nums[dq.peekFirst()];
    }
    return result;
}
```

**Canonical problems**: LC 239 (sliding window max), LC 1696 (jump game VI — DP + sliding window max).

---

## 8 — Complexity Reference

| Flavor | Time | Space |
|--------|------|-------|
| Fixed window | O(n) | O(1) |
| Variable window | O(n) | O(k) — freq map |
| String window (freq compare) | O(n + \|Σ\|) | O(\|Σ\|) |
| Monotone queue window | O(n) | O(k) — deque |

---

## 9 — FAANG Interview Moves

1. **State the invariant first**: "I'll maintain a window where [condition]. I expand right and shrink left when [violated / satisfied]."
2. **Name the shrink trigger explicitly**: Shrink when INVALID (max-window) vs shrink while VALID (min-window) — interviewers probe this.
3. **Upgrade to deque when needed**: If the naive approach calls `max(window)` in O(k) per step → O(nk) total. Mention the deque upgrade → O(n).
4. **Exactly K → at most K trick**: Mention this immediately when you see "exactly K distinct" — saves a lot of complexity.
5. **Edge cases**: empty input, k > n, all same elements, window of size 1.

---

## 10 — Visual: How a Sliding Window Moves

Problem: Find the maximum sum of any subarray of size k=3 in `[2, 1, 5, 2, 3, 2]`

```
Array:   [ 2,  1,  5,  2,  3,  2 ]
Index:     0   1   2   3   4   5

Step 1: Build initial window [0..2]
         [  2   1   5  ] 2   3   2      sum=8
          L-----------R

Step 2: Slide right — add arr[3]=2, remove arr[0]=2
          2  [  1   5   2  ] 3   2      sum=8
                L-----------R

Step 3: Slide right — add arr[4]=3, remove arr[1]=1
          2   1  [  5   2   3  ] 2      sum=10  ← new max
                    L-----------R

Step 4: Slide right — add arr[5]=2, remove arr[2]=5
          2   1   5  [  2   3   2  ]    sum=7
                         L-----------R

Answer: 10
Key insight: we never recompute the whole sum — just add the incoming and subtract the outgoing element.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a binary array (only 0s and 1s), find the maximum length subarray that has at most one 0. You can flip at most one 0 to 1. *(Not on your canonical list.)*

**Step 1 — Read**: Input = binary array, output = int (max length), optimal = longest window with ≤1 zero (one flip allowed).

**Step 2 — Identify**: Trigger words: "subarray", "contiguous", "at most K". Brute force: check all O(n²) subarrays → O(n²). Can we maintain a window with a count of zeros? Yes → **Variable Sliding Window**.

Rule out DP: there's no dependency between non-overlapping subarrays. Rule out two-pointers: we're not looking for a pair, we're looking at a range.

**Step 3 — Plan**:
- Window `[left..right]` contains at most `K=1` zeros.
- Invariant: `zeroCount ≤ 1` always holds after shrinking.
- Expand right always. Shrink left only when `zeroCount > 1`.

**Step 4 — Code**:
```java
int longestOnes(int[] nums, int k) {   // k = max zeros allowed (here k=1)
    int left = 0, zeros = 0, maxLen = 0;
    for (int right = 0; right < nums.length; right++) {
        if (nums[right] == 0) zeros++;          // new 0 entered window
        while (zeros > k) {                      // window invalid
            if (nums[left] == 0) zeros--;        // remove outgoing 0
            left++;
        }
        maxLen = Math.max(maxLen, right - left + 1);
    }
    return maxLen;
}
// Time: O(n), Space: O(1)
```

**Step 5 — Verify** on `[1,1,0,1,1,0,1]`, k=1:
- right=2: zeros=1, window=[0..2] length=3
- right=5: zeros=2 > 1 → shrink left until zeros=1: left moves to 3, window=[3..5] length=3
- right=6: zeros=1, window=[3..6] length=4
- Answer: 4 ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty array `[]` | Loop never runs, result = 0 | `if (nums.length == 0) return 0;` or initialize result to 0 |
| k > array length | Window is the whole array | Works naturally — window never needs to shrink |
| All elements same | Window expands to full array | Works — just verify you're not skipping equal elements |
| Negative numbers in sum | Can't use shrink-while-valid logic | Switch to prefix sum + HashMap approach |
| "Exactly K" distinct | Variable window can't directly count exact | Use `f(exactly K) = f(atMost K) - f(atMost K-1)` |
| Result stays 0 | No valid window found | Initialize `maxLen = 0` not `-1` unless problem guarantees ≥1 valid window |

```java
// Tweaks for common variations:

// "At least K" → NOT directly a sliding window. Use prefix sum or complement trick.

// "Minimum length" → initialize to n+1 (impossible), return -1 if never updated
int minLen = nums.length + 1;
// ... at end:
return minLen == nums.length + 1 ? -1 : minLen;

// "Characters outside a-z" → use HashMap instead of int[26]
Map<Character, Integer> freq = new HashMap<>();
freq.merge(c, 1, Integer::sum);
freq.merge(left, -1, Integer::sum);
if (freq.get(left) == 0) freq.remove(left);
```

---

## 😵 Commonly Confused With

**vs Two Pointers**: Both use `left` and `right` on an array. Deciding question: *Are you maintaining a contiguous range (window) of elements that you aggregate, or finding two individual elements that satisfy a sum/condition?* Window with aggregation → Sliding Window. Individual pair → Two Pointers.

**vs Prefix Sum**: Both can answer subarray queries. Deciding question: *Can elements be negative?* If yes, sliding window's shrink logic breaks (shrinking doesn't guarantee the sum decreases) → use Prefix Sum + HashMap. If all values are non-negative, Sliding Window is simpler and O(1) space.

**vs DP**: If computing the optimal window requires knowing all possible window sizes and they interact with each other → DP. If you can maintain the answer by just adding/removing one element at the boundary → Sliding Window.
