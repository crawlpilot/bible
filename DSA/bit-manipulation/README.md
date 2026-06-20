# Bit Manipulation

> Operate directly on binary representations. Bit operations (AND, OR, XOR, shifts) run in O(1) and often replace loops or data structures when the key insight is bitwise.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem involve **finding unique numbers** in arrays with duplicates?
- [ ] Is the constraint "all numbers appear twice except one" or "find missing number in range"?
- [ ] Does the problem involve **subsets** (bitmask DP)?
- [ ] Do you need to **count bits**, check powers of two, or swap without a temp?
- [ ] Is the input **small enough** (≤ 20 elements) for bitmask DP?

**Trigger phrases**: "single number", "number of 1 bits", "power of two", "reverse bits", "missing number", "total hamming distance", "find two non-repeating", "maximum XOR", "minimum XOR sum", "counting bits"

---

## 2 — Core Bit Operations Cheat Sheet

```java
// Basic operations
int a = 0b1010;         // binary literal = 10
int bit = (a >> i) & 1; // get i-th bit (0-indexed from right)
a |= (1 << i);          // set i-th bit
a &= ~(1 << i);         // clear i-th bit
a ^= (1 << i);          // toggle i-th bit
boolean isSet = (a & (1 << i)) != 0;  // check i-th bit

// Common tricks
a & (a - 1)     // clear the LOWEST set bit (test if power of 2: result == 0)
a & (-a)        // isolate the LOWEST set bit (only lowest set bit remains)
a ^ a           // = 0  (anything XOR itself = 0)
a ^ 0           // = a  (anything XOR 0 = itself)
Integer.bitCount(a)   // count number of set bits (Brian Kernighan's under the hood)

// Shifts
a << k           // multiply by 2^k (left shift)
a >> k           // arithmetic right shift (sign-preserving) — divide by 2^k
a >>> k          // logical right shift (fills with 0) — use for unsigned operations

// Useful masks
0x55555555       // 0101... (even bits set)
0xAAAAAAAA       // 1010... (odd bits set)
0x0F0F0F0F       // 00001111... (lower nibbles)
0xFFFF           // lower 16 bits

// n-bit masks
(1 << n) - 1     // mask with n lowest bits set: n=3 → 0b111 = 7
```

---

## 3 — Flavor Detection

| Flavor | Signal | Key Operation |
|--------|--------|---------------|
| **Single number** | All appear twice, one appears once | XOR everything: duplicates cancel |
| **Missing number** | Range 0..n, one missing | XOR with indices OR sum formula |
| **Count set bits** | "hamming weight", "number of 1 bits" | `n & (n-1)` loop or `Integer.bitCount()` |
| **Power of two** | Is n exactly a power of two? | `n > 0 && (n & (n-1)) == 0` |
| **Bitmask DP** | Subsets of small set (n ≤ 20) | State = bitmask of which items used |
| **XOR tricks** | Find missing/duplicate, pair matching | XOR is commutative, associative, self-inverse |
| **Bit reversal** | Reverse bits of 32-bit integer | Swap bit pairs iteratively or bit-by-bit |
| **Two non-repeating** | Two elements appear once | XOR all → split by any set bit into two groups |

---

## 4 — Single Number (LC 136)

All elements appear twice except one. Find it.

```java
int singleNumber(int[] nums) {
    int result = 0;
    for (int num : nums) result ^= num;
    return result;
}
// Time: O(n), Space: O(1)
// Why: x ^ x = 0, x ^ 0 = x — duplicates cancel, single remains
```

---

## 5 — Single Number III — Two Non-Repeating Numbers (LC 260)

Two numbers appear once, all others twice. Find both.

```java
int[] singleNumber(int[] nums) {
    // Step 1: XOR all → result = a ^ b (where a, b are the two single numbers)
    int xorAll = 0;
    for (int num : nums) xorAll ^= num;

    // Step 2: find any set bit in a ^ b (means a and b differ here)
    int diffBit = xorAll & (-xorAll);   // isolate lowest set bit

    // Step 3: partition numbers into two groups by this bit → XOR each group
    int a = 0, b = 0;
    for (int num : nums) {
        if ((num & diffBit) == 0) a ^= num;
        else                      b ^= num;
    }
    return new int[]{a, b};
}
// Time: O(n), Space: O(1)
```

---

## 6 — Single Number II — Appears Three Times (LC 137)

All appear three times except one.

```java
// Bit counting approach: for each bit position, count how many numbers have it set.
// If count % 3 != 0, the single number has that bit set.
int singleNumber(int[] nums) {
    int result = 0;
    for (int i = 0; i < 32; i++) {
        int bitSum = 0;
        for (int num : nums) bitSum += (num >> i) & 1;
        result |= (bitSum % 3) << i;
    }
    return result;
}
// Time: O(32n) = O(n), Space: O(1)
```

---

## 7 — Number of 1 Bits / Hamming Weight (LC 191)

```java
int hammingWeight(int n) {
    int count = 0;
    while (n != 0) {
        n &= (n - 1);   // clear lowest set bit
        count++;
    }
    return count;
}
// Or: return Integer.bitCount(n);
// Time: O(number of set bits), Space: O(1)
```

**Brian Kernighan's trick**: `n & (n-1)` clears the lowest set bit. Loop until n = 0.

---

## 8 — Counting Bits (LC 338)

Count number of 1-bits for each number from 0 to n.

```java
int[] countBits(int n) {
    int[] dp = new int[n + 1];
    // dp[i] = dp[i >> 1] + (i & 1)
    // i >> 1 = i with last bit dropped; i & 1 = the bit we dropped
    for (int i = 1; i <= n; i++)
        dp[i] = dp[i >> 1] + (i & 1);
    return dp;
}
// Time: O(n), Space: O(n)
```

---

## 9 — Missing Number (LC 268)

```java
// Approach 1: XOR (index XOR value, duplicates cancel)
int missingNumber(int[] nums) {
    int xor = nums.length;
    for (int i = 0; i < nums.length; i++) xor ^= i ^ nums[i];
    return xor;
}

// Approach 2: Math (expected sum - actual sum)
int missingNumberMath(int[] nums) {
    int n = nums.length;
    int expected = n * (n + 1) / 2;
    int actual = 0;
    for (int num : nums) actual += num;
    return expected - actual;
}
// Time: O(n), Space: O(1)
```

---

## 10 — Power of Two (LC 231)

```java
boolean isPowerOfTwo(int n) {
    return n > 0 && (n & (n - 1)) == 0;
}
// n & (n-1) clears the lowest set bit. If n is a power of 2, only one bit is set → result is 0.
// Time: O(1), Space: O(1)
```

---

## 11 — Reverse Bits (LC 190)

```java
int reverseBits(int n) {
    int result = 0;
    for (int i = 0; i < 32; i++) {
        result = (result << 1) | (n & 1);   // shift result left, OR in n's last bit
        n >>>= 1;                            // logical right shift n
    }
    return result;
}
// Time: O(32) = O(1), Space: O(1)
```

---

## 12 — Total Hamming Distance (LC 477)

Sum of Hamming distances between all pairs.

```java
int totalHammingDistance(int[] nums) {
    int total = 0;
    for (int i = 0; i < 32; i++) {
        int ones = 0;
        for (int num : nums) ones += (num >> i) & 1;
        // ones * (n - ones) pairs differ at this bit position
        total += (long) ones * (nums.length - ones);
    }
    return total;
}
// Time: O(32n) = O(n), Space: O(1)
```

---

## 13 — Bitmask DP — Traveling Salesman / State Subset

**Pattern**: when n ≤ 20, enumerate all `2^n` subsets as bitmasks.

**State**: `dp[mask][i]` = min cost to visit all cities in `mask`, ending at city `i`.

```java
// LC 847 — Shortest Path Visiting All Nodes
int shortestPathLength(int[][] graph) {
    int n = graph.length;
    int fullMask = (1 << n) - 1;

    // BFS over (visited_mask, current_node) states
    int[][] dist = new int[1 << n][n];
    for (int[] row : dist) Arrays.fill(row, Integer.MAX_VALUE);
    Queue<int[]> queue = new LinkedList<>();

    // Start from every node simultaneously
    for (int i = 0; i < n; i++) {
        dist[1 << i][i] = 0;
        queue.offer(new int[]{1 << i, i});
    }

    while (!queue.isEmpty()) {
        int[] curr = queue.poll();
        int mask = curr[0], node = curr[1];

        if (mask == fullMask) return dist[mask][node];

        for (int next : graph[node]) {
            int newMask = mask | (1 << next);
            if (dist[newMask][next] > dist[mask][node] + 1) {
                dist[newMask][next] = dist[mask][node] + 1;
                queue.offer(new int[]{newMask, next});
            }
        }
    }
    return -1;
}
// Time: O(2^n × n), Space: O(2^n × n)
```

**Assignment Problem (minimum XOR sum) — bitmask DP** (LC 1879):
```java
int minimumXORSum(int[] nums1, int[] nums2) {
    int n = nums1.length;
    int[] dp = new int[1 << n];
    Arrays.fill(dp, Integer.MAX_VALUE);
    dp[0] = 0;

    for (int mask = 0; mask < (1 << n); mask++) {
        if (dp[mask] == Integer.MAX_VALUE) continue;
        int i = Integer.bitCount(mask);  // how many of nums1 we've matched so far
        if (i == n) continue;
        for (int j = 0; j < n; j++) {
            if ((mask & (1 << j)) == 0) {   // nums2[j] not yet used
                int newMask = mask | (1 << j);
                dp[newMask] = Math.min(dp[newMask], dp[mask] + (nums1[i] ^ nums2[j]));
            }
        }
    }
    return dp[(1 << n) - 1];
}
// Time: O(2^n × n), Space: O(2^n)
```

---

## 14 — Subset Enumeration with Bitmask

```java
// Enumerate ALL 2^n subsets of an array
void enumerateSubsets(int[] arr) {
    int n = arr.length;
    for (int mask = 0; mask < (1 << n); mask++) {
        List<Integer> subset = new ArrayList<>();
        for (int i = 0; i < n; i++)
            if ((mask & (1 << i)) != 0) subset.add(arr[i]);
        // process subset
    }
}

// Enumerate all subsets OF a given mask (sub-mask enumeration)
// Useful in: LC 1986 (Minimum Number of Work Sessions)
void enumerateSubMasks(int mask) {
    for (int sub = mask; sub > 0; sub = (sub - 1) & mask) {
        // process sub (it's always a subset of mask)
        // sub = (sub - 1) & mask is the key: iterates all submasks in O(3^n) total
    }
}
```

---

## 15 — XOR Tricks Reference

```
XOR Properties:
  a ^ a = 0          (self-cancellation)
  a ^ 0 = a          (identity)
  a ^ b = b ^ a      (commutative)
  (a^b)^c = a^(b^c)  (associative)

Common patterns:
  Find single non-duplicate:     XOR all elements
  Find missing in [0..n]:        XOR all indices 0..n with all elements
  Check if two numbers differ at bit i:  (a ^ b) & (1 << i)
  Swap without temp:             a ^= b; b ^= a; a ^= b;
  Toggle case (ASCII letter):    ch ^ 32  (upper ↔ lower, works because 'a'-'A' = 32)
```

---

## 16 — Visual: XOR Cancellation & Bit State

```
XOR BASICS:
  a ^ a = 0   (same value cancels)
  a ^ 0 = a   (XOR with 0 is identity)
  XOR is commutative and associative → order doesn't matter

Find single number in [2,2,3,4,4]:
  result = 0
  0 ^ 2 = 2
  2 ^ 2 = 0   (2 cancels itself)
  0 ^ 3 = 3
  3 ^ 4 = 7
  7 ^ 4 = 3   (4 cancels itself)
  → single number = 3

BIT TRICKS:
  n & (n-1)   → clears lowest set bit   (count 1-bits: loop until n==0)
  n & (-n)    → isolates lowest set bit (rightmost 1)
  n >> 1      → divide by 2
  n << 1      → multiply by 2
  n & 1       → check if odd (last bit is 1)
  x | (1<<k)  → set bit k
  x & ~(1<<k) → clear bit k
  x ^ (1<<k)  → toggle bit k

BITMASK for subsets of [0..n-1]:
  for (int mask = 0; mask < (1<<n); mask++) {
      // mask represents a subset
      // bit k is set if element k is included
  }
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an integer array where every element appears exactly three times except for one element that appears once, find that single element. *(LC 137 — Single Number II)*

**Step 1 — Read**: Input = int[] where all but one element appear 3× (not 2×). Output = the element appearing once.

**Step 2 — Identify**: XOR trick works for "appears twice" but not three times. However, we can count bits modulo 3. For each bit position, count how many numbers have that bit set. If count % 3 != 0, the single number has that bit set. This is **bit manipulation** (count per bit position).

**Step 3 — Plan**:
- For each bit position `i` (0 to 31):
  - Count how many numbers in array have bit `i` set.
  - If count % 3 == 1 → the single number has bit `i` set.
- Reconstruct the answer by setting the appropriate bits.

**Step 4 — Code**:
```java
int singleNumber(int[] nums) {
    int result = 0;
    for (int i = 0; i < 32; i++) {
        int bitSum = 0;
        for (int num : nums)
            bitSum += (num >> i) & 1;      // count 1s at bit position i
        if (bitSum % 3 != 0)
            result |= (1 << i);            // this bit belongs to the single number
    }
    return result;
}
// Time: O(32n) = O(n). Space: O(1).
```

**Alternative** (circuit/state machine for O(n)):
```java
int singleNumber2(int[] nums) {
    int ones = 0, twos = 0;
    for (int num : nums) {
        ones = (ones ^ num) & ~twos;   // add to ones if not in twos
        twos = (twos ^ num) & ~ones;   // add to twos if not in ones
    }
    return ones;  // what's in ones but not twos = appeared once
}
```

**Step 5 — Verify** on `[2, 2, 3, 2]`:
- bit 0: 2=10, 2=10, 3=11, 2=10 → bit 0 set count = 1 (only 3). 1%3=1 → result bit 0 = 1.
- bit 1: all four have bit 1 set (count=4). 4%3=1 → result bit 1 = 1.
- result = 0b11 = 3. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Negative numbers | `(num >> 31) & 1` extracts sign bit | Use `>>> 1` (unsigned right shift) if needed, or rely on 32-bit loop |
| Integer overflow in bit operations | `1 << 31` is `Integer.MIN_VALUE` | Use `1L << i` when building long results |
| Counting set bits (popcount) | Manual loop O(32) | `Integer.bitCount(n)` in Java |
| n & (n-1): n=0 | Loop never executes | Check n!=0 first; for Hamming weight: starts loop at 0 |
| Bitmask DP with n>20 | `1<<n` overflows int | Use `long` or limit n to ≤20 |
| Subset enumeration of large n | 2^n subsets is exponential | Only feasible for n≤20; larger n needs different approach |

```java
// Count number of 1-bits (Hamming weight — LC 191):
int hammingWeight(int n) {
    int count = 0;
    while (n != 0) {
        n &= (n - 1);   // clear lowest set bit
        count++;
    }
    return count;
}

// Check if n is a power of 2:
boolean isPowerOfTwo(int n) {
    return n > 0 && (n & (n - 1)) == 0;
}

// Reverse bits (LC 190):
int reverseBits(int n) {
    int result = 0;
    for (int i = 0; i < 32; i++) {
        result = (result << 1) | (n & 1);
        n >>= 1;
    }
    return result;
}
```

---

## 😵 Commonly Confused With

**vs Math (division/modulo)**: Some bit problems have math equivalents (power of 2 → log, popcount → counting). Deciding question: *Does the problem mention "without using multiplication/division" or "in O(1)"? That's a hint for bit tricks.*

**vs DP Bitmask**: Bitmask DP uses the bit pattern as a state (visited set of nodes). Pure bit manipulation doesn't have a DP table. Deciding question: *Are you iterating over subsets as states in a DP recurrence (bitmask DP), or manipulating individual bits for arithmetic/logic (bit manipulation)?*

**vs HashSet for "find single/duplicate"**: HashSet with add/remove can find the unique element in O(n) space. XOR does it in O(1) space. Deciding question: *Is this a "appears twice, find one" problem (XOR O(1) space), or a more complex counting problem (HashMap / bit counting)?*

---

## 17 — Canonical LeetCode Problems

| Flavor | Problems |
|--------|---------|
| Single number | LC 136, LC 137, LC 260 |
| Missing/duplicate | LC 268, LC 287, LC 41 |
| Bit counting | LC 191, LC 338, LC 477 |
| Powers | LC 231 (power of 2), LC 342 (power of 4) |
| Manipulation | LC 190 (reverse bits), LC 461 (hamming distance) |
| XOR maximization | LC 421 (→ Trie), LC 1707 |
| Bitmask DP | LC 847, LC 1879, LC 1986, LC 464 |
| Subset enumeration | LC 78 (→ backtracking), LC 1994 |
