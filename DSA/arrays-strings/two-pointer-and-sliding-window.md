# Two-Pointer and Sliding Window Patterns

**Category**: Arrays & Strings  
**Time Complexity**: O(n) for most variants  
**Space Complexity**: O(1) auxiliary (excluding output)  
**Real-world connection**: Rate limiter (sliding window counter), stream deduplication, network packet inspection

---

## Core Insight

Two-pointer and sliding window are the same idea at different levels of abstraction: maintain two indices into a sequence that move in a coordinated way, processing each element at most once. This turns O(n²) brute-force range queries into O(n) linear scans.

**When to reach for it**: whenever the problem asks about a contiguous subarray/substring satisfying some condition (max, min, count, validity), and the condition has a monotone relationship with window size — if a window is valid, expanding it stays valid (or invalid), never oscillates.

---

## Pattern 1: Opposite-End Two Pointers

Two pointers start at opposite ends and move toward each other.

**Template:**
```python
def two_sum_sorted(nums: list[int], target: int) -> tuple[int, int]:
    left, right = 0, len(nums) - 1
    while left < right:
        total = nums[left] + nums[right]
        if total == target:
            return left, right
        elif total < target:
            left += 1
        else:
            right -= 1
    return -1, -1
```

**When to use**: sorted array, finding pairs with a property (sum, difference, product), container-with-most-water style problems.

**Key problems**:
- Two Sum II (sorted input)
- Container With Most Water
- Trapping Rain Water (can also use stack)
- 3Sum (sort + two-pointer for each fixed element)

**Trap**: Only works when the array is sorted OR you can sort it without changing the answer. Never use on unsorted arrays expecting sorted-array behavior.

---

## Pattern 2: Same-Direction Two Pointers (Fast/Slow)

Both pointers start at the beginning; the fast pointer probes ahead while the slow pointer marks a processed boundary.

**Template:**
```python
def remove_duplicates(nums: list[int]) -> int:
    if not nums:
        return 0
    slow = 0
    for fast in range(1, len(nums)):
        if nums[fast] != nums[slow]:
            slow += 1
            nums[slow] = nums[fast]
    return slow + 1
```

**When to use**: in-place array modification, cycle detection (Floyd's), removing elements while preserving order.

**Key problems**:
- Remove Duplicates from Sorted Array
- Move Zeroes
- Linked List Cycle Detection (Floyd's — slow moves 1 step, fast moves 2)
- Find Duplicate Number (array as linked list — Floyd's)

---

## Pattern 3: Fixed-Size Sliding Window

Window size k is known. Slide across the array, adding the incoming element and removing the outgoing one.

**Template:**
```python
def max_sum_subarray_k(nums: list[int], k: int) -> int:
    window_sum = sum(nums[:k])
    max_sum = window_sum
    for i in range(k, len(nums)):
        window_sum += nums[i] - nums[i - k]
        max_sum = max(max_sum, window_sum)
    return max_sum
```

**When to use**: aggregate over every window of a fixed size (max, sum, count, average).

**Key problems**:
- Maximum Sum Subarray of Size K
- Find All Anagrams in a String (character count window)
- Sliding Window Maximum (use monotone deque for O(n))

---

## Pattern 4: Variable-Size Sliding Window (Expand/Shrink)

Window grows from the right; shrinks from the left when a constraint is violated.

**Template:**
```python
def length_of_longest_substring_k_distinct(s: str, k: int) -> int:
    from collections import defaultdict
    freq = defaultdict(int)
    left = 0
    max_len = 0
    for right in range(len(s)):
        freq[s[right]] += 1
        while len(freq) > k:           # constraint violated → shrink
            freq[s[left]] -= 1
            if freq[s[left]] == 0:
                del freq[s[left]]
            left += 1
        max_len = max(max_len, right - left + 1)
    return max_len
```

**When to use**: find the longest/shortest subarray/substring satisfying a constraint, when expanding can make the window invalid and shrinking can restore validity.

**Key problems**:
- Longest Substring Without Repeating Characters
- Longest Substring with At Most K Distinct Characters
- Minimum Window Substring (shrink as much as possible while still valid)
- Fruit Into Baskets
- Subarrays with K Different Integers (exactly-k = at-most-k minus at-most-(k-1))

**Trap**: The "minimum window" variant shrinks greedily: expand until valid, then shrink as far as possible before recording the answer and expanding again.

---

## Pattern 5: Sliding Window with Monotone Deque

For "maximum in every window of size k," a deque maintains a decreasing sequence of values — the front is always the current window maximum.

```python
from collections import deque

def sliding_window_maximum(nums: list[int], k: int) -> list[int]:
    dq: deque[int] = deque()  # stores indices
    result = []
    for i, val in enumerate(nums):
        # remove elements outside the window
        while dq and dq[0] < i - k + 1:
            dq.popleft()
        # maintain decreasing order — remove smaller elements from back
        while dq and nums[dq[-1]] < val:
            dq.pop()
        dq.append(i)
        if i >= k - 1:
            result.append(nums[dq[0]])
    return result
```

**Complexity**: O(n) — each element enters and leaves the deque at most once.

---

## Complexity Reference

| Pattern | Time | Space |
|---------|------|-------|
| Opposite-end two pointers | O(n) | O(1) |
| Fast/slow two pointers | O(n) | O(1) |
| Fixed window | O(n) | O(1) |
| Variable window | O(n) | O(k) where k = constraint size |
| Monotone deque window | O(n) | O(k) |

---

## Real-World System Design Connections

### Rate Limiter — Sliding Window Counter
The variable-size window pattern is the conceptual basis for the sliding window log and sliding window counter rate limiting algorithms.

```
Fixed window counter:  bucket[minute] += 1         → O(1) but boundary burst problem
Sliding window log:    store each request timestamp → O(requests) — exact but expensive
Sliding window counter: interpolate between two fixed-window buckets → O(1) approximation
```

The sliding window counter formula:
```
allowed_requests = prev_window_count × (1 - elapsed_fraction) + current_window_count
```
If this exceeds the limit, reject. This is an approximation but within 0.003% of exact for most traffic patterns. Redis uses this internally for its `CL.THROTTLE` command.

### Stream Deduplication — Fixed Window
Deduplicating events in a Kafka consumer: maintain a Bloom filter or LRU cache over the last N events. The "window" is the dedup horizon. LinkedIn uses a 24-hour sliding window for notification deduplication.

### TCP Congestion Window
TCP's congestion window is a variable-size sliding window over unacknowledged bytes. The slow-start algorithm is expand-aggressively, and congestion-detected-shrink — the same expand/shrink dynamic as pattern 4.

---

## Interview Decision Tree

```
Does the problem involve a contiguous range in a sequence?
    └── Yes → Two-pointer / sliding window
            Is the window size fixed?
                └── Yes → Fixed window (Pattern 3)
                └── No  → Variable window (Pattern 4)
                        Is the constraint a max/min within the window?
                            └── Yes → Monotone deque (Pattern 5)
            Are we finding a pair with a property?
                └── Yes → Sorted? → Opposite-end (Pattern 1)
                           Not sorted? → HashMap for O(n) (Two Sum I style)
            Are we modifying in-place?
                └── Yes → Fast/slow (Pattern 2)
```

---

## Common Mistakes

1. **Off-by-one on window boundary**: `right - left + 1` is the window size (inclusive both ends). Easy to forget the `+1`.
2. **Shrinking too eagerly**: in minimum window problems, shrink only after recording the current valid window.
3. **Wrong invariant on deque**: the deque stores indices, not values — always use `nums[dq[0]]` not `dq[0]` for the maximum.
4. **Assuming sorted input for pattern 1**: opposite-end only works when the monotone property holds — usually requires a sorted array.
5. **Not clearing frequency maps between test cases**: in contest settings, leftover state in a `defaultdict` causes wrong answers.
