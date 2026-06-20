# Intervals

> Interval problems involve ranges `[start, end]`. The core operations are **merging overlapping intervals**, **inserting a new interval**, and **scheduling tasks** to minimize resources.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the input contain ranges/intervals `[start, end]`?
- [ ] Does the problem ask to **merge, insert, count overlaps, or schedule**?
- [ ] Is the first step almost always **sorting by start time**?

**Trigger phrases**: "merge intervals", "insert interval", "meeting rooms", "minimum meeting rooms", "non-overlapping intervals", "employee free time", "minimum number of arrows", "video stitching", "remove covered intervals"

**Key insight**: two intervals `[a, b]` and `[c, d]` **overlap** if and only if `a <= d && c <= b` (or equivalently: they DON'T overlap only if `b < c` or `d < a`).

---

## 2 — Flavor Detection

| Flavor | Signal | Approach |
|--------|--------|---------|
| **Merge overlapping** | Reduce to minimum set of non-overlapping intervals | Sort by start; greedily extend current interval |
| **Insert and merge** | Add a new interval into a sorted list | Binary search or linear scan to find insertion point |
| **Minimum rooms (scheduling)** | Minimum resources for simultaneous events | Sort starts/ends separately OR min-heap of end times |
| **Maximum non-overlapping** | Remove minimum intervals to make non-overlapping | Sort by end time; greedily keep earliest-ending |
| **Point coverage** | Count how many intervals cover each point | Sort + sweep line or merge |
| **Burst balloons / arrows** | Minimum arrows to pop all balloons | Sort by end; greedily shoot at rightmost common point |

---

## 3 — Merge Intervals (LC 56)

```java
int[][] merge(int[][] intervals) {
    Arrays.sort(intervals, (a, b) -> a[0] - b[0]);   // sort by start

    List<int[]> result = new ArrayList<>();
    int[] current = intervals[0];

    for (int i = 1; i < intervals.length; i++) {
        if (intervals[i][0] <= current[1]) {
            // Overlapping: extend current interval's end
            current[1] = Math.max(current[1], intervals[i][1]);
        } else {
            // Non-overlapping: finalize current, start new
            result.add(current);
            current = intervals[i];
        }
    }
    result.add(current);   // add last interval
    return result.toArray(new int[result.size()][]);
}
// Time: O(n log n), Space: O(n)
```

**Overlap condition**: `intervals[i][0] <= current[1]` (new start ≤ current end).

---

## 4 — Insert Interval (LC 57)

Input is already sorted and non-overlapping. Insert `newInterval` and merge.

```java
int[][] insert(int[][] intervals, int[] newInterval) {
    List<int[]> result = new ArrayList<>();
    int i = 0, n = intervals.length;

    // Step 1: all intervals that END before newInterval starts — no overlap
    while (i < n && intervals[i][1] < newInterval[0]) {
        result.add(intervals[i++]);
    }

    // Step 2: all intervals that OVERLAP with newInterval — merge into newInterval
    while (i < n && intervals[i][0] <= newInterval[1]) {
        newInterval[0] = Math.min(newInterval[0], intervals[i][0]);
        newInterval[1] = Math.max(newInterval[1], intervals[i][1]);
        i++;
    }
    result.add(newInterval);

    // Step 3: all intervals that START after newInterval ends — no overlap
    while (i < n) result.add(intervals[i++]);

    return result.toArray(new int[result.size()][]);
}
// Time: O(n), Space: O(n)
```

---

## 5 — Meeting Rooms I — Can One Person Attend All? (LC 252)

```java
boolean canAttendMeetings(int[][] intervals) {
    Arrays.sort(intervals, (a, b) -> a[0] - b[0]);
    for (int i = 1; i < intervals.length; i++) {
        if (intervals[i][0] < intervals[i-1][1]) return false;   // overlap
    }
    return true;
}
// Time: O(n log n), Space: O(1)
```

---

## 6 — Meeting Rooms II — Minimum Rooms Required (LC 253)

**Approach 1: Min-Heap** (track when each room's meeting ends)

```java
int minMeetingRooms(int[][] intervals) {
    Arrays.sort(intervals, (a, b) -> a[0] - b[0]);   // sort by start

    PriorityQueue<Integer> endTimes = new PriorityQueue<>();   // min-heap of end times

    for (int[] interval : intervals) {
        if (!endTimes.isEmpty() && endTimes.peek() <= interval[0]) {
            endTimes.poll();   // reuse a room whose meeting just ended
        }
        endTimes.offer(interval[1]);   // add this meeting's end time
    }
    return endTimes.size();   // rooms in use = heap size
}
// Time: O(n log n), Space: O(n)
```

**Approach 2: Two sorted arrays (start/end sweep)** — O(n log n), O(n) but more elegant:

```java
int minMeetingRoomsSweep(int[][] intervals) {
    int n = intervals.length;
    int[] starts = new int[n], ends = new int[n];
    for (int i = 0; i < n; i++) { starts[i] = intervals[i][0]; ends[i] = intervals[i][1]; }
    Arrays.sort(starts);
    Arrays.sort(ends);

    int rooms = 0, maxRooms = 0, endPtr = 0;
    for (int start : starts) {
        if (start < ends[endPtr]) {
            rooms++;           // meeting started before any meeting ended
        } else {
            endPtr++;          // reuse a room
        }
        maxRooms = Math.max(maxRooms, rooms);
    }
    return maxRooms;
}
```

---

## 7 — Non-Overlapping Intervals — Minimum Removals (LC 435)

**Goal**: remove minimum intervals to make the rest non-overlapping.  
**Key insight**: sort by END time. Greedily keep each interval that doesn't conflict with the last kept one (earliest-ending first = most room left for future intervals).

```java
int eraseOverlapIntervals(int[][] intervals) {
    Arrays.sort(intervals, (a, b) -> a[1] - b[1]);   // sort by END time

    int removals = 0, lastEnd = Integer.MIN_VALUE;

    for (int[] interval : intervals) {
        if (interval[0] >= lastEnd) {
            lastEnd = interval[1];   // keep this interval
        } else {
            removals++;              // remove this interval (it overlaps and ends later)
        }
    }
    return removals;
}
// Time: O(n log n), Space: O(1)
```

**Why sort by end time?** We want to keep as many intervals as possible. Keeping the one that ends earliest leaves maximum space for subsequent intervals — classic interval scheduling maximization (Activity Selection Problem).

---

## 8 — Minimum Number of Arrows to Burst Balloons (LC 452)

Each balloon is an interval `[start, end]`. An arrow shot at position x bursts all balloons where `start <= x <= end`. Find minimum arrows.

**Key insight**: same as minimum non-overlapping partitions. Sort by end; one arrow at the first balloon's end covers all overlapping balloons.

```java
int findMinArrowShots(int[][] points) {
    Arrays.sort(points, (a, b) -> Integer.compare(a[1], b[1]));  // sort by end (avoid overflow)

    int arrows = 1, arrowPos = points[0][1];

    for (int i = 1; i < points.length; i++) {
        if (points[i][0] > arrowPos) {         // balloon starts after current arrow
            arrows++;
            arrowPos = points[i][1];           // shoot at this balloon's end
        }
        // else: current arrow also bursts this balloon (start <= arrowPos)
    }
    return arrows;
}
// Time: O(n log n), Space: O(1)
```

---

## 9 — Interval List Intersections (LC 986)

Given two lists of non-overlapping intervals (each sorted), find all intersections.

```java
int[][] intervalIntersection(int[][] A, int[][] B) {
    List<int[]> result = new ArrayList<>();
    int i = 0, j = 0;

    while (i < A.length && j < B.length) {
        int lo = Math.max(A[i][0], B[j][0]);
        int hi = Math.min(A[i][1], B[j][1]);

        if (lo <= hi) result.add(new int[]{lo, hi});   // there's an intersection

        if (A[i][1] < B[j][1]) i++;   // advance the interval that ends earlier
        else                   j++;
    }
    return result.toArray(new int[result.size()][]);
}
// Time: O(m + n), Space: O(m + n)
```

---

## 10 — Employee Free Time (LC 759)

Given K employees' schedules (each sorted), find free time slots all employees share.

```java
List<Interval> employeeFreeTime(List<List<Interval>> schedule) {
    // Collect and sort all intervals
    List<Interval> all = new ArrayList<>();
    for (List<Interval> emp : schedule) all.addAll(emp);
    all.sort((a, b) -> a.start - b.start);

    List<Interval> result = new ArrayList<>();
    int end = all.get(0).end;

    for (Interval interval : all) {
        if (interval.start > end) {
            result.add(new Interval(end, interval.start));  // gap = free time
        }
        end = Math.max(end, interval.end);
    }
    return result;
}
// Time: O(N log N) where N = total intervals across all employees
// Space: O(N)
```

---

## 11 — Remove Covered Intervals (LC 1288)

```java
int removeCoveredIntervals(int[][] intervals) {
    // Sort by start asc, then by end DESC (so longer interval comes first when same start)
    Arrays.sort(intervals, (a, b) -> a[0] != b[0] ? a[0] - b[0] : b[1] - a[1]);

    int kept = 0, maxEnd = 0;
    for (int[] interval : intervals) {
        if (interval[1] > maxEnd) {   // not covered by any previous interval
            kept++;
            maxEnd = interval[1];
        }
    }
    return kept;
}
// Time: O(n log n), Space: O(1)
```

---

## 12 — Video Stitching (LC 1024)

Cover [0, time] using minimum number of clips.

```java
int videoStitching(int[][] clips, int time) {
    Arrays.sort(clips, (a, b) -> a[0] != b[0] ? a[0] - b[0] : b[1] - a[1]);

    int count = 0, curEnd = 0, maxReach = 0, i = 0;

    while (curEnd < time) {
        // Among all clips starting at or before curEnd, pick the one extending farthest
        while (i < clips.length && clips[i][0] <= curEnd)
            maxReach = Math.max(maxReach, clips[i++][1]);

        if (maxReach == curEnd) return -1;   // no progress — gap exists
        curEnd = maxReach;
        count++;
    }
    return count;
}
// Time: O(n log n), Space: O(1)
// Same pattern as "Jump Game II"
```

---

## 13 — Summary: Sort Strategy by Problem Type

| Problem | Sort by | Key variable |
|---------|---------|-------------|
| Merge intervals | Start asc | Current interval's end (extend it) |
| Minimum rooms | Start asc | Min-heap of end times (or two sorted arrays) |
| Max non-overlapping (remove min) | **End asc** | Last accepted interval's end |
| Minimum arrows | **End asc** | Current arrow position |
| Insert interval | Already sorted | Three-phase linear scan |
| Interval intersections | Already sorted (two lists) | Two-pointer, advance earlier-ending |

---

## 14 — Visual: Interval Merge in Action

```
Input: [[1,3],[2,6],[8,10],[15,18]]
Sort by start:  [1,3]  [2,6]  [8,10]  [15,18]

merged=[1,3]
  [2,6]: 2 ≤ 3 (overlap) → extend end to max(3,6)=6.   merged=[1,6]
  [8,10]: 8 > 6 (gap)    → push [1,6], start new.       merged=[1,6],[8,10]
  [15,18]: 15 > 10 (gap) → push [8,10], start new.      merged=[1,6],[8,10],[15,18]

Result: [[1,6],[8,10],[15,18]]

Key rule: if nextInterval.start <= current.end → OVERLAP → merge (extend end)
          if nextInterval.start >  current.end → GAP     → push current, take next
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: You are given a list of employee work intervals (each is `[start, end]`). Find the total number of hours no employee is working (the gaps in coverage). Assume the overall workday spans from the minimum start to the maximum end.

**Step 1 — Read**: Input = list of `[start, end]` intervals (unsorted, may overlap). Output = total gap time (integer).

**Step 2 — Identify**: "Gaps between intervals" → I need to merge all overlapping intervals first, then measure the spaces between merged intervals. Core pattern: **Merge Intervals**.

**Step 3 — Plan**:
- Sort by start time.
- Merge all overlapping intervals (standard merge template).
- Gap = `merged[i].start - merged[i-1].end` for each adjacent pair.
- Sum all gaps.

**Step 4 — Code**:
```java
int totalGapTime(int[][] intervals) {
    if (intervals.length == 0) return 0;
    Arrays.sort(intervals, (a, b) -> a[0] - b[0]);

    // merge
    List<int[]> merged = new ArrayList<>();
    merged.add(intervals[0]);
    for (int i = 1; i < intervals.length; i++) {
        int[] last = merged.get(merged.size() - 1);
        if (intervals[i][0] <= last[1]) {
            last[1] = Math.max(last[1], intervals[i][1]);
        } else {
            merged.add(intervals[i]);
        }
    }

    // sum gaps
    int gap = 0;
    for (int i = 1; i < merged.size(); i++)
        gap += merged.get(i)[0] - merged.get(i - 1)[1];
    return gap;
}
// Time: O(n log n) sort. Space: O(n) merged list.
```

**Step 5 — Verify** on `[[1,4],[2,6],[8,10],[12,15]]`:
- Sorted: same. Merge → `[1,6],[8,10],[12,15]`.
- Gaps: (8-6)=2, (12-10)=2. Total = 4. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Unsorted input | Wrong merge — non-overlapping might appear to overlap | Always sort by `a[0] - b[0]` first |
| One interval | No merge needed | Return that single interval as-is |
| All intervals overlap | Everything merges into one | Handled — keep extending `last[1]` |
| Touching intervals `[1,3],[3,5]` | Depends on problem — touching = overlap? | Use `<=` for merge-if-touching, `<` for strict gap |
| Insert into sorted list | Must find right position and merge left+right neighbors | Use binary search to find insertion point, then merge |
| Negative times | Sort still works; difference still valid | No special handling needed |

```java
// "Touching = overlap" (closed intervals [1,3] and [3,5] share point 3):
if (intervals[i][0] <= last[1]) { ... }  // ≤ treats touching as overlap

// "Touching = gap" (open intervals, no shared point):
if (intervals[i][0] < last[1]) { ... }   // < treats touching as separate

// Meeting Rooms: can one person attend all?
Arrays.sort(intervals, (a, b) -> a[0] - b[0]);
for (int i = 1; i < intervals.length; i++)
    if (intervals[i][0] < intervals[i-1][1]) return false;  // overlap found
return true;
```

---

## 😵 Commonly Confused With

**vs Greedy Scheduling**: Interval problems often look like greedy scheduling (Job sequencing, Activity selection). Deciding question: *Are you minimizing rooms/resources (greedy on end times) or merging overlapping ranges (sort by start, extend)?*

**vs Sliding Window**: Both deal with ranges. Deciding question: *Is the range fixed or variable over a linear array (SW), or are the intervals given as explicit `[start,end]` pairs from a list (Intervals)?*

**vs Two Pointers on sorted arrays**: Two pointers scan one array from both ends. Interval merge scans a list of pairs. Deciding question: *Do you have one array of values, or a list of start/end pairs?*

---

## 15 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| Merge/insert | LC 56, LC 57, LC 1288 |
| Scheduling | LC 252, LC 253, LC 435 |
| Counting | LC 986, LC 759 |
| Minimum cover / greedy | LC 452, LC 1024, LC 45 (jump game II — same idea) |
| Meeting rooms (classic) | LC 252 (free), LC 253 (rooms needed) |

---

## 15 — System Design Connection

Interval logic appears in:
- **Calendar scheduling** (Google Calendar, Calendly): find free/busy slots, minimum resources
- **Database time-range queries**: B+ tree range scans, partition pruning
- **Network packet reassembly**: TCP reordering — merge received byte ranges, detect gaps
- **Prometheus alerting**: alert interval deduplication — merge overlapping alert windows
