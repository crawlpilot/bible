# Production Patterns — Idempotency, Consistency, Observability

This file covers the patterns that separate a working prototype from a production payment system. Each pattern exists because a real failure mode requires it.

---

## 1. Idempotency — The Most Critical Production Pattern

**Problem:** Mobile networks are unreliable. The user taps "Pay". The request reaches our server. The payment succeeds. The response never reaches the mobile app. The user taps "Pay" again. Without idempotency, the user pays twice.

**Solution:** Client generates a UUID before making the API call. Same UUID on retry. Server detects the duplicate and returns the original result.

### Full Idempotency Implementation

```java
/**
 * IdempotencyFilter — wraps every payment API call.
 * Applied at API layer before reaching the application layer.
 */
@Component
public class IdempotencyFilter implements Filter {

    private final RedisIdempotencyStore store;

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain) {
        HttpServletRequest request = (HttpServletRequest) req;
        String idempotencyKey = request.getHeader("X-Idempotency-Key");

        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            // For write operations, require idempotency key
            if (isWriteOperation(request)) {
                sendError(res, 400, "X-Idempotency-Key header required for payment operations");
                return;
            }
        }

        // Check if this key was already processed
        Optional<CachedResponse> cached = store.get(idempotencyKey);
        if (cached.isPresent()) {
            // Return cached response — exact same status code and body
            CachedResponse cr = cached.get();
            HttpServletResponse response = (HttpServletResponse) res;
            response.setStatus(cr.statusCode());
            response.setHeader("X-Idempotency-Replayed", "true");
            response.getWriter().write(cr.body());
            return;
        }

        // Process the request, capture the response
        CapturingResponseWrapper capturingResponse = new CapturingResponseWrapper((HttpServletResponse) res);
        chain.doFilter(request, capturingResponse);

        // Cache the response (24h TTL — covers network retry window)
        int statusCode = capturingResponse.getStatus();
        String body = capturingResponse.getCapturedBody();

        if (statusCode < 500) {  // don't cache server errors — let them retry
            store.set(idempotencyKey, new CachedResponse(statusCode, body), Duration.ofHours(24));
        }

        // Write actual response to client
        ((HttpServletResponse) res).setStatus(statusCode);
        ((HttpServletResponse) res).getWriter().write(body);
    }
}
```

### Database-Level Idempotency (Defense in Depth)

Even with the filter, we need database-level protection — in case two requests race through the filter simultaneously:

```sql
-- UNIQUE constraint on client_reference_id in payments table
CREATE UNIQUE INDEX idx_payments_idempotency ON payments(client_reference_id);
```

```java
// In the application handler — second line of defense
Optional<Payment> existing = paymentRepository.findByReferenceId(referenceId);
if (existing.isPresent()) {
    return toResult(existing.get()); // return existing, don't re-process
}

// If two threads race past this check simultaneously:
// One will succeed the INSERT, the other will get a unique constraint violation.
// The constraint violation is caught and handled gracefully:
try {
    paymentRepository.save(newPayment);
} catch (DataIntegrityViolationException e) {
    if (isUniqueConstraintViolation(e)) {
        // Another thread inserted first — load and return that payment
        return toResult(paymentRepository.findByReferenceId(referenceId).orElseThrow());
    }
    throw e;
}
```

---

## 2. Optimistic Locking — Preventing Concurrent Balance Corruption

**Problem:** Two simultaneous payment requests for the same wallet. Without locking, both could read the same balance, both could succeed, and the balance could go negative.

**Solution:** Version number on every aggregate. Database checks the version before updating.

```sql
-- The version column acts as an optimistic lock
UPDATE wallets
SET balance = 950.00, held_amount = 0.00, version = 3, updated_at = NOW()
WHERE wallet_id = 'WLT-ABC123'
  AND version = 2;   -- ← if version ≠ 2, UPDATE affects 0 rows → exception

-- If 0 rows updated: another thread modified the wallet — retry
```

```java
// Application layer handles optimistic lock conflicts
@Transactional
public void handle(DebitWalletCommand command) {
    int maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
            Wallet wallet = walletRepository.findById(command.walletId()).orElseThrow();
            wallet.debit(command.amount(), command.debitType(), command.reference(), command.description());
            walletRepository.save(wallet); // may throw OptimisticLockException
            return; // success
        } catch (OptimisticLockException e) {
            if (attempt == maxRetries - 1) throw e; // exhausted retries
            log.warn("Optimistic lock conflict on wallet {}. Retry {}/{}",
                command.walletId(), attempt + 1, maxRetries);
            // No sleep needed — just reload and retry immediately
        }
    }
}
```

**Why optimistic over pessimistic locking?**
Pessimistic locking (`SELECT FOR UPDATE`) holds a row lock for the entire duration of the operation. For UPI payments, that duration includes the NPCI round-trip (up to 30 seconds). A 30-second row lock on the wallet table would serialize all transactions for a user — catastrophic at scale. Optimistic locking only checks the version at commit time, which is milliseconds.

---

## 3. Outbox Pattern — Reliable Event Publishing

**Problem:** We save the payment in the DB, then publish to Kafka. If the process crashes between the DB commit and the Kafka publish, the event is lost. Other bounded contexts (Notification, Audit) never hear about the payment.

**Solution (Transactional Outbox):**
1. Write events to an outbox table **in the same transaction** as the aggregate save
2. A separate poller reads the outbox and publishes to Kafka
3. Mark as published after Kafka ACK

```
DB Transaction:
  INSERT INTO payments (...) VALUES (...);
  INSERT INTO payment_outbox (event_type, payload) VALUES ('payment.completed', '{...}');
  -- Both committed atomically, or both rolled back

Outbox Poller (separate thread/process):
  SELECT * FROM payment_outbox WHERE status = 'PENDING' FOR UPDATE SKIP LOCKED LIMIT 100;
  KafkaSend(event) → wait for ACK
  UPDATE payment_outbox SET status = 'SENT', sent_at = NOW() WHERE id = ?;
```

**`SKIP LOCKED`** is critical — allows multiple poller threads to pick non-overlapping batches without blocking each other.

### Debezium CDC Alternative (Lower Latency)

For sub-100ms event publishing, use **Debezium** (Change Data Capture):
- Reads PostgreSQL WAL (Write-Ahead Log) directly
- Every INSERT/UPDATE to outbox table streams to Kafka within milliseconds
- No polling overhead; no DB load from polling query
- Handles exactly-once semantics at the connector level

```
PostgreSQL WAL → Debezium Kafka Connector → Kafka topic (payment.events)
```

Trade-off: Debezium is operationally complex. Use polling for simplicity at early scale (<10k TPS), Debezium at higher scale.

---

## 4. Reconciliation — The Safety Net

**Problem:** Payment in `TIMEOUT` state. NPCI didn't send a callback. Did the payment actually succeed or fail at NPCI?

**Solution:** Scheduled reconciliation job queries NPCI/BBPS for the final status.

```java
@Component
public class PaymentReconciliationJob {

    @Scheduled(fixedDelay = 60_000) // every minute
    public void reconcileTimeoutPayments() {
        List<Payment> timeouts = paymentRepository.findTimeoutPayments();

        timeouts.forEach(payment -> {
            try {
                reconcile(payment);
            } catch (Exception e) {
                log.error("Reconciliation failed for payment {}", payment.getId(), e);
                metrics.counter("reconciliation.failures").increment();
            }
        });
    }

    @Transactional
    private void reconcile(Payment payment) {
        // Query NPCI for the final status of this payment
        PaymentStatusResult npciStatus = npciAdapter.queryPaymentStatus(payment.getId().getValue());

        if (npciStatus.isCompleted()) {
            payment.reconcileAsCompleted(npciStatus.npciTransactionId());
        } else if (npciStatus.isFailed()) {
            payment.fail(npciStatus.errorCode(), "Reconciliation: NPCI confirmed failure");
        } else if (npciStatus.isPending()) {
            // Still processing at NPCI — check again later
            // If still TIMEOUT after 24 hours, auto-fail and refund
            if (Duration.between(payment.getInitiatedAt(), Instant.now()).toHours() > 24) {
                payment.fail("RECONCILIATION_TIMEOUT", "No NPCI response after 24 hours");
            }
        }

        paymentRepository.save(payment);
        eventPublisher.publish(payment.pullDomainEvents());
    }
}
```

---

## 5. Rate Limiting — Protecting Against Abuse

**Problem:** A compromised account (or a bot) initiates 1,000 payment attempts per second. Without rate limiting, this saturates NPCI, triggers fraud alerts, and degrades service for legitimate users.

**Three-tier rate limiting:**

```java
@Component
public class PaymentRateLimiter {

    private final RedisRateLimitStore redis;

    /**
     * Tier 1: Per-user UPI payment rate limit
     * Rule: max 10 UPI initiations per minute per user
     * Source: NPCI UPI operational guidelines
     */
    public void checkUserUpiLimit(UserId userId) {
        String key = "rate:upi:" + userId.getValue() + ":" + currentMinuteBucket();
        long count = redis.incrementAndExpire(key, Duration.ofMinutes(2));
        if (count > 10)
            throw new RateLimitExceededException("Too many UPI payment attempts. Try after 1 minute.");
    }

    /**
     * Tier 2: Per-device rate limit
     * Rule: max 20 payment initiations per hour from same device fingerprint
     * Prevents: compromised device sending many payments
     */
    public void checkDeviceLimit(String deviceFingerprint) {
        String key = "rate:device:" + deviceFingerprint + ":" + currentHourBucket();
        long count = redis.incrementAndExpire(key, Duration.ofHours(2));
        if (count > 20)
            throw new RateLimitExceededException("Device rate limit exceeded.");
    }

    /**
     * Tier 3: Per-IP rate limit (at API Gateway level — not implemented here)
     * Rule: max 100 payment initiations per minute per IP
     * Implemented at nginx/API Gateway using Lua/WAF rules — not in application code
     */

    private String currentMinuteBucket() {
        return String.valueOf(Instant.now().getEpochSecond() / 60);
    }

    private String currentHourBucket() {
        return String.valueOf(Instant.now().getEpochSecond() / 3600);
    }
}
```

---

## 6. Observability — Metrics That Matter in Production

### Key Metrics by Bounded Context

```java
@Component
public class PaymentMetrics {

    private final MeterRegistry registry;

    // Payment funnel — track every state transition
    public void recordPaymentInitiated(String methodType) {
        registry.counter("payment.initiated", "method", methodType).increment();
    }

    public void recordPaymentCompleted(String methodType, Duration duration) {
        registry.timer("payment.completed.duration", "method", methodType)
            .record(duration);
        registry.counter("payment.completed", "method", methodType).increment();
    }

    public void recordPaymentFailed(String methodType, String failureCode) {
        registry.counter("payment.failed", "method", methodType, "code", failureCode).increment();
    }

    public void recordPaymentTimeout(String methodType) {
        registry.counter("payment.timeout", "method", methodType).increment();
    }

    // NPCI-specific
    public void recordNpciCallDuration(Duration duration, boolean success) {
        registry.timer("npci.call.duration", "result", success ? "success" : "failure")
            .record(duration);
    }

    // Wallet
    public void recordWalletInsufficientBalance() {
        registry.counter("wallet.insufficient_balance").increment();
    }
}
```

### Alerting Rules (Prometheus/CloudWatch)

```yaml
# Critical alerts — page oncall immediately
alerts:
  - name: HighPaymentFailureRate
    condition: rate(payment_failed_total[5m]) / rate(payment_initiated_total[5m]) > 0.05
    message: "Payment failure rate >5% — possible NPCI issue or fraud surge"
    severity: CRITICAL

  - name: UpiTimeoutSurge
    condition: rate(payment_timeout_total[5m]) > 10
    message: "UPI timeouts >10/min — possible NPCI network degradation"
    severity: HIGH

  - name: WalletOptimisticLockFailures
    condition: rate(wallet_optimistic_lock_failures_total[1m]) > 5
    message: "High wallet contention — investigate hot wallet accounts"
    severity: HIGH

  - name: OutboxLag
    condition: max(payment_outbox_pending_count) > 1000
    message: "Outbox events not being published — Kafka connectivity issue?"
    severity: CRITICAL

  - name: ReconciliationFailures
    condition: increase(reconciliation_failures_total[1h]) > 10
    message: "Reconciliation job failing — NPCI status API may be down"
    severity: HIGH

  - name: SagaStalled
    condition: count(saga_instances{state=~".*_PENDING", age_minutes>30}) > 0
    message: "Sagas stalled for >30 minutes — investigate"
    severity: HIGH
```

### Structured Logging for Payment Audit

```java
// Every payment state change logs in structured format
// Consumed by ELK/Datadog for regulatory audit trail

log.info("Payment state transition",
    StructuredArguments.keyValue("paymentId", payment.getId().getValue()),
    StructuredArguments.keyValue("referenceId", payment.getReferenceId().getValue()),
    StructuredArguments.keyValue("fromStatus", oldStatus.name()),
    StructuredArguments.keyValue("toStatus", payment.getStatus().name()),
    StructuredArguments.keyValue("userId", payment.getPayer().userId().getValue()),
    StructuredArguments.keyValue("amount", payment.getAmount().toString()),
    StructuredArguments.keyValue("method", payment.getPaymentMethod().getMethodType()),
    StructuredArguments.keyValue("timestamp", Instant.now())
);
```

---

## 7. Failure Mode Reference

| Failure | Detection | Mitigation | Recovery |
|---|---|---|---|
| NPCI unreachable | `NpciUnavailableException`, timeout | Save payment in PROCESSING; don't retry immediately | Reconciliation job polls NPCI status every 60s |
| NPCI timeout (payment may have succeeded) | HTTP 504 from NPCI | Save as TIMEOUT; never assume failed | Reconciliation confirms within 24h |
| DB connection pool exhausted | `CannotGetJdbcConnectionException` | Connection pool sizing (HikariCP max=20) | Circuit breaker on DB; HikariCP timeout |
| Kafka unavailable | Outbox poller fails | Outbox persists in DB; events survive restart | On Kafka recovery, poller resumes from last unprocessed entry |
| Duplicate payment | UniqueConstraintViolation | Idempotency key check + DB unique index | Return existing payment; log as retry |
| Wallet balance race condition | OptimisticLockException | Retry 3× with immediate retry | Log conflict; alert if >3 conflicts/min |
| BBPS timeout | HTTP 504 from BBPS | Save as TIMEOUT; reconcile | BBPS status API query by agentTransactionId |
| Saga stalled | Scheduled job finds old PENDING sagas | Automatic retry | Retry step; alert after 30 min |
| Fraud service down | HTTP 503 from Fraud AC | Use cached risk score or ALLOW with lower limit | Degrade: allow low-amount payments, block high-amount |

---

## 8. PCI-DSS Compliance Patterns

```java
/**
 * Card data never travels through our application servers in plaintext.
 * The mobile app uses a JavaScript tokenizer that calls the card vault directly.
 * Our servers receive only the token.
 *
 * Flow:
 * Mobile App → POST card data directly to Card Vault (PCI-compliant HSM)
 *           ← receives cardToken (encrypted reference)
 * Mobile App → POST payment with cardToken to our API (no card data ever here)
 * Our API    → sends cardToken to bank's payment gateway
 *
 * This reduces our PCI scope dramatically — we never see raw card data.
 */
public record CardPaymentMethod(
    EncryptedCardToken cardToken,     // vault-issued token, never raw PAN
    MaskedCardNumber maskedNumber,    // last 4 digits for display ONLY
    CardNetwork network,
    CardType cardType,
    String bankIssuerName
) implements PaymentMethod {}

// What we log (PCI-compliant):
// ✅ "Card payment initiated: VISA ending in 4242"
// ❌ "Card payment initiated: 4111111111114242" — NEVER

// What we store in DB:
// ✅ card_token (encrypted by card vault), masked_card_number (****4242)
// ❌ raw PAN, CVV, full expiry — NEVER stored, NEVER logged
```

---

## Summary: Production Patterns Checklist

| Pattern | Purpose | Implementation |
|---|---|---|
| **Idempotency keys** | Prevent duplicate payments | Header + Redis cache + DB unique index |
| **Optimistic locking** | Prevent concurrent balance corruption | `@Version` on JPA entity; retry on conflict |
| **Transactional outbox** | Never lose domain events | Outbox table in same DB; async poller |
| **Reconciliation job** | Resolve TIMEOUT payments | Scheduled job queries NPCI/BBPS status |
| **Rate limiting** | Prevent abuse | Redis counters per user/device |
| **Saga state persistence** | Survive crashes mid-flow | Saga state in DB; scheduled recovery |
| **Compensation transactions** | Undo failed saga steps | Explicit compensating actions per step |
| **ACL for every external system** | Protect domain from external API changes | Separate adapter per integration |
| **Circuit breaker** | Prevent cascade failure to NPCI | resilience4j CircuitBreaker on NPCI adapter |
| **Structured audit logging** | RBI compliance, forensics | JSON logs with all payment fields |
| **PCI-DSS tokenization** | Never handle raw card data | Card vault + tokens only |
