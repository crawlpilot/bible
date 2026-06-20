# AWS VPC, Security Groups, NACLs & Network Architecture

## Overview
A **Virtual Private Cloud (VPC)** is a logically isolated virtual network in AWS. Every resource you launch lives inside a VPC. The VPC defines the IP address space (CIDR), availability zones, subnets, routing, and the layers of security controlling traffic flow.

**Key components**:
| Component | Role |
|---|---|
| VPC | IP address namespace + isolation boundary |
| Subnet | Subdivision of VPC CIDR tied to a single AZ |
| Route Table | Controls where traffic from a subnet is forwarded |
| Internet Gateway (IGW) | Enables internet access for public subnets |
| NAT Gateway | Outbound internet for private subnets; no inbound |
| Security Group | Stateful firewall at the ENI (instance/resource) level |
| Network ACL (NACL) | Stateless firewall at the subnet level |
| VPC Endpoint | Private connectivity to AWS services without internet |
| Transit Gateway | Hub-and-spoke VPC interconnect across accounts/regions |
| VPC Peering | Direct one-to-one VPC interconnect (non-transitive) |

---

## Architecture: Standard 3-Tier VPC Layout

```
VPC: 10.0.0.0/16
│
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24) — one per AZ
│   ├── Internet Gateway attached
│   ├── Route: 0.0.0.0/0 → IGW
│   └── Resources: ALB, NAT Gateway, Bastion (if any)
│
├── Private App Subnets (10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24)
│   ├── Route: 0.0.0.0/0 → NAT Gateway (in same AZ)
│   └── Resources: ECS tasks, EC2 instances, Lambda in VPC
│
└── Private Data Subnets (10.0.21.0/24, 10.0.22.0/24, 10.0.23.0/24)
    ├── No outbound internet route
    └── Resources: RDS, ElastiCache, Redshift
```

**Subnet CIDR sizing rules**:
- AWS reserves 5 IPs per subnet (first 4 + last 1)
- A /24 = 251 usable IPs; a /20 = 4,091 usable
- EKS node groups need large subnets — each pod gets an IP from the VPC CIDR (ENI prefix delegation)
- Plan for 3× growth; CIDR expansion requires secondary CIDR or re-IP

---

## Security Groups (SGs)

**What they are**: Stateful virtual firewalls attached to ENIs (Elastic Network Interfaces). Rules evaluated on every packet; return traffic is automatically allowed.

**Key properties**:
- **Stateful**: if you allow inbound port 443, the response is automatically allowed outbound
- **Whitelist only**: default deny all; you only write allow rules
- **Reference other SGs**: the most powerful feature — rule: "allow port 5432 from the app-sg" means any resource in app-sg, regardless of IP
- **Up to 5 SGs per ENI**; up to 60 inbound + 60 outbound rules per SG (soft limit)

**Design pattern — SG chaining**:
```
ALB-SG:
  Inbound: 443 from 0.0.0.0/0
  Outbound: 8080 to App-SG

App-SG:
  Inbound: 8080 from ALB-SG
  Outbound: 5432 to DB-SG, 443 to 0.0.0.0/0 (for outbound HTTPS)

DB-SG:
  Inbound: 5432 from App-SG
  Outbound: none needed (stateful)
```

**Best practices**:
- Never use `0.0.0.0/0` inbound except on ALBs/NLBs facing the internet
- Prefer SG-to-SG rules over CIDR rules — IPs change, SG membership doesn't
- Name SGs descriptively: `prod-api-ecs-sg`, not `sg-08f3a...`
- One SG per logical tier; do not share SGs across services
- Audit SG rules with AWS Config rule `restricted-ssh`, `restricted-rdp`

---

## Network ACLs (NACLs)

**What they are**: Stateless firewall at the subnet boundary. Evaluated in rule number order; first match wins.

**Key properties**:
- **Stateless**: you must explicitly allow both inbound AND return traffic (ephemeral ports 1024–65535)
- **Ordered rules**: lower rule number wins; explicit DENY rules are possible
- **Subnet-level**: applies to all resources in the subnet regardless of SG
- Default NACL: allows all traffic; custom NACL: denies all until rules added

**When NACLs add value over SGs**:
- Explicit DENY of known bad IP ranges (threat intelligence blocking)
- Defense-in-depth: NACL blocks traffic before it reaches the SG
- Compliance requirement for subnet-level controls (PCI-DSS, HIPAA)

**Ephemeral port rule** (most common NACL mistake):
```
Custom NACL — allow HTTPS inbound + return traffic:
  Inbound rule 100: ALLOW TCP 443 from 0.0.0.0/0
  Outbound rule 100: ALLOW TCP 1024-65535 to 0.0.0.0/0   ← MUST add; response uses ephemeral port
```

---

## VPC Endpoints

Eliminate internet/NAT Gateway path for AWS service calls. Significant cost and security benefit at scale.

| Endpoint type | Supported services | How it works |
|---|---|---|
| **Gateway endpoint** | S3, DynamoDB | Route table entry; free |
| **Interface endpoint (PrivateLink)** | 100+ services (SQS, SNS, ECR, Secrets Manager, etc.) | ENI in your subnet; ~$7.50/month/AZ |

**Cost impact of Gateway Endpoints**: S3 data transfer via NAT Gateway costs $0.045/GB. Gateway endpoint to S3 is free. For services processing TBs of S3 data, this is a significant cost line.

**PrivateLink for inter-VPC**: Expose a service in VPC-A as a PrivateLink endpoint; consumers in VPC-B connect without VPC peering, no overlapping CIDR conflicts.

---

## NAT Gateway

Provides outbound internet for private subnets. **Managed by AWS** — no patching, auto-scales.

**Tuning and cost**:
- Deploy one NAT Gateway **per AZ** (not per VPC) — cross-AZ data transfer costs $0.01/GB; a single NAT Gateway in us-east-1a serves all traffic from us-east-1b incurs this cost
- NAT Gateway: $0.045/hr (~$32/month) + $0.045/GB processed data
- For high-throughput (>10 Gbps sustained), NAT Gateway scales automatically up to 100 Gbps per gateway
- For extremely cost-sensitive workloads: NAT Instance (EC2) gives control but requires management

**High availability pattern**:
```
AZ-1: Private Subnet → Route Table → NAT-GW-1 (in Public Subnet AZ-1)
AZ-2: Private Subnet → Route Table → NAT-GW-2 (in Public Subnet AZ-2)
AZ-3: Private Subnet → Route Table → NAT-GW-3 (in Public Subnet AZ-3)
```
Each AZ has its own NAT Gateway and its own route table pointing to it. AZ failure does not affect other AZs.

---

## Transit Gateway (TGW)

Hub-and-spoke model for connecting many VPCs and on-premise networks.

**When to use TGW over VPC Peering**:
| | VPC Peering | Transit Gateway |
|---|---|---|
| Topology | Mesh (N×(N-1)/2 connections) | Hub-and-spoke (N connections) |
| Transitivity | Non-transitive | Transitive routing |
| Cross-account | Yes | Yes (Resource Access Manager) |
| Bandwidth | Unlimited | Up to 50 Gbps/attachment |
| Cost | Free (data transfer only) | $0.05/hr/attachment + $0.02/GB |
| Use when | <5 VPCs, no need for full routing control | >5 VPCs, shared services, hybrid |

**TGW Route Tables**: Segment traffic between VPCs using multiple route tables (e.g., prod VPCs cannot route to dev VPCs via TGW route table isolation).

---

## Key Tuning Parameters

| Parameter | Default | Recommendation |
|---|---|---|
| VPC CIDR | /16 | Reserve /16 per environment; use RFC 1918 (10.x.x.x) |
| Subnet size | /24 | Use /20–/22 for EKS node subnets; /24 for app; /27 for infra |
| SG rules per SG | 60 | If approaching limit, decompose into multiple SGs |
| SG per ENI | 5 | Design SG hierarchy to stay ≤ 3 per resource |
| NACLs rules | 20 (default) | Increase via support ticket; keep rules minimal |
| VPC Flow Logs | Disabled | Enable on ALL VPCs in production; send to S3 for cost |
| DNS hostnames | Disabled by default | Enable for RDS, EFS, PrivateLink to resolve |
| DNS resolution | Enabled | Keep enabled; required for Route 53 resolver |

---

## Monitoring

| Metric/Log | Source | Alert condition |
|---|---|---|
| VPC Flow Logs | CloudWatch Logs / S3 | REJECT traffic from unexpected CIDRs |
| NAT Gateway bytes processed | CloudWatch `BytesOutToDestination` | Sudden spike → data exfiltration or misconfigured loop |
| NAT Gateway error count | `ErrorPortAllocation` | Port exhaustion → increase NAT Gateway count |
| VPC endpoint utilisation | CloudWatch `BytesProcessed` | Cost tracking |
| Network performance | EC2 `NetworkIn/Out` | Near baseline network limit |
| Security Hub finding | AWS Security Hub | Unrestricted inbound SSH/RDP SG rule |

**VPC Flow Log query (Athena)**:
```sql
SELECT srcaddr, dstaddr, protocol, action, COUNT(*) AS count
FROM vpc_flow_logs
WHERE action = 'REJECT' AND day = '2024/01/15'
GROUP BY 1,2,3,4 ORDER BY count DESC LIMIT 20;
```

---

## Best Practices

1. **One VPC per environment** (prod/staging/dev) in separate AWS accounts (AWS Organizations) — blast radius isolation
2. **Never use the default VPC** in production — it has permissive defaults (all instances get public IPs)
3. **Enable VPC Flow Logs** from day one — retro-enabling after an incident is too late
4. **Use private subnets for everything** except load balancers and NAT gateways
5. **Tag every subnet** with `Tier=public/private/data` and `AZ=us-east-1a` — simplifies automation
6. **Use VPC Endpoints** for S3, DynamoDB, SQS, SNS, ECR — remove NAT Gateway from critical data paths
7. **Separate route tables per subnet** — don't share route tables between public and private subnets
8. **Plan CIDR ranges with future in mind** — mergers, multi-region, Direct Connect all require non-overlapping CIDRs
9. **Prefer SG references over CIDR rules** — SG membership is dynamic; IP addresses change
10. **Security Hub + AWS Config rules** to continuously audit SG permissiveness

---

## FAANG Interview Patterns

**"Design the network for a multi-tier web application"**: Answer with the 3-tier layout above. Always mention: public subnets for ALB only, private subnets for compute, isolated data subnets for databases, NAT Gateway per AZ, VPC Endpoints for S3/DynamoDB.

**"How do you securely connect 50 VPCs across 10 AWS accounts?"**: Transit Gateway + AWS Organizations + TGW route table segmentation. Not VPC Peering (N² connections). Add AWS Network Firewall on the TGW for centralized inspection.

**"A Lambda function can't reach RDS — troubleshoot"**: Check (1) Lambda in VPC? (2) Same VPC as RDS? (3) SG on Lambda allows outbound 5432? (4) RDS SG allows inbound from Lambda SG? (5) Route table has a route to the subnet? (6) NACL allows ephemeral ports?

**"How do you reduce NAT Gateway costs?"**: VPC Endpoints for AWS services (S3, DynamoDB free; PrivateLink services ~$7.50/month/AZ cheaper than NAT data charges at scale). Move workloads to public subnets only if they truly need inbound access. Use S3 Gateway Endpoint for all S3 traffic from private subnets.
