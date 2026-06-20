# Backtracking

> Build a solution incrementally by exploring all options at each step, and abandon ("backtrack") a partial solution as soon as it violates a constraint — pruning the search tree.

---

## 1 — How to Recognize This Pattern

Ask yourself ALL of these:
- [ ] Problem asks for **all valid** combinations, subsets, permutations, or paths
- [ ] The decision space forms a **tree** — at each node you choose one option from a set
- [ ] A partial choice can be **validated early** (pruning opportunity)
- [ ] Brute force would enumerate all possibilities — backtracking prunes invalid branches

**Trigger phrases**: "all subsets", "all permutations", "all combinations that sum to", "generate all valid", "word search", "N-Queens", "Sudoku solver", "letter combinations of phone number"

**Anti-pattern**: You only need ONE answer, not ALL → BFS/DFS with early termination is often cleaner.

---

## 2 — Flavor Detection

| Flavor | Signal | Key Choice per Level |
|--------|--------|---------------------|
| **Subsets** | All 2ⁿ subsets of a set | Include or exclude each element |
| **Combinations (fixed size)** | Choose exactly k from n | Pick next element, index always moves forward |
| **Combinations (sum target)** | Elements sum to target | Pick element (reuse allowed or not), reduce remaining sum |
| **Permutations** | All orderings of elements | Pick any unused element at each position |
| **Grid / path search** | 2D grid, word search | 4 directions; mark visited; unmark on backtrack |
| **Constraint satisfaction** | N-Queens, Sudoku | Validate constraint before recursing |
| **Parentheses generation** | Balanced brackets | Track open-count and close-count |

---

## 3 — Universal Backtracking Template

Every backtracking problem follows the same skeleton:

```java
void backtrack(State state, ChoiceList choices, List<Result> result) {
    if (isGoalState(state)) {          // base case: valid complete solution
        result.add(new ArrayList<>(state.current));
        return;
    }

    for (Choice c : choices) {
        if (!isValid(state, c)) continue;   // prune early

        makeChoice(state, c);               // Step into
        backtrack(state, nextChoices(state, c), result);
        undoChoice(state, c);               // Step out (backtrack)
    }
}
```

The three key operations: **make → recurse → undo**. The undo must be the exact inverse of make.

---

## 4 — Subsets (LC 78)

**Every element: include or skip. No target condition — all 2ⁿ subsets are valid.**

```java
List<List<Integer>> subsets(int[] nums) {
    List<List<Integer>> result = new ArrayList<>();
    backtrack(nums, 0, new ArrayList<>(), result);
    return result;
}

void backtrack(int[] nums, int start, List<Integer> current, List<List<Integer>> result) {
    result.add(new ArrayList<>(current));          // every state is a valid subset

    for (int i = start; i < nums.length; i++) {
        current.add(nums[i]);                       // make choice
        backtrack(nums, i + 1, current, result);    // recurse (i+1: no reuse)
        current.remove(current.size() - 1);         // undo
    }
}
```

**With duplicates — Subsets II (LC 90)**:
```java
// Sort first, then skip duplicate elements at the same recursion level
void backtrack(int[] nums, int start, List<Integer> cur, List<List<Integer>> res) {
    res.add(new ArrayList<>(cur));
    for (int i = start; i < nums.length; i++) {
        if (i > start && nums[i] == nums[i - 1]) continue;   // skip dup at same level
        cur.add(nums[i]);
        backtrack(nums, i + 1, cur, res);
        cur.remove(cur.size() - 1);
    }
}
```

---

## 5 — Combinations — Sum Target (LC 39 / LC 40)

**Pick elements that sum to target. Candidate elements may be reused (LC 39) or used once (LC 40).**

**LC 39 — reuse allowed**:
```java
List<List<Integer>> combinationSum(int[] candidates, int target) {
    Arrays.sort(candidates);
    List<List<Integer>> res = new ArrayList<>();
    backtrack(candidates, 0, target, new ArrayList<>(), res);
    return res;
}

void backtrack(int[] cand, int start, int remaining, List<Integer> cur, List<List<Integer>> res) {
    if (remaining == 0) { res.add(new ArrayList<>(cur)); return; }

    for (int i = start; i < cand.length; i++) {
        if (cand[i] > remaining) break;        // pruning: sorted → rest are also too big
        cur.add(cand[i]);
        backtrack(cand, i, remaining - cand[i], cur, res);  // i (not i+1): reuse allowed
        cur.remove(cur.size() - 1);
    }
}
```

**LC 40 — each element used once, duplicates in input**:
```java
void backtrack(int[] cand, int start, int remaining, List<Integer> cur, List<List<Integer>> res) {
    if (remaining == 0) { res.add(new ArrayList<>(cur)); return; }

    for (int i = start; i < cand.length; i++) {
        if (cand[i] > remaining) break;
        if (i > start && cand[i] == cand[i - 1]) continue;  // skip dup at same level
        cur.add(cand[i]);
        backtrack(cand, i + 1, remaining - cand[i], cur, res); // i+1: no reuse
        cur.remove(cur.size() - 1);
    }
}
```

---

## 6 — Permutations (LC 46 / LC 47)

**All orderings of elements. Every position picks from remaining elements.**

**LC 46 — distinct elements**:
```java
List<List<Integer>> permute(int[] nums) {
    List<List<Integer>> res = new ArrayList<>();
    backtrack(nums, new boolean[nums.length], new ArrayList<>(), res);
    return res;
}

void backtrack(int[] nums, boolean[] used, List<Integer> cur, List<List<Integer>> res) {
    if (cur.size() == nums.length) { res.add(new ArrayList<>(cur)); return; }

    for (int i = 0; i < nums.length; i++) {
        if (used[i]) continue;
        used[i] = true;
        cur.add(nums[i]);
        backtrack(nums, used, cur, res);
        cur.remove(cur.size() - 1);
        used[i] = false;
    }
}
```

**LC 47 — with duplicates**:
```java
void backtrack(int[] nums, boolean[] used, List<Integer> cur, List<List<Integer>> res) {
    if (cur.size() == nums.length) { res.add(new ArrayList<>(cur)); return; }

    for (int i = 0; i < nums.length; i++) {
        if (used[i]) continue;
        // Skip: same value as previous AND previous was not used in this branch
        if (i > 0 && nums[i] == nums[i - 1] && !used[i - 1]) continue;
        used[i] = true;
        cur.add(nums[i]);
        backtrack(nums, used, cur, res);
        cur.remove(cur.size() - 1);
        used[i] = false;
    }
}
```

---

## 7 — Grid / Word Search (LC 79)

**Navigate a 2D grid; mark visited cells; unmark on backtrack.**

```java
boolean exist(char[][] board, String word) {
    int m = board.length, n = board[0].length;
    for (int i = 0; i < m; i++)
        for (int j = 0; j < n; j++)
            if (dfs(board, word, 0, i, j)) return true;
    return false;
}

boolean dfs(char[][] board, String word, int idx, int r, int c) {
    if (idx == word.length()) return true;                            // all chars matched
    if (r < 0 || r >= board.length || c < 0 || c >= board[0].length) return false;
    if (board[r][c] != word.charAt(idx)) return false;               // prune

    char tmp = board[r][c];
    board[r][c] = '#';                                                // mark visited

    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
    for (int[] d : dirs)
        if (dfs(board, word, idx + 1, r + d[0], c + d[1])) {
            board[r][c] = tmp;                                        // restore before return
            return true;
        }

    board[r][c] = tmp;                                                // undo
    return false;
}
```

---

## 8 — N-Queens (LC 51) — Constraint Satisfaction

**Place N queens so no two share row, column, or diagonal.**

```java
List<List<String>> solveNQueens(int n) {
    List<List<String>> res = new ArrayList<>();
    int[] queens = new int[n];   // queens[row] = col
    Arrays.fill(queens, -1);
    Set<Integer> cols = new HashSet<>(), diag1 = new HashSet<>(), diag2 = new HashSet<>();
    backtrack(0, n, queens, cols, diag1, diag2, res);
    return res;
}

void backtrack(int row, int n, int[] queens,
               Set<Integer> cols, Set<Integer> diag1, Set<Integer> diag2,
               List<List<String>> res) {
    if (row == n) { res.add(buildBoard(queens, n)); return; }

    for (int col = 0; col < n; col++) {
        if (cols.contains(col) || diag1.contains(row - col) || diag2.contains(row + col))
            continue;                            // prune: attacked cell

        queens[row] = col;
        cols.add(col); diag1.add(row - col); diag2.add(row + col);

        backtrack(row + 1, n, queens, cols, diag1, diag2, res);

        queens[row] = -1;
        cols.remove(col); diag1.remove(row - col); diag2.remove(row + col);
    }
}
```

---

## 9 — Balanced Parentheses (LC 22)

**State = (openCount, closeCount). Prune: open > n or close > open.**

```java
List<String> generateParenthesis(int n) {
    List<String> res = new ArrayList<>();
    backtrack(n, 0, 0, new StringBuilder(), res);
    return res;
}

void backtrack(int n, int open, int close, StringBuilder cur, List<String> res) {
    if (cur.length() == 2 * n) { res.add(cur.toString()); return; }

    if (open < n) {                   // can add open bracket
        cur.append('(');
        backtrack(n, open + 1, close, cur, res);
        cur.deleteCharAt(cur.length() - 1);
    }
    if (close < open) {               // can add close bracket (only if open > close)
        cur.append(')');
        backtrack(n, open, close + 1, cur, res);
        cur.deleteCharAt(cur.length() - 1);
    }
}
```

---

## 10 — Complexity Reference

| Problem | Time | Space |
|---------|------|-------|
| Subsets | O(2ⁿ × n) | O(n) stack depth |
| Combinations sum (reuse) | O(n^(t/m)) where t=target, m=min val | O(t/m) depth |
| Permutations | O(n! × n) | O(n) |
| Word search | O(m × n × 4^L) where L=word length | O(L) |
| N-Queens | O(n!) | O(n) |

---

## 11 — FAANG Interview Moves

1. **Template first**: Write the `backtrack(state, start, result)` signature before any logic — shows pattern recognition.
2. **Three moves**: always label "make choice → recurse → undo choice" in your code or narration.
3. **Pruning is the differentiator**: after the brute-force version, ask "where can I prune?" — sorted input + `break` when remaining < 0 eliminates vast branches.
4. **Duplicate elimination**: `if (i > start && nums[i] == nums[i-1]) continue` — interviewers always check for this in subsets/combinations with duplicates.
5. **State the search tree**: draw the first 2 levels for the interviewer to show you understand the branching factor and depth.

---

## 12 — Visual: Backtracking Decision Tree

**Subsets of [1, 2, 3]** — every branch = "include or skip":
```
                        []
              /                    \
          [1]                      []
        /      \                /       \
     [1,2]    [1]           [2]          []
     /   \    / \           / \          / \
[1,2,3][1,2][1,3][1]   [2,3] [2]    [3]   []

All leaf nodes (read path from root):
[], [3], [2], [2,3], [1], [1,3], [1,2], [1,2,3]  ← 2³ = 8 subsets

Pruning example (target sum = 6, sorted [1,2,3,4,5]):
  [1,2,3] sum=6 ✓  add to result
  [1,2,4] sum=7 > 6  → PRUNE (sorted, remaining only gets bigger)
  [1,2,5] → pruned
  [1,3] sum=4, try [1,3,4] sum=8 > 6 → PRUNE
  ...etc
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a string containing digits 2-9, return all possible letter combinations a phone number could represent. *(LC 17 — but let's recognize it fresh.)*

**Step 1 — Read**: Input = string of digits ("23"), output = list of all possible strings. "All possible" → need all combinations.

**Step 2 — Identify**: At each digit, we choose one of 3-4 letters. Next digit's choice is independent of current choice. We need ALL combinations → **Backtracking**. Not DP (we need all solutions, not count/min/max).

**Step 3 — Plan**:
- Map each digit to its letters: 2→abc, 3→def, ...
- At position `i` in digits: try each letter for `digits[i]`, recurse on `i+1`, backtrack.
- Base case: `i == digits.length()` → add current path to result.

**Step 4 — Code**:
```java
List<String> letterCombinations(String digits) {
    if (digits.isEmpty()) return new ArrayList<>();
    String[] map = {"", "", "abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz"};
    List<String> result = new ArrayList<>();
    backtrack(digits, 0, new StringBuilder(), result, map);
    return result;
}

void backtrack(String digits, int i, StringBuilder path, List<String> result, String[] map) {
    if (i == digits.length()) { result.add(path.toString()); return; }
    for (char c : map[digits.charAt(i) - '0'].toCharArray()) {
        path.append(c);                       // make choice
        backtrack(digits, i + 1, path, result, map);
        path.deleteCharAt(path.length() - 1); // undo choice
    }
}
// Time: O(4^n × n), Space: O(n) stack
```

**Step 5 — Verify** on "23":
- i=0, digit='2', letters="abc": try 'a' → recurse i=1
  - i=1, digit='3', letters="def": try 'd' → path="ad" → i=2 → add "ad"
  - try 'e' → add "ae"; try 'f' → add "af"
- backtrack, try 'b' → "bd","be","bf"; try 'c' → "cd","ce","cf"
- Result: ["ad","ae","af","bd","be","bf","cd","ce","cf"] ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty input `[]` | Base case never triggers meaningfully | Return `new ArrayList<>()` before calling backtrack |
| Duplicates in input (subsets/combos) | Duplicate subsets generated | Sort first; add `if (i > start && nums[i] == nums[i-1]) continue` |
| Reuse allowed vs not | Wrong start index | Reuse: `backtrack(..., i, ...)`. No reuse: `backtrack(..., i+1, ...)` |
| Grid boundary | Out-of-bounds access in word search | Always check bounds before recursing |
| StringBuilder vs String | `path.add(element)` on String creates new object | Use `StringBuilder` for character-level; `List<Integer>` for element-level |

```java
// Reuse vs no-reuse in combination sum:
// Reuse (Coin Change with all combos): pass same index i
for (int j = start; j < candidates.length; j++)
    backtrack(candidates, j, ...)     // j not j+1 → allows re-picking

// No reuse (Combinations): pass i+1
for (int j = start; j < candidates.length; j++)
    backtrack(candidates, j + 1, ...) // j+1 → each element used at most once

// Deduplication (sorted input):
Arrays.sort(nums);
for (int j = start; j < nums.length; j++) {
    if (j > start && nums[j] == nums[j-1]) continue;  // skip duplicate at same level
    ...
}
```

---

## 😵 Commonly Confused With

**vs DP**: Backtracking generates ALL solutions explicitly. DP counts or finds the optimal solution without enumerating all. Deciding question: *Do you need every individual solution, or just the count/min/max?* All solutions → Backtracking. Aggregate → DP.

**vs BFS/DFS on graphs**: Backtracking on an implicit decision tree is DFS with an undo step. The difference: in graph DFS you mark visited globally; in backtracking you undo the visit on return so the same node can appear in different branches. Deciding question: *Can the same element appear in multiple branches of different solutions?* Yes → Backtracking (with undo). No → Graph DFS (with visited set).

**vs Permutation vs Combination confusion**: Permutations care about ORDER ([1,2] ≠ [2,1]). Combinations do NOT ([1,2] = [2,1]). For combinations: always advance the index forward (`start = i+1`). For permutations: use a `used[]` boolean array to pick from all positions.
