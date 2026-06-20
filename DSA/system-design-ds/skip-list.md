# Skip List
**Category**: Probabilistic Data Structure — sorted ordered set with O(log N) operations; used in Redis Sorted Sets, LevelDB MemTable

---

## 1. The Problem It Solves

### Sorted Data at Scale

A sorted array gives O(log N) search (binary search) but O(N) insert/delete (shifting). A balanced BST (Red-Black, AVL) gives O(log N) for all ops but requires complex rebalancing rotations — hard to make lock-free.

```
Structure           Search      Insert      Delete      Lock-free?    Implementation
─────────────────────────────────────────────────────────────────────────────────────
Sorted Array        O(log N)    O(N)        O(N)        Possible      Simple
Red-Black Tree      O(log N)    O(log N)    O(log N)    Hard          Complex
Skip List           O(log N)*   O(log N)*   O(log N)*   Yes           Moderate
B-Tree              O(log N)    O(log N)    O(log N)    Hard          Complex

* expected, with high probability
```

Skip lists achieve balanced BST performance with a simpler structure and natural lock-free concurrency.

---

## 2. Algorithm

### 2.1 Structure

A skip list is a **multi-level linked list**:
- **Level 0**: contains all elements (full sorted linked list).
- **Level 1**: contains ~N/2 elements (express lane skipping every other node).
- **Level k**: contains ~N/2^k elements.

Each node stores a key/value and an array of forward pointers, one per level.

```
Level 3: head ──────────────────────────────────────────────────────► null
Level 2: head ──────────────────────────── 50 ──────────────────────► null
Level 1: head ─────────── 20 ──────────── 50 ──────── 80 ───────────► null
Level 0: head ─── 10 ─── 20 ─── 30 ─── 40 ─── 50 ─── 60 ─── 80 ───► null
```

### 2.2 Search

Start at the highest level, move right until the next key exceeds the target, then drop down a level. Repeat until level 0.

```
Search for 60:
Level 2: head → 50 (< 60) → null, drop
Level 1: 50 → 80 (> 60), drop
Level 0: 50 → 60 ✓ found!
```

### 2.3 Insert

- Find the insertion position at each level (same traversal as search, record predecessors).
- Flip coins to determine the new node's height: each level included with probability p=0.5.
- Insert the new node, update forward pointers.

### 2.4 Level Distribution

With probability p=0.5 for each level:
- 50% of nodes are at level 1 only
- 25% at level 2
- 12.5% at level 3, ...

Expected height of a node: 1/(1-p) = 2. Expected max level: log_{1/p}(N) = log₂(N).

---

## 3. Java Implementation

### 3.1 Core Skip List

```java
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;

public class SkipList<K extends Comparable<K>, V> {

    private static final int MAX_LEVEL = 32;
    private static final double PROBABILITY = 0.5;

    @SuppressWarnings("unchecked")
    private static final class Node<K, V> {
        final K key;
        V value;
        final Node<K, V>[] forward;

        @SuppressWarnings("unchecked")
        Node(K key, V value, int level) {
            this.key = key;
            this.value = value;
            this.forward = new Node[level + 1];
        }
    }

    private final Node<K, V> head; // sentinel head
    private int currentLevel = 0;
    private int size = 0;

    @SuppressWarnings("unchecked")
    public SkipList() {
        this.head = new Node<>(null, null, MAX_LEVEL);
    }

    public V get(K key) {
        Node<K, V> current = head;
        for (int i = currentLevel; i >= 0; i--) {
            while (current.forward[i] != null &&
                   current.forward[i].key.compareTo(key) < 0) {
                current = current.forward[i];
            }
        }
        current = current.forward[0];
        if (current != null && current.key.compareTo(key) == 0) return current.value;
        return null;
    }

    @SuppressWarnings("unchecked")
    public void put(K key, V value) {
        Node<K, V>[] update = new Node[MAX_LEVEL + 1];
        Node<K, V> current = head;

        for (int i = currentLevel; i >= 0; i--) {
            while (current.forward[i] != null &&
                   current.forward[i].key.compareTo(key) < 0) {
                current = current.forward[i];
            }
            update[i] = current;
        }

        current = current.forward[0];

        if (current != null && current.key.compareTo(key) == 0) {
            current.value = value; // update existing
            return;
        }

        int newLevel = randomLevel();
        if (newLevel > currentLevel) {
            for (int i = currentLevel + 1; i <= newLevel; i++) update[i] = head;
            currentLevel = newLevel;
        }

        Node<K, V> newNode = new Node<>(key, value, newLevel);
        for (int i = 0; i <= newLevel; i++) {
            newNode.forward[i] = update[i].forward[i];
            update[i].forward[i] = newNode;
        }
        size++;
    }

    @SuppressWarnings("unchecked")
    public boolean remove(K key) {
        Node<K, V>[] update = new Node[MAX_LEVEL + 1];
        Node<K, V> current = head;

        for (int i = currentLevel; i >= 0; i--) {
            while (current.forward[i] != null &&
                   current.forward[i].key.compareTo(key) < 0) {
                current = current.forward[i];
            }
            update[i] = current;
        }

        current = current.forward[0];
        if (current == null || current.key.compareTo(key) != 0) return false;

        for (int i = 0; i <= currentLevel; i++) {
            if (update[i].forward[i] != current) break;
            update[i].forward[i] = current.forward[i];
        }

        while (currentLevel > 0 && head.forward[currentLevel] == null) currentLevel--;
        size--;
        return true;
    }

    // Range query: all entries with key in [fromKey, toKey] inclusive
    public List<Map.Entry<K, V>> range(K fromKey, K toKey) {
        List<Map.Entry<K, V>> result = new ArrayList<>();
        Node<K, V> current = head;

        for (int i = currentLevel; i >= 0; i--) {
            while (current.forward[i] != null &&
                   current.forward[i].key.compareTo(fromKey) < 0) {
                current = current.forward[i];
            }
        }
        current = current.forward[0];

        while (current != null && current.key.compareTo(toKey) <= 0) {
            result.add(Map.entry(current.key, current.value));
            current = current.forward[0];
        }
        return result;
    }

    // Rank: how many keys are < given key (0-indexed rank)
    public int rank(K key) {
        int rank = 0;
        Node<K, V> current = head;
        for (int i = currentLevel; i >= 0; i--) {
            while (current.forward[i] != null &&
                   current.forward[i].key.compareTo(key) < 0) {
                rank++;
                current = current.forward[i];
            }
        }
        return rank;
    }

    public int size() { return size; }

    private int randomLevel() {
        int level = 0;
        while (level < MAX_LEVEL &&
               ThreadLocalRandom.current().nextDouble() < PROBABILITY) level++;
        return level;
    }
}
```

### 3.2 Concurrent Skip List (lock-free insert)

Java's standard library already has `ConcurrentSkipListMap<K,V>` (backed by a lock-free skip list). Use it directly in production:

```java
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.*;

public class LeaderboardService {

    // score → userId (negative score for descending order)
    private final ConcurrentSkipListMap<Double, String> board = new ConcurrentSkipListMap<>();
    private final Map<String, Double> scores = new java.util.concurrent.ConcurrentHashMap<>();

    public void updateScore(String userId, double newScore) {
        Double oldScore = scores.get(userId);
        if (oldScore != null) board.remove(-oldScore, userId);
        board.put(-newScore, userId); // negate for descending order
        scores.put(userId, newScore);
    }

    // Top-K leaderboard
    public List<Map.Entry<String, Double>> topK(int k) {
        List<Map.Entry<String, Double>> result = new ArrayList<>(k);
        for (Map.Entry<Double, String> entry : board.entrySet()) {
            result.add(Map.entry(entry.getValue(), -entry.getKey()));
            if (result.size() == k) break;
        }
        return result;
    }

    // Rank of a user (1-indexed)
    public int rankOf(String userId) {
        Double score = scores.get(userId);
        if (score == null) return -1;
        return board.headMap(-score).size() + 1;
    }

    // Users within score range [minScore, maxScore]
    public List<String> usersInRange(double minScore, double maxScore) {
        return new ArrayList<>(board.subMap(-maxScore, true, -minScore, true).values());
    }
}
```

### 3.3 Redis Sorted Set Commands (backed by skip list + hash map)

```java
// Redis Sorted Set commands — backed by skip list for O(log N) rank queries
// jedis.zadd(key, score, member)    → insert/update
// jedis.zrank(key, member)          → rank (ascending, 0-indexed)
// jedis.zrevrank(key, member)       → rank (descending)
// jedis.zrangebyscore(key, min, max) → members in score range
// jedis.zrange(key, start, stop)    → members by rank range

import redis.clients.jedis.Jedis;

public class RedisLeaderboard {

    private final Jedis jedis;
    private final String key;

    public RedisLeaderboard(Jedis jedis, String gameId) {
        this.jedis = jedis;
        this.key = "leaderboard:" + gameId;
    }

    public void addOrUpdate(String userId, double score) {
        jedis.zadd(key, score, userId);
    }

    public long rank(String userId) {
        Long r = jedis.zrevrank(key, userId); // descending rank
        return r == null ? -1 : r + 1;        // 1-indexed
    }

    public List<String> topK(int k) {
        return jedis.zrevrange(key, 0, k - 1);
    }

    public Set<String> inScoreRange(double min, double max) {
        return jedis.zrangeByScore(key, min, max);
    }
}
```

---

## 4. Redis Sorted Set Internals

Redis uses a **dual representation** depending on size:
- **Small set (≤128 members, values ≤64 bytes)**: `ziplist` (compact array) — O(N) but tiny data, cache-friendly.
- **Large set**: `skiplist + hashtable` hybrid:
  - Skip list: for rank queries (ZRANK), range queries (ZRANGEBYSCORE), ordered iteration.
  - Hash table: for O(1) score lookup by member (ZSCORE).

```
ZADD user:scores 100 alice
ZADD user:scores  90 bob
ZADD user:scores  95 carol

Skip list view (sorted by score):
  bob(90) → carol(95) → alice(100)
  
Hash table view:
  alice → 100
  bob   → 90
  carol → 95

ZRANK user:scores alice  → 2 (0-indexed: 0=bob, 1=carol, 2=alice)
ZSCORE user:scores alice → 100  (O(1) from hash table)
```

---

## 5. Skip List vs Red-Black Tree

| Attribute | Skip List | Red-Black Tree |
|---|---|---|
| Search | O(log N) expected | O(log N) worst |
| Insert | O(log N) expected | O(log N) worst |
| Delete | O(log N) expected | O(log N) worst |
| Lock-free concurrency | Natural (CAS on forward pointers) | Very hard |
| Memory per node | O(1) expected forward pointers | 2 child pointers + color bit |
| Cache locality | Poor (linked nodes scattered) | Poor |
| Range queries | Excellent (walk level-0 list) | Excellent (in-order traversal) |
| Implementation complexity | Moderate | High |
| Used in production | Redis, LevelDB, Java ConcurrentSkipListMap | Java TreeMap, Linux kernel rbtree |

---

## 6. Where Skip Lists Appear at FAANG

### 6.1 Redis Sorted Sets
The canonical production use. Every `ZADD`, `ZRANK`, `ZRANGEBYSCORE` operates on a skip list. Powers leaderboards, time-series event ordering, priority queues, rate limiters.

### 6.2 LevelDB / RocksDB MemTable
Both use a skip list as the in-memory MemTable (sorted structure). Concurrent writers use a lock-free skip list variant. When the MemTable flushes to an SSTable, the skip list provides in-order iteration.

### 6.3 Apache Lucene
Uses skip lists within posting lists for inverted index compression. Long posting lists store skip table entries at intervals; query intersection jumps to the right offset using skips rather than scanning every entry.

### 6.4 HBase / Cassandra MemTable
HBase's MemStore uses `ConcurrentSkipListMap`. Cassandra's MemTable also uses a concurrent skip list for the in-memory sorted buffer before flush.

---

## 7. FAANG Interview Callouts

**"Design a real-time leaderboard for 100M users":**
> Use Redis Sorted Set (skip list internally). `ZADD leaderboard {score} {userId}` on each score update. `ZREVRANK leaderboard {userId}` for a user's rank — O(log N) = ~26 ops for 100M users. `ZREVRANGE leaderboard 0 9` for top-10. Shard by game/region if a single Redis instance is insufficient (~100K ZADD/sec limit).

**"Why does Redis use a skip list instead of a balanced BST for sorted sets?":**
> Skip lists are simpler to implement correctly (especially the lock-free concurrent variant), support equivalent O(log N) operations, and provide equally efficient range queries via level-0 traversal. Redis author Antirez noted: "I believe that the skip list implementation is harder to get wrong vs. red-black trees, thus easier to maintain." Lock-free skip lists are also far simpler than lock-free AVL/RB trees.

**Follow-up questions to expect:**
1. "What's the probability that a skip list insert is O(N)?" → Probability 2^(-cN) for c>1; essentially 0 at N≥1000 for any practical constant. The skip list is O(log N) with overwhelming probability.
2. "How would you persist a skip list to disk?" → Walk level-0 (all nodes in sorted order), serialize each node. On recovery, insert nodes in sorted order — if heights are regenerated randomly, structure is statistically equivalent.
3. "How does ConcurrentSkipListMap achieve lock-free inserts?" → Uses CAS (compare-and-swap) on forward pointers. A deleted node is first marked with a special marker node, preventing ABA problems. Readers and writers proceed without locks.
