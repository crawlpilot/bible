# Strategic Design — Bounded Contexts & Context Map

## Step 1: Problem Space — Subdomain Analysis

Before writing a line of code, we identify **what the business actually does** and separate it into subdomains.

### What does a payment app do?
A user wants to send ₹500 to a friend via UPI. Behind that simple act:
1. The app must know who the user is and what they're allowed to do (Identity & KYC)
2. It must check if the user isn't trying to commit fraud (Fraud Detection)
3. It must route money from source to destination (Payment — the hard part)
4. It must update the user's virtual wallet balance (Wallet)
5. It must tell the user what happened (Notification)
6. It must keep an immutable record for regulators (Audit & Ledger)

Each of these is a **subdomain** — a distinct area of business capability.

### Subdomain Classification

```
┌─────────────────────────────────────────────────────────────┐
│                    CORE DOMAINS                             │
│  (where the competitive advantage lives; build, don't buy)  │
│                                                             │
│   ┌─────────────────┐    ┌──────────────────┐              │
│   │    Payment      │    │     Wallet        │              │
│   │                 │    │                  │              │
│   │ UPI routing,    │    │ Balance engine,  │              │
│   │ card processing,│    │ KYC-gated limits,│              │
│   │ settlement,     │    │ instant transfers│              │
│   │ reconciliation  │    │                  │              │
│   └─────────────────┘    └──────────────────┘              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  SUPPORTING DOMAINS                         │
│  (needed to support core; differentiating but not core)     │
│                                                             │
│   ┌─────────────┐  ┌───────────────┐  ┌─────────────────┐  │
│   │ Identity &  │  │ Bill Payment  │  │ Fraud Detection │  │
│   │    KYC      │  │  (BBPS)       │  │ & Risk          │  │
│   └─────────────┘  └───────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   GENERIC DOMAINS                           │
│  (commodity; buy off-shelf or use SaaS)                     │
│                                                             │
│   ┌──────────────┐  ┌─────────────────┐                    │
│   │ Notification │  │ Audit & Ledger  │                    │
│   │ (SMS, Email, │  │ (Immutable log, │                    │
│   │  Push)       │  │  Regulatory)    │                    │
│   └──────────────┘  └─────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

**Why Payment is Core (not Supporting):**
The sophistication of payment routing — handling NPCI timeout behavior, retry semantics, partial settlement, refund lifecycle, chargeback — is where Paytm/GPay differentiate themselves from a basic bank transfer. This is where the most engineering investment belongs.

**Why Notification is Generic:**
Sending an SMS when a payment succeeds is valuable but not differentiating. Any SaaS (Twilio, Firebase, AWS SNS) can do this. Build a thin adapter, not a complex domain.

---

## Step 2: Solution Space — Bounded Context Identification

Each subdomain maps to one **bounded context** — a deployable, independently-owned service with its own model.

The key question for each boundary: *"Would a concept mean something different if we crossed this boundary?"*

**Example — the word "Account":**
- In Identity: "Account" = login credentials, phone number, email, password
- In Payment: "Account" = bank account number linked to a VPA
- In Wallet: "Account" = the virtual wallet with a balance
- In Audit: "Account" is not even a concept — it talks about "entries" and "ledger lines"

Same word, four completely different things. This is why bounded contexts exist.

### Bounded Context Map

```
                    ┌──────────────────────────────────────────────────────┐
                    │            PAYMENT PLATFORM CONTEXT MAP              │
                    └──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────────┐
│                                                                                  │
│  ┌────────────────┐   Customer/Supplier   ┌─────────────────────────────────┐   │
│  │  Identity &    │──────────────────────▶│         Payment BC              │   │
│  │  KYC BC        │  (KYC gates what       │                                 │   │
│  │                │   Payment can do)      │  Aggregates: Payment            │   │
│  │  Upstream ↑    │                        │  Owns: UPI, Card processing     │   │
│  └───────┬────────┘                        └─────────────┬───────────────────┘   │
│          │ Open Host Service (User events)               │                        │
│          │                                               │ Domain Events          │
│  ┌───────▼────────┐   ACL (translates      ┌────────────▼───────────────────┐   │
│  │  Fraud         │◀──NPCI model to         │   Wallet BC                    │   │
│  │  Detection BC  │   our model)            │                                │   │
│  │                │                         │   Aggregates: Wallet           │   │
│  │  Upstream ↑    │◀──────────────────────  │   Owns: balance, limits        │   │
│  └───────┬────────┘   Risk score fed back   └─────────────┬──────────────────┘  │
│          │ Published Language                              │                      │
│          │ (RiskScore events)                              │ Domain Events         │
│          │                              ┌──────────────────▼──────────────────┐  │
│          │                              │        Bill Payment BC               │  │
│  ┌───────▼────────┐   Conformist         │                                     │  │
│  │  Notification  │◀───────────────────  │  Aggregates: BillPaymentOrder       │  │
│  │  BC            │  (subscribes to      │  Owns: BBPS integration             │  │
│  │  (Generic)     │   all events,        └─────────────────────────────────────┘  │
│  └───────┬────────┘   conforms to        │                                        │
│          │            their models)       │ All Payment/Wallet/Bill events         │
│  ┌───────▼────────┐                      │                                        │
│  │  Audit &       │◀─────────────────────┘                                        │
│  │  Ledger BC     │   Conformist                                                   │
│  │  (Generic)     │   (records all, influences none)                              │
│  └────────────────┘                                                               │
│                                                                                  │
│  External Systems (outside our platform):                                        │
│  NPCI UPI Network ← ACL → Payment BC                                            │
│  Bank Card Networks ← ACL → Payment BC                                          │
│  BBPS ← ACL → Bill Payment BC                                                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 3: Context Relationships Explained

### Payment BC ← Customer/Supplier → Identity & KYC BC

**Relationship:** Identity is **upstream**, Payment is **downstream**.

Payment needs to know: Is this user KYC-verified? What are their daily limits? What bank accounts are linked?

But Payment should NOT consume Identity's internal model directly. Instead, Identity publishes a **Shared Kernel** of KYC-related data:
```java
// Shared Kernel — minimal, stable, versioned
public record UserKycProfile(
    UserId userId,
    KycLevel kycLevel,         // MINIMAL, FULL, ENHANCED
    DailyUpiLimit dailyUpiLimit,
    DailyCardLimit dailyCardLimit,
    boolean isPhoneVerified,
    boolean isBankAccountLinked
) {}
```

Payment caches this (Redis, 5-min TTL) and enforces limits in its own domain. When KYC changes, Identity publishes a `KycLevelUpdated` event; Payment invalidates its cache.

**Why not call Identity synchronously on every payment?**
- Availability coupling: if Identity is down, payments fail
- Latency: adds 30–50ms to critical payment path
- KYC doesn't change during a payment — caching is safe

### Payment BC → Fraud Detection BC — Anti-Corruption Layer

**Relationship:** Fraud is **upstream** in the risk-scoring sense. But Payment must NOT expose its internal model to Fraud.

Before initiating a payment, Payment calls Fraud's API:
```
Payment → POST /risk/evaluate → Fraud BC
        ← RiskScore{score: 0.82, decision: ALLOW, sessionId: "f-abc"}
```

Payment wraps this call in an Anti-Corruption Layer (ACL):
```java
// In Payment's infrastructure layer — NOT in the domain
public class FraudServiceACL {
    private final FraudHttpClient fraudClient;

    // Translates Payment's PaymentContext to Fraud's RiskEvaluationRequest
    public RiskDecision evaluateRisk(Payment payment, DeviceContext device) {
        var request = toFraudRequest(payment, device); // ← translation here
        var response = fraudClient.evaluate(request);
        return fromFraudResponse(response);            // ← translation here
    }
}
```

If Fraud changes its API schema, only the ACL changes — the Payment domain is unaffected.

### Notification BC — Conformist

**Relationship:** Notification conforms to the models published by Payment, Wallet, and Bill Payment. It has no upstream influence.

Notification subscribes to events on Kafka:
```
PaymentCompleted → send "₹500 paid to rahul@upi" SMS + push
PaymentFailed    → send "Payment failed. Try again." push
MoneyAdded       → send "₹1,000 added to wallet" push
BillPaid         → send "Electricity bill ₹2,450 paid" push
```

Notification doesn't need a rich domain model — it's a thin event consumer with templates. This is a **Generic Domain** — buy Twilio/FCM/AWS SNS and build a thin adapter.

### External Systems — ACL at Every Integration Point

NPCI (UPI), bank networks (card processing), and BBPS (bill payment) are systems we don't own and can't control. Their APIs:
- Change without notice
- Have inconsistent error codes
- Use different concepts ("transaction reference" in NPCI ≠ "payment ID" in our system)

**Every external integration gets its own ACL:**
```
Payment Domain ← ACL (NpciUpiAdapter) ← NPCI REST API
Payment Domain ← ACL (VisaMasterCardAdapter) ← Bank Card Network API
Bill Payment Domain ← ACL (BbpsAdapter) ← BBPS API
```

The ACL translates:
- Their error codes → our domain exceptions
- Their data models → our value objects
- Their retry semantics → our timeout handling

---

## Step 4: What Lives Where — Decision Record

### "Should payment status history live in the Payment BC or Audit BC?"

**Decision:** Payment BC owns `PaymentStatus` transitions as part of the aggregate's state machine. Audit BC receives `PaymentStatusChanged` events and builds its own immutable ledger.

**Reasoning:**
- Payment needs to enforce: "you can't refund a FAILED payment" — this requires status in its own aggregate
- Audit needs to record: "at 14:32:07, payment P-123 transitioned from PROCESSING to COMPLETED" — this is an independent concern
- Separating them allows Audit to be eventually consistent (fine for reporting) while Payment is strongly consistent (required for correctness)

### "Should the Wallet balance be part of the Payment aggregate?"

**Decision:** No. Wallet is a separate bounded context with its own aggregate.

**Reasoning:**
- A payment can debit from a bank account (no wallet involvement at all)
- A payment can debit from wallet AND bank account (split payment)
- Wallet balance changes trigger their own events (cashback, expiry) unrelated to payments
- Combining them creates a massive aggregate with contention: every payment and every wallet top-up would lock the same record

**Integration:** When a payment is funded by wallet, Payment publishes `WalletDebitRequested` → Wallet processes it → Wallet publishes `WalletDebited` → Payment saga receives confirmation and continues.

### "Should UPI and Card payments be in the same Payment bounded context?"

**Decision:** Yes — one Payment BC, polymorphic payment methods.

**Reasoning:**
- Both share the same lifecycle: INITIATED → PROCESSING → COMPLETED/FAILED
- Both share settlement, refund, and reconciliation workflows
- Separating them would force the API layer to call two different services for "make a payment" — artificial complexity
- The differences (UPI uses VPA, Card uses PAN+CVV) are implementation details of payment method types, not separate domains

---

## Summary: Key Principles Applied

1. **Align bounded contexts with team structure** — one team per BC reduces coordination overhead
2. **Draw boundaries where the model breaks** — "account" means different things in Identity vs Wallet
3. **Protect core domains with ACLs** — external systems (NPCI) should not pollute our Payment model
4. **Make external dependencies explicit** — every integration point is a named adapter in the infrastructure layer
5. **Separate consistency requirements** — Payment is strongly consistent; Notification is eventually consistent; Audit is append-only
