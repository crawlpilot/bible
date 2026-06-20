# Symmetric & Asymmetric Encryption, Hashing, and MACs

> **Principal Engineer Reference** — covers the mathematical foundations and practical implementations of every cryptographic primitive you will encounter in system design and security interviews.

---

## Part A: Symmetric Encryption

### Stream Ciphers vs Block Ciphers

| Property | Stream Cipher | Block Cipher |
|---|---|---|
| Unit of operation | 1 bit or 1 byte at a time | Fixed-size block (128-bit for AES) |
| Examples | RC4 (broken), ChaCha20 | AES, 3DES (deprecated) |
| Use case | Real-time comms, low-latency | File/disk encryption, TLS record layer |
| Parallelizable | No (depends on previous state) | Depends on mode (CTR/GCM = yes) |

**Why block ciphers dominate at rest:** They offer deterministic transformations that can be combined with integrity checking (AEAD modes). ChaCha20 is the modern stream cipher of choice for devices lacking AES hardware acceleration.

---

### AES (Advanced Encryption Standard)

**Internals:**
- Block size: **128 bits** (fixed, regardless of key size)
- Key sizes: 128, 192, or 256 bits → 10, 12, or 14 rounds respectively
- Structure: **SPN (Substitution-Permutation Network)**

**Round operations (applied 10-14 times):**
1. **SubBytes** — each byte replaced via S-box (non-linear substitution)
2. **ShiftRows** — rows of 4×4 state matrix shifted cyclically
3. **MixColumns** — matrix multiplication over GF(2^8) — diffusion
4. **AddRoundKey** — XOR with round key derived from key schedule

**Key expansion (Rijndael key schedule):** master key expanded into per-round subkeys using SubBytes + Rcon constants. Changing 1 bit in the master key changes all round keys (avalanche effect).

```
AES-256 security: 2^256 brute-force operations
GPU cluster cracking AES-256: infeasible (universe age = 2^62 seconds)
```

---

### Block Cipher Modes

| Mode | IV Required | Parallelizable | Authenticated | Notes |
|---|---|---|---|---|
| **ECB** | No | Yes | No | **BROKEN** — identical plaintext blocks → identical ciphertext |
| **CBC** | Yes (random) | Decrypt only | No | Padding oracle attacks (POODLE); no parallel encryption |
| **CTR** | Yes (nonce) | Yes (both) | No | Turns block cipher into stream cipher; nonce MUST be unique |
| **GCM** | Yes (nonce, 96-bit) | Yes | **Yes (AEAD)** | Encryption + GHASH MAC in one pass; **recommended** |
| **CCM** | Yes | Partial | Yes | Used in TLS 1.3 for constrained devices |

**GCM deep-dive (the standard for TLS 1.3, disk encryption, JWT):**
- Encryption: CTR mode with counter starting at 2
- Authentication: GHASH over ciphertext + AAD (Additional Authenticated Data)
- Output: ciphertext + 128-bit auth tag
- **Critical: Never reuse a (key, nonce) pair** — GCM nonce reuse reveals the authentication key

```python
# Correct AES-256-GCM usage (Python cryptography library)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

key = os.urandom(32)       # 256-bit key
nonce = os.urandom(12)     # 96-bit nonce — MUST be unique per encryption

aesgcm = AESGCM(key)
ciphertext = aesgcm.encrypt(nonce, plaintext, aad)  # aad can be None
plaintext  = aesgcm.decrypt(nonce, ciphertext, aad)  # raises exception if auth fails
```

---

### ChaCha20-Poly1305

- Designed by Daniel Bernstein; standardized in RFC 8439
- ChaCha20 = stream cipher (256-bit key, 96-bit nonce, 32-bit counter)
- Poly1305 = one-time MAC for authentication → **AEAD when combined**
- **When to prefer over AES-GCM:** devices without AES-NI hardware instructions (mobile, embedded, IoT)
- Used in: TLS 1.3 (`TLS_CHACHA20_POLY1305_SHA256`), WireGuard, Signal Protocol

---

### Key Sizes and Security Margins

| Key Size | Algorithm | Security Bits | Status |
|---|---|---|---|
| 56-bit | DES | 56 | Broken (1998, 22h crack) |
| 112-bit | 3DES | 112 | Deprecated (NIST 2023) |
| 128-bit | AES-128 | 128 | Secure (Grover's algorithm reduces to 64-bit quantum security) |
| 256-bit | AES-256, ChaCha20 | 256 | **Recommended**; quantum-resistant with 128-bit post-quantum margin |

---

## Part B: Asymmetric Encryption

### One-Way Trapdoor Functions

Asymmetric cryptography relies on mathematical problems that are:
- **Easy to compute** (polynomial time with the key)
- **Hard to reverse** (exponential time without the secret)

| Algorithm | Hard Problem | Notes |
|---|---|---|
| RSA | Integer factorization: given `n = p×q`, find `p` and `q` | Best attack: GNFS; broken by Shor's algorithm on quantum computers |
| DH / ECDH | Discrete logarithm: given `g`, `g^a mod p`, find `a` | ECDH uses elliptic curve variant; also Shor-vulnerable |
| ECDSA / Ed25519 | Elliptic Curve Discrete Log | Shorter keys than RSA for same security |

---

### RSA

**Key generation:**
1. Choose two large primes `p` and `q` (2048-bit each → 4096-bit n for production)
2. `n = p × q` (public modulus)
3. `φ(n) = (p-1)(q-1)` (Euler's totient)
4. Choose `e` (public exponent, typically `65537 = 2^16 + 1`)
5. Compute `d = e^(-1) mod φ(n)` (private exponent via extended Euclidean)

**Encryption:** `C = M^e mod n`
**Decryption:** `M = C^d mod n`

**Why raw RSA (textbook RSA) is broken:**
- Deterministic: same message → same ciphertext → susceptible to chosen-plaintext attacks
- Multiplicative: `E(m1) × E(m2) = E(m1 × m2 mod n)` — homomorphic leak

**Required padding:**
- **OAEP (Optimal Asymmetric Encryption Padding)** — RFC 3447; adds randomness and MGF hash
- **PSS (Probabilistic Signature Scheme)** — for signatures (instead of PKCS#1 v1.5)

```
RSA-2048 security ≈ 112-bit symmetric equivalent
RSA-3072 security ≈ 128-bit symmetric equivalent  ← current recommendation
RSA-4096 security ≈ 140-bit (overkill for most; use ECC instead)
```

---

### Elliptic Curve Cryptography (ECC)

**Curve equation:** `y² = x³ + ax + b mod p` (Weierstrass form)

**Scalar multiplication (the one-way function):**
- Given point `G` (generator) on the curve and scalar `k`, compute `Q = k × G`
- **Easy:** compute `Q` from `k` and `G` (O(log k) doublings)
- **Hard:** given `G` and `Q`, find `k` (elliptic curve discrete log)

**Common curves:**

| Curve | Bits | Security | Notes |
|---|---|---|---|
| P-256 (secp256r1) | 256 | 128-bit | NIST curve; used in TLS 1.3, ECDSA, FIDO2 |
| P-384 | 384 | 192-bit | Government/high-security use |
| X25519 | 255 | 128-bit | Bernstein's curve; key exchange; constant-time |
| Ed25519 | 255 | 128-bit | Bernstein's curve; signatures; deterministic |
| secp256k1 | 256 | 128-bit | Bitcoin; NOT recommended for general use |

**Why 256-bit ECC ≈ 3072-bit RSA security:**
- Best ECC attack: Pollard's rho — O(√n) = O(2^128) for 256-bit curve
- Best RSA attack: GNFS — sub-exponential ~O(exp((64/9)^(1/3) × (log n)^(1/3)))
- At 256 ECC bits vs 3072 RSA bits, both require ~2^128 operations to break

---

### ECDSA vs Ed25519

| Property | ECDSA | Ed25519 |
|---|---|---|
| Curve | P-256, P-384, secp256k1 | Curve25519 (twisted Edwards) |
| Signature type | Probabilistic (requires random `k`) | Deterministic (RFC 8032) |
| Bad-RNG vulnerability | **Yes** — reusing `k` reveals private key | **No** — `k` derived deterministically from message + private key |
| Real exploit | Sony PS3 (2010): constant `k` used for all signatures | — |
| Signature size | 64 bytes (P-256) | 64 bytes |
| Verification speed | Slower | 2× faster than ECDSA P-256 |
| Adoption | TLS 1.3, FIDO2, code signing | SSH, TLS, Noise Protocol, Signal |

**Recommendation:** Prefer **Ed25519** for new systems. Use ECDSA P-256 when FIPS compliance requires it.

---

### Hybrid Encryption

**Why you never encrypt bulk data with RSA:**
- RSA-OAEP maximum plaintext size = `keysize/8 - 2×hashsize - 2 = 190 bytes` for RSA-2048 with SHA-256
- RSA is 100-1000× slower than AES for bulk data

**The correct pattern (used in TLS, PGP, S/MIME):**

```
1. Generate random DEK (Data Encryption Key) = 256-bit AES-GCM key
2. Encrypt data with DEK → ciphertext
3. Encrypt DEK with recipient's RSA public key (OAEP) → wrapped_key
4. Send: { wrapped_key, ciphertext, nonce }

Recipient:
5. Decrypt wrapped_key with RSA private key → DEK
6. Decrypt ciphertext with DEK + nonce → plaintext
```

**In TLS 1.3:** Uses ECDHE (key agreement) instead of RSA encryption, which provides forward secrecy. The shared ECDHE secret is fed into HKDF to derive symmetric keys for the session.

---

## Part C: Hash Functions and MACs

### Cryptographic Hash Properties

| Property | Definition | Broken by |
|---|---|---|
| **Pre-image resistance** | Given `h`, cannot find `m` such that `H(m) = h` | — |
| **Second pre-image resistance** | Given `m`, cannot find `m'≠m` such that `H(m') = H(m)` | — |
| **Collision resistance** | Cannot find any `m, m'` with `H(m) = H(m')` | MD5 (2004), SHA-1 (2017 SHAttered) |

### SHA-2 vs SHA-3

| Property | SHA-256 (SHA-2 family) | SHA-3-256 (Keccak) |
|---|---|---|
| Construction | Merkle-Damgård | Sponge |
| Length extension attack | **Vulnerable** (without HMAC wrapping) | Immune |
| Output size | 256-bit | 256-bit |
| Speed | Fast (AES-NI helps on some hardware) | Slightly slower |
| Adoption | TLS, JWT, Git, Bitcoin | Ethereum, post-quantum candidates |

**Length extension attack (SHA-2):** Given `H(secret || msg)` and `len(secret)`, attacker can compute `H(secret || msg || padding || extension)` without knowing `secret`. Fix: use HMAC.

---

### HMAC

**Construction:** `HMAC(K, m) = H((K ⊕ opad) || H((K ⊕ ipad) || m))`

- Two-pass construction — immune to length extension
- Security depends on the underlying hash's collision resistance
- `HMAC-SHA256` is the standard for JWT `HS256` and API request signing

```python
import hmac, hashlib, os

secret = os.urandom(32)
message = b"canonical_request"

mac = hmac.new(secret, message, hashlib.sha256).digest()
# Verify (timing-safe):
is_valid = hmac.compare_digest(mac, received_mac)  # NOT == operator
```

**Why `==` leaks timing info:** String comparison returns early on first mismatch → attacker can brute-force byte-by-byte. `hmac.compare_digest` uses constant-time comparison.

---

### Password Hashing: bcrypt, scrypt, Argon2

**Why MD5/SHA-256 is insufficient for passwords:**

```
NVIDIA RTX 4090: 100 billion MD5 hashes/second
bcrypt (cost=12): ~300 hashes/second per GPU
Argon2id (64MB, 3 iter): ~15 hashes/second per GPU
```

**bcrypt:**
- Based on Blowfish cipher's key schedule (expensive initialization)
- Cost factor: `2^cost` iterations; cost=12 → 4096 iterations
- Output includes salt: `$2b$12$[22-char-salt][31-char-hash]`
- **Limitation:** max 72-byte password (silently truncates beyond that — use pre-hashing if needed)

**Argon2id (OWASP 2024 recommendation):**
- Three variants: Argon2**d** (GPU-resistant, time-hard), Argon2**i** (side-channel resistant, memory-hard), Argon2**id** (both — hybrid)
- Parameters: `m` (memory in KB), `t` (iterations), `p` (parallelism), `salt` (16 bytes random), `hash_length` (32 bytes)
- **OWASP minimum:** `m=64MB, t=3, p=1`
- **Why memory-hard matters:** GPU/ASIC advantage vanishes when algorithm requires GBs of RAM

```python
# Argon2id in Python
from argon2 import PasswordHasher

ph = PasswordHasher(
    time_cost=3,        # iterations
    memory_cost=65536,  # 64 MB
    parallelism=1,
    hash_len=32,
    salt_len=16
)

hash = ph.hash("user_password")
is_valid = ph.verify(hash, "user_password")  # raises exception if invalid
```

---

### Key Derivation Functions

| KDF | Use Case | Construction |
|---|---|---|
| **PBKDF2** | Password → key (NIST approved) | HMAC iterations; 600,000+ for SHA-256 (NIST 2023) |
| **bcrypt** | Password storage | Blowfish key schedule |
| **scrypt** | Password storage, memory-hard | PBKDF2 + sequential memory-hard mixing |
| **Argon2id** | Password storage (recommended) | Memory-hard + side-channel resistant |
| **HKDF** | Session key derivation from shared secret | Extract (HMAC-hash → PRK) + Expand (PRK → output keys) |

**HKDF usage (TLS, Signal, Noise):**
```
HKDF-Extract(salt, IKM) → PRK
HKDF-Expand(PRK, info, L) → OKM (output key material)
```
TLS 1.3 uses HKDF to derive handshake keys and application keys from the ECDHE shared secret.

---

### Digital Signatures

**Concept:** Binds a message to an identity via the signer's private key.

```
Sign:   signature = sign(private_key, hash(message))
Verify: valid = verify(public_key, hash(message), signature)
```

**Why sign the hash, not the message:**
1. RSA/ECDSA operate on fixed-size inputs
2. Hashing with SHA-256 first ensures the signature covers the entire message

**Algorithm comparison:**

| Algorithm | Security | Signature Size | Deterministic | Notes |
|---|---|---|---|---|
| RSA-PSS-2048 | 112-bit | 256 bytes | No | Requires OAEP padding; slow |
| ECDSA P-256 | 128-bit | 64 bytes | No | Bad RNG = private key leak |
| Ed25519 | 128-bit | 64 bytes | **Yes** | **Recommended**; fast; immune to RNG attacks |
| RSA-PSS-4096 | 140-bit | 512 bytes | No | Overkill for most use cases |

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Symmetric cipher | AES-256-GCM | ChaCha20-Poly1305 | AES-256-GCM if AES-NI available; else ChaCha20 |
| Asymmetric for encryption | RSA-OAEP-3072 | ECDH X25519 | ECDH (forward secrecy, smaller keys, faster) |
| Signatures | ECDSA P-256 | Ed25519 | Ed25519 (deterministic, faster, no RNG risk) |
| Password hashing | bcrypt cost=12 | Argon2id 64MB/3 | Argon2id (memory-hard, more configurable) |
| Session key derivation | PBKDF2 | HKDF | HKDF for key material; PBKDF2 for passwords (NIST) |

---

## FAANG Interview Callout

> **Common interview questions on cryptography:**

**Q: "Why can't you use RSA to encrypt a 1GB file?"**
→ RSA max plaintext = 190 bytes (RSA-2048, OAEP-SHA256). Use hybrid encryption: random AES-256-GCM key for the file, RSA-OAEP to wrap the AES key.

**Q: "What's wrong with storing passwords as SHA-256(password)?"**
→ SHA-256 is fast (10^10 hashes/sec on GPU) → rainbow tables and brute force are trivial. Use Argon2id: slow (intentionally), memory-hard (defeats GPU/ASIC), per-user salt (defeats precomputation).

**Q: "You're rotating JWT signing keys. How do you avoid downtime?"**
→ Use asymmetric RS256/EdDSA: publish new public key to JWK endpoint with a new `kid`. Old tokens reference old `kid`; new tokens reference new `kid`. Validators check `kid` → fetch the matching public key. Old key stays in JWK endpoint until all old tokens expire.

**Q: "A developer wants to use ECB mode for encrypting user records. What do you say?"**
→ ECB is deterministic: identical plaintext blocks → identical ciphertext blocks. Classic attack: ECB penguin (encrypted Linux Tux image retains visible structure). Use AES-256-GCM: authenticated, randomized via nonce, no pattern leakage.

**Q: "Explain forward secrecy and why TLS 1.3 mandates it."**
→ Forward secrecy: ephemeral key agreement (ECDHE) generates a fresh session key per connection. If server's long-term private key is compromised later, past session keys cannot be reconstructed. TLS 1.3 removed all non-forward-secret key exchange methods (static RSA key exchange).
