# Cloud Architecture

Cloud-native design patterns and platform-specific service selection. Principal engineers must speak fluently about cloud trade-offs without vendor lock-in bias.

## Sub-directories

| Folder | Contents |
|--------|----------|
| `aws/` | AWS service selection, well-architected patterns, cost optimization |
| `gcp/` | GCP-specific patterns (BigQuery, Spanner, Pub/Sub, GKE) |
| `azure/` | Azure patterns and enterprise integration |
| `multi-cloud/` | Multi-cloud strategy, portability, hybrid architectures |
| `patterns/` | Cloud-agnostic patterns: serverless, event-driven, IaC, GitOps |

## Critical Topics

### AWS (dominant at FAANG interviews)
- When to use SQS vs SNS vs EventBridge vs Kinesis
- RDS vs Aurora vs DynamoDB vs ElastiCache selection
- API Gateway vs ALB vs CloudFront routing decisions
- ECS vs EKS vs Lambda for compute

### Cloud-Agnostic Patterns
- **Cell-based architecture**: blast radius containment
- **Bulkhead pattern**: resource isolation
- **Saga pattern**: distributed transaction management
- **Outbox pattern**: reliable event publishing
- **CQRS + Event Sourcing**: read/write separation at scale
