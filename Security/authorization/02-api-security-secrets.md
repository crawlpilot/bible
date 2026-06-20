# API Security and Secrets Management

> **Principal Engineer Reference** — covers API authentication patterns (API keys, HMAC signing, mTLS), secrets lifecycle management with HashiCorp Vault and AWS Secrets Manager, envelope encryption with KMS, and production secrets practices at FAANG scale.

---

## Part A: API Authentication Patterns

### Pattern Comparison

| Pattern | Revocation | Scope | Identity | Use Case |
|---|---|---|---|---|
| **API Key** | Immediate (DB lookup) | Per-key | Service/user | Simple M2M, public APIs |
| **JWT Bearer** | Delayed (expiry or blacklist) | In token | User or service | User-facing APIs, micro-services |
| **OAuth Client Credentials** | Via AS revocation | Scoped | Service | Cross-service with delegation |
| **mTLS** | Via cert revocation (short TTL) | Transport-level | Service (SPIFFE) | Internal microservices |
| **HMAC Request Signing** | Per-request | Request-level | Service | Webhook delivery, financial APIs |
| **AWS Signature V4** | Via IAM policy | Scoped to service | IAM principal | AWS API calls |

---

### API Keys

**Structure:** Opaque, random, high-entropy string. Typical format: `{prefix}_{random_base62}`.

```python
import secrets, base64

def generate_api_key(prefix: str = "sk") -> tuple[str, str]:
    """Returns (plaintext_key, hashed_key_for_storage)"""
    import hashlib
    raw = secrets.token_bytes(32)
    plaintext = f"{prefix}_{base64.urlsafe_b64encode(raw).rstrip(b'=').decode()}"
    # NEVER store plaintext — store hash only (like passwords)
    hashed = hashlib.sha256(plaintext.encode()).hexdigest()
    return plaintext, hashed
```

**Key properties:**
- Prefix identifies key type visually (`sk_` = secret key, `pk_` = public key — Stripe pattern)
- Store only SHA-256 hash in DB (never plaintext — same as passwords)
- Show plaintext only once at creation (user must copy and save)
- Support multiple active keys per account (rotation without downtime)

**Storage schema:**
```sql
CREATE TABLE api_keys (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id),
    name VARCHAR(255),                -- human label
    key_hash VARCHAR(64) NOT NULL,    -- SHA-256 hex, NOT the plaintext
    prefix VARCHAR(10) NOT NULL,      -- first 8 chars for display
    scopes TEXT[],                    -- ['read:orders', 'write:orders']
    created_at TIMESTAMPTZ DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,           -- optional expiry
    revoked_at TIMESTAMPTZ            -- NULL = active
);

CREATE INDEX idx_api_keys_hash ON api_keys(key_hash) WHERE revoked_at IS NULL;
```

**Request validation:**
```python
import hashlib, hmac
from functools import lru_cache

def validate_api_key(raw_key: str) -> Optional[ApiKey]:
    key_hash = hashlib.sha256(raw_key.encode()).hexdigest()
    key = db.query(
        "SELECT * FROM api_keys WHERE key_hash = $1 AND revoked_at IS NULL "
        "AND (expires_at IS NULL OR expires_at > now())",
        key_hash
    ).first()
    if key:
        db.execute("UPDATE api_keys SET last_used_at = now() WHERE id = $1", key.id)
    return key
```

**Rate limiting:** Associate rate limit buckets with `account_id`, not `key_id` — a user with 10 keys should not get 10× the rate limit.

---

### API Key vs JWT Comparison

| Concern | API Key | JWT |
|---|---|---|
| **Stateless validation** | No (DB lookup required) | Yes (signature verify) |
| **Revocation** | Immediate (remove from DB) | Delayed (expiry or blacklist) |
| **Information in token** | None (opaque) | Claims (user, roles, scopes) |
| **Rotation** | Manual + coordination | Automatic (refresh tokens) |
| **Suitable for** | Long-lived service credentials | Short-lived user sessions |
| **Audit trail** | Per-request DB log | Token metadata |

---

### HMAC Request Signing (AWS Signature V4 Pattern)

**Why HMAC signing vs Bearer tokens:**
- Covers the request body — modification of body is detectable
- Includes timestamp → prevents replay attacks (±5-minute window)
- Signatures are per-request, not long-lived tokens

**AWS Signature V4 algorithm:**

```
Step 1: Create Canonical Request
CanonicalRequest =
  HTTPMethod + "\n" +
  CanonicalURI + "\n" +
  CanonicalQueryString + "\n" +
  CanonicalHeaders + "\n" +   # header-name:value, sorted
  SignedHeaders + "\n" +      # header names, semicolon-separated
  HexHash(Payload)            # SHA-256 of request body

Step 2: Create String to Sign
StringToSign =
  "AWS4-HMAC-SHA256" + "\n" +
  Timestamp + "\n" +           # 20240101T120000Z
  CredentialScope + "\n" +     # 20240101/us-east-1/s3/aws4_request
  HexHash(CanonicalRequest)

Step 3: Calculate Signing Key
SigningKey =
  HMAC(HMAC(HMAC(HMAC("AWS4" + SecretKey, Date), Region), Service), "aws4_request")

Step 4: Create Signature
Signature = HexEncode(HMAC(SigningKey, StringToSign))

Step 5: Add to Authorization header
Authorization: AWS4-HMAC-SHA256
  Credential=ACCESS_KEY/CREDENTIAL_SCOPE,
  SignedHeaders=host;x-amz-date,
  Signature=SIGNATURE
```

**Custom implementation for webhooks:**

```python
import hmac, hashlib, time

def sign_request(payload: bytes, secret: str, timestamp: int = None) -> str:
    timestamp = timestamp or int(time.time())
    signed_content = f"v0:{timestamp}:{payload.decode()}".encode()
    signature = hmac.new(secret.encode(), signed_content, hashlib.sha256).hexdigest()
    return f"v0={signature}"  # Slack webhook format

def verify_webhook(payload: bytes, signature_header: str, secret: str,
                   max_age_seconds: int = 300) -> bool:
    ts, sig = signature_header.split(",")
    timestamp = int(ts.split("=")[1])

    # Prevent replay: reject if older than 5 minutes
    if abs(time.time() - timestamp) > max_age_seconds:
        return False

    expected = sign_request(payload, secret, timestamp)
    return hmac.compare_digest(expected, sig)  # timing-safe
```

---

## Part B: Secrets Management

### Secret Categories and Rotation Requirements

| Secret Type | Examples | Rotation Frequency | Storage |
|---|---|---|---|
| **Database credentials** | Postgres password | Every 1-90 days | Vault dynamic secrets |
| **API keys (3rd party)** | Stripe, SendGrid | Every 90 days | Vault KV / Secrets Manager |
| **TLS private keys** | Service certs | Every 90 days (SPIFFE: every 24h) | Vault PKI / SPIRE |
| **SSH private keys** | EC2 bastion | Per-session with SSH CA | SSH CA (8h certs) |
| **Encryption keys (DEK)** | Per-record AES keys | With key rotation policy | Vault Transit / KMS |
| **JWT signing keys** | RS256 private key | Every 30-90 days | Vault Transit / HSM |
| **Service account creds** | K8s ServiceAccount | Short-lived (IRSA, Workload Identity) | Cloud IAM |

---

### HashiCorp Vault

**Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│  Vault Server (Active + Standby, HA with Raft/Consul)        │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────────────────┐    │
│  │   Auth Methods   │  │       Secret Engines         │    │
│  │  - AppRole       │  │  - KV v2 (static secrets)    │    │
│  │  - Kubernetes    │  │  - Database (dynamic creds)  │    │
│  │  - AWS IAM       │  │  - PKI (certificate issuing) │    │
│  │  - OIDC          │  │  - Transit (encrypt/decrypt) │    │
│  │  - GitHub        │  │  - SSH (OTP + CA)            │    │
│  └──────────────────┘  └──────────────────────────────┘    │
│                                                             │
│  Audit Log (every request logged: accessor, path, response) │
└─────────────────────────────────────────────────────────────┘
```

**Auth Methods → Vault Token:** Every interaction requires a Vault token. The auth method authenticates the client and issues a token with attached policy.

```bash
# Kubernetes auth: pod authenticates using its ServiceAccount JWT
vault write auth/kubernetes/login \
  role=my-app \
  jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"

# Returns: vault_token with ttl=1h, policies=[my-app-policy]
```

---

### Vault KV v2 (Static Secrets)

```bash
# Store secret
vault kv put secret/myapp/database password="super-secret" user="app"

# Read secret
vault kv get secret/myapp/database

# Versioned: KV v2 keeps history
vault kv get -version=2 secret/myapp/database

# Metadata: view versions, deletion time
vault kv metadata get secret/myapp/database
```

**Python (vault SDK):**
```python
import hvac

client = hvac.Client(url="https://vault.internal:8200", token=vault_token)

# Read
secret = client.secrets.kv.v2.read_secret_version(
    path="myapp/database",
    mount_point="secret"
)
password = secret["data"]["data"]["password"]

# Write
client.secrets.kv.v2.create_or_update_secret(
    path="myapp/database",
    secret={"password": new_password, "user": "app"},
    mount_point="secret"
)
```

---

### Vault Dynamic Secrets (Database Engine)

**Game changer:** Vault creates a temporary database user with TTL. When TTL expires, Vault revokes it. No long-lived shared credentials.

```bash
# Configure database connection (once, by admin)
vault write database/config/mypostgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@db.internal:5432/mydb" \
  allowed_roles=my-app \
  username=vault-admin \
  password=vault-admin-password

# Configure role: template for temporary user
vault write database/roles/my-app \
  db_name=mypostgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN ENCRYPTED PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl=1h \
  max_ttl=24h

# Application requests credentials
vault read database/creds/my-app
# Returns:
#   username: v-appname-xkcd4321
#   password: A1b2-C3d4-E5f6
#   lease_duration: 1h
```

**Benefits:**
- Credentials unique per lease → breach of one credential doesn't expose others
- Automatic expiry → no manual rotation
- Audit log shows exactly which pod, which lease, which credentials
- Renewal: application renews lease before TTL → extends without new password

---

### Vault Transit Engine (Encryption-as-a-Service)

**What it does:** Vault holds encryption keys; applications encrypt/decrypt data without ever seeing the key.

```bash
# Create named key
vault write transit/keys/customer-data type=aes256-gcm96

# Encrypt
vault write transit/encrypt/customer-data \
  plaintext=$(base64 <<< "secret PII data")
# Returns: vault:v1:AbCdEf...base64...

# Decrypt
vault write transit/decrypt/customer-data \
  ciphertext="vault:v1:AbCdEf..."
# Returns: plaintext=base64-of-original
```

**Key rotation:**
```bash
vault write -f transit/keys/customer-data/rotate
# New version created: vault:v2:...
# Old version still decrypts vault:v1:... ciphertexts
# Set min_decryption_version to force migration
vault write transit/keys/customer-data/config min_decryption_version=2
```

---

### AWS Secrets Manager

```python
import boto3, json

client = boto3.client("secretsmanager", region_name="us-east-1")

# Read secret
response = client.get_secret_value(SecretId="prod/myapp/database")
secret = json.loads(response["SecretString"])
db_password = secret["password"]

# Automatic rotation (requires Lambda rotation function)
client.rotate_secret(
    SecretId="prod/myapp/database",
    RotationLambdaARN="arn:aws:lambda:...",
    RotationRules={"AutomaticallyAfterDays": 30}
)
```

**Cross-region replication:** Secrets Manager can replicate secrets to multiple regions for DR.

**Integration with RDS:** Managed automatic rotation for RDS passwords via built-in Lambda functions.

---

### Envelope Encryption

**The core pattern (used by all major clouds + Vault):**

```
Data → encrypt with DEK (Data Encryption Key, per record or per tenant)
DEK  → encrypt with KEK (Key Encryption Key, stored in KMS / Vault)

At rest:
  - ciphertext (encrypted data)
  - encrypted_dek (DEK wrapped by KEK)
  - key_id (which KEK version to use for decryption)

KEK never leaves the KMS/HSM.
```

```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import boto3, os, json

kms = boto3.client("kms")
KMS_KEY_ID = "arn:aws:kms:us-east-1:123456789012:key/..."

def encrypt(plaintext: bytes) -> dict:
    # 1. Generate DEK via KMS (returns both plaintext + encrypted version)
    dek_response = kms.generate_data_key(KeyId=KMS_KEY_ID, KeySpec="AES_256")
    dek_plaintext = dek_response["Plaintext"]       # 32 bytes
    dek_encrypted = dek_response["CiphertextBlob"]  # DEK encrypted by KMS CMK

    # 2. Encrypt data with DEK
    nonce = os.urandom(12)
    aesgcm = AESGCM(dek_plaintext)
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)

    # 3. Clear plaintext DEK from memory
    dek_plaintext = b"\x00" * 32  # overwrite

    return {
        "ciphertext": ciphertext,
        "nonce": nonce,
        "encrypted_dek": dek_encrypted  # stored alongside ciphertext
    }

def decrypt(envelope: dict) -> bytes:
    # 1. Decrypt DEK using KMS
    dek_response = kms.decrypt(CiphertextBlob=envelope["encrypted_dek"])
    dek_plaintext = dek_response["Plaintext"]

    # 2. Decrypt data with DEK
    aesgcm = AESGCM(dek_plaintext)
    return aesgcm.decrypt(envelope["nonce"], envelope["ciphertext"], None)
```

**Why envelope encryption:**
- **DEK rotation:** Re-encrypt DEK with new KEK → no need to re-encrypt all data
- **KEK never leaves KMS HSM** → even Vault/KMS admins cannot see it
- **Per-tenant DEKs:** different customers get different DEKs → breach of one doesn't affect others
- **Audit trail:** every KMS Decrypt call is logged in CloudTrail

---

### Secrets in CI/CD

**Anti-patterns:**
```yaml
# WRONG: Secret in environment variable printed in logs
env:
  DB_PASSWORD: "hardcoded-secret"   # visible in plaintext

# WRONG: Secret in repository
echo "password: my-secret" > config.yaml
git add config.yaml  # now in git history forever
```

**Correct patterns:**

```yaml
# GitHub Actions: secrets referenced, never echo'd
jobs:
  deploy:
    steps:
      - name: Deploy
        env:
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
        run: |
          # DO NOT: echo $DB_PASSWORD
          ./deploy.sh  # script reads $DB_PASSWORD from env

# Vault Agent sidecar (Kubernetes): inject secrets as files
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-inject-secret-db-creds: "secret/myapp/database"
  vault.hashicorp.com/role: "my-app"
# Result: /vault/secrets/db-creds mounted in pod (not env var)
```

**Secret sprawl detection:**
- **git-secrets / trufflehog / gitleaks:** scan git history for committed secrets
- **Vault audit log:** detect secrets being fetched but never revoked (stale leases)
- **AWS Config:** check for IAM keys unused > 90 days

---

### Kubernetes Secrets: The Problem

Kubernetes Secrets are base64-encoded, NOT encrypted by default.

```bash
# Default: stored in etcd as base64
kubectl get secret my-secret -o yaml
# data:
#   password: cGFzc3dvcmQ=  ← base64("password") — anyone with etcd access reads this
```

**Solutions:**
1. **etcd encryption at rest:** configure `EncryptionConfiguration` with KMS provider
2. **Sealed Secrets:** asymmetric encryption; only cluster can decrypt (Bitnami)
3. **External Secrets Operator:** Kubernetes operator that fetches from Vault/Secrets Manager and creates native Secrets
4. **Vault Agent Injector:** sidecar injects secrets as files, bypassing Kubernetes Secrets entirely

```yaml
# External Secrets Operator
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: my-k8s-secret   # creates this Kubernetes Secret
  data:
    - secretKey: db-password
      remoteRef:
        key: secret/myapp/database
        property: password
```

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Static vs dynamic secrets | Static (long-lived) | Vault dynamic (short-lived) | Dynamic where possible (DB creds, certs) |
| Secrets in K8s | Native Secrets | External Secrets + Vault | External Secrets Operator (encrypted, audited) |
| Encryption key management | App-managed | KMS/Vault Transit | KMS/Vault: key never leaves HSM |
| DEK granularity | One key per system | One key per tenant | Per-tenant DEKs (blast radius isolation) |
| Secret rotation | Manual | Automated (Vault/Secrets Manager) | Automated: 30-day or shorter TTL |

---

## FAANG Interview Callout

**Q: "Design a secrets management system for a 500-engineer, 100-microservice organization."**
→ HashiCorp Vault Enterprise (HA with Raft). Auth: Kubernetes auth for pods (IRSA on AWS), AppRole for non-K8s. Secrets: dynamic DB credentials (1h TTL, auto-revoke), Vault PKI for internal TLS certs (24h TTL), KV v2 for 3rd-party API keys. Envelope encryption for app-layer data (Transit engine as KMS). Vault Agent Injector for K8s → secrets as mounted files. Audit log → SIEM (CloudWatch/Splunk). Rotation: automated for DB + TLS; remind for 3rd-party keys (90-day alert).

**Q: "A developer accidentally committed an API key to Git. What do you do?"**
→ Immediate: revoke the key (don't wait — assume it's compromised even if the commit was "private"). Issue new key. If secret has been in git history: `git filter-repo` or BFG Repo Cleaner to purge history + force push all branches (coordinate with team). Check audit logs for any use of the compromised key. Post-incident: set up git-secrets or gitleaks pre-commit hooks; add Vault or External Secrets for secret injection instead of .env files.

**Q: "Explain envelope encryption and why it's used at AWS scale."**
→ DEK encrypts data (fast AES-256-GCM). KEK (CMK) encrypts DEK (via KMS API call). Only ciphertext + encrypted DEK are stored. CMK never leaves the KMS HSM. Benefits: DEK rotation = re-encrypt DEK only (not all data); per-customer DEKs = breach isolation; CMK audit trail via CloudTrail; compliance (FIPS 140-2 Level 3 HSM). At AWS scale: billions of KMS API calls per day; CMK is a logical key backed by HSM, autoscaled transparently.
