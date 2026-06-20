# LSM Tree (Log-Structured Merge Tree)
**Category**: Storage Data Structure — write-optimised storage engine used in Cassandra, RocksDB, LevelDB, HBase

---

## 1. The Problem It Solves

### B-Tree Write Amplification

B-trees (used in MySQL InnoDB, PostgreSQL) store data in sorted pages on disk. Every write requires a random I/O: locate the page, read it, modify it, write it back.

```
B-Tree write:   1 random read + 1 random write per record
                Write amplification: 10–30× (page splits, rebalancing)
                IOPS needed at 100K writes/sec: ~1M+ disk IOPS
```

HDDs deliver ~200 IOPS, SSDs ~100K IOPS. Even SSDs struggle at high write throughput with B-trees.

### LSM Tree Solution

**Convert all random writes into sequential writes.** Absorb writes in RAM, then flush to disk in sorted sequential batches. Sacrifice some read performance for dramatically better write throughput.

```
B-Tree:    100K writes/sec → needs fast SSD
LSM Tree:  100K writes/sec → works well on HDD, excellent on SSD
```

---

## 2. Architecture

### 2.1 Components

```
┌─────────────────────────────────────────────────────┐
│  WRITE PATH                                          │
│                                                      │
│  Client Write                                        │
│       │                                              │
│       ▼                                              │
│  WAL (Write-Ahead Log) ──── sequential append ─────► disk
│       │                                              │
│       ▼                                              │
│  MemTable (in-memory sorted tree, e.g. Red-Black)   │
│       │  (when full, ~64–256 MB)                     │
│       ▼                                              │
│  Immutable MemTable (flushing)                       │
│       │                                              │
│       ▼                                              │
│  L0 SSTables ──────────────────────────────────────► disk
│       │  (compaction)                                │
│       ▼                                              │
│  L1 SSTables (sorted, non-overlapping)               │
│       │                                              │
│       ▼                                              │
│  L2 SSTables  (10× larger than L1)                   │
│       │                                              │
│       ▼                                              │
│  ...  Ln SSTables                                    │
└─────────────────────────────────────────────────────┘
```

### 2.2 SSTable (Sorted String Table)

An SSTable is an **immutable, sorted file** on disk:

```
SSTable file layout:
┌──────────────────────────────────────┐
│ Data blocks (sorted key-value pairs) │
│ [key1, val1][key2, val2]...          │
│──────────────────────────────────────│
│ Index block (sparse index into data) │
│ key_100 → offset 4096                │
│ key_200 → offset 8192                │
│──────────────────────────────────────│
│ Bloom filter (per-SSTable)           │
│ Quickly skip non-matching SSTables   │
│──────────────────────────────────────│
│ Footer (metadata, index offset)      │
└──────────────────────────────────────┘
```

---

## 3. Read and Write Paths

### 3.1 Write Path

1. Append to WAL (crash recovery).
2. Insert into MemTable (in-memory Red-Black or AVL tree — stays sorted).
3. When MemTable exceeds threshold (default ~64 MB in RocksDB): freeze → new MemTable. Background thread flushes frozen MemTable → new L0 SSTable.
4. Compaction merges L0 files into L1, L1 into L2, etc.

**Why WAL?** If the process crashes before MemTable flush, WAL is replayed to reconstruct the MemTable. Without WAL, unflushed writes are lost.

### 3.2 Read Path

1. Check MemTable (most recent data, in-memory O(log n)).
2. Check immutable MemTables (if any flushing in progress).
3. Check L0 SSTables newest → oldest (may overlap, must check all).
4. For L1+: binary search the level's key range index → find exactly which SSTable (ranges don't overlap). Check Bloom filter. If positive: binary search index block → read data block.

```
Worst case read: MemTable miss + all SSTable levels
Read amplification: O(levels) = typically 5–7 with leveled compaction
```

### 3.3 Compaction Strategies

#### Leveled Compaction (RocksDB default, Cassandra STCS → LCS)

- Each level has a size limit (L1: 256 MB, L2: 2.5 GB, L3: 25 GB...).
- When a level is full: pick one SSTable, merge it with overlapping SSTables in the next level, produce new sorted SSTables.
- Invariant: within L1+, **no key range overlaps between files** at the same level.

```
Benefits:  predictable read amplification (O(levels))
           space amplification ~10%
Costs:     high write amplification (10–30×) — each byte written ~10× across levels
```

#### Size-Tiered Compaction (Cassandra STCS, original LevelDB)

- Group SSTables of similar size into tiers. When N files in a tier exist: merge them into one larger file.
- Less write amplification, but reads are slower (many overlapping files at each tier).

#### FIFO Compaction (time-series data)

- No merging. Just delete oldest SSTables when space limit is hit.
- Only valid for time-series with TTL — data expires, no need to merge.

---

## 4. Java Implementation — Core LSM Components

### 4.1 MemTable

```java
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.Map;

public class MemTable {

    private final ConcurrentSkipListMap<String, String> data = new ConcurrentSkipListMap<>();
    private volatile long sizeBytes = 0;
    private static final long FLUSH_THRESHOLD = 64 * 1024 * 1024; // 64 MB

    public void put(String key, String value) {
        String old = data.put(key, value);
        sizeBytes += estimateSize(key, value);
        if (old != null) sizeBytes -= estimateSize(key, old);
    }

    public void delete(String key) {
        // Tombstone: special sentinel value marks deletion
        put(key, null);
    }

    public String get(String key) {
        return data.get(key); // null = tombstone (deleted) or not present
    }

    public boolean containsKey(String key) {
        return data.containsKey(key);
    }

    public boolean shouldFlush() {
        return sizeBytes >= FLUSH_THRESHOLD;
    }

    public Map<String, String> snapshot() {
        return Map.copyOf(data);
    }

    public long sizeBytes() { return sizeBytes; }
    public int size() { return data.size(); }

    private long estimateSize(String key, String value) {
        return (long) (key.length() + (value == null ? 0 : value.length())) * 2; // UTF-16
    }
}
```

### 4.2 SSTable Writer and Reader

```java
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class SSTable {

    private final Path filePath;
    // Sparse index: every 128th key → file offset
    private final TreeMap<String, Long> sparseIndex = new TreeMap<>();
    private static final int INDEX_INTERVAL = 128;

    // --- WRITE ---
    public static SSTable write(Map<String, String> sortedData, Path path) throws IOException {
        SSTable table = new SSTable(path);
        try (DataOutputStream out = new DataOutputStream(
                new BufferedOutputStream(Files.newOutputStream(path)))) {
            int i = 0;
            for (Map.Entry<String, String> entry : sortedData.entrySet()) {
                long offset = out.size();
                String key = entry.getKey();
                String value = entry.getValue(); // null = tombstone

                out.writeUTF(key);
                out.writeBoolean(value == null); // isTombstone
                if (value != null) out.writeUTF(value);

                if (i % INDEX_INTERVAL == 0) {
                    table.sparseIndex.put(key, offset);
                }
                i++;
            }
        }
        return table;
    }

    private SSTable(Path filePath) {
        this.filePath = filePath;
    }

    // --- READ ---
    public Optional<String> get(String key) throws IOException {
        // Find the largest index key <= target key
        Map.Entry<String, Long> floor = sparseIndex.floorEntry(key);
        if (floor == null) return Optional.empty();

        try (DataInputStream in = new DataInputStream(
                new BufferedInputStream(Files.newInputStream(filePath)))) {
            long skipped = in.skip(floor.getValue());
            if (skipped < floor.getValue()) return Optional.empty();

            // Scan forward until key found or exceeded
            while (in.available() > 0) {
                String k = in.readUTF();
                boolean isTombstone = in.readBoolean();
                String v = isTombstone ? null : in.readUTF();

                int cmp = k.compareTo(key);
                if (cmp == 0) return Optional.ofNullable(v); // null = tombstone
                if (cmp > 0) break; // passed it, key not in this SSTable
            }
        }
        return Optional.empty();
    }

    public Path getPath() { return filePath; }
    public TreeMap<String, Long> getSparseIndex() { return sparseIndex; }
}
```

### 4.3 LSM Storage Engine (orchestrator)

```java
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

public class LSMStorageEngine implements AutoCloseable {

    private final Path dataDir;
    private volatile MemTable activeMemTable = new MemTable();
    private final List<MemTable> immutableMemTables = new CopyOnWriteArrayList<>();
    private final List<SSTable> l0SSTables = new CopyOnWriteArrayList<>();
    private final AtomicInteger sstableCounter = new AtomicInteger(0);
    private final ExecutorService compactionExecutor = Executors.newSingleThreadExecutor();
    private final WAL wal;

    public LSMStorageEngine(Path dataDir) throws IOException {
        this.dataDir = dataDir;
        Files.createDirectories(dataDir);
        this.wal = new WAL(dataDir.resolve("wal.log"));
        recoverFromWAL();
    }

    public void put(String key, String value) throws IOException {
        wal.append(key, value);
        activeMemTable.put(key, value);
        if (activeMemTable.shouldFlush()) triggerFlush();
    }

    public void delete(String key) throws IOException {
        wal.appendTombstone(key);
        activeMemTable.delete(key);
    }

    public Optional<String> get(String key) throws IOException {
        // 1. Check active MemTable
        if (activeMemTable.containsKey(key)) {
            return Optional.ofNullable(activeMemTable.get(key)); // null = deleted
        }
        // 2. Check immutable MemTables newest → oldest
        for (int i = immutableMemTables.size() - 1; i >= 0; i--) {
            MemTable m = immutableMemTables.get(i);
            if (m.containsKey(key)) return Optional.ofNullable(m.get(key));
        }
        // 3. Check L0 SSTables newest → oldest (may overlap)
        for (int i = l0SSTables.size() - 1; i >= 0; i--) {
            Optional<String> result = l0SSTables.get(i).get(key);
            if (result.isPresent()) return result; // present but null = tombstone
        }
        return Optional.empty();
    }

    private synchronized void triggerFlush() {
        MemTable toFlush = activeMemTable;
        activeMemTable = new MemTable();
        immutableMemTables.add(toFlush);
        compactionExecutor.submit(() -> flushToDisk(toFlush));
    }

    private void flushToDisk(MemTable memTable) {
        try {
            int id = sstableCounter.incrementAndGet();
            Path path = dataDir.resolve("l0_" + id + ".sst");
            SSTable sst = SSTable.write(memTable.snapshot(), path);
            l0SSTables.add(sst);
            immutableMemTables.remove(memTable);
            wal.checkpoint(); // truncate WAL up to this flush
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private void recoverFromWAL() throws IOException {
        for (WAL.Entry entry : wal.readAll()) {
            if (entry.isTombstone) activeMemTable.delete(entry.key);
            else activeMemTable.put(entry.key, entry.value);
        }
    }

    @Override
    public void close() throws Exception {
        compactionExecutor.shutdown();
        compactionExecutor.awaitTermination(10, TimeUnit.SECONDS);
        wal.close();
    }
}
```

### 4.4 WAL (Write-Ahead Log)

```java
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class WAL implements AutoCloseable {

    private final Path path;
    private DataOutputStream out;

    public WAL(Path path) throws IOException {
        this.path = path;
        this.out = new DataOutputStream(
            new BufferedOutputStream(
                Files.newOutputStream(path,
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND)));
    }

    public synchronized void append(String key, String value) throws IOException {
        out.writeBoolean(false); // not tombstone
        out.writeUTF(key);
        out.writeUTF(value);
        out.flush();
    }

    public synchronized void appendTombstone(String key) throws IOException {
        out.writeBoolean(true);
        out.writeUTF(key);
        out.flush();
    }

    public List<Entry> readAll() throws IOException {
        List<Entry> entries = new ArrayList<>();
        if (!Files.exists(path)) return entries;
        try (DataInputStream in = new DataInputStream(
                new BufferedInputStream(Files.newInputStream(path)))) {
            while (in.available() > 0) {
                boolean isTombstone = in.readBoolean();
                String key = in.readUTF();
                String value = isTombstone ? null : in.readUTF();
                entries.add(new Entry(key, value, isTombstone));
            }
        }
        return entries;
    }

    public synchronized void checkpoint() throws IOException {
        out.close();
        Files.deleteIfExists(path);
        out = new DataOutputStream(
            new BufferedOutputStream(
                Files.newOutputStream(path, StandardOpenOption.CREATE)));
    }

    @Override
    public void close() throws IOException { out.close(); }

    public record Entry(String key, String value, boolean isTombstone) {}
}
```

---

## 5. Write Amplification, Read Amplification, Space Amplification

The **RUM conjecture**: you can only optimise for two of three:
- **R**ead amplification (RA): extra reads per logical read
- **U**pdate/write amplification (WA): extra writes per logical write
- **M**emory/space amplification (SA): extra storage vs actual data size

| Engine | RA | WA | SA |
|---|---|---|---|
| B-Tree | Low (1–2×) | High (10–30×) | Low (~10%) |
| LSM Leveled | Medium (5–7×) | High (10–30×) | Low (~10%) |
| LSM STCS | High (10–30×) | Low (3–5×) | High (50–100%) |
| Append-only log | High | 1× | Very high |

---

## 6. Where LSM Trees Appear at FAANG

| System | Use | Notes |
|---|---|---|
| **Cassandra** | Primary storage engine | STCS default, LCS for read-heavy tables |
| **RocksDB** | Embedded engine used by MySQL (MyRocks), TiKV, CockroachDB | Leveled compaction |
| **HBase / BigTable** | Distributed column store | Per-region LSM with HDFS backing |
| **LevelDB** | Google's embedded KV store | Original leveled compaction implementation |
| **InfluxDB** | Time-series | FIFO compaction; time always advances |
| **Apache Kafka log segments** | Not LSM, but sequential write principle shared | |

---

## 7. FAANG Interview Callouts

**Why Cassandra over MySQL for write-heavy workloads?**
> Cassandra's LSM engine converts random writes to sequential I/O. At 1M writes/sec, Cassandra scales horizontally across nodes each with sequential-write SSTables, while MySQL InnoDB B-trees require expensive random IOPS and become a single-node bottleneck.

**Compaction strategy trade-off question:**
> Choose **STCS** for write-heavy (less WA, more RA). Choose **LCS** for read-heavy (less RA, more WA). FIFO for pure time-series append-only data.

**Tombstone accumulation (Cassandra antipattern):**
> Heavy deletes create tombstones that accumulate in SSTables. Reads must scan past them until compaction removes them. Mitigation: set TTL instead of explicit delete, tune `gc_grace_seconds`, choose appropriate compaction strategy.

**Follow-up questions to expect:**
1. "How would you handle a hot partition in an LSM-based system?" → Partition by a composite key (user_id + bucket), distribute writes across multiple partitions.
2. "What happens during a compaction? Can reads/writes proceed?" → Reads/writes continue on old SSTables during compaction; atomic swap to new SSTables when compaction completes. Compaction paused/throttled to avoid I/O saturation.
3. "How does RocksDB handle column families differently from a single LSM?" → Each column family has its own MemTable + SSTable hierarchy, allowing independent compaction strategies and TTL policies.
