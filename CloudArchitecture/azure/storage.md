# Azure Storage — Blob Storage, ADLS Gen2, Azure Files, Azure Queues

**AWS Equivalents**:  
- Azure Blob Storage → Amazon S3  
- Azure Data Lake Storage Gen2 (ADLS) → Amazon S3 + AWS Lake Formation  
- Azure Files → Amazon EFS / Amazon FSx for Windows File Server  
- Azure Queue Storage → Amazon SQS (basic)  
- Azure Table Storage → Amazon DynamoDB (basic key-value)  

**Mental model**: An Azure Storage Account is a namespace containing multiple storage services: Blob, Files, Queues, Tables, and Data Lake. Unlike AWS where S3 is completely separate from EFS, in Azure they share an account (and billing). ADLS Gen2 is Blob Storage with hierarchical namespace enabled — same underlying service, different capabilities.

---

## Storage Account Overview

```
Azure Storage Account (region-scoped)
├── Blob Storage         ← objects/files (S3 equivalent)
│   ├── Container A (bucket)
│   └── Container B
├── Data Lake (ADLS Gen2) ← hierarchical namespace mode
│   ├── Filesystem A
│   └── Filesystem B
├── Azure Files          ← SMB/NFS shares (EFS/FSx equivalent)
│   ├── Share A (SMB)
│   └── Share B (NFS)
├── Azure Queue Storage  ← simple message queue (SQS basic)
└── Azure Table Storage  ← NoSQL key-value (DynamoDB basic)
```

**Storage Account types**:

| Type | Supported services | Performance |
|------|-------------------|-------------|
| **General-purpose v2** (GPv2) | All services | Standard or Premium |
| **Block Blob Storage** | Blob only | Premium SSD (low latency) |
| **Azure Files Storage** | Files only | Premium SSD (low latency) |

---

## 1. Azure Blob Storage

### What It Is

Object storage for any unstructured data. S3 equivalent.

### Access Tiers

| Tier | Use Case | Latency | Storage Cost | Retrieval Cost |
|------|---------|---------|--------------|----------------|
| **Hot** | Frequently accessed | Milliseconds | Highest | Lowest |
| **Cool** | Infrequently accessed (30-day min) | Milliseconds | Lower | Higher |
| **Cold** | Rarely accessed (90-day min) | Milliseconds | Even lower | Even higher |
| **Archive** | Long-term retention (180-day min) | Hours (rehydration) | Lowest | Highest + rehydration fee |

**vs S3 storage classes**:

| Azure Blob | Amazon S3 | Storage Cost (approx) | Access Pattern |
|-----------|----------|----------------------|----------------|
| Hot | Standard | ~$0.018/GB | Frequent |
| Cool | Standard-IA | ~$0.01/GB | Infrequent (30-day min) |
| Cold | S3 Glacier Instant Retrieval | ~$0.0045/GB | Rare but instant |
| Archive (rehydrate hours) | S3 Glacier Flexible Retrieval | ~$0.00099/GB | Archival (hours to restore) |
| — | S3 Glacier Deep Archive | ~$0.00012/GB | Deepest archival (12hr) |

**Lifecycle management**: Auto-transition blobs between tiers based on last access time or age (same as S3 lifecycle policies).

### Blob Types

| Type | Use Case | Notes |
|------|---------|-------|
| **Block Blob** | Files, media, documents, backups | Default; max 190.7 TB (blocks up to 100 MB each) |
| **Append Blob** | Log files, streaming data | Append-only; max 195 GB |
| **Page Blob** | Azure VM disks (VHD) | Random read/write; max 8 TB |

**S3 has only one object type** (no append-only or random-access distinction). Azure's type system maps to specific use cases.

### Redundancy Options

| Option | Description | Durability | Regions | AWS Equivalent |
|--------|-------------|-----------|---------|----------------|
| **LRS** (Locally Redundant) | 3 copies in one datacenter | 11 9s | 1 region | S3 (single AZ — no equivalent, S3 always multi-AZ) |
| **ZRS** (Zone Redundant) | 3 copies across 3 AZs | 12 9s | 1 region | S3 Standard (cross-AZ by default) |
| **GRS** (Geo-Redundant) | LRS + async copy to secondary region | 16 9s | 2 regions | S3 Cross-Region Replication (CRR) |
| **GZRS** (Geo-Zone Redundant) | ZRS + async copy to secondary | 16 9s | 2 regions | S3 CRR with multi-AZ (no single equivalent) |
| **RA-GRS** | GRS + read access to secondary | 16 9s | 2 regions | S3 CRR with cross-region read access |

**Default**: LRS (cheapest). Production recommendation: ZRS for regional HA, GZRS for DR.

### Azure Blob vs Amazon S3

| Feature | Azure Blob Storage | Amazon S3 |
|---------|-------------------|-----------|
| Max object size | **190.7 TB** | 5 TB |
| Multipart upload | Yes (block upload) | Yes (multipart) |
| Versioning | Yes | Yes |
| Object lock (WORM) | Immutability policies | S3 Object Lock |
| Server-side encryption | AES-256 (default, free) | SSE-S3 (default, free) |
| Customer-managed keys | Key Vault (CMK) | KMS (SSE-KMS) |
| Access control | RBAC + SAS + ACLs | IAM + Bucket Policies + ACLs |
| Static website hosting | Yes | Yes |
| Lifecycle management | Yes | Yes |
| Replication | GRS/GZRS (same account) + Object Replication (cross-account) | CRR / SRR |
| Event notifications | Event Grid | S3 Event Notifications → SQS/SNS/Lambda |
| Inventory | Storage Inventory | S3 Inventory |
| Analytics | Storage Analytics logs + Azure Monitor | S3 Access Logs + S3 Storage Lens |
| Pre-signed URLs | SAS tokens | Pre-signed URLs |

---

## 2. Azure Data Lake Storage Gen2 (ADLS Gen2)

### What It Is

Blob Storage with **hierarchical namespace (HNS) enabled**. Adds POSIX-compliant directory semantics, atomic rename/delete operations, and Azure Data Lake ACLs — required for big data analytics workloads.

**Key insight**: ADLS Gen2 = Blob Storage + HNS. Same pricing as Blob Storage, but operations on directories are O(1) instead of O(n).

### Why HNS Matters

Without HNS (regular Blob):
```
"Rename" directory = copy all blobs to new prefix + delete originals
Cost: O(n) operations — expensive at petabyte scale
"Delete" directory = list all blobs + delete individually
```

With HNS (ADLS Gen2):
```
Rename directory = atomic metadata operation
Cost: O(1) — instant regardless of directory size
Delete directory = single atomic operation
```

At petabyte scale, Spark jobs renaming output directories go from minutes to milliseconds.

### ADLS Gen2 vs S3 for Analytics

| Feature | ADLS Gen2 | Amazon S3 |
|---------|----------|-----------|
| Hierarchical namespace | **Yes** (POSIX semantics) | No (flat namespace, prefix simulation) |
| Atomic rename | **Yes** (O(1)) | No (copy + delete, O(n)) |
| POSIX ACLs | Yes (per file/directory) | No (bucket/object policies only) |
| Integration with Azure Synapse | Native | Via S3 connector |
| Integration with Databricks | Excellent (ABFS driver) | Good (s3a driver) |
| Integration with HDInsight | Native | N/A |
| Multi-protocol access | Blob API + ABFS API | S3 API only |
| Cost vs Blob | Same storage cost | S3 storage cost |

**ABFS (Azure Blob File System) driver**: Databricks/Spark use `abfss://` URI to access ADLS Gen2. Replaces older WASB driver.

### Analytics Stack Integration

```
Data Landing Zone (ADLS Gen2)
├── Raw zone    ← ingest from Event Hubs (streaming) or ADF (batch)
├── Curated zone ← transformed by Azure Databricks (Spark)
└── Serving zone ← queried by Azure Synapse Serverless SQL

Medallion Architecture:
Raw (Bronze) → Databricks (Silver) → Databricks (Gold) → Synapse / Power BI
```

---

## 3. Azure Files

### What It Is

Fully managed SMB 2.1 / 3.x and NFS 4.1 file shares in the cloud. EFS / FSx equivalent.

### Share Tiers

| Tier | Protocol | Max IOPS | Max Throughput | Use Case |
|------|---------|---------|---------------|---------|
| **Standard (Transaction Optimized)** | SMB, REST | 10,000 | 300 MB/s | General file sharing |
| **Standard (Hot)** | SMB, REST | 10,000 | 300 MB/s | Frequently accessed |
| **Standard (Cool)** | SMB, REST | 10,000 | 300 MB/s | Infrequently accessed |
| **Premium** | SMB, NFS | 100,000 | 10 GB/s | Low latency, databases |

### Azure Files vs AWS Equivalents

| Feature | Azure Files (SMB) | Azure Files (NFS) | Amazon EFS | Amazon FSx for Windows |
|---------|------------------|------------------|-----------|----------------------|
| Protocol | SMB 2.1 / 3.x | NFS 4.1 | NFS 4.x | SMB |
| Access from | Windows, Linux, macOS | Linux | Linux | Windows |
| Consistency | Strong | Strong | Strong | Strong |
| Multi-AZ | ZRS option | ZRS option | Yes (default) | Yes (Multi-AZ) |
| Max storage | 100 TB (Standard) | 100 TB | Unlimited (grows) | 64 TB |
| Max IOPS | 10,000 (Standard), 100,000 (Premium) | 100,000 (Premium) | 500,000+ (General Purpose) | 80,000 |
| Windows ACLs | **Yes** (identity-based via Entra ID) | No | No | Yes |
| Active Directory auth | **Yes** (Entra ID DS or on-prem AD) | No | No | Yes |
| Lift-and-shift Windows shares | **Best fit** | No | No | Also fits |

**Entra ID authentication for Azure Files**: Mount shares using Entra ID credentials (Kerberos). No VPN needed for cloud access. This is a key enterprise differentiator — AWS FSx for Windows requires AD domain join.

### Azure File Sync

Synchronize on-prem Windows Server file shares with Azure Files:
```
On-prem file server
  └── Azure File Sync agent
        │
        └── Azure Files (cloud tier)
              │
              └── Cloud tiering: hot files on local disk, cold files in Azure Files
```

Enables: **CloudEndpoint** (multi-site sync) + **cloud tiering** (local disk holds only hot files).

**AWS equivalent**: AWS DataSync (one-time or scheduled sync) + FSx for Windows (no continuous sync agent model).

---

## 4. Azure Queue Storage

Simple, durable message queue. **Not** for enterprise messaging — use Service Bus for that.

| Feature | Azure Queue Storage | Amazon SQS Standard |
|---------|--------------------|--------------------|
| Max message size | 64 KB | 256 KB |
| Max retention | 7 days | 14 days |
| Delivery | At-least-once | At-least-once |
| Ordering | Best-effort | Best-effort |
| Dead-letter | No (manual) | SQS DLQ |
| Price per million | ~$0.004 | ~$0.40 |

**Use when**: Simple task queue, don't need Service Bus features, very cost-sensitive, storing millions of tiny messages.

---

## SAS Tokens — Deep Dive (Valet Key Pattern)

SAS (Shared Access Signature) = time-limited, permission-scoped URL for direct client access to Azure Storage.

### Types of SAS

| Type | Scope | Revocable? |
|------|-------|-----------|
| **Account SAS** | Entire storage account | Only by rotating account key |
| **Service SAS** | Specific container/blob/file/queue | Only by rotating key (or stored access policy) |
| **User Delegation SAS** (recommended) | Specific blob/container | **Yes** — by revoking Entra ID user delegation key |

**User Delegation SAS is the most secure**: Signed with Entra ID credentials, not storage account key. Revoke by deleting the user delegation key (max 7 days).

### SAS Parameters

```
https://myaccount.blob.core.windows.net/mycontainer/file.pdf
  ?sv=2023-11-03      ← signed version
  &ss=b               ← signed service (b=blob)
  &srt=o              ← signed resource type (o=object)
  &sp=r               ← signed permissions (r=read)
  &se=2024-01-15T12:00:00Z  ← expiry
  &sip=203.0.113.0/24      ← signed IP range (optional)
  &spr=https              ← signed protocol (HTTPS only)
  &sig=<HMAC-SHA256 signature>
```

**vs AWS Pre-Signed URL**: Both work the same way. Azure SAS is more granular (per-service, per-resource-type, IP restriction, protocol restriction). AWS pre-signed URLs: tied to IAM credentials, can be revoked only by rotating IAM key (no stored access policy equivalent for pre-signed URLs).

---

## Key Numbers for Interviews

| Service | Number | Notes |
|---------|--------|-------|
| Blob max object size | **190.7 TB** | vs S3's 5 TB |
| Storage Account max capacity | 5 PB | Soft limit; 500 TB default request limit |
| Blob max throughput per account | 60 Gbps ingress, 60 Gbps egress | Standard GPv2 |
| ADLS Gen2 atomic rename | O(1) | vs S3 O(n) prefix copy |
| Azure Files Premium max IOPS | 100,000 | vs EFS 500,000+ |
| Azure Files max share size | 100 TB | Standard tier |
| Queue Storage max message | 64 KB | vs SQS 256 KB |
| SAS max expiry (User Delegation) | 7 days | Security best practice: 1 hour |
| Storage redundancy options | LRS / ZRS / GRS / GZRS / RA-GRS | vs S3 which is always multi-AZ |

---

> **FAANG Interview Callout**: "The two Azure storage architectural decisions that come up most in interviews: (1) ADLS Gen2 vs Blob Storage — if you're running Spark/Databricks at petabyte scale, enable hierarchical namespace; otherwise the atomic-rename overhead causes Spark job failures during partition output commits. (2) LRS vs ZRS vs GRS — I default to ZRS for production blob storage (3 AZs in-region for HA) and add RA-GRS only when cross-region read access is a recovery requirement. On AWS, S3 is always multi-AZ so developers don't think about this, but on Azure it's a configuration decision that affects both cost and SLA — LRS is 11 nines and ZRS is 12 nines, and ZRS costs about 25% more."
