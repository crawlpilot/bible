# Zero Trust Security Architecture Pattern

## Overview
Zero Trust is a security model based on the principle "never trust, always verify." Traditional perimeter-based security (trust everything inside the network, distrust everything outside) fails in cloud environments where there is no fixed perimeter — workloads span VPCs, accounts, SaaS, remote users, and third-party services.

Zero Trust replaces network location as the trust signal with **identity** and **context**:
- Who is making the request? (verified identity)
- What device are they on? (device posture)
- What do they want to do? (least-privilege authorisation)
- Is this behaviour normal? (continuous verification)

---

## The Five Pillars

### 1. Identity (Who)
Every access request is authenticated with a strong, verified identity. No implicit trust based on IP address or network location.

**Workload identity (service-to-service)**:
- IRSA (AWS IAM Roles for Service Accounts) — Kubernetes pods
- ECS Task Roles — container tasks
- EC2 Instance Roles — EC2 instances
- Lambda Execution Roles — Lambda functions
- SPIFFE/SPIRE — cross-platform workload identity standard

**Human identity**:
- Multi-factor authentication (MFA) enforced for all users
- SSO via corporate IdP (Okta, Azure AD) federated to AWS IAM Identity Center
- Short-lived credentials only — no long-lived IAM access keys
- Hardware security keys (FIDO2/WebAuthn) for privileged access

### 2. Device (What)
The device's security posture is validated before access is granted:
- MDM-enrolled and managed (Jamf, Intune)
- OS version is current (no known critical CVEs)
- Disk encryption enabled (FileVault, BitLocker)
- EDR agent running (CrowdStrike, SentinelOne)

**AWS implementation**: AWS Verified Access evaluates device posture via a trust provider (Jamf, CrowdStrike) before granting access to internal applications — without a VPN.

### 3. Network (Where)
Micro-segmentation replaces the flat trusted network. Every network path is explicitly authorised.

- **No implicit trust** within a VPC — east-west traffic filtered by Security Groups and NetworkPolicy
- **Service mesh** (Istio, Linkerd, AWS App Mesh) enforces mTLS between services
- **VPC Endpoints** eliminate internet paths for AWS service calls
- **PrivateLink** exposes services across accounts without VPC peering
- **AWS Network Firewall** enforces allowed outbound domain lists (egress filtering)

### 4. Application (How)
Access is authorised at the application level, not just the network level:
- Authentication at every service boundary (JWT validation, mTLS certificate verification)
- Authorisation at every API call (OPA, Cedar, Casbin policy engines)
- API Gateway as the north-south enforcement point (JWT authoriser, WAF)
- Application-level audit logging (who called what, with what parameters)

### 5. Data (What's protected)
Data access is governed independently of compute access:
- Data classification labels (PII, financial, confidential, public)
- Encryption at rest (KMS customer-managed keys) and in transit (TLS 1.2+)
- Column-level and row-level access control (Lake Formation, PostgreSQL RLS)
- Data Loss Prevention (Macie for S3, CloudTrail for data API calls)

---

## Zero Trust on AWS: Reference Architecture

```
Remote user → AWS Verified Access (device posture check + IdP auth)
                  ↓ (approved)
            Private application (no public IP, no VPN required)

Internal service → IRSA/Task Role → short-lived STS credentials
                       ↓
                AWS resource (verified IAM policy)

Service A → mTLS (via Istio sidecar) → Service B
               ↓ (identity verified by certificate)
        OPA policy engine validates: "can service-a call service-b's /payments endpoint?"

Data scientist → Lake Formation (column/row policy) → Athena query
                     ↓ (PII columns filtered, non-authorised rows excluded)
              Results without PII exposure
```

---

## Micro-Segmentation (East-West Traffic Control)

Zero Trust requires that even traffic within the same VPC or cluster is authenticated and authorised.

### AWS Security Groups (Layer 4)
```
api-service-sg: inbound 8080 from gateway-sg only
database-sg: inbound 5432 from api-service-sg only
cache-sg: inbound 6379 from api-service-sg only

No SG allows: database-sg ↔ cache-sg (they should never talk directly)
```

### Kubernetes NetworkPolicy (Layer 3/4)
```yaml
kind: NetworkPolicy
metadata: {name: payments-isolation, namespace: payments}
spec:
  podSelector: {matchLabels: {app: payments-api}}
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {team: api-gateway}}
    ports:
    - protocol: TCP; port: 8080
  egress:
  - to:
    - namespaceSelector: {matchLabels: {team: database}}
    ports:
    - protocol: TCP; port: 5432
```

### Service Mesh mTLS (Layer 7 + Identity)
Istio sidecar (Envoy proxy) handles:
- Mutual TLS between every service pair (workload certificate issued by SPIRE)
- AuthorizationPolicy: `payments-service` can call `inventory-service`'s `/reserve` endpoint; nothing else
- Traffic encryption even within the cluster (east-west TLS)

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata: {name: inventory-authz, namespace: inventory}
spec:
  selector: {matchLabels: {app: inventory-service}}
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/payments/sa/payments-service"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/api/v1/reserve"]
```

---

## AWS Verified Access (VPN Replacement)

Traditional pattern: users VPN into the corporate network, then access internal apps.

Zero Trust pattern: users authenticate + device posture is checked → they access only the specific app they need, without network-level access.

```
User opens browser → AWS Verified Access endpoint
                           ↓ checks:
                     1. Identity: user authenticated via Okta (OIDC)
                     2. Device: device in Jamf MDM, disk encrypted, no critical CVEs
                           ↓ (if both pass)
                     App receives request with user identity header (X-Amzn-Oidc-Identity)
                     App never has a public IP; no VPN required
```

**What it eliminates**: VPN (lateral movement risk — VPN gives network access, not just app access), bastion hosts, public IPs on internal apps.

---

## IAM: Zero Trust Foundation

Zero Trust IAM principles:

| Principle | Implementation |
|---|---|
| Least privilege | One IAM role per service; only the exact permissions needed |
| No standing privilege | Assume roles on-demand; STS credentials expire (1h default) |
| Verify always | IAM validates every API call; no "trusted" network zone bypasses IAM |
| Audit every access | CloudTrail logs every IAM decision; alert on anomalies |
| No long-lived keys | No IAM access keys in code/config; roles only |

**Privilege escalation prevention**: use IAM Access Analyser to verify no role can escalate its own permissions. Restrict `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole` to platform team only.

---

## Secrets Management (Zero Trust for Credentials)

No hardcoded credentials, anywhere. All secrets are:
- Stored in AWS Secrets Manager or HashiCorp Vault
- Retrieved at runtime by the service using its IAM identity
- Automatically rotated (RDS, Redshift: native rotation; custom: rotation Lambda)
- Audit-logged (every `GetSecretValue` call in CloudTrail)

```python
# NO: hardcoded credential
DB_PASSWORD = "my-secret-password"

# YES: IAM-authenticated runtime retrieval
import boto3
secrets = boto3.client('secretsmanager')
response = secrets.get_secret_value(SecretId='prod/payments/db-password')
DB_PASSWORD = json.loads(response['SecretString'])['password']
```

**Dynamic secrets** (Vault): instead of a rotating static password, the database issues a short-lived credential to each service instance. The credential expires after 1 hour; there is no long-lived password to steal.

---

## Continuous Verification

Zero Trust is not a point-in-time verification — it's continuous:

| Trigger | Action |
|---|---|
| User's device falls out of compliance | Revoke access token; require re-authentication with updated device |
| Unusual API call pattern (GuardDuty) | Automatically quarantine the IAM role (deny-all SCP) pending investigation |
| Certificate expiry approaching | Auto-rotate via cert-manager / ACM |
| Secrets approaching rotation window | Secrets Manager auto-rotates before expiry |
| CloudTrail: root account login | Immediate P0 alert; session revocation |
| GuardDuty: credential exfiltration | Automated: attach deny-all policy to the IAM identity |

**Automated threat response** (EventBridge + Lambda):
```
GuardDuty finding: "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration"
  → EventBridge rule → Lambda
    → Attaches inline deny-all policy to the compromised IAM role
    → Sends notification to security team
    → Creates CloudTrail alarm to track all subsequent calls from that role
```

---

## Trade-offs vs Traditional Perimeter Security

| Dimension | Zero Trust | Perimeter (Castle-and-Moat) |
|---|---|---|
| **Failure mode** | Compromised identity → limited blast radius (least privilege) | Compromised perimeter → full network access |
| **Insider threat** | Mitigated — lateral movement blocked by micro-segmentation | Not mitigated — trusted insiders have broad access |
| **User experience** | Slightly more friction (MFA, device checks) | Easier (inside network = trusted) |
| **Cloud compatibility** | Excellent — designed for cloud | Poor — no perimeter in cloud |
| **Implementation cost** | High — multiple layers, ongoing maintenance | Low — firewall rules |
| **Compliance** | Satisfies NIST 800-207, CISA ZTA | Does not satisfy modern compliance frameworks |
| **Breach cost** | Lower — breaches are contained | Higher — breach = full lateral movement |

---

## Best Practices

1. **Start with identity** — strong IAM + MFA is the most impactful first step; don't start with network changes
2. **Eliminate long-lived credentials first** — rotate all IAM access keys to roles; this alone eliminates a major attack class
3. **Implement least privilege systematically** — use IAM Access Analyser to right-size every role
4. **Deploy service mesh for east-west** — Istio or Linkerd; get mTLS for free with minimal app changes
5. **Enable GuardDuty in every account** — the anomaly detection signal is foundational to continuous verification
6. **Automate breach response** — don't rely on humans to quarantine a compromised role; EventBridge + Lambda does it in seconds
7. **Data classification before data access control** — you can't protect what you haven't labelled
8. **Replace VPN with AWS Verified Access** for human-to-app access — eliminate lateral movement risk
9. **Audit everything** — CloudTrail, VPC Flow Logs, ALB access logs, S3 data event logs. If you can't audit it, you can't detect breaches.
10. **Zero Trust is a journey, not a destination** — prioritise by risk: fix long-lived credentials, then least privilege, then micro-segmentation, then continuous verification

---

## FAANG Interview Points

**"How do you secure service-to-service communication in a microservices architecture?"**: IRSA/Task Roles for identity. Service mesh (Istio) for mTLS — workload certificates issued by SPIRE. AuthorizationPolicy at the sidecar level: only authorised service identities can call specific endpoints. No network-level trust — even same-VPC calls are verified. All calls logged via Istio telemetry.

**"How do you handle a compromised IAM credential?"**: GuardDuty detects unusual API call pattern → EventBridge rule fires → Lambda attaches inline `Deny *` policy to the IAM role → sends PagerDuty alert. All actions in <30 seconds. IAM role is effectively disabled without deleting it (preserves evidence). Security team investigates CloudTrail for blast radius before re-enabling.

**"Design security for a multi-account AWS organisation"**: SCPs (block root usage, restrict regions, prevent disabling security services) at OU level. GuardDuty, Security Hub, Config aggregated to security account. IAM Identity Center for SSO. All accounts ship CloudTrail to immutable S3 in log archive account. AWS Verified Access for human-to-app. IRSA + least-privilege task roles for service-to-service. No VPN; no bastion hosts; no long-lived keys.
