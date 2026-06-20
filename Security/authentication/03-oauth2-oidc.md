# OAuth 2.0 and OpenID Connect (OIDC)

> **Principal Engineer Reference** — covers all OAuth 2.0 grant types, PKCE deep-dive, OpenID Connect identity layer, token storage patterns, and how OAuth scales to billions of validations per day at Google/Meta/Amazon.

---

## OAuth 2.0 Core Concepts

### Roles (RFC 6749 §1.1)

| Role | Definition | Example |
|---|---|---|
| **Resource Owner** | Entity that can grant access to protected resources | End user, or org (for M2M) |
| **Client** | Application requesting access on behalf of resource owner | Web app, mobile app, CLI, service |
| **Authorization Server (AS)** | Issues access tokens after authenticating resource owner | Keycloak, Auth0, Okta, Google AS |
| **Resource Server (RS)** | Hosts the protected resources; validates access tokens | Your API, Google Calendar API |

### Token Types

| Token | Format | Validated by | TTL |
|---|---|---|---|
| **Access token** | JWT or opaque string | RS validates signature/introspection | 15 min – 1 hour |
| **Refresh token** | Opaque, random | AS validates at token endpoint | 7 days – 90 days |
| **Authorization code** | Short random string | AS validates at token endpoint | 60 seconds (single-use) |
| **ID token** (OIDC only) | JWT | Client validates signature + claims | Single-use (contains auth time) |

---

## All OAuth 2.0 Grant Types

### 1. Authorization Code Grant (RFC 6749 §4.1)

**Use case:** Server-side web applications with a client secret.

```
User                Browser              Client Server        Auth Server
 │                    │                       │                    │
 │── Click "Login" ──►│                       │                    │
 │                    │── GET /auth ─────────►│                    │
 │                    │   ?response_type=code │                    │
 │                    │   &client_id=ABC       │                    │
 │                    │   &redirect_uri=...   │                    │
 │                    │   &state=xyz          │                    │
 │                    │   &scope=read:orders  │                    │
 │                    │◄─ 302 redirect ───────│ to AS /authorize   │
 │                    │──────────────────────────────────────────►│
 │◄─ Login page ──────│◄──────────────────────────────────────────│
 │── Credentials ────►│──────────────────────────────────────────►│
 │                    │◄── 302 redirect ──────────────────────────│
 │                    │    ?code=AUTH_CODE&state=xyz               │
 │                    │── GET /callback?code=AUTH_CODE ──────────►│
 │                    │                       │── POST /token ───►│
 │                    │                       │   grant_type=code  │
 │                    │                       │   code=AUTH_CODE  │
 │                    │                       │   redirect_uri=...│
 │                    │                       │   client_id=ABC   │
 │                    │                       │   client_secret=XY│
 │                    │                       │◄─ access_token ───│
 │                    │                       │   refresh_token   │
 │                    │◄── session cookie ───│                    │
```

**State parameter:** CSRF protection — client generates random state, stores in session, verifies on callback.

---

### 2. Authorization Code + PKCE (RFC 7636)

**Use case:** Public clients (SPAs, mobile/desktop apps) that cannot safely store a client secret.

**The problem with implicit grant (now deprecated):**
- Access token returned directly in URL fragment (`#access_token=...`)
- Leaks via Referer header, browser history, proxy logs
- No way to verify the client that started the flow

**PKCE solution:**

```
1. Client generates:
   code_verifier  = base64url(random_bytes(32))  # 43-128 chars, stored in memory
   code_challenge = base64url(SHA256(code_verifier))

2. Authorization request includes:
   &code_challenge=BASE64URL_SHA256_VALUE
   &code_challenge_method=S256

3. AS stores code_challenge with auth code

4. Token exchange:
   POST /token
   code=AUTH_CODE
   code_verifier=ORIGINAL_VERIFIER  ← sent instead of client_secret

5. AS verifies: BASE64URL(SHA256(code_verifier)) == stored code_challenge
```

**Why this works:** Even if auth code is intercepted, attacker doesn't have `code_verifier` (only held in memory; never sent until token exchange). Even if `code_challenge` is seen in URL, can't reverse SHA256 to get `code_verifier`.

```python
import secrets, hashlib, base64

# Client-side PKCE generation
code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b'=').decode()
code_challenge = base64.urlsafe_b64encode(
    hashlib.sha256(code_verifier.encode()).digest()
).rstrip(b'=').decode()
```

---

### 3. Client Credentials Grant (RFC 6749 §4.4)

**Use case:** Machine-to-machine (M2M) without user involvement. Service-to-service authentication.

```
Service A                          Auth Server
    │── POST /token ──────────────►│
    │   grant_type=client_credentials
    │   client_id=service-a
    │   client_secret=... (or mTLS cert)
    │◄─ access_token ──────────────│
    │   (no refresh token)         │
    │
    │── API call with Bearer token ──► Service B (Resource Server)
```

**No user context:** Token subject (`sub`) is the client itself, not a user.
**Rotation:** Client secrets should be rotated regularly; prefer mTLS client certificates for higher assurance.

---

### 4. Device Authorization Grant (RFC 8628)

**Use case:** Devices with limited input capability (smart TVs, IoT, CLI tools).

```
Device                             User's Browser          Auth Server
    │── POST /device_authorization ──────────────────────►│
    │   client_id=CLI_APP                                  │
    │◄── device_code + user_code + verification_uri ───────│
    │
    │── Display to user: ─────────────────────────────────►│
    │   "Visit https://example.com/activate"               │
    │   "Enter code: ABCD-1234"               User enters code → approves
    │
    │── Poll POST /token (every 5s) ───────────────────────►│
    │   grant_type=urn:ietf:params:oauth:grant-type:device_code
    │   device_code=...
    │   client_id=...
    │                     while pending: returns "authorization_pending"
    │◄── access_token (once user approves) ────────────────│
```

---

### 5. Token Exchange Grant (RFC 8693)

**Use case:** Service A needs to act on behalf of a user when calling Service B.

```
Two patterns:
  Impersonation:  Service B receives token with subject = original user
  Delegation:     Service B receives token with actor = Service A AND subject = user

POST /token
  grant_type=urn:ietf:params:oauth:grant-type:token-exchange
  subject_token=USER_JWT
  subject_token_type=urn:ietf:params:oauth:token-type:access_token
  audience=service-b
  scope=read:orders

Returns: new token with reduced scope, targeted to Service B
```

**FAANG use case:** At Google, service mesh uses token exchange to create service-scoped tokens. At Stripe, payment processing services receive user-delegated tokens with billing-only scope.

---

### 6. Implicit Grant (Deprecated)

**Do not use.** Replaced by Authorization Code + PKCE. Issues:
- Access token in URL fragment → browser history, Referer leaks
- No client authentication → any client can use the token
- RFC 9700 (OAuth 2.1) removes it entirely

---

## Token Introspection and Revocation

### Introspection (RFC 7662)

**Use case:** Resource Server validates opaque (non-JWT) access tokens.

```
RS → AS: POST /introspect
         token=OPAQUE_ACCESS_TOKEN
         client_credentials...

AS → RS: {
  "active": true,
  "sub": "user123",
  "scope": "read:orders",
  "exp": 1735689600,
  "client_id": "web-app"
}
```

**Latency:** 10-50ms per introspection → cache results (token hash → introspection response) with TTL ≤ token expiry.

### Revocation (RFC 7009)

```
POST /revoke
token=REFRESH_TOKEN
token_type_hint=refresh_token
client_id=...
client_secret=...
```

For **JWT access tokens** (self-contained): cannot be revoked without a blacklist or short expiry. Common pattern: short-lived access tokens (15 min) + revocable refresh tokens.

---

## OpenID Connect (OIDC)

### What OIDC Adds to OAuth 2.0

```
OAuth 2.0:  authorization (access_token answers "can this client access X?")
OIDC:       authentication (id_token answers "who is the user?")
```

OIDC is OAuth 2.0 + ID token (JWT) + UserInfo endpoint + discovery document.

### OIDC Authorization Code Flow

**Additional parameters in authorization request:**
```
scope=openid profile email   ← "openid" scope is required for OIDC
nonce=RANDOM_VALUE           ← prevents ID token replay
```

**Token endpoint response adds `id_token`:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "...",
  "id_token": "eyJhbGciOiJSUzI1NiJ9..."
}
```

### ID Token Claims (RFC 8693 + OIDC Core §2)

```json
{
  "iss": "https://accounts.google.com",        // issuer
  "sub": "110169484474386276334",               // subject (unique user ID)
  "aud": "client_id_abc123",                   // audience (must be your client_id)
  "exp": 1735689600,                           // expiration
  "iat": 1735686000,                           // issued at
  "nonce": "n-0S6_WzA2Mj",                    // from authorization request
  "email": "user@example.com",                 // if email scope requested
  "name": "Alice Doe",                         // if profile scope
  "email_verified": true
}
```

**ID token validation checklist:**
1. Verify signature against issuer's JWK endpoint (`/.well-known/openid-configuration` → `jwks_uri`)
2. Verify `iss` = expected issuer
3. Verify `aud` contains your `client_id`
4. Verify `exp` > now
5. Verify `nonce` matches what you sent
6. If `acr` required: verify level of assurance meets requirement

### OIDC Discovery

```
GET https://accounts.google.com/.well-known/openid-configuration

{
  "issuer": "https://accounts.google.com",
  "authorization_endpoint": "https://accounts.google.com/o/oauth2/v2/auth",
  "token_endpoint": "https://oauth2.googleapis.com/token",
  "userinfo_endpoint": "https://openidconnect.googleapis.com/v1/userinfo",
  "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs",
  "scopes_supported": ["openid", "email", "profile"],
  "response_types_supported": ["code", "token"],
  "subject_types_supported": ["public"]
}
```

### UserInfo Endpoint

```
GET /userinfo
Authorization: Bearer ACCESS_TOKEN

{
  "sub": "110169484474386276334",
  "name": "Alice Doe",
  "email": "alice@example.com",
  "picture": "https://..."
}
```

---

## Token Storage Best Practices

| Storage Location | Token Type | XSS Risk | CSRF Risk | Notes |
|---|---|---|---|---|
| `localStorage` | Access token | **High** — any JS can read | None | **Avoid** for sensitive tokens |
| `sessionStorage` | Access token | **High** — any JS can read | None | Better than localStorage (cleared on tab close) |
| **HttpOnly cookie** | Refresh token | None (JS cannot read) | **Need SameSite** | Best for refresh tokens |
| **Memory (JS var)** | Access token | Low (cleared on reload) | None | **Recommended for access tokens in SPAs** |
| Server session | Both | None | Need CSRF token | Best for server-side rendered apps |

**Recommended SPA pattern:**
```
Access token:  memory (JS variable, lost on refresh) → use silent refresh
Refresh token: HttpOnly, Secure, SameSite=Strict cookie → CSRF-safe
```

**Silent refresh:** use hidden iframe or background fetch to AS token endpoint before access token expires.

---

## Scopes and Consent

**Scope design principles:**
- **Coarse-grained resource scopes:** `read:orders`, `write:orders` (not `read`, `write`)
- **Avoid over-granting:** request minimum scopes needed per operation
- **Incremental authorization:** request additional scopes only when needed (e.g., calendar access when user clicks calendar feature)

**Consent screen:** User sees which scopes are being requested. Machine clients (client credentials) don't have a consent screen.

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Public client auth | Implicit grant | Auth Code + PKCE | **PKCE always**; Implicit deprecated in OAuth 2.1 |
| M2M auth | API key | Client credentials | Client credentials (scoped, revocable, standard) |
| Token format (RS) | Opaque + introspection | Self-contained JWT | JWT for distributed RS; opaque + introspection for single-AS |
| Access token lifetime | 1 hour | 15 minutes | 15 min + refresh rotation (minimize blast radius) |
| Refresh token storage | localStorage | HttpOnly cookie | HttpOnly cookie (XSS-safe) |

---

## FAANG Interview Callout

> **OAuth/OIDC at scale:**

**Q: "How does Google handle 10B+ OAuth token validations per day?"**
→ JWT access tokens are self-contained and signed with RS256. Resource servers cache Google's JWK endpoint (public keys) and validate locally — no call to AS per request. JWK cache TTL = 1 hour. Key rotation uses `kid` to support overlapping keys. Only refresh token operations touch the AS.

**Q: "Design SSO for a multi-tenant SaaS with 500 enterprise customers, each with their own IdP (Okta, ADFS, Azure AD)."**
→ OIDC federation hub (Keycloak, Auth0). Each enterprise customer configures their IdP as an OIDC provider in your hub. Users are redirected to their IdP for authentication. Your hub receives `id_token`, creates local session, issues your own short-lived JWT. Tenant is identified by `client_id` or `iss` claim. Per-tenant RBAC in your authorization layer.

**Q: "What's the difference between OAuth 2.0 and OIDC? When would you use each?"**
→ OAuth 2.0 is an authorization framework (grants access). OIDC adds authentication on top (who is the user, via `id_token`). Use OAuth alone for API access delegation. Use OIDC when you need to establish user identity (login, user profile). In practice: almost always OIDC for user-facing login because you need both.

**Q: "A CLI tool needs to access user data from your API without a browser redirect. Which grant type?"**
→ Device Authorization Grant (RFC 8628). CLI prints URL + short code. User opens URL on phone/browser, approves. CLI polls token endpoint until approved. Works for any device without a browser for the redirect.
