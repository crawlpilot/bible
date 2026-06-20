# Binary Search

> When the input is sorted, or when the **answer space itself** is monotone (feasible for x implies feasible for x-1), binary search eliminates half the candidates per step — O(log n) instead of O(n).

---

## 1 — How to Recognize This Pattern

Ask yourself ALL of these:
- [ ] Is the array/list **sorted** (or rotated-sorted)?
- [ ] Is there a **monotone predicate**: if answer is feasible at X, it's feasible at all X' < X (or X' > X)?
- [ ] Would linear scan be O(n) and you can do O(log n)?
- [ ] Problem asks for "find target", "first/last occurrence", "minimum feasible", "maximum possible"?

**Trigger phrases**: "search in sorted array", "find minimum in rotated", "kth smallest", "minimum speed", "capacity to ship", "split array largest sum", "median of two sorted arrays", "peak element"

**Anti-pattern**: Unsorted input where you genuinely need every element → linear scan.

---

## 2 — Flavor Detection

| Flavor | Signal | Invariant |
|--------|--------|-----------|
| **Classic search** | Find exact target in sorted array | `nums[mid] == target` → return |
| **Lower bound** | First index where `nums[i] >= target` | Shrink right when `nums[mid] >= target` |
| **Upper bound** | First index where `nums[i] > target` | Shrink right when `nums[mid] > target` |
| **Rotated sorted** | One rotation, no duplicates | One half is always fully sorted |
| **Rotated with duplicates** | Multiple duplicates possible | When `nums[left] == nums[mid]`, shrink both |
| **Search on answer** | Minimize/maximize a value satisfying condition | Binary search over answer range, not array |
| **Peak element** | Find any local maximum | Move toward the rising side |
| **2D matrix search** | Sorted rows + first element of row > last of prev | Treat as 1D flattened array |

---

## 3 — The Universal Binary Search Template

**The single biggest mistake**: off-by-one errors. Memorize ONE template and parameterize it.

```java
// Template: find the LEFTMOST position where condition(mid) is true
// Precondition: condition is monotone — once true, stays true going right
int binarySearch(int[] nums, int target) {
    int left = 0, right = nums.length - 1;
    int result = -1;

    while (left <= right) {
        int mid = left + (right - left) / 2;   // avoids integer overflow

        if (nums[mid] == target) {
            result = mid;
            right = mid - 1;  // or return mid for first occurrence
        } else if (nums[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    return result;
}
```

**Three rules that eliminate all off-by-one bugs:**
1. `mid = left + (right - left) / 2` — never `(left + right) / 2` (overflow risk)
2. Loop condition `left <= right` (inclusive on both sides)
3. Never move to `mid` itself: always `left = mid + 1` or `right = mid - 1`

---

## 4 — Classic Search (LC 704)

```java
int search(int[] nums, int target) {
    int left = 0, right = nums.length - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if      (nums[mid] == target) return mid;
        else if (nums[mid] < target)  left  = mid + 1;
        else                          right = mid - 1;
    }
    return -1;
}
// Time: O(log n), Space: O(1)
```

---

## 5 — Lower Bound / Upper Bound (First and Last Occurrence)

```java
// First occurrence of target (lower bound)
int firstOccurrence(int[] nums, int target) {
    int left = 0, right = nums.length - 1, result = -1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) { result = mid; right = mid - 1; }  // keep going left
        else if (nums[mid] < target) left  = mid + 1;
        else                         right = mid - 1;
    }
    return result;
}

// Last occurrence of target (upper bound - 1)
int lastOccurrence(int[] nums, int target) {
    int left = 0, right = nums.length - 1, result = -1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) { result = mid; left = mid + 1; }   // keep going right
        else if (nums[mid] < target) left  = mid + 1;
        else                         right = mid - 1;
    }
    return result;
}
// Time: O(log n), Space: O(1)
// LC 34 — Find First and Last Position of Element in Sorted Array
```

---

## 6 — Rotated Sorted Array (No Duplicates) (LC 33)

**Key insight**: in a rotation, ONE half is always fully sorted. Use that to determine which side the target is on.

```java
int searchRotated(int[] nums, int target) {
    int left = 0, right = nums.length - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) return mid;

        // Left half is sorted
        if (nums[left] <= nums[mid]) {
            if (nums[left] <= target && target < nums[mid])
                right = mid - 1;      // target is in sorted left half
            else
                left  = mid + 1;
        }
        // Right half is sorted
        else {
            if (nums[mid] < target && target <= nums[right])
                left  = mid + 1;      // target is in sorted right half
            else
                right = mid - 1;
        }
    }
    return -1;
}
// Time: O(log n), Space: O(1)
```

**With duplicates (LC 81)** — when `nums[left] == nums[mid]`, can't determine sorted half:
```java
// Change the left-sorted check to strict:
if (nums[left] < nums[mid]) { ... }
else if (nums[left] > nums[mid]) { ... }
else { left++; }  // shrink left when ambiguous — degrades to O(n) worst case
```

---

## 7 — Find Minimum in Rotated Sorted Array (LC 153)

```java
int findMin(int[] nums) {
    int left = 0, right = nums.length - 1;
    while (left < right) {                      // note: left < right (not <=)
        int mid = left + (right - left) / 2;
        if (nums[mid] > nums[right])
            left  = mid + 1;   // min is in right half
        else
            right = mid;       // min could be mid itself — don't exclude it
    }
    return nums[left];
}
// Time: O(log n), Space: O(1)
```

---

## 8 — Find Peak Element (LC 162)

**Key insight**: if `nums[mid] < nums[mid+1]`, a peak exists to the right (going uphill).

```java
int findPeakElement(int[] nums) {
    int left = 0, right = nums.length - 1;
    while (left < right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] < nums[mid + 1])
            left  = mid + 1;  // climb the hill
        else
            right = mid;      // peak is at mid or left
    }
    return left;
}
// Time: O(log n), Space: O(1)
```

---

## 9 — Binary Search on Answer Space (Most Important Flavor)

**Pattern**: the answer is an integer in range `[lo, hi]`. There's a monotone predicate `feasible(x)`:
- "Can we achieve X?" where feasibility is monotone — if YES for X, then YES for X-1 (or X+1).

**Template**:
```java
int searchOnAnswer(int[] input, int constraint) {
    int lo = minPossibleAnswer, hi = maxPossibleAnswer;
    int result = hi;  // or lo, depending on min vs max

    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        if (feasible(input, mid, constraint)) {
            result = mid;         // record and try to do better
            hi = mid - 1;        // for minimization: try smaller
            // lo = mid + 1;     // for maximization: try larger
        } else {
            lo = mid + 1;        // for minimization: mid too small
            // hi = mid - 1;    // for maximization: mid too large
        }
    }
    return result;
}
```

### 9a — Capacity to Ship Packages in D Days (LC 1011)

```java
// Minimize capacity such that all packages shipped in <= D days
int shipWithinDays(int[] weights, int days) {
    int lo = Arrays.stream(weights).max().getAsInt(); // must carry heaviest
    int hi = Arrays.stream(weights).sum();            // ship all in 1 day

    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        if (canShip(weights, days, mid)) hi = mid;   // try smaller capacity
        else                             lo = mid + 1;
    }
    return lo;
}

boolean canShip(int[] weights, int days, int capacity) {
    int daysNeeded = 1, current = 0;
    for (int w : weights) {
        if (current + w > capacity) { daysNeeded++; current = 0; }
        current += w;
    }
    return daysNeeded <= days;
}
// Time: O(n log(sum)), Space: O(1)
```

### 9b — Split Array Largest Sum / Painter's Partition (LC 410)

```java
// Minimize the maximum sum when splitting array into k subarrays
int splitArray(int[] nums, int k) {
    int lo = Arrays.stream(nums).max().getAsInt();
    int hi = Arrays.stream(nums).sum();

    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        if (canSplit(nums, k, mid)) hi = mid;
        else                        lo = mid + 1;
    }
    return lo;
}

boolean canSplit(int[] nums, int k, int maxSum) {
    int parts = 1, current = 0;
    for (int n : nums) {
        if (current + n > maxSum) { parts++; current = 0; }
        current += n;
    }
    return parts <= k;
}
```

### 9c — Koko Eating Bananas (LC 875)

```java
int minEatingSpeed(int[] piles, int h) {
    int lo = 1, hi = Arrays.stream(piles).max().getAsInt();
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        long hours = 0;
        for (int p : piles) hours += (p + mid - 1) / mid;  // ceil division
        if (hours <= h) hi = mid;
        else            lo = mid + 1;
    }
    return lo;
}
// Time: O(n log(max_pile)), Space: O(1)
```

### 9d — Minimum Days to Make m Bouquets (LC 1482)

```java
int minDays(int[] bloomDay, int m, int k) {
    if ((long) m * k > bloomDay.length) return -1;
    int lo = 1, hi = Arrays.stream(bloomDay).max().getAsInt();
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;
        if (canMake(bloomDay, m, k, mid)) hi = mid;
        else                              lo = mid + 1;
    }
    return lo;
}

boolean canMake(int[] bloomDay, int m, int k, int day) {
    int bouquets = 0, consecutive = 0;
    for (int d : bloomDay) {
        if (d <= day) { if (++consecutive == k) { bouquets++; consecutive = 0; } }
        else          consecutive = 0;
    }
    return bouquets >= m;
}
```

---

## 10 — Search in 2D Matrix (LC 74)

**Key insight**: treat the m×n matrix as a 1D sorted array of size m*n.

```java
boolean searchMatrix(int[][] matrix, int target) {
    int m = matrix.length, n = matrix[0].length;
    int left = 0, right = m * n - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        int val = matrix[mid / n][mid % n];     // convert 1D index to 2D
        if      (val == target) return true;
        else if (val < target)  left  = mid + 1;
        else                    right = mid - 1;
    }
    return false;
}
// Time: O(log(m*n)), Space: O(1)
```

**Search in 2D Matrix II (LC 240)** — rows sorted, columns sorted (NOT globally sorted):
```java
boolean searchMatrixII(int[][] matrix, int target) {
    int r = 0, c = matrix[0].length - 1;   // start at top-right
    while (r < matrix.length && c >= 0) {
        if      (matrix[r][c] == target) return true;
        else if (matrix[r][c] > target)  c--;   // eliminate column
        else                             r++;   // eliminate row
    }
    return false;
}
// Time: O(m + n), Space: O(1)
```

---

## 11 — Median of Two Sorted Arrays (LC 4) — Hard

**Key insight**: binary search on the partition point of the smaller array.

```java
double findMedianSortedArrays(int[] nums1, int[] nums2) {
    if (nums1.length > nums2.length) return findMedianSortedArrays(nums2, nums1);

    int m = nums1.length, n = nums2.length;
    int lo = 0, hi = m;

    while (lo <= hi) {
        int partA = lo + (hi - lo) / 2;
        int partB = (m + n + 1) / 2 - partA;

        int maxLeftA  = (partA == 0) ? Integer.MIN_VALUE : nums1[partA - 1];
        int minRightA = (partA == m) ? Integer.MAX_VALUE : nums1[partA];
        int maxLeftB  = (partB == 0) ? Integer.MIN_VALUE : nums2[partB - 1];
        int minRightB = (partB == n) ? Integer.MAX_VALUE : nums2[partB];

        if (maxLeftA <= minRightB && maxLeftB <= minRightA) {
            if ((m + n) % 2 == 0)
                return (Math.max(maxLeftA, maxLeftB) + Math.min(minRightA, minRightB)) / 2.0;
            else
                return Math.max(maxLeftA, maxLeftB);
        } else if (maxLeftA > minRightB) {
            hi = partA - 1;
        } else {
            lo = partA + 1;
        }
    }
    throw new IllegalArgumentException("Input arrays not sorted");
}
// Time: O(log(min(m,n))), Space: O(1)
```

---

## 12 — Common Mistakes Checklist

```
□ Using (left + right) / 2 → overflow when left + right > Integer.MAX_VALUE
  Fix: left + (right - left) / 2

□ Loop condition: left < right vs left <= right
  Use <= when both bounds are inclusive candidates
  Use <  when one bound is always valid (find minimum rotated, peak element)

□ Moving to mid itself: left = mid or right = mid when you should skip it
  Fix: always left = mid + 1 or right = mid - 1 (with inclusive bounds)

□ Forgetting the answer search space bounds
  lo = minimum feasible value (not 0, not 1 — think what the constraint means)
  hi = maximum feasible value

□ Integer overflow in feasibility check (sum of large arrays)
  Fix: use long for accumulated sums
```

---

## 13 — Visual: How Binary Search Converges

Classic search for target=7 in `[1, 3, 5, 7, 9, 11, 13]`:
```
Index:  0   1   2   3   4   5   6
Array: [1,  3,  5,  7,  9,  11, 13]
        L           M               R    mid=3, arr[3]=7 == target → FOUND at index 3

Another pass (target=9):
        L           M               R    mid=3, arr[3]=7 < 9  → left = mid+1 = 4
                        L   M       R    mid=4, arr[4]=9 == 9 → FOUND at index 4

Rule: nums[mid] < target → left  = mid+1  (search RIGHT half)
      nums[mid] > target → right = mid-1  (search LEFT half)
      Always eliminate at least half — guaranteed O(log n)
```

**Binary search on answer** — monotone predicate visualized:
```
Answer space:  [1,  2,  3,  4,  5,  6,  7,  8,  9,  10]
Feasible?:     [NO, NO, NO, YES,YES,YES,YES,YES,YES,YES]
                              ^--- we want the LEFTMOST YES

Binary search finds the transition point in O(log(hi-lo)) feasibility checks.
Prerequisite: if feasible(x) then feasible(x+1) must also be true (monotone).
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Workers need at least `minProfit` profit and are grouped in teams. Given `difficulty[]` and `profit[]` for n jobs and a `group[]` of team sizes, count how many subsets of workers can do a job satisfying both constraints. *(Deliberately obscure — focus on the recognition step.)*

Actually, let's pick a cleaner unseen problem:

**Problem**: Given a sorted array and a target, return the index to insert the target (if not present, return where it would go). *(LC 35 — Search Insert Position — but let's walk through recognizing it.)*

**Step 1 — Read**: Input = sorted int[], target int. Output = int (index). No duplicates.

**Step 2 — Identify**: "sorted array", "find position" → classic binary search trigger. Brute force: scan left-to-right O(n). We can do O(log n). This is a **lower bound** binary search — first position where `nums[i] >= target`.

**Step 3 — Plan**:
- `left=0, right=n-1`.
- Invariant: the answer is always in `[left, right]` (inclusive).
- When `nums[mid] >= target`: the answer could be `mid` itself (first occurrence ≥ target), so `right = mid` (NOT `mid-1`).
- When `nums[mid] < target`: answer is to the right, so `left = mid + 1`.
- Exit: `left == right` → that's our answer.

```java
int searchInsert(int[] nums, int target) {
    int left = 0, right = nums.length;      // right = n (target could go at end)
    while (left < right) {                   // note: < not <=
        int mid = left + (right - left) / 2;
        if (nums[mid] < target) left  = mid + 1;
        else                    right = mid;   // could be the answer, don't exclude
    }
    return left;   // left == right == insertion point
}
// Time: O(log n), Space: O(1)
```

**Step 5 — Verify** on `[1,3,5,6]`, target=5:
- left=0, right=4, mid=2, nums[2]=5 >= 5 → right=2
- left=0, right=2, mid=1, nums[1]=3 < 5  → left=2
- left=2 == right=2 → return 2 ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty array | `right = -1`, loop skips | Return 0 or handle before loop |
| Target smaller than all | `left` never moves | Returns 0 — correct insertion point |
| Target larger than all | `right` never moves | Returns n — correct |
| Integer overflow in `mid` | `(left + right) / 2` overflows | Always use `left + (right - left) / 2` |
| `left < right` vs `left <= right` | Using wrong form causes infinite loop | `<= ` when both bounds are candidates; `<` when one bound is always valid |
| Floating point binary search | Integer `lo/hi` won't converge | Use `while (hi - lo > 1e-9)` and loop a fixed 100 times |

```java
// Small tweaks cheatsheet:

// "First true" (minimize) → shrink right, answer = right at end
int lo = 0, hi = max, ans = hi;
while (lo <= hi) {
    int mid = lo + (hi - lo) / 2;
    if (feasible(mid)) { ans = mid; hi = mid - 1; }
    else               lo = mid + 1;
}

// "Last true" (maximize) → shrink left, answer = lo-1 at end  
while (lo <= hi) {
    int mid = lo + (hi - lo) / 2;
    if (feasible(mid)) { ans = mid; lo = mid + 1; }
    else               hi = mid - 1;
}

// Floating point (e.g. find square root)
double lo = 0, hi = x;
for (int i = 0; i < 100; i++) {   // 100 iterations gives 2^-100 precision
    double mid = (lo + hi) / 2;
    if (mid * mid <= x) lo = mid; else hi = mid;
}
return lo;  // floor sqrt approximation
```

---

## 😵 Commonly Confused With

**vs Linear Scan**: Linear scan is O(n). Use binary search when the input is sorted OR the answer space has a monotone predicate. Deciding question: *Can I discard half the search space with one comparison?* Yes → Binary Search.

**vs Two Pointers**: Two pointers scan the full array pairing elements in O(n). Binary search halves the search space in O(log n). Deciding question: *Am I looking for a single position/value (BS) or combining two elements from opposite ends (TP)?*

**vs Ternary Search**: Ternary search finds the peak of a unimodal function. Binary search finds a boundary in a monotone (step) function. Use ternary search only when the function increases then decreases; otherwise binary search.

## 14 — Canonical LeetCode Problems by Flavor

| Flavor | Problems |
|--------|---------|
| Classic search | LC 704, LC 35 (search insert position) |
| First/last occurrence | LC 34 |
| Rotated sorted | LC 33, LC 81 (duplicates), LC 153 (find min), LC 154 |
| Peak element | LC 162, LC 852 (mountain array peak) |
| Search on answer — minimize | LC 875, LC 1011, LC 410, LC 1482, LC 2064 |
| Search on answer — maximize | LC 1552 (magnetic force), LC 2187 |
| 2D matrix | LC 74, LC 240 |
| Hard | LC 4 (median two arrays), LC 668 (kth in multiplication table) |

---

## 14 — System Design Connection

Binary search on answer is the backbone of:
- **Rate limiter calibration**: binary search for the minimum token bucket refill rate that keeps P99 latency under SLA
- **Auto-scaler**: binary search for minimum replica count that handles load
- **Database partitioning**: binary search for partition key range boundaries to ensure balanced splits
- **Kafka consumer lag**: binary search on offset to find first message after a timestamp (`offsetsForTimes`)

*Time: O(log n) all templates unless stated. Space: O(1).*
