# Azure SQL Databases — Azure SQL, Hyperscale, Managed Instance, PostgreSQL

**AWS Equivalents**:  
- Azure SQL Database → Amazon RDS for SQL Server / Amazon Aurora  
- Azure SQL Hyperscale → Amazon Aurora (auto-storage scaling comparison)  
- Azure SQL Managed Instance → Amazon RDS Custom for SQL Server  
- Azure Database for PostgreSQL (Flexible Server) → Amazon RDS for PostgreSQL / Aurora PostgreSQL  

**Mental model**: Azure SQL has four deployment models forming a spectrum from "fully managed SaaS DB" to "SQL Server in a box on your VNet." Unlike AWS where RDS and Aurora are separate services, Azure uses "service tiers" within Azure SQL Database to achieve the same range.

---

## The Azure SQL Family

```
Fully Managed (PaaS)                                    Full Control
────────────────────────────────────────────────────────────────────►
Azure SQL Database    Azure SQL Database    Azure SQL         SQL Server
(General Purpose /    (Hyperscale)          Managed Instance  on Azure VM
 Business Critical)
                                                              ▲
                                              Most compatible with
                                              on-prem SQL Server
```

---

## 1. Azure SQL Database

### Service Tiers (Purchasing Models)

**DTU model** (older, simpler, bundled CPU+IO+Storage):

| Tier | DTUs | Storage | Use Case |
|------|------|---------|---------|
| Basic | 5 | 2 GB | Dev/test, very small |
| Standard S0–S12 | 10–3,000 | 250 GB – 1 TB | Most workloads |
| Premium P1–P15 | 125–4,000 | 500 GB – 4 TB | High I/O, In-Memory OLTP |

**vCore model** (recommended, separate compute + storage, maps to AWS RDS model):

| Tier | vCores | Memory | Storage | IOPS | Use Case |
|------|--------|--------|---------|------|---------|
| **General Purpose** | 2–80 | 10–408 GB | 32 GB – 4 TB | Max 18,000 | Standard workloads |
| **Business Critical** | 2–80 | 10.2–407 GB | 32 GB – 4 TB | 200,000+ IOPS | High IOPS, always-on read replica |
| **Hyperscale** | 2–80 | 10.2–408 GB | Up to 100 TB | 200,000+ IOPS | Unpredictable growth, large data |

### Azure SQL Database vs Amazon RDS (SQL Server)

| Feature | Azure SQL Database | RDS for SQL Server |
|---------|-------------------|-------------------|
| Fully managed | Yes | Yes |
| Max storage | 4 TB (General Purpose), 100 TB (Hyperscale) | 64 TB (io2) |
| Read replicas | 1 (Business Critical, included free) | Up to 5 read replicas |
| HA mechanism | AlwaysOn Availability Groups (hidden) | Multi-AZ (sync standby) |
| Max IOPS | 200,000+ (Business Critical, local SSD) | 256,000 io2 |
| Serverless compute | Yes (auto-pause when idle) | No |
| Elastic pools | Yes (share DTUs/vCores across DBs) | No equivalent |
| Active geo-replication | Yes (cross-region read replicas) | Read Replica (cross-region) |
| Auto-failover groups | Yes (automatic failover to secondary region) | Multi-AZ (same region), RR is manual failover |
| Licensing | License Included or Azure Hybrid Benefit (BYOL) | License Included or BYOL |
| PaaS only | Yes (no OS access) | Mostly (RDS Custom for OS access) |

### Serverless Compute Tier

Azure SQL Database can auto-pause when inactive and auto-resume on first query:

```
Active (computing)  ──────► Idle (auto-pause after X minutes)
                                          │
First connection ◄────── Auto-resume (1–30 second cold start)
```

**Cost**: Pay only for compute when active. Storage always billed. Best for dev/test and intermittent workloads.

**AWS equivalent**: No direct equivalent in RDS. Aurora Serverless v2 scales compute down but never stops completely (min 0.5 ACUs).

### Elastic Pools

Multiple databases share a pool of vCores/DTUs. Cost-efficient for multi-tenant SaaS:

```
Elastic Pool: 8 vCores (General Purpose)
  ├── DB: tenant-acme    (uses 1–3 vCores, peaks at different times)
  ├── DB: tenant-globex  (uses 0.5–2 vCores)
  └── DB: tenant-initech (uses 0.5–1 vCores)

Without pool: 3 × 2 vCores = 6 vCores minimum
With pool:   8 vCores shared (assuming peak times don't overlap)
```

**AWS equivalent**: No direct equivalent. Approximation: Aurora Serverless v2 per-database can scale independently but doesn't share a capacity pool.

---

## 2. Azure SQL Hyperscale

### What It Is

Distributed SQL architecture that decouples compute from storage, enabling:
- Storage up to **100 TB** (grows automatically, no pre-provisioning)
- **Sub-second scaling** of storage
- **Named replicas**: Up to 30 read replicas with independent compute scaling
- **Fast backups and restores**: Snapshot-based, sub-minute regardless of DB size

### Architecture

```
Primary Compute Replica
         │
         ▼
     Log Service (distributed transaction log)
         │
    ┌────┼────────────┐
    ▼    ▼            ▼
Page   Page         Page
Server Server       Server
(shard) (shard)    (shard)
    │
    └── Azure Storage (underlying data, auto-growing)
```

- Compute replicas share page servers (data cached at page server layer)
- Adding a new replica: copy page server references (near-instant) vs full data copy on traditional HA

### Hyperscale vs Aurora (the closest comparison)

| Feature | Azure SQL Hyperscale | Amazon Aurora |
|---------|---------------------|---------------|
| Max storage | **100 TB** | 128 TB |
| Auto storage scaling | Yes | Yes (10 GB → 128 TB) |
| Storage IOPS | Decoupled (scales independently) | Up to 256,000 IOPS |
| Read replicas | Up to 30 (named replicas) | Up to 15 Aurora Replicas |
| Replica lag | < 1 second typical | < 100ms (Aurora replication) |
| Backup speed | Near-instant (snapshot) | Near-instant (incremental) |
| Restore speed | Near-instant (point-in-time) | Near-instant (PITR) |
| Engine | SQL Server only | MySQL or PostgreSQL |
| Serverless | No | Aurora Serverless v2 |
| Global Database | Via auto-failover groups | Aurora Global Database (< 1 second RPO) |

**Hyperscale advantage**: 30 read replicas (Aurora max is 15). Read-heavy analytical workloads can distribute across more replicas.
**Aurora advantage**: Multi-engine (MySQL + PostgreSQL); Aurora Serverless v2; Global Database with sub-second RPO.

---

## 3. Azure SQL Managed Instance

### What It Is

Full SQL Server engine deployed into your VNet. Near-100% compatibility with on-premises SQL Server. The RDS Custom for SQL Server equivalent, but more fully managed.

**Key difference from Azure SQL Database**: Managed Instance gives you SQL Server Agent, Cross-database queries, linked servers, Service Broker, CLR assemblies — features not available in Azure SQL Database.

### Compatibility Features

| Feature | Azure SQL Database | SQL Managed Instance |
|---------|-------------------|---------------------|
| SQL Server Agent jobs | No | **Yes** |
| Cross-database queries | No | **Yes** |
| Linked Servers | No | **Yes** |
| Service Broker | No | **Yes** |
| CLR assemblies | Limited | **Yes** |
| Database Mail | No | **Yes** |
| SSAS / SSRS / SSIS | No | Partial |
| Windows auth (Kerberos) | Limited | **Yes** |
| Transparent Data Encryption | Yes | Yes |

### vs RDS Custom for SQL Server

| Feature | SQL Managed Instance | RDS Custom for SQL Server |
|---------|--------------------|--------------------------| 
| OS access | No | **Yes** |
| SQL Server compatibility | Near-100% | 100% (full SQL Server) |
| VNet deployment | **Yes** (built-in) | VPC (needs manual config) |
| Automatic patching | Yes (managed) | Partial (you control maintenance) |
| Built-in HA | Yes (AlwaysOn) | Multi-AZ option |
| Migration from on-prem | Database Migration Service | DMS or backup/restore |
| Use case | Lift-and-shift PaaS | Maximum compatibility + OS control |

---

## 4. Azure Database for PostgreSQL — Flexible Server

### What It Is

Fully managed PostgreSQL as a service. Two generations exist; Flexible Server is current (Single Server is deprecated).

**Supported versions**: PostgreSQL 11, 12, 13, 14, 15, 16

### Compute Tiers

| Tier | vCores | Memory | IOPS | Use Case |
|------|--------|--------|------|---------|
| **Burstable** (B-series) | 1–2 | 2–8 GB | Up to 2,400 | Dev/test, intermittent |
| **General Purpose** (D-series) | 2–96 | 8–672 GB | Up to 80,000 | Most workloads |
| **Memory Optimized** (E-series) | 2–96 | 16–672 GB | Up to 80,000 | In-memory caching, analytics |

### Flexible Server vs Aurora PostgreSQL

| Feature | Azure DB for PostgreSQL (Flexible) | Amazon Aurora PostgreSQL |
|---------|----------------------------------|--------------------------|
| Max vCPUs | 96 | 128 |
| Max memory | 672 GB | 1,020 GB |
| Max storage | 32 TB | 128 TB |
| Read replicas | Up to 5 | Up to 15 Aurora Replicas |
| Replica lag | Seconds (streaming replication) | < 100ms (Aurora replication) |
| Failover time | 60–120 seconds | < 30 seconds (Aurora) |
| Standby (HA) | Same-zone or zone-redundant standby | Multi-AZ Aurora cluster |
| Serverless | No | Aurora Serverless v2 |
| Pgvector (AI/ML) | Yes | Yes |
| Citus (distributed) | Azure Cosmos DB for PostgreSQL (Citus) | No native; use Aurora + Sharding |
| Connection pooling | PgBouncer built-in | No (use RDS Proxy) |
| Cost at 8 vCPU | ~$600/month | ~$800/month (On-Demand) |

**Azure advantage**: PgBouncer connection pooling built-in (RDS requires RDS Proxy at extra cost). Flexible Server allows maintenance windows with zero-downtime patching.

**Aurora advantage**: Much faster failover (< 30 seconds vs 60–120s), better read replica replication lag, Aurora Serverless v2.

### Connection Pooling Built-In

```
Application → PgBouncer (built-in, port 6432) → PostgreSQL
                    │
              Pool modes:
              - Session pooling (default)
              - Transaction pooling (recommended for microservices)
              - Statement pooling
```

**AWS equivalent**: Amazon RDS Proxy ($0.015/vCPU/hour extra cost). Azure provides this free in Flexible Server.

---

## Tier Selection Decision Framework

```
Need SQL Server compatibility?
  └── Yes → Need on-prem SQL Server features (Agent, CLR, linked servers)?
      ├── Yes → SQL Managed Instance (PaaS) or SQL on Azure VM (IaaS)
      └── No → Azure SQL Database
          └── Expected data > 4 TB or need 30 read replicas? → Hyperscale

Need PostgreSQL?
  └── Flexible Server
      └── Need distributed/sharding at massive scale? → Azure Cosmos DB for PostgreSQL (Citus)

Need multi-engine or MySQL?
  └── Azure Database for MySQL Flexible Server (same pattern as PostgreSQL)
```

---

## Key Numbers for Interviews

| Service | Number | Notes |
|---------|--------|-------|
| Azure SQL DB max storage (General Purpose) | 4 TB | vCore model |
| Azure SQL Hyperscale max storage | **100 TB** | Auto-growing |
| Hyperscale max named replicas | **30** | vs Aurora's 15 |
| SQL Managed Instance max storage | 16 TB | General Purpose |
| Azure DB for PostgreSQL max vCPUs | 96 vCPUs | Memory Optimized |
| PostgreSQL Flexible Server max storage | 32 TB | |
| Azure SQL auto-failover RTO | < 30 seconds (Business Critical) | Premium SSD local replica |
| Elastic Pool max databases | 500 per pool | Standard tier |
| Azure Hybrid Benefit savings (SQL) | Up to **85%** | vs license-included pricing |

---

> **FAANG Interview Callout**: "When choosing between Azure SQL tiers, I ask three questions: How big will the data get? (< 4 TB = General Purpose, > 4 TB = Hyperscale which auto-scales to 100 TB), Do I need SQL Server-specific features like SQL Agent or cross-database queries? (Yes = Managed Instance), and Is this a migration from on-prem? (If yes, Managed Instance for maximum compat, then optionally modernize to SQL Database later). The Azure Hybrid Benefit is the economic argument that closes enterprise deals — an organization running SQL Server with Software Assurance pays 15 cents on the dollar for Azure SQL compared to RDS SQL Server license-included pricing. On the PostgreSQL side, the built-in PgBouncer in Flexible Server is underappreciated — it means you don't pay the extra $0.015/vCPU/hour for RDS Proxy equivalent functionality."
