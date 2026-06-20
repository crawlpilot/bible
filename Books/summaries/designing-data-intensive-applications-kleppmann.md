# Designing Data-Intensive Applications
**Author**: Martin Kleppmann  
**Edition**: O'Reilly Media, 2017  
**Category**: Distributed Systems · Databases · Data Engineering · Stream Processing

> "The limits of my language mean the limits of my world. A data system is only as reliable as the engineer's understanding of its guarantees."

---

## Why This Book Matters for FAANG PE Interviews

DDIA is the definitive technical reference for any interview question touching databases, distributed systems, replication, consistency, or stream processing. Unlike most system design books, it explains *why* systems are designed the way they are — the trade-offs behind B-Tree vs LSM-Tree, the exact anomalies prevented by each isolation level, the mathematical basis of quorum reads. At FAANG PE level, interviewers expect you to justify your architectural choices with this level of precision. This is not a book to read once — it is a reference guide to internalize and revise from.

**Direct interview mapping**:
- Storage engine internals → "Walk me through how Cassandra handles a write" (Staff-level deep-dive)
- Isolation levels → "How do you prevent double-spend in a payment system?"
- CAP/PACELC → "What consistency guarantees does your design provide?"
- Replication models → "How do you handle read-your-writes in a multi-region setup?"
- Stream processing → "How would you build a real-time fraud detection pipeline?"

---

## TL;DR — 3 Ideas to Internalize

1. **Data systems are composable primitives**: storage engines, replication, partitioning, and encoding are independent concerns — master each one, then reason about how they interact in a given database product.
2. **Every distributed design is a deliberate trade-off between consistency, availability, and latency** — the question is never "which two do I pick?" but "what is my system's behaviour during a partition, and what is it during normal operation?" (PACELC, not CAP).
3. **Batch and stream processing are two points on the same spectrum** — modern systems (Apache Flink) unify them under a single programming model; the differences are about latency and state management, not fundamental architecture.

---

## Section A — The Three Pillars: Reliability, Scalability, Maintainability

### Reliability

**Kleppmann's definition**: The system continues to work correctly (performing the correct function at the desired level of performance) even when things go wrong.

Faults (individual component failures) are not the same as failures (system-wide). The goal is fault-tolerance: detecting and handling faults before they become failures.

**Fault taxonomy**:

| Fault Type | Examples | Mitigation |
|------------|----------|------------|
| Hardware faults | Disk crash, RAM corruption, power outage | RAID, redundant power, replication |
| Software errors | Bug in OS, cascading failures, memory leaks | Process isolation, chaos testing, circuit breakers |
| Human errors | Misconfiguration, schema migration mistakes | Staging environments, rollback, gradual rollouts |

**Key insight**: Hardware faults are largely uncorrelated (one disk failing doesn't cause others to fail). Software errors are correlated (one bug can take down all instances simultaneously) — this is why software reliability is harder than hardware reliability at scale.

### Scalability

**Kleppmann's definition**: As the system grows, there are reasonable ways of dealing with that growth. Scalability is not a one-dimensional property — growth can be in data volume, read traffic, write traffic, or complexity.

**Load parameters**: Quantify the load before designing the solution.

**Twitter Home Timeline — The Canonical Case Study**:

| Approach | Mechanism | Problem |
|----------|-----------|---------|
| Query on read | SELECT tweets FROM followees WHERE user_id IN (...) | 300K reads/s, each joining millions of follower rows |
| Fan-out on write | Pre-compute home timeline in Redis for each follower on tweet creation | 6K writes/s × average 75 followers = 4.5M cache inserts/s for @justinbieber |
| Hybrid (Twitter's actual solution) | Fan-out for normal users; merge on read for accounts with >1M followers | Reduces fan-out storm; celebrity tweets merged at read time |

**What this teaches**: The optimal architecture depends on the read:write ratio *and* the distribution of the data (power law: a small number of accounts have disproportionate fan-out). Measure before you design.

**Percentile latency — the right way to measure performance**:
- Mean latency hides the distribution; a single slow response doesn't move the mean much
- **P99**: 1 in 100 requests is slower than this value; your highest-value customers (who make the most requests) are disproportionately likely to experience this
- **Tail latency amplification**: a request that calls 100 services serially has a cumulative P99 that is far worse than any individual service's P99

```
Single service P99 = 200ms
Request that calls 100 services serially:
  P(at least one call hits P99) = 1 - (0.99)^100 ≈ 63%
  → 63% of user-facing requests experience 200ms+ latency on at least one hop
```

**FAANG interview application**: "Before I propose any solution, I need to understand the load parameters: what is the read:write ratio? What is the distribution — is it uniform or does it follow a power law (a small number of users/keys generate disproportionate load)? For Twitter's timeline, the power-law distribution of follower counts is the key variable that drives the hybrid fan-out architecture."

---

### Maintainability

Three design principles:
- **Operability**: Make it easy for ops teams to keep the system running (good monitoring, clear documentation, predictable failure modes)
- **Simplicity**: Remove accidental complexity — complexity that arises from the implementation, not from the problem itself. Abstraction is the tool.
- **Evolvability**: Make it easy to adapt the system as requirements change — closely related to schema evolution and backward compatibility

---

## Section B — Data Models and Query Languages

The data model is the most foundational decision in any system design — it determines what queries are efficient, what relationships are expressible, and how the data can evolve.

### Relational Model (SQL)

- **Schema-on-write**: structure enforced by the database at insert/update time
- **Normalization**: eliminate duplication through foreign key references; join at query time
- **Strengths**: powerful ad-hoc queries, complex joins, multi-table ACID transactions, mature tooling
- **Best for**: complex many-to-many relationships, reporting, financial data, audit trails

### Document Model (MongoDB, CouchDB, DynamoDB document mode)

- **Schema-on-read**: structure validated by application code; database accepts any JSON/BSON document
- **Data locality**: an entire document is stored and retrieved together — one read for a self-contained entity
- **Limitations**: poor support for cross-document joins; many-to-many relationships require application-level joins or denormalization
- **Best for**: self-contained document data with one-to-many tree relationships (e.g., a résumé with work history, education, skills)

**Impedance mismatch**: OOP in-memory objects don't map cleanly to relational tables (especially for nested structures). Document DBs reduce this mismatch for tree-shaped data. ORMs exist to bridge the gap for relational systems.

### Graph Model (Neo4j, Amazon Neptune, JanusGraph)

- **Vertices** (entities) and **edges** (relationships), each with arbitrary properties
- No schema restriction on which vertex types can connect to which edge types
- Recursive graph traversal is natural; equivalent SQL requires multiple self-joins
- **Best for**: highly interconnected data where the relationships are as important as the entities — social graphs, fraud detection (ring structures), route planning, knowledge graphs

### Query Language Comparison

| Language | Model | Paradigm | Key Feature |
|----------|-------|----------|-------------|
| SQL | Relational | Declarative | Optimizer chooses execution plan; parallelizable |
| MongoDB Query Language (MQL) | Document | Declarative (JSON filters) | Rich document projection, aggregation pipeline |
| Cypher | Graph | Declarative (pattern matching) | MATCH (a)-[:KNOWS]->(b) pattern syntax |
| Gremlin | Graph | Imperative traversal | Step-by-step graph traversal; works across graph DBs |
| Datalog | Graph/Relational | Declarative (logic-based) | Rules for recursive queries; foundation of Datomic |
| MapReduce | Any | Imperative (functional) | Parallel batch computation over partitioned data |

**FAANG interview application**: "I map the entity relationships before choosing a data store. One-to-many tree structure with self-contained entities? Document DB — one network round-trip to fetch a complete résumé. Many-to-many with complex joins? Relational — the query optimizer handles the join strategy. Arbitrary traversal patterns where relationships have business meaning? Graph — Cypher pattern matching is far more expressive than recursive CTEs."

---

## Section C — Storage and Retrieval

This is the most interview-critical chapter in DDIA. Storage engine internals appear directly in staff-level system design deep-dives, especially questions about Cassandra, Kafka, RocksDB, and PostgreSQL.

### Hash Indexes

- In-memory hash map: `key → byte_offset` in an append-only log file
- All writes append to the log; reads look up the byte offset in the hash map, seek to that position, read the value
- **Compaction**: periodically merge log segments, keeping only the latest value per key — reclaims disk space
- **Limitations**: all keys must fit in RAM (hash map is in memory); range queries are unsupported (hash map has no ordering)
- **Real system**: Bitcask (Riak's default storage engine) — excellent for workloads where all keys fit in RAM and values are small

### SSTables and LSM-Trees (Log-Structured Merge-Tree)

**The core write path — memorize this:**

```
Client Write
    │
    ▼
Memtable (in-memory balanced BST: Red-Black or AVL tree)
    │ when memtable exceeds threshold (~4MB)
    ▼
SSTable flush to disk (keys sorted, sequential write)
    │ background
    ▼
Compaction: merge multiple SSTables into larger sorted SSTables
    │
    ▼
Resulting SSTable (new compacted, sorted file on disk)
```

**SSTable (Sorted String Table)**: A file where all (key, value) pairs are stored in sorted key order. Because the file is sorted, you can use binary search to find a key — but you don't even need to store every key in the index. Store a sparse index (every 1KB or so), and scan within each block.

**Bloom filter**: Before checking SSTables for a key, consult the Bloom filter — a space-efficient probabilistic structure that says "definitely not in this file" (no false negatives) or "maybe in this file" (some false positives). Eliminates the majority of unnecessary disk reads for non-existent keys. Configurable false positive rate (typically 1%): lower FPR → larger Bloom filter.

**Read path**:
1. Check memtable (most recent writes)
2. Check most recent SSTable (via Bloom filter first, then sparse index + block scan)
3. Check next most recent SSTable… and so on

**Compaction strategies**:

| Strategy | Mechanism | Write Amplification | Space Amplification | Read Performance | Used By |
|----------|-----------|--------------------|--------------------|-----------------|---------|
| Size-tiered | Merge N same-size SSTables into one larger one | Lower | Higher (overlapping key ranges between tiers) | Slower (must check all tiers) | Cassandra (default), HBase |
| Leveled | Data organized in levels (L0→L1→…); L(N) is 10× larger than L(N-1); non-overlapping key ranges per level | Higher (~10–30×) | Lower | Faster (check fewer files per level) | LevelDB, RocksDB, Cassandra (option) |

**Write amplification**: The ratio of bytes written to disk vs bytes written by the application. For leveled compaction, each byte may be rewritten 10–30 times as it moves through levels — relevant for write-heavy workloads and SSD wear.

**Systems using LSM-Trees**: Cassandra, HBase, LevelDB, RocksDB, InfluxDB, Apache Lucene (full-text index)

**FAANG interview application**: "Cassandra uses LSM-Trees with leveled compaction in its newer versions. For a write-heavy metrics ingestion pipeline (500K writes/sec), Cassandra is the right choice — all writes are sequential appends to the memtable, not random I/O. I'd configure the compaction strategy to leveled for predictable read latency at the cost of higher write amplification. For a read-heavy lookup service, I'd consider PostgreSQL's B-Tree instead."

---

### B-Trees

**The dominant storage engine for relational databases.**

**Structure**:
- Data divided into fixed-size **pages** (typically 4KB, matching OS page size)
- Pages organized as a tree: one root page, internal pages (routing only), leaf pages (store actual key-value pairs)
- **Branching factor** (number of children per internal page): typically 500–1000
- A 4-level B-Tree with branching factor 500 can index 500^4 = 62.5 billion pages — enough for 256TB

**Write path**:
1. Locate the leaf page that contains the key range (tree traversal: O(log n) page reads)
2. Modify the leaf page in-place (overwrite the page on disk)
3. If the leaf is full, split it into two pages and update the parent

**Write-Ahead Log (WAL)**: Before modifying any page, write the intended change to an append-only WAL on disk. If the system crashes mid-write, the WAL allows reconstruction of the intended state. This is why B-Tree writes require at least two disk writes (WAL + page) while LSM-Tree writes only require one (append to memtable log).

**Systems using B-Trees**: PostgreSQL, MySQL (InnoDB), SQLite, Oracle, SQL Server, etcd (BoltDB)

### B-Tree vs LSM-Tree — Master Comparison Table

| Dimension | B-Tree | LSM-Tree |
|-----------|--------|----------|
| Write performance | Slower — random I/O to update leaf pages in-place | Faster — sequential writes to in-memory memtable |
| Read performance | Faster — O(log n) page reads, predictable | Slower — must check memtable + multiple SSTables |
| Space amplification | Low — in-place updates reclaim space immediately | Higher — until compaction runs, stale data consumes space |
| Write amplification | Lower (~2–5×) | Higher — leveled compaction: ~10–30× |
| Range queries | Efficient — sequential leaf page traversal | Efficient — keys sorted within SSTables |
| Crash recovery | WAL required — replay WAL on startup | Replay memtable from commit log on startup |
| Compaction pauses | None | Yes — compaction can saturate disk I/O, causing read latency spikes |
| Key lookup for non-existent keys | Fast (tree traversal, definitive no) | Requires Bloom filter (otherwise checks all SSTables) |
| Best for | Read-heavy, mixed OLTP workloads | Write-heavy: time-series, logs, event sourcing |
| Examples | PostgreSQL, MySQL InnoDB, SQLite | Cassandra, HBase, RocksDB, InfluxDB |

### Indexes and Their Trade-offs

**Primary index**: the main B-Tree or LSM-Tree structure, keyed on the primary key.

**Secondary index**: index on a non-primary column. Two implementations:

| Implementation | Mechanism | Write Impact | Read Impact |
|----------------|-----------|-------------|------------|
| Index with references | Leaf stores a reference (row ID / primary key) to the actual row | One index entry per indexed row | Two lookups: index → heap row |
| Clustered index | Leaf stores the actual row data (not just a reference) | Larger index pages | One lookup: index is the data |
| Covering index | Leaf stores the primary key + some extra columns | Slightly larger | Zero heap lookups if query needs only indexed columns |
| Multi-column index | B-Tree on concatenated columns (a, b, c) | Normal | Efficient for queries filtering on a prefix of columns; useless for b or c alone |

**Local vs Global secondary index (for partitioned data)**:

| Type | Write path | Read path | Example |
|------|-----------|----------|---------|
| Local (document-partitioned) | Index entry written on same partition as the row | Scatter-gather: query all partitions, merge results | Most databases (Cassandra, MongoDB) |
| Global (term-partitioned) | Index entries distributed across partitions by indexed value | Read from one or few index partitions | DynamoDB GSI, Elasticsearch |

### OLTP vs OLAP

| Dimension | OLTP (Online Transaction Processing) | OLAP (Online Analytical Processing) |
|-----------|--------------------------------------|-------------------------------------|
| Query pattern | Small rows, fetched by primary key; low latency | Aggregate across millions of rows; high latency acceptable |
| Write pattern | Random-access, low-latency, concurrent | Bulk ETL or event stream |
| Schema | Normalized (3NF) | Denormalized (star/snowflake schema) |
| Dataset size | GB–TB | TB–PB |
| Storage engine | Row-oriented (B-Tree, LSM) | Column-oriented (Parquet, ORC) |
| Primary consumers | Application back-end, user-facing features | Internal analysts, data scientists, ML pipelines |
| Examples | PostgreSQL, MySQL, DynamoDB | Redshift, BigQuery, Snowflake, ClickHouse |

### Column-Oriented Storage

**Why it matters for analytics**: an OLAP query that aggregates across one column of a 100-column table with 10B rows only needs 1/100th of the data. Row storage requires reading all 100 columns. Column storage reads only the needed column.

**How it works**: Instead of storing all columns of a row together, store all values of each column together.

```
Row storage (OLTP):   [user1: name,age,email,country,...] [user2: name,age,email,country,...]
Column storage (OLAP): [name: user1_name, user2_name, ...] [age: user1_age, user2_age, ...]
```

**Compression**: Column data is homogeneous → highly compressible.
- **Bitmap encoding**: for low-cardinality columns (e.g., country: 195 distinct values), store one bit per row per value. 64 rows fit in a single 64-bit integer.
- **Run-length encoding**: `[3 × US, 2 × UK, 5 × DE]` instead of storing individual values. Achieves 100:1+ compression on sorted low-cardinality columns.

**Vectorized processing**: Operations on a column of integers can use CPU SIMD (Single Instruction, Multiple Data) instructions — process 8–16 integers per CPU cycle. Column storage enables this; row storage does not.

**Sort order in column stores**: Rows sorted by one column (e.g., date) enables run-length encoding on that column. Secondary sort key enables compression on a second column. Redshift allows defining multiple sort keys per table for different query patterns — each is a full copy of the table (storage trade-off for query speed).

**FAANG interview application**: "For the analytics layer of a ride-sharing platform — computing driver utilization, surge pricing models, revenue attribution — I'd use BigQuery or Redshift (column-oriented). The queries aggregate across dimensions (time, geography, driver tier) on tables with billions of rows. Column storage + vectorized execution + compression means these queries run in seconds rather than minutes. The OLTP path (driver location updates, ride matching) stays on DynamoDB."

---

## Section D — Encoding and Evolution

### Why Encoding Matters

Services are deployed independently. At any moment during a rolling deploy, old and new code co-exist — they must be able to read each other's data.

- **Backward compatibility**: new code reads data written by old code (easy — just don't remove or repurpose fields)
- **Forward compatibility**: old code reads data written by new code (harder — old code must gracefully ignore unknown fields)

### Encoding Format Comparison

| Format | Schema Required | Encoding | Backward Compat | Forward Compat | Size | Best For |
|--------|-----------------|----------|-----------------|----------------|------|----------|
| JSON | No | Text (UTF-8) | Partial (unknown fields ignored by lenient parsers) | Partial | Large | Human-readable APIs, config |
| XML | No | Text | Partial | Partial | Largest | Legacy enterprise integrations |
| Protocol Buffers | Yes (.proto file) | Binary (field tags) | Yes (add optional fields) | Yes (ignore unknown tags) | Small | High-performance gRPC services |
| Thrift | Yes (IDL file) | Binary (field tags) | Yes | Yes | Small | Thrift-based internal services |
| Avro | Yes (schema registry) | Binary (no field tags) | Yes (via schema evolution rules) | Yes | Smallest | Hadoop, Kafka event streams |
| MessagePack | No | Binary | Partial | Partial | Medium | JSON replacement where bytes matter |

**Protocol Buffers — critical details**:
- Each field is identified by a **field tag number** (not field name) in the binary encoding
- Renaming a field is safe (tag unchanged); adding a new field is safe if optional; never reuse a tag number
- **Removing** a field: mark it `reserved` so the tag is never reused; old code reading new messages ignores missing optional fields (backward compat)
- Adding a **required** field breaks backward compatibility — old writers won't include it; avoid `required` in production schemas

**Avro — critical details**:
- No field tags in the binary encoding — just values in schema-defined order
- Reader schema and writer schema can differ; Avro reconciles them at read time using a **schema registry**
- Field matching is by field name (not tag) — renaming a field breaks compatibility
- Adding a field with a default value is safe; removing a field is safe if it had a default value
- Ideal for Kafka-based event pipelines with many consumers at different schema versions

**FAANG interview application**: "For an event-driven architecture where the same Kafka topic is consumed by 15 downstream services at different deploy cadences, I'd use Avro with a schema registry (Confluent Schema Registry). Producers register schemas; consumers use reader-writer schema evolution to tolerate schema changes without coordinated deploys. This is how LinkedIn and Confluent handle schema evolution in production Kafka pipelines."

---

## Section E — Replication

Replication = keeping a copy of the same data on multiple nodes. Three main reasons: fault tolerance (if one node fails, others can serve), read throughput (spread reads across replicas), and latency (geo-distribute data close to users).

### Single-Leader Replication

**Architecture**: One node designated as the leader. All writes go to the leader. Leader writes to its local storage and sends the changes to all followers via a replication log. Reads can go to any follower (eventual consistency) or to the leader only (strong consistency).

**Replication log methods**:

| Method | Mechanism | Pros | Cons |
|--------|-----------|------|------|
| Statement-based | Replicate SQL INSERT/UPDATE/DELETE statements | Human-readable log | Non-deterministic functions (NOW(), RAND(), auto-increment) break consistency |
| WAL shipping | Send raw WAL bytes from leader storage engine | Exact replica of leader state | Tightly coupled to storage engine version — cannot upgrade followers independently |
| Row-based (logical) | Replicate before/after row images | Storage-engine independent; supports heterogeneous replication (PostgreSQL → Elasticsearch) | Larger log for wide rows |
| Trigger-based | Application-level triggers write to replication table | Flexible; any replication logic | High overhead; error-prone |

**Replication lag anomalies** — the three problems that arise when reads go to stale followers:

| Anomaly | Scenario | Solution |
|---------|----------|----------|
| Read-your-writes (RYW) violation | User submits a form, refreshes, reads from a stale replica that hasn't received the write yet — their own update appears lost | Route user's own reads to the leader for 60 seconds after a write. Or: read from leader if the user's last-write-timestamp is more recent than the replica's replication lag |
| Monotonic reads violation | Two reads return results from different replicas at different replication lag — the second read returns data that appears older than the first (time goes backward) | Route each user session to the same replica consistently (session affinity / sticky reads) |
| Consistent prefix reads violation | In a partitioned system, messages appear out of causal order — the response appears before the question | Ensure causally related writes go to the same partition; or use causal timestamps |

**Mr. Poons and Mrs. Cake** (Kleppmann's example): Mrs. Cake responds to Mr. Poons' question. If reads go to different replicas, Mr. Poons reads from a replica that has the response but not the question — the response appears to exist without context. Consistent prefix reads prevents this.

**Leader failure — failover risks**:
- **Split-brain**: two nodes both believe they are the leader. Must have a mechanism to force one to step down (fencing token, STONITH).
- **Data loss**: the new leader may not have received all writes from the old leader. Choosing the "most up-to-date" follower minimizes but doesn't eliminate data loss.
- **Asynchronous replication**: any unacknowledged writes from old leader are discarded when a new leader is elected — by design, for performance. Use synchronous replication (or semi-synchronous) if durability requires zero data loss.

**FAANG interview application**: "For a social media profile service at 100M users, I'd use single-leader replication with 3 read replicas. All writes go to the leader; reads are distributed across replicas with session-affinity to prevent monotonic reads violations. For the 'view your own profile after editing' case (read-your-writes), I route the user's own reads to the leader for 30 seconds after an update. Replication lag budget: < 500ms under normal conditions."

---

### Multi-Leader Replication

**When to use**:
- **Multi-datacenter**: one leader per datacenter; leaders replicate to each other across WAN. Writes served locally (low latency). WAN replication is asynchronous — tolerates transient connectivity loss.
- **Offline clients**: mobile app with a local database (CouchDB) that syncs when online. Each device is a leader; conflicts resolved on sync.
- **Collaborative editing**: Google Docs — every keystroke is a write. CRDTs (Conflict-free Replicated Data Types) for automatic conflict resolution.

**Conflict resolution strategies**:

| Strategy | Mechanism | Risk |
|----------|-----------|------|
| Last-write-wins (LWW) | Each write carries a timestamp; highest timestamp wins | Clock skew causes data loss; concurrent writes silently overwrite each other |
| Merge values | Concatenate or union concurrent values | Application-specific; works for sets/lists (shopping cart), not for scalars |
| Record and resolve later | Store all conflicting versions (siblings); surface to user or application for resolution | Complex UX; requires user intervention |
| CRDTs | Mathematically defined merge functions (grow-only sets, OR-sets, counters) | Only works for specific data types |
| Custom conflict handler | Application-level callback called on conflict | Most flexible; most complex |

**Replication topologies** (for multi-leader):
- **Circular**: A → B → C → A. Single node failure breaks the ring.
- **Star**: Central node replicates to all others. Single point of failure.
- **All-to-all**: Every leader replicates to every other leader. Most resilient; requires causality tracking (version vectors) to prevent out-of-order replication.

---

### Leaderless Replication (Dynamo-Style)

Pioneered by Amazon Dynamo (2007). Any replica can accept writes; client sends writes to N replicas and reads from R replicas. No leader election required.

**Quorum condition**:

```
W + R > N  →  at least one read-quorum replica has the latest write

Typical: N=3, W=2, R=2
  → reads and writes succeed even if 1 node is unavailable
  → W + R = 4 > N = 3 ✓

High availability (at cost of consistency): N=3, W=1, R=1
  → any single node handles reads or writes
  → W + R = 2 = N → not guaranteed to read latest write

Strong consistency: N=3, W=3, R=1
  → all nodes must acknowledge writes (expensive, slow)
  → W + R = 4 > N = 3 ✓ but write latency = max(all 3 nodes)
```

**Sloppy quorum**: During a network partition where fewer than W nodes of the normal N are reachable, should the system reject writes (maintaining quorum guarantee) or accept writes on reachable nodes outside the normal N set (improving availability)?

- **Strict quorum**: reject writes when W nodes unavailable → consistent, less available
- **Sloppy quorum**: accept writes on any reachable nodes (even outside the normal preference list) → more available, weaker consistency
- **Hinted handoff**: when the partition heals, nodes that accepted "foreign" writes hand them off to the correct home nodes

**Read repair**: When a client reads from R replicas and detects stale values (by comparing version vectors), it writes the latest value back to the stale replicas. Only triggers on read paths — hot keys get repaired frequently; cold keys may stay stale.

**Anti-entropy**: Background process that continuously compares replicas and copies missing data. Uses **Merkle trees** to efficiently identify differences without transferring all data (compare hashes top-down, then recursively dig into differing subtrees).

**Detecting concurrent writes — version vectors (vector clocks)**:

```
Replica 1: [R1=1, R2=0, R3=0]  (R1 wrote first)
Replica 2: [R1=1, R2=1, R3=0]  (R2 wrote after seeing R1's write)
Replica 3: [R1=1, R2=0, R3=1]  (R3 wrote concurrently with R2)

R2 and R3 are concurrent (neither dominates the other in the vector clock)
→ siblings detected → conflict resolution required
```

**Examples**: Amazon DynamoDB, Apache Cassandra, Riak, Voldemort

**FAANG interview application**: "For a shopping cart service at Amazon scale, I'd use leaderless replication with N=3, W=2, R=2, and sloppy quorum enabled. The cart is a natural CRDT candidate — concurrent adds from different devices are unioned (OR-Set CRDT). The LWW conflict resolution used by vanilla DynamoDB would incorrectly discard concurrent additions; explicit CRDT merging prevents silent data loss. Hinted handoff ensures eventual delivery during partition events."

---

## Section F — Partitioning (Sharding)

Partitioning = splitting the dataset across multiple nodes so each node stores only a subset. Necessary when data volume or write throughput exceeds a single node's capacity.

### Partitioning Strategies

| Strategy | Mechanism | Pros | Cons | Best For |
|----------|-----------|------|------|----------|
| Key-range | Assign contiguous key ranges to partitions (A–M, N–Z) | Efficient range queries; adjacent keys on same partition | Hotspots if keys are monotonically increasing (timestamps) | Time-series, alphabetical scans |
| Hash | `partition = hash(key) mod N` | Even key distribution; no hotspots (assuming uniform hash) | Range queries require scatter-gather across all partitions | Random access, key-value lookups |
| Consistent hashing | Keys and nodes placed on a virtual ring; each node owns keys from its position to next node's position | Adding/removing a node moves only 1/N of keys (vs full reshuffle for hash mod N) | Uneven load without virtual nodes; virtual nodes (vnodes) fix this | Distributed caches (Cassandra, Memcached), DHTs |

**Hotspot mitigation for known hot keys** (e.g., celebrity Twitter accounts):
```
Strategy: append a random 2-digit decimal suffix to the hot key
  "bieber" → "bieber-01", "bieber-47", "bieber-83", ...
  Writes distributed across 100 virtual partitions
  Reads: scatter-gather across all 100 suffixes, merge results

Cost: reads are now 100× more expensive.
Benefit: writes are distributed, eliminating hotspot.
Application decides: is this key hot enough to warrant the read overhead?
```

### Secondary Indexes on Partitioned Data

Secondary indexes in a partitioned database must also be partitioned. Two approaches:

| Type | Write | Read | Consistency | Example |
|------|-------|------|-------------|---------|
| Local (document-partitioned) | Write index entry on same partition as the primary record | Scatter-gather: query all N partitions, merge results | Eventually consistent (each partition's index is local) | Cassandra (local indexes), MongoDB |
| Global (term-partitioned) | Index entries for a term distributed across partitions by the indexed value | Read from 1–few index partitions (efficient) | Eventually consistent (async index update) | DynamoDB GSI, Elasticsearch |

### Rebalancing Strategies

| Strategy | Mechanism | Pros | Cons |
|----------|-----------|------|------|
| Fixed number of partitions | Create many more partitions than nodes at startup (e.g., 1000 partitions on 10 nodes = 100 partitions/node); add node → assign it some existing partitions | Simple; partition migration is whole-partition moves | Partition count must be estimated upfront; too few → partitions grow unbounded; too many → overhead |
| Dynamic partitioning | Split a partition when it exceeds a size threshold; merge two adjacent partitions when they shrink below a threshold | Adapts to data size automatically | Only one partition initially — all writes go to one node until the first split (pre-splitting required for new tables) |
| Partition proportional to nodes | Fixed number of partitions per node (e.g., 256 per node); adding a node randomly splits existing partitions | Partition size stays roughly constant | Splits are random — can create uneven key distribution |

**Request routing (service discovery)**:
- **ZooKeeper-based**: ZK tracks partition-to-node mapping; all clients (or a routing tier) watch ZK for changes — used by HBase, Kafka, SolrCloud
- **Gossip-based**: clients can contact any node; nodes forward requests to the correct node — used by Cassandra (with coordinator pattern)
- **Client-side routing**: client has a full copy of the partition map and routes directly — most efficient, but requires client-side cache invalidation

**FAANG interview application**: "For a distributed key-value store handling 10M writes/sec, I'd use consistent hashing with 256 virtual nodes per physical node. This allows me to add capacity incrementally — adding a new node moves 1/N of the keys, not a full reshuffle. I'd provision 1000 partitions upfront on 10 nodes (100 partitions/node), allowing me to add nodes without repartitioning the cluster. ZooKeeper tracks the partition map; the application tier caches it locally and refreshes on ZK change events."

---

## Section G — Transactions

Transactions group multiple reads and writes into a single logical unit. The system guarantees that either all operations in the transaction succeed (commit) or none of them do (abort/rollback).

### ACID — Precise Definitions

| Property | Precise Kleppmann Definition | Common Misconception |
|----------|------------------------------|---------------------|
| **Atomicity** | If a transaction is aborted, all writes it made are rolled back. It is the ability to abort a transaction on error and have all writes discarded. | Often confused with concurrency (it is not — atomicity is about abortability, not isolation) |
| **Consistency** | Certain invariants about the data (e.g., account balances never go negative) must always hold. This is a property of the **application**, not the database — the DB cannot enforce business logic it doesn't know about. | People assume RDBMS guarantees consistency; it only enforces the constraints you explicitly declare (CHECK, FK, UNIQUE) |
| **Isolation** | Concurrently executing transactions are isolated from each other — as if they ran serially, one after another. Often weakened for performance (see isolation levels below). | Many databases default to read committed, not serializable — transactions are not fully isolated by default |
| **Durability** | Once a transaction is committed, the data it wrote will not be lost, even if the system crashes. Requires: WAL + fsync, or replication to durable replicas. | Durability is probabilistic — even with replication, correlated failures (data center fire) can cause data loss |

### Isolation Levels and Anomalies — The Most Important Table in DDIA

| Isolation Level | Dirty Read | Non-Repeatable Read | Phantom Read | Write Skew | Lost Update |
|-----------------|:---:|:---:|:---:|:---:|:---:|
| Read Uncommitted | ❌ possible | ❌ possible | ❌ possible | ❌ possible | ❌ possible |
| Read Committed | ✅ prevented | ❌ possible | ❌ possible | ❌ possible | ❌ possible |
| Repeatable Read | ✅ prevented | ✅ prevented | ⚠️ partial* | ❌ possible | ✅ prevented |
| Snapshot Isolation (MVCC) | ✅ prevented | ✅ prevented | ✅ prevented | ❌ possible | ✅ prevented |
| Serializable | ✅ prevented | ✅ prevented | ✅ prevented | ✅ prevented | ✅ prevented |

*MySQL Repeatable Read uses gap locks to prevent phantom reads. PostgreSQL's snapshot isolation prevents phantoms as a side effect of MVCC.

**Anomaly Definitions — Know These Precisely**:

**Dirty read**: Transaction A reads a value written by Transaction B before B has committed. If B aborts, A has read data that was never "real."
```
T1: UPDATE accounts SET balance = balance - 100 WHERE id = 1;  (not committed)
T2: SELECT balance FROM accounts WHERE id = 1;  → reads T1's uncommitted value
T1: ROLLBACK;
→ T2 acted on a value that never existed
```

**Non-repeatable read**: Transaction A reads a row, Transaction B updates and commits that row, Transaction A reads the same row again and gets a different value.
```
T1: SELECT balance FROM accounts WHERE id = 1;  → 500
T2: UPDATE accounts SET balance = 300 WHERE id = 1; COMMIT;
T1: SELECT balance FROM accounts WHERE id = 1;  → 300 (changed!)
```

**Phantom read**: Transaction A executes a query that returns a set of rows. Transaction B inserts or deletes a row that would match that query. Transaction A re-executes the query and gets a different set of rows.
```
T1: SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;  → 2
T2: INSERT INTO doctors (name, on_call) VALUES ('Dr. Brown', TRUE); COMMIT;
T1: SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;  → 3 (phantom row appeared)
```

**Write skew**: Two transactions read the same data, make a decision based on it, then each writes a value that invalidates the other's assumption. Neither transaction individually violates any constraint; together they do.
```
Business rule: at least 1 doctor must be on-call at all times.

T1: SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;  → 2 (safe to go off-call)
T2: SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;  → 2 (safe to go off-call)
T1: UPDATE doctors SET on_call = FALSE WHERE id = 1; COMMIT;
T2: UPDATE doctors SET on_call = FALSE WHERE id = 2; COMMIT;
→ 0 doctors on-call. Business rule violated. Neither transaction alone was wrong.
```

**Lost update**: Two transactions do read-modify-write on the same record; one overwrites the other's update.
```
T1: x = READ(counter);  → 10
T2: x = READ(counter);  → 10
T1: WRITE(counter, x + 1);  → 11
T2: WRITE(counter, x + 1);  → 11 (T1's increment is lost)
```

### Snapshot Isolation and MVCC

**Multi-Version Concurrency Control (MVCC)**: Instead of locking rows on read, the database keeps multiple versions of each row.

```
Each row has: created_by_txn_id, deleted_by_txn_id (or NULL)
A transaction with id=12 can see only rows where:
  created_by_txn_id <= 12
  AND (deleted_by_txn_id IS NULL OR deleted_by_txn_id > 12)
```

**Key properties**:
- Writers don't block readers; readers don't block writers
- Each transaction sees a consistent snapshot of the database as of its start time
- Old versions garbage-collected after no active transaction needs them (VACUUM in PostgreSQL)
- Used by: PostgreSQL, MySQL InnoDB, Oracle, SQL Server (with snapshot isolation enabled)

### Implementing Serializability

| Method | Mechanism | Throughput | Latency | Deadlocks | Use When |
|--------|-----------|-----------|---------|-----------|----------|
| Actual serial execution | Single-threaded queue; one transaction at a time in RAM (VoltDB, Redis) | Limited to one CPU core throughput | Low (no locking) | Impossible (no concurrency) | Transactions very short; entire dataset fits in RAM |
| Two-Phase Locking (2PL) | Shared (read) locks held until commit; exclusive (write) locks held until commit; no reads during writes | Low under high contention | High (locks block) | Frequent; need deadlock detection + abort | Historical standard; now largely superseded |
| Serializable Snapshot Isolation (SSI) | Optimistic: run transactions concurrently under snapshot isolation; detect and abort at commit time if a serializability violation is detected | Higher than 2PL under low contention | Low (no locks during execution) | None (abort, not deadlock) | PostgreSQL's Serializable level; CockroachDB |

**SSI mechanics**: SSI tracks which transactions read which keys. If Transaction A's reads are later overwritten by Transaction B before A commits, SSI detects the anti-dependency and aborts A. Under low contention, most transactions succeed without abort. Under high contention, abort rate rises — application must retry.

**FAANG interview application**: "For a financial ledger that must prevent double-spend, I'd use PostgreSQL with `ISOLATION LEVEL SERIALIZABLE` (SSI). Write-skew (two concurrent withdraw transactions both reading a 'sufficient balance' and both committing) is prevented by SSI's anti-dependency tracking — one of the two transactions will be aborted and must be retried. The ~20% throughput penalty over Snapshot Isolation is justified by the correctness guarantee. I would NOT use application-level `SELECT FOR UPDATE` locks — they're correct but create contention and deadlock risk at scale."

---

## Section H — The Trouble with Distributed Systems

The most important conceptual shift in DDIA: distributed systems are fundamentally different from single-node systems because failures are **partial** — some components fail while others continue. In a single node, a crash is obvious; in a distributed system, you cannot distinguish a crashed node from a very slow one or a network partition.

### Unreliable Networks

Distributed systems use **asynchronous networks** (no timing guarantees). A packet sent over the network may be:
- Lost (router queue overflow, network cable cut)
- Queued and delayed arbitrarily (in the network, at the OS, at the VM hypervisor)
- Delivered multiple times (network retry)
- Reordered relative to other packets
- Delivered to a crashed recipient (recipient processes it and then crashes)

**The fundamental implication**: You cannot distinguish between a slow node and a crashed node using only timeouts. A timeout is all you have. The appropriate timeout is workload-dependent and must be calibrated empirically.

**Network faults in practice**: Anecdote from Kleppmann — a study of a single large datacenter found ~12 network faults per month, with some causing partial connectivity (some hosts can reach a node, others cannot). These partial failures are the hardest to handle.

### Unreliable Clocks

Three types of clocks in distributed systems:

| Clock Type | Guarantee | Across Nodes | Safe For |
|------------|-----------|-------------|---------|
| Wall clock (time-of-day) | Approximately reflects physical time | Not synchronized — can differ by 100ms–1s under NTP, more under load | Human-readable timestamps; NOT for ordering events |
| Monotonic clock | Only moves forward; no relationship to wall time | Meaningless — each process has its own | Measuring elapsed time within a single process |
| Logical clock (Lamport, vector) | Causal ordering — if A happened-before B, A's timestamp < B's | Comparable across nodes (by design) | Event ordering in distributed systems |

**The problem with Last-Write-Wins using wall clocks**: If two nodes have clocks skewed by 100ms and both write the same key concurrently, the one with the higher clock value wins — but the higher clock value may be on the node that wrote first in physical time. Data loss is silent.

**Google Spanner TrueTime**: GPS receivers + atomic clocks in each data center provide a bounded time uncertainty interval `[t_earliest, t_latest]`. Spanner waits out the uncertainty interval (typically 7ms) before committing a transaction, ensuring the commit timestamp is ordered correctly relative to all other transactions globally. This enables **external consistency** (a form of linearizability) across a globally distributed database.

**Lamport timestamps**: Each event incremented; `max(local, received) + 1` on message receipt. Establishes total ordering that respects causality. But: doesn't tell you when two events are concurrent (you need vector clocks for that).

**Vector clocks**: `[counter_per_node]`. If one event's vector clock dominates another's in all dimensions, it causally precedes the other. If neither dominates, they are concurrent. Used in Dynamo-style systems for sibling detection.

### Process Pauses

A process can be paused for an arbitrary duration with no warning:
- JVM/CLR garbage collection (GC): stop-the-world GC pauses of seconds are possible
- VM hypervisor scheduling: VM preempted for another tenant
- OS paging / swapping: process accessing cold memory may wait for page fault
- Disk I/O: synchronous disk access blocks the process

**The split-brain scenario**:
```
T=0:  Node A is leader; holds a lock via ZooKeeper
T=1:  Node A experiences a GC pause (15 seconds)
T=5:  ZooKeeper session expires; Node B is elected new leader
T=16: GC pause ends; Node A resumes, still believes it is leader
T=16: Node A and Node B both believe they are leader → split-brain
```

**Fencing tokens**: Monotonically increasing token granted with each lock/lease. Every write to the guarded resource includes the token. Resource rejects writes with stale tokens (lower than the last seen).
```
T=0:  Node A granted lock with token=33
T=1:  Node A pauses (GC)
T=5:  Node B granted lock with token=34
T=10: Node B writes with token=34 → accepted
T=16: Node A resumes, writes with token=33 → rejected (stale token)
```

**FAANG interview application**: "In a distributed file store where only one node should own a shard at a time, leader election alone is insufficient. After electing a leader via Raft/ZooKeeper, I'd issue a fencing token (monotonically increasing epoch number) with the lease. All writes to the shard must include the current epoch. The storage layer rejects writes from stale epochs — this handles the GC pause/split-brain scenario where an old leader resumes after being replaced."

---

## Section I — Consistency and Consensus

### Consistency Models

| Model | Guarantee | Example Systems | Latency Implication | Availability During Partition |
|-------|-----------|-----------------|--------------------|-----------------------------|
| **Linearizability** (strong consistency) | All operations appear instantaneous on a single copy. After a write completes, all subsequent reads (anywhere) see the new value. | ZooKeeper (its own data), etcd, Google Spanner | High — writes must wait for all replicas to acknowledge | Unavailable if cannot form a quorum |
| **Sequential consistency** | All nodes see all operations in the same order; that order is consistent with each client's local order (but not real-time). | GPU caches pre-coherency | Medium | Unavailable in same conditions as linearizability |
| **Causal consistency** | Operations that are causally related are seen in the same causal order everywhere. Concurrent operations may be seen in different orders by different nodes. | MongoDB causal sessions, CockroachDB follower reads | Medium — only causally dependent ops must be ordered | Available: causally independent ops proceed freely |
| **Eventual consistency** | If no new writes are made, all replicas will eventually converge to the same value. No guarantee on when, or what intermediate states look like. | DynamoDB, Cassandra default | Lowest — writes acknowledged by one node | Fully available |

**Linearizability vs. Serializability — the most commonly confused pair**:

| | Linearizability | Serializability |
|-|-----------------|-----------------|
| Scope | Single object (key/register), single operation (read or write) | Multiple objects, multiple operations (a transaction) |
| Guarantee | Recency — reads always see the most recently committed write | Isolation — concurrent transactions appear to execute serially |
| What it's about | The order of individual reads and writes in real time | The ordering of entire transactions relative to each other |
| Example violation | Node A writes X=2; Node B reads X=1 immediately after (didn't see A's write yet) | Two concurrent transfers both see the same balance and both succeed, creating an invalid state |
| Example systems | ZooKeeper (linearizable reads/writes of its own keys) | PostgreSQL Serializable (SSI) |

A system can be serializable without being linearizable (PostgreSQL snapshot isolation — transactions are isolated but reads can be from a past snapshot, so a client can read stale data). A system can be linearizable without being serializable (a single-register compare-and-swap with no transaction batching).

### CAP Theorem — and Why PACELC Is More Useful

**Classic CAP** (Brewer, 2000): A distributed system can provide at most 2 of 3 properties: Consistency (linearizability), Availability (every request gets a response), Partition Tolerance (the system continues operating during a network partition).

**Kleppmann's critique**: Partition tolerance is not optional — partitions will happen. The real choice is: *what does the system do DURING a partition?*

**PACELC** (Abadi, 2012) — more precise:
```
During a (P)artition:
  Choose (A)vailability or (C)onsistency

(E)lse (during normal operation, no partition):
  Choose (L)atency or (C)onsistency
```

| System | Partition Behaviour | Normal Behaviour | Classification |
|--------|--------------------|-----------------| --------------|
| Cassandra (default) | Accept writes even if only 1 of N replicas reachable (AP) | Low latency, eventual consistency (EL) | PA/EL |
| DynamoDB (eventually consistent reads) | Available (AP) | Low latency (EL) | PA/EL |
| Google Spanner | Consistent (CP) — waits for quorum | Consistent (EC) — waits out TrueTime uncertainty | PC/EC |
| ZooKeeper | Consistent (CP) — rejects writes if no quorum | Consistent (EC) — linearizable reads | PC/EC |
| MySQL (read replicas) | Consistent for writes to leader (CP); reads from replicas are stale (PA) | Replication lag = latency vs consistency tradeoff | PC/EL |

**FAANG interview application**: "When asked 'is your system consistent?', I reframe using PACELC. During a partition, my user profile service (Cassandra) prioritizes availability — users can still update their profiles even if one DC is unreachable, with the risk of conflicting updates. Else (normal operation), I accept eventual consistency (EL) to serve reads from the nearest replica with single-digit millisecond latency. The payment confirmation service uses a different design: PC/EC — it's unavailable during a partition rather than risk inconsistent state."

---

### Consensus Algorithms

**What consensus provides**: A cluster of N nodes agrees on a single value, even if up to (N-1)/2 nodes crash (majority quorum). Once a value is decided, it is never changed.

**Why it's hard**: Impossibility of deterministic consensus in asynchronous networks with any faults (FLP impossibility result). Real systems handle this by using timeouts and randomization — they sacrifice guaranteed termination in pathological network conditions, but terminate in practice.

**Raft** (the one to know for interviews):

```
Roles: Leader, Follower, Candidate

Normal operation (leader elected):
  1. Client sends write to leader
  2. Leader appends entry to its log with term number
  3. Leader sends AppendEntries RPC to all followers
  4. Followers append to their log, respond with success
  5. When majority acknowledge, leader marks entry committed
  6. Leader applies to state machine, responds to client
  7. Next AppendEntries notifies followers of commit → they apply

Leader election (leader has failed):
  1. Follower receives no heartbeat within election timeout (150–300ms randomized)
  2. Follower increments term, transitions to Candidate, votes for itself
  3. Sends RequestVote RPC to all nodes
  4. Nodes vote yes if: (a) they haven't voted this term, AND (b) candidate's log is at least as up-to-date
  5. If Candidate receives votes from majority → becomes Leader
  6. Randomized timeouts reduce split-vote probability

Log matching property: if two logs have the same index + term for an entry,
  all previous entries are also identical.
```

**Systems using Raft**: etcd (Kubernetes uses etcd for all cluster state), CockroachDB (consensus for each range), TiKV (consensus for each region), Consul, Vault

**ZooKeeper and ZAB (ZooKeeper Atomic Broadcast)**:
- ZK provides: linearizable reads/writes of znodes, ephemeral nodes (auto-deleted when client session expires), watches (one-time notifications on znode change)
- Uses ZAB (similar to Raft) internally for consensus across ZK nodes
- **Ephemeral nodes for leader election**: leader creates `/election/leader` as an ephemeral node. Followers watch this node. If leader crashes, ZK session expires, node is deleted, followers are notified → elect new leader. Fencing token = ZK zxid (transaction ID).
- **Practical use**: Don't implement Raft yourself. Use ZooKeeper or etcd as your consensus backbone for leader election, distributed locks, configuration, service discovery.

**FAANG interview application**: "For a distributed job scheduler where exactly one coordinator must own the work queue at a time, I'd use ZooKeeper for leader election. The coordinator holds an ephemeral ZK node; all standby coordinators watch it. If the coordinator crashes, ZK's session expires, the node is deleted, a standby wins the re-election race within 100–500ms (ZK session timeout). Each acquired lock includes a ZK zxid as a fencing token — the job queue storage rejects requests from stale epoch coordinators."

---

## Section J — Batch Processing

### MapReduce Model

**Conceptual model** (originated from Google's 2004 paper):

```
Input data (HDFS files, partitioned)
    │
    ▼ Map phase (parallel, one mapper per input partition)
    mapper(key, value) → emit(intermediate_key, intermediate_value)
    │
    ▼ Shuffle + Sort (framework-handled)
    All intermediate_value's grouped by intermediate_key
    Sorted by intermediate_key within each reducer's input
    │
    ▼ Reduce phase (parallel, one reducer per key group)
    reducer(key, [values]) → emit(output_key, output_value)
    │
    ▼ Output (HDFS files)
```

**Fault tolerance**: If a mapper or reducer fails, the framework re-runs it on another node using the same input data (inputs are immutable HDFS files). Intermediate results materialized to HDFS between each MapReduce job — allows individual jobs to be retried independently. Cost: high I/O (HDFS write + HDFS read between every stage).

**Why MapReduce matters even if you use Spark**: The MapReduce mental model (partition data → compute locally → shuffle by key → aggregate) describes how any distributed computation works. Spark, Flink, and BigQuery all implement this model, just without materializing intermediate results to disk.

**MapReduce limitations**:
- Materialized intermediate state between jobs → high latency for multi-step pipelines (hours for complex workflows)
- No streaming — batch only
- Rigid two-phase model — complex DAGs require chaining multiple MapReduce jobs

### Dataflow Engines (Spark, Tez, Flink in batch mode)

**Key difference from MapReduce**: operators are a generalization of map and reduce — any function from any number of inputs to any number of outputs. The framework builds a DAG of operators and optimizes execution.

**Advantages**:
- Intermediate results pipelined in memory (not materialized to HDFS) when possible
- Operators can start processing as soon as any input partition is ready (pipelining)
- Optimizer can push predicates through the DAG (predicate pushdown, projection pruning)
- Same code runs on bounded datasets (batch) and unbounded datasets (streaming) in Flink

**Batch join strategies**:

| Strategy | Mechanism | Memory Requirement | Latency | Best For |
|----------|-----------|-------------------|---------|----------|
| Sort-merge join | Sort both inputs by join key; merge in a single pass | Spills to disk if needed | High (must sort both sides first) | Joins where both sides are large |
| Broadcast hash join | Build a hash table from the smaller side; broadcast to all partitions of larger side | Small side must fit in RAM (per node) | Low (no shuffle of large side) | One small, one large input (dimension table × fact table) |
| Partitioned hash join | Hash-partition both sides on join key; each partition joins locally | Each partition must fit in RAM | Medium | Both sides too large for broadcast; keys evenly distributed |

**FAANG interview application**: "For a batch pipeline computing weekly revenue attribution (joining 100GB of click events with 1GB of ad campaign metadata), I'd use a broadcast hash join in Spark. Campaign metadata fits in each executor's memory; I broadcast it rather than shuffling 100GB of click events. The join key is `campaign_id` — I partition clicks by campaign_id to colocate them with the campaign metadata. Runtime: ~15 minutes for a full week's data vs ~2 hours for a sort-merge join."

---

## Section K — Stream Processing

### Event Streams vs Batch

| Dimension | Batch Processing | Stream Processing |
|-----------|-----------------|-------------------|
| Dataset | Bounded (finite) | Unbounded (infinite) |
| Processing time | After data has landed (hours delay) | As data arrives (milliseconds to seconds) |
| Fault tolerance | Re-run from input files | Checkpoint state; replay from log |
| Output | Fully computed result at end of job | Continuously updated result |
| State management | Reduce phase handles grouping | Stateful operators with keyed state |
| Examples | Spark batch, Hadoop MapReduce | Apache Flink, Kafka Streams, Spark Structured Streaming |

### Message Brokers

| System | Delivery | Retention | Ordering | Consumer Model | Best For |
|--------|----------|-----------|----------|----------------|----------|
| RabbitMQ (AMQP) | At-most-once or at-least-once | Until consumed (deleted after ack) | Per-queue (FIFO) | Competing consumers: message delivered to one consumer per queue | Task queues, RPC, work distribution |
| Apache Kafka | At-least-once (or exactly-once with transactions) | Configurable retention (days to forever) | Per-partition | Log-based: each consumer group reads its own offset; message not deleted | Event sourcing, audit logs, fan-out, stream processing |
| Amazon Kinesis | At-least-once | 24h–365 days | Per-shard | Similar to Kafka | AWS-native streaming pipelines |
| Amazon SQS | At-least-once (standard) or exactly-once (FIFO) | Until consumed | FIFO (FIFO queue only) | Competing consumers | Decoupling microservices; async task processing |

**Log-based brokers (Kafka) — critical properties**:
- Messages appended to a log; consumer group tracks its own offset (position in log)
- Messages are NOT deleted after consumption — consumers can replay from any offset
- Multiple consumer groups can independently consume the same topic at different offsets
- Partitions enable parallelism: a topic with 100 partitions can be consumed by up to 100 consumers in a group simultaneously
- **Compacted topics**: retain only the latest value per key — behaves like a changelog / database snapshot. Used for: change data capture (CDC) from a source database, materializing the current state of a table as a Kafka topic.
- **Consumer group rebalancing**: when a consumer joins or leaves a group, partition assignments are rebalanced across remaining members. During rebalance, consumption pauses — minimize rebalances with longer session timeouts.

**FAANG interview application**: "For a notifications system that fans out to 8 downstream consumers (email, push, SMS, in-app, analytics, compliance, A/B testing, archival), I'd use Kafka with a single `user-events` topic. Each downstream system is its own consumer group — they each read at their own pace and can replay if a consumer falls behind or is deployed fresh. RabbitMQ would delete messages after first consumption — wrong model for fan-out to N consumers."

---

### Stream Processing Patterns

**Stream-table join** (stream enrichment):
```
Input stream:  click events (user_id, page_id, timestamp)
Reference table: user profiles (user_id, age, country, plan_tier)

For each click event:
  Look up user profile by user_id in local state (loaded from changelog topic)
  Emit enriched event: (user_id, page_id, timestamp, age, country, plan_tier)
```
The reference table is loaded into local state as a materialized view from a Kafka changelog topic (CDC from the user DB). No remote database lookups at stream processing time — O(1) local state access.

**Stream-stream join** (windowed join):
```
Stream A: ad impression events (ad_id, user_id, timestamp)
Stream B: conversion events (ad_id, user_id, timestamp)

For each impression event, buffer it for 30 minutes.
If a matching conversion event arrives within 30 minutes:
  Emit: (ad_id, user_id, impression_time, conversion_time, latency_ms)
If no conversion within 30 minutes:
  Emit: (ad_id, user_id, impression_time, NULL, NULL)  [not converted]
```
Both streams buffered in keyed state store. State size = number of unmatched events × 30 minute window × event size.

**Windowing types**:

| Window Type | Definition | Example | Use Case |
|-------------|-----------|---------|----------|
| Tumbling | Fixed size, non-overlapping | Every 5 minutes: [0–5), [5–10), [10–15) | Hourly totals, per-minute rate |
| Hopping | Fixed size, overlapping (window step < window size) | 5-min window every 1 min: [0–5), [1–6), [2–7) | Moving averages |
| Sliding | Continuous; triggered by each event within a time range of it | All clicks within 30s of each other | Session identification |
| Session | Variable size; grouped by inactivity gap | User activity with 30-min idle timeout | User session analytics |

**Event time vs processing time**:

| Time Concept | Definition | Problem |
|-------------|-----------|---------|
| Processing time | Time the event is processed by the stream processor | Easy to measure; doesn't reflect when the event actually occurred |
| Event time | Timestamp embedded in the event by the producer | Correct; but events arrive out of order (mobile apps offline, network delays) |

**Watermarks**: A watermark at time T is the stream processor's assertion that "all events with event_time < T have now been received." Events arriving after their watermark has passed are **late data**.

```
Events: [e1: t=100], [e3: t=102], [e2: t=101] ← out of order
Watermark with 5s max delay: declare watermark when we see max(event_time) - 5s

After processing e3 (t=102): watermark = 97
  → any event with event_time < 97 is late data

Late data handling options:
  1. Ignore late data (simple; some data loss)
  2. Allow lateness: reopen window when late data arrives, emit updated result
  3. Side output: route late data to a separate stream for separate handling
```

**FAANG interview application**: "For a real-time fraud detection system, I'd use Flink with event-time processing and a 15-minute sliding window. I join the transaction stream with the user behavior stream (stream-stream join with 15-minute window). I set watermarks with a 30-second allowed lateness to handle mobile SDK clock skew. Flink's stateful operators store unmatched events in RocksDB-backed state — durable across failures. On window close, a Flink sink writes suspicious patterns (>5 transactions from >3 geos in 15 min) to a Kafka topic consumed by the blocking service."

---

## Section L — The Future of Data Systems

### Lambda Architecture (now largely legacy)

```
All writes
    ├──→ Batch layer: store all events in HDFS; reprocess periodically → accurate batch views
    └──→ Speed layer: stream processor → approximate real-time views

Serving layer: merge batch views + speed views for queries
```

**Problem**: The same logic must be implemented twice — once for batch (Spark), once for streaming (Kafka Streams / Flink). These two implementations tend to diverge over time, producing different results for the same data. Operational complexity doubles.

### Kappa Architecture

```
All writes → Kafka (the log; retained indefinitely)
    │
    └──→ Stream processor (Flink) processes both:
           - Real-time stream: consumes recent events as they arrive
           - Historical replay: restart job from offset=0 to reprocess all history
```

**Key insight**: If you can replay history through the stream processor at higher-than-real-time speed (by reading Kafka at max throughput), you don't need a separate batch layer. Same code, same logic, two execution modes.

**Requirements for Kappa**: Log-based storage with sufficient retention (Kafka with weeks/months of retention); stream processor that can checkpoint state and resume from any offset.

### Unbundling the Database

Kleppmann's architectural thesis: Traditional databases bundle many concerns — storage engine, query optimizer, transaction manager, replication, caching, indexing. Modern distributed systems unbundle these:

```
Kafka          → durable log (WAL as a service; the source of truth)
Flink          → stream processing (the query engine / materialized view maintainer)
Redis          → distributed cache (the buffer pool)
Elasticsearch  → inverted index (the full-text search view)
PostgreSQL     → relational store (OLTP transactions)
Druid / ClickHouse → columnar OLAP store (the analytics view)
```

**The integration challenge**: When you split these concerns across systems, you need to keep them consistent. Techniques:
- **CDC (Change Data Capture)**: capture every write to PostgreSQL as a stream (via WAL replication) → publish to Kafka → downstream consumers (Elasticsearch, Redis, Druid) update their views
- **Dual write**: write to two systems in the same application request — fragile (partial failure leaves systems inconsistent)
- **Event sourcing**: application writes events (not state mutations) to Kafka as the primary store; derived state is computed by consumers — Kafka is the source of truth

### Derived Data Systems

**Source of truth** (system of record): where data is first written; the authoritative store.

**Derived data**: computed from the source of truth. Can always be rebuilt from the source if lost.

```
Source of truth: Kafka (raw events) or PostgreSQL (user table)
Derived data:
  → Elasticsearch index (search view — rebuilt by replaying CDC stream)
  → Redis cache (hot user profiles — rebuilt by replaying user table CDC)
  → Druid rollup (analytics — rebuilt by replaying event stream)
  → ML feature store (pre-computed features — rebuilt by batch job over event history)
```

**Design principle**: Make derivation explicit. When you know which systems are derived, you can rebuild them. When you don't, you treat them as authoritative and resist changes out of fear.

**FAANG interview application**: "For a product search system at Amazon scale, the source of truth for product catalog is a PostgreSQL database. I derive: (1) Elasticsearch index for full-text search — continuously updated via CDC → Kafka → Elasticsearch connector; (2) Redis cache for product details API — populated via CDC, TTL 10 minutes; (3) BigQuery table for pricing analytics — hourly batch from Kafka. If Elasticsearch is corrupted, I replay the CDC stream from the beginning to rebuild the index. No data is lost because the source of truth (PostgreSQL + Kafka retention) is intact."

---

## Section M — Key Trade-offs (Master Reference Table)

| Trade-off | Kleppmann's Position | Key Nuance | FAANG Interview Context |
|-----------|---------------------|------------|------------------------|
| **B-Tree vs LSM-Tree** | Choose by workload: B-Tree for read-heavy, LSM-Tree for write-heavy | Measure write amplification and space amplification for your specific workload before deciding | "Cassandra for 500K writes/sec metrics ingestion; PostgreSQL for complex joins and mixed OLTP" |
| **Strong vs eventual consistency** | Always choose based on business requirements, not technology defaults | Most consistency bugs in production are isolation level bugs (write skew, lost update), not eventual consistency bugs | "Bank ledger: strong (Serializable SSI in PostgreSQL). Product views count: eventual (Cassandra with W=1)" |
| **Relational vs document vs graph** | Access pattern determines data model — never choose by brand or popularity | Joins are cheap in a normalized relational DB; joins across partitions are scatter-gather operations | "Résumé data: document (self-contained). Order + inventory: relational (FK integrity). Fraud ring detection: graph" |
| **Read committed vs snapshot isolation** | Snapshot isolation (MVCC) should be the default; few workloads need stronger guarantees | The gap between snapshot isolation and serializable is write skew — relatively rare in non-financial systems | "Default to PostgreSQL's Read Committed; upgrade to Repeatable Read for booking systems; Serializable for financial ledgers" |
| **MapReduce vs Dataflow** | Dataflow (Spark, Flink) supersedes MapReduce for all new workloads | MapReduce mental model (partition → compute local → shuffle → aggregate) is still the right abstraction for reasoning | "Spark for batch ETL; Flink for stream processing; BigQuery for ad-hoc OLAP — all implement the same dataflow DAG model" |
| **Log-based vs traditional broker** | Log-based (Kafka) when you need replay, fan-out, or audit trail | Traditional queue (RabbitMQ, SQS) is simpler when each message is consumed by exactly one consumer and must be deleted after processing | "Kafka for event sourcing, CDC, multi-consumer fan-out. SQS for decoupled microservice task queues." |
| **Batch vs stream processing** | Streaming for latency; batch for throughput, correctness, and complex joins | Flink unifies both — same code runs on bounded (batch) and unbounded (stream) datasets | "Design the stream processor first using Flink. For historical replay, restart from Kafka offset=0 — no separate batch layer needed" |
| **Quorum (N, W, R) configuration** | W + R > N is necessary but not sufficient for linearizability if sloppy quorums are enabled | Higher W and R → stronger consistency but higher latency and lower availability | "N=3, W=2, R=2 for normal ops. W=3, R=1 for the payment write path (no data loss tolerated)" |
| **LWW vs CRDT vs custom merge for conflict resolution** | LWW is the easiest and the most dangerous (silent data loss on clock skew). CRDTs where the data structure permits. Custom merge for everything else. | LWW with server-assigned timestamps (not client) is safer — server timestamps are more reliable | "Shopping cart: CRDT (OR-Set). User profile: LWW with server timestamp. Collaborative document: CRDT (sequence CRDT like LSEQ)" |
| **Event time vs processing time** | Always use event time for correctness in stream processing | Processing time is only acceptable when you control all producers and latency is bounded and small | "Use event time with watermarks in Flink. Processing time is acceptable only for internal metrics pipelines with sub-second latency" |

---

## Section N — Chapter-by-Chapter Reference

### Chapter 1: Reliable, Scalable, and Maintainable Applications
- **Core concept**: Reliability = fault tolerance; Scalability = handling growth; Maintainability = operability + simplicity + evolvability
- **Key detail**: Measure load parameters (QPS, P99 latency, fan-out per write) before designing. Twitter's hybrid timeline (fan-out on write for normal users, merge on read for celebrities) is the canonical example of load-parameter-driven design.
- **Interview takeaway**: Before proposing any architecture, state your load assumptions. "I'm assuming 10K writes/sec, 100K reads/sec, read:write ratio 10:1, power-law distribution on user follower count."

### Chapter 2: Data Models and Query Languages
- **Core concept**: Data model is the primary abstraction — it determines what's expressible and what's efficient
- **Key detail**: Relational (joins, normalized), Document (data locality, schema flexibility), Graph (relationship traversal). The "right" model is determined by your access patterns, not the technology's reputation.
- **Interview takeaway**: "I always start by mapping the entity relationships and the primary access patterns — that determines the data model, which determines the storage technology."

### Chapter 3: Storage and Retrieval
- **Core concept**: B-Trees (read-optimized, in-place updates, WAL) vs LSM-Trees (write-optimized, append-only, compaction)
- **Key detail**: Bloom filters (probabilistic, eliminates unnecessary disk reads), compaction strategies (size-tiered vs leveled), write amplification, column-oriented storage for OLAP
- **Interview takeaway**: "Cassandra uses LSM-Trees — I can justify this choice for write-heavy workloads by citing sequential write performance and the compaction strategy. PostgreSQL uses B-Trees — I can justify this for read-heavy OLTP by citing O(log n) point reads and in-place updates."

### Chapter 4: Encoding and Evolution
- **Core concept**: Services must evolve independently; backward and forward compatibility are the constraints
- **Key detail**: Protobuf uses numeric field tags (renaming safe, reusing tags unsafe); Avro uses field names + schema registry (renaming unsafe without default value); JSON ignores unknown fields (partial forward compatibility)
- **Interview takeaway**: "For any inter-service API, I define the compatibility contract: does old code need to read new messages (forward compat)? Does new code need to read old messages (backward compat)? Protobuf satisfies both with optional fields."

### Chapter 5: Replication
- **Core concept**: Single-leader (simple, SPOF), multi-leader (conflict-prone, multi-DC resilience), leaderless (quorum-based, no SPOF)
- **Key detail**: Replication lag causes three anomalies (read-your-writes, monotonic reads, consistent prefix reads); leaderless uses W+R>N quorum; sloppy quorum trades consistency for availability
- **Interview takeaway**: "For a multi-region user profile service, I'd use single-leader with read replicas and session affinity to prevent monotonic reads violations. For a shopping cart (merge-friendly), leaderless Dynamo-style with CRDT conflict resolution."

### Chapter 6: Partitioning
- **Core concept**: Key-range (efficient range queries, hotspot risk) vs hash (even distribution, range scatter-gather) vs consistent hashing (efficient rebalancing)
- **Key detail**: Hotspot mitigation via key suffix randomization; local vs global secondary indexes; ZooKeeper-based partition routing
- **Interview takeaway**: "I shard by `user_id` using consistent hashing with 256 vnodes per node. This gives even key distribution and allows capacity addition without full resharding."

### Chapter 7: Transactions
- **Core concept**: ACID precisely defined; isolation levels (read committed → serializable); MVCC; serializability via SSI
- **Key detail**: The 5-level × 5-anomaly isolation table; write skew is the anomaly that only Serializable prevents; SSI is the modern solution (PostgreSQL, CockroachDB)
- **Interview takeaway**: "Most 'consistency bugs' in production are actually isolation level bugs — developers assumed stronger guarantees than the database provides by default. Know your DB's default isolation level (PostgreSQL: Read Committed; MySQL: Repeatable Read) and what anomalies it allows."

### Chapter 8: The Trouble with Distributed Systems
- **Core concept**: Partial failures, unreliable networks, unreliable clocks, and process pauses make distributed systems fundamentally different from single-node systems
- **Key detail**: Fencing tokens prevent split-brain; wall clocks are unreliable for ordering events (use logical clocks or vector clocks); GC pauses can last seconds
- **Interview takeaway**: "A timeout is all you have to distinguish a slow node from a crashed node. Design protocols to handle both cases identically — and use fencing tokens to make stale nodes' writes harmless."

### Chapter 9: Consistency and Consensus
- **Core concept**: Consistency models hierarchy (linearizable → sequential → causal → eventual); PACELC > CAP; Raft for consensus; ZooKeeper for leader election
- **Key detail**: Linearizability ≠ Serializability (different scopes); FLP impossibility means deterministic consensus is impossible — real systems use timeouts + randomization; ZAB ≈ Raft
- **Interview takeaway**: "Never implement Raft yourself. Use etcd or ZooKeeper for leader election and distributed locks. Understand what guarantees they provide (linearizable writes, eventually consistent reads by default) and design around them."

### Chapter 10: Batch Processing
- **Core concept**: MapReduce mental model (map → shuffle → reduce); Dataflow engines (Spark, Flink batch) supersede MapReduce with DAG-based pipelined execution
- **Key detail**: Three join strategies (sort-merge, broadcast hash, partitioned hash); fault tolerance via immutable inputs + reprocessing; column-oriented formats (Parquet, ORC) for batch efficiency
- **Interview takeaway**: "I frame all batch computations as: partition the input by key → compute locally → shuffle to reduce by key → aggregate. The dataflow engine optimizes the physical plan. Broadcast hash join for dimension table × fact table joins."

### Chapter 11: Stream Processing
- **Core concept**: Unbounded event streams; log-based brokers (Kafka); stream-table joins, stream-stream joins, windowing; event time vs processing time; watermarks
- **Key detail**: Kafka consumer groups; compacted topics as changelogs; windowing types (tumbling/hopping/sliding/session); watermarks with allowed lateness
- **Interview takeaway**: "For any real-time pipeline, I design with event time and watermarks. I use Flink's stateful operators (keyed state, RocksDB backend) for joins and windowed aggregations. Kafka's log retention enables replay without a separate batch layer."

### Chapter 12: The Future of Data Systems
- **Core concept**: Lambda architecture (two code paths, batch + stream) → Kappa (stream only, replay for batch); unbundling the database into specialized components; derived data from a source of truth
- **Key detail**: CDC + Kafka as the integration backbone; derived data can always be rebuilt; event sourcing (events as the source of truth, state as derived)
- **Interview takeaway**: "I design every system with explicit source-of-truth vs derived-data separation. Derived systems (Elasticsearch, Redis, Druid) can be rebuilt by replaying the source stream. This makes the architecture resilient and evolvable — add a new derived view without migrating the source."

---

## Section O — FAANG Interview Cheat Sheet

### 5 Phrases That Signal DDIA-Level Depth

Say these in system design interviews to signal principal engineer calibration:

1. **"The choice between B-Tree and LSM-Tree is a choice between read amplification and write amplification — I'd profile the workload's read:write ratio and measure write amplification before deciding."**

2. **"Snapshot Isolation (MVCC) prevents dirty reads, non-repeatable reads, and phantom reads, but it does not prevent write skew — for that I need Serializable isolation, which PostgreSQL implements via SSI."**

3. **"Linearizability and serializability are often conflated — linearizability is a recency guarantee on a single register (every read sees the most recent write); serializability is a transaction isolation guarantee across multiple objects. You can have one without the other."**

4. **"In a Dynamo-style system with N=3, W=2, R=2, W + R > N guarantees reading at least one up-to-date replica — but this does not guarantee linearizability if sloppy quorums are enabled, because writes may be accepted by hinted nodes outside the normal preference list."**

5. **"The choice between event time and processing time in stream processing determines correctness — processing time is only acceptable when you control all producers and message latency is bounded and small. I'd use event time with watermarks and allowed lateness for any production pipeline."**

### Using DDIA Concepts in HLD Answers

**Database selection (OLTP context)**:
```
Step 1: Map entity relationships
  - Flat document? → Document DB (DynamoDB, MongoDB)
  - Complex joins / multi-table transactions? → Relational (PostgreSQL)
  - Graph traversal? → Graph DB (Neptune, Neo4j)

Step 2: Identify consistency requirement
  - Strong (financial)? → PostgreSQL Serializable (SSI)
  - Eventual acceptable? → Cassandra / DynamoDB

Step 3: Identify write:read ratio and access pattern
  - Write-heavy (>100K writes/sec)? → LSM-Tree (Cassandra, RocksDB)
  - Read-heavy with complex queries? → B-Tree (PostgreSQL)
  - Analytics (aggregations on billions of rows)? → Column-oriented (BigQuery, Redshift)
```

**Replication design**:
```
Step 1: Identify write concurrency requirement
  - Single DC, single team writes → single-leader
  - Multi-DC or multi-device offline writes → multi-leader or leaderless
  - High-availability, merge-friendly data → leaderless (Dynamo-style)

Step 2: Identify consistency requirement during lag
  - User must read their own writes → RYW fix (route to leader post-write)
  - No monotonic reads violations → session affinity to same replica

Step 3: Configure quorum (for leaderless)
  - N=3, W=2, R=2 → standard balanced
  - Increase W for critical write paths (payment)
  - Increase R for audit reads (must be up-to-date)
```

**Stream processing pipeline design**:
```
Step 1: Identify time semantics
  - Mobile or IoT sources → event time (out-of-order arrivals)
  - Internal microservices, bounded latency → processing time acceptable

Step 2: Identify join type
  - Enrich event with reference data → stream-table join (local state from CDC)
  - Correlate two event streams in time → stream-stream join (windowed)

Step 3: Set watermark + allowed lateness
  - Watermark = max(event_time) - max_expected_delay
  - Allowed lateness = how long to keep window open after watermark passes
```

### Connecting DDIA to Leadership Rounds

DDIA concepts appear in leadership behavioral questions at PE level:

- **"Describe a time you drove a data architecture decision that impacted multiple teams."** → Storage engine selection (LSM vs B-Tree), data model migration (relational → document), consistency model decision
- **"How did you handle a production incident caused by a database issue?"** → Replication lag causing RYW violations, write skew causing double-spend, partition imbalance causing hotspots
- **"How did you help your team understand a complex distributed systems concept?"** → Teaching isolation levels, explaining PACELC vs CAP, introducing event-time semantics to a team new to stream processing

---

## Section G — Connections to This Repository

| Topic | Related Folder | Specific Connection |
|-------|---------------|---------------------|
| Storage engine selection (LSM vs B-Tree) | [HLD/trade-offs/](../../HLD/trade-offs/) | Create dedicated trade-off document for DB storage engine selection |
| Consistency models (PACELC) | [Architecture/distributed-systems/](../../Architecture/distributed-systems/) | Core reference for any CAP/consistency discussion |
| Replication + partitioning | [HLD/designs/](../../HLD/designs/) | Every HLD involving a database should reference Chapters 5–6 |
| Transaction isolation levels | [Architecture/decisions/](../../Architecture/decisions/) | ADR template for "choosing isolation level" decisions |
| Kafka architecture | [HLD/designs/](../../HLD/designs/) | Kafka-based system designs (event sourcing, CDC, stream processing) |
| Stream processing (Flink) | [AI/ml-systems/](../../AI/ml-systems/) | ML feature store design, real-time model serving pipelines |
| Column-oriented storage (OLAP) | [CloudArchitecture/aws/](../../CloudArchitecture/aws/) | Redshift vs BigQuery vs Snowflake selection |
| CDC + event sourcing | [Architecture/microservices/](../../Architecture/microservices/) | Data consistency across microservices boundaries |

**Complementary Books**:
- *The Art of Scalability* (Abbott & Fisher) — organizational and process context for the technology decisions DDIA describes; Scale Cube complements DDIA's replication/partitioning model
- *Understanding Distributed Systems* (Vitillo) — lighter treatment of same topics; good companion for conceptual review
- *Database Internals* (Petrov) — deeper dive into storage engine internals (B-Trees, LSM-Trees at the implementation level)
- *Kafka: The Definitive Guide* (Narkhede, Shapira, Palino) — implementation depth for Chapter 11 topics

---

## Section P — Observability & Monitoring

> "Observability is not a feature you bolt on after the fact. It is a property of the system you build from the beginning. A system is observable if you can understand its internal state from its external outputs alone."
> — Charity Majors, Liz Fong-Jones, George Miranda — *Observability Engineering* (O'Reilly, 2022)

---

### Why Observability Matters at Principal Engineer Level

Kleppmann defines **operability** in Chapter 1 as one of the three pillars of maintainability — and operability is impossible without observability. At FAANG PE level, you are expected to design systems that are debuggable in production by someone who was not the original author, under time pressure, with partial information. Observability is the engineering discipline that makes this possible.

The *Observability Engineering* book by Charity Majors (CEO, Honeycomb), Liz Fong-Jones (Honeycomb staff engineer), and George Miranda builds the complete thesis: **monitoring tells you that something is wrong; observability tells you why.**

---

### Core Thesis: Observability vs Monitoring

| Dimension | Monitoring | Observability |
|-----------|------------|---------------|
| **Mental model** | Ask known questions about known-failure modes | Ask arbitrary questions about any system state |
| **Data unit** | Pre-aggregated metrics (time series, counters, gauges) | Raw structured events (one per request, one per unit of work) |
| **Question type** | "Is the error rate above 5%?" (known question) | "Why are requests from Safari on iOS 17 to /checkout failing for users with >10 items in their cart?" (unknown question) |
| **Failure mode coverage** | Detects known-unknowns | Reveals unknown-unknowns |
| **When it's useful** | Alerting when thresholds are breached | Debugging after an alert fires |
| **Primary tool** | Dashboards, alert rules, PagerDuty | Distributed tracing, structured logs, high-cardinality query |
| **Data shape** | `error_rate{service="checkout"} = 0.07` | `{user_id: 123, cart_items: 12, browser: "Safari", os: "iOS 17", error: "timeout", duration_ms: 4200}` |

**The key insight from Majors/Fong-Jones**: Pre-aggregation destroys the information you need to debug. A metric that says "P99 latency = 4.2s" cannot tell you *which users*, *which requests*, or *which code paths* are slow. A structured event per request can.

---

### The Three Pillars — and Why the Framing Is Incomplete

The industry often calls logs, metrics, and traces "the three pillars of observability." Majors/Fong-Jones argue this framing is **misleading**:

- **Logs + Metrics + Traces** are *telemetry signal types*, not a definition of observability
- Observability is achieved when you can ask arbitrary questions of your system without shipping new code
- The *combination* of these signals with high-cardinality querying is what matters, not each signal in isolation

#### Logs

**Traditional (unstructured) logs**:
```
2024-01-15 14:23:01 ERROR PaymentService - Payment failed for order 12345: timeout after 3000ms
```
- Human-readable; machine-unfilterable at high volume
- No correlation across services without manual parsing
- Cannot query: "show me all payment failures for users in Germany with cart value > $500"

**Structured logs (the right way)**:
```json
{
  "timestamp": "2024-01-15T14:23:01.234Z",
  "level": "ERROR",
  "service": "payment-service",
  "trace_id": "abc123",
  "span_id": "def456",
  "user_id": "user-789",
  "order_id": "order-12345",
  "amount_usd": 847.50,
  "user_country": "DE",
  "payment_provider": "stripe",
  "error_type": "timeout",
  "duration_ms": 3042,
  "cart_item_count": 8,
  "retry_attempt": 2
}
```
- Machine-queryable across any field
- Correlation via `trace_id` across services
- "Show me all payment timeouts where `amount_usd > 500` and `user_country = DE`" — answerable instantly

**Principal engineer rule**: Every log line should be a structured event. Every event should carry: `trace_id`, `service`, `timestamp`, `duration_ms`, and the business context fields relevant to the work unit (user_id, order_id, etc.).

#### Metrics

**What metrics are good for**:
- Alerting on rate/error/saturation (USE method)
- Capacity planning — trends over days/weeks
- SLO burn rate tracking
- High-level business dashboards (revenue per minute, orders per second)

**The four golden signals** (Google SRE book):

| Signal | Description | Example |
|--------|-------------|---------|
| **Latency** | Time to serve a request (distinguish successful vs error latency separately) | P50/P95/P99/P999 request latency per endpoint |
| **Traffic** | Rate of requests (demand on the system) | Requests per second, messages per second, active connections |
| **Errors** | Rate of failed requests (distinguish 4xx user errors from 5xx system errors) | Error rate per endpoint, per user cohort |
| **Saturation** | How "full" the service is (utilization of constrained resources) | CPU %, memory %, queue depth, connection pool utilization |

**USE Method** (Brendan Gregg) for infrastructure resources:
- **Utilization**: What fraction of time is the resource busy?
- **Saturation**: How much work is queued waiting for the resource?
- **Errors**: Are requests to the resource failing?

**RED Method** for services:
- **Rate**: requests per second
- **Errors**: errors per second
- **Duration**: latency distribution

**Histogram vs gauge vs counter**:

| Type | Description | When to Use |
|------|-------------|-------------|
| Counter | Monotonically increasing value; reset on restart | Request count, error count, bytes sent |
| Gauge | Current value; can go up or down | Queue depth, active connections, memory in use |
| Histogram | Samples bucketed into configurable ranges; enables P50/P95/P99 computation | Request latency, payload sizes |
| Summary | Pre-computed percentiles (client-side); cannot aggregate across instances | Avoid — use histograms for server-side aggregation |

**Why histograms over summaries**: Histograms are aggregatable across instances and across time — you can compute P99 across a fleet of 100 pods. Summaries compute percentiles on each instance and cannot be meaningfully averaged.

#### Distributed Tracing

The most powerful observability tool for microservices. A **trace** is a directed acyclic graph of **spans** — each span represents one unit of work (one RPC call, one database query, one cache lookup) within a request that crosses service boundaries.

```
Trace: user clicks "Place Order" (total duration: 847ms)
│
├── Span: API Gateway (12ms)
│
├── Span: OrderService.createOrder (832ms) ← root span
│   ├── Span: InventoryService.checkStock (45ms)
│   │   └── Span: Redis.GET inventory:item:xyz (3ms)
│   │
│   ├── Span: PaymentService.charge (780ms) ← THIS IS SLOW
│   │   ├── Span: PostgreSQL.SELECT payment_methods (8ms)
│   │   ├── Span: Stripe API call (762ms) ← ACTUAL BOTTLENECK
│   │   └── Span: PostgreSQL.INSERT transaction_log (9ms)
│   │
│   └── Span: NotificationService.sendConfirmation (async, 0ms latency to caller)
```

**What tracing answers that metrics cannot**:
- "The P99 latency for `/checkout` is 4s — which service/call is the bottleneck?"
- "This user's request was slow — exactly what happened, in what sequence, for how long?"
- "After my deploy, which downstream service started adding 200ms to each request?"

**W3C TraceContext standard** — propagation format:
```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             version  trace-id (128-bit)              parent-span-id  flags
```
Every service passes this header downstream, creating the causal chain.

**Sampling strategies**:

| Strategy | Mechanism | Pros | Cons |
|----------|-----------|------|------|
| Head-based (random %) | Decision made at trace entry point; propagated downstream | Simple; low overhead | Rare slow requests may be unsampled (P999 events) |
| Tail-based | Buffer all spans; decide to keep/drop after root span completes (knowing total duration) | Can ensure slow/erroneous traces are kept | High memory + complexity; requires trace aggregation before sampling decision |
| Exemplar-based | Keep one trace per histogram bucket (one P99 trace, one P99.9 trace) | Efficient; keeps representative samples | Implementation complexity |

**FAANG interview application**: "For a checkout service handling 50K RPS, I'd instrument every request with OpenTelemetry, propagate W3C TraceContext across all 8 downstream services, and store traces in Jaeger or Honeycomb. I'd use tail-based sampling at 10% for normal requests but 100% for requests > 1s or with any error — ensuring slow and failed traces are always captured for analysis."

---

### High-Cardinality Observability — The Majors/Fong-Jones Core Thesis

**High cardinality** = many distinct values for a field (user_id has millions of distinct values; country has 195).

Traditional monitoring systems (Prometheus, Datadog metrics) **cannot query high-cardinality fields** — storing a time series per user_id would produce millions of time series and OOM the metrics database.

**Why this matters**: The bugs that matter most are *specific* — they affect a subset of users, a subset of endpoints, a combination of conditions. Pre-aggregated metrics collapse the dimensions that make these bugs debuggable.

**The Honeycomb model**: Store structured events (one per request) with arbitrary fields. Query them with GROUP BY on any combination of fields, even high-cardinality ones, at query time. The computation is deferred to read time rather than write time.

```
Query: "What is the P99 latency for requests to /checkout where cart_item_count > 10,
        broken down by payment_provider, over the last 30 minutes?"

Traditional metrics: Cannot answer — no time series for cart_item_count + payment_provider combination.
High-cardinality events: Scan raw events for the time window, filter, group, compute — answerable in seconds.
```

**The tradeoff**: High-cardinality event storage is expensive at scale. Tail-based sampling reduces cost while preserving the "interesting" events (errors, slow requests).

---

### SLOs, SLIs, and Error Budgets

From Google's SRE book, operationalized by *Observability Engineering*:

**SLI (Service Level Indicator)**: A quantitative measure of a service behavior.
- Must be measurable from the user's perspective
- Examples: success rate of HTTP requests, P99 latency, data freshness

**SLO (Service Level Objective)**: A target value for an SLI over a rolling time window.
- "99.9% of checkout requests complete successfully over a 30-day rolling window"
- "P99 latency for checkout < 2s, measured over a 7-day window"
- Do NOT set SLOs without measuring your actual baseline first

**Error Budget**: `1 - SLO target` = the allowed downtime/error budget.
- 99.9% SLO → 0.1% error budget → 43.8 minutes/month downtime allowed
- 99.99% SLO → 0.01% error budget → 4.38 minutes/month
- 99.999% SLO → 0.001% error budget → 26 seconds/month

**Error budget policy** (the key to SLO culture):

| Budget State | Action |
|-------------|--------|
| Budget > 50% remaining | Deploy freely; invest in features |
| Budget 10–50% remaining | Increase caution on deploys; prioritize reliability work |
| Budget < 10% remaining | Freeze non-critical deploys; all hands on reliability |
| Budget exhausted | Incident; halt all changes until budget replenishes |

**Burn rate alerting** — alert on rate of budget consumption, not the threshold itself:

```
Error budget: 0.1% per 30 days = 43.8 minutes/month

Burn rate = actual error rate / SLO error rate

If burn rate = 1×:    consuming budget at exactly the allowed rate
If burn rate = 14.4×: will exhaust 30-day budget in 2 hours → page immediately
If burn rate = 6×:    will exhaust 30-day budget in 5 days → ticket + team alert

Multi-window alerting (Google's recommendation):
  Alert when burn rate is high over BOTH a long window (1h) and a short window (5min)
  → Reduces false positives from transient spikes
  → Long window: evidence of sustained problem; short window: still actively burning
```

**FAANG interview application**: "I'd define SLOs from the user journey, not from service internals. For a payment system: (1) checkout success rate ≥ 99.9% over 30 days, (2) checkout P99 latency < 3s over 7 days. I'd alert on error budget burn rate — if we're consuming the monthly budget at 14.4× the normal rate, that pages the on-call immediately. I'd store the SLI data in Prometheus, compute burn rate in Grafana, and automate budget freeze enforcement in our deploy pipeline."

---

### Distributed Tracing — Deep Dive

#### OpenTelemetry (OTel) — The Standard

OpenTelemetry is the CNCF standard for telemetry instrumentation. It provides:
- **API**: language-independent interfaces for spans, metrics, logs
- **SDK**: language-specific implementations (Java, Go, Python, Node.js, Rust, etc.)
- **Collector**: a vendor-neutral agent that receives, processes, and exports telemetry

```
Application code
    │ OTel SDK (auto-instrumentation + manual spans)
    ▼
OTel Collector (deployed as sidecar or daemonset)
    │ OTLP (OpenTelemetry Protocol)
    ▼
Backend: Jaeger / Honeycomb / Tempo / Datadog / New Relic
```

**Auto-instrumentation**: OTel agents automatically instrument HTTP frameworks, database clients, message brokers, gRPC — zero code changes required to get basic traces. Manual instrumentation adds business context (user_id, order_id, feature flags).

**Semantic conventions**: OTel defines standard attribute names — `http.method`, `db.system`, `messaging.system`, `rpc.service` — ensuring cross-service trace correlation works without per-service configuration.

#### Trace Correlation in Logs

Every log line should embed the current trace_id and span_id, enabling correlation between logs and traces:

```python
# Correct: inject trace context into every log line
import logging
from opentelemetry import trace

logger = logging.getLogger(__name__)

def process_order(order_id: str):
    span = trace.get_current_span()
    ctx = span.get_span_context()
    logger.info("Processing order", extra={
        "trace_id": format(ctx.trace_id, "032x"),
        "span_id": format(ctx.span_id, "016x"),
        "order_id": order_id,
    })
```

In your log aggregation tool (Loki, Splunk, CloudWatch Logs Insights), you can then click a trace_id to jump to the full trace in Jaeger, or click a log line in Jaeger to see the structured logs for that span.

#### Exemplars

A Prometheus exemplar is a specific trace_id attached to a histogram bucket. When you look at a P99 spike in Grafana, you can click the exemplar to jump directly to the trace that caused that P99 — no manual correlation.

```
# Prometheus histogram with exemplar
http_request_duration_seconds_bucket{le="4.0"} 12345 # {trace_id="abc123"} 3.84 1705320201
```

---

### On-Call Process — Engineering Operations

#### Incident Severity Levels

| Severity | Definition | Response Time | Example |
|----------|-----------|---------------|---------|
| **SEV-0** / P0 | Complete service outage; zero users can use core functionality | Immediate; all hands | Checkout is down; all payments failing; authentication unavailable |
| **SEV-1** / P1 | Major functionality degraded; >20% of users impacted or SLO exhausted | < 5 minutes (paged immediately) | P99 latency > 10s for checkout; 5% error rate on payment |
| **SEV-2** / P2 | Partial functionality degraded; < 20% of users impacted | < 30 minutes (paged) | Slow recommendations; email notifications delayed > 10 minutes |
| **SEV-3** / P3 | Minor issue; workaround available; no SLO impact | Business hours | Non-critical dashboard broken; flaky test; deprecated endpoint still called |
| **SEV-4** | Cosmetic / informational | Next sprint | Typo in error message; outdated documentation |

#### Incident Response Roles

| Role | Responsibility | Anti-pattern |
|------|---------------|-------------|
| **Incident Commander (IC)** | Owns the incident; coordinates response; communicates to stakeholders; declares resolution | IC doing their own technical investigation (context switch kills coordination) |
| **Technical Lead (TL)** | Drives the technical investigation; proposes and executes mitigations | TL spending time on status updates (IC's job) |
| **Comms Lead** | Writes status page updates; communicates to customers/stakeholders; manages internal Slack channel | Flooding the incident channel with questions instead of updates |
| **Scribe** | Documents the timeline in real time; records hypotheses, actions taken, outcomes | Not happening → post-mortem reconstruction is painful and incomplete |

**FAANG on-call expectation**: Engineers rotate on-call. At PE level, you are the escalation path when the primary on-call cannot resolve the incident. You are also expected to drive the process improvements that reduce incident frequency and severity.

#### The Incident Response Playbook

**Step 1: Triage (0–5 minutes)**
```
1. Acknowledge the alert — stops further escalation
2. Assess severity: how many users? which functionality? SLO burn rate?
3. Declare incident channel: #inc-YYYYMMDD-brief-description
4. Assign IC, TL, Comms
5. Post initial status page update (even if just "investigating")
```

**Step 2: Investigate (5–30 minutes)**
```
Investigation order of operations:
  1. What changed? (recent deploys, config changes, infra changes, traffic spikes)
     → Check deploy log, feature flag changes, cron jobs that ran recently
  2. What are the symptoms? (which endpoints, which users, which regions)
     → Error rate dashboards, distributed traces, structured logs
  3. Correlate with infrastructure signals
     → USE method on affected services (CPU, memory, saturation)
     → Dependency health checks (database, cache, external APIs)
  4. Form and test hypotheses
     → "Hypothesis: new deploy at 14:23 introduced a query regression"
     → Check traces for the new code path vs old code path
```

**Step 3: Mitigate (as fast as possible)**
```
Mitigation hierarchy (fastest to implement):
  1. Rollback: revert to last known-good deploy (< 5 min if CI/CD is mature)
  2. Feature flag off: disable the affected feature without code change (< 1 min)
  3. Traffic shift: route traffic away from affected region/instance
  4. Circuit breaker: enable rate limiting or graceful degradation on affected dependency
  5. Scale up: add capacity if the issue is resource saturation
  6. Hotfix: fix and deploy new code (30+ min if tests must pass)

Principle: MTTR (Mean Time to Restore) is more important than root cause understanding.
Restore first. Understand later. Production is not the place to learn.
```

**Step 4: Communicate**
```
External status page cadence:
  - T+5min: "Investigating reports of [symptom]"
  - T+15min: "We have identified the issue and are working on a fix"
  - T+30min: "A mitigation is in place; monitoring for stability"
  - T+resolution: "This incident has been resolved at [time]. Affected: [scope]. Duration: [X] minutes. We will publish a post-mortem within 5 business days."

Internal stakeholder cadence:
  - Every 15 minutes to executive channel
  - Every 30 minutes to broader eng channel
```

**Step 5: Resolve and Hand-off**
```
Resolution criteria (all must be true):
  ✅ Error rate back to normal (within SLO)
  ✅ Latency back to normal
  ✅ No active user complaints
  ✅ Root cause understood or active investigation ongoing with owner assigned
  ✅ Monitoring confirms stable for >15 minutes after mitigation

Post-incident tasks created:
  ✅ Post-mortem scheduled within 5 business days
  ✅ Immediate action items assigned with owners and due dates
  ✅ Incident documented in incident tracker
```

#### Triaging — How to Debug Systematically

**The elimination method** — used by senior engineers during incidents:

```
1. SCOPE the blast radius
   "Is this affecting all users or specific cohort? All endpoints or specific path?
    All regions or specific DC? Degraded or completely failing?"
   → Narrows hypothesis space from "anything" to "something that changed for this scope"

2. CORRELATE with changes
   "What changed in the 30 minutes before the first alert?"
   → Deploy, config, infra, traffic pattern, cron job, external dependency

3. INSPECT the traces
   "For an affected request, what does the full trace show?"
   → Identifies which span is slow or failing; which service, which call
   → Compares a slow trace with a fast trace — what's different?

4. FORM a falsifiable hypothesis
   "I believe the payment service timeout is caused by a slow Stripe API call due to
    network routing change at 14:23. I'll test this by checking Stripe's status page
    and comparing trace span durations before and after 14:23."

5. MITIGATE without full understanding
   "I don't need to know WHY Stripe is slow to rollback the network change.
    Restore first. Understand the network change later."

6. VERIFY restoration
   "SLO burn rate is back to 0.8× (normal). Error rate is 0.05%. Latency P99 is 280ms.
    Monitoring confirms stable for 20 minutes. Resolving."
```

**Red flags during triage that signal inexperience**:
- "I need to understand the root cause before I can mitigate" — no, mitigate first
- Debugging in production without confirming a mitigation path — changes to prod mid-incident can worsen the blast radius
- Not checking for recent changes first — the dog bites where it was last changed

---

### Post-Mortem Documentation Process

A post-mortem (also called a "post-incident review" or "PIR") is a structured retrospective on an incident. The purpose is **learning and systemic improvement**, not blame assignment.

**Blameless culture**: The post-mortem assumes that engineers acted with the information they had at the time, within the system they inherited. If the system allowed a human mistake to cause a production incident, the system is at fault — not the human.

#### Post-Mortem Template (Principal Engineer Standard)

```markdown
# Post-Mortem: [Incident Title]
**Date**: YYYY-MM-DD
**Severity**: SEV-[N]
**Duration**: [start time] to [end time] ([X] minutes)
**Author(s)**: [IC + TL]
**Status**: Draft / Under Review / Approved

## Impact
- Users affected: [N users / N% of traffic / specific cohort]
- Revenue impact: [$X estimated, or N/A]
- SLO impact: [SLO name] burned [X%] of monthly error budget
- External: [status page posted yes/no; customer escalations: N]

## Timeline
| Time (UTC) | Event |
|-----------|-------|
| 14:23 | Deploy v2.3.4 of payment-service (contains new Stripe timeout config) |
| 14:31 | First PagerDuty alert: checkout error rate 2.3% (threshold 1%) |
| 14:33 | On-call [name] acknowledges alert, opens incident channel #inc-20240115-checkout-errors |
| 14:35 | IC assigned: [name]; TL assigned: [name] |
| 14:41 | TL identifies trace showing Stripe API calls timing out after 500ms (default; was 3000ms) |
| 14:43 | Hypothesis confirmed: payment-service v2.3.4 introduced Stripe timeout regression |
| 14:46 | Rollback of payment-service to v2.3.3 initiated |
| 14:49 | Rollback complete; error rate returning to baseline |
| 14:55 | Error rate 0.02% (pre-incident baseline); incident resolved |

## Root Cause
[One paragraph. State the root cause precisely — the technical change that caused the failure, and the gap in process/testing that allowed it to reach production.]

payment-service v2.3.4 introduced a Stripe timeout configuration of 500ms (changed from 3000ms) in PR #4521. The change was intended to fail fast on Stripe slowness, but Stripe's normal P99 latency during EU business hours is 800–1200ms, causing all EU payment requests to time out. The CI/CD pipeline did not test against a realistic Stripe latency mock; the staging environment uses a local Stripe simulator with sub-10ms response times.

## Contributing Factors
- [ ] No load test with realistic Stripe latency in staging environment
- [ ] PR reviewer approved timeout change without checking Stripe's actual P99 latency
- [ ] No SLO-based smoke test in deployment pipeline that would have caught the EU error spike

## Action Items
| Action | Owner | Due Date | Priority |
|--------|-------|----------|----------|
| Add Stripe latency simulation (p95=400ms, p99=1200ms) to staging environment | @alice | 2024-01-29 | P1 |
| Add latency configuration guardrails: validation that timeout > (Stripe P99 + 200ms buffer) | @bob | 2024-01-22 | P1 |
| Add SLO-based automated rollback: if error rate > 2% within 5 minutes of deploy, auto-rollback | @charlie | 2024-02-05 | P2 |
| Add Stripe timeout config to deployment runbook review checklist | @alice | 2024-01-19 | P3 |

## What Went Well
- On-call acknowledged alert within 2 minutes of firing
- Rollback completed in 3 minutes — maturity in deployment pipeline
- Root cause identified in 8 minutes — distributed tracing showed the slow Stripe span immediately
- Clear blameless discussion in post-mortem; PR author felt safe raising the context

## Lessons Learned
- External API latency profiles must be part of staging environment contracts
- "Fail fast" configuration changes require real-world latency validation
- Trace-first debugging: the Stripe span was the bottleneck within 2 minutes of investigation

## Long-term Reliability Investment
[Optional: frame the action items in terms of the reliability gap they close. For PE-level post-mortems, this section is where you propose systemic improvements.]
```

**Post-mortem quality bar**:
- Timeline is factual, timestamped, and complete — a reader who was not present can reconstruct what happened
- Root cause is a single, precise statement — not "a bug was introduced"
- Action items are specific, assigned to one owner, and have a due date — not "improve testing"
- Blameless tone throughout — the system is the defendant, not the engineer

---

### Observability Tooling Landscape

#### Metrics

| Tool | Category | Strengths | Weaknesses |
|------|----------|-----------|------------|
| **Prometheus** | OLSS (Open-source, self-hosted) | Pull-based scraping; excellent Kubernetes integration; PromQL; active ecosystem | Cardinality limits; no long-term storage natively (use Thanos/Cortex/VictoriaMetrics) |
| **Grafana** | Visualization | Universal dashboard tool; supports Prometheus, Loki, Tempo, CloudWatch, Datadog, and 50+ data sources | Requires separate data stores; no built-in alerting as strong as dedicated tools |
| **Thanos / Cortex / VictoriaMetrics** | Long-term Prometheus storage | Global query across Prometheus shards; years of metric retention; deduplication | Operational complexity; cost |
| **Datadog** | SaaS, all-in-one | Metrics + logs + traces + APM + infra + alerts in one UI; excellent agent auto-discovery | Expensive at scale (pricing per host + per custom metric); vendor lock-in |
| **CloudWatch** | AWS-native | Zero ops overhead; integrates with all AWS services | Limited cardinality; expensive at high metric volume; weaker query language |
| **InfluxDB** | Time-series DB | SQL-like Flux query language; purpose-built for metrics | Less ecosystem than Prometheus |

#### Distributed Tracing

| Tool | Category | Strengths |
|------|----------|-----------|
| **Jaeger** | Open-source | CNCF project; OTel-native; excellent UI; Cassandra or Elasticsearch backend |
| **Zipkin** | Open-source | Older; simpler; good for getting started |
| **Tempo** (Grafana) | Open-source | Object-storage backed (S3); integrates natively with Grafana + Loki (TraceID → log correlation) |
| **Honeycomb** | SaaS | The reference implementation of high-cardinality observability; BubbleUp feature for automated anomaly correlation; founded by book's authors |
| **Datadog APM** | SaaS | Flame graph views; service maps; automatic anomaly detection |
| **AWS X-Ray** | AWS-native | Zero-ops for Lambda/ECS; integrates with AWS services |

#### Logging

| Tool | Category | Strengths |
|------|----------|-----------|
| **Elasticsearch + Kibana (ELK)** | Open-source | Full-text search; rich aggregations; Kibana dashboards; KQL query language |
| **Loki** (Grafana) | Open-source | Log aggregation indexed only by labels (cheap); query with LogQL; integrates with Grafana + Tempo |
| **Splunk** | Enterprise SaaS | Most powerful query language (SPL); SIEM capabilities; expensive |
| **CloudWatch Logs Insights** | AWS-native | Structured log queries; zero-ops for AWS workloads; cost spikes on large query scopes |
| **Datadog Logs** | SaaS | Unified with metrics + traces; pattern detection; expensive |

#### Alerting and On-Call

| Tool | Purpose | Notes |
|------|---------|-------|
| **PagerDuty** | On-call rotation, escalation policies, alert routing | Industry standard; integrates with all monitoring tools; runbooks attached to alerts |
| **OpsGenie** | On-call management | Atlassian product; strong Jira integration; similar to PagerDuty |
| **Alertmanager** (Prometheus) | Alert routing and deduplication | Groups related alerts; routes by severity/team; silences during maintenance |
| **Grafana OnCall** | Open-source on-call | Newer; free alternative to PagerDuty; integrates with Grafana dashboards |
| **StatusPage** | External communication | Atlassian product; public incident page; subscriber notifications |

#### The OTel Collector Pipeline

```
Application (OTel SDK)
    │ OTLP over gRPC or HTTP
    ▼
OTel Collector (sidecar or daemonset per node)
    ├── Processors:
    │   ├── Batch (reduce export overhead)
    │   ├── Tail-based sampler (keep only interesting traces)
    │   ├── Attribute enrichment (add k8s pod name, namespace, env)
    │   └── PII scrubber (redact user emails, credit card numbers)
    │
    └── Exporters:
        ├── Jaeger (traces)
        ├── Prometheus remote-write (metrics)
        └── Loki (logs)
```

The Collector decouples instrumentation from backend — change your observability backend without changing application code.

---

### Documentation Processes for Observability

#### Runbooks

A **runbook** is an operational document attached to an alert that tells the on-call engineer exactly what to do when that alert fires. At FAANG PE level, every production alert must have a runbook.

**Runbook template**:

```markdown
# Runbook: [Alert Name]
**Alert**: checkout_error_rate > 1%
**Severity**: SEV-1
**Team**: Payments Platform
**Last reviewed**: 2024-01-15

## What Does This Alert Mean?
[1-2 sentences. What is the metric? What does it measure? Why is this threshold set?]
The checkout error rate has exceeded 1% over a 5-minute window. Our SLO is 99.9% success rate,
and 1% error rate for >5 minutes will burn 15% of our monthly error budget.

## Immediate Actions (do these first, in order)
1. Check the Grafana dashboard: [link to dashboard]
   → Look at error rate by endpoint, by region, by error type
2. Check recent deploys: [link to deploy log]
   → Any deploy in the last 60 minutes? Roll it back immediately if error rate is > 2%
3. Check dependency health: [links to Stripe status page, PostgreSQL dashboard, Redis dashboard]
4. Open an incident channel if impact is > 5 minutes: [runbook for incident process]

## Diagnostic Queries
```
# Trace query: find slow checkout traces (Jaeger / Honeycomb)
service=checkout AND duration_ms > 2000 AND error=true | group by span.error_type

# Log query: find recent checkout errors (Loki / CloudWatch)
{service="checkout"} |= "error" | json | line_format "{{.error_type}} {{.order_id}} {{.user_id}}"

# Metric query (Prometheus): error rate by endpoint
rate(http_requests_total{service="checkout", status=~"5.."}[5m])
  / rate(http_requests_total{service="checkout"}[5m])
```

## Common Causes and Resolutions
| Cause | Signal | Resolution |
|-------|--------|-----------|
| Recent bad deploy | Errors started after deploy timestamp in traces | Rollback immediately |
| Stripe API degraded | Stripe spans showing > 1s in traces; Stripe status page shows incident | Enable Stripe fallback payment processor; page Stripe support |
| Database connection pool exhausted | PostgreSQL connection count at max in dashboard | Increase pool size (config change, 5 min); investigate connection leak |
| Redis cache miss storm | Cache hit rate drops; PostgreSQL CPU spikes | Force cache warm-up script; increase cache TTL |

## Escalation
- If unresolved in 15 minutes: escalate to Payments Platform TL on PagerDuty
- If Stripe is the cause: page Stripe enterprise support immediately
- If database is the cause: escalate to Database Platform team

## Related Runbooks
- [Runbook: Stripe API Degraded](./stripe-degraded.md)
- [Runbook: PostgreSQL Connection Pool](./postgres-connection-pool.md)
- [Runbook: Incident Process](./incident-process.md)
```

**Runbook quality bar**:
- Written by someone who has been on-call for this alert — not a documentation exercise
- Every link is working and points to the current system (runbooks with broken links are worse than no runbook)
- Reviewed and tested at least quarterly
- Action items are deterministic — no ambiguity about what to do first

#### Architecture Decision Records (ADRs) for Observability

Every observability architecture decision should be documented as an ADR:
- "Why we chose Honeycomb over Datadog"
- "Why we use tail-based sampling at 10% with 100% for errors/slow traces"
- "Why we adopted Loki over Elasticsearch for logs"
- "Why we standardized on OTel SDK instead of Datadog agent for instrumentation"

These decisions age poorly when undocumented — new engineers spend weeks rediscovering the rationale, or worse, re-evaluate and re-implement without understanding the original constraints.

#### Service Catalogs and Ownership

Every service must have a documented owner and a health contract:

```yaml
# service.yaml (checked in to each service repository)
name: payment-service
team: payments-platform
tier: 1  # 0=infrastructure, 1=customer-facing-critical, 2=internal, 3=non-critical
on-call: payments-platform-primary@pagerduty  # PagerDuty service key
slos:
  - name: checkout_success_rate
    target: 99.9%
    window: 30d
    measurement: "rate(http_requests_total{service='payment',status!~'5..'}) / rate(http_requests_total{service='payment'})"
runbooks:
  - alert: checkout_error_rate_high
    url: https://internal-docs/runbooks/payment-service/checkout-error-rate.md
dependencies:
  - service: postgres-payments
    criticality: hard  # outage of dependency = outage of this service
  - service: stripe-api
    criticality: hard
  - service: redis-cache
    criticality: soft  # can operate degraded without this dependency
dashboards:
  primary: https://grafana.internal/d/payment-service-slo
```

---

### Observability in System Design Interviews

When designing any system, proactively include an observability section. At PE level, omitting this signals operational immaturity.

**The observability design checklist** (include in every HLD):

```
□ SLIs and SLOs defined for each user-facing operation
  → What does "working" mean? How do we measure it from the user's perspective?

□ Four golden signals instrumented
  → Latency (P50/P99/P999), traffic (RPS), errors (rate + type), saturation (queue depth, pool utilization)

□ Distributed tracing with context propagation
  → Every request carries trace_id; every service propagates it downstream

□ Structured event logging
  → Every log line includes trace_id, span_id, user_id, and business context

□ Alerting on SLO burn rate
  → Alert when error budget is burning at a rate that threatens the monthly SLO

□ Runbooks for every alert
  → Each alert has a documented resolution procedure with escalation paths

□ Dependency health monitoring
  → Each external dependency (Stripe, Twilio, third-party APIs) has its own SLI + circuit breaker + runbook

□ Capacity signals for scaling decisions
  → CPU/memory saturation → auto-scaling triggers
  → Queue depth, p99 latency spikes → horizontal scaling events

□ Deployment verification
  → Canary analysis: deploy to 1% of traffic; compare SLO metrics; auto-rollback if burn rate spikes
```

**FAANG interview application**: "For a payment processing system at 10K RPS, I'd define these SLOs: (1) checkout success rate ≥ 99.95% over 30 days, (2) P99 checkout latency < 2s. I'd instrument with OTel, propagate TraceContext through the payment → inventory → fraud → Stripe call chain, and store traces in Honeycomb with tail-based sampling at 100% for errors. Alerts fire on 14.4× burn rate (exhausts budget in 2 hours), routing to PagerDuty with a runbook that walks the on-call through: check recent deploy → check Stripe status → check DB connection pool. Post-mortem required for all SEV-1 and above within 5 business days."

---

### Connections: Observability ↔ DDIA Concepts

| DDIA Topic | Observability Requirement |
|-----------|--------------------------|
| Replication lag | Monitor `replication_lag_seconds` per replica; alert if lag > SLO threshold |
| Partition hotspots | Track request rate and latency per partition key; detect skew via histogram |
| Compaction pauses (LSM-Tree) | Alert on sudden P99 spikes in Cassandra/RocksDB writes during compaction window |
| Leader election storms | Trace leader election events; alert on election frequency > N/hour |
| Kafka consumer lag | `kafka_consumer_group_lag` metric per topic-partition; alert on growing lag |
| MVCC vacuum (PostgreSQL) | Track `pg_stat_bgwriter`, `pg_stat_database` metrics; alert on bloat |
| Sloppy quorum events | Log each sloppy quorum write event with hinted node; alert on high frequency |
| Stream processing watermarks | Export watermark lag as a metric; alert on watermark falling behind event time |

---

### Observability Engineering — Book Summary

**Authors**: Charity Majors (CEO, Honeycomb.io), Liz Fong-Jones (Staff Engineer, Honeycomb), George Miranda (formerly at Honeycomb)
**Publisher**: O'Reilly, 2022
**Core thesis**: Monitoring tells you something is broken; observability tells you why. Systems at scale require the ability to ask arbitrary questions about production state without shipping new code.

#### Key Takeaways by Chapter Theme

**Part 1 — The Path to Observability**
- Monitoring dashboards are built around known failure modes. Modern complex systems fail in unknown ways — ways no one anticipated when writing the dashboards.
- The core property: "Can I understand any internal state from the outside, by asking questions of the system's outputs?" If yes, the system is observable.
- Cardinality is the unlock: high-cardinality fields (user_id, request_id, trace_id, feature_flag_variant) are the ones that make unknown failures debuggable. Traditional time-series databases cannot query them.

**Part 2 — Structured Events**
- The unit of observability is the **wide structured event** — one event per request, per unit of work, containing all relevant context fields.
- Wide events should grow fields throughout the request lifecycle: early middleware adds user_id and session_id; business logic adds order_id and cart_item_count; error handling adds error_type and stack_trace_hash.
- The event is emitted at the end of the request — it's a complete record of everything that happened.

**Part 3 — Distributed Tracing**
- Tracing is structured events + causality: events linked into parent-child spans, carrying trace_id across service boundaries.
- Trace-first debugging: start from a trace, not from logs. The trace shows the critical path; logs provide detail within each span.
- Sampling is a necessary evil. Tail-based sampling is strongly preferred — it makes the decision after knowing the full trace (error? slow? normal?).

**Part 4 — Observability-Driven Development**
- Instrument code before shipping, not after an incident makes you. Write instrumentation alongside features.
- Use production observability tools in development: deploy to staging with full tracing, query traces to verify behavior before shipping.
- "The cost of observability is paid once; the cost of being unobservable is paid continuously."

**Part 5 — Spreading Observability Culture**
- Observability culture starts with on-call: if the people who write code are also on-call for it, they invest in observability because they experience the pain of not having it.
- Teach engineers to debug with traces before opening a bash shell to a production host. The bash shell does not scale; the traces do.
- SLOs create a shared language for reliability between engineering and product: error budget gives product the authority to trade reliability investment for feature velocity, and vice versa.

---

## Quick Reference Card

```
═══════════════════════════════════════════════════════════════════════
STORAGE ENGINES
───────────────────────────────────────────────────────────────────────
LSM-Tree (Cassandra, RocksDB, HBase):
  Write: memtable (RAM) → SSTable (disk, sorted) → compaction
  Read:  memtable → Bloom filter → SSTable(s) → result
  Pros:  sequential writes (fast), compresses well
  Cons:  reads check multiple SSTables, compaction I/O bursts
  Use:   write-heavy (>50K writes/sec), time-series, logs

B-Tree (PostgreSQL, MySQL InnoDB, SQLite):
  Write: locate leaf page → update in-place → WAL
  Read:  O(log n) page reads — 3–4 page reads for most trees
  Pros:  predictable read latency, good for range scans
  Cons:  random I/O on writes, WAL write overhead
  Use:   read-heavy OLTP, complex queries, mixed workloads

Column-oriented (Redshift, BigQuery, ClickHouse, Parquet):
  Store column values together → compression, vectorized ops, SIMD
  Use:   OLAP — aggregate over millions of rows on few columns

═══════════════════════════════════════════════════════════════════════
REPLICATION
───────────────────────────────────────────────────────────────────────
Single-leader: one write master; followers replicate. Replication lag causes:
  - Read-your-writes: route post-write reads to leader for N seconds
  - Monotonic reads: session affinity to same replica
  - Consistent prefix: causally related writes to same partition

Multi-leader: write to any leader per DC; conflict resolution required.
  LWW (risky: silent data loss), CRDT (safe for sets/counters), custom merge

Leaderless (Dynamo): W + R > N for quorum read guarantee.
  N=3, W=2, R=2 → tolerate 1 node failure
  Sloppy quorum → higher availability, weaker consistency
  Fencing token (version vector) to detect concurrent writes → siblings

═══════════════════════════════════════════════════════════════════════
ISOLATION LEVELS (anomalies prevented ✅ / possible ❌)
───────────────────────────────────────────────────────────────────────
                      Dirty  Non-rep  Phantom  Write   Lost
                      Read   Read     Read     Skew    Update
Read Uncommitted:      ❌      ❌        ❌        ❌       ❌
Read Committed:        ✅      ❌        ❌        ❌       ❌
Repeatable Read:       ✅      ✅        ⚠️        ❌       ✅
Snapshot Isolation:    ✅      ✅        ✅        ❌       ✅
Serializable (SSI):   ✅      ✅        ✅        ✅       ✅

Write skew example: two doctors both go off-call because each reads
that the other is on-call. Fix: Serializable isolation (SSI) or
explicit SELECT FOR UPDATE locking.

═══════════════════════════════════════════════════════════════════════
CONSENSUS (Raft)
───────────────────────────────────────────────────────────────────────
Raft leader election:
  1. Follower times out (150–300ms, randomized) → becomes Candidate
  2. Increments term, votes for self, sends RequestVote RPC
  3. Wins if majority vote + candidate log ≥ up-to-date as any voter
  4. Leader sends AppendEntries (log replication + heartbeat)
  5. Entry committed when majority acknowledge → applied to state machine

ZooKeeper (ZAB ≈ Raft):
  - Ephemeral nodes: deleted when client session expires → leader election
  - Watches: one-time notification on node change → membership changes
  - Linearizable writes, reads from any replica (may be slightly stale)
  - Use for: leader election, distributed locks, config, service discovery
  - Never implement Raft yourself; use etcd / ZooKeeper / Consul

═══════════════════════════════════════════════════════════════════════
CONSISTENCY MODELS (strongest → weakest)
───────────────────────────────────────────────────────────────────────
Linearizable:  appears as single copy; reads always see latest write
Causal:        causally related ops ordered everywhere; concurrent ops may differ
Eventual:      all replicas converge eventually; stale reads possible

PACELC (more useful than CAP):
  During Partition → choose Availability or Consistency
  Else (normal)    → choose Latency or Consistency

  Cassandra:  PA / EL  — available + low latency; eventual consistency
  DynamoDB:   PA / EL  — (by default)
  Spanner:    PC / EC  — consistent everywhere; uses TrueTime (GPS clocks)
  ZooKeeper:  PC / EC  — consistent writes; higher latency

Linearizability ≠ Serializability:
  Linearizability = recency guarantee (single object, single op)
  Serializability = isolation guarantee (multiple objects, transactions)

═══════════════════════════════════════════════════════════════════════
STREAM PROCESSING
───────────────────────────────────────────────────────────────────────
Time semantics:
  Event time:      timestamp when event occurred (correct; can be late)
  Processing time: timestamp when event processed (easy; incorrect for out-of-order)
  → Always use event time. Use watermarks to handle late arrivals.

Watermark = max(event_time_seen) - max_expected_delay
  Events after watermark = late data → configurable: ignore / reopen / side output

Windowing:
  Tumbling:  fixed, non-overlapping     [0–5) [5–10) [10–15)
  Hopping:   fixed, overlapping         [0–5) [1–6)  [2–7)
  Session:   variable, gap-based        [login ... idle 30min ... logout]

Join patterns:
  Stream-table: enrich event with local state (loaded from CDC changelog)
  Stream-stream: windowed join, buffer both streams in keyed state
  Table-table: materialized view from two CDC streams

Kafka: log-based; consumer reads its own offset; replay any time
  Compacted topic: latest value per key → changelog/database semantics
  Consumer group: N consumers share M partitions (M/N partitions per consumer)

Delivery guarantees:
  At-most-once:  fast, possible data loss
  At-least-once: duplicates possible; consumer must be idempotent
  Exactly-once:  Kafka transactions + idempotent producers (highest cost)

═══════════════════════════════════════════════════════════════════════
OBSERVABILITY (Majors / Fong-Jones / Miranda)
───────────────────────────────────────────────────────────────────────
Monitoring vs Observability:
  Monitoring:     pre-aggregated metrics; answers known questions
  Observability:  raw structured events; answers unknown questions
  Unit of obs:    wide structured event per request (carries all context)

Four Golden Signals (Google SRE):
  Latency:    P50/P95/P99/P999 — segment successful vs error latency
  Traffic:    RPS, messages/sec, active connections
  Errors:     rate of failures — distinguish 4xx (user) vs 5xx (system)
  Saturation: CPU %, queue depth, connection pool utilization

SLO / Error Budget:
  SLI: quantitative measure (success rate, P99 latency)
  SLO: target value over rolling window ("99.9% success, 30-day rolling")
  Error budget = 1 - SLO target  (99.9% → 43.8 min/month downtime)
  Alert on burn rate: 14.4× burn = exhausts monthly budget in 2 hours

Distributed Tracing:
  Trace:     DAG of spans across services for a single request
  Span:      unit of work (one RPC, one DB query, one cache call)
  traceparent header: propagate trace_id + span_id across all service hops
  Sampling:  tail-based preferred (decide after knowing full trace outcome)
             100% for errors/slow; 10% for normal traffic

Incident Response order:
  1. Scope: who's affected, which endpoints, which regions
  2. Correlate: what changed 30 min before first alert (deploy/config/infra)
  3. Trace-first: find the slow/failing span — no bash sessions in prod
  4. Mitigate: rollback > feature flag > traffic shift > hotfix
  5. MTTR > root cause understanding during an active incident

Post-mortem must-haves:
  Timestamped timeline → root cause (single precise statement) →
  contributing factors → action items (specific owner + due date) →
  blameless tone (system is the defendant)

Tooling:
  Metrics:  Prometheus + Grafana + Thanos (long-term) | Datadog (SaaS)
  Traces:   Jaeger | Tempo | Honeycomb | Datadog APM
  Logs:     Loki (cheap, label-indexed) | ELK | Splunk | CloudWatch
  On-call:  PagerDuty | OpsGenie | Alertmanager (routing/dedup)
  OTel:     SDK → Collector (batch, sample, enrich, scrub PII) → backend

═══════════════════════════════════════════════════════════════════════
ENCODING (schema evolution)
───────────────────────────────────────────────────────────────────────
Protobuf: numeric field tags; rename safe; never reuse tags; new fields optional
Avro:     field name matching; schema registry required; rename breaks compat
JSON:     no schema; unknown fields ignored; partial forward/backward compat
Rule: for Kafka pipelines → Avro + schema registry; for gRPC → Protobuf
```
