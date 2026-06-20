# Threat Modeling, OWASP Top 10, and Supply Chain Security

> **Principal Engineer Reference** — covers hands-on threat modeling methodology (STRIDE with data flow diagrams), OWASP Top 10 2021 with vulnerable code and mitigations, and supply chain security (SLSA, Sigstore, SBOM). Designed to go far deeper than the summary table in `Development/best-practices/07-engineering-standards.md`.

---

## Part A: STRIDE Threat Modeling

### Why Threat Modeling?

Threat modeling answers: *"What can go wrong?"* — before building, not after a breach.

**Principal engineer responsibility:** Lead threat modeling for high-risk features, new systems, or significant architectural changes. Produce a threat model as part of design review / RFC.

---

### The 4-Step Process

```
1. Decompose the system → Data Flow Diagram (DFD)
2. Identify threats → STRIDE per element
3. Risk-rank threats → DREAD scoring
4. Mitigate threats → one per threat, tracked to completion
```

---

### Step 1: Data Flow Diagram (DFD)

**DFD elements:**

| Symbol | Element | What it represents | Example |
|---|---|---|---|
| Rectangle | **External Entity** | Actors outside your trust boundary | User, 3rd-party API, external IdP |
| Circle/Oval | **Process** | Code that transforms data | API service, Lambda function |
| Double line | **Data Store** | Persistent data | PostgreSQL, S3 bucket, Redis |
| Arrow | **Data Flow** | Data in motion | HTTP request, DB query result |
| Dashed rectangle | **Trust Boundary** | Where trust level changes | Internet ↔ DMZ, DMZ ↔ internal |

**DFD for a payment API (example):**

```
┌─────────────────────────────────────────────────────────────────────────┐
│  External (untrusted)                                                   │
│                                                                         │
│  [User Browser] ──HTTPS──► [TLS Terminator / API Gateway]              │
└─────────────────────────────────────────── │ ───────────────────────────┘
                                             │ (Trust Boundary: Internet → DMZ)
┌─────────────────────────────────────────── │ ───────────────────────────┐
│  DMZ                                       ▼                           │
│                                [Payment API Service]                   │
│                                    /        \                          │
│                          (read/write)      (read)                      │
│                         ▼                    ▼                         │
│              [PostgreSQL DB]           [Fraud Service]                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                             │
                             (Trust Boundary: DMZ → Internal)
┌─────────────────────────────────────────── │ ───────────────────────────┐
│  Internal                                  ▼                           │
│                              [Stripe API]  [Email Service]             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### Step 2: STRIDE Per Element

Apply each STRIDE category to each DFD element:

| STRIDE | Element | Threat | Mitigation |
|---|---|---|---|
| **S**poofing | External Entity, Process | Attacker impersonates legitimate user | Authentication (JWT, mTLS, FIDO2) |
| **T**ampering | Data Flow, Data Store | Attacker modifies data in transit or at rest | Integrity (TLS, HMAC, database audit log) |
| **R**epudiation | Process, Data Flow | User denies having performed an action | Audit log with tamper-proof signatures (immutable log) |
| **I**nformation Disclosure | Data Store, Data Flow, Process | Sensitive data exposed to unauthorized party | Encryption (TLS + at-rest), access control, PII masking |
| **D**enial of Service | Process, Data Flow | Attacker makes service unavailable | Rate limiting, WAF, circuit breakers, autoscaling |
| **E**levation of Privilege | Process | Attacker gains more permissions than authorized | Authorization checks, least privilege, input validation |

**Deep threat analysis (payment API example):**

| # | Element | Threat | STRIDE | Risk | Mitigation |
|---|---|---|---|---|---|
| 1 | User→API | Stolen JWT used to charge card | S (Spoofing) | High | Short TTL (15min) + token binding |
| 2 | API→DB | SQL injection → dump card numbers | T (Tamper) + I (Info) | Critical | Parameterized queries; DB accounts with minimal grants |
| 3 | API→Stripe | SSRF via crafted payment URL | T + I | High | Validate Stripe URL whitelist; no user-controlled URLs |
| 4 | DB | Admin exfiltrates card data | I (Info Disclosure) | High | Encryption at rest (AES-256); audit log; RBAC |
| 5 | API | Missing authorization: user A charges user B's card | E (Elevation) | Critical | Verify card.user_id == authenticated user_id |
| 6 | API | 10K requests/sec to payment endpoint | D (DoS) | High | Rate limit per user_id; circuit breaker to Stripe |

---

### Step 3: DREAD Risk Scoring

| Factor | Score 1 | Score 5 | Score 10 |
|---|---|---|---|
| **D**amage | Minimal data exposure | Moderate financial loss | Full system compromise |
| **R**eproducibility | Hard to reproduce | Reproducible with effort | Trivially reproducible |
| **E**xploitability | Expert attacker required | Skilled attacker | Script kiddie / automated |
| **A**ffected users | Single user | Some users | All users |
| **D**iscoverability | Hidden, attacker needs inside knowledge | Guessable via API exploration | Publicly known |

**DREAD Total = Average(D, R, E, A, D)**
- 1-3: Low — document, address in next sprint
- 4-6: Medium — address before release
- 7-10: Critical — fix before launch; escalate

---

### Threat Modeling Tools

| Tool | Type | Strengths |
|---|---|---|
| **Microsoft Threat Modeling Tool** | Desktop | STRIDE built-in; DFD stencils; official Microsoft |
| **OWASP Threat Dragon** | Web / Desktop | Open source; STRIDE + LINDDUN; GitHub integration |
| **IriusRisk** | Enterprise SaaS | Automated threat library; compliance mapping |
| **draw.io + manual STRIDE** | Lightweight | No specialized tool needed; works in code review |

---

## Part B: OWASP Top 10 — 2021 Deep Dive

> Beyond the summary table in `07-engineering-standards.md` — each item includes vulnerable code, exploit scenario, and specific mitigations with code.

### A01: Broken Access Control

**Vulnerable code (Java):**
```java
// VULNERABLE: missing authorization check
@GetMapping("/orders/{orderId}")
public Order getOrder(@PathVariable String orderId) {
    return orderRepository.findById(orderId)  // no check: does this user own it?
        .orElseThrow(NotFoundException::new);
}
```

**Exploit:** User A changes URL from `/orders/1001` to `/orders/1002` → retrieves User B's order.

**Mitigation:**
```java
@GetMapping("/orders/{orderId}")
public Order getOrder(@PathVariable String orderId,
                      @AuthenticationPrincipal UserDetails user) {
    Order order = orderRepository.findById(orderId)
        .orElseThrow(NotFoundException::new);

    // CRITICAL: verify ownership
    if (!order.getUserId().equals(user.getId())) {
        throw new ForbiddenException("Access denied");
    }
    return order;
}
```

**Detection:** Automated IDOR scanning; pen testing with two user accounts; audit log analysis for cross-user access patterns.

---

### A02: Cryptographic Failures

**Vulnerable code (Python):**
```python
# VULNERABLE: MD5 hash of credit card
import hashlib
card_hash = hashlib.md5(card_number.encode()).hexdigest()  # rainbow-table crackable

# VULNERABLE: ECB mode (deterministic)
from Crypto.Cipher import AES
cipher = AES.new(key, AES.MODE_ECB)
encrypted = cipher.encrypt(pad(data))  # same plaintext = same ciphertext
```

**Mitigation:**
```python
# Encrypt credit card data (only PAN, not required for most operations — use tokenization)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

aes_gcm = AESGCM(aes_256_key_from_kms)
nonce = os.urandom(12)
ciphertext = aes_gcm.encrypt(nonce, card_number.encode(), None)

# Or better: PCI DSS-compliant tokenization
token = payment_vault.tokenize(card_number)  # store token; vault holds real PAN
```

---

### A03: Injection

**SQL Injection:**
```python
# VULNERABLE
query = f"SELECT * FROM users WHERE username = '{username}'"  # username = ' OR '1'='1
cursor.execute(query)

# MITIGATION: parameterized queries
cursor.execute("SELECT * FROM users WHERE username = %s", (username,))
```

**Command Injection:**
```python
# VULNERABLE
import subprocess
subprocess.run(f"convert {filename} output.pdf", shell=True)
# filename = "input.jpg; rm -rf /; echo "

# MITIGATION: use list form, no shell=True
subprocess.run(["convert", filename, "output.pdf"], check=True)
```

**NoSQL Injection (MongoDB):**
```javascript
// VULNERABLE
db.users.find({ username: req.body.username, password: req.body.password })
// body: { "username": "admin", "password": { "$gt": "" } }  → bypasses password check

// MITIGATION: validate types explicitly
if (typeof req.body.password !== 'string') throw new Error("Invalid input");
```

---

### A04: Insecure Design

**Not a code bug but an architectural failure:**
- Password reset: security question instead of emailed OTP → guessable
- Shopping cart: total calculated client-side → tampered to $0
- Rate limiting: only on login endpoint, not on "check username exists" → username enumeration

**Design countermeasures:**
- Threat model during design (before code)
- Abuse case analysis: for every feature, ask "how would an attacker misuse this?"
- Defense in depth: multiple controls for each trust boundary

---

### A05: Security Misconfiguration

**Examples:**
```yaml
# VULNERABLE Kubernetes pod
spec:
  containers:
    - name: app
      securityContext:
        privileged: true          # has host kernel access
        runAsRoot: true           # running as root
      env:
        - name: DEBUG
          value: "true"           # verbose error messages expose internals
```

**Mitigation:**
```yaml
spec:
  containers:
    - name: app
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      env:
        - name: DEBUG
          value: "false"
```

**Other common misconfigs:**
- Default admin credentials left unchanged
- Cloud storage buckets set to public by default (`aws s3api put-bucket-acl --acl public-read`)
- Error messages revealing stack traces / SQL queries in production

---

### A06: Vulnerable and Outdated Components

```bash
# Python: check for known vulnerabilities
pip install pip-audit
pip-audit

# Java (Maven)
mvn dependency-check:check  # OWASP Dependency Check

# Node.js
npm audit

# Container images
trivy image myapp:latest  # checks OS packages + language deps
```

**FAANG practice:** Every build pipeline runs a dependency vulnerability scan. Critical/High CVEs block the build. Weekly automated PRs to bump dependencies (Renovate/Dependabot).

---

### A07: Identification and Authentication Failures

```python
# VULNERABLE: predictable session ID
session_id = str(user_id) + str(timestamp)  # guessable!

# MITIGATION: cryptographically random
import secrets
session_id = secrets.token_urlsafe(32)  # 256-bit entropy

# VULNERABLE: no rate limiting on login
@app.post("/login")
def login(username: str, password: str):
    user = db.find_user(username)
    if check_password(user, password):  # attacker can brute-force
        return create_session(user)

# MITIGATION: rate limiting + lockout
@rate_limit(max_attempts=5, window=300)  # 5 attempts per 5 minutes
@app.post("/login")
def login(username: str, password: str):
    ...
```

---

### A08: Software and Data Integrity Failures

```bash
# VULNERABLE: download without verification
curl -O https://downloads.example.com/app.tar.gz
tar xzf app.tar.gz  # what if MITM replaced this?

# MITIGATION: verify signature
curl -O https://downloads.example.com/app.tar.gz
curl -O https://downloads.example.com/app.tar.gz.sig
gpg --verify app.tar.gz.sig app.tar.gz  # verify before extracting
```

**Deserialization:**
```java
// VULNERABLE: ObjectInputStream with untrusted data
ObjectInputStream ois = new ObjectInputStream(request.getInputStream());
Object obj = ois.readObject();  // arbitrary code execution if gadget chain exists

// MITIGATION: never deserialize untrusted data with Java ObjectInputStream
// Use JSON/Protobuf with schema validation instead
```

---

### A09: Security Logging and Monitoring Failures

**What must be logged:**
```python
# Authentication events
logger.info("auth.login.success", user_id=user_id, ip=request.ip, method="password")
logger.warning("auth.login.failure", username=username, ip=request.ip, reason="bad_password")

# Authorization events
logger.warning("authz.denied", user_id=user_id, resource=resource_id, action=action,
               reason="insufficient_role")

# Security-relevant operations
logger.info("admin.role_granted", admin_id=admin_id, target_user_id=user_id, role=role)
logger.warning("sensitive.export", user_id=user_id, record_count=count, ip=request.ip)

# NEVER LOG: passwords, tokens, card numbers, SSNs
```

**SIEM integration:** Logs → structured JSON → CloudWatch / Datadog → SIEM alerts.

---

### A10: Server-Side Request Forgery (SSRF)

```python
# VULNERABLE: user-controlled URL fetched by server
@app.post("/webhook-test")
def test_webhook(url: str):
    response = requests.get(url)  # attacker sends http://169.254.169.254/latest/meta-data/
    return response.json()        # returns AWS instance credentials!
```

**Mitigation:**
```python
import ipaddress, urllib.parse

ALLOWED_SCHEMES = {"https"}
BLOCKED_HOSTS = {"169.254.169.254", "::1", "localhost", "metadata.google.internal"}

def validate_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)

    if parsed.scheme not in ALLOWED_SCHEMES:
        return False

    # Resolve hostname and check against blocklist
    try:
        import socket
        ip = socket.gethostbyname(parsed.hostname)
        addr = ipaddress.ip_address(ip)
        if addr.is_private or addr.is_loopback or addr.is_link_local:
            return False
        if parsed.hostname in BLOCKED_HOSTS:
            return False
    except Exception:
        return False

    return True
```

---

## Part C: Supply Chain Security

### SLSA (Supply-chain Levels for Software Artifacts)

**Published by:** Google (2021); adopted by OpenSSF (Open Source Security Foundation)

**Goal:** Ensure that the software you run is what was actually built from the source you trust — not tampered with anywhere in the build → package → deploy pipeline.

**SLSA Levels:**

| Level | Description | Requirements |
|---|---|---|
| **SLSA 0** | No guarantees | — |
| **SLSA 1** | Documentation | Build process is scripted and documented |
| **SLSA 2** | Tamper evidence | Version control + hosted build service; build provenance generated |
| **SLSA 3** | Extra resistance | Build service prevents parameter modification; builds are isolated |
| **SLSA 4** | Highest trust | Two-party review; hermetic (reproducible) builds |

**Provenance attestation:**
```json
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "subject": [{"name": "myapp", "digest": {"sha256": "abc123..."}}],
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "predicate": {
    "builder": {"id": "https://github.com/actions/runner"},
    "buildType": "https://github.com/Attestations/GitHubActionsWorkflow@v1",
    "invocation": {
      "configSource": {
        "uri": "git+https://github.com/acme/myapp@refs/heads/main",
        "digest": {"sha1": "deadbeef..."},
        "entryPoint": ".github/workflows/build.yaml"
      }
    }
  }
}
```

---

### Sigstore (Keyless Code Signing)

**Components:**
- **Cosign:** sign + verify container images and artifacts
- **Fulcio:** certificate authority issuing short-lived certs based on OIDC identity
- **Rekor:** transparency log (append-only, Merkle tree of signing events — like CT for code signing)

**Keyless signing workflow:**
```bash
# Sign image (uses GitHub Actions OIDC token — no long-lived key needed)
cosign sign --identity-token=$(oidc_token) ghcr.io/acme/myapp:v1.2.3

# Under the hood:
# 1. Cosign requests OIDC token from GitHub Actions (claims: repo, workflow, SHA)
# 2. Cosign sends OIDC token to Fulcio → receives short-lived certificate (10 min TTL)
# 3. Cosign signs image digest with ephemeral key
# 4. Signing event logged in Rekor (immutable record)
# 5. Cert + signature attached to image in OCI registry

# Verify image signature
cosign verify --certificate-identity="https://github.com/acme/myapp/.github/workflows/build.yaml@refs/heads/main" \
              --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
              ghcr.io/acme/myapp:v1.2.3
```

**Enforce signed images in Kubernetes:**
```yaml
# Kyverno policy: reject unsigned images
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  rules:
    - name: check-image-signature
      match:
        any:
          - resources:
              kinds: ["Pod"]
      verifyImages:
        - imageReferences:
            - "ghcr.io/acme/*"
          attestors:
            - count: 1
              entries:
                - keyless:
                    subject: "https://github.com/acme/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
```

---

### SBOM (Software Bill of Materials)

**What it is:** A machine-readable list of all software components in an artifact (like an ingredient list for software).

**Formats:**

| Format | Maintainer | File type | Tooling |
|---|---|---|---|
| **SPDX** | Linux Foundation / ISO 5962 | JSON, YAML, RDF | Syft, FOSSA |
| **CycloneDX** | OWASP | JSON, XML | Syft, cdxgen, Grype |

**Generating an SBOM:**
```bash
# Generate SBOM for a container image (Syft)
syft ghcr.io/acme/myapp:v1.2.3 -o spdx-json > myapp-sbom.spdx.json

# Generate for Maven project
syft dir:. -o cyclonedx-json > myapp-sbom.cdx.json

# Scan SBOM for known vulnerabilities (Grype)
grype sbom:myapp-sbom.spdx.json

# Attach SBOM to container image (cosign + ORAS)
cosign attach sbom --sbom myapp-sbom.spdx.json ghcr.io/acme/myapp:v1.2.3
```

**Use cases:**
- **Vulnerability response:** when Log4Shell (CVE-2021-44228) dropped, orgs with SBOMs knew immediately which services were affected; orgs without took days to inventory
- **License compliance:** scan for copyleft licenses (GPL) in commercial software
- **Regulatory compliance:** US Executive Order 14028 (May 2021) requires SBOMs for federal software procurement

---

### Dependency Confusion Attacks

**Attack pattern (Alex Birsan, 2021):**
1. Developer uses private package named `acme-internal-utils` hosted on internal registry
2. Attacker publishes `acme-internal-utils` on **public npm/PyPI** with a higher version number
3. npm/pip resolves public registry first (if not explicitly configured) → downloads malicious package
4. Attack was used against Apple, Microsoft, PayPal, Uber — got $130K in bug bounties

**Mitigations:**
```bash
# npm: scope all private packages with @org-name prefix
# Package name: @acme/internal-utils (scoped → always from configured registry)

# npm .npmrc: explicit registry per scope
@acme:registry=https://registry.internal.acme.com

# pip: configure extra-index-url with priority
pip install --index-url https://pypi.internal.acme.com/simple/
            --no-index  # don't fall back to public PyPI

# Preflight: check if package name exists on public registry
# If yes: squatter attack possible → claim the name or change the name
```

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Threat modeling timing | After implementation | At design phase | Design phase (fixes are 100× cheaper) |
| SLSA level | SLSA 1 (script) | SLSA 3 (isolated builds) | SLSA 3 for production artifacts |
| Image signing | No signing | Cosign + Sigstore | Cosign keyless signing + Kyverno enforcement |
| SBOM | None | SPDX/CycloneDX + scan | Generate in every build; scan for CVEs in CI |
| Dependency confusion | Public name overlap allowed | Scoped private packages | Scope all internal packages + explicit registries |

---

## FAANG Interview Callout

**Q: "Walk me through a STRIDE threat model for a payment API."**
→ Start with DFD: User → API Gateway → Payment Service → [Postgres DB, Stripe, Fraud Service]. Identify trust boundaries: internet/DMZ, DMZ/internal. For each flow and store: Spoofing (stolen JWT → short-lived tokens + binding), Tampering (SQL injection → parameterized queries; card data tampered in transit → TLS), Repudiation (no audit log → add immutable audit log), Info Disclosure (card numbers in DB → tokenize; tokens in logs → mask), DoS (unbounded request rate → rate limit per user_id), Elevation (IDOR on orderId → ownership check). DREAD-rank: IDOR and SQL injection are Critical (10); missing rate limit is High (7). Track mitigations to completion before launch.

**Q: "Log4Shell dropped last night (CVSS 10.0). How do you know which of your 200 microservices are affected?"**
→ With SBOMs: query SBOM database for all services with `log4j-core` in any version < 2.15.0 → affected list in minutes. Without SBOMs: manual inventory across 200 repos + build artifacts → hours to days. Response: patch affected services, rebuild images, deploy. Preventive: run Grype/Trivy in CI on every build; alert on new Critical CVEs in any component.

**Q: "What is Sigstore and why is it considered a step-change for supply chain security?"**
→ Sigstore eliminates the key management problem of traditional code signing. Cosign signs artifacts using short-lived certificates issued by Fulcio (against OIDC identity — e.g., GitHub Actions workflow). No long-lived private signing keys to manage, rotate, or accidentally expose. Every signing event is logged in Rekor (append-only transparency log) → anyone can audit who signed what and when. Kyverno/OPA enforces that only Sigstore-signed images with known identities can run in Kubernetes. This is now the default for all CNCF projects and is being adopted across the FAANG/major tech ecosystem.
