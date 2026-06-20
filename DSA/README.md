# Data Structures & Algorithms — Pattern Playbook

> FAANG PE-calibrated. Every section answers three questions: **How do I recognize this pattern?** → **Which flavor is this?** → **What are the exact solution steps?**  
> All code is **Java**. Complexity is always stated. LeetCode canonical problems are cited.

---

## Universal Problem-Solving Playbook

> Follow these 5 steps on **every** problem — new or familiar. In an interview, narrate each step aloud before touching the keyboard.

```
STEP 1 — READ (2 min)
  □ What is the INPUT?   (array / string / linked list / tree / graph / matrix / intervals)
  □ What is the OUTPUT?  (bool / int / list / tree node / void in-place)
  □ What does "optimal" mean?  (min / max / count / all solutions / any one solution)
  □ Any special constraints?   (in-place, O(1) space, no division, distinct elements, sorted)

STEP 2 — IDENTIFY (1 min)
  □ Scan the Quick Pattern Selector below
  □ Spot keyword triggers: sorted? contiguous? prefix? k-th? intervals? all combos?
  □ Brute-force it in your head → what is the naive complexity? → what could halve it?
  □ Rule out wrong patterns first, then commit to one

STEP 3 — PLAN  (3 min — say it aloud before writing code)
  □ Name the pattern: "This is a sliding window / binary search on answer / DP..."
  □ Define your state in one English sentence:
      "window = subarray [left..right] containing at most K distinct chars"
      "dp[i] = minimum cost to reach cell i"
  □ Write the loop invariant or recurrence before any code
  □ Identify base cases / empty-input return value / termination condition

STEP 4 — CODE  (10-15 min)
  □ Write helper / feasibility functions BEFORE the main loop
  □ Use a dummy head/sentinel for linked list and BFS problems
  □ Use descriptive names: left/right not i/j,  slow/fast not p/q,  dp[i] not arr[i]
  □ Mid-loop: pause and verify your invariant still holds

STEP 5 — VERIFY  (3 min)
  □ Dry-run on the given example manually (trace variables on paper)
  □ Run through the EDGE CASE CHECKLIST below
  □ State time and space complexity and why
  □ Mention one possible follow-up improvement
```

---

## Universal Edge Case Checklist

Run these for **every** problem before saying "I'm done":

```
□ Empty input          → n=0, null head, empty string "", empty matrix 0×0
□ Single element       → n=1 (does your loop even execute?)
□ All same elements    → [5,5,5,5] — does grouping/dedup logic break?
□ Already sorted       → both ascending AND descending
□ Negative numbers     → does sum/mod/product still behave? (Java % can be negative!)
□ Integer overflow     → multiply or add large values? cast to long first
□ Duplicates           → allowed? does your dedup skip too many or too few?
□ k = 0 or k = n      → boundary values of any k-based parameter
□ Target not found     → what do you return? (-1, [], false, n+1?)
□ Cycle in graph/list  → are you tracking visited[]? can you loop forever?
□ Off-by-one           → inclusive vs exclusive bounds; < vs <=; i-1 vs i
```

---

## Pattern Confusion Guide

When two patterns feel similar, use this table to decide:

| If it looks like... | But ask this question... | Answer → pick |
|--------------------|--------------------------|----|
| Sliding Window | Is the subarray **contiguous** and can I maintain it by adding/removing one element? | Yes → SW, No → Two Pointers or DP |
| Two Pointers | Is the input **sorted** and am I looking for a pair/partition? | Yes → TP, No → Hash Map |
| Binary Search | Is there a **monotone predicate** over the answer space (feasible/not)? | Yes → BS on answer, No → Linear scan |
| Dynamic Programming | Do local choices **conflict** with future choices? | Yes → DP, No → Greedy |
| Backtracking | Do I need **all** solutions, not just count/min/max? | Yes → BT, No → DP |
| BFS | Are edge **weights equal / unweighted**? | Yes → BFS, No → Dijkstra |
| Union-Find | Are edges **added incrementally** and I need connectivity? | Yes → UF, No → BFS/DFS |
| Cyclic Sort | Are values in a **known range [1..n]** and O(1) space required? | Yes → Cyclic Sort, No → HashMap |
| Prefix Sum | Can elements be **negative** (sliding window breaks on negatives)? | Yes → Prefix+HashMap, No → Sliding Window |
| Heap / Top-K | Do I need the K-th element from a **stream** (not a static sorted array)? | Yes → Heap, No → Quick Select |

---

---

## Master Pattern Index

| # | Pattern | Folder | Core Signal | Blind 75 / NeetCode |
|---|---------|--------|-------------|---------------------|
| 1 | **Hashing** | `hashing/` | Count/lookup in O(1); two-sum, anagram, consecutive | ★★★★★ |
| 2 | **Prefix Sum** | `prefix-sum/` | Range sum query; subarray sum = K | ★★★★★ |
| 3 | **Two Pointers** | `two-pointers/` | Sorted array; pair/triplet satisfying condition | ★★★★★ |
| 4 | **Sliding Window** | `sliding-window/` | Contiguous subarray/string; maximize/minimize range property | ★★★★★ |
| 5 | **Binary Search** | `binary-search/` | Sorted input OR monotone answer space | ★★★★★ |
| 6 | **Cyclic Sort** | `cyclic-sort/` | Numbers in range [1..n]; find missing/duplicate | ★★★☆☆ |
| 7 | **Linked List** | `linked-list/` | Reverse, cycle, merge, reorder pointer chains | ★★★★☆ |
| 8 | **Stack & Monotone** | `stacks/` | LIFO; nearest greater/smaller; expression evaluation | ★★★★★ |
| 9 | **Intervals** | `intervals/` | Overlapping ranges; merge, insert, scheduling | ★★★★☆ |
| 10 | **Trees** | `trees/` | Hierarchical structure; path, level, ancestor, subtree | ★★★★★ |
| 11 | **Trie** | `trie/` | Prefix lookup; word search; autocomplete | ★★★★☆ |
| 12 | **Heap / Priority Queue** | `heap-priority-queue/` | Top-K; median stream; K-way merge | ★★★★★ |
| 13 | **Backtracking** | `backtracking/` | All valid combinations/permutations; constraint satisfaction | ★★★★★ |
| 14 | **Graphs** | `graphs/` | BFS, DFS, Dijkstra, topo sort, MST, bipartite | ★★★★★ |
| 15 | **Union-Find** | `union-find/` | Dynamic connectivity; cycle detection in undirected | ★★★★☆ |
| 16 | **Dynamic Programming** | `dynamic-programming/` | Overlapping subproblems; count/min/max answer | ★★★★★ |
| 17 | **Greedy** | `greedy/` | Local optimal = global optimal; interval/jump/gas | ★★★★☆ |
| 18 | **Divide & Conquer** | `divide-and-conquer/` | Merge sort pattern; quick select; half + recurse | ★★★☆☆ |
| 19 | **Bit Manipulation** | `bit-manipulation/` | XOR tricks; bit masking; bitmask DP | ★★★★☆ |
| 20 | **Math** | `math/` | GCD, primes, modular arithmetic, combinatorics | ★★★☆☆ |
| 21 | **Matrix** | `matrix/` | 2D grid traversal; rotate; spiral; search | ★★★★☆ |
| 22 | **Segment Tree / Fenwick Tree** | `segment-tree/` | Range query + point/range update; count smaller after self | ★★★★☆ |
| 23 | **String Algorithms** | `string-algorithms/` | KMP, Z-function, Rabin-Karp, Manacher; pattern matching | ★★★★☆ |
| 24 | **Monotonic Deque** | `monotonic-deque/` | Sliding window max/min in O(n); DP optimization | ★★★★☆ |
| 25 | **Advanced DP** | `advanced-dp/` | String DP (LCS, edit distance, LIS); interval DP; digit DP; bitmask DP; knapsack variants | ★★★★★ |

---

## Quick Pattern Selector

```
Is the input a string or array?
├── Need O(1) lookup / counting?
│   └── HashMap / HashSet → Hashing
├── Range sum / prefix query?
│   └── Prefix Sum
├── Contiguous subarray/string + optimize?
│   ├── Fixed window size → Sliding Window (fixed)
│   └── Expand/shrink to satisfy condition → Sliding Window (variable)
├── Sorted array + pair/triplet?
│   └── Two Pointers (opposite ends)
├── Numbers in range [1..n], find missing/duplicate?
│   └── Cyclic Sort
└── Search in sorted array / answer space monotone?
    └── Binary Search

Is the input a linked list?
├── Reverse / reorder?           → Linked List in-place manipulation
├── Detect cycle / find middle?  → Fast-Slow Pointers
└── Merge sorted lists?          → K-way Merge with Heap

Is the input a tree?
├── Visit all nodes?             → DFS (pre/in/post) or BFS
├── Path / sum?                  → Postorder DFS
├── Level-by-level?              → BFS with queue
├── Prefix strings?              → Trie
└── BST property?                → Inorder or range-bounded recursion

Is the input a graph?
├── Shortest path (unweighted)?  → BFS
├── Shortest path (weighted)?    → Dijkstra
├── Dependencies / ordering?     → Topological Sort
├── Connected components?        → Union-Find or DFS
└── All paths?                   → DFS + Backtracking

Does the problem ask for intervals / ranges?
└── Intervals (merge, insert, overlap, schedule)

Does it ask for "how many ways" / "minimum" / "maximum"?
├── Can express as smaller version of same problem?  → DP
└── Local choice always leads to global optimum?    → Greedy

Does it need LIFO / "nearest element" / matching?
└── Stack / Monotone Stack

Does it need the MAX or MIN of every sliding window of fixed size?
└── Monotonic Deque  (O(n) vs O(nk) brute, O(n log k) heap)

Does it need k-th largest / smallest / top-K?
└── Heap / Priority Queue

Does it need RANGE QUERY + POINT/RANGE UPDATES?
├── Sum/XOR (invertible operation)?  → Fenwick Tree (BIT) — simpler
└── Min/Max or range updates?        → Segment Tree (± lazy propagation)

Is this a STRING-IN-STRING / PATTERN MATCHING problem?
├── Find first/all occurrences of pattern P in text T → KMP or Z-function
├── Palindrome structure / period / border?           → KMP failure function / Z
└── Compare many substring hashes quickly?           → Rabin-Karp rolling hash

Is the problem about bits (XOR, AND, OR)?
└── Bit Manipulation

Does it need prefix word matching or wildcard search?
└── Trie

Does the answer space have a binary structure (feasible / not feasible)?
└── Binary Search on Answer

Does it involve splitting into halves recursively?
└── Divide & Conquer

Is it a MULTI-STEP DP problem on strings or ranges?
├── Two strings → LCS / Edit Distance / Distinct Subsequences?  → String DP
├── Count integers in [1..N] with digit property?               → Digit DP
├── Split a range [i..j] optimally (burst balloons, matrix chain)? → Interval DP
└── Small set (n ≤ 20), visited subset as state?               → Bitmask DP
```

---

## Complexity Quick Reference

| Pattern | Time | Space |
|---------|------|-------|
| Hashing | O(n) average | O(n) |
| Prefix Sum | O(n) build, O(1) query | O(n) |
| Two Pointers | O(n) | O(1) |
| Sliding Window | O(n) | O(k) where k = window/alphabet |
| Binary Search | O(log n) | O(1) |
| Cyclic Sort | O(n) | O(1) |
| Linked List ops | O(n) | O(1) in-place |
| Stack / Monotone | O(n) amortized | O(n) |
| Intervals | O(n log n) | O(n) |
| Tree DFS/BFS | O(n) | O(h) / O(n) |
| Trie insert/search | O(L) per op | O(alphabet × n × L) |
| Heap Top-K | O(n log k) | O(k) |
| Backtracking | O(2ⁿ) worst | O(n) recursion stack |
| Graph BFS/DFS | O(V + E) | O(V) |
| Union-Find | O(α(n)) per op | O(n) |
| DP (1D) | O(n) | O(n) → O(1) optimized |
| DP (2D) | O(n × m) | O(n × m) → O(m) optimized |
| Greedy | O(n log n) typical | O(1) or O(n) |
| Divide & Conquer | O(n log n) typical | O(log n) stack |
| Bit Manipulation | O(1) or O(n) | O(1) |
| Fenwick Tree (BIT) | O(log n) update+query | O(n) |
| Segment Tree | O(n) build, O(log n) update+query | O(4n) |
| KMP / Z-function | O(n+m) | O(m) or O(n+m) |
| Rabin-Karp | O(n+m) average | O(1) rolling |
| Manacher (palindromes) | O(n) | O(n) |
| Monotonic Deque | O(n) | O(k) |
| LCS / Edit Distance | O(n × m) | O(n × m) → O(m) |
| LIS | O(n²) or O(n log n) | O(n) |
| Interval DP | O(n³) | O(n²) |
| Bitmask DP | O(n × 2ⁿ) | O(2ⁿ) |
| 0/1 Knapsack | O(n × W) | O(W) |

---

## Folder Map

```
DSA/
├── README.md                       ← this file — master index + selector
│
├── hashing/                        ← HashMap/HashSet; frequency; two-sum; anagram
├── prefix-sum/                     ← 1D/2D prefix; subarray sum = K; range queries
├── two-pointers/                   ← opposite-ends; same-direction; fast-slow
├── sliding-window/                 ← fixed; variable; anagram; monotone deque
├── binary-search/                  ← classic; rotated; search on answer space
├── cyclic-sort/                    ← missing number; duplicates; first missing positive
├── linked-list/                    ← reverse; merge; cycle; LRU cache
├── stacks/                         ← bracket match; monotone; expression; min-stack
├── intervals/                      ← merge; insert; meeting rooms; min heap schedule
├── trees/                          ← traversals; path sum; LCA; BST; construction
├── trie/                           ← insert/search; wildcard; replace words; XOR trie
├── heap-priority-queue/            ← Top-K; two-heap median; K-way merge; Dijkstra
├── backtracking/                   ← subsets; permutations; N-Queens; Sudoku
├── graphs/                         ← BFS; DFS; Dijkstra; topo; MST; bipartite
├── union-find/                     ← path compression; rank; connected components
├── dynamic-programming/            ← 1D; 2D; interval; knapsack; state machine
├── greedy/                         ← intervals; jump; gas station; activity selection
├── divide-and-conquer/             ← merge sort; quick select; closest pair
├── bit-manipulation/               ← XOR; masks; bitmask DP; counting bits
├── math/                           ← GCD; sieve; modular; combinatorics
├── matrix/                         ← BFS flood fill; spiral; rotate; search 2D
├── segment-tree/                   ← Fenwick BIT; Segment Tree; lazy propagation; coord compress
├── string-algorithms/              ← KMP; Z-function; Rabin-Karp; Manacher; period/border
├── monotonic-deque/                ← Sliding window max/min; DP deque optimization
└── advanced-dp/                    ← LCS; Edit Distance; LIS; Interval DP; Digit DP; Bitmask DP; Knapsack variants
```

---

## System Design DS Crossover

| DS / Algorithm | Where it appears in production |
|---------------|-------------------------------|
| Consistent Hashing | Distributed cache sharding (Redis, Memcached) |
| Bloom Filter | Cassandra SSTable, CDN cache miss, Akamai |
| Skip List | Redis sorted sets (ZADD/ZRANGE internals) |
| LSM Tree | RocksDB, Cassandra, LevelDB write path |
| B+ Tree | MySQL InnoDB, PostgreSQL index pages |
| Trie | Typeahead/autocomplete; IP routing tables |
| Min-Heap | Top-K items; priority queue in job schedulers |
| HyperLogLog | Redis `PFCOUNT`; approximate unique user count |
| Segment Tree | Range update queries in analytics engines |
| Union-Find | Network connectivity; Kruskal MST; Percolation |
| Consistent Hashing | Ring-based sharding in DynamoDB |

See `system-design-ds/` for production deep-dives on each.

---

Use `/dsa [problem]` for Claude-guided walkthroughs with system design connections.
