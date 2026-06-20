# Saga Patterns — Distributed Transactions Across Bounded Contexts

A **saga** is a sequence of local transactions across multiple bounded contexts, where each step publishes an event that triggers the next step. If a step fails, compensating transactions undo the preceding steps.

We use two saga styles:
- **Choreography**: no central coordinator — each service reacts to events
- **Orchestration**: a central saga orchestrator drives the flow, handles failures explicitly

---

## When to Use Which

| Saga Style | Use when | Avoid when |
|---|---|---|
| **Choreography** | Simple, short sequences; strong team ownership; clear event names | Many steps (>4); complex compensations; need centralized visibility |
| **Orchestration** | Complex flows; multiple failure paths; business visibility needed | Simple 2-step flows where a coordinator adds ceremony |

---

## Saga 1: UPI Payment Saga (Choreography)

**Flow:** User pays ₹500 via UPI from their wallet balance.

```
Step 1: Payment BC    → PaymentInitiated event
Step 2: Fraud BC      → evaluates risk → RiskApproved / RiskBlocked event
Step 3: Wallet BC     → deducts from wallet → WalletDebited event
Step 4: Payment BC    → sends to NPCI → NPCI callback → PaymentCompleted
Step 5: Notification  → sends SMS receipt

Compensation (if Step 4 fails after Step 3):
  Payment BC  → publishes WalletRefundRequired event
  Wallet BC   → credits wallet back → WalletRefunded event
```

### Event Flow Diagram

```
User initiates UPI payment (wallet-funded)
        │
        ▼
[Payment BC] initiates payment → saves (INITIATED) → publishes PaymentInitiated
        │
        ▼ (Kafka: payment.initiated)
[Fraud BC] evaluates risk score
        │
        ├── Approved → publishes RiskApproved
        └── Blocked  → publishes RiskBlocked → [Payment BC] marks BLOCKED → END
        │
        ▼ (Kafka: risk.approved)
[Wallet BC] holds funds → publishes MoneyHeld (or InsufficientBalance → payment fails)
        │
        ▼ (Kafka: wallet.money_held)
[Payment BC] receives MoneyHeld → sends to NPCI → marks PROCESSING
        │
        ├── NPCI callback: success → PaymentCompleted
        │       │
        │       ▼ (Kafka: payment.completed)
        │   [Wallet BC] applyHold (convert hold to actual debit)
        │   [Notification BC] sends SMS
        │   [Audit BC] records transaction
        │
        └── NPCI callback: failure → PaymentFailed
                │
                ▼ (Kafka: payment.failed)
            [Wallet BC] releaseHold (return funds to available) → HoldReleased
            [Notification BC] sends failure notification
```

### Choreography Implementation

```java
// In Wallet BC — listens for events from Payment BC
@KafkaListener(topics = "payment.events", groupId = "wallet-service")
@Service
public class WalletPaymentSagaListener {

    private final WalletRepository walletRepository;
    private final DomainEventPublisher eventPublisher;

    /**
     * Triggered by RiskApproved event from Fraud BC (via Payment BC).
     * Holds funds for the in-flight payment.
     */
    @KafkaHandler
    @Transactional
    public void onRiskApprovedForWalletPayment(RiskApprovedForWalletPayment event) {
        Wallet wallet = walletRepository.findByOwnerId(UserId.of(event.userId()))
            .orElseThrow(() -> new WalletNotFoundException(event.userId()));

        try {
            wallet.holdFunds(event.amount(), event.paymentReferenceId());
            walletRepository.save(wallet);
            eventPublisher.publish(wallet.pullDomainEvents()); // publishes MoneyHeld
        } catch (InsufficientWalletBalanceException e) {
            // Compensating event — Payment BC will mark payment as FAILED
            eventPublisher.publishDirect(new WalletInsufficientBalance(
                event.paymentId(), event.paymentReferenceId(), e.getMessage()
            ));
        }
    }

    /**
     * Triggered by PaymentCompleted — apply the hold (convert to actual debit).
     */
    @KafkaHandler
    @Transactional
    public void onPaymentCompleted(PaymentCompleted event) {
        if (!event.paymentMethodType().equals("WALLET")) return;

        Wallet wallet = walletRepository.findByOwnerId(UserId.of(event.payerId().getValue()))
            .orElseThrow(() -> new WalletNotFoundException(event.payerId().getValue()));

        wallet.applyHold(event.amount(), event.referenceId().getValue());
        walletRepository.save(wallet);
        eventPublisher.publish(wallet.pullDomainEvents());
    }

    /**
     * Triggered by PaymentFailed — release the hold (return funds to available).
     * This is the compensating transaction.
     */
    @KafkaHandler
    @Transactional
    public void onPaymentFailed(PaymentFailed event) {
        // Only release hold for wallet-funded payments
        walletRepository.findByHeldPaymentReference(event.paymentId().getValue())
            .ifPresent(wallet -> {
                wallet.releaseHold(event.heldAmount(), event.paymentId().getValue());
                walletRepository.save(wallet);
                eventPublisher.publish(wallet.pullDomainEvents());
            });
    }
}

// In Payment BC — listens for wallet events
@KafkaListener(topics = "wallet.events", groupId = "payment-service")
@Service
public class PaymentWalletSagaListener {

    private final PaymentRepository paymentRepository;
    private final NpciUpiAdapter npciAdapter;
    private final DomainEventPublisher eventPublisher;

    @KafkaHandler
    @Transactional
    public void onMoneyHeld(MoneyHeld event) {
        Payment payment = paymentRepository
            .findByReferenceId(PaymentReferenceId.of(event.paymentReferenceId()))
            .orElseThrow();

        // Wallet hold confirmed — now call NPCI
        npciAdapter.initiatePaymentAsync(payment);
        // Payment stays in PROCESSING; NPCI will callback to complete/fail
    }

    @KafkaHandler
    @Transactional
    public void onWalletInsufficientBalance(WalletInsufficientBalance event) {
        Payment payment = paymentRepository
            .findById(PaymentId.of(event.paymentId()))
            .orElseThrow();

        payment.fail("INSUFFICIENT_WALLET_BALANCE", "Wallet balance insufficient for payment");
        paymentRepository.save(payment);
        eventPublisher.publish(payment.pullDomainEvents());
    }
}
```

---

## Saga 2: Add Money to Wallet Saga (Orchestration)

**Flow:** User adds ₹1,000 to wallet from their linked bank account.

```
Step 1: User initiates top-up
Step 2: Debit ₹1,000 from user's bank account (via net banking / UPI)
Step 3: Credit ₹1,000 to wallet
Step 4: Notify user

Compensation:
  If Step 3 fails after Step 2: refund bank account (credit back)
  If Step 2 fails: no money moved; just mark order as failed
```

**Why orchestration here?**
- The "debit bank → credit wallet" sequence is a critical financial transaction
- Any failure must trigger explicit compensation (refund to bank)
- Visibility: product managers need to see every step in a dashboard
- The saga has 2+ failure modes that need different compensations

### Saga Orchestrator

```java
package com.paytm.wallet.application.saga;

import org.springframework.statemachine.StateMachine;

/**
 * AddMoneyToWalletSaga orchestrates the bank-debit → wallet-credit flow.
 *
 * Implemented as a state machine persisted in PostgreSQL.
 * Each step is a local transaction. The saga state is saved after each step.
 *
 * Uses the "Saga State Machine" pattern with a SagaLog table:
 *   sagaId, sagaType, currentState, payload, createdAt, updatedAt
 */
@Service
public class AddMoneyToWalletSaga {

    private final SagaRepository sagaRepository;
    private final BankAccountACL bankAccountACL;
    private final WalletRepository walletRepository;
    private final DomainEventPublisher eventPublisher;
    private final RefundService refundService;

    public enum SagaState {
        STARTED,
        BANK_DEBIT_REQUESTED,
        BANK_DEBIT_CONFIRMED,
        BANK_DEBIT_FAILED,
        WALLET_CREDIT_REQUESTED,
        COMPLETED,
        BANK_REFUND_REQUESTED,
        BANK_REFUND_COMPLETED,
        FAILED
    }

    /**
     * Step 1: Start the saga. Debit the bank account.
     */
    @Transactional
    public String start(StartAddMoneyCommand command) {
        String sagaId = UUID.randomUUID().toString();

        SagaInstance saga = SagaInstance.create(
            sagaId, "ADD_MONEY_TO_WALLET", SagaState.STARTED, command
        );
        sagaRepository.save(saga);

        // Request bank debit (async — bank callback will advance the saga)
        BankDebitResponse response = bankAccountACL.requestDebit(
            command.bankAccountId(),
            command.amount(),
            sagaId  // correlation ID for bank callback
        );

        saga.transitionTo(SagaState.BANK_DEBIT_REQUESTED);
        saga.setPayload("bankDebitRequestId", response.requestId());
        sagaRepository.save(saga);

        return sagaId;
    }

    /**
     * Step 2: Bank confirmed debit. Credit the wallet.
     * Called by bank webhook callback.
     */
    @Transactional
    public void onBankDebitConfirmed(String sagaId, String bankTransactionId) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        assertSagaInState(saga, SagaState.BANK_DEBIT_REQUESTED);

        saga.transitionTo(SagaState.BANK_DEBIT_CONFIRMED);
        saga.setPayload("bankTransactionId", bankTransactionId);
        sagaRepository.save(saga);

        // Now credit the wallet
        StartAddMoneyCommand originalCommand = saga.getOriginalCommand(StartAddMoneyCommand.class);

        Wallet wallet = walletRepository
            .findByOwnerId(UserId.of(originalCommand.userId()))
            .orElseThrow(() -> new WalletNotFoundException(originalCommand.userId()));

        try {
            wallet.credit(
                originalCommand.amount(),
                WalletTransactionType.CREDIT_TOPUP,
                sagaId,
                "Bank top-up via " + bankTransactionId
            );
            walletRepository.save(wallet);
            eventPublisher.publish(wallet.pullDomainEvents()); // publishes MoneyAdded

            saga.transitionTo(SagaState.COMPLETED);
            sagaRepository.save(saga);

        } catch (WalletKycViolationException e) {
            // Wallet credit failed (KYC limit exceeded) — MUST refund bank
            saga.transitionTo(SagaState.WALLET_CREDIT_REQUESTED); // partial — need to compensate
            sagaRepository.save(saga);
            initiateCompensation(saga, e.getMessage());
        }
    }

    /**
     * Step 3a: Bank debit failed (insufficient funds, account locked, etc.)
     * No money moved — just mark saga as failed.
     */
    @Transactional
    public void onBankDebitFailed(String sagaId, String reason) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        assertSagaInState(saga, SagaState.BANK_DEBIT_REQUESTED);

        saga.transitionTo(SagaState.BANK_DEBIT_FAILED);
        saga.setFailureReason(reason);
        saga.transitionTo(SagaState.FAILED);
        sagaRepository.save(saga);

        // Publish AddMoneyFailed event → Notification BC sends "Top-up failed" notification
        eventPublisher.publishDirect(new AddMoneyFailed(sagaId, reason, Instant.now()));
    }

    /**
     * Compensating transaction: bank was debited but wallet credit failed.
     * We MUST refund the bank.
     */
    @Transactional
    void initiateCompensation(SagaInstance saga, String reason) {
        saga.transitionTo(SagaState.BANK_REFUND_REQUESTED);
        sagaRepository.save(saga);

        StartAddMoneyCommand originalCommand = saga.getOriginalCommand(StartAddMoneyCommand.class);
        String bankTransactionId = saga.getPayload("bankTransactionId");

        // Initiate bank refund (credit back to bank account)
        refundService.refundBankTransaction(
            originalCommand.bankAccountId(),
            originalCommand.amount(),
            bankTransactionId,
            "Failed to credit wallet: " + reason,
            saga.getId()
        );
        // Bank refund confirmation will call onBankRefundConfirmed
    }

    @Transactional
    public void onBankRefundConfirmed(String sagaId) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        saga.transitionTo(SagaState.BANK_REFUND_COMPLETED);
        saga.transitionTo(SagaState.FAILED);
        sagaRepository.save(saga);
        eventPublisher.publishDirect(new AddMoneyFailed(sagaId, "Compensated", Instant.now()));
    }

    private void assertSagaInState(SagaInstance saga, SagaState expectedState) {
        if (saga.getCurrentState() != expectedState)
            throw new SagaStateException(
                "Saga " + saga.getId() + " expected state " + expectedState +
                " but was " + saga.getCurrentState()
            );
    }
}
```

---

## Saga 3: Bill Payment Saga (Orchestration)

```
Step 1: FetchBill from BBPS (ACL)
Step 2: User confirms amount
Step 3: Deduct payment from source (wallet/UPI/card)
Step 4: Submit payment to BBPS
Step 5: BBPS confirms → record completion

Compensation:
  If Step 4 fails after Step 3: refund source (wallet credit-back or bank refund)
```

```java
@Service
public class BillPaymentSaga {

    public enum State {
        FETCH_PENDING, FETCH_COMPLETED, FETCH_FAILED,
        AWAITING_USER_CONFIRMATION,
        SOURCE_DEBIT_PENDING, SOURCE_DEBITED, SOURCE_DEBIT_FAILED,
        BBPS_SUBMISSION_PENDING, BBPS_SUBMITTED,
        COMPLETED, COMPENSATION_NEEDED, COMPENSATING, FAILED
    }

    @Transactional
    public void onFetchCompleted(String sagaId, BillDetails billDetails) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        assertState(saga, State.FETCH_PENDING);

        BillPaymentOrder order = billPaymentOrderRepository
            .findById(BillPaymentOrderId.of(saga.getPayload("orderId")))
            .orElseThrow();

        order.recordBillFetched(billDetails, saga.getPayload("fetchTxnId"));
        billPaymentOrderRepository.save(order);
        eventPublisher.publish(order.pullDomainEvents()); // BillFetched event → UI shows bill

        saga.transitionTo(State.AWAITING_USER_CONFIRMATION);
        sagaRepository.save(saga);
    }

    @Transactional
    public void onUserConfirmed(String sagaId, ConfirmBillPaymentCommand command) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        assertState(saga, State.AWAITING_USER_CONFIRMATION);

        BillPaymentOrder order = loadOrder(saga);
        order.confirmPayment(command.amount(), command.paymentMode());
        billPaymentOrderRepository.save(order);

        // Deduct from source
        if ("WALLET".equals(command.paymentMode())) {
            deductFromWallet(sagaId, command.userId(), command.amount(), order.getId().getValue());
        } else {
            initiateUpiOrCardPayment(sagaId, command);
        }

        saga.transitionTo(State.SOURCE_DEBIT_PENDING);
        sagaRepository.save(saga);
    }

    @Transactional
    public void onSourceDebited(String sagaId) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        assertState(saga, State.SOURCE_DEBIT_PENDING);
        saga.transitionTo(State.SOURCE_DEBITED);

        BillPaymentOrder order = loadOrder(saga);
        order.markPaymentInitiated();
        billPaymentOrderRepository.save(order);
        eventPublisher.publish(order.pullDomainEvents());

        // Submit to BBPS
        bbpsACL.submitPaymentAsync(order.getAgentTransactionId(), order.getPaymentAmount());
        saga.transitionTo(State.BBPS_SUBMISSION_PENDING);
        sagaRepository.save(saga);
    }

    @Transactional
    public void onBbpsConfirmed(String sagaId, String bbpsTransactionId) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        BillPaymentOrder order = loadOrder(saga);
        order.recordPaymentCompleted(bbpsTransactionId);
        billPaymentOrderRepository.save(order);
        eventPublisher.publish(order.pullDomainEvents()); // BillPaymentCompleted

        saga.transitionTo(State.COMPLETED);
        sagaRepository.save(saga);
    }

    @Transactional
    public void onBbpsFailed(String sagaId, String reason) {
        SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();
        assertState(saga, State.BBPS_SUBMISSION_PENDING);

        BillPaymentOrder order = loadOrder(saga);
        order.recordPaymentFailed(reason);
        billPaymentOrderRepository.save(order);
        eventPublisher.publish(order.pullDomainEvents());

        // COMPENSATION: source was debited but BBPS failed — must refund
        saga.transitionTo(State.COMPENSATION_NEEDED);
        sagaRepository.save(saga);
        initiateSourceRefund(saga, order);
    }
}
```

---

## Saga SagaInstance (State Persistence)

```java
@Entity
@Table(name = "saga_instances")
public class SagaInstance {
    @Id
    private String id;
    private String sagaType;
    @Enumerated(EnumType.STRING)
    private Enum<?> currentState;
    @Type(JsonType.class)
    private Map<String, Object> payload;  // flexible bag for saga-specific data
    private String failureReason;
    private Instant createdAt;
    private Instant updatedAt;
    private long version;  // optimistic lock

    public void transitionTo(Enum<?> newState) {
        this.currentState = newState;
        this.updatedAt = Instant.now();
    }

    public void setPayload(String key, String value) {
        payload.put(key, value);
        this.updatedAt = Instant.now();
    }

    public String getPayload(String key) { return (String) payload.get(key); }
}
```

---

## Idempotency in Saga Steps

Every saga step handler must be idempotent — Kafka at-least-once delivery means the same event may arrive twice:

```java
@KafkaHandler
@Transactional
public void onBankDebitConfirmed(String sagaId, String bankTransactionId) {
    SagaInstance saga = sagaRepository.findById(sagaId).orElseThrow();

    // IDEMPOTENCY GUARD: if already processed, skip
    if (saga.getCurrentState() != SagaState.BANK_DEBIT_REQUESTED) {
        log.info("Ignoring duplicate bank debit confirmation for saga {}. Current state: {}",
            sagaId, saga.getCurrentState());
        return;
    }

    // ... proceed with processing
}
```

---

## Failure Modes & Recovery

| Failure Point | What Happens | Recovery |
|---|---|---|
| Service crashes mid-saga | Saga state persisted in DB; on restart, saga resumes from last state | Scheduled reconciliation job scans stalled sagas and resumes them |
| Kafka message lost | Saga stays in current state | Timeout-based job retries the pending step |
| Compensating transaction fails | Manual intervention required | Alert oncall; saga moves to COMPENSATION_FAILED state |
| Network timeout to NPCI/BBPS | Payment stays in TIMEOUT state | Reconciliation job queries NPCI/BBPS for final status |

**Saga timeout job:**
```java
@Scheduled(fixedDelay = 60_000) // every minute
public void resumeStalledSagas() {
    Instant timeout = Instant.now().minus(Duration.ofMinutes(10));
    List<SagaInstance> stalledSagas = sagaRepository
        .findByStatesAndUpdatedBefore(
            List.of(SagaState.BANK_DEBIT_REQUESTED, SagaState.BBPS_SUBMISSION_PENDING),
            timeout
        );

    stalledSagas.forEach(saga -> {
        log.warn("Saga {} stalled in state {}. Re-triggering.", saga.getId(), saga.getCurrentState());
        sagaRetryPublisher.retry(saga);
    });
}
```
