# PKI, TLS, X.509 Certificates, and mTLS

> **Principal Engineer Reference** — covers the full public-key infrastructure: certificate anatomy, PKI hierarchy, TLS 1.3 handshake step-by-step, forward secrecy, and mutual TLS for service-to-service authentication.

---

## Part A: X.509 Certificates

### Certificate Anatomy

An X.509 v3 certificate is a signed data structure binding a public key to an identity.

```
Certificate
├── Version: v3
├── Serial Number: unique within CA (e.g., 0x1A2B3C4D...)
├── Signature Algorithm: sha256WithRSAEncryption | ecdsa-with-SHA256
├── Issuer DN: CN=Let's Encrypt R11, O=Let's Encrypt, C=US
├── Validity
│   ├── Not Before: 2024-01-01 00:00:00 UTC
│   └── Not After:  2024-04-01 00:00:00 UTC   (90 days — Let's Encrypt policy)
├── Subject DN: CN=www.example.com
├── Subject Public Key Info
│   ├── Algorithm: EC (P-256)
│   └── Public Key: 04 8b 3a ... (uncompressed point)
└── Extensions (v3)
    ├── Subject Alternative Names (SANs): DNS:example.com, DNS:www.example.com
    ├── Key Usage: digitalSignature, keyEncipherment
    ├── Extended Key Usage: serverAuth, clientAuth (for mTLS)
    ├── Basic Constraints: CA:FALSE
    ├── Authority Key Identifier: links to issuing CA's public key
    ├── Subject Key Identifier: hash of this cert's public key
    ├── CRL Distribution Points: http://crl.example.com/r11.crl
    └── Authority Information Access: OCSP:http://ocsp.int-x3.letsencrypt.org
```

**Critical fields:**
- **SANs (Subject Alternative Names):** CN is deprecated for host verification; browsers use SANs. Wildcard: `*.example.com` covers one subdomain level only.
- **Key Usage + Extended Key Usage:** Controls what the key can be used for; servers need `serverAuth`; clients for mTLS need `clientAuth`.
- **Basic Constraints `CA:TRUE`:** If set, cert can sign other certs. Leaf certs MUST have `CA:FALSE`.

---

### PKI Hierarchy

```
Root CA (self-signed, offline)
│  ← stored in OS/browser trust stores
│  ← never used to sign leaf certs directly
│
├── Intermediate CA 1 ("Let's Encrypt R11")
│   │  ← cross-signed by Root CA
│   │  ← private key is online but HSM-protected
│   │
│   ├── Leaf cert: www.example.com (90-day)
│   ├── Leaf cert: api.example.com
│   └── ...thousands of leaf certs
│
└── Intermediate CA 2 (Backup / different region)
```

**Why intermediates exist:**
1. **Insulate root key:** Root CA key stored offline in air-gapped HSM. If intermediate is compromised, revoke the intermediate cert without touching the root.
2. **Operational independence:** Intermediate can be delegated to an org unit (e.g., `api.internal` uses internal CA).
3. **Revocation scope:** Revoking an intermediate invalidates all its leaf certs but not certs from other intermediates.

**Certificate chain validation:**
```
Browser receives: [Leaf cert] + [Intermediate cert]
1. Verify Leaf.signature using Intermediate.publicKey → valid?
2. Verify Intermediate.signature using Root.publicKey (from trust store) → valid?
3. Check Leaf.validity: now between NotBefore and NotAfter?
4. Check Leaf.SANs: hostname in SANs?
5. Check Leaf.revocation: not in CRL or OCSP response says "good"?
```

---

### Certificate Signing Request (CSR)

How to obtain a certificate:

```bash
# 1. Generate private key
openssl ecparam -name prime256v1 -genkey -noout -out server.key

# 2. Create CSR
openssl req -new -key server.key -out server.csr \
  -subj "/CN=api.example.com/O=ACME Corp/C=US"
# Add SANs via config or extension file

# 3. Submit to CA (manual or ACME protocol)
# CA verifies domain ownership (DV) or org identity (OV/EV)

# 4. CA issues signed certificate
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365 -sha256
```

---

### Certificate Revocation

| Method | Mechanism | Pros | Cons |
|---|---|---|---|
| **CRL** (Certificate Revocation List) | CA publishes list of revoked serial numbers; clients download periodically | Simple | Large (100K+ entries), stale (hours/days), must be downloaded |
| **OCSP** (Online Cert Status Protocol) | Client queries CA's OCSP responder per cert | Realtime | Privacy leak (CA knows which sites you visit); single point of failure; latency |
| **OCSP Stapling** | Server fetches OCSP response, caches it, includes it in TLS handshake | No client → CA request; cached | Server must implement stapling; response expires (24h typical) |
| **OCSP Must-Staple** | X.509 extension: browser rejects cert if no OCSP staple in handshake | Hard enforcement | Server misconfiguration = outage |
| **Short-lived certs** | No revocation needed if TTL < 24h; used by SPIFFE/SPIRE for workload certs | Eliminates revocation complexity | Requires automated issuance pipeline |

**The revocation problem (why it's hard):**
- CRLs were designed for small PKIs; modern CAs issue millions of certs → CRLs are GBs
- OCSP requires real-time availability of CA infrastructure
- Most browsers "fail open" on OCSP errors → revoked certs are still accepted under network failure
- **Google's solution:** Certificate Transparency (CT logs) + CRLSets (Chrome pre-downloads compact revocation list)

---

## Part B: TLS 1.3

### TLS 1.3 vs TLS 1.2 Comparison

| Property | TLS 1.2 | TLS 1.3 |
|---|---|---|
| Round trips (full handshake) | 2-RTT | **1-RTT** |
| Session resumption | 1-RTT (Session ID / Ticket) | **0-RTT** (with security caveats) |
| Key exchange | RSA (no FS) or DHE/ECDHE | **ECDHE only** (mandatory FS) |
| Cipher suites | 37 (many weak) | **5 modern suites** |
| Weak algorithms removed | No | RC4, 3DES, MD5, SHA-1, RSA key exchange |
| Handshake encryption | Extensions in clear | **Encrypted after ServerHello** |

**TLS 1.3 cipher suites (only 5):**
- `TLS_AES_256_GCM_SHA384`
- `TLS_AES_128_GCM_SHA256`
- `TLS_CHACHA20_POLY1305_SHA256`
- `TLS_AES_128_CCM_SHA256`
- `TLS_AES_128_CCM_8_SHA256`

---

### TLS 1.3 Full Handshake (1-RTT)

```
Client                                         Server
  │                                              │
  │── ClientHello ────────────────────────────► │
  │   • client_random                           │
  │   • supported_versions: [TLS 1.3]           │
  │   • key_share: {X25519: client_public_key}  │
  │   • supported_groups: [X25519, P-256]       │
  │   • signature_algorithms: [ed25519, RS256]  │
  │   • cipher_suites: [AES-256-GCM, ChaCha20] │
  │                                              │
  │◄─ ServerHello ──────────────────────────── │
  │   • server_random                           │
  │   • key_share: {X25519: server_public_key}  │
  │   • selected_cipher: AES-256-GCM-SHA384     │
  │                                              │
  │  [Both compute shared_secret via ECDHE:     │
  │   shared = X25519(client_priv, server_pub)  │
  │   Keys derived via HKDF from shared_secret] │
  │                                              │
  │◄─ {EncryptedExtensions} ────────────────── │  (encrypted from here)
  │◄─ {Certificate} ────────────────────────── │  server's X.509 cert
  │◄─ {CertificateVerify} ─────────────────── │  Sign(server_priv, transcript_hash)
  │◄─ {Finished} ───────────────────────────── │  HMAC of handshake transcript
  │                                              │
  │── {Finished} ──────────────────────────── ► │  client confirms
  │                                              │
  │◄═══════ Application Data ══════════════════ │  (1-RTT complete)
```

**HKDF key derivation (TLS 1.3 key schedule):**
```
ECDHE shared_secret
    │
    ▼
HKDF-Extract → Early Secret (0-RTT keys)
    │
    ▼
HKDF-Extract → Handshake Secret → handshake_traffic_secret
    │                              → client_handshake_key, server_handshake_key
    ▼
HKDF-Extract → Master Secret → application_traffic_secret_0
                                → client_application_key, server_application_key
```

---

### Forward Secrecy

**Definition:** Compromise of long-term private key does not compromise past session keys.

**Why TLS 1.3 provides it:**
- Key exchange uses **ephemeral ECDHE**: fresh key pair generated per handshake
- Session key derived from ephemeral secret → server's long-term private key is only used for signing (CertificateVerify), not key exchange
- After handshake, ephemeral private key is deleted
- **Attack defeated:** Mass-recorded TLS traffic + later private key theft = still encrypted

**TLS 1.2 without forward secrecy (RSA key exchange):**
```
Client → Server: Encrypt(server_pub_key, premaster_secret)
Server decrypts with private key → session key derived
If attacker records traffic AND later gets private key → can decrypt all past sessions
```

**This is why TLS 1.3 removed RSA key exchange entirely.**

---

### 0-RTT Resumption (and its caveat)

```
Session 1 complete → server sends NewSessionTicket (PSK = Pre-Shared Key)
Session 2:
Client → Server: {0-RTT Application Data} [PSK binder]
              + ClientHello
Server: decrypts with PSK, processes application data immediately
```

**Security caveat — replay attacks:**
- 0-RTT data is sent before server confirms the client is live
- Attacker can replay the 0-RTT flight → server processes same request twice
- **Mitigation:** Do not send non-idempotent requests in 0-RTT; server should use single-use tickets or replay cache
- HTTP GET safe; HTTP POST (payments, etc.) — **never in 0-RTT**

---

## Part C: Mutual TLS (mTLS)

### mTLS vs Standard TLS

```
Standard TLS:          mTLS:
Server proves identity  Both sides prove identity
to client              → Server's cert (normal TLS)
                       → Client's cert (additional step)
```

**mTLS handshake additions:**
```
After {Certificate} from server:
◄─ {CertificateRequest} ──── server requests client cert
── {Certificate} ──────────► client sends its X.509 cert
── {CertificateVerify} ────► client signs transcript with private key
```

**Use cases:**
- **Internal service-to-service:** proves identity without API keys
- **SPIFFE/SPIRE:** workload cert in SAN is the identity (`spiffe://cluster.local/ns/default/sa/payments`)
- **Istio STRICT mode:** enforces mTLS on all service communication
- **Client certificate authentication:** enterprise VPN, banking apps

---

### Certificate-Based Service Identity (SPIFFE SVID)

```
Standard cert SAN:  DNS:api.internal
SPIFFE SVID SAN:    URI:spiffe://cluster.local/ns/payments/sa/payments-svc

Trust domain:  cluster.local
Path:          /ns/payments/sa/payments-svc (Kubernetes namespace + service account)
```

**SPIRE issues SVIDs with:**
- 24-hour TTL (short-lived → minimal revocation need)
- Automatic rotation 5 minutes before expiry
- SVID rotation via SPIRE workload API (X.509-SVID or JWT-SVID)

---

### Certificate Pinning

**What it is:** App hardcodes specific public key or certificate fingerprint; refuses connection if server presents anything else.

```java
// Android (OkHttp) certificate pinning
OkHttpClient client = new OkHttpClient.Builder()
    .certificatePinner(new CertificatePinner.Builder()
        .add("api.example.com", "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        .build())
    .build();
```

**Trade-offs:**

| Pros | Cons |
|---|---|
| Defeats MITM even if CA is compromised | **Certificate rotation breaks app** until new version deployed |
| Defense against rogue CAs | App update required for each cert rotation |
| Required for high-value targets (banking apps) | Certificate transparency (CT) provides similar protection at lower cost |

**Recommendation:** Use **public key pinning** (pin the SPKI hash, not cert fingerprint) → survives certificate renewal with same key. Or use HPKP backup pins.

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| TLS version | TLS 1.2 | TLS 1.3 | TLS 1.3 minimum; TLS 1.2 for legacy compat |
| Certificate validity | 90 days (Let's Encrypt) | 1 year | Short-lived + automation (ACME) |
| Key type for certs | RSA-2048 | ECDSA P-256 | ECDSA P-256: 3× smaller, same security, faster |
| Revocation | CRL | OCSP Stapling | OCSP Stapling + Must-Staple; or short-lived certs |
| mTLS implementation | Manual cert management | SPIFFE/SPIRE | SPIFFE/SPIRE for microservices; auto-rotation |
| 0-RTT | Enabled for all | Disabled or idempotent only | Only for safe methods (GET/HEAD) |

---

## FAANG Interview Callout

> **TLS deep-dive questions at principal level:**

**Q: "Walk me through a TLS 1.3 handshake and where forward secrecy comes from."**
→ ClientHello includes ephemeral ECDHE key_share. ServerHello replies with its ephemeral key_share. Both compute the same shared secret via X25519. HKDF derives handshake and application traffic keys. Server's long-term private key only signs the transcript (CertificateVerify) — never used for key exchange. Ephemeral keys discarded post-handshake → forward secrecy.

**Q: "How does Istio enforce mTLS between services without developers doing anything?"**
→ SPIRE (or Istio's built-in CA, Citadel) issues SVID certs to each sidecar (Envoy). Envoy intercepts all pod traffic, presents its SVID for outbound connections, and requires peer SVID for inbound (STRICT mode PeerAuthentication). The workload never sees the TLS; Envoy handles it transparently via xDS/SDS APIs.

**Q: "Why are short-lived certificates better than revocation for internal microservices?"**
→ Revocation requires availability of OCSP/CRL infrastructure; clients often fail open. Short TTL (1h–24h for SPIFFE SVIDs) means a compromised cert is only valid briefly. Automated rotation (SPIRE workload API) means no manual intervention. At microservice scale (thousands of services × many pods), automated issuance is the only feasible approach.

**Q: "A CA in your browser's trust store was compromised. How does Certificate Transparency protect you?"**
→ Every CA must submit issued certs to CT logs (Merkle trees). Browsers check for SCTs (Signed Certificate Timestamps) in the cert. Google Chrome enforces CT for all new certs. A rogue cert issued by compromised CA would appear in CT logs → detected by domain owner's certificate monitoring (crt.sh, Google CT API). Browser adds CA to revocation set.
