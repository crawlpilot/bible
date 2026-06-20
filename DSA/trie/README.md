# Trie (Prefix Tree)

> A Trie is a tree where each path from root to node represents a string prefix. Every node can have up to 26 children (lowercase letters). Use it when you need **fast prefix lookups**, **word existence checks**, or **autocomplete**.

---

## 1 — How to Recognize This Pattern

Ask yourself:
- [ ] Does the problem involve **prefix matching** ("starts with", "autocomplete")?
- [ ] Are you searching for **words in a dictionary** with wildcard characters?
- [ ] Does the problem involve a **set of strings** with shared prefixes?
- [ ] Is the problem about **XOR maximization** over a set of integers (XOR Trie)?

**Trigger phrases**: "implement trie", "add and search words", "word search II", "replace words", "maximum XOR", "design search autocomplete", "word break", "prefix matching"

---

## 2 — Flavor Detection

| Flavor | Signal | Twist |
|--------|--------|-------|
| **Standard Trie** | Insert/search/startsWith | 26-ary tree of TrieNode |
| **Word dictionary (wildcard)** | `.` matches any character | DFS through Trie when `.` encountered |
| **Word Search II (board)** | Find all dictionary words in 2D grid | DFS on board + Trie pruning |
| **Replace words** | Replace suffixes with shortest root | Trie of roots; find earliest match |
| **XOR Trie** | Maximize/find XOR with a given number | Binary Trie (0/1 bits); greedily go opposite bit |
| **Autocomplete** | Top-K suggestions per prefix | Trie + DFS/BFS to collect completions |

---

## 3 — Core Implementation

```java
class Trie {
    private TrieNode root;

    static class TrieNode {
        TrieNode[] children = new TrieNode[26];
        boolean isEnd = false;
    }

    Trie() { root = new TrieNode(); }

    void insert(String word) {
        TrieNode node = root;
        for (char c : word.toCharArray()) {
            int idx = c - 'a';
            if (node.children[idx] == null)
                node.children[idx] = new TrieNode();
            node = node.children[idx];
        }
        node.isEnd = true;
    }

    boolean search(String word) {
        TrieNode node = root;
        for (char c : word.toCharArray()) {
            int idx = c - 'a';
            if (node.children[idx] == null) return false;
            node = node.children[idx];
        }
        return node.isEnd;   // must end exactly here
    }

    boolean startsWith(String prefix) {
        TrieNode node = root;
        for (char c : prefix.toCharArray()) {
            int idx = c - 'a';
            if (node.children[idx] == null) return false;
            node = node.children[idx];
        }
        return true;   // any word with this prefix exists
    }
}
// insert/search/startsWith: O(L) per op where L = word length
// Space: O(alphabet × N × L) = O(26 × total chars) worst case
// LC 208 — Implement Trie
```

---

## 4 — Add and Search Words (Wildcard) (LC 211)

`.` can match any single character — use DFS when `.` is encountered.

```java
class WordDictionary {
    private TrieNode root = new TrieNode();

    void addWord(String word) {
        TrieNode node = root;
        for (char c : word.toCharArray()) {
            if (node.children[c - 'a'] == null)
                node.children[c - 'a'] = new TrieNode();
            node = node.children[c - 'a'];
        }
        node.isEnd = true;
    }

    boolean search(String word) {
        return dfs(word, 0, root);
    }

    private boolean dfs(String word, int i, TrieNode node) {
        if (i == word.length()) return node.isEnd;

        char c = word.charAt(i);
        if (c != '.') {
            TrieNode next = node.children[c - 'a'];
            return next != null && dfs(word, i + 1, next);
        } else {
            // '.' matches any character — try all children
            for (TrieNode child : node.children)
                if (child != null && dfs(word, i + 1, child)) return true;
            return false;
        }
    }
}
// addWord: O(L), search: O(26^L) worst case (all dots), O(L) typical
```

---

## 5 — Word Search II (LC 212)

Find all words from a dictionary in a 2D board. Brute force: DFS for each word O(W × M × N × 4^L). With Trie: build Trie from dictionary, one DFS over board simultaneously matches all words.

```java
List<String> findWords(char[][] board, String[] words) {
    Trie trie = new Trie();
    for (String w : words) trie.insert(w);

    Set<String> result = new HashSet<>();
    int m = board.length, n = board[0].length;
    boolean[][] visited = new boolean[m][n];

    for (int r = 0; r < m; r++)
        for (int c = 0; c < n; c++)
            dfs(board, r, c, trie.root, new StringBuilder(), result, visited);

    return new ArrayList<>(result);
}

private void dfs(char[][] board, int r, int c, TrieNode node, StringBuilder path,
                 Set<String> result, boolean[][] visited) {
    if (r < 0 || r >= board.length || c < 0 || c >= board[0].length
        || visited[r][c] || node.children[board[r][c] - 'a'] == null) return;

    char ch = board[r][c];
    node = node.children[ch - 'a'];
    path.append(ch);
    visited[r][c] = true;

    if (node.isEnd) result.add(path.toString());

    int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
    for (int[] d : dirs)
        dfs(board, r + d[0], c + d[1], node, path, result, visited);

    // Backtrack
    path.deleteCharAt(path.length() - 1);
    visited[r][c] = false;
}
// Time: O(M*N*4^L + W*L) where W=words, L=avg length, M*N=board size
// Optimization: set node.isEnd = false after finding to avoid duplicates + prune empty branches
```

**Optimization — prune dead branches**:
```java
// After adding to result, mark as found and prune empty trie nodes bottom-up
node.isEnd = false;
// After DFS, if node has no children, remove it from parent (reduces future search space)
```

---

## 6 — Replace Words (LC 648)

Replace each word in a sentence with its shortest root from a dictionary.

```java
String replaceWords(List<String> dictionary, String sentence) {
    TrieNode root = new TrieNode();

    // Insert all roots
    for (String root2 : dictionary) {
        TrieNode node = root;
        for (char c : root2.toCharArray()) {
            if (node.children[c - 'a'] == null)
                node.children[c - 'a'] = new TrieNode();
            node = node.children[c - 'a'];
        }
        node.isEnd = true;
    }

    // Replace each word
    StringBuilder result = new StringBuilder();
    for (String word : sentence.split(" ")) {
        if (result.length() > 0) result.append(' ');

        TrieNode node = root;
        StringBuilder prefix = new StringBuilder();
        boolean replaced = false;

        for (char c : word.toCharArray()) {
            if (node.children[c - 'a'] == null) break;
            node = node.children[c - 'a'];
            prefix.append(c);
            if (node.isEnd) { result.append(prefix); replaced = true; break; }
        }
        if (!replaced) result.append(word);
    }
    return result.toString();
}
// Time: O(D*L + S) where D=dict size, L=avg root len, S=sentence length
```

---

## 7 — Maximum XOR of Two Numbers (LC 421) — XOR Trie

**Key insight**: for integers, use a binary Trie (one bit per level, MSB first). To maximize XOR, at each bit greedily go to the **opposite** child if it exists.

```java
class XORTrie {
    private int[][] children;   // children[node][0 or 1]
    private int next;

    XORTrie(int maxNodes) {
        children = new int[maxNodes][2];
        next = 1;   // root is node 0
    }

    void insert(int num) {
        int node = 0;
        for (int i = 31; i >= 0; i--) {
            int bit = (num >> i) & 1;
            if (children[node][bit] == 0) children[node][bit] = next++;
            node = children[node][bit];
        }
    }

    int maxXOR(int num) {
        int node = 0, result = 0;
        for (int i = 31; i >= 0; i--) {
            int bit = (num >> i) & 1;
            int want = 1 - bit;   // want the opposite bit to maximize XOR
            if (children[node][want] != 0) {
                result |= (1 << i);
                node = children[node][want];
            } else {
                node = children[node][bit];
            }
        }
        return result;
    }
}

int findMaximumXOR(int[] nums) {
    XORTrie trie = new XORTrie(nums.length * 32);
    for (int num : nums) trie.insert(num);
    int max = 0;
    for (int num : nums) max = Math.max(max, trie.maxXOR(num));
    return max;
}
// Time: O(32n) = O(n), Space: O(32n) = O(n)
// LC 421 — Maximum XOR of Two Numbers in an Array
```

---

## 8 — Count of Words With Prefix (Design Autocomplete)

```java
class AutocompleteSystem {
    private TrieNode root = new TrieNode();

    static class TrieNode {
        TrieNode[] children = new TrieNode[26];
        List<String> suggestions = new ArrayList<>();  // sorted top-K
    }

    void insert(String word) {
        TrieNode node = root;
        for (char c : word.toCharArray()) {
            int idx = c - 'a';
            if (node.children[idx] == null) node.children[idx] = new TrieNode();
            node = node.children[idx];
            // Maintain sorted list (or use TreeSet with custom comparator)
            if (!node.suggestions.contains(word)) {
                node.suggestions.add(word);
                node.suggestions.sort(Comparator.naturalOrder());
                if (node.suggestions.size() > 3) node.suggestions.remove(3);
            }
        }
    }

    List<String> search(String prefix) {
        TrieNode node = root;
        for (char c : prefix.toCharArray()) {
            if (node.children[c - 'a'] == null) return new ArrayList<>();
            node = node.children[c - 'a'];
        }
        return node.suggestions;
    }
}
// LC 1268 — Search Suggestions System
```

---

## 9 — Trie with Count (Word Frequency)

```java
class TrieWithCount {
    private TrieNode root = new TrieNode();

    static class TrieNode {
        TrieNode[] children = new TrieNode[26];
        int count = 0;   // number of words that pass through this node (prefix count)
        int endCount = 0; // number of words that end exactly here
    }

    void insert(String word) {
        TrieNode node = root;
        for (char c : word.toCharArray()) {
            int idx = c - 'a';
            if (node.children[idx] == null) node.children[idx] = new TrieNode();
            node = node.children[idx];
            node.count++;
        }
        node.endCount++;
    }

    int countWordsEqualTo(String word) {
        TrieNode node = traverse(word);
        return node == null ? 0 : node.endCount;
    }

    int countWordsStartingWith(String prefix) {
        TrieNode node = traverse(prefix);
        return node == null ? 0 : node.count;
    }

    private TrieNode traverse(String s) {
        TrieNode node = root;
        for (char c : s.toCharArray()) {
            int idx = c - 'a';
            if (node.children[idx] == null) return null;
            node = node.children[idx];
        }
        return node;
    }
}
// LC 2135 — Count Words Obtained After Adding a Letter
```

---

## 10 — Palindrome Pairs with Trie (LC 336)

```java
// Alternative to hash map approach for palindrome pairs
// Insert reverse of each word; for each word, check: prefix palindrome + reverse suffix match
// More complex — HashMap approach is simpler for interviews
List<List<Integer>> palindromePairs(String[] words) {
    Map<String, Integer> map = new HashMap<>();
    for (int i = 0; i < words.length; i++) map.put(words[i], i);

    List<List<Integer>> result = new ArrayList<>();
    for (int i = 0; i < words.length; i++) {
        String word = words[i];
        for (int j = 0; j <= word.length(); j++) {
            String left = word.substring(0, j);
            String right = word.substring(j);

            // Left is palindrome + reverse of right exists in dict
            if (isPalin(left) && map.containsKey(new StringBuilder(right).reverse().toString())) {
                int k = map.get(new StringBuilder(right).reverse().toString());
                if (k != i) result.add(Arrays.asList(k, i));
            }

            // Right is palindrome + reverse of left exists in dict (avoid double counting)
            if (j != word.length() && isPalin(right)
                && map.containsKey(new StringBuilder(left).reverse().toString())) {
                int k = map.get(new StringBuilder(left).reverse().toString());
                if (k != i) result.add(Arrays.asList(i, k));
            }
        }
    }
    return result;
}

boolean isPalin(String s) {
    int l = 0, r = s.length() - 1;
    while (l < r) if (s.charAt(l++) != s.charAt(r--)) return false;
    return true;
}
```

---

## 11 — Visual: Trie Insert & Search

```
Insert "cat", "car", "card" into an empty Trie:

root
 └─ c
     └─ a
         └─ t (isEnd=true)   ← "cat"
         └─ r (isEnd=true)   ← "car"
             └─ d (isEnd=true) ← "card"

Search "car":  root → c → a → r  (isEnd=true) → FOUND
Search "ca":   root → c → a      (isEnd=false) → NOT A WORD (but prefix exists)
Search "cab":  root → c → a → b  (node doesn't exist) → NOT FOUND

startsWith("ca"): root → c → a → exists → true  (prefix search)
startsWith("cb"): root → c → b → doesn't exist → false

26-child array at each node:
  children[0] = 'a', children[1] = 'b', ..., children[25] = 'z'
  children[c - 'a'] to map char → array index
```

---

## 🧠 Unseen Problem Walkthrough

**Problem**: Design a data structure that supports: (1) `insert(word)`, (2) `countWordsStartingWith(prefix)` — returns how many inserted words have the given prefix. *(Variation of LC 1268)*

**Step 1 — Read**: Insert words, then count words sharing a given prefix. Not just "exists" but count.

**Step 2 — Identify**: Prefix queries → **Trie**. To count, add a `count` field at each TrieNode that increments on every insert passing through that node.

**Step 3 — Plan**:
- `TrieNode`: `children[26]`, `int count` (how many words passed through here), `boolean isEnd`.
- `insert(word)`: traverse/create nodes for each char; increment `count` at every node; set `isEnd` at last.
- `countWordsStartingWith(prefix)`: traverse to the last node of prefix; return `node.count`.

**Step 4 — Code**:
```java
class Trie {
    private static class Node {
        Node[] ch = new Node[26];
        int count = 0;
        boolean isEnd = false;
    }

    private final Node root = new Node();

    public void insert(String word) {
        Node cur = root;
        for (char c : word.toCharArray()) {
            int idx = c - 'a';
            if (cur.ch[idx] == null) cur.ch[idx] = new Node();
            cur = cur.ch[idx];
            cur.count++;               // increment on every pass-through
        }
        cur.isEnd = true;
    }

    public int countWordsStartingWith(String prefix) {
        Node cur = root;
        for (char c : prefix.toCharArray()) {
            int idx = c - 'a';
            if (cur.ch[idx] == null) return 0;
            cur = cur.ch[idx];
        }
        return cur.count;
    }
}
```

**Step 5 — Verify**:
- Insert "apple", "app", "apply":
  - After inserts, node 'a'→'p'→'p' has `count=3`.
- `countWordsStartingWith("app")` → traverse a,p,p → return 3. ✓
- `countWordsStartingWith("appl")` → traverse a,p,p,l → count=2. ✓

---

## ⚠️ Edge Cases & Small Tweaks

| Scenario | What breaks | Fix |
|----------|-------------|-----|
| Empty string insert | `isEnd=true` at root | Decide if empty string is a valid word; handle if needed |
| Search for prefix of nothing | Empty prefix → all words match | Return `root.count` |
| Case-sensitive vs insensitive | `c - 'a'` fails for uppercase | Normalize: `Character.toLowerCase(c) - 'a'` |
| Non-alpha chars | Index out of bounds on `children[26]` | Use `HashMap<Character, Node>` instead of array |
| Delete a word | Standard Trie has no delete | Decrement `count`; clear `isEnd`; prune if `count==0` |
| Wildcard '.' (LC 211) | Can't use index directly | At '.' node: recursively search all 26 children |

```java
// Wildcard search (LC 211 — WordDictionary):
boolean search(String word, int idx, TrieNode node) {
    if (idx == word.length()) return node.isEnd;
    char c = word.charAt(idx);
    if (c == '.') {
        for (TrieNode child : node.children)
            if (child != null && search(word, idx + 1, child)) return true;
        return false;
    }
    TrieNode next = node.children[c - 'a'];
    return next != null && search(word, idx + 1, next);
}

// XOR Trie (max XOR pair — LC 421): store bits from MSB to LSB
// At each bit, try to go to the OPPOSITE bit to maximize XOR.
```

---

## 😵 Commonly Confused With

**vs HashMap for word lookup**: A HashMap is O(1) for exact match but can't do prefix queries efficiently. Deciding question: *Do you need prefix queries, common prefix counting, or auto-complete? → Trie. Just exact membership? → HashSet.*

**vs Binary Search on sorted strings**: Binary search can find a word in O(L log n) but can't count prefixes efficiently without extra indexing. Deciding question: *Is the word list static and you just need sorted order (binary search), or dynamic with prefix queries (Trie)?*

**vs Suffix Array**: A suffix array indexes all suffixes of one large string. A Trie indexes many separate strings. Deciding question: *Are you searching for patterns inside ONE big string (suffix array/trie of that string), or looking up words from a dictionary of separate strings (Trie)?*

---

## 12 — Canonical LeetCode Problems

| Flavor | Problems |
|--------|---------|
| Standard Trie | LC 208, LC 2135 |
| Wildcard search | LC 211 |
| Board + dictionary | LC 212 |
| Prefix replacement | LC 648 |
| XOR maximization | LC 421, LC 1707 |
| Autocomplete design | LC 1268, LC 642 |
| Palindrome + Trie | LC 336 |

---

## 12 — System Design Connection

- **Typeahead / Autocomplete** (Google Search, Bing): Trie built from historical queries; top-K completions per prefix served from Redis/Memcached
- **IP routing (LPM — Longest Prefix Match)**: routers use binary Tries over IP prefix bits; CIDR blocks are Trie paths
- **Spell checker / keyboard autocorrect**: Trie traversal with edit distance (BK-tree is a variant)
- **DNS resolution**: hierarchical name lookup is conceptually a Trie over labels (`.com`, `google.com`, `www.google.com`)
