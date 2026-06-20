# 05 — Compliance, Fraud Screening & Security

## 1. UIDAI / Aadhaar Integration Architecture

### 1.1 Integration Model

India's UIDAI permits two eKYC modes for Requesting Entities (RE):

| Mode | What RE receives | Biometric held by RE? | Use case in our system |
|---|---|---|---|
| **OTP-based eKYC** | Demographic XML (name, DOB, address, photo) over encrypted channel | No | Default for Wallet Full, Individual Savings |
| **Biometric eKYC** | Same as above | No (fingerprint/iris processed by AUA device) | EDD accounts; BC Agent channel |
| **Offline Aadhaar** (XML download) | User-downloaded XML with digital signature | No | Fallback if UIDAI API down |
| **DigiLocker** | OAuth-based document fetch | No | Alternate address/DOB proof |

**RE** = Requesting Entity (us, the bank). **AUA** = Authentication User Agency (we partner with a licensed AUA). We are a **KUA** (KYC User Agency).

### 1.2 Aadhaar OTP eKYC Flow

```
User App                 Onboarding Service           UIDAI ASA (Auth Server)
    │                          │                              │
    │  Enter Aadhaar UID ──────►│                              │
    │                          │  OTP Request (pid encrypted) │
    │                          │─────────────────────────────►│
    │                          │                              │ Generate OTP → SMS to user
    │  Enter OTP ──────────────►│                              │
    │                          │  Auth Request (OTP in pid)   │
    │                          │─────────────────────────────►│
    │                          │◄─────────────────────────────│
    │                          │  KycRes (encrypted XML)      │
    │                          │                              │
    │                          │ Decrypt with KUA private key │
    │                          │ Extract: name, DOB, addr, photo
    │                          │ Compute: SHA-256(UID+salt) → aadhaar_ref
    │                          │ Store:   aadhaar_ref, masked_aadhaar(XXXX1234)
    │                          │         name_verified=true (boolean)
    │                          │ DELETE:  raw UID, raw XML, raw photo immediately
    │                          │          (in-memory only, never persisted)
    │◄─────────────────────────│
    │  KYC verified (no raw data returned to client)
```

### 1.3 What We Store vs. What We Delete

| Data Element | Stored? | What We Store Instead | Legal Basis |
|---|---|---|---|
| Aadhaar Number (12 digits) | ❌ NEVER | SHA-256(UID + per-user salt) token | UIDAI Circular + Aadhaar Act §29 |
| Aadhaar XML | ❌ NEVER | — | UIDAI RE Agreement |
| Biometric (fingerprint/iris) | ❌ NEVER | — | UIDAI Act §29(1) |
| Aadhaar photo | ❌ (deleted post face-match) | Face-match result boolean | UIDAI Circular |
| Name | ✅ AES-256 encrypted | Encrypted blob + token | RBI KYC MD |
| DOB | ✅ AES-256 encrypted | Encrypted blob | RBI KYC MD |
| Address | ✅ AES-256 encrypted | Encrypted blob | RBI KYC MD |
| Masked Aadhaar (XXXX1234) | ✅ | Plain (non-sensitive) | UIDAI permits display |
| UIDAI transaction reference | ✅ | Audit trail only | UIDAI RE Agreement |
| VID (Virtual ID) | ✅ if provided | Replaces UID in communications | UIDAI Act |

### 1.4 Consent Flow (DPDPA 2023 §6 + Aadhaar Act §8(2)(b))

```
Before any Aadhaar-related step:
  1. Display: purpose of Aadhaar authentication in clear language
  2. Display: what data will be fetched, what will be stored, what will be deleted
  3. Require: explicit affirmative consent (checkbox, NOT pre-ticked)
  4. Record: consent_text_version, timestamp, user_id, channel, IP
  5. Store: consent record in immutable audit log (Kafka → Iceberg)

User can withdraw consent:
  ECA rule: ON CONSENT_WITHDRAWN →
    ANONYMISE_KYC_DATA (demographic fields → SHA-256 hash)
    RESTRICT_ACCOUNT (view-only)
    NOTIFY_COMPLIANCE (cannot delete records within PMLA retention period)
```

---

## 2. KRA / CKYC Integration

### 2.1 What is CKYC?

Central KYC Registry maintained by **CERSAI** (Central Registry of Securitisation Asset Reconstruction and Security Interest). Mandated by RBI: every RE must upload KYC data within 3 working days and look up existing records before collecting fresh documents.

```
CKYC Number: 14-digit unique identifier per individual
Benefits:
  - User doesn't need to re-submit documents across REs
  - RE fetches CKYC record, confirms identity, skips document collection
  - Reduces onboarding time from 5 min to < 2 min for returning customers
```

### 2.2 CKYC Lookup Flow

```
1. Trigger: after mobile OTP verification (we have name + DOB from user input, or PAN)
2. API call: CERSAI CKYC search by PAN or (name + DOB + mobile)
3. Response time SLA: < 200ms (CERSAI API)
4. Cache: CKYC lookup results cached in Redis (TTL = 24h, per PAN key)
5. On HIT:
     a. Fetch CKYC record (encrypted; decrypt with our KUA key)
     b. Pre-fill onboarding form with demographics
     c. Show user: "Your KYC is already on record — confirm details"
     d. User confirms → skip Steps 3-5 of KYC flow
     e. ECA: ON CKYC_FOUND → ADVANCE_LEAD_TO(KYC_COMPLETE)
6. On MISS:
     a. Proceed to full KYC flow
     b. After account created, schedule CKYC upload (T+3 working days)
```

### 2.3 CKYC Upload (T+3 days SLA)

```
ECA rule:
  ON ACCOUNT_ACTIVATED
  IF account.ckyc_uploaded == FALSE
  DO SCHEDULE_JOB(CKYC_UPLOAD, delay=3_working_days)

Upload job:
  1. Compile CKYC record: name, DOB, address, PAN, photo (from face-match)
  2. Encrypt with CERSAI public key
  3. Submit to CERSAI API
  4. Record: ckyc_number, upload_timestamp, status
  5. On failure: retry with exponential backoff; alert compliance team after 3 failures
  6. SLA monitor: daily job checks all accounts > 3 days old with ckyc_uploaded=false
```

---

## 3. Fraud & Blacklist Screening

### 3.1 Screening Architecture

Fraud screening is **synchronous and blocking** — no account is created until it passes.

```
┌──────────────────────────────────────────────────┐
│              Fraud Screening Service              │
│                                                  │
│  Input: FraudScreeningRequest {                  │
│    mobile_hash, device_fingerprint,              │
│    aadhaar_token, pan_token,                     │
│    name_hash, dob_hash,                          │
│    ip_address, geo_location,                     │
│    account_type, channel                         │
│  }                                               │
│                                                  │
│  Parallel checks (fan-out, 500ms total budget):  │
│  ┌──────────────────┐  ┌──────────────────────┐  │
│  │ Device Risk      │  │ Identity Dedup       │  │
│  │ (in-house ML)    │  │ (PAN/Aadhaar token   │  │
│  │ < 50ms           │  │  across accounts)    │  │
│  └──────────────────┘  │  < 30ms              │  │
│  ┌──────────────────┐  └──────────────────────┘  │
│  │ Phone Risk       │  ┌──────────────────────┐  │
│  │ (velocity +      │  │ PEP / Sanctions      │  │
│  │  TRAI blacklist) │  │ (WorldCheck API)     │  │
│  │ < 100ms          │  │ < 300ms              │  │
│  └──────────────────┘  └──────────────────────┘  │
│  ┌──────────────────┐  ┌──────────────────────┐  │
│  │ Blacklist /      │  │ Geo / IP Risk        │  │
│  │ Criminal DB      │  │ (TOR, VPN, high-risk │  │
│  │ < 100ms          │  │  jurisdiction)       │  │
│  └──────────────────┘  │ < 50ms               │  │
│                        └──────────────────────┘  │
│                                                  │
│  Scoring: weighted sum → RiskScore (0-100)       │
│  Decision: PASS(<30) REVIEW(30-70) BLOCK(>70)   │
└──────────────────────────────────────────────────┘
```

### 3.2 Blacklist / Criminal Database

We maintain a **composite blacklist** aggregated from multiple authoritative sources:

| Source | Data Type | Update Frequency |
|---|---|---|
| FIU-IND (Financial Intelligence Unit) | SAR-linked entities | Daily |
| RBI Defaulter List | Wilful defaulters | Weekly |
| NSE / BSE Debarred List | Market debarred entities | Daily |
| SEBI Debarred / Barred Persons | Securities fraud | Daily |
| MCA21 Disqualified Directors | Corporate fraud | Daily |
| Interpol Red Notices | International criminals | Daily |
| UN Security Council Consolidated List | Terrorism / sanctions | Real-time webhook |
| OFAC SDN List | US sanctions | Real-time |
| EU Consolidated Sanctions | EU sanctions | Daily |
| India PMLA Court Orders | Domestic criminal cases | Weekly |

**Architecture**:
```
External sources ──► Data Ingestion Job (nightly + real-time for UN/OFAC)
                            │
                            ▼
                    Normalisation pipeline
                    (name standardisation, transliteration, entity resolution)
                            │
                            ▼
                    Elasticsearch index
                    (fuzzy name search, phonetic matching)
                            │
                    Screening API: POST /screen
                    {name_variants[], dob?, pan?, entity_type}
                    → [{match_score, source, detail}]
                    Response < 100ms (in-memory Elasticsearch)
```

**Name matching strategy**:
- Exact match (score 100)
- Jaro-Winkler ≥ 0.92 (score 85)
- Phonetic (Soundex/Metaphone) match (score 70) → requires manual review
- Below 70: no match

### 3.3 PEP (Politically Exposed Person) Screening

```
PEP Sources:
  - WorldCheck (Refinitiv) — primary, global
  - Dow Jones Risk & Compliance — secondary
  - Internal PEP list (Indian politicians, bureaucrats, judges)

PEP Handling:
  - PEP detected → mandatory EDD (Enhanced Due Diligence)
  - EDD: source of funds declaration + senior management sign-off
  - Annual re-screening (regardless of risk cycle)
  - Continuous monitoring: transaction anomaly alerts with lower thresholds

Close associates of PEPs:
  - Immediate family (spouse, children) → treated as PEP
  - Business associates with > 25% UBO stake → EDD
```

### 3.4 Continuous Monitoring (Post-Onboarding)

```
ECA rules for account monitoring:
  ON TRANSACTION_AMOUNT(>₹10L_cash) → EMIT_CTR (Cash Transaction Report to FIU-IND)
  ON TRANSACTION_COUNT(>50/day from same beneficiary) → TRIGGER_AML_REVIEW
  ON ADDRESS_JURISDICTION_CHANGE(high_risk_country) → TRIGGER_REKYC
  ON SANCTION_LIST_UPDATED → BATCH_RESCAN_ACTIVE_ACCOUNTS (async)
  ON MULTIPLE_FAILED_LOGINS(>10/hour) → FREEZE_ACCOUNT + NOTIFY_USER
  ON DORMANT_ACCOUNT_REACTIVATION → TRIGGER_OTP_RECONFIRMATION
```

---

## 4. PII Encryption Strategy

### 4.1 Encryption Architecture

```
┌─────────────────────────────────────────────────────┐
│              Encryption Key Hierarchy                │
│                                                     │
│  CMK (Customer Master Key)                          │
│  └── Managed by CloudHSM (FIPS 140-2 Level 3)      │
│       └── Never leaves HSM                         │
│                                                     │
│  KEK (Key Encryption Key) per tenant               │
│  └── Derived from CMK via HSM                      │
│       └── Rotated annually                         │
│                                                     │
│  DEK (Data Encryption Key) per user                │
│  └── AES-256-GCM, randomly generated at account    │
│       creation                                     │
│  └── Encrypted by KEK; stored in Vault             │
│  └── DEK reference stored in `kyc_documents.dek_reference`
│                                                     │
│  Plaintext DEK: exists only in application memory  │
│  during encryption/decryption operations           │
└─────────────────────────────────────────────────────┘
```

### 4.2 PII Field Classification

| Field | Classification | At-Rest | In-Transit | In Logs |
|---|---|---|---|---|
| Aadhaar Number | CRITICAL — never store | N/A | N/A | NEVER |
| Aadhaar Token (SHA-256) | HIGH | AES-256-GCM | TLS 1.3 | Masked |
| Full Name | HIGH | AES-256-GCM per user DEK | TLS 1.3 | Masked (first letter only) |
| Date of Birth | HIGH | AES-256-GCM | TLS 1.3 | Year only |
| Mobile Number | HIGH | SHA-256 hash stored; raw via HSM decrypt | TLS 1.3 | Last 4 digits |
| PAN | HIGH | Tokenized (format-preserving encryption) | TLS 1.3 | XXXXXXX1234X |
| Address | HIGH | AES-256-GCM | TLS 1.3 | Never |
| Face Photo | CRITICAL | Deleted post face-match | TLS 1.3 | Never |
| Bank Account Number | HIGH | Tokenized | TLS 1.3 | Last 4 digits |
| Device Fingerprint | MEDIUM | SHA-256 hash | TLS 1.3 | Hashed |
| IP Address | MEDIUM | AES-256 | TLS 1.3 | Partial (/24 prefix only) |
| Transaction Amount | LOW | Plain in DB (needed for analytics) | TLS 1.3 | Bucketed |

### 4.3 Format-Preserving Encryption (FPE) for PAN

PAN is used as a lookup key across systems. Raw PAN cannot be stored but must be searchable.

```
Strategy: FF3-1 (NIST SP 800-38G) Format-Preserving Encryption
  Input:  ABCDE1234X  (PAN format: 5 alpha + 4 numeric + 1 alpha)
  Output: XYQPZ8823T  (same format, looks like a valid PAN)
  Benefit: downstream systems can store/index the token without knowing its real form
  Decryption: only via KMS with proper authorization scope
```

### 4.4 Document Encryption in S3

```
Upload flow:
  1. Client uploads document over TLS to Onboarding API
  2. App generates per-document AES-256-GCM key (doc_key)
  3. Encrypt document with doc_key → encrypted blob
  4. Encrypt doc_key with user DEK (retrieved from Vault) → encrypted_doc_key
  5. Store: S3 object (encrypted blob) + encrypted_doc_key in `kyc_documents.dek_reference`
  6. Delete: plaintext document and doc_key from memory

Retrieval flow:
  1. Fetch encrypted_doc_key from DB
  2. Decrypt with user DEK (via Vault) → doc_key
  3. Fetch encrypted blob from S3
  4. Decrypt in memory → serve to authorized principal
  5. Log access to audit trail (who accessed which doc, when, why)
```

### 4.5 Key Rotation

```
CMK: Rotated every 2 years (HSM hardware rotation)
KEK: Rotated annually — re-encrypt all DEKs with new KEK (background job)
DEK: Rotated on re-KYC event or on suspicious access detection
     Re-encryption: lazy (on next access) to avoid bulk re-encryption storms
```

---

## 5. Audit Trail & Compliance Evidence

### 5.1 Immutable Audit Log

```
Every system action produces an audit event:
{
  "event_id": "uuid",
  "timestamp": "ISO-8601",
  "actor": "system|userId|agentId",
  "action": "KYC_STEP_COMPLETED|ACCOUNT_CREATED|...",
  "lead_id": "...",
  "user_id": "...",
  "resource": "kyc_record|account|document",
  "resource_id": "...",
  "change_delta": {  // only field names and new values, PII encrypted
    "state": "KYC_IN_PROGRESS → KYC_COMPLETE"
  },
  "ip_address": "x.x.x.0/24",   // last octet masked
  "channel": "MOBILE|WEB|AGENT",
  "compliance_tags": ["RBI_KYC_MD", "PMLA_§12"]
}

Storage:
  Kafka → Flink stream → Apache Iceberg on S3 (immutable, append-only)
  Retention: 7 years (PMLA 5yr + 2yr buffer)
  Access: compliance team via Trino/Athena; no direct DB access
  Integrity: Merkle tree hash of daily log files; root hash stored in blockchain anchor
```

### 5.2 Right to Erasure (DPDPA 2023 §13)

```
User requests data deletion:
  1. Consent withdrawn → account moves to RESTRICTED
  2. 30-day cooling off period (user can reverse)
  3. After 30 days:
     a. PII fields: replaced with SHA-256(original + deletion_salt) → "anonymised"
     b. Document blobs: deleted from S3
     c. DEK: destroyed in Vault (DEK without data = no risk)
     d. Audit log: NOT deleted (PMLA exemption — §12 overrides DPDPA erasure for financial records)
     e. Lead events: PII in metadata JSON → anonymised
  4. After anonymisation: data cannot be linked back to user

Exception: Accounts under regulatory investigation (court order) → erasure blocked,
           flag added to account record, user notified of legal hold.
```

---

## 6. Network Security & Zero-Trust Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Network Segmentation                          │
│                                                                  │
│  Public Internet                                                 │
│       │                                                          │
│  ┌────▼────────────────────────────────────────────────────┐    │
│  │  WAF + DDoS Protection (CloudFront/Cloudflare)          │    │
│  └────────────────────┬───────────────────────────────────┘    │
│                       │                                          │
│  ┌────────────────────▼───────────────────────────────────┐    │
│  │  Public Subnet: API Gateway, Load Balancer              │    │
│  └────────────────────┬───────────────────────────────────┘    │
│                       │  (no direct DB access)                   │
│  ┌────────────────────▼───────────────────────────────────┐    │
│  │  Private Subnet: Application Services                   │    │
│  │  (Onboarding, KYC Engine, Fraud, Account Factory)       │    │
│  └────────────────────┬───────────────────────────────────┘    │
│                       │  (service mesh mTLS)                     │
│  ┌────────────────────▼───────────────────────────────────┐    │
│  │  Data Subnet: PostgreSQL, Redis, Kafka                  │    │
│  │  (no ingress from public subnets; app subnet only)      │    │
│  └────────────────────┬───────────────────────────────────┘    │
│                       │                                          │
│  ┌────────────────────▼───────────────────────────────────┐    │
│  │  Secrets Subnet: CloudHSM, Vault                        │    │
│  │  (accessible only from App Subnet via mTLS + RBAC)      │    │
│  └────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘

Zero Trust Controls:
  - Every service call requires mTLS (service mesh: Istio)
  - Short-lived JWT tokens (15 min) for inter-service auth
  - No long-lived credentials; all secrets from Vault with lease < 1hr
  - RBAC: KYC service cannot write to Account DB (separate service account per service)
  - Vault policy: KYC Engine can only access DEKs for leads it owns
```

---

## 7. Trade-Off Summary

| Design Decision | Option A | Option B | Choice | Reason |
|---|---|---|---|---|
| Fraud screening timing | Synchronous (pre-account) | Async (post-creation) | Sync | Cannot undo account creation; fraud must block |
| Aadhaar data retention | Store encrypted | Store token+hash only | Token+hash | UIDAI mandate; also zero breach risk on raw number |
| PAN storage | Format-preserving token | Hashed | FPE token | Enables cross-system dedup without exposing PAN |
| CKYC lookup | Sync (blocks onboarding) | Async (skip if slow) | Async with timeout | 200ms SLA usually fine; fallback to fresh KYC |
| Document encryption | Per-user DEK | Shared key | Per-user DEK | Compromise of one user's key doesn't expose others |
| Blacklist DB hosting | In-house aggregated | Third-party API per-call | In-house + third-party for PEP | Latency: in-house < 100ms; PEP via WorldCheck for accuracy |
| Audit log storage | Relational DB | Kafka → Iceberg | Kafka → Iceberg | Immutable, append-only, petabyte-scale, PMLA compliant |
| ECA rules hot-reload | Code deployment | DB + cache reload | DB hot-reload | Compliance rules change quarterly; code deploys are risky |

---

## FAANG Interview Callout

> "How do you handle a situation where a user's name appears on the UN Sanctions list — but it's a common name (e.g., 'Mohammed Khan') and there are 400 entries on the list. How do you avoid false positives that would block legitimate users?"

**Answer**:
1. Initial screening uses fuzzy name match — any hit above threshold 70 → `REVIEW` (not `BLOCK`).
2. Manual review queue with 4-hour SLA: agent performs secondary verification — checks DOB, nationality, additional identifiers against the specific list entry.
3. If multiple identifiers match (name + DOB + nationality) → escalate to `BLOCK` + SAR filing.
4. If name-only match with no other corroborating fields → `PASS` + flag for enhanced monitoring (6-month period of lower transaction thresholds).
5. All screening decisions logged with the exact list entry matched + analyst reasoning — creates a defensible compliance record for RBI inspection.
6. False positive rate tracked monthly; WorldCheck list quality feedback submitted to Refinitiv.
