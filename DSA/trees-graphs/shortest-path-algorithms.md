# Shortest Path Algorithms

**Category**: Trees & Graphs  
**Real-world connection**: GPS navigation, network routing (OSPF/BGP), social graph distance, recommendation engines, game AI pathfinding

---

## Algorithm Selection

| Algorithm | Graph Type | Edge Weights | Time Complexity | Use When |
|-----------|-----------|--------------|----------------|---------|
| **BFS** | Unweighted | All = 1 | O(V + E) | Fewest hops, grid mazes |
| **Dijkstra** | Directed/Undirected | Non-negative | O((V+E) log V) | Positive weights, GPS |
| **Bellman-Ford** | Directed | Any (negative ok) | O(VE) | Negative weights, detect negative cycles |
| **SPFA** | Directed | Any | O(VE) worst, O(V+E) avg | Bellman-Ford with queue optimization |
| **A\*** | Directed | Non-negative | O(E log V) with good heuristic | GPS with heuristic estimate |
| **Floyd-Warshall** | Any | Any | O(V³) | All-pairs shortest path, small graphs |
| **0-1 BFS** | Directed | 0 or 1 only | O(V + E) | Mixed 0/1 edge costs |

---

## Dijkstra's Algorithm

**Invariant**: when a node is popped from the min-heap, its distance is finalized — no shorter path exists.

```python
import heapq
from collections import defaultdict

def dijkstra(n: int, edges: list[tuple], src: int) -> list[int]:
    """
    n: number of nodes (0-indexed)
    edges: list of (u, v, weight)
    Returns: dist[v] = shortest distance from src to v; float('inf') if unreachable
    """
    graph = defaultdict(list)
    for u, v, w in edges:
        graph[u].append((v, w))

    dist = [float('inf')] * n
    dist[src] = 0
    heap = [(0, src)]   # (distance, node)

    while heap:
        d, u = heapq.heappop(heap)
        if d > dist[u]:
            continue    # stale entry — skip
        for v, w in graph[u]:
            new_dist = dist[u] + w
            if new_dist < dist[v]:
                dist[v] = new_dist
                heapq.heappush(heap, (new_dist, v))

    return dist
```

**Critical detail**: the `if d > dist[u]: continue` check skips stale heap entries. Without it, you process a node multiple times and get correct results but degrade to O(E log E) with E heap pushes.

**When Dijkstra fails**: negative weight edges. A negative edge `(u, v, -5)` means processing `v` later (after `u` is finalized) could improve `v`'s distance — violating Dijkstra's invariant.

### Dijkstra with Path Reconstruction

```python
def dijkstra_with_path(n, edges, src, dst):
    graph = defaultdict(list)
    for u, v, w in edges:
        graph[u].append((v, w))

    dist = [float('inf')] * n
    prev = [-1] * n
    dist[src] = 0
    heap = [(0, src)]

    while heap:
        d, u = heapq.heappop(heap)
        if d > dist[u]:
            continue
        for v, w in graph[u]:
            if dist[u] + w < dist[v]:
                dist[v] = dist[u] + w
                prev[v] = u
                heapq.heappush(heap, (dist[v], v))

    # Reconstruct path
    path = []
    node = dst
    while node != -1:
        path.append(node)
        node = prev[node]
    return dist[dst], path[::-1]
```

---

## Bellman-Ford Algorithm

Relax all edges V-1 times. After V-1 relaxations, all shortest paths are found (shortest simple path has at most V-1 edges). A V-th relaxation that still improves a distance → negative cycle exists.

```python
def bellman_ford(n: int, edges: list[tuple], src: int) -> tuple[list[int], bool]:
    """
    Returns (dist, has_negative_cycle).
    dist[v] = shortest distance from src; float('inf') if unreachable.
    """
    dist = [float('inf')] * n
    dist[src] = 0

    for _ in range(n - 1):
        relaxed = False
        for u, v, w in edges:
            if dist[u] != float('inf') and dist[u] + w < dist[v]:
                dist[v] = dist[u] + w
                relaxed = True
        if not relaxed:
            break   # early termination: no improvement in this pass

    # Check for negative cycles
    has_negative_cycle = False
    for u, v, w in edges:
        if dist[u] != float('inf') and dist[u] + w < dist[v]:
            has_negative_cycle = True
            break

    return dist, has_negative_cycle
```

**When to use**: negative weight edges, detecting negative cycles (arbitrage detection in currency exchange, bellman-ford on currency graph).

---

## Floyd-Warshall (All-Pairs Shortest Path)

Computes shortest path between ALL pairs of nodes in O(V³).

```python
def floyd_warshall(n: int, edges: list[tuple]) -> list[list[float]]:
    dist = [[float('inf')] * n for _ in range(n)]
    for i in range(n):
        dist[i][i] = 0
    for u, v, w in edges:
        dist[u][v] = w

    for k in range(n):          # intermediate node
        for i in range(n):      # source
            for j in range(n):  # destination
                if dist[i][k] + dist[k][j] < dist[i][j]:
                    dist[i][j] = dist[i][k] + dist[k][j]

    # Negative cycle detection: if dist[i][i] < 0 for any i
    return dist
```

**When to use**: V is small (< 300), need all-pairs distances, detecting negative cycles, finding transitive closure.  
**Don't use**: V > 500 (O(V³) becomes infeasible), single-source queries (use Dijkstra instead).

---

## A* Search

Dijkstra guided by a heuristic `h(v)` estimating distance from `v` to the goal. Explores nodes in order of `f(v) = g(v) + h(v)` where `g(v)` is the actual distance from source.

```python
def a_star(graph, src, dst, heuristic):
    """heuristic(v) must be admissible: never overestimate actual distance."""
    dist = defaultdict(lambda: float('inf'))
    dist[src] = 0
    heap = [(heuristic(src), 0, src)]   # (f=g+h, g, node)

    while heap:
        f, g, u = heapq.heappop(heap)
        if u == dst:
            return g
        if g > dist[u]:
            continue
        for v, w in graph[u]:
            new_g = g + w
            if new_g < dist[v]:
                dist[v] = new_g
                heapq.heappush(heap, (new_g + heuristic(v), new_g, v))
    return float('inf')
```

**Admissible heuristic**: must never overestimate. Common choices:
- Grid graphs: Manhattan distance `|x1-x2| + |y1-y2|` (4-directional) or Euclidean (8-directional)
- Road networks: straight-line (great-circle) distance

**When A* beats Dijkstra**: when the heuristic effectively prunes large portions of the graph. For a 1000×1000 grid with a good Manhattan heuristic, A* explores far fewer nodes than Dijkstra.

---

## Grid Shortest Path Variants

### Standard BFS (unweighted grid)
```python
def bfs_grid(grid, sr, sc, er, ec):
    from collections import deque
    m, n = len(grid), len(grid[0])
    queue = deque([(sr, sc, 0)])
    visited = {(sr, sc)}
    while queue:
        r, c, dist = queue.popleft()
        if r == er and c == ec:
            return dist
        for dr, dc in [(0,1),(0,-1),(1,0),(-1,0)]:
            nr, nc = r+dr, c+dc
            if 0 <= nr < m and 0 <= nc < n and (nr,nc) not in visited and grid[nr][nc] != '#':
                visited.add((nr, nc))
                queue.append((nr, nc, dist+1))
    return -1
```

### Dijkstra on grid (weighted cells)
When each cell has a traversal cost, use Dijkstra with the grid as an implicit graph:
```python
def dijkstra_grid(grid):
    m, n = len(grid), len(grid[0])
    dist = [[float('inf')] * n for _ in range(m)]
    dist[0][0] = grid[0][0]
    heap = [(grid[0][0], 0, 0)]
    while heap:
        d, r, c = heapq.heappop(heap)
        if d > dist[r][c]:
            continue
        for dr, dc in [(0,1),(0,-1),(1,0),(-1,0)]:
            nr, nc = r+dr, c+dc
            if 0 <= nr < m and 0 <= nc < n:
                nd = dist[r][c] + grid[nr][nc]
                if nd < dist[nr][nc]:
                    dist[nr][nc] = nd
                    heapq.heappush(heap, (nd, nr, nc))
    return dist[m-1][n-1]
```

---

## Key Problems Reference

| Problem | Algorithm | Key Detail |
|---------|-----------|-----------|
| Network Delay Time (LC 743) | Dijkstra | Single-source, non-negative weights |
| Cheapest Flights Within K Stops (LC 787) | Bellman-Ford (K iterations) | K stops = K+1 edges; BF with K passes |
| Path With Minimum Effort (LC 1631) | Dijkstra (max edge weight) | Minimize maximum edge traversed |
| Swim in Rising Water (LC 778) | Dijkstra / binary search + BFS | Minimize maximum height |
| Find the City With Smallest Number of Neighbors (LC 1334) | Floyd-Warshall | All-pairs within threshold |
| Shortest Path in Binary Matrix (LC 1091) | BFS | 8-directional unweighted |
| Minimum Cost to Reach Destination in Time (LC 1928) | DP + Dijkstra | State = (node, time) |
| The Maze II (LC 505) | Dijkstra | Ball rolls until hitting wall |
| K Shortest Paths | Modified Dijkstra | Allow each node to be popped k times |

---

## Real-World System Design Connections

### GPS Navigation (A* / Dijkstra)
Google Maps and Apple Maps use bidirectional Dijkstra with preprocessing (Contraction Hierarchies) for road networks with 10⁸+ nodes. Contraction Hierarchies preprocess the graph by "contracting" low-importance nodes, allowing queries to run in milliseconds.

A* with great-circle distance heuristic is used for route finding in airspace systems (FAA/Eurocontrol).

### Network Routing Protocols
- **OSPF** (link-state routing): each router computes shortest paths with Dijkstra on the full network topology. Convergence time is O(E log V) per router after a topology change.
- **BGP** (path vector): uses Bellman-Ford-inspired approach. BGP doesn't guarantee loop-free paths at convergence — it uses policies and AS-path attributes to prevent routing loops, unlike pure Bellman-Ford.

### Social Graph Degrees of Separation (BFS)
LinkedIn's "2nd-degree connections" is BFS limited to depth 2. For friend-of-friend at scale, LinkedIn uses a distributed BFS implemented on their Voldemort (distributed key-value store) + Kafka pipeline. The algorithm itself is BFS; the infrastructure is the interesting part.

### Game AI Pathfinding (A*)
Every AAA game engine uses A* for NPC pathfinding on navigation meshes. The heuristic is typically Euclidean distance in 3D space. Hierarchical A* (HPA*) precomputes paths between "waypoints" to handle large open worlds.

### Currency Arbitrage Detection (Bellman-Ford)
In forex trading, edge weight = `-log(exchange_rate)`. Shortest path in this log-transformed graph = maximum currency product. A negative cycle (Bellman-Ford cycle detection) indicates an arbitrage opportunity: a cycle of currency exchanges that returns profit. This is directly detected by Bellman-Ford's V-th iteration check.

---

## Common Mistakes

1. **Using Dijkstra with negative weights**: guaranteed to produce wrong answers. If you have negative weights, Bellman-Ford or rethink the graph model (can you offset all edges to be non-negative?).

2. **Not skipping stale heap entries**: without `if d > dist[u]: continue`, Dijkstra processes outdated heap entries, which is O(E log E) instead of O((V+E) log V) and can produce wrong results if edges are re-processed after a node is "finalized."

3. **Floyd-Warshall loop order**: the outer loop MUST be the intermediate node `k`, not source or destination. Getting the loop order wrong produces incorrect distances.

4. **Bellman-Ford early termination**: adding early termination (`if not relaxed: break`) is an optimization but must apply to the entire pass over all edges, not individual edges. Breaking inside the edge loop is wrong.

5. **A* with inadmissible heuristic**: if `h(v)` can overestimate, A* may not find the shortest path (it might skip the optimal path because a node on it looks "too far" from the goal). Always verify admissibility.

6. **BFS for weighted graphs**: BFS gives the fewest-hops path (unweighted), not the minimum-weight path. Using BFS on a graph with varying edge weights is a classic wrong answer.
