# Azure Cosmos DB — Deep Dive

**AWS Equivalent**: Amazon DynamoDB (primary) + MongoDB Atlas + Apache Cassandra  
**Type**: Globally distributed, multi-model NoSQL database  
**CAP Position**: Tunable — AP (default) to CP (Strong consistency)  
**Consistency Model**: 5 levels from Strong to Eventual (vs DynamoDB's 2)  
**Data Model**: Multi-API: NoSQL (document), MongoDB, Cassandra, Gremlin (graph), Table  
**Write Model**: Multi-region writes supported natively (vs DynamoDB Global Tables eventual-only writes to primary)

**Mental model**: A globally distributed commit log where data is replicated to N regions and exposed through multiple database APIs. You choose your consistency level per read operation — not just per table.

---

## API Choices (Multi-Model)

| API | Wire Protocol | Best For | AWS Equivalent |
|-----|-------------|---------|----------------|
| **NoSQL (Core)** | Cosmos SDK | New cloud-native apps, JSON documents | DynamoDB |
| **MongoDB** | MongoDB wire protocol | Lift-and-shift MongoDB apps | MongoDB Atlas, DocumentDB |
| **Apache Cassandra** | Cassandra wire protocol (CQL) | Cassandra apps migrating to managed | Amazon Keyspaces |
| **Gremlin** | Apache TinkerPop | Graph traversal, relationship queries | Amazon Neptune |
| **Table** | Azure Table Storage protocol | Simple key-value, legacy Table Storage | DynamoDB (simple schema) |

**Rule**: Choose the NoSQL API for all new apps. Use other APIs only for migration from existing databases to avoid rewrites.

---

## Data Model (NoSQL API)

### Hierarchy

```
Azure Subscription
└── Resource Group
    └── Cosmos DB Account (global resource with multiple regions)
        └── Database
            └── Container  ← the unit of throughput provisioning
                └── Items (JSON documents, max 2 MB each)
                    └── Logical Partition (grouped by partition key)
                        └── Physical Partition (auto-managed by Cosmos DB)
```

### Partition Key Design

The partition key is the **most important design decision** — determines data distribution and query performance.

| Criteria | Guidance |
|----------|---------|
| **Cardinality** | High cardinality — many distinct values (userId, orderId, not status) |
| **Distribution** | Even write distribution across partitions. Avoid hot partitions. |
| **Query pattern** | Ideally matches most frequent query filter (queries within a partition are cheap) |
| **Max partition size** | 20 GB logical partition limit (automatic physical partition split) |

**Good partition keys**: `userId`, `tenantId`, `deviceId`, `orderId`  
**Bad partition keys**: `status` (low cardinality), `country` (skewed), `boolean` (only 2 values)

### Synthetic Partition Keys

When no single attribute has high cardinality, combine fields:
```json
{
  "id": "order-12345",
  "partitionKey": "user-u789-2024-01",  ← synthetic: userId + month
  "userId": "u789",
  "month": "2024-01",
  "total": 199.99
}
```

### Item Limits

| Property | Limit |
|----------|-------|
| Max item size | **2 MB** (vs DynamoDB 400 KB — 5× larger) |
| Max partition size | 20 GB logical partition |
| Max properties per item | No hard limit (limited by 2 MB) |
| Max id length | 255 characters |
| Reserved properties | `id`, `_rid`, `_ts`, `_etag`, `_attachments` |

---

## Capacity Model: Request Units (RU/s)

**RU (Request Unit)** = the currency of Cosmos DB throughput. Every operation costs RUs.

### RU Cost Baselines

| Operation | Typical RU Cost |
|-----------|----------------|
| Read 1 KB item by id + partition key | **1 RU** |
| Write 1 KB item | **5 RUs** |
| Replace 1 KB item | **10 RUs** |
| Delete 1 KB item | **5 RUs** |
| Cross-partition query (full scan) | **High — avoid** |
| Same-partition query | **Low — design for this** |

**Rule**: Item reads by `id` + partition key = 1 RU. Everything else costs more. Design queries to use partition key.

### Throughput Modes

| Mode | When to Use | Cost Model | Scaling |
|------|------------|------------|---------|
| **Provisioned (Manual)** | Predictable, steady traffic | Pay for reserved RU/s | Manual scale up/down |
| **Provisioned (Autoscale)** | Variable traffic, need elasticity | Pay for max RU/s set | Scales 10%–100% of max automatically |
| **Serverless** | Dev/test, low-traffic, bursty | Pay per RU consumed | No provisioning needed |

**Mapping to DynamoDB**:

| Cosmos DB | DynamoDB |
|-----------|---------|
| 1 RU read (1 KB) | 0.5 RCU (eventually consistent) or 1 RCU (strongly consistent) |
| 5 RU write (1 KB) | 1 WCU |
| Autoscale (10%–100%) | On-Demand mode |
| Provisioned with manual RU/s | Provisioned with Auto Scaling |
| Serverless | On-Demand (best comparison) |

**Throughput provisioning levels**:
- **Account level**: Shared across all databases and containers (cheapest)
- **Database level**: Shared across containers in that database
- **Container level**: Dedicated to that container (recommended for production)

---

## Consistency Levels (5 levels)

This is Cosmos DB's biggest differentiator over DynamoDB.

```
Strongest                                              Weakest
    │                                                      │
    ▼                                                      ▼
Strong → Bounded Staleness → Session → Consistent Prefix → Eventual
```

| Level | Guarantee | Latency | Use When |
|-------|-----------|---------|---------|
| **Strong** | Linearizable reads — always read latest write | Highest (cross-region round trip) | Financial ledgers, critical inventory |
| **Bounded Staleness** | Reads lag writes by at most K versions or T seconds | High (configurable) | Near real-time dashboards with tolerable lag |
| **Session** | Within a session: reads your own writes | Low (default) | User-facing apps — user sees their own changes |
| **Consistent Prefix** | Reads never see out-of-order writes | Low | Apps that need order guarantees but tolerate lag |
| **Eventual** | No ordering guarantee; highest availability | Lowest | Analytics, leaderboards, non-critical counters |

**DynamoDB comparison**:
- DynamoDB offers only **Eventual** (default) or **Strong** (for point reads) — two levels
- Cosmos DB Session consistency is the sweet spot for most apps — not available in DynamoDB

**Default**: Session consistency. This means within a single client session, a write is immediately visible to subsequent reads from that same session. Cross-session: eventual.

**Cost**: Stronger consistency = higher RU cost and latency. Strong consistency doubles read cost because it must contact quorum replicas.

---

## Global Distribution

### Multi-Region Setup

```
Cosmos DB Account
├── Write Region: East US (primary)
├── Read Region: West Europe (replica)
├── Read Region: Southeast Asia (replica)
└── Failover priority: East US → West Europe → Southeast Asia
```

**Replication**: All data replicated to all regions. Reads from nearest region. Writes go to write region (or all regions with multi-write).

### Multi-Region Writes (Multi-Master)

Both Azure and AWS support multi-region writes, but with important differences:

| Feature | Cosmos DB Multi-Region Writes | DynamoDB Global Tables |
|---------|------------------------------|------------------------|
| Write to any region | Yes | Yes (all regions are write regions) |
| Conflict resolution | Last-Write-Wins (LWW) or custom procedure | Last-Writer-Wins only |
| Consistency with multi-write | Eventual, Session, Consistent Prefix | Eventual only |
| Strong consistency with multi-write | Not supported (fundamental CAP) | Not supported |
| Latency | Write to local region (< 10ms p99 typically) | Write to local region |

**Conflict resolution** in Cosmos DB:
- **Last-Write-Wins (LWW)**: Uses `_ts` timestamp or custom property — default
- **Custom conflict resolution procedure**: JavaScript stored procedure called on conflict — unique to Cosmos DB

### Automatic Failover

- Configured via `failoverPriorities` list
- When primary region is unhealthy, Cosmos DB promotes the next priority region automatically
- RTO: < 5 minutes for automatic failover
- RPO: 0 for Session/Consistent Prefix/Eventual; bounded by staleness window for Bounded Staleness

---

## Indexing

Cosmos DB **indexes all properties by default** — unlike DynamoDB where only primary key is indexed.

### Index Types

| Type | Purpose | Example |
|------|---------|---------|
| **Range index** | Comparison queries (`=`, `>`, `<`, `ORDER BY`) | Default for all scalar properties |
| **Composite index** | Multi-property ORDER BY or multiple filters | Must define explicitly |
| **Spatial index** | Geo-queries (Point, LineString, Polygon) | For location-based queries |

**Composite index example** (required for `ORDER BY` on multiple fields):
```json
{
  "indexingPolicy": {
    "compositeIndexes": [
      [
        { "path": "/lastName", "order": "ascending" },
        { "path": "/age", "order": "descending" }
      ]
    ]
  }
}
```

**Opt-out indexing**: Exclude paths not needed for queries to reduce RU overhead and storage:
```json
{
  "excludedPaths": [{ "path": "/largeTextBlob/*" }]
}
```

---

## Change Feed

Cosmos DB Change Feed is an ordered, persistent log of all changes (inserts + updates, **not deletes** by default in NoSQL API).

**Architecture**:
```
Cosmos DB Container (writes)
         │
         ▼
     Change Feed
    (ordered log)
         │
    ┌────┼──────────────┐
    ▼    ▼              ▼
Azure Fn  Stream      Custom
(trigger) Analytics   Consumer
```

**Primary uses**:
1. **CQRS read model**: Project writes to a read-optimized store
2. **Event Sourcing**: Treat Change Feed as the event stream
3. **Cache invalidation**: Invalidate Azure Cache for Redis on change
4. **Data migration**: Stream data to another store without ETL

**vs DynamoDB Streams**: Both are ordered streams. Change Feed has longer retention (configured up to 7 days); DynamoDB Streams default 24h, max 24h. Change Feed doesn't capture deletes in NoSQL API (DynamoDB Streams does capture deletes via `REMOVE` event type).

---

## Trade-Off Table

| Dimension | Cosmos DB | DynamoDB | MongoDB Atlas | Cassandra |
|-----------|-----------|---------|--------------|-----------|
| **Consistency options** | 5 levels (best) | 2 levels | Read/write concern levels | Tunable (CL per operation) |
| **Multi-region writes** | Yes | Yes (Global Tables) | Yes (Global Clusters) | Yes (multi-DC) |
| **Partition key constraints** | 20 GB per logical partition | 10 GB per partition | Flexible (sharding) | Wide rows, no hard limit |
| **Max item/document size** | 2 MB | 400 KB | 16 MB | No practical limit (row limit) |
| **SQL-like query** | Yes (Cosmos SQL API) | Limited (expressions) | Yes (aggregation pipeline) | CQL (limited) |
| **Schema flexibility** | Fully schemaless | Fully schemaless | Fully schemaless | Schema required (CQL) |
| **Serverless option** | Yes (Cosmos Serverless) | Yes (On-Demand) | Yes (Atlas Serverless) | No |
| **Cost at scale** | High (RU/s model) | High (RCU/WCU model) | Variable | Low (self-hosted) |
| **Vendor lock-in** | High (Cosmos-specific SDK) | High (DynamoDB-specific) | Low (MongoDB compatible) | Low (CQL standard) |
| **Best for** | Azure-native, multi-model, global | AWS-native, single-table design | MongoDB migration, rich queries | Write-heavy, time-series |

**Choose Cosmos DB when**:
- Already on Azure
- Need more than 2 consistency levels (Session is critical for UX)
- Need multi-region writes with custom conflict resolution
- Running multiple database models (document + graph + key-value) on one account
- Migrating existing MongoDB or Cassandra apps (use their native APIs)

**Choose DynamoDB when**:
- Already on AWS
- Single-table design pattern needed
- Maximum simplicity — no API choice paralysis
- Tighter per-operation cost control (RCU/WCU vs RU model)

---

## FAANG Interview Patterns

### Globally Distributed User Profile Service

**Problem**: 500M users globally. Profile reads must be < 10ms p99. Writes must be durable. Users must see their own writes immediately.

**Solution with Cosmos DB**:
```
User writes profile → Cosmos DB (session consistency, multi-region write)
User reads profile in same session → Read from local region, 1 RU, < 5ms
Cross-user reads (admin, friends) → Eventual consistency, local region

Partition key: userId
Regions: East US, West Europe, Southeast Asia (follow user base)
Consistency: Session (default)
Throughput: Autoscale on container (handles viral spikes)
```

**Why not Strong consistency**: Strong requires cross-region round-trip for every read. At 3 regions, that's 100–200ms RTT. Session consistency gives strong guarantees within a user session at local-region latency.

### Multi-Tenant SaaS — Data Isolation

**Pattern**: Partition-per-tenant (logical isolation, shared infrastructure)

```
Container: customer_data
Partition key: tenantId

Item: { "id": "order-123", "partitionKey": "tenant-acme", "data": {...} }
Item: { "id": "order-456", "partitionKey": "tenant-globex", "data": {...} }
```

**RU throttling per tenant**: Use Cosmos DB per-partition throughput controls (Azure Cosmos DB Burst Capacity + dedicated container per premium tenant).

> **FAANG Interview Callout**: "When designing a globally distributed data store, I start with the consistency level decision: Eventual for analytics/leaderboards, Session for user-facing CRUD (users must see their own writes), Strong only for financial ledgers where linearizability is a compliance requirement. Cosmos DB's 5-level consistency model gives me that precision without application-layer workarounds. On AWS, I'd get the same outcome with DynamoDB + ElastiCache for Session semantics, but it's two systems instead of one."
