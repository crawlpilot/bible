# AWS IAM (Identity and Access Management)

## Overview
IAM is the foundation of AWS security. Every API call to AWS is authenticated (who are you?) and authorised (are you allowed to do this?) through IAM. There are no "admin" users in a secure AWS environment — everything is governed by least-privilege policies.

**Core concepts**:
| Concept | Description |
|---|---|
| **Principal** | Entity making the request: IAM user, IAM role, AWS service, federated identity |
| **Policy** | JSON document defining allowed/denied actions |
| **Action** | AWS API operation (e.g., `s3:GetObject`, `ec2:DescribeInstances`) |
| **Resource** | The specific AWS resource the action applies to (ARN or `*`) |
| **Condition** | Context constraints (IP address, MFA, time, tag values) |
| **Effect** | `Allow` or `Deny`; explicit `Deny` always wins |

---

## Policy Types

| Type | Attached to | Scope | Use case |
|---|---|---|---|
| **Identity-based** (managed/inline) | IAM user, group, role | What the identity can do | Standard permission grants |
| **Resource-based** | AWS resource (S3, SQS, KMS, etc.) | Who can access this resource | Cross-account access, service-to-service |
| **Permissions boundary** | IAM user or role | Maximum permissions ceiling | Delegate creation to dev teams with guardrails |
| **SCP (Service Control Policy)** | AWS account or OU | Maximum permissions for entire account | Org-wide restrictions |
| **Session policy** | AssumeRole request | Restrict a specific assumed session | Temporary least-privilege credentials |
| **Access control list (ACL)** | S3, VPC | Legacy cross-account | Avoid for new designs |

**Policy evaluation order** (simplified):
1. Explicit **Deny** anywhere → DENY
2. **SCP** doesn't allow → DENY
3. No **Allow** in identity OR resource policy → DENY (implicit deny)
4. **Allow** present and no Deny → ALLOW

**Resource-based + identity-based for cross-account**: If principal is in account A and resource is in account B, BOTH the identity policy (in A) AND the resource policy (in B) must allow the action.

---

## IAM Roles (the central pattern)

**Never use IAM users with long-lived credentials in production code.** Use roles.

| Role type | Use case |
|---|---|
| **EC2 instance role** | EC2 instance assumes role; SDK uses instance metadata service |
| **Lambda execution role** | Lambda assumes this role during invocation |
| **ECS task role** | Per-task credentials; different from task execution role |
| **Service-linked role** | AWS service acts on your behalf (Auto Scaling, RDS, etc.) |
| **Cross-account role** | Account A trusts account B to assume a role |
| **Federated role (SAML/OIDC)** | Corporate IdP or GitHub Actions assumes role |

### Assume Role Flow (Cross-Account)
```
Account A (Developer/Service) → sts:AssumeRole → Account B (Target Role) → API calls to B's resources

Trust policy on the role in Account B:
{
  "Principal": {"AWS": "arn:aws:iam::ACCOUNT-A:role/dev-role"},
  "Action": "sts:AssumeRole",
  "Condition": {"StringEquals": {"sts:ExternalId": "unique-id-12345"}}
}
```
`ExternalId` is required for third-party access (confused deputy protection) — prevents a compromised third-party from using their role to access your account if they happen to know your account ID.

---

## Writing Least-Privilege Policies

### The structure
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowSpecificS3Access",
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:PutObject"
    ],
    "Resource": "arn:aws:s3:::my-bucket/prefix/*",
    "Condition": {
      "StringEquals": {"s3:prefix": ["prefix/"]},
      "Bool": {"aws:SecureTransport": "true"}
    }
  }]
}
```

### Common condition keys

| Condition key | Example | Use |
|---|---|---|
| `aws:SourceIp` | `"aws:SourceIp": ["10.0.0.0/8"]` | Restrict to internal IPs |
| `aws:sourceVpc` | `"aws:sourceVpc": "vpc-xxx"` | Restrict to VPC (for resource policies) |
| `aws:sourceVpce` | VPC endpoint ID | Restrict to a specific VPC endpoint |
| `aws:RequestedRegion` | `["us-east-1", "us-west-2"]` | Prevent resource creation in unwanted regions |
| `aws:CalledVia` | `["cloudformation.amazonaws.com"]` | Only allow when called through CloudFormation |
| `aws:MultiFactorAuthPresent` | `"true"` | Require MFA for sensitive operations |
| `aws:PrincipalTag` | Match tag on the caller's role | Attribute-based access control (ABAC) |
| `iam:PassedToService` | Limit which services a role can be passed to | Prevent privilege escalation via `iam:PassRole` |

---

## Attribute-Based Access Control (ABAC)

Scale permissions using tags instead of hundreds of policies. The same policy applies to all resources/principals with matching tags.

```json
{
  "Effect": "Allow",
  "Action": ["ec2:StartInstances", "ec2:StopInstances"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "ec2:ResourceTag/Team": "${aws:PrincipalTag/Team}",
      "ec2:ResourceTag/Env": "${aws:PrincipalTag/Env}"
    }
  }
}
```

This allows: a principal with tags `Team=payments, Env=prod` to start/stop only EC2 instances tagged `Team=payments, Env=prod`. One policy covers all teams and all environments.

ABAC scales from 10 teams to 100 teams without writing new policies. Critical for multi-tenant or large-org AWS environments.

---

## IAM Permissions Boundary

A permissions boundary caps what an IAM role or user can do — even if their identity policy grants more.

**Use case**: give platform teams the ability to create IAM roles for their services, but restrict those roles from escalating beyond a boundary:

```json
// Permissions boundary: dev-team boundary
{
  "Effect": "Allow",
  "Action": ["s3:*", "lambda:*", "dynamodb:*", "logs:*"],
  "Resource": "*"
}
// Even if the dev creates a role with AdministratorAccess,
// the effective permissions are capped to s3, lambda, dynamodb, logs
```

Platform team grants devs `iam:CreateRole` + `iam:AttachRolePolicy` but requires `iam:CreateRole` to include `PermissionsBoundary = dev-team-boundary`. Enforced by SCP or condition key `iam:PermissionsBoundary`.

---

## Service Control Policies (SCPs)

SCPs apply to entire AWS accounts or OUs in AWS Organizations. They are a ceiling, not a grant. Even if an IAM policy allows something, if the SCP denies it, it's denied.

```json
// Common SCP: deny resource creation outside approved regions
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["us-east-1", "eu-west-1"]
    },
    "ArnNotLike": {
      "aws:PrincipalARN": "arn:aws:iam::*:role/BreakGlass"
    }
  }
}
```

**Critical SCPs to have**:
- Deny leaving AWS Organizations
- Deny disabling CloudTrail
- Deny disabling S3 Block Public Access at account level
- Deny root account usage (except specific break-glass scenarios)
- Deny resource creation in unapproved regions
- Deny disabling GuardDuty, Security Hub, Config

---

## IAM Access Analyser

Automatically finds resources in your account that are accessible from outside your account or organisation.

- Analyses: S3 bucket policies, IAM roles, KMS keys, Lambda function policies, SQS queues, Secrets Manager secrets
- Findings: "This S3 bucket allows public read" or "This role is assumable from external account 123456789"
- Validates policies before deployment — `aws accessanalyzer validate-policy` in CI/CD pipeline
- Generates least-privilege policies from CloudTrail access activity

---

## Key Security Patterns

### No Root Account Usage
- Enable MFA on root account immediately
- Create an IAM admin role; use root only for break-glass scenarios
- SCP to deny root API calls except from a specific condition

### Rotation of Credentials
- **Roles**: credentials rotate automatically (default session: 1 hour; max: 12 hours)
- **Access keys** (if unavoidable): rotate every 90 days via IAM Credential Report
- **Secrets Manager**: automatic rotation for RDS, Redshift, DocumentDB credentials

### Privileged Access Workstation (PAW) Pattern
- Production AWS accounts accessed only via an approved bastion account
- Engineers assume a cross-account role from the bastion account into prod
- CloudTrail logs show: who assumed the role, from which account, at what time, which API calls

---

## Monitoring & Auditing

| Tool | What it provides |
|---|---|
| **CloudTrail** | Full API call log: who, what, when, from where |
| **IAM Access Analyser** | External access findings; unused permissions analysis |
| **IAM Credential Report** | Last used, password age, MFA status for all users |
| **AWS Config** | Continuous compliance — `iam-no-inline-policy`, `iam-root-access-key-check`, `mfa-enabled-for-iam-console-access` |
| **GuardDuty** | Anomaly detection — unusual API calls, credential exfiltration |
| **Security Hub** | Aggregated findings from multiple security services |

**CloudTrail alert examples**:
- `ConsoleLogin` with `MFAUsed=false` from a root account → P0 alert
- `DeleteTrail` or `StopLogging` → immediate alert (someone covering tracks)
- `AssumeRole` with unusual source IP → GuardDuty finding

---

## Best Practices

1. **Never use root account** for daily operations; lock it away with MFA
2. **Use IAM roles everywhere**; no long-lived access keys in code, EC2, Lambda, ECS
3. **Apply least privilege**; start with deny-all and add minimum permissions
4. **Use SCPs** to enforce guardrails at the organisation level — not just IAM policies
5. **Enable IAM Access Analyser** in every account and in every region
6. **Use Permissions Boundaries** when delegating IAM management to developer teams
7. **Adopt ABAC** for scaling permissions across many teams/resources without policy explosion
8. **Rotate access keys** and audit with Credential Report; better: eliminate them
9. **Enable MFA** for all IAM users with console access; enforce via IAM policy condition
10. **Use `aws:CalledVia` conditions** to prevent lateral movement via service chaining

---

## FAANG Interview Points

**"How do you secure cross-account access?"**: IAM role in target account with trust policy allowing specific role ARN from source account. Require `ExternalId` for third-party access. Enforce MFA condition for sensitive operations. Log all `AssumeRole` calls via CloudTrail. SCPs cap maximum permissions.

**"How does IAM evaluation work?"**: Explicit DENY always wins → SCP must allow → permissions boundary must allow → identity policy or resource policy must allow. All must be satisfied for Allow; any Deny = denied.

**"Design IAM strategy for a 500-engineer organisation on AWS"**: AWS Organizations with account-per-team or account-per-environment. SCPs for org-wide guardrails. Centralised identity via AWS SSO (IAM Identity Center) federated to corporate IdP. Permission sets (managed policy bundles) assigned per account per team. ABAC for resource-level isolation. IAM Access Analyser in every account. CloudTrail aggregated to security account.

**"Privilege escalation via IAM"**: Common vector: `iam:CreatePolicyVersion` or `iam:AttachUserPolicy` allows an attacker to grant themselves AdministratorAccess. Mitigation: never grant `iam:*` wildcard; use permissions boundaries; restrict `iam:PassRole` via `iam:PassedToService` condition; audit with IAM Access Analyser.
