# Graphs

> A graph is nodes (vertices) + edges (connections). The fundamental questions: **Can I reach X from Y? What is the shortest path? Are there cycles? What order should tasks run in?**

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Input has **explicit edges** (adjacency list, matrix, edge list) OR **implicit edges** (grid moves, word ladder transformations)
- [ ] Problem involves **reachability, connectivity, ordering, or shortest path**
- [ ] Structure may have **cycles** (unlike trees)
- [ ] Nodes may have **weights** on edges

**Trigger phrases**: "number of islands", "course schedule", "clone graph", "word ladder", "shortest path", "all paths", "critical connections", "redundant connection", "minimum spanning tree"

---

## 2 — Flavor Detection

| Flavor | Signal | Algorithm |
|--------|--------|-----------|
| **Connected components** | Count groups, number of islands | DFS/BFS + visited set |
| **Shortest path (unweighted)** | Min steps, min moves | BFS (level = distance) |
| **Shortest path (weighted)** | Min cost, weighted edges | Dijkstra (min-heap) |
| **Cycle detection (directed)** | "Can you finish all courses?" | DFS with 3-color: WHITE/GRAY/BLACK |
| **Cycle detection (undirected)** | "Is there a redundant edge?" | Union-Find or DFS with parent tracking |
| **Topological sort** | Dependency ordering, prerequisites | Kahn's BFS or DFS postorder |
| **All paths** | Enumerate every valid route | DFS + backtracking + visited set |
| **Minimum spanning tree** | Connect all nodes minimum cost | Kruskal (sort edges + Union-Find) |
| **Bipartite check** | 2-colorable, "can divide into 2 groups" | BFS/DFS 2-coloring |

---

## 3 — Graph Representations in Java

```java
// Adjacency list — most common in interviews
int n = 5;
List<List<Integer>> adj = new ArrayList<>();
for (int i = 0; i < n; i++) adj.add(new ArrayList<>());
adj.get(0).add(1); adj.get(1).add(2);  // 0→1→2

// For weighted graphs: List<int[]> where int[] = {neighbor, weight}
List<List<int[]>> adjW = new ArrayList<>();
for (int i = 0; i < n; i++) adjW.add(new ArrayList<>());
adjW.get(0).add(new int[]{1, 4});  // edge 0→1 with weight 4

// Grid as implicit graph (4-directional)
int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
// neighbor of (r,c): (r+d[0], c+d[1]) for d in dirs
```

---

## 4 — BFS — Shortest Path (Unweighted)

**Core rule**: BFS explores level by level → the first time you reach a node, you've found the shortest path.

```
Step 1: Start with source in queue, mark visited
Step 2: While queue not empty:
        a. Poll node
        b. If it's the target → return current distance
        c. For each unvisited neighbor:
              mark visited, add to queue with distance + 1
Step 3: Return -1 (unreachable)
```

**Java template**:
```java
int bfsShortestPath(List<List<Integer>> adj, int src, int dst, int n) {
    boolean[] visited = new boolean[n];
    Queue<int[]> queue = new LinkedList<>();  // [node, distance]
    queue.offer(new int[]{src, 0});
    visited[src] = true;

    while (!queue.isEmpty()) {
        int[] curr = queue.poll();
        int node = curr[0], dist = curr[1];

        if (node == dst) return dist;

        for (int neighbor : adj.get(node)) {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                queue.offer(new int[]{neighbor, dist + 1});
            }
        }
    }
    return -1;
}
```

**Number of Islands (LC 200) — BFS flood fill**:
```java
int numIslands(char[][] grid) {
    int m = grid.length, n = grid[0].length, count = 0;
    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};

    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            if (grid[i][j] == '1') {
                count++;
                // BFS to mark all connected land
                Queue<int[]> q = new LinkedList<>();
                q.offer(new int[]{i, j});
                grid[i][j] = '0';   // mark visited by overwriting

                while (!q.isEmpty()) {
                    int[] cell = q.poll();
                    for (int[] d : dirs) {
                        int r = cell[0] + d[0], c = cell[1] + d[1];
                        if (r >= 0 && r < m && c >= 0 && c < n && grid[r][c] == '1') {
                            grid[r][c] = '0';
                            q.offer(new int[]{r, c});
                        }
                    }
                }
            }
        }
    }
    return count;
}
```

**Word Ladder (LC 127) — BFS on implicit graph**:
```java
int ladderLength(String beginWord, String endWord, List<String> wordList) {
    Set<String> wordSet = new HashSet<>(wordList);
    if (!wordSet.contains(endWord)) return 0;

    Queue<String> queue = new LinkedList<>();
    queue.offer(beginWord);
    int level = 1;

    while (!queue.isEmpty()) {
        int size = queue.size();
        for (int i = 0; i < size; i++) {
            String word = queue.poll();
            char[] chars = word.toCharArray();
            for (int j = 0; j < chars.length; j++) {
                char orig = chars[j];
                for (char c = 'a'; c <= 'z'; c++) {
                    chars[j] = c;
                    String next = new String(chars);
                    if (next.equals(endWord)) return level + 1;
                    if (wordSet.remove(next)) queue.offer(next);  // remove = mark visited
                }
                chars[j] = orig;
            }
        }
        level++;
    }
    return 0;
}
```

---

## 5 — Dijkstra — Shortest Path (Weighted)

**Core rule**: Always expand the node with the SMALLEST current distance — use a min-heap.

```
Step 1: dist[src] = 0, all others = ∞
        Offer [0, src] to min-heap (priority = distance)
Step 2: While heap not empty:
        a. Poll [d, node] with smallest d
        b. If d > dist[node]: skip (stale entry)
        c. For each neighbor with edge weight w:
              if dist[node] + w < dist[neighbor]:
                  dist[neighbor] = dist[node] + w
                  offer [dist[neighbor], neighbor] to heap
Step 3: Return dist[dst]
```

**Java template**:
```java
int[] dijkstra(List<List<int[]>> adj, int src, int n) {
    int[] dist = new int[n];
    Arrays.fill(dist, Integer.MAX_VALUE);
    dist[src] = 0;

    // PriorityQueue: [distance, node]
    PriorityQueue<int[]> pq = new PriorityQueue<>(Comparator.comparingInt(a -> a[0]));
    pq.offer(new int[]{0, src});

    while (!pq.isEmpty()) {
        int[] curr = pq.poll();
        int d = curr[0], node = curr[1];

        if (d > dist[node]) continue;  // stale entry — skip

        for (int[] edge : adj.get(node)) {
            int neighbor = edge[0], weight = edge[1];
            if (dist[node] + weight < dist[neighbor]) {
                dist[neighbor] = dist[node] + weight;
                pq.offer(new int[]{dist[neighbor], neighbor});
            }
        }
    }
    return dist;  // dist[i] = shortest distance from src to i
}
```

**Complexity**: O((V + E) log V)

---

## 6 — Topological Sort

### Kahn's Algorithm (BFS — preferred for cycle detection)

```
Step 1: Compute in-degree for every node
Step 2: Add all nodes with in-degree = 0 to queue
Step 3: While queue not empty:
        a. Poll node, add to result
        b. For each neighbor: in-degree[neighbor]--
              If in-degree[neighbor] == 0: add to queue
Step 4: If result.size() != n → cycle exists (not all nodes processed)
```

**Course Schedule II (LC 210)**:
```java
int[] findOrder(int numCourses, int[][] prerequisites) {
    List<List<Integer>> adj = new ArrayList<>();
    int[] indegree = new int[numCourses];
    for (int i = 0; i < numCourses; i++) adj.add(new ArrayList<>());

    for (int[] pre : prerequisites) {
        adj.get(pre[1]).add(pre[0]);   // pre[1] must come before pre[0]
        indegree[pre[0]]++;
    }

    Queue<Integer> queue = new LinkedList<>();
    for (int i = 0; i < numCourses; i++)
        if (indegree[i] == 0) queue.offer(i);

    int[] order = new int[numCourses];
    int idx = 0;

    while (!queue.isEmpty()) {
        int course = queue.poll();
        order[idx++] = course;
        for (int next : adj.get(course)) {
            if (--indegree[next] == 0) queue.offer(next);
        }
    }

    return idx == numCourses ? order : new int[]{};  // empty = cycle detected
}
```

### DFS Topological Sort (postorder)
```java
// After DFS of all neighbors completes, push current node to a stack
// Reverse the stack at the end → topological order
```

---

## 7 — Cycle Detection in Directed Graph (DFS 3-color)

**WHITE (0)** = unvisited, **GRAY (1)** = in current DFS path (being processed), **BLACK (2)** = fully processed.  
A GRAY → GRAY back edge means a cycle.

```java
// Returns true if cycle found
boolean hasCycle(int node, List<List<Integer>> adj, int[] color) {
    color[node] = 1;  // GRAY: currently exploring

    for (int neighbor : adj.get(node)) {
        if (color[neighbor] == 1) return true;   // back edge → cycle
        if (color[neighbor] == 0 && hasCycle(neighbor, adj, color)) return true;
    }

    color[node] = 2;  // BLACK: fully explored
    return false;
}

boolean canFinish(int n, int[][] prerequisites) {
    List<List<Integer>> adj = new ArrayList<>();
    for (int i = 0; i < n; i++) adj.add(new ArrayList<>());
    for (int[] pre : prerequisites) adj.get(pre[1]).add(pre[0]);

    int[] color = new int[n];   // 0=white, 1=gray, 2=black
    for (int i = 0; i < n; i++)
        if (color[i] == 0 && hasCycle(i, adj, color)) return false;
    return true;
}
```

---

## 8 — Union-Find (Disjoint Set Union)

**Use for**: undirected cycle detection, connected components, redundant connections, dynamic connectivity.

```java
class UnionFind {
    int[] parent, rank;

    UnionFind(int n) {
        parent = new int[n]; rank = new int[n];
        for (int i = 0; i < n; i++) parent[i] = i;
    }

    int find(int x) {
        if (parent[x] != x) parent[x] = find(parent[x]);  // path compression
        return parent[x];
    }

    boolean union(int x, int y) {
        int px = find(x), py = find(y);
        if (px == py) return false;   // already connected → adding edge creates cycle
        if (rank[px] < rank[py]) { int tmp = px; px = py; py = tmp; }
        parent[py] = px;
        if (rank[px] == rank[py]) rank[px]++;
        return true;
    }
}

// LC 684 — Redundant Connection
int[] findRedundantConnection(int[][] edges) {
    UnionFind uf = new UnionFind(edges.length + 1);
    for (int[] edge : edges)
        if (!uf.union(edge[0], edge[1]))
            return edge;   // union returned false → would create cycle → redundant edge
    return new int[]{};
}
```

**Complexity**: O(α(n)) per operation (essentially O(1) with path compression + union by rank).

---

## 9 — Bipartite Check (2-Coloring)

**A graph is bipartite if and only if it has no odd-length cycle.**  
Try to 2-color using BFS; if a conflict is found → not bipartite.

```java
boolean isBipartite(int[][] graph) {
    int n = graph.length;
    int[] color = new int[n];   // 0=unvisited, 1=red, -1=blue
    Arrays.fill(color, 0);

    for (int start = 0; start < n; start++) {
        if (color[start] != 0) continue;    // already colored
        Queue<Integer> queue = new LinkedList<>();
        queue.offer(start);
        color[start] = 1;

        while (!queue.isEmpty()) {
            int node = queue.poll();
            for (int neighbor : graph[node]) {
                if (color[neighbor] == 0) {
                    color[neighbor] = -color[node];  // opposite color
                    queue.offer(neighbor);
                } else if (color[neighbor] == color[node]) {
                    return false;   // same color on adjacent nodes → conflict
                }
            }
        }
    }
    return true;
}
```

---

## 10 — All Paths DFS + Backtracking (LC 797)

```java
List<List<Integer>> allPathsSourceTarget(int[][] graph) {
    List<List<Integer>> res = new ArrayList<>();
    List<Integer> path = new ArrayList<>();
    path.add(0);
    dfs(graph, 0, path, res);
    return res;
}

void dfs(int[][] graph, int node, List<Integer> path, List<List<Integer>> res) {
    if (node == graph.length - 1) { res.add(new ArrayList<>(path)); return; }

    for (int next : graph[node]) {
        path.add(next);
        dfs(graph, next, path, res);
        path.remove(path.size() - 1);  // backtrack
    }
}
```

---

## 11 — Algorithm Selection Guide

```
Q: Is the graph weighted?
  No  → BFS for shortest path
  Yes → Dijkstra for shortest path (non-negative weights)
       → Bellman-Ford for negative weights

Q: Is the graph directed?
  Yes → DFS 3-color for cycle detection
      → Kahn's BFS for topological sort
  No  → Union-Find for cycle detection / components
      → BFS/DFS for connected components

Q: Need all valid paths?
  → DFS + backtracking + visited set (remove from visited on backtrack)

Q: Dynamic connectivity (edges added online)?
  → Union-Find
```

---

## 12 — Complexity Reference

| Algorithm | Time | Space |
|-----------|------|-------|
| BFS / DFS | O(V + E) | O(V) |
| Dijkstra | O((V + E) log V) | O(V) |
| Kahn's Topo Sort | O(V + E) | O(V) |
| DFS Cycle Detection | O(V + E) | O(V) |
| Union-Find (per op) | O(α(n)) ≈ O(1) | O(V) |
| Kruskal MST | O(E log E) | O(V) |

---

## 13 — FAANG Interview Moves

1. **BFS = shortest in unweighted, Dijkstra = shortest in weighted**. State this choice and why before coding.
2. **Kahn's vs DFS topo sort**: Prefer Kahn's — it detects cycles naturally (`result.size() != n`), no need for a separate cycle check.
3. **Union-Find path compression**: Always implement path compression AND union by rank — without both, worst case is O(log n); with both it's O(α(n)).
4. **Grid as graph**: State "I treat each cell as a node with edges to its 4 neighbors" — this maps a grid problem directly to BFS/DFS.
5. **3-color DFS for directed cycle**: WHITE/GRAY/BLACK tells you more than a simple visited set — GRAY means "currently on the recursion stack", which is what cycle detection needs.

---

## 14 — Visual: BFS Level-by-Level + DFS 3-Color

**BFS on a graph** — why it finds the shortest path:
```
Graph: 0-1-2-4
       |   |
       3---+

BFS from node 0:
Level 0 (start):   [0]                  dist[0]=0
Level 1 (neighbors of 0):  [1, 3]       dist[1]=1, dist[3]=1
Level 2 (unseen neighbors): [2]         dist[2]=2  (reached via 1)
Level 3:           [4]                  dist[4]=3

Key: BFS visits nodes in order of increasing distance.
The FIRST time you reach a node, you've taken the fewest steps.
Any later path to the same node would have taken ≥ as many steps.
→ That's why BFS = shortest path in UNWEIGHTED graphs.
```

**DFS 3-Color for directed cycle detection**:
```
Graph: A → B → C → A  (cycle!)
       A → D           (no cycle)

Start DFS at A:
  A = GRAY (on stack)
    visit B:
      B = GRAY
        visit C:
          C = GRAY
            visit A: A is GRAY → CYCLE DETECTED! ✓
        C = BLACK (done)
      B = BLACK
    visit D:
      D = GRAY → BLACK (no back edge found)
  A = BLACK

WHITE = unvisited | GRAY = currently on recursion stack | BLACK = fully done
Cycle exists ↔ we find an edge pointing to a GRAY node
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Given a list of prerequisites `[a, b]` meaning "to take course a you must first take course b", determine if it's possible to finish all n courses. *(Course Schedule — but let's recognize it from scratch.)*

**Step 1 — Read**: Input = n (courses 0..n-1), prerequisites[][] of pairs. Output = bool.

**Step 2 — Identify**: "prerequisites" = dependencies = directed edges in a graph. "Can finish all" = no circular dependency = **no cycle in directed graph**. This is a topological sort / cycle detection problem on a directed graph.

**Step 3 — Plan** (using Kahn's BFS — easier to explain):
- Build adjacency list + in-degree array.
- Add all nodes with in-degree 0 to the queue (can be taken immediately).
- BFS: take a course → reduce in-degree of its dependents → add any new zero-in-degree courses.
- If we process all n courses → no cycle → return true.

**Step 4 — Code**:
```java
boolean canFinish(int numCourses, int[][] prerequisites) {
    List<List<Integer>> adj = new ArrayList<>();
    int[] inDegree = new int[numCourses];
    for (int i = 0; i < numCourses; i++) adj.add(new ArrayList<>());

    for (int[] pre : prerequisites) {
        adj.get(pre[1]).add(pre[0]);   // pre[1] → pre[0]
        inDegree[pre[0]]++;
    }

    Queue<Integer> queue = new LinkedList<>();
    for (int i = 0; i < numCourses; i++)
        if (inDegree[i] == 0) queue.offer(i);

    int processed = 0;
    while (!queue.isEmpty()) {
        int course = queue.poll();
        processed++;
        for (int next : adj.get(course)) {
            if (--inDegree[next] == 0) queue.offer(next);
        }
    }
    return processed == numCourses;   // processed all → no cycle
}
// Time: O(V + E), Space: O(V + E)
```

**Step 5 — Verify**: n=2, prerequisites=[[1,0]] (to take 1, must take 0 first):
- inDegree = [0, 1], queue = [0]
- process 0: processed=1, next=1, inDegree[1]=0 → queue=[1]
- process 1: processed=2 == n=2 → return true ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Disconnected components | BFS only reaches one component | Initialize ALL in-degree-0 nodes in the queue |
| Self-loop `[a,a]` | `inDegree[a]++` → a never reaches 0 → detected | Works naturally — processed < n |
| No edges | All in-degree = 0 → all processed | Correct — return true |
| Very large graph | Stack overflow in recursive DFS | Use iterative BFS (Kahn's) instead |
| Parallel edges `[a,b]` twice | in-degree counts double | Usually fine for cycle detection; for shortest path, deduplicate |

```java
// Multi-source BFS (all sources in queue from the start):
for (int i = 0; i < n; i++)
    if (inDegree[i] == 0) queue.offer(i);   // DON'T start from just one node

// Visited set for undirected cycle detection (DFS variant):
boolean dfs(int node, int parent, boolean[] visited, List<List<Integer>> adj) {
    visited[node] = true;
    for (int neighbor : adj.get(node)) {
        if (!visited[neighbor]) {
            if (dfs(neighbor, node, visited, adj)) return true;
        } else if (neighbor != parent) return true;   // back edge = cycle
    }
    return false;
}
```

---

## 😵 Commonly Confused With

**vs Tree DFS**: A tree is a graph with no cycles and one root. In a tree you don't need a visited set (you can't revisit a node). In a general graph you MUST track visited to avoid infinite loops. Deciding question: *Is there a guaranteed parent-child hierarchy with no cycles?*

**vs Dijkstra**: BFS = unweighted shortest path (each edge has cost 1). Dijkstra = weighted shortest path (non-negative weights). Deciding question: *Are all edges equal weight?* Yes → BFS. No → Dijkstra with min-heap.

**vs Union-Find**: Both handle connectivity. Union-Find is better for incremental edge additions and "are X and Y connected?" queries. BFS/DFS is better when you need the actual path or when the graph is static. Deciding question: *Do edges get added over time, or is the graph static?*
