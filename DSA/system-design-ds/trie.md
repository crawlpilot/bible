# Trie (Prefix Tree)
**Category**: Tree Data Structure — prefix-based search; used in autocomplete, IP routing, DNS, spell-check

---

## 1. The Problem It Solves

### Prefix-Based Lookups

A HashMap answers "does key X exist?" in O(1) but cannot answer:
- "Give me all keys starting with 'apple'" — O(N) scan
- "What is the longest prefix of IP address 10.1.2.3 in the routing table?" — O(N) scan
- "Are there any words that start with 'pre'?" — O(N) scan

A Trie answers all of these in O(L) where L = length of the query prefix, independent of how many keys are stored.

```
HashMap: "find all words starting with 'app'" → scan all keys O(N)
Trie:    "find all words starting with 'app'" → navigate a → p → p → collect subtree O(L + results)
```

---

## 2. Structure

Each node represents one character. A path from root to a marked node spells a complete key.

```
Keys: ["apple", "app", "application", "apply", "apt"]

             root
              │
              a
              │
              p
             / \
            p   t
           /|\   \
          * l l   *    (* = end of word marker)
            |  \
            e   y
            |    \
            *     *
            |
            i
            |
            c
            |
            a
            |
            t
            |
            i
            |
            o
            |
            n
            |
            *
```

---

## 3. Java Implementation

### 3.1 Standard Trie

```java
import java.util.*;

public class Trie {

    private static final class TrieNode {
        final Map<Character, TrieNode> children = new HashMap<>();
        boolean isEnd = false;
        int prefixCount = 0; // how many keys pass through this node
    }

    private final TrieNode root = new TrieNode();

    public void insert(String word) {
        TrieNode cur = root;
        for (char c : word.toCharArray()) {
            cur.prefixCount++;
            cur = cur.children.computeIfAbsent(c, k -> new TrieNode());
        }
        cur.prefixCount++;
        cur.isEnd = true;
    }

    public boolean search(String word) {
        TrieNode node = nodeFor(word);
        return node != null && node.isEnd;
    }

    public boolean startsWith(String prefix) {
        return nodeFor(prefix) != null;
    }

    public int countWithPrefix(String prefix) {
        TrieNode node = nodeFor(prefix);
        return node == null ? 0 : node.prefixCount;
    }

    public boolean delete(String word) {
        return delete(root, word, 0);
    }

    private boolean delete(TrieNode node, String word, int depth) {
        if (depth == word.length()) {
            if (!node.isEnd) return false;
            node.isEnd = false;
            node.prefixCount--;
            return node.children.isEmpty();
        }
        char c = word.charAt(depth);
        TrieNode child = node.children.get(c);
        if (child == null) return false;

        boolean shouldDelete = delete(child, word, depth + 1);
        node.prefixCount--;
        if (shouldDelete) node.children.remove(c);
        return !node.isEnd && node.children.isEmpty();
    }

    // All words with given prefix
    public List<String> autocomplete(String prefix) {
        List<String> results = new ArrayList<>();
        TrieNode node = nodeFor(prefix);
        if (node != null) dfs(node, new StringBuilder(prefix), results);
        return results;
    }

    // Top-K completions by insertion order (extend with frequency for ranking)
    public List<String> autocomplete(String prefix, int k) {
        List<String> all = autocomplete(prefix);
        return all.subList(0, Math.min(k, all.size()));
    }

    private void dfs(TrieNode node, StringBuilder path, List<String> results) {
        if (node.isEnd) results.add(path.toString());
        for (Map.Entry<Character, TrieNode> entry : node.children.entrySet()) {
            path.append(entry.getKey());
            dfs(entry.getValue(), path, results);
            path.deleteCharAt(path.length() - 1);
        }
    }

    private TrieNode nodeFor(String prefix) {
        TrieNode cur = root;
        for (char c : prefix.toCharArray()) {
            cur = cur.children.get(c);
            if (cur == null) return null;
        }
        return cur;
    }
}
```

### 3.2 Ranked Autocomplete (with frequency)

```java
import java.util.*;

public class RankedAutocomplete {

    private static final class Node {
        final Map<Character, Node> children = new HashMap<>();
        boolean isEnd = false;
        long frequency = 0;
        // Top-K cache at this node for fast retrieval
        final TreeMap<Long, String> topK = new TreeMap<>(Collections.reverseOrder());
        private static final int K = 10;

        void updateTopK(String word, long freq) {
            topK.put(freq, word);
            if (topK.size() > K) topK.pollLastEntry();
        }
    }

    private final Node root = new Node();

    public void insert(String word, long frequency) {
        Node cur = root;
        for (int i = 0; i < word.length(); i++) {
            char c = word.charAt(i);
            cur = cur.children.computeIfAbsent(c, k -> new Node());
            cur.updateTopK(word, frequency);
        }
        cur.isEnd = true;
        cur.frequency = frequency;
    }

    // O(L) time — uses cached top-K at the prefix node
    public List<String> topSuggestions(String prefix) {
        Node node = nodeFor(prefix);
        if (node == null) return Collections.emptyList();
        return new ArrayList<>(node.topK.values());
    }

    private Node nodeFor(String prefix) {
        Node cur = root;
        for (char c : prefix.toCharArray()) {
            cur = cur.children.get(c);
            if (cur == null) return null;
        }
        return cur;
    }
}
```

### 3.3 Compressed Trie (Radix Tree / Patricia Trie)

Collapses single-child chains into single edges. Reduces node count from O(sum of key lengths) to O(number of keys):

```java
public class RadixTree {

    private static final class Node {
        String edge;   // label on the incoming edge (may be multi-char)
        final Map<Character, Node> children = new HashMap<>();
        boolean isEnd = false;

        Node(String edge) { this.edge = edge; }
    }

    private final Node root = new Node("");

    public void insert(String key) {
        insert(root, key, 0);
    }

    private void insert(Node node, String key, int depth) {
        if (depth == key.length()) { node.isEnd = true; return; }

        char firstChar = key.charAt(depth);
        Node child = node.children.get(firstChar);

        if (child == null) {
            Node newNode = new Node(key.substring(depth));
            newNode.isEnd = true;
            node.children.put(firstChar, newNode);
            return;
        }

        // Find common prefix length between child.edge and remaining key
        int common = commonPrefixLength(child.edge, key, depth);
        if (common == child.edge.length()) {
            insert(child, key, depth + common);
        } else {
            // Split: create intermediate node for the common prefix
            Node split = new Node(child.edge.substring(0, common));
            child.edge = child.edge.substring(common);
            split.children.put(child.edge.charAt(0), child);
            node.children.put(firstChar, split);
            insert(split, key, depth + common);
        }
    }

    private int commonPrefixLength(String edge, String key, int keyOffset) {
        int len = Math.min(edge.length(), key.length() - keyOffset);
        int i = 0;
        while (i < len && edge.charAt(i) == key.charAt(keyOffset + i)) i++;
        return i;
    }

    public boolean search(String key) {
        Node cur = root;
        int depth = 0;
        while (depth < key.length()) {
            Node child = cur.children.get(key.charAt(depth));
            if (child == null) return false;
            if (!key.startsWith(child.edge, depth)) return false;
            depth += child.edge.length();
            cur = child;
        }
        return cur.isEnd;
    }
}
```

### 3.4 IP Routing — Longest Prefix Match

```java
import java.util.*;

public class IPRoutingTable {

    private static final class Node {
        Node[] children = new Node[2]; // bit trie: 0 or 1
        String nextHop = null;         // set at end of prefix
    }

    private final Node root = new Node();

    // Insert CIDR prefix e.g. "192.168.1.0/24" → nextHop "gateway-A"
    public void addRoute(String cidr, String nextHop) {
        String[] parts = cidr.split("/");
        int prefixLen = Integer.parseInt(parts[1]);
        int ip = ipToInt(parts[0]);
        insert(root, ip, prefixLen, nextHop);
    }

    // Longest prefix match for a destination IP
    public String lookup(String ipStr) {
        int ip = ipToInt(ipStr);
        Node cur = root;
        String bestMatch = null;
        for (int i = 31; i >= 0 && cur != null; i--) {
            if (cur.nextHop != null) bestMatch = cur.nextHop;
            int bit = (ip >> i) & 1;
            cur = cur.children[bit];
        }
        if (cur != null && cur.nextHop != null) bestMatch = cur.nextHop;
        return bestMatch; // null = no route
    }

    private void insert(Node node, int ip, int prefixLen, String nextHop) {
        Node cur = node;
        for (int i = 31; i >= 32 - prefixLen; i--) {
            int bit = (ip >> i) & 1;
            if (cur.children[bit] == null) cur.children[bit] = new Node();
            cur = cur.children[bit];
        }
        cur.nextHop = nextHop;
    }

    private static int ipToInt(String ip) {
        String[] parts = ip.split("\\.");
        int result = 0;
        for (String part : parts) result = (result << 8) | Integer.parseInt(part);
        return result;
    }

    // Usage example
    public static void main(String[] args) {
        IPRoutingTable table = new IPRoutingTable();
        table.addRoute("0.0.0.0/0", "default-gateway");       // default route
        table.addRoute("10.0.0.0/8", "vpc-gateway");
        table.addRoute("10.1.0.0/16", "subnet-gateway");
        table.addRoute("10.1.2.0/24", "direct");

        System.out.println(table.lookup("10.1.2.5"));   // "direct" (longest match)
        System.out.println(table.lookup("10.1.3.5"));   // "subnet-gateway"
        System.out.println(table.lookup("10.2.0.1"));   // "vpc-gateway"
        System.out.println(table.lookup("8.8.8.8"));    // "default-gateway"
    }
}
```

---

## 4. Complexity

| Operation | Trie | HashMap | Sorted Array |
|---|---|---|---|
| Insert | O(L) | O(L) hash | O(L + log N) |
| Search (exact) | O(L) | O(L) | O(L log N) |
| Prefix search | O(L + results) | O(N) | O(L log N + results) |
| Longest prefix match | O(L) | N/A | O(N·L) |
| Memory | O(N × alphabet × L) | O(N × L) | O(N × L) |

L = key length, N = number of keys. Radix tree reduces memory to O(N × L) by collapsing single-child nodes.

---

## 5. Where Tries Appear at FAANG

| System | Use | Notes |
|---|---|---|
| **Google Search / Typeahead** | Prefix autocomplete | Distributed tries sharded by prefix |
| **Linux kernel networking** | IP routing (FIB trie) | Bit trie for longest-prefix match |
| **DNS resolvers** | Domain name lookup | Labels as edges; compressed radix trie |
| **Elasticsearch/Lucene** | FST (Finite State Transducer) | Radix trie with arc compression for term dictionary |
| **Cassandra/HBase** | Row key prefix scans | Trie-optimised bloom filter for prefix |
| **Redis** | `SCAN` with `MATCH` pattern | Underlying string structure uses radix tree (rax) |
| **Spell-checkers / NLP** | Dictionary compression | Radix trie + Levenshtein automata |

---

## 6. FAANG Interview Callouts

**"Design an autocomplete system for Google Search (1B daily active users, 100K QPS):"**
> Front-end query hits a trie sharded by prefix hash. Each shard holds a compressed radix tree with top-K completions cached at each node (updated offline by a MapReduce job over search logs). Cache at node = O(1) to serve top-10. Personalisation layer re-ranks suggestions for the specific user using their history. Trie updated asynchronously — stale by ~1 hour.

**"What's a Patricia Trie and why does Linux use it for routing?":**
> A Patricia (radix) trie collapses all single-child chains into single edges labelled with multi-character strings. Linux uses a level-compressed bit trie (LC-Trie) for the IPv4 FIB (Forwarding Information Base) because longest-prefix match on millions of routes must complete in nanoseconds — the trie's O(32) worst case (IPv4 = 32 bits) beats any hash-based approach for this problem.

**Follow-up questions to expect:**
1. "How do you handle updates to a distributed trie in a typeahead system?" → Rebuild offline from search logs in a batch job (Spark/MapReduce), swap atomically. Live updates use a small in-memory delta trie merged at query time.
2. "How would you support fuzzy matching (1 typo tolerance)?" → BFS/DFS through trie with an edit distance budget. At each node, try the exact character and also all substitutions/insertions/deletions within budget. Complexity: O(L × 26^k) where k = typo budget — manageable for k=1 or k=2.
3. "Memory estimate for a trie of 100M English words?" → Average word length ~8, ~26 average children near root but 1-2 deeper. Radix trie: ~100M × ~40 bytes per node ≈ 4 GB uncompressed. With DAWG (Directed Acyclic Word Graph) deduplication of shared suffixes: ~50–100 MB for full English dictionary.
