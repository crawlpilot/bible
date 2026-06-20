# Azure Identity and Security — Entra ID, RBAC, Key Vault, Defender

**AWS Equivalents**:  
- Microsoft Entra ID → AWS IAM + Amazon Cognito  
- Azure RBAC → AWS IAM Policies  
- Managed Identities → IAM Roles (instance profiles / Lambda execution roles)  
- Azure Key Vault → AWS Secrets Manager + AWS KMS  
- Microsoft Defender for Cloud → AWS Security Hub + Amazon GuardDuty  
- Microsoft Sentinel → Amazon Security Lake + SIEM partner  

**Mental model**: Azure's identity story is built around Entra ID (formerly Azure Active Directory), a full Identity Provider (IdP) that handles authentication for both human users and workloads. AWS IAM is authorization-first (resource policies, not a full IdP). The key insight: Entra ID does what IAM + Cognito + your SAML federation + MFA solution does on AWS — in one service.

---

## 1. Microsoft Entra ID (formerly Azure Active Directory)

### What It Is

Cloud-native Identity Provider (IdP) for authentication and directory services. Every Azure subscription has an Entra ID tenant. Unlike AWS IAM (which is authorization-only), Entra ID handles both authentication (who are you?) and is the foundation for authorization (what can you do via RBAC).

### Entra ID vs AWS IAM vs Cognito

| Capability | Entra ID | AWS IAM | Amazon Cognito |
|-----------|---------|---------|---------------|
| **Human user auth** | Yes (SSO, MFA, Conditional Access) | IAM users (anti-pattern at scale) | Yes (User Pools) |
| **Enterprise SSO** | SAML 2.0, OIDC, WS-Fed built-in | Identity Center (IAM IdC) | Federation to external IdP |
| **External user auth (B2B)** | Entra External ID (B2B) | Cognito (limited) | Yes (User Pools) |
| **Customer auth (B2C)** | Entra External ID (B2C) | Cognito User Pools | Yes |
| **Workload identity** | Managed Identities / Service Principals | IAM Roles + instance profiles | N/A |
| **MFA** | Built-in (TOTP, FIDO2, phone) | MFA on IAM users (limited) | Cognito MFA |
| **Conditional Access** | Yes (risk-based, location, device) | No native equivalent | No |
| **PIM (Privileged Identity)** | Yes (just-in-time access) | IAM temporary roles (limited) | No |
| **Directory services** | User/Group management, LDAP | No | No |

### Entra ID Key Concepts

**Tenant**: A dedicated instance of Entra ID for an organization. Every Azure subscription belongs to exactly one tenant.

**Users**: Human identities in the directory. Can be:
- Member users (from the organization)
- Guest users (B2B — external partners invited to tenant)

**Service Principals**: Non-human identities (applications, services). Two types:
1. **Application registration** + Service Principal pair: app registers, SP is the per-tenant identity
2. **Managed Identity**: System-managed SP with no credential management (see below)

**Groups**: Collections of users/service principals. Assign RBAC roles to groups — not individual users.

### Authentication Flows

```
User → App → Entra ID → Returns JWT (access token + id token)
                │
        Supports:
        - Authorization Code Flow (web apps)
        - PKCE (mobile/SPA)
        - Client Credentials (service-to-service, no user)
        - Device Code Flow (CLIs, IoT)
        - On-behalf-of (OBO) — service calls another service as user
```

### Conditional Access

Rules that gate authentication based on context:
- **Signals**: User risk (leaked credentials), Sign-in risk (unusual location), Device compliance, IP location, App being accessed
- **Controls**: Require MFA, Require compliant device, Block access, Require password change

**Example policy**:
```
IF: User accesses "Sensitive Finance App" AND sign-in risk = HIGH
THEN: Block access (not just MFA)

IF: User is in "Non-Corporate" IP range AND accessing "Azure Portal"
THEN: Require MFA + Require Intune-managed device
```

**AWS equivalent**: No direct equivalent. Closest: IAM permission boundaries + SCPs in Organizations + GuardDuty anomaly detection (reactive, not preventive).

### Privileged Identity Management (PIM)

Just-in-time privileged access — users are eligible for a role but must activate it with justification + approval:

```
User "Alice" → eligible for "Global Administrator"
Alice requests activation → Manager approves → Alice has role for 8 hours → role removed
Every activation is logged in audit trail
```

**AWS equivalent**: No direct equivalent. Approximated with: IAM role assumption + approval Lambda + time-based SCP to remove role.

---

## 2. Azure RBAC

### What It Is

Role-Based Access Control layered on top of Entra ID. Authorizes what a user/service principal can do on Azure resources.

**Key components**:
- **Security Principal**: Who (user, group, managed identity, service principal)
- **Role Definition**: What (collection of permissions — actions, notActions, dataActions)
- **Scope**: Where (management group, subscription, resource group, or specific resource)
- **Role Assignment**: Binding of principal + role + scope

```
Role Assignment:
  Principal: Alice (user)
  Role: Contributor
  Scope: /subscriptions/abc123/resourceGroups/prod-rg
  
Effect: Alice can create/modify/delete any resource in prod-rg, but NOT manage access (Owner required)
```

### Built-in Roles (Key ones)

| Role | Can Do | Cannot Do | AWS Equivalent |
|------|--------|-----------|----------------|
| **Owner** | Everything + manage access | — | AdministratorAccess |
| **Contributor** | Create/modify/delete resources | Manage access, assign roles | PowerUserAccess |
| **Reader** | View resources only | No modifications | ReadOnlyAccess |
| **User Access Administrator** | Manage access only | Create/modify resources | IAMFullAccess |
| **Storage Blob Data Contributor** | Read/write blobs | No management plane | S3FullAccess (scoped) |
| **Key Vault Secrets User** | Read secrets | No management | SecretsManager read-only |
| **AKS Cluster Admin** | Full kubectl access | No Azure resource changes | EKS cluster admin binding |

### RBAC Scope Hierarchy

```
Management Group (org-level policy)
└── Subscription
    └── Resource Group
        └── Resource (e.g., specific Storage Account)

Roles assigned at higher scope are inherited by lower scopes.
Deny assignments (preview) can block inherited permissions.
```

**vs AWS IAM**:

| Aspect | Azure RBAC | AWS IAM |
|--------|-----------|---------|
| Role assignment | Principal + Role + Scope | User/Group + Policy |
| Permission boundary | Azure Policy (deny effect) | Permission Boundaries |
| Resource-level control | Yes (scope = specific resource) | Resource-based policies (S3, SQS, etc.) |
| Group-based access | Entra ID Groups → Role assignment | IAM Groups → attached policies |
| Condition-based | ABAC via attribute conditions | IAM condition keys |

### Custom Roles

```json
{
  "Name": "VM Operator",
  "Actions": [
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/read"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["/subscriptions/abc123"]
}
```

---

## 3. Managed Identities

### What They Are

Auto-managed service principal with no password or certificate to manage. Assigned to Azure resources (VMs, Functions, AKS pods, Container Apps). The clean equivalent to IAM instance profiles and Lambda execution roles.

**Two types**:

| Type | Lifecycle | Sharing | Use When |
|------|----------|---------|---------|
| **System-assigned** | Created with resource, deleted with resource | 1:1 (bound to one resource) | Simple; one service, one identity |
| **User-assigned** | Standalone resource, manual lifecycle | Many resources can use same identity | Multiple services share same permissions |

### How It Works

```
Azure Function → Requests token from IMDS (Instance Metadata Service)
                         │
              Azure IMDS: http://169.254.169.254/metadata/identity/oauth2/token
                         │
              Returns: JWT access token for the resource
                         │
Azure Function → Calls Azure SQL / Key Vault / Storage with token
```

No connection strings. No passwords in config. No secret rotation needed.

**Python example**:
```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# DefaultAzureCredential uses Managed Identity in production,
# developer credentials locally (Entra ID CLI login)
credential = DefaultAzureCredential()
client = SecretClient(vault_url="https://myvault.vault.azure.net", credential=credential)
secret = client.get_secret("db-connection-string")
```

**vs IAM Instance Profile**:
```python
# AWS equivalent — boto3 reads credentials from EC2 metadata automatically
import boto3
sm = boto3.client('secretsmanager', region_name='us-east-1')
secret = sm.get_secret_value(SecretId='prod/db/connection')['SecretString']
```

**Workload Identity for AKS** (Kubernetes equivalent):
```yaml
# Pod uses a Service Account annotated with Managed Identity client ID
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  annotations:
    azure.workload.identity/client-id: "<managed-identity-client-id>"
```

---

## 4. Azure Key Vault

### What It Is

Managed service for secrets, cryptographic keys, and certificates. The Secrets Manager + KMS combined.

**Three object types**:

| Type | Use Case | AWS Equivalent |
|------|---------|----------------|
| **Secrets** | DB passwords, API keys, connection strings | AWS Secrets Manager |
| **Keys** | Encryption/decryption, signing (HSM-backed) | AWS KMS |
| **Certificates** | TLS certs, code signing certs | AWS Certificate Manager (ACM) |

### Tiers

| Tier | Key Storage | FIPS Level | Max ops/10s |
|------|------------|------------|-------------|
| **Standard** | Software-protected | FIPS 140-2 Level 1 | Varies by key type |
| **Premium** | HSM-protected | FIPS 140-2 Level 2 | Varies by key type |

**Azure Dedicated HSM** / **Azure Managed HSM**: FIPS 140-2 Level 3 — for regulated industries.

### Access Control

Two models (can coexist, but RBAC is recommended for new deployments):

| Model | How it works | Granularity |
|-------|-------------|-------------|
| **Vault Access Policy** (legacy) | Assign permissions per object type (get, list, set, delete) per principal | Vault-level only (not per-secret) |
| **Azure RBAC** (recommended) | Standard RBAC roles like "Key Vault Secrets User", "Key Vault Crypto Officer" | Can be scoped to individual secret/key |

### Secret Rotation

```
Key Vault → Event Grid → Azure Function (rotation function)
                              │
                         Updates backend credential
                              │
                         Updates Key Vault with new secret value
                              │
                         Sends notification (optional)
```

**vs AWS Secrets Manager**: Both support automatic rotation. AWS Secrets Manager has native rotation support for RDS, Redshift, DocumentDB. Azure Key Vault rotation requires a custom Azure Function trigger via Event Grid notification.

### Key Vault vs AWS KMS + Secrets Manager

| Feature | Azure Key Vault | AWS KMS | AWS Secrets Manager |
|---------|----------------|---------|---------------------|
| Symmetric encryption | Keys tier | Yes | No (wraps KMS) |
| Asymmetric (RSA/EC) | Keys tier | Yes | No |
| Secret storage | Secrets tier | No | Yes |
| Certificate management | Certificates tier | No (use ACM) | No |
| Auto-rotation | Via Event Grid + Function | N/A | Built-in (RDS, Redshift) |
| HSM backing | Premium tier | CloudHSM (separate service) | No |
| Soft delete | 7–90 day recovery | No delete without key state | 7–30 day recovery |
| Network restriction | VNet service endpoints + Private Endpoint | VPC endpoints | VPC endpoints |
| Cost per 10K operations | ~$0.03 (secrets), ~$0.015 (RSA keys) | $0.03 per 10K API calls | $0.40/secret/month |

---

## 5. Microsoft Defender for Cloud

### What It Is

Unified security posture management (CSPM) + cloud workload protection (CWPP). The AWS Security Hub + GuardDuty equivalent with an important addition: a single **Secure Score** that gamifies fixing misconfigurations.

### Two Pillars

| Pillar | Description | AWS Equivalent |
|--------|-------------|----------------|
| **CSPM** (Cloud Security Posture Mgmt) | Continuous assessment of resource configs against security benchmarks | AWS Security Hub (compliance checks) |
| **CWPP** (Cloud Workload Protection) | Threat detection for VMs, containers, databases, APIs | Amazon GuardDuty |

### Secure Score

Every recommendation has a score impact. Fixing misconfigurations raises your score (0–100%).

```
Secure Score: 67%
  ├── Enable MFA for all users (+5 pts)
  ├── Restrict public blob access (+3 pts)
  ├── Enable Azure Defender for SQL (+4 pts)
  └── Fix 23 other findings...
```

**AWS equivalent**: Security Hub has "Security Hub score" for Foundational Security Best Practices standard — same concept.

### Defender Plans (per resource type)

| Plan | Protects | Monthly Cost | AWS Equivalent |
|------|---------|-------------|----------------|
| Defender for Servers | VMs, Arc-enabled servers | ~$15/server | GuardDuty EC2 findings |
| Defender for SQL | Azure SQL, SQL Server on VMs | ~$15/server | GuardDuty RDS Protection |
| Defender for Storage | Blob, Files, Data Lake | ~$0.02/10K operations | Macie + GuardDuty S3 |
| Defender for Containers | AKS, ACR, Arc K8s | ~$7/vCore | GuardDuty EKS Protection |
| Defender for App Service | Azure App Service | ~$15/app | No direct equivalent |
| Defender for Key Vault | Key Vault threat detection | ~$0.02/10K ops | No direct equivalent |

### Microsoft Sentinel

Azure's SIEM/SOAR product. Collects logs from Defender for Cloud, Entra ID, Azure services, and external sources (AWS, Okta, Palo Alto). The AWS Security Lake + SIEM partner equivalent, but native.

```
Data Sources → Sentinel Analytics Workspace
                      │
              ┌───────┼───────┐
              ▼       ▼       ▼
           Alerts  Incidents Hunting
           (rules) (grouped) (queries)
              │
              ▼
          Playbooks (Logic Apps — automated response)
```

---

## Zero-Trust Architecture on Azure

**Principle**: Never trust, always verify. Verify explicitly, use least privilege, assume breach.

```
User access flow (Zero Trust):
1. User → Entra ID → Conditional Access evaluation
   └── Check: MFA done? Device compliant? Risk level acceptable?
2. Token issued → App (validates JWT signature + claims)
3. App → Azure resource (Managed Identity token — no credentials)
4. All traffic via Private Endpoints (no public internet)
5. NSG rules restrict lateral movement
6. Defender for Cloud monitors for anomalies
7. All logs → Sentinel (SIEM detection)
```

---

## Key Numbers for Interviews

| Service | Number | Notes |
|---------|--------|-------|
| Entra ID max users per tenant | 500,000 | Soft limit; contact Microsoft for more |
| Key Vault max secrets per vault | 25,000 | Soft limit |
| Key Vault RSA-2048 operations/10s | 2,000 | Per vault; use multiple vaults at scale |
| Key Vault soft delete retention | 7–90 days | Configurable; purge protection prevents permanent delete |
| RBAC role assignments per subscription | 4,000 | Assign to groups, not individuals to stay under limit |
| Managed Identity token expiry | 24 hours | SDK auto-renews via IMDS |
| PIM activation max duration | 8 hours | Configurable per role setting |
| Entra ID sign-in log retention | 30 days (P1/P2), 7 days (free) | Export to Log Analytics for long-term |

---

> **FAANG Interview Callout**: "The most important Azure security concept to understand for enterprise interviews is Managed Identities — they eliminate credentials from code entirely. On AWS you have IAM instance profiles and Lambda execution roles which do the same thing, but on Azure the SDK's DefaultAzureCredential makes it transparent: same code works locally (uses developer's Entra login) and in production (uses Managed Identity) with zero config change. For security posture, Defender for Cloud's Secure Score gives security engineering teams a prioritized backlog — the gamification works. The architectural principle I apply: every service-to-service call uses Managed Identity (no passwords), every secret lives in Key Vault (not environment variables), and Conditional Access blocks risky logins before they hit the application layer."
