# Heap / Priority Queue

> A heap gives you O(log n) insert/delete and O(1) peek at the minimum (min-heap) or maximum (max-heap). Use it whenever you need to **repeatedly extract the smallest or largest element** from a dynamic set.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Do you need the **k-th largest/smallest** element from a stream or array?
- [ ] Do you need to **repeatedly extract the minimum/maximum** from a changing set?
- [ ] Are you merging **k sorted lists** and need to know which list has the current minimum?
- [ ] Do you need the **running median** of a stream?
- [ ] Does the problem involve a **greedy choice** on the "best available" item at each step?

**Trigger phrases**: "k largest elements", "k closest points", "top k frequent", "find median from data stream", "merge k sorted lists", "task scheduler", "ugly number", "meeting rooms II", "reorganize string"

**In Java**: use `PriorityQueue<>` (min-heap by default). For max-heap: `new PriorityQueue<>(Collections.reverseOrder())`.

---

## 2 — Flavor Detection

| Flavor | Signal | Heap Type | Size |
|--------|--------|-----------|------|
| **Top-K largest** | K biggest elements | Min-heap | Keep K smallest seen → top = K-th largest |
| **Top-K smallest** | K smallest elements | Max-heap | Keep K largest seen → top = K-th smallest |
| **K-way merge** | Merge K sorted arrays/lists | Min-heap | K elements (one per list) |
| **Two-heap median** | Median of a stream | Max-heap (lower) + min-heap (upper) | Balanced halves |
| **Sliding window max/min** | Max/min in each window of size K | Monotone deque (prefer) or max-heap + lazy delete | — |
| **Greedy scheduling** | Assign tasks, minimize time | Min-heap on earliest deadline / frequency | Variable |
| **Dijkstra shortest path** | Weighted graph shortest path | Min-heap on (distance, node) | O(E) |

---

## 3 — Java PriorityQueue Cheat Sheet

```java
// Min-heap (default) — smallest element at top
PriorityQueue<Integer> minHeap = new PriorityQueue<>();

// Max-heap — largest element at top
PriorityQueue<Integer> maxHeap = new PriorityQueue<>(Collections.reverseOrder());

// Custom comparator (sort by second element of int[] pair)
PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> a[1] - b[1]);

// Common operations
minHeap.offer(x);       // insert — O(log n)
minHeap.poll();         // remove and return min — O(log n)
minHeap.peek();         // look at min without removing — O(1)
minHeap.size();         // number of elements
minHeap.isEmpty();      // check empty

// IMPORTANT: PriorityQueue does NOT support O(1) contains() or O(log n) remove(element)
// Lazy deletion pattern: mark deleted in a HashSet, skip when popping
```

---

## 4 — Top-K Largest Elements (LC 215)

**Key insight**: maintain a min-heap of size K. The top of the heap is the K-th largest.

```java
int findKthLargest(int[] nums, int k) {
    PriorityQueue<Integer> minHeap = new PriorityQueue<>();   // min-heap of size K
    for (int num : nums) {
        minHeap.offer(num);
        if (minHeap.size() > k) minHeap.poll();   // evict smallest
    }
    return minHeap.peek();   // K-th largest
}
// Time: O(n log k), Space: O(k)

// Get all top-K (not just k-th):
List<Integer> topK(int[] nums, int k) {
    PriorityQueue<Integer> minHeap = new PriorityQueue<>();
    for (int num : nums) {
        minHeap.offer(num);
        if (minHeap.size() > k) minHeap.poll();
    }
    return new ArrayList<>(minHeap);   // unordered, but all are top-K
}
```

**Why min-heap for top-K largest?**  
The heap's top is the *minimum* of the K candidates. When a new element comes in larger than the heap's min, replace the min — the newcomer deserves a spot.

---

## 5 — Top-K Frequent Elements (LC 347)

```java
int[] topKFrequent(int[] nums, int k) {
    // Step 1: count frequencies
    Map<Integer, Integer> freq = new HashMap<>();
    for (int num : nums) freq.merge(num, 1, Integer::sum);

    // Step 2: min-heap on frequency, keep top-K
    PriorityQueue<Map.Entry<Integer, Integer>> minHeap =
        new PriorityQueue<>((a, b) -> a.getValue() - b.getValue());

    for (Map.Entry<Integer, Integer> entry : freq.entrySet()) {
        minHeap.offer(entry);
        if (minHeap.size() > k) minHeap.poll();
    }

    // Step 3: extract results
    int[] result = new int[k];
    for (int i = k - 1; i >= 0; i--) result[i] = minHeap.poll().getKey();
    return result;
}
// Time: O(n log k), Space: O(n)
```

**Alternative — Bucket Sort approach** (O(n) time):
```java
int[] topKFrequentBucket(int[] nums, int k) {
    Map<Integer, Integer> freq = new HashMap<>();
    for (int n : nums) freq.merge(n, 1, Integer::sum);

    List<Integer>[] bucket = new List[nums.length + 1];
    for (var e : freq.entrySet()) {
        int f = e.getValue();
        if (bucket[f] == null) bucket[f] = new ArrayList<>();
        bucket[f].add(e.getKey());
    }

    List<Integer> result = new ArrayList<>();
    for (int i = bucket.length - 1; i >= 0 && result.size() < k; i--)
        if (bucket[i] != null) result.addAll(bucket[i]);

    return result.stream().mapToInt(Integer::intValue).toArray();
}
// Time: O(n), Space: O(n)
```

---

## 6 — K Closest Points to Origin (LC 973)

```java
int[][] kClosest(int[][] points, int k) {
    // Max-heap: evict the farthest point when size > K
    PriorityQueue<int[]> maxHeap = new PriorityQueue<>(
        (a, b) -> (b[0]*b[0] + b[1]*b[1]) - (a[0]*a[0] + a[1]*a[1])
    );
    for (int[] point : points) {
        maxHeap.offer(point);
        if (maxHeap.size() > k) maxHeap.poll();   // remove farthest
    }
    return maxHeap.toArray(new int[k][]);
}
// Time: O(n log k), Space: O(k)
```

---

## 7 — Find Median from Data Stream (LC 295) — Two Heaps

**Key insight**: split data into two halves.
- `lowerHalf` (max-heap): contains all elements ≤ median
- `upperHalf` (min-heap): contains all elements ≥ median
- Invariant: `lowerHalf.size() == upperHalf.size()` or `lowerHalf.size() == upperHalf.size() + 1`

```java
class MedianFinder {
    private PriorityQueue<Integer> lower;   // max-heap (lower half)
    private PriorityQueue<Integer> upper;   // min-heap (upper half)

    MedianFinder() {
        lower = new PriorityQueue<>(Collections.reverseOrder());
        upper = new PriorityQueue<>();
    }

    void addNum(int num) {
        lower.offer(num);                          // always insert into lower first
        upper.offer(lower.poll());                 // balance: push lower's max to upper

        if (lower.size() < upper.size())           // keep lower >= upper in size
            lower.offer(upper.poll());
    }

    double findMedian() {
        if (lower.size() > upper.size()) return lower.peek();
        return (lower.peek() + upper.peek()) / 2.0;
    }
}
// addNum: O(log n), findMedian: O(1), Space: O(n)
```

---

## 8 — Merge K Sorted Lists (LC 23)

**Key insight**: keep one element per list in a min-heap. Always extract the global minimum.

```java
ListNode mergeKLists(ListNode[] lists) {
    // Min-heap ordered by node value
    PriorityQueue<ListNode> pq = new PriorityQueue<>((a, b) -> a.val - b.val);

    for (ListNode head : lists)
        if (head != null) pq.offer(head);   // add initial heads

    ListNode dummy = new ListNode(0), curr = dummy;
    while (!pq.isEmpty()) {
        ListNode node = pq.poll();          // extract minimum
        curr.next = node;
        curr = curr.next;
        if (node.next != null) pq.offer(node.next);   // advance that list's pointer
    }
    return dummy.next;
}
// Time: O(N log k) where N = total nodes, k = number of lists
// Space: O(k)
```

**Generalization — K-Way Merge pattern** (also used in: external merge sort, merging K sorted arrays, smallest range covering K lists):
```java
// LC 632 — Smallest Range Covering Elements from K Lists
int[] smallestRange(List<List<Integer>> nums) {
    // Min-heap: [value, listIndex, elementIndex]
    PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> a[0] - b[0]);
    int max = Integer.MIN_VALUE;

    for (int i = 0; i < nums.size(); i++) {
        pq.offer(new int[]{nums.get(i).get(0), i, 0});
        max = Math.max(max, nums.get(i).get(0));
    }

    int[] result = {pq.peek()[0], max};
    while (true) {
        int[] curr = pq.poll();
        int val = curr[0], li = curr[1], ei = curr[2];
        if (ei + 1 == nums.get(li).size()) break;   // exhausted a list

        int next = nums.get(li).get(ei + 1);
        pq.offer(new int[]{next, li, ei + 1});
        max = Math.max(max, next);

        if (max - pq.peek()[0] < result[1] - result[0])
            result = new int[]{pq.peek()[0], max};
    }
    return result;
}
```

---

## 9 — Task Scheduler (LC 621)

**Key insight**: greedily schedule the most frequent remaining task. Use a max-heap for frequency and a queue for the cooldown period.

```java
int leastInterval(char[] tasks, int n) {
    int[] freq = new int[26];
    for (char t : tasks) freq[t - 'A']++;

    PriorityQueue<Integer> maxHeap = new PriorityQueue<>(Collections.reverseOrder());
    for (int f : freq) if (f > 0) maxHeap.offer(f);

    Queue<int[]> cooldown = new LinkedList<>();  // [remaining_freq, available_at_time]
    int time = 0;

    while (!maxHeap.isEmpty() || !cooldown.isEmpty()) {
        time++;
        if (!maxHeap.isEmpty()) {
            int freq2 = maxHeap.poll() - 1;
            if (freq2 > 0) cooldown.offer(new int[]{freq2, time + n});
        }
        if (!cooldown.isEmpty() && cooldown.peek()[1] == time)
            maxHeap.offer(cooldown.poll()[0]);
    }
    return time;
}
// Time: O(N log 26) = O(N), Space: O(26) = O(1)
```

**Math formula shortcut** (for this specific problem):
```java
int leastIntervalMath(char[] tasks, int n) {
    int[] freq = new int[26];
    for (char t : tasks) freq[t - 'A']++;
    Arrays.sort(freq);
    int maxFreq = freq[25];
    int idleSlots = (maxFreq - 1) * n;
    for (int i = 24; i >= 0 && freq[i] > 0; i--)
        idleSlots -= Math.min(freq[i], maxFreq - 1);
    return tasks.length + Math.max(0, idleSlots);
}
```

---

## 10 — Reorganize String (LC 767)

Arrange characters so no two adjacent are the same — greedily pick most frequent.

```java
String reorganizeString(String s) {
    int[] freq = new int[26];
    for (char c : s.toCharArray()) freq[c - 'a']++;

    PriorityQueue<int[]> maxHeap = new PriorityQueue<>((a, b) -> b[1] - a[1]);
    for (int i = 0; i < 26; i++)
        if (freq[i] > 0) maxHeap.offer(new int[]{i, freq[i]});

    StringBuilder sb = new StringBuilder();
    while (maxHeap.size() >= 2) {
        int[] first  = maxHeap.poll();
        int[] second = maxHeap.poll();
        sb.append((char)('a' + first[0]));
        sb.append((char)('a' + second[0]));
        if (--first[1]  > 0) maxHeap.offer(first);
        if (--second[1] > 0) maxHeap.offer(second);
    }
    if (!maxHeap.isEmpty()) {
        int[] last = maxHeap.poll();
        if (last[1] > 1) return "";   // impossible: same char must repeat
        sb.append((char)('a' + last[0]));
    }
    return sb.toString();
}
// Time: O(n log 26) = O(n), Space: O(n)
```

---

## 11 — Sliding Window Maximum (LC 239)

For max in each window of size K — **monotone deque is preferred** (O(n)), but heap with lazy deletion works:

```java
// Preferred: Monotone Deque — O(n)
int[] maxSlidingWindow(int[] nums, int k) {
    Deque<Integer> deque = new ArrayDeque<>();   // stores indices, decreasing values
    int[] result = new int[nums.length - k + 1];

    for (int i = 0; i < nums.length; i++) {
        // Remove elements out of window
        while (!deque.isEmpty() && deque.peekFirst() < i - k + 1)
            deque.pollFirst();

        // Maintain decreasing order — remove smaller elements from back
        while (!deque.isEmpty() && nums[deque.peekLast()] < nums[i])
            deque.pollLast();

        deque.offerLast(i);

        if (i >= k - 1) result[i - k + 1] = nums[deque.peekFirst()];
    }
    return result;
}
// Time: O(n), Space: O(k)
```

---

## 12 — Ugly Number II (LC 264)

Generate the n-th ugly number (factors only 2, 3, 5) using a min-heap:

```java
int nthUglyNumber(int n) {
    PriorityQueue<Long> minHeap = new PriorityQueue<>();
    Set<Long> seen = new HashSet<>();
    minHeap.offer(1L);
    seen.add(1L);
    long ugly = 1;

    for (int i = 0; i < n; i++) {
        ugly = minHeap.poll();
        for (long factor : new long[]{2, 3, 5}) {
            long next = ugly * factor;
            if (seen.add(next)) minHeap.offer(next);
        }
    }
    return (int) ugly;
}
// Time: O(n log n), Space: O(n)
```

**DP alternative** (O(n) time, O(n) space — three pointers):
```java
int nthUglyNumberDP(int n) {
    int[] dp = new int[n];
    dp[0] = 1;
    int p2 = 0, p3 = 0, p5 = 0;
    for (int i = 1; i < n; i++) {
        int next = Math.min(dp[p2]*2, Math.min(dp[p3]*3, dp[p5]*5));
        dp[i] = next;
        if (next == dp[p2]*2) p2++;
        if (next == dp[p3]*3) p3++;
        if (next == dp[p5]*5) p5++;
    }
    return dp[n-1];
}
```

---

## 13 — Visual: Min-Heap Structure

**Inserting [5, 2, 8, 1, 9] into a min-heap**:
```
Insert 5:        Insert 2:        Insert 8:        Insert 1:          Insert 9:
    5                2                2                1                  1
                    / \              / \              / \                 / \
                   5   8            5   8            2   8              2   8
                                                    /                  / \
                                                   5                  5   9

Heap property: parent ≤ both children (min-heap)
Root is ALWAYS the minimum element → poll() in O(log n), peek() in O(1)

"Top of stack" analogy: the smallest element always bubbles to the top.
```

**Why min-heap for top-K LARGEST?**
```
Goal: find 3 largest from [3,1,5,7,2,8]

Keep only K=3 elements in the heap.
The MINIMUM of those K is the "threshold" — anything smaller gets evicted.

Process 3: heap=[3]
Process 1: heap=[1,3]      (1 < 3 but still only 2 elements)
Process 5: heap=[3,5]      (heap full after removing 1 — 1 < threshold)
           Wait — heap=[1,3,5], now full (size=3). New element? Evict min:
Process 7: 7 > heap.peek()=1 → evict 1, add 7. heap=[3,5,7]
Process 2: 2 < heap.peek()=3 → 2 can't be in top-3. Skip.
Process 8: 8 > heap.peek()=3 → evict 3, add 8. heap=[5,7,8]

heap.peek() = 5 = 3rd largest ✓
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a list of points `(x, y)` and an integer K, find the K points closest to the origin `(0,0)`. Distance = `sqrt(x² + y²)`. *(LC 973 — but let's recognize it from scratch.)*

**Step 1 — Read**: Input = int[][] points, int K. Output = K points (any order). Closest = smallest Euclidean distance.

**Step 2 — Identify**: "K closest" → keep K candidates and always evict the worst (farthest). We need the K-th smallest distance. → **Max-Heap of size K** (the root = farthest of our K candidates; evict it when we find something closer).

**Step 3 — Plan**:
- Max-heap ordered by distance (largest distance at top).
- For each point: add to heap. If heap size > K → poll (remove farthest).
- After all points: heap contains exactly the K closest.

```java
int[][] kClosest(int[][] points, int k) {
    // max-heap: largest distance at top
    PriorityQueue<int[]> maxHeap = new PriorityQueue<>(
        (a, b) -> (b[0]*b[0] + b[1]*b[1]) - (a[0]*a[0] + a[1]*a[1])
    );
    for (int[] p : points) {
        maxHeap.offer(p);
        if (maxHeap.size() > k) maxHeap.poll();  // evict farthest
    }
    return maxHeap.toArray(new int[k][]);
}
// Time: O(n log k), Space: O(k)
```

**Step 5 — Verify** on `[(1,3),(-2,2),(5,8),(0,1)]`, K=2:
- Add (1,3): heap=[(1,3)], dist=10
- Add (-2,2): heap=[(1,3),(-2,2)], dists=10,8
- Add (5,8): heap=[(5,8),(1,3),(-2,2)], size=3>2 → evict max(89) = (5,8). heap=[(1,3),(-2,2)]
- Add (0,1): dist=1 < 10 (current max). heap=[(1,3),(-2,2),(0,1)], size=3>2 → evict (1,3). heap=[(-2,2),(0,1)]
- Result: [(-2,2),(0,1)] ✓ (distances 8 and 1 — the two smallest)

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| K > array size | Heap never shrinks | Handle: return entire array |
| K = 1 | Works — heap of size 1 | Fine — peek() gives the single answer |
| Ties in distance/frequency | Comparator returns 0, order undefined | Add secondary sort if deterministic order required |
| Two-heap median with same value | Add to lower, then rebalance | Always add to lower first, push max to upper, then rebalance sizes |
| Lazy deletion (remove arbitrary element) | PQ has no O(log n) remove by value | Use `HashSet<>` for deleted items; skip them when polling |

```java
// Lazy deletion pattern (when you need to remove specific elements):
PriorityQueue<Integer> pq = new PriorityQueue<>();
Set<Integer> deleted = new HashSet<>();

void delete(int val) { deleted.add(val); }  // mark, don't remove

int poll() {
    while (!pq.isEmpty() && deleted.contains(pq.peek()))
        pq.poll();    // drain marked elements
    return pq.poll();
}

// Comparator for int[] sorted by second element:
PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> a[1] - b[1]);
// CAREFUL: a[1] - b[1] can overflow if values are large! Use Integer.compare(a[1], b[1]) instead
PriorityQueue<int[]> pq2 = new PriorityQueue<>((a, b) -> Integer.compare(a[1], b[1]));
```

---

## 😵 Commonly Confused With

**vs Sorting**: Sorting gives you all K largest in O(n log n). Heap gives you only K largest in O(n log K). When K << n, heap is significantly faster. Deciding question: *Do you need ALL elements sorted, or just the top K?*

**vs Quick Select**: Quick select finds the K-th largest in O(n) average but O(n²) worst case. Heap is O(n log K) guaranteed. For a static array, quick select is faster on average. For a stream (elements arriving one at a time), heap is the only option. Deciding question: *Static array or dynamic stream?*

**vs Monotone Stack**: Monotone stack finds the NEAREST greater/smaller element. Heap finds the GLOBALLY smallest/largest. Deciding question: *Do you need the closest element satisfying a condition (stack) or the overall best element (heap)?*

## 14 — Canonical LeetCode Problems

| Flavor | Problems |
|--------|---------|
| K-th largest/smallest | LC 215, LC 703 (stream), LC 378 (sorted matrix) |
| Top-K frequent | LC 347, LC 692 |
| K closest | LC 973, LC 1470 |
| Two-heap median | LC 295, LC 480 (sliding window median) |
| K-way merge | LC 23, LC 378, LC 632 |
| Scheduling / greedy | LC 621, LC 767, LC 1882 |
| Dijkstra | LC 743, LC 787, LC 1514 |

---

## 14 — System Design Connection

Heaps power critical production systems:
- **Job schedulers** (Kubernetes HPA, Airflow): priority queue of pending tasks ordered by earliest deadline or priority score
- **Dijkstra in network routing**: link-state routing uses min-heap over (distance, router)
- **Top-K dashboards**: distributed approximate top-K using Count-Min Sketch + local heaps merged at query time
- **Median monitoring**: two-heap approach used in P50/P99 latency trackers (though in practice t-digest or HDR histogram is used)
