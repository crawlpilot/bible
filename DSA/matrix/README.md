# Matrix (2D Grid)

> A matrix is a 2D array where rows and columns define spatial relationships. The core insight: most matrix problems reduce to BFS/DFS on a grid, or careful index manipulation for rotation/spiral/search.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Is the input a **2D grid or matrix**?
- [ ] Does the problem involve **traversal**, **flood fill**, **shortest path**, or **connected regions**?
- [ ] Does it require **rotating**, **transposing**, or **spiraling** through the matrix?
- [ ] Is it a search problem on a matrix with sorted rows/columns?

**Trigger phrases**: "number of islands", "flood fill", "shortest path in binary matrix", "spiral order", "rotate image", "set matrix zeroes", "search a 2D matrix", "word search", "maximal rectangle", "pacific atlantic water flow"

---

## 2 — Flavor Detection

| Flavor | Signal | Algorithm |
|--------|--------|-----------|
| **Flood fill / region counting** | Connected cells of same value | BFS or DFS with visited tracking |
| **Shortest path** | Minimum steps from source to target | BFS (unweighted) |
| **Multi-source BFS** | Nearest 0, nearest gate | Start BFS from ALL sources simultaneously |
| **Spiral traversal** | Visit in spiral order | Four-pointer boundary shrinking |
| **Rotation** | Rotate 90° in-place | Transpose + reverse rows |
| **Matrix search** | Sorted rows and columns | Staircase from top-right corner |
| **Prefix sum 2D** | Submatrix sum queries | See `prefix-sum/README.md` |
| **Dynamic programming** | Paths, largest rectangle | DP on rows or cells |

---

## 3 — Grid Traversal Setup (BFS/DFS Template)

```java
int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};   // 4-directional
// 8-directional: also add {1,1},{1,-1},{-1,1},{-1,-1}

boolean inBounds(int r, int c, int m, int n) {
    return r >= 0 && r < m && c >= 0 && c < n;
}

// BFS from (startR, startC)
void bfs(int[][] grid, int startR, int startC) {
    int m = grid.length, n = grid[0].length;
    boolean[][] visited = new boolean[m][n];
    Queue<int[]> queue = new LinkedList<>();

    queue.offer(new int[]{startR, startC});
    visited[startR][startC] = true;
    int steps = 0;

    while (!queue.isEmpty()) {
        int size = queue.size();
        for (int i = 0; i < size; i++) {
            int[] curr = queue.poll();
            for (int[] d : dirs) {
                int nr = curr[0] + d[0], nc = curr[1] + d[1];
                if (inBounds(nr, nc, m, n) && !visited[nr][nc] && /* condition */) {
                    visited[nr][nc] = true;
                    queue.offer(new int[]{nr, nc});
                }
            }
        }
        steps++;
    }
}
```

---

## 4 — Number of Islands (LC 200)

```java
int numIslands(char[][] grid) {
    int m = grid.length, n = grid[0].length, count = 0;

    for (int r = 0; r < m; r++) {
        for (int c = 0; c < n; c++) {
            if (grid[r][c] == '1') {
                dfsFlood(grid, r, c);   // mark entire island as visited
                count++;
            }
        }
    }
    return count;
}

void dfsFlood(char[][] grid, int r, int c) {
    if (r < 0 || r >= grid.length || c < 0 || c >= grid[0].length || grid[r][c] != '1') return;
    grid[r][c] = '0';   // mark visited by modifying in-place
    for (int[] d : new int[][]{{0,1},{0,-1},{1,0},{-1,0}})
        dfsFlood(grid, r + d[0], c + d[1]);
}
// Time: O(m*n), Space: O(m*n) recursion stack (use BFS for O(min(m,n)) space)
```

---

## 5 — Multi-Source BFS — 01 Matrix (LC 542)

Find shortest distance to nearest 0 for each cell.

**Key**: start BFS from ALL 0s simultaneously, not from each 1 individually.

```java
int[][] updateMatrix(int[][] mat) {
    int m = mat.length, n = mat[0].length;
    int[][] dist = new int[m][n];
    Queue<int[]> queue = new LinkedList<>();

    // Initialize: all 0s go in queue with distance 0; all 1s get MAX distance
    for (int r = 0; r < m; r++) {
        for (int c = 0; c < n; c++) {
            if (mat[r][c] == 0) { queue.offer(new int[]{r, c}); }
            else                { dist[r][c] = Integer.MAX_VALUE; }
        }
    }

    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
    while (!queue.isEmpty()) {
        int[] curr = queue.poll();
        for (int[] d : dirs) {
            int nr = curr[0]+d[0], nc = curr[1]+d[1];
            if (nr >= 0 && nr < m && nc >= 0 && nc < n
                && dist[nr][nc] > dist[curr[0]][curr[1]] + 1) {
                dist[nr][nc] = dist[curr[0]][curr[1]] + 1;
                queue.offer(new int[]{nr, nc});
            }
        }
    }
    return dist;
}
// Time: O(m*n), Space: O(m*n)
```

---

## 6 — Shortest Path in Binary Matrix (LC 1091)

0-cells are open, 1-cells are blocked. 8-directional. Find shortest path from (0,0) to (n-1,n-1).

```java
int shortestPathBinaryMatrix(int[][] grid) {
    int n = grid.length;
    if (grid[0][0] == 1 || grid[n-1][n-1] == 1) return -1;
    if (n == 1) return 1;

    Queue<int[]> queue = new LinkedList<>();
    queue.offer(new int[]{0, 0, 1});   // row, col, path_length
    grid[0][0] = 1;                    // mark visited

    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0},{1,1},{1,-1},{-1,1},{-1,-1}};
    while (!queue.isEmpty()) {
        int[] curr = queue.poll();
        for (int[] d : dirs) {
            int nr = curr[0]+d[0], nc = curr[1]+d[1];
            if (nr >= 0 && nr < n && nc >= 0 && nc < n && grid[nr][nc] == 0) {
                if (nr == n-1 && nc == n-1) return curr[2] + 1;
                grid[nr][nc] = 1;
                queue.offer(new int[]{nr, nc, curr[2]+1});
            }
        }
    }
    return -1;
}
// Time: O(n²), Space: O(n²)
```

---

## 7 — Spiral Order (LC 54)

```java
List<Integer> spiralOrder(int[][] matrix) {
    List<Integer> result = new ArrayList<>();
    int top = 0, bottom = matrix.length-1, left = 0, right = matrix[0].length-1;

    while (top <= bottom && left <= right) {
        // Traverse right
        for (int c = left; c <= right; c++) result.add(matrix[top][c]);
        top++;
        // Traverse down
        for (int r = top; r <= bottom; r++) result.add(matrix[r][right]);
        right--;
        // Traverse left (only if rows remain)
        if (top <= bottom) {
            for (int c = right; c >= left; c--) result.add(matrix[bottom][c]);
            bottom--;
        }
        // Traverse up (only if columns remain)
        if (left <= right) {
            for (int r = bottom; r >= top; r--) result.add(matrix[r][left]);
            left++;
        }
    }
    return result;
}
// Time: O(m*n), Space: O(1) extra
```

**Spiral Matrix II — fill a new matrix in spiral order (LC 59)**:
```java
int[][] generateMatrix(int n) {
    int[][] matrix = new int[n][n];
    int top = 0, bottom = n-1, left = 0, right = n-1, num = 1;
    while (top <= bottom && left <= right) {
        for (int c = left; c <= right; c++) matrix[top][c] = num++;
        top++;
        for (int r = top; r <= bottom; r++) matrix[r][right] = num++;
        right--;
        if (top <= bottom) { for (int c = right; c >= left; c--) matrix[bottom][c] = num++; bottom--; }
        if (left <= right) { for (int r = bottom; r >= top; r--) matrix[r][left] = num++; left++; }
    }
    return matrix;
}
```

---

## 8 — Rotate Image 90° Clockwise (LC 48)

**Two-step trick**: Transpose, then reverse each row.

```java
void rotate(int[][] matrix) {
    int n = matrix.length;

    // Step 1: Transpose (swap matrix[i][j] with matrix[j][i])
    for (int i = 0; i < n; i++)
        for (int j = i+1; j < n; j++) {
            int tmp = matrix[i][j];
            matrix[i][j] = matrix[j][i];
            matrix[j][i] = tmp;
        }

    // Step 2: Reverse each row
    for (int[] row : matrix) {
        int left = 0, right = n-1;
        while (left < right) { int tmp = row[left]; row[left++] = row[right]; row[right--] = tmp; }
    }
}
// Time: O(n²), Space: O(1)
```

**Counter-clockwise 90°**: Transpose, then reverse each COLUMN (or reverse rows first, then transpose).

---

## 9 — Set Matrix Zeroes (LC 73)

If a cell is 0, set its entire row and column to 0.

```java
void setZeroes(int[][] matrix) {
    int m = matrix.length, n = matrix[0].length;
    boolean firstRowZero = false, firstColZero = false;

    // Check if first row/col themselves have zeros
    for (int c = 0; c < n; c++) if (matrix[0][c] == 0) firstRowZero = true;
    for (int r = 0; r < m; r++) if (matrix[r][0] == 0) firstColZero = true;

    // Use first row and column as markers
    for (int r = 1; r < m; r++)
        for (int c = 1; c < n; c++)
            if (matrix[r][c] == 0) { matrix[r][0] = 0; matrix[0][c] = 0; }

    // Zero out based on markers
    for (int r = 1; r < m; r++)
        for (int c = 1; c < n; c++)
            if (matrix[r][0] == 0 || matrix[0][c] == 0) matrix[r][c] = 0;

    // Zero out first row and column if needed
    if (firstRowZero) Arrays.fill(matrix[0], 0);
    if (firstColZero) for (int r = 0; r < m; r++) matrix[r][0] = 0;
}
// Time: O(m*n), Space: O(1)
```

---

## 10 — Pacific Atlantic Water Flow (LC 417)

Water can flow to both Pacific (top/left edges) and Atlantic (bottom/right edges). Find cells from which water can reach both.

**Key**: reverse the flow — BFS/DFS from ocean edges inward.

```java
List<List<Integer>> pacificAtlantic(int[][] heights) {
    int m = heights.length, n = heights[0].length;
    boolean[][] pacific = new boolean[m][n];
    boolean[][] atlantic = new boolean[m][n];

    Queue<int[]> pQueue = new LinkedList<>(), aQueue = new LinkedList<>();

    for (int r = 0; r < m; r++) {
        pQueue.offer(new int[]{r, 0});   pacific[r][0] = true;
        aQueue.offer(new int[]{r, n-1}); atlantic[r][n-1] = true;
    }
    for (int c = 0; c < n; c++) {
        pQueue.offer(new int[]{0, c});   pacific[0][c] = true;
        aQueue.offer(new int[]{m-1, c}); atlantic[m-1][c] = true;
    }

    bfsOcean(heights, pQueue, pacific);
    bfsOcean(heights, aQueue, atlantic);

    List<List<Integer>> result = new ArrayList<>();
    for (int r = 0; r < m; r++)
        for (int c = 0; c < n; c++)
            if (pacific[r][c] && atlantic[r][c]) result.add(Arrays.asList(r, c));
    return result;
}

void bfsOcean(int[][] heights, Queue<int[]> queue, boolean[][] visited) {
    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
    while (!queue.isEmpty()) {
        int[] curr = queue.poll();
        for (int[] d : dirs) {
            int nr = curr[0]+d[0], nc = curr[1]+d[1];
            if (nr < 0||nr>=heights.length||nc < 0||nc>=heights[0].length
                ||visited[nr][nc]||heights[nr][nc]<heights[curr[0]][curr[1]]) continue;
            visited[nr][nc] = true;
            queue.offer(new int[]{nr, nc});
        }
    }
}
// Time: O(m*n), Space: O(m*n)
```

---

## 11 — Maximal Square (LC 221)

Find the largest square of 1s.

```java
int maximalSquare(char[][] matrix) {
    int m = matrix.length, n = matrix[0].length, maxSide = 0;
    int[][] dp = new int[m+1][n+1];   // dp[i][j] = side length of max square ending at (i-1,j-1)

    for (int r = 1; r <= m; r++) {
        for (int c = 1; c <= n; c++) {
            if (matrix[r-1][c-1] == '1') {
                dp[r][c] = Math.min(dp[r-1][c], Math.min(dp[r][c-1], dp[r-1][c-1])) + 1;
                maxSide = Math.max(maxSide, dp[r][c]);
            }
        }
    }
    return maxSide * maxSide;
}
// dp[r][c] = min of top, left, top-left neighbors + 1 (a square requires all three to exist)
// Time: O(m*n), Space: O(m*n) → optimizable to O(n)
```

---

## 12 — Word Search in Grid (LC 79)

See `backtracking/README.md` for full solution. Key: DFS + mark/unmark visited.

---

## 13 — Visual: Matrix BFS (Multi-Source) & Spiral Traversal

```
MULTI-SOURCE BFS — "01 Matrix" (distance to nearest 0):
Grid:          Start: enqueue ALL 0s with distance 0.
0 0 0          Queue: [(0,0,0),(0,1,0),(0,2,0)]
0 1 0    →
0 0 0          BFS expands layer by layer:
               (1,1) is the only 1 → distance = 1 (reached from any adjacent 0)
Result:
0 0 0
0 1 0
0 0 0

4 DIRECTIONS template:
  int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
  for (int[] d : dirs) {
      int nr = r + d[0], nc = c + d[1];
      if (nr>=0 && nr<rows && nc>=0 && nc<cols) { ... }
  }

SPIRAL ORDER — n=3:
  1  2  3         Direction sequence: RIGHT → DOWN → LEFT → UP → repeat
  4  5  6    →    Boundaries: top, bottom, left, right
  7  8  9         Shrink boundary after each direction is exhausted.
  Output: [1,2,3,6,9,8,7,4,5]
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given an `m×n` binary grid, count the number of "islands" where an island is a group of 1s connected horizontally or vertically. *(LC 200 — Number of Islands)*

**Step 1 — Read**: Input = `char[][] grid` ('1' or '0'). Output = int (count of islands).

**Step 2 — Identify**: "Connected components in a grid" → **Matrix BFS** or DFS. For each unvisited '1', run BFS/DFS to mark the entire island as visited, then count.

**Step 3 — Plan**:
- Iterate every cell. If `grid[r][c] == '1'` and not visited:
  - Increment island count.
  - BFS from `(r,c)`: mark all connected '1's as visited (set to '0' or use boolean visited array).
- Return count.

**Step 4 — Code**:
```java
int numIslands(char[][] grid) {
    int rows = grid.length, cols = grid[0].length, count = 0;
    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};

    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            if (grid[r][c] == '1') {
                count++;
                // BFS to mark island
                Queue<int[]> queue = new LinkedList<>();
                queue.offer(new int[]{r, c});
                grid[r][c] = '0';    // mark visited immediately on enqueue

                while (!queue.isEmpty()) {
                    int[] cell = queue.poll();
                    for (int[] d : dirs) {
                        int nr = cell[0] + d[0], nc = cell[1] + d[1];
                        if (nr >= 0 && nr < rows && nc >= 0 && nc < cols
                                && grid[nr][nc] == '1') {
                            grid[nr][nc] = '0';     // mark before enqueue (prevents duplicates)
                            queue.offer(new int[]{nr, nc});
                        }
                    }
                }
            }
        }
    }
    return count;
}
// Time: O(m*n), Space: O(min(m,n)) for BFS queue in worst case
```

**Step 5 — Verify** on:
```
1 1 0
0 1 0
0 0 1
```
- (0,0): '1' → count=1. BFS marks (0,0),(0,1),(1,1) as '0'.
- Scan continues: (2,2) is '1' → count=2. BFS marks (2,2).
- Return 2. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty grid | `grid[0]` throws NPE | Check `grid.length == 0` first |
| Single cell grid | BFS queue handles trivially | Works with standard template |
| All 1s | One big island | BFS from (0,0) marks entire grid; count=1 |
| Mark visited on enqueue vs dequeue | Marking on dequeue → same cell enqueued multiple times → O(m*n * 4) work | Always mark visited BEFORE enqueuing |
| Pacific Atlantic: two BFS from opposite shores | Direction is reversed (water flows toward ocean) | BFS from ocean boundaries going INWARD (uphill) |
| Rotate 90°: transpose then reverse rows | Common mistake: wrong order of operations | Transpose first (`swap(matrix[i][j], matrix[j][i])`), then reverse each row |

```java
// In-place rotation 90° clockwise (LC 48):
// Step 1: transpose
for (int i = 0; i < n; i++)
    for (int j = i + 1; j < n; j++) {
        int tmp = matrix[i][j];
        matrix[i][j] = matrix[j][i];
        matrix[j][i] = tmp;
    }
// Step 2: reverse each row
for (int[] row : matrix) {
    int l = 0, r = row.length - 1;
    while (l < r) { int tmp = row[l]; row[l++] = row[r]; row[r--] = tmp; }
}

// Spiral: shrink 4 boundaries
int top=0, bottom=m-1, left=0, right=n-1;
while (top <= bottom && left <= right) {
    for (int c=left; c<=right; c++) result.add(matrix[top][c]); top++;
    for (int r=top; r<=bottom; r++) result.add(matrix[r][right]); right--;
    if (top <= bottom) { for (int c=right; c>=left; c--) result.add(matrix[bottom][c]); bottom--; }
    if (left <= right) { for (int r=bottom; r>=top; r--) result.add(matrix[r][left]); left++; }
}
```

---

## 😵 Commonly Confused With

**vs Graph BFS/DFS**: Matrix problems ARE graph problems where each cell is a node and the 4 neighbors are edges. Deciding question: *Is the input a 2D grid (matrix BFS with row/col bounds) or an explicit adjacency list (graph BFS)?* The code is nearly identical; the main difference is bounds checking.

**vs Dynamic Programming on matrix**: Some matrix problems need DP (Unique Paths, Minimum Path Sum) — where you build answers from previous cells. Others need BFS/DFS traversal (Islands, Flood Fill). Deciding question: *Does the answer at cell (r,c) depend only on adjacent cells in a fixed direction (DP), or do you need to explore all reachable connected cells (BFS/DFS)?*

**vs Union-Find**: For counting connected components in a matrix, both BFS and Union-Find work. Deciding question: *Are connections added dynamically one-by-one (Union-Find), or is the grid given all at once (BFS is simpler)?*

---

## 14 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| Region counting / flood fill | LC 200, LC 695 (max area), LC 733 (flood fill), LC 1020 |
| Multi-source BFS | LC 542, LC 994 (rotting oranges), LC 1765 |
| Shortest path | LC 1091, LC 1293 (obstacles) |
| Spiral / rotation | LC 54, LC 59, LC 48 |
| In-place marking | LC 73, LC 289 (game of life) |
| Two-ocean BFS | LC 417 |
| DP on matrix | LC 221, LC 62, LC 63, LC 64 |
| Search in sorted matrix | LC 74, LC 240 (→ binary-search) |
