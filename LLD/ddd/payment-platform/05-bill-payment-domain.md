# Bill Payment Bounded Context — Domain Model

Bill Payment handles utility payments, mobile recharges, and subscription payments via the **Bharat Bill Payment System (BBPS)** — India's RBI-mandated interoperable bill payment network.

**Key difference from P2P payment:** bill payment has a two-phase workflow:
1. **Fetch:** retrieve the bill details from the biller (amount, due date, account number)
2. **Pay:** make the payment with the confirmed amount

This fetch-before-pay is mandated by BBPS — you cannot pay without fetching. This shapes the entire domain model.

---

## Package Structure

```
com.paytm.billpayment.domain/
├── model/
│   ├── BillPaymentOrder.java          ← Aggregate Root
│   ├── BillPaymentOrderId.java        ← Value Object
│   ├── BillerInfo.java                ← Value Object
│   ├── BillerCategory.java            ← Enum
│   ├── CustomerIdentifier.java        ← Value Object (account/consumer number)
│   ├── BillDetails.java               ← Value Object (fetched bill data)
│   ├── BillPaymentStatus.java         ← Value Object (state machine)
│   └── BbpsTransactionRef.java        ← Value Object (BBPS reference)
├── events/
│   ├── BillFetchRequested.java
│   ├── BillFetched.java
│   ├── BillFetchFailed.java
│   ├── BillPaymentInitiated.java
│   ├── BillPaymentCompleted.java
│   └── BillPaymentFailed.java
├── repository/
│   └── BillPaymentOrderRepository.java
└── service/
    └── BillPaymentValidationService.java
```

---

## Value Objects

### BillerInfo — identifies who we're paying

```java
package com.paytm.billpayment.domain.model;

/**
 * Identifies a biller registered in BBPS.
 *
 * Every biller in BBPS has a unique billerId (assigned by NPCI).
 * Category determines the validation rules for CustomerIdentifier.
 */
public record BillerInfo(
    String billerId,         // BBPS-assigned biller ID (e.g., "ELECTRICITY_TNEB_001")
    String billerName,       // display name (e.g., "Tamil Nadu Electricity Board")
    BillerCategory category,
    String logoUrl
) {
    public BillerInfo {
        if (billerId == null || billerId.isBlank())
            throw new IllegalArgumentException("BillerId required");
        if (billerName == null || billerName.isBlank())
            throw new IllegalArgumentException("BillerName required");
        if (category == null)
            throw new IllegalArgumentException("Category required");
    }
}

public enum BillerCategory {
    ELECTRICITY,
    GAS,
    WATER,
    BROADBAND,
    MOBILE_PREPAID,
    MOBILE_POSTPAID,
    DTH,
    INSURANCE,
    LOAN_REPAYMENT,
    MUNICIPAL_TAXES,
    CREDIT_CARD,
    SUBSCRIPTION  // Netflix, Hotstar, etc.
}
```

### CustomerIdentifier — the account number for the biller

```java
package com.paytm.billpayment.domain.model;

/**
 * The identifier the biller uses to look up a customer's bill.
 *
 * Examples:
 * - Electricity: consumer number (12 digits)
 * - Mobile postpaid: mobile number (10 digits)
 * - DTH: subscriber ID
 * - Credit card: last 4 digits of card
 *
 * Validation rules are biller-specific — we store the raw identifier and
 * let the biller's ACL validate the format before calling BBPS.
 */
public record CustomerIdentifier(
    String identifierType,  // "CONSUMER_NUMBER", "MOBILE_NUMBER", "ACCOUNT_NUMBER"
    String identifierValue  // the actual value
) {
    public CustomerIdentifier {
        if (identifierType == null || identifierType.isBlank())
            throw new IllegalArgumentException("Identifier type required");
        if (identifierValue == null || identifierValue.isBlank())
            throw new IllegalArgumentException("Identifier value required");
        if (identifierValue.length() > 50)
            throw new IllegalArgumentException("Identifier too long");
    }
}
```

### BillDetails — the fetched bill data (immutable)

```java
package com.paytm.billpayment.domain.model;

import java.time.LocalDate;
import java.time.Instant;
import java.util.List;

/**
 * The bill information returned by BBPS.
 * Immutable — the fetched bill is a snapshot at fetch time.
 *
 * Production note: bill details have a validity window (typically 30 minutes to 24 hours
 * depending on the biller). After expiry, a fresh fetch is required.
 */
public record BillDetails(
    String billNumber,           // biller's internal bill reference
    Money billAmount,            // total amount due
    Money minimumDueAmount,      // for credit cards: minimum payment
    LocalDate dueDate,
    String billerDisplayName,
    List<BillLineItem> lineItems, // breakdown of charges
    Instant fetchedAt,
    Instant validUntil           // when this bill data expires
) {
    public boolean isExpired() { return Instant.now().isAfter(validUntil); }

    public boolean isDue() { return LocalDate.now().isAfter(dueDate) || LocalDate.now().isEqual(dueDate); }
}

public record BillLineItem(String description, Money amount) {}
```

---

## BillPaymentStatus — Two-Phase State Machine

```java
package com.paytm.billpayment.domain.model;

import java.util.Map;
import java.util.Set;

/**
 * Bill payment has a two-phase lifecycle:
 * Phase 1: Fetch  → FETCH_PENDING → BILL_FETCHED / FETCH_FAILED
 * Phase 2: Pay    → PAYMENT_PENDING → PAYMENT_COMPLETED / PAYMENT_FAILED
 *
 * You cannot go from FETCH_PENDING directly to PAYMENT_PENDING.
 * BBPS mandates: always fetch, then pay.
 */
public enum BillPaymentStatus {
    FETCH_PENDING,
    BILL_FETCHED,
    FETCH_FAILED,
    PAYMENT_PENDING,
    PAYMENT_INITIATED,   // sent to BBPS
    PAYMENT_COMPLETED,
    PAYMENT_FAILED,
    PAYMENT_TIMEOUT;     // BBPS didn't respond; reconcile later

    private static final Map<BillPaymentStatus, Set<BillPaymentStatus>> VALID_TRANSITIONS = Map.of(
        FETCH_PENDING,      Set.of(BILL_FETCHED, FETCH_FAILED),
        BILL_FETCHED,       Set.of(PAYMENT_PENDING, FETCH_FAILED), // re-fetch if expired
        PAYMENT_PENDING,    Set.of(PAYMENT_INITIATED),
        PAYMENT_INITIATED,  Set.of(PAYMENT_COMPLETED, PAYMENT_FAILED, PAYMENT_TIMEOUT),
        PAYMENT_TIMEOUT,    Set.of(PAYMENT_COMPLETED, PAYMENT_FAILED) // reconciliation
    );

    public boolean canTransitionTo(BillPaymentStatus next) {
        return VALID_TRANSITIONS.getOrDefault(this, Set.of()).contains(next);
    }

    public boolean isTerminal() {
        return Set.of(PAYMENT_COMPLETED, PAYMENT_FAILED, FETCH_FAILED).contains(this);
    }
}
```

---

## BillPaymentOrder Aggregate Root

```java
package com.paytm.billpayment.domain.model;

import com.paytm.billpayment.domain.events.*;
import java.time.Instant;
import java.util.*;

/**
 * BillPaymentOrder Aggregate Root.
 *
 * Represents the user's intent to pay a bill, from fetch through payment confirmation.
 *
 * Key invariant: a bill cannot be paid without a valid (non-expired) fetch.
 * Key idempotency: BBPS uses our agentTransactionId for deduplication.
 *   If BBPS times out and we retry, we send the same agentTransactionId.
 *   BBPS returns the original result (not a new transaction).
 */
public class BillPaymentOrder {

    private final BillPaymentOrderId id;
    private final UserId customerId;
    private final BillerInfo billerInfo;
    private final CustomerIdentifier customerIdentifier;
    private final String idempotencyKey;           // client-generated, for our deduplication
    private final String agentTransactionId;       // our reference sent to BBPS

    // Phase 1: Fetch
    private BillDetails fetchedBillDetails;
    private String fetchTransactionId;             // BBPS fetch transaction reference

    // Phase 2: Pay
    private Money paymentAmount;                   // confirmed by user (may differ from bill amount for partial)
    private String paymentMode;                    // WALLET, UPI, CARD
    private String bbpsPaymentTransactionId;       // BBPS payment confirmation reference

    // State
    private BillPaymentStatus status;
    private String failureReason;
    private final Instant createdAt;
    private Instant completedAt;
    private long version;

    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // ─────────────────── Factory ─────────────────────────────────────────

    public static BillPaymentOrder create(
        UserId customerId,
        BillerInfo billerInfo,
        CustomerIdentifier customerIdentifier,
        String idempotencyKey
    ) {
        Objects.requireNonNull(customerId);
        Objects.requireNonNull(billerInfo);
        Objects.requireNonNull(customerIdentifier);
        if (idempotencyKey == null || idempotencyKey.isBlank())
            throw new IllegalArgumentException("Idempotency key required");

        BillPaymentOrder order = new BillPaymentOrder();
        order.id = BillPaymentOrderId.generate();
        order.customerId = customerId;
        order.billerInfo = billerInfo;
        order.customerIdentifier = customerIdentifier;
        order.idempotencyKey = idempotencyKey;
        // Our reference to BBPS — stable across retries
        order.agentTransactionId = "BBPS-" + order.id.getValue();
        order.status = BillPaymentStatus.FETCH_PENDING;
        order.createdAt = Instant.now();
        order.version = 0L;

        order.domainEvents.add(new BillFetchRequested(
            order.id, customerId, billerInfo.billerId(),
            customerIdentifier, Instant.now()
        ));

        return order;
    }

    // ─────────────────── Phase 1: Fetch ───────────────────────────────────

    /**
     * Bill details successfully retrieved from BBPS.
     */
    public void recordBillFetched(BillDetails billDetails, String fetchTransactionId) {
        assertCanTransitionTo(BillPaymentStatus.BILL_FETCHED);
        Objects.requireNonNull(billDetails, "Bill details required");
        Objects.requireNonNull(fetchTransactionId, "Fetch transaction ID required");

        this.fetchedBillDetails = billDetails;
        this.fetchTransactionId = fetchTransactionId;
        this.status = BillPaymentStatus.BILL_FETCHED;

        domainEvents.add(new BillFetched(
            this.id, this.customerId, this.billerInfo.billerId(),
            billDetails, fetchTransactionId, Instant.now()
        ));
    }

    /**
     * Failed to fetch bill (biller offline, invalid account number, etc.)
     */
    public void recordFetchFailed(String reason) {
        assertCanTransitionTo(BillPaymentStatus.FETCH_FAILED);
        this.status = BillPaymentStatus.FETCH_FAILED;
        this.failureReason = reason;

        domainEvents.add(new BillFetchFailed(this.id, this.customerId, reason, Instant.now()));
    }

    // ─────────────────── Phase 2: Pay ─────────────────────────────────────

    /**
     * User confirmed payment amount and payment mode.
     *
     * Business rules:
     * - Bill must be in FETCHED state
     * - Fetched bill must not be expired (bill validity window)
     * - Payment amount must be positive and <= bill amount
     *   (partial payment allowed for credit cards; full payment required for utilities)
     */
    public void confirmPayment(Money paymentAmount, String paymentMode) {
        if (this.status != BillPaymentStatus.BILL_FETCHED)
            throw new InvalidBillPaymentStateException(
                "Cannot confirm payment. Bill must be fetched first. Current status: " + this.status);

        if (this.fetchedBillDetails.isExpired())
            throw new BillExpiredException(
                "Fetched bill has expired. Please re-fetch before paying.");

        if (paymentAmount.isZero())
            throw new IllegalArgumentException("Payment amount cannot be zero");

        if (paymentAmount.isGreaterThan(fetchedBillDetails.billAmount()))
            throw new IllegalArgumentException(
                "Payment amount " + paymentAmount +
                " exceeds bill amount " + fetchedBillDetails.billAmount());

        // For utilities: must pay full amount (no partial)
        if (billerCategory() != BillerCategory.CREDIT_CARD &&
            !paymentAmount.equals(fetchedBillDetails.billAmount()))
            throw new IllegalArgumentException(
                "Utility bills require full payment. Bill: " +
                fetchedBillDetails.billAmount() + ", Requested: " + paymentAmount);

        this.paymentAmount = paymentAmount;
        this.paymentMode = paymentMode;
        this.status = BillPaymentStatus.PAYMENT_PENDING;
    }

    /**
     * Payment request sent to BBPS.
     */
    public void markPaymentInitiated() {
        assertCanTransitionTo(BillPaymentStatus.PAYMENT_INITIATED);
        this.status = BillPaymentStatus.PAYMENT_INITIATED;

        domainEvents.add(new BillPaymentInitiated(
            this.id, this.customerId, this.billerInfo.billerId(),
            this.paymentAmount, this.agentTransactionId, Instant.now()
        ));
    }

    /**
     * BBPS confirmed successful payment.
     */
    public void recordPaymentCompleted(String bbpsPaymentTransactionId) {
        assertCanTransitionTo(BillPaymentStatus.PAYMENT_COMPLETED);
        Objects.requireNonNull(bbpsPaymentTransactionId, "BBPS payment transaction ID required");

        this.bbpsPaymentTransactionId = bbpsPaymentTransactionId;
        this.status = BillPaymentStatus.PAYMENT_COMPLETED;
        this.completedAt = Instant.now();

        domainEvents.add(new BillPaymentCompleted(
            this.id, this.customerId, this.billerInfo, this.customerIdentifier,
            this.paymentAmount, this.bbpsPaymentTransactionId, this.completedAt
        ));
    }

    /**
     * BBPS reported payment failure.
     */
    public void recordPaymentFailed(String reason) {
        assertCanTransitionTo(BillPaymentStatus.PAYMENT_FAILED);
        this.status = BillPaymentStatus.PAYMENT_FAILED;
        this.failureReason = reason;

        domainEvents.add(new BillPaymentFailed(
            this.id, this.customerId, this.billerInfo.billerId(), reason, Instant.now()
        ));
    }

    public void markTimeout() {
        assertCanTransitionTo(BillPaymentStatus.PAYMENT_TIMEOUT);
        this.status = BillPaymentStatus.PAYMENT_TIMEOUT;
    }

    // ─────────────────── Helpers ───────────────────────────────────────────

    private void assertCanTransitionTo(BillPaymentStatus next) {
        if (!this.status.canTransitionTo(next))
            throw new InvalidBillPaymentStateException(
                "Invalid transition: " + this.status + " → " + next);
    }

    private BillerCategory billerCategory() { return billerInfo.category(); }

    // ─────────────────── Queries ───────────────────────────────────────────

    public BillPaymentOrderId getId() { return id; }
    public UserId getCustomerId() { return customerId; }
    public BillerInfo getBillerInfo() { return billerInfo; }
    public CustomerIdentifier getCustomerIdentifier() { return customerIdentifier; }
    public String getAgentTransactionId() { return agentTransactionId; }
    public BillDetails getFetchedBillDetails() { return fetchedBillDetails; }
    public Money getPaymentAmount() { return paymentAmount; }
    public BillPaymentStatus getStatus() { return status; }
    public String getBbpsPaymentTransactionId() { return bbpsPaymentTransactionId; }
    public long getVersion() { return version; }

    public List<DomainEvent> pullDomainEvents() {
        List<DomainEvent> events = new ArrayList<>(domainEvents);
        domainEvents.clear();
        return Collections.unmodifiableList(events);
    }
}
```

---

## Domain Events

```java
// BillFetched — returned to UI to display bill details
public record BillFetched(
    String eventId,
    BillPaymentOrderId orderId,
    UserId customerId,
    String billerId,
    BillDetails billDetails,
    String fetchTransactionId,
    Instant occurredAt
) implements DomainEvent {
    public BillFetched(BillPaymentOrderId id, UserId uid, String bId,
                        BillDetails details, String txnId, Instant at) {
        this(UUID.randomUUID().toString(), id, uid, bId, details, txnId, at);
    }
    @Override public String eventType() { return "bill.fetched"; }
}

// BillPaymentCompleted — consumed by Notification BC, Audit BC
public record BillPaymentCompleted(
    String eventId,
    BillPaymentOrderId orderId,
    UserId customerId,
    BillerInfo billerInfo,
    CustomerIdentifier customerIdentifier,
    Money amountPaid,
    String bbpsTransactionId,
    Instant occurredAt
) implements DomainEvent {
    @Override public String eventType() { return "bill.payment_completed"; }
}
```

---

## Repository Interface

```java
public interface BillPaymentOrderRepository {
    void save(BillPaymentOrder order);
    Optional<BillPaymentOrder> findById(BillPaymentOrderId id);

    /**
     * Idempotency check — did the user already pay this bill?
     * Uses client-generated idempotency key.
     */
    Optional<BillPaymentOrder> findByIdempotencyKey(String idempotencyKey);

    /**
     * Find orders in PAYMENT_TIMEOUT status for reconciliation.
     */
    List<BillPaymentOrder> findTimeoutOrders();

    /**
     * All bill payments by a user for a date range (for history screen).
     */
    List<BillPaymentOrder> findByCustomerAndDateRange(
        UserId customerId, Instant from, Instant to
    );
}
```

---

## Why Two Separate Methods for `confirmPayment` and `markPaymentInitiated`?

**Question:** Why split user confirmation and BBPS initiation?

**Answer:** Application-layer separation of concerns.

1. `confirmPayment` is synchronous — user taps "Pay ₹2,450". Immediately validates and transitions to PAYMENT_PENDING. No external call yet.
2. `markPaymentInitiated` is called after the application layer sends the async request to BBPS. This prevents: if the BBPS call fails before we even send the request (network issue), the order stays in PAYMENT_PENDING and can be retried.

```
User confirms → [synchronous: confirmPayment] → PAYMENT_PENDING saved to DB
              → [async: send to BBPS ACL] → success: markPaymentInitiated
              →                            → BBPS callback: recordPaymentCompleted/Failed
```

This two-step approach also allows showing the user a "processing..." screen immediately after confirmation, while the BBPS round-trip happens asynchronously.
