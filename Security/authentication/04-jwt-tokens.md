# JWT Tokens: Structure, Algorithms, Vulnerabilities, and Patterns

> **Principal Engineer Reference** — covers JWT internals, signing algorithm selection, all critical vulnerabilities with exploit code, refresh token rotation, JWK key management, and JWT at FAANG scale.

---

## JWT Structure

### Three-Part Format

```
eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCIsImtpZCI6ImtleS0yMDI0MDEifQ
.
eyJzdWIiOiJ1c2VyMTIzIiwiaXNzIjoiaHR0cHM6Ly9hdXRoLmV4YW1wbGUuY29tIiwiYXVkIjoiYXBpLmV4YW1wbGUuY29tIiwiZXhwIjoxNzM1NjkwMDAwLCJpYXQiOjE3MzU2ODY0MDAsImp0aSI6InVuaXF1ZS10b2tlbi1pZCJ9
.
SIGNATURE
└──────────────────────────────────────────────────────────────────┘
   header (base64url)  .  payload (base64url)  .  signature (base64url)
```

**Critical:** Base64URL encoding is NOT encryption. Anyone can decode the header and payload. **JWT is not confidential by default** — never put secrets, PII, or sensitive data in the payload unless using JWE (JSON Web Encryption).

```python
import base64, json

def decode_jwt_part(part: str) -> dict:
    # Add padding
    padded = part + "=" * (4 - len(part) % 4)
    return json.loads(base64.urlsafe_b64decode(padded))
```

---

### Header

```json
{
  "alg": "EdDSA",         // signing algorithm — CRITICAL: must be validated
  "typ": "JWT",
  "kid": "key-20240101"  // key ID — used to look up the public key
}
```

**Fields:**
- `alg`: Which algorithm was used. **Must be verified against an allowlist.**
- `kid`: Key identifier. Allows serving multiple keys (rotation, multi-tenant).
- `typ`: Always `"JWT"` for standard JWTs.

---

### Payload (Claims)

**Registered claims (RFC 7519 §4.1):**

| Claim | Full Name | Type | Description |
|---|---|---|---|
| `iss` | Issuer | String (URI) | Who issued the token (e.g., `https://auth.example.com`) |
| `sub` | Subject | String | Whom the token refers to (user ID, service ID) |
| `aud` | Audience | String or Array | Intended recipient — **must be validated by RS** |
| `exp` | Expiration | NumericDate | Unix timestamp; token is invalid after this |
| `nbf` | Not Before | NumericDate | Token is invalid before this timestamp |
| `iat` | Issued At | NumericDate | When the token was issued |
| `jti` | JWT ID | String | Unique token identifier — enables blacklisting |

**Private claims (custom):**
```json
{
  "sub": "user:alice",
  "iss": "https://auth.example.com",
  "aud": "api.example.com",
  "exp": 1735690000,
  "iat": 1735686400,
  "jti": "550e8400-e29b-41d4-a716-446655440000",
  "roles": ["admin", "billing"],
  "tenant_id": "acme-corp",
  "scope": "read:orders write:orders"
}
```

---

## Signing Algorithms

### Algorithm Comparison

| Algorithm | Type | Signing Key | Verification Key | Signature Size | Notes |
|---|---|---|---|---|---|
| **HS256** | HMAC-SHA256 | Shared secret | Same shared secret | 256-bit | Symmetric — both sides need secret |
| **HS384** | HMAC-SHA384 | Shared secret | Same shared secret | 384-bit | Higher security margin |
| **RS256** | RSA-SHA256 | Private key | Public key (JWK) | 256 bytes | Most common; widely supported |
| **RS384** | RSA-SHA384 | Private key | Public key | 384 bytes | Marginal improvement |
| **ES256** | ECDSA P-256 | Private key | Public key (JWK) | 64 bytes | Smaller than RSA; probabilistic |
| **ES384** | ECDSA P-384 | Private key | Public key | 96 bytes | — |
| **EdDSA** | Ed25519 | Private key | Public key (JWK) | 64 bytes | **Recommended**; deterministic; fastest |
| `none` | No signature | — | — | 0 | **NEVER USE** — security disaster |

---

### HS256 (Symmetric — Shared Secret)

**When to use:** Single-party (same service signs and verifies), or fully-trusted parties where sharing the secret is acceptable.

**Risks:**
- Any service that can verify can also forge tokens
- Secret must be distributed to all verifying services → secret sprawl
- Secret must be ≥256 bits (32 bytes random) — **never use a short, guessable string**

```python
import jwt, secrets

# Sign
secret = secrets.token_bytes(32)  # 256-bit
token = jwt.encode({"sub": "user123", "exp": ...}, secret, algorithm="HS256")

# Verify
payload = jwt.decode(token, secret, algorithms=["HS256"],  # whitelist!
                     audience="api.example.com")
```

---

### RS256 / EdDSA (Asymmetric — Most Common Pattern)

**When to use:** Multiple services need to verify; only AS needs to sign. Publish public key via JWK endpoint.

```python
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import jwt

private_key = Ed25519PrivateKey.generate()
public_key = private_key.public_key()

# Sign (at Auth Server)
token = jwt.encode({"sub": "user123", "iss": "https://auth.example.com",
                    "aud": "api.example.com", "exp": ...},
                   private_key, algorithm="EdDSA",
                   headers={"kid": "key-20240101"})

# Verify (at Resource Server — using cached JWK)
payload = jwt.decode(token, public_key,
                     algorithms=["EdDSA"],          # MUST whitelist
                     audience="api.example.com",
                     issuer="https://auth.example.com")
```

---

### JWT Validation Checklist

**Every RS MUST validate all of these:**

```python
def validate_jwt(token: str, public_key, expected_audience: str, expected_issuer: str) -> dict:
    header = jwt.get_unverified_header(token)

    # 1. Algorithm whitelist — CRITICAL
    allowed_algorithms = {"RS256", "RS384", "ES256", "ES384", "EdDSA"}
    if header["alg"] not in allowed_algorithms:
        raise ValueError(f"Rejected algorithm: {header['alg']}")

    # 2. Fetch public key by kid (from JWK cache)
    key = jwk_cache.get(header.get("kid"), public_key)

    # 3-7. jwt.decode validates: signature, exp, nbf, iss, aud
    payload = jwt.decode(
        token, key,
        algorithms=list(allowed_algorithms),
        audience=expected_audience,    # validates aud claim
        issuer=expected_issuer,        # validates iss claim
        leeway=5,                      # 5-second clock skew tolerance
        options={
            "require": ["exp", "iat", "iss", "aud", "sub"],  # required claims
            "verify_exp": True,
            "verify_nbf": True,
        }
    )

    # 8. JTI blacklist check (optional, for stateful revocation)
    if jti_blacklist.is_revoked(payload.get("jti")):
        raise ValueError("Token has been revoked")

    return payload
```

---

## Critical Vulnerabilities

### 1. `alg: none` Attack

**Vulnerability:** Some libraries accept `"alg": "none"` and skip signature verification.

```python
# Attack: forge a token with alg=none, strip signature
import base64, json

header = base64.urlsafe_b64encode(
    json.dumps({"alg": "none", "typ": "JWT"}).encode()
).rstrip(b"=").decode()

payload = base64.urlsafe_b64encode(
    json.dumps({"sub": "admin", "role": "superuser"}).encode()
).rstrip(b"=").decode()

forged_token = f"{header}.{payload}."  # empty signature
```

**Mitigation:** Always pass an explicit algorithm allowlist to the JWT library. Never accept `"none"`.

---

### 2. Algorithm Confusion: HS256 with RS256 Public Key

**Vulnerability:** RS256 server expects asymmetric signature. Attacker sends HS256 token, using the server's PUBLIC KEY as the HMAC secret.

```
Scenario:
  Server's RS256 public key is known (from JWK endpoint) = pub_key

  Attacker signs token with: HMAC-SHA256(message, pub_key)
  Sets alg = "HS256"

  Vulnerable library: detects HS256, uses the configured "key" (pub_key) to verify HMAC
  → Accepts attacker's forged token
```

**Mitigation:** Maintain a strict per-issuer algorithm allowlist. Never allow the algorithm to be chosen from the token header without validation.

---

### 3. Missing Audience Validation

**Vulnerability:** Token issued for Service A (aud=service-a) is accepted by Service B.

```
Token: { "sub": "user123", "aud": "service-a", "scope": "read:orders" }
Service B validates signature (valid!) but skips aud check
→ Token intended for A is accepted by B
```

**Mitigation:** Always validate `aud`. Each service should have its own audience identifier.

---

### 4. Missing Expiry Enforcement

**Vulnerability:** Library configured with `verify_exp=False` or expiry check disabled.

```python
# WRONG
payload = jwt.decode(token, key, algorithms=["RS256"],
                     options={"verify_exp": False})  # stolen tokens valid forever
```

**Mitigation:** Always verify `exp`. Short-lived access tokens (15 min) limit blast radius even if check were missed.

---

### 5. Sensitive Data in Payload

**Vulnerability:** JWT payload is Base64URL-encoded, NOT encrypted. Anyone who intercepts the token can decode the payload.

```
Dangerous:
{
  "ssn": "123-45-6789",
  "credit_card": "4111111111111111",
  "internal_ip": "10.0.0.1"
}
```

**Mitigation:**
- Store only non-sensitive identifiers (`sub`, `role`, `scope`)
- For sensitive claims: use JWE (JSON Web Encryption) — wraps JWT in encrypted envelope
- Or: keep sensitive data server-side; JWT is just a reference key

---

## Refresh Token Patterns

### Short-Lived Access + Long-Lived Refresh

```
Access token:  15 minutes (stored in memory)
Refresh token: 7 days (stored in HttpOnly, Secure, SameSite=Strict cookie)
```

**Why not long-lived access tokens?** Stolen access token valid for days = catastrophic. Short expiry limits blast radius.

### Refresh Token Rotation

```
Client: POST /token?grant_type=refresh_token&refresh_token=RT1
AS:
  1. Validate RT1 (not expired, not revoked)
  2. Issue new access_token AT2 + new refresh_token RT2
  3. Invalidate RT1 (single-use)
  4. Return AT2 + RT2
```

**Refresh token family invalidation (theft detection):**
```
RT1 → AT1 + RT2
RT2 → AT2 + RT3

Attacker uses old RT2 after RT3 issued:
  AS detects RT2 was already used!
  → Invalidate entire family (RT1, RT2, RT3, all future)
  → User must re-authenticate
```

This detects token theft: legitimate client would only use the latest refresh token.

---

## JWK (JSON Web Key) Endpoint

### Public Key Distribution

```
GET https://auth.example.com/.well-known/jwks.json

{
  "keys": [
    {
      "kty": "OKP",
      "crv": "Ed25519",
      "use": "sig",
      "kid": "key-20240101",
      "x": "11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo"
    },
    {
      "kty": "OKP",
      "crv": "Ed25519",
      "use": "sig",
      "kid": "key-20231001",    ← previous key, still valid while old tokens expire
      "x": "ZHVtbXkta2V5LWZvcm1hdC1vbmx5..."
    }
  ]
}
```

### Zero-Downtime Key Rotation

```
Day 0:  JWK = { key-old }
Day 1:  Generate key-new
        JWK = { key-old, key-new }  ← publish both
        New tokens signed with key-new, kid=key-new
Day 2:  Old tokens (signed with key-old) expire (TTL = 15 min access token)
Day 2+: Remove key-old from JWK
        JWK = { key-new }
```

**RS finds the right key:** JWT header contains `kid`. RS fetches JWK endpoint → find key matching `kid` → verify signature. Cache JWK with 1-hour TTL; re-fetch on unknown `kid`.

```python
from functools import lru_cache
import jwt, requests
from jwt.algorithms import OKPAlgorithm

@lru_cache(maxsize=10)
def get_public_key(kid: str, issuer: str):
    jwks_uri = f"{issuer}/.well-known/jwks.json"
    resp = requests.get(jwks_uri, timeout=5)
    resp.raise_for_status()
    keys = {k["kid"]: k for k in resp.json()["keys"]}
    if kid not in keys:
        raise ValueError(f"Unknown kid: {kid}")
    return OKPAlgorithm.from_jwk(keys[kid])
```

---

## JWE (JSON Web Encryption)

**When to use:** Payload must be confidential (sensitive claims, PII).

```
JWE structure: header.encrypted_key.iv.ciphertext.tag
               (5 parts vs JWS 3 parts)
```

**Process:**
1. Generate random Content Encryption Key (CEK)
2. Encrypt CEK with recipient's public key (RSA-OAEP or ECDH-ES)
3. Encrypt payload with CEK using AES-256-GCM
4. Output: encrypted_key + iv + ciphertext + auth_tag

```python
from jwcrypto import jwt as jwcrypto_jwt, jwk

key = jwk.JWK.generate(kty="EC", crv="P-256")
token = jwcrypto_jwt.JWT(
    header={"alg": "ECDH-ES+A256KW", "enc": "A256GCM"},
    claims={"sub": "user123", "ssn": "123-45-6789"}
)
token.make_encrypted_token(key)
```

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Algorithm | HS256 | RS256 / EdDSA | RS256/EdDSA if multiple verifiers; HS256 only single-service |
| Access token lifetime | 1 hour | 15 minutes | 15 minutes (minimize stolen token blast radius) |
| Refresh token storage | Memory / localStorage | HttpOnly cookie | HttpOnly, Secure, SameSite=Strict cookie |
| Token revocation | JTI blacklist | Short expiry | Short expiry + refresh rotation (stateless preferred at scale) |
| Sensitive claims | In payload | JWE or server-side | Never plaintext JWT for sensitive data |
| Key distribution | Hardcoded public key | JWK endpoint | JWK endpoint (enables zero-downtime rotation) |

---

## FAANG Interview Callout

> **JWT deep-dive questions:**

**Q: "A JWT was stolen. How do you revoke it?"**
→ Short-lived (15 min): just wait — limited blast radius. Immediate: maintain JTI blacklist (Redis set of revoked `jti` values with TTL = token expiry). On each request: check blacklist. Refresh token: revoke at AS (invalidate family). For admin account compromise: rotate signing key (all existing tokens immediately invalid).

**Q: "You have 50 microservices. Each validates JWTs. How do you rotate signing keys without downtime?"**
→ Publish JWK endpoint with multiple keys (`kid` per key). New tokens use `kid=new-key`. Old tokens use `kid=old-key`. Both keys present in JWK for duration of old token TTL (max 15 min). After TTL, remove old key. Services cache JWK with 1h TTL; on `kid` not found → re-fetch immediately.

**Q: "Explain the `alg: none` attack and how to prevent it."**
→ JWT header declares `"alg": "none"`. Vulnerable library skips signature verification. Attacker strips signature, modifies payload (e.g., sets `role=admin`), server accepts it. Prevention: maintain explicit algorithm allowlist; never derive allowed algorithm from the token itself. Pass `algorithms=["RS256", "EdDSA"]` to the decode function.

**Q: "What's the difference between JWT and opaque tokens? When do you use each?"**
→ JWT is self-contained (validate with public key, no AS call). Opaque requires introspection (call to AS). JWT is better for distributed/high-scale (local validation, no AS dependency). Opaque is better when you need immediate revocation (AS invalidates immediately). Common pattern: short-lived JWT access tokens (fast validation) + opaque refresh tokens (revocable at AS).
