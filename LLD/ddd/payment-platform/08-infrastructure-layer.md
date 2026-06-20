# Infrastructure Layer — Repositories, ACLs, and Event Publishing

The infrastructure layer implements every interface defined in the domain layer. **Domain objects have zero knowledge of this layer.** A database schema change, a messaging platform swap, or an external API upgrade affects ONLY this layer.

---

## Repository Implementations

### JPA Payment Repository

```java
package com.paytm.payment.infrastructure.repository;

import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class JpaPaymentRepository implements PaymentRepository {

    private final PaymentJpaEntityRepository jpa;  // Spring Data JPA interface
    private final PaymentMapper mapper;             // converts domain ↔ JPA entity

    public JpaPaymentRepository(PaymentJpaEntityRepository jpa, PaymentMapper mapper) {
        this.jpa = jpa;
        this.mapper = mapper;
    }

    @Override
    @Transactional
    public void save(Payment payment) {
        PaymentJpaEntity entity = jpa.findByPaymentId(payment.getId().getValue())
            .map(existing -> mapper.updateEntity(existing, payment))
            .orElseGet(() -> mapper.toEntity(payment));

        try {
            jpa.save(entity);
        } catch (OptimisticLockingFailureException e) {
            throw new PaymentConcurrentModificationException(
                "Payment " + payment.getId() + " was modified concurrently. Retry.", e
            );
        }
    }

    @Override
    public Optional<Payment> findById(PaymentId id) {
        return jpa.findByPaymentId(id.getValue())
            .map(mapper::toDomain);
    }

    @Override
    public Optional<Payment> findByReferenceId(PaymentReferenceId referenceId) {
        return jpa.findByClientReferenceId(referenceId.getValue())
            .map(mapper::toDomain);
    }

    @Override
    public List<Payment> findTimeoutPayments() {
        return jpa.findByStatus("TIMEOUT").stream()
            .map(mapper::toDomain)
            .collect(toList());
    }

    @Override
    public List<Payment> findCompletedPaymentsForUserOnDate(UserId userId, LocalDate date) {
        Instant startOfDay = date.atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant();
        Instant endOfDay = date.plusDays(1).atStartOfDay(ZoneId.of("Asia/Kolkata")).toInstant();
        return jpa.findByPayerUserIdAndStatusAndInitiatedAtBetween(
                userId.getValue(), "COMPLETED", startOfDay, endOfDay)
            .stream().map(mapper::toDomain).collect(toList());
    }
}
```

### JPA Entity (Infrastructure Layer Only — domain knows nothing of this)

```java
package com.paytm.payment.infrastructure.entity;

import jakarta.persistence.*;

@Entity
@Table(
    name = "payments",
    indexes = {
        @Index(name = "idx_payments_client_ref", columnList = "client_reference_id", unique = true),
        @Index(name = "idx_payments_payer", columnList = "payer_user_id, status, initiated_at"),
        @Index(name = "idx_payments_npci_txn", columnList = "npci_transaction_id"),
        @Index(name = "idx_payments_status", columnList = "status, initiated_at")
    }
)
public class PaymentJpaEntity {

    @Id
    @Column(name = "payment_id")
    private String paymentId;

    @Column(name = "client_reference_id", nullable = false, unique = true, length = 64)
    private String clientReferenceId;  // idempotency key — unique constraint in DB

    @Column(name = "status", nullable = false, length = 30)
    private String status;

    @Column(name = "amount", nullable = false, precision = 15, scale = 2)
    private BigDecimal amount;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Column(name = "payment_method_type", nullable = false, length = 20)
    private String paymentMethodType;

    // UPI specific
    @Column(name = "payer_vpa", length = 100)
    private String payerVpa;

    @Column(name = "payee_vpa", length = 100)
    private String payeeVpa;

    // Card specific (tokenized — no raw PAN ever stored here)
    @Column(name = "card_token", length = 200)
    private String cardToken;

    @Column(name = "masked_card_number", length = 20)
    private String maskedCardNumber;

    @Column(name = "card_network", length = 20)
    private String cardNetwork;

    // Participants
    @Column(name = "payer_user_id", nullable = false, length = 50)
    private String payerUserId;

    @Column(name = "payee_user_id", length = 50)
    private String payeeUserId;

    // Settlement
    @Column(name = "npci_transaction_id", length = 100)
    private String npciTransactionId;

    @Column(name = "settlement_batch_id", length = 50)
    private String settlementBatchId;

    // Failure context
    @Column(name = "failure_code", length = 50)
    private String failureCode;

    @Column(name = "failure_reason", length = 500)
    private String failureReason;

    // Risk
    @Column(name = "risk_score")
    private Double riskScore;

    @Column(name = "risk_decision", length = 20)
    private String riskDecision;

    // Timestamps
    @Column(name = "initiated_at", nullable = false)
    private Instant initiatedAt;

    @Column(name = "processing_started_at")
    private Instant processingStartedAt;

    @Column(name = "completed_at")
    private Instant completedAt;

    @Column(name = "failed_at")
    private Instant failedAt;

    // Optimistic locking — database prevents concurrent overwrites
    @Version
    @Column(name = "version", nullable = false)
    private Long version;
}
```

### Database Schema

```sql
-- payments table
CREATE TABLE payments (
    payment_id          VARCHAR(50)     PRIMARY KEY,
    client_reference_id VARCHAR(64)     NOT NULL UNIQUE,    -- idempotency key
    status              VARCHAR(30)     NOT NULL,
    amount              DECIMAL(15, 2)  NOT NULL,
    currency            CHAR(3)         NOT NULL DEFAULT 'INR',
    payment_method_type VARCHAR(20)     NOT NULL,

    -- UPI
    payer_vpa           VARCHAR(100),
    payee_vpa           VARCHAR(100),
    upi_note            VARCHAR(100),

    -- Card (tokenized only)
    card_token          VARCHAR(200),
    masked_card_number  VARCHAR(20),
    card_network        VARCHAR(20),
    card_type           VARCHAR(20),

    -- Participants
    payer_user_id       VARCHAR(50)     NOT NULL,
    payee_user_id       VARCHAR(50),

    -- Settlement
    npci_transaction_id VARCHAR(100),
    settlement_batch_id VARCHAR(50),

    -- Risk
    risk_score          DECIMAL(5,4),
    risk_decision       VARCHAR(20),

    -- Failure
    failure_code        VARCHAR(50),
    failure_reason      VARCHAR(500),

    -- Timestamps
    initiated_at        TIMESTAMPTZ     NOT NULL,
    processing_started_at TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    failed_at           TIMESTAMPTZ,

    version             BIGINT          NOT NULL DEFAULT 0, -- optimistic lock
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Indexes for query patterns
CREATE INDEX idx_payments_payer_date ON payments(payer_user_id, status, initiated_at);
CREATE INDEX idx_payments_status ON payments(status, initiated_at) WHERE status IN ('TIMEOUT', 'PROCESSING');
CREATE INDEX idx_payments_npci ON payments(npci_transaction_id) WHERE npci_transaction_id IS NOT NULL;

-- Outbox table (Transactional Outbox Pattern)
CREATE TABLE payment_outbox (
    id              VARCHAR(50)     PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_id    VARCHAR(50)     NOT NULL,
    event_type      VARCHAR(100)    NOT NULL,
    payload         JSONB           NOT NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'PENDING',  -- PENDING, SENT, FAILED
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    sent_at         TIMESTAMPTZ,
    retry_count     INT             NOT NULL DEFAULT 0
);
CREATE INDEX idx_outbox_pending ON payment_outbox(status, created_at) WHERE status = 'PENDING';
```

---

## Anti-Corruption Layers (ACL)

### NPCI UPI Adapter

```java
package com.paytm.payment.infrastructure.acl;

import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

/**
 * Anti-Corruption Layer for NPCI UPI Network.
 *
 * Responsibility:
 * 1. Translate our domain concepts to NPCI API format
 * 2. Translate NPCI responses (and error codes) to our domain concepts
 * 3. Handle NPCI-specific retry logic and timeout behavior
 * 4. Shield the domain from NPCI API changes
 *
 * NPCI UPI API Reference: RBI PSP API specification v2.5
 */
@Component
public class NpciUpiAdapter {

    private final RestTemplate npciRestTemplate;  // pre-configured with NPCI mTLS cert
    private final NpciConfig config;
    private final MeterRegistry metrics;

    /**
     * Initiate a UPI payment. NPCI processes async — result via webhook callback.
     *
     * NPCI SLA: respond with txn ID within 20-30 seconds.
     * Our webhook endpoint: POST /webhooks/npci/upi-callback
     *
     * Key NPCI behavior:
     * - NPCI may timeout on our initial request but still process the payment
     * - NEVER assume TIMEOUT = FAILED at NPCI side
     * - Always reconcile TIMEOUT payments via the NPCI Status API
     */
    public NpciInitiateResponse initiatePaymentAsync(Payment payment) {
        UpiPaymentMethod upiMethod = (UpiPaymentMethod) payment.getPaymentMethod();

        // Translate domain → NPCI API format
        NpciCollectRequest npciRequest = new NpciCollectRequest(
            payment.getId().getValue(),                  // our agentTransactionId
            config.getPaymentServiceProviderId(),        // our PSP ID (registered with NPCI)
            upiMethod.payerVpa().getFullAddress(),
            upiMethod.payeeVpa().getFullAddress(),
            payment.getAmount().getAmount(),
            payment.getAmount().getCurrencyCode(),
            upiMethod.upiTransactionNote(),
            config.getCallbackUrl() + "/webhooks/npci/upi-callback"
        );

        try {
            Timer.Sample sample = Timer.start(metrics);
            NpciCollectResponse response = npciRestTemplate.postForObject(
                config.getBaseUrl() + "/api/v2/collect",
                npciRequest,
                NpciCollectResponse.class
            );
            sample.stop(metrics.timer("npci.initiate.latency", "result", "success"));

            return new NpciInitiateResponse(response.getTransactionId(), true);

        } catch (HttpServerErrorException e) {
            metrics.counter("npci.initiate.errors", "errorCode", e.getStatusCode().toString()).increment();
            if (e.getStatusCode().is5xxServerError()) {
                // NPCI 5xx: may or may not have processed. Do NOT mark as failed.
                throw new NpciUnavailableException("NPCI server error: " + e.getMessage());
            }
            throw translateNpciError(e);
        }
    }

    /**
     * Called by reconciliation job to check status of a TIMEOUT payment.
     */
    public PaymentStatusResult queryPaymentStatus(String agentTransactionId) {
        try {
            NpciStatusResponse response = npciRestTemplate.getForObject(
                config.getBaseUrl() + "/api/v2/status/" + agentTransactionId,
                NpciStatusResponse.class
            );
            // Translate NPCI status codes to our domain result
            return translateNpciStatus(response);
        } catch (Exception e) {
            throw new NpciQueryException("Failed to query NPCI for " + agentTransactionId, e);
        }
    }

    /**
     * Translate NPCI error codes to domain-meaningful failure codes.
     *
     * NPCI error codes are documented in NPCI UPI Technical Specification.
     * We normalize them to our standard failure codes.
     */
    private DomainException translateNpciError(HttpServerErrorException e) {
        String npciCode = extractNpciErrorCode(e.getResponseBodyAsString());
        return switch (npciCode) {
            case "RB"   -> new PaymentDeclinedException("BANK_DECLINED", "Bank declined the transaction");
            case "U30"  -> new PaymentDeclinedException("INSUFFICIENT_FUNDS", "Insufficient balance in bank account");
            case "U28"  -> new PaymentDeclinedException("INVALID_VPA", "Payee VPA not registered or inactive");
            case "U16"  -> new PaymentDeclinedException("RISK_THRESHOLD", "Transaction declined by bank's fraud system");
            case "ZR"   -> new PaymentDeclinedException("DAILY_LIMIT", "Daily limit exceeded at bank");
            default     -> new PaymentDeclinedException("BANK_ERROR", "Transaction failed: " + npciCode);
        };
    }

    private PaymentStatusResult translateNpciStatus(NpciStatusResponse response) {
        return switch (response.getStatus()) {
            case "SUCCESS" -> new PaymentStatusResult(true, response.getNpciTransactionId(), null);
            case "FAILURE" -> new PaymentStatusResult(false, null, response.getErrorCode());
            case "PENDING" -> new PaymentStatusResult(null, null, null); // still processing
            default        -> throw new IllegalStateException("Unknown NPCI status: " + response.getStatus());
        };
    }

    private String extractNpciErrorCode(String responseBody) {
        // Parse JSON error response from NPCI
        try {
            return objectMapper.readTree(responseBody).get("errorCode").asText();
        } catch (Exception e) {
            return "UNKNOWN";
        }
    }
}
```

### BBPS Adapter (Bill Payment System)

```java
package com.paytm.billpayment.infrastructure.acl;

@Component
public class BbpsAdapter {

    private final RestTemplate bbpsRestTemplate;
    private final BbpsConfig config;

    /**
     * Phase 1: Fetch bill from biller via BBPS.
     *
     * BBPS fetch flow:
     * 1. We (Agent Institution) call BBPS (Bharat Bill Payment Central Unit)
     * 2. BBPS routes to the specific Biller Operating Unit
     * 3. Biller returns bill details
     *
     * Fetch response validity: varies by biller (30 min to 24 hours)
     */
    public BillFetchResult fetchBill(BillPaymentOrder order) {
        BbpsFetchRequest request = new BbpsFetchRequest(
            config.getAgentId(),
            order.getBillerInfo().billerId(),
            order.getCustomerIdentifier().identifierType(),
            order.getCustomerIdentifier().identifierValue(),
            order.getAgentTransactionId()  // our stable reference for BBPS
        );

        try {
            BbpsFetchResponse response = bbpsRestTemplate.postForObject(
                config.getBaseUrl() + "/fetch",
                request,
                BbpsFetchResponse.class
            );
            return translateFetchResponse(response);

        } catch (HttpClientErrorException e) {
            String errorCode = extractBbpsErrorCode(e);
            throw switch (errorCode) {
                case "BOU001" -> new InvalidCustomerIdentifierException("Invalid account number");
                case "BOU002" -> new BillerUnavailableException("Biller system offline");
                case "BOU004" -> new NoBillDueException("No outstanding bill for this account");
                default -> new BillFetchException("Bill fetch failed: " + errorCode);
            };
        }
    }

    /**
     * Phase 2: Submit payment to BBPS.
     *
     * BBPS payment is synchronous (unlike NPCI UPI which is async).
     * BBPS confirms or rejects within 30 seconds.
     *
     * Idempotency: BBPS deduplicates on agentTransactionId (same ID = same payment).
     * If we send the same agentTransactionId twice, BBPS returns the original result.
     */
    public BbpsPaymentResult submitPayment(BillPaymentOrder order) {
        BbpsPaymentRequest request = new BbpsPaymentRequest(
            config.getAgentId(),
            order.getBillerInfo().billerId(),
            order.getCustomerIdentifier().identifierValue(),
            order.getFetchedBillDetails().billNumber(),
            order.getPaymentAmount().getAmount(),
            order.getPaymentAmount().getCurrencyCode(),
            order.getAgentTransactionId(),  // stable, idempotent key
            order.getPaymentMode()
        );

        try {
            BbpsPaymentResponse response = bbpsRestTemplate.postForObject(
                config.getBaseUrl() + "/payment",
                request,
                BbpsPaymentResponse.class
            );

            return new BbpsPaymentResult(
                "SUCCESS".equals(response.getStatus()),
                response.getBbpsTransactionId(),
                response.getErrorCode()
            );

        } catch (ResourceAccessException e) {
            // Network timeout — BBPS may have processed. Do NOT assume failure.
            throw new BbpsTimeoutException("BBPS did not respond within SLA for " + order.getAgentTransactionId());
        }
    }

    private BillFetchResult translateFetchResponse(BbpsFetchResponse response) {
        // Translate BBPS response to our domain value objects
        List<BillLineItem> lineItems = response.getLineItems().stream()
            .map(li -> new BillLineItem(li.getDescription(), Money.ofInr(li.getAmount())))
            .collect(toList());

        return new BillFetchResult(
            new BillDetails(
                response.getBillNumber(),
                Money.ofInr(response.getBillAmount()),
                response.getMinimumAmount() != null ? Money.ofInr(response.getMinimumAmount()) : null,
                LocalDate.parse(response.getDueDate()),
                response.getBillerDisplayName(),
                lineItems,
                Instant.now(),
                Instant.now().plus(Duration.ofMinutes(response.getValidityMinutes()))
            ),
            response.getFetchTransactionId()
        );
    }
}
```

---

## Event Publishing — Transactional Outbox Pattern

```java
package com.paytm.shared.infrastructure.event;

/**
 * DomainEventPublisher — writes events to the outbox table in the same transaction.
 * The outbox poller reads and publishes to Kafka asynchronously.
 *
 * This guarantees: events are never lost even if Kafka is down during the transaction.
 * Events are never published for rolled-back transactions.
 */
@Component
public class OutboxDomainEventPublisher implements DomainEventPublisher {

    private final OutboxRepository outboxRepository;
    private final ObjectMapper objectMapper;

    @Override
    public void publish(List<DomainEvent> events) {
        events.forEach(event -> {
            OutboxEntry entry = new OutboxEntry(
                event.eventId(),
                event.eventType(),          // maps to Kafka topic
                serializeEvent(event),
                "PENDING"
            );
            outboxRepository.save(entry);   // same DB transaction as aggregate save
        });
    }

    private String serializeEvent(DomainEvent event) {
        try {
            return objectMapper.writeValueAsString(event);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Failed to serialize event: " + event.eventType(), e);
        }
    }
}

/**
 * Outbox Poller — runs every 100ms, publishes pending events to Kafka.
 * This is a SEPARATE process from the main transaction.
 *
 * In production: use Debezium (CDC on outbox table) instead of polling
 * for lower latency and reduced DB load.
 */
@Component
public class OutboxPoller {

    private final OutboxRepository outboxRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;

    @Scheduled(fixedDelay = 100) // every 100ms
    public void poll() {
        List<OutboxEntry> pending = outboxRepository.findPending(100); // batch of 100

        pending.forEach(entry -> {
            try {
                kafkaTemplate.send(topicFor(entry.getEventType()), entry.getId(), entry.getPayload())
                    .get(5, TimeUnit.SECONDS);    // wait for broker ACK

                outboxRepository.markSent(entry.getId());
            } catch (Exception e) {
                outboxRepository.markFailed(entry.getId(), e.getMessage());
                // Retry via exponential backoff — failed entries retried on next poll
            }
        });
    }

    private String topicFor(String eventType) {
        // Map event type to Kafka topic
        return switch (eventType.split("\\.")[0]) {
            case "payment" -> "payment.events";
            case "wallet"  -> "wallet.events";
            case "bill"    -> "bill-payment.events";
            default        -> "domain.events";  // fallback
        };
    }
}
```

---

## Kafka Topics Configuration

```yaml
# application.yaml — Kafka topics by bounded context
kafka:
  topics:
    payment:
      name: payment.events
      partitions: 30       # 30 partitions = 30 parallel consumers; scale by user ID partition
      replication: 3
      retention: 7d        # 7 days for replay and audit
    wallet:
      name: wallet.events
      partitions: 30
      replication: 3
      retention: 7d
    bill-payment:
      name: bill-payment.events
      partitions: 10
      replication: 3
      retention: 30d
    notification:
      name: notification.commands
      partitions: 50       # high throughput — every payment triggers notification
      replication: 3
      retention: 1d
```

**Partition key strategy:** Always partition by `userId`. This ensures all events for a single user are processed in order by a single consumer partition, avoiding race conditions on saga steps.

---

## Idempotent Kafka Consumer

```java
@KafkaListener(topics = "payment.events")
@Service
public class NotificationEventConsumer {

    private final RedisIdempotencyStore idempotencyStore;
    private final NotificationService notificationService;

    @KafkaHandler
    public void onPaymentCompleted(PaymentCompleted event) {
        // Check if we already processed this event (Kafka at-least-once delivery)
        String deduplicationKey = "notification:payment-completed:" + event.eventId();

        if (idempotencyStore.exists(deduplicationKey)) {
            log.info("Skipping duplicate event {}", event.eventId());
            return;
        }

        // Process the event
        notificationService.sendPaymentSuccessNotification(
            event.payerId().getValue(),
            event.amount(),
            event.payeeDisplayName()
        );

        // Mark as processed (24h TTL — covers any Kafka re-delivery window)
        idempotencyStore.set(deduplicationKey, Duration.ofHours(24));
    }
}
```

---

## Infrastructure → Domain Mapping (The Mapper)

```java
@Component
public class PaymentMapper {

    public Payment toDomain(PaymentJpaEntity entity) {
        // Reconstruct the domain aggregate from persisted state
        // This is a reconstitution, not a new payment — no events emitted
        PaymentMethod method = switch (entity.getPaymentMethodType()) {
            case "UPI" -> new UpiPaymentMethod(
                Vpa.of(entity.getPayerVpa()),
                Vpa.of(entity.getPayeeVpa()),
                entity.getUpiNote()
            );
            case "CARD" -> new CardPaymentMethod(
                EncryptedCardToken.of(entity.getCardToken()),
                MaskedCardNumber.of(entity.getMaskedCardNumber()),
                CardNetwork.valueOf(entity.getCardNetwork()),
                CardType.valueOf(entity.getCardType()),
                entity.getBankIssuerName()
            );
            case "WALLET" -> new WalletPaymentMethod(
                UserId.of(entity.getPayerUserId()),
                WalletId.of(entity.getWalletId())
            );
            default -> throw new IllegalStateException("Unknown method: " + entity.getPaymentMethodType());
        };

        // Reconstitute aggregate from persistence
        return Payment.reconstitute(
            PaymentId.of(entity.getPaymentId()),
            PaymentReferenceId.of(entity.getClientReferenceId()),
            PaymentStatus.valueOf(entity.getStatus()),
            Money.ofInr(entity.getAmount()),
            method,
            new PaymentParticipant(UserId.of(entity.getPayerUserId()),
                entity.getPayerDisplayName(), entity.getPayerIdentifier()),
            new PaymentParticipant(UserId.of(entity.getPayeeUserId()),
                entity.getPayeeDisplayName(), entity.getPayeeIdentifier()),
            entity.getInitiatedAt(),
            entity.getCompletedAt(),
            entity.getNpciTransactionId(),
            entity.getFailureCode(),
            entity.getFailureReason(),
            entity.getVersion()
        );
    }
}
```

**Why `reconstitute()` and not `new Payment()`?**
When loading from DB, we don't want to emit domain events (the payment was already initiated in the past). `reconstitute()` is a static factory that bypasses event emission — it's a "here's what happened in the past" operation, not "something is happening now."
