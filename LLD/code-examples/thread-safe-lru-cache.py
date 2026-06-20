"""
Thread-Safe LRU Cache
======================
Design: Doubly-linked list + HashMap for O(1) get/put with thread safety.

Interface contract:
    get(key)       → value or None. Marks key as most recently used.
    put(key, value) → stores the pair, evicting LRU if at capacity.
    delete(key)    → removes key if present.
    size()         → current number of entries.

Time complexity:  O(1) get, put, delete
Space complexity: O(capacity)
Thread safety:    ReentrantLock guards all mutations (single lock — simple, correct)

Production alternatives:
  - Segmented lock per bucket to reduce contention at the cost of complexity
  - ConcurrentLinkedHashMap (Java) for non-blocking reads
  - Caffeine (Java) for production-grade concurrent cache with W-TinyLFU eviction
"""
import threading
from typing import Generic, TypeVar, Optional

K = TypeVar('K')
V = TypeVar('V')


class _Node(Generic[K, V]):
    """Doubly linked list node."""
    __slots__ = ('key', 'value', 'prev', 'next')

    def __init__(self, key: K, value: V):
        self.key = key
        self.value = value
        self.prev: Optional['_Node'] = None
        self.next: Optional['_Node'] = None


class LRUCache(Generic[K, V]):
    """
    Thread-safe LRU cache backed by a doubly linked list and a dict.

    MRU ← sentinel_head ↔ [most-recent] ↔ ... ↔ [least-recent] ↔ sentinel_tail → LRU
    """

    def __init__(self, capacity: int):
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        self._capacity = capacity
        self._map: dict[K, _Node[K, V]] = {}
        self._lock = threading.Lock()

        # Sentinel nodes — never store real data; simplify edge cases
        self._head: _Node = _Node(None, None)  # MRU side
        self._tail: _Node = _Node(None, None)  # LRU side
        self._head.next = self._tail
        self._tail.prev = self._head

    # ── Public API ────────────────────────────────────────────────────────

    def get(self, key: K) -> Optional[V]:
        with self._lock:
            node = self._map.get(key)
            if node is None:
                return None
            self._move_to_front(node)
            return node.value

    def put(self, key: K, value: V) -> None:
        with self._lock:
            if key in self._map:
                node = self._map[key]
                node.value = value
                self._move_to_front(node)
            else:
                if len(self._map) >= self._capacity:
                    self._evict_lru()
                node = _Node(key, value)
                self._map[key] = node
                self._insert_at_front(node)

    def delete(self, key: K) -> bool:
        with self._lock:
            node = self._map.pop(key, None)
            if node is None:
                return False
            self._remove_node(node)
            return True

    def size(self) -> int:
        with self._lock:
            return len(self._map)

    def peek_lru(self) -> Optional[K]:
        """Return the least-recently-used key without evicting it. Useful for testing."""
        with self._lock:
            lru_node = self._tail.prev
            if lru_node is self._head:
                return None
            return lru_node.key

    # ── Internal helpers (must be called with _lock held) ─────────────────

    def _insert_at_front(self, node: _Node) -> None:
        node.prev = self._head
        node.next = self._head.next
        self._head.next.prev = node
        self._head.next = node

    def _remove_node(self, node: _Node) -> None:
        node.prev.next = node.next
        node.next.prev = node.prev

    def _move_to_front(self, node: _Node) -> None:
        self._remove_node(node)
        self._insert_at_front(node)

    def _evict_lru(self) -> None:
        lru = self._tail.prev
        if lru is self._head:
            return
        self._remove_node(lru)
        del self._map[lru.key]

    def __repr__(self) -> str:
        with self._lock:
            items = []
            cur = self._head.next
            while cur is not self._tail:
                items.append(f"{cur.key}:{cur.value}")
                cur = cur.next
            return f"LRUCache([{', '.join(items)}], capacity={self._capacity})"


# ── Unit Tests ────────────────────────────────────────────────────────────

import unittest
import concurrent.futures


class TestLRUCache(unittest.TestCase):

    def test_basic_get_put(self):
        cache = LRUCache(3)
        cache.put("a", 1)
        cache.put("b", 2)
        self.assertEqual(cache.get("a"), 1)
        self.assertEqual(cache.get("b"), 2)
        self.assertIsNone(cache.get("c"))

    def test_eviction_lru_order(self):
        cache = LRUCache(2)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.get("a")        # a is now MRU
        cache.put("c", 3)     # b should be evicted (LRU)
        self.assertIsNone(cache.get("b"))
        self.assertEqual(cache.get("a"), 1)
        self.assertEqual(cache.get("c"), 3)

    def test_update_existing_key(self):
        cache = LRUCache(2)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.put("a", 99)    # update a, a becomes MRU
        cache.put("c", 3)     # b should be evicted
        self.assertIsNone(cache.get("b"))
        self.assertEqual(cache.get("a"), 99)

    def test_capacity_one(self):
        cache = LRUCache(1)
        cache.put("a", 1)
        cache.put("b", 2)
        self.assertIsNone(cache.get("a"))
        self.assertEqual(cache.get("b"), 2)

    def test_delete(self):
        cache = LRUCache(3)
        cache.put("a", 1)
        cache.put("b", 2)
        self.assertTrue(cache.delete("a"))
        self.assertFalse(cache.delete("a"))
        self.assertIsNone(cache.get("a"))
        self.assertEqual(cache.size(), 1)

    def test_size(self):
        cache = LRUCache(3)
        self.assertEqual(cache.size(), 0)
        cache.put("a", 1)
        self.assertEqual(cache.size(), 1)
        cache.put("a", 2)  # update — size unchanged
        self.assertEqual(cache.size(), 1)

    def test_thread_safety(self):
        cache = LRUCache(100)
        errors = []

        def worker(thread_id: int):
            try:
                for i in range(200):
                    key = f"key-{(thread_id * 200 + i) % 150}"
                    cache.put(key, thread_id * 200 + i)
                    cache.get(key)
            except Exception as e:
                errors.append(e)

        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
            futures = [pool.submit(worker, i) for i in range(10)]
            concurrent.futures.wait(futures)

        self.assertEqual(errors, [], f"Thread safety errors: {errors}")
        self.assertLessEqual(cache.size(), 100)

    def test_peek_lru(self):
        cache = LRUCache(3)
        cache.put("a", 1)
        cache.put("b", 2)
        cache.put("c", 3)
        # LRU is 'a' (inserted first, never accessed)
        self.assertEqual(cache.peek_lru(), "a")
        cache.get("a")  # a is now MRU
        self.assertEqual(cache.peek_lru(), "b")

    def test_invalid_capacity(self):
        with self.assertRaises(ValueError):
            LRUCache(0)


# ── Complexity Analysis ───────────────────────────────────────────────────
"""
Operation   Time        Space
─────────────────────────────
get         O(1)        O(1) extra
put         O(1)        O(capacity) total
delete      O(1)        O(1) extra
size        O(1)        O(1) extra

Total space: O(capacity) — dict + linked list, both bounded by capacity.

Why OrderedDict (Python stdlib) vs custom linked list:
  - OrderedDict is simpler and has the same asymptotic complexity
  - Custom linked list gives slightly better constant factors (no Python dict overhead
    for the ordered iteration) and is easier to extend (e.g., per-node TTL)
  - In a Java production system: ConcurrentLinkedHashMap or Caffeine are preferred
    over hand-rolled implementations

Concurrency model:
  - Single coarse lock: correct and simple; suitable for moderate throughput
  - For high-throughput (>1M ops/sec): use stripe locking by key hash
    (16 stripes = 16 locks; reduces contention 16×) at the cost of requiring
    additional synchronization for the doubly-linked list
"""

if __name__ == "__main__":
    unittest.main(verbosity=2)
