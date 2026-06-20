# SSH Keys and the SSH Protocol

> **Principal Engineer Reference** — covers SSH protocol internals, key types, authentication flows, ssh-agent, tunneling, SSH Certificate Authorities, and server hardening.

---

## Part A: SSH Protocol Architecture

### Protocol Layers (RFC 4251–4254)

```
┌─────────────────────────────────────────────┐
│  SSH Connection Protocol (RFC 4254)         │  Multiplexed channels: shells, forwarding
├─────────────────────────────────────────────┤
│  SSH User Authentication Protocol (RFC 4252)│  publickey, password, keyboard-interactive
├─────────────────────────────────────────────┤
│  SSH Transport Protocol (RFC 4253)          │  Encryption, MAC, compression, key exchange
├─────────────────────────────────────────────┤
│  TCP/IP                                     │  Default port 22
└─────────────────────────────────────────────┘
```

**SSH Transport Protocol responsibilities:**
1. **Algorithm negotiation:** client and server exchange lists of supported algorithms for key exchange, encryption, MAC, compression → pick the first common algorithm
2. **Key exchange (KEX):** Diffie-Hellman (classic) or Curve25519-SHA256 (modern) → session keys
3. **Host key verification:** server proves identity via its host key; client checks `known_hosts`
4. **Encryption + MAC:** all subsequent traffic encrypted and integrity-protected

**Typical algorithm negotiation result (modern client/server):**
```
kex_algorithm: curve25519-sha256
host_key_algorithm: ssh-ed25519
cipher: chacha20-poly1305@openssh.com
mac: implicit (AEAD — chacha20-poly1305 provides auth)
compression: none (or zlib@openssh.com after auth)
```

---

## Part B: SSH Key Types

### Key Type Comparison

| Algorithm | Key Size | Security | Generation | Notes |
|---|---|---|---|---|
| RSA | 4096-bit | 140-bit | `ssh-keygen -t rsa -b 4096` | Legacy; large keys; still widely supported |
| ECDSA | P-256 (256-bit) | 128-bit | `ssh-keygen -t ecdsa -b 256` | Probabilistic signature; bad RNG = key compromise |
| **Ed25519** | 255-bit | 128-bit | `ssh-keygen -t ed25519` | **Recommended**; deterministic; fast; small |
| ECDSA-SK / Ed25519-SK | 256-bit | 128-bit | `ssh-keygen -t ed25519-sk` | Backed by FIDO2 hardware key |

**Why Ed25519 is the default recommendation:**
- **Deterministic signatures** (no random k needed) → immune to Sony PS3-style attacks
- Fastest signature algorithm (verification: 77,000/sec on commodity hardware)
- Smallest key and signature size
- Curve25519 designed for resistance to timing side-channels

---

### Key Generation and File Format

```bash
# Generate Ed25519 key pair
ssh-keygen -t ed25519 -C "user@example.com" -f ~/.ssh/id_ed25519

# Output:
# ~/.ssh/id_ed25519       ← private key (PEM, optionally passphrase-encrypted)
# ~/.ssh/id_ed25519.pub   ← public key
```

**Private key format (OpenSSH private key format):**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtz...
-----END OPENSSH PRIVATE KEY-----
```
When passphrase-protected: key material encrypted with AES-256-CTR, key derived from passphrase via bcrypt (not PBKDF2 — stronger). Use `-a 100` for 100 KDF rounds.

**Public key format (single line):**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@example.com
            └── base64(key_type_len + key_type + key_material)
```

**`authorized_keys` file (on server):**
```
# ~/.ssh/authorized_keys on remote server
ssh-ed25519 AAAAC3Nza... user@laptop
ssh-ed25519 AAAAC3Nzb... user@workstation deploy-bot@ci
```
One public key per line. Prefix with options:
```
no-port-forwarding,no-X11-forwarding,command="/bin/backup.sh" ssh-ed25519 AAAA... backup-key
```

**`known_hosts` file (on client):**
```
# ~/.ssh/known_hosts
server.example.com ecdsa-sha2-nistp256 AAAAE2VjZH...
|1|hashed_hostname|hashed_key  (hashed format via HashKnownHosts yes)
```

---

## Part C: Authentication Flows

### Public Key Authentication (Challenge-Response)

```
Client                              Server
  │                                   │
  │── SSH_MSG_USERAUTH_REQUEST ──────► │
  │   method: "publickey"             │
  │   public_key: ed25519 key         │
  │   signature: Sign(priv_key,       │
  │     session_id || "publickey"     │
  │     || username || service        │
  │     || algorithm || public_key)   │
  │                                   │
  │  Server: check public_key in      │
  │          authorized_keys          │
  │          verify signature         │
  │◄─ SSH_MSG_USERAUTH_SUCCESS ─────── │
```

**One-step (no pre-check):** client sends key + signature immediately (modern OpenSSH default). The server verifies the `authorized_keys` lookup and signature in one step.

**Two-step (legacy pre-check):**
1. Client sends public key only (no signature) with `partial: false`
2. Server responds with `SSH_MSG_USERAUTH_PK_OK` if key is acceptable
3. Client sends signature → server verifies

---

### Password Authentication

```
Client                              Server
  │── SSH_MSG_USERAUTH_REQUEST ──────► │
  │   method: "password"              │
  │   password: "hunter2" (encrypted  │
  │   by the SSH transport layer)     │
  │◄─ SSH_MSG_USERAUTH_SUCCESS ─────── │
```

**Disable in production:** password auth allows brute force attacks. Always disable:
```
# /etc/ssh/sshd_config
PasswordAuthentication no
ChallengeResponseAuthentication no
```

---

## Part D: ssh-agent

### Purpose and Architecture

`ssh-agent` is a daemon that holds decrypted private keys in memory, acting as a signing oracle. The SSH client communicates with it via Unix socket (`$SSH_AUTH_SOCK`).

```bash
eval "$(ssh-agent -s)"           # start agent, set SSH_AUTH_SOCK
ssh-add ~/.ssh/id_ed25519        # load key (prompts for passphrase once)
ssh-add -l                       # list loaded keys
ssh-add -d ~/.ssh/id_ed25519.pub # remove key
ssh-add -D                       # remove all keys
```

**Security benefit:** Private key passphrase entered once; agent holds the decrypted key in locked memory. SSH client requests signatures via socket; private key material never leaves the agent process.

**`AddKeysToAgent yes` in `~/.ssh/config`:** automatically adds key on first use.
**`IdentitiesOnly yes`:** prevents agent from trying all loaded keys (useful for multiple hosts).

---

### Agent Forwarding (`-A` flag)

**What it does:** Forwards `SSH_AUTH_SOCK` to remote server. From the remote server, you can use your local keys to authenticate to a third server.

```
Laptop → Server A (with -A) → Server B
Laptop's agent handles signing for Server B connection
```

**Risks:**
- Anyone with root on Server A can use your agent socket → sign with your keys
- `ForwardAgent` should only be trusted to servers you fully control

**Safer alternative: SSH ProxyJump:**
```bash
# Instead of agent forwarding, use ProxyJump to "hop" through Server A
ssh -J user@serverA user@serverB
# Or in ~/.ssh/config:
Host serverB
    ProxyJump user@serverA
```
ProxyJump creates an SSH tunnel but does NOT expose the agent to intermediate servers.

---

## Part E: SSH Tunneling

### Local Port Forwarding (`-L`)

**Use case:** Access a service on a remote network as if it were local.

```bash
# Tunnel local:8080 → remote:80
ssh -L 8080:internal-service:80 bastion.example.com

# Local application connects to localhost:8080
# Traffic forwarded to internal-service:80 via bastion
```

```
Laptop:8080 → SSH tunnel → bastion → internal-service:80
```

**Common uses:** Access database, internal web UI, Kubernetes API server behind bastion.

---

### Remote Port Forwarding (`-R`)

**Use case:** Expose a local service to the remote server.

```bash
# Expose local:3000 as remote:9000
ssh -R 9000:localhost:3000 bastion.example.com
```

**Common use:** Webhook development (receive webhooks on local dev machine); IoT device callback.

---

### Dynamic SOCKS Proxy (`-D`)

```bash
ssh -D 1080 bastion.example.com  # SOCKS5 proxy on localhost:1080
# Configure browser to use SOCKS5 proxy → all traffic routed via bastion
```

**Use case:** Browse internal resources; all DNS queries go through remote too (prevent DNS leaks).

---

## Part F: SSH Certificate Authorities

### The Problem with `authorized_keys`

In a large organization, managing `authorized_keys` files across thousands of servers is operationally painful:
- Adding a new user → update `authorized_keys` on every server
- Revoking access → find and remove key from every server
- No expiration → long-lived credentials

**Solution: SSH Certificate Authority**

### SSH CA Setup

```bash
# 1. Create CA key pair (keep private key very secure)
ssh-keygen -t ed25519 -f /etc/ssh/ca_key -C "org-ssh-ca"

# 2. Configure all servers to trust this CA
# In /etc/ssh/sshd_config:
TrustedUserCAKeys /etc/ssh/ca_key.pub
```

### Issuing User Certificates

```bash
# Sign a user's public key with the CA
ssh-keygen -s /etc/ssh/ca_key \
  -I "user:alice" \               # identity (logged in sshd)
  -n alice,ubuntu \               # principals (allowed usernames)
  -V +8h \                        # validity: 8 hours
  ~/.ssh/id_ed25519.pub

# Output: ~/.ssh/id_ed25519-cert.pub
```

**Certificate contents:**
```
Type: ssh-ed25519-cert-v01@openssh.com user certificate
Public key: ED25519-CERT
Signing CA: ED25519 SHA256:...
Key ID: "user:alice"
Serial: 42
Valid: from 2024-01-01T10:00:00 to 2024-01-01T18:00:00  (8 hours)
Principals: alice, ubuntu
Critical Options: (none)
Extensions: permit-pty, permit-user-rc, permit-port-forwarding
```

**Authentication with certificate:**
```bash
ssh -i ~/.ssh/id_ed25519 -i ~/.ssh/id_ed25519-cert.pub user@server
# Or: ssh-add ~/.ssh/id_ed25519-cert.pub  (agent picks up cert automatically)
```

**Advantages over `authorized_keys`:**
- **No per-server configuration:** add one CA public key to all servers, done
- **Expiry built-in:** 8-hour cert → compromise window is 8 hours
- **Revocation:** For early revocation, use `RevokedKeys` file (principals or serial numbers)
- **Audit trail:** `KeyID` appears in sshd logs → trace back to issuance request
- **Principals:** limit which usernames a cert can authenticate as

---

## Part G: Server Hardening

### `sshd_config` Hardening Checklist

```ini
# /etc/ssh/sshd_config — hardened configuration

# Disable password authentication
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Disable root login
PermitRootLogin no

# Restrict to specific users/groups
AllowGroups ssh-users
# AllowUsers alice bob deploy-bot@192.168.1.0/24

# SSH protocol
Protocol 2

# Strong key exchange algorithms only
KexAlgorithms curve25519-sha256,ecdh-sha2-nistp521,diffie-hellman-group16-sha512

# Strong host key algorithms
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# Modern ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com

# Modern MACs (AEAD ciphers make MACs redundant, but for non-AEAD:)
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Connection limits
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30

# Disable unnecessary features
X11Forwarding no
AllowAgentForwarding no  # Only enable on jump hosts
AllowTcpForwarding no    # Only enable if needed

# Disconnect idle clients
ClientAliveInterval 300
ClientAliveCountMax 2

# Use SSH CA (if deployed)
TrustedUserCAKeys /etc/ssh/ca_key.pub
```

**Additional hardening:**
- `fail2ban` or `sshguard`: ban IPs after N failed attempts
- **Port obscurity** (security theater, not security): changing port 22 → 22000 reduces scan noise but not determined attacks
- **Port knocking**: firewall blocks SSH; sequence of TCP packets on specific ports opens port temporarily

---

## Trade-offs Summary

| Decision | Option A | Option B | Recommendation |
|---|---|---|---|
| Key algorithm | RSA-4096 | Ed25519 | Ed25519 (faster, smaller, deterministic) |
| Key management | `authorized_keys` | SSH Certificate Authority | SSH CA for >10 servers |
| Certificate validity | 1 year | 8 hours | Short-lived (hours) + automated issuance |
| Agent forwarding | `-A` flag | ProxyJump (`-J`) | ProxyJump — agent never exposed to hop host |
| Jump host access | Agent forwarding | Bastion + ProxyJump | ProxyJump via bastion (no agent exposure) |

---

## FAANG Interview Callout

> **SSH questions at principal level:**

**Q: "You're onboarding 500 engineers onto a new fleet of 2000 servers. How do you manage SSH access?"**
→ SSH Certificate Authority: deploy CA public key to all servers via config management (Ansible/Chef). Integrate CA signing with internal IdP (OIDC → CA signs 8h cert). Engineer runs `ssh-cert-login` → authenticates via browser SSO → receives short-lived cert. No per-server `authorized_keys`. Revocation via time expiry + PKI-managed `RevokedKeys` list for emergencies.

**Q: "An engineer left the company. How do you revoke their SSH access?"**
→ With `authorized_keys`: update all servers (days/weeks of operational work). With SSH CA + short-lived certs: do nothing — 8h cert expires automatically. If using long-lived certs, add serial/principal to `RevokedKeys` file on all servers (config management). De-provision IdP account → no new certs can be issued.

**Q: "Explain ProxyJump vs agent forwarding for bastion host access."**
→ Agent forwarding (`-A`) forwards the agent socket to the bastion host; root on bastion can use your agent. ProxyJump creates an encrypted SSH tunnel through the bastion but your agent never touches the bastion; the connection to the target server is negotiated end-to-end from your laptop. ProxyJump is strictly more secure for multi-hop scenarios.
