# Passwords, MFA, and Passkeys

> **Principal Engineer Reference** — covers the full authentication credential stack: from password hashing internals through TOTP/HOTP one-time codes to FIDO2/WebAuthn passkeys. Includes attack analysis for each layer.

---

## Part A: Password Authentication

### Why Legacy Password Hashing is Broken

**The GPU threat model:**

| Hash Function | Hashes/sec (RTX 4090) | Time to crack 8-char password |
|---|---|---|
| MD5 | 100 billion | < 1 second |
| SHA-1 | 45 billion | < 1 second |
| SHA-256 | 23 billion | < 5 seconds |
| bcrypt (cost=12) | ~300 | ~26 years |
| Argon2id (64MB, 3 iter) | ~15 | Centuries |

**Why salting alone is not enough:**

```
Without salt:  H("password123") → same hash for all users → one rainbow table cracks all
With salt:     H("password123" + random_salt_per_user) → unique hash per user
                → attacker must brute-force each hash individually
                → doesn't help if hash function is fast (SHA-256)
```

**The real fix:** Make the hash function deliberately slow AND memory-hard.

---

### bcrypt

**Algorithm internals:**
1. Derives a 448-bit Blowfish P-array and four 256-entry S-boxes from the password using `EksBlowfishSetup` (expensive key schedule)
2. Encrypts the constant `OrpheanBeholderScryDoubt` 64 times with derived key
3. Output format: `$2b$[cost]$[22-char-base64-salt][31-char-base64-hash]`

```
$2b$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW
 │   │  ├──────────────────────┤├────────────────────────────────┤
 version cost    salt (16 bytes)           hash (24 bytes)
```

**Key properties:**
- Cost factor `N`: iterations = `2^N`; cost 12 → 4096 rounds; target 100-300ms on production server
- **Critical limitation:** silently truncates passwords at 72 bytes (Blowfish internal limit)
  - Fix: `SHA-256(password) → bcrypt` (pre-hash then bcrypt), but risks null-byte issues
  - Better: use Argon2id

**Java example (Spring Security):**
```java
PasswordEncoder encoder = new BCryptPasswordEncoder(12);
String hashed = encoder.encode(rawPassword);
boolean valid = encoder.matches(rawPassword, hashed); // timing-safe
```

---

### Argon2id — OWASP 2024 Recommendation

**Three variants:**
- **Argon2d:** Data-dependent memory access → GPU-resistant, but vulnerable to side-channel attacks
- **Argon2i:** Data-independent memory access → side-channel resistant (safe in browser), lower GPU resistance
- **Argon2id:** Hybrid — Argon2i first pass, Argon2d subsequent → both GPU and side-channel resistant

**Parameters:**
- `m` (memory cost, KB): higher = more RAM per hash = cheaper for defenders, expensive for attackers
- `t` (time cost, iterations): multiple passes over memory
- `p` (parallelism): threads; set to number of available cores
- `salt`: 16 bytes random per credential
- `hash_length`: 32 bytes output

**OWASP minimums (2024):**
```
m=65536 (64 MB), t=3, p=4, hash_len=32, salt_len=16
```

**Why memory-hardness defeats hardware attackers:**
- ASIC/GPU advantage comes from parallelism: 10,000 cores at low cost
- If each hash requires 64MB RAM, 10,000 parallel hashes = 640GB RAM — prohibitively expensive

```python
# Python (argon2-cffi library)
from argon2 import PasswordHasher, exceptions

ph = PasswordHasher(
    time_cost=3,
    memory_cost=65536,   # 64 MB
    parallelism=4,
    hash_len=32,
    salt_len=16
)

hashed = ph.hash("secret_password")
try:
    ph.verify(hashed, "secret_password")  # raises if invalid
    if ph.check_needs_rehash(hashed):     # rehash if params upgraded
        hashed = ph.hash("secret_password")
except exceptions.VerifyMismatchError:
    raise AuthError("Invalid password")
```

---

### NIST SP 800-63B Guidelines (2024)

Key guidance for password policies at principal engineer level:

1. **Length over complexity:** minimum 8 chars; allow up to 64+ chars; Unicode support
2. **No mandatory rotation:** forced periodic rotation → predictable patterns (`Password1!` → `Password2!`)
3. **No complexity rules:** they reduce entropy (users just do `P@ssw0rd`)
4. **Check against breach databases:** NIST mandates checking against known-compromised passwords (HaveIBeenPwned k-Anonymity API)
5. **No security questions:** guessable, stored in plaintext on other sites
6. **MFA over complexity:** 2FA is more effective than complex password requirements

**HaveIBeenPwned k-Anonymity API:**
```python
import hashlib, requests

def is_pwned(password: str) -> bool:
    sha1 = hashlib.sha1(password.encode()).hexdigest().upper()
    prefix, suffix = sha1[:5], sha1[5:]
    resp = requests.get(f"https://api.pwnedpasswords.com/range/{prefix}")
    # Only send first 5 chars — server never sees full hash
    return suffix in resp.text
```

---

### Timing-Safe Comparison

```python
# WRONG — leaks timing info via early exit
def verify_password_WRONG(input_hash, stored_hash):
    return input_hash == stored_hash  # exits on first differing byte

# CORRECT — constant-time comparison
import hmac
def verify_password(input_hash: bytes, stored_hash: bytes) -> bool:
    return hmac.compare_digest(input_hash, stored_hash)
```

**Java:**
```java
// WRONG
if (userHash.equals(storedHash)) { ... }

// CORRECT
MessageDigest.isEqual(userHash, storedHash)
// or: Arrays.equals (NOT timing-safe!) — use MessageDigest.isEqual
```

---

## Part B: Multi-Factor Authentication (MFA)

### MFA Factor Categories

| Factor | Type | Examples | Phishing Resistant |
|---|---|---|---|
| Password | Knowledge | bcrypt-hashed password | No |
| TOTP/HOTP code | Knowledge + Possession | Authenticator app | No |
| SMS OTP | Possession | Phone number | No (SIM swap vulnerable) |
| Hardware token | Possession | YubiKey (FIDO2) | **Yes** |
| Biometric | Inherence | Touch ID, Face ID (local) | **Yes** (can't phish a fingerprint) |

---

### HOTP (RFC 4226)

**HMAC-Based One-Time Password:**

```
HOTP(K, C) = Truncate(HMAC-SHA1(K, C))

Where:
  K = shared secret (base32-encoded, stored server-side and in authenticator)
  C = counter (synchronized between client and server)
  Truncate = take 4 bytes at dynamic offset → 6-digit code
```

**Counter synchronization problem:** client and server counters can drift if user generates codes without authenticating → server must accept a window of counter values (look-ahead window).

---

### TOTP (RFC 6238) — The Standard

**Time-Based OTP:**

```
T = floor(unix_timestamp / 30)    # 30-second time step
TOTP(K, T) = HOTP(K, T)          # re-uses HOTP with time-step counter
OTP = TOTP(K, T) mod 10^6        # 6 digits
```

**Properties:**
- Shared secret `K` generated at enrollment (QR code = `otpauth://totp/Issuer:user@example.com?secret=BASE32SECRET&issuer=Issuer`)
- Server accepts T-1, T, T+1 (±30s clock drift tolerance)
- Secret stored on server; private key never leaves device (vs FIDO2)

**Weaknesses:**
- **Phishable:** attacker proxies login → relays TOTP code in real time (evilginx, Modlishka)
- Secret lives on server → breach of server = breach of all TOTP secrets
- SIM swap doesn't apply (app-based), but phishing does

```python
import pyotp, time

totp = pyotp.TOTP("BASE32SECRETHERE")
code = totp.now()                      # current OTP
valid = totp.verify(user_input)        # accepts ±1 window
valid = totp.verify(user_input, valid_window=1)  # ±30s
```

---

### FIDO2 and WebAuthn

**Architecture:**
- **FIDO2** = WebAuthn (W3C) + CTAP2 (Client to Authenticator Protocol)
- **Authenticator types:** Platform (TPM, Secure Enclave) or Roaming (YubiKey, phone)
- **Key insight:** Private key never leaves the authenticator; server stores public key only

**Registration Ceremony:**
```
1. Server → Browser: challenge (random, 32 bytes) + relying_party_id + user_id
2. Browser → Authenticator: create(challenge, rpId, userHandle)
3. Authenticator:
   a. Prompt user (touch/biometric/PIN)
   b. Generate key pair (ES256 / RS256 / EdDSA) bound to rpId
   c. Return: attestation_object (credentialId + public_key + attestation_statement + authenticatorData)
4. Browser → Server: send attestation_object
5. Server: verify attestation, store (credentialId, public_key, counter=0) for user
```

**Authentication Ceremony:**
```
1. Server → Browser: challenge + rpId + allowCredentials (list of credentialIds)
2. Browser → Authenticator: get(challenge, rpId, credentialId)
3. Authenticator:
   a. Prompt user
   b. Sign: signature = Sign(private_key, authenticatorData || hash(clientDataJSON))
   c. Return: assertion (credentialId + authenticatorData + clientDataJSON + signature)
4. Browser → Server: send assertion
5. Server:
   a. Verify rpIdHash matches
   b. Verify challenge matches (prevents replay)
   c. Verify userPresence flag
   d. Verify signature using stored public_key
   e. Check counter > stored_counter (prevents cloned authenticator)
   f. Update stored_counter
```

**Why FIDO2 is phishing-resistant:**
- The `rpId` (relying party ID, e.g., `"example.com"`) is bound to the credential at creation
- If user is on `evil-example.com`, the browser sends `rpId = "evil-example.com"` → authenticator rejects (wrong origin)
- Signature covers `clientDataJSON` which includes the origin → cannot be replayed cross-domain

---

### Passkeys (FIDO2 + Synced Credentials)

**What's new vs traditional FIDO2:**
- **Resident keys (discoverable credentials):** stored in authenticator memory, not just referenced by credentialId
- **Multi-device:** private key synced via platform (iCloud Keychain, Google Password Manager, 1Password)
- **No username/password needed:** server sends empty `allowCredentials`; user picks passkey

**Passkey security model:**

| Property | Traditional FIDO2 | Passkeys |
|---|---|---|
| Key never leaves device | Yes (hardware token) | No (synced to cloud) |
| Phishing resistant | Yes | Yes |
| Multi-device | Only via hardware token | Yes (cloud sync) |
| Recovery | Backup token | Cloud account recovery |
| Threat model | Physical device theft | Cloud account compromise |

**When to choose what:**
- High-security (admin accounts, finance): hardware FIDO2 key (YubiKey) — key physically cannot leave device
- Consumer accounts: passkeys — best UX, phishing-resistant, sync provides recovery

---

### MFA Fatigue and Modern Attacks

| Attack | Description | Mitigation |
|---|---|---|
| **MFA fatigue / push bombing** | Attacker has password; spams push notifications until user approves by mistake | Number matching: app shows 2-digit code; user must match to phone display |
| **Real-time phishing proxy** | evilginx proxies login, relaying TOTP in real time | FIDO2/WebAuthn — bound to origin; proxy gets wrong rpId |
| **SIM swap** | Attacker social-engineers carrier to transfer phone number | Abandon SMS OTP; use authenticator app or FIDO2 |
| **Recovery code theft** | Backup codes stored insecurely | Treat recovery codes as passwords; store in vault |
| **Authenticator app malware** | Malware reads TOTP from phone | FIDO2 hardware key; screen lock + app PIN |

---

## Trade-offs Summary

| Mechanism | Security | UX | Phishing Resistant | Recovery |
|---|---|---|---|---|
| Password only | Low | Good | No | Easy |
| Password + SMS OTP | Medium | OK | No (SIM swap, phishing) | Easy |
| Password + TOTP | Good | OK | No (real-time proxy) | Medium (recovery codes) |
| Password + FIDO2 hardware | **Excellent** | Slightly complex | **Yes** | Hard (need backup key) |
| Passkeys | **Excellent** | **Best** | **Yes** | Platform recovery |

---

## FAANG Interview Callout

> **Common interview questions:**

**Q: "Why don't we just use SHA-256 to hash passwords?"**
→ SHA-256: 23 billion hashes/second on an RTX 4090. An 8-character password space is ~200 trillion combinations → cracked in ~2.4 hours. Use Argon2id: 15 hashes/second → same space takes 400+ years. The solution is slow + memory-hard hashing.

**Q: "Design MFA for a consumer app at 100M users."**
→ Default TOTP (RFC 6238) with authenticator app; passkeys for supported platforms (iOS 16+, Android 9+). Store TOTP secrets encrypted at rest (AES-256 + KMS). Rate-limit OTP attempts (5 attempts per 30-second window). Provide 10 single-use recovery codes (Argon2id-hashed, displayed once at setup). Push SMS OTP only as fallback (clearly marked as less secure).

**Q: "A user's TOTP secret was leaked in a DB breach. What's the blast radius?"**
→ Attacker can generate valid TOTP codes for affected users. Immediate: invalidate all active sessions, force password reset, require users to re-enroll TOTP with new secrets. Mitigation going forward: encrypt TOTP secrets at rest with DEK per user + envelope encryption. Consider migrating to FIDO2 where server stores only public key → breach reveals nothing useful.

**Q: "Explain why FIDO2 is phishing-resistant at a protocol level."**
→ At registration, the credential is bound to `rpId` (origin). During authentication, the browser passes `origin` in `clientDataJSON`, which is signed. The server checks `rpIdHash` in `authenticatorData` against its own `rpId`. If the user is on `evil.com`, the `rpId` won't match → authentication fails. The attacker cannot replay the assertion because the challenge is single-use and the origin is cryptographically bound.
