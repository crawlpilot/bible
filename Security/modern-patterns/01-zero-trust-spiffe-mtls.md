# Zero Trust, SPIFFE/SPIRE, and mTLS at Platform Scale

> **Principal Engineer Reference** — covers the zero trust security model, BeyondCorp architecture, SPIFFE workload identity, SPIRE runtime, mTLS enforcement in Kubernetes, and ZTNA for remote access. Includes the shift from perimeter security to identity-centric security.

---

## Part A: Zero Trust Principles

### The Perimeter Model (What We're Replacing)

**Traditional "castle and moat" model:**
- Corporate network = trusted zone; internet = untrusted zone
- VPN provides access to the trusted zone
- Once inside the perimeter: implicit trust for all services

**Why the perimeter model fails:**
- **Lateral movement:** once attacker compromises one machine inside the perimeter, they can reach everything
- **Insider threats:** malicious employees or compromised credentials have wide access
- **Cloud and remote work:** "inside the perimeter" is meaningless when apps run in AWS and employees work from home
- **Real incidents:** Target (2013), SolarWinds (2020) — attackers moved laterally for weeks/months undetected

---

### Zero Trust Principles (NIST SP 800-207)

| Principle | Description |
|---|---|
| **Never trust, always verify** | Every request must be authenticated regardless of network location |
| **Assume breach** | Design assuming attackers are already inside; minimize blast radius |
| **Least privilege** | Grant minimum access needed for specific task; time-bound when possible |
| **Microsegmentation** | Divide network into small segments; services cannot reach each other by default |
| **Verify explicitly** | Use all available signals: user identity, device health, location, behavior |
| **Continuous validation** | Trust is not granted once; re-evaluate on every request |

---

### BeyondCorp (Google's Zero Trust Implementation)

**Published:** "BeyondCorp: A New Approach to Enterprise Security" (Google Technical Report 2014)

**Key insight:** Remove the concept of a "privileged network." Grant access based on:
1. **User identity** (who you are — Google Account)
2. **Device identity** (what device you're on — corporate-managed, certificate-enrolled)
3. **Device health** (is the device compliant? patch level, MDM enrollment)
4. **Request context** (what resource, what action, what time, what location)

```
User request to internal app
       │
       ▼
Access Proxy (Google Front End / GFE)
       │
       ├── AuthN: Google SSO (Kerberos + OIDC)
       ├── Device cert check: corporate CA issued?
       ├── Device inventory: registered in device DB?
       ├── Device trust level: fully compliant / managed / unknown
       ├── User group membership: allowed access level?
       └── Policy evaluation (trust tier × resource sensitivity)
              │
              ▼
        Allow / Deny / Step-up auth
```

**Trust tiers:**
- **Tier 1:** Corp-managed device + corp credentials → full internal access
- **Tier 2:** Unmanaged device + corp credentials → limited access (no PII, no prod)
- **Tier 0:** No corp credentials → unauthenticated → redirect to login

---

## Part B: ZTNA (Zero Trust Network Access)

### ZTNA vs VPN

| Property | Traditional VPN | ZTNA |
|---|---|---|
| Network access | Broad (subnet-level) | Per-application (micro-tunnel) |
| Trust after auth | Full network access | Application-specific only |
| Lateral movement risk | High (one cred = all access) | Low (each app requires separate auth) |
| User experience | Slow, heavy client | Invisible, fast (direct app access) |
| Visibility | Encrypted tunnel (hard to inspect) | Identity-aware, logged per request |
| Implementation | IPsec / OpenVPN | Cloudflare Access, Zscaler, Palo Alto Prisma |

**ZTNA workflow:**
```
1. User installs ZTNA agent (lightweight, not network VPN)
2. User authenticates: OIDC → identity platform
3. Device posture check: is device managed? patch level OK?
4. User requests app.internal.example.com
5. ZTNA agent → ZTNA controller: "I'm alice, on device D, requesting app.internal"
6. Controller: evaluate policy (identity + device + resource)
7. If allowed: controller creates ephemeral encrypted tunnel directly to app
8. Connection is per-application, not per-network → no lateral movement
```

---

## Part C: SPIFFE — Workload Identity

### Problem: How Do Services Prove Identity?

In traditional architectures, services shared secrets (DB passwords, API keys) or relied on network location ("if traffic comes from 10.0.1.x, trust it"). Neither works at scale:
- Shared secrets spread → breach of one service compromises others
- IP-based trust → container IPs change; IP is not an identity

**SPIFFE (Secure Production Identity Framework For Everyone)** solves this by giving every workload a cryptographic identity.

---

### SPIFFE ID

```
spiffe://trust-domain/path

Examples:
spiffe://cluster.local/ns/payments/sa/payment-processor
spiffe://prod.acme.com/service/order-service
spiffe://us-east-1.aws.acme.com/ec2/i-1234567890abcdef
```

- **trust-domain:** analogous to a domain name; identifies the SPIFFE trust domain (organization/cluster)
- **path:** identifies the specific workload (Kubernetes: namespace + service account; EC2: instance ID)

---

### SVID (SPIFFE Verifiable Identity Document)

**X.509 SVID** (most common):
```
X.509 certificate with:
  Subject: CN=payment-processor
  SAN (Subject Alternative Name): URI: spiffe://cluster.local/ns/payments/sa/payment-processor
  Not After: [24 hours from issuance]    ← short-lived!
  Issuer: CN=SPIRE CA, O=cluster.local
```

**JWT SVID** (for HTTP APIs):
```json
{
  "sub": "spiffe://cluster.local/ns/payments/sa/payment-processor",
  "aud": ["spiffe://cluster.local/ns/orders/sa/order-service"],
  "exp": 1735690000,
  "iat": 1735686400
}
```

---

## Part D: SPIRE (SPIFFE Runtime Environment)

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  SPIRE Server (per trust domain, HA with Raft)               │
│                                                              │
│  - CA: signs SVIDs (integrated CA or delegates to Vault PKI) │
│  - Registration API: maps workload attributes → SPIFFE IDs   │
│  - Node attestation: verifies SPIRE Agents                   │
└──────────────────────────────────────────────────────────────┘
          │ mTLS + Node Attestation
          ▼
┌──────────────────────────────────────────────────────────────┐
│  SPIRE Agent (one per node/VM)                               │
│                                                              │
│  - Workload attestation: identify each pod/process           │
│  - Workload API: serve X.509 SVIDs via Unix socket           │
│  - Auto-rotate SVIDs 5 minutes before expiry                 │
└──────────────────────────────────────────────────────────────┘
          │ Unix socket (/run/spire/sockets/agent.sock)
          ▼
┌──────────────────────────────────────────────────────────────┐
│  Workload (your microservice)                                │
│                                                              │
│  - Requests SVID from Workload API                           │
│  - Uses SVID as TLS client/server certificate                │
│  - Auto-updates when SVID is rotated                         │
└──────────────────────────────────────────────────────────────┘
```

### Node Attestation

**How SPIRE Agent proves it's running on a legitimate node:**

| Plugin | Proof | Use case |
|---|---|---|
| `k8s_sat` (K8s Service Account Token) | K8s API verifies JWT | Kubernetes nodes |
| `aws_iid` (AWS Instance Identity Document) | AWS signed IMDS document | EC2 instances |
| `gcp_iit` (GCP Instance Identity Token) | GCP metadata service | GCP VMs |
| `tpm` (Trusted Platform Module) | Hardware-attested key | Physical servers |

### Workload Attestation (Kubernetes)

```yaml
# SPIRE Server: registration entry
spire-server entry create \
  -spiffeID spiffe://cluster.local/ns/payments/sa/payment-processor \
  -parentID spiffe://cluster.local/k8s-workload-registrar/node \
  -selector k8s:ns:payments \
  -selector k8s:sa:payment-processor
```

SPIRE Agent verifies: pod with UID X is in namespace `payments` running as ServiceAccount `payment-processor` → issues SVID for `spiffe://cluster.local/ns/payments/sa/payment-processor`.

---

## Part E: mTLS in Kubernetes with Istio

### Automatic mTLS (No Code Changes)

Istio handles certificate issuance, rotation, and mTLS negotiation in Envoy sidecars.

```yaml
# PeerAuthentication: enforce STRICT mTLS in namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: payments
spec:
  mtls:
    mode: STRICT  # Reject plaintext; require valid SVID cert
```

```yaml
# AuthorizationPolicy: deny-by-default, allow only specific sources
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: payment-processor-policy
  namespace: payments
spec:
  selector:
    matchLabels:
      app: payment-processor
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              # Only order-service can call payment-processor
              - "cluster.local/ns/orders/sa/order-service"
      to:
        - operation:
            methods: ["POST"]
            paths: ["/process"]
```

---

### SVID Rotation Flow in Istio

```
cert TTL = 24 hours (Istio default), rotation at 80% of TTL (~19h 12min)

1. Envoy sidecar requests SVID from istiod (acting as SPIRE server)
2. istiod issues X.509 cert with SPIFFE ID (spiffe://cluster.local/ns/...)
3. Envoy uses cert for mTLS on both inbound and outbound connections
4. At 80% TTL: Envoy automatically requests new cert (no service interruption)
5. Old cert accepted until expiry (for in-flight connections)
```

---

### Lateral Movement Prevention

**Zero trust segmentation for microservices:**

```
Default: DENY all service-to-service communication

Policy: Explicit allowlist
  - order-service → payment-processor: POST /process (allowed)
  - payment-processor → fraud-service: GET /check (allowed)
  - All other paths: DENY

At runtime:
  - payment-processor cannot call user-service (not in allowlist)
  - Even if payment-processor is compromised, it cannot pivot to user-service
```

**Kubernetes NetworkPolicy (L3/L4):**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payment-processor
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payment-processor
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: orders
          podSelector:
            matchLabels:
              app: order-service
      ports:
        - port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: fraud
          podSelector:
            matchLabels:
              app: fraud-service
      ports:
        - port: 8081
    - to:  # allow DNS
        - namespaceSelector: {}
      ports:
        - port: 53
```

---

## Zero Trust vs Perimeter: Architecture Comparison

```
Perimeter Model:
  Internet ──► [Firewall] ──► Internal Network
                                  ├── App A (trusted)
                                  ├── App B (trusted)
                                  ├── DB (trusted)
                                  └── Attacker (after one breach = trusted!)

Zero Trust Model:
  Internet ──► Identity-Aware Proxy ──► App A
                │                     App B
                │                     DB
                │
                └── Every request re-evaluated:
                    - User identity (verified)
                    - Device posture (checked)
                    - Context (IP, time, behavior)
                    - Service identity (SPIFFE SVID)
                    - Policy (OPA/Istio AuthorizationPolicy)
```

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Service identity | IP-based / API keys | SPIFFE SVID | SPIFFE for microservices (cryptographic, rotatable) |
| mTLS management | Manual certs | Service mesh (Istio/Linkerd) | Service mesh for K8s (auto-rotate, zero code change) |
| SVID TTL | 90 days | 24 hours | 24 hours (auto-rotation eliminates operational burden) |
| Remote access | VPN | ZTNA | ZTNA (per-app, least privilege, no lateral movement) |
| Network policy | Default allow | Default deny + allowlist | Default deny (zero trust principle) |

---

## FAANG Interview Callout

**Q: "Design workload identity for a 500-service Kubernetes platform."**
→ SPIFFE/SPIRE: deploy SPIRE Server (HA, 3 replicas with Raft) per cluster. SPIRE Agent as DaemonSet on every node. K8s Workload Registrar: auto-creates registration entries from K8s objects. Istio integrates SPIRE as the cert provider. Every pod gets an X.509 SVID (24h TTL, auto-rotated by Envoy). mTLS enforced via `PeerAuthentication: STRICT`. AuthorizationPolicy restricts which services can talk to which. Result: no service-account tokens or shared secrets needed for M2M auth.

**Q: "SolarWinds-style attack: attacker is inside your perimeter. How does zero trust limit damage?"**
→ Zero trust limits lateral movement: every service-to-service call requires valid SVID + passes AuthorizationPolicy. Compromised payment-processor cannot call user-service (not in allowlist). Egress NetworkPolicy prevents calling external C2 servers. Vault audit log shows unexpected secret reads. SIEM alert on SPIFFE identity calling unusual destinations. Blast radius = only services the compromised service was authorized to call, not the entire network.

**Q: "Compare VPN vs ZTNA for a 10,000-employee organization going remote-first."**
→ VPN: grants access to network subnet → compromised device accesses everything on that subnet. ZTNA: per-application micro-tunnel, policy re-evaluated per request (identity + device health + context). ZTNA benefits: lower blast radius (no lateral movement), better UX (no slowdown from routing all traffic through VPN concentrator), better visibility (every access logged with identity). Migration: inventory all apps → create ZTNA policies per app → pilot with IT/engineering → phase out VPN.
