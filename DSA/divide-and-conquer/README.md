# Divide and Conquer

> Split the problem into independent subproblems, solve each recursively, then combine results. The hallmark: subproblems are of the **same type** as the original and are **independent** (unlike DP where subproblems overlap).

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Can the problem be solved by **splitting the input in half** and recursing?
- [ ] Are the subproblems **independent** (no shared state)?
- [ ] Is there a **merge step** that combines two half-results into a full result?
- [ ] Does the structure resemble a **tournament** or **tree**?

**Trigger phrases**: "sort array", "merge sort", "find k-th largest", "count inversions", "maximum subarray", "closest pair of points", "expression evaluation", "different ways to add parentheses"

**Master Theorem** (runtime analysis):
```
T(n) = a·T(n/b) + O(n^d)
  a = subproblems, b = split factor, d = merge cost exponent
  If d > log_b(a): O(n^d)
  If d == log_b(a): O(n^d log n)
  If d < log_b(a): O(n^log_b(a))

Merge Sort: a=2, b=2, d=1 → d == log_2(2) → O(n log n)
Binary Search: a=1, b=2, d=0 → d > log_2(1)=0 → O(n^0) = O(1)... wrong frame; T(n)=T(n/2)+O(1) → O(log n)
```

---

## 2 — Merge Sort (Count Inversions)

```java
// Standard merge sort
void mergeSort(int[] arr, int left, int right) {
    if (left >= right) return;
    int mid = left + (right - left) / 2;
    mergeSort(arr, left, mid);
    mergeSort(arr, mid+1, right);
    merge(arr, left, mid, right);
}

void merge(int[] arr, int left, int mid, int right) {
    int[] tmp = Arrays.copyOfRange(arr, left, right+1);
    int i = 0, j = mid - left + 1, k = left;
    while (i <= mid-left && j <= right-left)
        arr[k++] = tmp[i] <= tmp[j] ? tmp[i++] : tmp[j++];
    while (i <= mid-left)  arr[k++] = tmp[i++];
    while (j <= right-left) arr[k++] = tmp[j++];
}
// Time: O(n log n), Space: O(n)
```

**Count Inversions** (pairs where i < j but arr[i] > arr[j]):

```java
int mergeCount(int[] arr, int left, int right) {
    if (left >= right) return 0;
    int mid = left + (right - left) / 2;
    int count = mergeCount(arr, left, mid) + mergeCount(arr, mid+1, right);

    // Count cross-inversions during merge
    int i = left, j = mid+1;
    List<Integer> tmp = new ArrayList<>();
    while (i <= mid && j <= right) {
        if (arr[i] <= arr[j]) {
            tmp.add(arr[i++]);
        } else {
            count += mid - i + 1;   // all remaining left elements > arr[j]
            tmp.add(arr[j++]);
        }
    }
    while (i <= mid)  tmp.add(arr[i++]);
    while (j <= right) tmp.add(arr[j++]);
    for (int k = left; k <= right; k++) arr[k] = tmp.get(k-left);

    return count;
}
// Time: O(n log n), Space: O(n)
```

---

## 3 — Quick Select — K-th Largest Element (LC 215)

Find k-th largest in **average O(n)** using Lomuto/Hoare partition. Worst case O(n²) with bad pivots.

```java
int findKthLargest(int[] nums, int k) {
    int target = nums.length - k;   // k-th largest = (n-k)-th smallest (0-indexed)
    return quickSelect(nums, 0, nums.length-1, target);
}

int quickSelect(int[] nums, int left, int right, int target) {
    int pivot = partition(nums, left, right);
    if      (pivot == target) return nums[pivot];
    else if (pivot < target)  return quickSelect(nums, pivot+1, right, target);
    else                      return quickSelect(nums, left, pivot-1, target);
}

int partition(int[] nums, int left, int right) {
    int pivot = nums[right];
    int i = left;
    for (int j = left; j < right; j++) {
        if (nums[j] <= pivot) swap(nums, i++, j);
    }
    swap(nums, i, right);
    return i;
}

void swap(int[] nums, int a, int b) { int t = nums[a]; nums[a] = nums[b]; nums[b] = t; }
// Average: O(n), Worst: O(n²), Space: O(log n) recursion
// Use heap (O(n log k)) for guaranteed O(n log k) or introselect for guaranteed O(n)
```

---

## 4 — Maximum Subarray (Kadane's vs. D&C)

**Kadane's** (greedy, O(n)) is usually preferred. D&C gives O(n log n) but demonstrates the pattern.

```java
// D&C approach (O(n log n))
int maxSubArray(int[] nums, int left, int right) {
    if (left == right) return nums[left];
    int mid = left + (right - left) / 2;

    int leftMax  = maxSubArray(nums, left, mid);
    int rightMax = maxSubArray(nums, mid+1, right);
    int crossMax = maxCrossing(nums, left, mid, right);

    return Math.max(Math.max(leftMax, rightMax), crossMax);
}

int maxCrossing(int[] nums, int left, int mid, int right) {
    // Expand from mid outward in both directions
    int leftSum = Integer.MIN_VALUE, sum = 0;
    for (int i = mid; i >= left; i--) { sum += nums[i]; leftSum = Math.max(leftSum, sum); }

    int rightSum = Integer.MIN_VALUE; sum = 0;
    for (int i = mid+1; i <= right; i++) { sum += nums[i]; rightSum = Math.max(rightSum, sum); }

    return leftSum + rightSum;
}
// Time: O(n log n), Space: O(log n)

// Kadane's (always preferred — O(n), O(1) space)
int maxSubArrayKadane(int[] nums) {
    int maxSum = nums[0], current = nums[0];
    for (int i = 1; i < nums.length; i++) {
        current = Math.max(nums[i], current + nums[i]);
        maxSum  = Math.max(maxSum, current);
    }
    return maxSum;
}
```

---

## 5 — Different Ways to Add Parentheses (LC 241)

Split the expression at each operator; recursively solve left and right; combine.

```java
List<Integer> diffWaysToCompute(String expression) {
    List<Integer> result = new ArrayList<>();

    for (int i = 0; i < expression.length(); i++) {
        char c = expression.charAt(i);
        if (c == '+' || c == '-' || c == '*') {
            // Divide at operator i
            List<Integer> left  = diffWaysToCompute(expression.substring(0, i));
            List<Integer> right = diffWaysToCompute(expression.substring(i+1));

            // Combine all pairs
            for (int l : left)
                for (int r : right)
                    result.add(c=='+' ? l+r : c=='-' ? l-r : l*r);
        }
    }

    // Base case: expression is a pure number
    if (result.isEmpty()) result.add(Integer.parseInt(expression));
    return result;
}
// Time: O(n × Catalan(n)) where n = number of operators, Space: O(n × Catalan(n))
// Memoize with HashMap<String, List<Integer>> to avoid recomputing same substrings
```

---

## 6 — Construct Binary Tree from Traversals (LC 105, LC 106)

**Key insight**: preorder gives root; inorder gives left/right split. This is D&C — divide at root.

```java
// Build from preorder + inorder (LC 105)
Map<Integer, Integer> inorderMap;  // value → index
int[] preorder;

TreeNode buildTree(int[] preorder, int[] inorder) {
    this.preorder = preorder;
    inorderMap = new HashMap<>();
    for (int i = 0; i < inorder.length; i++) inorderMap.put(inorder[i], i);
    return build(0, 0, inorder.length-1);
}

TreeNode build(int preStart, int inStart, int inEnd) {
    if (preStart >= preorder.length || inStart > inEnd) return null;

    int rootVal = preorder[preStart];
    int inMid = inorderMap.get(rootVal);
    int leftSize = inMid - inStart;

    TreeNode root = new TreeNode(rootVal);
    root.left  = build(preStart + 1, inStart, inMid - 1);          // left subtree
    root.right = build(preStart + leftSize + 1, inMid + 1, inEnd); // right subtree
    return root;
}
// Time: O(n), Space: O(n)
```

---

## 7 — Closest Pair of Points (Classic D&C)

Find minimum distance between any two points in O(n log n).

```java
double closestPair(int[][] points) {
    Arrays.sort(points, (a, b) -> a[0] - b[0]);  // sort by x
    return closest(points, 0, points.length-1);
}

double closest(int[][] pts, int l, int r) {
    if (r - l <= 2) return bruteForce(pts, l, r);

    int mid = (l + r) / 2;
    int midX = pts[mid][0];

    double d = Math.min(closest(pts, l, mid), closest(pts, mid+1, r));

    // Check strip of width 2d around midline
    List<int[]> strip = new ArrayList<>();
    for (int i = l; i <= r; i++)
        if (Math.abs(pts[i][0] - midX) < d) strip.add(pts[i]);
    strip.sort((a, b) -> a[1] - b[1]);  // sort strip by y

    for (int i = 0; i < strip.size(); i++)
        for (int j = i+1; j < strip.size() && strip.get(j)[1]-strip.get(i)[1] < d; j++)
            d = Math.min(d, dist(strip.get(i), strip.get(j)));

    return d;
}

double dist(int[] a, int[] b) { return Math.sqrt(Math.pow(a[0]-b[0],2)+Math.pow(a[1]-b[1],2)); }
double bruteForce(int[][] pts, int l, int r) {
    double d = Double.MAX_VALUE;
    for (int i = l; i <= r; i++) for (int j = i+1; j <= r; j++) d = Math.min(d, dist(pts[i], pts[j]));
    return d;
}
// Time: O(n log² n), Space: O(n)
// O(n log n) achievable if strip is maintained in sorted order during divide step
```

---

## 8 — Merge K Sorted Arrays (D&C version)

Merge arrays pairwise, like merge sort's merge step.

```java
int[] mergeKArrays(int[][] arrays) {
    if (arrays.length == 0) return new int[0];
    return mergeRange(arrays, 0, arrays.length-1);
}

int[] mergeRange(int[][] arrays, int left, int right) {
    if (left == right) return arrays[left];
    int mid = left + (right - left) / 2;
    int[] leftArr  = mergeRange(arrays, left, mid);
    int[] rightArr = mergeRange(arrays, mid+1, right);
    return mergeSorted(leftArr, rightArr);
}

int[] mergeSorted(int[] a, int[] b) {
    int[] result = new int[a.length + b.length];
    int i = 0, j = 0, k = 0;
    while (i < a.length && j < b.length) result[k++] = a[i] <= b[j] ? a[i++] : b[j++];
    while (i < a.length) result[k++] = a[i++];
    while (j < b.length) result[k++] = b[j++];
    return result;
}
// Time: O(N log k) where N = total elements, k = number of arrays
```

---

## 9 — Skyline Problem (LC 218)

Find the outline of buildings. Classic D&C merging of skylines.

```java
List<List<Integer>> getSkyline(int[][] buildings) {
    if (buildings.length == 0) return new ArrayList<>();
    return divide(buildings, 0, buildings.length - 1);
}

List<List<Integer>> divide(int[][] buildings, int l, int r) {
    if (l == r) {
        return Arrays.asList(
            Arrays.asList(buildings[l][0], buildings[l][2]),
            Arrays.asList(buildings[l][1], 0)
        );
    }
    int mid = l + (r - l) / 2;
    return mergeSkylines(divide(buildings, l, mid), divide(buildings, mid+1, r));
}

List<List<Integer>> mergeSkylines(List<List<Integer>> left, List<List<Integer>> right) {
    List<List<Integer>> result = new ArrayList<>();
    int h1 = 0, h2 = 0, i = 0, j = 0;
    while (i < left.size() && j < right.size()) {
        int x, maxH;
        List<Integer> lp = left.get(i), rp = right.get(j);
        if (lp.get(0) < rp.get(0)) { x = lp.get(0); h1 = lp.get(1); i++; }
        else if (lp.get(0) > rp.get(0)) { x = rp.get(0); h2 = rp.get(1); j++; }
        else { x = lp.get(0); h1 = lp.get(1); h2 = rp.get(1); i++; j++; }
        maxH = Math.max(h1, h2);
        if (result.isEmpty() || result.get(result.size()-1).get(1) != maxH)
            result.add(Arrays.asList(x, maxH));
    }
    while (i < left.size())  result.add(left.get(i++));
    while (j < right.size()) result.add(right.get(j++));
    return result;
}
// Time: O(n log n), Space: O(n)
```

---

## 10 — D&C vs. DP vs. Greedy

| Feature | D&C | DP | Greedy |
|---------|-----|----|--------|
| Subproblems | Independent | Overlapping | One at a time |
| Memoization needed | No | Yes | No |
| Direction | Top-down recursion | Bottom-up table | Forward scan |
| Combine step | Yes (explicit) | Yes (recurrence) | No |
| Typical complexity | O(n log n) | O(n²) or O(n³) | O(n log n) or O(n) |

---

## 11 — Visual: Merge Sort Recursion Tree

```
Input: [5, 2, 8, 1, 9, 3]

DIVIDE phase (split until size 1):
                [5, 2, 8, 1, 9, 3]
               /                   \
         [5, 2, 8]              [1, 9, 3]
          /      \              /       \
       [5, 2]   [8]          [1, 9]    [3]
       /    \                /    \
     [5]   [2]            [1]    [9]

CONQUER phase (merge sorted halves):
     [5]   [2]     →  [2, 5]
     [2, 5] + [8]  →  [2, 5, 8]
     [1]    [9]    →  [1, 9]
     [1, 9] + [3]  →  [1, 3, 9]
     [2,5,8] + [1,3,9] → [1,2,3,5,8,9]

Master theorem: T(n) = 2T(n/2) + O(n) → O(n log n)
  - log n levels in the recursion tree
  - O(n) work at each level to merge
  - Total: O(n log n)
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an integer array, count the number of "reverse pairs" where `i < j` and `nums[i] > 2 * nums[j]`. *(LC 493 — Reverse Pairs)*

**Step 1 — Read**: Input = `int[]`. Output = count of pairs (i,j) where i<j and `nums[i] > 2*nums[j]`.

**Step 2 — Identify**: Brute force = O(n²). "Count pairs across a split" → **Divide & Conquer** (like counting inversions with merge sort). During the merge of two sorted halves, count pairs efficiently.

**Step 3 — Plan**:
- Split array in half. Recursively count pairs in left half, right half.
- Count cross pairs: for each element `left[i]`, use two pointers to count how many `right[j]` satisfy `left[i] > 2*right[j]`.
- Merge the two halves (standard merge sort to keep them sorted for future counting).
- **Key insight**: when left and right halves are sorted, the counting step is O(n) with a two-pointer scan.

**Step 4 — Code**:
```java
int reversePairs(int[] nums) {
    return mergeCount(nums, 0, nums.length - 1);
}

int mergeCount(int[] nums, int lo, int hi) {
    if (lo >= hi) return 0;
    int mid = lo + (hi - lo) / 2;
    int count = mergeCount(nums, lo, mid) + mergeCount(nums, mid + 1, hi);

    // count cross pairs: nums[i] > 2 * nums[j], i in [lo,mid], j in [mid+1,hi]
    int j = mid + 1;
    for (int i = lo; i <= mid; i++) {
        while (j <= hi && (long) nums[i] > 2L * nums[j]) j++;
        count += j - (mid + 1);    // j elements in right half satisfy the condition for nums[i]
    }

    // merge (standard merge sort)
    int[] temp = new int[hi - lo + 1];
    int left = lo, right = mid + 1, k = 0;
    while (left <= mid && right <= hi)
        temp[k++] = nums[left] <= nums[right] ? nums[left++] : nums[right++];
    while (left <= mid)  temp[k++] = nums[left++];
    while (right <= hi)  temp[k++] = nums[right++];
    System.arraycopy(temp, 0, nums, lo, temp.length);

    return count;
}
// Time: O(n log n), Space: O(n) for temp array
```

**Step 5 — Verify** on `[1, 3, 2, 3, 1]`:
- Pairs: (3,1) → 3>2*1=2 ✓; (3,1)→same; (2,1)→2>2=false. Count = 2. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Single element | `lo >= hi` base case | Return 0 — handled |
| Overflow in pair counting | `nums[i] > 2 * nums[j]` overflows int | Cast to long: `(long) nums[i] > 2L * nums[j]` |
| All same elements | Merge sort works; no inversions | Count = 0 correctly |
| Already sorted (ascending) | Zero inversions/reverse pairs | Correct — cross count = 0 at each level |
| Already sorted (descending) | Maximum inversions: n*(n-1)/2 | Merge sort counts them all in O(n log n) |
| QuickSelect median: all duplicates | Pivot equals everything → never partitions | Choose pivot randomly or use 3-way partition |

```java
// Mid calculation — ALWAYS use this to avoid overflow:
int mid = lo + (hi - lo) / 2;   // NOT (lo + hi) / 2

// QuickSelect (k-th smallest) — O(n) average, O(n²) worst:
int quickSelect(int[] nums, int lo, int hi, int k) {
    int pivot = partition(nums, lo, hi);   // pivot is now at correct sorted position
    if (pivot == k) return nums[pivot];
    return pivot < k ? quickSelect(nums, pivot+1, hi, k)
                     : quickSelect(nums, lo, pivot-1, k);
}
// Use random pivot to avoid O(n²) worst case:
// swap nums[lo] with nums[lo + random.nextInt(hi - lo + 1)] before partition
```

---

## 😵 Commonly Confused With

**vs Dynamic Programming**: Both break problems into subproblems. Deciding question: *Do subproblems OVERLAP (same subproblem computed multiple times) → DP with memoization. Or are subproblems INDEPENDENT (no overlap, just split and combine) → Divide & Conquer.*

**vs Greedy**: Greedy makes one local decision and moves on. D&C splits the problem, solves recursively, and combines. Deciding question: *Can you make one irrevocable choice that reduces the problem (greedy), or do you need to solve both halves and combine results (D&C)?*

**vs Binary Search**: Binary search is a special case of divide and conquer where you discard one half entirely (O(log n)). Full D&C (like merge sort) recurses into BOTH halves. Deciding question: *Can you discard half the search space after each comparison (binary search), or must you process both halves (D&C)?*

---

## 12 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| Sorting | LC 912 (sort array — implement merge sort) |
| Selection | LC 215 (k-th largest — quick select), LC 973 (k closest — quick select) |
| Expression parsing | LC 241, LC 282 (add operators) |
| Tree construction | LC 105, LC 106, LC 889 |
| Geometry | LC 218 (skyline), LC 973 |
| Inversion count | CLRS exercise — use modified merge sort |
