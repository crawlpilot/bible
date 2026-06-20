# Interval Problems

**Category**: Arrays & Strings  
**Time Complexity**: O(n log n) for most (dominated by sort)  
**Space Complexity**: O(n) for output; O(1) extra  
**Real-world connection**: Calendar systems, resource scheduling, database range locks, CPU task scheduling, network bandwidth reservation

---

## Core Insight

Interval problems (merge overlapping intervals, find all intersections, minimum meeting rooms) share a common structure: **sort by start time, then sweep**. Sorting converts the 2D problem (each interval has a start and end) into a 1D problem where you process intervals in order and make local decisions.

The two-pointer pattern, priority queues (min-heaps), and greedy sweeps are the main tools.

---

## Overlap Condition

Two intervals `[a, b]` and `[c, d]` overlap iff `a <= d AND c <= b`. They do NOT overlap iff `b < c OR d < a` (one ends before the other starts).

**Closed vs half-open matters in interviews**: clarify whether `[1,3]` and `[3,5]` overlap. Usually yes (they share point 3), but edge cases matter in scheduling problems.

---

## Pattern 1: Merge Overlapping Intervals

```python
def merge_intervals(intervals: list[list[int]]) -> list[list[int]]:
    intervals.sort(key=lambda x: x[0])   # sort by start
    merged = [intervals[0]]
    for start, end in intervals[1:]:
        if start <= merged[-1][1]:        # overlaps with last merged interval
            merged[-1][1] = max(merged[-1][1], end)  # extend end
        else:
            merged.append([start, end])
    return merged
```

**Time**: O(n log n) — dominated by sort  
**Key**: after sorting, you only need to compare each interval to the last merged interval (not all previous ones).

---

## Pattern 2: Insert Interval into Sorted List

```python
def insert_interval(intervals: list[list[int]], new: list[int]) -> list[list[int]]:
    result = []
    i, n = 0, len(intervals)

    # Add all intervals that end before new starts (no overlap)
    while i < n and intervals[i][1] < new[0]:
        result.append(intervals[i])
        i += 1

    # Merge all overlapping intervals
    while i < n and intervals[i][0] <= new[1]:
        new[0] = min(new[0], intervals[i][0])
        new[1] = max(new[1], intervals[i][1])
        i += 1
    result.append(new)

    # Add remaining intervals
    result.extend(intervals[i:])
    return result
```

**Time**: O(n) — already sorted, single pass  
**Use this template for**: "insert interval and merge" problems where the list is already sorted.

---

## Pattern 3: Minimum Meeting Rooms (Resource Counting)

How many meeting rooms (or workers, CPUs, servers) are needed to handle all intervals simultaneously?

**Approach: sort starts and ends separately, use two pointers.**

```python
def min_meeting_rooms(intervals: list[list[int]]) -> int:
    starts = sorted(i[0] for i in intervals)
    ends = sorted(i[1] for i in intervals)

    rooms = 0
    max_rooms = 0
    j = 0   # pointer into ends

    for start in starts:
        if start < ends[j]:   # new meeting starts before any meeting ends
            rooms += 1
        else:
            j += 1            # a meeting ended — room freed
        max_rooms = max(max_rooms, rooms)
    return max_rooms
```

**Alternative: min-heap approach** (track end times of active meetings):

```python
import heapq

def min_meeting_rooms_heap(intervals: list[list[int]]) -> int:
    intervals.sort(key=lambda x: x[0])
    heap = []   # min-heap of end times of active meetings
    for start, end in intervals:
        if heap and heap[0] <= start:
            heapq.heapreplace(heap, end)  # reuse the room whose meeting ended earliest
        else:
            heapq.heappush(heap, end)     # need a new room
    return len(heap)
```

**Two-pointer vs heap**: two-pointer is O(n log n) time, O(n) space. Heap is also O(n log n) but the heap approach is more generalizable when you need to know *which* resource is freed (not just *how many*).

---

## Pattern 4: Interval Intersection

Given two lists of non-overlapping sorted intervals, find all intersections.

```python
def interval_intersection(A: list[list[int]], B: list[list[int]]) -> list[list[int]]:
    i, j = 0, 0
    result = []
    while i < len(A) and j < len(B):
        lo = max(A[i][0], B[j][0])
        hi = min(A[i][1], B[j][1])
        if lo <= hi:
            result.append([lo, hi])
        # Advance the interval that ends first (it can't contribute to more intersections)
        if A[i][1] < B[j][1]:
            i += 1
        else:
            j += 1
    return result
```

**Time**: O(m + n) where m, n are lengths of A and B.  
**Key insight**: always advance the pointer to the interval with the smaller end — it cannot overlap with any future interval in the other list.

---

## Pattern 5: Non-Overlapping Intervals (Greedy Removal)

Find the minimum number of intervals to remove so no two overlap. Classic greedy: sort by end time, greedily keep intervals.

```python
def erase_overlap_intervals(intervals: list[list[int]]) -> int:
    intervals.sort(key=lambda x: x[1])  # sort by END time (not start)
    removed = 0
    last_end = float('-inf')
    for start, end in intervals:
        if start >= last_end:
            last_end = end    # keep this interval
        else:
            removed += 1      # remove this interval (it overlaps with the previous kept)
    return removed
```

**Why sort by end?** Keeping the interval with the earliest end leaves maximum room for future intervals — this is the interval scheduling maximization (ISM) greedy argument.

**Same template applies to**: "minimum arrows to burst balloons," "activity selection problem," "task scheduler."

---

## Pattern 6: Sweep Line for Coverage Problems

Count how many intervals cover each point, or find a point covered by the maximum number of intervals.

```python
from collections import defaultdict

def max_overlap_at_any_point(intervals: list[list[int]]) -> int:
    events = []
    for start, end in intervals:
        events.append((start, 1))    # +1 at start
        events.append((end + 1, -1)) # -1 just after end (closed interval)
    events.sort()
    max_overlap = current = 0
    for _, delta in events:
        current += delta
        max_overlap = max(max_overlap, current)
    return max_overlap
```

**Use this when**: "how many intervals contain point X?", "what is the maximum simultaneous load?", "find the peak concurrent connections."

---

## Key Problems Reference

| Problem | Pattern | Sort By |
|---------|---------|---------|
| Merge Intervals (LC 56) | Merge sweep | Start |
| Insert Interval (LC 57) | Three-phase insert | Already sorted |
| Meeting Rooms I (LC 252) | Any overlap? | Start, compare adjacent |
| Meeting Rooms II (LC 253) | Min rooms | Starts + ends separately |
| Non-overlapping Intervals (LC 435) | Greedy keep | End |
| Interval List Intersections (LC 986) | Two-pointer | Both already sorted |
| Employee Free Time (LC 759) | Merge all → find gaps | Start |
| Car Pooling (LC 1094) | Difference array | N/A (difference array) |
| Maximum CPU Load | Heap of end times | Start |
| Minimum Number of Arrows (LC 452) | Greedy keep | End |

---

## Real-World System Design Connections

### Database Range Locks
InnoDB's gap locking and next-key locking use interval logic: a transaction holds a range lock `[a, b]` that blocks inserts in that key range. Detecting conflicts between lock requests is an interval intersection problem. The lock manager maintains active intervals in a sorted structure and runs intersection checks O(log n) per request.

### Calendar / Scheduling Systems
Google Calendar's "find a meeting time" feature across multiple attendees is the inverse of "minimum meeting rooms": given N people's busy intervals, find free slots common to all. Implementation: merge busy intervals per person → intersect free-time intervals across people → return gaps.

### CPU Task Scheduling (CFS)
Linux CFS (Completely Fair Scheduler) uses a red-black tree keyed by virtual runtime (analogous to interval start). Selecting the next task is O(log n). The "minimum meeting rooms" problem is isomorphic to CPU scheduling with preemption.

### Network Bandwidth Reservation
RSVP (Resource Reservation Protocol) treats bandwidth reservations as intervals in time. Admitting a new flow requires checking that the total reserved bandwidth in the requested time interval doesn't exceed link capacity — a maximum overlap problem.

### A/B Test Slot Management
Feature flag systems that allocate user cohorts use interval-style allocation: user hash space [0, 1] is divided into experiment slots. Checking whether a new experiment conflicts with existing ones is an interval intersection problem. Optimizely and LaunchDarkly handle this internally.

---

## Common Mistakes

1. **Wrong overlap condition**: intervals `[a, b]` and `[c, d]` overlap iff `a <= d && c <= b`. The negation is `b < c || d < a`. Getting this wrong produces wrong merge logic.

2. **Sorting by the wrong field**: merge intervals → sort by start. Remove minimum overlapping → sort by end. Mixing these up produces wrong greedy results.

3. **Not handling the max correctly in merge**: `merged[-1][1] = max(merged[-1][1], end)`. If you just use `end`, a shorter interval fully contained within the current merged interval would incorrectly shrink the merged end.

4. **Two-pointer meeting rooms off-by-one**: the condition is `start < ends[j]` (strictly less than) for closed intervals. For half-open intervals `[start, end)`, it's `start < ends[j]`. Clarify the problem's interval convention.

5. **Sweep line with closed intervals**: if intervals are closed `[a, b]`, the event at `b` should end after events at `b` start (use `(b+1, -1)` for integer coordinates, or process start events before end events at the same coordinate for floating-point).
