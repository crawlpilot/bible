# Security Knowledge Base

> **Principal Engineer Reference** — covers the full security stack from cryptographic primitives through transport security, authentication protocols, authorization models, and modern zero-trust patterns. Calibrated for FAANG principal engineer interviews.

---

## Folder Map

```
Security/
├── README.md                                   ← You are here
├── cryptography/
│   ├── 01-symmetric-asymmetric-encryption.md  (AES, RSA, ECC, Ed25519, hashing, MACs)
│   └── 02-pki-tls-certificates.md             (X.509, PKI, TLS 1.3 handshake, mTLS)
├── authentication/
│   ├── 01-passwords-mfa-passkeys.md           (bcrypt, Argon2id, TOTP, FIDO2, WebAuthn)
│   ├── 02-ssh-keys-and-protocol.md            (SSH protocol, Ed25519, agent, CA certs)
│   ├── 03-oauth2-oidc.md                      (all grant types, PKCE, OIDC, token exchange)
│   ├── 04-jwt-tokens.md                       (structure, algorithms, vulnerabilities, rotation)
│   └── 05-enterprise-auth-saml-ldap-kerberos.md (SAML 2.0, LDAP, AD groups, Kerberos)
├── authorization/
│   ├── 01-rbac-abac-rebac-opa.md              (RBAC, ABAC, Zanzibar/ReBAC, OPA/Rego)
│   └── 02-api-security-secrets.md             (API auth, AWS Sig V4, Vault, envelope encryption)
└── modern-patterns/
    ├── 01-zero-trust-spiffe-mtls.md           (BeyondCorp, SPIFFE/SPIRE, workload identity)
    └── 02-threat-modeling-supply-chain.md     (STRIDE methodology, OWASP deep-dive, SLSA)
```

---

## How to Use This Folder

| You need to understand... | Go to |
|---|---|
| AES, RSA, ECC, hashing, MACs | `cryptography/01-symmetric-asymmetric-encryption.md` |
| TLS handshake, PKI, mTLS, certificates | `cryptography/02-pki-tls-certificates.md` |
| Password hashing, MFA, FIDO2, passkeys | `authentication/01-passwords-mfa-passkeys.md` |
| SSH keys, tunneling, SSH CA certificates | `authentication/02-ssh-keys-and-protocol.md` |
| OAuth 2.0, OIDC, PKCE, token exchange | `authentication/03-oauth2-oidc.md` |
| JWT structure, algorithms, vulnerabilities | `authentication/04-jwt-tokens.md` |
| SAML, LDAP/AD groups, Kerberos attacks | `authentication/05-enterprise-auth-saml-ldap-kerberos.md` |
| RBAC, ABAC, ReBAC, OPA/Rego | `authorization/01-rbac-abac-rebac-opa.md` |
| API keys, secrets management, Vault, KMS | `authorization/02-api-security-secrets.md` |
| Zero trust, SPIFFE, mTLS at platform level | `modern-patterns/01-zero-trust-spiffe-mtls.md` |
| Threat modeling, OWASP Top 10, SLSA | `modern-patterns/02-threat-modeling-supply-chain.md` |

---

## Cross-References to Existing Repo Files

> These files cover adjacent topics — link out rather than duplicate.

| Topic | Existing File | Coverage |
|---|---|---|
| OWASP Top 10 checklist table | [`Development/best-practices/07-engineering-standards.md`](../Development/best-practices/07-engineering-standards.md) | One-row enforcement patterns (shallow) |
| STRIDE model summary | [`Development/best-practices/07-engineering-standards.md`](../Development/best-practices/07-engineering-standards.md) | One-row-per-threat table |
| AWS IAM roles, SCPs, Access Analyzer | [`CloudArchitecture/aws/iam.md`](../CloudArchitecture/aws/iam.md) | AWS-specific identity & access management |
| Envoy mTLS sidecar | [`Architecture/microservices/sidecar-pattern-envoy-otel-consul.md`](../Architecture/microservices/sidecar-pattern-envoy-otel-consul.md) | mTLS in service mesh sidecar pattern |
| JWT multi-tenant injection | [`AI/ai-architecture/rag-system-hld.md`](../AI/ai-architecture/rag-system-hld.md) | Tenant isolation via JWT claim |
| Kubernetes RBAC model | [`technologies/kubernetes/01-architecture.md`](../technologies/kubernetes/01-architecture.md) | K8s ClusterRole, RoleBinding, ServiceAccount |
| AWS VPC Security Groups, NACLs | [`CloudArchitecture/aws/vpc-networking.md`](../CloudArchitecture/aws/vpc-networking.md) | Network-level access control |
| Istio zero-trust policy | [`CloudArchitecture/patterns/service-mesh.md`](../CloudArchitecture/patterns/service-mesh.md) | STRICT mTLS + L7 AuthorizationPolicy |

---

## AAA Framework

| Concept | Question Answered | Examples |
|---|---|---|
| **Authentication** (AuthN) | *Who are you?* | Password, SSH key, X.509 certificate, FIDO2, SAML assertion |
| **Authorization** (AuthZ) | *What can you do?* | RBAC roles, ABAC policy, OPA decision, Zanzibar tuple lookup |
| **Accounting** (Audit) | *What did you do?* | Audit log, SIEM event, AWS CloudTrail, Vault audit log |

---

## Security Decision Guide

| Problem | Mechanism | Standard/Protocol |
|---|---|---|
| Protect data **at rest** | Symmetric encryption + KMS | AES-256-GCM + envelope encryption |
| Protect data **in transit** | TLS 1.3 | X.509 certificates, ECDHE forward secrecy |
| User authenticates with **password** | Password hashing | Argon2id (OWASP 2024 recommendation) |
| User **login** to web/mobile app | OAuth 2.0 Authorization Code + PKCE | RFC 6749 + RFC 7636 |
| **Machine-to-machine** API auth | Client credentials or mTLS | RFC 6749 Client Credentials or SPIFFE SVID |
| **Enterprise SSO** (SAML federation) | SAML 2.0 or OIDC | SAML 2.0 (legacy B2B), OIDC (modern) |
| **Remote server** access | SSH with Ed25519 | OpenSSH, RFC 4251 |
| **Fine-grained resource** authorization | ReBAC or ABAC | Google Zanzibar, OPA/Rego |
| **Workload-to-workload** identity | SPIFFE/SPIRE | SPIFFE SVID (X.509 SAN) |
| **Secret storage** and rotation | Secrets manager + envelope encryption | HashiCorp Vault, AWS Secrets Manager |
| **Phishing-resistant** 2FA | FIDO2/WebAuthn/Passkeys | CTAP2, WebAuthn Level 2 |
| **API key** rotation without downtime | Overlapping key validity window + `kid` | JWK endpoint, Vault key versioning |

---

## Cryptographic Primitives Quick Reference

| Use Case | Algorithm | Key Size | Notes |
|---|---|---|---|
| Data encryption (symmetric) | AES-256-GCM | 256-bit | AEAD: encryption + integrity in one pass |
| Stream cipher | ChaCha20-Poly1305 | 256-bit | Preferred on hardware without AES-NI |
| Key exchange | X25519 (ECDH) | 256-bit | Forward secrecy via ephemeral keys |
| Digital signatures | Ed25519 | 256-bit | Deterministic, immune to bad-RNG attacks |
| General hashing | SHA-256 / SHA-3-256 | 256-bit output | SHA-3 immune to length-extension attacks |
| Password hashing | Argon2id | — | 64MB memory, 3 iterations minimum (OWASP) |
| Message authentication | HMAC-SHA256 | ≥256-bit secret | Prevents length-extension attacks on bare SHA |
| Key derivation (session keys) | HKDF | — | Extract + Expand from shared secret |
| Key derivation (from password) | PBKDF2 | salt + iterations | 600,000 iterations minimum (NIST 2023) |

---

## Threat Actor Taxonomy

| Actor | Motivation | Typical Attack |
|---|---|---|
| **External attacker** | Financial gain, espionage | Credential stuffing, SQL injection, SSRF |
| **Malicious insider** | Revenge, financial gain | Privilege abuse, data exfiltration |
| **Compromised service** | Lateral movement | Stolen JWT/service account, SSRF → IMDS |
| **Supply chain attacker** | Persistent backdoor | Compromised npm/Maven package, typosquatting |
| **Nation-state actor** | Espionage, disruption | APT, zero-day exploitation, traffic interception |

---

## Security Glossary (30+ Terms)

| Term | Definition |
|---|---|
| **Principal** | An entity that can be authenticated (user, service, device, workload) |
| **Claim** | A key-value assertion about a principal (e.g., in a JWT payload) |
| **Nonce** | Number used once — prevents replay attacks |
| **Salt** | Random per-credential value mixed before hashing — defeats rainbow tables |
| **IV / Nonce** | Initial state for block cipher — never reuse with the same key |
| **PKCE** | Proof Key for Code Exchange — prevents OAuth auth-code interception in public clients |
| **SVID** | SPIFFE Verifiable Identity Document — workload cert with SPIFFE ID in X.509 SAN |
| **SPIFFE** | Secure Production Identity Framework For Everyone |
| **JWK** | JSON Web Key — standardized public key format for JWT signature verification |
| **JWE** | JSON Web Encryption — encrypted JWT (vs JWS = signed JWT) |
| **PAC** | Privilege Attribute Certificate — Kerberos ticket extension with group memberships |
| **TGT** | Ticket Granting Ticket — Kerberos proof of authentication to the KDC |
| **PKIX / X.509** | Public Key Infrastructure standard for TLS certificates |
| **OCSP** | Online Certificate Status Protocol — real-time cert revocation check |
| **CRL** | Certificate Revocation List — batch revocation list |
| **HSM** | Hardware Security Module — tamper-resistant hardware for key operations |
| **KEK** | Key Encryption Key — wraps DEKs in envelope encryption; never leaves KMS |
| **DEK** | Data Encryption Key — encrypts actual data; wrapped by KEK |
| **PEP** | Policy Enforcement Point — intercepts requests and enforces PDP decisions |
| **PDP** | Policy Decision Point — evaluates policy rules, returns allow/deny |
| **PAP** | Policy Administration Point — where policies are authored and stored |
| **SoD** | Separation of Duties — user cannot hold conflicting roles simultaneously |
| **AEAD** | Authenticated Encryption with Associated Data — encryption + integrity (AES-GCM) |
| **CSR** | Certificate Signing Request — sent to CA to obtain a signed certificate |
| **mTLS** | Mutual TLS — both client and server present certificates |
| **ZTNA** | Zero Trust Network Access — identity-aware proxy; replaces VPN |
| **SDP** | Software Defined Perimeter — hides resources until identity is verified |
| **SLSA** | Supply-chain Levels for Software Artifacts — provenance attestation framework |
| **SBOM** | Software Bill of Materials — inventory of all software components and versions |
| **Attestation** | Cryptographic proof of identity or integrity (FIDO2, SPIFFE, TPM) |
| **Forward Secrecy** | Past sessions cannot be decrypted even if long-term private key is later compromised |

---

## FAANG Interview Callout

> **Principal-level questions asked at Google, Meta, Amazon, Stripe:**

**Q1: "Design authentication for a multi-tenant SaaS serving 10M users with enterprise SSO requirements."**
→ OAuth 2.0 AS (Keycloak/Auth0) + OIDC for consumer; SAML 2.0 federation bridge for enterprise IdPs; JWT with `tenant_id` claim; per-tenant RBAC; short-lived access tokens (15 min) + refresh rotation.

**Q2: "A service's private TLS key was exfiltrated. Walk me through incident response."**
→ Forward secrecy means past sessions are safe (ECDHE). Immediate: revoke cert (OCSP must-staple), issue new cert, rotate JWT signing keys (publish new `kid` to JWK endpoint, drain old). Investigation: check logs for anomalous signing, scan for lateral movement.

**Q3: "How do you prevent a compromised microservice from accessing other services?"**
→ mTLS with SPIFFE SVID (24h TTL auto-rotation); zero-trust `AuthorizationPolicy` deny-by-default; K8s NetworkPolicy for L3/L4; Istio `PeerAuthentication` STRICT mode; audit decision logs.

**Q4: "Design a secrets management system for a 500-engineer org."**
→ HashiCorp Vault with K8s auth + AppRole; dynamic DB credentials (1h TTL); envelope encryption for app-layer data; CI/CD secret injection via Vault Agent; audit log → SIEM. Never store secrets in Git.

**Q5: "OAuth 2.0 vs API keys — when do you use each?"**
→ API keys: simple M2M with rate limiting; immediate revocation; opaque. OAuth: user-delegated access, scoped permissions, short-lived tokens, federated identity. At scale: OAuth for user-facing; mTLS + SPIFFE for internal M2M.
