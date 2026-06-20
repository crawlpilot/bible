# Wallet Bounded Context — Domain Model

The Wallet BC is responsible for the virtual wallet balance — money that lives inside our platform. It is a **core domain** because the wallet experience (cashback, offers, instant transfers) is a key differentiator.

---

## Package Structure

```
com.paytm.wallet.domain/
├── model/
│   ├── Wallet.java                    ← Aggregate Root
│   ├── WalletId.java                  ← Value Object
│   ├── WalletTransaction.java         ← Entity (child of Wallet)
│   ├── WalletTransactionId.java       ← Value Object
│   ├── WalletTransactionType.java     ← Enum
│   ├── WalletStatus.java              ← Enum
│   ├── Money.java                     ← Value Object (shared kernel from Payment BC)
│   └── KycLimit.java                  ← Value Object
├── events/
│   ├── WalletCreated.java
│   ├── MoneyAdded.java
│   ├── MoneyDeducted.java
│   ├── MoneyHeld.java
│   ├── HoldReleased.java
│   ├── WalletSuspended.java
│   └── WalletClosed.java
├── repository/
│   └── WalletRepository.java
└── service/
    └── WalletKycLimitService.java
```

---

## Wallet Domain — Key Invariants

Before writing code, state the invariants the aggregate must protect:

1. **Balance can never go below zero** — no overdraft in a wallet
2. **KYC Minimal users cannot hold > ₹10,000** in wallet at any time (RBI rule)
3. **KYC Minimal users cannot transact > ₹10,000/month** from wallet (RBI rule)
4. **A suspended wallet cannot transact** (fraud/compliance hold)
5. **Money holds must be released or applied** — no permanently held funds
6. **Transaction log is append-only** — history is never deleted or modified

---

## Value Objects

### WalletId

```java
package com.paytm.wallet.domain.model;

import java.util.UUID;

public final class WalletId {
    private final String value;

    private WalletId(String value) {
        if (value == null || value.isBlank())
            throw new IllegalArgumentException("WalletId cannot be blank");
        this.value = value;
    }

    public static WalletId generate() {
        return new WalletId("WLT-" + UUID.randomUUID().toString().replace("-", "").toUpperCase());
    }

    public static WalletId of(String value) { return new WalletId(value); }

    public String getValue() { return value; }

    @Override public boolean equals(Object o) {
        if (!(o instanceof WalletId w)) return false;
        return value.equals(w.value);
    }
    @Override public int hashCode() { return value.hashCode(); }
    @Override public String toString() { return value; }
}
```

### KycLimit — encapsulates RBI-mandated limits per KYC level

```java
package com.paytm.wallet.domain.model;

/**
 * RBI Prepaid Payment Instrument (PPI) limits by KYC level.
 * Source: RBI Master Direction on Prepaid Payment Instruments (2017, updated 2023)
 *
 * MINIMAL KYC: Mobile number + OTP verified only
 *   - Max balance: ₹10,000
 *   - Monthly spending limit: ₹10,000
 *   - Can only top-up from bank (not receive P2P)
 *
 * FULL KYC (Aadhaar or PAN verified):
 *   - Max balance: ₹2,00,000
 *   - No monthly spending limit for card-funded wallets
 *   - Can send/receive P2P
 */
public enum KycLevel {
    MINIMAL(
        Money.ofInr("10000"),   // max balance
        Money.ofInr("10000"),   // monthly spend limit
        false                    // P2P allowed
    ),
    FULL(
        Money.ofInr("200000"),  // max balance
        null,                    // no monthly limit for FULL KYC
        true                     // P2P allowed
    ),
    ENHANCED(
        Money.ofInr("200000"),  // same as FULL for wallet purposes
        null,
        true
    );

    private final Money maxBalance;
    private final Money monthlySpendLimit;  // null = no limit
    private final boolean p2pAllowed;

    KycLevel(Money maxBalance, Money monthlySpendLimit, boolean p2pAllowed) {
        this.maxBalance = maxBalance;
        this.monthlySpendLimit = monthlySpendLimit;
        this.p2pAllowed = p2pAllowed;
    }

    public Money getMaxBalance() { return maxBalance; }
    public boolean hasMonthlyLimit() { return monthlySpendLimit != null; }
    public Money getMonthlySpendLimit() { return monthlySpendLimit; }
    public boolean isP2pAllowed() { return p2pAllowed; }
}
```

---

## WalletTransaction — Entity (child of Wallet aggregate)

```java
package com.paytm.wallet.domain.model;

import java.time.Instant;

/**
 * An individual debit or credit on the wallet.
 *
 * Entity: has its own identity (WalletTransactionId).
 * Part of the Wallet aggregate — cannot be created or accessed outside of Wallet.
 * Immutable after creation — the ledger entry is never modified.
 *
 * Production note: we store running balance at the time of transaction.
 * This allows reconstructing balance for any point in time without replaying all transactions.
 */
public class WalletTransaction {

    private final WalletTransactionId id;
    private final WalletTransactionType type;
    private final Money amount;
    private final Money balanceAfter;            // running balance snapshot
    private final String externalReferenceId;   // payment ID, topup ID, etc.
    private final String description;           // human-readable
    private final Instant createdAt;

    // Package-private constructor — only Wallet can create transactions
    WalletTransaction(
        WalletTransactionId id,
        WalletTransactionType type,
        Money amount,
        Money balanceAfter,
        String externalReferenceId,
        String description
    ) {
        this.id = id;
        this.type = type;
        this.amount = amount;
        this.balanceAfter = balanceAfter;
        this.externalReferenceId = externalReferenceId;
        this.description = description;
        this.createdAt = Instant.now();
    }

    public WalletTransactionId getId() { return id; }
    public WalletTransactionType getType() { return type; }
    public Money getAmount() { return amount; }
    public Money getBalanceAfter() { return balanceAfter; }
    public String getExternalReferenceId() { return externalReferenceId; }
    public String getDescription() { return description; }
    public Instant getCreatedAt() { return createdAt; }
}

public enum WalletTransactionType {
    CREDIT_TOPUP,        // add money from bank
    CREDIT_CASHBACK,     // cashback from offer
    CREDIT_REFUND,       // refund from payment
    CREDIT_P2P_RECEIVE,  // received from another user
    DEBIT_PAYMENT,       // paid for something
    DEBIT_P2P_SEND,      // sent to another user
    DEBIT_HOLD,          // funds held for pending payment
    CREDIT_HOLD_RELEASE, // hold released (payment failed/cancelled)
    DEBIT_EXPIRY         // funds expired per RBI rule (unused wallet money after 1 year)
}
```

---

## The Wallet Aggregate Root

```java
package com.paytm.wallet.domain.model;

import com.paytm.wallet.domain.events.*;
import java.time.Instant;
import java.time.YearMonth;
import java.util.*;

/**
 * Wallet Aggregate Root.
 *
 * Key design decisions:
 *
 * 1. BALANCE AS SNAPSHOT: balance is stored directly on the aggregate.
 *    Alternative (event-sourced: replay all transactions to get balance) would be
 *    too slow for a 1M-transaction wallet. Snapshot + transaction log is the pragmatic choice.
 *
 * 2. HOLDS: before a payment is confirmed, we hold (reserve) funds.
 *    This prevents double-spending without locking the wallet row for the duration of
 *    the NPCI round-trip (which can take 20-30 seconds).
 *
 * 3. TRANSACTION LOG: WalletTransaction entities are created by the Wallet aggregate.
 *    External code cannot create WalletTransactions directly — they're always a side-effect
 *    of a wallet operation.
 *
 * 4. MONTHLY SPENDING: we accumulate monthly spend as a field to avoid querying
 *    transaction history on every debit (expensive at scale).
 *
 * 5. OPTIMISTIC LOCKING: version field prevents concurrent double-debits.
 */
public class Wallet {

    private final WalletId id;
    private final UserId ownerId;
    private Money balance;
    private Money heldAmount;          // funds reserved for in-flight payments
    private Money monthlySpent;        // rolling monthly total for KYC limit
    private YearMonth monthlySpentFor; // which month monthlySpent belongs to
    private KycLevel kycLevel;
    private WalletStatus status;
    private final Instant createdAt;
    private Instant suspendedAt;
    private String suspensionReason;
    private long version;

    // Child entities — loaded with the aggregate
    private final List<WalletTransaction> transactions = new ArrayList<>();
    private final List<DomainEvent> domainEvents = new ArrayList<>();

    // ─────────────────── Factory ──────────────────────────────────────────

    public static Wallet open(UserId ownerId, KycLevel kycLevel) {
        Objects.requireNonNull(ownerId, "Owner ID required");
        Objects.requireNonNull(kycLevel, "KYC level required");

        Wallet wallet = new Wallet();
        wallet.id = WalletId.generate();
        wallet.ownerId = ownerId;
        wallet.balance = Money.zero("INR");
        wallet.heldAmount = Money.zero("INR");
        wallet.monthlySpent = Money.zero("INR");
        wallet.monthlySpentFor = YearMonth.now();
        wallet.kycLevel = kycLevel;
        wallet.status = WalletStatus.ACTIVE;
        wallet.createdAt = Instant.now();
        wallet.version = 0L;

        wallet.domainEvents.add(new WalletCreated(wallet.id, ownerId, kycLevel, wallet.createdAt));
        return wallet;
    }

    // ─────────────────── Core Operations ──────────────────────────────────

    /**
     * Add money to wallet (top-up from bank account, cashback, refund, P2P receive).
     *
     * Business rules:
     * - Wallet must be ACTIVE
     * - After credit, balance must not exceed KYC max balance limit
     * - P2P credits require FULL or ENHANCED KYC
     */
    public void credit(
        Money amount,
        WalletTransactionType creditType,
        String externalReferenceId,
        String description
    ) {
        assertActive();
        Objects.requireNonNull(amount, "Amount required");

        if (creditType == WalletTransactionType.CREDIT_P2P_RECEIVE && !kycLevel.isP2pAllowed())
            throw new WalletKycViolationException(
                "P2P receive not allowed for KYC level: " + kycLevel);

        Money newBalance = balance.add(amount);

        // KYC max balance check
        if (newBalance.isGreaterThan(kycLevel.getMaxBalance()))
            throw new WalletKycViolationException(
                "Credit of " + amount + " would exceed max balance " +
                kycLevel.getMaxBalance() + " for KYC level " + kycLevel
            );

        this.balance = newBalance;

        WalletTransaction txn = new WalletTransaction(
            WalletTransactionId.generate(), creditType, amount, this.balance,
            externalReferenceId, description
        );
        transactions.add(txn);

        domainEvents.add(new MoneyAdded(
            this.id, this.ownerId, amount, this.balance, creditType, externalReferenceId, Instant.now()
        ));
    }

    /**
     * Deduct money from wallet (payment, P2P send).
     *
     * Business rules:
     * - Wallet must be ACTIVE
     * - Available balance (balance - heldAmount) must cover the debit
     * - Monthly spend limit enforced for MINIMAL KYC users
     */
    public void debit(
        Money amount,
        WalletTransactionType debitType,
        String externalReferenceId,
        String description
    ) {
        assertActive();
        assertSufficientAvailableBalance(amount);
        assertWithinMonthlyLimit(amount);

        if (debitType == WalletTransactionType.DEBIT_P2P_SEND && !kycLevel.isP2pAllowed())
            throw new WalletKycViolationException(
                "P2P send not allowed for KYC level: " + kycLevel);

        this.balance = this.balance.subtract(amount);
        accumMonthlySpent(amount);

        WalletTransaction txn = new WalletTransaction(
            WalletTransactionId.generate(), debitType, amount, this.balance,
            externalReferenceId, description
        );
        transactions.add(txn);

        domainEvents.add(new MoneyDeducted(
            this.id, this.ownerId, amount, this.balance, debitType, externalReferenceId, Instant.now()
        ));
    }

    /**
     * Reserve funds for an in-flight payment.
     *
     * Instead of immediately debiting, we hold the funds. This prevents double-spending
     * during the NPCI round-trip (which can take 10-30 seconds) without locking the wallet
     * row for that entire duration.
     *
     * Pattern: Hold → (Payment succeeds: applyHold) OR (Payment fails: releaseHold)
     */
    public void holdFunds(Money amount, String paymentReferenceId) {
        assertActive();
        assertSufficientAvailableBalance(amount);
        assertWithinMonthlyLimit(amount);

        this.heldAmount = this.heldAmount.add(amount);

        WalletTransaction txn = new WalletTransaction(
            WalletTransactionId.generate(), WalletTransactionType.DEBIT_HOLD, amount,
            getAvailableBalance(), paymentReferenceId, "Hold for payment: " + paymentReferenceId
        );
        transactions.add(txn);

        domainEvents.add(new MoneyHeld(this.id, this.ownerId, amount, getAvailableBalance(),
            paymentReferenceId, Instant.now()));
    }

    /**
     * Confirm held funds as spent (payment completed successfully).
     */
    public void applyHold(Money amount, String paymentReferenceId) {
        assertActive();
        if (heldAmount.isGreaterThan(this.balance))
            throw new InvalidWalletStateException("Held amount exceeds balance — data inconsistency");

        this.heldAmount = this.heldAmount.subtract(amount);
        this.balance = this.balance.subtract(amount);
        accumMonthlySpent(amount);

        WalletTransaction txn = new WalletTransaction(
            WalletTransactionId.generate(), WalletTransactionType.DEBIT_PAYMENT, amount,
            this.balance, paymentReferenceId, "Payment: " + paymentReferenceId
        );
        transactions.add(txn);
    }

    /**
     * Release held funds back to available (payment cancelled or failed).
     */
    public void releaseHold(Money amount, String paymentReferenceId) {
        this.heldAmount = this.heldAmount.subtract(amount);

        WalletTransaction txn = new WalletTransaction(
            WalletTransactionId.generate(), WalletTransactionType.CREDIT_HOLD_RELEASE,
            amount, getAvailableBalance(), paymentReferenceId,
            "Hold released: " + paymentReferenceId
        );
        transactions.add(txn);

        domainEvents.add(new HoldReleased(this.id, this.ownerId, amount,
            getAvailableBalance(), paymentReferenceId, Instant.now()));
    }

    /**
     * Upgrade KYC level. New limits apply from this moment.
     * Production: re-validate any pending holds under new limits.
     */
    public void upgradeKyc(KycLevel newKycLevel) {
        if (newKycLevel.ordinal() <= this.kycLevel.ordinal())
            throw new IllegalArgumentException("Can only upgrade KYC, not downgrade");
        this.kycLevel = newKycLevel;
    }

    /**
     * Suspend wallet (fraud, compliance, court order).
     * Suspended wallets cannot transact. Money is safe but inaccessible.
     */
    public void suspend(String reason) {
        if (this.status == WalletStatus.SUSPENDED)
            return; // idempotent
        this.status = WalletStatus.SUSPENDED;
        this.suspendedAt = Instant.now();
        this.suspensionReason = reason;

        domainEvents.add(new WalletSuspended(this.id, this.ownerId, reason, Instant.now()));
    }

    public void reinstate() {
        if (this.status != WalletStatus.SUSPENDED)
            throw new InvalidWalletStateException("Can only reinstate SUSPENDED wallet");
        this.status = WalletStatus.ACTIVE;
        this.suspendedAt = null;
        this.suspensionReason = null;
    }

    // ─────────────────── Invariant Helpers ────────────────────────────────

    private void assertActive() {
        if (this.status != WalletStatus.ACTIVE)
            throw new WalletNotActiveException(
                "Wallet " + this.id + " is not active. Status: " + this.status);
    }

    private void assertSufficientAvailableBalance(Money amount) {
        Money available = getAvailableBalance();
        if (amount.isGreaterThan(available))
            throw new InsufficientWalletBalanceException(
                "Insufficient balance. Available: " + available + ", Requested: " + amount);
    }

    private void assertWithinMonthlyLimit(Money amount) {
        if (!kycLevel.hasMonthlyLimit()) return; // FULL/ENHANCED KYC — no monthly limit

        resetMonthlySpentIfNewMonth();

        Money projectedMonthlySpent = this.monthlySpent.add(amount);
        if (projectedMonthlySpent.isGreaterThan(kycLevel.getMonthlySpendLimit()))
            throw new WalletKycViolationException(
                "Monthly spend limit " + kycLevel.getMonthlySpendLimit() +
                " would be exceeded. Spent so far: " + this.monthlySpent +
                ", Requested: " + amount
            );
    }

    private void accumMonthlySpent(Money amount) {
        resetMonthlySpentIfNewMonth();
        this.monthlySpent = this.monthlySpent.add(amount);
    }

    private void resetMonthlySpentIfNewMonth() {
        YearMonth currentMonth = YearMonth.now();
        if (!currentMonth.equals(this.monthlySpentFor)) {
            this.monthlySpent = Money.zero("INR");
            this.monthlySpentFor = currentMonth;
        }
    }

    // ─────────────────── Query Methods ────────────────────────────────────

    public Money getAvailableBalance() { return balance.subtract(heldAmount); }
    public Money getBalance() { return balance; }
    public Money getHeldAmount() { return heldAmount; }
    public WalletId getId() { return id; }
    public UserId getOwnerId() { return ownerId; }
    public KycLevel getKycLevel() { return kycLevel; }
    public WalletStatus getStatus() { return status; }
    public long getVersion() { return version; }
    public List<WalletTransaction> getTransactions() {
        return Collections.unmodifiableList(transactions);
    }

    public List<DomainEvent> pullDomainEvents() {
        List<DomainEvent> events = new ArrayList<>(domainEvents);
        domainEvents.clear();
        return Collections.unmodifiableList(events);
    }
}

public enum WalletStatus { ACTIVE, SUSPENDED, CLOSED }
```

---

## Domain Events

```java
// MoneyAdded — consumed by Notification BC (send SMS), Audit BC (record)
public record MoneyAdded(
    String eventId,
    WalletId walletId,
    UserId ownerId,
    Money amount,
    Money balanceAfter,
    WalletTransactionType creditType,
    String externalReferenceId,
    Instant occurredAt
) implements DomainEvent {
    public MoneyAdded(WalletId wId, UserId uid, Money amt, Money bal,
                       WalletTransactionType type, String ref, Instant at) {
        this(UUID.randomUUID().toString(), wId, uid, amt, bal, type, ref, at);
    }
    @Override public String eventType() { return "wallet.money_added"; }
}

// MoneyDeducted — consumed by Notification BC, Audit BC
public record MoneyDeducted(
    String eventId,
    WalletId walletId,
    UserId ownerId,
    Money amount,
    Money balanceAfter,
    WalletTransactionType debitType,
    String externalReferenceId,
    Instant occurredAt
) implements DomainEvent {
    public MoneyDeducted(WalletId wId, UserId uid, Money amt, Money bal,
                          WalletTransactionType type, String ref, Instant at) {
        this(UUID.randomUUID().toString(), wId, uid, amt, bal, type, ref, at);
    }
    @Override public String eventType() { return "wallet.money_deducted"; }
}

// MoneyHeld — consumed by Payment BC saga (confirms hold placed)
public record MoneyHeld(
    String eventId,
    WalletId walletId,
    UserId ownerId,
    Money heldAmount,
    Money availableBalance,
    String paymentReferenceId,
    Instant occurredAt
) implements DomainEvent {
    public MoneyHeld(WalletId w, UserId u, Money h, Money avail, String ref, Instant at) {
        this(UUID.randomUUID().toString(), w, u, h, avail, ref, at);
    }
    @Override public String eventType() { return "wallet.money_held"; }
}

// HoldReleased — payment failed; funds released back
public record HoldReleased(
    String eventId,
    WalletId walletId,
    UserId ownerId,
    Money releasedAmount,
    Money availableBalance,
    String paymentReferenceId,
    Instant occurredAt
) implements DomainEvent {
    public HoldReleased(WalletId w, UserId u, Money amt, Money avail, String ref, Instant at) {
        this(UUID.randomUUID().toString(), w, u, amt, avail, ref, at);
    }
    @Override public String eventType() { return "wallet.hold_released"; }
}
```

---

## Repository Interface

```java
package com.paytm.wallet.domain.repository;

public interface WalletRepository {

    void save(Wallet wallet); // optimistic lock: throws on version conflict

    Optional<Wallet> findById(WalletId id);

    Optional<Wallet> findByOwnerId(UserId ownerId);

    /**
     * Find wallets that exceed their KYC balance limit.
     * Used by compliance job to flag KYC violations.
     */
    List<Wallet> findWalletsExceedingKycLimit();
}
```

---

## Why Balance-as-Field (Not Event Sourcing)?

**Question:** Why not use event sourcing — replay all transactions to get the balance?

**Answer:**
1. **Performance:** A user with 5 years of daily transactions has ~1,825 events. Replaying 1,825 events on every balance read is too slow.
2. **Complexity:** Event sourcing adds significant complexity (snapshots, event schema evolution, replay ordering). This complexity is justified for some domains (audit trails, time-travel queries) but not for a balance engine where a single field is sufficient.
3. **RBI compliance:** RBI requires real-time balance visibility. An event-sourced system with eventual consistency on the read model doesn't meet this requirement without additional infrastructure.

**The pragmatic DDD choice:** Store balance as a snapshot field on the aggregate. Maintain transaction history as an append-only log (for audit). This gives us O(1) balance reads and a full audit trail.

**When event sourcing IS right:** the Payment aggregate could benefit from event sourcing — the full history of state transitions is compliance-critical and queried regularly. But even there, a state machine with domain events achieves 90% of the value with 20% of the complexity.
