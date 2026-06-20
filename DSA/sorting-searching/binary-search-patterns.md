# Binary Search Patterns

**Category**: Sorting & Searching  
**Time Complexity**: O(log n) per query  
**Space Complexity**: O(1)  
**Real-world connection**: Database index lookups, consistent hashing ring, load balancer routing, version bisection (git bisect)

---

## Core Insight

Binary search is not just "find a value in a sorted array." It is a general technique for any problem where:
1. The search space can be represented as a range (numbers, indices, or values)
2. A predicate on that space is **monotone**: once it becomes true, it stays true (or vice versa)

When you see these two properties, binary search applies — even if there's no explicit sorted array.

---

## The Universal Binary Search Template

Avoid the classic off-by-one errors by using a single, consistent template:

```python
def binary_search(lo: int, hi: int, condition) -> int:
    """
    Returns the smallest value in [lo, hi] for which condition(mid) is True.
    Precondition: condition is False for some prefix of [lo, hi], then True for the rest.
    """
    while lo < hi:
        mid = lo + (hi - lo) // 2   # avoids integer overflow (critical in Java/C++)
        if condition(mid):
            hi = mid        # mid might be the answer; don't exclude it
        else:
            lo = mid + 1   # mid is definitely not the answer
    return lo   # lo == hi; this is the answer
```

**Choosing lo/hi**: set lo and hi to be the smallest and largest possible answers, not indices into an array.

---

## Pattern 1: Classic Value Search

Find the exact value (or confirm absence):

```python
def search(nums: list[int], target: int) -> int:
    lo, hi = 0, len(nums) - 1
    while lo <= hi:         # note: lo <= hi (not lo < hi) for exact search
        mid = lo + (hi - lo) // 2
        if nums[mid] == target:
            return mid
        elif nums[mid] < target:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1
```

**When to use**: exact lookup in a sorted array. If you only need "does X exist," this is the base case.

---

## Pattern 2: Lower Bound (first position ≥ target)

Find the leftmost index where `nums[i] >= target`. Equivalent to C++'s `lower_bound`.

```python
def lower_bound(nums: list[int], target: int) -> int:
    lo, hi = 0, len(nums)   # hi = len(nums) so we can return "not found" = n
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if nums[mid] < target:
            lo = mid + 1
        else:
            hi = mid
    return lo   # position where target would be inserted to maintain sorted order
```

**Use this for**:
- Finding where to insert a value (bisect_left)
- Counting elements < target: `lower_bound(nums, target)` gives that count
- First occurrence of target: check `nums[lo] == target`

---

## Pattern 3: Upper Bound (first position > target)

Find the leftmost index where `nums[i] > target`. Equivalent to C++'s `upper_bound`.

```python
def upper_bound(nums: list[int], target: int) -> int:
    lo, hi = 0, len(nums)
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if nums[mid] <= target:
            lo = mid + 1
        else:
            hi = mid
    return lo
```

**Count of target in array**: `upper_bound(nums, target) - lower_bound(nums, target)`  
**Last occurrence of target**: `upper_bound(nums, target) - 1` (then verify)

---

## Pattern 4: Binary Search on the Answer (Search Space is Values)

The array isn't sorted, but the *answer* (a value you're minimizing or maximizing) lives in a range with a monotone validity predicate.

**Template problem**: "Minimize the maximum" or "Maximize the minimum" — almost always binary search on the answer.

```python
def minimize_maximum_distance(positions: list[int], k: int) -> int:
    """Place k balls in sorted positions to maximize the minimum gap."""
    def can_place_k_balls(min_gap: int) -> bool:
        count = 1
        last = positions[0]
        for pos in positions[1:]:
            if pos - last >= min_gap:
                count += 1
                last = pos
        return count >= k

    lo, hi = 1, positions[-1] - positions[0]
    return binary_search(lo, hi + 1, can_place_k_balls) - 1
    # we want the last value for which can_place is True
    # so binary search for first False, then subtract 1
```

**Key problems using this pattern**:
- Koko Eating Bananas (minimize eating speed)
- Capacity to Ship Packages Within D Days (minimize ship capacity)
- Aggressive Cows / Magnetic Force Between Balls (maximize minimum distance)
- Split Array Largest Sum (minimize largest sum of subarray)
- Find Minimum Time to Finish Jobs (minimize maximum job time per worker)

---

## Pattern 5: Binary Search in Rotated Sorted Array

The array was sorted, then rotated at an unknown pivot. It has two sorted halves. Determine which half mid falls in by comparing with lo.

```python
def search_rotated(nums: list[int], target: int) -> int:
    lo, hi = 0, len(nums) - 1
    while lo <= hi:
        mid = lo + (hi - lo) // 2
        if nums[mid] == target:
            return mid
        if nums[lo] <= nums[mid]:   # left half is sorted
            if nums[lo] <= target < nums[mid]:
                hi = mid - 1
            else:
                lo = mid + 1
        else:                        # right half is sorted
            if nums[mid] < target <= nums[hi]:
                lo = mid + 1
            else:
                hi = mid - 1
    return -1
```

**Trap**: the condition is `nums[lo] <= nums[mid]` (not `<`). Equal handles the case where lo == mid.

---

## Pattern 6: Find Peak Element

A peak is any element greater than its neighbors. In any array without plateaus, a peak always exists. Binary search by comparing mid to mid+1.

```python
def find_peak(nums: list[int]) -> int:
    lo, hi = 0, len(nums) - 1
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if nums[mid] > nums[mid + 1]:
            hi = mid        # peak is at mid or to the left
        else:
            lo = mid + 1   # peak is to the right of mid
    return lo
```

**Insight**: if `nums[mid] < nums[mid+1]`, the slope is ascending — a peak must exist to the right. If `nums[mid] > nums[mid+1]`, the slope is descending — a peak exists at mid or to the left.

---

## Complexity Reference

| Operation | Time | Notes |
|-----------|------|-------|
| Exact search | O(log n) | Classic |
| Lower/upper bound | O(log n) | Useful for range counting |
| Binary search on answer | O(log(range) × check) | check is usually O(n) |
| Rotated array search | O(log n) | Two sorted halves |
| Peak finding | O(log n) | Slope direction argument |

---

## Real-World System Design Connections

### Consistent Hashing Ring
A node's position on the hash ring is looked up with `bisect_right(ring, hash(key))` — an upper_bound operation on a sorted list of node positions. This maps every key to its successor node in O(log N) where N is the number of virtual nodes. Cassandra, DynamoDB, and Riak all use this variant.

### Database Index Lookups (B-Tree)
A B-tree page search is multi-level binary search: within each page, binary search the sorted key array to find the next-level pointer. The height of the B-tree is log_B(N) (where B is the branching factor ~500 for a 16KB page with 4-byte keys). PostgreSQL's `btree_gist` extension and MySQL's InnoDB both traverse B-trees this way.

### Git Bisect
`git bisect` is binary search over the commit graph. You mark a commit as good or bad; git picks the midpoint commit. After O(log N) steps, it finds the first bad commit. This is binary search on the answer where the predicate is "does this commit contain the bug."

### Load Balancer — Weighted Round Robin
A weighted round-robin load balancer builds a prefix-sum array of weights and uses `bisect_left(prefix_sums, random_value)` to find the selected backend in O(log N). NGINX's `upstream` module uses this approach.

### Version Rollout (Feature Flags)
Gradual rollouts by user ID use binary search on a sorted list of user ID ranges. Check if `user_id` falls in the enabled range using `bisect_left` — O(log segments) per lookup.

---

## Decision Tree

```
Does a sorted array or sorted search space exist?
    └── Yes → binary search applies
            Do I want an exact value?
                └── Yes → classic template (lo <= hi)
            Do I want the first position ≥ target?
                └── Yes → lower_bound
            Do I want the first position > target?
                └── Yes → upper_bound
            Is the array rotated?
                └── Yes → rotated search (compare nums[lo] to nums[mid])
            Is it a "minimize max" or "maximize min" problem?
                └── Yes → binary search on answer; write a feasibility checker
    └── No → is there a monotone predicate on a value range?
                └── Yes → binary search on the answer space
                └── No  → not a binary search problem
```

---

## Common Mistakes

1. **`mid = (lo + hi) // 2` overflow**: in Java/C++ with 32-bit int, this overflows when lo+hi > 2³¹-1. Use `mid = lo + (hi - lo) // 2`. Python has arbitrary-precision integers so this is only relevant in interviews where you're thinking about language choice.

2. **Wrong loop condition for bounds**: classic exact search uses `while lo <= hi`. Lower/upper bound uses `while lo < hi`. Mixing them is the #1 source of off-by-one bugs.

3. **Not defining what `condition(mid)` means**: for binary-search-on-answer problems, write out the feasibility function clearly before writing the binary search loop. Ambiguous predicates cause wrong `lo`/`hi` update rules.

4. **Rotated array with duplicates**: if the array has duplicates (e.g., [1,3,1,1,1]), the left/right determination `nums[lo] <= nums[mid]` breaks. The safe fallback is `lo += 1` when `nums[lo] == nums[mid]`, degrading to O(n) worst case.

5. **Off-by-one in "search on answer" hi**: if the answer can equal `hi`, set `hi = max_possible_value` (inclusive). If you set `hi = max - 1`, you may exclude the valid answer. Always derive `hi` from the problem constraints, not from "looks about right."
