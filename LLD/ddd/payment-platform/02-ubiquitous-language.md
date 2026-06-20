# Ubiquitous Language — Domain Glossary per Bounded Context

**Ubiquitous Language** is the shared vocabulary used by domain experts (product, compliance, operations) and engineers. Every class name, method name, and field name in the codebase must use these exact terms. When code diverges from the glossary, the model has drifted.

How to maintain this: whenever a product manager or compliance officer uses a new term in a meeting, add it here first, then add it to the code.

---

## Payment Bounded Context

| Term | Definition | NOT |
|---|---|---|
| **Payment** | A single intent to transfer money from a payer to a payee | Transaction, Transfer, Order |
| **PaymentReferenceId** | Client-generated idempotency key; stable across retries | PaymentId, OrderId, RequestId |
| **PaymentId** | System-generated unique identifier for a Payment | ExternalId, UUID |
| **VPA** | Virtual Payment Address — the UPI address (e.g., rahul@okicici) | UPI ID, UPI Handle, Handle |
| **Payer** | The entity initiating the payment (debit side) | Sender, Source, From |
| **Payee** | The entity receiving the payment (credit side) | Receiver, Destination, To, Beneficiary |
| **Complete** | Payment confirmed as successful by NPCI/bank | Settle, Succeed, Approve, Confirm |
| **Fail** | Payment definitively rejected by NPCI/bank | Decline, Reject, Cancel |
| **Timeout** | Payment sent to NPCI, response not received within SLA — final status unknown | Pending, Processing |
| **Block** | Fraud system prevented the payment from proceeding | Decline, Reject, Fail |
| **Cancel** | User-initiated termination before NPCI submission | Abandon, Delete, Revert |
| **NPCI Transaction ID** | NPCI's own reference for a UPI transaction | RRN (Retrieval Reference Number — don't use this term internally) |
| **Refund** | Reversal of a completed payment initiated by merchant or us | Reversal, Chargeback (chargeback is bank-initiated, refund is us-initiated) |
| **Chargeback** | Bank-initiated reversal on behalf of the payer (not the same as refund) | Refund |
| **Risk Decision** | Fraud service's decision: ALLOW, CHALLENGE, or BLOCK | Risk Score (score is an attribute; decision is the outcome) |
| **Settlement** | End-of-day batch process where NPCI moves net money between banks | Clearing, Transfer |

---

## Wallet Bounded Context

| Term | Definition | NOT |
|---|---|---|
| **Wallet** | The virtual store of money owned by a user within our platform | Account, Balance, Purse |
| **Available Balance** | Wallet balance minus held amount — what the user can spend right now | Balance (balance without qualifier is ambiguous) |
| **Held Amount** | Funds reserved for an in-flight payment — not yet debited | Frozen, Reserved, Blocked Amount |
| **KYC Level** | The degree of identity verification (MINIMAL, FULL, ENHANCED) — determines limits | Verification Level, Auth Level |
| **Hold** | Reserve funds for an in-flight payment without debiting | Block, Freeze, Lock |
| **Apply Hold** | Convert a hold to an actual debit when payment succeeds | Settle Hold, Confirm Hold |
| **Release Hold** | Return held funds to available balance when payment fails/cancels | Unblock, Unfreeze, Rollback |
| **Top-Up** | Add money to wallet from a bank account | Load, Deposit, Recharge (recharge is for mobile, not wallet) |
| **Monthly Spend** | Rolling total of debits in the current calendar month — governs RBI limits | Monthly Usage, Monthly Total |
| **Suspend** | Block all wallet activity pending investigation (compliance action) | Freeze (preferred: suspend for compliance context) |
| **Reinstate** | Re-activate a suspended wallet | Unblock, Unfreeeze, Restore |
| **Cashback** | Promotional credit to wallet (not a refund) | Reward, Bonus |

---

## Bill Payment Bounded Context

| Term | Definition | NOT |
|---|---|---|
| **Bill Payment Order** | The lifecycle entity from fetch through payment confirmation | Bill Transaction, Bill Payment |
| **Biller** | The company receiving the bill payment (TNEB, Airtel, BSNL, etc.) | Vendor, Merchant, Payee |
| **BillerId** | BBPS-assigned unique identifier for a registered biller | Vendor ID, Merchant ID |
| **Customer Identifier** | The account number used to look up a bill (consumer number, mobile number) | Account Number (term is biller-specific) |
| **Bill Fetch** | Phase 1: retrieve bill details from biller via BBPS | Bill Inquiry, Bill Lookup |
| **Bill Details** | The fetched data: amount, due date, breakdown | Bill Info, Bill Data |
| **Confirm Payment** | User's explicit approval of the fetched amount before payment | Accept, Approve, Authorize |
| **Agent Transaction ID** | Our reference sent to BBPS — stable across retries (enables BBPS-side idempotency) | External Reference |
| **BBPS Transaction ID** | BBPS's own reference for a confirmed payment | Reference Number |
| **Biller Category** | The type of biller: ELECTRICITY, MOBILE_POSTPAID, etc. | Biller Type, Category |

---

## Cross-Context Terms (Shared Kernel)

These terms appear in multiple bounded contexts but mean the same thing across all of them:

| Term | Definition |
|---|---|
| **UserId** | Platform-wide unique identifier for a registered user |
| **Money** | An amount (BigDecimal, 2 decimal places) paired with a currency code (INR) |
| **DomainEvent** | An immutable record of something that happened in a bounded context |
| **Idempotency Key** | Client-generated UUID that prevents duplicate processing on retry |
| **Aggregate** | A cluster of domain objects treated as a single unit of consistency |

---

## Terms to Avoid (Anti-Patterns in Language)

| Avoid | Use instead | Why |
|---|---|---|
| "Transaction" (generic) | Payment, Wallet Transaction, Bill Payment Order | "Transaction" is overloaded — DB transaction, financial transaction, NPCI transaction |
| "Status" (without context) | PaymentStatus, WalletStatus | Every aggregate has a status; qualify it |
| "Account" (without BC qualifier) | Bank Account (Identity BC), Wallet (Wallet BC) | Means different things in each context |
| "Decline" | Fail (bank/NPCI-initiated), Block (fraud-initiated) | Decline conflates two different causes |
| "Balance" | Available Balance or Total Balance | Ambiguous when holds are involved |
| "Settle" for UPI | Complete | Settle in payments = nightly bank settlement, not individual payment completion |
| "Abort" | Cancel (user-initiated), Fail (system-initiated) | Abort is a DB concept; use domain language |
| "User" | Payer, Payee, Customer (context-dependent) | "User" has no domain meaning; use the specific role |

---

## Event Language Rules

Domain events use **past tense** — they record what happened, not what is being requested:

| ✅ Correct (past tense) | ❌ Incorrect |
|---|---|
| `PaymentInitiated` | `InitiatePayment` |
| `PaymentCompleted` | `PaymentComplete`, `PaymentSuccess` |
| `MoneyHeld` | `HoldMoney`, `MoneyOnHold` |
| `BillFetched` | `FetchBill`, `BillFetch` |
| `WalletSuspended` | `SuspendWallet` |

**Commands** use **imperative present tense** — they express intent:

| ✅ Correct | ❌ Incorrect |
|---|---|
| `InitiateUpiPaymentCommand` | `UpiPaymentInitiatedCommand` |
| `AddMoneyToWalletCommand` | `MoneyAddedCommand` |
| `PayBillCommand` | `BillPaidCommand` |

---

## Ubiquitous Language Evolution

This glossary is a living document. When:

1. **A product manager uses a new term** in a spec → add it here before writing code
2. **Two engineers argue over a term** → the term isn't in the glossary → stop, define it, add it
3. **A compliance officer uses industry terminology** → add the regulatory term + our internal term (e.g., "NPCI calls this RRN; we call it `npciTransactionId`")
4. **A term starts meaning different things** in different contexts → you've found an implicit bounded context boundary
