# Consistent Hashing
**Category**: Distributed Systems Algorithm — DS choice for system design interviews

---

## 1. The Problem It Solves

### Naive Modular Hashing

The simplest way to distribute keys across `N` nodes is:

```
node = hash(key) % N
```

**Fatal flaw**: when `N` changes (node added or removed), **almost every key remaps**.

```
Example: 3 nodes, 9 keys (key_0 … key_8)

Initial:  key_0→N0, key_1→N1, key_2→N2, key_3→N0, key_4→N1, key_5→N2 ...

Add N3 (N=4):
  key_0→N0   (unchanged)
  key_1→N1   (unchanged)
  key_2→N2   (unchanged)
  key_3→N3   ← moved!
  key_4→N0   ← moved!
  key_5→N1   ← moved!
  key_6→N2   (unchanged)
  key_7→N3   ← moved!
  key_8→N0   ← moved!

Keys remapped: 5 of 9 = ~56%
```

In a cache cluster this causes a **cache stampede**: all remapped keys miss, flood the origin, and crash it. In a storage cluster it triggers **massive data migration**.

### What Consistent Hashing Guarantees

When a node is added or removed, only `K/N` keys need to move (where `K` = total keys, `N` = number of nodes) — the theoretical minimum. All other keys stay on their current node.

---

## 2. Algorithm Overview — The Hash Ring

### 2.1 The Ring

Both nodes and keys are hashed onto a **virtual circle** (ring) of size `2^32` (for a 32-bit hash function) or `2^64` for 64-bit. The ring wraps around: position `2^32` = position `0`.

```
Hash space: 0 ────────────────────────────────► 2^32 (wraps to 0)

Visualised as a ring:

                    0
                    │
           315 ─────┼───── 45
                    │
           270 ─────┼───── 90
                    │
           225 ─────┼───── 135
                    │
                   180

Nodes placed at their hash positions:
  hash(NodeA) → position 45°
  hash(NodeB) → position 135°
  hash(NodeC) → position 270°

Keys placed at their hash positions:
  hash(key1) → position 80°   → assigned to NodeB (next clockwise node)
  hash(key2) → position 160°  → assigned to NodeC
  hash(key3) → position 300°  → assigned to NodeA (wraps around ring)
```

### 2.2 Key Assignment Rule

> A key is assigned to the **first node encountered when walking clockwise** from the key's position on the ring.

Implementation: maintain a sorted list of node positions. For a given key, binary-search for the first node position ≥ hash(key). If none found (key is past the last node), wrap to the first node on the ring.

### 2.3 Node Addition

```
Before (3 nodes: A=45°, B=135°, C=270°):
  Keys in [45°,135°) → B
  Keys in [135°,270°) → C
  Keys in [270°,45°)  → A   (wraps)

Add NodeD at position 200°:
  Keys in [135°,200°) → D   ← only these keys move (from C to D)
  Keys in [200°,270°) → C   ← untouched
  All other key ranges: untouched
```

Only keys that were previously in the range `(prev_node_position, D_position]` need to move from their old node to D. Everything else is undisturbed.

### 2.4 Node Removal

When NodeB (135°) is removed:
- Keys that were in range `(45°, 135°]` → now assigned to NodeC (next clockwise node)
- Only those keys must migrate. All other keys are untouched.

### 2.5 Complexity

| Operation | Time Complexity |
|---|---|
| Add node | O(K/N) key remappings; O(log N) ring position insert |
| Remove node | O(K/N) key remappings; O(log N) ring position delete |
| Key lookup | O(log N) binary search on sorted node list |
| Space | O(N) for ring positions; O(N×V) with virtual nodes |

---

## 3. Advantages

| Advantage | Detail |
|---|---|
| **Minimal key movement** | Only K/N keys move on topology change vs ~K for modular hashing |
| **No central coordinator** | Each client independently computes the target node; no separate metadata server required |
| **Horizontal scalability** | Add nodes incrementally; each addition dilutes load proportionally |
| **Graceful degradation** | Node failure only impacts keys assigned to that node; other nodes unaffected |
| **Heterogeneous nodes** | Weighted rings allow more powerful nodes to own larger arcs (via more virtual nodes) |
| **Cache-friendly** | Cache hit rate during ring changes only drops for the K/N migrating keys, not all keys |
| **No resharding storm** | Unlike modular hashing, avoids the "thundering herd" when cache cluster is resized |
| **Decentralised** | Used in peer-to-peer systems (Chord DHT) without any central directory |

---

## 4. The Virtual Nodes Problem & Solution

### 4.1 Why Bare Rings Have Load Imbalance

With 3 real nodes placed at their hash positions, the ring is divided into **3 arcs of random length**. Due to hash randomness, these arcs will be unequal in size.

```
Example with a perfect (but unlucky) hash:
  NodeA → position 5°
  NodeB → position 10°
  NodeC → position 180°

Arc ownership:
  NodeA owns [180°, 5°)  = 185° arc  → ~51% of all keys
  NodeB owns [5°, 10°)   =   5° arc  → ~1.4% of all keys
  NodeC owns [10°, 180°) = 170° arc  → ~47% of all keys

NodeB is severely underloaded; NodeA is overloaded.
```

With few physical nodes the variance is enormous. Simulation shows:
```
N=3 nodes, no vnodes: std dev of load ≈ ±40% of mean
N=10 nodes, no vnodes: std dev ≈ ±20% of mean
N=100 nodes, no vnodes: std dev ≈ ±7% of mean
N=3 nodes, V=150 vnodes: std dev ≈ ±3% of mean
```

### 4.2 Virtual Nodes (vnodes)

Each physical node is assigned **V positions** on the ring instead of 1. Each position is a **virtual node** (vnode). The ring now has `N × V` positions total.

```
Physical nodes: A, B, C
Virtual factor: V = 3

Hash each as:
  A → hash("NodeA-0"), hash("NodeA-1"), hash("NodeA-2")
  B → hash("NodeB-0"), hash("NodeB-1"), hash("NodeB-2")
  C → hash("NodeC-0"), hash("NodeC-1"), hash("NodeC-2")

Ring (9 positions, interleaved):

  0°──[A-2]──45°──[B-0]──90°──[C-1]──135°──[A-0]──180°──[B-2]──220°──[C-0]──270°──[A-1]──300°──[B-1]──330°──[C-2]──360°

Key assignment:
  A owns: [C-2..A-2] + [C-1..A-0] + [B-2..A-1] = three non-contiguous arcs totalling ~33%
  B owns: [A-2..B-0] + [A-0..B-2] + [A-1..B-1] = three non-contiguous arcs totalling ~33%
  C owns: [B-0..C-1] + [B-2..C-0] + [B-1..C-2] = three non-contiguous arcs totalling ~33%
```

Load converges to uniform as V increases. Law of large numbers in action.

### 4.3 Choosing V (Virtual Node Count)

| V | Load std dev (N=3) | Memory overhead | Used by |
|---|---|---|---|
| 1 | ±40% | Minimal | Avoid |
| 10 | ±15% | Low | Development only |
| 100 | ±5% | Moderate | Acceptable |
| 150 | ±3.5% | Moderate | Cassandra default |
| 256 | ±2.5% | Higher | Dynamo/DynamoDB |
| 1000 | ±1% | High | Redis Cluster (16384 slots) |

**Rule of thumb**: V=150 gives good load balance for N≥3. For weighted nodes (one node 2× the size), assign 2V vnodes to the larger node.

### 4.4 Node Addition with Vnodes

```
Adding NodeD with V=3:
  D gets 3 random positions on the ring: [D-0, D-1, D-2]
  For each vnode D-i, the range (predecessor, D-i] is claimed from its current owner
  3 × (K / N×V) keys move per vnode = 3K / (N×V) total

With N=3, V=150, adding 1 node:
  Keys that move ≈ K/4 = 25% — mathematically optimal for adding 1 of 4 nodes
  Those keys are evenly spread across all 3 existing nodes (each loses 1/3 of the 25%)
```

---

## 5. Implementation

### 5.1 Core Data Structures

```python
import hashlib
import bisect
from collections import defaultdict

class ConsistentHashRing:
    """
    Hash ring with virtual nodes.
    Uses sorted list + binary search for O(log N*V) lookup.
    """

    def __init__(self, virtual_nodes: int = 150, hash_fn=None):
        self.virtual_nodes = virtual_nodes
        self.hash_fn = hash_fn or self._md5_hash

        # Sorted list of virtual node positions on the ring
        self._ring_positions: list[int] = []

        # Maps position → physical node name
        self._position_to_node: dict[int, str] = {}

        # Maps node name → list of its positions (for removal)
        self._node_to_positions: dict[str, list[int]] = defaultdict(list)

    def _md5_hash(self, key: str) -> int:
        """Returns a 32-bit integer position on the ring."""
        digest = hashlib.md5(key.encode()).hexdigest()
        return int(digest[:8], 16)  # first 8 hex chars = 32-bit int

    def add_node(self, node: str) -> None:
        for i in range(self.virtual_nodes):
            vnode_key = f"{node}#vn{i}"
            position = self.hash_fn(vnode_key)

            # Insert into sorted position list (bisect maintains order)
            bisect.insort(self._ring_positions, position)
            self._position_to_node[position] = node
            self._node_to_positions[node].append(position)

    def remove_node(self, node: str) -> None:
        for position in self._node_to_positions.get(node, []):
            idx = bisect.bisect_left(self._ring_positions, position)
            if idx < len(self._ring_positions) and self._ring_positions[idx] == position:
                self._ring_positions.pop(idx)
            del self._position_to_node[position]
        del self._node_to_positions[node]

    def get_node(self, key: str) -> str | None:
        """Return the node responsible for this key."""
        if not self._ring_positions:
            return None

        position = self.hash_fn(key)

        # Binary search: find index of first ring position >= key position
        idx = bisect.bisect_left(self._ring_positions, position)

        # Wrap around: if past the last node, map to first node
        if idx == len(self._ring_positions):
            idx = 0

        return self._position_to_node[self._ring_positions[idx]]

    def get_nodes(self, key: str, count: int) -> list[str]:
        """
        Return `count` distinct physical nodes for replication.
        Walks clockwise, skipping vnodes that map to already-seen physical nodes.
        Used by Dynamo-style systems for replica placement.
        """
        if not self._ring_positions:
            return []

        position = self.hash_fn(key)
        idx = bisect.bisect_left(self._ring_positions, position)
        if idx == len(self._ring_positions):
            idx = 0

        result = []
        seen = set()
        attempts = 0
        max_attempts = len(self._ring_positions)

        while len(result) < count and attempts < max_attempts:
            actual_idx = (idx + attempts) % len(self._ring_positions)
            node = self._position_to_node[self._ring_positions[actual_idx]]
            if node not in seen:
                result.append(node)
                seen.add(node)
            attempts += 1

        return result
```

### 5.2 Usage Example

```python
ring = ConsistentHashRing(virtual_nodes=150)

# Build cluster
for node in ["node-1", "node-2", "node-3"]:
    ring.add_node(node)

# Key routing
print(ring.get_node("user:12345"))        # → "node-2"
print(ring.get_node("session:abc"))       # → "node-1"

# Replication: 3 replicas for a key
print(ring.get_nodes("user:12345", 3))   # → ["node-2", "node-3", "node-1"]

# Add a node — only K/N keys remapped
ring.add_node("node-4")
print(ring.get_node("user:12345"))        # → "node-4" or "node-2" (depends on ring)

# Remove a node — only its keys migrate to successor
ring.remove_node("node-2")
```

### 5.3 Load Distribution Test

```python
def test_load_distribution(virtual_nodes: int = 150, num_keys: int = 100_000):
    ring = ConsistentHashRing(virtual_nodes=virtual_nodes)
    nodes = ["node-1", "node-2", "node-3"]
    for n in nodes:
        ring.add_node(n)

    counts = defaultdict(int)
    for i in range(num_keys):
        node = ring.get_node(f"key-{i}")
        counts[node] += 1

    expected = num_keys / len(nodes)
    print(f"V={virtual_nodes}, keys={num_keys}")
    for node, count in sorted(counts.items()):
        deviation = (count - expected) / expected * 100
        print(f"  {node}: {count} keys ({deviation:+.1f}% from ideal)")

# Results (representative):
# V=1:    node-1: 52318 (+57%), node-2: 3201 (-90%), node-3: 44481 (+33%)  ← terrible
# V=10:   node-1: 35201 (+6%),  node-2: 28910 (-13%), node-3: 35889 (+8%)  ← poor
# V=150:  node-1: 33891 (+2%),  node-2: 32741 (-2%),  node-3: 33368 (+0%)  ← good
# V=1000: node-1: 33423 (+0%),  node-2: 33312 (-0%),  node-3: 33265 (-0%)  ← excellent
```

### 5.4 Java Implementation (production-style, thread-safe)

```java
import java.security.MessageDigest;
import java.util.SortedMap;
import java.util.TreeMap;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

public class ConsistentHashRing<T> {
    private final int virtualNodes;
    private final TreeMap<Long, T> ring = new TreeMap<>();
    private final ReadWriteLock lock = new ReentrantReadWriteLock();

    public ConsistentHashRing(int virtualNodes) {
        this.virtualNodes = virtualNodes;
    }

    public void addNode(T node) {
        lock.writeLock().lock();
        try {
            for (int i = 0; i < virtualNodes; i++) {
                long hash = hashKey(node.toString() + "#vn" + i);
                ring.put(hash, node);
            }
        } finally {
            lock.writeLock().unlock();
        }
    }

    public void removeNode(T node) {
        lock.writeLock().lock();
        try {
            for (int i = 0; i < virtualNodes; i++) {
                long hash = hashKey(node.toString() + "#vn" + i);
                ring.remove(hash);
            }
        } finally {
            lock.writeLock().unlock();
        }
    }

    public T getNode(String key) {
        lock.readLock().lock();
        try {
            if (ring.isEmpty()) return null;
            long hash = hashKey(key);
            SortedMap<Long, T> tail = ring.tailMap(hash);
            // clockwise lookup; wrap if past last position
            Long pos = tail.isEmpty() ? ring.firstKey() : tail.firstKey();
            return ring.get(pos);
        } finally {
            lock.readLock().unlock();
        }
    }

    private long hashKey(String key) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(key.getBytes());
            // Combine 4 bytes into a long (positive, 32-bit range)
            return ((long)(digest[3] & 0xFF) << 24)
                 | ((long)(digest[2] & 0xFF) << 16)
                 | ((long)(digest[1] & 0xFF) << 8)
                 | ((long)(digest[0] & 0xFF));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }
}
```

---

## 6. Types of Consistent Hashing Algorithms

### 6.1 Classic Ring Hashing (Karger et al., 1997)

The foundational algorithm described above. Introduced in the MIT paper "Consistent Hashing and Random Trees".

```
Hash function: any (MD5, SHA-1, MurmurHash3 recommended)
Data structure: sorted array / TreeMap
Lookup: O(log N×V)
Space: O(N×V)
Load distribution: good with V ≥ 150
Used by: original Akamai CDN, Chord DHT
```

**Characteristics**:
- Simple to implement
- Memory proportional to vnode count
- Ring must be managed and distributed to all clients
- Suitable when the client library caches the ring in memory

---

### 6.2 Ketama Consistent Hashing

A specific, widely-deployed implementation originally created for memcached by Last.fm. Now the de facto standard for memcached client libraries.

```
Hash function: MD5 (produces 128-bit digest; uses 4 × 32-bit windows per key)
  → Each node gets 40 × 4 = 160 virtual positions per node by default

Key computation:
  For node "cache1:11211" with weight 1:
    vnode_key = "cache1:11211-{i}"  for i in 0..39
    md5_bytes = MD5(vnode_key)
    position_j = (md5_bytes[j*4+3] << 24) | (md5_bytes[j*4+2] << 16)
               | (md5_bytes[j*4+1] << 8)  | (md5_bytes[j*4])
               for j in 0..3  → 4 positions per hash call

  Total: 40 calls × 4 positions = 160 vnodes per node

Weighting: weighted_vnodes = base_vnodes × (weight / total_weight) × N
```

**Pros**: Widely supported (Ruby, Python, PHP, Java memcached clients), proven in production at scale.
**Cons**: MD5 is cryptographically heavy; 160 vnodes per node may be insufficient for very few nodes.

---

### 6.3 Jump Consistent Hashing (Google, 2014)

A space-efficient algorithm that requires **no ring data structure**. Computes node assignment via a deterministic loop using only a 64-bit integer.

```python
def jump_hash(key: int, num_buckets: int) -> int:
    """
    Assigns key to one of num_buckets buckets.
    O(log N) time, O(1) space — no ring stored.
    key must be a 64-bit integer (hash your string key first).
    """
    b, j = -1, 0
    while j < num_buckets:
        b = j
        key = ((key * 2862933555777941757) + 1) & 0xFFFFFFFFFFFFFFFF
        j = int((b + 1) * (1 << 31) / ((key >> 33) + 1))
    return b
```

```
Usage:
  import mmh3  # MurmurHash3
  key_int = mmh3.hash64("user:12345")[0]
  node_index = jump_hash(key_int, num_nodes=5)  # → 0-4

Properties:
  - O(log N) time, O(1) space (no ring stored anywhere)
  - Perfect uniform distribution (mathematically proven)
  - No virtual nodes needed — inherently balanced
  - Can ONLY add nodes to the END of the list (not arbitrary positions)
  - Cannot weight nodes differently
  - Node removal requires renumbering → not suitable for arbitrary topology changes
```

**Best for**: Stateless sharding where the number of shards changes monotonically (only additions). Google uses it for internal storage sharding.

**Not suitable for**: Arbitrary node removal (e.g., a cache node crashes — must re-number remaining nodes, causing remapping of K/N keys but from a different distribution than ring hashing).

---

### 6.4 Rendezvous Hashing (HRW — Highest Random Weight)

Also called **HRW hashing**. Each node computes a score for a given key; the key goes to the node with the **highest score**.

```python
import hashlib

def hrw_hash(key: str, node: str) -> int:
    combined = f"{key}:{node}"
    return int(hashlib.sha256(combined.encode()).hexdigest(), 16)

def get_node_hrw(key: str, nodes: list[str]) -> str:
    """Returns node with highest score for this key."""
    return max(nodes, key=lambda node: hrw_hash(key, node))

# For k replicas:
def get_nodes_hrw(key: str, nodes: list[str], k: int) -> list[str]:
    scored = sorted(nodes, key=lambda n: hrw_hash(key, n), reverse=True)
    return scored[:k]
```

```
Properties:
  - O(N) lookup (must score all N nodes)
  - O(1) space (no ring, no vnode table — just the node list)
  - Perfectly uniform distribution (each node equally likely to win)
  - No virtual nodes needed
  - Supports arbitrary node removal (just remove from the list; only K/N keys remap)
  - Easy to weight: repeat a node in the list or use weighted scoring
```

**Best for**: Small-to-medium N (< 100 nodes) where O(N) lookup is acceptable. Used by Nginx (upstream selection), Varnish (cache routing), some CDN implementations.

**Not suitable for**: Very large N (1000+ nodes) where O(N) per-key lookup is too expensive.

---

### 6.5 Maglev Consistent Hashing (Google, 2016)

Designed for Google's Maglev load balancer. The goal: **O(1) lookup** with **near-perfect consistency**.

```
Pre-computation phase: build a lookup table M of size M (prime, e.g., 65537)
  For each backend server i:
    Generate a permutation of [0..M-1] using:
      offset_i  = hash1(backend_i) % M
      skip_i    = hash2(backend_i) % (M-1) + 1
      perm_i[j] = (offset_i + j * skip_i) % M  for j in 0..M-1

  Fill lookup table:
    table = [-1] * M
    next_i = [0] * N  # next position in each backend's permutation
    filled = 0
    while filled < M:
      for i in range(N):
        c = perm_i[next_i[i]]
        while table[c] != -1:
          next_i[i] += 1
          c = perm_i[next_i[i]]
        table[c] = i  # backend i claims slot c
        next_i[i] += 1
        filled += 1

Lookup phase (O(1)):
  key_hash = hash(key) % M
  backend_index = table[key_hash]
```

```
Properties:
  - O(1) lookup (single array index)
  - O(M × N) pre-computation (done once on topology change)
  - Near-consistent: ~1/N keys remap on single server add/remove (slightly more than theoretical minimum)
  - Very low load variance (fill algorithm ensures near-equal distribution)
  - Table must be rebuilt on topology change — expensive for large M and N
```

**Best for**: High-frequency load balancing where O(1) lookup is critical and topology changes are infrequent. Google uses it for network load balancing at line rate.

**Not suitable for**: Frequent topology changes (table rebuild is expensive); caches with frequent node churn.

---

### 6.6 Algorithm Comparison Table

| Algorithm | Lookup Time | Space | Load Balance | Handles Removal | Weighting | Best Use Case |
|---|---|---|---|---|---|---|
| Ring (Karger) | O(log N·V) | O(N·V) | Good (V≥150) | ✅ Any node | ✅ Via vnode count | General-purpose; most common |
| Ketama | O(log N·V) | O(N·V) | Good | ✅ Any node | ✅ Via weight param | Memcached, legacy cache clusters |
| Jump Hash | O(log N) | O(1) | Perfect | ❌ End-only | ❌ | Append-only sharding (storage tiers) |
| Rendezvous (HRW) | O(N) | O(1) | Perfect | ✅ Any node | ✅ Easy | Small N; CDN, load balancers |
| Maglev | O(1) | O(M×N) | Near-perfect | ✅ (rebuild) | ✅ (via entries) | High-frequency L4 load balancing |

---

## 7. Hash Function Selection

The choice of hash function affects distribution quality and performance.

| Hash Function | Speed | Collision Resistance | Distribution Quality | Use Case |
|---|---|---|---|---|
| **MurmurHash3** | Very fast (< 10ns) | Non-crypto | Excellent | **Recommended default** — Cassandra, Redis, Kafka |
| **xxHash64** | Fastest (< 5ns) | Non-crypto | Excellent | High-throughput systems; Clickhouse, LZ4 |
| **FNV-1a** | Fast (< 15ns) | Non-crypto | Good | Embedded systems; simple implementations |
| **MD5** | Slow (> 100ns) | Crypto (broken) | Excellent | Ketama memcached; legacy — avoid for new systems |
| **SHA-1** | Very slow (> 200ns) | Crypto (weak) | Excellent | Avoid — use MurmurHash3 instead |
| **CRC32** | Very fast | Non-crypto | Poor (patterns in data) | Avoid — biased distribution |

**Recommendation**: Use MurmurHash3 (128-bit, take lower 64 bits) for new implementations. It has zero known weaknesses for non-cryptographic hashing and is extremely fast.

```python
import mmh3  # pip install murmurhash

def murmur_hash(key: str, seed: int = 42) -> int:
    # Returns a 64-bit unsigned integer
    return mmh3.hash64(key, seed=seed)[0] & 0xFFFFFFFFFFFFFFFF
```

### Protecting Against Hash DoS (HashFlood)

If the hash function is predictable, an attacker can craft keys that all hash to the same node (hash flooding attack). For publicly-facing systems:

- Use a **seeded hash** with a server-side secret seed (MurmurHash3 with random seed)
- Or use **SipHash** (designed for hash-table DoS resistance, used in Python, Ruby, Rust)

```python
import siphash
secret_key = os.urandom(16)

def sip_hash(key: str) -> int:
    return siphash.SipHash_2_4(secret_key, key.encode()).hash()
```

---

## 8. Replication with Consistent Hashing

For fault tolerance, each key is stored on multiple nodes. The standard approach (Dynamo-style):

```
Replication factor = N (typically 3)

Primary replica: first node clockwise from key's position
Replica 2:       second distinct physical node clockwise
Replica 3:       third distinct physical node clockwise

Critical detail: skip vnodes belonging to the same physical node.
When walking clockwise for replicas, skip any vnode whose physical node
is already in the replica set.

def get_replicas(key, replication_factor):
    start_idx = binary_search(ring, hash(key))
    replicas = []
    seen_nodes = set()
    for i in range(len(ring)):
        idx = (start_idx + i) % len(ring)
        node = ring[idx].physical_node
        if node not in seen_nodes:
            replicas.append(node)
            seen_nodes.add(node)
        if len(replicas) == replication_factor:
            break
    return replicas
```

**Rack/zone awareness**: Extend the skip logic to also skip nodes in the same rack/AZ until at least one replica is placed per rack:

```python
# Prefer: replica 1 in zone-A, replica 2 in zone-B, replica 3 in zone-C
# This ensures the data survives a full AZ failure.
# Cassandra NetworkTopologyStrategy does exactly this.
```

---

## 9. Real-World Usage

| System | Variant | V (Vnodes) | Notes |
|---|---|---|---|
| **Apache Cassandra** | Ring (Karger) | 256 per node | `num_tokens=256`; uses Murmur3; NetworkTopologyStrategy for multi-DC |
| **Amazon DynamoDB** | Ring (Dynamo) | 100–200 | Original Dynamo paper (2007); popularised consistent hashing |
| **Redis Cluster** | Slot-based | 16,384 slots | Fixed slot ring, not arbitrary positions; slots assigned to nodes |
| **Memcached (Ketama)** | Ketama | 160 | MD5-based; standard across all language clients |
| **Apache Kafka** | Modular (not CH) | N/A | Partition → broker via round-robin; no consistent hashing |
| **Riak** | Ring (Dynamo-style) | 64–4096 | Configurable ring size |
| **Couchbase** | vBucket map | 1024 vBuckets | Consistent hash variant with explicit vBucket-to-node map |
| **Nginx** (upstream) | Rendezvous (HRW) | N/A | `consistent_hash` directive; uses CRC32 (switch to Murmur3) |
| **Envoy Proxy** | Maglev / Ring | Configurable | Both Maglev and Ring available as load balancing policies |
| **Chord DHT** | Ring (Finger table) | O(log N) | P2P distributed hash table; each node stores only O(log N) pointers |

---

## 10. Common Pitfalls & Interview Traps

### Pitfall 1: Forgetting the Wrap-Around

```
Bug: idx = bisect_left(ring, key_hash)
     return ring[idx]           # IndexError if key_hash > all positions!
Fix: if idx == len(ring): idx = 0
```

### Pitfall 2: Physical vs Virtual Node Confusion for Replicas

```
Wrong: walk clockwise and take the next 3 positions
       → all 3 might be vnodes of the same physical node

Right: walk clockwise, collect distinct physical nodes until count == replication_factor
```

### Pitfall 3: Hash Space Collision

Two vnodes hashing to the same position. With 32-bit hash and N=3, V=150: 450 positions in a 4 billion-position space — collision probability is negligible. With 16-bit hash or massive vnode counts, collisions are a real concern. Use 64-bit hashes.

### Pitfall 4: Ring Inconsistency Across Clients

```
Problem: Client A has ring state {A, B, C}; Client B has {A, B, C, D} (just added).
         Same key routes to different nodes.

Mitigations:
  a. Gossip protocol: nodes broadcast ring state; clients refresh ring from any node
  b. Consistent versioning: ring has a version counter; clients check version on connect
  c. Central ring registry (ZooKeeper/etcd): clients watch for updates
  d. Server-side routing: client sends to any node; node forwards to owner (Dynamo's "sloppy quorum")
```

### Pitfall 5: Hot Key Problem

A single extremely popular key (e.g., a celebrity's profile) overwhelms its assigned node. Consistent hashing distributes keys uniformly but cannot distribute **load per key**.

**Solutions**:
- Application-level sharding: `hash(key + random_suffix_1..N)` spreads hot key across N nodes
- Read replicas: route reads to any replica, not just the primary
- Local cache (L1): popular keys cached in-process before hitting the ring

---

## 11. Trade-Off Summary

| Trade-Off | Ring Hashing Decision | When to Reconsider |
|---|---|---|
| More virtual nodes (V) | Better load balance but more memory | V=150 is sweet spot; increase if < 5 nodes |
| Async vs consistent ring views | Simpler but transient routing errors | Use versioned ring + retry if strict routing correctness required |
| MD5 vs MurmurHash3 | MurmurHash3 is 10× faster | MD5 only for Ketama compatibility |
| Active-passive vs ring replication | Ring replication enables N-replica writes | For caches, single-replica is fine; for storage, use 3-replica |
| Consistent hashing vs sharding | CH wins for dynamic topology | Static partition count (Kafka) is simpler when topology never changes |

---

## FAANG Interview Callout

> "If I have 3 cache nodes and add a 4th, how many cache keys need to move in consistent hashing vs. modular hashing, and what is the user-visible impact?"

**Answer**:
- Modular hashing: `hash(key) % 3` → `hash(key) % 4`. About 75% of keys remap. Miss rate on the cache jumps from ~0% to ~75% for the duration of the migration → cache stampede → origin overloaded.
- Consistent hashing: only `K/4` keys (25%) move, and they move only from their current node to the new node. The miss rate spike is 25% and is temporary (seconds to minutes as the new node warms up).
- With virtual nodes (V=150): the 25% that moves is evenly spread across all 3 existing nodes (each loses ~8.3%), so no single node is drained. The new node fills up smoothly via LRU fill as misses hit origin.

> "Why does Cassandra use 256 vnodes per node instead of 1?"

**Answer**: With only 1 token per node (original Cassandra v1 design), each node owns one contiguous arc. Adding a node means copying a single large range from one node to the new one — that one source node becomes a replication bottleneck. With 256 vnodes, the new node's 256 positions are distributed across the ring, so data flows from 256 different source nodes simultaneously — **parallelising the streaming repair and avoiding a single hotspot during node bootstrap**.
