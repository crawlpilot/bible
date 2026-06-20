# AWS DynamoDB — Deep Dive

## Overview

DynamoDB is a fully managed, serverless, key-value + document NoSQL database. It delivers single-digit millisecond latency at any scale, with automatic multi-AZ replication and no schema migrations. Designed at Amazon for the shopping cart — every FAANG interview involving high-throughput, low-latency reads/writes eventually lands here.

**Mental model:** A distributed hash table partitioned on a primary key, with optional sorted secondary structures. Everything is optimized for key-based access; scans are the enemy.

---

## Data Model

### Primary Key Types

| Type | Composition | Use when |
|------|-------------|----------|
| **Simple (hash)** | Partition key only | Lookup by a single unique identifier |
| **Composite (hash + range)** | Partition key + sort key | One-to-many relationships, range queries |

- **Partition key** determines the physical partition. Must distribute evenly — a hot partition key is the #1 DynamoDB anti-pattern.
- **Sort key** enables `begins_with`, `between`, `<`, `>` queries within a partition.

### Item Limits
- Max item size: **400 KB**
- Max partition throughput: **3,000 RCUs or 1,000 WCUs** per partition (hard limit — even with on-demand mode)
- A single partition holds up to **10 GB** of data

---

## Capacity Modes

| Mode | When to use | Cost model |
|------|-------------|------------|
| **Provisioned** (with Auto Scaling) | Predictable, sustained traffic | Pay for capacity reserved (under-provisioned → throttle) |
| **On-Demand** | Spiky, unpredictable; new tables | Pay per request, 2–3× more expensive at steady state |

**Rule:** Start on-demand during development/early growth. Switch to provisioned + Auto Scaling once traffic is predictable (P95 traffic pattern stable for 2+ weeks).

### Read Capacity Units (RCU)
- 1 RCU = 1 **strongly consistent** read of item ≤ 4 KB/s
- 1 RCU = 2 **eventually consistent** reads of item ≤ 4 KB/s
- Transactional reads: 2 RCUs per 4 KB

### Write Capacity Units (WCU)
- 1 WCU = 1 write of item ≤ 1 KB/s
- Transactional writes: 2 WCUs per 1 KB

---

## Indexes

### Local Secondary Index (LSI)
- **Same partition key**, different sort key
- Must be defined at table creation — cannot add later
- Shares throughput with base table
- Max 5 per table
- Use when: you need to sort the same partition by a different attribute

### Global Secondary Index (GSI)
- **Different partition key and/or sort key** — allows access patterns across partitions
- Can be added/removed after table creation
- Has its own throughput (provisioned separately)
- Eventually consistent reads only
- Max 20 per table (soft limit)
- Use when: you need to query on a non-primary-key attribute

**GSI anti-pattern:** writing heavily to a GSI with a sparse attribute creates a hot GSI partition.

---

## Single-Table Design

The FAANG approach: store **multiple entity types in one table**. Access patterns drive the key structure, not the data model.

```
PK              SK                  Attributes
USER#u123       PROFILE             name, email, created_at
USER#u123       ORDER#o456          status, total, items
USER#u123       ORDER#o789          status, total, items
ORDER#o456      ITEM#prod-1         qty, price
```

Benefits:
- Single request for hierarchical data (parent + children in one query by partition)
- No JOINs — all related data co-located
- Eliminates hot key issues with careful PK design

Drawbacks:
- Complex key schema — requires upfront access pattern analysis
- Difficult to query across entity types without a GSI

**Tool:** NoSQL Workbench for DynamoDB — visualize and model access patterns.

---

## Hot Partition Mitigation

### Write Sharding
```
Instead of PK = "PRODUCT#p1"
Use:          PK = "PRODUCT#p1#SHARD#" + random(1..10)

Reads: scatter-gather across 10 shards and merge
```

### Time-Series Partitioning
```
PK = "EVENTS#2026-06"  ← one partition per month
SK = timestamp#uuid
```
- Avoids hot write partition (current month takes all writes)
- Cold partitions are naturally archived

### Write-Sharding with Suffix
For counters / leaderboards: use DynamoDB Streams + Lambda aggregator pattern rather than atomic counter on one item.

---

## DynamoDB Streams

- Ordered, time-limited (24h) changelog of item changes
- Events: `INSERT`, `MODIFY`, `REMOVE`
- Image types: `NEW_IMAGE`, `OLD_IMAGE`, `NEW_AND_OLD_IMAGES`, `KEYS_ONLY`
- Consumed by Lambda via Event Source Mapping (one shard = one Lambda concurrent execution)

**Use cases:** CDC (change data capture) → feed to OpenSearch, trigger downstream workflows, maintain aggregates, replicate to read models (CQRS).

---

## DynamoDB Accelerator (DAX)

- In-memory cache cluster (compatible with DynamoDB API), microsecond reads
- Write-through: writes go to DynamoDB, cache invalidated
- Does **not** help with write-heavy workloads
- Ideal for read-heavy, latency-sensitive: product catalog, leaderboard reads

**DAX vs ElastiCache for DynamoDB:**

| | DAX | ElastiCache |
|--|-----|-------------|
| API compatibility | DynamoDB SDK drop-in | Custom caching logic required |
| Cache invalidation | Automatic (TTL per item) | Manual or TTL |
| Latency | Microseconds | Sub-millisecond |
| Complexity | Zero | Requires cache management code |

Use DAX when you can't change the application code. ElastiCache when you need more control or share the cache across services.

---

## Global Tables

- Multi-region, multi-master replication
- Eventual consistency across regions (~1s typical replication lag)
- Last-writer-wins conflict resolution (by `_last_updated_at` timestamp)
- **Use case:** active-active multi-region; disaster recovery with RPO ~1s; geo-proximity reads

**Conflict resolution:** DynamoDB uses wall-clock timestamps — if two regions write to the same item concurrently, the write with the higher timestamp wins. Design writes to be idempotent.

---

## Transactions

```python
dynamodb.transact_write(
    TransactItems=[
        {"Put": {"TableName": "Orders", "Item": {...}}},
        {"Update": {"TableName": "Inventory", "Key": {...}, "ConditionExpression": "#qty > :needed"}},
    ]
)
```

- Up to 100 items per transaction (across multiple tables)
- Costs 2 WCUs per item (vs 1 WCU for regular write)
- Atomic, isolated (uses 2PC-like protocol internally)
- **Not a replacement for distributed sagas** — transactions span only DynamoDB

---

## TTL (Time-To-Live)

- Set a Unix timestamp attribute on items; DynamoDB deletes expired items within 48h (typically faster)
- Deletion is free (doesn't consume WCUs)
- Deleted items appear in Streams with `REMOVE` marker — can trigger cleanup logic in Lambda

---

## Conditional Writes & Optimistic Locking

```python
# Only update if version matches (optimistic lock)
table.update_item(
    Key={"pk": "USER#u1"},
    UpdateExpression="SET #v = :new_v, balance = :balance",
    ConditionExpression="#v = :old_v",
    ExpressionAttributeNames={"#v": "version"},
    ExpressionAttributeValues={":old_v": 5, ":new_v": 6, ":balance": 1000},
)
```

If condition fails: `ConditionalCheckFailedException` → application retries. This is how DynamoDB achieves optimistic concurrency without locks.

---

## Backup & Recovery

| Type | RPO | RTO | Cost |
|------|-----|-----|------|
| On-demand backup | Point-in-time | Minutes | $0.10/GB-month |
| PITR (35-day window) | 1 second | Minutes | $0.20/GB-month |
| Cross-region copy | ~minutes lag | Minutes | Transfer + storage |

PITR is the safety net — always enable it on production tables. It does not affect table performance.

---

## Observability

Key CloudWatch metrics to alarm on:

| Metric | Threshold | Meaning |
|--------|-----------|---------|
| `ThrottledRequests` | > 0 | Capacity exhausted; urgent |
| `SystemErrors` | > 0 | AWS-side issue |
| `ConsumedReadCapacityUnits` | > 80% provisioned | Scale up |
| `SuccessfulRequestLatency` | P99 > 10ms | Hot partition or large item |
| `TransactionConflict` | Spike | Contention on same item |

---

## DynamoDB vs Alternatives

| Dimension | DynamoDB | Cassandra (self-managed) | Redis | PostgreSQL |
|-----------|----------|--------------------------|-------|------------|
| Ops overhead | None | High | Low-Medium | Medium |
| Latency | Single-digit ms | Single-digit ms | Sub-ms | 5–50ms |
| Query flexibility | Low (key-based) | Medium | Low | High (SQL) |
| Scale ceiling | Unlimited | Unlimited | ~TB (RAM-bound) | Hard to scale writes |
| Cost (high scale) | Can be expensive | Cheaper at massive scale | Cheap | Expensive (large instances) |
| Multi-region | Built-in (Global Tables) | Manual (multi-DC) | Manual (Active-Active) | Complex |
| Transactions | Yes (limited) | LWT (slow) | Lua scripts | Full ACID |

**Choose DynamoDB when:** access patterns are known and key-based, you need zero ops at massive scale, multi-region replication is needed, and you can tolerate limited query flexibility.

**Choose Cassandra when:** you need more control, can manage ops, and cost at petabyte scale matters more than ops simplicity.

---

## FAANG Interview Callouts

**"Design Twitter's home timeline"**
→ Fan-out on write: store timeline items keyed by `USER#uid / TWEET#timestamp`. DynamoDB with GSI on `timestamp` for range queries. Hot user problem: hybrid fan-out (push for normal users, pull for celebrities).

**"How do you handle a hot partition in DynamoDB?"**
→ Write sharding: add a random suffix (1–N) to PK, scatter-gather on reads. For time-series: shard by time window. For counters: use Streams + Lambda aggregator instead of incrementing one item.

**"DynamoDB vs RDS — when do you pick which?"**
→ DynamoDB: known key-based access patterns, massive scale, multi-region, ops simplicity. RDS/Aurora: ad hoc queries, complex JOINs, strong ACID across many entities, reporting.

**"How do you design a leaderboard with DynamoDB?"**
→ Naive: single PK with score attribute — hot partition. Better: ElastiCache Redis Sorted Set for real-time leaderboard; DynamoDB as source of truth. For non-real-time: DynamoDB Streams → Lambda → aggregate table.

**"How do you implement optimistic locking in DynamoDB?"**
→ Store `version` number on each item. Conditional write: `ConditionExpression="version = :expected"`. On `ConditionalCheckFailedException`, read the latest state and retry.

**"What's single-table design and when would you NOT use it?"**
→ Single-table collocates related entities for efficient access. Don't use it when: access patterns are unknown/evolving (adds schema rigidity), team lacks DynamoDB expertise (high cognitive cost), or you need complex analytics (use a separate data warehouse instead).
