# Two Pointers

> Use two index variables that move through the input — converging, diverging, or chasing each other — to reduce O(n²) brute force to O(n).

---

## 1 — How to Recognize This Pattern

Ask yourself ALL of these:
- [ ] Input is an **array, string, or linked list**
- [ ] You need to find **a pair, triplet, or partition** satisfying a condition
- [ ] The input is **sorted** (or can be sorted without violating constraints)
- [ ] Brute force is O(n²) nested loops — two pointers should cut it to O(n) or O(n log n)

**Trigger phrases**: "two sum sorted", "three sum", "container with most water", "valid palindrome", "remove duplicates", "partition array", "find cycle", "middle of linked list", "trapping rain water"

**Anti-pattern**: input is unsorted and sorting would change indices needed for the answer → use HashMap instead.

---

## 2 — Flavor Detection

| Flavor | Signal | Pointer Movement |
|--------|--------|-----------------|
| **Opposite ends** | Sorted array, find pair with target sum | `left = 0`, `right = n-1`, converge inward |
| **Same direction** | Remove duplicates, in-place filter | `slow` = write head, `fast` = scanner |
| **Fast-Slow (Floyd's)** | Detect cycle, find middle of list | `slow += 1`, `fast += 2` |
| **3-sum / k-sum** | Find k numbers summing to target | Outer loop fixes one; inner uses opposite-end two pointers |
| **Partition** | Dutch National Flag, quicksort pivot | `low` / `mid` / `high` swap positions |
| **Merge from both ends** | Squares of sorted array | Read from both ends into result from back |

---

## 3 — Opposite-Ends (Convergence) Solution Steps

**Problem shape**: Sorted array, find pair whose combination meets a target.

```
Step 1: Sort if needed
Step 2: left = 0, right = n - 1
Step 3: While left < right:
        a. Compute value = f(arr[left], arr[right])
        b. If value == target  → record, advance both pointers
        c. If value < target   → left++   (need larger value)
        d. If value > target   → right--  (need smaller value)
Step 4: Skip duplicates after recording to avoid duplicate answers
```

**Two sum sorted (LC 167)**:
```java
int[] twoSum(int[] numbers, int target) {
    int left = 0, right = numbers.length - 1;
    while (left < right) {
        int sum = numbers[left] + numbers[right];
        if (sum == target)      return new int[]{left + 1, right + 1};
        else if (sum < target)  left++;
        else                    right--;
    }
    return new int[]{};
}
```

**3-sum (LC 15) — with duplicate skipping**:
```java
List<List<Integer>> threeSum(int[] nums) {
    Arrays.sort(nums);
    List<List<Integer>> res = new ArrayList<>();

    for (int i = 0; i < nums.length - 2; i++) {
        if (i > 0 && nums[i] == nums[i - 1]) continue;   // skip outer dup

        int left = i + 1, right = nums.length - 1;
        while (left < right) {
            int sum = nums[i] + nums[left] + nums[right];
            if (sum == 0) {
                res.add(Arrays.asList(nums[i], nums[left], nums[right]));
                while (left < right && nums[left] == nums[left + 1]) left++;   // skip inner dup
                while (left < right && nums[right] == nums[right - 1]) right--;
                left++; right--;
            } else if (sum < 0) left++;
            else right--;
        }
    }
    return res;
}
```

**Container with most water (LC 11)**:
```java
int maxArea(int[] height) {
    int left = 0, right = height.length - 1, best = 0;
    while (left < right) {
        int area = Math.min(height[left], height[right]) * (right - left);
        best = Math.max(best, area);
        if (height[left] <= height[right]) left++;   // advance shorter side
        else right--;
    }
    return best;
}
```

---

## 4 — Same-Direction (Slow-Fast Read/Write) Solution Steps

**Problem shape**: In-place modification — remove elements, deduplicate, partition.

```
Step 1: slow = 0   (write pointer — next valid slot)
Step 2: For fast = 0 to n-1:
        a. If arr[fast] passes the keep-condition:
              arr[slow] = arr[fast]
              slow++
Step 3: Return slow (= new logical length)
```

**Remove duplicates from sorted array (LC 26)**:
```java
int removeDuplicates(int[] nums) {
    int slow = 0;
    for (int fast = 0; fast < nums.length; fast++) {
        if (slow == 0 || nums[fast] != nums[slow - 1]) {
            nums[slow++] = nums[fast];
        }
    }
    return slow;
}
```

**Allow at most K duplicates (LC 80, k=2)**:
```java
int removeDuplicatesII(int[] nums) {
    int slow = 0;
    for (int num : nums) {
        if (slow < 2 || nums[slow - 2] != num) {  // generalises to any k
            nums[slow++] = num;
        }
    }
    return slow;
}
```

**Move zeroes (LC 283)**:
```java
void moveZeroes(int[] nums) {
    int slow = 0;
    for (int fast = 0; fast < nums.length; fast++) {
        if (nums[fast] != 0) nums[slow++] = nums[fast];
    }
    while (slow < nums.length) nums[slow++] = 0;
}
```

**Squares of sorted array — merge from both ends (LC 977)**:
```java
int[] sortedSquares(int[] nums) {
    int n = nums.length;
    int[] res = new int[n];
    int left = 0, right = n - 1, pos = n - 1;
    while (left <= right) {
        int l2 = nums[left] * nums[left], r2 = nums[right] * nums[right];
        if (l2 > r2) { res[pos--] = l2; left++; }
        else          { res[pos--] = r2; right--; }
    }
    return res;
}
```

---

## 5 — Fast-Slow Pointers (Floyd's Cycle Detection)

**Problem shape**: Linked list — detect cycle, find cycle entry, find middle.

```
Find middle:
  slow = fast = head
  while (fast != null && fast.next != null):
      slow = slow.next; fast = fast.next.next
  // slow is at the middle

Detect cycle:
  slow = fast = head
  while (fast != null && fast.next != null):
      slow = slow.next; fast = fast.next.next
      if (slow == fast) → cycle exists

Find cycle start (after slow == fast inside cycle):
  slow = head
  while (slow != fast): slow = slow.next; fast = fast.next
  return slow   // cycle entry point
```

**Java implementation (LC 142)**:
```java
ListNode detectCycle(ListNode head) {
    ListNode slow = head, fast = head;

    // Phase 1: detect meeting point
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
        if (slow == fast) {
            // Phase 2: find cycle start
            slow = head;
            while (slow != fast) {
                slow = slow.next;
                fast = fast.next;
            }
            return slow;
        }
    }
    return null;  // no cycle
}
```

**Find duplicate number — array as linked list (LC 287)**:
```java
// Value at index i acts as "next pointer" → cycle detection finds the duplicate
int findDuplicate(int[] nums) {
    int slow = nums[0], fast = nums[0];
    do {
        slow = nums[slow];
        fast = nums[nums[fast]];
    } while (slow != fast);

    slow = nums[0];
    while (slow != fast) { slow = nums[slow]; fast = nums[fast]; }
    return slow;
}
```

**Canonical problems**: LC 141 (cycle detect), LC 142 (cycle entry), LC 287 (find duplicate), LC 876 (middle of list), LC 143 (reorder list = find middle + reverse + merge).

---

## 6 — Dutch National Flag (3-Way Partition)

**Problem shape**: Rearrange array in-place into exactly 3 groups without extra space.

```
low = 0, mid = 0, high = n - 1

While mid <= high:
  if arr[mid] == 0: swap(low, mid); low++; mid++
  if arr[mid] == 1: mid++
  if arr[mid] == 2: swap(mid, high); high--   // do NOT increment mid
```

**Java (LC 75 — Sort Colors)**:
```java
void sortColors(int[] nums) {
    int low = 0, mid = 0, high = nums.length - 1;
    while (mid <= high) {
        if (nums[mid] == 0) {
            int tmp = nums[low]; nums[low] = nums[mid]; nums[mid] = tmp;
            low++; mid++;
        } else if (nums[mid] == 1) {
            mid++;
        } else {
            int tmp = nums[mid]; nums[mid] = nums[high]; nums[high] = tmp;
            high--;                // don't advance mid — newly swapped element is unchecked
        }
    }
}
```

---

## 7 — Trapping Rain Water (Two-Pointer O(1) Space)

Each bar traps `min(maxLeft, maxRight) - height[i]`. Two pointers let you determine which bound is limiting without precomputing prefix arrays.

```java
// LC 42
int trap(int[] height) {
    int left = 0, right = height.length - 1;
    int maxLeft = 0, maxRight = 0, water = 0;

    while (left < right) {
        if (height[left] <= height[right]) {
            if (height[left] >= maxLeft) maxLeft = height[left];
            else water += maxLeft - height[left];
            left++;
        } else {
            if (height[right] >= maxRight) maxRight = height[right];
            else water += maxRight - height[right];
            right--;
        }
    }
    return water;
}
```

**Why it works**: The shorter side's water is fully determined by its own running max — the taller side can only be ≥ what we've seen.

---

## 8 — Complexity Reference

| Flavor | Time | Space |
|--------|------|-------|
| Opposite ends | O(n) after O(n log n) sort | O(1) |
| 3-sum | O(n²) | O(1) |
| Same direction (in-place) | O(n) | O(1) |
| Fast-slow (cycle) | O(n) | O(1) |
| Dutch National Flag | O(n) | O(1) |
| Trapping rain water | O(n) | O(1) |

---

## 9 — FAANG Interview Moves

1. **Sort first then state the invariant**: "After sorting, left is the smallest candidate and right is the largest. I advance whichever side's contribution needs to grow."
2. **Duplicate skipping is a mandatory mention** in 3-sum/4-sum — interviewers always probe for it.
3. **Floyd's cycle = two-pointer with implicit graph**: For "find duplicate in array with values 1..n", interpret values as next-pointers and run cycle detection.
4. **Rain water two variants**: Mention O(n) space prefix-array approach first if pressed, then upgrade to O(1) two-pointer version.
5. **Dutch National Flag invariant**: After processing, `[0..low-1]` = 0s, `[low..mid-1]` = 1s, `[high+1..n-1]` = 2s. State this invariant explicitly.

---

## 10 — Visual: How Two Pointers Move

**Opposite-ends convergence** on sorted array `[-3, -1, 2, 4, 6]`, target = 5:
```
[-3, -1,  2,  4,  6]   target = 5
  L                R    sum = -3+6 = 3 < 5  → move L right
      L            R    sum = -1+6 = 5 = 5  → FOUND! return [1,4]

Rule: sum too small → LEFT moves right (need bigger left)
      sum too big  → RIGHT moves left (need smaller right)
      They always converge — never skip a valid pair
```

**Fast-slow on linked list** — detecting middle/cycle:
```
List: 1 → 2 → 3 → 4 → 5 → null

Start: slow=1, fast=1
Step1: slow=2, fast=3
Step2: slow=3, fast=5
Step3: fast.next=null → stop.  slow=3 = MIDDLE ✓

For cycle detection: fast catches slow from behind inside the cycle.
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a sorted array, remove all duplicates in-place and return the new length. Do not allocate extra space. *(Same-direction / slow-fast variant.)*

**Step 1 — Read**: Input = sorted int[], output = int (new length), in-place required, O(1) space.

**Step 2 — Identify**: "in-place filter on sorted array" → same-direction two pointers. `slow` = write head (next position to place a unique value), `fast` = scanner. Brute force would require O(n) extra array; two pointers do it O(1).

**Step 3 — Plan**:
- `slow` points to the last written unique value.
- `fast` scans forward.
- Invariant: `nums[0..slow]` always holds the deduplicated result so far.
- When `nums[fast] != nums[slow]`, write it at `slow+1` and advance `slow`.

**Step 4 — Code**:
```java
int removeDuplicates(int[] nums) {
    if (nums.length == 0) return 0;
    int slow = 0;
    for (int fast = 1; fast < nums.length; fast++) {
        if (nums[fast] != nums[slow]) {   // new unique value found
            slow++;
            nums[slow] = nums[fast];       // write it
        }
        // if equal, fast keeps advancing — slow stays (overwriting with same value later)
    }
    return slow + 1;   // length = index + 1
}
// Time: O(n), Space: O(1)
```

**Step 5 — Verify** on `[1,1,2,3,3]`:
- fast=1: nums[1]=1 == nums[0]=1 → skip
- fast=2: nums[2]=2 != nums[0]=1 → slow=1, nums[1]=2. Array: [1,2,2,3,3]
- fast=3: nums[3]=3 != nums[1]=2 → slow=2, nums[2]=3. Array: [1,2,3,3,3]
- fast=4: nums[4]=3 == nums[2]=3 → skip
- Return slow+1 = 3 ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty array `[]` | `nums[0]` crashes | `if (nums.length == 0) return 0;` before loop |
| Single element | Loop doesn't run | Works — returns 1 naturally |
| All duplicates `[5,5,5]` | slow stays 0 | Correct — returns 1 (one unique element) |
| All unique `[1,2,3]` | Every step advances slow | Correct — returns n |
| Unsorted input | Opposite-ends won't work | MUST sort first for opposite-ends; same-direction works on unsorted for some problems |
| Overflow `a + b` | `Integer.MAX_VALUE + 1` wraps negative | Cast: `(long)a + b`, or rearrange condition |

```java
// Skip duplicates after recording a match (3-sum dedup pattern):
while (left < right && nums[left]  == nums[left  + 1]) left++;
while (left < right && nums[right] == nums[right - 1]) right--;
// Do this AFTER adding the triplet, BEFORE the next left++/right--

// Overflow-safe sum comparison:
long sum = (long) nums[left] + nums[right];   // safe before comparing to target
```

---

## 😵 Commonly Confused With

**vs Sliding Window**: Both use left/right pointers. Deciding question: *Are you maintaining a contiguous subarray (with aggregation/count), or finding two specific elements that combine to meet a condition?* Contiguous aggregate → Sliding Window. Pair combination → Two Pointers.

**vs Binary Search**: Both work on sorted arrays. Deciding question: *Do you need to find a single target efficiently (O(log n)), or traverse the entire array pairing up elements (O(n))?* Single-target lookup → Binary Search. Full pass pairing → Two Pointers.

**vs HashMap (Two Sum)**: Two Pointers requires the array to be sorted. If you can't sort (need original indices), or the array is unsorted and sorting breaks the answer, use a HashMap instead.
