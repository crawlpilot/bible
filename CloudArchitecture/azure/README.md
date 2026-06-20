# Azure Cloud Architecture — Overview & Decision Guide

**Cloud**: Microsoft Azure  
**Primary Strength**: Enterprise identity (Entra ID), hybrid/on-prem connectivity (ExpressRoute), .NET/Windows workloads  
**Market Position**: Second-largest public cloud; dominant in enterprise, government, and Microsoft-stack organizations  
**Key Differentiator vs AWS**: Active Directory integration is native, not bolted on. Azure Hybrid Benefit for Windows/SQL licensing.

---

## AWS ↔ Azure Service Mapping Matrix

| Category | AWS Service | Azure Equivalent | Key Difference |
|----------|-------------|-----------------|----------------|
| **Compute** | EC2 | Azure Virtual Machines | Azure Hybrid Benefit for Windows licensing |
| **Compute** | EC2 Auto Scaling Groups | Azure VM Scale Sets (VMSS) | VMSS has flexible/uniform orchestration modes |
| **Compute** | AWS Lambda | Azure Functions | Azure has Durable Functions for stateful orchestration |
| **Compute** | AWS Fargate | Azure Container Apps | Container Apps adds built-in KEDA-based autoscaling |
| **Compute** | Amazon ECS | Azure Container Instances (ACI) | ACI is lower-level; no service mesh built-in |
| **Compute** | Amazon EKS | Azure Kubernetes Service (AKS) | AKS free control plane; Entra ID auth built-in |
| **Storage** | Amazon S3 | Azure Blob Storage | Azure has Hot/Cool/Cold/Archive tiers (vs S3's 6 classes) |
| **Storage** | S3 + Lake Formation | Azure Data Lake Storage Gen2 (ADLS) | ADLS uses hierarchical namespace; unified with Blob |
| **Storage** | Amazon EFS | Azure Files (SMB/NFS) | Azure Files supports SMB 3.x natively |
| **Storage** | Amazon FSx for Windows | Azure Files Premium | Direct replacement for Windows file shares |
| **Database (NoSQL)** | DynamoDB | Azure Cosmos DB | Cosmos DB offers 5 consistency levels vs DynamoDB's 2 |
| **Database (NoSQL)** | DynamoDB (Table API) | Azure Table Storage | Table Storage is simpler, cheaper, less feature-rich |
| **Database (SQL)** | Amazon RDS | Azure SQL Database / Azure DB for PostgreSQL | Azure SQL Hyperscale scales to 100 TB |
| **Database (SQL)** | Amazon Aurora | Azure SQL Hyperscale | Aurora has global database; Hyperscale has named replicas |
| **Database (SQL)** | RDS Custom | Azure SQL Managed Instance | Managed Instance = full SQL Server engine in a VNet |
| **Caching** | Amazon ElastiCache (Redis) | Azure Cache for Redis | Same Redis versions; Azure has Enterprise tier with RediSearch |
| **Messaging (Queue)** | Amazon SQS | Azure Service Bus Queues | Service Bus adds sessions, dead-letter, scheduled delivery |
| **Messaging (Pub/Sub)** | Amazon SNS | Azure Service Bus Topics | Service Bus Topics support SQL-based subscriptions |
| **Messaging (Event)** | Amazon EventBridge | Azure Event Grid | Event Grid is push-only; no schema registry (use Event Hubs) |
| **Messaging (Stream)** | Amazon Kinesis | Azure Event Hubs | Event Hubs is Kafka-protocol compatible |
| **Messaging (Kafka)** | Amazon MSK | Azure Event Hubs (Kafka surface) | Event Hubs = managed Kafka without cluster management |
| **Serverless Workflows** | AWS Step Functions | Azure Durable Functions / Logic Apps | Durable Functions = code-first; Logic Apps = low-code |
| **API Gateway** | Amazon API Gateway | Azure API Management (APIM) | APIM has built-in developer portal, policy engine |
| **Load Balancer (L7)** | Application Load Balancer | Azure Application Gateway | App Gateway has WAF integrated |
| **Load Balancer (L4)** | Network Load Balancer | Azure Load Balancer | Azure Load Balancer supports HA Ports |
| **CDN / Edge** | Amazon CloudFront | Azure Front Door | Front Door = global anycast CDN + WAF + load balancer |
| **DNS** | Amazon Route 53 | Azure DNS | Azure Traffic Manager for routing policies |
| **Networking** | Amazon VPC | Azure Virtual Network (VNet) | Azure uses NSGs + ASGs; AWS uses SGs + NACLs |
| **Private Connectivity** | AWS PrivateLink | Azure Private Link / Private Endpoints | Same concept, similar implementation |
| **Hybrid Connectivity** | AWS Direct Connect | Azure ExpressRoute | ExpressRoute has Global Reach for on-prem ↔ on-prem |
| **Identity** | AWS IAM | Microsoft Entra ID + Azure RBAC | Entra ID = full IdP (SAML, OIDC, MFA, Conditional Access) |
| **Identity (Workload)** | IAM Roles (instance profiles) | Azure Managed Identities | Managed Identities: System-assigned or User-assigned |
| **Secrets** | AWS Secrets Manager | Azure Key Vault (Secrets) | Key Vault also stores certificates and encryption keys |
| **Key Management** | AWS KMS | Azure Key Vault (Keys) + Azure HSM | Azure Dedicated HSM for FIPS 140-2 Level 3 |
| **Security Posture** | AWS Security Hub | Microsoft Defender for Cloud | Defender has Secure Score + attack path analysis |
| **Threat Detection** | Amazon GuardDuty | Microsoft Defender for Cloud (threat protection) | Defender integrates with Sentinel (SIEM) |
| **SIEM** | AWS Security Lake | Microsoft Sentinel | Sentinel is purpose-built SIEM/SOAR |
| **Observability (Metrics)** | Amazon CloudWatch Metrics | Azure Monitor Metrics | Azure Monitor is the umbrella for all observability |
| **Observability (Logs)** | CloudWatch Logs | Azure Monitor Logs (Log Analytics) | Log Analytics uses KQL; more powerful query language |
| **Observability (Traces)** | AWS X-Ray | Azure Application Insights | App Insights auto-instruments .NET, Java, Node, Python |
| **IaC** | AWS CloudFormation | Azure Resource Manager (ARM) / Bicep | Bicep is the modern ARM replacement (like CloudFormation YAML) |
| **IaC (multi-cloud)** | AWS CDK / Terraform | Azure CDK / Terraform | Terraform equally supported on both |
| **Container Registry** | Amazon ECR | Azure Container Registry (ACR) | ACR has geo-replication and Tasks for CI builds |
| **Analytics** | Amazon Athena | Azure Synapse Analytics (Serverless SQL) | Synapse is broader (includes pipelines + Spark) |
| **Analytics** | Amazon EMR | Azure HDInsight / Azure Databricks | Databricks is preferred on Azure for Spark workloads |
| **Data Pipeline** | AWS Glue | Azure Data Factory | Data Factory has 100+ connectors; visual pipeline builder |
| **Search** | Amazon OpenSearch | Azure AI Search (Cognitive Search) | Azure AI Search integrates with Azure OpenAI |
| **AI/ML Platform** | Amazon SageMaker | Azure Machine Learning | Both are full ML lifecycle platforms |
| **Configuration** | AWS Systems Manager Parameter Store | Azure App Configuration | App Configuration has feature flags built-in |

---

## When to Choose Azure Over AWS

### Strong Azure scenarios

| Scenario | Why Azure Wins |
|----------|---------------|
| **Enterprise with existing Microsoft 365 / Active Directory** | Entra ID SSO is native; no federation complexity |
| **Windows Server or SQL Server workloads** | Azure Hybrid Benefit saves 40–85% on licensing |
| **On-prem hybrid via ExpressRoute** | ExpressRoute Global Reach enables on-prem to on-prem routing through Azure backbone |
| **.NET / C# primary stack** | Deepest SDK support; Visual Studio + Azure DevOps integration |
| **Regulated industries (HIPAA, FedRAMP, SOC 2)** | Azure has more government cloud regions (Azure Government) |
| **Teams already using Teams / Power Platform** | Logic Apps + Power Automate integrates with O365 natively |
| **OpenAI API on enterprise terms** | Azure OpenAI Service = same models, enterprise SLAs, private VNet |

### Strong AWS scenarios

| Scenario | Why AWS Wins |
|----------|-------------|
| **Breadth of managed services** | AWS has more niche managed services (Textract, Rekognition, etc.) |
| **Greenfield startups** | Larger ecosystem, more third-party integrations |
| **Multi-region global footprint** | AWS has more regions (33 vs Azure's 30+) |
| **Open-source first** | AWS has deeper managed open-source (RDS, MSK, OpenSearch) |
| **Lambda at edge** | Lambda@Edge is more mature than Azure Functions on Front Door |

---

## Azure Well-Architected Framework (WAF) Pillars

The five pillars map to the same concepts as AWS WAF:

| WAF Pillar | Azure Focus | AWS Equivalent |
|------------|-------------|----------------|
| **Reliability** | Availability Zones, Traffic Manager, Cosmos DB multi-region | Multi-AZ, Route 53, DynamoDB Global Tables |
| **Security** | Entra ID, Defender for Cloud, Private Endpoints | IAM, Security Hub, PrivateLink |
| **Cost Optimization** | Reserved Instances, Hybrid Benefit, Spot VMs | Reserved Instances, Savings Plans, Spot |
| **Operational Excellence** | Azure DevOps, Bicep, Azure Policy | CodePipeline, CloudFormation, AWS Config |
| **Performance Efficiency** | Cosmos DB, Azure Front Door, Event Hubs | DynamoDB, CloudFront, Kinesis |

---

## File Index

| File | Azure Services Covered | AWS Comparison |
|------|------------------------|----------------|
| [cosmos-db.md](cosmos-db.md) | Azure Cosmos DB | DynamoDB, MongoDB Atlas, Cassandra |
| [messaging.md](messaging.md) | Service Bus, Event Grid, Event Hubs | SQS, SNS, EventBridge, Kinesis |
| [design-patterns.md](design-patterns.md) | 44 Azure architecture patterns | AWS implementation equivalents for each |
| [compute.md](compute.md) | Azure Functions, AKS, Container Apps, VMs | Lambda, EKS, Fargate, EC2 |
| [networking.md](networking.md) | VNet, Front Door, APIM, ExpressRoute | VPC, CloudFront+ALB, API Gateway, Direct Connect |
| [identity-security.md](identity-security.md) | Entra ID, RBAC, Key Vault, Defender | IAM, Secrets Manager, KMS, Security Hub |
| [sql-databases.md](sql-databases.md) | Azure SQL, Hyperscale, Managed Instance, PostgreSQL | RDS, Aurora, RDS Custom |
| [storage.md](storage.md) | Blob Storage, ADLS Gen2, Azure Files | S3, Lake Formation, EFS |
| [monitoring-observability.md](monitoring-observability.md) | Azure Monitor, Application Insights, Log Analytics | CloudWatch, X-Ray |
| [serverless-workflows.md](serverless-workflows.md) | Durable Functions, Logic Apps | Step Functions, EventBridge Pipes |

---

## Key Numbers for Interviews

| Service | Limit / Number | Why It Matters |
|---------|---------------|----------------|
| Azure Functions (Consumption) | 10 min max execution (default 5 min) | Longer than Lambda's 15 min only on Premium/Dedicated |
| AKS max nodes per cluster | 5,000 nodes | Same as EKS |
| Cosmos DB max item size | 2 MB | vs DynamoDB's 400 KB — 5× larger |
| Service Bus max message size | 256 KB (Standard), 100 MB (Premium) | vs SQS 256 KB — Premium tier is a game-changer |
| Event Hubs max throughput units | 40 TUs standard (auto-inflate to 20 TUs) | Each TU = 1 MB/s ingress, 2 MB/s egress |
| Azure Blob Storage max object size | 190.7 TB | vs S3's 5 TB |
| ExpressRoute max bandwidth | 100 Gbps | vs Direct Connect's 100 Gbps (same) |
| Azure Front Door PoPs | 118+ edge locations globally | vs CloudFront's 600+ (CloudFront has more PoPs) |
| Key Vault operations | 2,000 RSA-2048 ops/10 sec per vault | Soft limit; use multiple vaults for high-throughput |

---

> **FAANG Interview Framing**: When discussing cloud architecture in an interview, demonstrate cloud-agnostic reasoning: "This pattern applies equally on AWS and Azure — on AWS you'd use Kinesis + Lambda, on Azure it's Event Hubs + Azure Functions with the same fan-out semantics. My recommendation depends on where the existing workload lives and what identity provider is in use."
