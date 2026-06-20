# AWS Cloud Architecture Reference

Deep-dive files for every major AWS service — covering overview, architecture, use cases, tuning parameters, monitoring, best practices, patterns, and FAANG interview callouts.

---

## Service Index

### Compute
| File | Services Covered | Key Topics |
|---|---|---|
| [lambda.md](lambda.md) | Lambda, SnapStart, Lambda@Edge, CloudFront Functions, Powertools | Cold starts, concurrency model, ESM, VPC Lambda, layers, function URLs |
| [ec2-ami.md](ec2-ami.md) | EC2 instance types, AMIs, EC2 Image Builder, EBS | Graviton, Spot/Reserved/Savings Plans, golden AMI, IMDSv2 |
| [ec2-asg.md](ec2-asg.md) | Auto Scaling Groups, Launch Templates, Scaling Policies | Target tracking, mixed Spot/On-Demand, instance refresh, lifecycle hooks |
| [ecs.md](ecs.md) | ECS, Fargate, ECR, ECS Service Auto Scaling | Fargate vs EC2, blue/green deploy, task roles, Container Insights |
| [eks.md](eks.md) | EKS, Karpenter, VPC CNI, IRSA, Add-ons | IRSA, prefix delegation, Karpenter, NetworkPolicy, Pod Security Admission |

### Databases & Caching
| File | Services Covered | Key Topics |
|---|---|---|
| [dynamodb.md](dynamodb.md) | DynamoDB, DAX, Global Tables, DynamoDB Streams | Partition key design, GSI/LSI, single-table design, hot partition mitigation |
| [rds-aurora.md](rds-aurora.md) | RDS Multi-AZ, Aurora Serverless v2, Aurora Global DB, RDS Proxy, Aurora DSQL | Shared storage architecture, read replicas, connection pooling, blue/green |
| [elasticache.md](elasticache.md) | ElastiCache Redis, ElastiCache Serverless, MemoryDB | Caching patterns, cluster mode, sorted sets, rate limiting, eviction policies |

### Networking & CDN
| File | Services Covered | Key Topics |
|---|---|---|
| [vpc-networking.md](vpc-networking.md) | VPC, Subnets, Security Groups, NACLs, NAT Gateway, Transit Gateway, VPC Endpoints | Network topology, SG chaining, NACL rules, TGW segmentation |
| [gateways.md](gateways.md) | API Gateway, ALB, NLB, IGW, NAT GW, TGW, GWLB, VPC Endpoints | REST vs HTTP API, ALB routing, NLB for PrivateLink, gateway decision matrix |
| [cloudfront-route53.md](cloudfront-route53.md) | CloudFront, Origin Shield, Lambda@Edge, Route 53 routing policies | Signed URLs, cache behaviors, latency/failover/geolocation routing, health checks |

### Messaging & Event-Driven
| File | Services Covered | Key Topics |
|---|---|---|
| [eventbridge.md](eventbridge.md) | EventBridge, EventBridge Pipes, Scheduler, Schema Registry, Archive & Replay | Content-based routing, vs SNS/SQS/Kinesis, choreography vs orchestration |
| [sqs.md](sqs.md) | SQS Standard, SQS FIFO | Standard vs FIFO, DLQ, Lambda ESM, partial batch failure, throughput scaling |
| [sns.md](sns.md) | SNS Standard, SNS FIFO, Mobile Push | Fan-out, filter policies, SNS vs EventBridge, mobile push at scale |
| [kinesis.md](kinesis.md) | Kinesis Data Streams, Kinesis Firehose | Shards, partition keys, enhanced fan-out, Firehose dynamic partitioning |
| [step-functions.md](step-functions.md) | Step Functions Standard & Express | Saga pattern, choreography vs orchestration, Distributed Map, `.waitForTaskToken` |

### Storage & Analytics
| File | Services Covered | Key Topics |
|---|---|---|
| [s3.md](s3.md) | S3, S3 Glacier, S3 Intelligent-Tiering | Storage classes, lifecycle, Parquet data lake, security model, presigned URLs |
| [athena.md](athena.md) | Athena, Glue Data Catalog | Parquet optimisation, partition projection, CTAS, federated query, cost control |

### Security & Identity
| File | Services Covered | Key Topics |
|---|---|---|
| [iam.md](iam.md) | IAM, SCPs, Permissions Boundaries, ABAC | Policy evaluation, IRSA, ABAC, SCPs, privilege escalation prevention |

### Observability
| File | Services Covered | Key Topics |
|---|---|---|
| [cloudwatch.md](cloudwatch.md) | CloudWatch Metrics, Logs, Alarms, Dashboards, Synthetics | EMF, Logs Insights, composite alarms, anomaly detection, Container Insights |

---

## Key AWS Decision Matrices

### Compute Selection
```
Serverless (no infra management)?
  → Lambda (event-driven, <15 min) or Fargate (containerised, any duration)

Containers with Kubernetes ecosystem?
  → EKS (+ Karpenter for nodes)

Containers without Kubernetes?
  → ECS on Fargate (simplest) or ECS on EC2 (cost-dense workloads)

VMs for legacy apps or GPU/HPC?
  → EC2 in ASG (+ Graviton for cost)
```

### Messaging Selection
```
Need message persistence + replay?
  → Kafka (MSK) or Kinesis Data Streams

Simple queue (one consumer processes each message)?
  → SQS (Standard for throughput, FIFO for ordering)

Fan-out to multiple independent consumers?
  → SNS → multiple SQS queues

Complex routing rules + schema registry + replay?
  → EventBridge

Deliver stream to S3/Redshift/OpenSearch?
  → Kinesis Firehose
```

### Storage Selection
```
Object storage (data lake, artifacts, backups)?
  → S3

Block storage (EC2 database, OS volume)?
  → EBS (gp3 default)

Shared filesystem (multiple EC2/ECS/EKS)?
  → EFS

Relational, high-performance, autoscaled?
  → Aurora Serverless v2

Key-value, single-digit ms, infinite scale?
  → DynamoDB
```

---

## Critical Numbers to Know

| Service | Key limit / number |
|---|---|
| SQS message size | 256 KB (use S3 Claim Check for larger) |
| SQS FIFO throughput | 3,000 msg/s with batching; 300 msg/s without |
| SNS message size | 256 KB |
| Lambda payload | 6 MB sync; 256 KB async |
| Lambda max timeout | 15 minutes |
| Lambda default concurrency | 1,000 (account) |
| Lambda burst scaling | 500–3,000 concurrent/minute (region dependent) |
| Lambda max memory | 10,240 MB → 6 vCPU |
| S3 PUT/DELETE per prefix | 3,500/s |
| S3 GET per prefix | 5,500/s |
| Kinesis shard write | 1 MB/s, 1,000 records/s |
| Kinesis shard read | 2 MB/s (shared) |
| Step Functions payload | 256 KB per state |
| API Gateway REST timeout | 29 seconds (hard limit) |
| ALB target group health check | configurable 2-120s interval |
| EKS max pods per node (prefix delegation) | ~110 (m5.xlarge with prefix) |
| Fargate task max CPU | 16 vCPU |
| Fargate task max memory | 120 GB |
| DynamoDB item size | 400 KB max |
| DynamoDB partition throughput | 3,000 RCU or 1,000 WCU (hard limit per partition) |
| DynamoDB GSI max | 20 per table (soft limit) |
| Aurora max read replicas | 15 (Aurora) vs 5 (RDS) |
| Aurora replication lag | Near-zero (shared storage, vs async for RDS) |
| Aurora Global DB replication lag | <1 second typical |
| ElastiCache Redis cluster max shards | 500 nodes (250 shards × 2 replicas) |
| EventBridge max event size | 256 KB |
| EventBridge default throughput | 10,000 events/s per bus (soft limit) |
| EventBridge rule targets | 5 per rule |
| CloudFront max file size (cache) | 30 GB |
| Route 53 health check interval | 10s (fast) or 30s (standard) |

---

## FAANG Interview Quick-Reference

| Common question | File to review |
|---|---|
| SQS vs SNS vs Kinesis vs EventBridge | sqs.md, sns.md, kinesis.md, eventbridge.md |
| How to design a microservices network | vpc-networking.md, gateways.md |
| Saga pattern for distributed transactions | step-functions.md, eventbridge.md |
| Data lake query optimisation | s3.md, athena.md |
| Zero-downtime deployments | ecs.md, ec2-asg.md, eks.md, rds-aurora.md |
| Secure AWS access for containers | iam.md, ecs.md, eks.md |
| Cost optimisation for compute | ec2-ami.md, ec2-asg.md, ecs.md, lambda.md |
| Observability strategy | cloudwatch.md, lambda.md (Powertools) |
| Caching strategy (cache-aside, write-through) | elasticache.md |
| Serverless compute trade-offs | lambda.md |
| DynamoDB key design / hot partitions | dynamodb.md |
| Relational DB: RDS vs Aurora vs DynamoDB | rds-aurora.md, dynamodb.md |
| Global latency reduction / CDN | cloudfront-route53.md |
| DNS routing for multi-region failover | cloudfront-route53.md |
| Event-driven architecture patterns | eventbridge.md, step-functions.md |
| Leaderboard / rate limiter design | elasticache.md, dynamodb.md |
