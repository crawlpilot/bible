# Topological Sort

**Category**: Trees & Graphs  
**Time Complexity**: O(V + E)  
**Space Complexity**: O(V)  
**Real-world connection**: Build systems (Make, Bazel, Gradle), Kubernetes pod scheduling, database migration ordering, task scheduling, package dependency resolution

---

## Core Insight

Topological sort produces a linear ordering of vertices in a Directed Acyclic Graph (DAG) such that for every directed edge `u → v`, vertex `u` comes before `v` in the ordering. It only exists when the graph has **no cycles** (i.e., is a DAG).

**Key properties**:
- A topological order may not be unique (if multiple nodes have in-degree 0 at any step)
- If a cycle exists, no topological order exists
- Every DAG has at least one topological order

---

## Algorithm 1: Kahn's Algorithm (BFS-based)

Intuition: repeatedly remove nodes that have no incoming edges (in-degree = 0) — they can safely come first.

```python
from collections import deque, defaultdict

def topological_sort_kahn(n: int, edges: list[tuple]) -> list[int]:
    """
    n: number of nodes (0-indexed: 0..n-1)
    edges: list of (u, v) meaning u must come before v
    Returns topological order, or [] if cycle detected.
    """
    graph = defaultdict(list)
    in_degree = [0] * n
    for u, v in edges:
        graph[u].append(v)
        in_degree[v] += 1

    # start with all nodes with no prerequisites
    queue = deque(i for i in range(n) if in_degree[i] == 0)
    order = []

    while queue:
        node = queue.popleft()
        order.append(node)
        for neighbor in graph[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    if len(order) != n:
        return []   # cycle detected: some nodes never reached in-degree 0
    return order
```

**Cycle detection**: if the result has fewer than `n` nodes, a cycle exists (those nodes never had in-degree 0).

**When to prefer Kahn's**: when you need to detect cycles as part of the result, when you want BFS-style level-by-level processing, or when you need all "ready" tasks at each step (task scheduling with parallelism).

---

## Algorithm 2: DFS Post-Order (Reverse DFS)

Intuition: in DFS, a node is fully processed (all descendants visited) when we backtrack from it. If we push nodes to a stack when they're fully processed, then reverse the stack, we get topological order.

```python
def topological_sort_dfs(n: int, edges: list[tuple]) -> list[int]:
    graph = defaultdict(list)
    for u, v in edges:
        graph[u].append(v)

    # 0 = unvisited, 1 = in-stack (currently being explored), 2 = done
    state = [0] * n
    result = []
    has_cycle = [False]

    def dfs(node: int):
        if has_cycle[0]:
            return
        state[node] = 1     # entering
        for neighbor in graph[node]:
            if state[neighbor] == 1:
                has_cycle[0] = True   # back edge → cycle
                return
            if state[neighbor] == 0:
                dfs(neighbor)
        state[node] = 2     # fully processed
        result.append(node) # post-order: append when done

    for i in range(n):
        if state[i] == 0:
            dfs(i)

    if has_cycle[0]:
        return []
    return result[::-1]     # reverse post-order = topological order
```

**When to prefer DFS**: when you need cycle detection mid-traversal, when implementing recursive graph algorithms, or when already using DFS for other graph properties.

---

## Algorithm 3: Parallel Topological Sort (Finding BFS Levels)

For task scheduling where tasks at the same level can run in parallel:

```python
def parallel_topo_sort(n: int, edges: list[tuple]) -> list[list[int]]:
    """Returns groups of tasks that can run in parallel."""
    graph = defaultdict(list)
    in_degree = [0] * n
    for u, v in edges:
        graph[u].append(v)
        in_degree[v] += 1

    queue = deque(i for i in range(n) if in_degree[i] == 0)
    levels = []

    while queue:
        level_size = len(queue)
        level = []
        for _ in range(level_size):
            node = queue.popleft()
            level.append(node)
            for neighbor in graph[node]:
                in_degree[neighbor] -= 1
                if in_degree[neighbor] == 0:
                    queue.append(neighbor)
        levels.append(level)

    total = sum(len(l) for l in levels)
    return levels if total == n else []
```

This is Kahn's algorithm with level-order BFS — identical to level-order tree traversal but on a DAG.

---

## Key Problems

| Problem | Key Insight |
|---------|-------------|
| Course Schedule (LC 207) | Can you take all courses? = does a topological order exist? = no cycle |
| Course Schedule II (LC 210) | Return the ordering = Kahn's or DFS post-order |
| Alien Dictionary (LC 269) | Build an edge u→v for each adjacent pair where chars first differ; topo sort the char graph |
| Minimum Time to Complete Tasks (LC 2050) | Topo sort + DP: `time[v] = max(time[v], time[u] + task_time[v])` |
| Find All Possible Recipes (LC 2115) | Ingredients = nodes; recipes = nodes; edge from ingredient to recipe |
| Parallel Courses (LC 1136) | Level-order topo sort; answer is number of levels |
| Sequence Reconstruction (LC 444) | Verify a unique topological order: at each step, exactly one node has in-degree 0 |

---

## Topological Sort + Dynamic Programming

Many optimization problems on DAGs combine topological sort with DP: process nodes in topological order and update downstream nodes.

```python
def longest_path_dag(n: int, edges: list[tuple]) -> int:
    """Longest path (number of edges) in a DAG."""
    graph = defaultdict(list)
    in_degree = [0] * n
    for u, v in edges:
        graph[u].append(v)
        in_degree[v] += 1

    # Kahn's
    queue = deque(i for i in range(n) if in_degree[i] == 0)
    dp = [0] * n

    while queue:
        node = queue.popleft()
        for neighbor in graph[node]:
            dp[neighbor] = max(dp[neighbor], dp[node] + 1)
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    return max(dp)
```

**Pattern**: topological order ensures that when we process node `v`, all predecessors `u` have already been processed. This is the DAG analogue of the DP subproblem ordering condition.

---

## Real-World System Design Connections

### Build Systems (Bazel, Gradle, Make)
Every build system maintains a dependency DAG of targets (libraries, binaries, test suites). Topological sort determines build order: compile libraries before the binaries that depend on them. Bazel further uses the parallel topo sort variant to find which targets can build in parallel at each level, enabling distributed builds.

Cycle detection is critical: a circular dependency (`A depends on B; B depends on A`) is detected as a graph cycle and reported as an error during dependency resolution.

### Kubernetes Pod Scheduling
Kubernetes Helm charts define dependencies between resources (e.g., a Deployment depends on a ConfigMap and a Secret). Helm uses topological sort to determine installation order. A misconfigured chart with circular dependencies triggers a cycle detection error before any resources are created.

### Database Schema Migrations
Flyway and Liquibase apply migrations in topological order. Each migration declares which previous migrations it depends on (via version number or explicit dependency). The migration DAG is topologically sorted to ensure migrations are applied in a consistent order that doesn't violate foreign key constraints.

### Package Managers (npm, pip, cargo)
`npm install` resolves a package dependency tree. The resolution algorithm performs a topological sort to determine installation order. Circular dependencies are either rejected (Cargo) or handled via special cases (npm's symlink trick for peer dependencies).

### Apache Airflow DAG Execution
Each Airflow DAG is literally a Directed Acyclic Graph of tasks. The scheduler uses topological sort to determine which tasks can be submitted to workers at each step. The parallel variant (level-order) enables Airflow to submit all tasks with satisfied dependencies simultaneously.

---

## Comparison: Kahn's vs DFS

| Aspect | Kahn's (BFS) | DFS (post-order) |
|--------|-------------|-----------------|
| Approach | Remove in-degree-0 nodes iteratively | Post-order traversal; reverse |
| Cycle detection | `len(result) < n` at end | Back edge during DFS (`state == 1`) |
| Parallel levels | Natural (level-order BFS) | Requires extra tracking |
| Lexicographically smallest | Use min-heap instead of queue | Harder to achieve |
| Implementation simplicity | Slightly more code | Recursive is compact |
| Stack overflow risk | None | Yes, for deep graphs |

**Interview default**: Kahn's algorithm. It's more intuitive to explain, natural for cycle detection, and easier to extend for parallel scheduling.

---

## Common Mistakes

1. **Not handling disconnected graphs**: if the graph has multiple components, initialize the queue with ALL nodes that have in-degree 0, not just node 0.

2. **Confusing in-degree and out-degree**: in-degree of `v` = number of edges pointing INTO `v`. In Kahn's, you decrement `in_degree[v]` for each outgoing edge of the processed node, not incoming edges.

3. **Using DFS without the 3-color state**: a 2-color visited set (visited/unvisited) cannot distinguish a back edge (cycle) from a cross edge (already visited via a different path). You need 3 states: unvisited (0), in-stack (1), done (2). Back edge: neighbor is in-stack. Cross edge: neighbor is done.

4. **Topological sort on undirected graphs**: doesn't work. Topological sort is defined only for directed acyclic graphs. An undirected graph is treated as a directed graph with edges in both directions, which always creates cycles.

5. **Expecting a unique ordering**: most topological sorts have multiple valid orderings. If the problem requires a specific ordering (e.g., lexicographically smallest), you need a min-heap in Kahn's, not a regular queue.
