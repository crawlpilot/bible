# Prefix Sum and Difference Arrays

**Category**: Arrays & Strings  
**Time Complexity**: O(n) preprocessing, O(1) per query  
**Space Complexity**: O(n)  
**Real-world connection**: Database range aggregates, time-series analytics, distributed tracing latency percentiles

---

## Core Insight

A prefix sum array converts the problem "what is the sum of elements from index i to j?" from O(n) per query to O(1) per query after O(n) preprocessing. The tradeoff: you spend space and preprocessing time to answer many range queries cheaply.

The difference array inverts this: instead of querying a range, you want to *update* a range efficiently — add a value to all elements from i to j in O(1), then recover the array in O(n).

---

## Prefix Sum

**Construction:**
```python
def build_prefix_sum(nums: list[int]) -> list[int]:
    prefix = [0] * (len(nums) + 1)  # 1-indexed: prefix[i] = sum(nums[0..i-1])
    for i, val in enumerate(nums):
        prefix[i + 1] = prefix[i] + val
    return prefix

def range_sum(prefix: list[int], left: int, right: int) -> int:
    return prefix[right + 1] - prefix[left]  # sum of nums[left..right] inclusive
```

**Complexity after preprocessing:**
| Operation | Time |
|-----------|------|
| Build | O(n) |
| Range sum query | O(1) |
| Point update | O(n) — rebuild required |

**Use prefix sum when**: static array, many range queries.  
**Don't use when**: array is modified frequently — use a Fenwick tree (BIT) instead.

---

## 2D Prefix Sum

For matrices, extend to two dimensions. Used in image processing (summed area table) and 2D range queries.

```python
def build_2d_prefix(grid: list[list[int]]) -> list[list[int]]:
    m, n = len(grid), len(grid[0])
    prefix = [[0] * (n + 1) for _ in range(m + 1)]
    for r in range(m):
        for c in range(n):
            prefix[r+1][c+1] = (grid[r][c]
                                 + prefix[r][c+1]
                                 + prefix[r+1][c]
                                 - prefix[r][c])  # inclusion-exclusion
    return prefix

def rect_sum(prefix, r1, c1, r2, c2):
    return (prefix[r2+1][c2+1]
            - prefix[r1][c2+1]
            - prefix[r2+1][c1]
            + prefix[r1][c1])
```

---

## Prefix Sum — Key Problem Patterns

### Pattern 1: Subarray Sum Equals K
Count subarrays whose sum equals k. Without prefix sums: O(n²). With prefix sums + hashmap: O(n).

```python
def subarray_sum_equals_k(nums: list[int], k: int) -> int:
    from collections import defaultdict
    count = defaultdict(int)
    count[0] = 1   # empty prefix
    prefix = 0
    result = 0
    for num in nums:
        prefix += num
        result += count[prefix - k]  # if prefix[j] - prefix[i] == k, subarray [i..j] sums to k
        count[prefix] += 1
    return result
```

**Insight**: `prefix[j] - prefix[i] = k` ↔ `prefix[i] = prefix[j] - k`. We've seen prefix[j]-k before iff the map has it.

### Pattern 2: Maximum Subarray Sum (Kadane's as prefix sum view)

Kadane's algorithm is equivalent to: track the minimum prefix sum seen so far, then `max(prefix[j] - min_prefix_so_far)` at each j.

```python
def max_subarray(nums: list[int]) -> int:
    max_sum = float('-inf')
    min_prefix = 0
    prefix = 0
    for num in nums:
        prefix += num
        max_sum = max(max_sum, prefix - min_prefix)
        min_prefix = min(min_prefix, prefix)
    return max_sum
```

### Pattern 3: Number of Subarrays Divisible by K
Use `prefix % k` instead of raw prefix sum. Two subarrays with the same prefix mod k have a subarray between them divisible by k.

### Pattern 4: Binary Subarray Sum (0/1 arrays)
For problems like "count subarrays with equal 0s and 1s": convert 0 → -1, then count subarrays summing to 0 using the hashmap approach.

---

## Difference Array

The difference array D is defined as `D[i] = A[i] - A[i-1]` (with `D[0] = A[0]`). This makes range updates O(1): to add `val` to `A[l..r]`, do `D[l] += val` and `D[r+1] -= val`. Recover the array by prefix-summing D.

```python
def apply_range_updates(n: int, updates: list[tuple]) -> list[int]:
    diff = [0] * (n + 1)
    for l, r, val in updates:
        diff[l] += val
        diff[r + 1] -= val
    # recover array
    result = []
    running = 0
    for i in range(n):
        running += diff[i]
        result.append(running)
    return result
```

**Complexity:**
| Operation | Time |
|-----------|------|
| Range update | O(1) |
| Recover full array | O(n) |
| Point query after all updates | O(n) — prefix-sum the diff array first |

**When to use**: many range updates, then one full-array read at the end (not interleaved queries).

---

## Key Problems

| Problem | Pattern | Trick |
|---------|---------|-------|
| Subarray Sum Equals K (LC 560) | Prefix sum + hashmap | `prefix[j] - prefix[i] = k` → look up `prefix[j]-k` |
| Maximum Subarray (LC 53) | Prefix sum min tracking | Kadane's = max(prefix[j] - min_prefix[0..j]) |
| Product of Array Except Self (LC 238) | Left/right prefix product | No division needed |
| Range Sum Query (LC 303) | Static prefix sum | Build once, query O(1) |
| Range Sum Query 2D (LC 304) | 2D prefix sum | Summed area table |
| Number of Subarrays Divisible by K (LC 974) | Prefix mod hashmap | Group by prefix%k |
| Car Pooling (LC 1094) | Difference array | Range update on [pickup, dropoff] |
| Corporate Flight Bookings (LC 1109) | Difference array | Range update on seat counts |
| Shifting Letters II (LC 2381) | Difference array | Apply char shifts as range updates |

---

## Real-World System Design Connections

### Database Range Aggregates
PostgreSQL's window functions (`SUM() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`) implement prefix sums at query time. This is why analytical queries over sorted time columns are faster than arbitrary-range aggregates — the database can exploit prefix sum structure in sorted clustered indexes.

### Time-Series Analytics
ClickHouse's array functions include `arrayCumSum` (prefix sum). Grafana's "cumulative sum" panel type is a client-side prefix sum over returned data points.

### Latency Percentiles in Distributed Tracing
A histogram of response latencies is an array of bucket counts. The cumulative histogram (prefix sum of buckets) lets you compute any percentile in O(log(buckets)) via binary search: find the smallest bucket where `cumulative_count ≥ target_percentile × total_count`. Prometheus histograms are stored as cumulative counts precisely for this reason.

### Segment-Based Traffic Shaping
Network traffic shapers use a difference-array-like structure: events arrive as (start_time, end_time, bandwidth_reserved). The "how much bandwidth is in use at time t?" query is: apply all (start, end, bw) updates to a difference array, then prefix-sum to time t. This is the bandwidth reservation model in RSVP and similar QoS protocols.

---

## Decision: Prefix Sum vs. Fenwick Tree vs. Segment Tree

| Need | Data Structure |
|------|---------------|
| Static array, range sum queries | Prefix sum array — O(1) query, simplest |
| Dynamic array, point updates + range sum | Fenwick tree (BIT) — O(log n) update, O(log n) query |
| Dynamic array, range updates + range queries | Segment tree — O(log n) both, more complex |
| Range updates, one final read | Difference array — O(1) update, O(n) final read |
| 2D range sum queries | 2D prefix sum or 2D Fenwick tree |

---

## Common Mistakes

1. **Off-by-one in 1-indexed prefix arrays**: `prefix[i]` = sum of first `i` elements = `sum(nums[0..i-1])`. Range sum `nums[l..r]` = `prefix[r+1] - prefix[l]`.
2. **Forgetting `count[0] = 1`** in the hashmap approach: the empty prefix (sum = 0) must be pre-inserted.
3. **Using prefix sum for dynamic arrays**: if the array changes between queries, rebuild cost is O(n) per update. Use BIT instead.
4. **Difference array for interleaved updates + queries**: difference array only works if you do all updates first, then recover the array. Interleaved point queries require BIT.
5. **2D inclusion-exclusion sign error**: the formula has `- prefix[r][c]` (adding back the corner that was subtracted twice). A consistent derivation beats memorizing the formula.
