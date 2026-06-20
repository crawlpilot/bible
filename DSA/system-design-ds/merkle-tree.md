# Merkle Tree
**Category**: Data Integrity Structure — used in distributed systems for efficient anti-entropy, sync, and verification

---

## 1. The Problem It Solves

### Data Divergence in Distributed Systems

In a distributed database with replication, nodes can diverge silently:
- A network partition temporarily prevents writes from reaching a replica.
- A crash leaves a node with a partially applied batch.
- A silent disk corruption flips bits on one replica.

**Challenge**: compare two datasets of 1 billion records across two nodes without transferring all data.

```
Naive approach:  stream all 1B keys + checksums across network
                 1B × ~20 bytes = 20 GB per comparison run
                 At once-per-hour: 480 GB/day per node pair

Merkle Tree:     O(log N) messages to identify which subset diverges
                 Only transfer the differing subtrees, not the entire dataset
```

---

## 2. How a Merkle Tree Works

### 2.1 Structure

A Merkle tree is a **binary tree where**:
- **Leaf nodes** contain the hash of individual data chunks (records, blocks).
- **Internal nodes** contain the hash of the concatenation of their two children's hashes.
- The **root** is a single hash that represents the entire dataset.

```
                     Root
                  [H(H12 ‖ H34)]
                 /               \
           H12                     H34
       [H(H1 ‖ H2)]           [H(H3 ‖ H4)]
       /          \            /           \
     H1           H2          H3            H4
  [hash(D1)]  [hash(D2)]  [hash(D3)]    [hash(D4)]
      |             |          |              |
     D1            D2         D3             D4
  (record 1)  (record 2)  (record 3)    (record 4)
```

### 2.2 Key Properties

1. **Tamper-evident**: changing any leaf changes all hashes up to the root.
2. **Efficient proof**: to prove D2 is in the tree, only provide H1, H34, Root — O(log N) hashes.
3. **Efficient diff**: to find which subtree differs between two nodes, compare root → walk down mismatching subtrees → O(log N) rounds.

### 2.3 Anti-Entropy Sync Protocol

```
Node A                          Node B
  │                               │
  │── send Root hash ─────────────►│
  │◄─ Root hashes match? ─────────│
  │   (No — roots differ)         │
  │── send H12, H34 ──────────────►│
  │◄─ H12 matches, H34 differs ───│
  │── send H3, H4 ─────────────────►│
  │◄─ H3 differs, H4 matches ─────│
  │── send D3 content ─────────────►│
  │   (only D3 needs syncing)      │
```

Only O(log N) round trips to isolate the diverging leaf, then transfer only the differing data.

---

## 3. Java Implementation

### 3.1 Merkle Tree

```java
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.*;

public class MerkleTree {

    public static final class Node {
        final byte[] hash;
        final Node left, right;
        final String key;     // only for leaf nodes

        Node(byte[] hash, Node left, Node right, String key) {
            this.hash = hash;
            this.left = left;
            this.right = right;
            this.key = key;
        }

        boolean isLeaf() { return left == null && right == null; }
    }

    private final Node root;
    private static final ThreadLocal<MessageDigest> SHA256 = ThreadLocal.withInitial(() -> {
        try { return MessageDigest.getInstance("SHA-256"); }
        catch (NoSuchAlgorithmException e) { throw new RuntimeException(e); }
    });

    // Build tree from sorted (key, value) pairs
    public MerkleTree(SortedMap<String, byte[]> data) {
        if (data.isEmpty()) throw new IllegalArgumentException("Cannot build Merkle tree from empty data");
        List<Node> leaves = new ArrayList<>(data.size());
        for (Map.Entry<String, byte[]> entry : data.entrySet()) {
            byte[] leafHash = hash(entry.getKey().getBytes(), entry.getValue());
            leaves.add(new Node(leafHash, null, null, entry.getKey()));
        }
        this.root = buildTree(leaves);
    }

    private static Node buildTree(List<Node> nodes) {
        if (nodes.size() == 1) return nodes.get(0);
        List<Node> parents = new ArrayList<>();
        for (int i = 0; i < nodes.size(); i += 2) {
            Node left = nodes.get(i);
            Node right = (i + 1 < nodes.size()) ? nodes.get(i + 1) : left; // duplicate last for odd count
            byte[] parentHash = hash(left.hash, right.hash);
            parents.add(new Node(parentHash, left, right, null));
        }
        return buildTree(parents);
    }

    public byte[] rootHash() { return root.hash; }

    // Returns proof path for a given key (sibling hashes from leaf to root)
    public List<byte[]> proofPath(String key) {
        List<byte[]> proof = new ArrayList<>();
        collectProof(root, key, proof);
        return proof;
    }

    private boolean collectProof(Node node, String key, List<byte[]> proof) {
        if (node.isLeaf()) return key.equals(node.key);
        if (collectProof(node.left, key, proof)) {
            proof.add(node.right.hash);
            return true;
        }
        if (node.right != node.left && collectProof(node.right, key, proof)) {
            proof.add(node.left.hash);
            return true;
        }
        return false;
    }

    // Find keys that differ between this tree and another of the same structure
    public Set<String> diff(MerkleTree other) {
        Set<String> diffKeys = new HashSet<>();
        collectDiffs(this.root, other.root, diffKeys);
        return diffKeys;
    }

    private static void collectDiffs(Node a, Node b, Set<String> diffKeys) {
        if (Arrays.equals(a.hash, b.hash)) return; // subtrees identical
        if (a.isLeaf()) {
            diffKeys.add(a.key);
            return;
        }
        collectDiffs(a.left, b.left, diffKeys);
        if (a.right != a.left) collectDiffs(a.right, b.right, diffKeys);
    }

    private static byte[] hash(byte[]... parts) {
        MessageDigest md = SHA256.get();
        md.reset();
        for (byte[] part : parts) md.update(part);
        return md.digest();
    }

    public Node getRoot() { return root; }
}
```

### 3.2 Merkle-Based Anti-Entropy Sync

```java
import java.util.*;

public class AntiEntropyService {

    private final Map<String, byte[]> localStore;
    private MerkleTree localTree;

    public AntiEntropyService(Map<String, byte[]> initialData) {
        this.localStore = new TreeMap<>(initialData);
        this.localTree = rebuild();
    }

    public void put(String key, byte[] value) {
        localStore.put(key, value);
        localTree = rebuild(); // in production: incremental update, not full rebuild
    }

    public byte[] get(String key) { return localStore.get(key); }

    public byte[] rootHash() { return localTree.rootHash(); }

    // Simulate sync with a remote node (in practice, over RPC)
    public SyncResult syncWith(AntiEntropyService remote) {
        if (Arrays.equals(this.rootHash(), remote.rootHash())) {
            return new SyncResult(0, 0); // identical, nothing to do
        }

        // Find diverging keys
        Set<String> divergingKeys = this.localTree.diff(remote.localTree);
        int transferred = 0;

        for (String key : divergingKeys) {
            byte[] remoteValue = remote.get(key);
            byte[] localValue = this.get(key);

            // Simple last-write-wins (in practice, use vector clocks or timestamps)
            if (remoteValue != null && !Arrays.equals(remoteValue, localValue)) {
                this.put(key, remoteValue);
                transferred++;
            }
        }

        return new SyncResult(divergingKeys.size(), transferred);
    }

    private MerkleTree rebuild() {
        if (localStore.isEmpty()) return null;
        return new MerkleTree(new TreeMap<>(
            localStore.entrySet().stream()
                .collect(java.util.stream.Collectors.toMap(
                    Map.Entry::getKey, Map.Entry::getValue,
                    (a, b) -> a, TreeMap::new))));
    }

    public record SyncResult(int divergingKeys, int transferred) {}
}
```

### 3.3 Membership Proof Verification

```java
import java.security.MessageDigest;
import java.util.*;

public class MerkleProofVerifier {

    // Verify that a leaf (key, value) belongs to a tree with a known root hash
    public static boolean verify(String key, byte[] value, List<byte[]> proofPath,
                                  byte[] expectedRoot) {
        MessageDigest md;
        try { md = MessageDigest.getInstance("SHA-256"); }
        catch (Exception e) { throw new RuntimeException(e); }

        // Start from the leaf hash
        md.reset();
        md.update(key.getBytes());
        md.update(value);
        byte[] current = md.digest();

        // Walk up the tree using sibling hashes
        for (byte[] sibling : proofPath) {
            md.reset();
            // Canonical ordering: smaller hash on left (deterministic)
            if (compare(current, sibling) <= 0) {
                md.update(current);
                md.update(sibling);
            } else {
                md.update(sibling);
                md.update(current);
            }
            current = md.digest();
        }

        return Arrays.equals(current, expectedRoot);
    }

    private static int compare(byte[] a, byte[] b) {
        for (int i = 0; i < Math.min(a.length, b.length); i++) {
            int cmp = Byte.compareUnsigned(a[i], b[i]);
            if (cmp != 0) return cmp;
        }
        return Integer.compare(a.length, b.length);
    }
}
```

### 3.4 Cassandra-Style Partitioned Merkle Tree

In Cassandra, each token range on the ring has its own Merkle tree. Repair (`nodetool repair`) builds Merkle trees per token range, exchanges root hashes between replicas, and drills into differing ranges:

```java
public class PartitionedMerkleForest {

    private final int numPartitions;
    private final Map<Integer, MerkleTree> partitionTrees = new HashMap<>();

    public PartitionedMerkleForest(SortedMap<String, byte[]> allData, int numPartitions) {
        this.numPartitions = numPartitions;
        // Split data into partitions by key hash
        Map<Integer, SortedMap<String, byte[]>> partitionData = new HashMap<>();
        for (int i = 0; i < numPartitions; i++) partitionData.put(i, new TreeMap<>());

        for (Map.Entry<String, byte[]> entry : allData.entrySet()) {
            int partition = Math.abs(entry.getKey().hashCode()) % numPartitions;
            partitionData.get(partition).put(entry.getKey(), entry.getValue());
        }

        for (int i = 0; i < numPartitions; i++) {
            if (!partitionData.get(i).isEmpty()) {
                partitionTrees.put(i, new MerkleTree(partitionData.get(i)));
            }
        }
    }

    public byte[] rootHashForPartition(int partition) {
        MerkleTree tree = partitionTrees.get(partition);
        return tree == null ? new byte[0] : tree.rootHash();
    }

    // Returns partition indices that differ between this and another forest
    public List<Integer> divergingPartitions(PartitionedMerkleForest other) {
        List<Integer> diverging = new ArrayList<>();
        for (int i = 0; i < numPartitions; i++) {
            if (!Arrays.equals(rootHashForPartition(i), other.rootHashForPartition(i))) {
                diverging.add(i);
            }
        }
        return diverging;
    }
}
```

---

## 4. Where Merkle Trees Appear at FAANG

### 4.1 Cassandra — Anti-Entropy Repair

```
Cassandra repair flow:
1. Coordinator asks all replicas to build Merkle trees for each token range.
2. Exchange root hashes — O(1) per range.
3. For differing ranges: exchange tree levels top-down until leaf discrepancy isolated.
4. Streaming: only stream the differing key ranges.

Without Merkle trees: full table scan + hash comparison across replicas per repair cycle.
With Merkle trees: O(log N) messages per differing partition.
```

### 4.2 DynamoDB / Amazon S3
S3 uses Merkle-tree-based synchronisation to detect and repair split-brain scenarios during network partitions. DynamoDB uses a similar approach for replica consistency.

### 4.3 Git
Each Git commit object's tree is a Merkle DAG. The commit hash encodes the hash of the root tree, which encodes hashes of all subtrees and blobs. `git diff` walks the tree to find changed subtrees.

### 4.4 Ethereum / Bitcoin
Bitcoin block headers contain a Merkle root of all transactions. SPV (Simplified Payment Verification) nodes download only block headers and a proof path to verify inclusion of a specific transaction in a block — O(log N) hashes, not the full block.

### 4.5 Certificate Transparency (Google)
Certificate authorities publish a Merkle tree of all issued TLS certificates. Browsers can verify any certificate is in the log with a short proof path — prevents stealth certificate issuance.

---

## 5. Trade-Offs

| Attribute | Merkle Tree | Full Checksum | Naive Diff |
|---|---|---|---|
| Sync messages to isolate diff | O(log N) | O(1) detect, O(N) locate | O(N) |
| Proof of inclusion | O(log N) hashes | Not possible | O(N) scan |
| Build cost | O(N log N) | O(N) | O(N) |
| Space | O(N) nodes | O(1) | O(N) |
| Supports streaming rebuild | Partial (per-leaf update) | Yes | Yes |
| Suitable for distributed sync | Excellent | Detect only | Poor at scale |

---

## 6. FAANG Interview Callouts

**"How does Cassandra's repair work?"**
> Cassandra builds a Merkle tree per token range on each replica. The coordinator exchanges root hashes — if they match the range is consistent. For mismatches it drills down, exchanging subtree hashes level-by-level to isolate the differing key ranges. Only those key ranges are streamed between nodes. This limits repair I/O to the inconsistent subset rather than the entire dataset.

**"Why does Git content-address blobs?"**
> Git's Merkle DAG means two commits with identical content have identical hashes. This enables fast `git diff` (walk the tree, compare subtree hashes, skip matching subtrees), deduplication (same file in two places shares one blob), and immutability (a hash uniquely identifies a tree state forever).

**Follow-up questions to expect:**
1. "What happens if two leaves in your Merkle tree have the same hash?" → Hash collision breaks the integrity guarantee. Use SHA-256 (collision-resistant); probability is negligible (2^-128). Pre-image resistance means an attacker can't craft collisions.
2. "How would you update a Merkle tree incrementally without rebuilding?" → Recompute only the path from the changed leaf to the root — O(log N) hash computations instead of O(N).
3. "Why does Cassandra limit repair to one token range at a time?" → Memory constraint: holding a full Merkle tree for all data simultaneously is expensive. Per-range trees cap memory to a manageable subtree size.
