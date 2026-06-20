# Amazon Web Services in Action, 2nd Edition
**Authors:** Andreas Wittig & Michael Wittig  
**Publisher:** Manning Publications, 2018  
**Relevance:** Principal Engineer interviews — AWS service internals, architecture patterns, infrastructure automation, security, cost management

---

## Why This Book Matters at Principal Level

Most AWS documentation tells you *what* a service does. This book tells you *how to wire services together* and *why* a particular design beats alternatives. The Wittig brothers were AWS consultants — every chapter reflects real trade-offs from production systems, not toy demos. Read it to answer interview questions like: "Walk me through your VPC design" or "How did you harden IAM in your org?" with precise operational knowledge, not vague platitudes.

---

## Part 1: Getting Started

### Chapter 1 — What Is Amazon Web Services?

#### The Core Value Proposition
AWS operates on the premise that compute, storage, and networking are commodities. Rather than buying hardware, you rent capacity by the second. This fundamentally changes cost structure: CapEx becomes OpEx, infrastructure becomes code, and teams can experiment at near-zero marginal cost.

**Global Infrastructure (2018 baseline, still the mental model):**
```
Region         → Independent geographic deployment (e.g., us-east-1, eu-west-1)
  Availability Zone (AZ) → Isolated data center(s) within a region; distinct power/network
    Edge Location → CDN PoP for CloudFront; DNS for Route 53 — 150+ globally
```

- **Regions** are fully independent. A failure in us-east-1 does not affect eu-west-1.
- **AZs** within a region are connected by low-latency, high-bandwidth links but isolated for failures (separate power grids, facilities). This is the unit of redundancy for almost all multi-AZ architectures.
- **Edge Locations** serve cached content from CloudFront and handle Route 53 DNS — orders of magnitude more PoPs than regions.

#### Pricing Model
AWS charges per unit of consumption — no upfront hardware cost:
- **EC2:** per-second billing (Linux), hourly (Windows)
- **S3:** per GB stored + per request
- **RDS:** per instance-hour + storage
- **Data transfer:** within AZ free, cross-AZ $0.01/GB, cross-region $0.02–0.09/GB, to internet $0.09/GB (first 10 TB)

**Free Tier:** 12-month trial includes 750h/month t2.micro EC2, 5 GB S3, 20 GB RDS. Useful for learning but watch for charges when tier expires.

#### The Shared Responsibility Model
This is a principal engineer concept: AWS and you divide security responsibilities.

```
AWS responsibility ("security OF the cloud"):
  Physical infrastructure, network hardware, hypervisor, managed service patching
  (e.g., RDS engine patching, Lambda runtime security)

Your responsibility ("security IN the cloud"):
  Guest OS patching (EC2), IAM configuration, network (SG/NACL/VPC), application security
  Data encryption (at rest + in transit), access logging, compliance controls
```

Misunderstanding this boundary causes security gaps. Example: AWS patches the RDS engine; you are responsible for not leaving the DB in a public subnet.

---

### Chapter 2 — A Simple Example: WordPress in Five Minutes

This chapter walks through deploying WordPress end-to-end on AWS using CloudFormation — the book's first exposure to infrastructure as code. The practical lesson:

**Architecture deployed:**
```
Internet → ELB → EC2 (WordPress, PHP, Apache) → RDS MySQL (Multi-AZ)
                ↕
               EBS (storage for uploads)
               ElastiCache (session/object cache)
```

**Key lessons from this chapter:**
1. **CloudFormation templates are the spec** — the YAML/JSON file is the authoritative description of your infrastructure. Drift = risk.
2. **Resources have dependencies** — CloudFormation handles ordering. EC2 waits for RDS; ELB waits for EC2. Declare `DependsOn` only when CloudFormation can't infer the dependency.
3. **Stacks fail atomically** — if any resource fails to create, the stack rolls back. This all-or-nothing behavior means partial infrastructure states don't linger.
4. **Outputs expose resources** — `Outputs` section exports the ELB DNS name, RDS endpoint, etc. for other stacks or humans to consume.

---

## Part 2: Building Virtual Infrastructure with Servers and Networking

### Chapter 3 — Using Virtual Machines: EC2

#### Instance Families and Types
EC2 instance families map to workload profiles. Choosing wrong is expensive:

| Family | Optimized for | Examples | Use case |
|--------|--------------|----------|----------|
| General Purpose (T, M) | Balanced CPU/RAM | t3.medium, m6g.large | Web servers, app servers |
| Compute Optimized (C) | High CPU | c6i.2xlarge | Batch, ML inference, gaming |
| Memory Optimized (R, X) | High RAM | r6g.8xlarge, x2idn | In-memory DB, analytics |
| Storage Optimized (I, D) | NVMe SSD / HDD | i4i.xlarge, d2.8xlarge | Distributed FS, data warehouses |
| Accelerated (P, G, Inf) | GPU / FPGA | p4d.24xlarge, g5.xlarge | ML training, rendering |
| High Memory (u-) | 3-24 TB RAM | u-24tb1.metal | SAP HANA, in-memory DBs |

**Graviton (ARM64):** AWS-designed ARM processor, 20% cheaper per vCPU-hour and up to 40% better price-performance than x86 equivalents. Use for workloads without x86-only dependencies (most modern stacks).

**Sizing heuristic for interviews:** Start at m6g.large (2 vCPU, 8 GB), vertical-scale to m6g.4xlarge (16 vCPU, 64 GB) before horizontal scaling becomes necessary. Measure before sizing.

#### Amazon Machine Images (AMIs)

An AMI is a template containing the OS, software, and configuration for an EC2 instance. Three types:

1. **AWS-managed AMIs** — Amazon Linux 2023, Ubuntu, Windows Server. Start here.
2. **Marketplace AMIs** — pre-built by vendors (Nginx Plus, F5 BIG-IP, etc.). Convenient but can be expensive.
3. **Custom AMIs (Golden AMIs)** — your org's base image with pre-installed agents, hardened OS configuration, compliance controls. Built via EC2 Image Builder pipeline (packer is the OSS alternative).

**Golden AMI pattern:** Build monthly (security patches), bake in: CloudWatch agent, SSM agent, custom certificates, compliance hardening. All EC2 instances in org launch from this AMI. Eliminates per-instance bootstrap time and ensures consistency.

#### Instance Lifecycle
```
Pending → Running → [Stopping → Stopped → Pending]
                  ↘ Shutting-down → Terminated (permanent)
```

- **Stop/Start:** Instance moves to a new physical host; public IP changes (use Elastic IP or ELB DNS to avoid dependency on IP).
- **Reboot:** Same physical host; public IP preserved.
- **Hibernate:** Memory contents saved to EBS; instance resumes from that state. Prerequisite: encrypted EBS root volume, <150 GB RAM.
- **Terminate:** Instance deleted; root EBS volume deleted (by default). Data on instance store lost immediately.

#### Purchasing Options — The Cost Dimension Every Principal Must Know

| Option | Discount vs On-Demand | Commitment | Interruption risk | Use case |
|--------|----------------------|-----------|------------------|----------|
| On-Demand | 0% | None | None | Unpredictable, short-term |
| Reserved (1-yr, no upfront) | ~30% | 1 year | None | Steady-state baseline |
| Reserved (3-yr, all upfront) | ~60% | 3 years | None | Long-lived, cost-sensitive |
| Savings Plans (Compute) | Up to 66% | 1–3 years | None | Flexible (covers Lambda, Fargate, EC2) |
| Spot | Up to 90% | None | 2-min warning | Fault-tolerant batch, stateless |
| Dedicated Host | Higher | 1–3 years optional | None | Licensing (Windows/SQL Server), compliance |

**Spot strategy for principal engineers:** Design batch jobs and stateless workers to handle Spot interruptions via SQS. Use mixed fleet ASG (On-Demand base + Spot additional capacity). Never use Spot for: leader nodes, databases, stateful services, or latency-sensitive user-facing services.

#### User Data & Instance Metadata

**User data script** runs once at first launch (as root):
```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
```

**Best practices:** Keep user data minimal. Install software in AMI (pre-bake). Use user data only for last-mile config (inject environment-specific values). Long bootstrap scripts = long time to healthy = slow autoscaling.

**Instance Metadata Service (IMDS):**
```
curl http://169.254.169.254/latest/meta-data/instance-id
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/MyRole
```

- IMDSv1 is vulnerable to SSRF attacks (attacker can access metadata via server-side request forgery).
- **Always enforce IMDSv2** (requires session token, `PUT` request for token): blocks SSRF exploitation.
- IMDSv2 enforcement via instance metadata options or organization-level SCP.

#### Placement Groups

| Type | Behavior | Use case |
|------|----------|----------|
| **Cluster** | Instances on same physical rack, lowest latency | HPC, tightly coupled distributed computing |
| **Spread** | Instances on different racks, max isolation | Critical instances, HA |
| **Partition** | Groups of instances on separate racks | Kafka, Cassandra, HDFS — rack-aware apps |

Cluster placement group: must use instance types with enhanced networking (ENA). If insufficient capacity, request fails — plan for this in HPC environments.

---

### Chapter 4 — Infrastructure as Code: CLI, SDKs, CloudFormation

#### AWS CLI
Structure: `aws <service> <operation> [--options]`

Key operational commands:
```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
aws s3 sync ./dist s3://my-bucket/ --delete
aws cloudformation deploy --template-file template.yaml --stack-name my-stack
aws sts get-caller-identity   # verify which identity is making API calls
```

**Named profiles** (`~/.aws/credentials`): switch between accounts/roles. Use `AWS_PROFILE` env var or `--profile` flag. Use `aws-vault` for secure credential storage in production.

#### CloudFormation — Infrastructure as Code

CloudFormation is the bedrock of repeatable, auditable infrastructure. A template is a YAML/JSON document with six sections:

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "My stack"

Parameters:             # Inputs — customize per environment
  Environment:
    Type: String
    AllowedValues: [dev, staging, prod]

Mappings:               # Static lookup tables
  RegionAMI:
    us-east-1:
      AMI: ami-0abcdef1234567890

Conditions:             # Conditional resource creation
  IsProd: !Equals [!Ref Environment, prod]

Resources:              # Required — the actual AWS resources
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "my-bucket-${Environment}"

Outputs:                # Values to export or display
  BucketName:
    Value: !Ref MyBucket
    Export:
      Name: !Sub "${AWS::StackName}-BucketName"
```

**Intrinsic functions** (the glue):
| Function | Purpose | Example |
|----------|---------|---------|
| `!Ref` | Reference a parameter or resource's primary ID | `!Ref MyBucket` → bucket name |
| `!GetAtt` | Get a resource attribute | `!GetAtt MyBucket.Arn` |
| `!Sub` | String substitution | `!Sub "arn:aws:s3:::${BucketName}"` |
| `!If` | Conditional value | `!If [IsProd, r6g.2xlarge, t3.small]` |
| `!ImportValue` | Read an exported output from another stack | `!ImportValue vpc-stack-VpcId` |

**Change Sets:** Preview what CloudFormation will change before executing. Mandatory for production updates:
```bash
aws cloudformation create-change-set --stack-name my-stack --template-body file://template.yaml
aws cloudformation describe-change-set --change-set-name my-change-set
aws cloudformation execute-change-set --change-set-name my-change-set
```

**Stack Policies:** Prevent accidental deletion/replacement of critical resources (e.g., RDS instances):
```json
{"Statement": [{"Effect": "Deny", "Action": "Update:Replace", "Resource": "LogicalResourceId/MyRDSInstance"}]}
```

**Drift Detection:** CloudFormation detects when actual resource configuration diverges from the template. Drift = manual change bypassed IaC. Treat drift as a security/compliance incident.

**Custom Resources:** Invoke a Lambda during stack create/update/delete to provision resources CloudFormation doesn't natively support (DNS provider record, Datadog monitor, Slack notification).

---

### Chapter 5 — Automating Deployment: Elastic Beanstalk

#### Elastic Beanstalk Philosophy
Beanstalk is PaaS on top of CloudFormation. You give it a ZIP of your application code; it handles the EC2, ASG, ELB, CloudWatch alarms, and deployment pipeline. Principal engineers use Beanstalk for internal tools or teams that want to focus on application code, not infrastructure.

**Environment types:**
- **Web server:** ALB + ASG. HTTP traffic. Blue/green deployments.
- **Worker:** SQS + EC2. Polls SQS for tasks. Scheduled tasks via cron (SQS periodic tasks).

**Deployment policies:**
| Policy | Downtime | Speed | Safety |
|--------|---------|-------|--------|
| All at once | Brief | Fastest | Lowest (all instances replaced simultaneously) |
| Rolling | None | Slow | Medium (% of instances at a time) |
| Rolling with additional batch | None | Slowest | High (adds extra capacity, then rolls) |
| Immutable | None | Slow | Highest (new ASG, traffic shifted) |
| Blue/Green | None | Controlled | Highest (swap environment URLs) |

**Principal engineer note:** For most applications, use **Rolling with additional batch** in staging, **Immutable** or **Blue/Green** in production. All-at-once is only acceptable in dev.

**`.ebextensions`** — customize environment configuration via config files in `.ebextensions/` directory:
```yaml
# .ebextensions/nginx.config
files:
  "/etc/nginx/conf.d/proxy.conf":
    content: |
      client_max_body_size 20M;
commands:
  reload_nginx:
    command: "service nginx reload"
```

**Limits of Beanstalk:** Limited control over networking, security, and IAM. For complex multi-service architectures, CloudFormation directly (or CDK/Terraform) gives more control. Beanstalk is a productivity shortcut, not an architectural foundation.

---

### Chapter 6 — Securing Your System: IAM, Security Groups, and VPC

#### IAM Architecture

IAM is the authorization backbone of AWS. Every API call is checked against IAM policies.

**Identity types:**
| Type | Use case |
|------|----------|
| IAM User | Human with long-term credentials (avoid for applications) |
| IAM Group | Collection of users sharing policies |
| IAM Role | Assumed by services, users, or external identities; temporary credentials |
| IAM Policy | JSON document defining permissions |

**Policy evaluation logic (simplified):**
```
1. Start: implicit DENY on everything
2. Evaluate all applicable policies
3. Explicit ALLOW overrides implicit DENY
4. Explicit DENY overrides any ALLOW (including Allow in resource policies)
5. SCPs (Organizations) constrain what's possible — even if IAM allows it, SCP can block
```

**Types of policies:**
- **Identity-based:** attached to a user/role/group
- **Resource-based:** attached to a resource (S3 bucket policy, KMS key policy, Lambda function policy)
- **Permissions boundaries:** maximum permissions an identity can have (can't grant more than the boundary allows)
- **SCPs (Service Control Policies):** org-level guardrails applied to accounts/OUs

**Principle of least privilege:** Every role gets only what it needs for its specific task. Review with AWS Access Analyzer (finds unused permissions). Tighten over time as access patterns stabilize.

**IRSA (IAM Roles for Service Accounts):** EKS pods assume IAM roles via OIDC provider — no long-term credentials on pods. The gold standard for EKS authorization.

**Instance profiles:** EC2 instances assume an IAM role via instance profile. The application calls IMDS to get temporary credentials. No credentials stored in application code or config files.

#### VPC Design

A VPC is your isolated network on AWS. Every production workload lives in one.

**CIDR planning** — the decisions you live with:
- Don't overlap with on-premises CIDR (VPN/Direct Connect will conflict)
- Use RFC 1918: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
- **Recommended:** `10.0.0.0/16` per VPC (65,536 IPs). Reserve top bits for account/environment, lower for AZ/subnet.
- AWS reserves 5 IPs per subnet (first 4 + last 1)

**Subnet strategy:**
```
VPC: 10.0.0.0/16
  Public subnets (per AZ):
    us-east-1a: 10.0.0.0/24  (254 usable IPs)
    us-east-1b: 10.0.1.0/24
    us-east-1c: 10.0.2.0/24
  Private subnets (per AZ):
    us-east-1a: 10.0.10.0/24
    us-east-1b: 10.0.11.0/24
    us-east-1c: 10.0.12.0/24
  Data subnets (per AZ):
    us-east-1a: 10.0.20.0/24
    us-east-1b: 10.0.21.0/24
    us-east-1c: 10.0.22.0/24
```

**Layers:**
- **Public subnets:** ALB, NAT Gateways, Bastion hosts. Direct internet access via Internet Gateway.
- **Private subnets:** EC2, ECS, EKS. Internet egress only via NAT Gateway. No direct inbound from internet.
- **Data subnets:** RDS, ElastiCache, OpenSearch. No internet access. Only reachable from private subnets.

**Routing:**
```
Public subnet route table:
  10.0.0.0/16 → local
  0.0.0.0/0  → Internet Gateway

Private subnet route table:
  10.0.0.0/16 → local
  0.0.0.0/0  → NAT Gateway (in same AZ — NAT GW is AZ-scoped)

Data subnet route table:
  10.0.0.0/16 → local
  (no 0.0.0.0/0 route — no internet)
```

**Security Groups vs NACLs:**
| Dimension | Security Group | NACL |
|-----------|---------------|------|
| Level | Instance (ENI) | Subnet |
| State | Stateful (return traffic auto-allowed) | Stateless (must allow inbound AND outbound explicitly) |
| Rules | Allow only | Allow and Deny |
| Evaluation | All rules evaluated | Rules evaluated in number order, first match wins |
| Default | All deny inbound, all allow outbound | Allow all |

**Security Group chaining (the pattern):**
```
ALB SG: allow 443 from 0.0.0.0/0
App SG: allow 8080 from ALB SG   ← reference SG, not CIDR
DB SG:  allow 5432 from App SG
```
Never open DB to a CIDR — always reference the application's Security Group ID. This survives IP changes.

**NAT Gateway vs NAT Instance:**
- **NAT Gateway:** Managed, highly available within AZ, 5–45 Gbps, $0.045/hr + $0.045/GB. No management.
- **NAT Instance:** EC2 running NAT AMI. Must manage HA, scaling, patching. Only use to save cost in dev/test.

One NAT Gateway per AZ. Route each AZ's private subnet to the NAT Gateway in its AZ (avoid cross-AZ traffic costs and single point of failure).

---

## Part 3: Storing Data on AWS

### Chapter 7 — Object Storage: S3 and Glacier

#### S3 Fundamentals

S3 is an object store — files are objects, organized in flat buckets with key-based addressing. Not a filesystem (no append, no partial write).

**Consistency model (strong since Dec 2020):** Read-after-write consistency for all operations. Reads after PUT or DELETE always see the latest data. The old "eventual consistency for overwrites" is gone.

**Key design principles:**
- Object keys that start with the same prefix hit the same storage partition. High throughput: randomize prefixes.
- AWS auto-partitions at 3,500 PUT/s and 5,500 GET/s per prefix. Modern S3 handles almost any workload without prefix tricks — but know the history.

#### Storage Classes

| Class | Durability | Availability | Min storage | Use case |
|-------|-----------|-------------|-------------|----------|
| Standard | 11 nines | 99.99% | None | Hot data |
| Intelligent-Tiering | 11 nines | 99.9% | 30 days | Unknown access pattern |
| Standard-IA | 11 nines | 99.9% | 30 days | Infrequent access, accessed in seconds |
| One Zone-IA | 11 nines | 99.5% | 30 days | Recreatable data, infrequent |
| Glacier Instant | 11 nines | 99.9% | 90 days | Archive, millisecond retrieval |
| Glacier Flexible | 11 nines | 99.99% | 90 days | Archive, minutes–hours retrieval |
| Glacier Deep Archive | 11 nines | 99.99% | 180 days | 7–10yr archive, 12h retrieval |

**Lifecycle rules:** Automatically transition objects between classes or expire them:
```
Created → Standard (0-30 days) → Standard-IA (30-90 days) → Glacier (90+ days) → Deleted (730 days)
```

#### Versioning

Enabling versioning on a bucket:
- Every PUT creates a new version, keyed by version ID
- DELETE creates a delete marker — object is "gone" but versions remain
- Recover from accidental deletion by removing the delete marker
- Recover from accidental overwrite by restoring a prior version
- **MFA Delete:** require MFA to delete versions or disable versioning — protection against rogue admin or compromised credentials

**Cost implication:** All versions are stored and billed. Use lifecycle rules to expire non-current versions.

#### Security Model

**S3 Block Public Access:** Account-level and bucket-level settings that override any policy granting public access. Enable at the account level; disable selectively only where truly needed (public website bucket).

**Bucket policies vs IAM policies:**
```json
{
  "Effect": "Allow",
  "Principal": {"AWS": "arn:aws:iam::123456789012:role/MyRole"},
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/*"
}
```

**Encryption (server-side):**
- **SSE-S3:** AWS-managed keys. No cost, no control.
- **SSE-KMS:** Customer-managed keys (CMK). Audit trail in CloudTrail. Key rotation. Slightly higher latency. Cost: $0.03/10,000 KMS API calls.
- **SSE-C:** Customer provides key per request. AWS never stores the key.
- **DSSE-KMS:** Dual-layer encryption (two independent keys).

**Always use SSE-KMS for regulated data.** Bucket policy can enforce: `"Condition": {"StringNotEquals": {"s3:x-amz-server-side-encryption": "aws:kms"}}` — deny unencrypted puts.

#### Presigned URLs

Allow temporary, time-limited access to a private object without exposing credentials:
```python
url = s3.generate_presigned_url(
    'get_object',
    Params={'Bucket': 'my-bucket', 'Key': 'private-file.pdf'},
    ExpiresIn=3600  # 1 hour
)
```

**Use case:** User uploads directly to S3 (presigned PUT) — bypasses your backend for large files. S3 handles multipart upload for objects >100 MB (up to 5 TB per object).

#### Cross-Region Replication (CRR)

- Replicates objects to a bucket in another region (or account)
- Requires versioning on both buckets
- Replication lag: typically seconds to minutes
- Use cases: DR, compliance (data residency), reduce read latency by reading from the nearest region

---

### Chapter 8 — Block Storage: EBS and Instance Store

#### EBS Volume Types

| Type | Use case | Max IOPS | Max throughput | Latency |
|------|----------|----------|---------------|---------|
| gp3 | General purpose root volume | 16,000 | 1,000 MB/s | Low |
| gp2 | Legacy general purpose | 16,000 (burst) | 250 MB/s | Low |
| io2 Block Express | High-performance DB | 256,000 | 4,000 MB/s | Sub-ms |
| io1 | Legacy high-performance | 64,000 | 1,000 MB/s | Sub-ms |
| st1 | Throughput-optimized HDD | 500 | 500 MB/s | Higher |
| sc1 | Cold HDD (lowest cost) | 250 | 250 MB/s | Highest |

**Default:** Always use `gp3` — it's cheaper than `gp2` and IOPS/throughput are independently configurable (not tied to volume size). Upgrade existing gp2 volumes to gp3 with no downtime.

**Provisioned IOPS (io2):** For Oracle, SQL Server, high-transaction PostgreSQL, or any workload requiring consistent sub-millisecond I/O. io2 durability: 99.999% (one extra 9 over gp3).

#### EBS Snapshots

- Incremental: first snapshot = full backup, subsequent = only changed blocks
- Stored in S3 (managed by AWS, not visible in your bucket)
- Restore: create new volume from snapshot (in any AZ within the region)
- Cross-region copy for DR
- **Fast Snapshot Restore (FSR):** pre-warms restored volumes — avoids cold-start I/O performance degradation. Extra cost ($0.75/AZ/hour per snapshot with FSR enabled).

#### Instance Store (Ephemeral Storage)

Physically attached NVMe SSDs — not network-attached:
- **Highest possible I/O** (millions of IOPS, 19 GB/s on some instance types)
- **Data is lost on stop, terminate, or hardware failure**
- Not suitable for data that must persist
- **Use for:** temporary scratch data, distributed system replicas (Kafka, Cassandra can tolerate node loss if data is replicated to other nodes), ML training data staging

**Instance families with instance store:** i4i, i3, d2, d3, h1. Size these carefully — you can't add instance store volumes after launch.

---

### Chapter 9 — Relational Database: RDS

#### Why Managed DB?

Self-managing a DB on EC2: you handle OS patching, engine upgrades, backups, replication, failover, parameter tuning. RDS handles all of this — you manage only the schema and queries.

#### Multi-AZ Deployment

```
Primary: us-east-1a
  ↕ synchronous block-level replication
Standby: us-east-1b (not readable, not visible in console)
```

On failure: Route 53 CNAME record updated from primary endpoint to standby. Failover time: 60–120 seconds. Application must handle brief connection reset. **Use connection retry in application code.**

Multi-AZ is about durability and availability, not read scaling. The standby is not readable.

#### Read Replicas

```
Primary → async replication → Read Replica 1 (same region)
                            → Read Replica 2 (different region)
                            → Read Replica 3 (chain from Replica 1)
```

- Up to 5 read replicas per primary (MySQL/PostgreSQL)
- Used for read scaling, not HA (replica is eventually consistent)
- Replica can be promoted to standalone primary (manual operation — for DR or migration)
- Cross-region read replicas: DR + geographic read latency reduction

**Replication lag** is the critical metric. If replica lag spikes, reads from replica are stale. Route time-sensitive reads (current balance, inventory check) to primary.

#### Parameter Groups and Option Groups

- **Parameter Group:** DB engine config (e.g., `max_connections`, `innodb_buffer_pool_size`). Changes to static parameters require reboot. Dynamic parameters take effect immediately.
- **Option Group:** Additional features enabled on the engine (e.g., Oracle Transparent Data Encryption, MySQL memcached plugin).

Never use default parameter groups in production — at minimum, tune `max_connections`, `slow_query_log`, and engine-specific buffer sizes.

#### Security

- RDS in a private subnet (data tier). Security group: allow only from app tier SG.
- Encryption at rest: enable at creation time (cannot enable later without snapshot restore). Uses KMS.
- Encryption in transit: require SSL connections (`rds.force_ssl = 1` in parameter group for PostgreSQL).
- **IAM database authentication:** database passwords replaced with IAM tokens for MySQL/PostgreSQL. Tokens generated by AWS SDK, valid 15 minutes. Eliminates long-lived DB passwords.

---

### Chapter 10 — NoSQL: DynamoDB

*(This chapter's key content is extensively covered in the `dynamodb.md` file in CloudArchitecture/aws/.)*

**Core lessons from the book:**

**Capacity planning math:**
```
Table: 1 million users, user reads 10 times/day, user writes once/day
Read QPS:  (1M × 10) / 86400 = 116 RPS → 116 RCU (eventually consistent = 58 RCU)
Write QPS: (1M × 1) / 86400  = 12 WPS → 12 WCU (assuming 1 KB items)
```
Add 3× headroom for peak: 348 RCU, 36 WCU provisioned. Enable Auto Scaling to handle actual variance.

**Local Secondary Indexes (LSI):**
- Must be created at table creation — plan access patterns upfront
- Share throughput and 10 GB partition limit with the base table
- Use when: you need to query the same partition key with a different sort key

**Write Sharding Pattern:**
```
Hot key problem: all writes go to "status=PENDING" → single partition overloaded
Solution: add random suffix: "status=PENDING#3" (1-10 random)
Query: scatter-gather across all 10 shards
```

---

### Chapter 11 — In-Memory Caching: ElastiCache

*(Key content covered in `elasticache.md`.)*

**Book's key caching lessons:**

**Session storage with Redis:**
```
User login:
  1. Create session: {userId, roles, cart, expires}
  2. Store in Redis: SET session:{sid} {json} EX 1800
  3. Return session cookie to user

Request validation:
  1. Read cookie sid
  2. GET session:{sid} from Redis
  3. If nil → 401 (session expired)
  4. If found → reset TTL: EXPIRE session:{sid} 1800
```

Benefits over DB-stored sessions: sub-millisecond access, eliminates DB load for every authenticated request, TTL handles cleanup automatically.

**Cache stampede (thundering herd) prevention:**
When a popular cache key expires, thousands of requests all miss cache simultaneously and all query the DB:
```
Solution 1: Probabilistic early expiration
  if current_time > (expiry - random(0, 10)):
    refresh cache proactively before TTL expires

Solution 2: Locking (mutex on cache miss)
  if cache miss:
    acquire distributed lock
    if lock acquired: fetch from DB, set cache, release lock
    else: wait and retry
```

---

### Chapter 12 — Message Queue: SQS

*(Key content covered in `sqs.md`.)*

**Book's key SQS lessons:**

**Visibility timeout:** When a consumer reads a message, it becomes invisible to other consumers for the visibility timeout duration. If the consumer crashes before deleting, the message becomes visible again after the timeout. Set visibility timeout to 6× the expected processing time.

**Long polling:** `ReceiveMessage` waits up to 20 seconds for a message (vs short polling that returns immediately even if empty). Reduces empty receives by 99%, lowers cost and latency.

**Message ordering guarantee:**
- Standard SQS: best-effort ordering. Messages may arrive out of order or be delivered more than once.
- FIFO SQS: strict ordering within a Message Group ID. Exactly-once processing (within 5-minute deduplication window).
- If you need ordering: use FIFO, or use Kinesis (shard-level ordering), or include a sequence number in the message payload and handle out-of-order in the consumer.

---

## Part 4: Architecting on AWS

### Chapter 13 — High Availability: AZs, Auto Scaling, CloudWatch

#### The Multi-AZ Architecture Pattern

HA on AWS = deploy across at least 2 AZs. The canonical HA pattern:

```
Region: us-east-1
  AZ-1a:
    - Public subnet: ALB node
    - Private subnet: EC2 / ECS tasks
    - Data subnet: RDS Primary
  AZ-1b:
    - Public subnet: ALB node
    - Private subnet: EC2 / ECS tasks
    - Data subnet: RDS Standby
```

**The critical constraint:** both AZs must be active (active-active) for EC2/ECS. RDS Multi-AZ is active-passive (standby is not serving requests). Design for AZ failure: if 1 of 2 AZs goes down, remaining AZ must handle 100% of traffic.

**Capacity planning for AZ failure:**
```
Normal: 2 AZs, 4 instances each = 8 total. Load per instance: X/8.
Failure: 1 AZ down. Remaining: 4 instances must handle X load.
Each surviving instance handles 2× normal load.
→ Provision for 2× peak in each AZ, or set min ASG = 2 per AZ.
```

#### Auto Scaling Groups (ASG)

ASG manages a fleet of EC2 instances, automatically replacing unhealthy instances and scaling based on load.

**Health check types:**
- **EC2 health check:** instance running + basic system checks pass
- **ELB health check:** instance passes ELB target group health check (your HTTP endpoint)

Always use ELB health check in production. An instance can be EC2-healthy but serving 500 errors — ELB health check catches this.

**Scaling policies:**
| Policy | Behavior | Use case |
|--------|----------|----------|
| Target Tracking | Maintain CPU/network at target (e.g., 60% CPU) | Most use cases |
| Step Scaling | Step-wise increase/decrease based on alarm thresholds | Workloads with distinct patterns |
| Scheduled | Add/remove capacity on a schedule | Predictable load patterns (business hours) |
| Predictive Scaling | ML-based pre-scaling before predicted load | Recurring spiky workloads |

**Target tracking preferred:** AWS manages the PID controller. You declare the desired metric (CPU 60%, ALB requests per target = 1,000), and ASG continuously adjusts capacity.

**Scale-in protection:** Mark specific instances as protected to prevent them from being terminated during scale-in (useful for long-running batch jobs in progress on that instance).

**Lifecycle hooks:** Execute actions before an instance enters/exits service:
```
Instance launch:
  Pending → Pending:Wait [your code: install software, register with service discovery] → InService

Instance terminate:
  Terminating → Terminating:Wait [your code: drain connections, flush state] → Terminated
```

**Instance warmup time:** Prevents newly launched instances from triggering another scale-out by holding metrics during warmup.

#### CloudWatch

CloudWatch is the observability plane for AWS. Three pillars:

**1. Metrics**
- Every AWS service publishes default metrics (CPUUtilization, RequestCount, etc.)
- Custom metrics via PutMetricData API or CloudWatch agent
- Resolution: 1-minute standard, 1-second high-resolution (at extra cost)
- Retention: 1-second for 3h, 1-min for 15d, 5-min for 63d, 1h for 15 months

**EMF (Embedded Metrics Format):** Emit structured logs; CloudWatch automatically extracts custom metrics from log patterns. Zero additional API calls, zero additional cost beyond log storage.

```python
import json
print(json.dumps({
    "_aws": {"Timestamp": 1719000000000, "CloudWatchMetrics": [
        {"Namespace": "MyApp", "Dimensions": [["Service"]], "Metrics": [{"Name": "OrderCount", "Unit": "Count"}]}
    ]},
    "Service": "OrderService",
    "OrderCount": 42
}))
```

**2. Alarms**
- Evaluate a metric against a threshold; transition: OK → ALARM → INSUFFICIENT_DATA
- Actions: send SNS notification, trigger ASG scaling, stop/terminate/reboot EC2
- **Composite alarms:** combine multiple alarms with AND/OR logic to reduce alert noise
- **Anomaly detection:** ML-based alarm that learns the metric's normal band, alerts on deviations

**3. Logs**
- Log groups → log streams (one per instance/function/container)
- Retention: 1 day to indefinite (default: indefinite — set retention to control cost)
- **CloudWatch Logs Insights:** SQL-like query language for log analysis across log groups
- **Subscription filters:** stream logs in real-time to Kinesis, Lambda, or OpenSearch
- **Metric filters:** extract metric values from log patterns (e.g., count of "ERROR" log lines → ErrorCount metric)

**Key operational metrics (principal engineer should know by heart):**

| Service | Critical metric | Alarm |
|---------|-----------------|-------|
| EC2 | CPUUtilization | >80% sustained 5 min |
| RDS | DatabaseConnections | >80% max_connections |
| ALB | TargetResponseTime | P99 >500ms |
| Lambda | Errors | >1% error rate |
| SQS | ApproximateAgeOfOldestMessage | >60s (consumer falling behind) |
| DynamoDB | ThrottledRequests | >0 |

---

### Chapter 14 — Decoupling Infrastructure: ELB and Async Patterns

#### Elastic Load Balancing

**ALB (Application Load Balancer):**
- Layer 7 (HTTP/HTTPS/gRPC)
- Route by path, host, HTTP headers, query strings, source IP
- Target types: EC2 instances, ECS tasks, Lambda functions, IP addresses
- Sticky sessions (cookie-based)
- WebSocket and HTTP/2 support
- Built-in WAF integration

**NLB (Network Load Balancer):**
- Layer 4 (TCP/UDP/TLS)
- Preserves source IP (ALB does not — use X-Forwarded-For header)
- Ultra-low latency (<1ms) — no connection termination
- Static IP per AZ (can be Elastic IPs — required for IP allowlisting)
- Handle millions of connections per second

**ALB vs NLB decision:**
- HTTP/HTTPS → ALB (content routing, WAF)
- Preserve source IP, UDP, static IP, PrivateLink → NLB
- gRPC → ALB (with HTTP/2)
- Non-HTTP protocols (MQTT, custom TCP) → NLB

**Connection draining (deregistration delay):**
- When an instance is deregistered (scale-in, deployment), ALB stops sending new requests
- Waits up to 300s (configurable) for in-flight requests to complete
- Critical for zero-downtime deployments — don't set to 0 unless requests are trivially short

#### The Async Decoupling Pattern

The book's central architecture principle: **decouple producers from consumers with a queue**.

```
Synchronous (tightly coupled):
  Web server → directly calls image processor → blocks until done → user waits 30s

Asynchronous (decoupled via SQS):
  Web server → enqueue job to SQS → return 202 immediately (user sees "processing")
  Worker → poll SQS → process image → update status
```

Benefits:
1. **Resilience:** if processor is down, jobs queue up; no requests lost
2. **Load leveling:** web servers at peak throughput, workers process at their own pace
3. **Independent scaling:** scale workers based on queue depth; web servers scale based on HTTP traffic
4. **Retry:** SQS retries on worker failure up to DLQ threshold

**Queue depth alarm:**
```
Alarm: ApproximateNumberOfMessagesVisible > threshold
Action: scale-out worker ASG

Scale in: workers drain the queue faster, queue depth drops, scale in
```

This is **queue-depth based auto-scaling** — the correct pattern for batch-processing architectures.

---

### Chapter 15 — Scaling: Horizontal vs Vertical

#### Horizontal vs Vertical Scaling

| Dimension | Vertical (Scale Up) | Horizontal (Scale Out) |
|-----------|---------------------|------------------------|
| Mechanism | Larger instance | More instances |
| Downtime | Yes (instance stop/start) | No (rolling) |
| Limit | Max instance size in family | Nearly unlimited |
| Cost | Linear per instance | Linear per instance, but distributes |
| State | Easier (single instance) | Harder (stateless required) |
| Suitable for | DB primaries, single-node services | Web/app tier, stateless workers |

**Stateless design is a prerequisite for horizontal scaling:**
- No local session state → use ElastiCache or DynamoDB
- No local file storage → use S3 or EFS
- No local in-memory caches with global state → use Redis
- Configuration → environment variables or Parameter Store, not config files

**Database scaling:**
- Vertical first (easy, no architecture change) — RDS supports online instance class change (Multi-AZ: no downtime; Single-AZ: brief outage)
- Read replicas for read scaling
- Write scaling: hardest — requires sharding (application-level) or switching to DynamoDB/Aurora DSQL
- **Sharding** is a last resort for relational DBs: pick shard key carefully (even distribution, no cross-shard queries), implement at application layer, migrations become very expensive

---

### Chapter 16 — Designing for Fault Tolerance

#### Core Fault Tolerance Principles

**1. Accept failure, design for recovery, not prevention**
AWS infrastructure fails. Disks fail, instances fail, AZs fail, regions fail. Architect assuming each component will fail at the worst possible time.

**2. Idempotency**
Operations should produce the same result when retried:
```
Bad:  POST /order → creates a new order each time (double-charge on retry)
Good: PUT /order/{idempotency-key} → creates order if not exists, no-ops if already created
```
Use idempotency keys (UUID generated by client) stored in DynamoDB. DynamoDB conditional write ensures at-most-once creation.

**3. Retry with exponential backoff + jitter**
```python
import random, time
for attempt in range(max_attempts):
    try:
        return make_api_call()
    except ThrottlingException:
        sleep_time = (2 ** attempt) + random.uniform(0, 1)  # jitter
        time.sleep(sleep_time)
raise MaxRetriesExceeded()
```
Without jitter: all retrying clients synchronize and create a thundering herd. Full jitter breaks the synchronization.

**4. Circuit breaker**
Prevent cascading failures. If a downstream service is failing, stop calling it immediately:
```
Closed (normal): requests flow through
Open (failure detected): requests fail-fast without calling downstream
Half-Open (probe): periodic test request — if success, move to Closed
```
Libraries: Resilience4j (Java), pybreaker (Python). AWS has no native circuit breaker — implement in code or use a service mesh (App Mesh/Istio).

**5. Graceful degradation**
When a component fails, serve degraded (but functional) responses:
```
Search service down → show "search unavailable" instead of 500
Recommendation service down → show popular items instead of personalized
Payment service slow → queue the request, show "processing" status
```

**6. Chaos engineering**
Deliberately inject failures to test resilience:
- Terminate random EC2 instances (Netflix Chaos Monkey approach)
- AWS Fault Injection Service (FIS): managed chaos experiments — stop instances, throttle APIs, inject network latency
- Run game days: simulate AZ failure, test actual RTO/RPO

**The operational runbook for AZ failure:**
```
Trigger: AZ-1a loses power
Expected behavior:
  1. ALB health checks detect unhealthy targets in AZ-1a (30s)
  2. ALB stops routing to AZ-1a (immediate after health check)
  3. ASG detects unhealthy instances, launches replacements in AZ-1b and AZ-1c (2-5 min)
  4. RDS fails over to standby in AZ-1b (60-120s)
Actual RTO: 2-5 minutes for full capacity restoration
Verify: run AZ failure game day quarterly
```

---

## Part 5: Managing and Securing Your AWS Infrastructure

### Chapter 17 — Containers: ECS and Docker

*(Detailed in `ecs.md` and `eks.md` in CloudArchitecture/aws/.)*

**Book's key container lessons:**

**Task definition:** The container spec — image, CPU/memory, port mappings, environment variables, logging, volumes, IAM task role.

```json
{
  "family": "api-task",
  "cpu": "512",
  "memory": "1024",
  "taskRoleArn": "arn:aws:iam::123:role/api-task-role",
  "containerDefinitions": [{
    "name": "api",
    "image": "123.dkr.ecr.us-east-1.amazonaws.com/api:v1.2.3",
    "portMappings": [{"containerPort": 8080}],
    "environment": [{"name": "ENV", "value": "prod"}],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {"awslogs-group": "/ecs/api", "awslogs-region": "us-east-1", "awslogs-stream-prefix": "ecs"}
    }
  }]
}
```

**Fargate vs EC2 launch type:**
- **Fargate:** serverless — AWS manages the underlying EC2 instances. You define CPU/memory per task. No cluster capacity management. Higher cost-per-task, zero ops.
- **EC2 launch type:** you manage the EC2 cluster (instance types, scaling). Lower cost for sustained workloads, higher ops overhead.

**ECR (Elastic Container Registry):** Private container image registry. Integrates with ECS/EKS natively — no Docker Hub credentials needed. Enable image scan-on-push (uses Clair vulnerability scanner). Set lifecycle policies to expire old images.

**Service auto scaling:** ECS services scale based on CloudWatch metrics:
- CPU/memory utilization (task-level)
- Custom metrics (queue depth, request count)
- Target tracking: maintain CPU at 60% → add/remove tasks

---

### Chapter 18 — Protecting Your Data: Encryption and KMS

#### Encryption at Rest

**AWS Key Management Service (KMS):**
- Manage cryptographic keys centrally
- Keys never leave KMS in plaintext — all encrypt/decrypt operations happen inside KMS hardware
- **CMK (Customer Managed Key):** you create, control, and can audit usage in CloudTrail
- **AWS Managed Key:** AWS creates and manages for a service (e.g., `aws/s3`, `aws/rds`). Less control, free.
- **Key rotation:** CMKs can auto-rotate annually. Old key material is retained for decryption of old data.

**Envelope encryption (the pattern KMS uses):**
```
1. Application requests DataKey from KMS
2. KMS generates: {plaintext DataKey, encrypted DataKey (wrapped with CMK)}
3. Application uses plaintext DataKey to encrypt data
4. Application stores: {encrypted data, encrypted DataKey}
5. Discard plaintext DataKey (never persisted)
6. Decryption: send encrypted DataKey to KMS → receive plaintext DataKey → decrypt data
```

This pattern means:
- The CMK never touches your data directly
- KMS processes only tiny DataKey operations (not your large data)
- You can re-encrypt (rotate) just by calling KMS with the old encrypted DataKey, getting a new one, without re-encrypting the data

**Key policies:** KMS keys have resource-based policies controlling who can use/manage them. Never make the CMK policy too permissive — use fine-grained conditions.

#### Encryption in Transit

**TLS everywhere:**
- ALB: terminate TLS at ALB (ACM certificates — free, auto-renew), forward HTTP or TLS to targets
- RDS: enforce SSL connections (parameter group `rds.force_ssl`)
- ElastiCache Redis: in-transit encryption (enable at cluster creation)
- S3: enforce HTTPS only via bucket policy condition `aws:SecureTransport`

**ACM (AWS Certificate Manager):** Free TLS certificates for ALB, CloudFront, API Gateway. Auto-renews. Cannot export the private key (designed for use with AWS services only). For non-AWS services, use Let's Encrypt.

---

### Chapter 19 — Controlling Access: IAM Deep Dive

*(Core concepts covered in `iam.md`.)*

**Book's advanced IAM lessons:**

**Cross-account access (role assumption):**
```
Account A (production) has resources.
Account B (developer laptops) has IAM users.

Setup:
  1. Create role in Account A: trust policy allows Account B principal to assume it
  2. Attach permissions policy to role: what the role can do in Account A
  3. Developers in Account B: `aws sts assume-role --role-arn arn:aws:iam::AccountA:role/DevRole`
  4. Receive temporary credentials (valid 1-12 hours)
  5. Use credentials to call Account A APIs
```

This enables: developers never have long-term credentials to production. All production access is via assumed role, auditable in CloudTrail.

**SCPs (Service Control Policies):**
Applied at Organization level. Act as guardrails — even if an account's IAM policy allows an action, the SCP can block it:
```json
{
  "Effect": "Deny",
  "Action": ["ec2:RunInstances"],
  "Resource": "*",
  "Condition": {"StringNotEquals": {"ec2:Region": ["us-east-1", "eu-west-1"]}}
}
```
This SCP prevents launching EC2 in any region other than us-east-1 and eu-west-1 — enforces data sovereignty across all accounts in the OU.

**AWS Organizations best practices:**
```
Root
├── Management Account (billing only, no workloads)
├── Security OU
│   ├── Security Tooling Account (GuardDuty master, Security Hub master, CloudTrail aggregator)
│   └── Log Archive Account (centralized CloudTrail, Config, VPC Flow Logs storage)
├── Infrastructure OU
│   └── Shared Services Account (Route 53, ECR, Artifact registries)
├── Workload OU
│   ├── Dev Account
│   ├── Staging Account
│   └── Production Account
```

Separate accounts = blast radius containment. A compromised Dev account can't touch Production. S3 bucket name conflicts don't exist across accounts.

---

### Chapter 20 — Limits and Cost Management

#### Service Quotas (formerly Limits)

Every AWS service has quotas — request increases before you need them, not during an incident:
- EC2: running instance vCPUs per region (default 32–64 depending on account age)
- Lambda: concurrent executions (1,000 default)
- API Gateway: requests/s (10,000 default)
- ELB: load balancers per region (50 default)

**Process:** AWS Console → Service Quotas → select service → Request increase → fill reason. Plan capacity 6-8 weeks ahead for high-traffic events.

#### Cost Optimization Framework

**The four levers:**

1. **Right-sizing:** Use CloudWatch metrics + Compute Optimizer to find over-provisioned instances. EC2 Compute Optimizer analyzes vCPU/memory usage and recommends the optimal instance type.

2. **Purchasing model:** Match commitment to workload:
   - Steady-state: Reserved (1-year convertible) or Compute Savings Plans
   - Variable: On-Demand
   - Fault-tolerant batch: Spot (up to 90% off)

3. **Unused/idle resources:** EBS volumes attached to stopped instances, idle RDS instances, old snapshots, data transfer between AZs. AWS Trusted Advisor identifies these.

4. **Storage tier optimization:** S3 Intelligent-Tiering, RDS storage auto-scaling, Glacier for old backups.

**Cost Explorer:** Visualize spending by service, account, region, tag. Identify cost anomalies. Forecast future spend.

**AWS Budgets:** Set spending thresholds and receive alerts:
- Cost budget: alert when actual or forecast exceeds $X
- Usage budget: alert when EC2 Spot usage drops (you're paying On-Demand unexpectedly)
- Reserved Instance coverage: alert when RI coverage drops below 80%

**Tagging strategy:** Tag every resource with: `Environment`, `Team`, `Project`, `CostCenter`. Enforce via Config rules or SCPs. Without consistent tags, cost attribution is guesswork.

```
aws:ResourceTag/Environment = prod
aws:ResourceTag/Team = platform
aws:ResourceTag/Project = auth-service
aws:ResourceTag/CostCenter = 42
```

**Trusted Advisor:** Automated best-practice checks across five categories:
- Cost Optimization (idle resources, RI recommendations)
- Performance (over-utilized instances, CloudFront config issues)
- Security (open SGs, MFA on root, key rotation)
- Fault Tolerance (no Multi-AZ, old snapshots)
- Service Limits (approaching quota limits)

Full Trusted Advisor requires Business or Enterprise Support plan ($100+/month).

---

## Key Architectural Patterns (Cross-Chapter)

### The Three-Tier Web Architecture (AWS Reference)

```
Internet
  ↓ HTTPS
Route 53 (DNS, latency routing, health checks)
  ↓
CloudFront (CDN, Lambda@Edge, WAF, TLS termination)
  ↓
ALB (path routing, target groups, health checks)
  ↓ HTTP
EC2 / ECS / EKS (stateless app tier, in private subnets)
  ├→ ElastiCache (session store, object cache)
  ├→ S3 (static assets, user uploads)
  ├→ SQS → Worker fleet → S3 / external API
  └→ RDS Aurora (primary: writes, replicas: reads, in data subnets)

All tiers: CloudWatch metrics + logs + alarms
IAM: least-privilege roles per service
```

### The Event-Driven Microservices Pattern

```
Service A → publishes event to EventBridge bus
  ↓ rule match
Service B (Lambda): reacts synchronously, fast processing
Service C (SQS → Worker): reacts async, heavy processing
Service D (Step Functions): reacts with multi-step workflow

All failures → DLQ → monitoring → alert
```

### The Data Lake Pattern

```
Raw sources → Kinesis Firehose → S3 (raw zone)
                               ↓
                         Glue Crawler (schema discovery)
                               ↓
                         Glue Data Catalog
                               ↓
                         Athena queries (SQL on S3)
                               ↓
                         QuickSight (BI dashboard)

Transformations:
  Glue ETL or EMR Spark → S3 (processed zone, Parquet/ORC)
```

---

## Principal Engineer Interview Takeaways

### The Decision Framework

Every architectural decision in this book follows the same structure:
1. **Understand the requirement** — throughput, latency, consistency, durability, scale, cost
2. **Identify the managed service** — don't build what AWS operates
3. **Design for failure** — what happens when each component fails?
4. **Measure and iterate** — capacity estimation first, then observe actual usage

### Services You Must Know Cold

| Service | Why it appears in every design |
|---------|-------------------------------|
| VPC | Every workload runs in a VPC |
| IAM | Every API call is authorized by IAM |
| EC2 / ECS / Lambda | Compute choice drives architecture |
| RDS Aurora / DynamoDB | Data tier — biggest architectural decision |
| S3 | Universal durable storage |
| CloudWatch | Observability plane |
| SQS / SNS / EventBridge | Decoupling and event routing |
| ALB / CloudFront | Traffic ingress |
| CloudFormation | Everything as code |

### The Book's Core Thesis for Principal Engineers

> "The cloud is not just a different data center — it is a different way of building systems. Infrastructure as code, managed services instead of self-operated ones, and assuming hardware failure as normal operation are the mental shifts that separate engineers who use the cloud from engineers who architect with it."

The second edition makes this concrete: every chapter ends with an operational example, not a theoretical diagram. The mark of a principal engineer is knowing not just *what* to choose, but *how to configure it, operate it, and debug it when it breaks*.

---

## Quick Reference Card

| Pattern | AWS Services | Key parameter |
|---------|-------------|---------------|
| Multi-AZ HA | ASG + ALB + RDS Multi-AZ | Min 2 AZs, health checks on ELB |
| Async decoupling | SQS + Lambda/EC2 workers | Visibility timeout = 6× processing time |
| Event fan-out | SNS → multiple SQS | Filter policies per subscriber |
| Caching | ElastiCache Redis | Cache-aside; TTL; eviction = allkeys-lru |
| Big data ingest | Kinesis Firehose → S3 | Buffer: 128 MB or 300s |
| Serverless API | API GW + Lambda | Concurrency limit, warm-up, DLQ |
| Container platform | ECS Fargate / EKS | Task roles, no hardcoded credentials |
| Secret management | Secrets Manager + KMS | Rotation enabled, no env var secrets |
| Compliance audit | CloudTrail + AWS Config | Multi-region, all services, S3 with lock |
| Cost governance | Budgets + Cost Explorer + Tags | Alert at 80% of budget |
