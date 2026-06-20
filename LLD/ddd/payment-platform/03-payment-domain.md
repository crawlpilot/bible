# Payment Bounded Context — Domain Model

This is the **core domain**. Every class here is pure Java — no Spring, no JPA, no HTTP client. This layer is independently testable and infrastructure-free.

---

## Package Structure

```
com.paytm.payment.domain/
├── model/
│   ├── payment/
│   │   ├── Payment.java                  ← Aggregate Root
│   │   ├── PaymentId.java                ← Value Object
│   │   ├── PaymentReferenceId.java       ← Value Object (client-generated idempotency key)
│   │   ├── PaymentStatus.java            ← Value Object (state machine)
│   │   ├── PaymentMethod.java            ← sealed interface
│   │   ├── UpiPaymentMethod.java         ← Value Object (implements PaymentMethod)
│   │   ├── CardPaymentMethod.java        ← Value Object (implements PaymentMethod)
│   │   ├── WalletPaymentMethod.java      ← Value Object (implements PaymentMethod)
│   │   ├── Money.java                    ← Value Object (amount + currency)
│   │   ├── Vpa.java                      ← Value Object (UPI Virtual Payment Address)
│   │   ├── MaskedCardNumber.java         ← Value Object (last 4 digits only — PCI-DSS)
│   │   ├── EncryptedCardToken.java       ← Value Object (tokenized card reference)
│   │   ├── PaymentParticipant.java       ← Value Object (payer / payee)
│   │   ├── RiskDecision.java             ← Value Object (from Fraud BC)
│   │   └── RefundDetails.java            ← Value Object
│   └── shared/
│       ├── UserId.java
│       └── DeviceFingerprint.java
├── events/
│   ├── PaymentInitiated.java
│   ├── PaymentProcessingStarted.java
│   ├── PaymentCompleted.java
│   ├── PaymentFailed.java
│   ├── PaymentRefunded.java
│   └── DomainEvent.java                  ← base interface
├── repository/
│   └── PaymentRepository.java            ← interface only
├── service/
│   ├── PaymentLimitService.java          ← domain service
│   └── PaymentIdempotencyService.java    ← domain service
└── exception/
    ├── PaymentNotFoundException.java
    ├── InvalidPaymentStateException.java
    ├── PaymentLimitExceededException.java
    └── DuplicatePaymentException.java
```

---

## Value Objects

### Money — the Most Critical Value Object

```java
package com.paytm.payment.domain.model.payment;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Currency;
import java.util.Objects;

/**
 * Represents an amount of money in a specific currency.
 * Immutable. Equality by value. Never use double/float for money.
 *
 * Production constraint: all amounts stored with 2 decimal places.
 * BigDecimal.ROUND_HALF_UP matches Indian banking regulation.
 */
public final class Money {
    private static final int SCALE = 2;
    private static final RoundingMode ROUNDING = RoundingMode.HALF_UP;

    private final BigDecimal amount;
    private final Currency currency;

    private Money(BigDecimal amount, Currency currency) {
        if (amount == null) throw new IllegalArgumentException("Amount cannot be null");
        if (currency == null) throw new IllegalArgumentException("Currency cannot be null");
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("Amount cannot be negative: " + amount);
        this.amount = amount.setScale(SCALE, ROUNDING);
        this.currency = currency;
    }

    public static Money of(BigDecimal amount, String currencyCode) {
        return new Money(amount, Currency.getInstance(currencyCode));
    }

    public static Money ofInr(BigDecimal amount) {
        return of(amount, "INR");
    }

    public static Money ofInr(String amount) {
        return ofInr(new BigDecimal(amount));
    }

    public static Money zero(String currencyCode) {
        return of(BigDecimal.ZERO, currencyCode);
    }

    public Money add(Money other) {
        assertSameCurrency(other);
        return new Money(this.amount.add(other.amount), this.currency);
    }

    public Money subtract(Money other) {
        assertSameCurrency(other);
        BigDecimal result = this.amount.subtract(other.amount);
        if (result.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("Subtraction results in negative: " + result);
        return new Money(result, this.currency);
    }

    public boolean isGreaterThan(Money other) {
        assertSameCurrency(other);
        return this.amount.compareTo(other.amount) > 0;
    }

    public boolean isGreaterThanOrEqual(Money other) {
        assertSameCurrency(other);
        return this.amount.compareTo(other.amount) >= 0;
    }

    public boolean isZero() {
        return this.amount.compareTo(BigDecimal.ZERO) == 0;
    }

    private void assertSameCurrency(Money other) {
        if (!this.currency.equals(other.currency))
            throw new IllegalArgumentException(
                "Currency mismatch: " + this.currency + " vs " + other.currency);
    }

    public BigDecimal getAmount() { return amount; }
    public Currency getCurrency() { return currency; }
    public String getCurrencyCode() { return currency.getCurrencyCode(); }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Money m)) return false;
        return amount.compareTo(m.amount) == 0 && currency.equals(m.currency);
    }

    @Override
    public int hashCode() { return Objects.hash(amount.stripTrailingZeros(), currency); }

    @Override
    public String toString() { return currency.getCurrencyCode() + " " + amount.toPlainString(); }
}
```

### PaymentId — Identity Value Object

```java
package com.paytm.payment.domain.model.payment;

import java.util.Objects;
import java.util.UUID;

/**
 * System-generated unique identifier for a Payment.
 * Uses UUID v7 (time-ordered) for database index efficiency.
 */
public final class PaymentId {
    private final String value;

    private PaymentId(String value) {
        if (value == null || value.isBlank())
            throw new IllegalArgumentException("PaymentId cannot be blank");
        this.value = value;
    }

    public static PaymentId generate() {
        // UUID v7 is time-ordered — better B-tree index performance than random UUID v4
        // Using UUID.randomUUID() here; in production, use a UUID v7 library (e.g., uuid-creator)
        return new PaymentId("PAY-" + UUID.randomUUID().toString().replace("-", "").toUpperCase());
    }

    public static PaymentId of(String value) {
        return new PaymentId(value);
    }

    public String getValue() { return value; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof PaymentId p)) return false;
        return value.equals(p.value);
    }

    @Override
    public int hashCode() { return Objects.hash(value); }

    @Override
    public String toString() { return value; }
}
```

### PaymentReferenceId — Client-Generated Idempotency Key

```java
package com.paytm.payment.domain.model.payment;

/**
 * Client-generated idempotency key. The mobile app generates this UUID before
 * initiating a payment. If the network call fails and the app retries, the same
 * referenceId ensures the payment is not processed twice.
 *
 * Production rule: store this with a UNIQUE constraint in DB.
 * Any retry with the same referenceId returns the existing payment, not a new one.
 */
public final class PaymentReferenceId {
    private final String value;

    private PaymentReferenceId(String value) {
        if (value == null || value.isBlank())
            throw new IllegalArgumentException("ReferenceId cannot be blank");
        if (value.length() > 64)
            throw new IllegalArgumentException("ReferenceId too long (max 64): " + value.length());
        this.value = value;
    }

    public static PaymentReferenceId of(String value) { return new PaymentReferenceId(value); }
    public String getValue() { return value; }

    @Override
    public boolean equals(Object o) {
        if (!(o instanceof PaymentReferenceId r)) return false;
        return value.equals(r.value);
    }
    @Override public int hashCode() { return value.hashCode(); }
    @Override public String toString() { return value; }
}
```

### VPA — Virtual Payment Address (UPI)

```java
package com.paytm.payment.domain.model.payment;

import java.util.regex.Pattern;

/**
 * UPI Virtual Payment Address (VPA): "user@bankname" format.
 * Examples: rahul@okicici, 9876543210@paytm, merchant@ybl
 *
 * Domain rule: VPA must contain exactly one '@', have non-empty handle and provider.
 */
public final class Vpa {
    // Regex from NPCI VPA specification (simplified)
    private static final Pattern VPA_PATTERN = Pattern.compile("^[a-zA-Z0-9.\\-_]+@[a-zA-Z]{2,}$");

    private final String handle;    // part before @
    private final String provider;  // part after @ (okicici, paytm, ybl, etc.)

    private Vpa(String handle, String provider) {
        this.handle = handle;
        this.provider = provider;
    }

    public static Vpa of(String vpa) {
        if (vpa == null || !VPA_PATTERN.matcher(vpa).matches())
            throw new IllegalArgumentException("Invalid VPA format: " + vpa);
        int atIndex = vpa.indexOf('@');
        return new Vpa(vpa.substring(0, atIndex), vpa.substring(atIndex + 1));
    }

    public String getFullAddress() { return handle + "@" + provider; }
    public String getHandle() { return handle; }
    public String getProvider() { return provider; }

    @Override
    public boolean equals(Object o) {
        if (!(o instanceof Vpa v)) return false;
        // VPAs are case-insensitive per NPCI spec
        return getFullAddress().equalsIgnoreCase(v.getFullAddress());
    }
    @Override public int hashCode() { return getFullAddress().toLowerCase().hashCode(); }
    @Override public String toString() { return getFullAddress(); }
}
```

### PaymentMethod — sealed interface (polymorphic payment types)

```java
package com.paytm.payment.domain.model.payment;

/**
 * Sealed interface: exactly three payment method types are allowed.
 * Java 17 sealed interfaces enable exhaustive pattern matching —
 * the compiler ensures every switch handles all cases.
 */
public sealed interface PaymentMethod permits UpiPaymentMethod, CardPaymentMethod, WalletPaymentMethod {
    String getMethodType();
}

// --- UPI Payment Method ---
public record UpiPaymentMethod(
    Vpa payerVpa,
    Vpa payeeVpa,
    String upiTransactionNote    // free-text note, max 50 chars
) implements PaymentMethod {

    public UpiPaymentMethod {
        if (payerVpa == null) throw new IllegalArgumentException("Payer VPA required");
        if (payeeVpa == null) throw new IllegalArgumentException("Payee VPA required");
        if (payerVpa.equals(payeeVpa))
            throw new IllegalArgumentException("Payer and payee VPA cannot be the same");
        if (upiTransactionNote != null && upiTransactionNote.length() > 50)
            throw new IllegalArgumentException("Note too long");
    }

    @Override
    public String getMethodType() { return "UPI"; }
}

// --- Card Payment Method ---
public record CardPaymentMethod(
    EncryptedCardToken cardToken,     // tokenized by our vault (never store raw PAN)
    MaskedCardNumber maskedNumber,    // last 4 digits only — for display
    CardNetwork network,              // VISA, MASTERCARD, RUPAY, AMEX
    CardType cardType,                // CREDIT, DEBIT
    String bankIssuerName
) implements PaymentMethod {

    @Override
    public String getMethodType() { return "CARD"; }
}

// --- Wallet Payment Method ---
public record WalletPaymentMethod(
    UserId walletOwner,
    WalletId walletId
) implements PaymentMethod {

    @Override
    public String getMethodType() { return "WALLET"; }
}
```

### PaymentStatus — State Machine as Value Object

```java
package com.paytm.payment.domain.model.payment;

import java.util.Set;
import java.util.Map;

/**
 * Payment lifecycle state machine.
 *
 * Valid transitions:
 *   INITIATED    → RISK_CHECKING, CANCELLED
 *   RISK_CHECKING → PROCESSING, BLOCKED
 *   PROCESSING   → COMPLETED, FAILED, TIMEOUT
 *   TIMEOUT      → PROCESSING (on NPCI callback), FAILED (after reconciliation)
 *   COMPLETED    → REFUND_INITIATED
 *   REFUND_INITIATED → REFUNDED, REFUND_FAILED
 *   FAILED, BLOCKED, CANCELLED, REFUNDED, REFUND_FAILED → terminal (no transitions)
 */
public enum PaymentStatus {
    INITIATED, RISK_CHECKING, PROCESSING, COMPLETED,
    FAILED, TIMEOUT, BLOCKED, CANCELLED,
    REFUND_INITIATED, REFUNDED, REFUND_FAILED;

    private static final Map<PaymentStatus, Set<PaymentStatus>> VALID_TRANSITIONS = Map.of(
        INITIATED,        Set.of(RISK_CHECKING, CANCELLED),
        RISK_CHECKING,    Set.of(PROCESSING, BLOCKED),
        PROCESSING,       Set.of(COMPLETED, FAILED, TIMEOUT),
        TIMEOUT,          Set.of(PROCESSING, FAILED),
        COMPLETED,        Set.of(REFUND_INITIATED),
        REFUND_INITIATED, Set.of(REFUNDED, REFUND_FAILED)
    );

    public boolean canTransitionTo(PaymentStatus next) {
        return VALID_TRANSITIONS.getOrDefault(this, Set.of()).contains(next);
    }

    public boolean isTerminal() {
        return Set.of(COMPLETED, FAILED, BLOCKED, CANCELLED, REFUNDED, REFUND_FAILED).contains(this);
    }

    public boolean isSuccessful() { return this == COMPLETED || this == REFUNDED; }
}
```

---

## The Payment Aggregate Root

This is the most important class in the system. It:
1. Enforces all payment lifecycle invariants
2. Emits domain events for every state change
3. Exposes no public setters — all mutation via domain methods
4. Is the only entry point to its contained value objects

```java
package com.paytm.payment.domain.model.payment;

import com.paytm.payment.domain.events.*;
import java.time.Instant;
import java.util.*;

/**
 * Payment Aggregate Root.
 *
 * Design decisions:
 * 1. All state changes go through named domain methods (initiate, approve, complete, fail)
 * 2. Each state change emits a domain event — consumed by other bounded contexts
 * 3. No setters — mutation is explicit and business-named
 * 4. Version field for optimistic locking (prevents lost-update in concurrent scenarios)
 * 5. Events are accumulated in a list, published AFTER the DB commit (outbox pattern)
 */
public class Payment {

    // Identity
    private final PaymentId id;
    private final PaymentReferenceId referenceId; // client idempotency key, unique

    // Core state
    private PaymentStatus status;
    private final Money amount;
    private final PaymentMethod paymentMethod;
    private final PaymentParticipant payer;
    private final PaymentParticipant payee;

    // Lifecycle timestamps
    private final Instant initiatedAt;
    private Instant processingStartedAt;
    private Instant completedAt;
    private Instant failedAt;

    // Settlement
    private String npciTransactionId;       // NPCI/bank's reference; null until PROCESSING
    private String settlementBatchId;       // populated during nightly settlement

    // Failure context
    private String failureReason;
    private String failureCode;             // standardized codes for retry decisions

    // Refund
    private RefundDetails refundDetails;    // null unless refund initiated

    // Risk
    private RiskDecision riskDecision;

    // Concurrency control
    private long version;                   // incremented on every save (optimistic lock)

    // Domain events — published AFTER transaction commits
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // ─────────────────────── Factory / Constructor ──────────────────────────

    /**
     * The only way to create a new Payment. Enforces all creation invariants.
     */
    public static Payment initiate(
        PaymentReferenceId referenceId,
        Money amount,
        PaymentMethod paymentMethod,
        PaymentParticipant payer,
        PaymentParticipant payee
    ) {
        validateInitiationPreConditions(amount, paymentMethod, payer, payee);

        Payment payment = new Payment();
        payment.id = PaymentId.generate();
        payment.referenceId = referenceId;
        payment.amount = amount;
        payment.paymentMethod = paymentMethod;
        payment.payer = payer;
        payment.payee = payee;
        payment.status = PaymentStatus.INITIATED;
        payment.initiatedAt = Instant.now();
        payment.version = 0L;

        payment.domainEvents.add(new PaymentInitiated(
            payment.id, payment.referenceId, payment.amount,
            payment.paymentMethod.getMethodType(), payment.payer.userId(),
            payment.payee.userId(), payment.initiatedAt
        ));

        return payment;
    }

    // ─────────────────────── Domain Methods (State Machine) ─────────────────

    /**
     * Move to RISK_CHECKING. Called when fraud service starts evaluating.
     */
    public void startRiskCheck() {
        assertCanTransitionTo(PaymentStatus.RISK_CHECKING);
        this.status = PaymentStatus.RISK_CHECKING;
    }

    /**
     * Risk check passed. Move to PROCESSING.
     */
    public void approveRisk(RiskDecision riskDecision) {
        assertCanTransitionTo(PaymentStatus.PROCESSING);
        if (!riskDecision.isApproved())
            throw new InvalidPaymentStateException("Cannot approve payment with rejected risk decision");
        this.riskDecision = riskDecision;
        this.status = PaymentStatus.PROCESSING;
        this.processingStartedAt = Instant.now();

        domainEvents.add(new PaymentProcessingStarted(
            this.id, this.amount, this.paymentMethod.getMethodType(), this.processingStartedAt
        ));
    }

    /**
     * Fraud service blocked this payment.
     */
    public void blockForRisk(RiskDecision riskDecision) {
        assertCanTransitionTo(PaymentStatus.BLOCKED);
        this.riskDecision = riskDecision;
        this.status = PaymentStatus.BLOCKED;
        this.failureReason = "Blocked by fraud prevention";
        this.failureCode = "FRAUD_BLOCK";
        this.failedAt = Instant.now();

        domainEvents.add(new PaymentFailed(
            this.id, this.failureCode, this.failureReason, Instant.now()
        ));
    }

    /**
     * NPCI/Bank confirmed successful debit and credit.
     */
    public void complete(String npciTransactionId) {
        assertCanTransitionTo(PaymentStatus.COMPLETED);
        if (npciTransactionId == null || npciTransactionId.isBlank())
            throw new IllegalArgumentException("NPCI transaction ID required for completion");

        this.npciTransactionId = npciTransactionId;
        this.status = PaymentStatus.COMPLETED;
        this.completedAt = Instant.now();

        domainEvents.add(new PaymentCompleted(
            this.id, this.referenceId, this.amount, this.paymentMethod.getMethodType(),
            this.payer.userId(), this.payee.userId(), this.npciTransactionId, this.completedAt
        ));
    }

    /**
     * NPCI/Bank confirmed failure.
     */
    public void fail(String failureCode, String failureReason) {
        assertCanTransitionTo(PaymentStatus.FAILED);
        this.failureCode = Objects.requireNonNull(failureCode, "Failure code required");
        this.failureReason = Objects.requireNonNull(failureReason, "Failure reason required");
        this.status = PaymentStatus.FAILED;
        this.failedAt = Instant.now();

        domainEvents.add(new PaymentFailed(this.id, this.failureCode, this.failureReason, this.failedAt));
    }

    /**
     * NPCI did not respond within SLA. Move to TIMEOUT for async reconciliation.
     * This is a key production scenario: the payment may have actually succeeded at NPCI
     * but we didn't receive the callback. Never assume TIMEOUT = FAILED.
     */
    public void markTimeout() {
        assertCanTransitionTo(PaymentStatus.TIMEOUT);
        this.status = PaymentStatus.TIMEOUT;
        this.failureCode = "TIMEOUT";
    }

    /**
     * Called during reconciliation when we discover a TIMEOUT payment actually completed.
     */
    public void reconcileAsCompleted(String npciTransactionId) {
        if (this.status != PaymentStatus.TIMEOUT)
            throw new InvalidPaymentStateException(
                "Can only reconcile TIMEOUT payments, but status is: " + this.status);
        complete(npciTransactionId);
    }

    /**
     * Initiate a refund for a COMPLETED payment.
     * Production rule: refund must happen within 180 days of payment.
     */
    public void initiateRefund(Money refundAmount, String refundReason, UserId initiatedBy) {
        assertCanTransitionTo(PaymentStatus.REFUND_INITIATED);

        if (this.completedAt == null)
            throw new InvalidPaymentStateException("Cannot refund: payment not completed");
        if (refundAmount.isGreaterThan(this.amount))
            throw new IllegalArgumentException("Refund amount exceeds original payment amount");

        long daysSincePayment = java.time.Duration.between(completedAt, Instant.now()).toDays();
        if (daysSincePayment > 180)
            throw new InvalidPaymentStateException("Refund window expired (180 days)");

        this.status = PaymentStatus.REFUND_INITIATED;
        this.refundDetails = new RefundDetails(
            PaymentId.generate(), refundAmount, refundReason, initiatedBy, Instant.now()
        );

        domainEvents.add(new PaymentRefundInitiated(
            this.id, this.refundDetails.refundId(), refundAmount, refundReason, Instant.now()
        ));
    }

    /**
     * User-initiated cancel (only valid in INITIATED status — before risk check).
     */
    public void cancel(String reason) {
        assertCanTransitionTo(PaymentStatus.CANCELLED);
        this.status = PaymentStatus.CANCELLED;
        this.failureReason = reason;
        this.failedAt = Instant.now();
    }

    // ─────────────────────── Invariant Enforcement ──────────────────────────

    private void assertCanTransitionTo(PaymentStatus next) {
        if (!this.status.canTransitionTo(next))
            throw new InvalidPaymentStateException(
                "Invalid transition: " + this.status + " → " + next +
                " for payment " + this.id
            );
    }

    private static void validateInitiationPreConditions(
        Money amount, PaymentMethod method, PaymentParticipant payer, PaymentParticipant payee
    ) {
        Objects.requireNonNull(amount, "Amount required");
        Objects.requireNonNull(method, "Payment method required");
        Objects.requireNonNull(payer, "Payer required");
        Objects.requireNonNull(payee, "Payee required");

        if (amount.isZero())
            throw new IllegalArgumentException("Payment amount cannot be zero");

        Money maxSingleTransaction = Money.ofInr("100000"); // RBI UPI limit ₹1L
        if (amount.isGreaterThan(maxSingleTransaction))
            throw new PaymentLimitExceededException(
                "Amount " + amount + " exceeds maximum allowed " + maxSingleTransaction
            );
    }

    // ─────────────────────── Event Collection ────────────────────────────────

    /**
     * Called by Application Layer AFTER the transaction commits.
     * Events are then published to Kafka.
     * Clears the list to prevent duplicate publishing.
     */
    public List<DomainEvent> pullDomainEvents() {
        List<DomainEvent> events = new ArrayList<>(domainEvents);
        domainEvents.clear();
        return Collections.unmodifiableList(events);
    }

    // ─────────────────────── Query Methods ───────────────────────────────────

    public PaymentId getId() { return id; }
    public PaymentReferenceId getReferenceId() { return referenceId; }
    public PaymentStatus getStatus() { return status; }
    public Money getAmount() { return amount; }
    public PaymentMethod getPaymentMethod() { return paymentMethod; }
    public PaymentParticipant getPayer() { return payer; }
    public PaymentParticipant getPayee() { return payee; }
    public Instant getInitiatedAt() { return initiatedAt; }
    public Instant getCompletedAt() { return completedAt; }
    public String getNpciTransactionId() { return npciTransactionId; }
    public String getFailureCode() { return failureCode; }
    public RefundDetails getRefundDetails() { return refundDetails; }
    public long getVersion() { return version; }

    public boolean isUpiPayment() { return paymentMethod instanceof UpiPaymentMethod; }
    public boolean isCardPayment() { return paymentMethod instanceof CardPaymentMethod; }
    public boolean isWalletPayment() { return paymentMethod instanceof WalletPaymentMethod; }
    public boolean isCompleted() { return status.isSuccessful(); }
    public boolean isTerminal() { return status.isTerminal(); }
}
```

---

## Domain Events

```java
package com.paytm.payment.domain.events;

import java.time.Instant;
import java.util.UUID;

// Base interface — all events are immutable records
public interface DomainEvent {
    String eventId();        // unique event ID
    String eventType();      // for Kafka topic routing
    Instant occurredAt();
}

// ─── Payment Initiated ───
public record PaymentInitiated(
    String eventId,
    PaymentId paymentId,
    PaymentReferenceId referenceId,
    Money amount,
    String paymentMethodType,
    UserId payerId,
    UserId payeeId,
    Instant occurredAt
) implements DomainEvent {
    public PaymentInitiated(PaymentId id, PaymentReferenceId ref, Money amount,
                             String method, UserId payer, UserId payee, Instant at) {
        this(UUID.randomUUID().toString(), id, ref, amount, method, payer, payee, at);
    }
    @Override public String eventType() { return "payment.initiated"; }
}

// ─── Payment Processing Started ───
public record PaymentProcessingStarted(
    String eventId,
    PaymentId paymentId,
    Money amount,
    String paymentMethodType,
    Instant occurredAt
) implements DomainEvent {
    public PaymentProcessingStarted(PaymentId id, Money amount, String method, Instant at) {
        this(UUID.randomUUID().toString(), id, amount, method, at);
    }
    @Override public String eventType() { return "payment.processing_started"; }
}

// ─── Payment Completed ───
public record PaymentCompleted(
    String eventId,
    PaymentId paymentId,
    PaymentReferenceId referenceId,
    Money amount,
    String paymentMethodType,
    UserId payerId,
    UserId payeeId,
    String npciTransactionId,
    Instant occurredAt
) implements DomainEvent {
    public PaymentCompleted(PaymentId id, PaymentReferenceId ref, Money amount,
                             String method, UserId payer, UserId payee,
                             String npciTxnId, Instant at) {
        this(UUID.randomUUID().toString(), id, ref, amount, method, payer, payee, npciTxnId, at);
    }
    @Override public String eventType() { return "payment.completed"; }
}

// ─── Payment Failed ───
public record PaymentFailed(
    String eventId,
    PaymentId paymentId,
    String failureCode,
    String failureReason,
    Instant occurredAt
) implements DomainEvent {
    public PaymentFailed(PaymentId id, String code, String reason, Instant at) {
        this(UUID.randomUUID().toString(), id, code, reason, at);
    }
    @Override public String eventType() { return "payment.failed"; }
}

// ─── Payment Refund Initiated ───
public record PaymentRefundInitiated(
    String eventId,
    PaymentId originalPaymentId,
    PaymentId refundId,
    Money refundAmount,
    String reason,
    Instant occurredAt
) implements DomainEvent {
    public PaymentRefundInitiated(PaymentId original, PaymentId refundId, Money amount,
                                   String reason, Instant at) {
        this(UUID.randomUUID().toString(), original, refundId, amount, reason, at);
    }
    @Override public String eventType() { return "payment.refund_initiated"; }
}
```

---

## Repository Interface (Domain Layer)

```java
package com.paytm.payment.domain.repository;

import java.util.Optional;
import java.time.LocalDate;
import java.util.List;

/**
 * Repository interface lives in the DOMAIN layer.
 * Implementation lives in the INFRASTRUCTURE layer (JPA, DynamoDB, etc.).
 *
 * This interface speaks the domain language — not SQL, not JPA.
 */
public interface PaymentRepository {

    /**
     * Save a new payment or update existing. Throws on version conflict (optimistic lock).
     */
    void save(Payment payment);

    Optional<Payment> findById(PaymentId id);

    /**
     * Critical for idempotency — if referenceId already exists, return existing payment.
     */
    Optional<Payment> findByReferenceId(PaymentReferenceId referenceId);

    /**
     * Find payments in TIMEOUT state for reconciliation job.
     */
    List<Payment> findTimeoutPayments();

    /**
     * Find all payments for a user on a given date — for daily limit calculation.
     */
    List<Payment> findCompletedPaymentsForUserOnDate(UserId userId, LocalDate date);

    /**
     * For reconciliation — find payments by NPCI transaction ID.
     */
    Optional<Payment> findByNpciTransactionId(String npciTransactionId);
}
```

---

## Domain Service: PaymentLimitService

```java
package com.paytm.payment.domain.service;

import java.time.LocalDate;

/**
 * Domain Service: calculates whether a user has exceeded their daily payment limits.
 *
 * This logic spans multiple aggregates (Payment history + UserKycProfile) and doesn't
 * naturally belong to any single aggregate — classic domain service use case.
 *
 * Note: this is a pure domain service — no HTTP calls, no DB calls here.
 * It works with domain objects passed in. The application layer provides the data.
 */
public class PaymentLimitService {

    /**
     * UPI daily limit per RBI regulation: ₹1,00,000 per user per day.
     * Per-transaction limit: ₹1,00,000.
     */
    private static final Money UPI_DAILY_LIMIT = Money.ofInr("100000");

    /**
     * @param requestedAmount   the new payment being initiated
     * @param todayUsage        sum of COMPLETED UPI payments today for this user
     * @param kycProfile        the user's KYC-determined limits
     */
    public void assertWithinUpiLimits(
        Money requestedAmount,
        Money todayUsage,
        UserKycProfile kycProfile
    ) {
        // RBI hard limit
        if (requestedAmount.isGreaterThan(UPI_DAILY_LIMIT))
            throw new PaymentLimitExceededException(
                "Single UPI transaction exceeds RBI limit of " + UPI_DAILY_LIMIT
            );

        // KYC-derived user limit (Minimal KYC: ₹10k/day; Full KYC: ₹1L/day)
        Money userDailyLimit = kycProfile.getDailyUpiLimit();
        Money projectedTotal = todayUsage.add(requestedAmount);

        if (projectedTotal.isGreaterThan(userDailyLimit))
            throw new PaymentLimitExceededException(
                "Daily UPI limit of " + userDailyLimit + " exceeded. " +
                "Already spent: " + todayUsage + ", Requested: " + requestedAmount
            );
    }
}
```

---

## Supporting Value Objects

```java
// PaymentParticipant — represents payer or payee
public record PaymentParticipant(
    UserId userId,
    String displayName,      // cached name for display (e.g., "Rahul B.")
    String accountIdentifier // VPA for UPI, masked card for card, walletId for wallet
) {}

// RiskDecision — from Fraud BC (ACL translates Fraud model to this)
public record RiskDecision(
    String sessionId,
    double riskScore,        // 0.0 = no risk, 1.0 = certain fraud
    RiskOutcome outcome,     // ALLOW, CHALLENGE, BLOCK
    String reason
) {
    public boolean isApproved() { return outcome == RiskOutcome.ALLOW; }
    public boolean requiresChallenge() { return outcome == RiskOutcome.CHALLENGE; }
}

public enum RiskOutcome { ALLOW, CHALLENGE, BLOCK }

// RefundDetails
public record RefundDetails(
    PaymentId refundId,
    Money refundAmount,
    String reason,
    UserId initiatedBy,
    Instant initiatedAt
) {}
```
