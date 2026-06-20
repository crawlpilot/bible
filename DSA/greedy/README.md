# Greedy

> Make the locally optimal choice at each step, trusting it leads to a globally optimal solution. Greedy is correct only when the problem has the **greedy choice property** and **optimal substructure** — verify with an exchange argument before coding.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Can you make a **decision at each step** without reconsidering previous decisions?
- [ ] Does **sorting** by some attribute enable optimal local choices?
- [ ] Is there a **"take as much as possible / earliest / smallest"** structure?
- [ ] Would DP work, but the DP recurrence reveals only one choice is ever optimal?

**Trigger phrases**: "minimum number of", "maximum profit", "can reach the end", "minimum platforms", "schedule tasks", "assign cookies", "jump game", "gas station", "partition labels"

**Verify greediness**: use an **exchange argument** — assume the greedy solution differs from optimal at position i, show you can swap without making things worse. If you can, greedy is correct.

**When Greedy FAILS**: fractional decisions must be binary (0/1 knapsack → use DP), or local choices conflict with future decisions (coin change with arbitrary denominations → use DP).

---

## 2 — Flavor Detection

| Flavor | Signal | Greedy Key |
|--------|--------|-----------|
| **Interval scheduling** | Maximize non-overlapping events | Sort by end time, take earliest-ending |
| **Jump game** | Can reach end / minimum jumps | Always jump to farthest reachable |
| **Gas station** | Circular route feasibility | Track surplus/deficit; start from highest surplus |
| **Assign resources** | Match children ↔ cookies, workers ↔ jobs | Sort both; match smallest satisfying |
| **String rearrangement** | No two adjacent same | Take most frequent; interleave |
| **Minimum additions** | Make array valid with fewest changes | Forward scan, greedily extend coverage |
| **Buy-sell stock** | Multiple transactions | Sum all positive differences |
| **Partition labels** | Each char in only one part | Last occurrence of each character |

---

## 3 — Jump Game I — Can Reach End? (LC 55)

```java
boolean canJump(int[] nums) {
    int maxReach = 0;
    for (int i = 0; i < nums.length; i++) {
        if (i > maxReach) return false;             // can't reach index i
        maxReach = Math.max(maxReach, i + nums[i]); // update farthest reachable
    }
    return true;
}
// Time: O(n), Space: O(1)
```

---

## 4 — Jump Game II — Minimum Jumps (LC 45)

**Greedy**: at each position, track the farthest you can reach in the NEXT jump. Take a jump only when you've exhausted your current range.

```java
int jump(int[] nums) {
    int jumps = 0, currentEnd = 0, farthest = 0;
    for (int i = 0; i < nums.length - 1; i++) {
        farthest = Math.max(farthest, i + nums[i]);
        if (i == currentEnd) {          // exhausted current jump's range
            jumps++;
            currentEnd = farthest;      // take the jump to the farthest point
        }
    }
    return jumps;
}
// Time: O(n), Space: O(1)
```

---

## 5 — Gas Station (LC 134)

Determine the only starting index that allows a complete circuit.

**Key insights**:
1. If total gas ≥ total cost, a solution always exists (and is unique for circular problems).
2. If running sum drops below 0, reset: start is impossible at any previous station.

```java
int canCompleteCircuit(int[] gas, int[] cost) {
    int totalSurplus = 0, currentSurplus = 0, start = 0;

    for (int i = 0; i < gas.length; i++) {
        int gain = gas[i] - cost[i];
        totalSurplus  += gain;
        currentSurplus += gain;

        if (currentSurplus < 0) {
            start = i + 1;          // can't start at any station 0..i
            currentSurplus = 0;     // reset
        }
    }
    return totalSurplus >= 0 ? start : -1;
}
// Time: O(n), Space: O(1)
```

---

## 6 — Best Time to Buy and Sell Stock II (LC 122) — Multiple Transactions

**Greedy**: capture every upswing. Add `prices[i] - prices[i-1]` whenever it's positive.

```java
int maxProfit(int[] prices) {
    int profit = 0;
    for (int i = 1; i < prices.length; i++)
        profit += Math.max(0, prices[i] - prices[i-1]);
    return profit;
}
// Time: O(n), Space: O(1)
```

---

## 7 — Assign Cookies (LC 455)

Maximize number of content children. Each child needs `greed[i]`, each cookie has size `size[j]`.

```java
int findContentChildren(int[] greed, int[] size) {
    Arrays.sort(greed);
    Arrays.sort(size);
    int child = 0, cookie = 0;
    while (child < greed.length && cookie < size.length) {
        if (size[cookie] >= greed[child]) child++;   // cookie satisfies child
        cookie++;                                      // always move to next cookie
    }
    return child;
}
// Time: O(n log n + m log m), Space: O(1)
```

---

## 8 — Partition Labels (LC 763)

Partition a string so each letter appears in at most one part. Maximize number of parts.

```java
List<Integer> partitionLabels(String s) {
    int[] last = new int[26];
    for (int i = 0; i < s.length(); i++) last[s.charAt(i) - 'a'] = i;

    List<Integer> result = new ArrayList<>();
    int start = 0, end = 0;

    for (int i = 0; i < s.length(); i++) {
        end = Math.max(end, last[s.charAt(i) - 'a']);  // extend partition to cover all occurrences
        if (i == end) {                                  // reached the end of current partition
            result.add(end - start + 1);
            start = i + 1;
        }
    }
    return result;
}
// Time: O(n), Space: O(1) [26-element array is constant]
```

---

## 9 — Minimum Number of Platforms / Meeting Rooms (LC 253 variant)

See `intervals/README.md` for the full solution. Greedy insight: sort starts and ends separately; a new platform is needed only when a meeting starts before any previous meeting ends.

---

## 10 — Activity Selection (Maximum Non-Overlapping Intervals)

Classic greedy proof: always take the activity ending earliest. Exchange argument: if optimal doesn't take the earliest-ending activity, replace it with the earliest-ending one — the schedule is at least as good.

```java
int maxActivities(int[][] activities) {
    Arrays.sort(activities, (a, b) -> a[1] - b[1]);   // sort by end time
    int count = 1, lastEnd = activities[0][1];
    for (int i = 1; i < activities.length; i++) {
        if (activities[i][0] >= lastEnd) {    // start >= last end → no overlap
            count++;
            lastEnd = activities[i][1];
        }
    }
    return count;
}
// Same pattern as LC 435 (eraseOverlapIntervals)
```

---

## 11 — Candy Distribution (LC 135)

Each child must get ≥ 1 candy. Children with higher rating than neighbor must get more.

**Two-pass greedy**: left-to-right (enforce left neighbor rule), right-to-left (enforce right neighbor rule), take max.

```java
int candy(int[] ratings) {
    int n = ratings.length;
    int[] candies = new int[n];
    Arrays.fill(candies, 1);

    // Left to right: if ratings[i] > ratings[i-1], give more than left neighbor
    for (int i = 1; i < n; i++)
        if (ratings[i] > ratings[i-1]) candies[i] = candies[i-1] + 1;

    // Right to left: if ratings[i] > ratings[i+1], ensure more than right neighbor
    for (int i = n-2; i >= 0; i--)
        if (ratings[i] > ratings[i+1]) candies[i] = Math.max(candies[i], candies[i+1]+1);

    int total = 0;
    for (int c : candies) total += c;
    return total;
}
// Time: O(n), Space: O(n)
```

---

## 12 — Minimum Number of Boats (LC 881)

Pairs of people in boats; boat can hold weight ≤ limit.

```java
int numRescueBoats(int[] people, int limit) {
    Arrays.sort(people);
    int boats = 0, light = 0, heavy = people.length - 1;
    while (light <= heavy) {
        if (people[light] + people[heavy] <= limit) light++;  // pair lightest with heaviest
        heavy--;    // heaviest always takes a boat (alone or paired)
        boats++;
    }
    return boats;
}
// Time: O(n log n), Space: O(1)
// Greedy: always try to pair the heaviest with the lightest
```

---

## 13 — Minimum Cost to Connect Sticks (LC 1167)

Merge sticks with minimum total cost (cost = sum of two sticks being merged).

**Key insight**: always merge the two cheapest sticks first (Huffman coding!).

```java
int connectSticks(int[] sticks) {
    PriorityQueue<Integer> minHeap = new PriorityQueue<>();
    for (int s : sticks) minHeap.offer(s);
    int totalCost = 0;
    while (minHeap.size() > 1) {
        int merged = minHeap.poll() + minHeap.poll();
        totalCost += merged;
        minHeap.offer(merged);
    }
    return totalCost;
}
// Time: O(n log n), Space: O(n)
// Same pattern as Huffman encoding
```

---

## 14 — Two City Scheduling (LC 1029)

N people fly to city A or B (different costs). Exactly N to each. Minimize total cost.

```java
int twoCitySchedCost(int[][] costs) {
    // Greedily assign: sort by "extra cost of sending to B instead of A" = cost[B] - cost[A]
    Arrays.sort(costs, (a, b) -> (a[0] - a[1]) - (b[0] - b[1]));
    // Those preferring A go to A (cheaper), rest go to B
    int total = 0, n = costs.length / 2;
    for (int i = 0; i < n; i++)     total += costs[i][0];    // first half to city A
    for (int i = n; i < 2*n; i++)   total += costs[i][1];    // second half to city B
    return total;
}
// Time: O(n log n), Space: O(1)
```

---

## 15 — Greedy Proof Framework (Exchange Argument)

To prove your greedy is correct:

```
1. Assume an optimal solution OPT differs from greedy at step k
2. Show you can swap OPT's choice at step k for greedy's choice
3. Show the modified solution is at least as good as OPT
4. By induction, greedy matches or beats OPT at every step
```

**Example for interval scheduling** (sort by end, take earliest-ending):
- OPT picks interval `A` at some step; greedy picks `B` where `B.end ≤ A.end`
- Replace `A` with `B` in OPT's solution — `B` ends no later, so it conflicts with at least as few future intervals
- Modified OPT is still valid and optimal → greedy is optimal

---

## 16 — Visual: Jump Game Greedy Reach Expansion

```
nums = [2, 3, 1, 1, 4]
       idx: 0  1  2  3  4

maxReach starts at 0.

i=0: maxReach = max(0, 0+2) = 2.  Can visit indices 0,1,2.
i=1: maxReach = max(2, 1+3) = 4.  Can visit up to index 4!
i=2: maxReach = max(4, 2+1) = 4.
i=3: maxReach = max(4, 3+1) = 4.
i=4: i == n-1 → reached end. Return true.

Key insight: at every index, ask "how far can I reach FROM HERE?"
Maintain the global farthest reachable index.
If you ever find i > maxReach, you're stuck → return false.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: You are given an array of non-negative integers `cost[]` where `cost[i]` is the cost to step on stair `i`. You can climb 1 or 2 steps at a time. Find the minimum total cost to reach the top (past the last stair). *(LC 746 Min Cost Climbing Stairs)*

**Step 1 — Read**: Input = `cost[]`, output = minimum total cost (int). You start at index 0 or 1. Goal: reach index `n` (past array).

**Step 2 — Identify**: "Minimum cost to reach the end with choices at each step" — sounds like DP. But: at each step the locally optimal choice (pay once, reach either i+1 or i+2) is well-defined. The key question for Greedy vs DP: *Does a local choice ever conflict with a future decision?* Here: paying `cost[i]` frees you to jump 1 or 2 — you don't need to undo that. But you still choose the cheaper of two predecessors, which feels like DP. This is a **DP problem** that's *often mistaken for greedy*. The greedy of "always step on the cheaper stair" fails because cheap now might trap you on expensive later.

**Step 3 — Plan** (DP flavor):
- `dp[i]` = min cost to reach stair `i`.
- `dp[i] = cost[i] + min(dp[i-1], dp[i-2])`.
- Base: `dp[0] = cost[0]`, `dp[1] = cost[1]`.
- Answer: `min(dp[n-1], dp[n-2])`.

**Step 4 — Code**:
```java
int minCostClimbingStairs(int[] cost) {
    int n = cost.length;
    int prev2 = cost[0], prev1 = cost[1];
    for (int i = 2; i < n; i++) {
        int curr = cost[i] + Math.min(prev1, prev2);
        prev2 = prev1;
        prev1 = curr;
    }
    return Math.min(prev1, prev2);   // can start from last or second-to-last
}
// Time: O(n), Space: O(1)
```

**Step 5 — Verify** on `[10, 15, 20]`:
- `dp[0]=10, dp[1]=15`.
- `dp[2]=20+min(15,10)=30`.
- Answer: `min(15, 30) = 15`. Take stair 1 → done. ✓

> **Takeaway**: When a problem looks greedy but the local choice affects future cost, use DP. When the local choice is provably never undone (activity selection, jump game "can I reach"), use greedy + exchange argument.

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Single element | Jump Game II: 0 jumps | Check `n == 1` → return 0 |
| Zero in array | Jump Game I: might get stuck | `if (i > maxReach) return false` catches it |
| All zeros except last | Must reach non-zero jump exactly | Greedy still works — max reach stops growing |
| Gas station: sum(gas) < sum(cost) | Can never complete circuit | Return -1 early if total gas < total cost |
| Negative values in input | Greedy exchange argument may break | Verify monotone property still holds before applying |
| Duplicate tasks (task scheduler) | Idle slots calculation off-by-one | `ceil((maxFreq - 1) * (n + 1) + countOfMaxFreq)` |

```java
// Jump Game I — can reach end?
boolean canJump(int[] nums) {
    int maxReach = 0;
    for (int i = 0; i < nums.length; i++) {
        if (i > maxReach) return false;          // stuck!
        maxReach = Math.max(maxReach, i + nums[i]);
    }
    return true;
}

// Gas Station — which starting point works?
int canCompleteCircuit(int[] gas, int[] cost) {
    int total = 0, tank = 0, start = 0;
    for (int i = 0; i < gas.length; i++) {
        tank += gas[i] - cost[i];
        total += gas[i] - cost[i];
        if (tank < 0) { start = i + 1; tank = 0; }  // restart from next station
    }
    return total >= 0 ? start : -1;
}
```

---

## 😵 Commonly Confused With

**vs Dynamic Programming**: DP considers all previous choices; greedy commits to the locally best without looking back. Deciding question: *Can you prove that the locally optimal choice is NEVER regretted? (Exchange argument proof)* If yes → greedy. If choices conflict with future steps → DP.

**vs Backtracking**: Backtracking explores all choices and backtracks when stuck. Greedy never backtracks. Deciding question: *Do you need to find ALL solutions or THE BEST solution without undoing choices?* All solutions → backtracking. Best with provable local optimality → greedy.

**vs BFS/Dijkstra**: For "shortest path" in a graph, BFS/Dijkstra is correct. Greedy (like "always go to the nearest unvisited node") can fail. Deciding question: *Is this a graph traversal problem, or a sequence of choices on a linear/sorted structure?*

---

## 17 — Canonical LeetCode Problems

| Flavor | Problems |
|--------|---------|
| Jump game | LC 55, LC 45 |
| Gas station / circular | LC 134 |
| Stock / profit | LC 122 (multiple tx), LC 121 (one tx → not greedy) |
| Interval scheduling | LC 435, LC 452, LC 621 |
| Assignment | LC 455, LC 881, LC 1029 |
| String partition | LC 763, LC 767 |
| Merge / Huffman | LC 1167, LC 502 |
| Two-pass greedy | LC 135 (candy), LC 42 (trap water — two passes or stack) |
