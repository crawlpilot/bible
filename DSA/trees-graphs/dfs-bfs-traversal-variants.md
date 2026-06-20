# DFS and BFS Traversal Variants

**Category**: Trees & Graphs  
**Time Complexity**: O(V + E) for both  
**Space Complexity**: O(V) — BFS for queue width, DFS for call stack depth  
**Real-world connection**: DNS resolution, web crawlers, social graph traversal, dependency resolution, Kubernetes pod scheduling

---

## Core Decision: DFS vs BFS

| Property | DFS | BFS |
|----------|-----|-----|
| Explores | Deep before wide | Wide before deep |
| Finds shortest path | No (unweighted) | Yes (unweighted) |
| Memory | O(depth) — good for narrow-deep graphs | O(width) — bad for wide graphs |
| Implementation | Recursive or explicit stack | Queue |
| When to use | Topological sort, cycle detection, connected components, all paths, backtracking | Shortest path (unweighted), level-order, nearest neighbor, "minimum steps" |

**Rule of thumb**: if the answer is "the shortest X," use BFS. If the answer is "does X exist" or "all X," start with DFS.

---

## BFS Patterns

### Pattern 1: Standard BFS (shortest path, unweighted)

```python
from collections import deque

def bfs_shortest_path(graph: dict, start: int, end: int) -> int:
    if start == end:
        return 0
    visited = {start}
    queue = deque([(start, 0)])
    while queue:
        node, dist = queue.popleft()
        for neighbor in graph[node]:
            if neighbor == end:
                return dist + 1
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, dist + 1))
    return -1  # unreachable
```

**Key invariant**: when a node is first dequeued, its distance is final. Never update a node's distance after first visit.

### Pattern 2: Level-Order BFS

Process all nodes at depth d before any node at depth d+1. Used for level-by-level tree problems.

```python
def level_order(root) -> list[list[int]]:
    if not root:
        return []
    result = []
    queue = deque([root])
    while queue:
        level_size = len(queue)     # snapshot before expansion
        level = []
        for _ in range(level_size):
            node = queue.popleft()
            level.append(node.val)
            if node.left:
                queue.append(node.left)
            if node.right:
                queue.append(node.right)
        result.append(level)
    return result
```

**Trap**: take `level_size = len(queue)` before the inner loop, not inside it.

### Pattern 3: Multi-Source BFS

Start BFS from multiple source nodes simultaneously. Used when the problem has multiple valid "origins" (e.g., "nearest cell of type X").

```python
def multi_source_bfs(grid: list[list[int]]) -> list[list[int]]:
    m, n = len(grid), len(grid[0])
    dist = [[float('inf')] * n for _ in range(m)]
    queue = deque()
    for r in range(m):
        for c in range(n):
            if grid[r][c] == 1:   # source cells
                dist[r][c] = 0
                queue.append((r, c))
    while queue:
        r, c = queue.popleft()
        for dr, dc in [(0,1),(0,-1),(1,0),(-1,0)]:
            nr, nc = r + dr, c + dc
            if 0 <= nr < m and 0 <= nc < n and dist[nr][nc] == float('inf'):
                dist[nr][nc] = dist[r][c] + 1
                queue.append((nr, nc))
    return dist
```

### Pattern 4: 0-1 BFS (Deque BFS)

When edge weights are 0 or 1, use a deque: push weight-0 edges to the front, weight-1 edges to the back. Achieves O(V + E) vs Dijkstra's O((V+E) log V).

```python
def zero_one_bfs(graph, start, end):
    from collections import deque
    dist = {start: 0}
    dq = deque([start])
    while dq:
        node = dq.popleft()
        for neighbor, weight in graph[node]:
            new_dist = dist[node] + weight
            if neighbor not in dist or new_dist < dist[neighbor]:
                dist[neighbor] = new_dist
                if weight == 0:
                    dq.appendleft(neighbor)  # free edge — explore first
                else:
                    dq.append(neighbor)
    return dist.get(end, float('inf'))
```

---

## DFS Patterns

### Pattern 1: Iterative DFS (explicit stack)

```python
def dfs_iterative(graph: dict, start: int) -> list[int]:
    visited = set()
    stack = [start]
    order = []
    while stack:
        node = stack.pop()
        if node in visited:
            continue
        visited.add(node)
        order.append(node)
        for neighbor in graph[node]:  # push in reverse to match recursive order
            if neighbor not in visited:
                stack.append(neighbor)
    return order
```

**When to use iterative over recursive**: deep graphs where Python's recursion limit (~1000) would be hit. Always use iterative for grid-based DFS on large inputs.

### Pattern 2: DFS with Pre/Post-Order (for cycle detection and topological sort)

```python
def dfs_with_state(graph: dict, node: int,
                   state: dict,    # 0=unvisited, 1=in-stack, 2=done
                   result: list) -> bool:
    state[node] = 1  # entering
    for neighbor in graph[node]:
        if state[neighbor] == 1:
            return True    # back edge → cycle
        if state[neighbor] == 0:
            if dfs_with_state(graph, neighbor, state, result):
                return True
    state[node] = 2  # done
    result.append(node)   # post-order → reverse for topological sort
    return False
```

### Pattern 3: DFS on Grid (Flood Fill / Island Counting)

```python
def num_islands(grid: list[list[str]]) -> int:
    if not grid:
        return 0
    m, n = len(grid), len(grid[0])
    count = 0

    def dfs(r: int, c: int):
        if r < 0 or r >= m or c < 0 or c >= n or grid[r][c] != '1':
            return
        grid[r][c] = '#'   # mark visited in-place
        dfs(r+1, c); dfs(r-1, c); dfs(r, c+1); dfs(r, c-1)

    for r in range(m):
        for c in range(n):
            if grid[r][c] == '1':
                dfs(r, c)
                count += 1
    return count
```

**Marking in-place vs. visited set**: marking in-place saves memory but mutates the input. Use a visited set if the original grid must be preserved.

### Pattern 4: DFS for All Paths / Backtracking

```python
def all_paths(graph: dict, start: int, end: int) -> list[list[int]]:
    result = []

    def dfs(node, path):
        if node == end:
            result.append(list(path))
            return
        for neighbor in graph[node]:
            if neighbor not in path:   # avoid cycles in undirected graph
                path.append(neighbor)
                dfs(neighbor, path)
                path.pop()             # backtrack

    dfs(start, [start])
    return result
```

---

## Problem Classification

| Problem | Algorithm | Why |
|---------|-----------|-----|
| Shortest path (unweighted) | BFS | First visit = shortest |
| Shortest path (weighted, non-negative) | Dijkstra | Greedy by distance |
| Shortest path (0/1 weights) | 0-1 BFS | Deque trick |
| Shortest path (negative weights) | Bellman-Ford | Relax V-1 times |
| Topological sort | DFS (post-order reversed) or BFS (Kahn's) | Both work |
| Cycle detection (directed) | DFS with 3-color state | Back edge = cycle |
| Cycle detection (undirected) | BFS/DFS tracking parent | Cross edge to visited ≠ parent |
| Connected components | DFS/BFS from each unvisited node | Count starts |
| Bipartite check | BFS 2-coloring | Odd cycle = not bipartite |
| Strongly connected components | Kosaraju's or Tarjan's | DFS twice or low-link |
| Nearest X in grid | Multi-source BFS | All X as sources |

---

## Real-World System Design Connections

### Web Crawler (BFS)
A web crawler is a distributed multi-source BFS over the URL graph. Frontiers are managed as queues partitioned by domain. Crawl depth limits prevent DFS from going infinitely deep on adversarial sites (e.g., calendar generators that produce infinite URLs). BFS ensures popular/shallow pages are crawled before deep obscure ones.

### DNS Resolution (DFS)
DNS resolution is a depth-first traversal of the DNS delegation tree: root → TLD → authoritative → record. Each level delegates down. DNSSEC adds signature verification at each level — a decorator on each DFS step.

### Social Graph — Degrees of Separation (BFS)
LinkedIn's "people you may know" and "2nd-degree connections" are BFS limited to depth 2. Meta's friend-of-friend queries use BFS on their TAO graph store. BFS depth-2 on a graph with average degree 150 explores 150² = 22,500 nodes per query — this is why these systems need graph databases with adjacency-list storage (not tables with JOINs).

### Kubernetes Dependency Resolution (Topological Sort via DFS)
Helm chart dependencies form a DAG. Installation order is a topological sort of that DAG. Cycle detection prevents circular dependencies. This is DFS post-order in disguise.

### Database Query Plan Optimization (DFS + Cost)
A SQL query tree is traversed DFS to apply transformation rules (push-down predicates, join reordering). Each DFS visit applies a rule and recurses. Dynamic programming memoizes subtree costs to avoid re-evaluating identical subplans.

---

## Common Mistakes

1. **BFS without a visited set**: queuing the same node multiple times causes O(V²) or worse behavior and infinite loops in cyclic graphs. Always add to `visited` **when enqueuing**, not when dequeuing.

2. **DFS misidentifying cross edges as back edges**: in undirected graphs, the edge back to the parent is not a cycle. Track the parent node and skip it: `if neighbor != parent: dfs(neighbor)`.

3. **Level-order BFS inner loop size**: computing `len(queue)` inside the inner loop gives the wrong level size as the queue grows. Snapshot it before the loop.

4. **Recursive DFS stack overflow**: Python's default recursion limit is 998. For large grids (1000×1000 = 10⁶ cells), always use iterative DFS with an explicit stack.

5. **Multi-source BFS missing initial sources**: if you forget to add all source nodes to the queue before starting BFS, only one source is explored — the others are treated as regular nodes.

6. **Using DFS for shortest path on unweighted graphs**: DFS finds *a* path, not the *shortest* path. This is one of the most common wrong answers in graph problems.
