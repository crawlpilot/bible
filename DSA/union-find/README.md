# Union-Find (Disjoint Set Union)

> Union-Find answers one question in near-constant time: **are two nodes in the same connected component?** And it can merge components with `union`. With path compression + union by rank, each operation is effectively O(α(n)) ≈ O(1).

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem involve **grouping elements** into connected components dynamically?
- [ ] Are edges/connections **added incrementally** (not removed)?
- [ ] Do you need to answer "are X and Y connected?" repeatedly?
- [ ] Is there cycle detection in an **undirected** graph?

**Trigger phrases**: "number of connected components", "redundant connection", "accounts merge", "friend circles", "smallest string with swaps", "number of provinces", "satisfiability of equality equations", "minimum spanning tree (Kruskal)"

**When NOT to use**: if edges are removed (use DFS/BFS snapshot per query), or if the graph is directed (use DFS for SCC or topological sort).

---

## 2 — The Template (Path Compression + Union by Rank)

```java
class UnionFind {
    private int[] parent;
    private int[] rank;
    private int components;

    UnionFind(int n) {
        parent = new int[n];
        rank   = new int[n];
        components = n;
        for (int i = 0; i < n; i++) parent[i] = i;   // each node is its own parent
    }

    // Find root with PATH COMPRESSION (flattens the tree)
    int find(int x) {
        if (parent[x] != x)
            parent[x] = find(parent[x]);   // compress: point directly to root
        return parent[x];
    }

    // Union by RANK (attach smaller tree under larger)
    boolean union(int x, int y) {
        int rootX = find(x), rootY = find(y);
        if (rootX == rootY) return false;   // already in same component (cycle!)

        if      (rank[rootX] < rank[rootY]) parent[rootX] = rootY;
        else if (rank[rootX] > rank[rootY]) parent[rootY] = rootX;
        else { parent[rootY] = rootX; rank[rootX]++; }

        components--;
        return true;
    }

    boolean connected(int x, int y) { return find(x) == find(y); }
    int count() { return components; }
}
// find: O(α(n)) amortized ≈ O(1), union: O(α(n)), Space: O(n)
// α(n) is the inverse Ackermann function — effectively constant for all practical n
```

---

## 3 — Number of Provinces / Friend Circles (LC 547)

```java
int findCircleNum(int[][] isConnected) {
    int n = isConnected.length;
    UnionFind uf = new UnionFind(n);

    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++)
            if (isConnected[i][j] == 1) uf.union(i, j);

    return uf.count();
}
// Time: O(n² × α(n)) ≈ O(n²), Space: O(n)
```

---

## 4 — Number of Connected Components in Graph (LC 323)

```java
int countComponents(int n, int[][] edges) {
    UnionFind uf = new UnionFind(n);
    for (int[] edge : edges) uf.union(edge[0], edge[1]);
    return uf.count();
}
// Time: O(E × α(n)), Space: O(n)
```

---

## 5 — Redundant Connection — Detect Cycle in Undirected Graph (LC 684)

```java
int[] findRedundantConnection(int[][] edges) {
    UnionFind uf = new UnionFind(edges.length + 1);   // nodes 1-indexed

    for (int[] edge : edges) {
        if (!uf.union(edge[0], edge[1])) {
            return edge;   // union returned false → nodes already connected → this edge creates a cycle
        }
    }
    return new int[]{};
}
// Time: O(n × α(n)), Space: O(n)
```

**Key**: `union()` returns `false` when both nodes share a root → the edge being added would form a cycle.

---

## 6 — Accounts Merge (LC 721)

Merge accounts that share at least one email address.

```java
List<List<String>> accountsMerge(List<List<String>> accounts) {
    // Map each email to an ID
    Map<String, Integer> emailToId = new HashMap<>();
    int n = accounts.size();
    UnionFind uf = new UnionFind(n);

    for (int i = 0; i < n; i++) {
        List<String> account = accounts.get(i);
        for (int j = 1; j < account.size(); j++) {
            String email = account.get(j);
            if (emailToId.containsKey(email)) {
                uf.union(i, emailToId.get(email));   // same email → same person
            } else {
                emailToId.put(email, i);
            }
        }
    }

    // Group emails by their root account
    Map<Integer, TreeSet<String>> groups = new HashMap<>();
    for (Map.Entry<String, Integer> e : emailToId.entrySet()) {
        int root = uf.find(e.getValue());
        groups.computeIfAbsent(root, k -> new TreeSet<>()).add(e.getKey());
    }

    // Build result
    List<List<String>> result = new ArrayList<>();
    for (Map.Entry<Integer, TreeSet<String>> e : groups.entrySet()) {
        List<String> merged = new ArrayList<>();
        merged.add(accounts.get(e.getKey()).get(0));  // account name
        merged.addAll(e.getValue());                   // sorted emails
        result.add(merged);
    }
    return result;
}
// Time: O(N log N × α(N)) where N = total emails, Space: O(N)
```

---

## 7 — Satisfiability of Equality Equations (LC 990)

```java
boolean equationsPossible(String[] equations) {
    UnionFind uf = new UnionFind(26);   // 26 lowercase letters

    // Pass 1: union all equal pairs
    for (String eq : equations)
        if (eq.charAt(1) == '=')
            uf.union(eq.charAt(0) - 'a', eq.charAt(3) - 'a');

    // Pass 2: verify no inequality pairs share a component
    for (String eq : equations)
        if (eq.charAt(1) == '!' && uf.connected(eq.charAt(0)-'a', eq.charAt(3)-'a'))
            return false;   // contradiction: a == b but a != b

    return true;
}
// Time: O(n × α(26)) = O(n), Space: O(26) = O(1)
```

---

## 8 — Smallest String With Swaps (LC 1202)

Swap characters at any pair of indices (transitively), then sort each connected component.

```java
String smallestStringWithSwaps(String s, List<List<Integer>> pairs) {
    int n = s.length();
    UnionFind uf = new UnionFind(n);
    for (List<Integer> pair : pairs) uf.union(pair.get(0), pair.get(1));

    // Group indices by root
    Map<Integer, PriorityQueue<Character>> groups = new HashMap<>();
    for (int i = 0; i < n; i++) {
        int root = uf.find(i);
        groups.computeIfAbsent(root, k -> new PriorityQueue<>()).offer(s.charAt(i));
    }

    // Build smallest string: pick smallest char from each group in order
    char[] result = new char[n];
    for (int i = 0; i < n; i++)
        result[i] = groups.get(uf.find(i)).poll();

    return new String(result);
}
// Time: O((n + p) log n) where p = pairs count, Space: O(n)
```

---

## 9 — Number of Islands — Union-Find Alternative (LC 200)

```java
int numIslands(char[][] grid) {
    if (grid.length == 0) return 0;
    int m = grid.length, n = grid[0].length;
    UnionFind uf = new UnionFind(m * n);
    int waterCount = 0;

    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
    for (int r = 0; r < m; r++) {
        for (int c = 0; c < n; c++) {
            if (grid[r][c] == '0') { waterCount++; continue; }
            for (int[] d : dirs) {
                int nr = r + d[0], nc = c + d[1];
                if (nr >= 0 && nr < m && nc >= 0 && nc < n && grid[nr][nc] == '1')
                    uf.union(r * n + c, nr * n + nc);
            }
        }
    }
    return uf.count() - waterCount;   // subtract water cells (each is its own component)
}
// Time: O(m*n × α(m*n)), Space: O(m*n)
// Note: BFS/DFS is simpler for static grid; Union-Find shines when edges are added dynamically
```

---

## 10 — Kruskal's MST (Minimum Spanning Tree)

**Algorithm**: sort all edges by weight; greedily add edge if it doesn't create a cycle (Union-Find cycle check).

```java
int minCostConnectPoints(int[][] points) {
    int n = points.length;

    // Build all edges
    List<int[]> edges = new ArrayList<>();   // [cost, i, j]
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++) {
            int cost = Math.abs(points[i][0]-points[j][0]) + Math.abs(points[i][1]-points[j][1]);
            edges.add(new int[]{cost, i, j});
        }
    edges.sort((a, b) -> a[0] - b[0]);

    UnionFind uf = new UnionFind(n);
    int totalCost = 0, edgesUsed = 0;

    for (int[] edge : edges) {
        if (uf.union(edge[1], edge[2])) {   // false = would create cycle
            totalCost += edge[0];
            if (++edgesUsed == n - 1) break;  // MST has exactly n-1 edges
        }
    }
    return totalCost;
}
// Time: O(E log E) = O(n² log n) for complete graph, Space: O(n)
// LC 1584 — Min Cost to Connect All Points
```

---

## 11 — Union-Find with Weighted / Bipartite Check

**Bipartite check using Union-Find**:
```java
boolean isBipartite(int[][] graph) {
    int n = graph.length;
    int[] color = new int[n];   // 0 = uncolored, 1 = red, -1 = blue
    Arrays.fill(color, 0);

    // Simpler with BFS 2-coloring than Union-Find for bipartite
    for (int start = 0; start < n; start++) {
        if (color[start] != 0) continue;
        Queue<Integer> queue = new LinkedList<>();
        queue.offer(start);
        color[start] = 1;
        while (!queue.isEmpty()) {
            int node = queue.poll();
            for (int neighbor : graph[node]) {
                if (color[neighbor] == 0) {
                    color[neighbor] = -color[node];
                    queue.offer(neighbor);
                } else if (color[neighbor] == color[node]) {
                    return false;
                }
            }
        }
    }
    return true;
}
// Time: O(V+E), Space: O(V)
```

---

## 12 — Union-Find vs BFS/DFS Decision

| Situation | Prefer |
|-----------|--------|
| Static graph, one-time connectivity query | BFS/DFS (simpler) |
| Edges added **incrementally**, many connectivity queries | **Union-Find** |
| Find if adding this edge creates a cycle | **Union-Find** (one-liner: `!uf.union(u, v)`) |
| Need actual path between nodes | BFS/DFS (Union-Find only answers yes/no) |
| Directed graph components (SCC) | Kosaraju/Tarjan DFS |
| MST construction | **Kruskal + Union-Find** |

---

## 13 — Visual: Union-Find Operations

```
Initial: 5 nodes, each is its own component.
parent=[0,1,2,3,4]  rank=[0,0,0,0,0]

union(0,1): find(0)=0, find(1)=1. rank equal → parent[1]=0, rank[0]++.
  parent=[0,0,2,3,4]  Components: {0,1}, {2}, {3}, {4}

union(2,3): find(2)=2, find(3)=3. rank equal → parent[3]=2, rank[2]++.
  parent=[0,0,2,2,4]  Components: {0,1}, {2,3}, {4}

union(1,3): find(1)→parent[1]=0→root=0. find(3)→parent[3]=2→root=2.
  rank[0]==rank[2]==1 → parent[2]=0, rank[0]++.
  parent=[0,0,0,2,4]  Components: {0,1,2,3}, {4}

find(3) with path compression:
  3→parent[3]=2→parent[2]=0 (root). Set parent[3]=0 directly.
  parent=[0,0,0,0,4]  Next find(3) is O(1).
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: You have n cities and a list of `[city1, city2]` pairs indicating direct connections. Find the number of distinct provinces (connected components of cities). *(LC 547 — Number of Provinces)*

**Step 1 — Read**: Input = `int[][] isConnected` (adjacency matrix, n×n), `isConnected[i][j]=1` means city i and j are connected. Output = number of connected components.

**Step 2 — Identify**: "Connected components" → **Union-Find** or BFS/DFS. Union-Find is ideal here because: (1) we're adding edges and counting components, (2) we don't need shortest path, just "same group or not?"

**Step 3 — Plan**:
- Initialize Union-Find with n components.
- For every edge (i,j) where `isConnected[i][j] == 1`, call `union(i, j)`.
- Answer = number of distinct roots (count nodes where `parent[i] == i`).

**Step 4 — Code**:
```java
int findCircleNum(int[][] isConnected) {
    int n = isConnected.length;
    int[] parent = new int[n], rank = new int[n];
    for (int i = 0; i < n; i++) parent[i] = i;

    // find with path compression
    java.util.function.IntUnaryOperator find = null;
    // Use iterative path compression instead:
    // (defined inline in union)

    int components = n;

    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            if (isConnected[i][j] == 1) {
                // find roots
                int ri = i, rj = j;
                while (parent[ri] != ri) ri = parent[ri] = parent[parent[ri]];
                while (parent[rj] != rj) rj = parent[rj] = parent[parent[rj]];
                if (ri != rj) {
                    if (rank[ri] < rank[rj]) { int t = ri; ri = rj; rj = t; }
                    parent[rj] = ri;
                    if (rank[ri] == rank[rj]) rank[ri]++;
                    components--;
                }
            }
        }
    }
    return components;
}
// Time: O(n² · α(n)) ≈ O(n²). Space: O(n).
```

**Step 5 — Verify** on `[[1,1,0],[1,1,0],[0,0,1]]`:
- n=3, components=3.
- (0,1): connected → union → components=2.
- (0,2),(1,2): not connected.
- Return 2. ✓ (Province 1: {0,1}, Province 2: {2})

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| n=1 | One component by definition | Returns `components = 1` correctly |
| All connected | Single component | All unions reduce count to 1 |
| No edges | n components | No union calls; return n |
| Self-loops (`isConnected[i][i]=1`) | Union with itself is a no-op | `find(i) == find(j)` → skip, no change |
| Weighted Union-Find | Need extra `weight[]` array | Propagate weight during path compression |
| Dynamic edge removal | Standard UF doesn't support it | Use link-cut trees or offline reverse-time trick |

```java
// Standard Union-Find template (copy this into every problem):
int[] parent, rank;
void init(int n) {
    parent = new int[n]; rank = new int[n];
    for (int i = 0; i < n; i++) parent[i] = i;
}
int find(int x) {
    if (parent[x] != x) parent[x] = find(parent[x]);  // path compression
    return parent[x];
}
boolean union(int x, int y) {
    int rx = find(x), ry = find(y);
    if (rx == ry) return false;  // already same component
    if (rank[rx] < rank[ry]) { int t = rx; rx = ry; ry = t; }
    parent[ry] = rx;
    if (rank[rx] == rank[ry]) rank[rx]++;
    return true;  // merged
}
```

---

## 😵 Commonly Confused With

**vs BFS/DFS for connected components**: Both find connected components. Deciding question: *Are edges added incrementally (dynamic graph) or is the full graph given upfront?* Incremental → Union-Find (online). Static → BFS/DFS (often simpler code).

**vs Minimum Spanning Tree (Kruskal's)**: Kruskal's uses Union-Find internally. Deciding question: *Do you need the minimum weight set of edges that connects everything (MST), or just which nodes are connected (component count)?*

**vs Topological Sort**: Topological sort is for directed graphs with dependency ordering. Union-Find is for undirected graphs with connectivity. Deciding question: *Are edges directed (→) with an ordering constraint, or undirected (—) with a grouping constraint?*

---

## 14 — Canonical LeetCode Problems

| Category | Problems |
|---------|---------|
| Connected components | LC 547, LC 323, LC 200 (alternative) |
| Cycle detection | LC 684, LC 685 (directed — harder) |
| Account/group merging | LC 721, LC 1202 |
| Satisfiability | LC 990 |
| MST | LC 1584, LC 1135 |
| Dynamic connectivity | LC 305 (number of islands II — online) |
