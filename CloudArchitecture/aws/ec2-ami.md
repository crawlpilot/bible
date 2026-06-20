# AWS EC2 & AMIs

## Overview
EC2 (Elastic Compute Cloud) is AWS's virtual machine service. An AMI (Amazon Machine Image) is a pre-packaged virtual machine image — the blueprint from which EC2 instances are launched. Together they form the backbone of virtually all non-serverless compute on AWS.

---

## EC2 Instance Types

### Family Overview

| Family | Optimised for | Examples | Use cases |
|---|---|---|---|
| **General Purpose** | Balanced CPU/memory/network | m7i, m6a, t3 | Web servers, app servers, dev environments |
| **Compute Optimised** | High CPU | c7i, c6a | Batch processing, ML inference, media encoding, gaming |
| **Memory Optimised** | High memory-to-CPU | r7i, r6a, x2iedn | In-memory databases (Redis), SAP HANA, analytics |
| **Storage Optimised** | High IOPS / throughput | i4i, i3, d3 | NoSQL (Cassandra, MongoDB), data warehouses, HDFS |
| **Accelerated Computing** | GPU / custom chips | p4d, g5, inf2, trn1 | ML training (p4d), ML inference (inf2), graphics (g5) |
| **HPC Optimised** | High-performance cluster | hpc7g | Simulation, CFD, molecular dynamics |

**Graviton (ARM) instances**: m7g, c7g, r7g — AWS's custom ARM chip. Up to 40% better price-performance than comparable x86 Intel instances. Most Java/Go/Python workloads run unchanged. Use as default for new workloads.

**T-series (burstable)**: `t3`, `t3a`, `t4g`. Low baseline CPU with burst credits. Cost-efficient for dev/test and variable workloads. In production, use `unlimited` mode carefully — unlimited burst accrues hourly charges.

---

## Purchasing Models

| Model | Discount vs On-Demand | Commitment | Best for |
|---|---|---|---|
| **On-Demand** | 0% | None | Variable, unpredictable, new workloads |
| **Reserved (1yr, all upfront)** | ~40% | 1 year | Stable baseline (min capacity always needed) |
| **Reserved (3yr, all upfront)** | ~60% | 3 years | Long-lived stable workloads |
| **Savings Plans (Compute)** | ~66% | 1–3 years | Flexible — applies to EC2, Lambda, Fargate |
| **Spot Instances** | Up to 90% | None (can be terminated with 2-min notice) | Fault-tolerant, stateless, batch workloads |
| **Dedicated Hosts** | ~30% discount vs on-demand (BYOL) | 1–3 years | License compliance (Windows Server, Oracle per-core) |

**Spot Instance patterns**:
- Use spot for: batch jobs (Glue, EMR), stateless web tier (behind ALB), CI/CD runners, ML training (checkpoint-enabled)
- Always use a **Spot Fleet** or ASG with mixed instances (multiple families/sizes) — increases spot availability
- Handle 2-minute termination notice: Lambda subscribes to EC2 Spot Interruption Warning event → drain from ALB target group, checkpoint state to S3

**Cost optimisation stack**:
1. Right-size instances (use Compute Optimiser recommendations)
2. Savings Plans for baseline (Compute Savings Plans — most flexible)
3. Reserved Instances for stable, predictable workloads
4. Spot for everything batchable
5. Graviton for everything that runs on ARM

---

## AMIs (Amazon Machine Images)

### What an AMI Contains
- **Root volume snapshot**: OS, installed software, configuration
- **Launch permissions**: who can use this AMI
- **Block device mapping**: which EBS volumes to attach at launch
- **Architecture**: x86_64 or arm64

### AMI Lifecycle

**Build → Scan → Share → Launch**:

1. **Build**: start with an AWS base AMI (Amazon Linux 2023, Ubuntu 22.04) → install software → configure → create AMI snapshot via `CreateImage` API or EC2 Image Builder
2. **Scan**: run automated vulnerability scanning (Inspector v2 scans AMIs automatically for CVEs)
3. **Share**: cross-account via `ModifyImageAttribute`; cross-region via `CopyImage`
4. **Launch**: reference AMI ID in ASG launch template; new instances from fleet get the same image

### EC2 Image Builder
Fully managed AMI pipeline:
```
Source AMI (Amazon Linux 2023)
    ↓ Component pipeline (install, configure, harden)
    ↓ Test pipeline (run automated tests)
    ↓ Distribution (copy to target regions/accounts)
    ↓ AMI ready for production
```
Schedule weekly/monthly builds to pick up OS security patches. AMI IDs are version-controlled — roll back by pointing ASG to previous AMI ID.

### Golden AMI Pattern
A **Golden AMI** is a pre-baked, hardened, approved AMI used as the base for all production instances:
- OS + runtime + monitoring agent (CloudWatch Agent, Datadog) + security config pre-installed
- No software installed at runtime (faster boot, no external dependency at launch)
- Versioned: `golden-ami-amazonlinux2023-java21-v1.2.3`
- Required by many security compliance frameworks (PCI, SOC2) — known-good state baseline

### AMI Sharing & Encryption
- Share AMIs cross-account: `aws ec2 modify-image-attribute --image-id ami-xxx --attribute launchPermission`
- Encrypt AMIs with KMS: encrypted AMI creates an encrypted root snapshot; shared-AMI recipients must also have access to the KMS key
- AWS Marketplace AMIs: third-party software available directly; some require a license subscription

---

## EC2 Storage Options

| Type | Use case | IOPS | Throughput | Notes |
|---|---|---|---|---|
| **gp3 (General Purpose SSD)** | Boot, most workloads | Up to 16,000 | Up to 1,000 MB/s | Default choice; configure IOPS/throughput independently |
| **io2 Block Express** | Databases (Oracle, SQL Server) | Up to 256,000 | Up to 4,000 MB/s | Highest performance; 99.999% durability |
| **st1 (Throughput HDD)** | Big data, sequential reads | 500 IOPS (max) | Up to 500 MB/s | $0.045/GB vs $0.08/GB for gp3 |
| **sc1 (Cold HDD)** | Infrequent access | 250 IOPS (max) | Up to 250 MB/s | Cheapest; rarely appropriate |
| **Instance Store** | Temp storage, scratch space | Millions of IOPS | Very high | Ephemeral: data lost on stop/terminate |

**gp3 vs gp2**: gp3 decouples IOPS from volume size (gp2 was 3 IOPS/GB). Always use gp3 — better performance, same price.

**EBS Multi-Attach (io2 only)**: attach one EBS volume to multiple EC2 instances simultaneously. Use for shared storage between clustered databases (Oracle RAC). Requires application-level locking.

---

## EC2 Networking

**Placement Groups**:
| Type | Benefit | Use case |
|---|---|---|
| **Cluster** | Low latency, 10 Gbps between instances (same AZ, same rack) | HPC, distributed ML training, Kafka brokers |
| **Spread** | Instances on different hardware (max 7 per AZ) | HA: each instance on different underlying hardware |
| **Partition** | Groups of instances on separate racks | Cassandra, HDFS, Kafka — rack-aware replication |

**Enhanced Networking (ENA)**: up to 100 Gbps on supported instance types. Enabled by default on modern instances. Required for cluster placement groups.

**Elastic Network Interfaces (ENI)**: virtual NIC. Multiple ENIs per instance for network segmentation. Elastic IPs attach to ENIs, so an Elastic IP can move across instances by detaching/re-attaching the ENI.

---

## EC2 Instance Metadata Service (IMDS)

The IMDS provides instance identity, IAM role credentials, and other metadata to code running on the instance.

**Critical: enforce IMDSv2** (token-based, not IMDSv1 path-accessible):
```bash
# Get token (IMDSv2)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
# Use token
curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/iam/security-credentials/my-role"
```

IMDSv1 is a SSRF vulnerability target — any SSRF can steal IAM credentials via IMDSv1. Enforce IMDSv2 via instance metadata option `HttpTokens: required` in launch template, or via SCP.

---

## Key Tuning Parameters

| Parameter | Recommendation |
|---|---|
| `DeleteOnTermination` (EBS) | True for ephemeral workloads; False for persistent data volumes |
| `EbsOptimized` | Always enable — dedicated bandwidth between EC2 and EBS |
| `Monitoring` (detailed) | Enable for 1-minute metrics (vs 5-minute default) |
| `IMDSv2 HttpTokens` | `required` — enforce IMDSv2 |
| EBS `gp3` IOPS | Default 3,000; set to match workload; max 16,000 (no extra cost up to 3,000) |
| EBS `gp3` Throughput | Default 125 MB/s; up to 1,000 MB/s; +$0.04/MB/s above 125 |
| CPU Credits (T-series) | Set `unlimited` for production; watch `CPUCreditBalance` metric |
| Placement Group | Cluster for HPC; Spread for HA; Partition for distributed data |

---

## Monitoring EC2

| Metric | Alert condition |
|---|---|
| `CPUUtilization` | > 80% sustained → scale or resize |
| `NetworkIn` / `NetworkOut` | Near instance network limit → upgrade instance type |
| `EBSReadOps` / `EBSWriteOps` | Near volume IOPS limit → increase IOPS or use io2 |
| `StatusCheckFailed_Instance` | > 0 → instance hardware issue; auto-recover or terminate |
| `StatusCheckFailed_System` | > 0 → underlying host issue; AWS action required |
| `DiskReadBytes` (instance store) | Monitor for temporary disk saturation |
| EC2 Spot `InterruptionWarning` | 2-minute warning → drain and checkpoint |

**EC2 Auto-Recovery**: configure `StatusCheckFailed_System` alarm with action `ec2:RecoverInstances` — AWS migrates the instance to healthy hardware and preserves the same instance ID, EIP, and EBS volumes.

---

## Best Practices

1. **Use Graviton (ARM) instances** for all CPU-bound workloads — 40% better price/performance
2. **Use gp3 EBS** for all new volumes — same cost as gp2, decoupled IOPS/throughput
3. **Use EC2 Image Builder** for golden AMI pipeline — weekly builds pick up OS patches
4. **Enforce IMDSv2** on all instances — closes SSRF credential theft vector
5. **Use Savings Plans** (Compute) for baseline, Spot for batch — not On-Demand for either
6. **Enable EBS optimization** on all instances — dedicated bandwidth prevents storage/network contention
7. **Use placement groups** for latency-sensitive clusters (Cluster) and distributed data (Partition)
8. **Enable EC2 Auto-Recovery** for critical singleton instances that can't be replaced by ASG
9. **Use Compute Optimiser** to right-size — frequently overprovisioned by 30–50%
10. **Delete unattached EBS volumes** — orphaned volumes from terminated instances accumulate silently

---

## FAANG Interview Points

**"On-Demand vs Reserved vs Spot"**: On-Demand for new, unpredictable workloads. Compute Savings Plans for stable baseline (most flexible). Spot for fault-tolerant batch. Reserved for stable, long-lived, steady-state workloads where 3yr commitment makes financial sense.

**"How do you update AMIs across 1,000 instances?"**: EC2 Image Builder builds a new AMI weekly. ASG launch template references the AMI ID. Rolling update: instance refresh in the ASG (`StartInstanceRefresh`) with a min healthy percentage — replaces instances in batches. Zero downtime if behind an ALB.

**"How do you handle SSRF attacks on EC2?"**: Enforce IMDSv2 (`HttpTokens: required`) — SSRF cannot make PUT requests with custom headers. VPC network controls limit IMDS access. Use IAM roles with least-privilege — even if stolen, credentials have limited blast radius.
