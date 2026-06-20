# 01 — Requirements & Estimation

## 1. Functional Requirements

### 1.1 Account Types & KYC Tiers

| Account Type | KYC Tier | Regulatory Handle | Max Balance | Key Documents |
|---|---|---|---|---|
| **Wallet (PPI)** | Minimum KYC | RBI PPI MD 2017 | ₹10,000 | Mobile OTP only |
| **Wallet (Full KYC PPI)** | Full KYC | RBI PPI MD 2017 | ₹2,00,000 | Aadhaar + PAN / CKYC |
| **Individual Savings** | Full KYC | Banking Regulation Act | No cap | Aadhaar eKYC + Video KYC |
| **Retailer / Merchant** | Business KYC | RBI KYC MD + GST Act | Per limit | PAN + GSTIN + shop address |
| **Nodal / Escrow** | Enhanced Due Diligence | RBI PA-PG Guidelines | Per escrow | Business KYC + escrow agreement |
| **Current Account** | Full Business KYC | Banking Regulation Act | No cap | Incorporation docs + financials |

### 1.2 Core User Onboarding Flows

1. **Self-onboarding** (Mobile/Web) — 90% of volume
   - OTP-based identity anchor
   - Aadhaar OTP / biometric eKYC via UIDAI
   - Liveness check (selfie + face-match vs Aadhaar photo)
   - PAN verification via NSDL/UTI
   - CKYC lookup before fresh document collection

2. **Assisted onboarding** (Agent / KYC point)
   - Business Correspondent (BC) agent captures biometrics via AUA device
   - Notarised / in-person document upload
   - Video KYC (VKYC) for savings accounts (RBI mandated since Jan 2020)

3. **API / B2B onboarding** (Merchant, Nodal)
   - Webhook-driven, async document verification
   - Maker-checker workflow for high-risk accounts

### 1.3 KYC Verification Steps (per tier)

| Step | Minimum KYC | Full KYC | EDD |
|---|---|---|---|
| Mobile OTP | ✅ | ✅ | ✅ |
| Aadhaar OTP eKYC | ❌ | ✅ | ✅ |
| Biometric eKYC (fingerprint/iris) | ❌ | Optional | ✅ |
| PAN / Form 60 | ❌ | ✅ | ✅ |
| CKYC / KRA lookup | ❌ | ✅ | ✅ |
| Face liveness + match | ❌ | ✅ | ✅ |
| Video KYC (VKYC) | ❌ | For savings | ✅ |
| Address proof (doc OCR) | ❌ | Fallback | ✅ |
| Business docs (GST, incorporation) | ❌ | Merchant | ✅ |
| PEP / Sanctions screening | ❌ | ✅ | ✅ |
| CIBIL / Bureau check | ❌ | Optional | Lending only |
| Criminal / blacklist check | ❌ | ✅ | ✅ |
| Geo-fencing / IP risk | ❌ | ✅ | ✅ |

### 1.4 Workflow Lead Tracking (ECA)

- Every onboarding attempt creates a **Lead** entity
- Lead progresses through states driven by events (ECA engine)
- Supports **resume from last checkpoint** if user drops off
- Supports **manual override** (compliance team intervention)
- Full audit trail per lead: who did what, when, via which channel

### 1.5 Non-Functional Requirements

| Attribute | Target |
|---|---|
| Onboarding completion (P99) | < 3 minutes for Minimum KYC |
| Aadhaar OTP round-trip | < 5 seconds |
| CKYC lookup | < 200 ms |
| Fraud screening | < 500 ms (synchronous, pre-account) |
| System availability | 99.95% (< 4.4 hr/year downtime) |
| Eventual consistency | Max 30 seconds for cross-service state sync |
| Data residency | All PII stored within India (RBI + DPDPA) |
| Audit log retention | 5 years (PMLA mandate) |
| Re-KYC trigger latency | < 5 minutes from risk event to re-KYC initiation |

---

## 2. Back-of-Envelope Estimation

### 2.1 User Scale

```
Total registered users           : 300M
Monthly Active Users (MAU)       : 150M
Daily Active Users (DAU)         : 50M

New onboardings / day            : 500,000  (~6 new users/second peak)
KYC completions / day            : 350,000  (70% funnel completion)
Upgrade (min→full KYC) / day     : 50,000
Re-KYC triggers / day            : 10,000
```

### 2.2 QPS Estimates

```
Peak onboarding QPS              : 6 × 5 (burst factor) = 30 QPS
Aadhaar OTP requests / day       : 350,000 → peak ~20 QPS
CKYC lookups / day               : 350,000 → peak ~20 QPS
Fraud screening calls / day      : 500,000 → peak ~30 QPS
ECA event ingestion / day        : 5M events → peak ~300 QPS
Lead state reads (dashboards)    : ~500 QPS sustained
```

### 2.3 Storage Estimates

```
Lead record size                 : 2 KB (metadata + state)
Per-user KYC doc metadata        : 5 KB
Document blob (S3/blob store)    : avg 500 KB per doc × 2 docs = 1 MB/user
Aadhaar XML (NEVER stored)       : 0 (only token + hash retained)
Audit event per user             : ~50 events × 500 bytes = 25 KB/user

Total users: 300M
Lead + KYC metadata              : 300M × 7 KB  = ~2 TB
Document blobs                   : 300M × 1 MB  = ~300 TB (S3, tiered)
Audit logs                       : 300M × 25 KB = ~7.5 TB (append-only log store)
Encryption key store (HSM-backed): < 1 GB (per-user DEK references only)
```

### 2.4 Bandwidth

```
Inbound document upload          : 500K × 1 MB = 500 GB/day ≈ 6 MB/s sustained
Aadhaar eKYC response payload    : 20 QPS × 2 KB = 40 KB/s (trivial)
ECA event bus                    : 300 QPS × 500 bytes = 150 KB/s
```

---

## 3. Compliance Requirements Matrix

| Requirement | Standard | System Component |
|---|---|---|
| Customer Due Diligence (CDD) | RBI KYC MD 2016 | KYC Engine + Document Verifier |
| Enhanced Due Diligence (EDD) | RBI KYC MD + FATF R.10 | EDD Service + Manual Review |
| CKYC upload within 3 working days | RBI MD 2016 §56 | KRA Adapter (async, SLA monitored) |
| Suspicious Activity Reports | PMLA §12 | SAR Service (triggered by fraud flags) |
| Cash Transaction Reports (CTR) | PMLA Rule 3 | Transaction Monitoring (downstream) |
| Aadhaar consent capture | Aadhaar Act §8(2)(b) | Consent Service + immutable audit |
| Biometric deletion post-use | UIDAI Circular 2023 | Document Vault (TTL-purge on biometric) |
| PEP / Sanctions screening | FATF R.12, UN Security Council | Screening Service (WorldCheck/Dow Jones) |
| Data localisation | RBI 2018 circular + DPDPA 2023 | All infra in ap-south-1 (Mumbai) |
| Right to erasure | DPDPA 2023 §13 | PII Anonymisation Service |
| Explicit consent for PII | DPDPA 2023 §6 | Consent Management Platform |
| Re-KYC periodicity | RBI MD §38: Low-risk 10yr, Medium 8yr, High 2yr | Re-KYC Scheduler + Risk Classifier |

---

## 4. Capacity Planning Summary

| Tier | Instances | Rationale |
|---|---|---|
| Onboarding API gateway | 10 pods (autoscale to 40) | 30 QPS peak, stateless |
| ECA event processor | 20 pods (Kafka consumer group) | 300 QPS event ingestion |
| KYC Engine | 15 pods | Aadhaar OTP + CKYC + doc OCR fan-out |
| Fraud Screening | 10 pods | 30 QPS with < 500ms SLA |
| Document Store (blob) | Object store (S3 compatible) | 300 TB, lifecycle to Glacier after 90 days |
| Lead DB | PostgreSQL (2 primary, 2 replicas) | 2 TB operational, 7-year partition archive |
| Audit Log | Kafka → Iceberg (S3) | 7.5 TB, append-only, immutable |
| HSM (key management) | AWS CloudHSM FIPS 140-2 Level 3 | Per-user DEK, KMS envelope encryption |
