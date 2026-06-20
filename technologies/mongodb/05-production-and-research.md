# MongoDB in Production & Research

## Research Foundation

### Core Paper: "MongoDB: A Scalable, High-Performance, Open-Source, Schema-Free, Document-Oriented Database"

MongoDB doesn't have a single canonical research paper the way Cassandra (Lakshman & Malik, 2009) or Bigtable (Chang et al., 2006) do. Its design is instead documented through:

1. **WiredTiger storage engine** — originally developed by WiredTiger Inc. (acquired by MongoDB 2014). WiredTiger's design is based on LSM trees + B-trees with MVCC, influenced by the paper *"WiredTiger: A high performance, NoSQL storage engine"*.
2. **MongoDB 4.0 Transactions** — multi-document ACID transactions used snapshot isolation with the WiredTiger snapshot read model, documented in "Transactions in MongoDB" (VLDB 2019 by Cabral Brooker, Douglas Terry et al.).
3. **The Raft consensus paper** — MongoDB's replication protocol is Raft-inspired (Ongaro & Ousterhout, 2014), though MongoDB's implementation predates the paper and uses a variation called "protocol version 1."

### Key Design Decisions (and Their Origins)

| Decision | Origin | Impact |
|---------|--------|--------|
| BSON document model | 10gen internal; inspired by JSON ubiquity in web apps (2009) | Eliminated object-relational impedance mismatch |
| Single-primary replica set | Deliberate CP choice; influenced by Google Chubby (Burrows 2006) | Strong consistency without conflict resolution |
| Oplog as replication log | Influenced by MySQL binlog; designed for idempotent replay | Enables change streams, PITR, and zero-downtime upgrades |
| WiredTiger MVCC | WiredTiger acquisition (2014); motivated by MMAPv1 lock contention | Document-level locking; concurrent read/write without collection-level locks |
| Aggregation pipeline | Internal (v2.2, 2012); influenced by MapReduce | Replaced JavaScript MapReduce; enables server-side processing |
| Distributed transactions | Long-requested; implemented after WiredTiger MVCC enabled it (v4.0 2018) | Made MongoDB viable for financial/inventory workloads |

---

## Companies Using MongoDB in Production

### Uber — Real-Time Geospatial & Trip Data

**Scale**: Hundreds of millions of trips; multiple petabytes; thousands of collections.

**Use cases**:
- Driver/rider location tracking (2dsphere geospatial queries: `$near`, `$geoWithin`)
- Trip history: embedded line items + route + pricing in one document
- Surge pricing computation: time-series reads for geographic zones
- Driver profile store: nested documents for vehicle info, ratings, certifications

**Why MongoDB**:
- Geospatial queries were native (2dsphere indexes); spatial lookups needed for dispatch
- Flexible schema accommodated rapid product iteration (new ride types, new markets)
- Strong consistency per document for trip state machine (pending → active → completed)

**Architecture decisions**:
- Sharded on `{city, driverId}` — zone sharding per city for data locality
- `w:majority` for trip state changes; `w:1` for location pings (high-frequency, loss acceptable)
- Dedicated secondary replicas for analytics (prevent impact on production primaries)

**Migration lessons**:
- Uber migrated ride dispatch off MongoDB to a custom system (Schemaless) for higher write throughput at global scale — MongoDB's single-primary model couldn't scale to their global writes-per-second without an unwieldy number of shards.
- **Key lesson**: MongoDB is excellent for documents with strong consistency requirements. When your workload becomes pure write throughput at global scale, you need a leaderless system.

---

### eBay — Product Catalog

**Scale**: Hundreds of millions of active listings; terabytes of product attributes.

**Use cases**:
- Product listing storage: each category (electronics, clothing, auto parts) has different attribute schemas
- Seller inventory: nested documents per seller
- Search facet metadata: pre-computed facets for category filters

**Why MongoDB**:
- Product catalog is the canonical document store use case: every item has a `{title, price, images}` core with category-specific extensions (electronics: `{voltage, wattage}`; clothing: `{size, color, material}`)
- Schema flexibility eliminated the "EAV table" anti-pattern (Entity-Attribute-Value) that plagued relational product catalogs
- Rich secondary indexes for faceted search without pre-defining access patterns

**Architecture decisions**:
- Sharded on `{categoryId, listingId: "hashed"}` — uniform distribution within category; category-local range scans
- Wildcard indexes on `attributes.*` for dynamic attribute filtering
- Aggregation pipeline for facet computation; results cached in Redis

**eBay's insight**: For highly polymorphic data (product catalog), MongoDB eliminates the 10+ table join that a normalized relational schema requires to reconstruct a single product. One document read vs. one N-way JOIN.

---

### Shopify — Multi-Tenant E-Commerce

**Scale**: 2M+ merchants; billions of orders; multi-petabyte dataset.

**Use cases**:
- Order storage: line items, shipping, payment, fulfillment — all embedded in one order document
- Product variants: nested `{options, sku, inventory}` per variant
- Metafields: merchant-defined custom attributes (wildcard document fields)

**Why MongoDB**:
- Multi-tenant SaaS with merchants having wildly different data shapes (high-fashion vs. handmade goods vs. digital products)
- Embedded order documents allow single-read retrieval of the complete order context
- Flexible metafields without DDL migrations for every new merchant-defined attribute

**Architecture decisions**:
- Sharded on `{shopId, _id: "hashed"}` — shop isolation on shards; `w:majority` for orders
- Transactions for inventory decrement + order creation atomicity
- Oplog-based change streams drive order fulfillment event bus (webhooks to merchants)

**Shopify's shard key lesson (public post-mortem)**:
- Early sharding used `_id` (ObjectId) as ranged shard key → classic hotspot on last shard
- Migration to `{shopId, _id: "hashed"}` required a full collection rebuild — multi-day operation with dual-write and backfill
- **Key lesson**: The shard key decision is operationally expensive to change. Treat it as permanent. Invest heavily in getting it right before launch.

---

### Coinbase — Financial Data with Auditability

**Scale**: Tens of millions of users; billions of transactions; regulatory compliance across 100+ countries.

**Use cases**:
- Transaction ledger: individual transaction documents with embedded metadata
- User KYC documents: identity verification records with audit trail
- Compliance reporting: transaction history for regulatory filings

**Why MongoDB**:
- Transaction documents are naturally document-shaped: `{userId, amount, currency, type, timestamp, metadata}` with per-transaction-type metadata variations
- Strong consistency (`w:majority`) critical for financial correctness
- Multi-document transactions for atomic balance updates + transaction record creation

**Architecture decisions**:
- `w:majority`, `j:true` for all financial writes — zero data loss tolerance
- `readConcern: "majority"` for all balance reads — read-your-writes + no stale data
- Delayed replica (24 hours) for point-in-time recovery against human error
- Separate replica set for audit/compliance reads — avoids compliance workload impacting production

**Write concern incident**: Early in production, `w:1` (default at the time) was used for some write paths. A primary failover exposed a gap: writes that were acknowledged by the primary but hadn't replicated before failover were lost. Migration to `w:majority` everywhere was non-trivial — required driver-level changes + application testing.
**Key lesson**: In financial systems, `w:majority` is non-negotiable. The latency cost (10–50ms) is trivially acceptable versus the compliance and reputational risk of data loss.

---

### LinkedIn — Social Graph + Content

**Scale**: 900M+ users; billions of profile views; petabytes of content.

**Use cases** (historical, before partial migration):
- User profile data: skills, experience, connections count embedded in user document
- Activity feed items: posts, reactions, comments per member
- InMail message metadata

**Why MongoDB (initially)**:
- User profiles are documents: professional experience is a list of `{company, title, dates, description}` — perfect for embedding
- Schema flexibility for different user types (individual vs. company pages)
- Rapid product iteration without migration scripts

**Migration away (partial)**:
- LinkedIn migrated heavy social graph traversal (connection graph, mutual connections) to Espresso (internal key-value store) and later Voldemort/Venice
- MongoDB's `$lookup` was too slow for 6-hop graph traversals across 900M nodes
- Retained MongoDB for profile content storage but moved graph traversal to purpose-built graph stores
**Key lesson**: MongoDB excels at document retrieval but is not a graph database. Deep relationship traversal (friend-of-friend, recommendation graph) requires a graph-native store (Neo4j, Neptune) or a purpose-built system.

---

### Cisco — Network Telemetry (Time-Series Collections)

**Scale**: Millions of network devices; billions of metrics per day.

**Use cases**:
- Network device telemetry: CPU, memory, interface stats per device per minute
- Fault event logs: alerts, anomalies, configuration changes
- Security event streams: intrusion detection, flow records

**Why MongoDB (v5.0+ Time Series Collections)**:
- MongoDB 5.0 introduced native **Time Series Collections** — columnar storage for `{timestamp, metadata, measurement}` documents
- Compression ratios of 5–10× vs regular collections for time-series data
- Automatic query routing for time-range queries using internal bucketing

```javascript
// Create a time series collection:
db.createCollection("device_metrics", {
  timeseries: {
    timeField: "timestamp",        // Must be a Date field
    metaField: "deviceId",         // Field to partition on (like a tag)
    granularity: "minutes"         // seconds | minutes | hours
  },
  expireAfterSeconds: 2592000      // Auto-expire after 30 days
});

// Insert telemetry:
db.device_metrics.insertMany([
  { deviceId: "switch-001", timestamp: new Date(), cpu: 45.2, memory: 67.8 },
  { deviceId: "switch-001", timestamp: new Date(), cpu: 46.1, memory: 68.2 }
]);
```

**Key lesson**: MongoDB Time Series Collections (v5.0+) make MongoDB competitive with InfluxDB for moderate-scale telemetry. For > 500K events/sec or petabyte-scale time-series, purpose-built TSDBs (InfluxDB Clustered, TimescaleDB, Cassandra with TWCS) are still superior.

---

## Operational Lessons from Production

### 1. Shard Key is Permanent — Choose Carefully

The most expensive MongoDB operational mistake. Resharding (v5.0+) is possible but slow and I/O intensive:

```
Checklist before sharding a collection:
□ High cardinality (> 1M distinct values)
□ Not monotonically increasing (no ObjectId, no timestamp as ranged key)
□ Included in 80%+ of query filters
□ Distributes writes evenly across key space
□ Supports data locality requirements (zone sharding)
□ Validated with production-representative data distribution
```

### 2. Replication Lag is a Capacity Problem

Replication lag is not a replication bug — it's a signal that secondaries cannot keep up with the primary's write rate:

```
Diagnosis:
  rs.printSecondaryReplicationInfo()
  → "behind the primary by X secs"

Common causes:
  1. Secondary under read load (analytics queries hogging I/O)
     Fix: Dedicate a secondary for reads; limit read preference routing
  2. Index build on secondary
     Fix: Schedule rolling index builds during off-peak
  3. Oplog entry too large (bulk write with large documents)
     Fix: Reduce batch size; increase oplog size
  4. Replication applier thread saturation
     Fix: Increase replWriterThreadCount (default: 16, max: 256)

Critical: If lag > oplog window, secondary must resync:
  db.adminCommand({ resync: 1 })  // Forces full initial sync
  // This takes hours/days for large datasets — prevent it
```

### 3. Backup Strategy: Never Rely Solely on Oplog

| Strategy | RTO | RPO | Cost | When to Use |
|---------|-----|-----|------|------------|
| **mongodump** | Hours | Last dump | Low | Small datasets; non-critical |
| **Atlas backup (continuous)** | Minutes | 1 second | Medium (managed) | Production Atlas deployments |
| **Ops Manager / Cloud Manager backup** | Minutes | Minutes | Medium | Self-hosted production |
| **Filesystem snapshot (EBS, etc.)** | Minutes | Last snapshot (hourly/daily) | Low–Medium | Self-hosted; fast recovery |
| **Delayed replica** | Near-zero (replica is ready) | Up to delay window (e.g., 6h) | +1 replica node | Protecting against human error |

**Point-in-time recovery with oplog**:
```bash
# Restore from snapshot, then replay oplog to specific point in time:
mongorestore --oplogReplay --oplogLimit <timestamp>:<ordinal> /backup/dump
# Example: restore to 2024-06-10T14:30:00 UTC
mongorestore --oplogReplay --oplogLimit 1718026200:1 /backup/dump
```

### 4. Rolling Index Builds for Zero-Downtime Deployments

Never use `createIndex()` directly on a live primary of a large collection. Use rolling index builds:

```bash
# 1. On each secondary (one at a time):
mongosh --eval 'db.collection.createIndex({ field: 1 }, { name: "field_idx" })'

# 2. Step down primary:
mongosh --eval 'rs.stepDown(30)'

# 3. Build index on former primary (now secondary):
mongosh --eval 'db.collection.createIndex({ field: 1 }, { name: "field_idx" })'

# Verify index present on all members:
mongosh --eval 'db.collection.getIndexes().map(i => i.name)'
```

### 5. Schema Migrations: Backward-Compatible Patterns

MongoDB's flexible schema is a feature, but uncontrolled schema drift is a bug. Use version fields:

```javascript
// Add a schema version field to all documents:
// v1 document:
{ _id: ..., schemaVersion: 1, name: "Alice", address: "123 Main St" }

// v2 adds structured address:
{ _id: ..., schemaVersion: 2, name: "Alice",
  address: { street: "123 Main St", city: "NYC", zip: "10001" } }

// Application code handles both versions:
function getCity(user) {
  if (user.schemaVersion >= 2) return user.address.city;
  return parseCityFromString(user.address);  // backward compat
}

// Background migration: update v1 docs to v2 (non-disruptive):
db.users.find({ schemaVersion: 1 }).forEach(doc => {
  db.users.updateOne(
    { _id: doc._id },
    { $set: { address: parseAddress(doc.address), schemaVersion: 2 } }
  );
});
```

---

## FAANG Interview: Full System Design Framing

### Scenario: Design a Product Catalog for 100M Products (E-Commerce)

**Interviewer**: "We need to store 100 million products. Each product has a title, price, category, images, and category-specific attributes (electronics have voltage/watts, clothing has size/color). How do you design the data store?"

**Model Answer**:

> "This is a document store use case — specifically, the flexible attributes make MongoDB the right call over a relational DB. A normalized schema for this would require an EAV table (entity_id, attribute_name, attribute_value) which is notoriously slow for retrieval and hard to index efficiently.
>
> **Schema design**: Each product is a single document with a fixed core schema and a flexible `attributes` subdocument:
> ```javascript
> {
>   _id: ObjectId(),
>   title: "MacBook Pro 16-inch",
>   price: 2499.99,
>   category: "electronics/laptops",
>   images: ["url1", "url2"],
>   attributes: { ram: "32GB", storage: "1TB SSD", voltage: "110-240V" },
>   createdAt: ISODate(),
>   schemaVersion: 1
> }
> ```
>
> **Indexing**: Compound index `{category: 1, price: 1}` for category browsing with price sort. Wildcard index on `attributes.$**` for attribute filtering. Text index on `title` + `description` for basic search (though at scale, I'd push search to Elasticsearch and use MongoDB as the source of truth).
>
> **Sharding**: Shard key `{category: 1, _id: "hashed"}` — category prefix for zone sharding (US catalog on US shards, EU catalog on EU shards for GDPR compliance) with hash suffix for uniform distribution within category.
>
> **Replication**: 3-2 split across two DCs. `w:majority` for product writes (catalog accuracy matters). `readPreference: nearest` for catalog reads (latency-sensitive, minor staleness acceptable).
>
> **Scale**: At 100M products with 2KB average document size, that's ~200GB — fits comfortably in a modest 3-shard cluster. At 1B products (~2TB), I'd scale to 5–10 shards. WiredTiger's snappy compression gets us to ~800GB on disk.
>
> **What I'd NOT use MongoDB for**: Search ranking, recommendation, and inventory updates at order-processing scale. Those go to Elasticsearch (search), a recommendation service backed by a graph store, and a write-optimized inventory service respectively."

### Common Follow-up Questions

| Question | Key Answer |
|---------|-----------|
| "What happens if your primary DC goes down?" | 3-2 split means minority DC (2 nodes) cannot elect a primary — manual failover required. Mitigation: runbook for `rs.reconfig(force:true)`; RTO ~5–15 minutes. If RTO < 30s required, use 3-DC 1-1-1 topology for automatic failover. |
| "How do you handle the 16MB document size limit for products with many images?" | Store image URLs (not binary) in document; actual images in S3/CDN. If metadata exceeds 16MB, use GridFS for the attribute blob or extract to a separate `product_extended_attributes` collection. |
| "Why not Cassandra for this?" | Cassandra requires knowing access patterns at schema design time (one table per query pattern). A product catalog has ad-hoc filtering (any attribute combination). Cassandra doesn't support secondary index queries efficiently; MongoDB's rich index model fits this use case. |
| "How do you handle schema changes when you add a new product category?" | New category just starts writing documents with the new attribute set — no DDL needed. For backward compatibility, use schemaVersion field + lazy migration. For enforced constraints, add `$jsonSchema` validator to the collection. |
| "How would you scale writes if the catalog gets 100K writes/second?" | 100K writes/sec exceeds a single shard's capacity (~50K/sec). Add more shards. With `{category: 1, _id: "hashed"}` sharding, adding shards is online. At extreme scale (500K writes/sec for a flash-sale event), consider a write buffer (Kafka → batch upserts) to smooth the spike. |

---

## Related Files

| File | Topic |
|------|-------|
| [README.md](README.md) | Overview, quick-reference card, use cases, anti-patterns |
| [01-architecture.md](01-architecture.md) | Replica sets, sharding, multi-DC topologies with config examples |
| [02-read-write-path.md](02-read-write-path.md) | Write concern internals, oplog, active-passive failover mechanics |
| [03-trade-offs-and-alternatives.md](03-trade-offs-and-alternatives.md) | vs Cassandra, PostgreSQL, DynamoDB; topology trade-off table |
| [04-tuning-guide.md](04-tuning-guide.md) | Shard key selection guide, write concern tuning, anti-patterns |
