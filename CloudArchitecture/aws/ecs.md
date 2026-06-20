# AWS ECS (Elastic Container Service)

## Overview
ECS is AWS's native container orchestration service. It manages the scheduling, placement, networking, scaling, and health of Docker containers on two compute substrates: **Fargate** (serverless) and **EC2** (self-managed nodes).

ECS is simpler to operate than EKS (Kubernetes) — no control plane to manage, no etcd, no kubectl learning curve. It integrates natively with all AWS services.

---

## Core Concepts

| Concept | Description |
|---|---|
| **Cluster** | Logical grouping of compute capacity (Fargate or EC2 nodes) |
| **Task Definition** | Blueprint for a container group: image, CPU, memory, networking, env vars, IAM role |
| **Task** | A running instance of a task definition (one or more containers) |
| **Service** | Maintains a desired count of tasks; integrates with ALB; handles rolling deploys |
| **Container Definition** | Per-container config within a task definition: image, ports, CPU/memory, health check |
| **Task Role** | IAM role assumed by the running task (for AWS API calls) |
| **Task Execution Role** | IAM role ECS agent uses to pull images and write logs |

---

## Fargate vs EC2 Launch Type

| Dimension | Fargate | EC2 |
|---|---|---|
| **Node management** | None — AWS manages | You manage ASG of EC2 instances |
| **Bin packing** | Per-task CPU/memory allocation | Multiple tasks share a node |
| **Isolation** | VM-level isolation per task (Firecracker microVM) | Container-level isolation (shared kernel) |
| **Cost** | $0.04048/vCPU-hr + $0.004445/GB-hr | EC2 instance cost; more efficient at high density |
| **Scaling speed** | Fast (~30s task launch) | Slower (must launch EC2 + ECS agent registers) |
| **GPU/custom** | No GPU support | Full EC2 instance capabilities (GPU, EFA) |
| **EBS volumes** | Ephemeral only (20–200 GB task storage) | Mount EBS volumes |
| **Use when** | Most workloads; serverless simplicity | GPU workloads; cost-sensitive high-density; EBS required |

**Fargate Spot**: up to 70% cheaper than Fargate On-Demand. Use for batch, background jobs, dev/test. Handle Fargate Spot interruptions via SIGTERM handler in your application.

---

## Task Definition

```json
{
  "family": "payments-api",
  "taskRoleArn": "arn:aws:iam::...:role/payments-task-role",
  "executionRoleArn": "arn:aws:iam::...:role/ecs-task-execution-role",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [{
    "name": "payments-api",
    "image": "123456789.dkr.ecr.us-east-1.amazonaws.com/payments-api:v1.2.3",
    "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
    "environment": [{"name": "ENV", "value": "prod"}],
    "secrets": [
      {"name": "DB_PASSWORD", "valueFrom": "arn:aws:secretsmanager:...:secret:payments-db-password"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/payments-api",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "healthCheck": {
      "command": ["CMD", "curl", "-f", "http://localhost:8080/health"],
      "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60
    },
    "readonlyRootFilesystem": true,
    "cpu": 512,
    "memory": 1024
  }]
}
```

**Key task definition settings**:
- `networkMode: awsvpc` — each task gets its own ENI and private IP. Required for Fargate; recommended for EC2. Enables SG-to-task security groups.
- `secrets` — inject secrets from Secrets Manager or SSM Parameter Store as environment variables. Never put secrets in environment variables directly.
- `readonlyRootFilesystem: true` — security hardening; application can't write to container filesystem
- `startPeriod` in healthCheck — grace period during container startup before health check failures count

---

## ECS Service: Deployment & Scaling

### Service Configuration
```json
{
  "serviceName": "payments-api-service",
  "cluster": "prod-cluster",
  "taskDefinition": "payments-api:5",
  "desiredCount": 6,
  "deploymentConfiguration": {
    "minimumHealthyPercent": 75,
    "maximumPercent": 200
  },
  "loadBalancers": [{
    "targetGroupArn": "arn:aws:elasticloadbalancing:...",
    "containerName": "payments-api",
    "containerPort": 8080
  }],
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["subnet-a", "subnet-b", "subnet-c"],
      "securityGroups": ["sg-payments"],
      "assignPublicIp": "DISABLED"
    }
  }
}
```

**Deployment parameters**:
- `minimumHealthyPercent`: during deploy, always keep at least this % of tasks healthy. `75` with `desiredCount=4` means at least 3 tasks must be running during replace
- `maximumPercent`: during deploy, can run at most this % over desired count. `200` = can double the task count temporarily during blue-green

### Deployment Types

| Type | Mechanism | Use case |
|---|---|---|
| **Rolling update** (default) | Replace old tasks with new tasks incrementally | Standard deploys; simple rollback (update task def version) |
| **Blue/Green (CodeDeploy)** | Launch full green deployment; shift traffic; terminate blue | Canary and linear traffic shifting; instant rollback |
| **External** | Your own deployment tool | Custom deployment pipelines (Spinnaker, Argo) |

**Blue/Green with CodeDeploy**:
1. ECS creates new "green" task set with new image
2. CodeDeploy shifts traffic: Canary10Percent5Minutes (10% for 5 min, then 100%) or Linear10PercentEvery1Minute
3. On success: old "blue" task set terminated
4. On alarm: automatic rollback to blue in seconds

### Service Auto Scaling
ECS service scales on CloudWatch metrics via Application Auto Scaling:

```json
{
  "PolicyType": "TargetTrackingScaling",
  "TargetTrackingScalingPolicyConfiguration": {
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }
}
```

**Custom metric scaling** (e.g., SQS queue depth):
```
Metric: SQS ApproximateNumberOfMessagesVisible / ECS service RunningTaskCount
Target: 10 (10 messages per task)
Scale out: add tasks when queue depth per task > 10
Scale in: remove tasks when queue depth per task < 2
```

---

## Networking Models

**awsvpc mode** (recommended): each task has its own ENI, private IP, and Security Group. Full VPC networking — apply task-level security groups, use VPC flow logs per task, SG references work task-to-task.

**bridge mode** (EC2 only): tasks share the host ENI; port mapping required. Multiple tasks of the same type on one instance requires dynamic port mapping. ALB uses dynamic port registration on the host. Complex; avoid for new designs.

**host mode** (EC2 only): task uses host network stack directly. For performance-critical workloads needing bare-metal network performance. Security risk: container and host share network namespace.

---

## Container Insights & Monitoring

Enable Container Insights on the cluster:
```bash
aws ecs update-cluster-settings --cluster prod-cluster \
  --settings name=containerInsights,value=enabled
```

**Key metrics**:
| Metric | Alert condition |
|---|---|
| `CpuUtilized` / `CpuReserved` | Utilization > 85% → scale out or resize |
| `MemoryUtilized` / `MemoryReserved` | > 90% → OOMKilled risk; increase memory or scale |
| `RunningTaskCount` | < `DesiredCount` → tasks failing health checks |
| `PendingTaskCount` | Persistently high → insufficient cluster capacity (EC2) |
| `DeploymentCount` | > 1 prolonged → stuck rolling deployment |
| ALB `UnHealthyHostCount` | > 0 → tasks failing ALB health check |

**Logging**: `awslogs` log driver sends container stdout/stderr to CloudWatch Logs. Use `awslogs-stream-prefix=ecs` to get per-task log streams. Set CloudWatch Log Group retention.

**FireLens** (log routing): use FluentBit/Fluentd sidecar to route logs to multiple destinations (S3, Kinesis, Datadog, Splunk) with transformation. Replaces `awslogs` for complex log routing.

---

## ECR (Elastic Container Registry)

Private Docker registry tightly integrated with ECS:

**Pull-through cache**: ECR mirrors Docker Hub, ECR Public, Quay.io — your containers pull from ECR instead of internet registries. Faster pulls; no Docker Hub rate limits; no NAT Gateway for internet pull.

**Lifecycle policies**: automatically delete old/untagged images:
```json
{
  "rules": [{
    "rulePriority": 1,
    "selection": {"tagStatus": "untagged", "countType": "sinceImagePushed", "countNumber": 7, "countUnit": "days"},
    "action": {"type": "expire"}
  }]
}
```

**Image scanning**: ECR Basic (free, on push) or Enhanced (Inspector v2, continuous CVE scanning). Block deployment of images with Critical CVEs via ECR Scan + Lambda hook.

---

## ECS Task Placement (EC2 Launch Type)

When running ECS on EC2, ECS places tasks across your cluster nodes:

| Strategy | Behaviour |
|---|---|
| `spread` | Distribute evenly across AZs and instances (HA) |
| `binpack` | Pack tasks on fewest instances (cost efficient) |
| `random` | Random placement (testing) |

**Production pattern**: spread by AZ first, then binpack by memory within an AZ:
```json
[
  {"type": "spread", "field": "attribute:ecs.availability-zone"},
  {"type": "binpack", "field": "memory"}
]
```

Task placement constraints: require `distinctInstance` (one task per instance), or `memberOf` an attribute group (e.g., only GPU instances).

---

## ECS vs EKS Decision

| Choose ECS when | Choose EKS when |
|---|---|
| AWS-native integration is priority | Kubernetes ecosystem required (Helm, service mesh, CRDs) |
| Team has no Kubernetes experience | Existing Kubernetes workloads/expertise |
| Simpler operational model preferred | Need Kubernetes-native features (PodDisruptionBudgets, NetworkPolicies, etc.) |
| Fargate (fully serverless) is desired | Need GPU, RDMA, custom networking |
| AWS service integration is critical | Multi-cloud portability matters |
| Small-to-medium team | Large platform team to operate Kubernetes |
| Most API-driven services | Stateful workloads using StatefulSets, PVCs |

**FAANG context**: Amazon runs almost everything on ECS internally (ECS is their internal scheduling system origin). Netflix and Airbnb use Kubernetes. The choice is more about team expertise and ecosystem than technical superiority.

---

## Security Best Practices

1. **Task role = least privilege IAM** — each service has a unique task role with only the permissions it needs
2. **Task execution role** — allow `ecr:GetAuthorizationToken`, `logs:CreateLogStream`, `secretsmanager:GetSecretValue` for the secrets used
3. **`readonlyRootFilesystem: true`** — containers can't write to the root; use `tmpfs` mounts for temp files
4. **Never pass secrets as plaintext env vars** — use `secrets` field referencing Secrets Manager
5. **awsvpc networking** — task-level Security Groups; VPC Flow Logs for per-task visibility
6. **ECR image scanning** — block deployment of Critical CVE images in CI/CD pipeline
7. **IMDSv2 on EC2 nodes** — prevent container SSRF attacks that steal node IAM credentials

---

## Best Practices

1. **Use Fargate for most workloads** — no node management; faster to start; VM-level isolation
2. **Pin image tags to digest** (`image:sha256:xxxx`), not `:latest` — predictable, immutable deployments
3. **Set CPU and memory reservations** accurately — over-provisioning wastes money; under-provisioning causes OOM
4. **Configure health check `startPeriod`** to match application startup time
5. **Use Blue/Green deployment** for production services — instant traffic rollback on alarm
6. **Enable Container Insights** on all production clusters
7. **Use pull-through cache in ECR** — eliminate Docker Hub rate limits and reduce NAT Gateway costs
8. **Set lifecycle policies on ECR** — orphaned images accumulate; daily scans need current images
9. **Use Service Connect** for service-to-service discovery within the cluster (replaces ELB for internal calls)
10. **Run Fargate Spot for batch/async tasks** — 70% cost reduction; implement SIGTERM handler for graceful termination

---

## FAANG Interview Points

**"ECS vs EKS for a microservices platform"**: ECS for AWS-native shops prioritising simplicity and Fargate; EKS for teams with Kubernetes expertise or needing Kubernetes ecosystem. Operationally ECS is simpler; functionally EKS is more powerful. At FAANG scale, both are used.

**"How do you do zero-downtime deployments in ECS?"**: Blue/Green via CodeDeploy with canary traffic shifting (10% → 100%). ALB sends 10% to new task set; CloudWatch alarms monitor error rate; if clean, shift to 100%. If alarm, CodeDeploy rolls back to blue in seconds.

**"How do ECS tasks access AWS services securely?"**: Task IAM role (`taskRoleArn`) — the ECS agent injects short-lived credentials via the Task Metadata endpoint (not the EC2 IMDS). The task doesn't need the node's IAM role. Each service gets its own least-privilege role. Credentials rotate automatically.
