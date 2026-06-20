# Cyclic Sort

> When array elements are in the range [1..n] (or [0..n]), each element has a "correct" index it belongs to. Cyclically sort by swapping each element to its correct index in a single O(n) pass — then scan for violations to find missing/duplicate numbers.

---

## 1 — How to Recognize This Pattern

Ask yourself ALL of these:
- [ ] Input array has integers in a **known range** (typically [1..n] or [0..n])?
- [ ] Problem asks to find **missing**, **duplicate**, or **misplaced** numbers?
- [ ] O(1) space (no additional array) is required?

**Trigger phrases**: "missing number", "find all duplicates", "find all missing numbers", "first missing positive", "set mismatch", "find duplicate"

**Anti-pattern**: elements are NOT in a known integer range → use HashMap or sorting instead.

---

## 2 — Core Template

For arrays in range **[1..n]**: element `nums[i]` belongs at index `nums[i] - 1`.

```java
void cyclicSort(int[] nums) {
    int i = 0;
    while (i < nums.length) {
        int correctIdx = nums[i] - 1;             // where nums[i] should go
        if (nums[i] != nums[correctIdx]) {         // not in its correct place
            swap(nums, i, correctIdx);             // put it there
        } else {
            i++;                                   // already correct, move forward
        }
    }
}

void swap(int[] nums, int a, int b) {
    int tmp = nums[a]; nums[a] = nums[b]; nums[b] = tmp;
}
// Time: O(n) — each element is placed at most once, each swap reduces misplacements by 1
// Space: O(1)
```

**Why O(n)?** Each swap places at least one element correctly. At most n swaps occur total. The outer `while` loop body runs O(n) times in total.

---

## 3 — Missing Number in [1..n] (LC 268 variant / LC 448)

### Find All Missing Numbers (LC 448)

Array of length n with values in [1..n]. Some numbers appear twice, others are missing. Find all missing numbers.

```java
List<Integer> findDisappearedNumbers(int[] nums) {
    // Step 1: cyclic sort — place each number at its correct index
    int i = 0;
    while (i < nums.length) {
        int correct = nums[i] - 1;
        if (nums[i] != nums[correct]) swap(nums, i, correct);
        else i++;
    }

    // Step 2: scan — indices where nums[i] != i+1 are missing
    List<Integer> missing = new ArrayList<>();
    for (int j = 0; j < nums.length; j++)
        if (nums[j] != j + 1) missing.add(j + 1);

    return missing;
}
// Time: O(n), Space: O(1) extra
```

---

## 4 — Find All Duplicates (LC 442)

Array of length n with values in [1..n]. Each element appears once or twice. Find all duplicates.

```java
List<Integer> findDuplicates(int[] nums) {
    // Step 1: cyclic sort (skip if nums[i] == nums[correct] — that's a duplicate)
    int i = 0;
    while (i < nums.length) {
        int correct = nums[i] - 1;
        if (nums[i] != nums[correct]) swap(nums, i, correct);
        else i++;
    }

    // Step 2: scan — nums[i] != i+1 means nums[i] is the duplicate at position i
    List<Integer> duplicates = new ArrayList<>();
    for (int j = 0; j < nums.length; j++)
        if (nums[j] != j + 1) duplicates.add(nums[j]);

    return duplicates;
}
// Time: O(n), Space: O(1) extra
```

**Key distinction from missing numbers**: at index `j` where `nums[j] != j+1`, the value `nums[j]` is a duplicate (because the element that belongs at j was already in its place).

---

## 5 — Find the Duplicate Number (LC 287)

Array of n+1 numbers in [1..n], exactly one duplicate. Find it **without modifying array** and in O(1) space.

**Approach 1: Cyclic Sort (modifies array)**:
```java
int findDuplicateCyclicSort(int[] nums) {
    int i = 0;
    while (i < nums.length) {
        if (nums[i] != i) {
            int correct = nums[i];
            if (nums[correct] == nums[i]) return nums[i];   // duplicate found
            swap(nums, i, correct);
        } else { i++; }
    }
    return -1;
}
```

**Approach 2: Floyd's Cycle Detection (O(1) space, doesn't modify array)**:
```java
int findDuplicate(int[] nums) {
    // Treat array as a linked list: index → nums[index] → next node
    // Duplicate means two indices point to same "next" → cycle exists
    int slow = nums[0], fast = nums[0];

    // Phase 1: find intersection inside the cycle
    do {
        slow = nums[slow];
        fast = nums[nums[fast]];
    } while (slow != fast);

    // Phase 2: find cycle entry (= duplicate number)
    slow = nums[0];
    while (slow != fast) {
        slow = nums[slow];
        fast = nums[fast];
    }
    return slow;
}
// Time: O(n), Space: O(1), array not modified
```

---

## 6 — Set Mismatch (LC 645)

One number is duplicated, one is missing. Find both.

```java
int[] findErrorNums(int[] nums) {
    // Cyclic sort
    int i = 0;
    while (i < nums.length) {
        int correct = nums[i] - 1;
        if (nums[i] != nums[correct]) swap(nums, i, correct);
        else i++;
    }

    // Find the wrong position: nums[i] != i+1
    for (int j = 0; j < nums.length; j++)
        if (nums[j] != j + 1) return new int[]{nums[j], j + 1};
        //                                     ^duplicate  ^missing

    return new int[]{-1, -1};
}
// Time: O(n), Space: O(1)
```

---

## 7 — First Missing Positive (LC 41) — Hard

Find the smallest missing positive integer in O(n) time, O(1) space. Values can be negative, zero, or > n.

**Key insight**: only care about values in [1..n] (anything outside this range can't be the answer when array has n elements).

```java
int firstMissingPositive(int[] nums) {
    int n = nums.length;

    // Cyclic sort variant: ignore negatives and values > n
    int i = 0;
    while (i < n) {
        int correct = nums[i] - 1;
        if (nums[i] > 0 && nums[i] <= n && nums[i] != nums[correct]) {
            swap(nums, i, correct);
        } else {
            i++;
        }
    }

    // First index where nums[i] != i+1 → i+1 is the missing positive
    for (int j = 0; j < n; j++)
        if (nums[j] != j + 1) return j + 1;

    return n + 1;   // all [1..n] present → answer is n+1
}
// Time: O(n), Space: O(1)
```

**Why does this work?** After sorting: if all numbers 1..n are present, `nums[i] == i+1` for all i. The first violation is the first missing positive.

---

## 8 — Find the Corrupt Pair (Missing + Duplicate)

Alternative to LC 645 using XOR:

```java
int[] findMissingAndDuplicate(int[] nums) {
    // XOR all indices and values
    int xorAll = 0;
    for (int i = 1; i <= nums.length; i++) xorAll ^= i;
    for (int num : nums) xorAll ^= num;
    // xorAll = missing ^ duplicate

    // Find a set bit (they differ here)
    int diffBit = xorAll & (-xorAll);
    int a = 0, b = 0;
    for (int num : nums) {
        if ((num & diffBit) != 0) a ^= num; else b ^= num;
    }
    for (int i = 1; i <= nums.length; i++) {
        if ((i & diffBit) != 0) a ^= i; else b ^= i;
    }

    // Determine which of a,b is missing vs duplicate
    for (int num : nums) if (num == a) return new int[]{a, b}; // a is duplicate
    return new int[]{b, a};
}
```

---

## 9 — Decision: Cyclic Sort vs. Other Approaches

| Constraint | Use |
|-----------|-----|
| Range [1..n], can modify array, O(n) time O(1) space | **Cyclic Sort** |
| Range [0..n] (includes 0) | Adjust: `correct = nums[i]` (0-indexed correct position) |
| Cannot modify array, O(1) space | **Floyd's Cycle Detection** |
| N+1 elements in [1..N], just find duplicate | Floyd's Cycle |
| Small n, O(n log n) acceptable | Sort then scan |
| Any range | HashMap (O(n) time + O(n) space) |

---

## 10 — Visual: Cyclic Sort Swap Sequence

```
Array: [3, 1, 5, 4, 2]  (values in range [1..5])
Correct position for value v = index v-1.

i=0: nums[0]=3. Correct pos=2. nums[2]=5≠3. Swap nums[0]↔nums[2].
  → [5, 1, 3, 4, 2]

i=0: nums[0]=5. Correct pos=4. nums[4]=2≠5. Swap nums[0]↔nums[4].
  → [2, 1, 3, 4, 5]

i=0: nums[0]=2. Correct pos=1. nums[1]=1≠2. Swap nums[0]↔nums[1].
  → [1, 2, 3, 4, 5]

i=0: nums[0]=1. Correct pos=0. Already placed! Move i++.
i=1: nums[1]=2. Correct pos=1. Already placed! Move i++.
... all placed. Array sorted!

Rule: while nums[i] is NOT at its correct position → swap it to its correct position.
      When nums[i] IS correct (or it's a duplicate) → advance i.
O(n) time because each swap places one element permanently. Total swaps ≤ n.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an array of n integers where each integer is in the range [1, n] and some numbers appear TWICE, find ALL duplicates. *(LC 442 — Find All Duplicates in an Array)*

**Step 1 — Read**: Input = `int[]` of length n, each value ∈ [1,n], each appears 1 or 2 times. Output = list of all values appearing twice.

**Step 2 — Identify**: Values in range [1..n] → **Cyclic Sort**. After sorting cyclically, any index where `nums[i] != i+1` has a duplicate (the correct value for that spot appears elsewhere, and the duplicate is sitting here).

**Step 3 — Plan**:
- Phase 1 (cyclic sort): for each `i`, while `nums[i] != nums[nums[i]-1]` → swap `nums[i]` with `nums[nums[i]-1]`.
  - Stop condition `nums[i] == nums[nums[i]-1]` catches duplicates (can't place a duplicate at its "correct" spot since the original is already there).
- Phase 2 (find duplicates): scan array; anywhere `nums[i] != i+1` → `nums[i]` is a duplicate.

**Step 4 — Code**:
```java
List<Integer> findDuplicates(int[] nums) {
    int i = 0;
    while (i < nums.length) {
        int j = nums[i] - 1;                // correct index for nums[i]
        if (nums[i] != nums[j]) {           // avoid infinite loop on duplicates
            int tmp = nums[i]; nums[i] = nums[j]; nums[j] = tmp;
        } else {
            i++;                            // already placed or duplicate — move on
        }
    }

    List<Integer> result = new ArrayList<>();
    for (int k = 0; k < nums.length; k++)
        if (nums[k] != k + 1) result.add(nums[k]);   // nums[k] is a duplicate

    return result;
}
// Time: O(n), Space: O(1) — output list doesn't count
```

**Step 5 — Verify** on `[4,3,2,7,8,2,3,1]` (range [1..8]):
- After cyclic sort: duplicates (2 and 3 each appear twice) → after sort, some positions have wrong values.
- Positions where `nums[k] != k+1` give the duplicates: 2 and 3. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Range [0..n-1] instead of [1..n] | `j = nums[i] - 1` is off-by-one | Use `j = nums[i]` (correct index = value directly) |
| Duplicate present | `nums[i] == nums[nums[i]-1]` → infinite loop | Check `nums[i] != nums[j]` before swapping (stop condition) |
| Find missing + duplicate | Two-pass: cyclic sort then check mismatched index | Phase 1: sort. Phase 2: `nums[i] != i+1` → i+1 is missing, nums[i] is duplicate |
| Values start at 0 in range [0..n-1] | Index calculation shifts | Adjust: `j = nums[i]` instead of `nums[i]-1` |
| Multiple missing numbers | Same approach: after sort, all positions with wrong value → the index+1 is a missing number | Collect all `i+1` where `nums[i] != i+1` |

```java
// Find the ONE missing number (LC 268 — range [0..n]):
// Option A: Cyclic sort then scan
// Option B: Math — expected sum = n*(n+1)/2, subtract actual sum
int missingNumber(int[] nums) {
    int n = nums.length;
    int expected = n * (n + 1) / 2;
    int actual = 0;
    for (int num : nums) actual += num;
    return expected - actual;
}

// When to use cyclic sort vs math:
// Math: find ONE missing/duplicate — simpler, O(n) time O(1) space
// Cyclic sort: find ALL missing/duplicates — O(n) time O(1) space, handles multiple
// XOR: find ONE missing/duplicate — O(n) time O(1) space, elegant
```

---

## 😵 Commonly Confused With

**vs HashMap/HashSet counting**: You can find missing/duplicate numbers using a HashMap in O(n) time but O(n) space. Cyclic sort does it in O(1) space. Deciding question: *Does the problem specifically ask for O(1) space, or can you spot the range [1..n] constraint? → Cyclic sort beats HashMap on space.*

**vs Sorting (Arrays.sort)**: Standard sort is O(n log n). Cyclic sort is O(n) for the specific case of range [1..n]. Deciding question: *Are values exactly in range [1..n] (or [0..n-1])? → Cyclic sort. Arbitrary values → Arrays.sort.*

**vs Binary Search on sorted array**: After cyclic sort, you could binary search. But you can find the answer in a single O(n) scan. Deciding question: *Does the array have the [1..n] range property? → Cyclic sort + linear scan beats binary search.*

---

## 11 — Canonical LeetCode Problems

| Problem | Approach |
|---------|---------|
| LC 268 — Missing Number | XOR or sum formula (range 0..n) |
| LC 287 — Find Duplicate (no modify) | Floyd's cycle detection |
| LC 442 — Find All Duplicates | Cyclic sort |
| LC 448 — Find All Disappeared Numbers | Cyclic sort |
| LC 645 — Set Mismatch | Cyclic sort |
| LC 41 — First Missing Positive | Cyclic sort variant |
| LC 765 — Couples Holding Hands | Greedy / Union-Find |
