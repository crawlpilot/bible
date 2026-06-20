# Azure Compute — Functions, AKS, Container Apps, VMs

**AWS Equivalents**:  
- Azure Functions → AWS Lambda  
- Azure Kubernetes Service (AKS) → Amazon EKS  
- Azure Container Apps → AWS App Runner / Fargate  
- Azure VMs / VMSS → Amazon EC2 / Auto Scaling Groups  

**Mental model**: Azure compute has the same four-tier ladder as AWS — serverless functions, managed containers, managed Kubernetes, and raw VMs. The key Azure differentiations: AKS has a free control plane (EKS charges $0.10/hr), Azure Functions has Durable Functions for stateful orchestration built-in, and VMSS supports Azure Hybrid Benefit for Windows licensing savings.

---

## Compute Tier Decision

```
Is the workload event-driven and short-lived (< 10 min)?
  └── Yes → Azure Functions (Consumption or Premium plan)
      └── Need stateful orchestration? → Durable Functions

Is it containerized but I don't want to manage Kubernetes?
  └── Yes → Azure Container Apps (built-in KEDA autoscaling, Dapr)

Is it containerized and I need full Kubernetes control?
  └── Yes → Azure Kubernetes Service (AKS)

Is it a VM-based workload (Windows, legacy, licensed software)?
  └── Yes → Azure VMs + VMSS
      └── Windows/SQL Server? → Apply Azure Hybrid Benefit (40–85% discount)
```

---

## 1. Azure Functions

### What It Is

Serverless compute that runs code in response to triggers. Pay per execution. The Lambda equivalent.

### Hosting Plans

| Plan | Cold Start | Max Duration | VNet | Scale |
|------|-----------|-------------|------|-------|
| **Consumption** | Yes (0.5–3s .NET, 1–3s Python) | 10 min | No (unless Premium for VNet) | 0–200 instances auto |
| **Flex Consumption** (GA 2024) | Reduced (pre-provisioned) | Unlimited | Yes | 0–1000 per-function concurrency |
| **Premium** | No (always-warm) | Unlimited | Yes | Min/max instances configurable |
| **Dedicated (App Service)** | No | Unlimited | Yes | Manual or App Service scale rules |
| **Container Apps** (Functions on ACA) | Reduced | Unlimited | Yes | KEDA-driven |

**vs Lambda**:

| Feature | Azure Functions | AWS Lambda |
|---------|----------------|-----------|
| Max execution time | 10 min (Consumption), unlimited (Premium) | **15 min** |
| Max memory | 1.5 GB (Consumption), 14 GB (Premium E4v3) | **10 GB** |
| Cold start (Python) | 1–3s | 0.5–2s |
| VNet integration | Premium plan required (Consumption = no VNet) | All Lambda functions can use VPC |
| Stateful orchestration | **Durable Functions (built-in)** | Step Functions (separate service) |
| Deployment package max | 250 MB compressed | 250 MB compressed (same) |
| Concurrency limit | 200 per region (Consumption, soft) | 1,000 per region (default, adjustable) |
| SnapStart (fast cold start) | Flex Consumption plan | Lambda SnapStart (Java 11+) |
| Extension bundles | Yes (NuGet/npm packages) | Lambda Layers |

### Triggers

| Trigger | Description | AWS Equivalent |
|---------|-------------|----------------|
| HTTP | REST endpoint | API Gateway → Lambda |
| Timer (CRON) | Scheduled execution | EventBridge Scheduler → Lambda |
| Service Bus Queue | Message processing | SQS → Lambda |
| Event Hubs | Stream processing | Kinesis → Lambda |
| Blob Storage | File uploaded | S3 Event → Lambda |
| Cosmos DB | Change Feed | DynamoDB Streams → Lambda |
| Event Grid | Azure service events | EventBridge → Lambda |

### Durable Functions

Stateful orchestration built into Azure Functions. The equivalent of AWS Step Functions — but in code.

**Four function types**:
1. **Orchestrator**: Defines the workflow (deterministic, replayable)
2. **Activity**: Individual work unit (makes external calls, writes to DB)
3. **Entity**: Stateful actor (think counter, aggregate)
4. **Client**: Starts orchestrations, queries status

**Example — Fan-out/Fan-in pattern**:
```python
@app.orchestration_trigger(context_name="context")
def parallel_approval(context: df.DurableOrchestrationContext):
    # Fan-out: call N activities in parallel
    tasks = [context.call_activity("ProcessOrder", order) for order in orders]
    results = yield context.task_all(tasks)  # Fan-in: wait for all
    return results
```

**Durable Function patterns**:

| Pattern | Description | Step Functions Equivalent |
|---------|-------------|--------------------------|
| **Function Chaining** | Sequential F1 → F2 → F3 | Sequential states |
| **Fan-out/Fan-in** | Parallel tasks, wait for all | Parallel state |
| **Async HTTP API** | Long-running with polling endpoint | `.waitForTaskToken` |
| **Monitor** | Polling loop with custom sleep/retry | Wait state loop |
| **Human Interaction** | Wait for external event (approval) | `.waitForTaskToken` + callback |
| **Aggregator** (Entity) | Stateful counter/accumulator | Not natively available |

**Durable vs Step Functions**:

| Aspect | Durable Functions | Step Functions |
|--------|-----------------|---------------|
| Definition format | Code (Python/C#/JS) | JSON (ASL) or CDK |
| Max workflow duration | Unlimited | 1 year (Standard), 5 min (Express) |
| Cost | Activity execution time | $0.025 per 1K state transitions |
| Debugging | Local development with emulator | CloudWatch Logs only |
| External events | `raise_event()` | `.sendTaskSuccess()` API |
| History storage | Azure Storage (auto-managed) | DynamoDB (internal) |
| Language support | C#, Python, JavaScript, Java | Language-agnostic (JSON) |

---

## 2. Azure Kubernetes Service (AKS)

### What It Is

Managed Kubernetes. Azure manages the control plane (free). You manage the worker nodes.

**Key differentiators vs EKS**:
- **Free control plane**: EKS charges $0.10/hr = $73/month per cluster. AKS control plane is free.
- **Entra ID integration**: AKS uses Entra ID for cluster access natively; EKS uses IAM + aws-auth ConfigMap (more friction)
- **Azure CNI**: First-class VNet-native pod networking; each pod gets a VNet IP

### Node Pools

AKS uses node pools as the unit of compute configuration:

```
AKS Cluster
├── System Node Pool (required — runs kube-system components)
│   └── VM: Standard_D4s_v5, min 1, max 5
└── User Node Pools (optional — run workloads)
    ├── pool: payments — Standard_D8s_v5, GPU=No, min 2, max 20
    ├── pool: ml-inference — Standard_NC6s_v3 (GPU), min 0, max 10
    └── pool: spot-batch — Standard_D4s_v5, Spot VMs, min 0, max 50
```

Node pool types:

| Type | VM pricing | Use case |
|------|-----------|---------|
| **Regular** | On-demand | Production workloads |
| **Spot** | Up to 90% discount, evictable | Batch, CI/CD, fault-tolerant apps |
| **System** | On-demand | Required for AKS system pods |

**vs EKS node groups**:
- EKS: managed node groups or self-managed node groups or Fargate
- AKS: system + user node pools + Virtual Nodes (Azure Container Instances for burstable capacity)

### Networking Options

| Mode | Pod IP source | When to use |
|------|-------------|-------------|
| **Kubenet** | Separate CIDR, NAT to VNet | Simple setup, fewer IPs needed |
| **Azure CNI** | VNet IPs (one IP per pod) | Production, needs pod VNet access |
| **Azure CNI Overlay** | Overlay CIDR, VNet for nodes only | Large clusters (avoids VNet IP exhaustion) |
| **Azure CNI + Cilium** | Cilium dataplane | eBPF networking, network policy |

**VNet IP math with Azure CNI**: If node has 30 pods max and you have 10 nodes = 300 VNet IPs consumed. Plan subnet sizing carefully.

### Scaling

| Mechanism | What it does | AWS Equivalent |
|-----------|-------------|----------------|
| **Cluster Autoscaler** | Adds/removes nodes based on pending pods | AWS Cluster Autoscaler / Karpenter |
| **Horizontal Pod Autoscaler (HPA)** | Scales pods based on CPU/memory/custom metrics | Same (HPA in EKS) |
| **KEDA** (built-in AKS add-on) | Scales pods based on event sources (Service Bus queue depth, Event Hubs lag) | KEDA on EKS (third-party) |
| **Virtual Nodes** | Burst to Azure Container Instances (no node provisioning) | Fargate profiles on EKS |

### AKS vs EKS Comparison

| Feature | AKS | EKS |
|---------|-----|-----|
| Control plane cost | **Free** | $0.10/hr = $73/month |
| Identity for cluster access | Entra ID (built-in) | IAM + aws-auth ConfigMap |
| GPU node pools | Supported (NC/ND/NV series) | Supported (p3/p4 instances) |
| Windows node pools | Supported | Supported |
| Managed node OS upgrades | Node image auto-upgrade | Managed node group AMI updates |
| Network policy | Azure NPM, Calico, Cilium | Calico, VPC CNI network policy |
| Service mesh | Istio (AKS add-on), Open Service Mesh, Linkerd | AWS App Mesh, Istio |
| GitOps | Flux (AKS extension) | Flux via EKS Blueprints |
| Monitoring | Azure Monitor + Container Insights | CloudWatch Container Insights |
| Cost per cluster/month (3 nodes) | ~$150–300 (nodes only) | ~$220–370 (control plane + nodes) |

---

## 3. Azure Container Apps

### What It Is

Managed serverless containers built on Kubernetes + KEDA + Dapr. You don't manage nodes. The Fargate/App Runner equivalent with more capabilities.

**Unique features**:
- **KEDA built-in**: Scale to zero based on Service Bus queue depth, Event Hubs lag, HTTP traffic, CRON
- **Dapr built-in**: Service discovery, pub/sub, state management as sidecars — no code changes needed
- **Environments**: Shared VNet boundary for multiple Container Apps (vs separate ALB/API GW per App Runner service)
- **Ingress**: HTTP/HTTPS built-in with custom domains + TLS (no ALB required)

**vs App Runner vs Fargate**:

| Feature | Container Apps | AWS App Runner | AWS Fargate |
|---------|---------------|----------------|------------|
| Scale to zero | Yes | Yes | No (min 1 task) |
| Event-driven scale | KEDA (queue, stream) | HTTP only | KEDA via ECS (manual setup) |
| Service mesh / discovery | Dapr built-in | No | AWS Cloud Map |
| VNet integration | Yes (environment-level) | Yes (VPC connector) | Yes (VPC-native) |
| Kubernetes-based | Yes (hidden) | No | No |
| Max CPU | 4 vCPU per replica | 4 vCPU | 16 vCPU per task |
| Max memory | 8 GB per replica | 12 GB | 120 GB per task |

**When to use Container Apps over AKS**: Stateless APIs, event-driven microservices, background jobs where Kubernetes control plane complexity is overhead. Use AKS when you need custom node configurations, advanced networking, or cluster-level control.

---

## 4. Azure VMs and VMSS

### VM Series (Key Families)

| Series | vCPU Range | Use Case | AWS Equivalent |
|--------|-----------|---------|----------------|
| **B-series** | 1–20 vCPU | Burstable, dev/test | T3/T4g |
| **D-series** (Dv5) | 2–96 vCPU | General purpose | M5/M6i |
| **E-series** (Ev5) | 2–104 vCPU | Memory-optimized | R5/R6i |
| **F-series** (Fsv2) | 2–72 vCPU | Compute-optimized | C5/C6i |
| **L-series** | 8–80 vCPU | Storage-optimized (NVMe) | I3/I4i |
| **NC-series** (NCv3, NC T4) | 6–24 vCPU + GPU | GPU (ML inference/training) | P3/P4 |
| **M-series** | 8–416 vCPU, up to 11.4 TB RAM | SAP HANA, in-memory | X1e/High Memory |

### Azure Hybrid Benefit

Use existing Windows Server or SQL Server licenses on Azure VMs:
- Windows Server + Software Assurance → **Up to 49% discount** on Windows VM
- SQL Server + Software Assurance → **Up to 85% discount** on SQL VM (vs RDS)
- SQL Server to Azure SQL Database: additional savings (BYOL model)

**This is the primary cost advantage of Azure over AWS for Windows/SQL workloads.**

### VMSS (Virtual Machine Scale Sets)

| Feature | VMSS (Uniform) | VMSS (Flexible) | AWS ASG |
|---------|---------------|-----------------|---------|
| VM model | Identical VMs | Mix VM types/sizes | Mix instance types (Launch Template) |
| Max instances | 1,000 | 1,000 | 2,500 |
| Spot VMs | Supported | Supported | Spot Instances |
| Rolling upgrades | Built-in | Built-in | Instance Refresh |
| Availability Zones | Supported | Supported | Multi-AZ |
| Overprovisioning | Yes (spare VMs) | No | N/A |

**Flexible orchestration mode** (equivalent to AWS mixed instances policy): Mix regular and spot VMs, different VM sizes, maintain minimum capacity.

---

## Key Numbers for Interviews

| Service | Number | Notes |
|---------|--------|-------|
| Azure Functions Consumption max instances | 200 per region | Soft limit; increase via support |
| Azure Functions max execution (Consumption) | 10 minutes | Lambda wins at 15 min |
| Azure Functions max memory (Premium E4) | 14 GB | Lambda wins at 10 GB Arm / same x86 |
| AKS control plane cost | **$0** | vs EKS $0.10/hr |
| AKS max nodes per cluster | 5,000 (same as EKS) | Cluster limit |
| AKS max pods per node | 250 (Azure CNI), 110 (Kubenet) | Plan capacity per node |
| Container Apps max CPU | 4 vCPU per replica | vs Fargate 16 vCPU per task |
| VMSS max instances | 1,000 | vs AWS ASG 2,500 |
| Azure Hybrid Benefit SQL savings | Up to 85% | Key differentiator for SQL workloads |

---

> **FAANG Interview Callout**: "When an interviewer asks about compute on Azure, I frame it around three questions: Is the workload event-driven and stateless? → Functions. Is it containerized with event-driven scaling needs? → Container Apps with KEDA. Does it need full Kubernetes control or stateful workloads? → AKS. The AKS-vs-EKS comparison I highlight most: AKS has a free control plane (saves $73/month per cluster at scale this matters) and native Entra ID integration eliminates the aws-auth ConfigMap complexity that causes operational incidents. For Windows workloads, Azure Hybrid Benefit is the decisive cost argument — 85% SQL licensing discount changes the TCO conversation completely."
