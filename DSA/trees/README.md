# Trees

> A tree is a connected, acyclic graph with a designated root. The key insight for every tree problem: **which traversal order exposes the information you need?**

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Input is a tree node (with `.left`, `.right`, `.children`, `.parent`)
- [ ] Problem asks about **paths, depths, ancestors, subtree properties, or level-wise data**
- [ ] Structure is hierarchical — a node's answer depends on its children's answers

**Trigger phrases**: "maximum depth", "path sum", "lowest common ancestor", "level order", "diameter", "serialize/deserialize", "validate BST", "right side view", "construct from traversal"

---

## 2 — Flavor Detection

| Flavor | Signal | Approach |
|--------|--------|---------|
| **Preorder (root first)** | Build / serialize / copy / path-from-root | Process node BEFORE children |
| **Inorder (left-root-right)** | BST sorted order, kth smallest | Process node BETWEEN children |
| **Postorder (children first)** | Height, diameter, delete, path-through-node | Process node AFTER children |
| **Level order (BFS)** | Level-by-level, right side view, zigzag | Queue-based; process level by level |
| **Path sum** | Root-to-leaf or any-node path | DFS + running sum; return on leaf |
| **LCA** | Common ancestor of two nodes | Postorder: if both sides return non-null → current node is LCA |
| **BST property** | Validation, search, insert, floor/ceiling | Maintain valid range `[min, max]` per node |
| **Construction** | Build tree from preorder + inorder | Use index map for O(n) reconstruction |

---

## 3 — DFS Traversals (Recursive)

```java
// Preorder — Node → Left → Right
void preorder(TreeNode node, List<Integer> res) {
    if (node == null) return;
    res.add(node.val);              // process BEFORE children
    preorder(node.left, res);
    preorder(node.right, res);
}

// Inorder — Left → Node → Right
void inorder(TreeNode node, List<Integer> res) {
    if (node == null) return;
    inorder(node.left, res);
    res.add(node.val);              // process BETWEEN children
    inorder(node.right, res);
}

// Postorder — Left → Right → Node
void postorder(TreeNode node, List<Integer> res) {
    if (node == null) return;
    postorder(node.left, res);
    postorder(node.right, res);
    res.add(node.val);              // process AFTER children
}
```

**Iterative inorder (uses explicit stack — common interview ask)**:
```java
List<Integer> inorderIterative(TreeNode root) {
    List<Integer> res = new ArrayList<>();
    Deque<TreeNode> stack = new ArrayDeque<>();
    TreeNode curr = root;

    while (curr != null || !stack.isEmpty()) {
        while (curr != null) {         // go as far left as possible
            stack.push(curr);
            curr = curr.left;
        }
        curr = stack.pop();            // process node
        res.add(curr.val);
        curr = curr.right;             // move to right subtree
    }
    return res;
}
```

---

## 4 — Level Order BFS (LC 102)

**Use a Queue. At each iteration, process ALL nodes at the current level before moving to the next.**

```java
List<List<Integer>> levelOrder(TreeNode root) {
    List<List<Integer>> res = new ArrayList<>();
    if (root == null) return res;

    Queue<TreeNode> queue = new LinkedList<>();
    queue.offer(root);

    while (!queue.isEmpty()) {
        int size = queue.size();           // number of nodes at current level
        List<Integer> level = new ArrayList<>();

        for (int i = 0; i < size; i++) {
            TreeNode node = queue.poll();
            level.add(node.val);
            if (node.left  != null) queue.offer(node.left);
            if (node.right != null) queue.offer(node.right);
        }
        res.add(level);
    }
    return res;
}
```

**Right side view (LC 199)** — just take the LAST element of each level:
```java
List<Integer> rightSideView(TreeNode root) {
    List<Integer> res = new ArrayList<>();
    if (root == null) return res;
    Queue<TreeNode> q = new LinkedList<>();
    q.offer(root);
    while (!q.isEmpty()) {
        int size = q.size();
        for (int i = 0; i < size; i++) {
            TreeNode node = q.poll();
            if (i == size - 1) res.add(node.val);   // last node of this level
            if (node.left  != null) q.offer(node.left);
            if (node.right != null) q.offer(node.right);
        }
    }
    return res;
}
```

**Zigzag level order (LC 103)** — alternate direction using a flag:
```java
List<List<Integer>> zigzagLevelOrder(TreeNode root) {
    List<List<Integer>> res = new ArrayList<>();
    if (root == null) return res;
    Queue<TreeNode> q = new LinkedList<>();
    q.offer(root);
    boolean leftToRight = true;

    while (!q.isEmpty()) {
        int size = q.size();
        LinkedList<Integer> level = new LinkedList<>();
        for (int i = 0; i < size; i++) {
            TreeNode node = q.poll();
            if (leftToRight) level.addLast(node.val);
            else              level.addFirst(node.val);  // reverse: add to front
            if (node.left  != null) q.offer(node.left);
            if (node.right != null) q.offer(node.right);
        }
        res.add(level);
        leftToRight = !leftToRight;
    }
    return res;
}
```

---

## 5 — Path Sum Problems

**Key insight**: Path-from-root problems pass a **running sum** down. Path-through-any-node problems compute **max gain from each subtree** bottom-up in postorder.

**Root-to-leaf path sum exists? (LC 112)**:
```java
boolean hasPathSum(TreeNode root, int targetSum) {
    if (root == null) return false;
    if (root.left == null && root.right == null) return root.val == targetSum;  // leaf
    return hasPathSum(root.left, targetSum - root.val)
        || hasPathSum(root.right, targetSum - root.val);
}
```

**All root-to-leaf paths with target sum (LC 113)**:
```java
List<List<Integer>> pathSum(TreeNode root, int target) {
    List<List<Integer>> res = new ArrayList<>();
    dfs(root, target, new ArrayList<>(), res);
    return res;
}

void dfs(TreeNode node, int remaining, List<Integer> path, List<List<Integer>> res) {
    if (node == null) return;
    path.add(node.val);
    if (node.left == null && node.right == null && remaining == node.val)
        res.add(new ArrayList<>(path));
    dfs(node.left,  remaining - node.val, path, res);
    dfs(node.right, remaining - node.val, path, res);
    path.remove(path.size() - 1);    // backtrack
}
```

**Maximum path sum through any node (LC 124)** — postorder, each node returns its best one-sided gain:
```java
int maxPathSum(TreeNode root) {
    int[] globalMax = {Integer.MIN_VALUE};
    maxGain(root, globalMax);
    return globalMax[0];
}

int maxGain(TreeNode node, int[] globalMax) {
    if (node == null) return 0;

    int leftGain  = Math.max(0, maxGain(node.left,  globalMax));  // ignore negative branches
    int rightGain = Math.max(0, maxGain(node.right, globalMax));

    // Path through this node (can't extend both sides upward — only one side goes up)
    globalMax[0] = Math.max(globalMax[0], node.val + leftGain + rightGain);

    return node.val + Math.max(leftGain, rightGain);   // best single-side for parent
}
```

---

## 6 — Tree Diameter (LC 543)

**Diameter = longest path between any two nodes = max(leftHeight + rightHeight) across all nodes.**

```java
int diameterOfBinaryTree(TreeNode root) {
    int[] diameter = {0};
    height(root, diameter);
    return diameter[0];
}

int height(TreeNode node, int[] diameter) {
    if (node == null) return 0;
    int left  = height(node.left,  diameter);
    int right = height(node.right, diameter);
    diameter[0] = Math.max(diameter[0], left + right);  // path through this node
    return 1 + Math.max(left, right);                    // height returned to parent
}
```

---

## 7 — Lowest Common Ancestor (LC 236 / LC 235)

**LCA in arbitrary binary tree**: postorder — if both subtrees return non-null, current node IS the LCA.

```java
TreeNode lowestCommonAncestor(TreeNode root, TreeNode p, TreeNode q) {
    if (root == null || root == p || root == q) return root;   // base: found one

    TreeNode left  = lowestCommonAncestor(root.left,  p, q);
    TreeNode right = lowestCommonAncestor(root.right, p, q);

    if (left != null && right != null) return root;   // p and q on different sides
    return left != null ? left : right;               // both on same side
}
```

**LCA in BST (LC 235)** — use BST property (no full traversal needed):
```java
TreeNode lowestCommonAncestorBST(TreeNode root, TreeNode p, TreeNode q) {
    while (root != null) {
        if (p.val < root.val && q.val < root.val) root = root.left;   // both in left
        else if (p.val > root.val && q.val > root.val) root = root.right; // both in right
        else return root;   // split point = LCA
    }
    return null;
}
```

---

## 8 — BST Validation (LC 98)

**Pass valid range `[min, max]` top-down. Every node must satisfy `min < node.val < max`.**

```java
boolean isValidBST(TreeNode root) {
    return validate(root, Long.MIN_VALUE, Long.MAX_VALUE);
}

boolean validate(TreeNode node, long min, long max) {
    if (node == null) return true;
    if (node.val <= min || node.val >= max) return false;
    return validate(node.left,  min, node.val)   // left: max shrinks to current
        && validate(node.right, node.val, max);  // right: min rises to current
}
```

---

## 9 — Construct Tree from Preorder + Inorder (LC 105)

**Preorder[0] = root. Find root in inorder to split left/right subtrees.**

```java
TreeNode buildTree(int[] preorder, int[] inorder) {
    Map<Integer, Integer> inMap = new HashMap<>();
    for (int i = 0; i < inorder.length; i++) inMap.put(inorder[i], i);
    return build(preorder, 0, preorder.length - 1, inorder, 0, inorder.length - 1, inMap);
}

TreeNode build(int[] pre, int ps, int pe, int[] in, int is, int ie, Map<Integer,Integer> inMap) {
    if (ps > pe || is > ie) return null;

    int rootVal = pre[ps];
    TreeNode root = new TreeNode(rootVal);
    int mid = inMap.get(rootVal);          // root's position in inorder
    int leftSize = mid - is;

    root.left  = build(pre, ps + 1, ps + leftSize, in, is, mid - 1, inMap);
    root.right = build(pre, ps + leftSize + 1, pe, in, mid + 1, ie, inMap);
    return root;
}
```

---

## 10 — Maximum Depth & Balance Check

```java
// LC 104
int maxDepth(TreeNode root) {
    if (root == null) return 0;
    return 1 + Math.max(maxDepth(root.left), maxDepth(root.right));
}

// LC 110 — Balanced Binary Tree (postorder: return -1 on imbalance)
boolean isBalanced(TreeNode root) { return checkHeight(root) != -1; }

int checkHeight(TreeNode node) {
    if (node == null) return 0;
    int left  = checkHeight(node.left);
    int right = checkHeight(node.right);
    if (left == -1 || right == -1 || Math.abs(left - right) > 1) return -1;
    return 1 + Math.max(left, right);
}
```

---

## 11 — Traversal Order Selection Guide

```
Need root value BEFORE children values?   → Preorder
  Examples: serialize tree, copy tree, paths from root

Need left < root < right property?        → Inorder (BST)
  Examples: kth smallest in BST, BST iterator, sorted output

Need children values BEFORE root value?   → Postorder
  Examples: height, diameter, delete tree, path-through-node

Need level-by-level processing?           → BFS (Queue)
  Examples: level order, right side view, min depth, zigzag
```

---

## 12 — Complexity Reference

| Problem | Time | Space |
|---------|------|-------|
| Any DFS traversal | O(n) | O(h) — h = tree height |
| Level order BFS | O(n) | O(w) — w = max width |
| LCA binary tree | O(n) | O(h) |
| LCA BST | O(h) | O(1) |
| BST validate | O(n) | O(h) |
| Build from pre+in | O(n) | O(n) — inorder map |

---

## 13 — FAANG Interview Moves

1. **Name the traversal first**: "This needs postorder because we need child heights before computing the parent's answer."
2. **Return value from recursion**: For postorder aggregation, your recursive function's return type IS the key — `int` for height, `TreeNode` for LCA, `-1` for sentinel.
3. **Global variable pattern**: When the answer is updated at each node but recursion returns something else (diameter, max path sum), use an instance variable or a single-element int array.
4. **Iterative traversal = explicit stack**: Iterative inorder is a common follow-up — know the "go left until null, pop, process, go right" loop.
5. **BST constraints propagate downward**: Pass `[min, max]` range top-down; don't just compare `node.val` to `node.left.val` (classic mistake with the grandparent case).

---

## 14 — Visual: Tree Traversal Orders

Sample tree:
```
         4
        / \
       2   6
      / \ / \
     1  3 5  7
```

```
PREORDER  (Root → Left → Right):  4, 2, 1, 3, 6, 5, 7
            ↑ visit ROOT first → use for: copy tree, serialize, path-from-root

INORDER   (Left → Root → Right):  1, 2, 3, 4, 5, 6, 7
                  ↑ sorted order for BST → use for: kth smallest, validate BST

POSTORDER (Left → Right → Root):  1, 3, 2, 5, 7, 6, 4
                           ↑ children BEFORE parent → use for: height, diameter, delete

LEVEL ORDER (BFS):  [4], [2,6], [1,3,5,7]
                     → use for: right side view, zigzag, level averages

Memory trick:
  PRE  = root is PRE-pended (first)
  IN   = root is IN the middle
  POST = root is POST-pended (last)
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a binary tree, return the sum of all left leaf nodes. *(Not in your canonical list.)*

**Step 1 — Read**: Input = TreeNode root, output = int (sum). "Left leaf" = a leaf node that is the left child of its parent.

**Step 2 — Identify**: We need to visit every node to check if it's a left leaf. We need the parent's context ("am I approaching this node from the left?"). → **Preorder DFS** — we make decisions about a node using info passed from the parent.

**Step 3 — Plan**:
- Pass a boolean `isLeft` down the recursion.
- Base case: `node == null → return 0`.
- Leaf check: `node.left == null && node.right == null && isLeft → return node.val`.
- Otherwise: `return dfs(node.left, true) + dfs(node.right, false)`.

**Step 4 — Code**:
```java
int sumOfLeftLeaves(TreeNode root) {
    return dfs(root, false);   // root itself is not a left child
}

int dfs(TreeNode node, boolean isLeft) {
    if (node == null) return 0;
    if (node.left == null && node.right == null)   // it's a leaf
        return isLeft ? node.val : 0;
    return dfs(node.left, true) + dfs(node.right, false);
}
// Time: O(n), Space: O(h) where h = tree height
```

**Step 5 — Verify** on tree above: left leaves are 1 and 5. Sum = 6.
- dfs(4,false): not leaf → dfs(2,true) + dfs(6,false)
- dfs(2,true): not leaf → dfs(1,true) + dfs(3,false)
- dfs(1,true): leaf AND isLeft=true → return 1 ✓
- dfs(3,false): leaf AND isLeft=false → return 0 ✓
- dfs(6,false): not leaf → dfs(5,true) + dfs(7,false)
- dfs(5,true): leaf AND isLeft=true → return 5 ✓
- Total = 1+0+5+0 = 6 ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| `root == null` | `root.left` crashes | Always check `if (node == null) return ...` as first line |
| Single node (leaf root) | No left/right children | Handle: single node has depth 1, path sum = root.val |
| Path with negative values | Pruning `if pathSum < 0` skips valid paths | Never prune on negative in path-sum problems |
| BST with duplicate values | `<` vs `<=` in range check | Use strict `<` for left, strict `>` for right (duplicates go one side by convention) |
| Skewed tree (linked list shape) | O(n) recursion stack → StackOverflow | Mention iterative solution as follow-up; use explicit stack |
| Global variable in recursion | Not reset between test cases | Use instance variable inside class or `int[]` array passed by reference |

```java
// Safe null-first template (always start with this):
int solve(TreeNode node) {
    if (node == null) return BASE_VALUE;    // 0 for sum, MAX for min, MIN for max
    // ... process node
}

// Global max pattern (diameter, max path sum):
int[] maxVal = {0};   // single-element array — mutable in lambda/inner method
void dfs(TreeNode node) {
    if (node == null) return;
    int left  = Math.max(0, gain(node.left));    // ignore negative contributions
    int right = Math.max(0, gain(node.right));
    maxVal[0] = Math.max(maxVal[0], left + right + node.val);
}
```

---

## 😵 Commonly Confused With

**vs Graphs**: A tree IS a graph (connected acyclic undirected). Deciding question: *Is there a designated root and parent-child hierarchy?* Yes → treat as tree (use recursive DFS with return values). No → general graph (use BFS/DFS with visited set).

**vs Backtracking on Trees**: Backtracking on a tree traverses paths from root to leaf, maintaining a current path and undoing choices on return. Standard tree DFS computes a value at each node and passes it up. Deciding question: *Do you need to enumerate all root-to-leaf paths, or compute a single aggregate per node?*

**Preorder vs Postorder confusion**: If your recursion needs to USE the children's values to compute the current node's value → Postorder. If your recursion needs to PASS something from the current node DOWN to children → Preorder.
