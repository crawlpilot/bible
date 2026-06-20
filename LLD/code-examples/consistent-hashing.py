"""
Consistent Hashing with Virtual Nodes
=======================================
Used for distributing keys across a dynamic set of nodes while minimizing
key remapping when nodes are added or removed.

Problem:
    Naive modulo hashing (key % N) remaps all keys when N changes.
    Consistent hashing remaps only ~1/N keys when one node is added/removed.

Design:
    - Hash ring: keys and nodes occupy positions on a circular hash space [0, 2^128)
    - Virtual nodes: each physical node occupies V positions on the ring
      (reduces load imbalance from O(1/N ± high variance) to O(1/N ± 5%)
    - For a key: walk clockwise on the ring to the first node position → that node owns the key

Applications:
    - Distributed caches (Memcached, Redis Cluster)
    - Load balancers (routing sticky sessions)
    - DHT (Distributed Hash Tables: Chord, Kademlia)
    - Cassandra's token ring (variant: multiple tokens per node)

Time complexity:
    - add_node:    O(V log(V×N))  — insert V virtual nodes, sort
    - remove_node: O(V log(V×N))  — remove V virtual nodes, rebuild or re-sort
    - get_node:    O(log(V×N))    — binary search on sorted ring
"""
import hashlib
import bisect
import threading
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Node:
    name: str
    host: str
    port: int
    weight: int = 1   # relative weight; controls virtual node count

    def __hash__(self):
        return hash(self.name)

    def __eq__(self, other):
        return isinstance(other, Node) and self.name == other.name

    def __repr__(self):
        return f"Node({self.name}, {self.host}:{self.port})"


class ConsistentHashRing:
    """
    Consistent hash ring with virtual nodes.

    Parameters:
        base_virtual_nodes: virtual node count for a node with weight=1.
                            A node with weight=2 gets 2× virtual nodes.
        hash_fn:            function(key: str) → int. Defaults to MD5-based.
    """

    def __init__(self, base_virtual_nodes: int = 150, hash_fn=None):
        if base_virtual_nodes <= 0:
            raise ValueError("base_virtual_nodes must be positive")
        self._base_vnodes = base_virtual_nodes
        self._hash_fn = hash_fn or self._default_hash
        # Sorted list of hash positions
        self._ring: list[int] = []
        # Map from hash position → Node
        self._position_to_node: dict[int, Node] = {}
        # Map from node name → list of its virtual positions
        self._node_to_positions: dict[str, list[int]] = {}
        self._lock = threading.RLock()

    @staticmethod
    def _default_hash(key: str) -> int:
        return int(hashlib.md5(key.encode()).hexdigest(), 16)

    def add_node(self, node: Node) -> None:
        """Add a node and its virtual nodes to the ring."""
        vnode_count = self._base_vnodes * node.weight
        with self._lock:
            if node.name in self._node_to_positions:
                raise ValueError(f"Node '{node.name}' is already in the ring")
            positions = []
            for i in range(vnode_count):
                pos = self._hash_fn(f"{node.name}#{i}")
                self._position_to_node[pos] = node
                bisect.insort(self._ring, pos)
                positions.append(pos)
            self._node_to_positions[node.name] = positions

    def remove_node(self, node_name: str) -> None:
        """Remove a node and all its virtual nodes from the ring."""
        with self._lock:
            positions = self._node_to_positions.pop(node_name, None)
            if positions is None:
                raise KeyError(f"Node '{node_name}' not in ring")
            for pos in positions:
                del self._position_to_node[pos]
                idx = bisect.bisect_left(self._ring, pos)
                if idx < len(self._ring) and self._ring[idx] == pos:
                    self._ring.pop(idx)

    def get_node(self, key: str) -> Optional[Node]:
        """Return the node responsible for `key`. Returns None if ring is empty."""
        with self._lock:
            if not self._ring:
                return None
            pos = self._hash_fn(key)
            idx = bisect.bisect_right(self._ring, pos) % len(self._ring)
            return self._position_to_node[self._ring[idx]]

    def get_nodes(self, key: str, count: int) -> list[Node]:
        """
        Return `count` distinct nodes in ring order starting from the node for `key`.
        Used for replication: primary + N-1 replicas.
        """
        with self._lock:
            if not self._ring or count <= 0:
                return []
            pos = self._hash_fn(key)
            start_idx = bisect.bisect_right(self._ring, pos) % len(self._ring)
            result: list[Node] = []
            seen_nodes: set[str] = set()
            for offset in range(len(self._ring)):
                idx = (start_idx + offset) % len(self._ring)
                node = self._position_to_node[self._ring[idx]]
                if node.name not in seen_nodes:
                    result.append(node)
                    seen_nodes.add(node.name)
                if len(result) == count:
                    break
            return result

    def node_count(self) -> int:
        with self._lock:
            return len(self._node_to_positions)

    def ring_size(self) -> int:
        """Total number of virtual nodes on the ring."""
        with self._lock:
            return len(self._ring)

    def load_distribution(self) -> dict[str, float]:
        """Return the fraction of the hash space owned by each node."""
        with self._lock:
            if not self._ring:
                return {}
            space_size = 2 ** 128
            distribution: dict[str, float] = {
                name: 0.0 for name in self._node_to_positions
            }
            for i, pos in enumerate(self._ring):
                prev_pos = self._ring[i - 1] if i > 0 else 0
                arc_size = (pos - prev_pos) % space_size
                node = self._position_to_node[pos]
                distribution[node.name] += arc_size / space_size
            return distribution


# ── Unit Tests ────────────────────────────────────────────────────────────

import unittest
from collections import defaultdict


class TestConsistentHashRing(unittest.TestCase):

    def _make_ring(self, node_names: list[str], vnodes: int = 150) -> ConsistentHashRing:
        ring = ConsistentHashRing(base_virtual_nodes=vnodes)
        for name in node_names:
            ring.add_node(Node(name=name, host=f"{name}.example.com", port=8080))
        return ring

    def test_empty_ring(self):
        ring = ConsistentHashRing()
        self.assertIsNone(ring.get_node("any-key"))

    def test_single_node_gets_all_keys(self):
        ring = self._make_ring(["node-a"])
        for key in ["key1", "key2", "key3", "user:42"]:
            node = ring.get_node(key)
            self.assertIsNotNone(node)
            self.assertEqual(node.name, "node-a")

    def test_deterministic_routing(self):
        ring = self._make_ring(["a", "b", "c"])
        results = {key: ring.get_node(key).name for key in ["x", "y", "z"]}
        # Same ring, same keys → same results
        for key, name in results.items():
            self.assertEqual(ring.get_node(key).name, name)

    def test_minimal_remapping_on_add(self):
        ring = self._make_ring(["a", "b", "c"], vnodes=200)
        keys = [f"key-{i}" for i in range(10000)]
        before = {k: ring.get_node(k).name for k in keys}

        ring.add_node(Node("d", "d.example.com", 8080))

        after = {k: ring.get_node(k).name for k in keys}
        remapped = sum(1 for k in keys if before[k] != after[k])
        # Expect ~1/4 of keys to remap (4 nodes → 1/4 average)
        self.assertLess(remapped, len(keys) * 0.35,
                        f"Too many remapped: {remapped} ({remapped/len(keys):.1%})")
        self.assertGreater(remapped, len(keys) * 0.10,
                           f"Too few remapped: {remapped}")

    def test_minimal_remapping_on_remove(self):
        ring = self._make_ring(["a", "b", "c"], vnodes=200)
        keys = [f"key-{i}" for i in range(10000)]
        before = {k: ring.get_node(k).name for k in keys}

        ring.remove_node("c")

        after = {k: ring.get_node(k).name for k in keys}
        remapped = sum(1 for k in keys if before[k] != after[k])
        # Only keys that were on "c" should remap (~1/3)
        self.assertLess(remapped, len(keys) * 0.45)
        # And only to existing nodes (a or b), not back to c
        for k in keys:
            self.assertNotEqual(after[k], "c")

    def test_replication_get_nodes(self):
        ring = self._make_ring(["a", "b", "c", "d"])
        replicas = ring.get_nodes("mykey", 3)
        self.assertEqual(len(replicas), 3)
        # All distinct
        names = [n.name for n in replicas]
        self.assertEqual(len(names), len(set(names)))

    def test_get_nodes_count_exceeds_nodes(self):
        ring = self._make_ring(["a", "b"])
        replicas = ring.get_nodes("key", 5)
        # Can return at most as many nodes as exist
        self.assertEqual(len(replicas), 2)

    def test_duplicate_node_raises(self):
        ring = ConsistentHashRing()
        ring.add_node(Node("a", "a.host", 80))
        with self.assertRaises(ValueError):
            ring.add_node(Node("a", "a.host", 80))

    def test_remove_nonexistent_raises(self):
        ring = ConsistentHashRing()
        with self.assertRaises(KeyError):
            ring.remove_node("ghost")

    def test_load_distribution_roughly_even(self):
        ring = self._make_ring(["a", "b", "c", "d"], vnodes=200)
        dist = ring.load_distribution()
        self.assertEqual(set(dist.keys()), {"a", "b", "c", "d"})
        for name, fraction in dist.items():
            # Each node should own roughly 25% ± 10%
            self.assertAlmostEqual(fraction, 0.25, delta=0.10,
                                   msg=f"Node {name} owns {fraction:.1%}")

    def test_weighted_nodes(self):
        ring = ConsistentHashRing(base_virtual_nodes=100)
        ring.add_node(Node("small", "s.host", 80, weight=1))
        ring.add_node(Node("large", "l.host", 80, weight=3))
        dist = ring.load_distribution()
        # "large" should own ~75% of the ring
        self.assertGreater(dist["large"], 0.60)
        self.assertLess(dist["small"], 0.40)


# ── Design Notes ──────────────────────────────────────────────────────────
"""
Key Parameters:
    base_virtual_nodes=150: gives ~±5% load variance across nodes with 3+ nodes.
                            Lower values (50) → higher variance (±15%);
                            Higher values (300) → lower variance (±2%) but more memory.

Why MD5 and not SHA-256?
    MD5 is fast and has good distribution for this use case. Security is not
    a concern — we're using it as a hash function, not for cryptographic purposes.
    In Java production systems, MurmurHash3 is preferred (faster, good distribution).

Alternative: Jump Consistent Hash (Google, 2014)
    - O(ln N) time, O(1) space (no ring stored)
    - But: doesn't support node removal in a decentralized way
    - Best for: bucket-based sharding where you know N in advance

Cassandra's Token Ring:
    - Uses 256 virtual tokens per node (legacy) or vnodes (newer)
    - Token assignment is explicit (not hash-based) for better control
    - Replication factor R: a key's R successive nodes on the ring hold replicas
    - get_nodes(key, R) is exactly the replica selection algorithm above

Redis Cluster:
    - Uses 16384 "hash slots" (not consistent hashing)
    - Each slot is assigned to a node; remapping = reassigning slots
    - Less flexible than consistent hashing but simpler to reason about
"""

if __name__ == "__main__":
    unittest.main(verbosity=2)
