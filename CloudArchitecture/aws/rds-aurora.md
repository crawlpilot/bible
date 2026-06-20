# AWS RDS & Aurora — Deep Dive

## Overview

RDS is AWS's managed relational database service. Aurora is AWS's cloud-native relational engine — purpose-built to decouple compute from storage, delivering 5× MySQL and 3× PostgreSQL throughput at the same price point.

**Mental model:**
- **RDS** = managed EC2 with a DB engine on top (MySQL, PostgreSQL, Oracle, SQL Server, MariaDB)
- **Aurora** = a distributed storage engine with a MySQL/PostgreSQL-compatible front end

---

## RDS Architecture

### Deployment Options

| Mode | Durability | RTO | RPO | Use case |
|------|-----------|-----|-----|----------|
| Single-AZ | AZ failure = outage | Minutes–hours | Minutes | Dev/test only |
| Multi-AZ (1 standby) | Synchronous replication, AZ-isolated standby | 60–120s failover | ~0 (sync replication) | Production baseline |
| Multi-AZ Cluster (2 readable standbys) | 2 standbys, each in different AZ | <35s | ~0 | High availability + read scale |

### Read Replicas
- Async replication from primary (eventual consistency; replication lag = key metric)
- Up to 5 replicas per RDS instance (MySQL/PostgreSQL)
- Can promote to standalone primary (manual DR)
- Cross-region read replicas: regional read scale + disaster recovery

**Replication lag** is the silent killer in read-replica architectures. Always read from primary for anything requiring consistent state (payment status, inventory check). Route to replica only for analytics, reporting, search suggestions.

---

## Aurora Architecture

### Shared Distributed Storage

```
Compute layer:       [Writer Instance]  [Reader 1]  [Reader 2]
                             ↕               ↕           ↕
Storage layer:  [ AZ-1 ] [ AZ-1 ] [ AZ-2 ] [ AZ-2 ] [ AZ-3 ] [ AZ-3 ]
                  6 copies across 3 AZs, quorum write (4/6), quorum read (3/6)
```

- Storage is **independent of compute** — readers and writer all read from the same shared storage volume
- **No storage replication lag** between writer and readers (readers see writes after quorum commit)
- Aurora storage auto-grows in 10 GB increments, up to 128 TB
- Quorum write (4/6) tolerates: 1 AZ down + 1 additional failure
- Quorum read (3/6) tolerates: 1 AZ down

This is Aurora's core differentiation from RDS Multi-AZ: **readers see committed writes immediately** (no async lag).

### Aurora vs RDS Read Replicas

| Dimension | Aurora Read Replicas | RDS Read Replicas |
|-----------|---------------------|-------------------|
| Replication lag | Near zero (shared storage) | Seconds to minutes |
| Max replicas | 15 | 5 |
| Failover to replica | Automatic, <30s | Manual promotion |
| Cross-region | Aurora Global Database | Manual cross-region replica |
| Replica types | Aurora Replicas (same engine), MySQL binlog replicas | MySQL/PostgreSQL native |

---

## Aurora Serverless v2

- Auto-scales compute in fine-grained increments (0.5 ACU steps, where 1 ACU ≈ 2 GB RAM)
- Min capacity: 0.5 ACU, Max capacity: 256 ACU
- **Does NOT scale to zero** (unlike v1) — minimum 0.5 ACU always running
- Scaling latency: seconds (vs minutes for v1 cold start)
- Works with Multi-AZ, Aurora Global Database, read replicas, RDS Proxy

**When to use:**
- Unpredictable traffic (dev/test environments, SaaS multi-tenant with variable load)
- Want Aurora features without capacity planning
- Cost: you pay per ACU-second — more expensive than provisioned at steady high load

**When to use provisioned instead:**
- Sustained high throughput (e.g., >100 connections/s constantly)
- Consistent load makes provisioned ~2–3× cheaper per transaction

---

## Aurora Global Database

```
Primary Region:  [Writer + Readers] ──── storage replication ──→  [Readers] Secondary Region
                                         < 1s typical lag                    (read-only)
```

- **Replication lag:** <1 second typical (physical, block-level replication — faster than logical)
- **Failover (managed):** 1 secondary becomes new primary, <1 min RPO, ~1 min RTO
- **Failover (manual):** Full failover in <1 minute
- Up to 5 secondary regions
- Reads in secondary region: low-latency local reads (geo-proximity)

**Use cases:** active-passive DR with RPO <1s; global applications where reads are geographically distributed.

**vs DynamoDB Global Tables:** Aurora Global DB is for relational workloads requiring ACID. DynamoDB Global Tables are multi-master but eventually consistent.

---

## RDS Proxy

**Problem:** Lambda, ECS, or EKS with autoscaling opens many short-lived connections to RDS. Each connection consumes ~10 MB of DB memory. 1,000 Lambdas × 10 MB = 10 GB just for connections — saturates the DB before query load does.

**Solution:** RDS Proxy sits between application and DB, maintains a warm connection pool, and multiplexes application connections onto a smaller pool of DB connections.

```
1,000 Lambda connections → [RDS Proxy: 50 pooled DB connections] → RDS/Aurora
```

- Reduces connection count to DB by 87%+ (observed at AWS)
- Automatic failover (proxy maintains connection to new primary after failover)
- Supports IAM authentication and Secrets Manager for credentials
- Supported engines: MySQL, PostgreSQL, MariaDB, SQL Server (limited)

**Proxy adds ~1–2ms latency** — worth it whenever connection count is the bottleneck.

---

## Aurora DSQL (2024 — Distributed SQL)

Aurora DSQL is a new serverless, distributed SQL database designed for global active-active deployments:
- Full PostgreSQL compatibility
- No single writer — multi-master across regions
- Optimistic concurrency control (no distributed locks)
- Scales compute independently, storage is distributed automatically
- Target use case: globally distributed OLTP with strong consistency requirements

**Status (2024–2025):** Preview/GA in select regions. Not yet the default choice — Aurora Serverless v2 + Global Database covers most use cases. Watch this space.

---

## Performance Insights & Monitoring

**Performance Insights:** Visualizes DB load by SQL query, wait event, user, host. The primary tool for finding slow queries and lock contention.

Key CloudWatch metrics:

| Metric | Alarm threshold | Meaning |
|--------|-----------------|---------|
| `CPUUtilization` | >80% sustained | Scale up compute |
| `DatabaseConnections` | >80% max_connections | Use RDS Proxy |
| `ReplicaLag` | >1,000ms | Replica is falling behind |
| `FreeStorageSpace` | <20% | Expand or enable auto-growth |
| `ReadLatency` / `WriteLatency` | >20ms | Storage or query issue |
| `Deadlocks` | Spike | Transaction design issue |

**Enhanced Monitoring:** OS-level metrics (1s granularity) — shows CPU steal, memory, network per process. Useful for noisy-neighbor and host-level diagnosis.

---

## Parameter Groups & Tuning

Key PostgreSQL parameters (Aurora PG):

| Parameter | Default | Recommended (production) |
|-----------|---------|--------------------------|
| `max_connections` | 100 | Use formula: `LEAST({DBInstanceClassMemory/9531392}, 5000)` |
| `shared_buffers` | 128MB | 25% of RAM (Aurora manages this automatically) |
| `work_mem` | 4MB | 16–64 MB (monitor `sort_disk` usage) |
| `wal_level` | replica | logical (for logical replication) |
| `log_min_duration_statement` | -1 (off) | 1000 (log slow queries >1s) |

Aurora manages many parameters automatically. Focus tuning effort on `work_mem`, connection limits, and query plan via `pg_stat_statements`.

---

## Blue/Green Deployments (RDS)

Native RDS feature for zero-downtime schema changes and engine upgrades:
1. AWS creates a **green** (staging) environment, pre-populated from the blue (production) snapshot
2. You apply migrations, upgrades to green
3. Test green thoroughly
4. **Switch over** — AWS temporarily locks writes to blue, waits for green to catch up, then redirects traffic
5. Switchover window: 1 minute typical

Blue/green eliminates the risk of applying migrations directly to production. The cost is running two environments for the validation period.

---

## Backup & Recovery

| Feature | Aurora | RDS |
|---------|--------|-----|
| Automated backup | 1–35 days retention | 0–35 days |
| Backup window | Continuous (no I/O impact on Aurora) | Daily snapshot (brief I/O impact) |
| PITR | To any second within retention period | To any 5-minute interval |
| Manual snapshots | Unlimited, retained indefinitely | Unlimited |
| Cross-region copy | Yes | Yes |
| Backtrack | Yes (Aurora only) — rewind DB in-place to past timestamp | No |

**Aurora Backtrack:** Rewind to a specific timestamp without restoring a snapshot — much faster (seconds). Useful for accidentally dropped tables. Max 72-hour backtrack window.

---

## Connection Management Best Practices

```
Lambda/ECS autoscaling → RDS Proxy → Aurora cluster

Application code:
  - Use connection pool (PgBouncer or RDS Proxy)
  - Set connection_timeout (fail fast if pool exhausted)
  - Set statement_timeout to prevent runaway queries
  - Explicitly close connections in finally blocks
  - Use read replicas for read-heavy paths
```

**Max connections guideline:**
```
Aurora PostgreSQL max_connections ≈ instance_memory_GB × 100
  r6g.large (16 GB) → ~1,600 max connections
  With RDS Proxy: proxy holds 1,600 DB connections, app sees 10,000+ virtual connections
```

---

## RDS vs Aurora vs DynamoDB — Decision Matrix

| Requirement | Choice | Reason |
|-------------|--------|--------|
| Ad-hoc SQL queries, reporting | RDS or Aurora | Full SQL |
| ACID transactions across 10+ tables | RDS or Aurora | DynamoDB transactions limited to 100 items |
| Simple key lookups, 100k+ RPS | DynamoDB | SQL at that scale requires sharding complexity |
| Multi-region active-active | DynamoDB Global Tables or Aurora DSQL | Aurora Global DB is active-passive |
| Variable load, want auto-scaling | Aurora Serverless v2 | No capacity planning |
| Predictable high load, cost-sensitive | Aurora Provisioned | 2-3× cheaper than Serverless at scale |
| Legacy app, exact MySQL/PG compatibility | RDS | Aurora is mostly compatible but edge cases exist |
| Very large OLAP queries | Redshift | RDS is OLTP-optimized |

---

## FAANG Interview Callouts

**"How does Aurora differ from RDS internally?"**
→ Aurora decouples compute from storage. The storage layer is a distributed, quorum-based system across 6 copies in 3 AZs. Readers connect to the same storage volume as the writer — no async replication lag. RDS Multi-AZ replicates the entire DB volume synchronously to a standby using block-level mirroring.

**"Design a payment system that handles 50k TPS with ACID guarantees"**
→ Aurora Provisioned (PostgreSQL), r6g.8xlarge or larger. RDS Proxy for connection pooling. Read replicas for ledger-read paths. Partition by account ID if single instance can't handle writes. Consider Aurora DSQL for global multi-region writes.

**"How do you do zero-downtime schema migrations on a live Aurora database?"**
→ Blue/Green deployment for major changes. For small changes: online schema change tools (gh-ost, pt-online-schema-change). For adding columns: PostgreSQL supports `ADD COLUMN NOT NULL DEFAULT` without table lock in PG 11+.

**"Your Aurora instance is getting thousands of Lambda connections and slowing down — what do you do?"**
→ Add RDS Proxy. Proxy maintains a warm pool of DB connections (e.g., 200) and multiplexes the Lambda connections onto it. Cuts DB connection overhead by 90%+ and adds ~1–2ms latency (acceptable trade-off).

**"RDS Multi-AZ vs Aurora read replicas — when do you use which?"**
→ Multi-AZ is for HA — standby is not readable, just for failover. Aurora replicas serve live reads AND act as failover targets. Use Aurora replicas when you need both read scaling and HA. Use RDS Multi-AZ when you just need basic HA for a non-Aurora engine.
