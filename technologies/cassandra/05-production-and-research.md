# Cassandra — Production Usage & Research

## Research Paper

### "Cassandra: A Decentralized Structured Storage System"

**Authors**: Avinash Lakshman, Prashant Malik  
**Organization**: Facebook  
**Published**: ACM SIGOPS Operating Systems Review, Vol. 44, Issue 2 (April 2010)  
**Link**: [dl.acm.org/doi/10.1145/1773912.1773922](https://dl.acm.org/doi/10.1145/1773912.1773922)

### Problem Statement

Facebook's **Inbox Search** feature required indexing every message sent between users to make them searchable. The workload was:
- **Write-heavy**: hundreds of millions of messages written per day
- **Geographically distributed**: users in US + EU with no latency tolerance for cross-continent writes
- **High availability**: inbox search must work even when datacenters partially fail
- **Scale**: 200M+ users, growing

Existing options in 2007–2008: MySQL (sharded, operational nightmare at scale), HBase (required Hadoop, complex, leader bottleneck), Dynamo (Amazon-internal, not available).

### Key Contributions

| Contribution | Description |
|-------------|-------------|
| **Masterless replication** | Every node is a peer; no leader election; all nodes accept reads and writes |
| **Dynamo-style consistent hashing** | Ring topology; partition key hash determines owning node; nodes added/removed without full reshuffle |
| **BigTable-style storage model** | SSTable/MemTable storage; column-family data model; sorted string storage for efficient column range queries |
| **Tunable consistency** | Per-operation consistency level; same cluster can serve `ONE` and `QUORUM` requests simultaneously |
| **Gossip failure detection** | Phi Accrual failure detector; continuous suspicion score rather than binary alive/dead |
| **Hinted handoff** | Coordinator stores hints for temporarily unreachable replicas; eventual delivery |

### Why the Paper Matters for Interviews

The Cassandra paper introduced the idea of **picking the best ideas from multiple systems** rather than designing from scratch. The interviewer often probes:
1. *"What did Dynamo contribute vs BigTable?"* → Dynamo: ring topology, tunable consistency, masterless; BigTable: SSTable, column-family model
2. *"What trade-off did Facebook explicitly accept?"* → AP (availability + partition tolerance over consistency); inbox search could return slightly stale results — acceptable
3. *"What problems did this paper NOT solve that were discovered later?"* → Tombstone accumulation, compaction complexity, JVM GC pauses at large heap sizes

---

## Companies Using Cassandra

### Apple — Largest Known Deployment

**Scale**: 75,000+ nodes (as of 2019); petabyte-scale data across multiple services  
**Use cases**:
- iCloud Drive: user files metadata, sync state
- iCloud Photos: photo metadata, album memberships
- Siri user preferences
- App Store ratings and reviews

**Why Cassandra**:
- Massive scale that makes DynamoDB cost-prohibitive
- Need for multi-DC active-active (Apple has 3+ datacenters)
- Write throughput: iCloud sync events generate billions of writes per day

**Operational model**: Apple maintains a dedicated Cassandra Platform team; they have contributed significantly upstream to the Apache project, including improvements to repair, streaming, and CQL.

---

### Netflix — Multi-Region Time-Series + Operational Data

**Scale**: 30+ petabytes across clusters; largest single cluster: ~2,500 nodes  
**Use cases**:
- **Play history**: every time a user plays, pauses, or stops a video — stored as a time-series row per user
- **Customer service data**: billing history, account events
- **Studio operations**: content scheduling, production pipeline metadata
- **A/B test assignment**: which experiment variant each user is in

**Why Cassandra**:
- Multi-region active-active: Netflix serves US, EU, APAC simultaneously; writes must be accepted locally
- Play events are write-heavy and read-by-user (perfect partition key = user ID)
- Netflix is all-in on AWS but at their scale, self-managed Cassandra is 10x cheaper than DynamoDB

**Netflix's contribution**: Netflix developed **Astyanax** (Java driver, predated the official DataStax driver), the **Priam** sidecar for automated backup and repair, and extensive tooling for capacity management. They publish extensively on their Tech Blog about Cassandra operations.

---

### Discord — Message Store (Then Migrated to ScyllaDB)

**Scale**: Billions of messages; hundreds of millions of users  
**Use cases**:
- Message history per channel (Discord channel = partition key; message timestamp = clustering key)
- User read state (which messages each user has seen)

**Why Cassandra initially**:
- Chat message history is the textbook Cassandra use case: append-only writes (messages), time-ordered reads (load last N messages in a channel)
- TWCS compaction fit perfectly: messages older than 14 days rarely accessed, TTL for ephemeral channels

**Why Discord migrated to ScyllaDB (2023)**:
- At billions of rows, JVM GC pauses caused unacceptable p99 latency spikes
- ScyllaDB (C++, no GC, shard-per-core architecture) gave 3–5x better p99 latency
- Same CQL API: migration was a drop-in replacement with no application code changes

**Lesson**: Cassandra is excellent for this use case; at extreme scale, JVM overhead becomes the bottleneck — ScyllaDB solves this without changing the programming model.

---

### Uber — Geospatial and Trip Data

**Scale**: Hundreds of terabytes; dozens of clusters  
**Use cases**:
- **Driver location history**: every GPS ping from every driver stored as time-series (driver ID + time → lat/lng)
- **Trip metadata**: trip start/end, route, fare — append-heavy, read by user or driver
- **Surge pricing data**: per-hexagonal-grid pricing, updated every few seconds

**Why Cassandra**:
- GPS pings are write-intensive (every driver sends a ping every few seconds; millions of drivers globally)
- Partitioned by driver ID naturally distributes load
- Multi-region: Uber operates in 70+ countries; local writes are critical for sub-100ms API response

**Uber's contribution**: Uber developed **Cherami** (a message queue on Cassandra) and contributed to the Apache project. They have published extensively on schema design for geospatial data and their migration from MySQL → Cassandra.

---

### Instagram — Activity Feeds (Then Migrated)

**Scale**: Hundreds of millions of users; billions of follows/likes/comments  
**Use cases**:
- User activity feed (follow, like, comment, post events per user)
- Direct message storage (2013–2015 era)

**Why Cassandra initially**:
- Activity events are append-heavy; partition by user ID; range-read last 50 events

**Why Instagram moved away**:
- Instagram ultimately landed on **custom-sharded PostgreSQL** for most core data because:
  1. Product requirements evolved to need more complex queries (filtering, aggregations)
  2. PostgreSQL with proper sharding gave them stronger consistency for critical flows (purchases)
  3. Operational complexity of Cassandra wasn't justified for their team size

**Lesson**: Cassandra's schema-rigidity is a long-term cost if your product evolves query patterns. If you don't know your access patterns will remain stable for 5+ years, a more flexible store may be better.

---

### Spotify — User Data and Playlists

**Scale**: 500M+ users; billions of songs  
**Use cases**:
- User playlist contents (user ID → list of track IDs)
- Listening history (user ID + time → track played)
- Artist and album metadata lookup

**Why Cassandra**:
- Listening history is perfect Cassandra: high-write, time-series, partitioned by user
- Multi-region write availability: Spotify serves EU + US simultaneously

---

### Twitter (Historical — Flock)

**Use case**: Social graph storage — who follows whom  
**Migrated to**: Custom Manhattan (Twitter's own KV store) and later sharded MySQL

**Why migrated away**: Social graph requires efficient traversal across many users — graph-style queries that don't fit the partition-key model. The social graph use case is better served by graph databases or purpose-built stores with richer index structures.

---

## Operational Lessons from Production

### 1. Repair is Not Optional

**Lesson**: Anti-entropy repair must run at least once within `gc_grace_seconds`. Teams that skip repair discover deleted data resurrecting itself (zombie rows) and consistency violations that violate their application's invariants.

**Operationalisation**:
```bash
# Run on each node, weekly (automated via Priam or custom job)
nodetool repair -pr --full keyspace_name
```
`-pr` = primary ranges only; run on each node to cover the full cluster without duplicate work.

### 2. Capacity Plan for Compaction I/O

Compaction with STCS requires ~50% free disk space (two copies of the data during a compaction run). Teams routinely run out of disk during compaction, causing the node to stop accepting writes.

**Rule**: Never fill Cassandra nodes above 50% disk capacity. Alert at 40%.

### 3. Monitor SSTable Count

A growing SSTable count means compaction is falling behind writes. Every SSTable above ~20 adds measurable read latency. Alert when `cfstats` shows > 50 SSTables for any table.

### 4. Never Skip the Schema Review

Bad schema design is irreversible at scale. Adding a clustering key requires rewriting all data. Changing the partition key is a full migration. The most expensive Cassandra mistakes are caught in the schema review, not in production.

**Schema review checklist**:
- [ ] No `ALLOW FILTERING` in any application query
- [ ] Partition key distributes load evenly (no hotspots)
- [ ] Partition size bounded (time bucket for time-series)
- [ ] TTL set for all time-bounded data (avoid tombstone accumulation)
- [ ] TWCS chosen for tables with TTL
- [ ] No secondary indexes on high-cardinality columns

### 5. Cassandra Requires a Platform Team at Scale

Apple, Netflix, and Uber all have dedicated Cassandra platform teams (5–20 engineers). If you don't have that capacity, DynamoDB or a managed Cassandra offering (DataStax Astra, Amazon Keyspaces) significantly reduces operational burden.

---

## FAANG Interview: Full-System Design Framing

### How to Introduce Cassandra in a System Design Answer

**Scenario**: "Design a time-series metrics system for 100M devices sending a data point every second."

> "For storage, I'd reach for Cassandra. The write throughput requirement — 100M writes/second — exceeds what you can achieve with a relational database, and it fits Cassandra's write-optimised LSM-tree model perfectly. I'd model the schema as: partition key = (device_id, day_bucket) to bound partition size to one day's data per device; clustering key = timestamp descending, so recent data is at the top of the partition. Replication factor 3 per region, LOCAL_QUORUM for both reads and writes. TWCS compaction with a 1-day window and 30-day TTL — data expires cleanly without tombstone accumulation. For horizontal scale, I'd start with 30 nodes and add nodes as write throughput grows; Cassandra scales linearly."

### Common Follow-up Questions

| Question | Key Answer |
|----------|-----------|
| "What happens if a node goes down?" | Writes go to the other 2 replicas (RF=3). Hinted handoff stores mutations for the down node. When it recovers, hints are replayed. If down > 3 hours, run `nodetool repair`. |
| "How do you handle a datacenter outage?" | With NetworkTopologyStrategy RF=3 per DC, the surviving DC continues serving LOCAL_QUORUM reads and writes. No data loss. Resume cross-DC replication when the failed DC recovers. |
| "What's the consistency level you'd use?" | LOCAL_QUORUM — gives strong consistency within the DC at the cost of one additional replica round trip vs ONE. Tolerates 1 node failure per DC. |
| "How do you know a partition is too large?" | `nodetool tablehistograms` shows partition size distribution. Alert when p99 partition size > 100MB. Redesign schema (add bucket) before it hits 1GB. |
| "How does Cassandra compare to InfluxDB for this use case?" | InfluxDB is purpose-built for time-series with better compression and retention policies. But it doesn't offer Cassandra's multi-DC active-active and horizontal scale. For 100M devices, I'd choose Cassandra unless dedicated time-series semantics are critical. |

---

## Related Files

| File | Topic |
|------|-------|
| [README.md](README.md) | Decision drivers — when this production evidence tips the decision |
| [01-architecture.md](01-architecture.md) | The ring topology that makes multi-region active-active possible |
| [04-tuning-guide.md](04-tuning-guide.md) | How to operationalise the lessons from Netflix/Apple |
