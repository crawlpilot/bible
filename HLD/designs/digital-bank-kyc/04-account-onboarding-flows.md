# 04 — Account Type Onboarding Flows

## 1. Document & KYC Requirements Matrix

| Requirement | Wallet (Min) | Wallet (Full) | Individual Savings | Retailer / Merchant | Nodal / Escrow | Current Account |
|---|---|---|---|---|---|---|
| Mobile OTP | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Aadhaar OTP eKYC | ❌ | ✅ | ✅ | Owner only | Signatory | Signatory |
| Biometric eKYC | ❌ | Optional | Optional | Optional | ✅ EDD | ✅ EDD |
| PAN | ❌ | ✅ | ✅ | ✅ Business PAN | ✅ | ✅ |
| Face liveness + match | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Video KYC (VKYC) | ❌ | ❌ | ✅ Required | Optional | ✅ Required | ✅ Required |
| CKYC lookup | ❌ | ✅ | ✅ | Owner PAN-based | ✅ | ✅ |
| CKYC upload | ❌ | ✅ T+3d | ✅ T+3d | ✅ T+3d | ✅ T+3d | ✅ T+3d |
| GST Certificate | ❌ | ❌ | ❌ | ✅ | ✅ | Optional |
| Business registration | ❌ | ❌ | ❌ | Optional | ✅ | ✅ |
| Financial statements | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ last 2 yrs |
| Escrow agreement | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| RBI approval reference | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Sanctions screening | ❌ | ✅ | ✅ | ✅ + UBOs | ✅ + UBOs | ✅ + UBOs |
| Criminal / blacklist | ❌ | ✅ | ✅ | ✅ + directors | ✅ + directors | ✅ + directors |
| Re-KYC cycle | N/A | 10yr Low / 8yr Med / 2yr High | 10/8/2yr | 8/5/2yr | Annual | Annual |
| Max balance | ₹10,000 | ₹2,00,000 | Unlimited | Per RBI | Per escrow | Unlimited |

---

## 2. Flow 1: Wallet — Minimum KYC

**Regulatory basis**: RBI PPI Master Directions §9.1 — Minimum-KYC PPIs

```
ENTRY: User downloads app, chooses "Quick Wallet"
│
├── Step 1: Mobile OTP (60s expiry, max 3 attempts)
│         └── ECA: ON MOBILE_OTP_VERIFIED → ADVANCE_STATE(KYC_COMPLETE)
│
├── Step 2: Fraud screening (synchronous)
│         ├── Device fingerprint risk
│         ├── Phone velocity check (>3 registrations from same device → BLOCK)
│         └── Phone on TRAI blacklist → BLOCK
│
├── Step 3: Wallet creation (WalletMinKycStrategy)
│         ├── Balance cap: ₹10,000
│         ├── Monthly debit limit: ₹10,000
│         ├── No cash withdrawal
│         └── Validity: 12 months (RBI §9.2), then prompt for upgrade
│
EXIT: Wallet ACTIVE in < 90 seconds
      ECA schedules: upgrade nudge at T+7 days, T+30 days, T+6 months

Upgrade path:
  ON UPGRADE_INITIATED → trigger Full KYC flow → account_type upgraded in-place
  (no new account number; limits increase post-verification)
```

**Key constraint**: Minimum KYC wallet cannot exceed ₹10K balance OR ₹10K monthly load. ECA triggers `UPGRADE_PROMPT` when either threshold is approached (80% threshold).

---

## 3. Flow 2: Wallet — Full KYC

**Regulatory basis**: RBI PPI MD §9.2 — Full-KYC PPIs

```
Entry from: New user choosing "Full Wallet" OR Minimum KYC upgrade
│
├── Step 1: Mobile OTP ✅ (inherited if upgrading)
│
├── Step 2: CKYC Lookup (async, 200ms SLA)
│         ├── HIT: pre-fill demographics from CKYC record
│         │        └── prompt user to confirm/correct; skip document re-collection
│         └── MISS: proceed to fresh KYC
│
├── Step 3: Aadhaar OTP eKYC (via UIDAI ASA)
│         ├── Request Aadhaar OTP → user enters 12-digit UID + OTP
│         ├── UIDAI returns demographic XML (encrypted)
│         ├── Decrypt → extract name, DOB, address, photo → store token + hash only
│         └── NEVER persist: raw UID, raw XML, biometric data
│
├── Step 4: PAN Verification (parallel with Step 3)
│         └── Name-DOB match between PAN and Aadhaar → fuzzy match (Jaro-Winkler ≥ 0.92)
│
├── Step 5: Face Liveness + Match
│         ├── On-device liveness SDK (anti-spoofing: 3D depth, blink detection)
│         ├── Upload selfie (encrypted, ephemeral — deleted post-match)
│         └── Face-match: selfie vs Aadhaar photo (on-prem model, threshold 0.85 cosine sim)
│
├── Step 6: Fraud Screening (all checks + PEP/sanctions)
│
├── Step 7: Account upgrade / creation
│         ├── Balance limit: ₹2,00,000
│         └── Monthly load limit: ₹1,00,000
│
└── Step 8 (async, T+3 days): CKYC upload to CERSAI
          ECA: ON ACCOUNT_ACTIVATED → SCHEDULE_JOB(CKYC_UPLOAD, delay=3d)
```

---

## 4. Flow 3: Individual Savings Account

**Regulatory basis**: Banking Regulation Act; RBI KYC MD Full KYC; VKYC mandatory from Jan 2020

```
Entry: User selects "Open Savings Account"
│
├── Steps 1-5: Same as Wallet Full KYC above
│
├── Step 6: Video KYC (VKYC) — differentiator for savings
│         ├── RBI mandates for digital banks (no physical branch)
│         ├── Scheduling: user books slot; median wait < 10 minutes
│         ├── VKYC Session:
│         │     Agent joins live video call
│         │     ├── Agent verifies: face matches Aadhaar photo
│         │     ├── Agent reads out: random 4-digit code (anti-replay)
│         │     ├── Agent reviews: PAN card physical (if presented)
│         │     ├── Agent asks: name, DOB, address (anti-coaching check)
│         │     └── Agent decision: APPROVE / REJECT / RETRY
│         └── Recording: stored encrypted for 2 years (RBI requirement)
│
├── Step 7: Fraud Screening (full suite including credit bureau check optional)
│
├── Step 8: Account creation (IndividualSavingsStrategy)
│         ├── IFSC: virtual branch code (digital bank)
│         ├── Debit card: provisioned to mobile wallet
│         └── Ledger: created in core banking ledger service
│
└── Step 9 (async): CKYC upload T+3 days; Set re-KYC reminder per risk class

VKYC Agent Capacity Planning:
  350,000 full KYC completions/day × 30% savings account = 105,000 VKYC sessions/day
  Avg session: 5 minutes
  Agent hours needed: 105,000 × 5min = 8,750 agent-hours/day = ~1,094 agents (8hr shifts)
  Solution: Tiered pool — AI pre-screening + human agent for final 2 minutes
```

---

## 5. Flow 4: Retailer / Merchant Account

**Regulatory basis**: RBI KYC MD (business entity); GST Act; Payment Aggregator Guidelines PA-PG 2020

```
Entry: Retailer onboarding via Merchant Portal or BC Agent app
│
├── Phase 1: Proprietor / Signatory KYC (same as Individual Full KYC)
│           Aadhaar + PAN of business owner
│
├── Phase 2: Business Entity Verification
│   ├── GSTIN verification (GSTN API)
│   │     └── Verify: trade name, registered address, status (Active/Cancelled)
│   ├── Business PAN verification (NSDL)
│   ├── Shop/establishment address proof (utility bill, lease deed) — OCR
│   ├── Bank account verification (penny-drop test to existing bank)
│   └── MCC code assignment (Merchant Category Code per transaction type)
│
├── Phase 3: UBO (Ultimate Beneficial Owner) Declaration
│   ├── If entity type = Company/LLP: UBO with > 25% shareholding must be identified
│   ├── UBO verification: Aadhaar + PAN + sanctions screen of each UBO
│   └── Stored in UBO registry (internal) + CKYC (as legal entity)
│
├── Phase 4: Risk Classification
│   ├── LOW: kiranas, small retail (< ₹10L monthly GMV)
│   ├── MEDIUM: mid-size retail, restaurants (₹10L-₹1Cr GMV)
│   └── HIGH: jewellers, forex, real estate, political-adjacent (triggers EDD)
│
├── Phase 5: Fraud + Sanctions Screening
│   ├── GST blacklist (GSTN deregistered / fraudulent)
│   ├── MCA21 disqualified director check
│   ├── NSE/SEBI debarred entity check
│   └── All UBOs through PEP/sanctions
│
├── Phase 6: Account Creation (RetailerMerchantStrategy)
│   ├── Creates merchant account + settlement account link
│   ├── Configures MDR (Merchant Discount Rate) per MCC
│   ├── Settlement T+1 or T+2 per risk tier
│   └── Creates virtual account for QR / UPI collection
│
└── Phase 7 (async): CKYC for business entity T+3 days
                     GSTIN change monitoring (webhook from GSTN)

ECA rules specific to merchants:
  ON GSTIN_DEACTIVATED → FREEZE_SETTLEMENT → NOTIFY_COMPLIANCE
  ON HIGH_VALUE_TRANSACTION(>₹10L) → TRIGGER_ENHANCED_MONITORING
  ON MONTHLY_GMV_THRESHOLD_EXCEEDED → TRIGGER_RE_CLASSIFICATION
```

---

## 6. Flow 5: Nodal / Escrow Account

**Regulatory basis**: RBI PA-PG Guidelines 2020 (Escrow); RBI Nodal Account Guidelines

```
Nodal accounts hold funds in transit for payment aggregators.
They are NOT operated by individuals — operated by a licensed PA entity.

Pre-condition: Entity must have:
  ├── Valid PA (Payment Aggregator) license from RBI
  ├── Completed business KYC (same as merchant)
  └── RBI approval letter for nodal account purpose

Onboarding Flow:
│
├── Step 1: Business entity KYC (same as merchant Phase 1-4)
│
├── Step 2: Regulatory document submission
│   ├── Certificate of Incorporation
│   ├── MoA / AoA (Memorandum / Articles of Association)
│   ├── RBI PA license / in-principle approval
│   ├── Escrow agreement (with bank as escrow agent)
│   ├── Board resolution for account operation
│   └── Audited financials (2 years)
│
├── Step 3: Maker-Checker workflow (internal compliance)
│   ├── Maker: RO/compliance analyst reviews docs
│   ├── Checker: Senior compliance / CFO approves
│   └── Dual-approval logged with digital signature
│
├── Step 4: EDD (Enhanced Due Diligence) — mandatory
│   ├── On-site visit (or virtual equivalent with geo-tagged photos)
│   ├── Director biometric eKYC
│   ├── FATF country risk assessment
│   └── Source of funds declaration
│
├── Step 5: Account creation (NodalEscrowStrategy)
│   ├── Account type: NODAL / ESCROW
│   ├── Max hold duration: T+3 days (RBI mandate for PA settlements)
│   ├── Automated sweep: funds settled to merchant accounts on schedule
│   ├── Audit: every debit/credit logged to FIU-IND daily
│   └── RBI inspection access: read-only API endpoint for regulator
│
└── Re-KYC: Annual (mandatory for high-risk entity type)
            ECA: ON ACCOUNT_ANNIVERSARY(type=NODAL) → TRIGGER_REKYC
```

---

## 7. Flow 6: Current Account

**Regulatory basis**: Banking Regulation Act; RBI KYC MD (Corporate); PMLA for business entities

```
Target: SMBs, corporations, NGOs, trusts

Differences from Merchant:
  - No PA license required
  - No settlement sweep logic
  - Full cheque-book / RTGS / NEFT access
  - Minimum balance requirements
  - Financial statement review for credit risk

Onboarding Steps:
│
├── Phase 1: Entity type classification
│   ├── Proprietorship → proprietor individual KYC
│   ├── Partnership → all partners' individual KYC
│   ├── Private Limited → 2+ directors + UBOs ≥ 25%
│   ├── Public Limited → same + listed entity check (BSE/NSE)
│   ├── NGO/Trust → trustees' individual KYC + deed/registration
│   └── HUF → karta's individual KYC
│
├── Phase 2: Entity-specific document collection
│   (Per entity type — driven by ECA rule `ENTITY_DOCS_REQUIRED(entityType)`)
│   ├── Proprietorship: trade license + proprietor KYC
│   ├── Pvt Ltd: CIN, MoA/AoA, board resolution, shareholders list
│   ├── NGO: 12A/80G registration, trust deed
│   └── HUF: HUF deed, karta identity
│
├── Phase 3: Financial risk assessment
│   ├── CIBIL MSME score (for SMBs)
│   ├── GST return analysis (last 12 months)
│   ├── Bank statement analysis (last 6 months)
│   └── Risk tier: LOW / MEDIUM / HIGH
│
├── Phase 4: Sanctions + Director screening (per UBO)
│
├── Phase 5: VKYC (mandatory for digital current account opening)
│
├── Phase 6: Account creation (CurrentAccountStrategy)
│   ├── IFSC + account number assignment
│   ├── Cheque book provisioning (physical mailed or virtual)
│   ├── NEFT/RTGS/IMPS enabled
│   └── Internet banking credentials provisioned
│
└── Re-KYC: Annual for High, 2yr for Medium, periodic for Low
```

---

## 8. KYC Upgrade Paths

```
Minimum KYC Wallet ─────────────────────────────────────────►  Full KYC Wallet
                                                                      │
                                                                      ▼
                                                               Individual Savings
                                                               (+ VKYC required)
                                                                      │
                                                               (if business):
                                                                      ▼
                                                               Merchant Account
                                                                      │
                                                               (if PA license):
                                                                      ▼
                                                               Nodal Account
```

Upgrade is always **in-place** (same user record; account_type updated, new account number may be issued by bank core). ECA rule:

```sql
INSERT INTO eca_rules (name, event_type, condition_expr, actions) VALUES (
  'wallet-balance-nudge-upgrade',
  'WALLET_BALANCE_THRESHOLD',
  'event.balance_pct >= 80 && lead.account_type == "WALLET_MIN"',
  '[{"type": "NOTIFY_USER", "params": {"template": "UPGRADE_NUDGE_LIMIT_APPROACHING"}},
    {"type": "CREATE_UPGRADE_LEAD", "params": {"target_type": "WALLET_FULL"}}]'
);
```

---

## FAANG Interview Callout

> "A merchant's GSTIN is deactivated by GSTN. How does your system detect this, and what is the exact sequence of events that follows?"

**Answer**:
1. GSTN sends webhook to our `GST_STATUS_CHANGED` event endpoint (or we poll GSTN API nightly for active merchants).
2. Event published to Kafka topic `account.events`.
3. ECA rule `ON GSTIN_DEACTIVATED` fires → Action: `FREEZE_SETTLEMENT_ACCOUNT`.
4. Simultaneously: `NOTIFY_COMPLIANCE_TEAM` + `NOTIFY_MERCHANT`.
5. Merchant has 14 days to re-activate GSTIN or provide alternate registration proof.
6. If not resolved → `CLOSE_ACCOUNT` action with 30-day notice (RBI account closure norms).
7. All fund movements during freeze: inbound allowed (settlement to customers), outbound blocked.
