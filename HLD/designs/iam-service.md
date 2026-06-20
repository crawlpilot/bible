# HLD: In-House IAM Service (AWS IAM Equivalent)

> **Problem Statement:** Build a centralized Identity and Access Management platform that lets platform teams define fine-grained authorization policies (who can do what on which resource under what conditions), evaluate those policies at request time with <5ms p99 latency, and produce a full audit trail — replacing a patchwork of per-service RBAC tables and hardcoded role checks.

---

## 0. AWS IAM — How It Actually Works

> Read this section before the design. The in-house system is a faithful adaptation of AWS IAM's mental model for internal platform resources. Understanding AWS IAM precisely means you understand what you're building and why every design choice exists.

### 0.1 What IAM Is and Is Not

AWS IAM is an **authorization** system, not an authentication system. It answers the question: *given that I know who you are, are you allowed to do this thing?* Authentication (proving who you are) is handled separately — by console login with passwords + MFA, by the AWS SDK signing requests with access keys, or by OIDC/SAML federation. IAM never verifies identity; it only enforces access policy once identity is established.

IAM is also **not a network firewall**. It controls API-level access to AWS service operations. A Security Group controls whether a TCP packet reaches an EC2 instance; IAM controls whether a `DeleteObject` API call on S3 is permitted. Both are needed; they operate at different layers.

IAM is **global** within an AWS account — it is not a regional service. A policy created in us-east-1 applies to resources in ap-southeast-1 as well, though some services (like S3) have additional resource-level controls.

---

### 0.2 The Six Core Concepts

#### 1. Principal
The entity making a request. AWS recognizes four kinds:

| Principal Type | Description | Example ARN |
|---|---|---|
| **IAM User** | A long-lived identity representing a human or application | `arn:aws:iam::123456789012:user/alice` |
| **IAM Group** | A collection of IAM Users that share policies; not a principal itself — policies on groups attach to the member users | `arn:aws:iam::123456789012:group/developers` |
| **IAM Role** | An assumable identity with no long-lived credentials; designed for delegation | `arn:aws:iam::123456789012:role/lambda-execution-role` |
| **AWS Service** | AWS services themselves (e.g., Lambda, EC2) that need to call other AWS services on your behalf | `lambda.amazonaws.com` |

A critical distinction: **Users have passwords and access keys** (long-lived credentials). **Roles have no credentials** — they issue temporary credentials via STS when assumed. This is why AWS pushes roles over users for everything except human console access.

#### 2. Resource
The AWS entity being acted upon. Every resource has an ARN (Amazon Resource Name):

```
arn:partition:service:region:account-id:resource-type/resource-id

arn:aws:s3:::my-bucket                          # S3 bucket (no region, no account — global)
arn:aws:s3:::my-bucket/path/to/object.txt       # S3 object
arn:aws:dynamodb:us-east-1:123456789012:table/Orders
arn:aws:lambda:us-east-1:123456789012:function:ProcessOrder
arn:aws:iam::123456789012:role/deployer
```

The `*` wildcard is valid anywhere in an ARN: `arn:aws:s3:::my-bucket/*` means all objects in `my-bucket`. `arn:aws:dynamodb:*:*:table/Orders` means the Orders table in any region, any account (dangerous).

#### 3. Action
What operation is being requested. Actions are always `service:Operation` pairs:

```
s3:GetObject        s3:PutObject        s3:DeleteObject    s3:ListBucket
dynamodb:GetItem    dynamodb:PutItem    dynamodb:Query      dynamodb:DeleteTable
ec2:RunInstances    ec2:TerminateInstances
iam:CreateUser      iam:AttachUserPolicy
sts:AssumeRole
```

Wildcards apply: `s3:*` means all S3 actions; `s3:*Object` means GetObject, PutObject, DeleteObject, CopyObject, etc.

#### 4. Policy
A JSON document that defines permissions. A policy is **inert until attached** to a principal or resource. The document structure:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadOnMyBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ],
      "Condition": {
        "StringEquals": { "aws:RequestedRegion": "us-east-1" },
        "Bool":         { "aws:MultiFactorAuthPresent": "true" }
      }
    },
    {
      "Sid": "DenyDeleteEverywhere",
      "Effect": "Deny",
      "Action": "s3:DeleteObject",
      "Resource": "*"
    }
  ]
}
```

- `Version`: always `"2012-10-17"` — this is a schema version, not a date you change
- `Statement`: array of permission blocks (evaluated as a whole; order does not matter)
- `Sid`: optional human-readable label, unique within the document
- `Effect`: `Allow` or `Deny` — these are the only two values
- `Action`: single string or array; supports wildcards
- `Resource`: single ARN, array, or `"*"` (all resources)
- `Condition`: optional; if present, the statement only applies when ALL conditions are true

#### 5. Role and Trust Policy
A Role has two policy documents attached to it, which confuses most people:

**Trust Policy** — answers: *who is allowed to assume this role?*
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```
This says: "Lambda (the AWS service) may call `sts:AssumeRole` to become this role." Without a trust policy entry for your entity, you cannot assume the role regardless of your own permissions.

**Permission Policies** — answers: *what is this role allowed to do?*
Standard policy documents attached to the role; define the actual permissions the role carries.

When a principal assumes a role:
1. STS validates the trust policy (is this principal allowed to assume the role?)
2. STS issues temporary credentials: `AccessKeyId`, `SecretAccessKey`, `SessionToken`, expiry
3. The principal uses those credentials for subsequent API calls
4. Those calls are evaluated against the role's permission policies, not the original principal's

#### 6. Condition
Conditions add context-aware constraints to statements. AWS evaluates conditions as:

```
outer key     = condition operator (how to compare)
inner key     = condition key (what to compare)
inner value   = expected value(s)

Multiple inner keys within one operator → AND (all must match)
Multiple values in one inner key → OR (any must match)
Multiple condition blocks → AND (all operators must match)
```

Common operators:

| Operator | Applies To | Example |
|---|---|---|
| `StringEquals` | String context keys | `aws:RequestedRegion = us-east-1` |
| `StringLike` | Strings with wildcards | `s3:prefix = home/${aws:username}/*` |
| `IpAddress` / `NotIpAddress` | IP or CIDR | `aws:SourceIp = 203.0.113.0/24` |
| `Bool` | Boolean context keys | `aws:MultiFactorAuthPresent = true` |
| `DateGreaterThan` | Timestamp keys | `aws:CurrentTime > 2024-01-01T00:00:00Z` |
| `NumericLessThan` | Numeric keys | `s3:max-keys < 1000` |
| `ArnLike` | ARN matching with wildcards | `aws:SourceArn = arn:aws:sns:*:*:prod-*` |
| `Null` | Key presence check | `aws:MultiFactorAuthAge = false` (key must exist) |

The `IfExists` suffix (e.g., `StringEqualsIfExists`) means: if the key is absent, pass the condition — only evaluate if the key is present. Critical for writing policies that work across services that don't always send the context key.

---

### 0.3 Five Policy Types — and When Each Applies

AWS has five distinct policy types, each serving a different trust boundary:

#### Type 1: Identity-Based Policy
Attached to a **User, Group, or Role**. Controls what that identity can do.
- **Managed policy**: standalone document reusable across multiple identities (AWS-managed or customer-managed)
- **Inline policy**: embedded directly in one identity; deleted when the identity is deleted
- Identity-based policies form the primary "allow" surface for most use cases

```
User alice
  └── Identity-based policy: AllowS3Read
        └── Effect: Allow, Action: s3:GetObject, Resource: arn:aws:s3:::my-bucket/*
```

#### Type 2: Resource-Based Policy
Attached to a **resource** (S3 bucket policy, SQS queue policy, Lambda resource policy, etc.). Controls who can access that resource.

Resource-based policies are the only way to grant **cross-account access without role assumption** — you can name an ARN from a different account in the Principal field of an S3 bucket policy, and that account's users can access it directly.

```json
{
  "Statement": [{
    "Principal": { "AWS": "arn:aws:iam::999999999999:user/bob" },
    "Effect": "Allow",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::my-bucket/*"
  }]
}
```

Not all services support resource-based policies. S3, SQS, SNS, Lambda, KMS do. DynamoDB and EC2 do not — cross-account access to those always requires role assumption.

#### Type 3: Permission Boundary
A **ceiling** on what an identity can do. Set on a User or Role. The effective permissions are the **intersection** of the identity's policies and the boundary.

```
Identity Policy: Allow s3:*, ec2:*, iam:*
Permission Boundary: Allow s3:*, ec2:*
Effective Permissions: s3:*, ec2:*   ← iam:* is cut off by the boundary
```

Critical use case: **delegated administration**. If you give a junior admin permission to create IAM roles, they could create a role with AdministratorAccess and use it to escalate. If you mandate that all roles they create must have a permission boundary that excludes `iam:*`, they can't escalate beyond their own boundary.

#### Type 4: Organizations SCP (Service Control Policy)
A **maximum permissions guardrail** set at the AWS Organizations level. Applies to all accounts in an OU or the organization. An SCP cannot grant permissions — it can only restrict.

```
SCP on "Production" OU: Deny ec2:TerminateInstances
→ No user in any account in the Production OU can terminate EC2 instances,
  even if their identity policy explicitly Allows it.
```

SCPs are transparent to IAM evaluation within the account — IAM evaluates as if the SCP is a permission boundary applied at the account level.

#### Type 5: Session Policy
Passed inline when calling `sts:AssumeRole` or `sts:GetFederationToken`. Scopes down the role's permissions for that specific session. The effective permissions are the intersection of the role's policies and the session policy.

```python
sts.assume_role(
    RoleArn="arn:aws:iam::123456789012:role/DataScientist",
    RoleSessionName="alice-jupyter-session",
    Policy=json.dumps({
        "Statement": [{
            "Effect": "Allow",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::ml-data/alice/*"  # only alice's prefix
        }]
    })
)
```

The data science role might have broad S3 access; the session policy scopes it to exactly one S3 prefix. This is how you issue least-privilege temporary tokens without creating a new role per user.

---

### 0.4 The Policy Evaluation Algorithm — Complete Flow

This is the most important thing to understand. AWS evaluates policy in a strict, deterministic order. **Memorize this — it comes up in every IAM design conversation.**

```
Request: (principal P, action A, resource R, context C)

Step 1 ── Organizations SCP check
         If an SCP applies and does NOT allow (A, R) → DENY immediately
         SCPs are guardrails: if none of the SCPs cover this action → DENY

Step 2 ── Resource-based policy check (for cross-account requests)
         If P is from a different account than R:
           If no resource-based policy on R explicitly Allows P → DENY
           (Cross-account requires both sides to agree)

Step 3 ── IAM Permission Boundary check (if P has a boundary)
         If boundary exists and does NOT Allow (A, R) → DENY

Step 4 ── Session Policy check (if P is using a role session)
         If session policy exists and does NOT Allow (A, R) → DENY

Step 5 ── Explicit Deny scan
         Collect all applicable identity-based + resource-based policies for P
         If ANY statement has Effect=Deny AND matches (A, R, C) → DENY
         Explicit deny ALWAYS wins over any explicit allow

Step 6 ── Explicit Allow scan
         If ANY statement has Effect=Allow AND matches (A, R, C) → ALLOW

Step 7 ── Implicit Deny (default)
         No matching Allow found → DENY
```

**The three rules that govern all edge cases:**
1. **Explicit Deny always wins** — nothing overrides a Deny statement
2. **Default is Deny** — you must explicitly grant every permission; missing = denied
3. **Cross-account requires both sides** — a resource policy must allow the foreign principal AND the foreign principal's identity policy must allow the action

**Common mistake:** `Allow *:*` on an identity policy does not give you full access if an SCP or permission boundary restricts it. Many engineers assume "Allow *" = full access. It means "as much as the layers above permit."

---

### 0.5 IAM Roles — The Three Primary Use Patterns

Roles are the most powerful and most misunderstood IAM primitive. Three canonical patterns:

#### Pattern 1: Service Role (EC2, Lambda, ECS Task Role)
A service needs to call other AWS services. Instead of putting access keys in environment variables, you attach a role to the compute resource. The AWS SDK auto-fetches temporary credentials from the instance metadata endpoint.

```
EC2 instance → instance profile → IAM Role "my-app-role"
                                   └── Policy: Allow s3:GetObject on my-bucket/*
App on EC2 → boto3.client('s3').get_object() → SDK fetches creds from 169.254.169.254
→ Credentials auto-rotated every hour, never touch disk, never in code
```

**Key design principle:** Never put access keys in application code or environment variables if a service role can be attached. Long-lived keys are the #1 source of credential leaks.

#### Pattern 2: Cross-Account Role Assumption
Account A needs to access resources in Account B. The pattern: B creates a role with a trust policy naming A's account; A's user/role calls `sts:AssumeRole` on B's role ARN; gets temporary credentials scoped to B's permissions.

```
Account A (Audit Account)
  User "auditor" calls sts:AssumeRole(arn:aws:iam::ACCOUNT_B:role/ReadOnlyAudit)

Account B (Production Account)
  Role "ReadOnlyAudit"
    Trust policy: { Principal: { AWS: "arn:aws:iam::ACCOUNT_A:root" }, Action: sts:AssumeRole }
    Permission policy: Allow ec2:Describe*, s3:List*, cloudwatch:Get*

Result: auditor gets a 1-hour token scoped to ReadOnly in Account B
```

This is the basis for AWS Organizations centralized audit, AWS Config, and Security Hub — they all assume cross-account roles into your member accounts.

#### Pattern 3: Identity Federation (OIDC/SAML)
Employees log in via your corporate IdP (Okta, Active Directory). The IdP asserts their identity via SAML or OIDC. AWS STS exchanges the assertion for temporary credentials.

```
Employee → Okta login → SAML assertion
         → sts:AssumeRoleWithSAML(roleArn=..., samlAssertion=...)
         → Temporary credentials for IAM Role mapped to their Okta group
         → AWS Console session or programmatic access
```

OIDC works identically for web applications and for GitHub Actions CI/CD: the CI system gets an OIDC token proving it's running for repo X on branch Y; STS exchanges it for AWS credentials with a role whose trust policy validates those claims.

---

### 0.6 STS — Security Token Service

STS is the credential-issuance service. All temporary credentials come from STS. Five key APIs:

| API | When to Use |
|---|---|
| `AssumeRole` | Cross-account or same-account role assumption by an IAM principal |
| `AssumeRoleWithWebIdentity` | OIDC federation (Cognito, GitHub Actions, Kubernetes IRSA) |
| `AssumeRoleWithSAML` | Enterprise SAML federation (Okta, ADFS) |
| `GetFederationToken` | Issue temp credentials for a federated user (legacy; prefer AssumeRole) |
| `GetSessionToken` | Issue temp credentials for an existing IAM User with MFA |

All STS responses return the same structure:
```json
{
  "Credentials": {
    "AccessKeyId":     "ASIA...",
    "SecretAccessKey": "wJalrXUtnFEMI...",
    "SessionToken":    "IQoJb3JpZ2lu...",
    "Expiration":      "2024-01-15T12:00:00Z"
  },
  "AssumedRoleUser": {
    "AssumedRoleId":  "AROAI3KUPZ6EXAMPLE:session-name",
    "Arn":            "arn:aws:sts::123456789012:assumed-role/RoleName/session-name"
  }
}
```

The `SessionToken` must accompany every API call when using temporary credentials. The SDK handles this automatically when credentials are obtained via `AssumeRole` or instance metadata.

Token lifetime defaults:
- `AssumeRole`: 1 hour (min 15 min, max 12 hours if role allows)
- `AssumeRoleWithWebIdentity`: 1 hour
- EC2 instance metadata creds: auto-rotated every 6 hours

---

### 0.7 Common IAM Usage Patterns at FAANG Scale

#### Least Privilege via Permission Boundaries + SCPs

The standard FAANG pattern for giving teams self-service IAM access without privilege escalation:

```
Root → SCP on Production OU: Deny iam:*, Deny s3:DeleteBucket, Deny ec2:TerminateInstances in prod
     → Each team account has a "TeamAdmin" role
     → TeamAdmin can create roles/users BUT must attach the org-standard permission boundary
     → Permission boundary: { Allow: everything EXCEPT iam:*, except specific admin actions }
     → Net result: teams are self-sufficient, can't escalate to org-admin level
```

#### Service Mesh Authorization (Workload Identity)

At scale, services authenticate to each other using IAM roles assigned to the compute:

```
Service A (ECS Task Role: arn:aws:iam::...:role/service-a-task)
  → calls Service B's API
  → request signed with STS creds from ECS task role
  → Service B's resource policy or API Gateway authorizer validates the caller's ARN
  → No hardcoded service credentials anywhere
```

This is exactly the pattern the in-house scheduler uses for its `ServiceAccount` principal type.

#### Dynamic Least Privilege via Session Policies

Data platform issuing user-scoped S3 access:

```
User wants to read their personal workspace files
→ Backend calls sts:AssumeRole with Session Policy:
  { Allow s3:GetObject on arn:aws:s3:::workspaces/${userId}/* }
→ Issues 15-minute token to the browser
→ Browser uploads/downloads directly to S3
→ Token expires; no standing access
```

Pattern: permanent role with broad permissions + session policy that narrows to exactly what this user-at-this-moment needs.

#### Break-Glass Access

For production incidents, no engineer should have standing access. Break-glass pattern:

```
1. PagerDuty alert fires → engineer needs prod DB access
2. Engineer calls internal "break-glass" API with incident ID
3. API assumes a "break-glass-db-reader" role with 1-hour session
4. Cloudtrail + SIEM alert fires: "break-glass role assumed by alice, incident INC-1234"
5. Session expires after 1 hour; all access auto-revoked
6. Audit trail is permanent and tamper-proof
```

---

### 0.8 IAM Quotas and Operational Limits

Worth knowing for design discussions:

| Limit | Default |
|---|---|
| Managed policies per IAM entity | 10 (user/role/group) |
| Size of a managed policy document | 6,144 characters |
| IAM Users per account | 5,000 |
| IAM Roles per account | 1,000 (adjustable) |
| IAM Groups per account | 300 |
| Policy versions retained | 5 per managed policy |
| Max session duration (AssumeRole) | 12 hours |
| Min session duration | 15 minutes |
| STS token size (with session policy) | 2,048 bytes for inline session policy |

These limits inform the in-house design decisions: no limit of 10 policies per principal (we control the store), document size governed by statement count validation in `PolicyValidator`, policy version history retained indefinitely (columnar storage is cheap).

---

### 0.9 AWS CloudTrail — The Audit Layer

Every AWS API call (including all IAM and STS operations) is logged to CloudTrail. A CloudTrail log entry:

```json
{
  "eventTime":       "2024-01-15T10:23:45Z",
  "eventSource":     "s3.amazonaws.com",
  "eventName":       "GetObject",
  "userIdentity": {
    "type":           "AssumedRole",
    "principalId":    "AROAI3KUPZ6EXAMPLE:alice-session",
    "arn":            "arn:aws:sts::123456789012:assumed-role/DataScientist/alice-session",
    "accountId":      "123456789012",
    "sessionContext": {
      "sessionIssuer": {
        "type":     "Role",
        "arn":      "arn:aws:iam::123456789012:role/DataScientist"
      },
      "mfaAuthenticated": "true"
    }
  },
  "requestParameters": { "bucketName": "ml-data", "key": "alice/model-v2.pkl" },
  "responseElements":  null,
  "sourceIPAddress":   "203.0.113.45",
  "errorCode":         null,
  "errorMessage":      null
}
```

Key fields for incident investigation:
- `userIdentity.arn` — who made the call (after role assumption, shows the session ARN)
- `userIdentity.sessionContext.sessionIssuer.arn` — which role the session came from
- `errorCode` — `AccessDenied` if IAM blocked the call
- `requestParameters` — what exactly they were trying to access

The in-house audit pipeline replicates this structure into ClickHouse: every authorization decision is a CloudTrail-equivalent event that answers the same who/what/when/allowed questions.

---

### 0.10 What the In-House System Takes from AWS IAM

| AWS IAM Concept | In-House Equivalent | Notes |
|---|---|---|
| IAM User | `User` principal | Same semantics; no long-lived access keys in in-house (always token-based) |
| IAM Group | `Group` principal | Same semantics |
| IAM Role | `Role` principal | Same semantics; trust policy identical |
| Service Principal | `ServiceAccount` | First-class concept (AWS buries this in role trust policies) |
| ARN | Platform URN (`urn:platform:service:env:id`) | Same structure; different namespace |
| Identity-based policy | `PolicyAttachment` with `type=IDENTITY` | Identical JSON structure |
| Resource-based policy | `PolicyAttachment` with `type=RESOURCE` | Identical semantics |
| Permission Boundary | `PolicyAttachment` with `type=PERMISSION_BOUNDARY` | Identical semantics |
| SCP | Out of scope (single-org, no nested orgs) | Could be added as `OrgPolicy` layer |
| Session Policy | Embedded in JWT claims on `AssumeRole` | Same scoping semantics |
| `sts:AssumeRole` | `POST /v1/sts/assume-role` | Same flow; JWT instead of AWS-format temp creds |
| CloudTrail | Kafka → Flink → ClickHouse audit pipeline | Same data per event; self-hosted |
| IAM Policy Simulator | `POST /v1/simulate` | Same inputs/outputs |
| Condition operators | `ConditionOperatorRegistry` with same operator names | `StringEquals`, `IpAddress`, `Bool`, `DateGreaterThan` etc. |

---

## 1. Why Build This — Motivation

### The Problem with Per-Service Authorization

Most platforms start with authorization baked into each service: a `roles` table, a `permissions` column, middleware that checks `user.role == 'ADMIN'`. This works for one service. It breaks at scale.

**The pain points that drove this build:**

| Problem | Per-service RBAC reality | Impact |
|---|---|---|
| **No cross-service policy** | Each service owns its own role model; there's no way to say "user A can read Orders AND write Inventory" in one place | Users get access in one service but not adjacent ones; support tickets for every permission change |
| **No least-privilege enforcement** | Role assignments are coarse (`ADMIN`, `USER`, `READ_ONLY`); no way to say "read Orders for account 12345 only" | Developers get admin access to prod because there's no narrower role available |
| **No audit trail** | Permission checks are in-memory; nothing records that user X accessed resource Y at time T | Compliance failures; can't answer "who had access to this record on Dec 31?" |
| **No temporary / delegated access** | Permanent role assignments only; no way to grant a service cross-account access for 1 hour | Engineers share long-lived credentials to work around the missing delegation model |
| **Policy drift** | Each service team copies and evolves the RBAC schema; models diverge | Three different definitions of "what can a `MODERATOR` do?" across three services |
| **No policy simulation** | Can't ask "would this user be allowed to do X?" without making the actual call | Debugging access issues requires production traffic; no safe pre-flight check |

### Why Not Use AWS IAM Directly

AWS IAM controls access to AWS resources. It cannot authorize access to internal application resources (e.g., `urn:platform:orders:12345`). The IAM policy engine, the evaluation algorithm, and the concept model are the right primitives — the goal is to replicate that model for internal platform resources.

---

## 1. Requirements (RESHADED — R)

### Functional
- **Identity management:** Create/update/delete Users, Groups, Service Accounts (machine identities), and Roles
- **Policy management:** Define JSON policies with `Effect`, `Action`, `Resource`, and `Condition` blocks; attach to identities
- **Policy types:** Identity-based policies (attached to user/group/role), Resource-based policies (attached to a resource), Permission boundaries (max permission cap on an identity)
- **Role assumption:** A principal can assume a role (like `sts:AssumeRole`) and receive short-lived credentials scoped to that role's policies
- **Authorization check:** Single API — `IsAuthorized(principal, action, resource, context)` → `Allow | Deny`
- **Policy evaluation order:** Explicit Deny > Permission Boundary > Explicit Allow (identity) > Resource-based Allow > Implicit Deny
- **Conditions:** Policy statements can have conditions: IP range, time-of-day, MFA required, request tags
- **Policy simulation:** `SimulatePolicy(principal, action, resource)` → decision + which policy produced it
- **Wildcard matching:** Actions and resources support `*` and `?` glob patterns
- **Audit log:** Every authorization decision (allow or deny) recorded with principal, action, resource, matched policy, timestamp

### Non-Functional
| Attribute | Target |
|---|---|
| Authorization check latency | p50 < 2ms, p99 < 5ms |
| Availability | 99.99% (authorization is in the critical path of every API call) |
| Throughput | 100,000 authorization checks/second |
| Policy store scale | 1M policies, 10M identities, 1B audit records/year |
| Policy propagation | Changes visible to authorization engine within 5 seconds |
| Zero-trust default | Implicit deny — no access unless explicitly granted |

---

## 2. Estimation (RESHADED — E)

**Traffic**
- 100K services × avg 10 RPS each × 2 auth checks per request = **2M authorization checks/second** at peak
- Policy admin operations (create/update/delete): ~1,000 writes/second

**Storage**
- Policies: 1M policies × 5KB avg = **5 GB** (fits in memory with caching)
- Identity-policy bindings: 10M identities × 10 policies each = 100M rows → **~50 GB** (relational DB)
- Audit records: 2M/s × 500 bytes × 86,400 s/day = **~85 TB/day** → stream to cold storage; keep 90 days hot = **~7.7 PB** → compress + columnar = **~500 GB hot**

**Cache math**
- 80% of checks are for 20% of (principal, resource) pairs (power law)
- Cache 1M most-active policy decision entries × 1KB = **1 GB per cache node** — trivially fits
- 5s propagation SLA → TTL ≤ 5s on cached decisions

---

## 3. Core Concepts

### Identity Model

```
┌──────────────────────────────────────────────────────┐
│                    Principal                          │
│  (who is making the request)                         │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │   User   │  │  Group   │  │ Service Account  │   │
│  │(human)   │  │(set of   │  │(machine identity)│   │
│  │          │  │ users)   │  │                  │   │
│  └──────────┘  └──────────┘  └──────────────────┘   │
│        │             │                │              │
│        └─────────────┴────────────────┘              │
│                      │                               │
│                   assumes                            │
│                      ▼                               │
│               ┌────────────┐                         │
│               │    Role    │                         │
│               │(assumable  │                         │
│               │ identity)  │                         │
│               └────────────┘                         │
└──────────────────────────────────────────────────────┘
```

### Policy Model (AWS IAM-Compatible JSON)

```json
{
  "Version": "2024-01-01",
  "Statement": [
    {
      "Sid": "AllowOrderRead",
      "Effect": "Allow",
      "Action": [
        "orders:GetOrder",
        "orders:ListOrders"
      ],
      "Resource": "urn:platform:orders:*",
      "Condition": {
        "StringEquals": { "platform:RequestedRegion": "us-east-1" },
        "Bool":         { "platform:MultiFactorAuthPresent": "true" }
      }
    },
    {
      "Sid": "DenyProdDelete",
      "Effect": "Deny",
      "Action": "orders:DeleteOrder",
      "Resource": "urn:platform:orders:prod:*"
    }
  ]
}
```

### Policy Evaluation Algorithm

```
Request: (principal P, action A, resource R, context C)

1. Collect all policies applicable to P:
   - Policies directly attached to P (identity-based)
   - Policies attached to groups P belongs to
   - If P has assumed a role: policies attached to that role
   - Resource-based policies on R that name P

2. Determine permission boundary (if any) for P

3. Evaluate:
   ┌─────────────────────────────────────────────────────┐
   │  Does any applicable policy have Effect=Deny        │
   │  AND matches (A, R, C)?                             │
   │          YES → DENY (explicit deny wins always)     │
   │           NO → continue                             │
   ├─────────────────────────────────────────────────────┤
   │  Does any applicable policy have Effect=Allow       │
   │  AND matches (A, R, C)?                             │
   │           NO → DENY (implicit deny)                 │
   │          YES → continue                             │
   ├─────────────────────────────────────────────────────┤
   │  Is there a permission boundary?                    │
   │          YES → Does boundary also Allow (A, R, C)?  │
   │                 NO → DENY (boundary blocks allow)   │
   │                YES → ALLOW                          │
   │           NO → ALLOW                                │
   └─────────────────────────────────────────────────────┘
```

---

## 4. High-Level Architecture (RESHADED — S, H)

```
                                   ┌──────────────────────────────────────────────────┐
                                   │                 Client Services                   │
                                   │   (Orders, Inventory, Payments, Analytics...)     │
                                   └──────────┬─────────────────────┬─────────────────┘
                                              │ IsAuthorized()       │ Admin CRUD
                                              │ (sync, <5ms)         │ (async ok)
                          ┌───────────────────▼──────┐  ┌───────────▼─────────────────┐
                          │   Authorization Gateway   │  │        Admin API             │
                          │   (stateless, N nodes)    │  │   (REST, rate-limited)       │
                          └───────────┬───────────────┘  └───────────┬─────────────────┘
                                      │                               │
                         ┌────────────▼───────────────────────────────▼──────────┐
                         │                    IAM Core Service                    │
                         │                                                        │
                         │  ┌──────────────────┐   ┌───────────────────────────┐ │
                         │  │  Policy Engine   │   │    Identity Manager       │ │
                         │  │  (evaluation)    │   │ (users/groups/roles/SAs)  │ │
                         │  └────────┬─────────┘   └───────────────────────────┘ │
                         │           │                                             │
                         │  ┌────────▼─────────┐   ┌───────────────────────────┐ │
                         │  │ Decision Cache   │   │       STS Service         │ │
                         │  │ (Redis, TTL=5s)  │   │  (role assumption, temp   │ │
                         │  └──────────────────┘   │   credentials)            │ │
                         │                         └───────────────────────────┘ │
                         └──────────┬─────────────────────────┬───────────────────┘
                                    │                         │
               ┌────────────────────▼──────────┐  ┌──────────▼──────────────────────┐
               │        Policy Store            │  │       Identity Store             │
               │  (Postgres — source of truth)  │  │  (Postgres — users, groups,     │
               │  Policies, Attachments,        │  │   roles, memberships)            │
               │  Resource-based policies       │  └─────────────────────────────────┘
               └────────────────────┬──────────┘
                                    │  publish on change
               ┌────────────────────▼──────────────────────────────────┐
               │              Policy Cache (Redis Cluster)              │
               │  Resolved policy set per principal — TTL 5s           │
               │  Invalidated on policy/attachment write                │
               └────────────────────┬──────────────────────────────────┘
                                    │
               ┌────────────────────▼──────────────────────────────────┐
               │              Audit Pipeline                            │
               │  Auth Gateway → Kafka → Flink → ClickHouse/S3         │
               │  Every decision logged: principal, action,             │
               │  resource, matched policy, allow/deny, latency         │
               └────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Scale |
|---|---|---|
| **Authorization Gateway** | Receives `IsAuthorized` RPC; looks up cache; falls back to Policy Engine; writes audit event | Stateless, horizontally scaled; 50+ nodes at peak |
| **Policy Engine** | Fetches applicable policies for principal; runs evaluation algorithm; returns decision + matched policy ID | Stateless; called only on cache miss |
| **Identity Manager** | CRUD for users, groups, roles, service accounts; manages memberships and policy attachments | 2-node active-passive; writes are low-frequency |
| **STS Service** | Issues short-lived JWT tokens when a principal assumes a role; tokens carry embedded policy snapshot | Stateless |
| **Policy Store** | Postgres: source of truth for all policy documents and attachments | Single writer; read replicas for Policy Engine |
| **Identity Store** | Postgres: principal hierarchy, group memberships, role trust policies | Single writer; read replicas |
| **Decision Cache** | Redis Cluster: cached `IsAuthorized` decisions keyed by `(principal, action, resource)` → `{allow/deny, policy_id, ttl}` | 5-node cluster, ~1M keys, ~1GB |
| **Policy Cache** | Redis: resolved effective policy set per principal; invalidated within 5s of any policy change | Warm on first auth check; LRU eviction |
| **Audit Pipeline** | Kafka topic per region; Flink jobs aggregate and sink to ClickHouse (90-day hot) + S3 (cold) | 2M events/sec; Kafka partition per principal hash |

---

## 5. API Design (RESHADED — A)

### Authorization API (gRPC — latency critical)

```protobuf
service AuthorizationService {
  rpc IsAuthorized (AuthorizationRequest) returns (AuthorizationResponse);
  rpc BatchIsAuthorized (BatchAuthorizationRequest) returns (BatchAuthorizationResponse);
  rpc SimulatePolicy (SimulatePolicyRequest) returns (SimulatePolicyResponse);
}

message AuthorizationRequest {
  string principal_arn = 1;     // urn:iam:user:alice / urn:iam:role:deployer
  string action        = 2;     // orders:GetOrder
  string resource      = 3;     // urn:platform:orders:prod:12345
  map<string, string> context = 4;  // ip_address, mfa_present, request_time, tags
}

message AuthorizationResponse {
  enum Decision { ALLOW = 0; DENY = 1; }
  Decision decision   = 1;
  string   reason     = 2;      // "ExplicitDeny:policy-arn-xyz" | "ImplicitDeny" | "Allow:policy-arn-abc"
  string   request_id = 3;      // audit correlation
}
```

### Admin REST API

```
# Policies
POST   /v1/policies                            Create policy document
GET    /v1/policies/{policyId}                 Get policy + all attachments
PUT    /v1/policies/{policyId}                 Update policy (creates new version)
DELETE /v1/policies/{policyId}                 Delete policy
GET    /v1/policies/{policyId}/versions        List versions (immutable history)

# Identities
POST   /v1/users                               Create user
POST   /v1/groups                              Create group
POST   /v1/groups/{groupId}/members            Add user to group
POST   /v1/roles                               Create role + trust policy
POST   /v1/service-accounts                    Create machine identity

# Attachments
POST   /v1/users/{userId}/policies             Attach policy to user
POST   /v1/groups/{groupId}/policies           Attach policy to group
POST   /v1/roles/{roleId}/policies             Attach policy to role
POST   /v1/resources/{resourceArn}/policies    Set resource-based policy
PUT    /v1/users/{userId}/permission-boundary  Set permission boundary

# STS
POST   /v1/sts/assume-role                     Assume a role, get temp credentials
POST   /v1/sts/assume-role-with-token          Assume role via OIDC/SAML token

# Simulation
POST   /v1/simulate                            Dry-run authorization check
```

---

## 6. Data Model (RESHADED — S, D)

```
┌─────────────────┐       ┌────────────────────┐       ┌────────────────────┐
│   principals    │       │ principal_policies  │       │      policies      │
│─────────────────│       │────────────────────│       │────────────────────│
│ id (uuid)       │──┐    │ principal_id (fk)  │    ┌──│ id (uuid)          │
│ type            │  └───►│ policy_id (fk)     │◄───┘  │ name               │
│   USER          │       │ attached_at        │       │ version            │
│   GROUP         │       │ attached_by        │       │ document (jsonb)   │
│   ROLE          │       └────────────────────┘       │ created_by         │
│   SERVICE_ACCT  │                                    │ created_at         │
│ name            │       ┌────────────────────┐       └────────────────────┘
│ arn             │       │   group_members    │
│ trust_policy    │       │────────────────────│       ┌────────────────────┐
│   (jsonb, roles)│       │ group_id (fk)      │       │  resource_policies │
│ permission_     │       │ member_id (fk)     │       │────────────────────│
│   boundary_id   │       │ added_at           │       │ resource_arn       │
│ created_at      │       └────────────────────┘       │ policy_id (fk)     │
│ deleted_at      │                                    │ attached_at        │
└─────────────────┘       ┌────────────────────┐       └────────────────────┘
                          │   policy_versions  │
                          │────────────────────│       ┌────────────────────┐
                          │ policy_id (fk)     │       │   audit_decisions  │
                          │ version_number     │       │────────────────────│
                          │ document (jsonb)   │       │ id                 │
                          │ created_at         │       │ principal_arn      │
                          │ created_by         │       │ action             │
                          └────────────────────┘       │ resource           │
                                                       │ decision           │
                          ┌────────────────────┐       │ matched_policy_id  │
                          │  temp_credentials  │       │ context (jsonb)    │
                          │────────────────────│       │ latency_ms         │
                          │ token_id           │       │ ts (partitioned)   │
                          │ principal_arn      │       └────────────────────┘
                          │ assumed_role_arn   │
                          │ policy_snapshot    │
                          │   (jsonb)          │
                          │ expires_at         │
                          │ issued_at          │
                          └────────────────────┘
```

---

## 7. Deep Dives (RESHADED — D)

### 7.1 The Authorization Hot Path (Cache-First)

```
IsAuthorized(alice, orders:GetOrder, urn:platform:orders:prod:12345, ctx)

Step 1: Cache lookup
  key = sha256(principal_arn + action + resource + sorted_context)
  Redis GET → HIT (p80) → return cached decision in <1ms

Step 2: Cache miss → Policy Engine
  2a. Fetch principal's policy set from Policy Cache
      key = principal_arn
      Cache hit → skip DB; cache miss → query DB + populate cache
  2b. Resolve group memberships (cached; TTL 30s)
  2c. Expand wildcard matches: "orders:*" matches "orders:GetOrder"
  2d. Evaluate statements in priority order (Deny first)
  2e. Return decision

Step 3: Write decision to Decision Cache
  SET key decision EX 5  (5s TTL — matches propagation SLA)

Step 4: Async — publish audit event to Kafka
  Fire-and-forget; never blocks the response
```

**Latency budget (p99 cache-miss path):**

| Step | Budget |
|---|---|
| Network (client → gateway) | 0.5ms |
| Policy Cache lookup (Redis) | 0.5ms |
| Policy evaluation (CPU) | 1.0ms |
| Decision Cache write (async) | 0ms (fire-and-forget) |
| Network (gateway → client) | 0.5ms |
| **Total** | **~2.5ms** |

### 7.2 Policy Propagation (5-Second SLA)

```
Admin API writes new policy attachment
          │
          ▼
   Postgres (write)
          │
          ├──► Invalidate Policy Cache key for affected principal (Redis DEL)
          │    → next auth check re-derives from DB
          │
          └──► Publish PolicyChanged event to Kafka
                    │
                    ▼
            All Authorization Gateway nodes consume event
            → each node clears its in-process LRU for that principal
            → next check sees fresh policy within <5s
```

No eventual-consistency window is longer than the Kafka lag + Redis TTL. Both are bounded under 5s under normal conditions.

### 7.3 Role Assumption (STS Flow)

```
Service A wants to call Service B's admin endpoint

1. Service A calls POST /v1/sts/assume-role
   Body: { roleArn: "urn:iam:role:service-b-admin", durationSeconds: 3600 }

2. STS validates:
   - Is Service A's identity in the role's TrustPolicy?
     { "Principal": "urn:iam:service-account:service-a", "Action": "sts:AssumeRole" }
   - Has the role's own policies been checked? (not yet — they scope the issued token)

3. STS issues a signed JWT:
   {
     "sub":         "urn:iam:service-account:service-a",
     "assumed_role": "urn:iam:role:service-b-admin",
     "policy_snapshot": "<base64 of role's effective policy set at issue time>",
     "exp":          now + 3600,
     "jti":          "unique-token-id"
   }
   Policy snapshot is embedded so authorization checks don't need a DB lookup for this token.

4. Service A sends JWT in Authorization header to Service B

5. Service B's auth middleware extracts assumed_role + policy_snapshot from JWT
   → calls IsAuthorized with those policies (no principal DB lookup needed)
   → fast path: policy evaluation only, no identity resolution

6. Token stored in temp_credentials table for revocation checking
   → On revoke, delete row; auth gateway checks jti against revocation set
```

### 7.4 Wildcard Matching in Policies

ARN matching uses a compiled glob automaton, not a regex (avoids ReDoS):

```
Pattern: "urn:platform:orders:prod:*"
Input:   "urn:platform:orders:prod:12345"

Split on ":" → match segment by segment
* in segment → match any non-separator characters
? in segment → match exactly one non-separator character

Pre-compile per policy statement at store time → O(n) matching at eval time
```

### 7.5 Audit Pipeline

```
Authorization Gateway
    │  (fire-and-forget, Kafka producer async batching)
    ▼
Kafka Topic: iam.decisions
    Partition key: principal_arn (ensures per-principal ordering)
    Retention: 24h (ClickHouse consumes within minutes)
    │
    ▼
Flink Job: AuditSink
    - Window: 1s tumbling
    - Enriches with policy name (lookup from Policy Store)
    - Writes to ClickHouse (hot, 90 days) + S3 Parquet (cold, 7 years)
    │
    ▼
ClickHouse Table: iam_decisions
    Partition by: toYYYYMM(ts)
    Order by:     (principal_arn, ts)       ← covers "show all decisions for user X"
    Materialized view: decisions_by_resource ← covers "who accessed resource Y?"
```

---

## 8. Bottlenecks & Failure Modes (RESHADED — E)

| Scenario | Impact | Mitigation |
|---|---|---|
| Redis cluster down | All auth checks hit DB; latency spikes to 50ms+ | Circuit breaker on Redis; fallback to DB with connection pool; shed non-critical traffic |
| Policy Engine bug produces wrong ALLOW | Privilege escalation | Policy simulation endpoint for pre-deploy validation; shadow mode (log decisions, compare with expected) |
| Policy propagation lag > 5s | Stale decisions served from cache | Monitor Kafka consumer lag; alert at 3s; force cache eviction via admin API |
| DB slow on policy fetch | Auth latency spikes | Read replicas for Policy Engine; all writes go to primary; replicas serve all reads |
| Wildcard explosion (`*:*:*:*`) | O(n) policy scan on every request | Validate policies at write time; reject over-broad policies without explicit justification flag |
| JWT token compromise | Attacker uses valid token for 1h | Revocation list in Redis; checked on every auth for tokens in `temp_credentials`; short expiry (1h default, 15min recommended) |
| Audit Kafka backpressure | Auth gateway blocks on Kafka send | Producer is async with local buffer; if buffer full, drop audit event (business integrity > audit completeness for auth latency) |

---

## 9. Security Considerations

- **Defense in depth:** IAM is not the only auth layer. Services should also validate that the resource in the request actually belongs to the account in the token.
- **Bootstrap problem:** Who authorizes calls to the IAM Admin API itself? A separate bootstrap policy attached to a root service account, with MFA required (`platform:MultiFactorAuthPresent: true` condition).
- **Policy injection:** Policy documents are stored as JSONB and never interpreted as code. No eval, no template expansion at query time.
- **Credential rotation:** Service account keys rotated every 90 days; automated via secrets manager integration.
- **Principle of least surprise:** New identities get zero policies by default — implicit deny without a single Allow statement.

---

## 10. Distinctive Features vs AWS IAM

| Feature | AWS IAM | This System |
|---|---|---|
| Resource namespace | AWS ARNs (`arn:aws:s3:::bucket`) | Platform URNs (`urn:platform:orders:prod:12345`) |
| Principal types | User, Group, Role, Federated | Same + Service Account (first-class) |
| Policy evaluation | 5-layer evaluation | Same algorithm |
| Cross-account | Via role assumption across account boundaries | Via role assumption across service boundaries |
| STS | Fully managed | STS service (custom JWT) |
| Audit | CloudTrail | ClickHouse + S3 via Kafka/Flink |
| Admin API | Console + CLI + SDK | REST API (self-service for platform teams) |
| Policy simulation | IAM Policy Simulator | `/v1/simulate` endpoint |
| Propagation SLA | ~seconds (not guaranteed) | Hard 5s SLA with monitoring |

---

## FAANG Interview Callouts

**Q: How do you guarantee sub-5ms authorization at 2M RPS?**
Cache-first: 80% of decisions are served from the Decision Cache (Redis, <1ms). Cache misses hit the Policy Cache (resolved policy set per principal, also Redis). Only cold-start or post-invalidation checks touch the DB. Stateless auth nodes scale horizontally with no shared state except Redis.

**Q: How do you handle the cache invalidation problem when a policy changes?**
Two-pronged: (1) immediate Redis DEL of the affected principal's Policy Cache key on write; (2) Kafka event consumed by all Authorization Gateway nodes to clear their in-process LRU. The Decision Cache TTL is 5s, so even without the explicit invalidation, stale decisions expire within the SLA.

**Q: What's your blast radius if someone gets a policy wrong?**
An overly permissive policy is bounded by the permission boundary of the principal. An overly restrictive policy just causes 403s — the `/v1/simulate` endpoint lets teams test before applying. Explicit Deny statements can never be overridden by any Allow, so a deny-all emergency policy can instantly lock down a compromised identity without touching other policies.

**Q: How does this differ from just using OPA (Open Policy Agent)?**
OPA evaluates Rego policies pulled from a bundle. It's an excellent evaluation engine but doesn't own the identity store, policy store, or audit pipeline. This system is a complete platform — OPA would be a valid choice for just the evaluation layer (swap `PolicyEngine` for an OPA sidecar). The trade-off: OPA's Rego is more expressive but harder to audit and simulate; the JSON policy model here is constrained but reviewable by non-engineers.
