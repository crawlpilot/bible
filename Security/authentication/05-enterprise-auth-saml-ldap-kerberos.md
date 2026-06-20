# Enterprise Authentication: SAML 2.0, LDAP/Active Directory, and Kerberos

> **Principal Engineer Reference** — covers enterprise identity protocols used in B2B SaaS, corporate networks, and legacy systems. Includes attack analysis for each protocol and migration paths to modern alternatives.

---

## Part A: SAML 2.0

### What SAML Solves

SAML 2.0 (Security Assertion Markup Language) enables **cross-domain SSO** between organizations. An enterprise employee authenticates with their company's Identity Provider (IdP — e.g., Okta, Azure AD) and is granted access to external SaaS applications (Service Providers) without re-entering credentials.

### Components

| Role | Description | Example |
|---|---|---|
| **Identity Provider (IdP)** | Authenticates users; issues SAML assertions | Okta, Azure AD, ADFS, Ping Identity |
| **Service Provider (SP)** | Relies on IdP for authentication; grants access | Salesforce, GitHub, your SaaS app |
| **User Agent** | Browser mediating the redirect flow | Chrome, Safari |

---

### SP-Initiated Flow (Most Common)

```
User          Browser                  Service Provider (SP)         Identity Provider (IdP)
 │                │                          │                                │
 │── Access ─────►│                          │                                │
 │                │── GET /resource ─────────►│                                │
 │                │                          │ (no session → initiate SSO)    │
 │                │◄─ 302 with SAMLRequest ──│                                │
 │                │   Location: IdP/sso?SAMLRequest=BASE64_DEFLATE_XML        │
 │                │                                                            │
 │                │───────────────────────────────────────────────────────────►│
 │◄─ Login page ──│◄───────────────────────────────────────────────────────────│
 │── Credentials ►│───────────────────────────────────────────────────────────►│
 │                │                                                            │
 │                │◄── HTML form with SAMLResponse (base64 XML) ───────────────│
 │                │    (auto-submits via JavaScript POST)                      │
 │                │── POST /acs (Assertion Consumer Service) ──────────────────►│
 │                │   SAMLResponse=BASE64_ENCODED_XML                          │
 │                │                          │ (validate, create session)     │
 │◄─ Redirect ────│◄─────────────────────────│                                │
 │   to resource  │                          │                                │
```

**SP builds AuthnRequest:**
```xml
<samlp:AuthnRequest
    xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
    ID="_unique_request_id"
    Version="2.0"
    IssueInstant="2024-01-01T10:00:00Z"
    Destination="https://idp.example.com/sso"
    AssertionConsumerServiceURL="https://sp.example.com/acs"
    ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST">
  <saml:Issuer>https://sp.example.com</saml:Issuer>
</samlp:AuthnRequest>
```
Compressed with DEFLATE, Base64-encoded, sent as `SAMLRequest` query parameter.

---

### SAML Assertion Structure

```xml
<samlp:Response InResponseTo="_unique_request_id"
                IssueInstant="2024-01-01T10:00:05Z">
  <saml:Issuer>https://idp.example.com</saml:Issuer>
  <samlp:Status>
    <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/>
  </samlp:Status>
  <saml:Assertion ID="_assertion_id" IssueInstant="...">
    <saml:Issuer>https://idp.example.com</saml:Issuer>
    <ds:Signature>...</ds:Signature>              <!-- XML DSig on Assertion -->

    <saml:Subject>
      <saml:NameID Format="urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress">
        alice@enterprise.com
      </saml:NameID>
      <saml:SubjectConfirmation Method="...bearer">
        <saml:SubjectConfirmationData
          InResponseTo="_unique_request_id"        <!-- ties to AuthnRequest -->
          NotOnOrAfter="2024-01-01T10:05:00Z"      <!-- assertion valid 5 min -->
          Recipient="https://sp.example.com/acs"/> <!-- must match SP ACS URL -->
      </saml:SubjectConfirmation>
    </saml:Subject>

    <saml:Conditions
      NotBefore="2024-01-01T09:59:55Z"
      NotOnOrAfter="2024-01-01T10:05:00Z">
      <saml:AudienceRestriction>
        <saml:Audience>https://sp.example.com</saml:Audience>
      </saml:AudienceRestriction>
    </saml:Conditions>

    <saml:AuthnStatement AuthnInstant="2024-01-01T10:00:03Z">
      <saml:AuthnContext>
        <saml:AuthnContextClassRef>
          urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport
        </saml:AuthnContextClassRef>
      </saml:AuthnContext>
    </saml:AuthnStatement>

    <saml:AttributeStatement>
      <saml:Attribute Name="email">
        <saml:AttributeValue>alice@enterprise.com</saml:AttributeValue>
      </saml:Attribute>
      <saml:Attribute Name="groups">
        <saml:AttributeValue>Engineering</saml:AttributeValue>
        <saml:AttributeValue>JIRA-Admins</saml:AttributeValue>
      </saml:Attribute>
    </saml:AttributeStatement>
  </saml:Assertion>
</samlp:Response>
```

---

### SP Validation Checklist

```
1. Verify XML signature (XML DSig) on Assertion using IdP's public certificate
2. Verify InResponseTo == the request ID we sent (prevents unsolicited assertions)
3. Verify Issuer == expected IdP entity ID
4. Verify AudienceRestriction contains our SP entity ID
5. Verify NotBefore ≤ now ≤ NotOnOrAfter (clock skew: ±2 min)
6. Verify SubjectConfirmationData.Recipient == our ACS URL
7. Check assertion has not been replayed (cache assertion IDs for lifetime of assertion)
```

**Common SAML vulnerabilities:**
- **Assertion replay:** no `AssertionID` replay cache → same assertion accepted multiple times
- **Signature wrapping attacks (XSW):** XML DSig validates only part of the document; attacker wraps a malicious assertion around the valid signed assertion
- **Missing audience validation:** assertion for another SP accepted
- **Comment injection attacks:** `al<!-- comment -->ice@example.com` parses differently in different XML parsers

---

### IdP-Initiated Flow (Security Concern)

IdP sends assertion without prior AuthnRequest → no `InResponseTo` to validate. SP cannot verify the assertion was triggered by a legitimate user request.

**Risk:** If attacker can trigger IdP-initiated flow with a crafted assertion (e.g., IdP misconfiguration), SP must accept it.

**Mitigation:** Prefer SP-initiated flow; if IdP-initiated required, implement additional state validation.

---

### SAML vs OIDC

| Property | SAML 2.0 | OIDC (OAuth 2.0 + Identity) |
|---|---|---|
| Format | XML | JSON (JWT) |
| Transport | Browser redirects (FORM POST) | Browser redirects + REST API |
| Token type | XML Assertion | JWT (id_token) |
| Signing | XML DSig (complex, attack surface) | JWT signature (simpler) |
| Mobile support | Poor (XML POST in browser) | Excellent (JSON, PKCE) |
| Discovery | Federation metadata XML | `/.well-known/openid-configuration` |
| Adoption | Legacy enterprise, Salesforce, etc. | Modern apps, mobile, APIs |
| When to use | Existing enterprise IdP (ADFS); B2B with no choice | New systems, modern IdPs, APIs |

---

## Part B: LDAP and Active Directory

### LDAP Protocol Basics

LDAP (Lightweight Directory Access Protocol) is a hierarchical directory service over TCP/IP.

```
Port 389: LDAP (plaintext)
Port 636: LDAPS (TLS)
Port 389 + StartTLS: upgrade to TLS after connection
```

**Directory Information Tree (DIT):**
```
DC=example,DC=com                    ← domain root (DC = Domain Component)
├── OU=Engineering                   ← Organizational Unit
│   ├── CN=Alice Smith              ← user (CN = Common Name)
│   ├── CN=Bob Jones
│   └── CN=Dev-Leads                ← group
│       (member: CN=Alice Smith,OU=Engineering,DC=example,DC=com)
├── OU=Finance
└── OU=ServiceAccounts
    └── CN=deploy-bot
```

**Distinguished Name (DN):** Full path to an LDAP entry.
`CN=Alice Smith,OU=Engineering,DC=example,DC=com`

---

### LDAP Operations

| Operation | Description |
|---|---|
| **Bind** | Authenticate to LDAP server (simple bind: DN + password; SASL for Kerberos) |
| **Search** | Query directory; filter + base DN + scope |
| **Add** | Create new entry |
| **Modify** | Update attributes |
| **Delete** | Remove entry |
| **ModifyDN** | Rename/move entry |
| **Compare** | Check if attribute matches value |
| **Unbind** | End session |

### LDAP Search Filter Syntax

```python
# Find user by email
filter = "(mail=alice@example.com)"

# Find all users in Engineering group (direct members)
filter = "(&(objectClass=user)(memberOf=CN=Engineering,OU=Groups,DC=example,DC=com))"

# Find all enabled users
filter = "(&(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
# AD flag: userAccountControl bit 1 = disabled

# Nested group membership (AD-specific OID)
filter = "(memberOf:1.2.840.113556.1.4.1941:=CN=Admins,OU=Groups,DC=example,DC=com)"
```

---

### Active Directory Schema

**Key AD object classes:**

| Class | Attributes | Notes |
|---|---|---|
| `user` | sAMAccountName, mail, userPrincipalName, memberOf, userAccountControl | Standard user account |
| `group` | cn, member, memberOf, groupType | Security or Distribution group |
| `computer` | cn, dNSHostName, operatingSystem | Domain-joined machine |
| `organizationalUnit` | ou, description | Container for objects |

**AD group types:**

| Type | Purpose | Scope |
|---|---|---|
| **Security group** | Access control (ACLs, RBAC) | Universal / Global / Domain Local |
| **Distribution group** | Email distribution lists | Universal / Global |

**Group scope:**

| Scope | Can contain members from | Can be used in ACLs on |
|---|---|---|
| **Domain Local** | Any domain, universal/global groups | Same domain only |
| **Global** | Same domain only | Any domain |
| **Universal** | Any domain | Any domain |

---

### AD Group Nesting and Token Bloat

**The problem:** Kerberos service tickets include the PAC (Privilege Attribute Certificate) containing all group SIDs for the user. Every nested group is included.

```
User Alice is a member of:
  Engineering → Dev-Team → Squad-A → Frontend-Lead → Code-Reviewers → ...

Kerberos PAC size grows with each group.
Windows max token size: ~65KB
```

**Symptoms of token bloat:**
- Users cannot authenticate to certain services
- "Authentication failed" errors after adding many group memberships
- HTTP 400 errors (oversized request headers when token sent in Authorization)

**Mitigations:**
- **Active Directory:** increase MaxTokenSize registry key (default 12KB → 65KB)
- **Application level:** query LDAP for group membership at login instead of relying on PAC
- **Design:** flatten group hierarchy; avoid deep nesting chains
- **JWT approach:** include only application-relevant roles in JWT (not all AD groups)

---

### LDAP Authentication Flow in an Application

```
1. User submits credentials (username + password) to app
2. App binds to LDAP with service account (read-only):
   ldap.bind("CN=app-svc,OU=ServiceAccounts,DC=example,DC=com", svc_password)
3. App searches for user DN:
   base_dn = "OU=Engineering,DC=example,DC=com"
   filter = f"(&(objectClass=user)(sAMAccountName={username}))"
   result = ldap.search(base_dn, filter)
4. App rebinds with user's DN + submitted password:
   ldap.bind(result.dn, submitted_password)  ← this validates the password
5. On success: fetch group memberships
   filter = "(memberOf=CN=App-Users,OU=Groups,DC=example,DC=com)"
```

**LDAP injection risk:**
```python
# VULNERABLE — never concatenate user input into LDAP filter
filter = f"(sAMAccountName={username})"
# username = "*)(|(password=*))" → retrieves all users

# SAFE — escape special characters
from ldap3.utils.conv import escape_filter_chars
safe_username = escape_filter_chars(username)
filter = f"(sAMAccountName={safe_username})"
```

---

## Part C: Kerberos

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Key Distribution Center (KDC) — usually the Domain Controller  │
│                                                                  │
│  ┌────────────────────────┐  ┌──────────────────────────────┐   │
│  │ Authentication Service │  │ Ticket Granting Service (TGS)│   │
│  │ (AS)                   │  │                              │   │
│  │ Issues Ticket Granting │  │ Issues Service Tickets       │   │
│  │ Tickets (TGTs)         │  │ for specific services        │   │
│  └────────────────────────┘  └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Kerberos principals:** `alice@EXAMPLE.COM` (user), `HTTP/web.example.com@EXAMPLE.COM` (service)
**Symmetric key model:** KDC shares a long-term key with every principal (derived from password for users).

---

### Authentication Flow (6 Steps)

```
Client (Alice)                KDC / AS                  KDC / TGS              Service
    │                              │                          │                    │
    │── 1. AS-REQ ─────────────►  │                          │                    │
    │   {principal: alice,         │                          │                    │
    │    timestamp: encrypted      │                          │                    │
    │    with Alice's key}         │                          │                    │
    │                              │ (verify Alice's key,     │                    │
    │                              │  create TGT)             │                    │
    │◄─ 2. AS-REP ─────────────── │                          │                    │
    │   {TGT: encrypted with       │                          │                    │
    │    krbtgt key (opaque to     │                          │                    │
    │    Alice),                   │                          │                    │
    │    session_key_1: encrypted  │                          │                    │
    │    with Alice's key}         │                          │                    │
    │                              │                          │                    │
    │ Alice decrypts session_key_1 │                          │                    │
    │                              │                          │                    │
    │── 3. TGS-REQ ────────────────────────────────────────► │                    │
    │   {TGT (opaque),             │                          │                    │
    │    service: HTTP/web.example │                          │                    │
    │    authenticator: timestamp  │                          │                    │
    │    encrypted with session_key_1}                        │                    │
    │                              │                          │ (verify TGT,       │
    │                              │                          │  create service    │
    │                              │                          │  ticket)           │
    │◄─ 4. TGS-REP ────────────────────────────────────────── │                    │
    │   {service_ticket: encrypted │                          │                    │
    │    with service's key,       │                          │                    │
    │    session_key_2: encrypted  │                          │                    │
    │    with session_key_1}       │                          │                    │
    │                              │                          │                    │
    │── 5. AP-REQ ─────────────────────────────────────────────────────────────►│
    │   {service_ticket,           │                          │                    │
    │    authenticator: encrypted  │                          │                    │
    │    with session_key_2}       │                          │                    │
    │                              │                          │ (service decrypts  │
    │                              │                          │  ticket with its   │
    │                              │                          │  own key, verifies)│
    │◄─ 6. AP-REP (optional) ──────────────────────────────────────────────────── │
    │   (mutual auth: service      │                          │                    │
    │    proves it knows session key)                         │                    │
```

**Key observations:**
- Alice's password never traverses the network
- Service never communicates with KDC — validates ticket with its own pre-shared key
- TGT cached on client; valid 8-10 hours (typically); service tickets ~10 minutes

---

### Kerberos PAC (Privilege Attribute Certificate)

The PAC is embedded in service tickets. It contains:
- User's SID (Security Identifier)
- All group SIDs the user belongs to
- Sign with `krbtgt` key (AS signature) + service key (Server signature)
- Service uses this to authorize without calling DC for every request

---

### Kerberos Attacks

| Attack | Description | Mitigation |
|---|---|---|
| **Pass-the-Ticket (PtT)** | Steal TGT from memory (Mimikatz); use it as if you're the user | Credential Guard (isolates LSASS in Hyper-V); short TGT TTL |
| **Pass-the-Hash (PtH)** | Steal NTLM hash; authenticate without the plaintext password | Disable NTLM; enforce Kerberos; Protected Users group |
| **Kerberoasting** | Request service ticket for any SPN; crack the encrypted ticket offline (brute-force service password) | Service accounts with long random passwords; use Managed Service Accounts (MSA) |
| **AS-REP Roasting** | Request AS response for accounts with "Do not require Kerberos pre-authentication"; crack offline | Enforce pre-authentication for all users |
| **Golden Ticket** | Forge TGT using `krbtgt` account's hash; valid for any principal; bypasses all security | Rotate `krbtgt` password twice (flush old keys); detect via 4769 events with unusual PAC |
| **Silver Ticket** | Forge service ticket using service account hash; no KDC contact needed | Regularly rotate service account passwords; Privilege Attribute Certificate validation |
| **DCSync** | Use AD replication rights to pull all password hashes from DC | Restrict replication permissions; monitor for unusual DCSync traffic |

---

### Kerberoasting in Detail

```
Normal flow: Only the client requests a service ticket for services they need.

Kerberoasting:
1. Attacker is an authenticated domain user (low privilege)
2. Attacker requests TGS for ALL services with SPNs:
   GetTGSForService("MSSQLSvc/db.example.com@EXAMPLE.COM")
3. Receives service ticket encrypted with service account's hash (RC4-HMAC by default)
4. Offline brute-force: try passwords → encrypt with hash → compare
5. If service account password is weak (e.g., "Password1!") → cracked in minutes

Mitigation:
- Service accounts: 20+ random character passwords (or gMSA with auto-rotation)
- Request AES encryption for service tickets (harder to crack than RC4)
- Monitor for unusual TGS requests (4769 events with RC4 encryption)
```

---

### Modern Alternatives to Kerberos

| Scenario | Legacy (Kerberos) | Modern Alternative |
|---|---|---|
| Browser authentication | NTLM/Kerberos (Windows auth) | OIDC + FIDO2/Passkeys |
| API authentication | SPNEGO Kerberos header | OAuth 2.0 Bearer JWT |
| Service-to-service | Kerberos S4U2Proxy (constrained delegation) | SPIFFE/SPIRE mTLS |
| AD integration | Direct LDAP + Kerberos | LDAP → OIDC bridge (Azure AD, Okta) |

**Migration path:** AD FS (Active Directory Federation Services) can act as a SAML/OIDC IdP, federating AD identities into modern protocols.

---

## Trade-offs Summary

| Comparison | SAML 2.0 | OIDC | Kerberos |
|---|---|---|---|
| Protocol | XML over HTTPS | JSON/JWT over HTTPS | Binary over TCP |
| Use case | Enterprise B2B SSO | Modern web/mobile/API | Windows domain auth |
| Mobile support | Poor | Excellent | Limited (domain-joined only) |
| Attack surface | XSW, assertion replay | Token theft, PKCE bypass | PtT, Kerberoasting, Golden Ticket |
| Migration effort | High (XML, complex) | Low (standard libraries) | High (requires AD) |

---

## FAANG Interview Callout

**Q: "Explain how you'd federate 500 enterprise customers (each with their own AD/OIDC) into your SaaS."**
→ Use an OIDC federation hub (Keycloak, Auth0, Ping). Each enterprise customer configures their IdP (SAML or OIDC). Your hub acts as SP for their IdP and as IdP for your app. User is redirected based on their email domain (HRD — Home Realm Discovery). Hub issues your app's JWT with `tenant_id` from the assertion. Per-tenant RBAC mapped from AD groups → application roles.

**Q: "What is Kerberoasting and how would you detect it in a 10,000-user AD environment?"**
→ Kerberoasting: attacker requests TGS for accounts with SPNs to crack offline. Detection: monitor Event ID 4769 with RC4 encryption type (0x17) — AES requests are normal; RC4 requests for service accounts are suspicious. Alert on: new source requesting TGS for service accounts not previously accessed, bulk TGS requests within a short window. Mitigation: gMSA (Group Managed Service Accounts) with auto-rotated 240-char passwords.

**Q: "A user has AD group membership in 150 groups due to org complexity. What problems can this cause?"**
→ Kerberos PAC / Windows access token size limits. Default MaxTokenSize (12KB) holds ~160 group SIDs. Symptoms: authentication failures, HTTP 400 errors (header too large with Negotiate auth). Solutions: raise MaxTokenSize to 65KB (registry key + reboot); redesign group structure to reduce nesting depth; in your app, query LDAP directly for relevant groups rather than trusting PAC.
