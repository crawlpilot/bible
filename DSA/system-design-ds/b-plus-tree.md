# B+ Tree
**Category**: Balanced Tree Data Structure — used in MySQL InnoDB, PostgreSQL, SQLite, most relational database storage engines

---

## 1. The Problem It Solves

### On-Disk Sorted Data

A binary BST has O(log₂ N) operations — but each node comparison may be a disk read. At 1M rows, that's 20 disk seeks × 10 ms = 200 ms per query. Unacceptable.

The key insight: a **disk read fetches a full page** (typically 4–16 KB). If a node spans the full page and contains hundreds of keys, the tree height drops from log₂(N) to log_B(N) where B = branching factor (~100–400 for typical page sizes):

```
N = 1,000,000 rows, B = 200:
  Binary BST:  height = log₂(1M) = 20 disk reads
  B+ Tree:     height = log₂₀₀(1M) = 3 disk reads
```

This is why every production relational database uses a B+ tree (or variant) as its primary index structure.

---

## 2. Structure

### 2.1 B+ Tree vs B-Tree

| Property | B-Tree | B+ Tree |
|---|---|---|
| Data in | All nodes (internal + leaf) | Leaf nodes only |
| Internal nodes | Keys + data pointers | Keys only (routing keys) |
| Leaf nodes | Linked list | Yes — doubly linked |
| Range scans | Slow (tree traversal) | Fast (leaf linked list) |
| Used in | MongoDB MMAPV1 (legacy) | MySQL InnoDB, PostgreSQL, SQLite |

### 2.2 Node Types

```
Internal Node (order d: d to 2d keys, d+1 to 2d+1 children):
┌──────────────────────────────────────────────────────┐
│ P0 │ K1 │ P1 │ K2 │ P2 │ … │ K_{2d} │ P_{2d} │     │
└──────────────────────────────────────────────────────┘
  P0→keys < K1, P1→K1≤keys<K2, P2→K2≤keys<K3, ...

Leaf Node (d to 2d key-value pairs, plus sibling pointers):
┌──────────────────────────────────────────────────────┐
│ K1 │ V1 │ K2 │ V2 │ … │ K_{2d} │ V_{2d} │ next ──►│
└──────────────────────────────────────────────────────┘
```

### 2.3 Invariants

1. All leaves at the same depth (perfectly balanced).
2. Every non-root node has at least `d` keys (half-full).
3. Root has at least 1 key (2 children) unless it is a leaf.
4. Leaf nodes form a sorted doubly linked list.

---

## 3. Operations

### 3.1 Search — O(log_B N)

Traverse root → leaf following the correct child pointer at each level. Binary search within each node (since keys are sorted).

### 3.2 Insert — O(log_B N)

1. Search for the correct leaf.
2. Insert key/value into the leaf (maintaining sort order).
3. If leaf is now over-full (2d+1 keys): **split** — move median key up to parent, create two leaves of d keys each.
4. If parent is over-full: recurse split upward. In the worst case split propagates to root, increasing tree height by 1.

### 3.3 Delete — O(log_B N)

1. Search for and remove the key from the leaf.
2. If leaf is under-full (< d keys): try to **borrow** a key from a sibling (rotate through parent). If sibling also at minimum: **merge** the two leaves, remove separator key from parent.
3. If parent is now under-full: recurse merge/borrow upward.

### 3.4 Range Scan — O(log_B N + k)

Descend to the start key's leaf, then follow the linked list of leaves until the end key — no backtracking needed. This is the primary reason B+ trees dominate over B-trees for databases.

---

## 4. Java Implementation

### 4.1 B+ Tree (in-memory, ordered)

```java
import java.util.*;

public class BPlusTree<K extends Comparable<K>, V> {

    private final int order; // minimum degree d: each node has d to 2d keys
    private Node root;
    private int height = 0;

    public BPlusTree(int order) {
        this.order = order;
        this.root = new LeafNode();
    }

    // ─── Node types ────────────────────────────────────────────────────────

    private abstract class Node {
        List<K> keys = new ArrayList<>();
        abstract boolean isLeaf();
        abstract V search(K key);
        abstract InsertResult insert(K key, V value);
    }

    private class LeafNode extends Node {
        List<V> values = new ArrayList<>();
        LeafNode next = null;
        LeafNode prev = null;

        boolean isLeaf() { return true; }

        V search(K key) {
            int idx = Collections.binarySearch(keys, key);
            return idx >= 0 ? values.get(idx) : null;
        }

        InsertResult insert(K key, V value) {
            int idx = lowerBound(keys, key);
            if (idx < keys.size() && keys.get(idx).compareTo(key) == 0) {
                values.set(idx, value); // update
                return null;
            }
            keys.add(idx, key);
            values.add(idx, value);

            if (keys.size() <= 2 * order) return null; // no split needed
            return splitLeaf();
        }

        private InsertResult splitLeaf() {
            int mid = order;
            LeafNode newLeaf = new LeafNode();
            newLeaf.keys = new ArrayList<>(keys.subList(mid, keys.size()));
            newLeaf.values = new ArrayList<>(values.subList(mid, values.size()));
            keys.subList(mid, keys.size()).clear();
            values.subList(mid, values.size()).clear();
            // Link leaves
            newLeaf.next = this.next;
            newLeaf.prev = this;
            if (this.next != null) this.next.prev = newLeaf;
            this.next = newLeaf;
            return new InsertResult(newLeaf.keys.get(0), newLeaf);
        }
    }

    private class InternalNode extends Node {
        List<Node> children = new ArrayList<>();

        boolean isLeaf() { return false; }

        V search(K key) {
            return children.get(childIndex(key)).search(key);
        }

        InsertResult insert(K key, V value) {
            int idx = childIndex(key);
            InsertResult result = children.get(idx).insert(key, value);
            if (result == null) return null;

            // Absorb the promoted key from child split
            int insertAt = lowerBound(keys, result.promotedKey);
            keys.add(insertAt, result.promotedKey);
            children.add(insertAt + 1, result.newNode);

            if (keys.size() <= 2 * order) return null;
            return splitInternal();
        }

        private InsertResult splitInternal() {
            int mid = order;
            K promotedKey = keys.get(mid);

            InternalNode newNode = new InternalNode();
            newNode.keys = new ArrayList<>(keys.subList(mid + 1, keys.size()));
            newNode.children = new ArrayList<>(children.subList(mid + 1, children.size()));
            keys.subList(mid, keys.size()).clear();
            children.subList(mid + 1, children.size()).clear();

            return new InsertResult(promotedKey, newNode);
        }

        private int childIndex(K key) {
            int idx = lowerBound(keys, key);
            // If key equals keys[idx], go right
            if (idx < keys.size() && keys.get(idx).compareTo(key) == 0) idx++;
            return idx;
        }
    }

    private record InsertResult(K promotedKey, Node newNode) {}

    // ─── Public API ─────────────────────────────────────────────────────────

    public V get(K key) {
        return root.search(key);
    }

    public void put(K key, V value) {
        InsertResult result = root.insert(key, value);
        if (result != null) {
            InternalNode newRoot = new InternalNode();
            newRoot.keys.add(result.promotedKey);
            newRoot.children.add(root);
            newRoot.children.add(result.newNode);
            root = newRoot;
            height++;
        }
    }

    // Range scan: returns all key-value pairs with key in [from, to] inclusive
    public List<Map.Entry<K, V>> range(K from, K to) {
        List<Map.Entry<K, V>> result = new ArrayList<>();
        LeafNode leaf = findLeaf(from);
        while (leaf != null) {
            for (int i = 0; i < leaf.keys.size(); i++) {
                K k = leaf.keys.get(i);
                if (k.compareTo(from) >= 0 && k.compareTo(to) <= 0) {
                    result.add(Map.entry(k, leaf.values.get(i)));
                } else if (k.compareTo(to) > 0) {
                    return result;
                }
            }
            leaf = leaf.next;
        }
        return result;
    }

    private LeafNode findLeaf(K key) {
        Node cur = root;
        while (!cur.isLeaf()) {
            InternalNode internal = (InternalNode) cur;
            cur = internal.children.get(internal.childIndex(key));
        }
        return (LeafNode) cur;
    }

    public int height() { return height; }

    // ─── Utilities ──────────────────────────────────────────────────────────

    private static <K extends Comparable<K>> int lowerBound(List<K> list, K key) {
        int lo = 0, hi = list.size();
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            if (list.get(mid).compareTo(key) < 0) lo = mid + 1;
            else hi = mid;
        }
        return lo;
    }
}
```

### 4.2 Usage

```java
BPlusTree<Integer, String> index = new BPlusTree<>(2); // order 2: 2–4 keys per node

// Simulate inserting rows
for (int i = 1; i <= 100; i++) index.put(i, "row_" + i);

System.out.println(index.get(42));           // "row_42"
System.out.println(index.height());          // ~3 for 100 entries with order=2

// Range scan: IDs 30 to 35
List<Map.Entry<Integer, String>> rows = index.range(30, 35);
rows.forEach(e -> System.out.println(e.getKey() + " → " + e.getValue()));
// 30→row_30, 31→row_31, 32→row_32, 33→row_33, 34→row_34, 35→row_35
```

### 4.3 InnoDB-Style Clustered Index Sketch

```java
// InnoDB primary key index is a clustered B+ tree:
// Leaf nodes store the full row data, not just a pointer.
// Secondary indexes store (secondary_key, primary_key) pairs.
// Lookup via secondary index: two B+ tree traversals (secondary → PK, PK → row).

public class ClusteredIndex<PK extends Comparable<PK>> {

    // Simulates InnoDB clustered index: leaf stores full row
    private final BPlusTree<PK, Map<String, Object>> pkIndex;

    // Secondary index: secondary key → primary key (then look up in pkIndex)
    private final Map<String, BPlusTree<Comparable<?>, PK>> secondaryIndexes = new HashMap<>();

    public ClusteredIndex(int order) {
        pkIndex = new BPlusTree<>(order);
    }

    public void insertRow(PK pk, Map<String, Object> row) {
        pkIndex.put(pk, row);
        for (Map.Entry<String, BPlusTree<Comparable<?>, PK>> idx : secondaryIndexes.entrySet()) {
            @SuppressWarnings("unchecked")
            Comparable<Object> secKey = (Comparable<Object>) row.get(idx.getKey());
            if (secKey != null) {
                @SuppressWarnings("unchecked")
                BPlusTree<Comparable<Object>, PK> secTree = (BPlusTree<Comparable<Object>, PK>) (Object) idx.getValue();
                secTree.put(secKey, pk);
            }
        }
    }

    public Map<String, Object> getByPK(PK pk) {
        return pkIndex.get(pk);
    }

    // Range scan on PK (efficient — walks leaf linked list)
    public List<Map<String, Object>> rangeByPK(PK from, PK to) {
        return pkIndex.range(from, to).stream()
            .map(Map.Entry::getValue)
            .collect(java.util.stream.Collectors.toList());
    }
}
```

---

## 5. B+ Tree in InnoDB: Key Design Choices

### 5.1 Page Size and Branching Factor

```
InnoDB page: 16 KB
Row size: ~200 bytes
Leaf keys per page: 16384 / 200 ≈ 80 rows
Internal keys per page (key=8 bytes + ptr=6 bytes): 16384 / 14 ≈ 1170 pointers

Tree height for 1M rows:
  Level 0 (root):       1 node, 1170 children
  Level 1:           1170 nodes, 1170 × 1170 = 1.37M children
  Level 2 (leaves):  16K rows per page → 1M / 80 = 12,500 pages

→ Height = 3 (root + 1 internal level + leaf) for 1M rows
→ Height = 4 for up to ~1.37B rows
```

### 5.2 Clustered vs Secondary Indexes

```
SELECT * FROM orders WHERE order_id = 42;
  → 1 B+ tree lookup (clustered): O(log_B N) ≈ 3–4 page reads

SELECT * FROM orders WHERE customer_id = 99;  (secondary index on customer_id)
  → 1 B+ tree lookup on secondary index → returns order_id(s)
  → N clustered index lookups to fetch full rows ("index back lookup")
  → InnoDB covering index: if all needed columns are in the index, skip back lookup
```

---

## 6. Trade-Offs

| Attribute | B+ Tree | B-Tree | Skip List | Hash Index |
|---|---|---|---|---|
| Range scans | Excellent (leaf list) | Slow (tree traversal) | Good (level-0) | Not supported |
| Point lookup | O(log_B N) | O(log_B N) | O(log N) expected | O(1) |
| Disk I/O per query | 3–4 page reads | 3–4 page reads | N/A (in-memory) | 1–2 reads |
| Write amplification | High (page splits) | High | Low | Low |
| Ordered iteration | Natural | Possible | Natural | Not supported |
| Concurrent writes | Latches on path | Latches on path | Lock-free variants | Partition locks |

---

## 7. FAANG Interview Callouts

**"Why does MySQL use a B+ tree instead of a hash index by default?"**
> Hash indexes support only equality lookups (O(1)) and cannot serve range queries (`BETWEEN`, `>`, `ORDER BY`). B+ trees support both equality and range operations in O(log_B N). Since most queries involve ranges or sorting, B+ trees win as the general-purpose default. MySQL InnoDB's `MEMORY` engine does support hash indexes for equality-only use cases.

**"What happens when you insert 1M rows into an InnoDB table with a UUID primary key?"**
> UUID primary keys are random — inserts land at random leaf positions. This causes high page fragmentation: pages fill slowly (average 50% full instead of 90%), and page splits happen frequently. Every insert requires reading a random page from disk. Recommendation: use sequential IDs (AUTO_INCREMENT) or time-ordered UUIDs (UUID v7) to ensure inserts always append to the rightmost leaf — zero page splits, maximum page fill.

**Follow-up questions to expect:**
1. "What is an index-organized table?" → Same as InnoDB clustered index: primary key B+ tree stores full row data at the leaf. PostgreSQL's heap tables keep data in separate heap files; InnoDB stores rows directly in the leaf — fewer I/O hops for PK lookups.
2. "How would you design a B+ tree for an SSD vs HDD?" → HDDs: large pages (16–64 KB) to amortise seek time; sequential I/O critical. SSDs: smaller pages acceptable (4–8 KB, matches SSD block size); random reads are fast so page splits less painful; write amplification is a concern (SSD endurance) — consider copy-on-write variants.
3. "What is a covering index and when does it eliminate a join?" → A covering index includes all columns referenced in a query (SELECT + WHERE). InnoDB reads only the secondary B+ tree leaf, avoiding the PK back lookup entirely. Example: `CREATE INDEX idx ON orders(customer_id, order_date, status)` covers `SELECT order_date, status FROM orders WHERE customer_id = 99`.
