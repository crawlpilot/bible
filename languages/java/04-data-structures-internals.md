# 04 — Java Data Structures Internals

**Calibration:** Principal Engineer bar  
**Focus:** Implementation mechanics, not API. This is where principal engineers separate from senior engineers.

---

## Thread Safety Summary (Quick Reference)

| Structure | Thread Safe? | Notes |
|-----------|-------------|-------|
| `HashMap` | No | Fail-fast iterators, infinite loop in Java 7 resize under race |
| `ConcurrentHashMap` | Yes | Lock-free reads, bin-level locking for writes |
| `ArrayList` | No | Fail-fast iterators via `modCount` |
| `CopyOnWriteArrayList` | Yes | Full array copy on write — O(n) writes, O(1) reads |
| `LinkedList` | No | Not thread safe, not cache-friendly |
| `ArrayDeque` | No | Fastest queue/stack for single-threaded use |
| `TreeMap` | No | Use `Collections.synchronizedSortedMap` or `ConcurrentSkipListMap` |
| `PriorityQueue` | No | Use `PriorityBlockingQueue` |
| `EnumMap` | No | Always prefer over `HashMap<MyEnum,V>` for single-threaded use |
| `EnumSet` | No | Bitmask-based, always prefer over `HashSet<MyEnum>` |

---

## 1. HashMap Internals

### Data Structure

```
HashMap<K,V> internals:

  table: Node<K,V>[]      ← backing array (initially null, lazy init)
  size: int               ← number of key-value pairs
  threshold: int          ← size at which to resize (capacity × loadFactor)
  loadFactor: float       ← default 0.75
  modCount: int           ← structural modification count (for fail-fast)

  Node<K,V>:
    hash: int             ← cached hash
    key: K
    value: V
    next: Node<K,V>       ← linked list chain (or null)

  TreeNode<K,V> extends LinkedHashMap.Entry<K,V>:
    ← replaces Node when bucket chain reaches threshold 8
    ← red-black tree internally
```

### Hash Function — The Critical Detail

```java
// HashMap.hash() in JDK source
static final int hash(Object key) {
    int h;
    return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
}
```

Why XOR with the upper 16 bits?

- The bucket index is `hash & (capacity - 1)` — only the low bits matter for small tables.
- Many hash functions differ only in high bits (e.g., sequential Longs: 0x00000001, 0x00000002).
- Without spreading, all those keys land in the same bucket → O(n) worst case.
- XOR with `h >>> 16` folds high entropy bits into low bits at zero cost.

```
Example: Long keys 0x00010000 and 0x00020000 in a 16-bucket table
  Without spread: both hash to bucket 0 (low 4 bits are 0000)
  With spread:    h ^ (h>>>16) gives distinct low bits → different buckets
```

### `null` Key

`null` always maps to bucket 0 (the `hash(null) = 0` case). HashMap supports exactly one `null` key; Hashtable does not.

### Treeification

When a bucket chain reaches **TREEIFY_THRESHOLD = 8** nodes AND the table has **MIN_TREEIFY_CAPACITY = 64** entries:
- The linked list is converted to a red-black `TreeNode` tree.
- Worst case lookup drops from O(n) to O(log n).

**Why 8?** With a good hash function, the probability of 8+ collisions in one bucket follows a Poisson distribution with λ = 0.5; P(k=8) ≈ 0.00000006. At this point, the overhead of maintaining a tree is justified.

**Why not treeify below capacity 64?** If the table is small, resizing (doubling capacity) distributes the collisions better than tree overhead. Treeification is a last resort.

**Untreeification at UNTREEIFY_THRESHOLD = 6** (not 8) prevents thrashing when elements are repeatedly removed and re-added near the threshold.

### Resize

```java
// Triggered when: size > threshold (= capacity × 0.75)
// New capacity: oldCapacity << 1  (double)
// Each entry rehashed into new table
// Amortized O(1) put — each element moves at most O(log n) times total
```

**Java 7 resize bug under concurrent access:** Two threads simultaneously triggering resize would create a circular linked list in the old table → infinite loop on `get()`. Java 8 eliminated this by using a head-tail link construction instead of reversal, but HashMap is still not thread-safe under concurrent writes — data loss can occur.

---

## 2. ConcurrentHashMap Internals

### Evolution: Java 7 → Java 8

**Java 7:** Segment array (lock striping). 16 independent `Segment<K,V>` objects, each a mini-HashMap with its own `ReentrantLock`. Concurrency level = 16.

**Java 8+:** Segments eliminated entirely. Per-bin locking instead. Much lower memory overhead, better scalability.

### Java 8 Read Path (No Locks)

```java
public V get(Object key) {
    Node<K,V>[] tab; Node<K,V> e, p; int n, eh; K ek;
    int h = spread(hash(key));
    if ((tab = table) != null && (n = tab.length) > 0 &&
        (e = tabAt(tab, (n - 1) & h)) != null) {
        // tabAt uses Unsafe.getObjectVolatile — atomic read of volatile array slot
        if ((eh = e.hash) == h) {
            if ((ek = e.key) == key || (ek != null && key.equals(ek)))
                return e.val;
        }
        else if (eh < 0)
            return (p = e.find(h, key)) != null ? p.val : null;
            // eh < 0 means ForwardingNode (resize in progress) or TreeBin
        while ((e = e.next) != null) {
            if (e.hash == h && ((ek = e.key) == key || (ek != null && key.equals(ek))))
                return e.val;
        }
    }
    return null;
}
```

Keys: `table` is `volatile Node<K,V>[]`. Individual `Node.val` and `Node.next` are `volatile`. Reads traverse the list with no lock.

### Java 8 Write Path

```java
// Simplified put
if (bucket is empty):
    casTabAt(tab, i, null, new Node<>(...))  // CAS — no lock if bucket empty

if (bucket has first node):
    synchronized (firstNode) {               // lock only this bin
        // add to linked list or tree
    }
```

**Why CAS for empty bucket:** If the bucket is null, a CAS from null to the new node is atomic and requires no lock. This is the common case for a well-distributed map.

### Size Counter

No single `AtomicLong counter`. Instead, a `CounterCell[]` array (same pattern as `LongAdder`):
- Each thread updates a pseudo-random cell.
- `size()` sums all cells — O(cells) not O(1).
- Under contention this is much faster than a single shared counter.

### `ForwardingNode` During Resize

When a bucket has been migrated to the new table, a `ForwardingNode` (hash = `MOVED = -1`) is placed in the old slot. Readers that encounter a `ForwardingNode` follow it to the new table. Writers that encounter `MOVED` help with the migration (cooperative resize).

### `computeIfAbsent` Reentrancy Bug (Java 8)

```java
// Java 8 bug: calling computeIfAbsent inside the mapping function deadlocks
map.computeIfAbsent("key1", k -> {
    return map.computeIfAbsent("key2", k2 -> "value2");  // DEADLOCK in Java 8
    // The outer call holds synchronized(bin) for key1's bin.
    // If key2 hashes to the same bin — same lock → deadlock.
    // If different bin — works in Java 8 but still undefined behavior.
});
```

**Java 9 fix:** The behavior is documented: calling `computeIfAbsent` reentrantly on the same map is permitted but the mapping function must not modify the map. The implementation was changed to detect recursion and throw `IllegalStateException` rather than deadlock silently.

**How to detect in code review:** Any lambda passed to `compute*` methods that captures the `ConcurrentHashMap` and calls any mutating method on it.

---

## 3. ArrayList Internals

```
ArrayList<E>:
  elementData: Object[]   ← backing array
  size: int               ← number of elements (≤ elementData.length)
  modCount: int           ← inherited from AbstractList, fail-fast support
```

### Growth Factor: 1.5×

```java
// JDK ArrayList.grow()
private Object[] grow(int minCapacity) {
    int oldCapacity = elementData.length;
    if (oldCapacity > 0 || elementData != DEFAULTCAPACITY_EMPTY_ELEMENTDATA) {
        int newCapacity = ArraysSupport.newLength(oldCapacity,
                minCapacity - oldCapacity,  // minimum growth
                oldCapacity >> 1);          // preferred growth (50%)
        return elementData = Arrays.copyOf(elementData, newCapacity);
    } else {
        return elementData = new Object[Math.max(DEFAULT_CAPACITY, minCapacity)];
    }
}
// newCapacity = oldCapacity + max(minGrowth, oldCapacity >> 1)
// = oldCapacity + oldCapacity/2  ≈  1.5 × oldCapacity
```

**Why 1.5 and not 2?**

With growth factor 2: after k doublings, the new array size = 2^k. The sum of all previous array sizes = 2^k - 1 < 2^k. This means the discarded arrays can **never** be reused by the allocator to satisfy the new allocation — the new array is always larger than all previous arrays combined. This prevents memory reuse.

With growth factor < golden ratio (≈1.618): the sum of all previous sizes eventually exceeds the new size, allowing the allocator to reuse discarded memory. Factor 1.5 is slightly below 1.618 — a pragmatic choice.

**Amortized O(1) `add`:** Each element is copied at most O(log_{1.5}(n)) times. Total copies over n insertions = O(n). Amortized per insertion = O(1).

### `add(int index, E element)` Cost

```java
// Shifts elements right by 1 position
System.arraycopy(elementData, index, elementData, index + 1, size - index);
elementData[index] = element;
```

O(n - index) time. Inserting at position 0 = O(n). This is why ArrayList is bad for frequent middle insertions.

### Fail-Fast Iterators

```java
// Iterator records modCount at construction
int expectedModCount = modCount;

// On next():
if (modCount != expectedModCount)
    throw new ConcurrentModificationException();
```

Any structural modification (add, remove, clear) to an ArrayList while iterating throws `ConcurrentModificationException`. This is a programming error detector, not a thread-safety guarantee.

---

## 4. LinkedList Internals

```java
// Node structure
private static class Node<E> {
    E item;
    Node<E> next;
    Node<E> prev;
}

// LinkedList fields
transient int size = 0;
transient Node<E> first;  // head
transient Node<E> last;   // tail
```

### Complexity Profile

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| `addFirst` / `addLast` | O(1) | Pointer update only |
| `removeFirst` / `removeLast` | O(1) | Pointer update only |
| `get(index)` | O(n) | Traverse from nearest end |
| `add(index, e)` | O(n) | Find position first |
| `contains(o)` | O(n) | Linear scan |

### Memory Overhead

Each `Node` object: **24 bytes** (16-byte object header + 8-byte references for `item`, `next`, `prev` after compression, actually varies).

For 1M elements:
- `LinkedList`: ~24MB for nodes alone + heap fragmentation
- `ArrayList`: 8MB for references + elements stored elsewhere (or inline for primitives)

**LinkedList cache behavior:** Each `get(i)` follows a pointer chain — each pointer likely a cache miss. A 1000-element list traversal triggers ~1000 cache misses vs. ~2 cache misses for `ArrayList` (contiguous memory).

### When `LinkedList` Actually Wins

**Only one case:** You maintain **external references to nodes** and need O(1) removal. Java's `LinkedList` does not expose its nodes, so this use case requires a custom doubly-linked list (as in LRU cache implementations).

```java
// LRU cache: maintain a custom DLL where each entry holds a node reference
// O(1) removal when a key is evicted: splice out the node directly
// LinkedList<E> cannot do this — you'd need to call remove(Object) which is O(n)
```

---

## 5. TreeMap Internals

`TreeMap` is a **red-black tree** — a self-balancing BST that guarantees O(log n) for get, put, remove.

### Red-Black Tree Invariants (5 Rules)

1. Every node is red or black.
2. The root is black.
3. Null leaves (sentinels) are black.
4. A red node's children are both black (no two consecutive red nodes).
5. All paths from any node to its descendant null leaves have the same number of black nodes.

These invariants bound the tree height to `2 × log₂(n+1)`.

### Rebalancing

On insert: new node is red. If parent is also red → violation → fix via **rotation** and/or **recoloring**.

```
Case 1: Uncle is red → recolor parent and uncle black, grandparent red, recurse up
Case 2: Uncle is black, inner child → rotate parent in opposite direction → Case 3
Case 3: Uncle is black, outer child → rotate grandparent, swap colors
```

### `NavigableMap` API

Because it's a BST, `TreeMap` can answer range queries efficiently:

```java
TreeMap<Integer, String> map = new TreeMap<>();
map.floorKey(5)           // largest key ≤ 5
map.ceilingKey(5)         // smallest key ≥ 5
map.headMap(10)           // all keys < 10 (view, not copy)
map.tailMap(10)           // all keys ≥ 10 (view)
map.subMap(3, 7)          // keys in [3, 7) (view)
map.descendingKeySet()    // keys in reverse order
```

These views are O(1) to create (BST traversal start points) and O(k) to iterate where k = number of elements in range.

---

## 6. PriorityQueue Internals

`PriorityQueue` is a **binary min-heap** stored in an array.

### Index Arithmetic

```
          0
        /   \
       1     2
      / \   / \
     3   4 5   6

Parent of i:    (i - 1) / 2
Left child:     2*i + 1
Right child:    2*i + 2
```

### Heap Property

`queue[parent] ≤ queue[child]` for all nodes (min-heap). The minimum is always at `queue[0]`.

### `offer(E e)` — siftUp O(log n)

```java
// Add at end, then sift up
queue[size] = e;
siftUp(size, e);
size++;

void siftUp(int k, E x) {
    while (k > 0) {
        int parent = (k - 1) >>> 1;
        Object e = queue[parent];
        if (comparator.compare(x, (E) e) >= 0) break;  // heap property restored
        queue[k] = e;     // move parent down
        k = parent;
    }
    queue[k] = x;
}
```

### `poll()` — siftDown O(log n)

```java
// Remove root, move last element to root, sift down
E result = (E) queue[0];
E x = (E) queue[--size];
queue[size] = null;
if (size > 0) siftDown(0, x);
return result;

void siftDown(int k, E x) {
    int half = size >>> 1;  // stop at last parent
    while (k < half) {
        int child = (k << 1) + 1;  // left child
        Object c = queue[child];
        int right = child + 1;
        if (right < size && comparator.compare((E)c, (E)queue[right]) > 0)
            c = queue[child = right];  // pick smaller child
        if (comparator.compare(x, (E) c) <= 0) break;
        queue[k] = c;
        k = child;
    }
    queue[k] = x;
}
```

### `contains(Object o)` — O(n)

Linear scan of the array. The heap property does NOT help for containment checks. If frequent `contains` is needed, use a `HashMap` as a secondary index alongside the heap (the pattern used by Dijkstra implementations).

### Heapify — O(n) via Floyd's Algorithm

```java
// When constructing from a Collection
// Run siftDown on every non-leaf node, bottom-up
for (int i = (size >>> 1) - 1; i >= 0; i--)
    siftDown(i, (E) queue[i]);
```

**Why O(n) and not O(n log n)?**

Nodes at height h require O(h) siftDown work. Number of nodes at height h ≈ n/2^(h+1).

```
Total work = Σ (n/2^(h+1)) × h  for h = 0 to log n
           = n × Σ h/2^(h+1)
           = n × 2  (the sum converges to 2 for the geometric-like series)
           = O(n)
```

Starting from the bottom (leaves require 0 work, roots require log n work) leverages the fact that most nodes are near the bottom.

---

## 7. EnumMap and EnumSet

### EnumMap

```java
// Internal storage: direct array indexed by Enum.ordinal()
Object[] vals = new Object[universe.length];  // universe = all enum constants

// get:
return vals[key.ordinal()];   // O(1), no hashing, no collision

// put:
vals[key.ordinal()] = value;  // O(1)

// iteration: scan vals array from 0 to universe.length
// iteration order = ordinal order = declaration order
```

**EnumMap vs HashMap<MyEnum,V>:**
- No hashing, no collision resolution, no resize.
- Iteration is 3–5× faster (contiguous array vs. sparse hash table).
- Memory: `EnumMap` is exactly `N` slots (N = enum size). `HashMap` has 75% load = ~1.33N slots + entry objects.

### EnumSet

```java
// For enums with ≤ 64 constants: RegularEnumSet
private long elements = 0L;

// add:
elements |= (1L << e.ordinal());  // set the bit

// contains:
(elements & (1L << e.ordinal())) != 0;  // single AND operation

// addAll (union):
elements |= other.elements;  // single OR

// retainAll (intersection):
elements &= other.elements;  // single AND
```

For >64 constants: `JumboEnumSet` uses `long[]` with the ordinal divided into word index and bit index.

**Performance**: `EnumSet.of(A, B, C)` is 3 OR operations. Iteration is a single `Long.numberOfTrailingZeros` in a loop. Beats `HashSet<MyEnum>` by 10–50× for small sets.

---

## 8. ArrayDeque Internals

```java
// Circular array
Object[] elements;   // backing array, size = power of 2
int head;            // index of first element
int tail;            // index after last element

// Add to front:
head = (head - 1) & (elements.length - 1);  // wrap-around using bitmask
elements[head] = e;

// Add to back:
elements[tail] = e;
tail = (tail + 1) & (elements.length - 1);
```

The `& (length - 1)` bitmask works because `length` is always a power of 2 — equivalent to modulo but a single AND operation.

**Growth:** When `head == tail` (full), double the array. Copy in two segments to handle wrap-around.

**Why prefer `ArrayDeque` over `LinkedList` for Queue/Stack?**

| Operation | ArrayDeque | LinkedList |
|-----------|-----------|-----------|
| `push` / `offer` | O(1) amortized, no alloc | O(1), but allocates `Node` object |
| `pop` / `poll` | O(1), no dealloc | O(1), but GC pressure from `Node` |
| Memory per element | 8 bytes (pointer in array) | 24 bytes (Node header + prev + next) |
| Cache behavior | Contiguous array | Pointer chasing |

For 1M queue operations, `ArrayDeque` produces ~3× less GC pressure than `LinkedList`.

**Stack usage**: Java's `Stack<E>` extends `Vector` (synchronized). Use `ArrayDeque` as a `Deque` instead — `push`/`pop` on the deque front gives identical stack semantics with no synchronization overhead.

---

## Interview Q&A

### Q1 `[Principal]` When does HashMap treeify a bucket, and what are the exact conditions? Why are the treeify and untreeify thresholds different?

**Answer:**

**Conditions for treeification:**
- Bucket chain reaches `TREEIFY_THRESHOLD = 8` nodes.
- AND table capacity ≥ `MIN_TREEIFY_CAPACITY = 64`.

If capacity < 64 and a bucket reaches 8 nodes, HashMap **resizes instead of treeifying**. Resizing distributes entries across twice as many buckets, resolving the collision without tree overhead. Treeification is reserved for when the table is already large and the collision is a true hash distribution problem.

**Why UNTREEIFY_THRESHOLD = 6 (not 8):**

Hysteresis prevents thrashing. If the thresholds were identical (both 8), a sequence of add/remove operations at the boundary would cause repeated treeify/untreeify cycles. With a gap of 2, the bucket must shrink to 6 before converting back to a linked list, providing stability.

**The probability argument:** With a good hash function and load factor 0.75, the expected bucket size follows Poisson(λ=0.75). P(size ≥ 8) ≈ 0.0000006 — so treeification is genuinely a last resort for poor hash functions or adversarial inputs.

---

### Q2 `[Principal]` How does ConcurrentHashMap achieve thread safety in Java 8 without any segment locks or global read locks?

**Answer:**

Three mechanisms combine to make reads lock-free:

1. **Volatile table array:** The `table` field is `volatile`. Any thread that reads `table` sees the latest write (happens-before from the last write to `table`).

2. **Volatile node fields:** Each `Node.val` and `Node.next` is `volatile`. Traversing a bin's linked list without a lock is safe because each field read is sequentially consistent.

3. **CAS for empty bins:** When adding the first element to an empty bin, `casTabAt` uses `Unsafe.compareAndSwapObject` — a single atomic hardware instruction. No lock needed.

**Write path:** For non-empty bins, `synchronized(firstNode)` locks only that bin's first node — not the whole table, not a segment. 256 bins can be written concurrently on a 256-bucket table.

**During resize:** `ForwardingNode` markers redirect concurrent readers to the new table without locking. Writers cooperate with the migration.

---

### Q3 `[Principal]` Why is ArrayList's growth factor 1.5 and not 2? Give the allocator reuse argument.

**Answer:**

With growth factor φ (phi), the array at generation k has size φ^k. A new allocation at generation k needs size φ^k. The sum of all previous discarded arrays is:

```
1 + φ + φ² + ... + φ^(k-1) = (φ^k - 1) / (φ - 1)
```

For this to be ≥ φ^k (so the allocator can reuse old memory):

```
(φ^k - 1) / (φ - 1) ≥ φ^k
→ solving: φ ≤ golden ratio ≈ 1.618
```

With **φ = 2**: sum of previous = 2^k - 1 < 2^k. The new allocation is always larger than all previous combined. Reuse is impossible.

With **φ = 1.5**: sum of previous eventually exceeds the new size. The allocator can satisfy the new request from old freed blocks. This reduces memory fragmentation and total memory used over time.

Java chose 1.5 as a pragmatic round number below the golden ratio.

---

### Q4 `[Principal]` Service processes 100k events/second with an event type from a 50-value enum. Need a counter per type. Walk through your data structure choice.

**Answer:**

```java
EnumMap<EventType, LongAdder> counters = new EnumMap<>(EventType.class);
for (EventType t : EventType.values()) {
    counters.put(t, new LongAdder());
}

// On each event:
counters.get(event.type()).increment();

// Read:
long count = counters.get(EventType.CLICK).sum();
```

**Why `EnumMap<EventType, LongAdder>` beats every alternative:**

- **EnumMap over HashMap:** `EnumMap.get` is `vals[ordinal()]` — one array lookup, no hash, no collision, no null check on `Entry`. Faster and lower memory.

- **LongAdder over AtomicLong:** At 100k events/second with multiple consumer threads, `AtomicLong.incrementAndGet` has ~15% CAS retry rate under 8+ concurrent updaters. `LongAdder` uses `Striped64` — each thread updates a pseudo-randomly assigned cell. CAS retry rate drops to < 1%. `sum()` aggregates all cells. The only cost: `sum()` is slightly slower (loops over cells), but for monitoring counters read at ~1Hz, this is irrelevant.

- **Not ConcurrentHashMap<EventType, LongAdder>:** ConcurrentHashMap has per-bin locking overhead for every read/write, plus boxing `EventType` into `Object`. Unnecessary complexity.

---

### Q5 `[Principal]` Prove that siftDown is O(log n), then prove that Floyd's heapify from a Collection is O(n).

**Answer:**

**siftDown is O(log n):**

The binary heap has height h = ⌊log₂(n)⌋. `siftDown` starts at some node and swaps downward at most one level per comparison. Maximum swaps = height = O(log n).

**Floyd's heapify is O(n):**

Run `siftDown` on every internal node (non-leaf), bottom-up from index ⌊n/2⌋ - 1 down to 0.

The work for a node at height h is O(h). Number of nodes at height h ≈ ⌈n/2^(h+1)⌉.

```
Total work T(n) = Σ(h=0 to ⌊log n⌋) [⌈n/2^(h+1)⌉ × O(h)]
               ≤ n × Σ(h=0 to ∞) h/2^(h+1)
               = n × Σ(h=0 to ∞) h × (1/2)^(h+1)
               = n × 1   (standard sum: Σ h×x^h = x/(1-x)² at x=1/2 → 2, divided by 2 → 1)
               = O(n)
```

The key insight: most nodes are near the bottom with height ≈ 0, requiring almost no sifting. The O(log n) worst case only applies to the root.

**If built by repeated insertion** (n calls to `offer`): each `offer` is O(log n), so total is O(n log n). Floyd's O(n) heapify is 2–3× faster in practice for large collections.

---

### Q6 `[Principal]` Why is LinkedList almost never the right choice in modern Java? Describe the one case where it wins.

**Answer:**

**LinkedList loses because of three factors:**

1. **Memory:** Each `Node` object consumes 24–40 bytes (object header + 3 pointer fields). An `ArrayList` of 1M elements uses 8MB for references. A `LinkedList` of 1M uses 24–40MB just for node objects, plus heap fragmentation.

2. **Cache misses:** CPU caches exploit spatial locality — fetching memory loads adjacent addresses. `ArrayList` stores references in a contiguous array; accessing element N brings elements N+1, N+2, ... into cache for free. `LinkedList` nodes are scattered across the heap. Each `node.next` access is likely a cache miss (~100ns vs. 1ns for L1 cache hit).

3. **Modern GC pressure:** 1M `Node` objects are 1M GC roots. The GC must scan/trace each one during marking. `ArrayList`'s `Object[]` is one object scanned in one pass.

**The one case LinkedList wins:**

When you hold a direct reference to a node and need O(1) removal. Example: an O(1) LRU cache requires moving recently-used entries to the front in O(1). This requires splicing a node out of the middle in O(1) — only possible with a direct `Node` reference.

Java's `LinkedList` does NOT expose `Node` references — `remove(Object)` is O(n) because it must search first. The LRU use case requires a **custom doubly-linked list** that returns `Node` handles, not Java's `LinkedList`.

---

### Q7 `[Principal]` HashMap has two distinct failure modes under concurrent access without synchronization — one in Java 7 and one in Java 8. Describe both.

**Answer:**

**Java 7 — Infinite Loop:**

During resize, `transfer()` reverses the insertion order of each bucket's linked list as it migrates entries. If two threads simultaneously trigger resize:

1. Thread A reads the head of bucket B's chain as `e1 → e2 → null`.
2. Thread B completes resize, reversing the chain to `e2 → e1 → null`.
3. Thread A resumes, inserts `e1` into the new bucket with `e1.next = e2`.
4. Thread A then inserts `e2`, sets `e2.next = e1` (it was previously e1's next before reversal).
5. Now: `e1.next = e2` AND `e2.next = e1` — circular linked list.
6. Any subsequent `get()` that traverses this bucket enters an infinite loop, pegging a CPU core at 100%.

**Java 8 — Data Loss (no infinite loop):**

Java 8 replaced the reversal-based resize with tail-insertion (`loHead`/`hiHead` chains) — this eliminated the circular list scenario. But the race condition still exists:

Two threads simultaneously adding elements to the same empty bucket both CAS `null` to their respective new node. One thread's CAS succeeds; the other's fails silently (the CAS returns the old null, the write is lost). No loop, but one put is silently dropped.

**Both are silent failures** — no exception, no warning. This is why "don't use HashMap from multiple threads" is a correctness rule, not just a performance guideline. Use `ConcurrentHashMap` or explicit synchronization.

---

*See also:* [03-concurrency-and-loom.md](03-concurrency-and-loom.md) for `LongAdder` Striped64 internals | [02-type-system-and-generics.md](02-type-system-and-generics.md) for generic type parameters in collections
